import Foundation
import Combine
import GameController

@MainActor
final class GameGuideViewModel: ObservableObject {
    nonisolated(unsafe) static var isGuideSidebarOpen: Bool = false

    @Published private(set) var navigationStack: [GuideNavigationLevel] = [.root]
    @Published private(set) var currentTopics: [GuideNode] = []
    @Published private(set) var currentQuestion: GuideQuestion? = nil
    @Published private(set) var currentWalkthroughText: String? = nil
    @Published private(set) var revealedHintCount: [Int: Int] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var hasGuideData: Bool = false
    @Published private(set) var guideSource: GuideSource? = nil
    @Published private(set) var uhsSlug: String? = nil
    @Published private(set) var gamefaqsFAQs: [GameFAQsFAQEntry] = []
    @Published private(set) var gamefaqsGameURL: String? = nil
    @Published var isSidebarVisible: Bool = false
    @Published private(set) var isPrefetching: Bool = false
    @Published private(set) var prefetchProgress: String? = nil
    @Published var controllerSelectedIndex: Int? = nil
    // Vertical scroll offset (in points) for scrollable text content such as
    // walkthroughs. Driven by the controller stick; the sidebar's scroll view
    // observes and applies it.
    @Published var guideScrollOffset: CGFloat = 0

    private let service = GameGuideService.shared
    private let mappingStore = AdventureGuideMappingStore.shared
    private var rom: ROM?
    private var topicCache: [Int: GuideTopic] = [:]
    private var questionCache: [Int: GuideQuestion] = [:]
    private var preloadedRootTopic: GuideTopic?
    private var controllerNavTimer: Timer?
    private var lastNavStickY: Float = 0
    private var navRepeatDelay: TimeInterval = 0.0
    private var lastAPressed = false
    private var lastBPressed = false
    private var lastR3Pressed = false

    var currentLevel: GuideNavigationLevel {
        navigationStack.last ?? .root
    }

    var canGoBack: Bool {
        navigationStack.count > 1
    }

    func loadForGame(_ rom: ROM) {
        self.rom = rom
        clearGuideMemory()

        let mapping: AdventureGuideMapping?
        if rom.systemID == "scummvm" {
            let gameID = extractScummVMGameID(from: rom.path.path)
            if let gameID {
                mapping = mappingStore.findMapping(scummvmID: gameID)
            } else {
                mapping = mappingStore.findMapping(title: rom.displayName)
            }
        } else {
            mapping = mappingStore.findMapping(title: rom.displayName)
        }

        if let mapping {
            uhsSlug = mapping.uhsSlug
            guideSource = .uhs
            hasGuideData = true
        } else if isAdventureGenre(rom) {
            guideSource = .gamefaqs
            hasGuideData = true
        } else {
            hasGuideData = false
        }
    }

    private func showRootTopics() {
        if let preloaded = preloadedRootTopic {
            saveViewState()
            currentTopics = preloaded.children
            navigationStack = [.root]
            currentQuestion = nil
            currentWalkthroughText = nil
            restoreViewState()
            return
        }
        fetchFullGuide()
    }

    private func fetchFullGuide() {
        guard let slug = uhsSlug else {
            tryGameFAQsFallback()
            return
        }
        isLoading = true
        errorMessage = nil
        prefetchProgress = LocalizationManager.shared.localized("guide.prefetching")
        isPrefetching = true
        Task {
            let rootTopic = await service.prefetchUHSTree(slug: slug)
            if let rootTopic {
                preloadedRootTopic = rootTopic
                buildCaches(from: rootTopic)
                currentTopics = rootTopic.children
                navigationStack = [.root]
                currentQuestion = nil
                currentWalkthroughText = nil
                restoreViewState()
            } else {
                tryGameFAQsFallback()
            }
            isPrefetching = false
            prefetchProgress = nil
            isLoading = false
        }
    }

    private func buildCaches(from topic: GuideTopic) {
        topicCache[topic.nodeID] = topic
        for child in topic.children {
            switch child {
            case .topic(let subTopic):
                buildCaches(from: subTopic)
            case .question(let question):
                questionCache[question.nodeID] = question
            }
        }
    }

    func navigateToNode(_ node: GuideNode) {
        switch node {
        case .topic(let topic):
            navigateToTopic(topic)
        case .question(let question):
            showQuestion(question)
        }
    }

    // Memory of sidebar position, per view. The key is the full path from
    // the root to the current view, so scroll and selection return when
    // you go back or reopen the sidebar. New views start at the top.
    private var savedScrollOffsets: [String: CGFloat] = [:]
    private var savedSelections: [String: Int] = [:]

    private func stateKey(for stack: [GuideNavigationLevel]) -> String {
        let path = stack.map { level -> String in
            switch level {
            case .root: return "root"
            case .topic(let nodeID): return "t\(nodeID)"
            case .question(let nodeID): return "q\(nodeID)"
            }
        }.joined(separator: "/")
        let source = guideSource == .gamefaqs ? "g" : "u"
        return source + "|" + path
    }

    private func saveViewState() {
        let key = stateKey(for: navigationStack)
        savedScrollOffsets[key] = max(0, guideScrollOffset)
        if let index = controllerSelectedIndex {
            savedSelections[key] = index
        } else {
            savedSelections.removeValue(forKey: key)
        }
    }

    private func restoreViewState() {
        let key = stateKey(for: navigationStack)
        guideScrollOffset = max(0, savedScrollOffsets[key] ?? 0)
        let count = navigationControllerItemCount
        if count > 0 {
            if let saved = savedSelections[key] {
                controllerSelectedIndex = max(0, min(count - 1, saved))
            } else {
                controllerSelectedIndex = 0
            }
        } else {
            controllerSelectedIndex = nil
        }
    }

    private func clearGuideMemory() {
        navigationStack = [.root]
        currentTopics = []
        currentQuestion = nil
        currentWalkthroughText = nil
        revealedHintCount = [:]
        topicCache = [:]
        questionCache = [:]
        preloadedRootTopic = nil
        gamefaqsFAQs = []
        gamefaqsGameURL = nil
        errorMessage = nil
        isLoading = false
        savedScrollOffsets = [:]
        savedSelections = [:]
        guideScrollOffset = 0
        controllerSelectedIndex = nil
    }

    func navigateToTopic(_ topic: GuideTopic) {
        guard let cachedTopic = topicCache[topic.nodeID] else {
            errorMessage = "Topic data not loaded"
            return
        }
        saveViewState()
        currentTopics = cachedTopic.children
        if case .topic(let lastID) = navigationStack.last, lastID == topic.nodeID {
            // already viewing this topic, don't re-push
        } else {
            navigationStack.append(.topic(nodeID: topic.nodeID))
        }
        currentQuestion = nil
        restoreViewState()
    }

    func showQuestion(_ question: GuideQuestion) {
        guard let cachedQuestion = questionCache[question.nodeID] else {
            saveViewState()
            currentQuestion = question
            navigationStack.append(.question(nodeID: question.nodeID))
            currentTopics = []
            if revealedHintCount[question.nodeID] == nil {
                revealedHintCount[question.nodeID] = 0
            }
            restoreViewState()
            return
        }
        saveViewState()
        currentQuestion = cachedQuestion
        navigationStack.append(.question(nodeID: question.nodeID))
        currentTopics = []
        if revealedHintCount[question.nodeID] == nil {
            revealedHintCount[question.nodeID] = 0
        }
        restoreViewState()
    }

    func revealNextHint() {
        guard let question = currentQuestion else { return }
        let current = revealedHintCount[question.nodeID] ?? 0
        if current < question.hints.count {
            revealedHintCount[question.nodeID] = current + 1
        }
    }

    func revealAllHints() {
        guard let question = currentQuestion else { return }
        revealedHintCount[question.nodeID] = question.hints.count
    }

    func revealedHints(for question: GuideQuestion) -> [Hint] {
        let count = revealedHintCount[question.nodeID] ?? 0
        return Array(question.hints.prefix(count))
    }

    func hasMoreHints(for question: GuideQuestion) -> Bool {
        let revealed = revealedHintCount[question.nodeID] ?? 0
        return revealed < question.hints.count
    }

    func goBack() {
        guard navigationStack.count > 1 else { return }
        saveViewState()
        navigationStack.removeLast()
        currentQuestion = nil
        currentWalkthroughText = nil
        restoreViewState()

        switch navigationStack.last {
        case .root:
            if let preloaded = preloadedRootTopic {
                currentTopics = preloaded.children
            }
        case .topic(let nodeID):
            if let cached = topicCache[nodeID] {
                currentTopics = cached.children
            }
        case .question:
            break
        case .none:
            break
        }
    }

    func loadGameFAQsFAQList() {
        guard gamefaqsGameURL != nil || uhsSlug == nil else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if gamefaqsGameURL == nil {
                    guard let rom else {
                        errorMessage = "No ROM loaded"
                        isLoading = false
                        return
                    }
                    let searchResult = try await service.searchGameFAQs(title: rom.displayName)
                    guard let result = searchResult else {
                        errorMessage = "No GameFAQs entry found"
                        isLoading = false
                        return
                    }
                    gamefaqsGameURL = result.gameURL
                }
                let faqs = try await service.fetchGameFAQsFAQList(gameURL: gamefaqsGameURL!)
                gamefaqsFAQs = faqs
                navigationStack = [.root]
                currentTopics = faqs.map { .topic(GuideTopic(title: $0.title, nodeID: $0.id)) }
                guideSource = .gamefaqs
                restoreViewState()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadGameFAQsFAQText(_ entry: GameFAQsFAQEntry) {
        isLoading = true
        errorMessage = nil
        saveViewState()
        Task {
            do {
                let text = try await service.fetchGameFAQsFAQText(faqPath: entry.path)
                currentWalkthroughText = text
                navigationStack.append(.topic(nodeID: entry.id))
                currentTopics = []
                currentQuestion = nil
                restoreViewState()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func activate() {
        isSidebarVisible = true
        Self.isGuideSidebarOpen = true
        restoreViewState()
        // Only load the root when no view is open. At hint or walkthrough
        // depth currentTopics is empty by design, so topics alone must not
        // trigger a reset to root.
        if navigationStack == [.root] && currentTopics.isEmpty && currentQuestion == nil && currentWalkthroughText == nil && !isLoading && errorMessage == nil {
            if guideSource == .uhs {
                showRootTopics()
            } else {
                loadGameFAQsFAQList()
            }
        }
        startControllerNavigation()
    }

    func deactivate() {
        saveViewState()
        isSidebarVisible = false
        Self.isGuideSidebarOpen = false
        stopControllerNavigation()
    }

    func tryGameFAQsFallback() {
        guideSource = .gamefaqs
        loadGameFAQsFAQList()
    }

    var isCapturedGameSystem: Bool {
        guard let rom else { return false }
        let systemID = rom.systemID?.lowercased() ?? ""
        return systemID == "dos" || systemID == "scummvm"
    }

    private func isAdventureGenre(_ rom: ROM) -> Bool {
        guard let genre = rom.metadata?.genre?.lowercased() else {
            return rom.systemID == "scummvm"
        }
        return genre.contains("adventure")
            || genre.contains("point & click")
            || genre.contains("point-and-click")
            || rom.systemID == "scummvm"
    }

    private func extractScummVMGameID(from path: String) -> String? {
        guard path.hasSuffix(".scummvm") else { return nil }
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !filename.isEmpty, filename != "unknown" else { return nil }
        return filename
    }

    // MARK: - Controller Navigation

    private var navigationControllerItemCount: Int {
        if currentWalkthroughText != nil { return 0 }
        if let question = currentQuestion {
            if hasMoreHints(for: question) { return 2 }
            return 0
        }
        if guideSource == .gamefaqs { return gamefaqsFAQs.count }
        return currentTopics.count
    }

    func startControllerNavigation() {
        restoreViewState()
        lastNavStickY = 0
        navRepeatDelay = 0.0
        lastAPressed = false
        lastBPressed = false
        lastR3Pressed = false

        controllerNavTimer?.invalidate()
        controllerNavTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { @MainActor [weak self] in
                self?.pollControllerNavigationStick()
            }
        }
        #if LOG_DEBUG
        LoggerService.debug(category: "GameGuide", "Controller navigation started")
        #endif
    }

    func stopControllerNavigation() {
        controllerNavTimer?.invalidate()
        controllerNavTimer = nil
        controllerSelectedIndex = nil
    }

    func controllerSelectItem() {
        guard let index = controllerSelectedIndex else { return }
        if let question = currentQuestion {
            if hasMoreHints(for: question) {
                if index == 0 { revealNextHint() }
                else if index == 1 { revealAllHints() }
            }
            return
        }
        if guideSource == .gamefaqs {
            guard index < gamefaqsFAQs.count else { return }
            loadGameFAQsFAQText(gamefaqsFAQs[index])
        } else {
            guard index < currentTopics.count else { return }
            navigateToNode(currentTopics[index])
        }
    }

    func controllerGoBack() {
        goBack()
    }

    func controllerRevealHint() {
        guard currentQuestion != nil else { return }
        if hasMoreHints(for: currentQuestion!) {
            revealNextHint()
        }
    }

    private func pollControllerNavigationStick() {
        guard isSidebarVisible else {
            stopControllerNavigation()
            return
        }

        // Gather navigation intent from every recognized gamepad. GCController
        // gamepads are read directly; SDL-only pads (never exposed as
        // GCController) are read via SDLInputManager's nav snapshot. This
        // mirrors GamepadNavigationManager so both controller types work.
        var up = false, down = false
        var aPressed = false, bPressed = false
        var sdlTogglePressed = false

        let controllers = ControllerService.shared.connectedControllers
        let gamepads = controllers.compactMap { $0.isKeyboard ? nil : $0.gcController?.extendedGamepad }
        for gamepad in gamepads {
            if gamepad.dpad.up.isPressed { up = true }
            if gamepad.dpad.down.isPressed { down = true }
            let ry = gamepad.rightThumbstick.yAxis.value
            if fabsf(ry) >= 0.5 {
                if ry > 0 { up = true } else { down = true }
            }
            if gamepad.buttonA.isPressed { aPressed = true }
            if gamepad.buttonB.isPressed { bPressed = true }
        }

        let sdl = SDLInputManager.shared.pollNavButtons()
        if sdl.contains(.dpadUp) || sdl.contains(.rightStickUp) { up = true }
        if sdl.contains(.dpadDown) || sdl.contains(.rightStickDown) { down = true }
        if sdl.contains(.buttonA) { aPressed = true }
        if sdl.contains(.buttonB) { bPressed = true }
        sdlTogglePressed = sdl.contains(.l3) || sdl.contains(.r3)

        let itemCount = navigationControllerItemCount
        if itemCount == 0 {
            controllerSelectedIndex = nil
        } else if let idx = controllerSelectedIndex, idx >= itemCount {
            controllerSelectedIndex = max(0, itemCount - 1)
        } else if controllerSelectedIndex == nil && itemCount > 0 {
            controllerSelectedIndex = 0
        }

        let now = CACurrentMediaTime()
        if up || down {
            if now >= navRepeatDelay {
                let direction = down ? 1 : -1
                if itemCount == 0 {
                    // Scrollable text content (walkthrough / hints).
                    guideScrollOffset += CGFloat(direction) * 36.0
                    if guideScrollOffset < 0 {
                        guideScrollOffset = 0
                    }
                } else if var idx = controllerSelectedIndex {
                    idx += direction
                    controllerSelectedIndex = max(0, min(itemCount - 1, idx))
                } else {
                    controllerSelectedIndex = 0
                }
                navRepeatDelay = now + 0.12
            }
        } else {
            navRepeatDelay = 0.0
        }

        if aPressed && !lastAPressed {
            controllerSelectItem()
        }
        lastAPressed = aPressed

        if bPressed && !lastBPressed {
            controllerGoBack()
        }
        lastBPressed = bPressed

        // Close the guide from an SDL-only pad. GC pads toggle via the runner's
        // handleGuideToggleButton so we only act on the SDL snapshot here.
        if sdlTogglePressed && !lastR3Pressed {
            NotificationCenter.default.post(name: .toggleGuideSidebar, object: nil)
        }
        lastR3Pressed = sdlTogglePressed
    }
}

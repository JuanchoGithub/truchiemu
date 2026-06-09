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
        errorMessage = nil

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
            currentTopics = preloaded.children
            navigationStack = [.root]
            currentQuestion = nil
            currentWalkthroughText = nil
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
        resetControllerSelection()
    }

    func navigateToTopic(_ topic: GuideTopic) {
        guard let cachedTopic = topicCache[topic.nodeID] else {
            errorMessage = "Topic data not loaded"
            return
        }
        currentTopics = cachedTopic.children
        if case .topic(let lastID) = navigationStack.last, lastID == topic.nodeID {
            // already viewing this topic, don't re-push
        } else {
            navigationStack.append(.topic(nodeID: topic.nodeID))
        }
        currentQuestion = nil
        resetControllerSelection()
    }

    func showQuestion(_ question: GuideQuestion) {
        guard let cachedQuestion = questionCache[question.nodeID] else {
            currentQuestion = question
            navigationStack.append(.question(nodeID: question.nodeID))
            currentTopics = []
            if revealedHintCount[question.nodeID] == nil {
                revealedHintCount[question.nodeID] = 0
            }
            resetControllerSelection()
            return
        }
        currentQuestion = cachedQuestion
        navigationStack.append(.question(nodeID: question.nodeID))
        currentTopics = []
        if revealedHintCount[question.nodeID] == nil {
            revealedHintCount[question.nodeID] = 0
        }
        resetControllerSelection()
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
        navigationStack.removeLast()
        currentQuestion = nil
        currentWalkthroughText = nil
        resetControllerSelection()

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
        resetControllerSelection()
        Task {
            do {
                let text = try await service.fetchGameFAQsFAQText(faqPath: entry.path)
                currentWalkthroughText = text
                navigationStack.append(.topic(nodeID: entry.id))
                currentTopics = []
                currentQuestion = nil
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
        if currentTopics.isEmpty && !isLoading && errorMessage == nil {
            if guideSource == .uhs {
                showRootTopics()
            } else {
                loadGameFAQsFAQList()
            }
        }
        startControllerNavigation()
    }

    func deactivate() {
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

    private func resetControllerSelection() {
        controllerSelectedIndex = navigationControllerItemCount > 0 ? 0 : nil
    }

    func startControllerNavigation() {
        controllerSelectedIndex = 0
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
        LoggerService.debug(category: "GameGuide", "Controller navigation started")
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
        controllerSelectedIndex = navigationControllerItemCount > 0 ? 0 : nil
    }

    func controllerGoBack() {
        goBack()
        controllerSelectedIndex = navigationControllerItemCount > 0 ? 0 : nil
    }

    func controllerRevealHint() {
        guard currentQuestion != nil else { return }
        if hasMoreHints(for: currentQuestion!) {
            revealNextHint()
        }
    }

    private var controllerNavPollCount: Int = 0

    private func pollControllerNavigationStick() {
        guard isSidebarVisible else {
            stopControllerNavigation()
            return
        }

        controllerNavPollCount += 1
        let controllers = ControllerService.shared.connectedControllers
        if controllerNavPollCount <= 5 {
            LoggerService.debug(category: "GameGuide", "Poll #\(controllerNavPollCount): controllers=\(controllers.count), first=\(controllers.first?.gcController != nil ? "hasGC" : "nilGC")")
        }

        guard let gc = controllers.first?.gcController,
              let gamepad = gc.extendedGamepad else {
            if controllerNavPollCount <= 5 {
                LoggerService.debug(category: "GameGuide", "Poll #\(controllerNavPollCount): no gamepad found")
            }
            return
        }

        let itemCount = navigationControllerItemCount
        if itemCount == 0 {
            controllerSelectedIndex = nil
        } else if let idx = controllerSelectedIndex, idx >= itemCount {
            controllerSelectedIndex = max(0, itemCount - 1)
        } else if controllerSelectedIndex == nil && itemCount > 0 {
            controllerSelectedIndex = 0
        }

        let sysID = rom?.systemID?.lowercased() ?? ""
        let stickString = AppSettings.getString("analogMouse_stick_\(sysID)", defaultValue: "left") ?? "left"
        let navStick = stickString == "right" ? gamepad.leftThumbstick : gamepad.rightThumbstick

        let yVal = navStick.yAxis.value
        let xVal = navStick.xAxis.value
        let deadZone: Float = 0.5

        if fabsf(yVal) >= deadZone || fabsf(xVal) >= deadZone {
            let now = CACurrentMediaTime()
            if now >= navRepeatDelay {
                if itemCount > 0 {
                    var direction: Int = 0
                    if fabsf(yVal) >= fabsf(xVal) {
                        direction = yVal > 0 ? -1 : 1
                    } else {
                        direction = xVal > 0 ? 1 : -1
                    }
                    if var idx = controllerSelectedIndex {
                        idx += direction
                        controllerSelectedIndex = max(0, min(itemCount - 1, idx))
                    } else {
                        controllerSelectedIndex = 0
                    }
                    LoggerService.debug(category: "GameGuide", "Nav stick moved: y=\(yVal) x=\(xVal) idx=\(String(describing: controllerSelectedIndex)) items=\(itemCount)")
                }
                navRepeatDelay = now + 0.12
            }
        } else {
            navRepeatDelay = 0.0
        }

        let aPressed = gamepad.buttonA.isPressed
        if aPressed && !lastAPressed {
            // A button handled via postMacMouseClick in runner
        }
        lastAPressed = aPressed

        let bPressed = gamepad.buttonB.isPressed
        if bPressed && !lastBPressed {
            // B button handled via postMacMouseClick in runner
        }
        lastBPressed = bPressed

        let sysIDStr = rom?.systemID?.lowercased() ?? ""
        let stickStr = AppSettings.getString("analogMouse_stick_\(sysIDStr)", defaultValue: "left") ?? "left"
        let toggleButton = stickStr == "right" ? gamepad.leftThumbstickButton : gamepad.rightThumbstickButton
        let togglePressed = toggleButton?.isPressed ?? false
        if togglePressed && !lastR3Pressed {
            // R3/L3 toggle handled via handleGuideToggleButton in runner
        }
        lastR3Pressed = togglePressed
    }
}

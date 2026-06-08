import Foundation
import Combine

@MainActor
final class GameGuideViewModel: ObservableObject {
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

    private let service = GameGuideService.shared
    private let mappingStore = AdventureGuideMappingStore.shared
    private var rom: ROM?
    private var topicCache: [Int: GuideTopic] = [:]
    private var questionCache: [Int: GuideQuestion] = [:]
    private var preloadedRootTopic: GuideTopic?

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

    func loadRootTopics() {
        guard let slug = uhsSlug else {
            tryGameFAQsFallback()
            return
        }

        if let preloaded = preloadedRootTopic {
            currentTopics = preloaded.children
            navigationStack = [.root]
            currentQuestion = nil
            currentWalkthroughText = nil
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let topics = try await service.fetchUHSTopics(slug: slug)
                currentTopics = topics
                navigationStack = [.root]
                currentQuestion = nil
                currentWalkthroughText = nil
                isLoading = false
            } catch {
                isLoading = false
                tryGameFAQsFallback()
            }
        }

        prefetchFullTree()
    }

    private func prefetchFullTree() {
        guard let slug = uhsSlug, !isPrefetching else { return }
        isPrefetching = true
        prefetchProgress = LocalizationManager.shared.localized("guide.prefetching")
        Task {
            let rootTopic = await service.prefetchUHSTree(slug: slug)
            if let rootTopic {
                preloadedRootTopic = rootTopic
                buildCaches(from: rootTopic)
                if currentTopics.isEmpty || currentTopics.allSatisfy({ node in
                    if case .topic(let t) = node { return t.children.isEmpty }
                    if case .question(let q) = node { return q.hints.isEmpty }
                    return true
                }) {
                    currentTopics = rootTopic.children
                }
            }
            isPrefetching = false
            prefetchProgress = nil
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

    func navigateToTopic(_ topic: GuideTopic) {
        let cachedTopic = topicCache[topic.nodeID] ?? topic
        if cachedTopic.children.isEmpty {
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    let result = try await service.fetchUHSNodePage(slug: uhsSlug!, nodeID: topic.nodeID)
                    switch result {
                    case .topic(let fetchedTopic):
                        topicCache[topic.nodeID] = fetchedTopic
                        currentTopics = fetchedTopic.children
                        navigationStack.append(.topic(nodeID: topic.nodeID))
                        currentQuestion = nil
                    case .question(let question):
                        showQuestion(question)
                    }
                    isLoading = false
                } catch {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        } else {
            currentTopics = cachedTopic.children
            navigationStack.append(.topic(nodeID: topic.nodeID))
            currentQuestion = nil
        }
    }

    func showQuestion(_ question: GuideQuestion) {
        let cachedQuestion = questionCache[question.nodeID] ?? question
        if cachedQuestion.hints.isEmpty && question.hints.isEmpty {
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    let result = try await service.fetchUHSNodePage(slug: uhsSlug!, nodeID: question.nodeID)
                    switch result {
                    case .question(let fetchedQuestion):
                        questionCache[fetchedQuestion.nodeID] = fetchedQuestion
                        currentQuestion = fetchedQuestion
                        navigationStack.append(.question(nodeID: question.nodeID))
                        currentTopics = []
                        revealedHintCount[question.nodeID] = 0
                    case .topic:
                        break
                    }
                    isLoading = false
                } catch {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        } else {
            let displayQuestion = cachedQuestion.hints.isEmpty ? question : cachedQuestion
            currentQuestion = displayQuestion
            navigationStack.append(.question(nodeID: question.nodeID))
            currentTopics = []
            if revealedHintCount[question.nodeID] == nil {
                revealedHintCount[question.nodeID] = 0
            }
        }
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

        switch navigationStack.last {
        case .root:
            if let preloaded = preloadedRootTopic {
                currentTopics = preloaded.children
            } else {
                loadRootTopics()
            }
        case .topic(let nodeID):
            if let cached = topicCache[nodeID] {
                currentTopics = cached.children
            } else {
                loadRootTopics()
            }
        case .question:
            break
        case .none:
            loadRootTopics()
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
        if currentTopics.isEmpty && !isLoading && errorMessage == nil {
            if guideSource == .uhs {
                loadRootTopics()
            } else {
                loadGameFAQsFAQList()
            }
        }
    }

    func deactivate() {
        isSidebarVisible = false
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
}

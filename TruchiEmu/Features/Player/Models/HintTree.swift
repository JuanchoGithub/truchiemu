import Foundation

enum GuideSource {
    case uhs
    case gamefaqs
}

struct GuideTopic: Identifiable, Sendable {
    let id: Int
    let title: String
    let nodeID: Int
    var children: [GuideNode]

    init(id: Int = UUID().hashValue, title: String, nodeID: Int, children: [GuideNode] = []) {
        self.id = nodeID
        self.title = title
        self.nodeID = nodeID
        self.children = children
    }
}

indirect enum GuideNode: Identifiable, Sendable {
    case topic(GuideTopic)
    case question(GuideQuestion)

    var id: Int {
        switch self {
        case .topic(let t): return t.id
        case .question(let q): return q.id
        }
    }

    var title: String {
        switch self {
        case .topic(let t): return t.title
        case .question(let q): return q.title
        }
    }
}

struct GuideQuestion: Identifiable, Sendable {
    let id: Int
    let title: String
    let nodeID: Int
    let hints: [Hint]

    init(id: Int = UUID().hashValue, title: String, nodeID: Int, hints: [Hint] = []) {
        self.id = nodeID
        self.title = title
        self.nodeID = nodeID
        self.hints = hints
    }
}

struct Hint: Identifiable, Sendable {
    let id: Int
    let index: Int
    let numberText: String
    let text: String
}

struct WalkthroughFAQ: Identifiable, Sendable {
    let id: Int
    let title: String
    let author: String
    let text: String
}

enum GuideNavigationLevel: Equatable {
    case root
    case topic(nodeID: Int)
    case question(nodeID: Int)
}

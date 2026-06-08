import SwiftUI

struct HelpShortcut: Identifiable {
    let id = UUID()
    let key: String
    let modifiers: [String]
    let descriptionKey: String
}

struct HelpFAQItem: Identifiable {
    let id = UUID()
    let questionKey: String
    let answerKey: String
}

enum HelpContent {
    static let docsBaseURL = "https://juanchogithub.github.io/truchiemu"

    static func docURL(_ path: String) -> URL {
        if path.isEmpty {
            return URL(string: docsBaseURL)!
        }
        return URL(string: "\(docsBaseURL)/\(path).html")!
    }

    static var keyboardShortcuts: [HelpShortcut] {
        [
            HelpShortcut(key: ",", modifiers: ["⌘"], descriptionKey: "help.shortcut.openSettings"),
            HelpShortcut(key: "O", modifiers: ["⇧", "⌘"], descriptionKey: "help.shortcut.addROMFolder"),
            HelpShortcut(key: "R", modifiers: ["⇧", "⌘"], descriptionKey: "help.shortcut.rescanLibrary"),
            HelpShortcut(key: "1", modifiers: ["⌘"], descriptionKey: "help.shortcut.gridView"),
            HelpShortcut(key: "2", modifiers: ["⌘"], descriptionKey: "help.shortcut.listView"),
            HelpShortcut(key: "B", modifiers: ["⌘"], descriptionKey: "help.shortcut.toggleBoxArt"),
            HelpShortcut(key: "P", modifiers: ["⇧", "⌘"], descriptionKey: "help.shortcut.sortLastPlayed"),
            HelpShortcut(key: "A", modifiers: ["⇧", "⌘"], descriptionKey: "help.shortcut.sortLastAdded"),
            HelpShortcut(key: "H", modifiers: ["⇧", "⌘"], descriptionKey: "help.shortcut.playHistory"),
            HelpShortcut(key: "S", modifiers: ["⌘"], descriptionKey: "help.shortcut.saveState"),
            HelpShortcut(key: "L", modifiers: ["⌘"], descriptionKey: "help.shortcut.loadState"),
            HelpShortcut(key: "Z", modifiers: ["⌘"], descriptionKey: "help.shortcut.undoLoadState"),
            HelpShortcut(key: "0-9", modifiers: ["⌘"], descriptionKey: "help.shortcut.selectSlot"),
            HelpShortcut(key: "F6", modifiers: [], descriptionKey: "help.shortcut.slotPlus"),
            HelpShortcut(key: "F4", modifiers: [], descriptionKey: "help.shortcut.slotMinus"),
            HelpShortcut(key: "M", modifiers: ["⌘"], descriptionKey: "help.shortcut.toggleInputCapture"),
            HelpShortcut(key: "T", modifiers: ["⇧", "⌘"], descriptionKey: "help.shortcut.toggleTrainingMode"),
            HelpShortcut(key: "T", modifiers: ["⌘"], descriptionKey: "help.shortcut.trainingReset"),
            HelpShortcut(key: "Esc", modifiers: [], descriptionKey: "help.shortcut.releaseInput"),
        ]
    }

    static var faqItems: [HelpFAQItem] {
        [
            HelpFAQItem(questionKey: "help.faq.addROMs.q", answerKey: "help.faq.addROMs.a"),
            HelpFAQItem(questionKey: "help.faq.cores.q", answerKey: "help.faq.cores.a"),
            HelpFAQItem(questionKey: "help.faq.controllers.q", answerKey: "help.faq.controllers.a"),
            HelpFAQItem(questionKey: "help.faq.saveStates.q", answerKey: "help.faq.saveStates.a"),
            HelpFAQItem(questionKey: "help.faq.shaders.q", answerKey: "help.faq.shaders.a"),
            HelpFAQItem(questionKey: "help.faq.cheats.q", answerKey: "help.faq.cheats.a"),
            HelpFAQItem(questionKey: "help.faq.bezels.q", answerKey: "help.faq.bezels.a"),
            HelpFAQItem(questionKey: "help.faq.achievements.q", answerKey: "help.faq.achievements.a"),
        ]
    }
}

import Foundation
import SwiftData

@Model
final class RAGameCacheEntry {
    @Attribute(.unique) var id: Int // The RetroAchievements Game ID
    var title: String
    var consoleID: Int
    var consoleName: String

    init(id: Int, title: String, consoleID: Int, consoleName: String) {
        self.id = id
        self.title = title
        self.consoleID = consoleID
        self.consoleName = consoleName
    }
}
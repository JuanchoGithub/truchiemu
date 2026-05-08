import Foundation
import SwiftData

@Model
final class RAConsole {
    @Attribute(.unique) var id: Int
    var name: String
    var iconURL: String?
    var isActive: Bool
    var isGameSystem: Bool
    var cachedAt: Date

    init(id: Int, name: String, iconURL: String? = nil, isActive: Bool = true, isGameSystem: Bool = true, cachedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.isActive = isActive
        self.isGameSystem = isGameSystem
        self.cachedAt = cachedAt
    }
}

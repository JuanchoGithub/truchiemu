import Foundation
import GameController

struct PlayerController: Identifiable {
    var id: Int { playerIndex }
    var playerIndex: Int
    var gcController: GCController?
    var mapping: ControllerGamepadMapping
    var sortOrder: Int

    var name: String { gcController?.vendorName ?? "Player \(playerIndex)" }
    var isConnected: Bool { gcController != nil }

    init(playerIndex: Int, gcController: GCController?, mapping: ControllerGamepadMapping, sortOrder: Int = 0) {
        self.playerIndex = playerIndex
        self.gcController = gcController
        self.mapping = mapping
        self.sortOrder = sortOrder
    }
}

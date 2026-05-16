import Foundation
import GameController

struct PlayerController: Identifiable {
    var id: Int { playerIndex }
    var playerIndex: Int
    var gcController: GCController?
    var mapping: ControllerGamepadMapping

    var name: String { gcController?.vendorName ?? "Player \(playerIndex)" }
    var isConnected: Bool { gcController != nil }
}

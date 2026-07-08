import Foundation

enum InputSystem: String, Codable, Hashable {
    case apple
    case sdl
    case keyboard
}

struct ControllerIdentityKey: Codable, Hashable {
    let inputSystem: InputSystem
    let productKey: String
    let vendorName: String?

    init(inputSystem: InputSystem, productKey: String, vendorName: String? = nil) {
        self.inputSystem = inputSystem
        self.productKey = productKey
        self.vendorName = vendorName
    }

    var compositeKey: String {
        let systemTag = inputSystem.rawValue
        let vendor = vendorName ?? ""
        return "\(systemTag)|\(productKey)|\(vendor)"
    }
}

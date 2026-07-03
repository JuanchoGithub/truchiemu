import Foundation
import Combine
import GameController
import AppKit

@MainActor
final class ControllerHotkeyCaptureCoordinator: ObservableObject {
    static let shared = ControllerHotkeyCaptureCoordinator()

    enum State: Equatable {
        case idle
        case listening(source: ControllerHotkeySource, displayName: String)
        case captured(ControllerHotkeyBinding)
    }

    @Published private(set) var state: State = .idle

    private let threshold: Float = 0.5
    private var capturedHandler: ((ControllerHotkeyBinding) -> Void)?

    private init() {}

    func startListening(source: ControllerHotkeySource,
                        currentLabel: String,
                        onCapture: @escaping (ControllerHotkeyBinding) -> Void) {
        if RunningGamesTracker.shared.isGameRunning {
            LoggerService.warning(category: "HotkeyCapture", "Cannot capture during gameplay; close the game window first")
            state = .listening(source: source, displayName: loc("hotkeys.unavailableDuringPlay"))
            capturedHandler = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if case .listening = self?.state { self?.state = .idle }
            }
            return
        }

        capturedHandler = onCapture
        state = .listening(source: source, displayName: loc("hotkeys.pressButton"))

        switch source {
        case .gameController:
            beginGCCapture()
        case .sdl:
            beginSDLCapture()
        }
    }

    func cancel() {
        clearGCCaptureHandler()
        SDLInputManager.shared.stopCapture()
        capturedHandler = nil
        if case .listening = state { state = .idle }
    }

    private func beginGCCapture() {
        clearGCCaptureHandler()
        let controllers = GCController.controllers()
        guard let first = controllers.first,
              let gamepad = first.extendedGamepad else {
            state = .idle
            return
        }
        let id = ObjectIdentifier(first)
        let handler: (GCControllerElement) -> Void = { [weak self] element in
            self?.handle(element: element)
        }
        Self.gcHandlers[id] = handler
        gamepad.valueChangedHandler = { _, element in
            Self.gcHandlers[id]?(element)
        }
    }

    private func clearGCCaptureHandler() {
        let controllers = GCController.controllers()
        let leftover = Self.gcHandlers.keys
        for id in leftover {
            if let gc = controllers.first(where: { ObjectIdentifier($0) == id }) {
                gc.extendedGamepad?.valueChangedHandler = nil
            }
        }
        Self.gcHandlers.removeAll()
    }

    private func handle(element: GCControllerElement) {
        let name = element.localizedName ?? ""
        guard !name.isEmpty else { return }
        if let dpad = element as? GCControllerDirectionPad {
            let dir = identifyDPad(dpad)
            if let identifier = dir {
                finishGC(name: identifier, label: dirDisplayName(identifier))
            }
            return
        }
        if let button = element as? GCControllerButtonInput {
            if button.value > threshold {
                finishGC(name: name, label: name)
            }
        }
    }

    private func identifyDPad(_ dpad: GCControllerDirectionPad) -> String? {
        let x = dpad.xAxis.value
        let y = dpad.yAxis.value
        if abs(x) < 0.5 && abs(y) < 0.5 { return nil }
        if abs(x) > abs(y) {
            return x > 0 ? "D-pad (Right)" : "D-pad (Left)"
        } else {
            return y > 0 ? "D-pad (Down)" : "D-pad (Up)"
        }
    }

    private func dirDisplayName(_ identifier: String) -> String {
        switch identifier {
        case "D-pad (Up)":    return "↑"
        case "D-pad (Down)":  return "↓"
        case "D-pad (Left)":  return "←"
        case "D-pad (Right)": return "→"
        default: return identifier
        }
    }

    private func finishGC(name: String, label: String) {
        let binding = ControllerHotkeyBinding.gc(name, label: label)
        clearGCCaptureHandler()
        state = .captured(binding)
        capturedHandler?(binding)
        capturedHandler = nil
    }

    private func beginSDLCapture() {
        guard let instanceID = pickFirstSDLInstance() else {
            state = .idle
            return
        }
        SDLInputManager.shared.startCapture(instanceID: instanceID) { [weak self] index, alias in
            guard let self else { return }
            let binding = ControllerHotkeyBinding.sdl(index, label: alias)
            self.state = .captured(binding)
            self.capturedHandler?(binding)
            self.capturedHandler = nil
        }
    }

    private func pickFirstSDLInstance() -> Int32? {
        let ids = SDLInputManager.shared.connectedSDLInstanceIDs()
        return ids.first
    }

    private func loc(_ key: String) -> String {
        LocalizationManager.shared.localized(key)
    }

    private static var gcHandlers: [ObjectIdentifier: (GCControllerElement) -> Void] = [:]
}

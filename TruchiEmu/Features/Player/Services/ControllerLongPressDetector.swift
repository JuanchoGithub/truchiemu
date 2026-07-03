import Foundation

@MainActor
final class ControllerLongPressDetector: ObservableObject {
    static let shared = ControllerLongPressDetector()

    private enum PressState {
        case idle
        case pressing(CFTimeInterval)
        case longPressFired
    }

    private var state: PressState = .idle
    private var longPressWorkItem: DispatchWorkItem?
    private var currentElementName: String?
    private var currentButtonIndex: Int?

    var onSinglePress: (() -> Void)?
    var onLongPress: (() -> Void)?

    private let longPressThreshold: CFTimeInterval = 1.2

    func handlePressDown(elementName: String) {
        LoggerService.info(category: "LongPress", "handlePressDown: \(elementName)")
        currentElementName = elementName
        let now = CACurrentMediaTime()
        state = .pressing(now)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            LoggerService.info(category: "LongPress", "Timer fired for: \(self.currentElementName ?? "nil")")
            if case .pressing = self.state {
                self.state = .longPressFired
                self.onLongPress?()
            }
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: workItem)
    }

    func handlePressUp(elementName: String) {
        guard elementName == currentElementName else {
            LoggerService.info(category: "LongPress", "handlePressUp ignored: \(elementName) != \(currentElementName ?? "nil")")
            return
        }
        currentElementName = nil
        longPressWorkItem?.cancel()
        longPressWorkItem = nil

        switch state {
        case .pressing:
            state = .idle
            onSinglePress?()
        case .longPressFired:
            state = .idle
        case .idle:
            break
        }
    }

    func handleSDLPressDown(buttonIndex: Int) {
        currentButtonIndex = buttonIndex
        let now = CACurrentMediaTime()
        state = .pressing(now)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if case .pressing = self.state {
                self.state = .longPressFired
                self.onLongPress?()
            }
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: workItem)
    }

    func handleSDLPressUp(buttonIndex: Int) {
        guard buttonIndex == currentButtonIndex else { return }
        currentButtonIndex = nil
        longPressWorkItem?.cancel()
        longPressWorkItem = nil

        switch state {
        case .pressing:
            state = .idle
            onSinglePress?()
        case .longPressFired:
            state = .idle
        case .idle:
            break
        }
    }

    func reset() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        state = .idle
        currentElementName = nil
        currentButtonIndex = nil
    }
}

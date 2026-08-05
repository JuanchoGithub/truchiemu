import SwiftUI
import AppKit
import GameController

struct ControllerHotkeyCaptureButton: NSViewRepresentable {
    var binding: ControllerHotkeyBinding
    var isListening: Bool
    var availableSources: [ControllerHotkeySource]
    var onBindingCaptured: (ControllerHotkeyBinding) -> Void
    var onListenStateChanged: (Bool) -> Void
    var onClearRequested: () -> Void
    var onSourceChanged: (ControllerHotkeySource) -> Void

    func makeNSView(context: Context) -> NSView {
        let wrapper = ControllerHotkeyCaptureContainer()
        wrapper.button.bezelStyle = .rounded
        wrapper.button.target = context.coordinator
        wrapper.button.action = #selector(Coordinator.clicked)
        wrapper.clearButton.bezelStyle = .rounded
        wrapper.clearButton.target = context.coordinator
        wrapper.clearButton.action = #selector(Coordinator.clearClicked)
        wrapper.clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        wrapper.clearButton.imagePosition = .imageOnly
        wrapper.popUp.target = context.coordinator
        wrapper.popUp.action = #selector(Coordinator.popUpChanged)
        return wrapper
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let wrapper = nsView as? ControllerHotkeyCaptureContainer else { return }
        context.coordinator.parent = self

        wrapper.button.title = isListening
            ? LocalizationManager.shared.localized("hotkeys.pressButton")
            : (binding.isUnset
                ? LocalizationManager.shared.localized("hotkeys.notSet")
                : binding.displayLabel)
        wrapper.clearButton.isHidden = binding.isUnset || isListening

        // Sync source picker
        if availableSources.isEmpty {
            wrapper.popUp.isHidden = true
        } else {
            // Only populate once or when sources change
            if wrapper.popUp.numberOfItems != availableSources.count {
                wrapper.popUp.removeAllItems()
                for src in availableSources {
                    wrapper.popUp.addItem(withTitle: sourceLabel(src))
                    wrapper.popUp.lastItem?.representedObject = src.rawValue
                }
            } else {
                for (idx, src) in availableSources.enumerated() where idx < wrapper.popUp.numberOfItems {
                    wrapper.popUp.item(at: idx)?.title = sourceLabel(src)
                    wrapper.popUp.item(at: idx)?.representedObject = src.rawValue
                }
            }
            let active = activeSource()
            for i in 0..<wrapper.popUp.numberOfItems {
                if (wrapper.popUp.item(at: i)?.representedObject as? String) == active.rawValue {
                    wrapper.popUp.selectItem(at: i)
                    break
                }
            }
        }
    }

    private func activeSource() -> ControllerHotkeySource {
        if availableSources.isEmpty { return binding.source }
        if availableSources.contains(binding.source) { return binding.source }
        return availableSources.first!
    }

    fileprivate func sourceLabel(_ src: ControllerHotkeySource) -> String {
        switch src {
        case .gameController: return LocalizationManager.shared.localized("hotkeys.sourceAppleControllerShort")
        case .sdl: return LocalizationManager.shared.localized("hotkeys.sourceSDLShort")
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: ControllerHotkeyCaptureButton
        init(parent: ControllerHotkeyCaptureButton) { self.parent = parent }

        @objc func clicked() {
            parent.onListenStateChanged(true)
        }

        @objc func clearClicked() {
            parent.onClearRequested()
        }

        @objc func popUpChanged(_ sender: NSPopUpButton) {
            guard let raw = sender.selectedItem?.representedObject as? String,
                  let src = ControllerHotkeySource(rawValue: raw) else { return }
            parent.onSourceChanged(src)
        }
    }
}

private final class ControllerHotkeyCaptureContainer: NSView {
    let button = NSButton()
    let clearButton = NSButton()
    let popUp = NSPopUpButton(frame: .zero)
    private let outerStack: NSStackView
    private let innerStack: NSStackView

    private static let buttonMinWidth: CGFloat = 110
    private static let clearButtonWidth: CGFloat = 22
    private static let popUpWidth: CGFloat = 96

    override init(frame frameRect: NSRect) {
        outerStack = NSStackView()
        innerStack = NSStackView()
        super.init(frame: frameRect)
        outerStack.orientation = .horizontal
        outerStack.spacing = 6
        outerStack.alignment = .centerY
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        innerStack.orientation = .horizontal
        innerStack.spacing = 2
        innerStack.detachesHiddenViews = false
        innerStack.addView(button, in: .leading)
        innerStack.addView(clearButton, in: .leading)
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        outerStack.addView(innerStack, in: .leading)
        outerStack.addView(popUp, in: .leading)

        addSubview(outerStack)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.buttonMinWidth).isActive = true
        clearButton.widthAnchor.constraint(equalToConstant: Self.clearButtonWidth).isActive = true
        popUp.widthAnchor.constraint(equalToConstant: Self.popUpWidth).isActive = true

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

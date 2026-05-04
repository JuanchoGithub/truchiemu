import SwiftUI
import Cocoa

// MARK: - MouseDownButton (NSButton that fires action on mouseDown)
class MouseDownButton: NSButton {
    override func mouseDown(with event: NSEvent) {
        // Fire action immediately on mouse down
        if let target = self.target, let action = self.action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

// MARK: - MouseDownButtonAction (SwiftUI wrapper for mouse-down button)
struct MouseDownButtonAction<Label: View>: NSViewRepresentable {
    let action: () -> Void
    let label: () -> Label
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        
        // Create the clickable button area
        let button = MouseDownButton()
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // Create hosting view for SwiftUI label
        let hostingView = NSHostingView(rootView: label())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(button)
        container.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update the hosting view content if needed
        if let hostingView = nsView.subviews.first(where: { $0 is NSHostingView<Label> }) as? NSHostingView<Label> {
            hostingView.rootView = label()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
        }
        @objc func performAction() {
            action()
        }
    }
}

// MARK: - MouseDownButtonActionStyled (with pressed state tracking)
struct MouseDownButtonActionStyled<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    @State private var isPressed = false
    
    var body: some View {
        MouseDownButtonAction(action: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        }) {
            label()
                .opacity(isPressed ? 0.7 : 1.0)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPressed ? Color.white.opacity(0.25) : Color.white.opacity(0.15))
                )
                .contentShape(Rectangle())
        }
        .frame(minWidth: 50)
    }
}

// MARK: - Custom Button Style for Toolbar Buttons
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Toolbar Button Component
struct ToolbarButton: View {
    let icon: String
    let label: String
    var danger: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(danger ? .red.opacity(0.9) : .white.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(danger ? Color.red.opacity(0.15) : Color.white.opacity(0.1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle())
        .buttonStyle(.plain)
    }
}

// MARK: - Pause/Resume Button
struct PauseResumeButton: View {
    @ObservedObject var runner: EmulatorRunner
    
    var body: some View {
        Button(action: {
            runner.togglePause()
        }) {
            VStack(spacing: 4) {
                Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(runner.isPaused ? "Resume" : "Pause")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(minWidth: 50)
        }
        .buttonStyle(ToolbarButtonStyle())
        .foregroundColor(runner.isPaused ? .green : .white)
    }
}

// MARK: - Fullscreen Toggle Button
struct FullscreenButton: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    
    var body: some View {
        Button(action: {
            windowController.toggleFullscreen()
        }) {
            VStack(spacing: 4) {
                Image(systemName: windowController.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                Text(windowController.isFullscreen ? "Exit FS" : "Full")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 50)
        }
        .buttonStyle(ToolbarButtonStyle())
    }
}

// MARK: - Reload Button
struct ReloadButton: View {
    @ObservedObject var runner: EmulatorRunner
    
    var body: some View {
        MouseDownButtonActionStyled(action: {
            runner.reloadGame()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                Text("Reload")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(minWidth: 50)
        }
    }
}

// MARK: - Auto Fullscreen Toggle Button
struct AutoFullscreenButton: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    
    var body: some View {
        Button(action: {
            windowController.toggleAutoFullscreen()
        }) {
            VStack(spacing: 4) {
                Image(systemName: windowController.autoFullscreenEnabled ? "rectangle.expand.vertical" : "rectangle")
                    .font(.system(size: 16, weight: .semibold))
                Text(windowController.autoFullscreenEnabled ? "Auto-FS" : "Auto-FS")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 50)
        }
        .buttonStyle(ToolbarButtonStyle())
        .foregroundColor(windowController.autoFullscreenEnabled ? .green : .white)
    }
}

// MARK: - Slot Selector Button
struct SlotSelectorButton: View {
    let currentSlot: Int
    let onSlotChange: (Int) -> Void
    @State private var isDropdownShown = false
    @State private var selectedSlot: Int = 0
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "number.circle")
                .font(.system(size: 16, weight: .semibold))
            Text("Slot \(currentSlot == -1 ? "Auto" : "\(abs(currentSlot))")")
                .font(.system(size: 10, weight: .medium))
        }
        .frame(minWidth: 50)
        .foregroundColor(.white)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropdownShown ? Color.white.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSlot = currentSlot
            isDropdownShown = true
        }
        .popover(isPresented: $isDropdownShown, arrowEdge: .top) {
            SlotPickerView(selectedSlot: $selectedSlot, onSlotSelect: onSlotChange)
                .frame(width: 180, height: 200)
        }
    }
}

// MARK: - Slot Picker View
struct SlotPickerView: View {
    @Binding var selectedSlot: Int
    let onSlotSelect: ((Int) -> Void)?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Select Save Slot")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(-1...9, id: \.self) { slot in
                        Button(action: {
                            selectedSlot = slot
                            onSlotSelect?(slot)
                            AppSettings.setInt("selected_save_slot", value: slot)
                            dismiss()
                        }) {
                            HStack {
                                Text(slot == -1 ? "Auto" : "Slot \(slot)")
                                    .foregroundColor(.white)
                                Spacer()
                                if selectedSlot == slot {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if slot < 9 {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
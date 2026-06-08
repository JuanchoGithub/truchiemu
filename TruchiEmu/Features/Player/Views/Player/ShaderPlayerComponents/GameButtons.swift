import SwiftUI
import Cocoa

class MouseDownButton: NSButton {
    override func mouseDown(with event: NSEvent) {
        if let target = self.target, let action = self.action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}

struct MouseDownButtonAction<Label: View>: NSViewRepresentable {
    let action: () -> Void
    let label: () -> Label
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        
        let button = MouseDownButton()
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.translatesAutoresizingMaskIntoConstraints = false
        
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

struct MouseDownButtonActionStyled<Label: View>: View {
  let action: () -> Void
  let label: () -> Label
  @Environment(\.colorScheme) private var colorScheme
  @State private var isPressed = false
  @State private var isHovered = false

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
                    .fill(Color.white.opacity(isPressed ? 0.15 : (isHovered ? 0.08 : 0)))
            )
            .contentShape(Rectangle())
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        .opacity(configuration.isPressed ? 0.6 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ToolbarHoverButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        .opacity(configuration.isPressed ? 0.6 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(configuration.isPressed ? 0.15 : (isHovered ? 0.08 : 0)))
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct HoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(ToolbarHoverButtonStyle(isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct ToolbarButton: View {
  let icon: String
  let label: String
  var danger: Bool = false
  var disabled: Bool = false
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
        HoverButton(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(disabled ? .white.opacity(0.3) : (danger ? AppColors.error(colorScheme).opacity(0.9) : .white.opacity(0.9)))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(danger ? AppColors.error(colorScheme).opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .disabled(disabled)
    }
}

struct PauseResumeButton: View {
  @ObservedObject var runner: EmulatorRunner
  @ObservedObject private var loc = LocalizationManager.shared
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
        HoverButton(action: {
            runner.togglePause()
        }) {
            VStack(spacing: 4) {
                Image(systemName: runner.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .semibold))
                Text(runner.isPaused ? loc.localized("toolbar.resume") : loc.localized("toolbar.pause"))
                .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .foregroundColor(runner.isPaused ? .green : .white)
    }
}

struct FullscreenButton: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        HoverButton(action: {
            windowController.toggleFullscreen()
        }) {
            VStack(spacing: 4) {
                Image(systemName: windowController.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                Text(windowController.isFullscreen ? loc.localized("toolbar.exitFullscreen") : loc.localized("toolbar.fullscreen"))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

struct ReloadButton: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        MouseDownButtonActionStyled(action: {
            runner.reloadGame()
        }) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                Text(loc.localized("toolbar.reload"))
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

struct AutoFullscreenButton: View {
  @ObservedObject var windowController: StandaloneGameWindowController
  @ObservedObject private var loc = LocalizationManager.shared
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
        HoverButton(action: {
            windowController.toggleAutoFullscreen()
        }) {
            VStack(spacing: 4) {
                Image(systemName: windowController.autoFullscreenEnabled ? "rectangle.expand.vertical" : "rectangle")
                .font(.system(size: 16, weight: .semibold))
                Text(loc.localized("toolbar.autoFullscreen"))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .foregroundColor(windowController.autoFullscreenEnabled ? .green : .white)
    }
}

struct SlotSelectorButton: View {
  let currentSlot: Int
  let onSlotChange: (Int) -> Void
  @ObservedObject var runner: EmulatorRunner
  @ObservedObject private var loc = LocalizationManager.shared
  @Environment(\.colorScheme) private var colorScheme
  @State private var isDropdownShown = false
    @State private var selectedSlot: Int = 0
    @State private var isHovered = false
    var disabled: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "number.circle")
            .font(.system(size: 16, weight: .semibold))
            Text("Slot \(currentSlot == -1 ? loc.localized("toolbar.slotAuto") : "\(abs(currentSlot))")")
            .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundColor(disabled ? .white.opacity(0.3) : .white)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isHovered && !disabled ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if !disabled {
                withAnimation(.easeOut(duration: 0.1)) {
                    isHovered = hovering
                }
            }
        }
        .onTapGesture {
            if !disabled {
                selectedSlot = currentSlot
                isDropdownShown = true
            }
        }
        .popover(isPresented: $isDropdownShown, arrowEdge: .top) {
            SlotPickerView(selectedSlot: $selectedSlot, onSlotSelect: onSlotChange, runner: runner)
                .frame(width: 280, height: 400)
        }
        .disabled(disabled)
    }
}

struct SlotPickerView: View {
    @Binding var selectedSlot: Int
    let onSlotSelect: ((Int) -> Void)?
    @ObservedObject var runner: EmulatorRunner
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var slotThumbnails: [Int: NSImage] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            Text(loc.localized("toolbar.selectSaveSlot"))
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
                            HStack(spacing: 10) {
                                ZStack {
                                    if let thumbnail = slotThumbnails[slot], let info = slotInfo(for: slot), info.exists {
                                        Image(nsImage: thumbnail)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 40, height: 30)
                                            .clipped()
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 40, height: 30)
                                            .overlay(
Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                            )
                                    }
                                }
                                .cornerRadius(4)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slotInfo(for: slot)?.displayName ?? (slot == -1 ? loc.localized("toolbar.slotAuto") : "Slot \(slot)"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                    
if let info = slotInfo(for: slot), info.exists, let timestamp = info.formattedDate {
                        Text(timestamp)
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    } else {
                        Text(slot == -1 ? loc.localized("toolbar.systemAutoSave") : loc.localized("toolbar.emptySlot"))
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                                    }
                                }
                                
                                Spacer()
                                
                                if selectedSlot == slot {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppColors.brandAccent)
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
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            loadThumbnails()
        }
    }
    
    private func slotInfo(for slot: Int) -> SlotInfo? {
        guard let rom = runner.rom else { return nil }
        let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
        return runner.saveManager.slotInfo(gameName: gameKey, systemID: rom.systemID ?? "default", slot: slot)
    }
    
    private func loadThumbnails() {
        guard let rom = runner.rom else { return }
        let systemID = rom.systemID ?? "default"
        let gameKey = "\(rom.displayName)__\(rom.id.uuidString.prefix(8))"
        for slot in -1...9 {
            if let thumbnail = runner.saveManager.loadThumbnail(gameName: gameKey, systemID: systemID, slot: slot) {
                slotThumbnails[slot] = thumbnail
            }
        }
    }
}

struct FightTrainingToolbarButton: View {
    @ObservedObject var windowController: StandaloneGameWindowController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var trainingManager = TrainingModeManager.shared

    private var isActive: Bool {
        trainingManager.isMenuVisible
    }

    var body: some View {
        if windowController.trainingModeViewModel.hasGameData {
            HoverButton(action: {
                windowController.toggleTrainingModeOverlay()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "figure.martial.arts")
                        .font(.system(size: 16, weight: .semibold))
                    Text(loc.localized("toolbar.fightTraining"))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
.foregroundColor(isActive ? AppColors.brandAccent : .white)
}
}
}

struct GameGuideToolbarButton: View {
@ObservedObject var windowController: StandaloneGameWindowController
@ObservedObject private var loc = LocalizationManager.shared

private var isActive: Bool {
windowController.gameGuideViewModel.isSidebarVisible
}

var body: some View {
if windowController.gameGuideViewModel.hasGuideData {
HoverButton(action: {
windowController.toggleGuideSidebar()
}) {
VStack(spacing: 4) {
Image(systemName: "book")
.font(.system(size: 16, weight: .semibold))
Text(loc.localized("toolbar.gameGuide"))
.font(.system(size: 10, weight: .medium))
.lineLimit(1)
}
.padding(.horizontal, 10)
.padding(.vertical, 6)
}
.foregroundColor(isActive ? AppColors.brandAccent : .white)
}
}
}
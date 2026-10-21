import SwiftUI
import Cocoa
import Combine

// MARK: - Toolbar Compact Mode

enum ToolbarCompactMode: Equatable {
    case full        // icon + label, normal spacing
    case compact     // icon + label, tighter spacing, smaller fonts
    case iconOnly    // icon only, minimal spacing
}

private struct ToolbarCompactModeKey: EnvironmentKey {
    static let defaultValue: ToolbarCompactMode = .full
}

extension EnvironmentValues {
    var toolbarCompactMode: ToolbarCompactMode {
        get { self[ToolbarCompactModeKey.self] }
        set { self[ToolbarCompactModeKey.self] = newValue }
    }
}

// Shared inner content for toolbar buttons — adapts icon/label/padding based on compact mode.
struct ToolbarButtonContent: View {
    let icon: String
    let label: String
    var badge: String? = nil
    var horizontal: Bool = false
    var textAsIcon: Bool = false
    @Environment(\.toolbarCompactMode) private var mode
    @Environment(\.colorScheme) private var colorScheme

    private func iconRow(size: CGFloat, badgeSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
            if let badge {
                Text(verbatim: badge)
                    .font(.system(size: badgeSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColors.textOnAccent(colorScheme))
                    .padding(.horizontal, badgeSize * 0.45)
                    .padding(.vertical, badgeSize * 0.15)
                    .frame(minWidth: badgeSize + 4)
                    .background(Capsule().fill(AppColors.brandAccent))
            }
        }
    }

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: 5) {
                    iconRow(
                        size: mode == .full ? 14 : 12,
                        badgeSize: mode == .full ? 9 : 8
                    )
                    Text(verbatim: label)
                        .font(.system(size: mode == .full ? 10 : 9, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, mode == .full ? 8 : 6)
                .padding(.vertical, mode == .full ? 6 : 5)
                .frame(maxWidth: .infinity)
            } else if textAsIcon {
                Text(verbatim: label)
                    .font(.system(
                        size: mode == .full ? 15 : 13,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: mode == .full ? 46 : 38)
                    .padding(.horizontal, mode == .full ? 8 : 6)
                    .padding(.vertical, mode == .full ? 8 : 7)
            } else {
                switch mode {
                case .full:
                    VStack(spacing: 4) {
                        iconRow(size: 16, badgeSize: 10)
                        Text(verbatim: label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                case .compact:
                    VStack(spacing: 2) {
                        iconRow(size: 13, badgeSize: 9)
                        Text(verbatim: label)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                case .iconOnly:
                    iconRow(size: 14, badgeSize: 9)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
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
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
        .opacity(configuration.isPressed ? 0.6 : 1.0)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.15 : (isHovered ? 0.08 : 0)))
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
  var active: Bool = false
  var badge: String? = nil
  var horizontal: Bool = false
  var textAsIcon: Bool = false
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  private var foreground: Color {
    if disabled { return AppColors.textTertiary(colorScheme) }
    if danger { return AppColors.error(colorScheme) }
    if active { return AppColors.brandAccent }
    return AppColors.textPrimary(colorScheme)
  }

  private var background: Color {
    if danger { return AppColors.error(colorScheme).opacity(0.15) }
    if active { return AppColors.brandAccent.opacity(0.16) }
    return .clear
  }

  var body: some View {
        HoverButton(action: action) {
            ToolbarButtonContent(
                icon: icon,
                label: label,
                badge: badge,
                horizontal: horizontal,
                textAsIcon: textAsIcon
            )
            .foregroundColor(foreground)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

private enum SaveStatesLayout {
    static let slotCount = 10
    static let columns = 5
    static let autoIndex = slotCount
    static let saveHereIndex = slotCount + 1
    static let loadIndex = slotCount + 2
}

@MainActor
final class SaveStatesBrowserNavContext: GamepadNavContext {
    override var priority: Int { 100 }
    override var bypassesGameplaySuppression: Bool { true }

    @Published var focusIndex = 0 {
        didSet { GamepadNavContextStack.shared.focusPublisher.send() }
    }
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let slotCount = SaveStatesLayout.slotCount
    private let columns = SaveStatesLayout.columns
    private var autoIndex: Int { SaveStatesLayout.autoIndex }
    private var saveHereIndex: Int { SaveStatesLayout.saveHereIndex }
    private var loadIndex: Int { SaveStatesLayout.loadIndex }

    override func handleAction(_ action: GamepadNavAction) {
        switch action {
        case .navigateUp:
            if focusIndex < slotCount {
                if focusIndex >= columns { focusIndex -= columns }
            } else if focusIndex == autoIndex {
                focusIndex = columns
            } else if focusIndex == saveHereIndex || focusIndex == loadIndex {
                focusIndex = autoIndex
            }
        case .navigateDown:
            if focusIndex < slotCount {
                focusIndex = focusIndex + columns < slotCount ? focusIndex + columns : autoIndex
            } else if focusIndex == autoIndex {
                focusIndex = saveHereIndex
            } else if focusIndex == saveHereIndex {
                focusIndex = loadIndex
            }
        case .navigateLeft:
            if focusIndex < slotCount {
                if focusIndex % columns > 0 { focusIndex -= 1 }
            } else if focusIndex == loadIndex {
                focusIndex = saveHereIndex
            }
        case .navigateRight:
            if focusIndex < slotCount {
                if focusIndex % columns < columns - 1 && focusIndex + 1 < slotCount {
                    focusIndex += 1
                }
            } else if focusIndex == saveHereIndex {
                focusIndex = loadIndex
            }
        case .select:
            onSelect?(focusIndex)
        case .cancel, .focusSearch:
            onDismiss?()
        default:
            break
        }
    }
}

struct SaveStatesBrowserView: View {
    @ObservedObject var runner: EmulatorRunner
    @Binding var isPresented: Bool
    var disabled: Bool = false
    var onLoadCompleted: (() -> Void)? = nil
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var navContext = SaveStatesBrowserNavContext()
    @State private var selectedSlot: Int = 0
    @State private var slotInfos: [Int: SlotInfo] = [:]
    @State private var versionCounts: [Int: Int] = [:]
    @State private var thumbnails: [Int: NSImage] = [:]
    @State private var sheetFocusIndex: Int = 0

    private let slotCount = SaveStatesLayout.slotCount
    private let gridColumns = SaveStatesLayout.columns

    private var autoIndex: Int { SaveStatesLayout.autoIndex }
    private var saveHereIndex: Int { SaveStatesLayout.saveHereIndex }
    private var loadIndex: Int { SaveStatesLayout.loadIndex }

    private var canLoad: Bool {
        !disabled && (slotInfos[selectedSlot]?.exists ?? false)
    }

    private var canSaveHere: Bool {
        !disabled && selectedSlot >= 0
    }

    private func title(for slot: Int) -> String {
        if slot == -1 { return loc.localized("slot.auto") }
        if let name = slotInfos[slot]?.customName, !name.isEmpty { return name }
        return loc.localized("osd.slot", "\(slot)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("slot.title")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 12) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: gridColumns),
                    spacing: 8
                ) {
                    ForEach(0..<slotCount, id: \.self) { slot in
                        slotTile(slot)
                    }
                }

                autoTile

                preview
            }
            .padding(12)

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button(action: saveHere) {
                    Text("slot.saveToSlot")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 96)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppColors.brandAccent)
                .disabled(!canSaveHere)
                .overlay {
                    if sheetFocusIndex == saveHereIndex {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.brandAccent, lineWidth: 2)
                            .padding(-3)
                    }
                }

                Button(action: { loadSlot(selectedSlot) }) {
                    Text("slot.loadFromSlot")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 76)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(AppColors.brandAccent)
                .disabled(!canLoad)
                .overlay {
                    if sheetFocusIndex == loadIndex {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColors.brandAccent, lineWidth: 2)
                            .padding(-3)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 340, height: 376)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            navContext.onSelect = { handleGamepadSelect($0) }
            navContext.onDismiss = { isPresented = false }
            prepare()
        }
        .gamepadNavContext(navContext)
        .onReceive(navContext.$focusIndex) { index in
            sheetFocusIndex = index
            if index < slotCount {
                selectSlot(index)
            } else if index == autoIndex {
                selectSlot(-1)
            }
        }
    }

    private func slotTile(_ slot: Int) -> some View {
        let hasSave = slotInfos[slot]?.exists == true
        let isActive = selectedSlot == slot
        let isFocused = sheetFocusIndex == slot

        return Button {
            navContext.focusIndex = slot
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: "\(slot)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(hasSave ? AppColors.textPrimary(colorScheme) : AppColors.textTertiary(colorScheme))
                Circle()
                    .fill(hasSave ? AppColors.brandAccent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? AppColors.accentBackground(colorScheme) : AppColors.buttonBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isFocused ? AppColors.brandAccent : (isActive ? AppColors.brandAccent.opacity(0.6) : AppColors.cardBorder(colorScheme)),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var autoTile: some View {
        let hasSave = slotInfos[-1]?.exists == true
        let isActive = selectedSlot == -1
        let isFocused = sheetFocusIndex == autoIndex

        return Button {
            navContext.focusIndex = autoIndex
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("slot.auto")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Circle()
                    .fill(hasSave ? AppColors.brandAccent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundColor(hasSave ? AppColors.textPrimary(colorScheme) : AppColors.textTertiary(colorScheme))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? AppColors.accentBackground(colorScheme) : AppColors.buttonBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isFocused ? AppColors.brandAccent : (isActive ? AppColors.brandAccent.opacity(0.6) : AppColors.cardBorder(colorScheme)),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if let image = thumbnails[selectedSlot] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(AppColors.cardBackgroundSubtle(colorScheme))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.textTertiary(colorScheme))
                        )
                }
            }
            .frame(width: 96, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title(for: selectedSlot))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary(colorScheme))

                if let info = slotInfos[selectedSlot], info.exists {
                    if let date = info.formattedDate {
                        Text(verbatim: date)
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                    if let size = info.fileSize {
                        Text(verbatim: size.formattedByteSize)
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                    if let count = versionCounts[selectedSlot], count > 1 {
                        Text(verbatim: String(format: loc.localized("slot.versionCount"), count))
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                } else {
                    Text("slot.noSaveInSlot")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
        )
    }

    private func prepare() {
        selectedSlot = (0..<slotCount).contains(runner.currentSlot) ? runner.currentSlot : 0
        sheetFocusIndex = selectedSlot
        navContext.focusIndex = sheetFocusIndex
        reload()
    }

    private func reload() {
        guard let rom = runner.rom else { return }
        let candidates = rom.stateKeyCandidates
        let systemID = rom.systemID ?? "default"
        let saveSet = runner.saveManager.mergedSaveSet(
            primaryKey: candidates.primary,
            fallbackKeys: candidates.fallbacks,
            systemID: systemID
        )
        let progressive = saveSet.progressiveSlotList

        var infos: [Int: SlotInfo] = [:]
        var counts: [Int: Int] = [:]
        for slot in -1..<slotCount {
            infos[slot] = saveSet.slotInfo(for: slot)
            counts[slot] = progressive[slot]?.count ?? 0
        }
        slotInfos = infos
        versionCounts = counts
        thumbnails = [:]
        loadThumbnail(for: selectedSlot)
    }

    private func selectSlot(_ slot: Int) {
        selectedSlot = slot
        loadThumbnail(for: slot)
    }

    private func loadThumbnail(for slot: Int) {
        guard thumbnails[slot] == nil,
              slotInfos[slot]?.exists == true,
              let rom = runner.rom else { return }
        let candidates = rom.stateKeyCandidates
        let systemID = rom.systemID ?? "default"
        if let image = runner.saveManager.loadThumbnail(
            primaryKey: candidates.primary,
            fallbackKeys: candidates.fallbacks,
            systemID: systemID,
            slot: slot
        ) {
            thumbnails[slot] = image
        }
    }

    private func loadSlot(_ slot: Int) {
        guard !disabled, slotInfos[slot]?.exists == true else { return }
        HardcoreModeManager.shared.attemptLoadState {
            Task { @MainActor in
                guard runner.loadState(slot: slot) else { return }
                if slot >= 0 {
                    runner.selectSlot(slot)
                }
                isPresented = false
                onLoadCompleted?()
            }
        }
    }

    private func saveHere() {
        guard canSaveHere else { return }
        HardcoreModeManager.shared.attemptSaveState {
            Task { @MainActor in
                if runner.saveState(slot: selectedSlot) {
                    runner.selectSlot(selectedSlot)
                    isPresented = false
                }
            }
        }
    }

    private func handleGamepadSelect(_ index: Int) {
        if index < slotCount {
            selectSlot(index)
            loadSlot(index)
        } else if index == autoIndex {
            selectSlot(-1)
            loadSlot(-1)
        } else if index == saveHereIndex {
            saveHere()
        } else if index == loadIndex {
            loadSlot(selectedSlot)
        }
    }
}

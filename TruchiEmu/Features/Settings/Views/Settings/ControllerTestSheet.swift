import SwiftUI
import GameController

/// Sheet that visualizes a connected gamepad as a SwiftUI-drawn Xbox layout
/// and lets the user test, remap, set deadzones, and calibrate it.
///
/// The sheet drives live input through `ControllerInputObserver`, which owns
/// a single set of `valueChangedHandler` closures (for GC) or SDL observer
/// callbacks. The remap rows use `captureNextButton()` instead of stomp-on-
/// handler so capture and the live highlight state coexist.
struct ControllerTestSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var controllerService: ControllerService
    @Environment(SystemDatabaseWrapper.self) private var systemDatabase
    @StateObject private var observer = ControllerInputObserver.shared
    @StateObject private var calibrationSession = StickCalibrationSession()
    @StateObject private var navBlocker = NavBlocker()

    let player: PlayerController
    let systemID: String
    let onDismiss: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @State private var listeningForRetroButton: RetroButton? = nil

    /// Default stick deadzone. Matches the value used by
    /// `ControllerSettingsViewGroup.DeadzoneSlidersSection` so the "reset"
    /// button in this sheet returns to the same baseline the rest of the
    /// app uses. Kept as a private constant here rather than a shared
    /// static so the test sheet remains self-contained.
    private static let defaultDeadzone: Float = 0.15

    private var usesSDL: Bool {
        player.gcController == nil && player.isSDL
    }

    private var currentGCMapping: ControllerGamepadMapping {
        if let identity = player.identityKey {
            return controllerService.mapping(forIdentity: identity, systemID: systemID)
        }
        let vendor = player.gcController?.vendorName ?? "Unknown"
        return controllerService.mapping(for: vendor, systemID: systemID)
    }

    private var currentSDLMapping: SDLControllerMapping {
        if let identity = player.identityKey {
            return controllerService.sdlMapping(forIdentity: identity, systemID: systemID)
        }
        let vendor = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
        return controllerService.sdlMapping(for: vendor, systemID: systemID)
    }

    /// For each physical button, the list of `RetroButton` entries bound to it.
    /// A physical button is in conflict if more than one `RetroButton` maps to
    /// it. Conflict entries are allowed (user choice has priority) but are
    /// highlighted in the UI so the user knows a duplicate binding exists.
    private var conflictMap: [String: [RetroButton]] {
        if usesSDL {
            var byIndex: [Int: [RetroButton]] = [:]
            for (retroBtn, m) in currentSDLMapping.buttons {
                byIndex[m.sdlButtonIndex, default: []].append(retroBtn)
            }
            var result: [String: [RetroButton]] = [:]
            for (idx, entries) in byIndex where entries.count > 1 {
                result["sdl:\(idx)"] = entries
            }
            return result
        }
        var byName: [String: [RetroButton]] = [:]
        for (retroBtn, m) in currentGCMapping.buttons {
            guard let name = m.gcElementName else { continue }
            byName[name, default: []].append(retroBtn)
        }
        var result: [String: [RetroButton]] = [:]
        for (name, entries) in byName where entries.count > 1 {
            result["gc:\(name)"] = entries
        }
        return result
    }

    private func conflictKey(for button: RetroButton) -> String? {
        if usesSDL {
            guard let m = currentSDLMapping.buttons[button] else { return nil }
            return "sdl:\(m.sdlButtonIndex)"
        }
        guard let m = currentGCMapping.buttons[button], let name = m.gcElementName else { return nil }
        return "gc:\(name)"
    }

    /// Returns every retro button currently wired to the given physical
    /// `PadButton` (or empty if none). Multiple retro buttons may share a
    /// physical position when the user duplicates bindings — every wired
    /// retro will be returned so the highlight layer can light them all up.
    private func retrosWiredTo(_ physical: PadButton) -> [RetroButton] {
        let targetIdentifier = padButtonToGCIdentifier(physical)
        let targetSDLIndex = padButtonToSDLIndex(physical)
        if usesSDL {
            return currentSDLMapping.buttons
                .filter { $1.sdlButtonIndex == targetSDLIndex }
                .map { $0.key }
        }
        return currentGCMapping.buttons
            .filter { entry in
                let m = entry.value
                return m.identifier == targetIdentifier || m.gcElementName == targetIdentifier.rawValue
            }
            .map { $0.key }
    }

    /// Set of retro buttons currently being triggered by the user's
    /// physical presses. Computed by looking up which retros are wired to
    /// each pressed physical position and unioning them. When the user
    /// presses a single physical button that has multiple retro bindings,
    /// all those retro bindings appear here at once.
    private var triggeredRetros: Set<RetroButton> {
        var result: Set<RetroButton> = []
        for physical in observer.pressed {
            result.formUnion(retrosWiredTo(physical))
        }
        return result
    }

    /// Human-readable name of the system the test sheet is currently
    /// editing, or nil when the sheet is showing the default mapping
    /// (e.g. when auto-presented from a new-controller-connect event).
    /// The auto-present path always passes `systemID: "default"`, so
    /// this stays nil and the header shows just the controller name.
    private var currentSystemName: String? {
        guard systemID != "default" else { return nil }
        return systemDatabase.system(forID: systemID)?.name
    }

    private var deadzones: (left: Float, right: Float) {
        if usesSDL {
            return (currentSDLMapping.leftStickDeadzone, currentSDLMapping.rightStickDeadzone)
        }
        return (currentGCMapping.leftStickDeadzone, currentGCMapping.rightStickDeadzone)
    }

    private var storedCalibration: ControllerCalibration {
        if let identity = player.identityKey {
            return controllerService.calibration(for: identity)
        }
        if let gc = player.gcController {
            return controllerService.calibration(forGC: gc)
        }
        return controllerService.calibration(forSDL: player.sdlInstanceID ?? 0)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            HStack(alignment: .top, spacing: 16) {
                XboxPadView(observer: observer, deadzones: deadzones, triggeredRetros: triggeredRetros, pressed: observer.pressed)
                    .frame(width: 380, height: 360)
                VStack(alignment: .leading, spacing: 12) {
                    remapSection
                    Divider()
                    deadzoneSection
                    Divider()
                    calibrateSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 760, height: 640)
        .background(AppColors.windowBackground(colorScheme, tinted: false))
        .modifier(NavBlockerModifier(context: navBlocker))
        .onAppear { observer.startObserving(player: player) }
        .onDisappear { observer.stopObserving() }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            dismissIfControllerGone()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdlControllerDisconnected)) { _ in
            dismissIfControllerGone()
        }
    }

    private func dismissIfControllerGone() {
        let stillPresent = controllerService.connectedControllers.contains { $0.id == player.id }
        if !stillPresent { onDismiss() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = player.typeIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.brandAccent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                HStack(spacing: 4) {
                    Text(String(format: loc.localized("controllers.playerShort"), player.primaryPlayer))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                    if let systemName = currentSystemName {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                        Text(systemName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColors.brandAccent)
                    }
                }
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: Remap

    private var remapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("controllers.testSheet.remapSection"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            // Every retro button the user can wire from this sheet. Mirrors
            // the full surface of the main controller settings page so the
            // sheet is a complete mirror: dpad, shoulders, triggers, stick
            // clicks, start/select/share, plus the 8 stick directions
            // (synthesised by `ControllerInputObserver` from analog axes).
            let buttons: [RetroButton] = [
                .a, .b, .x, .y,
                .l1, .r1, .l2, .r2, .l3, .r3,
                .up, .down, .left, .right,
                .start, .select
            ]
            let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(buttons, id: \.self) { btn in
                    remapRow(button: btn)
                }
            }
            if listeningForRetroButton != nil {
                Text(loc.localized("controllers.press"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning(colorScheme))
            }
            // Second group for stick directions — labelled separately so
            // the user knows these are captured from analog stick motion,
            // not a single button press. The capture flow watches the
            // observer's leftStick/rightStick values and resolves when
            // the user pushes the stick in the appropriate direction.
            stickDirectionSection
        }
    }

    private var stickDirectionSection: some View {
        let stickButtons: [RetroButton] = [
            .lStickUp, .lStickDown, .lStickLeft, .lStickRight,
            .rStickUp, .rStickDown, .rStickLeft, .rStickRight
        ]
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return VStack(alignment: .leading, spacing: 6) {
            Text(loc.localized("controllers.testSheet.stickDirectionsSection"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(stickButtons, id: \.self) { btn in
                    remapRow(button: btn)
                }
            }
        }
    }

    private func remapRow(button: RetroButton) -> some View {
        let alias: String? = {
            if usesSDL {
                return currentSDLMapping.buttons[button]?.sdlButtonAlias
            }
            return currentGCMapping.buttons[button]?.gcElementAlias
        }()
        let isListening = listeningForRetroButton == button
        let conflict: [RetroButton]? = conflictKey(for: button).flatMap { conflictMap[$0] }
        let isConflict = conflict != nil
        let hint: String? = conflict.flatMap { entries -> String? in
            let others = entries.filter { $0 != button }
            guard !others.isEmpty else { return nil }
            return String(format: loc.localized("controllers.keyConflictHint"),
                          others.map { $0.displayName(for: systemID) }.joined(separator: ", "))
        }
        // Use the compact direction label (e.g. "L ↑") for stick directions
        // so the row's left side stays short and readable in the two-column
        // grid. The full `displayName` is still surfaced via the `.help`
        // tooltip on the row.
        let compactLabel = shortLabel(for: button)
        let fullLabel = button.displayName(for: systemID)
        let aliasText = isListening ? loc.localized("controllers.press") : (alias ?? "—")
        let row = HStack(spacing: 4) {
            Text(compactLabel)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(AppColors.textPrimary(colorScheme))
            if isConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.warning(colorScheme))
            }
            Spacer(minLength: 4)
            // `lineLimit(1)` + tail truncation so the bound physical-button
            // name (`Stick Izq Izquierda` etc.) never overflows the cell.
            // The full text is still in `.help` for hover/inspection.
            Text(aliasText)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(
                    isConflict ? AppColors.warning(colorScheme)
                    : (isListening ? AppColors.warning(colorScheme)
                       : AppColors.textSecondary(colorScheme))
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isConflict ? AppColors.warning(colorScheme).opacity(0.6)
                            : (isListening ? AppColors.warning(colorScheme).opacity(0.6)
                               : AppColors.cardBorder(colorScheme).opacity(0.5)),
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture { startRemap(for: button) }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            isConflict
            ? AppColors.warning(colorScheme).opacity(0.15)
            : AppColors.cardBackgroundSubtle(colorScheme)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isConflict ? AppColors.warning(colorScheme).opacity(0.6) : .clear,
                    lineWidth: 1
                )
        )
        .cornerRadius(4)
        // Two tooltips: the left side gets the full retro-button name (e.g.
        // "Left Stick Up") so the user always knows what each row is, and
        // the row also gets the conflict hint when applicable.
        return row
            .help(fullLabel)
            .modifier(RowHelpModifier(hint: hint))
    }

    /// Compact label for the remap row's left side. Uses an ASCII arrow
    /// glyph + a single stick letter so the row stays under ~6 characters
    /// even in languages with longer localizations. Falls back to the
    /// canonical `displayName` for everything else.
    private func shortLabel(for button: RetroButton) -> String {
        switch button {
        case .lStickUp: return "L ↑"
        case .lStickDown: return "L ↓"
        case .lStickLeft: return "L ←"
        case .lStickRight: return "L →"
        case .rStickUp: return "R ↑"
        case .rStickDown: return "R ↓"
        case .rStickLeft: return "R ←"
        case .rStickRight: return "R →"
        default: return button.displayName(for: systemID)
        }
    }

    /// Applies the conflict `.help` hint to a row view when a hint is
    /// available. Kept as a private ViewModifier so `remapRow` can keep
    /// its `some View` return type without conditional view casting.
    private struct RowHelpModifier: ViewModifier {
        let hint: String?
        func body(content: Content) -> some View {
            if let hint {
                content.help(hint)
            } else {
                content
            }
        }
    }

    private func startRemap(for btn: RetroButton) {
        listeningForRetroButton = btn
        Task {
            if let pressed = await observer.captureNextButton() {
                applyMapping(retroButton: btn, padButton: pressed)
            }
            listeningForRetroButton = nil
        }
    }

    private func applyMapping(retroButton: RetroButton, padButton: PadButton) {
        // Use a meaningful alias (e.g. "D-pad (Up)", "Left Stick (Left)")
        // rather than `PadButton.label`, which returns "" for axis-style
        // buttons because they don't draw a glyph on the pad — the
        // persisted alias needs a label the user can read in the remap
        // row.
        let alias = padButtonToAlias(padButton)
        if usesSDL {
            var mapping = currentSDLMapping
            let sdlIndex = padButtonToSDLIndex(padButton)
            mapping.buttons[retroButton] = SDLButtonMapping(sdlButtonIndex: sdlIndex, sdlButtonAlias: alias)
            if let identity = player.identityKey {
                controllerService.updateSDLMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
            } else {
                let vendor = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
                controllerService.updateSDLMapping(for: vendor, systemID: systemID, mapping: mapping)
            }
        } else {
            var mapping = currentGCMapping
            let identifier = padButtonToGCIdentifier(padButton)
            mapping.buttons[retroButton] = GCButtonMapping(identifier: identifier, gcElementName: alias, gcElementAlias: alias)
            if let identity = player.identityKey {
                controllerService.updateMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
            } else {
                let vendor = player.gcController?.vendorName ?? "Unknown"
                controllerService.updateMapping(for: vendor, systemID: systemID, mapping: mapping)
            }
        }
    }

    private func padButtonToGCIdentifier(_ button: PadButton) -> GCButtonIdentifier {
        switch button {
        case .a: return .faceSouth
        case .b: return .faceEast
        case .x: return .faceWest
        case .y: return .faceNorth
        case .l1: return .leftShoulder
        case .r1: return .rightShoulder
        case .l2: return .leftTrigger
        case .r2: return .rightTrigger
        case .l3: return .leftThumbstickButton
        case .r3: return .rightThumbstickButton
        case .start: return .buttonMenu
        case .select: return .buttonOptions
        case .share: return .buttonShare
        case .dpadUp: return .dpadUp
        case .dpadDown: return .dpadDown
        case .dpadLeft: return .dpadLeft
        case .dpadRight: return .dpadRight
        case .lStickUp: return .leftThumbstickUp
        case .lStickDown: return .leftThumbstickDown
        case .lStickLeft: return .leftThumbstickLeft
        case .lStickRight: return .leftThumbstickRight
        case .rStickUp: return .rightThumbstickUp
        case .rStickDown: return .rightThumbstickDown
        case .rStickLeft: return .rightThumbstickLeft
        case .rStickRight: return .rightThumbstickRight
        }
    }

    /// Canonical human-readable alias for a physical `PadButton`, matching
    /// the naming used by the existing `GCButtonIdentifier.identify` (e.g.
    /// "D-pad (Up)", "Left Stick (Left)"). Used as the persisted
    /// `gcElementName` / `gcElementAlias` / `sdlButtonAlias` so the remap
    /// row can show a meaningful label after capture instead of an empty
    /// string. `PadButton.label` returns "" for axis-style buttons
    /// (dpad, stick directions) because those buttons don't draw a
    /// glyph on the rendered pad — but the alias field needs a label
    /// the user can read.
    private func padButtonToAlias(_ button: PadButton) -> String {
        switch button {
        case .a: return "Button A"
        case .b: return "Button B"
        case .x: return "Button X"
        case .y: return "Button Y"
        case .l1: return "Left Bumper"
        case .r1: return "Right Bumper"
        case .l2: return "Left Trigger"
        case .r2: return "Right Trigger"
        case .l3: return "Left Stick Click"
        case .r3: return "Right Stick Click"
        case .start: return "Menu Button"
        case .select: return "View Button"
        case .share: return "Share Button"
        case .dpadUp: return "D-pad (Up)"
        case .dpadDown: return "D-pad (Down)"
        case .dpadLeft: return "D-pad (Left)"
        case .dpadRight: return "D-pad (Right)"
        case .lStickUp: return "Left Stick (Up)"
        case .lStickDown: return "Left Stick (Down)"
        case .lStickLeft: return "Left Stick (Left)"
        case .lStickRight: return "Left Stick (Right)"
        case .rStickUp: return "Right Stick (Up)"
        case .rStickDown: return "Right Stick (Down)"
        case .rStickLeft: return "Right Stick (Left)"
        case .rStickRight: return "Right Stick (Right)"
        }
    }

    private func padButtonToSDLIndex(_ button: PadButton) -> Int {
        switch button {
        case .a: return Int(SDL_CONTROLLER_BUTTON_A.rawValue)
        case .b: return Int(SDL_CONTROLLER_BUTTON_B.rawValue)
        case .x: return Int(SDL_CONTROLLER_BUTTON_X.rawValue)
        case .y: return Int(SDL_CONTROLLER_BUTTON_Y.rawValue)
        case .l1: return Int(SDL_CONTROLLER_BUTTON_LEFTSHOULDER.rawValue)
        case .r1: return Int(SDL_CONTROLLER_BUTTON_RIGHTSHOULDER.rawValue)
        case .l2: return Int(SDL_CONTROLLER_BUTTON_LEFTSHOULDER.rawValue)
        case .r2: return Int(SDL_CONTROLLER_BUTTON_RIGHTSHOULDER.rawValue)
        case .l3: return Int(SDL_CONTROLLER_BUTTON_LEFTSTICK.rawValue)
        case .r3: return Int(SDL_CONTROLLER_BUTTON_RIGHTSTICK.rawValue)
        case .start: return Int(SDL_CONTROLLER_BUTTON_START.rawValue)
        case .select: return Int(SDL_CONTROLLER_BUTTON_BACK.rawValue)
        case .share: return Int(SDL_CONTROLLER_BUTTON_BACK.rawValue)
        case .dpadUp: return Int(SDL_CONTROLLER_BUTTON_DPAD_UP.rawValue)
        case .dpadDown: return Int(SDL_CONTROLLER_BUTTON_DPAD_DOWN.rawValue)
        case .dpadLeft: return Int(SDL_CONTROLLER_BUTTON_DPAD_LEFT.rawValue)
        case .dpadRight: return Int(SDL_CONTROLLER_BUTTON_DPAD_RIGHT.rawValue)
        // Stick directions don't map to a standard SDL button (they're
        // analog events). Reuse the same index range the SDL default
        // mapping uses for stick-direction aliases (0-3). The dispatch
        // layer reads the persisted binding by index, so what matters is
        // consistency with .
        case .lStickUp, .lStickLeft: return 0
        case .lStickDown, .lStickRight: return 1
        case .rStickUp, .rStickLeft: return 2
        case .rStickDown, .rStickRight: return 3
        }
    }

    // MARK: Deadzones

    private var deadzoneSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc.localized("controllers.testSheet.deadzoneSection"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                Spacer()
                if deadzones.left != Self.defaultDeadzone || deadzones.right != Self.defaultDeadzone {
                    Button {
                        updateDeadzone(left: Self.defaultDeadzone, right: Self.defaultDeadzone)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                            Text(loc.localized("controllers.testSheet.deadzoneReset"))
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppColors.brandAccent)
                }
            }
            deadzoneRow(label: loc.localized("controllers.deadzoneLeft"),
                        value: Double(deadzones.left),
                        onChange: { newVal in updateDeadzone(left: Float(newVal), right: nil) })
            deadzoneRow(label: loc.localized("controllers.deadzoneRight"),
                        value: Double(deadzones.right),
                        onChange: { newVal in updateDeadzone(left: nil, right: Float(newVal)) })
        }
    }

    private func deadzoneRow(label: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColors.textPrimary(colorScheme))
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...0.5)
                .controlSize(.small)
            Text(String(format: "%.2f", value))
                .font(.caption2.monospaced())
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func updateDeadzone(left: Float?, right: Float?) {
        if usesSDL {
            var mapping = currentSDLMapping
            if let left { mapping.leftStickDeadzone = left }
            if let right { mapping.rightStickDeadzone = right }
            if let identity = player.identityKey {
                controllerService.updateSDLMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
            } else {
                let vendor = SDLInputManager.shared.sdlVendorName(for: player.sdlInstanceID ?? 0)
                controllerService.updateSDLMapping(for: vendor, systemID: systemID, mapping: mapping)
            }
        } else {
            var mapping: ControllerGamepadMapping
            if let identity = player.identityKey {
                mapping = controllerService.mapping(forIdentity: identity, systemID: systemID)
            } else {
                let vendorName = player.gcController?.vendorName ?? "Unknown"
                mapping = controllerService.mapping(for: vendorName, systemID: systemID)
            }
            if let left { mapping.leftStickDeadzone = left }
            if let right { mapping.rightStickDeadzone = right }
            if let identity = player.identityKey {
                controllerService.updateMapping(forIdentity: identity, systemID: systemID, mapping: mapping)
            } else {
                let vendorName = player.gcController?.vendorName ?? "Unknown"
                controllerService.updateMapping(for: vendorName, systemID: systemID, mapping: mapping)
            }
        }
    }

    // MARK: Calibrate

    private var calibrateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc.localized("controllers.testSheet.calibrateSection"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
            if calibrationSession.isActive {
                Text(loc.localized("controllers.calibrateInstructions"))
                    .font(.caption2)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                HStack(spacing: 8) {
                    Button(loc.localized("controllers.calibrateCancel")) {
                        calibrationSession.stop()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(loc.localized("controllers.calibrateSave")) {
                        saveCalibration()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(AppColors.brandAccent)
                }
            } else {
                HStack(spacing: 8) {
                    Button(loc.localized("controllers.calibrate")) {
                        calibrationSession.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(AppColors.brandAccent)
                    if !storedCalibration.isDefault {
                        Button(loc.localized("controllers.calibrateReset")) {
                            clearCalibration()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(AppColors.error(colorScheme))
                    }
                }
            }
        }
    }

    private func saveCalibration() {
        let calibration = ControllerCalibration(leftStick: calibrationSession.leftStick, rightStick: calibrationSession.rightStick)
        if let identity = player.identityKey {
            controllerService.saveCalibration(calibration, for: identity)
        } else if let gc = player.gcController {
            controllerService.saveCalibration(calibration, for: controllerService.identityKey(for: gc))
        } else if let identity = controllerService.identityKey(forSDL: player.sdlInstanceID ?? 0) {
            controllerService.saveCalibration(calibration, for: identity)
        }
        calibrationSession.stop()
    }

    private func clearCalibration() {
        if let identity = player.identityKey {
            controllerService.clearCalibration(for: identity)
        } else if let gc = player.gcController {
            controllerService.clearCalibration(for: controllerService.identityKey(for: gc))
        } else if let identity = controllerService.identityKey(forSDL: player.sdlInstanceID ?? 0) {
            controllerService.clearCalibration(for: identity)
        }
    }
}

// MARK: - XboxPadView (SwiftUI-drawn)

private struct XboxPadView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var observer: ControllerInputObserver
    let deadzones: (left: Float, right: Float)
    /// Retro buttons currently being triggered by the user's physical
    /// presses. Computed in the parent from `observer.pressed` and the
    /// current wiring. A visual at canonical position `P` lights up
    /// strongly iff the retro whose canonical position is `P` is in this
    /// set — regardless of which physical button the user actually pressed.
    /// When two retro buttons share a physical press, both canonical
    /// visuals light up.
    let triggeredRetros: Set<RetroButton>
    /// Physical `PadButton` set currently held down. The visual at any
    /// physical position in this set gets a subtle text tint so the user
    /// can tell *which* physical button they're pressing — distinct from
    /// the strong retro-trigger highlight.
    let pressed: Set<PadButton>

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.18)
                    .fill(AppColors.cardBackground(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: h * 0.18)
                            .stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                    )
                // The view reads `observer.leftStick` / `observer.rightStick`
                // directly here, so SwiftUI's @ObservedObject subscription
                // on `observer` invalidates this body whenever the
                // observer publishes a new stick position. (We also pass
                // the values down to `stickView` so the rendered offset
                // updates with the latest values — using only the prop
                // chain would require the parent to re-evaluate, which
                // it doesn't when only the stick values change.)
                padContent(w: w, h: h, leftStick: observer.leftStick, rightStick: observer.rightStick)
            }
        }
    }

    private func padContent(w: CGFloat, h: CGFloat, leftStick: (x: Float, y: Float), rightStick: (x: Float, y: Float)) -> some View {
        let lStickCenter = CGPoint(x: w * 0.28, y: h * 0.62)
        let rStickCenter = CGPoint(x: w * 0.72, y: h * 0.62)
        let stickRadius = h * 0.13
        let triggerHeight = h * 0.06
        let bumperY = h * 0.18

        return ZStack {
            // L2/R2 trigger bars (drawn behind everything else)
            triggerBar(x: w * 0.18, y: 0, width: w * 0.18, height: triggerHeight, value: observer.leftTrigger, isLeft: true)
            triggerBar(x: w * 0.64, y: 0, width: w * 0.18, height: triggerHeight, value: observer.rightTrigger, isLeft: false)

            // L1/R1 bumpers
            padButton(.l1, center: CGPoint(x: w * 0.18, y: bumperY), radius: w * 0.06)
            padButton(.r1, center: CGPoint(x: w * 0.82, y: bumperY), radius: w * 0.06)

            // D-pad (cross)
            dpad(center: CGPoint(x: w * 0.28, y: h * 0.30), arm: w * 0.05, thick: w * 0.04)

            // ABXY (diamond, right side)
            abxy(center: CGPoint(x: w * 0.72, y: h * 0.30), spacing: w * 0.07, radius: w * 0.045)

            // Start/Select/Share
            smallPill(.select, center: CGPoint(x: w * 0.45, y: h * 0.42))
            smallPill(.start, center: CGPoint(x: w * 0.55, y: h * 0.42))
            smallPill(.share, center: CGPoint(x: w * 0.50, y: h * 0.34))

            // Sticks (L3/R3 clickable)
            stickView(.l3, center: lStickCenter, radius: stickRadius, deadZone: deadzones.left,
                      x: leftStick.x, y: leftStick.y, label: "L")
            stickView(.r3, center: rStickCenter, radius: stickRadius, deadZone: deadzones.right,
                      x: rightStick.x, y: rightStick.y, label: "R")
        }
    }

    private func padButton(_ button: PadButton, center: CGPoint, radius: CGFloat) -> some View {
        let diameter = radius * 2
        // Two independent signals per visual:
        //  - isTriggeredRetro: this position is the canonical home of a
        //    retro button that the user just triggered (by pressing
        //    wherever the wiring sends it). Strong accent fill.
        //  - isPressed: the user is currently holding this exact physical
        //    position. Subtle text tint so the user sees "you're pressing
        //    X" without confusing it with a mapping-trigger highlight.
        // The two can be true together (default mappings: physical A
        // pressed → retro A triggers → A position both lit by trigger and
        // pressed). Visual label is always the physical default.
        let canonicalRetro = Self.canonicalRetro(for: button)
        let isTriggeredRetro = canonicalRetro.map { triggeredRetros.contains($0) } ?? false
        let isPressed = pressed.contains(button)
        return ZStack {
            Circle()
                .fill(
                    isTriggeredRetro
                    ? AppColors.brandAccent
                    : AppColors.cardBackgroundSubtle(colorScheme)
                )
            Circle()
                .stroke(
                    isTriggeredRetro
                    ? AppColors.brandAccent.opacity(0.6)
                    : AppColors.cardBorder(colorScheme),
                    lineWidth: isTriggeredRetro ? 2 : 1
                )
            Text(button.label.uppercased())
                .font(.system(size: radius * 0.7, weight: .semibold))
                .foregroundStyle(
                    isTriggeredRetro
                    ? .white
                    : (isPressed
                        ? AppColors.brandAccent.opacity(0.1)
                        : AppColors.textPrimary(colorScheme))
                )
        }
        .frame(width: diameter, height: diameter)
        .position(center)
        .animation(.easeOut(duration: 0.08), value: isTriggeredRetro)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    /// Reverse of `canonicalPadButton(for:)`: maps a physical position
    /// back to the retro button whose canonical home it represents. Used
    /// here to decide whether a visual should light up strongly when the
    /// user presses a button wired to that retro somewhere else.
    private static func canonicalRetro(for button: PadButton) -> RetroButton? {
        switch button {
        case .a: return .a
        case .b: return .b
        case .x: return .x
        case .y: return .y
        case .l1: return .l1
        case .r1: return .r1
        case .l2: return .l2
        case .r2: return .r2
        case .l3: return .l3
        case .r3: return .r3
        case .start: return .start
        case .select: return .select
        case .dpadUp: return .up
        case .dpadDown: return .down
        case .dpadLeft: return .left
        case .dpadRight: return .right
        case .lStickUp: return .lStickUp
        case .lStickDown: return .lStickDown
        case .lStickLeft: return .lStickLeft
        case .lStickRight: return .lStickRight
        case .rStickUp: return .rStickUp
        case .rStickDown: return .rStickDown
        case .rStickLeft: return .rStickLeft
        case .rStickRight: return .rStickRight
        case .share: return nil
        }
    }

    private func smallPill(_ button: PadButton, center: CGPoint) -> some View {
        let canonicalRetro = Self.canonicalRetro(for: button)
        let isTriggeredRetro = canonicalRetro.map { triggeredRetros.contains($0) } ?? false
        let isPressed = pressed.contains(button)
        return Capsule()
            .fill(
                isTriggeredRetro
                ? AppColors.brandAccent
                : AppColors.cardBackgroundSubtle(colorScheme)
            )
            .overlay(
                Capsule().stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
            )
            .overlay(
                Text(button.label.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(
                        isTriggeredRetro
                        ? .white
                        : (isPressed
                            ? AppColors.brandAccent.opacity(0.1)
                            : AppColors.textSecondary(colorScheme))
                    )
            )
            .frame(width: 36, height: 14)
            .position(center)
            .animation(.easeOut(duration: 0.08), value: isTriggeredRetro)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private func abxy(center: CGPoint, spacing: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            padButton(.y, center: CGPoint(x: center.x, y: center.y - spacing), radius: radius)
            padButton(.a, center: CGPoint(x: center.x, y: center.y + spacing), radius: radius)
            padButton(.x, center: CGPoint(x: center.x - spacing, y: center.y), radius: radius)
            padButton(.b, center: CGPoint(x: center.x + spacing, y: center.y), radius: radius)
        }
    }

    private func dpad(center: CGPoint, arm: CGFloat, thick: CGFloat) -> some View {
        ZStack {
            dpadArm(.dpadUp, center: CGPoint(x: center.x, y: center.y - arm), size: CGSize(width: thick, height: arm * 1.6))
            dpadArm(.dpadDown, center: CGPoint(x: center.x, y: center.y + arm), size: CGSize(width: thick, height: arm * 1.6))
            dpadArm(.dpadLeft, center: CGPoint(x: center.x - arm, y: center.y), size: CGSize(width: arm * 1.6, height: thick))
            dpadArm(.dpadRight, center: CGPoint(x: center.x + arm, y: center.y), size: CGSize(width: arm * 1.6, height: thick))
        }
    }

    private func dpadArm(_ button: PadButton, center: CGPoint, size: CGSize) -> some View {
        let canonicalRetro = Self.canonicalRetro(for: button)
        let isTriggeredRetro = canonicalRetro.map { triggeredRetros.contains($0) } ?? false
        let isPressed = pressed.contains(button)
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    isTriggeredRetro
                    ? AppColors.brandAccent
                    : AppColors.cardBackgroundSubtle(colorScheme)
                )
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isTriggeredRetro
                    ? AppColors.brandAccent.opacity(0.6)
                    : AppColors.cardBorder(colorScheme),
                    lineWidth: isTriggeredRetro ? 2 : 1
                )
        }
        .frame(width: size.width, height: size.height)
        .position(center)
        .animation(.easeOut(duration: 0.08), value: isTriggeredRetro)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private func stickView(_ clickButton: PadButton, center: CGPoint, radius: CGFloat, deadZone: Float, x: Float, y: Float, label: String) -> some View {
        let isClicked = pressed.contains(clickButton)
        // Layer order (bottom → top):
        //   1. outer ring
        //   2. dot + label (the stick position the user is moving)
        //   3. deadzone ring + fill (drawn last so it sits on top of the
        //      dot — gives the user a clear visual of the "off-limits"
        //      zone without the dot hiding it)
        let deadzoneDiameter = CGFloat(deadZone * 2 * Float(radius * 1.2))
        return ZStack {
            Circle()
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    Circle().stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
            Circle()
                .fill(isClicked ? AppColors.brandAccent : AppColors.brandAccent.opacity(0.85))
                .frame(width: radius * 0.85, height: radius * 0.85)
                .offset(x: CGFloat(x) * radius * 0.55, y: -CGFloat(y) * radius * 0.55)
                .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 3)
            Text(label)
                .font(.system(size: radius * 0.3, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: CGFloat(x) * radius * 0.55, y: -CGFloat(y) * radius * 0.55)
            // Deadzone — drawn on top so it's the most prominent overlay
            // on the stick. Subtle fill makes the "off" area obvious; the
            // ring stroke is a 2px warning-tinted line so users can see
            // exactly where the active range begins.
            Circle()
                .fill(AppColors.textSecondary(colorScheme).opacity(0.18))
                .frame(width: deadzoneDiameter, height: deadzoneDiameter)
            Circle()
                .stroke(AppColors.warning(colorScheme).opacity(0.7), lineWidth: 2)
                .frame(width: deadzoneDiameter, height: deadzoneDiameter)
        }
        .frame(width: radius * 2.4, height: radius * 2.4)
        .position(center)
    }

    private func triggerBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, value: Float, isLeft: Bool) -> some View {
        let clamped = max(0, min(1, value))
        return ZStack(alignment: isLeft ? .trailing : .leading) {
            Capsule()
                .fill(AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    Capsule().stroke(AppColors.cardBorder(colorScheme), lineWidth: 1)
                )
            Capsule()
                .fill(AppColors.brandAccent)
                .frame(width: width * CGFloat(clamped), height: height - 2)
                .opacity(0.85)
        }
        .frame(width: width, height: height)
        .position(x: x + width / 2, y: y + height / 2)
    }
}


// MARK: - NavBlocker

/// `GamepadNavContext` that swallows every action silently and outranks the
/// library context (priority 100). Used by the test sheet so library-level
/// actions bound to A/Start (launch game) and other buttons don't fire while
/// the user is testing their controller. The context handles no actions
/// itself — it just sits on top of the stack and wins the dispatch.
@MainActor
final class NavBlocker: GamepadNavContext {
    override var priority: Int { 100 }
}

private struct NavBlockerModifier: ViewModifier {
    let context: NavBlocker

    func body(content: Content) -> some View {
        content
            .onAppear { GamepadNavContextStack.shared.push(context) }
            .onDisappear { GamepadNavContextStack.shared.remove(context) }
    }
}

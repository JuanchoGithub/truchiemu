import Foundation
import SwiftUI

// MARK: - Hardcore Mode Manager

// Manages hardcore mode enforcement for RetroAchievements.
// When hardcore mode is active, save states, load states, rewind, slow motion, and cheats
// will disqualify hardcore. The user is shown a confirmation dialog before proceeding.
// Supports layered scope: global → per-system → per-game.
// The user's persistent settings (auto-load, auto-save, cheats) are NEVER modified globally.
// Instead, point-of-use gates check `isHardcoreActive` at runtime to block/allow actions.
@MainActor
class HardcoreModeManager: ObservableObject {
    static let shared = HardcoreModeManager()

    @Published var isHardcoreActive: Bool = false
    @Published var pendingViolation: HardcoreViolation?

    private static let perSystemPrefix = "ra_hardcore_system_"
    private static let hardcoreOptionKey = "hardcore_mode"
    static let coresWithHardcoreOption: Set<String> = [
        "mupen64plus_next_libretro"
    ]

    init() {}

    // MARK: - Violation Types

    enum HardcoreFeature: String, CaseIterable {
        case saveState = "saveState"
        case loadState = "loadState"
        case rewind = "rewind"
        case slowMotion = "slowMotion"
        case cheats = "cheats"

        func localizedName() -> String {
            let loc = LocalizationManager.shared
            switch self {
            case .saveState: return loc.localized("hardcore.saveStates")
            case .loadState: return loc.localized("hardcore.loadStates")
            case .rewind: return loc.localized("hardcore.rewind")
            case .slowMotion: return loc.localized("hardcore.slowMotion")
            case .cheats: return loc.localized("hardcore.cheats")
            }
        }
    }

    struct HardcoreViolation {
        let feature: HardcoreFeature
        let action: () -> Void
    }

    // MARK: - Scoped Hardcore Resolution

    func isHardcoreActive(for rom: ROM?) -> Bool {
        guard RetroAchievementsService.shared.isEnabled else { return false }
        if let rom, let perGame = rom.settings.hardcoreMode {
            return perGame
        }
        if let systemID = rom?.systemID,
           let perSystem = AppSettings.get("\(Self.perSystemPrefix)\(systemID)", type: Bool.self) {
            return perSystem
        }
        return RetroAchievementsService.shared.hardcoreMode
    }

    // MARK: - Activation / Deactivation

    func activateHardcore(rom: ROM? = nil, coreID: String? = nil, systemID: String? = nil) {
        guard !isHardcoreActive(for: rom) else { return }

        isHardcoreActive = true

        if let coreID, let systemID {
            Self.pushCoreOption(coreID: coreID, systemID: systemID)
        }

        NotificationCenter.default.post(name: .hardcoreModeChanged, object: nil)
    }

    func deactivateHardcore(rom: ROM? = nil, coreID: String? = nil, systemID: String? = nil) {
        guard isHardcoreActive(for: rom) else { return }

        isHardcoreActive = false

        if let coreID, let systemID {
            Self.removeCoreOption(coreID: coreID, systemID: systemID)
        }

        NotificationCenter.default.post(name: .hardcoreModeChanged, object: nil)
    }

    func syncState(rom: ROM? = nil, coreID: String? = nil, systemID: String? = nil) {
        isHardcoreActive = isHardcoreActive(for: rom)
    }

    // MARK: - Feature Confirmation

    // Silent guard for automatic/programmatic checks (auto-save, auto-load, cheat injection at launch).
    var areSaveStatesBlocked: Bool { isHardcoreActive }
    var isRewindBlocked: Bool { isHardcoreActive }
    var isSlowMotionBlocked: Bool { isHardcoreActive }
    var areCheatsBlocked: Bool { isHardcoreActive }

    // If hardcore is active, presents a confirmation dialog. If not, executes immediately.
    @discardableResult
    func attemptFeature(_ feature: HardcoreFeature, action: @escaping () -> Void) -> Bool {
        guard isHardcoreActive else {
            action()
            return true
        }
        pendingViolation = HardcoreViolation(feature: feature, action: action)
        NotificationCenter.default.post(name: .hardcoreConfirmationRequired, object: nil)
        return false
    }

    // User confirmed — disqualify hardcore and perform the action.
    func confirmViolation() {
        guard let violation = pendingViolation else { return }
        disqualifyHardcore(reason: "User chose to use \(violation.feature.rawValue)")
        pendingViolation = nil
        NotificationCenter.default.post(name: .hardcoreConfirmationDismissed, object: nil)
        violation.action()
    }

    // User cancelled — dismiss the dialog, no action taken.
    func cancelViolation() {
        pendingViolation = nil
        NotificationCenter.default.post(name: .hardcoreConfirmationDismissed, object: nil)
    }

    // MARK: - Compatibility Shorthands

    func attemptSaveState(action: @escaping () -> Void) -> Bool {
        attemptFeature(.saveState, action: action)
    }

    func attemptLoadState(action: @escaping () -> Void) -> Bool {
        attemptFeature(.loadState, action: action)
    }

    func attemptRewind(action: @escaping () -> Void) -> Bool {
        attemptFeature(.rewind, action: action)
    }

    func attemptSlowMotion(action: @escaping () -> Void) -> Bool {
        attemptFeature(.slowMotion, action: action)
    }

    func attemptUseCheats(action: @escaping () -> Void) -> Bool {
        attemptFeature(.cheats, action: action)
    }

    // MARK: - Session-Only Disqualification

    // Drops session to softcore (in-memory only; persisted setting stays on).
    // Persistent settings (auto-load, auto-save, cheats) are NOT modified,
    // so they remain at the user's preferred values and will take effect
    // on the next relevant event (e.g., auto-save on close).
    func disqualifyHardcore(reason: String) {
        guard isHardcoreActive else { return }

        LoggerService.warning(category: "HardcoreMode", "Hardcore disqualified: \(reason)")

        isHardcoreActive = false

        NotificationCenter.default.post(name: .hardcoreModeChanged, object: nil)
    }

    // MARK: - Core Option Push

    static func pushCoreOption(coreID: String, systemID: String) {
        guard coresWithHardcoreOption.contains(coreID) else { return }
        var overrides = CoreOptionsManager.shared.loadSystemOverrides(for: coreID, systemID: systemID)
        overrides[hardcoreOptionKey] = "true"
        CoreOptionsManager.shared.saveSystemOverride(for: coreID, systemID: systemID, values: overrides)
        XPCBridgeAdapter.shared.setVariablesUpdated()
    }

    static func removeCoreOption(coreID: String, systemID: String) {
        guard coresWithHardcoreOption.contains(coreID) else { return }
        var overrides = CoreOptionsManager.shared.loadSystemOverrides(for: coreID, systemID: systemID)
        overrides.removeValue(forKey: hardcoreOptionKey)
        if overrides.isEmpty {
            CoreOptionsManager.shared.deleteSystemOverride(for: coreID, systemID: systemID)
        } else {
            CoreOptionsManager.shared.saveSystemOverride(for: coreID, systemID: systemID, values: overrides)
        }
        XPCBridgeAdapter.shared.setVariablesUpdated()
    }
}

// MARK: - Notification

extension Notification.Name {
    static let hardcoreModeChanged = Notification.Name("hardcoreModeChanged")
    static let hardcoreConfirmationRequired = Notification.Name("hardcoreConfirmationRequired")
    static let hardcoreConfirmationDismissed = Notification.Name("hardcoreConfirmationDismissed")
}

// MARK: - Hardcore Mode Confirmation Alert

struct HardcoreViolationAlert: View {
    @ObservedObject var hardcoreManager = HardcoreModeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Group {
            if hardcoreManager.pendingViolation != nil {
                VStack {
                    Spacer()
                    VStack(spacing: AppSpacing.lg) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(AppColors.warning(colorScheme))

                        Text(loc.localized("hardcore.confirmTitle"))
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(loc.localized("hardcore.confirmMessage"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: AppSpacing.lg) {
                            Button {
                                hardcoreManager.cancelViolation()
                            } label: {
                                Text(loc.localized("hardcore.confirmCancel"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppColors.textPrimary(colorScheme))
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(AppColors.cardBackground(colorScheme))
                                    .cornerRadius(AppRadius.md)
                            }
                            .buttonStyle(.plain)

                            Button {
                                hardcoreManager.confirmViolation()
                            } label: {
                                Text(loc.localized("hardcore.confirmProceed"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppColors.error(colorScheme))
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(AppColors.error(colorScheme).opacity(0.15))
                                    .cornerRadius(AppRadius.md)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppSpacing.xl)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .frame(maxWidth: 400)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Hardcore Mode Banner

struct HardcoreModeBanner: View {
    @ObservedObject var raService = RetroAchievementsService.shared
    @ObservedObject var hardcoreManager = HardcoreModeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Group {
            if hardcoreManager.isHardcoreActive && raService.isEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.fill")
                        .font(.caption)
                        .foregroundColor(AppColors.warning(colorScheme))
                    Text(loc.localized("achievement.hardcoreModeActive"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.warning(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.warning(colorScheme).opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

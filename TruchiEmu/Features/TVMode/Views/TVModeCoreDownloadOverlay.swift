import SwiftUI
import AppKit

/// Sheet-style nav context bespoke to `TVModeCoreDownloadOverlay`.
///
/// - D-pad Up / Down: cycle the available cores (driven by `onCycleCore`).
/// - D-pad Left / Right: cycle the action buttons (Refresh / Primary / Cancel).
/// - A (select): activate the currently focused action (`onSelect`).
/// - B (cancel): dismiss (`onDismiss`).
/// - L/R shoulder buttons also cycle cores as a convenience.
///
@MainActor
final class TVModeCoreDownloadSheetContext: GamepadNavContext {
    override var priority: Int { 100 }

    @Published var focusIndex: Int = 1 {
        didSet { GamepadNavContextStack.shared.focusPublisher.send() }
    }

    var itemCount: Int = 3
    var onCycleCore: ((_ delta: Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    override func handleAction(_ action: GamepadNavAction) {
        switch action {
        case .navigateUp:        onCycleCore?(-1)
        case .navigateDown:      onCycleCore?(1)
        case .navigateLeft:      if focusIndex > 0 { focusIndex -= 1 }
        case .navigateRight:     if focusIndex < itemCount - 1 { focusIndex += 1 }
        case .scrollUp:          onCycleCore?(-3)
        case .scrollDown:        onCycleCore?(3)
        case .select:            onSelect?(focusIndex)
        case .cancel:            onDismiss?()
        case .focusSearch:       onDismiss?()
        default:                 break
        }
    }
}

/// Self-contained, TV-mode-native core download overlay.
///
/// Re-implements the minimal essentials of `CoreDownloadSheet` directly so
/// the entire surface is gamepad-navigable. We don't drive the existing
/// sheet because its actions are private — replicating the core flow here
/// keeps the controller path simple: pick a core, install or launch, cancel.
///
/// Driven by D-pad L/R (cycle cores), U/D (Refresh / Primary / Cancel), and
/// A (activate) / B (cancel). A `GamepadSheetContext` is pushed on
/// `GamepadNavContextStack` while visible; it owns hardware-button routing.
///
struct TVModeCoreDownloadOverlay: View {
    let pending: CoreManager.PendingCoreDownload
    @ObservedObject var coreManager: CoreManager
    @ObservedObject var library: ROMLibrary
    @ObservedObject var loc: LocalizationManager
    let colorScheme: ColorScheme
    let onDismiss: () -> Void

    @State private var selectedCoreID: String
    @State private var isDownloading: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var error: String?
    @StateObject private var navContext = TVModeCoreDownloadSheetContext()

    private var focusIndex: Int { navContext.focusIndex }

    /// Tracks the direction of the last core change so the slide-in
    /// transition matches (down→next core slides up, up→prev core slides down).
    @State private var slideUp: Bool = true

    /// Three row actions, in nav order. The primary label switches between
    /// "Install" / "Launch" depending on whether the selected core is installed.


    init(
        pending: CoreManager.PendingCoreDownload,
        coreManager: CoreManager,
        library: ROMLibrary,
        loc: LocalizationManager,
        colorScheme: ColorScheme,
        onDismiss: @escaping () -> Void
    ) {
        self.pending = pending
        self._coreManager = ObservedObject(wrappedValue: coreManager)
        self._library = ObservedObject(wrappedValue: library)
        self._loc = ObservedObject(wrappedValue: loc)
        self.colorScheme = colorScheme
        self.onDismiss = onDismiss
        _selectedCoreID = State(initialValue: pending.coreInfo.coreID)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack {
                Spacer()
                card
                Spacer()
                hintBar
                    .padding(.top, 18)
            }
            .padding(60)
        }
        .gamepadNavContext(navContext)
        .onAppear { bindNav(); seedInitialSelection() }
        .onDisappear { navContext.onCycleCore = nil; navContext.onSelect = nil; navContext.onDismiss = nil }
    }

    private func bindNav() {
        navContext.onCycleCore = { [self] delta in shiftCore(delta) }
        navContext.onSelect = { [self] idx in activateAction(at: idx) }
        navContext.onDismiss = { [self] in onDismiss() }
        navContext.focusIndex = 1   // start on Primary (install/launch)
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            corePicker
            Divider().opacity(0.4)
            actionRow
            if let error { errorBanner(error) }
            if case .downloading(let progress) = coreManager.downloadPhase, isDownloading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.brandAccent)
            }
        }
        .padding(24)
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.windowBackground(colorScheme, tinted: false))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.brandAccent.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.6), radius: 30, y: 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("coreDownload.title")
                .font(.system(size: 22, weight: .bold))
            if let rom = pendingROM, let system = pendingSystem {
                Text(verbatim: "\(rom.name) — \(system.name)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var corePicker: some View {
        VStack(spacing: 8) {
            coreListArrow(forward: false)
            selectedCoreCard
                .id(selectedCoreID)
                .transition(.asymmetric(
                    insertion: .move(edge: slideUp ? .bottom : .top).combined(with: .opacity),
                    removal: .move(edge: slideUp ? .top : .bottom).combined(with: .opacity)
                ))
            coreListArrow(forward: true)
        }
    }

    private func coreListArrow(forward: Bool) -> some View {
        Button(action: { shiftCore(forward ? 1 : -1) }) {
            Image(systemName: forward ? "chevron.down" : "chevron.up")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var selectedCoreCard: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(verbatim: currentEntry.displayName)
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                if currentEntry.isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(loc.localized("coreDownload.installed"))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                    Text(loc.localized("coreDownload.downloadable"))
                        .foregroundStyle(.secondary)
                }
                if let rec = currentEntry.metadata.recommendation {
                    Text(verbatim: "· \(rec)").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            if let desc = currentEntryOptionalDesc {
                Text(verbatim: desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Text(verbatim: "\(corePositionText)  ·  \(availableCount) \(loc.localized("coreDownload.cores"))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            actionButton(index: 0, label: loc.localized("coreDownload.refresh"),
                         icon: "arrow.clockwise", tint: .secondary)
            actionButton(index: 1, label: primaryLabel,
                         icon: currentEntry.isInstalled ? "play.fill" : "icloud.and.arrow.down.fill",
                         tint: AppColors.brandAccent, prominent: true)
            actionButton(index: 2, label: loc.localized("app.cancel"),
                         icon: "xmark", tint: .red)
        }
    }

    private func actionButton(index: Int, label: String, icon: String,
                              tint: Color, prominent: Bool = false) -> some View {
        let focused = focusIndex == index
        return Button(action: { activateAction(at: index) }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(verbatim: label).font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if prominent {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(focused ? tint.opacity(0.95) : tint.opacity(0.75))
                    } else if focused {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tint.opacity(0.22))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.12))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(focused ? tint : Color.clear, lineWidth: 2)
            )
            .foregroundStyle(prominent && focused ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isDownloading || isRefreshing)
    }

    private var hintBar: some View {
        HStack(spacing: 20) {
            hint("\u{2190}\u{2192}", loc.localized("tvMode.coreDownload.cycle"))
            hint("\u{2191}\u{2193}", loc.localized("tvMode.coreDownload.actions"))
            hint("A", loc.localized("tvMode.coreDownload.confirm"))
            hint("B", loc.localized("tvMode.coreDownload.cancel"))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Capsule().fill(AppColors.windowBackground(colorScheme, tinted: false).opacity(0.9)))
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: key).font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary)
            Text(verbatim: label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(verbatim: msg).font(.system(size: 13)).foregroundStyle(.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
    }

    // MARK: - Derived data

    private struct CorePick {
        let id: String
        let displayName: String
        let isInstalled: Bool
        let metadata: CoreMetadata
        let remoteInfo: RemoteCoreInfo?
    }

    private var allCoresForSystem: [CorePick] {
        var result: [CorePick] = []
        var seen: Set<String> = []
        if let sysID = pending.systemID, let system = SystemDatabase.system(forID: sysID) {
            for c in coreManager.installedCores where c.systemIDs.contains(system.id) || system.defaultCoreID == c.id {
                if seen.insert(c.id).inserted {
                    result.append(CorePick(id: c.id, displayName: c.displayName, isInstalled: true,
                                           metadata: c.metadata, remoteInfo: nil))
                }
            }
            for r in coreManager.availableCores where !seen.contains(r.coreID) &&
                (r.systemIDs.contains(system.id) || system.defaultCoreID == r.coreID) {
                seen.insert(r.coreID)
                result.append(CorePick(id: r.coreID, displayName: r.displayName, isInstalled: false,
                                       metadata: r.metadata, remoteInfo: r))
            }
        } else {
            for c in coreManager.installedCores {
                if seen.insert(c.id).inserted {
                    result.append(CorePick(id: c.id, displayName: c.displayName, isInstalled: true,
                                           metadata: c.metadata, remoteInfo: nil))
                }
            }
            for r in coreManager.availableCores where !seen.contains(r.coreID) {
                seen.insert(r.coreID)
                result.append(CorePick(id: r.coreID, displayName: r.displayName, isInstalled: false,
                                       metadata: r.metadata, remoteInfo: r))
            }
        }
        return result
    }

    private var currentEntry: CorePick {
        if let pick = allCoresForSystem.first(where: { $0.id == selectedCoreID }) { return pick }
        if allCoresForSystem.isEmpty {
            return CorePick(id: pending.coreInfo.coreID, displayName: pending.coreInfo.displayName,
                            isInstalled: false, metadata: pending.coreInfo.metadata,
                            remoteInfo: pending.coreInfo)
        }
        return allCoresForSystem.first ?? CorePick(id: pending.coreInfo.coreID,
                                                    displayName: pending.coreInfo.displayName,
                                                    isInstalled: false,
                                                    metadata: pending.coreInfo.metadata,
                                                    remoteInfo: pending.coreInfo)
    }

    private var currentEntryOptionalDesc: String? {
        let d = currentEntry.metadata.description
        return d.isEmpty ? nil : d
    }

    private var availableCount: Int { allCoresForSystem.count }

    private var corePositionText: String {
        let i = allCoresForSystem.firstIndex(where: { $0.id == selectedCoreID }).map { $0 + 1 } ?? 1
        return "\(i)"
    }

    private var primaryLabel: String {
        currentEntry.isInstalled ? loc.localized("coreDownload.launch")
                                  : loc.localized("coreDownload.downloadAndInstall")
    }

    private var pendingROM: ROM? {
        guard let id = pending.romID else { return nil }
        return library.roms.first { $0.id == id }
    }

    private var pendingSystem: SystemInfo? {
        guard let sysID = pending.systemID else { return nil }
        return SystemDatabase.system(forID: sysID)
    }

    // MARK: - Actions

    private func seedInitialSelection() {
        if let firstInstalled = allCoresForSystem.first(where: { $0.isInstalled }) {
            selectedCoreID = firstInstalled.id
        } else {
            selectedCoreID = pending.coreInfo.coreID
        }
    }

    private func shiftCore(_ delta: Int) {
        guard !allCoresForSystem.isEmpty else { return }
        let count = allCoresForSystem.count
        let currentIdx = allCoresForSystem.firstIndex(where: { $0.id == selectedCoreID }) ?? 0
        var newIdx = (currentIdx + delta) % count
        if newIdx < 0 { newIdx += count }
        if newIdx == currentIdx { return }
        // delta > 0 means the user pressed Down (next core) — the new card
        // should enter from below and the old one exit upward.
        slideUp = delta > 0
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedCoreID = allCoresForSystem[newIdx].id
        }
    }

    private func activateAction(at index: Int) {
        switch index {
        case 0: refreshCores()
        case 1: startDownloadOrLaunch()
        default: onDismiss()
        }
    }

    private func refreshCores() {
        guard !isRefreshing, !isDownloading else { return }
        isRefreshing = true
        error = nil
        Task {
            await LibretroInfoManager.shared.refreshCoreInfo()
            await coreManager.fetchAvailableCores()
            await MainActor.run {
                isRefreshing = false
                let found = allCoresForSystem.contains(where: { $0.id == selectedCoreID })
                if !found {
                    if let firstInstalled = allCoresForSystem.first(where: { $0.isInstalled }) {
                        selectedCoreID = firstInstalled.id
                    } else if let first = allCoresForSystem.first {
                        selectedCoreID = first.id
                    }
                }
                if allCoresForSystem.isEmpty {
                    error = loc.localized("coreDownload.noCoresFound")
                }
            }
        }
    }

    private func startDownloadOrLaunch() {
        guard !isDownloading else { return }
        let entry = currentEntry
        if entry.isInstalled {
            Task { await launchWithCoreID(entry.id) }
            return
        }
        guard let remote = entry.remoteInfo else {
            error = loc.localized("coreDownload.noDownloadable")
            return
        }
        isDownloading = true
        error = nil
        Task {
            let romPath = pendingROM?.path.path
            await coreManager.downloadCore(remote, romPath: romPath)
            await MainActor.run {
                if coreManager.isInstalled(coreID: entry.id) {
                    isDownloading = false
                    Task { await launchWithCoreID(entry.id) }
                } else {
                    isDownloading = false
                    error = loc.localized("coreDownload.downloadFailed")
                }
            }
        }
    }

    @MainActor
    private func launchWithCoreID(_ cid: String) async {
        guard let rom = pendingROM else { onDismiss(); return }
        coreManager.pendingDownload = nil
        if let sysID = rom.systemID {
            SystemPreferences.shared.setPreferredCoreID(cid, for: sysID)
        }
        var updatedROM = rom
        updatedROM.selectedCoreID = cid
        updatedROM.useCustomCore = true
        library.updateROM(updatedROM)
        await GameLauncher.shared.launchGame(
            rom: updatedROM, coreID: cid, slotToLoad: pending.slotToLoad, library: library
        )
        onDismiss()
    }
}

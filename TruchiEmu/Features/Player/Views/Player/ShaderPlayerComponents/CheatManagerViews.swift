import SwiftUI
import Cocoa

struct CheatManagerViewWrapper: View {
    let rom: ROM
    weak var windowController: StandaloneGameWindowController?

    @ObservedObject private var cheatManager = CheatManagerService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.localized("cheat.cheatsForGame").replacingOccurrences(of: "{0}", with: rom.displayName))
                        .font(.headline)
                    Text(loc.localized("cheat.enabledCount")
                        .replacingOccurrences(of: "{0}", with: "\(cheatManager.enabledCount(for: rom))")
                        .replacingOccurrences(of: "{1}", with: "\(cheatManager.totalCount(for: rom))"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                Spacer()
                Button {
                    windowController?.dismissCheatManager()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .help(loc.localized("cheat.close"))
            }
            .padding()

            Divider()

                CheatBrowserList(
                    rom: rom,
                    showCategoryFilter: true,
                    showAddButton: true,
                    showDownloadButton: true,
                    showImportButton: true,
                    showApplyButton: true
                )
        }
        .frame(minWidth: 500, minHeight: 600)
    }
}

/// Gamepad-navigable cheat list presented as a popover from the in-game
/// toolbar (mirrors the slot/record popovers). A toggles, B closes.
struct CheatPickerView: View {
    let rom: ROM
    weak var windowController: StandaloneGameWindowController?

    @ObservedObject private var cheatManager = CheatManagerService.shared
    @ObservedObject private var cheatDownloadService = CheatDownloadService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var cheats: [Cheat] = []
    @State private var sheetFocusIndex: Int = 0
    @State private var isPresented: Bool = true

    private var orderedCheats: [Cheat] {
        cheats.sorted { $0.enabled && !$1.enabled }
    }

    private func loadCheats() {
        cheatManager.loadCheatsForROM(rom)
        cheats = cheatManager.cheats(for: rom)
    }

    private func toggleCheat(at index: Int) {
        guard orderedCheats.indices.contains(index) else { return }
        var updated = orderedCheats[index]
        updated.enabled.toggle()
        cheatManager.updateCheat(updated, for: rom)
        let enabled = cheatManager.cheats(for: rom).filter { $0.enabled }
        let cheatData = enabled.map { ["index": $0.index, "code": $0.code, "enabled": $0.enabled] as [String: Any] }
        if !HardcoreModeManager.shared.areCheatsBlocked {
            XPCBridgeAdapter.shared.applyCheats(cheatData)
        }
        loadCheats()
    }

    private func refreshSheetFocus() {
        if let ctx = GamepadNavContextStack.shared.topActive() as? GamepadSheetContext,
           ctx.itemCount == orderedCheats.count {
            sheetFocusIndex = ctx.focusIndex
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.localized("cheat.cheatsForGame").replacingOccurrences(of: "{0}", with: rom.displayName))
                        .font(.headline)
                    Text(loc.localized("cheat.enabledCount")
                        .replacingOccurrences(of: "{0}", with: "\(cheatManager.enabledCount(for: rom))")
                        .replacingOccurrences(of: "{1}", with: "\(cheatManager.totalCount(for: rom))"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                Spacer()
                Button {
                    windowController?.isCheatPickerShown = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                .help(loc.localized("cheat.close"))
            }
            .padding()

            Divider()

            if orderedCheats.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    Text(LocalizationManager.shared.localized("cheat.searching"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(orderedCheats.enumerated()), id: \.element.id) { index, cheat in
                                CheatListRowView(cheat: cheat, isOn: cheat.enabled) {
                                    toggleCheat(at: index)
                                }
                                .id(index)
                                .overlay(alignment: .center) {
                                    if sheetFocusIndex == index {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppColors.brandAccent, lineWidth: 2)
                                            .padding(-2)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding()
                    }
                    .onReceive(GamepadNavContextStack.shared.focusPublisher) { _ in
                        refreshSheetFocus()
                        if sheetFocusIndex >= 0, sheetFocusIndex < orderedCheats.count {
                            proxy.scrollTo(sheetFocusIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .gamepadSheetNav(
            isPresented: $isPresented,
            itemCount: orderedCheats.count,
            onSelect: { idx in toggleCheat(at: idx) },
            onDismiss: {
                windowController?.isCheatPickerShown = false
            }
        )
        .onChange(of: orderedCheats.count) { _, newCount in
            if let ctx = GamepadNavContextStack.shared.topActive() as? GamepadSheetContext {
                ctx.itemCount = newCount
            }
        }
        .onAppear {
            loadCheats()
            if cheatManager.totalCount(for: rom) == 0,
               let systemID = rom.systemID {
                Task {
                    _ = try? await cheatDownloadService.downloadCheatForROM(rom, systemID: systemID)
                }
            }
        }
    }
}

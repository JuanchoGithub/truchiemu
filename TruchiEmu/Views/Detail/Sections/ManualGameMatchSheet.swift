import SwiftUI

/// Lets the user select the game of a ROM by hand. The list holds the games
/// of the system of the ROM. The system DAT comes first. The LaunchBox list
/// comes second.
struct ManualGameMatchSheet: View {
    @EnvironmentObject var library: ROMLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    let rom: ROM
    let onComplete: (String) -> Void

    @State private var query: String = ""
    @State private var allCandidates: [GameMatchCandidate] = []
    @State private var results: [GameMatchCandidate] = []
    @State private var selected: GameMatchCandidate?
    @State private var isLoading: Bool = true
    @State private var isApplying: Bool = false
    @State private var loadFailed: Bool = false
    @State private var fetchBoxArt: Bool

    init(rom: ROM, onComplete: @escaping (String) -> Void) {
        self.rom = rom
        self.onComplete = onComplete
        // The box art of a game with art can be a custom image. The user must
        // ask for a new one.
        _fetchBoxArt = State(initialValue: !rom.hasBoxArt)
    }

    private var systemName: String {
        SystemDatabase.systemName(forInternalID: rom.systemID ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppColors.divider(colorScheme))
            searchBar
            Divider().overlay(AppColors.divider(colorScheme))
            content
            Divider().overlay(AppColors.divider(colorScheme))
            footer
        }
        .frame(width: 760, height: 620)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .task {
            await loadCandidates()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.localized("gameInfo.manualMatchTitle"))
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary(colorScheme))
                Text(loc.localized("gameInfo.manualMatchHelp"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(loc.localized("gameInfo.matchCurrent"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                    Text(verbatim: rom.metadata?.title ?? rom.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                        .lineLimit(1)
                    if !systemName.isEmpty {
                        Text(verbatim: "·")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                        Text(verbatim: systemName)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary(colorScheme))
            TextField(loc.localized("gameInfo.matchSearchPlaceholder"), text: $query)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary(colorScheme))
                .onSubmit { applyFilter() }
            if !query.isEmpty {
                Button {
                    query = ""
                    applyFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .onChange(of: query) { _, _ in
            applyFilter()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: AppSpacing.md) {
                ProgressView().controlSize(.small)
                Text(loc.localized("gameInfo.matchLoading"))
                    .font(.callout)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            emptyState(icon: "exclamationmark.triangle", message: loc.localized("gameInfo.matchLoadFailed"))
        } else if allCandidates.isEmpty {
            emptyState(icon: "list.bullet.rectangle", message: loc.localized("gameInfo.matchNoCandidates"))
        } else if results.isEmpty {
            emptyState(icon: "magnifyingglass", message: loc.localized("gameInfo.matchNoResults"))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { candidate in
                        candidateRow(candidate)
                        Divider().overlay(AppColors.divider(colorScheme)).padding(.leading, AppSpacing.xl)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(AppColors.textTertiary(colorScheme))
            Text(verbatim: message)
                .font(.callout)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func candidateRow(_ candidate: GameMatchCandidate) -> some View {
        let isSelected = selected?.id == candidate.id
        return Button {
            selected = candidate
        } label: {
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: candidate.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                        .lineLimit(1)
                    if !candidate.detailLine.isEmpty {
                        Text(verbatim: candidate.detailLine)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: AppSpacing.md)
                sourceTag(candidate.source)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.brandAccent)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
            .background(isSelected ? AppColors.accentBackground(colorScheme) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func sourceTag(_ source: GameMatchCandidate.Source) -> some View {
        Text(verbatim: loc.localized(source.localizedKey))
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundColor(AppColors.textSecondary(colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColors.cardBackgroundSubtle(colorScheme))
            )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: AppSpacing.md) {
            Toggle(isOn: $fetchBoxArt) {
                Text(loc.localized("gameInfo.matchFetchArt"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
            .toggleStyle(.checkbox)
            .disabled(selected == nil)

            Spacer(minLength: 0)

            if rom.metadata?.manualMatch == true {
                Button {
                    library.unlockManualMatch(for: library.rom(withID: rom.id) ?? rom)
                    onComplete(loc.localized("gameInfo.matchUnlocked"))
                    dismiss()
                } label: {
                    Text(loc.localized("gameInfo.matchUnlock"))
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundColor(AppColors.warning(colorScheme))
            }

            Button {
                dismiss()
            } label: {
                Text(loc.localized("library.cancel"))
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.textSecondary(colorScheme))

            Button {
                applyMatch()
            } label: {
                HStack(spacing: 6) {
                    if isApplying {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(loc.localized("gameInfo.matchApply"))
                }
                .font(.subheadline)
                .foregroundColor(AppColors.textOnAccent(colorScheme))
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.brandAccent)
                .cornerRadius(AppRadius.md)
            }
            .buttonStyle(.plain)
            .disabled(selected == nil || isApplying)
            .opacity(selected == nil ? 0.5 : 1)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.surface(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
    }

    // MARK: - Actions

    private func loadCandidates() async {
        guard let systemID = rom.systemID, SystemDatabase.system(forID: systemID) != nil else {
            isLoading = false
            loadFailed = true
            return
        }
        let candidates = await ManualGameMatchService.shared.candidates(for: systemID)
        allCandidates = candidates
        applyFilter()
        isLoading = false
    }

    private func applyFilter() {
        results = ManualGameMatchService.filter(allCandidates, query: query)
    }

    private func applyMatch() {
        guard let candidate = selected else { return }
        isApplying = true

        Task { @MainActor in
            let current = library.rom(withID: rom.id) ?? rom
            var updated = library.applyManualMatch(candidate, to: current)

            if fetchBoxArt {
                if let artURL = candidate.boxArtURL {
                    BoxArtService.shared.invalidateResolvedBoxArtCache(for: updated.id)
                    if await BoxArtService.shared.downloadAndCache(
                        artURL: artURL,
                        for: updated,
                        forceReplace: current.hasBoxArt
                    ) != nil {
                        updated.hasBoxArt = true
                        library.updateROM(updated)
                        BoxArtService.shared.signalBoxArtUpdated(for: updated.id)
                    }
                } else if await BoxArtService.shared.fetchBoxArt(
                    for: updated,
                    preferredTitle: candidate.name,
                    forceReplace: current.hasBoxArt
                ) != nil {
                    updated.hasBoxArt = true
                    library.updateROM(updated)
                    BoxArtService.shared.signalBoxArtUpdated(for: updated.id)
                }
            }

            isApplying = false
            onComplete(
                loc.localized("gameInfo.matchApplied")
                    .replacingOccurrences(of: "{name}", with: candidate.name)
            )
            dismiss()
        }
    }
}

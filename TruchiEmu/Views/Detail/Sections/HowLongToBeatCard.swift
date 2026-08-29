import SwiftUI

/// Shows HowLongToBeat completion-time estimates for a game.
///
/// Data is fetched on demand (lazy). Automatic matching by title + platform is best-effort
/// (HLTB's search API is bot-protected); the reliable path is manual paste of an HLTB
/// game link/ID, which scrapes the public game detail page.
struct HowLongToBeatCard: View {
    @EnvironmentObject var library: ROMLibrary
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var loc = LocalizationManager.shared
    var rom: ROM

    @State private var loading = false
    @State private var candidates: [HLTBMatch] = []
    @State private var pasteText = ""
    @State private var errorMessage: String?
    @State private var didAttemptAuto = false
    @State private var showWebSearch = false
    // True after an auto-search definitively returned no HLTB match for this
    // game (vs. a transient network/search failure). Drives the empty-state UI.
    @State private var notFound = false

    private var meta: ROMMetadata? { rom.metadata }
    private var hasCandidate: Bool { meta?.hltbGameID != nil }
    private var hasTimes: Bool {
        guard let m = meta else { return false }
        return m.hltbMainStoryHours != nil
            || m.hltbMainPlusExtrasHours != nil
            || m.hltbCompletionistHours != nil
            || m.hltbAllStylesHours != nil
    }
    // Decode HTML entities for display so titles from the detail page (which
    // HTML-encodes apostrophes etc.) render cleanly even if a game was stored
    // before the decoder landed in the parser.
    private var matchedTitleDisplay: String? {
        guard let raw = meta?.hltbMatchedTitle, !raw.isEmpty else { return nil }
        return raw.htmlDecoded
    }

    var body: some View {
        Group {
            if hasTimes {
                dataCard
            } else if hasCandidate {
                // An HLTB entry was previously chosen; just need to (re)fetch its times.
                pickedCard
                    .onAppear { fetchTimesIfNeeded() }
            } else if HowLongToBeatService.isEnabled {
                lookupCard
                    .onAppear { attemptAutoIfNeeded() }
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showWebSearch) {
            HLTBWebSearchSheet(
                initialQuery: rom.displayName,
                onPick: { match in Task { await applyCandidate(match) } },
                onAutoSearch: { sheetAutoSearch() }
            )
        }
    }

    // MARK: - Picked (gameID known, times not yet fetched)

    private var pickedCard: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.hltb.title"),
            icon: "hourglass"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(loc.localized("gameDetail.hltb.loading"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }

                if let matched = matchedTitleDisplay {
                    Text(matched)
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                }

                HStack {
                    if let id = meta?.hltbGameID {
                        Button {
                            if let url = URL(string: "https://howlongtobeat.com/game/\(id)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text(loc.localized("gameDetail.hltb.attribution"))
                                .font(.caption2)
                                .foregroundColor(AppColors.brandAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        showWebSearch = true
                    } label: {
                        Label(loc.localized("gameDetail.hltb.notThisGameButton"),
                              systemImage: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Resolved data

    private var dataCard: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.hltb.title"),
            icon: "hourglass"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.lg),
                        GridItem(.flexible(), spacing: AppSpacing.lg)
                    ],
                    alignment: .leading,
                    spacing: AppSpacing.md
                ) {
                    timeField(loc.localized("gameDetail.hltb.mainStory"), meta?.hltbMainStoryHours)
                    timeField(loc.localized("gameDetail.hltb.mainPlusExtras"), meta?.hltbMainPlusExtrasHours)
                    timeField(loc.localized("gameDetail.hltb.completionist"), meta?.hltbCompletionistHours)
                    timeField(loc.localized("gameDetail.hltb.allStyles"), meta?.hltbAllStylesHours)
                }

                if let matched = matchedTitleDisplay {
                    Text(matched)
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                }

                HStack(spacing: 12) {
                    if let id = meta?.hltbGameID {
                        Button {
                            if let url = URL(string: "https://howlongtobeat.com/game/\(id)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text(loc.localized("gameDetail.hltb.attribution"))
                                .font(.caption2)
                                .foregroundColor(AppColors.brandAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        showWebSearch = true
                    } label: {
                        Label(loc.localized("gameDetail.hltb.notThisGameButton"),
                              systemImage: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func timeField(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textTertiary(colorScheme))
            Text(formatHours(value))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary(colorScheme))
        }
    }

    private func formatHours(_ value: Double?) -> String {
        guard let v = value else { return loc.localized("gameDetail.hltb.noTime") }
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(v))h"
        }
        return String(format: "%.1fh", v)
    }

    // MARK: - Lookup (no data yet)

    private var lookupCard: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.hltb.title"),
            icon: "hourglass"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(loc.localized("gameDetail.hltb.loading"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                } else if !candidates.isEmpty {
                    Text(loc.localized("gameDetail.hltb.chooseMatch"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    ForEach(candidates) { m in
                        Button {
                            Task { await applyCandidate(m) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).font(.subheadline).fontWeight(.medium)
                                        .foregroundColor(AppColors.textPrimary(colorScheme))
                                    if let p = m.platform, !p.isEmpty {
                                        Text(p).font(.caption2)
                                            .foregroundColor(AppColors.textMuted(colorScheme))
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(AppColors.brandAccent)
                            }
                            .padding(8)
                            .background(AppColors.cardBackground(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                        }
                        .buttonStyle(.plain)
                    }
                    manualPasteRow
                } else if notFound {
                    // HLTB genuinely has no match for this game title. Point the
                    // user at the web search sheet as the way to find the right
                    // entry manually instead of leaving them on a generic
                    // "unavailable" message with only a refresh button.
                    Text(loc.localized("gameDetail.hltb.notFoundHint"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    HStack {
                        Button {
                            showWebSearch = true
                        } label: {
                            Label(loc.localized("gameDetail.hltb.findGameManually"),
                                  systemImage: "magnifyingglass")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    manualPasteRow
                } else {
                    Text(loc.localized("gameDetail.hltb.searchUnavailable"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    manualPasteRow
                    HStack {
                        Spacer()
                        Button {
                            retryAuto()
                        } label: {
                            Label(loc.localized("gameDetail.hltb.refresh"), systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(AppColors.brandAccent)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var manualPasteRow: some View {
        HStack(spacing: 8) {
            TextField(loc.localized("gameDetail.hltb.pastePrompt"), text: $pasteText)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await applyManual() }
            } label: {
                Text(loc.localized("gameDetail.hltb.match"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    private func attemptAutoIfNeeded(force: Bool = false) {
        // The force flag bypasses the once-per-view auto-search guard so the
        // web search sheet's "Auto search" button and the manual retry can
        // always trigger a fresh network search.
        guard !hasCandidate, !(didAttemptAuto && !force) else { return }
        didAttemptAuto = true
        loading = true
        errorMessage = nil
        notFound = false
        Task {
            let res = await HowLongToBeatService.shared.searchCandidates(for: rom, library: library, force: force)
            await MainActor.run {
                loading = false
                switch res {
                case .success(let matches):
                    if matches.count == 1, let only = matches.first {
                        Task { await applyCandidate(only) }
                    } else if !matches.isEmpty {
                        candidates = matches
                    } else {
                        notFound = true
                        errorMessage = loc.localized("gameDetail.hltb.notFound")
                    }
                case .failure(let e):
                    errorMessage = e.localizedDescription
                    if case .noMatch = e { notFound = true }
                }
            }
        }
    }

    private func retryAuto() {
        // Manual override: force a fresh search even if the 15-day negative cache is active.
        didAttemptAuto = false
        errorMessage = nil
        notFound = false
        attemptAutoIfNeeded(force: true)
    }

    /// Fetch (or re-fetch) the times for the already-persisted HLTB candidate
    /// using the service's 30-day freshness policy. Used on re-open when a
    /// candidate was saved without its times (e.g. previous fetch was interrupted).
    private func fetchTimesIfNeeded(force: Bool = false) {
        guard let id = meta?.hltbGameID, !loading, !hasTimes else { return }
        Task {
            await MainActor.run { loading = true }
            let res = await HowLongToBeatService.shared.loadTimes(gameID: id, rom: rom, library: library, force: force)
            await MainActor.run {
                loading = false
                switch res {
                case .success:
                    candidates = []
                    errorMessage = nil
                case .failure(let e):
                    errorMessage = e.localizedDescription
                }
            }
        }
    }

    /// Manual override: bypass the 30-day freshness and refetch times now.
    private func retryTimes() {
        errorMessage = nil
        fetchTimesIfNeeded(force: true)
    }

    private func applyCandidate(_ m: HLTBMatch) async {
        // Persist the candidate (id + title) right away so this pick survives
        // an app relaunch or a mid-fetch close — the card will then go straight
        // to fetching times on next open instead of re-searching HLTB.
        await MainActor.run {
            HowLongToBeatService.shared.persistCandidate(m, to: rom, library: library)
            loading = true
            notFound = false
        }
        let res = await HowLongToBeatService.shared.loadTimes(gameID: m.id, rom: rom, library: library)
        await MainActor.run {
            loading = false
            switch res {
            case .success:
                candidates = []
                errorMessage = nil
            case .failure(let e):
                errorMessage = e.localizedDescription
            }
        }
    }

    private func applyManual() async {
        guard let id = HowLongToBeatService.shared.parseGameID(from: pasteText) else {
            errorMessage = loc.localized("gameDetail.hltb.notFound")
            return
        }
        await applyCandidate(HLTBMatch(
            id: id, title: "", platform: nil,
            mainStory: nil, mainPlusExtras: nil, completionist: nil, allStyles: nil
        ))
    }

    /// Triggered from the web search sheet's "Auto search" button. Wipes the
    /// current HLTB candidate (and the 15-day not-found throttle) and runs
    /// **the same** `HowLongToBeatService.searchCandidates` call — with the
    /// same fuzzy name cleaning (`searchQueryVariants`) and 15-day negative
    /// cache — that the lookupCard's `onAppear` runs on first open. The
    /// result is handled identically: a single match is auto-applied via
    /// `applyCandidate`, multiple matches populate the picker, and zero
    /// matches flip the card into the "no match on HowLongToBeat" state
    /// with the prominent "Search HLTB" button.
    private func sheetAutoSearch() {
        clearHLTBCandidate()
        candidates = []
        pasteText = ""
        errorMessage = nil
        notFound = false
        loading = true
        Task {
            let res = await HowLongToBeatService.shared.searchCandidates(
                for: rom, library: library, force: false
            )
            await MainActor.run {
                loading = false
                switch res {
                case .success(let matches):
                    if matches.count == 1, let only = matches.first {
                        Task { await applyCandidate(only) }
                    } else if !matches.isEmpty {
                        candidates = matches
                    } else {
                        notFound = true
                        errorMessage = loc.localized("gameDetail.hltb.notFound")
                    }
                case .failure(let e):
                    errorMessage = e.localizedDescription
                    if case .noMatch = e { notFound = true }
                }
            }
        }
    }

    /// Wipes the HLTB candidate + times + not-found timestamp from the ROM
    /// metadata, so the card transitions back to the lookup state and the
    /// next auto-search isn't blocked by the 15-day negative cache.
    private func clearHLTBCandidate() {
        var updated = rom
        var m = updated.metadata ?? ROMMetadata()
        m.hltbGameID = nil
        m.hltbMatchedTitle = nil
        m.hltbMainStoryHours = nil
        m.hltbMainPlusExtrasHours = nil
        m.hltbCompletionistHours = nil
        m.hltbAllStylesHours = nil
        m.hltbLastNotFoundAt = nil
        updated.metadata = m
        library.updateROM(updated)
    }
}

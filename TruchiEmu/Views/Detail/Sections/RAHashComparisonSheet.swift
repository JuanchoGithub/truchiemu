import SwiftUI
import AppKit

struct RAHashComparisonContent: View {
    let gameTitle: String
    let systemName: String
    let hashes: [String]
    let currentHash: String
    let matchedHash: String?
    let raGameId: Int?
    let error: String?
    let isLoading: Bool
    let nameMatches: [NameMatchItem]
    let showDownloadOption: Bool
    let onDownload: (() -> Void)?

    struct NameMatchItem: Identifiable {
        let id: Int
        let title: String
        let hashes: [String]
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var raCacheCoordinator = RAGameCacheCoordinator.shared
    @State private var showCopied = false

    private var gameFoundByName: Bool { !nameMatches.isEmpty }
    private var isDownloading: Bool { raCacheCoordinator.isActive }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(error)
                } else if isDownloading {
                    downloadingView
                } else if showDownloadOption {
                    needsDownloadView
                } else if gameFoundByName {
                    hashMismatchView
                } else {
                    gameNotFoundView
                }
            }
            .navigationTitle(loc.localized("raHash.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.localized("raHash.done")) { dismiss() }
                }
            }
        }
        .frame(width: 600, height: isDownloading || showDownloadOption ? 400 : 520)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(loc.localized("raHash.searching"))
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(AppColors.warning(colorScheme))
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .padding()
    }

    // MARK: - Downloading (hash download in progress)

    private var downloadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(raCacheCoordinator.statusLine)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if raCacheCoordinator.totalSteps > 0 {
                Text("\(raCacheCoordinator.currentStep)/\(raCacheCoordinator.totalSteps)")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary(colorScheme))
                    .monospacedDigit()
            }
            if raCacheCoordinator.progress > 0 {
                ProgressView(value: raCacheCoordinator.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
            }
            Text(loc.localized("raHash.downloadingKeepOpen"))
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary(colorScheme))
        }
        .padding()
    }

    // MARK: - Needs Download (hash data missing, prompt to download)

    private var needsDownloadView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(AppColors.brandAccent)

            Text(loc.localized("raHash.missingHashDataTitle"))
                .font(.headline)

            Text(loc.localized("raHash.missingHashDataExplanation"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onDownload?()
            } label: {
                Label(loc.localized("raHash.downloadGameLists"), systemImage: "arrow.down.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
    }

    // MARK: - Game Not Found (no name matches at all)

    private var gameNotFoundView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(AppColors.textMuted(colorScheme))
                        Text(loc.localized("raHash.gameNotFoundTitle"))
                            .font(.headline)
                    }
                    Text(loc.localized("raHash.gameNotFoundExplanation")
                        .replacingOccurrences(of: "{title}", with: gameTitle)
                        .replacingOccurrences(of: "{system}", with: systemName))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackgroundSubtle(colorScheme))
                .cornerRadius(8)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.localized("raHash.yourRomHash"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(currentHash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppColors.warning(colorScheme))
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.localized("raHash.whatYouCanDo"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "1.circle.fill")
                                .font(.caption)
                                .foregroundColor(AppColors.brandAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.localized("raHash.requestNewGames"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(loc.localized("raHash.requestNewGamesExplanation"))
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    if let url = URL(string: "https://retroachievements.org/viewtopic.php?t=15027") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Label(loc.localized("raHash.requestNewGames"), systemImage: "arrow.up.forward.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.top, 2)
                            }
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "2.circle.fill")
                                .font(.caption)
                                .foregroundColor(AppColors.brandAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.localized("raHash.checkDifferentRom"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(loc.localized("raHash.checkDifferentRomExplanation"))
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary(colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Hash Mismatch (game found by name, but hash doesn't match)

    private var hashMismatchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(AppColors.warning(colorScheme))
                        Text(loc.localized("raHash.hashMismatchTitle"))
                            .font(.headline)
                    }
                    Text(loc.localized("raHash.hashMismatchExplanation")
                        .replacingOccurrences(of: "{title}", with: nameMatches.first?.title ?? gameTitle))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.warning(colorScheme).opacity(0.08))
                .cornerRadius(8)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.localized("raHash.yourRomHash"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(currentHash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppColors.warning(colorScheme))
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(loc.localized("raHash.possibleMatches")
                        .replacingOccurrences(of: "{0}", with: "\(nameMatches.count)"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(loc.localized("raHash.romFilenameMatched"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(nameMatches) { match in
                                nameMatchCard(match)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.localized("raHash.howToFindMatchingRom"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(loc.localized("raHash.howToFindMatchingRomExplanation"))
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Button {
                    let text = generateMismatchCopyText()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                } label: {
                    Label(showCopied ? loc.localized("raHash.copiedToClipboard") : loc.localized("raHash.copyAllInfo"),
                          systemImage: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }

    private func nameMatchCard(_ match: NameMatchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    if let url = URL(string: "https://retroachievements.org/game/\(match.id)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(loc.localized("raHash.viewOnRetroAchievements"), systemImage: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(loc.localized("raHash.acceptedHashes"))
                .font(.caption)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))

            ForEach(match.hashes, id: \.self) { hash in
                HStack(spacing: 6) {
                    Text(hash)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    if hash.lowercased() == currentHash.lowercased() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.success(colorScheme))
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(8)
    }

    private func generateMismatchCopyText() -> String {
        var text = "=== RETROACHIEVEMENTS ROM MISMATCH ===\n\n"
        text += "Your ROM filename: \(gameTitle)\n"
        text += "Your ROM hash (MD5): \(currentHash)\n\n"

        if !nameMatches.isEmpty {
            text += "=== MATCHING GAMES IN RA (\(nameMatches.count)) ===\n\n"
            for (index, match) in nameMatches.enumerated() {
                text += "--- Match #\(index + 1): \(match.title) ---\n"
                text += "RA Game ID: \(match.id)\n"
                text += "RA Game Page: https://retroachievements.org/game/\(match.id)\n"
                text += "Accepted hashes:\n"
                for hash in match.hashes {
                    text += "  \(hash)\n"
                }
                text += "\n"
            }
        }

        text += "=== WHAT THIS MEANS ===\n"
        text += "Your ROM's hash does not match any RA-supported version.\n"
        text += "You likely have a different revision, region, or dump of the game.\n"
        text += "To earn achievements, find a ROM whose hash matches one listed above.\n"
        text += "No-Intro and Redump ROM sets contain verified dumps that match these hashes.\n"
        return text
    }
}

#Preview("Hash Mismatch") {
    RAHashComparisonContent(
        gameTitle: "Super Mario World (USA)",
        systemName: "SNES",
        hashes: [],
        currentHash: "notmatchinghash",
        matchedHash: nil,
        raGameId: nil,
        error: nil,
        isLoading: false,
        nameMatches: [
            RAHashComparisonContent.NameMatchItem(id: 1234, title: "Super Mario World (USA)", hashes: ["abc123def456", "def456abc789"]),
            RAHashComparisonContent.NameMatchItem(id: 1235, title: "Super Mario World (Europe)", hashes: ["789xyz123", "aaa111bbb222"])
        ],
        showDownloadOption: false,
        onDownload: nil
    )
}

#Preview("Game Not Found") {
    RAHashComparisonContent(
        gameTitle: "Some Obscure Game",
        systemName: "NES",
        hashes: [],
        currentHash: "abcdef123456",
        matchedHash: nil,
        raGameId: nil,
        error: nil,
        isLoading: false,
        nameMatches: [],
        showDownloadOption: false,
        onDownload: nil
    )
}

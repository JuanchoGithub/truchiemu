import SwiftUI
import AppKit

struct RAHashComparisonContent: View {
    let gameTitle: String
    let hashes: [String]
    let currentHash: String
    let matchedHash: String?
    let raGameId: Int?
    let error: String?
    let isLoading: Bool
    let nameMatches: [NameMatchItem]

    struct NameMatchItem: Identifiable {
        let id: Int
        let title: String
        let hashes: [String]
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showCopied = false
    @State private var selectedMatchId: Int?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(error)
                } else if hashes.isEmpty && nameMatches.isEmpty {
                    emptyView
                } else if matchedHash != nil {
                    hashMatchView
                } else {
                    noMatchView
                }
            }
            .navigationTitle("RetroAchievements")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching RetroAchievements...")
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No game found in RetroAchievements")
                .font(.headline)
            Text("This game may not be supported by RetroAchievements.")
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var hashMatchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(gameTitle)
                        .font(.headline)
                    if let raGameId = raGameId {
                        Button {
                            if let url = URL(string: "https://retroachievements.org/game/\(raGameId)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("View on RetroAchievements", systemImage: "arrow.up.forward.square")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Hash Match Found!")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text("Your ROM matches the RetroAchievements version. Achievements can be earned with this ROM.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your ROM Hash (MD5)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(currentHash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
    }

    private var noMatchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("No Matching ROM Found")
                            .font(.headline)
                    }
                    Text("Your ROM's hash does not match any version in the RetroAchievements database. To earn achievements, you need a different ROM file that matches one of the supported hashes below.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Your ROM Hash (MD5)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(currentHash)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                        .textSelection(.enabled)
                }

                Divider()

                if !nameMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Possible Matches (\(nameMatches.count))")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Your ROM filename matched these games in the RA database. Your hash does not match any of them, so you need a different ROM file.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(nameMatches) { match in
                                    nameMatchCard(match)
                                }
                            }
                        }
                        .frame(maxHeight: 250)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RetroAchievements Supported Hashes")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(hashes, id: \.self) { hash in
                                    HStack {
                                        Text(hash)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                        if hash.lowercased() == currentHash.lowercased() {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }

                Divider()

                Button {
                    let text = generateMismatchCopyText()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopied = false
                    }
                } label: {
                    Label(showCopied ? "Copied to Clipboard!" : "Copy All Info for Google Search", systemImage: showCopied ? "checkmark.circle.fill" : "doc.on.doc")
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
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            Text("Supported Hashes:")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(match.hashes, id: \.self) { hash in
                HStack {
                    Text(hash)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    if hash.lowercased() == currentHash.lowercased() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func generateMismatchCopyText() -> String {
        var text = "=== RETROACHIEVEMENTS ROM MISMATCH ===\n\n"
        text += "Your ROM filename: \(gameTitle)\n"
        text += "Your ROM hash (MD5): \(currentHash)\n\n"

        if !nameMatches.isEmpty {
            text += "=== POSSIBLE MATCHES FOUND (\(nameMatches.count)) ===\n\n"
            for (index, match) in nameMatches.enumerated() {
                text += "--- Match #\(index + 1): \(match.title) ---\n"
                text += "RA Game ID: \(match.id)\n"
                text += "Supported hashes:\n"
                for hash in match.hashes {
                    text += "  \(hash)\n"
                }
                text += "\n"
            }
        }

        text += "=== ACTION REQUIRED ===\n"
        text += "Your ROM's hash does not match any RA-supported version.\n"
        text += "To earn achievements, you need to find a different ROM file that matches one of the hashes above.\n"
        text += "Try searching Google for one of the hashes with the game title.\n"
        return text
    }
}

#Preview {
    RAHashComparisonContent(
        gameTitle: "Super Mario World (USA)",
        hashes: ["abc123def456", "def456abc789", "789xyz123"],
        currentHash: "notmatchinghash",
        matchedHash: nil,
        raGameId: 1234,
        error: nil,
        isLoading: false,
        nameMatches: [
            RAHashComparisonContent.NameMatchItem(id: 1234, title: "Super Mario World (USA)", hashes: ["abc123def456", "def456abc789"]),
            RAHashComparisonContent.NameMatchItem(id: 1235, title: "Super Mario World (Europe)", hashes: ["789xyz123", "aaa111bbb222"]),
            RAHashComparisonContent.NameMatchItem(id: 1236, title: "Super Mario World (Japan)", hashes: ["ccc333ddd444"])
        ]
    )
}
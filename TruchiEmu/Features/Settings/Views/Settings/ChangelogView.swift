import SwiftUI

struct ChangelogView: View {
    @ObservedObject private var updateService = AppUpdateService.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isLoading = false
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(loc.localized("update.changelog"))
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    SettingsActionButton(loc.localized("update.refresh")) {
                        Task {
                            isLoading = true
                            _ = await updateService.checkForUpdates()
                            isLoading = false
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(AppSpacing.md)

            Divider()

            if updateService.allReleases.isEmpty && !isLoading {
                AppEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: loc.localized("update.noReleases"),
                    description: loc.localized("update.noReleasesDescription")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        ForEach(updateService.allReleases) { release in
                            ChangelogRow(
                                release: release,
                                isExpanded: expandedIDs.contains(release.id),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedIDs.contains(release.id) {
                                            expandedIDs.remove(release.id)
                                        } else {
                                            expandedIDs.insert(release.id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(AppSpacing.md)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .task { await loadReleasesIfNeeded() }
    }

    private func loadReleasesIfNeeded() async {
        guard updateService.allReleases.isEmpty else { return }
        isLoading = true
        _ = await updateService.checkForUpdates()
        isLoading = false
    }
}

private struct ChangelogRow: View {
    let release: AppRelease
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary(colorScheme))
                    .frame(width: 16)

                if release.isCurrent {
                    Text("v\(release.version)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    Text(loc.localized("update.currentVersion"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                } else {
                    Text("v\(release.version)")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                if let date = release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary(colorScheme))
                }
            }
            .padding(AppSpacing.md)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    MarkdownBodyView(markdown: release.body)
                        .padding(AppSpacing.md)
                }
            }
        }
        .background(AppColors.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

struct MarkdownBodyView: View {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if markdown.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let text, let level):
                        Text(renderMarkdown(text))
                            .font(headingFont(level: level))
                            .foregroundStyle(AppColors.textPrimary(colorScheme))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                            Text("•")
                            Text(renderMarkdown(text))
                                .textSelection(.enabled)
                        }
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case .text(let text):
                        Text(renderMarkdown(text))
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let alt, let url):
                        MarkdownImageView(alt: alt, url: url)
                    }
                }
            }
        }
    }

    private var blocks: [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var textBuffer: [String] = []

        func flushText() {
            let text = textBuffer.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(text))
            }
            textBuffer.removeAll()
        }

        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let image = parseImageLine(line) {
                flushText()
                result.append(.image(alt: image.alt, url: image.url))
            } else if trimmed.isEmpty {
                flushText()
            } else if let heading = parseHeading(trimmed) {
                flushText()
                result.append(heading)
            } else if let bullet = parseBullet(trimmed) {
                flushText()
                result.append(.bullet(bullet))
            } else {
                textBuffer.append(line)
            }
        }
        flushText()
        return result
    }

    private func parseHeading(_ line: String) -> MarkdownBlock? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        let text = line.dropFirst(markerCount).trimmingCharacters(in: .whitespaces)
        guard line.dropFirst(markerCount).hasPrefix(" "), !text.isEmpty else { return nil }
        return .heading(text, level: markerCount)
    }

    private func parseBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline
        default: return .subheadline.bold()
        }
    }

    private func parseImageLine(_ line: String) -> (alt: String, url: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")"),
              let closeBracket = trimmed.firstIndex(of: "]") else { return nil }
        let afterBracket = trimmed.index(after: closeBracket)
        guard afterBracket < trimmed.endIndex, trimmed[afterBracket] == "(" else { return nil }

        let alt = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<closeBracket])
        let urlStart = trimmed.index(after: afterBracket)
        let urlEnd = trimmed.index(before: trimmed.endIndex)
        guard urlStart < urlEnd else { return nil }

        var url = String(trimmed[urlStart..<urlEnd])
        if let space = url.firstIndex(of: " ") {
            url = String(url[..<space])
        }
        return (alt, url)
    }

    private func renderMarkdown(_ source: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(source)
    }
}

private enum MarkdownBlock {
    case heading(String, level: Int)
    case bullet(String)
    case text(String)
    case image(alt: String, url: String)
}

private struct MarkdownImageView: View {
    let alt: String
    let url: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let url = URL(string: url) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                case .failure:
                    placeholder(icon: "photo.badge.exclamationmark")
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                @unknown default:
                    placeholder(icon: "photo")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func placeholder(icon: String) -> some View {
        Label(alt.isEmpty ? "Image" : alt, systemImage: icon)
            .font(.caption)
            .foregroundStyle(AppColors.textTertiary(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.lg)
    }
}

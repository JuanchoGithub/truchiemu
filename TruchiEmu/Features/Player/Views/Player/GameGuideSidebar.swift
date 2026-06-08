import SwiftUI

struct GameGuideSidebar: View {
    @ObservedObject var viewModel: GameGuideViewModel
    @ObservedObject var windowController: StandaloneGameWindowController
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if let question = viewModel.currentQuestion {
                questionView(question)
            } else if let text = viewModel.currentWalkthroughText {
                walkthroughView(text)
            } else {
                topicListView
            }
        }
        .frame(width: 320)
        .background(AppColors.sidebarBackground(colorScheme, tinted: themeManager.tintedSurfacesEnabled))
        .opacity(isHovered ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if viewModel.canGoBack {
                Button(action: { viewModel.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.brandAccent)
                        Text(headerTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.guideSource == .uhs {
                Text(loc.localized("guide.hints"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.brandAccent)
            } else {
                Text(loc.localized("guide.walkthrough"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.brandAccent)
            }

        Button(action: { windowController.toggleGuideSidebar() }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .overlay(alignment: .bottom) {
        if let progress = viewModel.prefetchProgress {
            Text(verbatim: progress)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 2)
        }
    }
    }

    private var headerTitle: String {
        switch viewModel.currentLevel {
        case .root:
            return loc.localized("guide.chapters")
        case .topic:
            return loc.localized("guide.chapters")
        case .question(let nodeID):
            if let q = viewModel.currentQuestion, q.nodeID == nodeID {
                return q.title
            }
            return loc.localized("guide.hints")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text(loc.localized("guide.loading"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if viewModel.guideSource == .uhs {
                Button(loc.localized("guide.tryGameFAQs")) {
                    viewModel.tryGameFAQsFallback()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.brandAccent)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topicListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.guideSource == .gamefaqs {
                    ForEach(viewModel.gamefaqsFAQs) { faq in
                        faqRow(faq)
                    }
                } else {
                    ForEach(viewModel.currentTopics) { node in
                        topicRow(node)
                    }
                }
            }
        }
    }

    private func topicRow(_ node: GuideNode) -> some View {
        Button(action: { viewModel.navigateToNode(node) }) {
            HStack(spacing: 8) {
                if case .topic = node {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.brandAccent.opacity(0.7))
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.orange.opacity(0.7))
                }
                Text(node.title)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func faqRow(_ faq: GameFAQsFAQEntry) -> some View {
        Button(action: { viewModel.loadGameFAQsFAQText(faq) }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.brandAccent.opacity(0.7))
                Text(faq.title)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func questionView(_ question: GuideQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.revealedHints(for: question)) { hint in
                    hintView(hint)
                }

                if viewModel.hasMoreHints(for: question) {
                    HStack(spacing: 8) {
                        Button(action: { viewModel.revealNextHint() }) {
                            Text(loc.localized("guide.showNextHint"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.brandAccent)
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.revealAllHints() }) {
                            Text(loc.localized("guide.revealAll"))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                } else if !question.hints.isEmpty {
                    Text(loc.localized("guide.noMoreHints"))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func hintView(_ hint: Hint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: hint.numberText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppColors.brandAccent.opacity(0.6))
            Text(hint.text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
        )
        .padding(.horizontal, 8)
    }

    private func walkthroughView(_ text: String) -> some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .textSelection(.enabled)
                .padding(12)
        }
    }
}

import SwiftUI

// Save the current search as a smart category. Two visual styles:
// - `.sidebar`: a floating card. Click the card to preview the rule; the
//   large plus button saves directly.
// - `.chip`: compact capsule for the "Filtering:" status row.
struct SaveSearchButton: View {
    enum Style {
        case sidebar
        case chip
    }

    let query: String
    var style: Style = .sidebar
    let action: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false
    @State private var isHovered = false
    @State private var isPlusHovered = false
    @State private var showPreview = false

    private var title: String { loc.localized("search.save") }

    var body: some View {
        Group {
            switch style {
            case .sidebar:
                sidebar
            case .chip:
                chip
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -4)
        .onAppear {
            withAnimation(AppMotion.stateChange) { appeared = true }
        }
    }

    private var sidebar: some View {
        HStack(spacing: 8) {
            Button {
                showPreview = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.brandAccent)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary(colorScheme))
                            .lineLimit(1)

                        MarqueeText(
                            text: query,
                            font: .system(size: 11, weight: .medium),
                            speed: 24,
                            height: 13
                        )
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(loc.localized("search.previewTitle"))
            .popover(isPresented: $showPreview, arrowEdge: .bottom) {
                preview
            }

            Button {
                showPreview = false
                action()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        AppColors.textOnAccent(
                            for: AppColors.selectedFill(for: AppColors.brandAccent),
                            colorScheme: colorScheme
                        )
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(
                            AppColors.brandAccent.opacity(isPlusHovered ? 1 : 0.9)
                        )
                    )
                    .scaleEffect(isPlusHovered ? 1.06 : 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isPlusHovered = $0 }
            .accessibilityLabel(loc.localized("search.addCategory"))
            .help(loc.localized("search.addCategory"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(isHovered ? AppColors.accentBackground(colorScheme) : AppColors.cardBackgroundSubtle(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.brandAccent.opacity(isHovered ? 0.35 : 0.2), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(AppMotion.micro, value: isPlusHovered)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AppColors.brandAccent)
                Text(loc.localized("search.previewTitle"))
                    .font(.headline)
            }

            Text(verbatim: query)
                .font(.system(size: 12))
                .lineLimit(3)
                .truncationMode(.tail)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.cardBackgroundSubtle(colorScheme))
                )

            Text(loc.localized("search.previewHint"))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(loc.localized("search.addCategory")) {
                    showPreview = false
                    action()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var chip: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(verbatim: title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(
                AppColors.textOnAccent(
                    for: AppColors.selectedFill(for: AppColors.brandAccent),
                    colorScheme: colorScheme
                )
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isHovered
                        ? AppColors.brandAccent.opacity(0.85)
                        : AppColors.selectedFill(for: AppColors.brandAccent)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
    }
}

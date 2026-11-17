import SwiftUI
import AppKit

// MARK: - Section header for grouped library views

/// SwiftUI content for a per-system section header. Hosted by the grid,
/// holo grid (NSCollectionViewItem) and the list (NSTableCellView).
/// Clicking anywhere on the row collapses/expands the section; a collapsed
/// section renders as this single header line.
struct LibrarySectionHeaderView: View {
    let title: String
    let year: Int?
    let count: Int
    let systemID: String?
    let isCollapsed: Bool
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                iconPlate

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary(colorScheme))
                        .lineLimit(1)

                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary(colorScheme))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                countBlock

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isHovered ? AppColors.brandAccent : AppColors.textTertiary(colorScheme))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14)
                    .animation(reduceMotion ? nil : AppMotion.micro, value: isCollapsed)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.cardBackground(colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppColors.brandAccent.opacity(isHovered ? 0.06 : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isHovered ? AppColors.brandAccent.opacity(0.28) : AppColors.cardBorder(colorScheme),
                                lineWidth: 1
                            )
                    }
            )
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: countLabel))
    }

    /// Gray descriptor under the title: manufacturer and/or launch year, the
    /// same role the subtitle plays in a numbered list row.
    private var subtitle: String? {
        var parts: [String] = []
        if let systemID,
           let system = SystemDatabase.displaySystem(forInternalID: systemID) {
            let maker = system.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !maker.isEmpty, maker != "Unknown", maker != "Various" {
                parts.append(maker)
            }
        }
        if let year {
            parts.append(String(year))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var iconPlate: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.16 : 0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AppColors.brandAccent.opacity(0.18), lineWidth: 1)
            }
            .overlay {
                iconView
                    .frame(width: 20, height: 20)
            }
            .frame(width: 30, height: 30)
    }

    private var countBlock: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: count.formatted())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary(colorScheme))
            Text(verbatim: unitLabel.uppercased())
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(AppColors.textTertiary(colorScheme))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppColors.brandAccent.opacity(colorScheme == .dark ? 0.14 : 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppColors.brandAccent.opacity(0.16), lineWidth: 1)
        )
        .fixedSize()
    }

    @ViewBuilder
    private var iconView: some View {
        if let systemID,
           let system = SystemDatabase.displaySystem(forInternalID: systemID),
           let image = system.emuImage(size: 132) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gamecontroller")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.brandAccent)
        }
    }

    private var unitLabel: String {
        LocalizationManager.shared.localized(count == 1 ? "shell.unit.games.one" : "shell.unit.games")
    }

    private var countLabel: String {
        String(format: LocalizationManager.shared.localized("library.sectionGamesCount"), count)
    }
}

/// NSCollectionViewItem hosting a section header. Registered and recycled by
/// both the boxart grid and the holo grid.
final class LibrarySectionHeaderItem: NSCollectionViewItem {
    static let itemIdentifier = NSUserInterfaceItemIdentifier("LibrarySectionHeaderItem")

    private let hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.0, *) {
            // Same measure-feedback-loop guard as the game item views.
            hostingView.sizingOptions = []
        }
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func configure(title: String, year: Int?, count: Int, systemID: String?, isCollapsed: Bool, onToggle: @escaping () -> Void) {
        hostingView.rootView = AnyView(
            LibrarySectionHeaderView(
                title: title,
                year: year,
                count: count,
                systemID: systemID,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
        )
    }
}

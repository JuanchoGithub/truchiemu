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

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(width: 12)

                iconView
                    .frame(width: 28, height: 28)

                Text(verbatim: title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(AppColors.textPrimary(colorScheme))

                if let year {
                    Text(verbatim: String(year))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }

                Spacer(minLength: 12)

                Text(verbatim: countLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(AppColors.cardBackgroundSubtle(colorScheme), in: Capsule())
                    .overlay(Capsule().strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.brandAccent)
        }
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

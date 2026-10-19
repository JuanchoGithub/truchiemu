import SwiftUI
import AppKit

// MARK: - Section header for grouped library views

/// SwiftUI content for a per-system section header. Hosted by the grid,
/// holo grid (NSCollectionViewItem) and the list (NSTableCellView).
struct LibrarySectionHeaderView: View {
    let title: String
    let year: Int?
    let count: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.brandAccent)
                .frame(width: 3, height: 14)
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary(colorScheme))
            if let year {
                Text(verbatim: String(year))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            Spacer(minLength: 12)
            Text(verbatim: countLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    func configure(title: String, year: Int?, count: Int) {
        hostingView.rootView = AnyView(LibrarySectionHeaderView(title: title, year: year, count: count))
    }
}

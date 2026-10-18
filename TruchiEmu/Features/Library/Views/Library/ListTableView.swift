import SwiftUI
import AppKit

// MARK: - NSTableView-backed row mode
//
// macOS List eagerly rebuilds EVERY row value on each parent re-evaluation
// (see the GameListRowView header); even with tiny equatable row values that
// walk cost ~200ms per system switch at 2100+ ROMs (Release) vs ~100ms for
// the NSCollectionView-backed grid/holo views. This table mirrors the
// GridCollectionView architecture: only visible rows are configured and
// measured, so switching is O(visible), not O(all rows).
//
// Row content stays GameListRowView hosted in NSHostingView — gestures,
// context menu, hover, double-tap and drag all live inside the row (same as
// GameCardView in the grid), so the sidebar drag flow (GameDragState +
// plain-text UUID payload) is unchanged.

// MARK: - Row cell

final class ListTableRowView: NSTableCellView {
    private let hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    private var isConfigured = false

    private var rom: ROM?
    private var indexCached: Int = 0
    private var isSelectedCached = false
    private var isEvenRowCached = false
    private var zoomLevelCached: Double = 0.5
    private var showSystemLabelCached = false
    private var raEnabledCached = false
    private var boxArtVersionCached = UUID()
    private var selectedIDsCached: Set<UUID> = []
    private var lastSelectedIndexCached: Int?
    private var actionsCached: GameListRowView.Actions?
    private var libraryCached: ROMLibrary?
    private var categoryManagerCached: CategoryManager?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        // Width comes from the table column; height stays free so fittingSize
        // can report the row content height (self-sizing).
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    func configure(
        with rom: ROM,
        index: Int,
        isSelected: Bool,
        isEvenRow: Bool,
        zoomLevel: Double,
        showSystemLabel: Bool,
        raEnabled: Bool,
        boxArtVersion: UUID,
        selectedIDs: Set<UUID>,
        lastSelectedIndex: Int?,
        actions: GameListRowView.Actions,
        library: ROMLibrary,
        categoryManager: CategoryManager
    ) {
        self.rom = rom
        indexCached = index
        isSelectedCached = isSelected
        isEvenRowCached = isEvenRow
        zoomLevelCached = zoomLevel
        showSystemLabelCached = showSystemLabel
        raEnabledCached = raEnabled
        boxArtVersionCached = boxArtVersion
        selectedIDsCached = selectedIDs
        lastSelectedIndexCached = lastSelectedIndex
        actionsCached = actions
        libraryCached = library
        categoryManagerCached = categoryManager
        isConfigured = true
        rebuildRootView()
    }

    func updateSelectionState(isSelected: Bool, selectedIDs: Set<UUID>, lastSelectedIndex: Int?) {
        guard rom != nil, isConfigured else { return }
        isSelectedCached = isSelected
        selectedIDsCached = selectedIDs
        lastSelectedIndexCached = lastSelectedIndex
        rebuildRootView()
    }

    private func rebuildRootView() {
        guard let rom,
              let actionsCached,
              let libraryCached,
              let categoryManagerCached else { return }
        let row = GameListRowView(
            rom: rom,
            index: indexCached,
            isSelected: isSelectedCached,
            isEvenRow: isEvenRowCached,
            zoomLevel: zoomLevelCached,
            showSystemLabel: showSystemLabelCached,
            raEnabled: raEnabledCached,
            boxArtVersion: boxArtVersionCached,
            boxType: SystemPreferences.shared.boxType(for: rom.systemID ?? ""),
            selectedIDs: selectedIDsCached,
            lastSelectedIndex: lastSelectedIndexCached,
            actions: actionsCached
        )
        .environmentObject(libraryCached)
        .environmentObject(categoryManagerCached)
        hostingView.rootView = AnyView(row)
    }

    /// Content height for the current row at the given width. Sets the width
    /// first so autolayout resolves the free height via fittingSize.
    func measureHeight(proposedWidth: CGFloat) -> CGFloat {
        guard isConfigured else { return 0 }
        setFrameSize(NSSize(width: proposedWidth, height: bounds.height))
        return fittingSize.height
    }
}

// MARK: - Reload token

struct ListReloadToken: Equatable {
    let romsVersion: Int
    let romsCount: Int
    let zoomLevel: Double
    let raEnabled: Bool
    let boxArtVersion: UUID
}

// MARK: - Coordinator

final class ListTableViewCoordinator: NSObject {
    var roms: [ROM] = []
    var zoomLevel: Double = 0.5
    var showSystemLabel = false
    var raEnabled = false
    var boxArtVersion = UUID()
    var selectionIDs: Set<UUID> = []
    var lastSelectedIndex: Int?
    var actions: GameListRowView.Actions?
    var library: ROMLibrary?
    var categoryManager: CategoryManager?

    fileprivate var previousReloadToken: ListReloadToken?
    /// Row height per ROM id. Zoom changes the art extent, so it clears the
    /// cache; data reloads keep it — heights only depend on the rom content
    /// and zoom, and re-measure on configure corrects any drift.
    fileprivate var heightCache: [UUID: CGFloat] = [:]
    private var heightCacheZoom: Double = 0.5
    private var pendingHeightNotes: Set<Int> = []
    private var heightNoteScheduled = false

    var onSelectionChanged: (([UUID]) -> Void)?
    var onPrimarySelectionChanged: ((UUID?) -> Void)?

    private weak var tableView: NSTableView?
    private let rowIdentifier = NSUserInterfaceItemIdentifier("ListTableRow")

    func setup(tableView: NSTableView) {
        self.tableView = tableView
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        let column = NSTableColumn(identifier: rowIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    func syncHeightCacheZoom() {
        if heightCacheZoom != zoomLevel {
            heightCacheZoom = zoomLevel
            heightCache.removeAll()
        }
    }

    func estimatedHeight(for rom: ROM) -> CGFloat {
        if let cached = heightCache[rom.id] { return cached }
        // Art extent mirrors GameListRowView.artExtent; the text block is
        // usually shorter. Corrected by measurement after first configure.
        let extent: CGFloat = 64 + zoomLevel * 72
        let aspect = SystemPreferences.shared.boxType(for: rom.systemID ?? "").aspectRatio
        let artHeight = aspect >= 1 ? extent / aspect : extent
        return artHeight + 16
    }

    /// Records a measured height and schedules a heightOfRow re-pass for the
    /// row when it differs from what the table currently uses.
    func recordMeasuredHeight(_ height: CGFloat, for rom: ROM, index: Int) {
        let previous = heightCache[rom.id]
        heightCache[rom.id] = height
        if previous == nil || abs((previous ?? 0) - height) > 0.5 {
            noteHeightChanged(index: index)
        }
    }

    private func noteHeightChanged(index: Int) {
        pendingHeightNotes.insert(index)
        guard !heightNoteScheduled, let tableView else { return }
        heightNoteScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heightNoteScheduled = false
            let indices = IndexSet(self.pendingHeightNotes)
            self.pendingHeightNotes.removeAll()
            tableView.noteHeightOfRows(withIndexesChanged: indices)
        }
    }
}

// MARK: - Data source

extension ListTableViewCoordinator: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        roms.count
    }
}

// MARK: - Delegate

extension ListTableViewCoordinator: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < roms.count,
              let actions,
              let library,
              let categoryManager else { return nil }
        let rom = roms[row]
        let view = tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? ListTableRowView ?? ListTableRowView()
        view.identifier = rowIdentifier
        view.configure(
            with: rom,
            index: row,
            isSelected: selectionIDs.contains(rom.id),
            isEvenRow: row.isMultiple(of: 2),
            zoomLevel: zoomLevel,
            showSystemLabel: showSystemLabel,
            raEnabled: raEnabled,
            boxArtVersion: boxArtVersion,
            selectedIDs: selectionIDs,
            lastSelectedIndex: lastSelectedIndex,
            actions: actions,
            library: library,
            categoryManager: categoryManager
        )

        // Self-size: measure now that the content is configured so the next
        // heightOfRow pass for this row is exact.
        let measured = view.measureHeight(proposedWidth: tableView.bounds.width)
        if measured > 0 {
            recordMeasuredHeight(measured, for: rom, index: row)
        }
        return view
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < roms.count else { return 40 }
        return estimatedHeight(for: roms[row])
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard row >= 0, row < roms.count else { return nil }
        return roms[row].displayName
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView else { return }
        let ids = tableView.selectedRowIndexes.compactMap { $0 < roms.count ? roms[$0].id : nil }
        onSelectionChanged?(ids)
        onPrimarySelectionChanged?(ids.first)
    }
}

// MARK: - NSScrollView + NSTableView setup

private func makeListScrollView(coordinator: ListTableViewCoordinator) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false

    let tableView = NSTableView()
    scrollView.documentView = tableView

    coordinator.setup(tableView: tableView)
    return scrollView
}

// MARK: - SwiftUI Representable

struct ListTableViewRepresentable: NSViewRepresentable {
    @Binding var roms: [ROM]
    /// Incremented by LibraryViewModel on every displayedROMs publish.
    var romsVersion: Int
    @Binding var selection: Set<UUID>
    @Binding var primarySelection: ROM?
    var zoomLevel: Double
    var showSystemLabel: Bool
    var raEnabled: Bool
    var boxArtVersion: UUID
    var lastSelectedIndex: Int?
    var actions: GameListRowView.Actions
    var library: ROMLibrary
    var categoryManager: CategoryManager
    @Binding var scrollTargetRow: Int?

    func makeCoordinator() -> ListTableViewCoordinator {
        let c = ListTableViewCoordinator()
        c.onSelectionChanged = { [self] ids in
            DispatchQueue.main.async {
                self.selection = Set(ids)
            }
        }
        c.onPrimarySelectionChanged = { [self] id in
            DispatchQueue.main.async {
                if let id, let rom = self.roms.first(where: { $0.id == id }) {
                    self.primarySelection = rom
                } else if id == nil {
                    self.primarySelection = nil
                }
            }
        }
        return c
    }

    private var selectionIDsValue: Set<UUID> {
        var ids = selection
        if let primary = primarySelection { ids.insert(primary.id) }
        return ids
    }

    private var currentToken: ListReloadToken {
        ListReloadToken(
            romsVersion: romsVersion,
            romsCount: roms.count,
            zoomLevel: zoomLevel,
            raEnabled: raEnabled,
            boxArtVersion: boxArtVersion
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        c.roms = roms
        c.zoomLevel = zoomLevel
        c.showSystemLabel = showSystemLabel
        c.raEnabled = raEnabled
        c.boxArtVersion = boxArtVersion
        c.selectionIDs = selectionIDsValue
        c.lastSelectedIndex = lastSelectedIndex
        c.actions = actions
        c.library = library
        c.categoryManager = categoryManager
        c.previousReloadToken = currentToken

        let scrollView = makeListScrollView(coordinator: c)
        (scrollView.documentView as? NSTableView)?.reloadData()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let c = context.coordinator

        let token = currentToken
        let needsReload = token != c.previousReloadToken

        c.roms = roms
        c.zoomLevel = zoomLevel
        c.showSystemLabel = showSystemLabel
        c.raEnabled = raEnabled
        c.boxArtVersion = boxArtVersion
        c.selectionIDs = selectionIDsValue
        c.lastSelectedIndex = lastSelectedIndex
        c.actions = actions
        c.library = library
        c.categoryManager = categoryManager
        c.syncHeightCacheZoom()

        if needsReload {
            c.previousReloadToken = token
            tableView.reloadData()
        }

        // Sync selection SwiftUI -> NSTableView
        let swiftUISelected = IndexSet(roms.enumerated().compactMap { idx, rom in
            selectionIDsValue.contains(rom.id) ? idx : nil
        })
        if tableView.selectedRowIndexes != swiftUISelected {
            tableView.selectRowIndexes(swiftUISelected, byExtendingSelection: false)
        }

        // Selection visuals without a reload: reconfigure visible cells
        // whose selected state changed.
        if !needsReload {
            let visible = tableView.rows(in: tableView.visibleRect)
            for row in visible.toRange() ?? 0..<0 {
                guard row < roms.count,
                      let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ListTableRowView
                else { continue }
                cell.updateSelectionState(
                    isSelected: selectionIDsValue.contains(roms[row].id),
                    selectedIDs: selectionIDsValue,
                    lastSelectedIndex: lastSelectedIndex
                )
            }
        }

        // Gamepad navigation scroll target
        if let target = scrollTargetRow, target >= 0, target < roms.count {
            tableView.scrollRowToVisible(target)
            DispatchQueue.main.async {
                scrollTargetRow = nil
            }
        }
    }
}

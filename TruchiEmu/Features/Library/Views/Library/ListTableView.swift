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
        hostingView.rootView = AnyView(row.id(rom.id))
    }

    /// Content height for the current row at the given width. Sets the width
    /// first so autolayout resolves the free height via fittingSize.
    func measureHeight(proposedWidth: CGFloat) -> CGFloat {
        guard isConfigured else { return 0 }
        setFrameSize(NSSize(width: proposedWidth, height: bounds.height))
        return fittingSize.height
    }
}

// MARK: - Section header row

final class ListSectionHeaderRowView: NSTableCellView {
    private let hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))

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
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(title: String, year: Int?, count: Int) {
        hostingView.rootView = AnyView(LibrarySectionHeaderView(title: title, year: year, count: count))
    }
}

// MARK: - Reload token

struct ListReloadToken: Equatable {
    let romsVersion: Int
    let romsCount: Int
    let zoomLevel: Double
    let raEnabled: Bool
    let boxArtVersion: UUID
    let groupedBySystem: Bool
}

// MARK: - Coordinator

final class ListTableViewCoordinator: NSObject {
    var roms: [ROM] = []
    /// True when a system sort is active — the display list interleaves
    /// per-system section header rows between the games.
    var groupedBySystem = false
    /// Render-ready form of `roms` (headers + games); rebuilt on reload.
    var displayList: LibraryDisplayList = .empty
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
    private let headerRowIdentifier = NSUserInterfaceItemIdentifier("ListSectionHeaderRow")

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

    /// Rebuilds the render-ready display list (header rows + games) from the
    /// current `roms` and grouping flag. Must run before `reloadData`.
    func rebuildDisplayList() {
        displayList = LibrarySectionBuilder.displayList(for: roms, grouped: groupedBySystem)
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
        displayList.entries.count
    }
}

// MARK: - Delegate

extension ListTableViewCoordinator: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < displayList.entries.count else { return nil }

        // Section header row.
        if case .header(let title, let year, let count) = displayList.entries[row] {
            let view = tableView.makeView(withIdentifier: headerRowIdentifier, owner: self) as? ListSectionHeaderRowView ?? ListSectionHeaderRowView()
            view.identifier = headerRowIdentifier
            view.configure(title: title, year: year, count: count)
            return view
        }

        guard case .game(let rom, let flatIndex) = displayList.entries[row],
              let actions,
              let library,
              let categoryManager else { return nil }
        let view = tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? ListTableRowView ?? ListTableRowView()
        view.identifier = rowIdentifier
        view.configure(
            with: rom,
            index: flatIndex,
            isSelected: selectionIDs.contains(rom.id),
            isEvenRow: flatIndex.isMultiple(of: 2),
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
        guard row >= 0, row < displayList.entries.count else { return 40 }
        if case .header = displayList.entries[row] { return 40 }
        guard case .game(let rom, _) = displayList.entries[row] else { return 40 }
        return estimatedHeight(for: rom)
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard row >= 0, row < displayList.entries.count,
              case .game(let rom, _) = displayList.entries[row] else { return nil }
        return rom.displayName
    }

    /// Section header rows are never selectable.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < displayList.entries.count else { return false }
        if case .game = displayList.entries[row] { return true }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView else { return }
        let ids = tableView.selectedRowIndexes.compactMap { row -> UUID? in
            guard row >= 0, row < displayList.entries.count,
                  case .game(let rom, _) = displayList.entries[row] else { return nil }
            return rom.id
        }
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
    var groupedBySystem: Bool
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
            boxArtVersion: boxArtVersion,
            groupedBySystem: groupedBySystem
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        c.roms = roms
        c.groupedBySystem = groupedBySystem
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
        c.rebuildDisplayList()
        (scrollView.documentView as? NSTableView)?.reloadData()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let c = context.coordinator

        let token = currentToken
        let needsReload = token != c.previousReloadToken

        c.roms = roms
        c.groupedBySystem = groupedBySystem
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
            c.rebuildDisplayList()
            tableView.reloadData()
        }

        // Sync selection SwiftUI -> NSTableView
        let swiftUISelected = IndexSet(roms.enumerated().compactMap { (idx, rom) -> Int? in
            guard idx < c.displayList.entryIndexForRomIndex.count else { return nil }
            return selectionIDsValue.contains(rom.id) ? c.displayList.entryIndexForRomIndex[idx] : nil
        })
        if tableView.selectedRowIndexes != swiftUISelected {
            tableView.selectRowIndexes(swiftUISelected, byExtendingSelection: false)
        }

        // Selection visuals without a reload: reconfigure visible cells
        // whose selected state changed.
        if !needsReload {
            let visible = tableView.rows(in: tableView.visibleRect)
            for row in visible.toRange() ?? 0..<0 {
                guard row < c.displayList.entries.count,
                      let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ListTableRowView,
                      case .game(let rom, _) = c.displayList.entries[row]
                else { continue }
                cell.updateSelectionState(
                    isSelected: selectionIDsValue.contains(rom.id),
                    selectedIDs: selectionIDsValue,
                    lastSelectedIndex: lastSelectedIndex
                )
            }
        }

        // Gamepad navigation scroll target
        if let target = scrollTargetRow, target >= 0, target < c.displayList.entryIndexForRomIndex.count {
            tableView.scrollRowToVisible(c.displayList.entryIndexForRomIndex[target])
            DispatchQueue.main.async {
                scrollTargetRow = nil
            }
        }
    }
}

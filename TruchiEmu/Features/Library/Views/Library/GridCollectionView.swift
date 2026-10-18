import SwiftUI
import AppKit

// MARK: - NSCollectionViewItem wrapping GameCardView

final class GridCollectionViewItem: NSCollectionViewItem {
    private let hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))

    private var rom: ROM?
    private var isMultiSelectedCached: Bool = false
    private var zoomLevelCached: Double = 0.5
    private var filterCached: LibraryFilter?
    private var raEnabledCached: Bool = false
    private var onTapCached: (() -> Void)?
    private var onDoubleClickCached: (() -> Void)?
    private var contextMenuProviderCached: (() -> AnyView)?
    private var selectedIDsProviderCached: (() -> Set<UUID>)?
    private var libraryCached: ROMLibrary?
    private var categoryManagerCached: CategoryManager?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override init(nibName nibName: NSNib.Name?, bundle nibBundle: Bundle?) {
        super.init(nibName: nibName, bundle: nibBundle)
        ScrollPerfCounters.gridItemsCreated += 1
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        ScrollPerfCounters.gridItemsCreated += 1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.0, *) {
            // Prevent the hosting view from feeding intrinsic size back into the
            // collection-view layout (measure → relayout → re-measure feedback
            // loop; holo-grid parity).
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

    func configure(
        with rom: ROM,
        isSelected: Bool,
        isMultiSelected: Bool,
        zoomLevel: Double,
        filter: LibraryFilter?,
        raEnabled: Bool,
        onTap: (() -> Void)?,
        onDoubleClick: (() -> Void)?,
        contextMenuProvider: (() -> AnyView)?,
        selectedIDsProvider: @escaping () -> Set<UUID>,
        library: ROMLibrary,
        categoryManager: CategoryManager
    ) {
        // A configure on an item that already shows a ROM means AppKit reused
        // a prepared item; nil means this is a freshly created cell.
        if rom != nil { ScrollPerfCounters.gridItemsReused += 1 }
        self.rom = rom
        self.isMultiSelectedCached = isMultiSelected
        self.zoomLevelCached = zoomLevel
        self.filterCached = filter
        self.raEnabledCached = raEnabled
        self.onTapCached = onTap
        self.onDoubleClickCached = onDoubleClick
        self.contextMenuProviderCached = contextMenuProvider
        self.selectedIDsProviderCached = selectedIDsProvider
        self.libraryCached = library
        self.categoryManagerCached = categoryManager
        rebuildRootView()
    }

    func updateSelectionState(isSelected: Bool, isMultiSelected: Bool) {
        guard rom != nil else { return }
        isMultiSelectedCached = isMultiSelected
        rebuildRootView(isSelectedOverride: isSelected)
    }

    private func rebuildRootView(isSelectedOverride: Bool? = nil) {
        guard let rom = rom,
              let libraryCached = libraryCached,
              let categoryManagerCached = categoryManagerCached else { return }
        let isSelected = isSelectedOverride ?? isMultiSelectedCached
        let card = GameCardView(
            rom: rom,
            isSelected: isSelected,
            isMultiSelected: isMultiSelectedCached,
            zoomLevel: zoomLevelCached,
            filter: filterCached,
            raEnabled: raEnabledCached,
            onTap: onTapCached,
            onDoubleClick: onDoubleClickCached,
            contextMenu: contextMenuProviderCached,
            selectedIDsProvider: selectedIDsProviderCached
        )
        .environmentObject(libraryCached)
        .environmentObject(categoryManagerCached)
        hostingView.rootView = AnyView(card)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}

// MARK: - Coordinator

final class GridCollectionViewCoordinator: NSObject {
    var roms: [ROM] = []
    var zoomLevel: Double = 0.5
    var filter: LibraryFilter?
    var raEnabled: Bool = false
    var gridPadding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    var gridSpacing: CGFloat = 10
    var library: ROMLibrary?
    var categoryManager: CategoryManager?
    fileprivate var previousRomsCount: Int = 0
    fileprivate var previousRomsFingerprint: [String] = []
    fileprivate var previousZoomLevel: Double = 0.5
    fileprivate var previousBoxArtVersion: UUID = UUID()
    fileprivate var previousSelection: Set<UUID> = []

    var onSelectionChanged: (([UUID]) -> Void)?
    var onPrimarySelectionChanged: ((UUID?) -> Void)?
    var onDoubleClick: ((ROM) -> Void)?
    var onTap: ((ROM, Int) -> Void)?
    var contextMenuProvider: ((ROM) -> AnyView)?

    private weak var collectionView: NSCollectionView?
    fileprivate let itemID = NSUserInterfaceItemIdentifier("GridCollectionViewItem")
    // Scroll detection (holo-grid parity): observes the enclosing scroll view
    // so the shared `ScrollActivity.isScrolling` flag flips true while the
    // boxart grid scrolls. GameCardView suppresses hover/pivot/play-button
    // effects and its per-frame frame-tracking GeometryReader while this is
    // set — otherwise every card that passes under a stationary cursor mounts
    // the pivot + GlassOrbPlayButton and re-renders mid-scroll.
    var boundsObserver: NSObjectProtocol?
    var liveScrollStartObserver: NSObjectProtocol?
    var liveScrollEndObserver: NSObjectProtocol?
    fileprivate var scrollResetTimer: Timer?

    // Re-armed on every scroll event so `isScrolling` stays true for the
    // whole gesture and only flips false 0.3s after the last one. Writes the
    // plain `ScrollActivity` flag (same as the list view's wheel monitor):
    // cards read it LIVE in their hover/tilt handlers instead of observing
    // it, so a gesture start/end does not re-render every visible card —
    // an ObservableObject publish here measured as a ~70ms hitch at each
    // gesture boundary (36 cards × full body re-eval). The flag's didSet
    // posts `.libraryScrollActivityChanged` once per transition so cards
    // reset their transient hover/tilt state.
    fileprivate func markScrolling() {
        // Observers pass queue: .main, so the main-actor assumption holds.
        MainActor.assumeIsolated {
            ScrollActivity.isScrolling = true
            self.scrollResetTimer?.invalidate()
            self.scrollResetTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    ScrollActivity.isScrolling = false
                    self?.scrollResetTimer = nil
                }
            }
        }
    }

    func setup(collectionView: NSCollectionView, scrollView: NSScrollView) {
        self.collectionView = collectionView
        // Register the item class so the collection view RECYCLES a bounded
        // pool of items instead of the data source instantiating a fresh
        // NSHostingView (with its own SwiftUI view tree) for every index path
        // scrolled into view (holo-grid parity).
        collectionView.register(GridCollectionViewItem.self, forItemWithIdentifier: itemID)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.collectionViewLayout = createLayout()
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        if collectionView.responds(to: Selector(("allowsRubberBandSelection"))) {
            collectionView.setValue(true, forKey: "allowsRubberBandSelection")
        }

        // Scroll detection from ALL sources (scrollbar drag, keyboard,
        // programmatic, trackpad/wheel), holo-grid parity.
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.markScrolling()
        }
        liveScrollStartObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.markScrolling()
        }
        liveScrollEndObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scrollResetTimer?.invalidate()
                self.scrollResetTimer = nil
                ScrollActivity.isScrolling = false
            }
        }

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        collectionView.addGestureRecognizer(doubleClick)
    }

    func reloadData() {
        collectionView?.reloadData()
    }

    func updateItemSizes() {
        guard let cv = collectionView else { return }
        let cardWidth: CGFloat = (80 + (zoomLevel * 200)) * 1.25
        let spacing: CGFloat = max(8, 18 - (zoomLevel * 8))
        gridSpacing = spacing

        _ = max(1, min(8, Int((cv.bounds.width - (gridPadding.leading + gridPadding.trailing) + spacing) / (cardWidth + spacing))))

        let boxType: BoxType?
        if case .system(let system) = filter {
            let type = SystemPreferences.shared.boxType(for: system.id)
            // Adaptive cards keep the system's default frame aspect so the
            // uniform flow-layout item size stays valid for mixed art.
            boxType = (type == .adaptive) ? system.defaultBoxType : type
        } else {
            boxType = nil
        }

        let cardHeight = cardHeightForBoxType(boxType, cardWidth: cardWidth, zoomLevel: zoomLevel)

        let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout
        layout?.itemSize = CGSize(width: cardWidth, height: cardHeight)
        layout?.minimumInteritemSpacing = spacing
        layout?.minimumLineSpacing = spacing
        layout?.sectionInset = NSEdgeInsets(
            top: gridPadding.top,
            left: gridPadding.leading,
            bottom: gridPadding.bottom,
            right: gridPadding.trailing
        )
    }

    func scrollToItem(at index: Int) {
        guard let cv = collectionView, index >= 0, index < roms.count else { return }
        let ip = IndexPath(item: index, section: 0)
        cv.scrollToItems(at: [ip], scrollPosition: .centeredVertically)
    }

    // MARK: - Double-click

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        guard let cv = collectionView else { return }
        let point = gesture.location(in: cv)
        if let ip = cv.indexPathForItem(at: point), ip.item < roms.count {
            onDoubleClick?(roms[ip.item])
        }
    }

    // MARK: - Layout

    private func createLayout() -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = gridSpacing
        layout.minimumLineSpacing = gridSpacing
        return layout
    }

    private func cardHeightForBoxType(_ boxType: BoxType?, cardWidth: CGFloat, zoomLevel: Double) -> CGFloat {
        let titleSize = 10.0 + zoomLevel * 6.0
        let textRowHeight = ceil(titleSize * 1.3)
        let textBlockHeight = textRowHeight * 2.0 + 4.0
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 4

        let artHeight: CGFloat
        let gap: CGFloat
        if let boxType {
            switch boxType {
            // `.adaptive` is resolved to the system's default box type by
            // updateItemSizes; this branch is only a safe fallback.
            case .vertical, .adaptive:
                artHeight = cardWidth / 0.75
                gap = 8
            case .box:
                artHeight = cardWidth
                gap = 4
            case .landscape:
                artHeight = cardWidth / 1.333
                gap = 4
            }
        } else {
            switch SystemPreferences.shared.boxArtDisplayMode() {
            case .fillBlurred:
                artHeight = cardWidth / 0.75
                gap = 8
            case .cropSquare:
                artHeight = cardWidth
                gap = 4
            }
        }

        return ceil(artHeight + textBlockHeight + gap + topPadding + bottomPadding)
    }
}

// MARK: - Data Source

extension GridCollectionViewCoordinator: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        roms.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        // Register defensively every dequeue: a prior registration can be
        // invalidated if AppKit recreates the underlying view-layer, and an
        // unregistered identifier makes `makeItem` fail. Dequeue through
        // `makeItem` so a bounded pool of items is RECYCLED as cells scroll
        // in and out — creating a fresh item here built a new NSHostingView
        // (+ full SwiftUI tree) for every cell that scrolled into view, which
        // was the boxart grid's main mid-scroll stall (measured: 72 fresh
        // items + ~300-590ms main-thread busy per scroll burst at 2108 ROMs).
        collectionView.register(GridCollectionViewItem.self, forItemWithIdentifier: itemID)
        let item = collectionView.makeItem(withIdentifier: itemID, for: indexPath) as! GridCollectionViewItem
        let rom = roms[indexPath.item]
        let selected = collectionView.selectionIndexPaths.contains(indexPath)
        let selectedIDsProvider: () -> Set<UUID> = { [weak self] in
            guard let self else { return [] }
            return Set(self.collectionView?.selectionIndexPaths.compactMap { $0.item < self.roms.count ? self.roms[$0.item].id : nil } ?? [])
        }
        item.configure(
            with: rom,
            isSelected: selected,
            isMultiSelected: selected,
            zoomLevel: zoomLevel,
            filter: filter,
            raEnabled: raEnabled,
            onTap: { [weak self] in self?.onTap?(rom, indexPath.item) },
            onDoubleClick: { [weak self] in self?.onDoubleClick?(rom) },
            contextMenuProvider: { [weak self] in
                self?.contextMenuProvider?(rom) ?? AnyView(EmptyView())
            },
            selectedIDsProvider: selectedIDsProvider,
            library: library ?? ROMLibrary(),
            categoryManager: categoryManager ?? CategoryManager()
        )
        return item
    }
}

// MARK: - Delegate

extension GridCollectionViewCoordinator: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        forwardSelection(collectionView)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        forwardSelection(collectionView)
    }

    private func forwardSelection(_ collectionView: NSCollectionView) {
        let ids = collectionView.selectionIndexPaths
            .sorted { $0.item < $1.item }
            .compactMap { $0.item < roms.count ? roms[$0.item].id : nil }
        onSelectionChanged?(ids)
        onPrimarySelectionChanged?(ids.first)
    }
}

// MARK: - Prefetching

extension GridCollectionViewCoordinator: NSCollectionViewPrefetching {
    func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        ScrollPerfCounters.prefetchIndexPaths += indexPaths.count
        let thumbSize = BoxArtThumbnailSize.forGridZoom(zoomLevel)
        for ip in indexPaths where ip.item < roms.count {
            let rom = roms[ip.item]
            // Use the precomputed path; skip ROMs without art. The global
            // resolveLocalBoxArt is only needed for unrecognized naming, which
            // the scan/automation path handles — prefetch shouldn't re-stat.
            let artPath = rom.boxArtLocalPath
            guard rom.hasBoxArt, FileManager.default.fileExists(atPath: artPath.path) else { continue }
            Task {
                if thumbSize != .tiny {
                    _ = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .tiny)
                }
                _ = await ImageCache.shared.thumbnail(for: artPath, preferredSize: thumbSize)
            }
        }
    }

    func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        // In-flight ImageCache tasks complete and cache the result regardless,
        // so explicit cancellation is unnecessary.
    }
}

// MARK: - NSScrollView + NSCollectionView setup

private func makeCollectionScrollView(coordinator: GridCollectionViewCoordinator) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false

    let cv = NSCollectionView()
    scrollView.documentView = cv

    // Register the item class so `makeItem` recycles a bounded item pool.
    cv.register(GridCollectionViewItem.self, forItemWithIdentifier: coordinator.itemID)

    coordinator.setup(collectionView: cv, scrollView: scrollView)
    coordinator.updateItemSizes()

    return scrollView
}

// MARK: - SwiftUI Representable

struct GridCollectionViewRepresentable: NSViewRepresentable {
    @Binding var roms: [ROM]
    @Binding var selection: Set<UUID>
    @Binding var primarySelection: ROM?
    var zoomLevel: Double
    var filter: LibraryFilter?
    var raEnabled: Bool
    var gridPadding: EdgeInsets
    var boxArtVersion: UUID
    var onDoubleClick: ((ROM) -> Void)?
    var onTap: ((ROM, Int) -> Void)?
    var contextMenuProvider: ((ROM) -> AnyView)?
    var library: ROMLibrary?
    var categoryManager: CategoryManager?

    func makeCoordinator() -> GridCollectionViewCoordinator {
        let c = GridCollectionViewCoordinator()
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
        c.onDoubleClick = onDoubleClick
        c.onTap = onTap
        c.contextMenuProvider = contextMenuProvider
        c.library = library
        c.categoryManager = categoryManager
        return c
    }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        c.roms = roms
        c.zoomLevel = zoomLevel
        c.filter = filter
        c.raEnabled = raEnabled
        c.gridPadding = gridPadding
        c.onDoubleClick = onDoubleClick
        c.onTap = onTap
        c.contextMenuProvider = contextMenuProvider
        c.library = library
        c.categoryManager = categoryManager
        c.previousRomsCount = roms.count
        c.previousRomsFingerprint = roms.map { "\($0.id)|\($0.hasBoxArt)|\($0.raMatchStatus ?? "")|\($0.raGameId ?? 0)" }
        c.previousZoomLevel = zoomLevel
        c.previousBoxArtVersion = boxArtVersion
        c.previousSelection = selection

        let scrollView = makeCollectionScrollView(coordinator: c)
        c.reloadData()
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: GridCollectionViewCoordinator) {
        if let observer = coordinator.boundsObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.boundsObserver = nil
        }
        if let observer = coordinator.liveScrollStartObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.liveScrollStartObserver = nil
        }
        if let observer = coordinator.liveScrollEndObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.liveScrollEndObserver = nil
        }
        coordinator.scrollResetTimer?.invalidate()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let cv = nsView.documentView as? NSCollectionView else { return }
        let c = context.coordinator

        let newFingerprint = roms.map { "\($0.id)|\($0.hasBoxArt)|\($0.raMatchStatus ?? "")|\($0.raGameId ?? 0)" }
        let dataChanged = roms.count != c.previousRomsCount || newFingerprint != c.previousRomsFingerprint
        let zoomChanged = zoomLevel != c.previousZoomLevel
        let boxArtChanged = boxArtVersion != c.previousBoxArtVersion
        let needsReload = dataChanged || zoomChanged || boxArtChanged

        c.roms = roms
        c.zoomLevel = zoomLevel
        c.filter = filter
        c.raEnabled = raEnabled
        c.gridPadding = gridPadding
        c.onDoubleClick = onDoubleClick
        c.onTap = onTap
        c.contextMenuProvider = contextMenuProvider
        c.library = library
        c.categoryManager = categoryManager
        c.previousRomsCount = roms.count
        c.previousRomsFingerprint = newFingerprint
        c.previousZoomLevel = zoomLevel
        c.previousBoxArtVersion = boxArtVersion

        let oldSelection = c.previousSelection
        let selectionChanged = selection != oldSelection

        if needsReload {
            c.updateItemSizes()
            c.reloadData()
        }

        // Sync selection from SwiftUI → NSCollectionView
        let swiftUISelected = Set(roms.enumerated().compactMap { idx, rom in
            (selection.contains(rom.id) || primarySelection?.id == rom.id)
                ? IndexPath(item: idx, section: 0) : nil
        })
        let currentSelected = cv.selectionIndexPaths
        if currentSelected != swiftUISelected {
            let toDeselect = currentSelected.subtracting(swiftUISelected)
            let toSelect = swiftUISelected.subtracting(currentSelected)
            if !toDeselect.isEmpty { cv.deselectItems(at: toDeselect) }
            if !toSelect.isEmpty { cv.selectItems(at: toSelect, scrollPosition: []) }
        }

        // Update only the affected items' selection state to avoid full reload blink
        if selectionChanged && !needsReload {
            let oldIndexSet = Set(oldSelection.compactMap { id in
                roms.firstIndex(where: { $0.id == id }).map { IndexPath(item: $0, section: 0) }
            })
            let newIndexSet = swiftUISelected
            let changedPaths = oldIndexSet.symmetricDifference(newIndexSet)
            for ip in changedPaths {
                if cv.indexPathsForVisibleItems().contains(ip),
                   let item = cv.item(at: ip) as? GridCollectionViewItem {
                    let selected = newIndexSet.contains(ip)
                    item.updateSelectionState(isSelected: selected, isMultiSelected: selected)
                }
            }
        }

        c.previousSelection = selection
    }
}

import SwiftUI
import AppKit

// MARK: - Scroll state

/// Shared flag indicating whether the holo library grid is currently
/// scrolling. Holo card effects (foil, glare, tilt, bump) are suppressed
/// while this is true so cards don't light up mid-scroll — they only engage
/// once the scroll settles. A single shared instance is updated by the grid's
/// scroll-wheel monitor and observed by each `HoloGameCardView`. All updates
/// happen on the main runloop, so no actor isolation is needed.
final class LibraryScrollState: ObservableObject {
    static let shared = LibraryScrollState()
    @Published var isScrolling: Bool = false
}

// MARK: - NSCollectionViewItem wrapping HoloGameCardView

final class HoloGridCollectionViewItem: NSCollectionViewItem {
    private let hostingView = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    
    private var rom: ROM?
    private var romID: UUID?
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
        view.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        hostingView.translatesAutoresizingMaskIntoConstraints = false
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
        self.rom = rom
        self.romID = rom.id
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
        // `rebuildRootView` sets `.id(rom.id)` on the SwiftUI root, so
        // SwiftUI tears down the previous card's @State (image, holoMasks,
        // hover position) and rebuilds clean. No need to swap in an
        // EmptyView first — that just delays the diff and gives the old
        // state a window to remain visible during the very next runloop.
        rebuildRootView(isSelectedOverride: isSelected)
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
        let card = HoloGameCardView(
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
        // `.id(rom.id)` forces SwiftUI to treat each rom as a distinct view
        // identity. When an NSCollectionViewItem slot is reused for a
        // different rom, SwiftUI tears down the old card's @State
        // (image / holoMasks / hover / cardBounds) and runs the new card's
        // .task bodies from clean defaults. Without this, AnyView erases the
        // rom identity and SwiftUI diff-matches old↔new state, so the new
        // card inherits the previous rom's already-loaded image/masks and the
        // task bodies bail out — the "stuck card" bug.
        .id(rom.id)
        hostingView.rootView = AnyView(card)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        // Drop SwiftUI state when the slot is recycled. The next configure()
        // will rebuild the rootView from a fresh HoloGameCardView, and bailing
        // here lets SwiftUI discard the previous card's @State immediately
        // instead of leaking it into the new rom.
        rom = nil
        romID = nil
        hostingView.rootView = AnyView(EmptyView())
    }
}

// MARK: - Coordinator

final class HoloGridCollectionViewCoordinator: NSObject {
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
    fileprivate var previousRomsSystemSet: Set<String?> = []
    fileprivate var previousZoomLevel: Double = 0.5
    fileprivate var previousBoxArtVersion: UUID = UUID()
    fileprivate var previousSelection: Set<UUID> = []
    fileprivate var scrollResetTimer: Timer?
    var scrollMonitor: Any?
    
    var onSelectionChanged: (([UUID]) -> Void)?
    var onPrimarySelectionChanged: ((UUID?) -> Void)?
    var onDoubleClick: ((ROM) -> Void)?
    var onTap: ((ROM, Int) -> Void)?
    var contextMenuProvider: ((ROM) -> AnyView)?
    
    // MARK: Scroll detection
    //
    // The enclosing NSScrollView's delegate is set to this coordinator so we
    // can observe scrolling and flag it on `LibraryScrollState`. A short
    // debounce (matching `LibraryGridView`'s scroll-wheel monitor) keeps the
    // flag true for 0.3s after the last scroll event, so the holo effects
    // only resume once the scroll has genuinely stopped.
    fileprivate func markScrolling() {
        LibraryScrollState.shared.isScrolling = true
        scrollResetTimer?.invalidate()
        scrollResetTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            LibraryScrollState.shared.isScrolling = false
            self?.scrollResetTimer = nil
        }
    }
    
    private weak var collectionView: NSCollectionView?
    private let itemID = NSUserInterfaceItemIdentifier("HoloGridCollectionViewItem")
    
    func setup(collectionView: NSCollectionView) {
        self.collectionView = collectionView
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
            boxType = SystemPreferences.shared.boxType(for: system.id)
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
            case .vertical:
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

extension HoloGridCollectionViewCoordinator: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        roms.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = HoloGridCollectionViewItem()
        item.identifier = itemID
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

extension HoloGridCollectionViewCoordinator: NSCollectionViewDelegate {
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

extension HoloGridCollectionViewCoordinator: NSCollectionViewPrefetching {
    func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let thumbSize = BoxArtThumbnailSize.forGridZoom(zoomLevel)
        for ip in indexPaths where ip.item < roms.count {
            let rom = roms[ip.item]
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

private func makeHoloCollectionScrollView(coordinator: HoloGridCollectionViewCoordinator) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    
    let cv = NSCollectionView()
    scrollView.documentView = cv
    
    coordinator.setup(collectionView: cv)
    coordinator.updateItemSizes()
    
    return scrollView
}

// MARK: - SwiftUI Representable

struct HoloGridCollectionViewRepresentable: NSViewRepresentable {
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
    
    func makeCoordinator() -> HoloGridCollectionViewCoordinator {
        let c = HoloGridCollectionViewCoordinator()
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
        c.previousRomsFingerprint = roms.map { "\($0.id)|\($0.raMatchStatus ?? "")|\($0.raGameId ?? 0)" }
        c.previousRomsSystemSet = Set(roms.map(\.systemID))
        c.previousZoomLevel = zoomLevel
        c.previousBoxArtVersion = boxArtVersion
        c.previousSelection = selection
        
        let scrollView = makeHoloCollectionScrollView(coordinator: c)
        c.reloadData()
        
        // Track scrolling so holo cards can suppress their effects mid-scroll
        // (they only engage once the scroll settles). Mirrors the scroll-wheel
        // monitor used by `LibraryGridView`.
        c.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            c.markScrolling()
            return event
        }
        
        return scrollView
    }
    
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: HoloGridCollectionViewCoordinator) {
        if let monitor = coordinator.scrollMonitor {
            NSEvent.removeMonitor(monitor)
            coordinator.scrollMonitor = nil
        }
        coordinator.scrollResetTimer?.invalidate()
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let cv = nsView.documentView as? NSCollectionView else { return }
        let c = context.coordinator
        
let newFingerprint = roms.map { "\($0.id)|\($0.raMatchStatus ?? "")|\($0.raGameId ?? 0)" }
        let dataChanged = roms.count != c.previousRomsCount || newFingerprint != c.previousRomsFingerprint
        let zoomChanged = zoomLevel != c.previousZoomLevel
        let boxArtChanged = boxArtVersion != c.previousBoxArtVersion
        let needsReload = dataChanged || zoomChanged || boxArtChanged

        // The user switched systems (the displayed roms now belong to a
        // different set of systems). Abort every in-flight mask generation
        // for the system they just left so the CPU frees up immediately and
        // the new system's cards are the ones that get decomposed. Without
        // this, a quick switch-back stacks stale decomposes on top of fresh
        // ones and the machine stays pinned.
        let systemSet = Set(roms.map(\.systemID))
        let systemChanged = systemSet != c.previousRomsSystemSet
        if systemChanged {
            HoloSaliencyService.shared.cancelAll()
        }

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
        c.previousRomsSystemSet = systemSet
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
                   let item = cv.item(at: ip) as? HoloGridCollectionViewItem {
                    let selected = newIndexSet.contains(ip)
                    item.updateSelectionState(isSelected: selected, isMultiSelected: selected)
                }
            }
        }
        
        c.previousSelection = selection
    }
}
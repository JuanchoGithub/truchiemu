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
    
    var isScrolling: Bool = false {
        willSet {
            guard newValue != isScrolling else { return }
            objectWillChange.send()
        }
    }
}

// MARK: - NSCollectionViewItem wrapping HoloGameCardView

final class HoloGridCollectionViewItem: NSCollectionViewItem {
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.0, *) {
            // Prevent the hosting view from feeding intrinsic size back into the
            // collection-view layout (which caused a measure → relayout →
            // re-measure feedback loop).
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

    func configure(with rom: ROM,
                   isSelected: Bool,
                   isMultiSelected: Bool,
                   zoomLevel: Double,
                   filter: LibraryFilter?,
                   raEnabled: Bool,
                   onTap: (() -> Void)?,
                   onDoubleClick: (() -> Void)?,
                   contextMenuProvider: (() -> AnyView)?,
                   selectedIDsProvider: @escaping () -> Set<UUID>,
                   library: ROMLibrary?,
                   categoryManager: CategoryManager?) {
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
        rebuildRootView(isSelectedOverride: isSelected)
    }

    /// Apply a selection-state change to the currently displayed card without
    /// re-running the data-source `configure` path (used by `updateNSView`).
    func updateSelectionState(isSelected: Bool, isMultiSelected: Bool) {
        self.isMultiSelectedCached = isMultiSelected
        rebuildRootView(isSelectedOverride: isSelected)
    }

    private func rebuildRootView(isSelectedOverride: Bool? = nil) {
        guard let rom = rom else { return }
        let card = HoloGameCardView(
            rom: rom,
            isSelected: isSelectedOverride ?? false,
            isMultiSelected: isMultiSelectedCached,
            zoomLevel: zoomLevelCached,
            filter: filterCached,
            raEnabled: raEnabledCached,
            onTap: onTapCached,
            onDoubleClick: onDoubleClickCached,
            contextMenu: contextMenuProviderCached,
            selectedIDsProvider: selectedIDsProviderCached ?? { [] }
        )
        .environmentObject(libraryCached ?? ROMLibrary())
        .environmentObject(categoryManagerCached ?? CategoryManager())
        hostingView.rootView = AnyView(card)
        hostingView.needsLayout = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Keep `rom` set so a late `rebuildRootView` (from a pending selection
        // update) doesn't early-return; `configure` always re-sets rom on reuse.
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
    fileprivate     var scrollResetTimer: Timer?
    // Observes the scroll-view bounds changing for ALL scroll sources
    // (scrollbar drag, keyboard, programmatic, trackpad/wheel). The
    // scrollWheel monitor alone misses non-wheel scrolls, which left
    // `isScrolling` false during scrollbar drags — so holo cards kept
    // building their foil layers (main-thread tile render) mid-scroll and
    // the grid would eventually peg the main thread.
    var boundsObserver: NSObjectProtocol?
    var liveScrollStartObserver: NSObjectProtocol?
    var liveScrollEndObserver: NSObjectProtocol?
    
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
        if !LibraryScrollState.shared.isScrolling {
            LibraryScrollState.shared.isScrolling = true
        }
        // Re-arm the idle timer on EVERY scroll event so `isScrolling` stays
        // true for the whole gesture. The previous code only armed the timer
        // on the first event, so during a continuous (momentum) scroll the
        // timer fired ~0.3s in and flipped `isScrolling` false mid-gesture,
        // then true again on the next frame — a flicker. That flicker
        // defeated `cardContent`'s `!scrollState.isScrolling` guard on the
        // per-frame frame-tracking GeometryReader, mounting it mid-scroll and
        // rebuilding every visible cell each frame (pegging the main thread
        // into the permanent lock-up). Re-arming per event keeps `isScrolling`
        // high until 0.3s after the LAST scroll event.
        scrollResetTimer?.invalidate()
        scrollResetTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            LibraryScrollState.shared.isScrolling = false
            self?.scrollResetTimer = nil
        }
    }
    
    private weak var collectionView: NSCollectionView?
    fileprivate let itemID = NSUserInterfaceItemIdentifier("HoloGridCollectionViewItem")
    
    func setup(collectionView: NSCollectionView, scrollView: NSScrollView) {
        self.collectionView = collectionView
        // Register the custom item subclass for reuse. `itemForRepresentedObjectAt`
        // also registers defensively before `makeItem` (AppKit can drop the
        // registration if it recreates the view layer, which otherwise makes
        // `makeItem` fail with "must register a nib or a class").
        collectionView.register(HoloGridCollectionViewItem.self, forItemWithIdentifier: itemID)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.collectionViewLayout = createLayout()

        // Detect scroll from ALL sources (scrollbar drag, keyboard, programmatic,
        // trackpad/wheel) so `LibraryScrollState.isScrolling` is reliably true
        // while scrolling. Without this the holo foil layers would build their
        // main-thread-rendered tiles during scrollbar drags and peg the main
        // thread. The scrollView is passed explicitly (rather than relying on
        // `collectionView.enclosingScrollView`) because that isn't guaranteed to
        // resolve at setup time.
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.markScrolling()
        }
        // Canonical "user is scrolling" signals — fire for wheel, scrollbar
        // drag, keyboard, and trackpad, unlike the wheel-only monitor. These
        // guarantee `isScrolling` is true for the whole scroll gesture so the
        // lightweight scroll card engages.
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
            guard let self else { return }
            scrollResetTimer?.invalidate()
            scrollResetTimer = nil
            LibraryScrollState.shared.isScrolling = false
        }
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
        // Register defensively every dequeue: a prior registration can be
        // invalidated if AppKit recreates the underlying view-layer, and an
        // unregistered identifier makes `makeItem` fall back to a nib lookup and
        // abort ("must register a nib or a class").
        collectionView.register(HoloGridCollectionViewItem.self, forItemWithIdentifier: itemID)
        let item = collectionView.makeItem(withIdentifier: itemID, for: indexPath) as! HoloGridCollectionViewItem
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
            contextMenuProvider: { [weak self] in self?.contextMenuProvider?(rom) ?? AnyView(EmptyView()) },
            selectedIDsProvider: selectedIDsProvider,
            library: library,
            categoryManager: categoryManager
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

        // Register the item class so the collection view RECYCLES a bounded
        // pool of items instead of instantiating a fresh `NSHostingView`
        // (with its own SwiftUI view tree + `.task`s) for every index path it
        // scrolls into view. Without registration `itemForRepresentedObjectAt`
        // creates a new item each call and none are ever recycled, so on a
        // large system the grid accumulates thousands of retained hosting
        // views + in-flight tasks, pegging memory/CPU until the whole holo
        // view is torn down — the "scroll freeze that only clears on view
        // change" symptom.
        cv.register(HoloGridCollectionViewItem.self, forItemWithIdentifier: coordinator.itemID)

        coordinator.setup(collectionView: cv, scrollView: scrollView)
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

        return scrollView
    }
    
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: HoloGridCollectionViewCoordinator) {
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
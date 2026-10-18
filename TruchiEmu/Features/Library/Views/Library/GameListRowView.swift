import SwiftUI
import AppKit

// MARK: - Scroll Activity Flag

// Scroll-gesture state WITHOUT SwiftUI observation. Flipping a parent @State
// on the first wheel event made macOS List re-diff all row identities
// (OutlineListCoordinator.diffRows — seconds at 2108 rows) on every gesture
// start. Rows read this flag live in hover/tilt handlers instead, and reset
// their transient hover/tilt state via the scroll-activity notification.
@MainActor
enum ScrollActivity {
    static var isScrolling = false {
        didSet {
            guard oldValue != isScrolling else { return }
            NotificationCenter.default.post(name: .libraryScrollActivityChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let libraryScrollActivityChanged = Notification.Name("libraryScrollActivityChanged")
}

// MARK: - List Row

// macOS List eagerly rebuilds EVERY row value on each parent re-evaluation
// (unlike iOS): the ForEach content closure runs for all ~2100 rows, and
// each result is copied, compared and destroyed. Profiled cost of a system
// switch was dominated by `initializeWithCopy/destroy for GameListRowView`,
// `outlined init with copy of LibraryGridView` (per-row closures captured
// the whole parent struct), and ROM copy churn — ~600ms per switch.
// Contract that keeps this O(visible rows):
//   1. The row VALUE must stay tiny: plain data fields plus `actions`, a
//      struct of closures created ONCE per parent body evaluation — copying
//      it into a row only bumps reference counts.
//   2. No per-row closures in the parent's ForEach. All gestures, context
//      menus, drag handlers etc. live INSIDE `body`, which List evaluates
//      lazily for visible rows only.
//   3. The custom == must cover every field the body reads; the action
//      closures are excluded (never equal), so any parent VALUE-type state
//      they capture (selection, lastSelectedIndex) must have a matching
//      compared field or it would go stale when == short-circuits an update.
struct GameListRowView: View, Equatable {
    let rom: ROM
    let index: Int
    let isSelected: Bool
    let isEvenRow: Bool
    let zoomLevel: Double
    // Derived once per parent evaluation from `filter`: rows must not store
    // the whole LibraryFilter or every system switch invalidates every row
    // value (the filter always changes) and forces a full eager re-walk.
    let showSystemLabel: Bool
    let raEnabled: Bool
    // Passed down instead of observing BoxArtService here: the parent already
    // re-renders on boxArtUpdated bumps, and a @ObservedObject in every row
    // made each bump invalidate all realized rows.
    let boxArtVersion: UUID
    // Passed down instead of reading SystemPreferences in the row: == would
    // otherwise short-circuit a box-type change before the row re-read it.
    let boxType: BoxType
    // Equality-only inputs. The action closures capture the parent's
    // value-type selection state, so any change to it must refresh this row
    // value through == (otherwise the hover-orb menu and shift-select would
    // act on stale selection).
    let selectedIDs: Set<UUID>
    let lastSelectedIndex: Int?
    // Created once per parent body evaluation. See contract in the header
    // comment: per-row closures here would reintroduce the copy storm.
    let actions: Actions

    struct Actions {
        let onLaunch: (ROM) -> Void
        let onTap: (ROM, Int) -> Void
        let onContextMenu: (ROM) -> AnyView
        let dragItemsFor: (ROM, Bool) -> [ROM]
        let onDragStarted: ([ROM]) -> Void
    }

    static func == (lhs: GameListRowView, rhs: GameListRowView) -> Bool {
        lhs.rom == rhs.rom
            && lhs.index == rhs.index
            && lhs.isSelected == rhs.isSelected
            && lhs.isEvenRow == rhs.isEvenRow
            && lhs.zoomLevel == rhs.zoomLevel
            && lhs.showSystemLabel == rhs.showSystemLabel
            && lhs.raEnabled == rhs.raEnabled
            && lhs.boxArtVersion == rhs.boxArtVersion
            && lhs.boxType == rhs.boxType
            && lhs.selectedIDs == rhs.selectedIDs
            && lhs.lastSelectedIndex == rhs.lastSelectedIndex
    }
    @Environment(\.colorScheme) private var colorScheme
    @State private var thumb: NSImage?
    @State private var isHovered = false
    @State private var raProgress: (earned: Int, total: Int)?
    @State private var mousePosition: CGPoint?
    @State private var tiltRotationX: Double = 0
    @State private var tiltRotationY: Double = 0
    @State private var artFrame: CGRect = .zero
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var gamepadNav = GamepadNavigationManager.shared
    @EnvironmentObject var categoryManager: CategoryManager

    // Identifies the per-row thumbnail task without string interpolation.
    // hasBoxArt: handleFilterChange resolves local box art in the background
    // after a system switch; without it in the task id, rows that survive
    // the switch never restart the task and keep the placeholder art.
    private struct ArtTaskID: Equatable {
        let romID: UUID
        let artVersion: UUID
        let hasBoxArt: Bool
    }
    
    private var titleFontSize: CGFloat {
        12 + zoomLevel * 8
    }
    
    private var subtitleFontSize: CGFloat {
        9 + zoomLevel * 5
    }
    
    private var artExtent: CGFloat {
        64 + zoomLevel * 72
    }

    private var thumbWidth: CGFloat {
        let aspect = boxType.aspectRatio
        return aspect >= 1 ? artExtent : artExtent * aspect
    }

    private var thumbHeight: CGFloat {
        let aspect = boxType.aspectRatio
        return aspect >= 1 ? artExtent / aspect : artExtent
    }
    
    private var categoryBadges: [GameCategory] {
        categoryManager.categories(containing: rom)
    }

    // MARK: - 3D Pivoting Effect (mirrors GameCardView)

    private var pivotingEnabled: Bool {
        SystemPreferences.shared.boxArtPivotingEnabled() && !ScrollActivity.isScrolling
    }

    private var normalizedMouseX: CGFloat {
        guard let mp = mousePosition, artFrame.width > 0 else { return 0.5 }
        return min(max((mp.x - artFrame.minX) / artFrame.width, 0), 1)
    }

    private var normalizedMouseY: CGFloat {
        guard let mp = mousePosition, artFrame.height > 0 else { return 0.5 }
        return min(max((mp.y - artFrame.minY) / artFrame.height, 0), 1)
    }

    private let maxTiltAngle: Double = 9
    private let tiltPerspective: CGFloat = 0.5

    private var tiltTargetRotationX: Double {
        (normalizedMouseY - 0.5) * 2 * maxTiltAngle
    }

    private var tiltTargetRotationY: Double {
        (0.5 - normalizedMouseX) * 2 * maxTiltAngle
    }

    private var tiltCombinedAngle: Double {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        let qw = cos(ay / 2) * cos(ax / 2)
        return 2 * acos(min(max(qw, -1), 1)) * 180 / .pi
    }

    private var tiltCombinedAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        var x = cos(ay / 2) * sin(ax / 2)
        var y = sin(ay / 2) * cos(ax / 2)
        var z = -sin(ay / 2) * sin(ax / 2)
        let len = sqrt(x * x + y * y + z * z)
        if len < 1e-6 { return (1, 0, 0) }
        return (x / len, y / len, z / len)
    }
    
    // MARK: - Formatted Playtime
    
    private var formattedPlaytime: String? {
        guard rom.totalPlaytimeSeconds > 0 else { return nil }
        let seconds = rom.totalPlaytimeSeconds
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
    
    private var timesPlayedLabel: String? {
        guard rom.timesPlayed > 0 else { return nil }
        if rom.timesPlayed == 1 {
            return "1 play"
        } else {
            return "\(rom.timesPlayed) plays"
        }
    }

    // MARK: - Formatted HowLongToBeat Main Story

    private var formattedHLTBTime: String? {
        guard let hours = rom.metadata?.hltbMainStoryHours, hours > 0 else { return nil }
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }

    private func summarizedLastPlayed(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        guard interval >= 0 else { return loc.localized("library.stat.justNow") }
        let sec = Int(interval)
        if sec < 60 { return loc.localized("library.stat.justNow") }
        let min = sec / 60
        if min < 60 { return String(format: loc.localized("library.stat.minutes"), min) }
        let hr = min / 60
        if hr < 24 { return String(format: loc.localized("library.stat.hours"), hr) }
        let day = hr / 24
        if day < 7 { return String(format: loc.localized("library.stat.days"), day) }
        let week = day / 7
        if week < 5 { return String(format: loc.localized("library.stat.weeks"), week) }
        let month = day / 30
        if month < 12 { return String(format: loc.localized("library.stat.months"), month) }
        let year = day / 365
        return String(format: loc.localized("library.stat.years"), year)
    }
    
    private var metadataLine1: String? {
        var parts: [String] = []
        if let year = rom.metadata?.year, !year.isEmpty {
            parts.append(year)
        }
        if let dev = rom.metadata?.developer, !dev.isEmpty {
            parts.append(dev)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{2022} ")
    }
    
    private var metadataLine2: String? {
        var parts: [String] = []
        if let genre = rom.metadata?.genre, !genre.isEmpty {
            parts.append(GenreManager.shared.effectiveDisplayName(for: genre))
        }
        if let players = rom.metadata?.players, players > 0 {
            parts.append(players == 1 ? "1 player" : "\(players) players")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{2022} ")
    }

    var body: some View {
        rowRoot
            .contentShape(Rectangle())
            .onTapGesture { actions.onTap(rom, index) }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { _ in actions.onLaunch(rom) }
            )
            .contextMenu { LibraryGridView.LazyContextMenuContent(build: { actions.onContextMenu(rom) }) }
            .overlay {
                if gamepadNav.activeZone == .content && gamepadNav.contentIndex == index {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppColors.brandAccent, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .onDrag {
                let items = actions.dragItemsFor(rom, isSelected)
                actions.onDragStarted(items)
                return NSItemProvider(object: NSString(string: items.map { $0.id.uuidString }.joined(separator: ",")))
            } preview: {
                DragPreviewStack(
                    mainROM: rom,
                    mainImage: nil,
                    draggedROMs: actions.dragItemsFor(rom, isSelected).filter { $0.id != rom.id },
                    zoomLevel: zoomLevel
                )
            }
    }

    private var rowRoot: some View {
        return HStack(spacing: 12) {
            artThumb
            
            // Left side: game info
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rom.displayName)
                        .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    
                    if let systemID = rom.systemID, systemID != "unknown", showSystemLabel {
                        Text(systemID.uppercased())
                            .font(.system(size: subtitleFontSize * 0.8, weight: .regular, design: .rounded))
                            .foregroundColor(AppColors.textMuted(colorScheme))
                            .lineLimit(1)
                    }
                }
                
                // System name
                if let sys = SystemDatabase.system(forID: rom.systemID ?? "") {
                    HStack(spacing: 4) {
                        if let emuImg = sys.emuImage(size: 132) {
                            Image(nsImage: emuImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                        }
Text(sys.name)
                        .font(.system(size: subtitleFontSize))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                }
                
                // Category badges
                if !categoryBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(categoryBadges) { category in
                                CategoryBadgeView(category: category)
                            }
                        }
                    }
                }
                
                // Metadata: Year/Developer
                if let line1 = metadataLine1 {
                    Text(line1)
                        .font(.system(size: subtitleFontSize - 1))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.8))
                }
                
                // Metadata: Genre/Players
                if let line2 = metadataLine2 {
                    Text(line2)
                        .font(.system(size: subtitleFontSize - 1))
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.8))
                }
            }
            
            Spacer()
            
            // Right side: stats column
            VStack(alignment: .trailing, spacing: 4) {
                // Playtime
                if let playtime = formattedPlaytime {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: subtitleFontSize - 0.5))
                        if isHovered {
                            Text(loc.localized("library.stat.time"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(playtime)
                            .font(.system(size: subtitleFontSize))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }

                // Times played
                if let timesPlayed = timesPlayedLabel {
                    HStack(spacing: 3) {
                        if isHovered {
                            Text(loc.localized("library.stat.plays"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(timesPlayed)
                            .font(.system(size: subtitleFontSize))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                    }
                }

                // Last played
                if let played = rom.lastPlayed {
                    HStack(spacing: 3) {
                        if isHovered {
                            Text(loc.localized("library.stat.lastPlayed"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(summarizedLastPlayed(played))
                            .font(.system(size: subtitleFontSize - 0.5))
                            .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                    }
                }

                // RetroAchievements
                if raEnabled && rom.raMatchStatus == "matched" {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: subtitleFontSize - 0.5))
                        if isHovered {
                            Text(loc.localized("library.stat.achievements"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.brandAccent.opacity(0.8))
                        }
                        if let progress = raProgress {
                            Text("\(progress.earned)/\(progress.total)")
                                .font(.system(size: subtitleFontSize))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(AppColors.brandAccent)
                }

                // HowLongToBeat Main Story
                if let hltb = formattedHLTBTime {
                    HStack(spacing: 3) {
                        Image(systemName: "hourglass")
                            .font(.system(size: subtitleFontSize - 0.5))
                        if isHovered {
                            Text(loc.localized("library.stat.hltb"))
                                .font(.system(size: subtitleFontSize - 1))
                                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme).opacity(0.7))
                        }
                        Text(hltb)
                            .font(.system(size: subtitleFontSize))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }

                // Favorite indicator
                    if rom.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.pink)
                            .font(.system(size: subtitleFontSize))
                    }
                }

            if isHovered {
                ZStack {
                    Circle()
                        .fill(AppColors.brandAccent)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                }
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: AppColors.brandAccent.opacity(0.4), radius: 4, y: 2)
                .opacity(0.7)
                .overlay(
                    Menu { LibraryGridView.LazyContextMenuContent(build: { actions.onContextMenu(rom) }) } label: {
                        Color.clear
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.vertical, 4)
        .coordinateSpace(name: "gameListRow")
        .background(
            Rectangle()
            .fill(isEvenRow ? AppColors.cardBackground(colorScheme) : .clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? AppColors.accentBackground(colorScheme) :
                  isHovered ? AppColors.brandAccentSecondary.opacity(0.04) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppColors.brandAccentSecondary.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColors.brandAccentSecondary.opacity(0.2))
                .frame(width: 2, height: 20)
                .padding(.leading, 4)
        }
        .onHover { hovering in
            if ScrollActivity.isScrolling {
                if !hovering { isHovered = false }
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
        .onContinuousHover { phase in
            guard pivotingEnabled else { return }
            switch phase {
            case .active(let location):
                mousePosition = location
                withAnimation(AppMotion.tilt) {
                    tiltRotationX = tiltTargetRotationX
                    tiltRotationY = tiltTargetRotationY
                }
            case .ended:
                mousePosition = nil
                withAnimation(AppMotion.tilt) {
                    tiltRotationX = 0
                    tiltRotationY = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryScrollActivityChanged)) { _ in
            if ScrollActivity.isScrolling {
                isHovered = false
                mousePosition = nil
                tiltRotationX = 0
                tiltRotationY = 0
            }
        }
        .task(id: ArtTaskID(romID: rom.id, artVersion: boxArtVersion, hasBoxArt: rom.hasBoxArt)) {
            // rom.boxArtLocalPath is authoritative and rom.hasBoxArt is correct
            // (resolved during the off-scroll pipeline), so this is zero
            // main-thread I/O. Art-less ROMs show the system placeholder.
            if rom.hasBoxArt {
                let artPath = rom.boxArtLocalPath
                // NSCache-only fast path (zero disk I/O / decode on main); the
                // async loader fills cold entries. thumbnailSync's synchronous
                // disk fallback stalled scrolling here the same way it did in
                // the holo grid before it switched to this API.
                if let cached = ImageCache.shared.thumbnailCachedOrPregen(for: artPath, preferredSize: .small) {
                    self.thumb = cached
                } else if let thumb = await ImageCache.shared.thumbnail(for: artPath, preferredSize: .small) {
                    self.thumb = thumb
                }
            } else {
                self.thumb = nil
            }

            if let raGameId = rom.raGameId, raGameId > 0, rom.raMatchStatus == "matched" {
                raProgress = RetroAchievementsService.cachedAchievementProgress(for: raGameId)
            }
        }
    }

    private var artThumb: some View {
        Group {
            if let img = thumb {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                let sys = SystemDatabase.system(forID: rom.systemID ?? "")
                if let emuImg = sys?.emuImage(size: 132) {
                    Image(nsImage: emuImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: sys?.iconName ?? "gamecontroller")
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.cardBackgroundSubtle(colorScheme))
                }
            }
        }
        .frame(width: thumb != nil ? thumbWidth : min(thumbWidth, thumbHeight), height: thumb != nil ? thumbHeight : min(thumbWidth, thumbHeight))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .shadow(color: AppColors.brandAccent.opacity(0.12), radius: 3, x: 0, y: 1)
        // 3D pivoting effect — only the art pivots, text stays flat
        .rotation3DEffect(
            .degrees(pivotingEnabled && isHovered ? tiltCombinedAngle : 0),
            axis: tiltCombinedAxis,
            anchor: .center,
            perspective: tiltPerspective
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { artFrame = geo.frame(in: .named("gameListRow")) }
                    .onChange(of: geo.frame(in: .named("gameListRow"))) { _, new in artFrame = new }
            }
        )
        .overlay(alignment: .center) {
            if isHovered {
                GlassOrbPlayButton(
                    content: {
                        if let nsImage = thumb {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.secondary.opacity(0.3)
                        }
                    },
                    accent: AppColors.brandAccent,
                    action: { actions.onLaunch(rom) },
                    diameter: min(thumbWidth, thumbHeight) * 0.5
                )
                .transition(.opacity)
                .accessibilityLabel(Text("Launch " + rom.displayName))
            }
        }
    }
}

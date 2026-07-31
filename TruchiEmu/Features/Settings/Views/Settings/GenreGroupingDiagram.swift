import SwiftUI

/// A lateral three-tier hierarchical chart that visualises how the three
/// `GenreGrouping` presets collapse raw metadata into broader display names.
///
/// Tier 1 (Broad)      — `.minimal`:   few top-level groups (Action, RPG, Sports).
/// Tier 2 (Sub-genre)  — `.detailed`:  mid-level groups (Shoot 'em Up, Run and Gun, ...).
/// Tier 3 (Original)   — `.raw`:       unmodified metadata strings.
///
/// The model is an explicit parent-child tree, so every connector line links a
/// node only to its own children — there is no node-to-node mesh. Connector
/// paths are orthogonal S-curves (horizontal stub → vertical trunk → horizontal
/// stub), the standard org-chart shape that makes the branching legible.
///
/// The column matching the currently selected `GenreGrouping` is highlighted
/// with the active theme accent; the other two columns render muted.
struct GenreGroupingDiagram: View {
    let grouping: GenreGrouping

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    // MARK: - Tree model

    /// A node in the diagram. `childIndices` references positions in the next
    /// tier, so a connector is drawn only between a parent and its own children.
    private struct Node: Identifiable, Hashable {
        let id: Int                  // index within its tier
        let title: String            // genre name (proper noun, shown verbatim)
        let mergedCount: Int?        // Tier 1 / 2: how many raw genres collapse here
        let examples: [String]       // Tier 2 / 3: example raw strings
        let childIndices: [Int]      // indices into the next tier (its own children)
    }

    private let tier1: [Node] = [
        Node(id: 0, title: "Action", mergedCount: 6, examples: [],
             childIndices: [0, 1]),
        Node(id: 1, title: "RPG", mergedCount: 5, examples: [],
             childIndices: [2]),
        Node(id: 2, title: "Sports", mergedCount: 10, examples: [],
             childIndices: [3, 4])
    ]

    private let tier2: [Node] = [
        Node(id: 0, title: "Shoot 'em Up", mergedCount: 8,
             examples: ["Flying Vertical", "Flying Horizontal"],
             childIndices: [0, 1]),
        Node(id: 1, title: "Run and Gun", mergedCount: 3,
             examples: ["Commando", "Walking"],
             childIndices: [2, 3]),
        Node(id: 2, title: "Action RPG", mergedCount: 2,
             examples: ["Role-playing (RPG)"],
             childIndices: [4, 5]),
        Node(id: 3, title: "Racing", mergedCount: 6,
             examples: ["Driving", "Race Track"],
             childIndices: [6, 7]),
        Node(id: 4, title: "Team Sports", mergedCount: 5,
             examples: ["Soccer", "Football"],
             childIndices: [8])
    ]

    private let tier3: [Node] = [
        // Shoot 'em Up children
        Node(id: 0, title: "Shooter / Flying Vertical",
             mergedCount: nil, examples: [], childIndices: []),
        Node(id: 1, title: "Shooter / Flying Horizontal",
             mergedCount: nil, examples: [], childIndices: []),
        // Run and Gun children
        Node(id: 2, title: "Shooter / Walking",
             mergedCount: nil, examples: [], childIndices: []),
        Node(id: 3, title: "Shooter / Commando",
             mergedCount: nil, examples: [], childIndices: []),
        // Action RPG children
        Node(id: 4, title: "Action RPG",
             mergedCount: nil, examples: [], childIndices: []),
        Node(id: 5, title: "Role-playing (RPG)",
             mergedCount: nil, examples: [], childIndices: []),
        // Racing children
        Node(id: 6, title: "Driving",
             mergedCount: nil, examples: [], childIndices: []),
        Node(id: 7, title: "Race Track",
             mergedCount: nil, examples: [], childIndices: []),
        // Team Sports children
        Node(id: 8, title: "Sports / Soccer",
             mergedCount: nil, examples: [], childIndices: []),
    ]

    private var tierData: [(GenreGrouping, String, [Node])] {
        [
            (.minimal,  "genre.grouping.minimal.label",  tier1),
            (.detailed, "genre.grouping.detailed.label", tier2),
            (.raw,      "genre.grouping.raw.label",      tier3)
        ]
    }

    // MARK: - Body

    var body: some View {
        Canvas { ctx, size in
            drawBackground(ctx: ctx, size: size)
            drawConnectorsTier(ctx: ctx, size: size, parentTierIdx: 0)
            drawConnectorsTier(ctx: ctx, size: size, parentTierIdx: 1)
            drawNodes(ctx: ctx, size: size)
            drawHeaders(ctx: ctx, size: size)
        }
        .frame(height: diagramHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("genre.grouping.title"))
        .accessibilityValue(Text("genre.grouping.\(grouping.rawValue).label"))
    }

    // MARK: - Geometry

    private let headerHeight: CGFloat = 18
    private let topPadding: CGFloat = 24
    private let bottomPadding: CGFloat = 8
    private let nodeHeight: CGFloat = 26
    private let nodeGap: CGFloat = 6
    private let connectorStub: CGFloat = 14

    private var diagramHeight: CGFloat {
        let h = headerHeight + topPadding
              + CGFloat(tier3.count) * nodeHeight
              + CGFloat(max(0, tier3.count - 1)) * nodeGap
              + bottomPadding
        return max(h, 168)
    }

    private func columnX(_ size: CGSize, _ index: Int) -> CGFloat {
        let colWidth = size.width / CGFloat(tierData.count)
        return colWidth * (CGFloat(index) + 0.5)
    }

    private func nodeY(for index: Int, total: Int, size: CGFloat) -> CGFloat {
        let totalH = CGFloat(total) * nodeHeight + CGFloat(max(0, total - 1)) * nodeGap
        let contentTop = headerHeight + topPadding
        let available = size - contentTop - bottomPadding
        let startY = totalH >= available
            ? contentTop
            : contentTop + (available - totalH) / 2
        return startY + CGFloat(index) * (nodeHeight + nodeGap) + nodeHeight / 2
    }

    private func nodeWidth(_ size: CGSize) -> CGFloat {
        let colWidth = size.width / CGFloat(tierData.count)
        return min(colWidth - 18, 160)
    }

    // MARK: - Drawing: background

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        let bg = ThemeManager.shared.tintedSurfacesEnabled
            ? AppColors.cardBackground(colorScheme)
            : Color(.controlBackgroundColor)
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(bg))
    }

    // MARK: - Drawing: headers

    private func drawHeaders(ctx: GraphicsContext, size: CGSize) {
        for (i, (column, headerKey, _)) in tierData.enumerated() {
            let active = isActive(column)
            let title = loc.localized(headerKey)
            let headerColor: Color = active
                ? AppColors.accentForScheme(colorScheme)
                : AppColors.textTertiary(colorScheme)
            let headerView = Text(verbatim: title)
                .font(.caption2.weight(.bold))
                .foregroundColor(headerColor)
            ctx.draw(
                headerView,
                at: CGPoint(x: columnX(size, i), y: headerHeight / 2 + 6),
                anchor: .center
            )
        }
    }

    // MARK: - Drawing: connectors (parent → own children only, orthogonal S)

    /// Draw every connector that leaves tier `parentTierIdx`.
    /// Each parent node fans out to its own `childIndices` in the next tier.
    private func drawConnectorsTier(ctx: GraphicsContext, size: CGSize,
                                    parentTierIdx: Int) {
        let activeCol = activeColumn()
        let accent = AppColors.accentForScheme(colorScheme)
        let muted = AppColors.textTertiary(colorScheme)
        let (_, _, parents) = tierData[parentTierIdx]
        let (_, _, children) = tierData[parentTierIdx + 1]
        let parentTotal = parents.count
        let childTotal = children.count

        let parentRightX = columnX(size, parentTierIdx) + nodeWidth(size) / 2
        let childLeftX = columnX(size, parentTierIdx + 1) - nodeWidth(size) / 2
        let midX = (parentRightX + childLeftX) / 2

        for parent in parents {
            let pY = nodeY(for: parent.id, total: parentTotal, size: size.height)
            let branchActive = activeCol == parentTierIdx || activeCol == parentTierIdx + 1
            let lineColor: Color = branchActive
                ? accent.opacity(0.55)
                : muted.opacity(0.30)
            let lineWidth: CGFloat = branchActive ? 1.4 : 1

            // Trunk start: short horizontal stub from the parent's right edge,
            // then drop/rise to each child's Y level at midX, then stub into child.
            let trunkStart = CGPoint(x: parentRightX, y: pY)
            let trunkElbow = CGPoint(x: midX, y: pY)

            for childIdx in parent.childIndices {
                guard childIdx < childTotal else { continue }
                let cY = nodeY(for: childIdx, total: childTotal, size: size.height)
                let childElbow = CGPoint(x: midX, y: cY)
                let childStart = CGPoint(x: childLeftX, y: cY)

                var path = Path()
                path.move(to: trunkStart)
                path.addLine(to: trunkElbow)   // parent stub
                path.addLine(to: childElbow)   // vertical trunk segment
                path.addLine(to: childStart)   // child stub
                ctx.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
    }

    // MARK: - Drawing: nodes

    private func drawNodes(ctx: GraphicsContext, size: CGSize) {
        for (i, (column, _, nodes)) in tierData.enumerated() {
            let active = isActive(column)
            let accent = AppColors.accentForScheme(colorScheme)
            let w = nodeWidth(size)
            let cx = columnX(size, i)

            for node in nodes {
                let cy = nodeY(for: node.id, total: nodes.count, size: size.height)
                let rect = CGRect(x: cx - w / 2, y: cy - nodeHeight / 2,
                                  width: w, height: nodeHeight)
                let shape = Path(roundedRect: rect, cornerRadius: 6)

                let fill: Color = active
                    ? accent.opacity(0.18)
                    : Color.gray.opacity(0.08)
                ctx.fill(shape, with: .color(fill))

                let border: Color = active
                    ? accent
                    : AppColors.textTertiary(colorScheme).opacity(0.5)
                ctx.stroke(shape, with: .color(border), lineWidth: active ? 1.5 : 1)

                drawNodeText(ctx: ctx, node: node, rect: rect, active: active)
            }
        }
    }

    private func drawNodeText(ctx: GraphicsContext, node: Node,
                              rect: CGRect, active: Bool) {
        let titleColor: Color = active
            ? AppColors.textPrimary(colorScheme)
            : AppColors.textSecondary(colorScheme)
        let subColor: Color = active
            ? AppColors.accentForScheme(colorScheme)
            : AppColors.textTertiary(colorScheme)

        let titleView = Text(verbatim: node.title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(titleColor)

        if let subtitle = subtitle(for: node) {
            let subView = Text(verbatim: subtitle)
                .font(.system(size: 8))
                .foregroundColor(subColor)
            ctx.draw(titleView, at: CGPoint(x: rect.midX, y: rect.minY + 9),
                     anchor: .center)
            ctx.draw(subView, at: CGPoint(x: rect.midX, y: rect.maxY - 8),
                     anchor: .center)
        } else {
            ctx.draw(titleView, at: CGPoint(x: rect.midX, y: rect.midY),
                     anchor: .center)
        }
    }

    /// Localized subtitle string for a node. Tier 1/2 show "N genres merged";
    /// tier 3 shows nothing (leaves are the raw strings themselves).
    private func subtitle(for node: Node) -> String? {
        if let count = node.mergedCount {
            return loc.localized("genre.grouping.diagram.merged", count)
        }
        if !node.examples.isEmpty {
            let joined = node.examples.joined(separator: ", ")
            return loc.localized("genre.grouping.diagram.example", joined)
        }
        return nil
    }

    // MARK: - Selection

    private func activeColumn() -> Int {
        switch grouping {
        case .minimal: return 0
        case .detailed: return 1
        case .raw:     return 2
        case .custom:  return 1
        }
    }

    private func isActive(_ column: GenreGrouping) -> Bool {
        switch grouping {
        case .custom:
            return column == .detailed
        default:
            return column == grouping
        }
    }
}

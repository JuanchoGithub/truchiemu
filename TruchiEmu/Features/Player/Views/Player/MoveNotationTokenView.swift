import SwiftUI
import AppKit

struct MoveNotationTokenView: View {
    let token: NotationToken
    var isHighlighted: Bool = false
    var compact: Bool = false

    private var nsImage: NSImage {
        switch token {
        case .buttonKeyLabel(let btnType, let keyLabel):
            return NotationTokenImageCache.shared.image(for: .button(btnType), highlighted: isHighlighted, compact: compact, keyLabel: keyLabel)
        default:
            return NotationTokenImageCache.shared.image(for: token, highlighted: isHighlighted, compact: compact)
        }
    }

    var body: some View {
        Image(nsImage: nsImage)
    }
}

struct MoveNotationTokenRow: View {
    let tokens: [NotationToken]
    var matchedStepCount: Int = 0
    var compact: Bool = false

    var body: some View {
        let stepMap = buildStepToTokenMap()
        HStack(spacing: NotationMetrics.tokenSpacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                let stepIdx = stepMap[index]
                let isHighlighted = stepIdx != nil && stepIdx! < matchedStepCount

                MoveNotationTokenView(
                    token: token,
                    isHighlighted: isHighlighted && matchedStepCount > 0,
                    compact: compact
                )
            }
        }
    }

    private func buildStepToTokenMap() -> [Int: Int] {
        var map: [Int: Int] = [:]
        var stepIdx = 0
        for (tokenIdx, token) in tokens.enumerated() {
            switch token {
            case .direction, .motion, .button, .buttonKeyLabel:
                map[tokenIdx] = stepIdx
                stepIdx += 1
            case .separator, .wait, .air, .charge, .holdButton, .rapidPress, .hitLevel, .alternative, .motion360, .standClose:
                break
            }
        }
        return map
    }
}

import Foundation

struct InputParser {
    private static let directionMap: [String: Int] = [
        "_1": 1, "_2": 2, "_3": 3,
        "_4": 4, "_5": 5, "_6": 6,
        "_7": 7, "_8": 8, "_9": 9,
    ]

    private static let chargeDirectionMap: [String: Int] = [
        "^1": 1, "^2": 2, "^3": 3,
        "^4": 4, "^6": 6,
        "^7": 7, "^8": 8, "^9": 9,
    ]

    static func parse(_ input: String) -> [[ParsedStep]] {
        let alternatives = input.components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if shouldCrossProduct(alternatives) {
            return expandCrossProduct(alternatives)
        }

        return alternatives.map { parseAlternative($0) }
    }

    /// Detects the cross-product pattern: direction-only and button-only
    /// parts are combined into all possible direction × button combinations.
    /// E.g., `_4 / _6_+^F / ^G` → 4 inputs: ←+MP, ←+HP, →+MP, →+HP
    private static func shouldCrossProduct(_ parts: [String]) -> Bool {
        guard parts.count >= 2 else { return false }
        guard !parts.contains(where: { $0.contains(", ") }) else { return false }

        let sequences = parts.map { parseAlternative($0) }

        var hasDirectionOnly = false
        var hasButtons = false

        for seq in sequences {
            let hasDir = seq.contains(where: { $0.direction != nil })
            let hasBtn = seq.contains(where: { !$0.buttons.isEmpty })
            if hasDir && !hasBtn { hasDirectionOnly = true }
            if hasBtn { hasButtons = true }
        }

        return hasDirectionOnly && hasButtons
    }

    /// Expands direction sequences × button sets into all combinations.
    private static func expandCrossProduct(_ parts: [String]) -> [[ParsedStep]] {
        let sequences = parts.map { parseAlternative($0) }

        var directionSequences: [[ParsedStep]] = []
        var buttonSets: [[String]] = []

        for seq in sequences {
            let hasDir = seq.contains(where: { $0.direction != nil })
            let hasBtn = seq.contains(where: { !$0.buttons.isEmpty })

            if hasDir {
                let dirOnly = seq.map { step -> ParsedStep in
                    ParsedStep(direction: step.direction, buttons: [], isCharge: step.isCharge, isHold: step.isHold, isRelease: step.isRelease, isRapid: false, isAirStep: step.isAirStep)
                }
                if !directionSequences.contains(dirOnly) {
                    directionSequences.append(dirOnly)
                }
            }

            if hasBtn {
                let btns = seq.flatMap { $0.buttons }
                if !btns.isEmpty && !buttonSets.contains(btns) {
                    buttonSets.append(btns)
                }
            }
        }

        guard !directionSequences.isEmpty, !buttonSets.isEmpty else {
            return sequences
        }

        var result: [[ParsedStep]] = []
        for dirSeq in directionSequences {
            for btns in buttonSets {
                var newSeq = dirSeq
                if !newSeq.isEmpty {
                    let last = newSeq[newSeq.count - 1]
                newSeq[newSeq.count - 1] = ParsedStep(
                    direction: last.direction,
                    buttons: btns,
                    isCharge: last.isCharge,
                    isHold: last.isHold,
                    isRelease: last.isRelease,
                    isRapid: false,
                    isAirStep: last.isAirStep
                )
                }
                result.append(newSeq)
            }
        }

        return result
    }

    private static func parseAlternative(_ input: String) -> [ParsedStep] {
        var steps: [ParsedStep] = []
        var currentDirection: Int?
        var currentButtons: [String] = []
        var isCharge = false
        var isHold = false
        var isRelease = false
        var isAir = false
        var isRapid = false
        var i = input.startIndex

        while i < input.endIndex {
            let remaining = String(input[i...])

            if remaining.hasPrefix("_O") {
                flushStep()
                isCharge = true
                i = input.index(i, offsetBy: 2)
                continue
            }

            if remaining.hasPrefix("_^") {
                isAir = true
                i = input.index(i, offsetBy: 2)
                continue
            }

        if remaining.hasPrefix("_X") {
            isRapid = true
            i = input.index(i, offsetBy: 2)
            continue
        }

            if remaining.hasPrefix("_(") {
                let closeParen = input[i...].firstIndex(of: ")") ?? input.endIndex
                i = input.index(after: closeParen)
                continue
            }

            if let (dir, len) = matchChargeDirection(remaining) {
                flushStep()
                currentDirection = dir
                isCharge = true
                i = input.index(i, offsetBy: len)
                continue
            }

            if let (dir, len) = matchDirection(remaining) {
                flushStep()
                currentDirection = dir
                i = input.index(i, offsetBy: len)
                continue
            }

            if let (key, len) = matchButton(remaining) {
                currentButtons.append(key)
                i = input.index(i, offsetBy: len)
                continue
            }

            if remaining.hasPrefix("_+") {
                i = input.index(i, offsetBy: 2)
                continue
            }

            if remaining.first == "+" {
                i = input.index(after: i)
                continue
            }

            if remaining.first == " " {
                flushStep()
                i = input.index(after: i)
                continue
            }

            if remaining.hasPrefix("_>") {
                flushStep()
                isRelease = true
                flushStep()
                isRelease = false
                i = input.index(i, offsetBy: 2)
                continue
            }

            if remaining.hasPrefix("_!") || remaining.hasPrefix("_#") || remaining.hasPrefix("_?") {
                currentButtons.append(String(input[i..<input.index(i, offsetBy: 2)]))
                i = input.index(i, offsetBy: 2)
                continue
            }

            if remaining.hasPrefix("@") {
                let endIdx = input[i...].firstIndex(where: { $0.isWhitespace || $0 == "+" }) ?? input.endIndex
                currentButtons.append(String(input[i..<endIdx]))
                i = endIdx
                continue
            }

            if remaining.first == "~" {
            flushStep()
            i = input.index(after: i)
            continue
        }

            if remaining.hasPrefix("^*") {
                isRapid = true
                i = input.index(i, offsetBy: 2)
                continue
            }

            if remaining.hasPrefix("^") {
                let nextIdx = input.index(after: i)
                if nextIdx < input.endIndex {
                    let twoChar = String(input[i..<input.index(after: nextIdx)])
                    if let dir = chargeDirectionMap[twoChar] {
                        flushStep()
                        currentDirection = dir
                        isCharge = true
                        i = input.index(after: nextIdx)
                        continue
                    }
                }
                let afterCaret = input.index(after: i)
                var endIdx = input.index(after: afterCaret)
                while endIdx < input.endIndex {
                    let c = input[endIdx]
                    if c.isLetter || c.isNumber || c == "#" {
                        endIdx = input.index(after: endIdx)
                    } else {
                        break
                    }
                }
                currentButtons.append(String(input[i..<endIdx]))
                i = endIdx
                continue
            }

            i = input.index(after: i)
        }

        flushStep()

        if isAir, !steps.isEmpty {
            let airStep = ParsedStep(direction: 8, buttons: [], isCharge: false, isHold: false, isRelease: false, isRapid: false, isAirStep: true)
            steps.insert(airStep, at: 0)
        }

        return steps

        func flushStep() {
            if currentDirection != nil || !currentButtons.isEmpty || isCharge || isHold || isRelease || isRapid {
            steps.append(ParsedStep(
                direction: currentDirection,
                buttons: currentButtons,
                isCharge: isCharge,
                isHold: isHold,
                isRelease: isRelease,
                isRapid: isRapid,
                isAirStep: false
            ))
                currentDirection = nil
                currentButtons = []
                isCharge = false
                isHold = false
                isRelease = false
                isRapid = false
            }
        }
    }

    private static func matchDirection(_ remaining: String) -> (Int, Int)? {
        for (key, dir) in directionMap where remaining.hasPrefix(key) {
            return (dir, key.count)
        }
        return nil
    }

    private static func matchChargeDirection(_ remaining: String) -> (Int, Int)? {
        for (key, dir) in chargeDirectionMap where remaining.hasPrefix(key) {
            return (dir, key.count)
        }
        return nil
    }

    private static func matchButton(_ remaining: String) -> (String, Int)? {
        guard remaining.hasPrefix("_") else { return nil }
        let afterUnderscore = remaining.index(after: remaining.startIndex)
        guard afterUnderscore < remaining.endIndex else { return nil }
        let nextChar = remaining[afterUnderscore]

        if nextChar.isLetter || nextChar.isNumber {
            var endIdx = remaining.index(after: afterUnderscore)
            while endIdx < remaining.endIndex {
                let c = remaining[endIdx]
                if c.isLetter || c.isNumber || c == "#" || c == "c" || c == "j" || c == "P" {
                    endIdx = remaining.index(after: endIdx)
                } else {
                    break
                }
            }
            let key = String(remaining[remaining.startIndex..<endIdx])
            return (key, key.count)
        }

        if "^#?!>".contains(nextChar) {
            let key = String(remaining.prefix(2))
            return (key, 2)
        }

        return nil
    }
}

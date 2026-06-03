import Foundation

enum MoveNotationRenderer {

    static func renderSteps(
        _ sequences: [[ParsedStep]],
        hitLevels: [HitLevel]? = nil,
        controls: [String: String] = [:],
        controlAbbr: [String: String] = [:],
        controlGroups: [String: [String]] = [:]
    ) -> [NotationToken] {
        var tokens: [NotationToken] = []
        let hitLevelList = hitLevels ?? []

        for (seqIndex, sequence) in sequences.enumerated() {
            if seqIndex > 0 {
                tokens.append(.alternative)
            }

        for (stepIndex, step) in sequence.enumerated() {
            if step.isAirStep {
                tokens.append(.air)
            } else if step.isCharge, let dirVal = step.direction, let dir = FightDataDirection(rawValue: dirVal) {
                tokens.append(.charge(dir))
            } else if let dirVal = step.direction, let dir = FightDataDirection(rawValue: dirVal) {
                tokens.append(.direction(dir))
            }

                if !step.buttons.isEmpty {
                    for (i, key) in step.buttons.enumerated() {
                        if i > 0 { tokens.append(.separator) }
                        tokens.append(mapButtonToToken(key, controls: controls, controlAbbr: controlAbbr, controlGroups: controlGroups))
                    }
                }

                if step.isRapid {
                    tokens.append(.rapidPress)
                }

                if step.isHold {
                    tokens.append(.holdButton)
                }

                if seqIndex == 0, stepIndex < hitLevelList.count, hitLevelList[stepIndex] != .none {
                    tokens.append(.hitLevel(hitLevelList[stepIndex]))
                }
            }
        }

        return tokens
    }

    static func mapButtonToToken(
        _ key: String,
        controls: [String: String] = [:],
        controlAbbr: [String: String] = [:],
        controlGroups: [String: [String]] = [:]
    ) -> NotationToken {
        let label = controls[key] ?? controlAbbr[key] ?? key

        let isPunchGroupKey = controlGroups["_P"]?.contains(key) == true
        let isKickGroupKey = controlGroups["_K"]?.contains(key) == true

        if isPunchGroupKey {
            let strength = resolveButtonStrength(key, inGroup: controlGroups["_P"])
            return .button(.punch(strength: strength))
        }
        if isKickGroupKey {
            let strength = resolveButtonStrength(key, inGroup: controlGroups["_K"])
            return .button(.kick(strength: strength))
        }

        if controlGroups["_W"]?.contains(key) == true {
            return .button(.weapon(style: .sword))
        }

    let lower = label.lowercased()
    if lower.contains("guard") || lower.contains("block") {
        return .button(.block)
    }
    if lower.contains("throw") || lower.contains("grapple") || lower.contains("hold") || lower.contains("grab") {
        return .button(.grapple)
    }
    if lower.contains("weapon") || lower.contains("sword") || lower.contains("slash") {
        return .button(.weapon(style: .sword))
    }
    if lower.contains("axe") {
        return .button(.weapon(style: .axe))
    }

    let abbrLabel = controlAbbr[key] ?? key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
    if lower.contains("punch") {
        return .button(.punch(strength: .low))
    }
    if lower.contains("kick") {
        return .button(.kick(strength: .low))
    }

    let cleanKey = key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
    if cleanKey == "G" { return .button(.block) }
    if cleanKey == "a" || cleanKey == "b" {
            return .button(.weapon(style: .sword))
        }

        if abbrLabel == "P" || abbrLabel == "p" {
            return .button(.punch(strength: .low))
        }
        if abbrLabel == "K" || abbrLabel == "k" {
            return .button(.kick(strength: .low))
        }

        return .button(.generic(label: abbrLabel))
    }

    static func resolveButtonStrength(_ key: String, inGroup group: [String]?) -> ButtonStrength {
        guard let group, let index = group.firstIndex(of: key) else { return .low }
        switch index {
        case 0: return .low
        case 1: return .medium
        case 2: return .high
        default: return .low
        }
    }
}

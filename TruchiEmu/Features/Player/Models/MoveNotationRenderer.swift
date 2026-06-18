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

        let sequencesToShow: [[ParsedStep]]
        if sequences.count > 2 {
            let seed = sequences.first?.first?.direction.hashValue ?? 0
            var rng = SeededRandomGenerator(seed: seed)
            let count = rng.nextBool() ? 1 : 2
            let grouped = Dictionary(grouping: sequences, by: { $0.first?.direction ?? -1 })
            if grouped.count > 1, count == 2 {
                var picked: [[ParsedStep]] = []
                let keys = grouped.keys.sorted().shuffled(using: &rng)
                for key in keys {
                    let group = grouped[key]!
                    picked.append(group[Int(rng.next() % UInt64(group.count))])
                    if picked.count >= count { break }
                }
                sequencesToShow = picked
            } else {
                sequencesToShow = Array(sequences.shuffled(using: &rng).prefix(count))
            }
        } else {
            sequencesToShow = sequences
        }

        for (seqIndex, sequence) in sequencesToShow.enumerated() {
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

            if step.isMotion360 {
                tokens.append(.motion360)
            }

            if step.isCloseRange {
                tokens.append(.standClose)
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
        let abbrLabel = controlAbbr[key] ?? key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
        let lower = label.lowercased()
        let cleanKey = key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")

    // --- Step 1: Group-key label override ---
    if key == "_x" || key == "_X" {
        if key == "_x" { return .motion360 }
        return .standClose
    }
    // _P/_K/_W keys may have contradictory labels (e.g., _P = "Projectile")
        if key == "_P" || key == "_p" {
            if let groupLabel = controls[key]?.lowercased(),
               !groupLabel.contains("punch"), !groupLabel.contains("attack"),
               !groupLabel.contains("strike"), !groupLabel.contains("blow") {
                return resolveByLabel(lower, abbrLabel: abbrLabel, cleanKey: cleanKey)
            }
            return .button(.punch(strength: .medium))
        }
        if key == "_K" || key == "_k" {
            if let groupLabel = controls[key]?.lowercased(),
               !groupLabel.contains("kick"), !groupLabel.contains("attack"),
               !groupLabel.contains("strike"), !groupLabel.contains("blow") {
                return resolveByLabel(lower, abbrLabel: abbrLabel, cleanKey: cleanKey)
            }
            return .button(.kick(strength: .medium))
        }
        if key == "_W" || key == "_w" {
            if let groupLabel = controls[key]?.lowercased(),
               !groupLabel.contains("weapon"), !groupLabel.contains("sword"),
               !groupLabel.contains("slash"), !groupLabel.contains("axe") {
                return resolveByLabel(lower, abbrLabel: abbrLabel, cleanKey: cleanKey)
            }
            return .button(.weapon(style: .sword))
        }

        // --- Step 2: Label-first for all clear button types ---
        if lower.contains("guard") || lower.contains("block") || lower.contains("dodge") {
            return .button(.block)
        }
        if lower.contains("throw") || lower.contains("grapple") || lower.contains("grab") || lower.contains("suplex") {
            return .button(.grapple)
        }
        if lower.contains("weapon") || lower.contains("sword") || lower.contains("slash") {
            return .button(.weapon(style: .sword))
        }
        if lower.contains("axe") {
            return .button(.weapon(style: .axe))
        }
        if lower.contains("punch") {
            return .button(.punch(strength: resolveLabelStrength(lower)))
        }
        if lower.contains("kick") {
            return .button(.kick(strength: resolveLabelStrength(lower)))
        }

        // --- Step 3: Group membership ---
        if controlGroups["_P"]?.contains(key) == true {
            let grpLabel = controls[key]?.lowercased() ?? ""
            if grpLabel.contains("attack") || grpLabel.contains("strike") || grpLabel.contains("blow") || grpLabel.isEmpty {
                return .button(.punch(strength: resolveButtonStrength(key, inGroup: controlGroups["_P"])))
            }
            return resolveByLabel(grpLabel, abbrLabel: abbrLabel, cleanKey: cleanKey)
        }
        if controlGroups["_K"]?.contains(key) == true {
            let grpLabel = controls[key]?.lowercased() ?? ""
            if grpLabel.contains("attack") || grpLabel.contains("strike") || grpLabel.contains("blow") || grpLabel.isEmpty {
                return .button(.kick(strength: resolveButtonStrength(key, inGroup: controlGroups["_K"])))
            }
            return resolveByLabel(grpLabel, abbrLabel: abbrLabel, cleanKey: cleanKey)
        }
        if controlGroups["_W"]?.contains(key) == true {
            return .button(.weapon(style: .sword))
        }

        // --- Step 4: Safe abbreviation patterns only ---
        if let match = safeAbbrMatch(abbrLabel) {
            return .button(match)
        }

        // --- Step 5: Hardcoded key overrides ---
        if cleanKey == "G" { return .button(.block) }

        // --- Step 6: Fallback ---
        return .button(.generic(label: abbrLabel))
    }

    private static func resolveByLabel(_ lower: String, abbrLabel: String, cleanKey: String) -> NotationToken {
        if lower.contains("guard") || lower.contains("block") || lower.contains("dodge") {
            return .button(.block)
        }
        if lower.contains("throw") || lower.contains("grapple") || lower.contains("grab") || lower.contains("suplex") {
            return .button(.grapple)
        }
        if lower.contains("weapon") || lower.contains("sword") || lower.contains("slash") {
            return .button(.weapon(style: .sword))
        }
        if lower.contains("axe") {
            return .button(.weapon(style: .axe))
        }
        if lower.contains("punch") {
            return .button(.punch(strength: resolveLabelStrength(lower)))
        }
        if lower.contains("kick") {
            return .button(.kick(strength: resolveLabelStrength(lower)))
        }
        if lower.contains("attack") || lower.contains("strike") || lower.contains("blow") {
            if lower.contains("weak") || lower.contains("light") { return .button(.punch(strength: .low)) }
            if lower.contains("strong") || lower.contains("heavy") || lower.contains("powerful") { return .button(.punch(strength: .high)) }
            return .button(.generic(label: abbrLabel))
        }
        if cleanKey == "G" { return .button(.block) }
        return .button(.generic(label: abbrLabel))
    }

    private static func safeAbbrMatch(_ abbr: String) -> ButtonTokenType? {
        let upper = abbr.uppercased()
        switch upper {
        case "LP", "QP":
            return .punch(strength: .low)
        case "MP", "P":
            return .punch(strength: .medium)
        case "HP":
            return .punch(strength: .high)
        case "LK", "QK":
            return .kick(strength: .low)
        case "MK", "K", "MS":
            return .kick(strength: .medium)
        case "HK", "FK", "RK", "SK":
            return .kick(strength: .high)
        case "GR", "TG":
            return .grapple
        default:
            return nil
        }
    }

    private static func resolveLabelStrength(_ lower: String) -> ButtonStrength {
        if lower.contains("weak") || lower.contains("light") || lower.contains("short") || lower.contains("quick") {
            return .low
        }
        if lower.contains("strong") || lower.contains("heavy") || lower.contains("hard") || lower.contains("fierce") {
            return .high
        }
        if lower.contains("medium") || lower.contains("middle") {
            return .medium
        }
        return .medium
    }

    static func resolveButtonType(_ key: String, gameData: FightDataGame?) -> ButtonTokenType {
        if case .button(let type) = mapButtonToToken(
            key,
            controls: gameData?.controls ?? [:],
            controlAbbr: gameData?.controlAbbr ?? [:],
            controlGroups: gameData?.controlGroups ?? [:]
        ) {
            return type
        }
        return .generic(label: key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: ""))
    }

	static func resolveButtonStrength(_ key: String, inGroup group: [String]?) -> ButtonStrength {
		guard let group, let index = group.firstIndex(of: key) else { return .medium }
		if group.count == 1 { return .medium }
		if group.count == 2 {
			switch index {
			case 0: return .low
			case 1: return .high
			default: return .medium
			}
		}
		switch index {
		case 0: return .low
		case 1: return .medium
		case 2: return .high
		default: return .medium
		}
	}
}

private struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1; return state }
    mutating func nextBool() -> Bool { next() & 1 == 1 }
}

private extension Array {
    func shuffled(using rng: inout SeededRandomGenerator) -> [Element] {
        var copy = self
        copy.shuffle(using: &rng)
        return copy
    }
}

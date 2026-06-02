import Foundation

func repairAndDecodeCustomGameJSON(_ jsonString: String) -> (game: FightDataGame, json: String)? {
    guard var gameDict = try? JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? [String: Any] else { return nil }
    var didRepair = false
    if gameDict["year"] is String {
        gameDict["year"] = NSNull()
        didRepair = true
    }
    guard let data = try? JSONSerialization.data(withJSONObject: gameDict, options: [.sortedKeys, .prettyPrinted]),
          let game = try? JSONDecoder().decode(FightDataGame.self, from: data) else { return nil }
    let repairedJson = String(data: data, encoding: .utf8) ?? jsonString
    return (game, didRepair ? repairedJson : jsonString)
}

func buildMoveNotationTokens(_ input: String) -> [NotationToken] {
    let sequences = InputParser.parse(input)
    var tokens: [NotationToken] = []
    for (idx, seq) in sequences.enumerated() {
        if idx > 0 { tokens.append(.alternative) }
        for step in seq {
            if step.direction == 8 && step.buttons.isEmpty && !step.isCharge {
                tokens.append(.air)
                continue
            }
            if let dir = step.direction, let fdDir = FightDataDirection(rawValue: dir) {
                tokens.append(.direction(fdDir))
            }
            for (bi, btn) in step.buttons.enumerated() {
                if bi > 0 { tokens.append(.separator) }
                tokens.append(.button(buttonTokenType(for: btn)))
            }
        }
    }
    return tokens
}

func buttonTokenType(for key: String) -> ButtonTokenType {
    if key == "^E" || key == "^F" || key == "^G" || key == "_P" {
        let strength: ButtonStrength = key == "^E" ? .low : key == "^F" ? .medium : key == "^G" ? .high : .low
        return .punch(strength: strength)
    }
    if key == "^H" || key == "^I" || key == "^J" || key == "_K" {
        let strength: ButtonStrength = key == "^H" ? .low : key == "^I" ? .medium : key == "^J" ? .high : .low
        return .kick(strength: strength)
    }
    if key == "_G" { return .grapple }
    return .generic(label: key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: ""))
}

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

func buildMoveNotationTokens(_ input: String, game: FightDataGame? = nil) -> [NotationToken] {
    let sequences = InputParser.parse(input)
    return MoveNotationRenderer.renderSteps(
        sequences,
        controls: game?.controls ?? [:],
        controlAbbr: game?.controlAbbr ?? [:],
        controlGroups: game?.controlGroups ?? [:]
    )
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
    if key == "_G" { return .block }
    let clean = key.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "_", with: "")
    if clean == "a" || clean == "b" {
        return .weapon(style: .sword)
    }
    if clean == "P" || clean == "p" {
        return .punch(strength: .low)
    }
    if clean == "K" || clean == "k" {
        return .kick(strength: .low)
    }
    return .generic(label: clean)
}

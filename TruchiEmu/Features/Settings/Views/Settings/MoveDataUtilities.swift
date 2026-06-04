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

@MainActor
func buildMoveNotationTokens(_ input: String, game: FightDataGame? = nil) -> [NotationToken] {
	let resolvedGame = game ?? MoveListService.shared.currentGameData
	let sequences = InputParser.parse(input)
	return MoveNotationRenderer.renderSteps(
		sequences,
		controls: resolvedGame?.controls ?? [:],
		controlAbbr: resolvedGame?.controlAbbr ?? [:],
		controlGroups: resolvedGame?.controlGroups ?? [:]
	)
}


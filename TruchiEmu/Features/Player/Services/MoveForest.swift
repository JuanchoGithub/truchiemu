import Foundation

class MoveTreeNode {
    let step: ParsedStep
    var children: [MoveTreeNode] = []
    var passingMoves: [String: Int] = [:]
    var terminalMoves: [String: Int] = [:]

    init(step: ParsedStep) {
        self.step = step
    }
}

class MoveForest {
    private var roots: [MoveTreeNode] = []

    func build(with moves: [ResolvedMove]) {
        roots.removeAll()
        for move in moves {
            for steps in move.parsedSteps {
                guard !steps.isEmpty else { continue }
                insert(steps: steps, moveId: move.id, totalSteps: move.totalSteps)
            }
        }
    }

    private func splitStep(_ step: ParsedStep) -> [ParsedStep] {
        guard step.direction != nil, !step.buttons.isEmpty else { return [step] }

        let dirStep = ParsedStep(
            direction: step.direction,
            buttons: [],
            isCharge: step.isCharge,
            isHold: false,
            isRelease: step.isRelease,
            isRapid: false,
            isAirStep: step.isAirStep,
            isMotion360: step.isMotion360,
            isCloseRange: step.isCloseRange
        )

        let btnStep = ParsedStep(
            direction: nil,
            buttons: step.buttons,
            isCharge: false,
            isHold: step.isHold,
            isRelease: false,
            isRapid: step.isRapid,
            isAirStep: false,
            isMotion360: false,
            isCloseRange: false
        )

        return [dirStep, btnStep]
    }

    private func insert(steps: [ParsedStep], moveId: String, totalSteps: Int) {
        var current: MoveTreeNode?

        for step in steps {
            let subSteps = splitStep(step)
            for subStep in subSteps {
                if current == nil {
                    if let existing = roots.first(where: { $0.step == subStep }) {
                        current = existing
                    } else {
                        let node = MoveTreeNode(step: subStep)
                        roots.append(node)
                        current = node
                    }
                } else {
                    if let child = current?.children.first(where: { $0.step == subStep }) {
                        current = child
                    } else {
                        let node = MoveTreeNode(step: subStep)
                        current?.children.append(node)
                        current = node
                    }
                }
                current?.passingMoves[moveId] = totalSteps
            }
        }

        current?.terminalMoves[moveId] = totalSteps
    }

    func evaluate(
        inputs: [InputSequenceStep],
        controlGroups: [String: [String]]
    ) -> (inProgress: [String: (matched: Int, total: Int)], completed: [String]) {
        guard !inputs.isEmpty, !roots.isEmpty else { return ([:], []) }

        var inProgress: [String: (matched: Int, total: Int)] = [:]
        var completed: [String] = []
        var seenCompleted = Set<String>()

        for startPos in 0..<inputs.count {
            for root in roots {
                guard stepMatches(input: inputs[startPos], step: root.step, controlGroups: controlGroups) else {
                    continue
                }

                var path: [MoveTreeNode] = [root]

                for offset in 1..<(inputs.count - startPos) {
                    let userStep = inputs[startPos + offset]
                    guard let child = path.last!.children.first(where: {
                        stepMatches(input: userStep, step: $0.step, controlGroups: controlGroups)
                    }) else {
                        path = []
                        break
                    }
                    path.append(child)
                }

                guard !path.isEmpty else { continue }

                for (i, node) in path.enumerated() {
                    recordMoves(at: node, depth: i + 1, inProgress: &inProgress)
                }
                checkTerminal(at: path.last!, completed: &completed, seenCompleted: &seenCompleted)
            }
        }

        return (inProgress, completed)
    }

    private func recordMoves(at node: MoveTreeNode, depth: Int, inProgress: inout [String: (matched: Int, total: Int)]) {
        for (moveId, total) in node.passingMoves {
            let current = inProgress[moveId]?.matched ?? 0
            if depth > current {
                inProgress[moveId] = (depth, total)
            }
        }
    }

    private func checkTerminal(at node: MoveTreeNode, completed: inout [String], seenCompleted: inout Set<String>) {
        for (moveId, _) in node.terminalMoves {
            if !seenCompleted.contains(moveId) {
                completed.append(moveId)
                seenCompleted.insert(moveId)
            }
        }
    }

    private func stepMatches(input: InputSequenceStep, step: ParsedStep, controlGroups: [String: [String]]) -> Bool {
        let needsDir = step.direction != nil
        let needsBtns = !step.buttons.isEmpty

        if needsDir {
            guard let userDir = input.direction,
                  let moveDirVal = step.direction,
                  let _ = FightDataDirection(rawValue: moveDirVal) else {
                return false
            }
            if stepDirectionMatches(userDir, moveDirVal) != true {
                return false
            }
        }

        if needsBtns {
            guard !input.buttons.isEmpty else { return false }
            if !buttonSetsMatch(userBtns: input.buttons, moveBtns: step.buttons, controlGroups: controlGroups) {
                return false
            }
        }

        if step.isCharge && !input.isCharge {
            return false
        }

        return true
    }

    private func stepDirectionMatches(_ userDir: FightDataDirection, _ moveDirVal: Int) -> Bool {
        guard let moveDir = FightDataDirection(rawValue: moveDirVal) else { return false }
        if userDir == moveDir { return true }
        switch (userDir, moveDir) {
        case (.up, .down), (.down, .up), (.left, .right), (.right, .left),
            (.upLeft, .downRight), (.downRight, .upLeft),
            (.upRight, .downLeft), (.downLeft, .upRight):
            return false
        default:
            return false
        }
    }

    private func buttonSetsMatch(userBtns: Set<String>, moveBtns: [String], controlGroups: [String: [String]]) -> Bool {
        let userNormalized = Set(userBtns.map { normalizeFightDataKey($0) })

        for moveKey in moveBtns {
            let moveNorm = normalizeFightDataKey(moveKey)
            if userNormalized.contains(moveNorm) {
                return true
            }
            if let members = controlGroups[moveKey] {
                let memberNorms = Set(members.map { normalizeFightDataKey($0) })
                if !userNormalized.isDisjoint(with: memberNorms) {
                    return true
                }
            }
        }

        return false
    }

    private func normalizeFightDataKey(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "^", with: "")
    }
}

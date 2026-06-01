import Foundation

struct FrameExpander {
    private let resolvedSteps: [ResolvedStep]
    private let frameProfile: FrameProfile

    private struct ResolvedStep {
        let directions: Set<RetroButton>
        let buttons: Set<RetroButton>
        let isCharge: Bool
        let isHold: Bool
        let isRelease: Bool
        let isNeutral: Bool
    }

    private static let chargeFrameCount = 48

    @MainActor init(steps: [ParsedStep], frameProfile: FrameProfile, layout: ArcadeLayout, systemID: String, systemControlMappings: [String: [String: String]]?) {
        self.frameProfile = frameProfile
        self.resolvedSteps = steps.map { step in
            let dirs = Self.directionToRetroButtons(step.direction)
            let btns = Self.fightDataKeysToRetroButtons(step.buttons, layout: layout, systemID: systemID, systemControlMappings: systemControlMappings)
            let isNeutral = step.direction == nil && step.buttons.isEmpty && !step.isCharge && !step.isHold && !step.isRelease
            return ResolvedStep(directions: dirs, buttons: btns, isCharge: step.isCharge, isHold: step.isHold, isRelease: step.isRelease, isNeutral: isNeutral)
        }
    }

    func expand() -> [FrameInput] {
        var frames: [FrameInput] = []
        var prevDirections: Set<RetroButton> = []
        var prevButtons: Set<RetroButton> = []

        for step in resolvedSteps {
            if step.isCharge {
                let holdInput = FrameInput(directions: step.directions, buttons: [])
                for _ in 0..<Self.chargeFrameCount {
                    frames.append(holdInput)
                }
                frames.append(FrameInput(directions: [], buttons: []))
                prevDirections = []
                prevButtons = []
                continue
            }

            if step.isRelease {
                prevDirections = []
                prevButtons = []
                frames.append(FrameInput(directions: [], buttons: []))
                continue
            }

            if step.isHold {
                let mergedDirs = prevDirections.union(step.directions)
                let mergedBtns = prevButtons.union(step.buttons)
                let holdInput = FrameInput(directions: mergedDirs, buttons: mergedBtns)
                for _ in 0..<frameProfile.rawValue {
                    frames.append(holdInput)
                }
                prevDirections = mergedDirs
                prevButtons = mergedBtns
                continue
            }

            if step.isNeutral {
                for _ in 0..<frameProfile.rawValue {
                    frames.append(.empty)
                }
                prevDirections = []
                prevButtons = []
                continue
            }

            if !prevDirections.isEmpty || !prevButtons.isEmpty {
                frames.append(.empty)
            }

            let input = FrameInput(directions: step.directions, buttons: step.buttons)
            for _ in 0..<frameProfile.rawValue {
                frames.append(input)
            }
            prevDirections = step.directions
            prevButtons = step.buttons
        }

        if let lastFrame = frames.last, !lastFrame.buttons.isEmpty {
            frames.append(.empty)
        }

        return frames
    }

    private static func directionToRetroButtons(_ dir: Int?) -> Set<RetroButton> {
        guard let dir = dir, let fd = FightDataDirection(rawValue: dir) else { return [] }
        var buttons: Set<RetroButton> = []
        if fd == .up || fd == .upRight || fd == .upLeft { buttons.insert(.up) }
        if fd == .down || fd == .downRight || fd == .downLeft { buttons.insert(.down) }
        if fd == .left || fd == .downLeft || fd == .upLeft { buttons.insert(.left) }
        if fd == .right || fd == .downRight || fd == .upRight { buttons.insert(.right) }
        return buttons
    }

    @MainActor private static func fightDataKeysToRetroButtons(_ keys: [String], layout: ArcadeLayout, systemID: String, systemControlMappings: [String: [String: String]]?) -> Set<RetroButton> {
        var result = Set<RetroButton>()
        for key in keys {
            if let button = ArcadeButtonMapper.shared.retroButton(
                for: key,
                layout: layout,
                systemID: systemID,
                systemControlMappings: systemControlMappings
            ) {
                result.insert(button)
            }
        }
        return result
    }
}

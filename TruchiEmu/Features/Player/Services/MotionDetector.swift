import Foundation

enum DetectedMotion: Equatable {
    case quarterCircle(FightDataDirection)
    case halfCircle(FightDataDirection)
    case fullCircle(direction: FightDataDirection)
}

struct MotionDetector {
    private static let ring: [FightDataDirection] = [
        .up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft
    ]

    static func detect(in raw: [FightDataDirection]) -> [DetectedMotion] {
        guard raw.count >= 3 else { return [] }

        var i = raw.count
        var motions: [DetectedMotion] = []

        while i >= 3 {
            let remaining = i
            if remaining >= 8, let fc = matchFullCircle(raw, i - 8) {
                motions.insert(fc, at: 0)
                i -= 8
            } else if remaining >= 5, let hc = matchHalfCircle(raw, i - 5) {
                motions.insert(hc, at: 0)
                i -= 5
            } else if remaining >= 3, let qc = matchQuarterCircle(raw, i - 3) {
                motions.insert(qc, at: 0)
                i -= 3
            } else {
                break
            }
        }

        return motions
    }

    private static func matchQuarterCircle(_ raw: [FightDataDirection], _ start: Int) -> DetectedMotion? {
        for len in [3] {
            guard start + len <= raw.count else { continue }
            let slice = Array(raw[start..<start+len])
            for offset in 0..<ring.count {
                let cw = (0..<len).map { ring[(offset + $0) % 8] }
                let ccw = (0..<len).map { ring[(offset - $0 + 8) % 8] }
                if slice == cw { return .quarterCircle(.left) }
                if slice == ccw { return .quarterCircle(.down) }
            }
        }
        return nil
    }

    private static func matchHalfCircle(_ raw: [FightDataDirection], _ start: Int) -> DetectedMotion? {
        for len in [5] {
            guard start + len <= raw.count else { continue }
            let slice = Array(raw[start..<start+len])
            for offset in 0..<ring.count {
                let cw = (0..<len).map { ring[(offset + $0) % 8] }
                let ccw = (0..<len).map { ring[(offset - $0 + 8) % 8] }
                if slice == cw { return .halfCircle(.left) }
                if slice == ccw { return .halfCircle(.right) }
            }
        }
        return nil
    }

    private static func matchFullCircle(_ raw: [FightDataDirection], _ start: Int) -> DetectedMotion? {
        for len in [8] {
            guard start + len <= raw.count else { continue }
            let slice = Array(raw[start..<start+len])
            for offset in 0..<ring.count {
                let cw = (0..<len).map { ring[(offset + $0) % 8] }
                let ccw = (0..<len).map { ring[(offset - $0 + 8) % 8] }
                if slice == cw { return .fullCircle(direction: .right) }
                if slice == ccw { return .fullCircle(direction: .left) }
            }
        }
        return nil
    }
}

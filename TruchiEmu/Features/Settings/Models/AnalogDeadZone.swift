import Foundation

struct AnalogDeadZone: Codable {
    var radial: Float
    var anti: Float

    static let `default` = AnalogDeadZone(radial: 0.15, anti: 0.0)

    func apply(_ value: Float) -> Float {
        let absVal = abs(value)
        let sign: Float = value >= 0 ? 1.0 : -1.0
        if absVal < radial {
            return 0.0
        }
        let scaled = (absVal - radial) / (1.0 - radial)
        return sign * min(max(scaled, 0.0), 1.0)
    }
}

import Foundation
import Combine

/// Per-direction analog stick range calibration. Each field stores the maximum
/// raw magnitude the stick reached in that direction (in GC convention where
/// Y-positive is up). A value of 1.0 means "no correction" — the direction
/// already reaches full range. Directions never captured during calibration
/// stay at 0.0 and apply no correction (see `scale` floor).
struct StickCalibration: Codable, Equatable {
    var up: Float = 1.0
    var down: Float = 1.0
    var left: Float = 1.0
    var right: Float = 1.0

    private enum CodingKeys: String, CodingKey {
        case up, down, left, right
    }

    init(up: Float = 1.0, down: Float = 1.0, left: Float = 1.0, right: Float = 1.0) {
        self.up = up
        self.down = down
        self.left = left
        self.right = right
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        up = try container.decodeIfPresent(Float.self, forKey: .up) ?? 1.0
        down = try container.decodeIfPresent(Float.self, forKey: .down) ?? 1.0
        left = try container.decodeIfPresent(Float.self, forKey: .left) ?? 1.0
        right = try container.decodeIfPresent(Float.self, forKey: .right) ?? 1.0
    }

    var isDefault: Bool {
        up == 1.0 && down == 1.0 && left == 1.0 && right == 1.0
    }

    /// Scale a raw value by the max reached in its direction. Maxes at or below
    /// the floor are ignored so a direction never pushed during calibration
    /// does not amplify noise.
    private func scale(_ value: Float, max magnitude: Float) -> Float {
        guard magnitude > 0.05 else { return value }
        let scaled = value / magnitude
        return max(-1.0, min(1.0, scaled))
    }

    /// Apply calibration to a raw `(x, y)` pair in GC convention (Y positive = up).
    func apply(x: Float, y: Float) -> (Float, Float) {
        (applyX(x), applyY(y))
    }

    /// Scale a raw X value (positive = right, negative = left).
    func applyX(_ x: Float) -> Float {
        x >= 0 ? scale(x, max: right) : scale(x, max: left)
    }

    /// Scale a raw Y value (positive = up, negative = down).
    func applyY(_ y: Float) -> Float {
        y >= 0 ? scale(y, max: up) : scale(y, max: down)
    }

    /// Per-direction magnitude scaling for gameplay paths that track each
    /// direction separately (values are already absolute magnitudes).
    func scalingUp(_ value: Float) -> Float { scale(value, max: up) }
    func scalingDown(_ value: Float) -> Float { scale(value, max: down) }
    func scalingLeft(_ value: Float) -> Float { scale(value, max: left) }
    func scalingRight(_ value: Float) -> Float { scale(value, max: right) }
}

/// Calibration for both sticks of one controller. `isDefault` is true when
/// neither stick needs correction.
struct ControllerCalibration: Codable, Equatable {
    var leftStick: StickCalibration = StickCalibration()
    var rightStick: StickCalibration = StickCalibration()

    private enum CodingKeys: String, CodingKey {
        case leftStick, rightStick
    }

    init(leftStick: StickCalibration = StickCalibration(), rightStick: StickCalibration = StickCalibration()) {
        self.leftStick = leftStick
        self.rightStick = rightStick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leftStick = try container.decodeIfPresent(StickCalibration.self, forKey: .leftStick) ?? StickCalibration()
        rightStick = try container.decodeIfPresent(StickCalibration.self, forKey: .rightStick) ?? StickCalibration()
    }

    var isDefault: Bool {
        leftStick.isDefault && rightStick.isDefault
    }
}

/// In-progress calibration capture for one controller. Held while the user
/// rotates the sticks; maxima are recorded live and written to persistence
/// only when the user saves. Uncaptured directions stay 0.0 (no correction
/// when applied) until the user pushes that way.
final class StickCalibrationSession: ObservableObject {
    @Published var isActive = false
    @Published var leftStick = StickCalibration()
    @Published var rightStick = StickCalibration()

    /// Record a raw `(x, y)` sample for one stick, expanding each direction's
    /// max magnitude as needed. Samples below the floor are ignored so resting
    /// jitter does not get captured as a range edge.
    func record(x: Float, y: Float, stick: Int) {
        let ax = abs(x)
        let ay = abs(y)
        let maxes: (inout StickCalibration) -> Void = { cal in
            if ax > 0.05 {
                if x >= 0 {
                    if ax > cal.right { cal.right = ax }
                } else if ax > cal.left {
                    cal.left = ax
                }
            }
            if ay > 0.05 {
                if y >= 0 {
                    if ay > cal.up { cal.up = ay }
                } else if ay > cal.down {
                    cal.down = ay
                }
            }
        }
        if stick == 0 {
            maxes(&leftStick)
        } else {
            maxes(&rightStick)
        }
    }

    func start() {
        isActive = true
        leftStick = StickCalibration(up: 0, down: 0, left: 0, right: 0)
        rightStick = StickCalibration(up: 0, down: 0, left: 0, right: 0)
    }

    func stop() {
        isActive = false
    }
}
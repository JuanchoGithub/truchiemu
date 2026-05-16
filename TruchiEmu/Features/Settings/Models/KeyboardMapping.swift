import Foundation
import Carbon.HIToolbox

struct KeyboardMapping: Codable {
    var buttons: [RetroButton: UInt16]

    static func defaults(for systemID: String, handedness: String = "right") -> KeyboardMapping {
        let isLeftHanded = handedness == "left"
        var base: [RetroButton: UInt16] = [:]

        base[.up] = 126
        base[.down] = 125
        base[.left] = 123
        base[.right] = 124

        base[.start] = 36
        base[.select] = 48

        switch systemID.lowercased() {
        case "nes", "nes_turbo":
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.turboA] = 6
                base[.turboB] = 7
            } else {
                base[.a] = 6
                base[.b] = 7
                base[.turboA] = 8
                base[.turboB] = 9
            }

        case "snes", "sfc":
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }

        case "genesis", "megadrive":
            base[.a] = 6
            base[.b] = 7
            base[.c] = 8
            base[.x] = 12
            base[.y] = 13
            base[.z] = 14

        case "n64":
            base[.a] = 6
            base[.b] = 7
            base[.z] = 14
            base[.l1] = 12
            base[.r1] = 11
            base[.cUp] = 126
            base[.cDown] = 125
            base[.cLeft] = 123
            base[.cRight] = 124

        case "psx", "ps1":
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14
            base[.l2] = 1
            base[.r2] = 3
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }

        case "gba":
            base[.a] = 6
            base[.b] = 7
            base[.l1] = 12
            base[.r1] = 14

        case "gb", "gbc":
            base[.a] = 6
            base[.b] = 7

        case "dreamcast":
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14
            base[.l2] = 1
            base[.r2] = 3

        case "saturn":
            base[.a] = 6
            base[.b] = 7
            base[.c] = 8
            base[.x] = 12
            base[.y] = 13
            base[.z] = 14
            base[.l1] = 1
            base[.r1] = 3

        case "ps2":
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14
            base[.l2] = 1
            base[.r2] = 3
            if isLeftHanded {
                base[.a] = 8
                base[.b] = 9
                base[.x] = 6
                base[.y] = 7
            }

        case "psp":
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14

        case "mame", "fba", "arcade":
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14
            base[.coin1] = 15
            base[.start1] = 17
            base[.coin2] = 16
            base[.start2] = 32

        case "dos":
            base[.a] = 0
            base[.b] = 11
            base[.c] = 8
            base[.x] = 7
            base[.y] = 16
            base[.z] = 6
            base[.space] = 49
            base[.l1] = 12
            base[.r1] = 14

        default:
            base[.a] = 6
            base[.b] = 7
            base[.x] = 8
            base[.y] = 9
            base[.l1] = 12
            base[.r1] = 14
            base[.l2] = 18
            base[.r2] = 20
            base[.l3] = 19
            base[.r3] = 21
            base[.lStickUp] = 13
            base[.lStickDown] = 1
            base[.lStickLeft] = 0
            base[.lStickRight] = 2
            base[.rStickUp] = 34
            base[.rStickDown] = 40
            base[.rStickLeft] = 38
            base[.rStickRight] = 37
        }

        return KeyboardMapping(buttons: base)
    }
}

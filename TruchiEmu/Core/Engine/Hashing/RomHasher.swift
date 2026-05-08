import Foundation
import CommonCrypto
import zlib

enum RomHasher {

    static func hashRom(at path: String, systemID: String) -> String? {
        let url = URL(fileURLWithPath: path)

        switch systemID.lowercased() {
        case "nes":
            return hashNES(url: url)
        case "snes", "snes-msu", "sufami", "satellaview":
            return hashSNES(url: url)
        case "n64":
            return hashN64(url: url)
        case "gamecube", "wii":
            return hashGameCube(url: url)
        case "nds":
            return hashNDS(url: url)
        case "gb", "gbc", "gba", "virtualboy", "pokemonmini":
            return md5File(url: url)
        case "fds":
            return hashFDS(url: url)
        case "psx", "ps1":
            return hashPS1(url: url)
        case "ps2":
            return hashPS2(url: url)
        case "psp":
            return hashPSP(url: url)
        case "dreamcast":
            return hashDreamcast(url: url)
        case "saturn":
            return hashSaturn(url: url)
        case "genesis", "megadrive", "sms", "gamegear", "32x", "sg-1000":
            return md5File(url: url)
        case "mame", "arcade", "mess", "ume":
            return hashMAME(url: url)
        case "3do":
            return hash3DO(url: url)
        case "atari2600":
            return md5File(url: url)
        case "atari7800":
            return hashAtari7800(url: url)
        case "jaguar", "jaguarcd":
            return md5File(url: url)
        case "lynx":
            return hashLynx(url: url)
        case "pce", "tg16", "supergrafx":
            return hashPCEngine(url: url)
        case "pcecd", "tgcd":
            return hashPCEngineCD(url: url)
        case "pcfx":
            return hashPCFX(url: url)
        case "amstradcpc", "apple2", "apple2GS", "msx", "msx2":
            return md5File(url: url)
        case "wonderswan", "wonderswancolor":
            return md5File(url: url)
        case "coleco", "intellivision", "channelF", "channelf", "vectrex", "odyssey2":
            return md5File(url: url)
        case "ngp", "ngpc":
            return md5File(url: url)
        case "neocd", "neocdz":
            return hashNeoGeoCD(url: url)
        case "arduboy", "wasm4":
            return hashNormalizedTextFile(url: url)
        case "megaduck", "supervision":
            return md5File(url: url)
        default:
            return nil
        }
    }

    // MARK: - MD5 Helpers

    private static func md5Data(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func md5File(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return md5Data(data)
    }

    private static func md5Update(context: inout CC_MD5_CTX, data: Data) {
        data.withUnsafeBytes { buffer in
            _ = CC_MD5_Update(&context, buffer.baseAddress, CC_LONG(data.count))
        }
    }

    private static func md5Final(context: inout CC_MD5_CTX) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = CC_MD5_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - CRC32

    private static func crc32Compute(url: URL, skipHeader: Bool = false) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        if skipHeader {
            try? handle.seek(toOffset: 16)
        }

        var crc: uLong = 0
        let bufferSize = 128 * 1024
        while let data = try? handle.read(upToCount: bufferSize), !data.isEmpty {
            crc = data.withUnsafeBytes { buffer in
                crc32(crc, buffer.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(buffer.count))
            }
        }
        return String(format: "%08X", crc).uppercased()
    }

    // MARK: - NES / Famicom

    private static func hashNES(url: URL) -> String? {
        return crc32Compute(url: url, skipHeader: true)
    }

    // MARK: - SNES / Sufami Turbo / Satellaview

    private static func hashSNES(url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? UInt64 else { return nil }

        let headerSize: UInt64 = (fileSize % (8 * 1024) == 512) ? 512 : 0

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        if headerSize > 0 {
            try? handle.seek(toOffset: headerSize)
        }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        let bufferSize = 128 * 1024
        while let data = try? handle.read(upToCount: bufferSize), !data.isEmpty {
            md5Update(context: &context, data: data)
        }

        return md5Final(context: &context)
    }

    // MARK: - N64

    private static func hashN64(url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        let needsByteSwap = ext == "v64" || ext == "n64"

        guard var data = try? Data(contentsOf: url) else { return nil }

        if needsByteSwap {
            let count = data.count
            for i in stride(from: 0, to: count, by: 2) {
                data[i] = data[i + 1]
                data[i + 1] = data[i]
            }
        }

        return md5Data(data)
    }

    // MARK: - GameCube

    private static func hashGameCube(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        try? handle.seek(toOffset: 0)

        guard let apploaderData = try? handle.read(upToCount: 32 * 1024), apploaderData.count >= 8 else {
            return nil
        }

        let codeOffset = apploaderData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let codeSize = apploaderData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }

        try? handle.seek(toOffset: UInt64(codeOffset))

        var buffer = apploaderData
        var remaining = Int(codeSize)

        while remaining > 0 {
            let toRead = min(remaining, 128 * 1024)
            guard let chunk = try? handle.read(upToCount: toRead) else { break }
            if chunk.isEmpty { break }
            buffer.append(chunk)
            remaining -= chunk.count
        }

        return buffer.isEmpty ? nil : md5Data(buffer)
    }

    // MARK: - NDS

    private static func hashNDS(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 0x160), header.count == 0x160 else { return nil }

        let iconTitleOffset = header.subdata(in: 0x68..<0x6C).withUnsafeBytes { $0.load(as: UInt32.self) }
        let arm9Offset = header.subdata(in: 0x20..<0x24).withUnsafeBytes { $0.load(as: UInt32.self) }
        let arm9Size = header.subdata(in: 0x2C..<0x30).withUnsafeBytes { $0.load(as: UInt32.self) }
        let arm7Offset = header.subdata(in: 0x30..<0x34).withUnsafeBytes { $0.load(as: UInt32.self) }
        let arm7Size = header.subdata(in: 0x3C..<0x40).withUnsafeBytes { $0.load(as: UInt32.self) }

        var buffer = Data()

        if iconTitleOffset > 0 {
            try? handle.seek(toOffset: UInt64(iconTitleOffset))
            if let iconData = try? handle.read(upToCount: 0xA00), !iconData.isEmpty {
                buffer.append(iconData)
            }
        }

        if arm9Offset > 0 {
            try? handle.seek(toOffset: UInt64(arm9Offset))
            var remaining = Int(arm9Size)
            while remaining > 0 {
                let toRead = min(remaining, 128 * 1024)
                if let chunk = try? handle.read(upToCount: toRead), !chunk.isEmpty {
                    buffer.append(chunk)
                    remaining -= chunk.count
                } else { break }
            }
        }

        if arm7Offset > 0 {
            try? handle.seek(toOffset: UInt64(arm7Offset))
            var remaining = Int(arm7Size)
            while remaining > 0 {
                let toRead = min(remaining, 128 * 1024)
                if let chunk = try? handle.read(upToCount: toRead), !chunk.isEmpty {
                    buffer.append(chunk)
                    remaining -= chunk.count
                } else { break }
            }
        }

        return buffer.isEmpty ? nil : md5Data(buffer)
    }

    // MARK: - Famicom Disk System

    private static func hashFDS(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 16), header.count >= 4 else {
            return md5File(url: url)
        }

        let isFDS = header[0] == 0x46 && header[1] == 0x44 && header[2] == 0x53 && header[3] == 0x1A
        if isFDS {
            try? handle.seek(toOffset: 16)
        }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        let bufferSize = 128 * 1024
        while let data = try? handle.read(upToCount: bufferSize), !data.isEmpty {
            md5Update(context: &context, data: data)
        }

        return md5Final(context: &context)
    }

    // MARK: - PlayStation (PS1)

    private static func hashPS1(url: URL) -> String? {
        guard let config = ROMIdentifier.ISOScanner.extractSystemConfig(from: url),
              let bootLine = config.components(separatedBy: .newlines).first(where: { $0.contains("BOOT") }) else {
            return nil
        }

        let exeName: String
        if let range = bootLine.range(of: "BOOT=") {
            let after = String(bootLine[range.upperBound...])
            exeName = after.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? after
        } else if let range = bootLine.range(of: "BOOT2=") {
            let after = String(bootLine[range.upperBound...])
            exeName = after.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? after
        } else {
            return nil
        }

        guard !exeName.isEmpty else { return nil }
        return hashPSXExe(url: url, exeName: exeName)
    }

    // MARK: - PlayStation 2

    private static func hashPS2(url: URL) -> String? {
        guard let config = ROMIdentifier.ISOScanner.extractSystemConfig(from: url),
              let bootLine = config.components(separatedBy: .newlines).first(where: { $0.contains("BOOT2") }) else {
            return nil
        }

        let exeName: String
        if let range = bootLine.range(of: "BOOT2=") {
            let after = String(bootLine[range.upperBound...])
            exeName = after.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? after
        } else {
            return nil
        }

        guard !exeName.isEmpty else { return nil }
        return hashPSXExe(url: url, exeName: exeName)
    }

    private static func hashPSXExe(url: URL, exeName: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let scanRange = 8 * 1024 * 1024
        guard let scanData = try? handle.read(upToCount: scanRange) else { return nil }

        let targetName = ("\\" + exeName).data(using: .ascii) ?? exeName.data(using: .ascii)
        guard let targetData = targetName,
              let range = scanData.range(of: targetData) else { return nil }

        let lbnOffset = range.lowerBound - 10
        guard lbnOffset > 0 else { return nil }

        let lbn = scanData.subdata(in: lbnOffset..<lbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let fileOffset = UInt64(lbn) * 2048

        try? handle.seek(toOffset: fileOffset)
        guard let exeData = try? handle.read(upToCount: 128 * 1024 * 1024) else { return nil }

        var nameData = exeName.data(using: .ascii) ?? Data()
        nameData.append(exeData)
        return md5Data(nameData)
    }

    // MARK: - PSP

    private static func hashPSP(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let scanRange = 8 * 1024 * 1024
        guard let scanData = try? handle.read(upToCount: scanRange) else { return nil }

        let sfoName = "PSP_GAME\\PARAMS.SFO".data(using: .ascii)!
        guard let sfoRange = scanData.range(of: sfoName) else { return nil }

        let sfoLbnOffset = sfoRange.lowerBound - 10
        let sfoLbn = scanData.subdata(in: sfoLbnOffset..<sfoLbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let sfoOffset = UInt64(sfoLbn) * 2048

        try? handle.seek(toOffset: sfoOffset)
        guard let sfoData = try? handle.read(upToCount: 4096) else { return nil }

        let ebootName = "PSP_GAME\\SYSDIR\\EBOOT.BIN".data(using: .ascii)!
        guard let ebootRange = scanData.range(of: ebootName) else { return nil }

        let ebootLbnOffset = ebootRange.lowerBound - 10
        let ebootLbn = scanData.subdata(in: ebootLbnOffset..<ebootLbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let ebootOffset = UInt64(ebootLbn) * 2048

        try? handle.seek(toOffset: ebootOffset)
        guard let ebootData = try? handle.read(upToCount: 128 * 1024 * 1024) else { return nil }

        var buffer = sfoData
        buffer.append(ebootData)
        return md5Data(buffer)
    }

    // MARK: - Dreamcast

    private static func hashDreamcast(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let sector0 = try? handle.read(upToCount: 512), sector0.count == 512 else { return nil }

        let marker = "SEGA SEGAKATANA ".data(using: .ascii)!
        guard sector0.prefix(16).elementsEqual(marker) else { return nil }

        let primaryExeOffset = sector0.subdata(in: 0x80..<0x84).withUnsafeBytes { $0.load(as: UInt32.self) }
        let primaryExeSize = sector0.subdata(in: 0x84..<0x88).withUnsafeBytes { $0.load(as: UInt32.self) }

        try? handle.seek(toOffset: UInt64(primaryExeOffset))
        var buffer = sector0
        var remaining = Int(primaryExeSize)

        while remaining > 0 {
            let toRead = min(remaining, 128 * 1024)
            if let chunk = try? handle.read(upToCount: toRead), !chunk.isEmpty {
                buffer.append(chunk)
                remaining -= chunk.count
            } else { break }
        }

        return md5Data(buffer)
    }

    // MARK: - Saturn

    private static func hashSaturn(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count >= 512 else { return nil }

        let marker1 = "SEGA SEGASATURN ".data(using: .ascii)!
        let marker2 = "SEGADISCSYSTEM ".data(using: .ascii)!

        let isSaturn = data.prefix(16).elementsEqual(marker1) || data.prefix(16).elementsEqual(marker2)
        guard isSaturn else { return nil }

        return md5Data(data.prefix(512))
    }

    // MARK: - MAME / Arcade

    private static func hashMAME(url: URL) -> String? {
        let filename = url.deletingPathExtension().lastPathComponent
        return md5Data(filename.data(using: .ascii) ?? Data())
    }

    // MARK: - 3DO Interactive Multiplayer

    private static func hash3DO(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let sector0 = try? handle.read(upToCount: 512), sector0.count >= 132 else { return nil }

        let scanRange = 8 * 1024 * 1024
        guard let scanData = try? handle.read(upToCount: scanRange) else { return nil }

        let launchMeName = "LaunchMe".data(using: .ascii)!
        guard let range = scanData.range(of: launchMeName) else { return nil }

        var buffer = Data(sector0.prefix(132))

        let lbnOffset = range.lowerBound - 10
        guard lbnOffset > 0 else { return nil }

        let lbn = scanData.subdata(in: lbnOffset..<lbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let launchMeOffset = UInt64(lbn) * 2048

        try? handle.seek(toOffset: launchMeOffset)
        if let launchMeData = try? handle.read(upToCount: 128 * 1024 * 1024) {
            buffer.append(launchMeData)
        }

        return md5Data(buffer)
    }

    // MARK: - Atari 7800

    private static func hashAtari7800(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 128), header.count >= 8 else {
            return md5File(url: url)
        }

        let isAtari7800 = header[0] == 0x01 && header[1] == 0x41 && header[2] == 0x54 && header[3] == 0x41 && header[4] == 0x52 && header[5] == 0x49 && header[6] == 0x37 && header[7] == 0x38

        if isAtari7800 {
            try? handle.seek(toOffset: 128)
        }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        let bufferSize = 128 * 1024
        while let data = try? handle.read(upToCount: bufferSize), !data.isEmpty {
            md5Update(context: &context, data: data)
        }

        return md5Final(context: &context)
    }

    // MARK: - Atari Lynx

    private static func hashLynx(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 64), header.count >= 5 else {
            return md5File(url: url)
        }

        let isLynx = header[0] == 0x4C && header[1] == 0x59 && header[2] == 0x4E && header[3] == 0x58 && header[4] == 0x00

        if isLynx {
            try? handle.seek(toOffset: 64)
        }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        let bufferSize = 128 * 1024
        while let data = try? handle.read(upToCount: bufferSize), !data.isEmpty {
            md5Update(context: &context, data: data)
        }

        return md5Final(context: &context)
    }

    // MARK: - PC Engine / TurboGrafx-16 / SuperGrafx

    private static func hashPCEngine(url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? UInt64 else { return nil }

        let headerSize: UInt64 = (fileSize % (128 * 1024) == 512) ? 512 : 0

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        if headerSize > 0 {
            try? handle.seek(toOffset: headerSize)
        }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        let bufferSize = 128 * 1024
        while let data = try? handle.read(upToCount: bufferSize), !data.isEmpty {
            md5Update(context: &context, data: data)
        }

        return md5Final(context: &context)
    }

    // MARK: - PC Engine CD / TurboGrafx-CD

    private static func hashPCEngineCD(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        try? handle.seek(toOffset: 2048)
        guard let sector1 = try? handle.read(upToCount: 128), sector1.count == 128 else { return nil }

        let marker = "PC Engine CD-ROM SYSTEM".data(using: .ascii)!
        guard let range = sector1.range(of: marker), range.lowerBound >= 32 && range.lowerBound < 54 else { return nil }

        var buffer = Data(sector1.suffix(22))

        let sectorIndex = UInt32(sector1[0]) | (UInt32(sector1[1]) << 8) | (UInt32(sector1[2]) << 16)
        let sectorCount = sector1[3]

        try? handle.seek(toOffset: UInt64(sectorIndex) * 2048)
        var remaining = Int(sectorCount)
        while remaining > 0 {
            let toRead = min(remaining, 64)
            if let chunk = try? handle.read(upToCount: toRead * 2048), !chunk.isEmpty {
                buffer.append(chunk)
                remaining -= chunk.count
            } else { break }
        }

        return md5Data(buffer)
    }

    // MARK: - PC-FX

    private static func hashPCFX(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let sector0 = try? handle.read(upToCount: 2048), sector0.count >= 32 else { return nil }

        let marker = "PC-FX:Hu_CD-ROM".data(using: .ascii)!
        guard sector0.prefix(15).elementsEqual(marker) else { return nil }

        try? handle.seek(toOffset: 2048)
        guard let sector1 = try? handle.read(upToCount: 128), sector1.count == 128 else { return nil }

        var buffer = Data(sector0.prefix(32))
        buffer.append(sector1)

        let sectorIndex = sector1.subdata(in: 0x20..<0x24).withUnsafeBytes { $0.load(as: UInt32.self) }
        let sectorCount = sector1.subdata(in: 0x24..<0x28).withUnsafeBytes { $0.load(as: UInt32.self) }

        try? handle.seek(toOffset: UInt64(sectorIndex) * 2048)
        var remaining = Int(sectorCount)
        while remaining > 0 {
            let toRead = min(remaining, 64)
            if let chunk = try? handle.read(upToCount: toRead * 2048), !chunk.isEmpty {
                buffer.append(chunk)
                remaining -= chunk.count
            } else { break }
        }

        return md5Data(buffer)
    }

    // MARK: - Neo Geo CD

    private static func hashNeoGeoCD(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let scanRange = 16 * 1024 * 1024
        guard let scanData = try? handle.read(upToCount: scanRange) else { return nil }

        let iplName = "IPL.TXT".data(using: .ascii)!
        guard scanData.range(of: iplName) != nil else { return nil }

        try? handle.seek(toOffset: 0)

        var buffer = Data()
        for entry in ["MAIN.BIN", "SAFETY.BIN"] {
            let entryData = entry.data(using: .ascii)!
            if let range = scanData.range(of: entryData) {
                let lbnOffset = range.lowerBound - 10
                if lbnOffset > 0 {
                    let lbn = scanData.subdata(in: lbnOffset..<lbnOffset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
                    try? handle.seek(toOffset: UInt64(lbn) * 2048)
                    if let chunk = try? handle.read(upToCount: 2 * 1024 * 1024) {
                        buffer.append(chunk)
                    }
                }
            }
        }

        return buffer.isEmpty ? nil : md5Data(buffer)
    }

    // MARK: - Arduboy / WASM-4 (normalize line endings)

    private static func hashNormalizedTextFile(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        if let string = String(data: data, encoding: .utf8) {
            let normalized = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            if let normalizedData = normalized.data(using: .ascii) {
                return md5Data(normalizedData)
            }
        }

        return md5File(url: url)
    }
}

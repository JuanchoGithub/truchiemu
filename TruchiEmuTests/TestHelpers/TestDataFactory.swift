import Foundation
@testable import TruchieEmu

/// Centralized test data factory for consistent test data across the test suite
class TestDataFactory {
    // MARK: - MOCK ROM DATA
    
    static func createTestROM(
        name: String = "Test Game",
        systemID: String = "nes",
        path: String? = nil,
        hasBoxArt: Bool = false,
        isFavorite: Bool = false,
        crc32: String? = nil
    ) -> ROM {
        return ROM(
            name: name,
            systemID: systemID,
            path: path ?? testROMPath(name: name, systemID: systemID),
            hasBoxArt: hasBoxArt,
            isFavorite: isFavorite,
            crc32: crc32 ?? generateTestCRC(name: name)
        )
    }
    
    static func createTestROMs(count: Int, systemID: String = "nes") -> [ROM] {
        return (0..<count).map { i in
            createTestROM(name: "TestGame\(i)", systemID: systemID)
        }
    }
    
    static func testROMPath(name: String, systemID: String) -> String {
        return "/test/roms/\(name).\(systemID)"
    }
    
    static func generateTestCRC(name: String) -> String {
        // Generate deterministic CRC32 based on name for consistent tests
        let data = Data(name.utf8)
        let checksum = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> UInt32 in
            var crc: UInt32 = 0
            for byte in ptr {
                crc = crc ^ UInt32(byte)
                crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1))
            }
            return crc
        }
        return String(format: "%08X", checksum)
    }
    
    // MARK: - TEST FILE SYSTEM UTILITIES
    
    static func createTempDirectory(prefix: String = "test") -> URL {
        let unique = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(unique)")
        
        try! FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
    
    static func createTestROMDirectory(
        count: Int,
        extensions: [String] = ["nes", "sfc", "gb"],
        nestedLevels: Int = 0
    ) -> URL {
        let rootDir = createTempDirectory(prefix: "roms")
        
        for i in 0..<count {
            let ext = extensions[i % extensions.count]
            let fileName = "game\(i).\(ext)"
            
            let fileURL: URL
            if nestedLevels > 0 && i % 3 == 0 {
                // Create nested directory structure for some files
                let subdir = rootDir.appendingPathComponent("subdir\(i % nestedLevels)")
                try! FileManager.default.createDirectory(
                    at: subdir,
                    withIntermediateDirectories: true
                )
                fileURL = subdir.appendingPathComponent(fileName)
            } else {
                fileURL = rootDir.appendingPathComponent(fileName)
            }
            
            // Write mock ROM data
            let romData = "ROM_DATA_\(i)\(ext)".data(using: .utf8)!
            try! romData.write(to: fileURL)
        }
        
        return rootDir
    }
    
    static func createMixedDirectory(romCount: Int, otherCount: Int) -> URL {
        let dir = createTempDirectory(prefix: "mixed")
        
        // Create ROM files
        for i in 0..<romCount {
            let romData = "ROM_DATA_\(i)".data(using: .utf8)!
            let romURL = dir.appendingPathComponent("game\(i).nes")
            try! romData.write(to: romURL)
        }
        
        // Create non-ROM files (should be ignored)
        for i in 0..<otherCount {
            let textURL = dir.appendingPathComponent("doc\(i).txt")
            try! "This is a text file".data(using: .utf8)!.write(to: textURL)
            
            let imageURL = dir.appendingPathComponent("image\(i).png")
            try! "FAKE_IMAGE_DATA".data(using: .utf8)!.write(to: imageURL)
        }
        
        return dir
    }
    
    // MARK: - MOCK SAVE STATE DATA
    
    static func createTestSaveStateData(size: Int = 1024) -> Data {
        let pattern = "SAVE_STATE_DATA_"
        let patternData = pattern.data(using: .utf8)!
        var data = Data()
        
        while data.count < size {
            data.append(patternData)
        }
        
        return data.subdata(in: 0..<size)
    }
    
    static func createTestSaveStateDirectory(romID: UUID, slotCount: Int) -> URL {
        let baseDir = createTempDirectory(prefix: "saves")
        let romDir = baseDir.appendingPathComponent(romID.uuidString)
        
        try! FileManager.default.createDirectory(
            at: romDir,
            withIntermediateDirectories: true
        )
        
        for slot in 0..<slotCount {
            let slotData = createTestSaveStateData(size: 1024 * (slot + 1))
            let slotFile = romDir.appendingPathComponent("slot_\(slot).sav")
            try! slotData.write(to: slotFile)
        }
        
        return romDir
    }
    
    // MARK: - MOCK CONTROLLER DATA
    
    static func mockGCController(vendorName: String, playerIndex: Int = 0) -> MockGCController {
        return MockGCController(vendorName: vendorName, playerIndex: playerIndex)
    }
    
    static func mockControllerMapping(systemID: String = "nes", handedness: String = "right") -> ControllerGamepadMapping {
        return ControllerGamepadMapping.defaults(for: "Xbox Controller", systemID: systemID, handedness: handedness)
    }
    
    static func mockKeyboardMapping() -> KeyboardMapping {
        return KeyboardMapping(
            upKey: .w,
            downKey: .s,
            leftKey: .a,
            rightKey: .d,
            aButton: .k,
            bButton: .j,
            xButton: .l,
            yButton: .i,
            start: .space,
            select: .enter
        )
    }
    
    // MARK: - MOCK SHADER PRESETS
    
    static func createTestShaderPreset(id: String = "test-shader", name: String = "Test Shader") -> ShaderPreset {
        return ShaderPreset(
            id: id,
            name: name,
            shader: "PassThrough",
            uniforms: [
                "shaderPasses": 1.0,
                "shaderSize": Float([256, 224])
            ]
        )
    }
    
    // MARK: - MOCK CORE DATA
    
    static func mockCoreInfo(id: String = "nestopia", name: String = "Nestopia") -> LibretroCore {
        return LibretroCore(
            id: id,
            name: name,
            version: "1.51",
            supportedExtensions: ["nes", "fds"],
            systemIDs: ["nes"],
            isInstalled: true
        )
    }
    // MARK: - TEST ASSERTION HELPERS
    
    static func assertROMExistsInLibrary(library: ROMLibrary, romID: UUID, file: StaticString = #file, line: UInt = #line) {
        let exists = library.roms.contains { $0.id == romID }
        XCTAssertTrue(exists, "ROM with ID \(romID) should exist in library", file: file, line: line)
    }
    
    static func assertFileExists(at url: URL, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "File should exist at \(url.path)", file: file, line: line)
    }
    
    static func assertDataEqual(_ data1: Data?, _ data2: Data?, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(data1, data2, "Data should be equal", file: file, line: line)
    }
}

// MARK: - MOCK CLASSES

class MockGCController {
    let vendorName: String
    let playerIndex: Int
    
    init(vendorName: String, playerIndex: Int) {
        self.vendorName = vendorName
        self.playerIndex = playerIndex
    }
}

// MARK: - TEST RESOURCE LOCATORS

extension Bundle {
    static func testResourceURL(name: String, ext: String = "rom") -> URL {
        return Bundle.main.url(forResource: name, withExtension: ext)!
    }
}
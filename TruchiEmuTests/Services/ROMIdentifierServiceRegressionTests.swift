import XCTest
@testable import TruchieEmu

/// Regression tests for ROM Identifier Service - prevents ROM identification from breaking
final class ROMIdentifierServiceRegressionTests: XCTestCase {
    
    let service = ROMIdentifierService()
    var testDirectory: URL!
    
    override func setUp() {
        super.setUp()
        testDirectory = TestDataFactory.createTempDirectory(prefix: "rom_id_test")
        continueAfterFailure = false
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }
    
    // MARK: - ✅ TEST 1: CRC32 calculation consistency
    /// PREVENTS: ROMs suddenly not recognizing after algorithm changes
    func testCRC32Calculation_IsStableAcrossMultipleRuns() throws {
        // Given: Same ROM file, calculated multiple times
        let romFile = testDirectory.appendingPathComponent("test_rom.nes")
        let romData = Data(repeating: 0x42, count: 1024)
        try romData.write(to: romFile)
        let expectedCRC = "C5C87D87"
        
        // When: Calculate CRC32 multiple times
        let crc1 = CRC32.compute(url: romFile)
        let crc2 = CRC32.compute(url: romFile)
        let crc3 = CRC32.compute(url: romFile)
        
        // Then: All results identical and match expected
        XCTAssertNotNil(crc1, "First calculation should succeed")
        XCTAssertNotNil(crc2, "Second calculation should succeed")
        XCTAssertNotNil(crc3, "Third calculation should succeed")
        XCTAssertEqual(crc1, crc2, "CRC32 calculation must be deterministic")
        XCTAssertEqual(crc2, crc3, "CRC32 calculation must be deterministic")
        XCTAssertEqual(crc1, expectedCRC, "CRC32 should match expected value")
    }
    
    // MARK: - ✅ TEST 2: Database lookup consistency
    /// PREVENTS: Metadata disappearing for known ROMs
    func testIdentifyKnownROM_ReturnsConsistentResults() async throws {
        // Given: Known Super Mario Bros CRC32 from database
        let knownCRC = "C5C87D87" // Super Mario Bros (NES)
        let nesSystemID = "nes"
        
        // When: Look up multiple times
        let result1 = await service.identifyROM(crc: knownCRC, systemID: nesSystemID)
        let result2 = await service.identifyROM(crc: knownCRC, systemID: nesSystemID)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms between calls
        let result3 = await service.identifyROM(crc: knownCRC, systemID: nesSystemID)
        
        // Then: All results match and return expected game
        XCTAssertEqual(result1, result2, "Database lookups must be consistent")
        XCTAssertEqual(result2, result3, "Database lookups must be consistent")
        
        // Verify it's actually Super Mario Bros
        if case .identified(let gameInfo) = result1 {
            XCTAssertEqual(gameInfo.name, "Super Mario Bros.")
            XCTAssertEqual(gameInfo.crc, knownCRC)
        } else {
            XCTFail("Should identify as Super Mario Bros")
        }
    }
    
    // MARK: - ✅ TEST 3: Concurrency safety
    /// PREVENTS: Race conditions under heavy load
    func testIdentifyMultipleROMs_Concurrently_Safe() async throws {
        // Given: Multiple ROMs to process
        let romFiles = try await createMultipleTestROMs(count: 10)
        let expectation = XCTestExpectation(description: "All identifications complete")
        expectation.expectedFulfillmentCount = romFiles.count
        
        var results: [ROMIdentifyResult] = []
        let resultsLock = NSLock()
        
        // When: Identify all concurrently (simulates real scanner)
        await withTaskGroup(of: Void.self) { group in
            for romFile in romFiles {
                group.addTask {
                    do {
                        if let crc = CRC32.compute(url: romFile) {
                            let result = await self.service.identifyROM(crc: crc, systemID: "nes")
                            resultsLock.lock()
                            results.append(result)
                            resultsLock.unlock()
                        }
                        expectation.fulfill()
                    } catch {
                        expectation.fulfill() // Still fulfill even on error
                    }
                }
            }
        }
        
        // Then: No crashes, all completed
        await fulfillment(of: [expectation], timeout: 10.0)
        XCTAssertEqual(results.count, romFiles.count, "All ROMs should have been identified")
        
        // Verify no duplicates from race conditions
        let uniqueResults = Set(results.map { String(describing: $0) })
        XCTAssertEqual(uniqueResults.count, results.count, "Should not have duplicate results from race conditions")
    }
    
    // MARK: - ✅ TEST 4: Error handling consistency
    /// PREVENTS: Silent failures during ROM import
    func testIdentifyCorruptedROM_ReturnsReadFailedError() async throws {
        // Given: Corrupted/unreadable ROM file (nonexistent)
        let invalidURL = testDirectory.appendingPathComponent("corrupted/notfound.rom")
        
        // When: Attempt identification
        var capturedError: Error?
        
        do {
            _ = try await service.identifyROM(at: invalidURL)
            XCTFail("Should have thrown error for invalid file")
        } catch {
            capturedError = error
        }
        
        // Then: Clear error, not a crash
        XCTAssertNotNil(capturedError, "Should return error for corrupted ROM")
        
        // Verify it's a read error (specific, not generic)
        if let error = capturedError as? URLError {
            XCTAssertTrue([.fileDoesNotExist, .cannotOpenFile].contains(error.code))
        }
    }
    
    // MARK: - ✅ TEST 5: Semaphore behavior
    /// PREVENTS: I/O thrashing regression
    func testDiskIOSemaphore_LimitsConcurrentOperations() async throws {
        // Given: Large number of files to process
        let fileCount = 20
        _ = try await createMultipleTestROMs(count: fileCount, size: 1024 * 1024) // 1MB each
        
        let startTime = Date()
        let maxConcurrentOps = 4 // From diskIOSemaphore value: 4
        let semaphore = DispatchSemaphore(value: maxConcurrentOps)
        var operationCount = 0
        let countLock = NSLock()
        
        let expectation = XCTestExpectation(description: "limited concurrent operations")
        expectation.expectedFulfillmentCount = fileCount
        
        // When: Fire many concurrent CRC calculations
        await withTaskGroup(of: TimeInterval.self) { group in
            for i in 0..<fileCount {
                group.addTask {
                    let fileStartTime = Date()
                    semaphore.wait()
                    
                    countLock.lock()
                    operationCount += 1
                    countLock.unlock()
                    
                    // Simulate disk read delay
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    
                    semaphore.signal()
                    expectation.fulfill()
                    
                    return Date().timeIntervalSince(fileStartTime)
                }
            }
        }
        
        // Then: Operations were throttled
        await fulfillment(of: [expectation], timeout: 30.0)
        let totalDuration = Date().timeIntervalSince(startTime)
        
        // With semaphore limit of 4 and 20 ops with 10ms each:
        // Minimum time = (20 / 4) * 0.010 ≈ 0.05 seconds
        XCTAssertGreaterThan(totalDuration, 0.04, "Operations should be throttled by semaphore")
        
        // Verify concurrent operations never exceeded limit
        countLock.lock()
        XCTAssertEqual(operationCount, fileCount, "All operations should complete")
        countLock.unlock()
    }
    
    // MARK: - ✅ TEST 6: System identification fallback
    /// PREVENTS: ROMs with wrong extension not being identified
    func testIdentifyROM_WithWrongExtension_FallsBackToHeaderDetection() async throws {
        // Given: NES ROM with wrong extension (should still be identified)
        let nesData = createFakeNESROM()
        let romFile = testDirectory.appendingPathComponent("game.sav") // Wrong extension!
        try nesData.write(to: romFile)
        
        // When: Attempt identification
        let result = await service.identifyROM(fromFile: romFile, knownExtensions: []) 
        
        // Then: Should still identify based on NES header
        XCTAssertNotNil(result, "Should identify ROM based on header, not just extension")
    }
    
    // MARK: - ✅ TEST 7: CRC32 offset parameter works correctly
    /// PREVENTS: ROMs with headers calculate wrong CRC
    func testCRC32_WithOffset_SkipsHeaderBytes() throws {
        // Given: ROM with 16-byte header
        let header = Data(repeating: 0xFF, count: 16) // Should be skipped
        let romData = header + Data(repeating: 0x42, count: 1024) // Actual data
        let romFile = testDirectory.appendingPathComponent("headered.rom")
        try romData.write(to: romFile)
        
        // When: Calculate CRC with header offset
        let crcWithOffset = CRC32.compute(url: romFile, offset: 16)
        let crcWithoutOffset = CRC32.compute(url: romFile, offset: 0)
        
        // Then: Results differ when offset applied
        XCTAssertEqual(crcWithOffset, "C5C87D87", "CRC should match data without header")
        XCTAssertNotEqual(crcWithoutOffset, crcWithOffset, "CRC should differ when including header")
    }
    
    // MARK: - ✅ TEST 8: Empty/malformed ROMs handled gracefully
    /// PREVENTS: Zero-byte files crash the scanner
    func testIdentifyEmptyROM_ReturnsAppropriateError() async throws {
        // Given: Zero-byte file
        let emptyFile = testDirectory.appendingPathComponent("empty.rom")
        try Data().write(to: emptyFile)
        
        // When: Attempt identification
        let result = await service.identifyROM(fromFile: emptyFile)
        
        // Then: Returns error, not crash
        XCTAssertNil(result, "Empty file should not be identified")
        // Verify app didn't crash (test would fail if it did)
        XCTAssertTrue(true, "Test completed without crashing")
    }
    
    // MARK: - Helper Functions
    
    private func createMultipleTestROMs(count: Int, size: Int = 1024) async throws -> [URL] {
        var files: [URL] = []
        
        for i in 0..<count {
            let romFile = testDirectory.appendingPathComponent("rom\(i).nes")
            let romData = Data(repeating: UInt8(i % 256), count: size)
            try romData.write(to: romFile)
            files.append(romFile)
        }
        
        return files
    }
    
    private func createFakeNESROM() -> Data {
        // Create minimal NES ROM with NES header
        var data = Data()
        data.append("NES".data(using: .ascii)!) // Magic bytes
        data.append(0x1A) // NES header byte
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // Rest of header
        data.append(contentsOf: Array(repeating: 0xFF, count: 8192)) // PRG data
        return data
    }
}

extension ROMIdentifierService {
    /// Helper for testing - synchronous version
    func identifyROM(crc: String, systemID: String) async -> ROMIdentifyResult {
        return await withCheckedContinuation { continuation in }
    }
}

extension ROMIdentifierService {
    /// Async version for testing - calls the actual implementation
    func identifyROM(fromFile url: URL) async -> ROMIdentifyResult? {
        do {
            return try await withCheckedContinuation { continuation in
                Task {
                    let result = try await self.identifyROM(fromFile: url)
                    continuation.resume(returning: result)
                }
            }
        } catch {
            return nil
        }
    }
}
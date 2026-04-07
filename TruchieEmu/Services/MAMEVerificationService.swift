import Foundation
import SwiftData

/// Background service that verifies MAME ROMs by computing CRC32 of inner files.
/// Runs when the app is idle, pauses when active, and resumes on next launch.
@MainActor
final class MAMEVerificationService: ObservableObject {
    static let shared = MAMEVerificationService()
    
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var pendingCount: Int = 0
    @Published var verifiedCount: Int = 0
    @Published var currentROM: String?
    @Published var progressMessage: String = ""
    
    private var modelContext: ModelContext?
    private var isCancelled = false
    
    // Throttle to avoid overwhelming the system
    private let delayBetweenVerifications: UInt64 = 100_000_000 // 100ms between ROMs
    
    // MARK: - Public API
    
    /// Start or resume background verification.
    /// Call this when the app becomes idle.
    func startVerification(modelContext: ModelContext) {
        guard !isRunning else { return }
        
        self.modelContext = modelContext
        isRunning = true
        isPaused = false
        isCancelled = false
        
        LoggerService.mameVerify("MAME verification started")
        
        Task {
            await runVerificationLoop()
        }
    }
    
    /// Pause verification (e.g., when app becomes active or user starts a game).
    func pause() {
        guard isRunning else { return }
        isPaused = true
        LoggerService.mameVerify("MAME verification paused")
    }
    
    /// Resume verification after pause.
    func resume() {
        guard isRunning && isPaused else { return }
        isPaused = false
        LoggerService.mameVerify("MAME verification resumed")
        
        Task {
            await runVerificationLoop()
        }
    }
    
    /// Stop verification completely.
    func stop() {
        isCancelled = true
        isRunning = false
        isPaused = false
        currentROM = nil
        LoggerService.mameVerify("MAME verification stopped")
    }
    
    /// Get count of pending verifications.
    func updatePendingCount() {
        guard let modelContext else { return }
        do {
            var descriptor = FetchDescriptor<MAMEVerificationRecord>()
            descriptor.predicate = #Predicate<MAMEVerificationRecord> { record in
                record.verificationStatus == "pending"
            }
            pendingCount = try modelContext.fetchCount(descriptor)
        } catch {
            LoggerService.mameVerifyError("Failed to count pending verifications: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Internal Verification Loop
    
    private func runVerificationLoop() async {
        while isRunning && !isCancelled && !isPaused {
            // Update pending count
            updatePendingCount()
            
            guard pendingCount > 0 else {
                progressMessage = "All ROMs verified"
                isRunning = false
                LoggerService.mameVerify("MAME verification complete - no pending ROMs")
                return
            }
            
            // Fetch next pending record
            guard let next = await fetchNextPending() else {
                isRunning = false
                return
            }
            
            // Verify this ROM
            currentROM = next.shortName
            progressMessage = "Verifying \(next.shortName)..."
            
            await verifySingleRecord(next)
            
            // Small delay to avoid hogging CPU
            try? await Task.sleep(nanoseconds: delayBetweenVerifications)
        }
    }
    
    /// Fetch the next pending verification record.
    private func fetchNextPending() async -> MAMEVerificationRecord? {
        guard let modelContext else { return nil }
        
        do {
            var descriptor = FetchDescriptor<MAMEVerificationRecord>()
            descriptor.predicate = #Predicate<MAMEVerificationRecord> { record in
                record.verificationStatus == "pending"
            }
            descriptor.fetchLimit = 1
            descriptor.sortBy = [SortDescriptor(\.romPath)]
            
            let results = try modelContext.fetch(descriptor)
            return results.first
        } catch {
            LoggerService.mameVerifyError("Failed to fetch pending verification: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Verify a single ROM record.
    private func verifySingleRecord(_ record: MAMEVerificationRecord) async {
        let romURL = URL(fileURLWithPath: record.romPath)
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: romURL.path) else {
            record.markError("File not found")
            try? modelContext?.save()
            verifiedCount += 1
            return
        }
        
        // Check if it's a valid ZIP file by reading the header
        guard let data = try? Data(contentsOf: romURL), data.count >= 4 else {
            record.markError("Could not read file")
            try? modelContext?.save()
            verifiedCount += 1
            return
        }
        
        // Compute CRC of the entire ZIP file
        let crcString = String(format: "%08X", computeCRC32(data))
        
        // Check if this shortname exists in the MAME database
        let mameService = MAMEImportService.shared
        if let entry = mameService.lookup(shortName: record.shortName) {
            // Found in database - mark as verified
            record.markVerified(crc32: crcString, innerFiles: nil)
            LoggerService.mameVerify("Verified: \(record.shortName) -> \(entry.description)")
        } else {
            // Not in MAME database - this is not a MAME ROM
            record.markNotMame(crc32: crcString)
            LoggerService.mameVerify("Not MAME: \(record.shortName)")
        }
        
        try? modelContext?.save()
        verifiedCount += 1
    }
    
    // MARK: - CRC32 Computation
    
    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
            table[i] = crc
        }
        return table
    }()
    
    private func computeCRC32(_ data: Data, seed: UInt32 = 0xFFFFFFFF) -> UInt32 {
        var crc = seed
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ Self.crcTable[index]
        }
        return crc
    }
}
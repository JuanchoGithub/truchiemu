import Testing
import Foundation
@testable import TruchieEmu

// MARK: - Bezel Download Progress Tests

@Suite("Bezel Download Progress Tests")
@MainActor
struct BezelDownloadProgressTests {
    
    @Test("Initial state is correct")
    func initialState() async throws {
        let progress = BezelDownloadProgress()
        
        #expect(!progress.isRunning)
        #expect(progress.currentDownloadedCount == 0)
        #expect(progress.totalItemsToDownload == 0)
        #expect(progress.downloadStatus.isEmpty)
        #expect(progress.downloadLog.isEmpty)
        #expect(progress.currentlyDownloadingCount == 0)
        #expect(progress.currentSystemID.isEmpty)
    }
    
    @Test("Progress calculation returns zero when no items")
    func progressZeroWhenNoItems() async throws {
        let progress = BezelDownloadProgress()
        #expect(progress.progress == 0.0)
    }
    
    @Test("Progress calculation is correct")
    func progressCalculationCorrect() async throws {
        let progress = BezelDownloadProgress()
        progress.totalItemsToDownload = 10
        progress.currentDownloadedCount = 5
        
        #expect(progress.progress == 0.5)
    }
    
    @Test("Total downloaded count counts successes only")
    func totalDownloadedCountsSuccesses() async throws {
        let progress = BezelDownloadProgress()
        
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file1", systemID: "snes", status: .success
        ))
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file2", systemID: "snes", status: .success
        ))
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file3", systemID: "snes", status: .failed("Network error")
        ))
        
        #expect(progress.totalDownloadedCount == 2)
    }
    
    @Test("Reset clears non-persistent state")
    func resetClearsNonPersistentState() async throws {
        let progress = BezelDownloadProgress()
        
        // Add a log entry (should persist)
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file1", systemID: "snes", status: .success
        ))
        
        // Set running state
        progress.isRunning = true
        progress.currentDownloadedCount = 5
        progress.totalItemsToDownload = 10
        progress.downloadStatus = "Downloading..."
        progress.currentlyDownloadingCount = 2
        progress.currentSystemID = "snes"
        
        progress.reset()
        
        #expect(!progress.isRunning)
        #expect(progress.currentDownloadedCount == 0)
        #expect(progress.totalItemsToDownload == 0)
        #expect(progress.downloadStatus.isEmpty)
        #expect(progress.currentlyDownloadingCount == 0)
        #expect(progress.currentSystemID.isEmpty)
        // Log should persist
        #expect(progress.downloadLog.count == 1)
    }
    
    @Test("Reset log clears all entries")
    func resetLogClearsAll() async throws {
        let progress = BezelDownloadProgress()
        
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file1", systemID: "snes", status: .success
        ))
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file2", systemID: "snes", status: .failed("Error")
        ))
        
        #expect(progress.downloadLog.count == 2)
        
        progress.resetLog()
        
        #expect(progress.downloadLog.isEmpty)
    }
    
    @Test("Cancel download updates state")
    func cancelDownloadUpdatesState() async throws {
        let progress = BezelDownloadProgress()
        progress.isRunning = true
        progress.currentSystemID = "snes"
        
        progress.cancelDownload()
        
        #expect(!progress.isRunning)
        #expect(progress.downloadStatus == "Download cancelled")
        #expect(progress.downloadLog.contains { entry in
            entry.systemID == "snes" &&
            entry.status.errorMessage == "User cancelled download"
        })
    }
    
    @Test("Log entry limit enforced")
    func logEntryLimitEnforced() async throws {
        let progress = BezelDownloadProgress()
        
        // Add 501 entries
        for i in 0..<501 {
            progress.addLogEntry(BezelDownloadLogEntry(
                fileName: "file\(i)", systemID: "snes", status: .success
            ))
        }
        
        #expect(progress.downloadLog.count == 500)
    }
    
    @Test("Last download date returns success date")
    func lastDownloadDateReturnsSuccess() async throws {
        let progress = BezelDownloadProgress()
        
        #expect(progress.lastDownloadDate == nil)
        
        let pastDate = Date().addingTimeInterval(-60)
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file1", systemID: "snes", timestamp: pastDate, status: .inProgress
        ))
        
        #expect(progress.lastDownloadDate == nil) // only inProgress entry
        
        let successDate = Date()
        progress.addLogEntry(BezelDownloadLogEntry(
            fileName: "file2", systemID: "snes", timestamp: successDate, status: .success
        ))
        
        #expect(progress.lastDownloadDate == successDate)
    }
}

// MARK: - Bezel Download Log Entry Tests

@Suite("Bezel Download Log Entry Tests")
struct BezelDownloadLogEntryTests {
    
    @Test("Default initializer generates UUID")
    func defaultInitGeneratesUUID() async throws {
        let entry = BezelDownloadLogEntry(
            fileName: "test.png",
            systemID: "snes",
            status: .success
        )
        
        #expect(entry.id != UUID())
    }
    
    @Test("Display duration formats correctly")
    func displayDurationFormatsCorrectly() async throws {
        let entry1 = BezelDownloadLogEntry(
            fileName: "test.png",
            systemID: "snes",
            duration: 0.5,
            status: .success
        )
        
        #expect(entry1.displayDuration == "500ms")
        
        let entry2 = BezelDownloadLogEntry(
            fileName: "test.png",
            systemID: "snes",
            duration: 2.345,
            status: .success
        )
        
        #expect(entry2.displayDuration == "2.3s")
        
        let entry3 = BezelDownloadLogEntry(
            fileName: "test.png",
            systemID: "snes",
            duration: nil,
            status: .success
        )
        
        #expect(entry3.displayDuration.isEmpty)
    }
    
    @Test("Status isSuccess returns correct value")
    func statusIsCorrectValue() async throws {
        #expect(BezelDownloadLogEntry.DownloadStatus.success.isSuccess)
        #expect(!BezelDownloadLogEntry.DownloadStatus.inProgress.isSuccess)
        #expect(!BezelDownloadLogEntry.DownloadStatus.failed("error").isSuccess)
    }
    
    @Test("Status errorMessage returns correct value")
    func statusErrorMessageCorrect() async throws {
        let success = BezelDownloadLogEntry.DownloadStatus.success.errorMessage
        let failed = BezelDownloadLogEntry.DownloadStatus.failed("Network error").errorMessage
        let inProgress = BezelDownloadLogEntry.DownloadStatus.inProgress.errorMessage
        
        #expect(success == nil)
        #expect(inProgress == nil)
        #expect(failed == "Network error")
    }
    
    @Test("Codable encoding and decoding")
    func codableEncodingAndDecoding() async throws {
        let entry = BezelDownloadLogEntry(
            fileName: "Super Mario World.png",
            systemID: "snes",
            timestamp: Date(timeIntervalSince1970: 1000000),
            duration: 1.5,
            status: .success
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BezelDownloadLogEntry.self, from: data)
        
        #expect(decoded.fileName == entry.fileName)
        #expect(decoded.systemID == entry.systemID)
        #expect(decoded.duration == entry.duration)
        #expect(decoded.status.isSuccess)
    }
    
    @Test("Codable with failed status")
    func codableWithFailedStatus() async throws {
        let entry = BezelDownloadLogEntry(
            fileName: "test.png",
            systemID: "snes",
            duration: 0.1,
            status: .failed("HTTP 404")
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BezelDownloadLogEntry.self, from: data)
        
        #expect(decoded.status.errorMessage == "HTTP 404")
        #expect(!decoded.status.isSuccess)
    }
}
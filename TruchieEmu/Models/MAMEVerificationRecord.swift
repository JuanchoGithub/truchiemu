import Foundation
import SwiftData

// MARK: - MAME ROM Verification Tracking

/// Tracks the CRC verification status of MAME ROMs.
/// This enables background verification that survives app restarts.
@Model
final class MAMEVerificationRecord {
    @Attribute(.unique) var romPath: String
    var shortName: String
    var crc32: String?
    var verificationStatus: String  // "pending", "verified", "notMame", "error"
    var isVerified: Bool
    var verifiedAt: Date?
    var innerFiles: String?  // JSON array of files inside ZIP (for debugging)
    var lastAttemptAt: Date?
    var attemptCount: Int
    
    init(
        romPath: String,
        shortName: String,
        verificationStatus: String = "pending",
        isVerified: Bool = false,
        crc32: String? = nil,
        innerFiles: String? = nil
    ) {
        self.romPath = romPath
        self.shortName = shortName
        self.verificationStatus = verificationStatus
        self.isVerified = isVerified
        self.crc32 = crc32
        self.innerFiles = innerFiles
        self.attemptCount = 0
    }
}

// MARK: - Verification Status Helpers

extension MAMEVerificationRecord {
    enum Status: String {
        case pending
        case verified
        case notMame
        case error
        
        var rawValue: String {
            switch self {
            case .pending: return "pending"
            case .verified: return "verified"
            case .notMame: return "notMame"
            case .error: return "error"
            }
        }
        
        init?(rawValue: String) {
            switch rawValue {
            case "pending": self = .pending
            case "verified": self = .verified
            case "notMame": self = .notMame
            case "error": self = .error
            default: return nil
            }
        }
    }
    
    var statusEnum: Status? {
        Status(rawValue: verificationStatus)
    }
    
    func markVerified(crc32: String, innerFiles: [String]? = nil) {
        self.crc32 = crc32
        self.verificationStatus = Status.verified.rawValue
        self.isVerified = true
        self.verifiedAt = Date()
        self.lastAttemptAt = Date()
        self.attemptCount += 1
        if let innerFiles {
            self.innerFiles = try? JSONEncoder().encode(innerFiles).base64EncodedString()
        }
    }
    
    func markNotMame(crc32: String) {
        self.crc32 = crc32
        self.verificationStatus = Status.notMame.rawValue
        self.isVerified = false
        self.verifiedAt = Date()
        self.lastAttemptAt = Date()
        self.attemptCount += 1
    }
    
    func markError(_ error: String) {
        self.verificationStatus = Status.error.rawValue
        self.isVerified = false
        self.lastAttemptAt = Date()
        self.attemptCount += 1
    }
}
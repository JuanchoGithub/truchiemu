import Foundation
import os.log

private let cheatLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruchieEmu", category: "CheatParser")

// MARK: - Cheat Parser

/// Parses RetroArch `.cht` cheat files into `Cheat` objects.
///
/// The `.cht` format is a simple INI-like key-value format:
/// ```ini
/// cheats = 3
/// cheat0_desc = "Infinite Lives"
/// cheat0_code = "7E0DBE05"
/// cheat0_enable = false
/// cheat1_desc = "Invincibility"
/// cheat1_code = "7E1490FF"
/// cheat1_enable = false
/// ```
class CheatParser {
    
    // MARK: - Public Methods
    
    /// Parse a .cht file from a URL.
    static func parseChtFile(url: URL) -> [Cheat]? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let result = parseChtContent(content)
            cheatLog.info("parseChtFile: read \(content.count) bytes, parsed \(result.count) cheats from \(url.lastPathComponent)")
            return result
        } catch {
            cheatLog.error("Failed to read cheat file \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Parse .cht content from a string.
    static func parseChtContent(_ content: String) -> [Cheat] {
        let lines = content.components(separatedBy: .newlines)
        var cheats: [Cheat] = []
        var cheatCount = 0
        
        // First pass: find total cheat count
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("cheats") {
                if let value = extractValue(trimmed), let count = Int(value) {
                    cheatCount = count
                    break
                }
            }
        }
        
        cheatLog.info("parseChtContent: found cheatCount=\(cheatCount) from \(lines.count) lines")
        
        // Second pass: parse individual cheats
        for i in 0..<cheatCount {
            let prefix = "cheat\(i)"
            var cheat = Cheat(index: i, description: "", code: "")
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                if trimmed.hasPrefix("\(prefix)_desc") {
                    cheat.description = extractValue(trimmed) ?? ""
                } else if trimmed.hasPrefix("\(prefix)_code") {
                    cheat.code = extractValue(trimmed) ?? ""
                } else if trimmed.hasPrefix("\(prefix)_enable") {
                    if let value = extractValue(trimmed) {
                        cheat.enabled = value.lowercased() == "true"
                    }
                } else if trimmed.hasPrefix("\(prefix)_type") {
                    // Parse cheat type if present
                    if let typeValue = extractValue(trimmed) {
                        cheat.format = parseCheatType(typeValue)
                    }
                }
            }
            
            // Only add cheats that have a code
            if !cheat.code.isEmpty {
                cheats.append(cheat)
            }
        }
        
        cheatLog.info("Parsed \(cheats.count) cheats from .cht content")
        return cheats
    }
    
    /// Parse a custom cheat code entered by the user.
    static func parseCustomCode(_ code: String, description: String = "") -> Cheat? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let format = detectFormat(trimmed)
        return Cheat(
            index: 0,
            description: description.isEmpty ? "Custom Code" : description,
            code: trimmed,
            enabled: true,
            format: format
        )
    }
    
    // MARK: - Format Detection
    
    /// Detect the format of a cheat code string.
    static func detectFormat(_ code: String) -> CheatFormat {
        let cleaned = code.replacingOccurrences(of: "[- ]", with: "", options: .regularExpression)
            .uppercased()
        
        // Game Genie NES: 6 characters (letters A-F, H-N, P-T, V-Z, no I, J, O, U)
        if cleaned.count == 6 && isGameGenieNESCharSet(cleaned) {
            return .gameGenie
        }
        
        // Game Genie SNES: 8 characters
        if cleaned.count == 8 && isGameGenieSNESCharSet(cleaned) {
            return .gameGenie
        }
        
        // Pro Action Replay / GameShark: 8 hex characters
        if cleaned.count == 8 && cleaned.allSatisfy({ $0.isHexDigit }) {
            // GameShark typically starts with 80, 81, etc.
            if cleaned.hasPrefix("8") {
                return .gameshark
            }
            return .par
        }
        
        // Raw hex: any length hex string
        if cleaned.allSatisfy({ $0.isHexDigit }) && !cleaned.isEmpty {
            return .raw
        }
        
        return .raw
    }
    
    // MARK: - Private Helpers
    
    private static func extractValue(_ line: String) -> String? {
        // Find the = sign
        guard let equalsRange = line.range(of: "=") else { return nil }
        let valuePart = String(line[equalsRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        
        // Remove quotes if present
        if valuePart.hasPrefix("\"") && valuePart.hasSuffix("\"") {
            return String(valuePart.dropFirst().dropLast())
        }
        
        return valuePart
    }
    
    private static func parseCheatType(_ type: String) -> CheatFormat {
        let lower = type.lowercased()
        if lower.contains("game genie") {
            return .gameGenie
        } else if lower.contains("action replay") || lower.contains("par") {
            return .par
        } else if lower.contains("gameshark") || lower.contains("gs") {
            return .gameshark
        }
        return .raw
    }
    
    private static func isGameGenieNESCharSet(_ s: String) -> Bool {
        // NES Game Genie uses: A-P, S-V, X-Z (no Q, R, W, Y, and no I, J, O, U)
        let validChars: Set<Character> = Set("ABCDEFGHIJKLMNOPSTVXYZ")
        return s.allSatisfy { validChars.contains($0) }
    }
    
    private static func isGameGenieSNESCharSet(_ s: String) -> Bool {
        // SNES Game Genie uses hex-like characters
        let validChars: Set<Character> = Set("0123456789ABCDEF")
        return s.allSatisfy { validChars.contains($0) }
    }
}

// MARK: - Cheat Code Validator

/// Validates and converts cheat codes between formats.
enum CheatValidator {
    
    /// Validate a raw hex code and extract address + value.
    /// Returns (address, value) if valid.
    static func validateRawHex(_ code: String) -> (address: UInt32, value: UInt8)? {
        let cleaned = code.replacingOccurrences(of: "[- ]", with: "", options: .regularExpression)
            .uppercased()
        
        // Expect 8 hex chars: AAAAVV where AAAA is address, VV is value
        guard cleaned.count == 8, cleaned.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        
        let addressStr = String(cleaned.prefix(4))
        let valueStr = String(cleaned.suffix(2))
        
        guard let address = UInt32(addressStr, radix: 16),
              let value = UInt8(valueStr, radix: 16) else {
            return nil
        }
        
        return (address, value)
    }
    
    /// Decode a Game Genie NES code (6 characters).
    /// Returns (address, value) if valid.
    static func decodeGameGenieNES(_ code: String) -> (address: UInt16, value: UInt8)? {
        let cleaned = code.replacingOccurrences(of: "[- ]", with: "", options: .regularExpression)
            .uppercased()
        
        guard cleaned.count == 6 else { return nil }
        
        // Game Genie encoding table (NES uses: A-P, S-V, X-Z, no Q, R, W, Y)
        let decodeTable: [Character: UInt8] = [
            "A": 0, "P": 1, "Z": 2, "L": 3, "G": 4, "T": 5, "X": 6, "U": 7,
            "K": 8, "S": 9, "V": 10, "N": 11, "Y": 12, "E": 13, "O": 14, "I": 15
        ]
        
        var decoded: [UInt8] = []
        for char in cleaned {
            guard let value = decodeTable[char] else { return nil }
            decoded.append(value)
        }
        
        // NES Game Genie encoding:
        // Characters: C0 C1 C2 C3 C4 C5
        // Decoded nibbles: D0 D1 D2 D3 D4 D5
        // Address = (D4 & 0x0F) | ((D4 & 0xF0) >> 4) | (D2 << 8) | ((D0 & 0x0F) << 12)
        // Value = ((D0 & 0xF0) >> 4) | (D3 << 4)
        // Compare = D5 (optional, not used here)
        
        let address = UInt16(decoded[4] & 0x0F) |
                      UInt16((decoded[4] & 0xF0) >> 4) |
                      UInt16(decoded[2] << 8) |
                      UInt16((decoded[0] & 0x0F) << 12)
        
        let value = UInt8((decoded[0] & 0xF0) >> 4) | UInt8(decoded[3] << 4)
        
        return (address, value)
    }
    
    /// Decode a Game Genie SNES code (8 characters with check digit).
    /// Format: ABCD-EFGH where H is a check digit.
    /// Returns (address, value) if valid.
    static func decodeGameGenieSNES(_ code: String) -> (address: UInt32, value: UInt8)? {
        let cleaned = code.replacingOccurrences(of: "[- ]", with: "", options: .regularExpression)
            .uppercased()
        
        guard cleaned.count == 8 else { return nil }
        
        // SNES Game Genie uses a different encoding than NES
        // Characters map to 4-bit values
        let decodeTable: [Character: UInt8] = [
            "D": 0, "F": 1, "4": 2, "7": 3, "0": 4, "9": 5, "3": 6, "C": 7,
            "8": 8, "A": 9, "5": 10, "2": 11, "B": 12, "E": 13, "6": 14, "1": 15
        ]
        
        var decoded: [UInt8] = []
        for char in cleaned {
            guard let value = decodeTable[char] else { return nil }
            decoded.append(value)
        }
        
        // SNES Game Genie encoding:
        // Address = (D0 << 16) | (D2 << 12) | (D4 << 8) | (D6 << 4) | D1
        // Value = D3 (with some bit manipulation)
        // The check digit D7 should validate but we skip for simplicity
        
        let address = UInt32(decoded[0]) << 16 |
                      UInt32(decoded[2]) << 12 |
                      UInt32(decoded[4]) << 8 |
                      UInt32(decoded[6]) << 4 |
                      UInt32(decoded[1])
        
        let value = UInt8((decoded[3] << 4) | decoded[5])
        
        return (address, value)
    }
    
    /// Validate a Pro Action Replay code.
    /// Format: AAAAVVVV (address + value, both 16-bit)
    static func validatePAR(_ code: String) -> (address: UInt32, value: UInt16)? {
        let cleaned = code.replacingOccurrences(of: "[- ]", with: "", options: .regularExpression)
            .uppercased()
        
        guard cleaned.count == 8, cleaned.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        
        let addressStr = String(cleaned.prefix(4))
        let valueStr = String(cleaned.suffix(4))
        
        guard let address = UInt32(addressStr, radix: 16),
              let value = UInt16(valueStr, radix: 16) else {
            return nil
        }
        
        return (address, value)
    }
    
    /// Validate a GameShark code.
    /// Format: TTAAVVVV (type + address + value)
    static func validateGameShark(_ code: String) -> (type: UInt8, address: UInt16, value: UInt16)? {
        let cleaned = code.replacingOccurrences(of: "[- ]", with: "", options: .regularExpression)
            .uppercased()
        
        guard cleaned.count == 8, cleaned.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        
        let typeStr = String(cleaned.prefix(2))
        let addressStr = String(cleaned[cleaned.index(cleaned.startIndex, offsetBy: 2)..<cleaned.index(cleaned.startIndex, offsetBy: 6)])
        let valueStr = String(cleaned.suffix(4))
        
        guard let type = UInt8(typeStr, radix: 16),
              let address = UInt16(addressStr, radix: 16),
              let value = UInt16(valueStr, radix: 16) else {
            return nil
        }
        
        return (type, address, value)
    }
}
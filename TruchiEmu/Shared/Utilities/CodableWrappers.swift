import Foundation

/// A property wrapper that attempts to decode an Int from either an Int or a String.
@propertyWrapper
public struct SafeInt: Codable, Hashable {
    public var wrappedValue: Int
    
    public init(wrappedValue: Int) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue
        } else if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
            wrappedValue = intValue
        } else {
            // Fallback to 0 instead of throwing to prevent entire array decoding failure
            wrappedValue = 0
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// A property wrapper that attempts to decode an optional Int from either an Int or a String.
@propertyWrapper
public struct SafeOptionalInt: Codable, Hashable {
    public var wrappedValue: Int?
    
    public init(wrappedValue: Int?) {
        self.wrappedValue = wrappedValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue
        } else if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
            wrappedValue = intValue
        } else {
            wrappedValue = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: SafeInt.Type, forKey key: K) throws -> SafeInt {
        return try decodeIfPresent(SafeInt.self, forKey: key) ?? SafeInt(wrappedValue: 0)
    }
    
    func decode(_ type: SafeOptionalInt.Type, forKey key: K) throws -> SafeOptionalInt {
        return try decodeIfPresent(SafeOptionalInt.self, forKey: key) ?? SafeOptionalInt(wrappedValue: nil)
    }
}

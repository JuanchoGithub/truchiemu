import Foundation
import Logboard

/// Routes HaishinKit's internal `LBLogger` output (VideoToolbox warnings,
/// RTMP socket errors, codec failures) through `LoggerService` so they end
/// up in TruchiEmu.log. HaishinKit ships with a `ConsoleAppender` by default
/// (which only `print()`s, captured by Xcode but not by the on-disk log);
/// this replaces it with one that funnels through our appender.
///
/// Identifier values come from the public `kHaishinKitIdentifier` /
/// `kRTMPHaishinKitIdentifier` constants exported by the libraries so we
/// pin them at runtime rather than hardcoding the strings.
import HaishinKit
import RTMPHaishinKit

enum HaishinKitLogger {
    static func installAppender() {
        let appender = LoggerServiceAppender()
        let hkLogger = LBLogger.with(kHaishinKitIdentifier)
        hkLogger.appender = appender
        hkLogger.level = .info
        let rtmpLogger = LBLogger.with(kRTMPHaishinKitIdentifier)
        rtmpLogger.appender = appender
        rtmpLogger.level = .info
    }
}

/// LBLoggerAppender that forwards to `LoggerService` under the "HaishinKit"
/// category. Implements both required `append(...)` overloads to satisfy the
/// protocol regardless of which `LBLogger` API surface the library calls.
private final class LoggerServiceAppender: LBLoggerAppender, @unchecked Sendable {
    func append(_ logboard: LBLogger,
               level: LBLogger.Level,
               message: [Any],
               file: StaticString,
               function: StaticString,
               line: Int) {
        let joined = message.map { String(describing: $0) }.joined()
        forward(level: level, message: joined, function: String(describing: function), line: line)
    }

    func append(_ logboard: LBLogger,
               level: LBLogger.Level,
               format: String,
               arguments: any CVarArg,
               file: StaticString,
               function: StaticString,
               line: Int) {
        // LBLoggerAppender passes a single CVarArg — fall back to the format
        // string itself when the boxed arguments aren't usable from Swift.
        forward(level: level, message: format, function: String(describing: function), line: line)
    }

    private func forward(level: LBLogger.Level, message: String, function: String, line: Int) {
        let category = "HaishinKit"
        let prefixed = "\(function):\(line) \(message)"
        switch level {
        case .trace, .debug:
            LoggerService.debug(category: category, prefixed)
        case .info:
            LoggerService.info(category: category, prefixed)
        case .warn:
            LoggerService.warning(category: category, prefixed)
        case .error:
            LoggerService.error(category: category, prefixed)
        }
    }
}

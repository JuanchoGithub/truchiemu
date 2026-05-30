import Foundation

final class RcheevosRuntime {
    private let runtime: RcheevosRuntimeRef
    private lazy var selfPtr: UnsafeMutableRawPointer = {
        Unmanaged.passUnretained(self).toOpaque()
    }()
    private var isGameLoaded = false
    private var peekDebugLogged = false
    private var activationTime: DispatchTime?

    var onAchievementTriggered: ((Int) -> Void)?
    var onAchievementProgress: ((Int, Int) -> Void)?
    var onChallengeStarted: ((Int) -> Void)?
    var onChallengeCancelled: ((Int) -> Void)?

    init() {
        self.runtime = rcheevos_create()
    }

    deinit {
        rcheevos_destroy(runtime)
    }

    func loadGame(achievements: [Achievement]) {
        guard !isGameLoaded else { return }
        isGameLoaded = true
        activationTime = DispatchTime.now()

        for achievement in achievements {
            guard let trigger = achievement.trigger, !achievement.isUnlocked else { continue }

            let result = trigger.withCString { triggerPtr in
                rcheevos_activate_achievement(runtime, UInt32(achievement.id), triggerPtr, 0)
            }

            if result != 0 {
                let errStr = rcheevos_error_str(result).map { String(cString: $0) } ?? "unknown"
                LoggerService.error(category: "Rcheevos",
                    "Failed to activate achievement \(achievement.id): \(errStr)")
            }
        }

        LoggerService.info(category: "Rcheevos",
            "Loaded \(achievements.filter { $0.trigger != nil && !$0.isUnlocked }.count) achievements")
    }

    func processFrame() {
        guard isGameLoaded else { return }

        if let activationTime = activationTime {
            let elapsed = DispatchTime.now().uptimeNanoseconds - activationTime.uptimeNanoseconds
            if elapsed < 2_000_000_000 {
                return
            }
            self.activationTime = nil
        }

        rcheevos_process_frame(
            runtime,
            Self.eventCallback,
            Self.peekCallback,
            selfPtr
        )
    }

    func deactivateAllAchievements() {
        rcheevos_reset(runtime)
        isGameLoaded = false
    }

    func resetTriggers() {
        rcheevos_reset(runtime)
        activationTime = DispatchTime.now()
    }

    func serializeProgress() -> Data? {
        let size = rcheevos_progress_size(runtime)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        let result = rcheevos_serialize_progress(runtime, &buffer, size)
        guard result == 0 else {
            LoggerService.error(category: "Rcheevos", "Failed to serialize progress: \(result)")
            return nil
        }
        return Data(buffer)
    }

    func deserializeProgress(_ data: Data) {
        guard !data.isEmpty else { return }
        let result = data.withUnsafeBytes { ptr in
            rcheevos_deserialize_progress(runtime, ptr.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt32(data.count))
        }
        if result != 0 {
            LoggerService.error(category: "Rcheevos", "Failed to deserialize progress: \(result)")
        }
    }

    private static func readValue(from data: Data, numBytes: Int) -> UInt32 {
        var value: UInt32 = 0
        let copyCount = min(data.count, min(numBytes, MemoryLayout<UInt32>.size))
        data.withUnsafeBytes { src in
            UnsafeMutableRawPointer(&value).copyMemory(from: src.baseAddress!, byteCount: copyCount)
        }
        return value
    }

    private static func peekMemory(address: UInt32, numBytes: UInt32) -> UInt32? {
        let rawOffset = Int(address)
        let nbytes = Int(numBytes)

        // Try SYSTEM_RAM first (type 0)
        if let data = LibretroBridgeSwift.getMemoryData(type: 0, offset: rawOffset, size: nbytes) {
            return readValue(from: data, numBytes: nbytes)
        }

        // Try SYSTEM_RAM with masked address for systems where RAM is mapped at high addresses
        // (e.g. Genesis 68K RAM at 0xFF0000 — offset = address & 0xFFFF into 64KB buffer)
        var systemRamSize: size_t = 0
        let hasSystemRam = LibretroBridge.getMemoryData(0, size: &systemRamSize) != nil && systemRamSize > 0
        if hasSystemRam && rawOffset >= Int(systemRamSize) {
            let mask = Int(systemRamSize) - 1
            let maskedOffset = rawOffset & mask
            if maskedOffset + nbytes <= Int(systemRamSize),
               let data = LibretroBridgeSwift.getMemoryData(type: 0, offset: maskedOffset, size: nbytes) {
                return readValue(from: data, numBytes: nbytes)
            }
        }

        // Try VIDEO_RAM (type 2) — some cores (e.g. picodrive/Genesis) expose 68K RAM as VIDEO_RAM
        var videoRamSize: size_t = 0
        let hasVideoRam = LibretroBridge.getMemoryData(2, size: &videoRamSize) != nil && videoRamSize > 0
        if hasVideoRam {
            let ramSize = Int(videoRamSize)
            if rawOffset < ramSize, rawOffset + nbytes <= ramSize,
               let data = LibretroBridgeSwift.getMemoryData(type: 2, offset: rawOffset, size: nbytes) {
                return readValue(from: data, numBytes: nbytes)
            }
            // Try masked address
            if rawOffset >= ramSize {
                let mask = ramSize - 1
                let maskedOffset = rawOffset & mask
                if maskedOffset + nbytes <= ramSize,
                   let data = LibretroBridgeSwift.getMemoryData(type: 2, offset: maskedOffset, size: nbytes) {
                    return readValue(from: data, numBytes: nbytes)
                }
            }
        }

        // Try SAVE_RAM (type 1)
        if let data = LibretroBridgeSwift.getMemoryData(type: 1, offset: rawOffset, size: nbytes) {
            return readValue(from: data, numBytes: nbytes)
        }

        return nil
    }

    private static let peekCallback: RcheevosPeekCallback = { address, numBytes, ud in
        guard let ud else { return 0 }
        let result = peekMemory(address: address, numBytes: numBytes) ?? 0
        let runtime = Unmanaged<RcheevosRuntime>.fromOpaque(ud).takeUnretainedValue()
        if !runtime.peekDebugLogged {
            runtime.peekDebugLogged = true
            var sysRamSize: size_t = 0
            let hasSysRam = LibretroBridge.getMemoryData(0, size: &sysRamSize) != nil && sysRamSize > 0
            var vidRamSize: size_t = 0
            let hasVidRam = LibretroBridge.getMemoryData(2, size: &vidRamSize) != nil && vidRamSize > 0
            LoggerService.info(category: "Rcheevos", "First peek: addr=0x\(String(format: "%X", address)) numBytes=\(numBytes) result=0x\(String(format: "%X", result)) systemRAM=\(hasSysRam ? "\(sysRamSize)B" : "none") videoRAM=\(hasVidRam ? "\(vidRamSize)B" : "none")")
        }
        return result
    }

    private static let eventCallback: RcheevosEventHandler = { event, ud in
        guard let ud, let event else { return }
        let runtime = Unmanaged<RcheevosRuntime>.fromOpaque(ud).takeUnretainedValue()
        runtime.handleEvent(event.pointee)
    }

    private func handleEvent(_ event: RcheevosEvent) {
        let achievementID = Int(event.id)
        switch Int32(event.type) {
        case RCHEEVOS_EVENT_ACHIEVEMENT_TRIGGERED:
            LoggerService.info(category: "Rcheevos", "Achievement TRIGGERED: \(achievementID)")
            onAchievementTriggered?(achievementID)
        case RCHEEVOS_EVENT_ACHIEVEMENT_PROGRESS_UPDATED:
            onAchievementProgress?(achievementID, Int(event.value))
        case RCHEEVOS_EVENT_ACHIEVEMENT_PRIMED:
            LoggerService.debug(category: "Rcheevos", "Achievement PRIMED: \(achievementID)")
            onChallengeStarted?(achievementID)
        case RCHEEVOS_EVENT_ACHIEVEMENT_UNPRIMED:
            onChallengeCancelled?(achievementID)
        default:
            LoggerService.debug(category: "Rcheevos", "Event type=\(event.type) id=\(achievementID) value=\(event.value)")
            break
        }
    }
}

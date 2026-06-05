import Foundation

struct MemoryMap {
    let workRamBase: UInt32
    let workRamSize: UInt32
    let mirrorBase: UInt32?

    static func forSystem(_ systemID: String?) -> MemoryMap? {
        switch (systemID ?? "").lowercased() {
        case "genesis", "megadrive":
            return MemoryMap(workRamBase: 0xFF0000, workRamSize: 0x10000, mirrorBase: 0xE00000)
        default:
            return nil
        }
    }
}

/// Wire-friendly achievement trigger descriptor. Mirrors the C struct in
/// `RcheevosWrapper.h` so it can be sent over XPC without the SwiftData
/// `Achievement` struct.
public struct RcheevosAchievementTrigger: Sendable {
    public let id: UInt32
    public let title: String
    public let trigger: String
    public let isUnlocked: Bool

    public init(id: UInt32, title: String, trigger: String, isUnlocked: Bool) {
        self.id = id
        self.title = title
        self.trigger = trigger
        self.isUnlocked = isUnlocked
    }
}

final class RcheevosRuntime {
    private let runtime: RcheevosRuntimeRef
    private lazy var selfPtr: UnsafeMutableRawPointer = {
        Unmanaged.passUnretained(self).toOpaque()
    }()
    private var isGameLoaded = false
    private var loggedPeekAddresses: Set<UInt32> = []
    private static let maxPeekAddressLogs = 32
    private var activationTime: DispatchTime?
    private let memoryMap: MemoryMap?

    var onAchievementTriggered: ((Int) -> Void)?
    var onAchievementProgress: ((Int, Int) -> Void)?
    var onChallengeStarted: ((Int) -> Void)?
    var onChallengeCancelled: ((Int) -> Void)?
    var onRichPresence: ((String) -> Void)?

    private var richPresenceInterval: Int = 120
    private var lastRichPresenceFrame: Int = 0

    init(systemID: String? = nil) {
        self.runtime = rcheevos_create()
        self.memoryMap = MemoryMap.forSystem(systemID)
    }

    deinit {
        rcheevos_destroy(runtime)
    }

    #if !XPC_SERVICE
    func loadGame(achievements: [Achievement]) {
        guard !isGameLoaded else { return }
        isGameLoaded = true
        activationTime = DispatchTime.now()
        loggedPeekAddresses.removeAll(keepingCapacity: true)

        var activated = 0
        var skippedUnlocked = 0
        var skippedNoTrigger = 0
        var activationFailed = 0

        for achievement in achievements {
            guard let trigger = achievement.trigger else {
                skippedNoTrigger += 1
                continue
            }
            guard !achievement.isUnlocked else {
                skippedUnlocked += 1
                continue
            }

            let result = trigger.withCString { triggerPtr in
                rcheevos_activate_achievement(runtime, UInt32(achievement.id), triggerPtr, 0)
            }

            if result != 0 {
                activationFailed += 1
                let errStr = rcheevos_error_str(result).map { String(cString: $0) } ?? "unknown"
                LoggerService.error(category: "Rcheevos",
                    "Failed to activate achievement \(achievement.id) (title='\(achievement.title)'): \(errStr) trigger=\(trigger.prefix(80))")
            } else {
                activated += 1
                LoggerService.debug(category: "Rcheevos",
                    "Activated id=\(achievement.id) title='\(achievement.title)' trigger=\(trigger.prefix(80))")
            }
        }

        LoggerService.info(category: "Rcheevos",
            "Loaded achievements: total=\(achievements.count) activated=\(activated) skippedUnlocked=\(skippedUnlocked) skippedNoTrigger=\(skippedNoTrigger) activationFailed=\(activationFailed)")
    }
    #endif

    /// Wire-friendly overload for the XPC service. Same activation logic, but
    /// accepts the minimal trigger descriptor instead of the full `Achievement`
    /// SwiftData struct (which only lives in the main app).
    func loadGame(triggers: [RcheevosAchievementTrigger]) {
        guard !isGameLoaded else { return }
        isGameLoaded = true
        activationTime = DispatchTime.now()
        loggedPeekAddresses.removeAll(keepingCapacity: true)

        var activated = 0
        var skippedUnlocked = 0
        var skippedNoTrigger = 0
        var activationFailed = 0

        for entry in triggers {
            guard !entry.trigger.isEmpty else {
                skippedNoTrigger += 1
                continue
            }
            guard !entry.isUnlocked else {
                skippedUnlocked += 1
                continue
            }

            let result = entry.trigger.withCString { triggerPtr in
                rcheevos_activate_achievement(runtime, entry.id, triggerPtr, 0)
            }

            if result != 0 {
                activationFailed += 1
                let errStr = rcheevos_error_str(result).map { String(cString: $0) } ?? "unknown"
                LoggerService.error(category: "Rcheevos",
                    "Failed to activate achievement \(entry.id) (title='\(entry.title)'): \(errStr) trigger=\(entry.trigger.prefix(80))")
            } else {
                activated += 1
                LoggerService.debug(category: "Rcheevos",
                    "Activated id=\(entry.id) title='\(entry.title)' trigger=\(entry.trigger.prefix(80))")
            }
        }

        LoggerService.info(category: "Rcheevos",
            "Loaded achievements: total=\(triggers.count) activated=\(activated) skippedUnlocked=\(skippedUnlocked) skippedNoTrigger=\(skippedNoTrigger) activationFailed=\(activationFailed)")
    }

    private var frameCount = 0

    func processFrame() {
        guard isGameLoaded else { return }

        if let activationTime = activationTime {
            let elapsed = DispatchTime.now().uptimeNanoseconds - activationTime.uptimeNanoseconds
            if elapsed < 500_000_000 {
                return
            }
            self.activationTime = nil
        }

        let start = DispatchTime.now().uptimeNanoseconds
        rcheevos_process_frame(
            runtime,
            Self.eventCallback,
            Self.peekCallback,
            selfPtr
        )
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        frameCount += 1
        if elapsed > 1_000_000 || frameCount <= 5 {
            LoggerService.info(category: "Rcheevos", "processFrame #\(frameCount) took \(elapsed / 1_000)us")
        }
        if frameCount - lastRichPresenceFrame >= richPresenceInterval,
           let rp = getRichPresence(), !rp.isEmpty {
            lastRichPresenceFrame = frameCount
            onRichPresence?(rp)
        }
    }

    func deactivateAllAchievements() {
        rcheevos_reset(runtime)
        isGameLoaded = false
    }

    func deactivateAchievement(id: UInt32) {
        rcheevos_deactivate_achievement(runtime, id)
    }

    func activateRichPresence(script: String) {
        let result = script.withCString { ptr in
            rcheevos_activate_richpresence(runtime, ptr)
        }
        if result != 0 {
            LoggerService.error(category: "Rcheevos", "Failed to activate rich presence: \(result)")
        } else {
            LoggerService.info(category: "Rcheevos", "Rich presence activated")
        }
    }

    func getRichPresence() -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let len = rcheevos_get_richpresence(runtime, &buffer, 256, Self.peekCallback, selfPtr)
        guard len > 0 else { return nil }
        return String(cString: buffer)
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

    /// Slice a region of libretro memory by type. Replaces
    /// `LibretroBridgeSwift.getMemoryData` so this file compiles into the XPC
    /// service target (where `LibretroBridgeSwift` is not linked).
    private func readMemory(type: UInt32, offset: Int, size: Int) -> Data? {
        var memSize: size_t = 0
        guard let ptr = LibretroBridge.getMemoryDataUnsafe(type, size: &memSize), memSize > 0 else {
            return nil
        }
        guard offset >= 0, offset < Int(memSize) else { return nil }
        let available = min(size, Int(memSize) - offset)
        return Data(bytes: ptr.advanced(by: offset), count: available)
    }

    private func peekMemory(address: UInt32, numBytes: UInt32) -> UInt32? {
        let nbytes = Int(numBytes)

        // For systems with a known address map (e.g. Genesis 64K work RAM at 0xFF0000),
        // translate the requested address to the SYSTEM_RAM buffer offset.
        if let map = memoryMap {
            let mapEnd = map.workRamBase &+ map.workRamSize
            let inWorkRam = address >= map.workRamBase && address < mapEnd
            let inMirror: Bool
            if let mirrorBase = map.mirrorBase {
                let mirrorEnd = mirrorBase &+ map.workRamSize
                inMirror = address >= mirrorBase && address < mirrorEnd
            } else {
                inMirror = false
            }

            if inWorkRam || inMirror {
                let offset = Int(address & (map.workRamSize - 1))
                if let data = readMemory(type: 0, offset: offset, size: nbytes) {
                    return Self.readValue(from: data, numBytes: nbytes)
                }
            }
            // Outside work RAM (e.g. ROM / Z80 / VDP region) — fall through to VIDEO/SAVE.
        } else {
            // Flat memory layout: use the address as a direct offset into SYSTEM_RAM.
            let rawOffset = Int(address)
            if let data = readMemory(type: 0, offset: rawOffset, size: nbytes) {
                return Self.readValue(from: data, numBytes: nbytes)
            }
        }

        // Try VIDEO_RAM (type 2) — some cores (e.g. picodrive/Genesis) expose 68K RAM as VIDEO_RAM
        var videoRamSize: size_t = 0
        let hasVideoRam = LibretroBridge.getMemoryDataUnsafe(2, size: &videoRamSize) != nil && videoRamSize > 0
        if hasVideoRam {
            let ramSize = Int(videoRamSize)
            let rawOffset = Int(address)
            if rawOffset < ramSize, rawOffset + nbytes <= ramSize,
               let data = readMemory(type: 2, offset: rawOffset, size: nbytes) {
                return Self.readValue(from: data, numBytes: nbytes)
            }
            // Try masked address
            if rawOffset >= ramSize {
                let mask = ramSize - 1
                let maskedOffset = rawOffset & mask
                if maskedOffset + nbytes <= ramSize,
                   let data = readMemory(type: 2, offset: maskedOffset, size: nbytes) {
                    return Self.readValue(from: data, numBytes: nbytes)
                }
            }
        }

        // Try SAVE_RAM (type 1)
        if let data = readMemory(type: 1, offset: Int(address), size: nbytes) {
            return Self.readValue(from: data, numBytes: nbytes)
        }

        return nil
    }

    private static let peekCallback: RcheevosPeekCallback = { address, numBytes, ud in
        guard let ud else { return 0 }
        let runtime = Unmanaged<RcheevosRuntime>.fromOpaque(ud).takeUnretainedValue()
        let result = runtime.peekMemory(address: address, numBytes: numBytes) ?? 0
        runtime.logPeekIfNeeded(address: address, numBytes: numBytes, value: result)
        return result
    }

    private func logPeekIfNeeded(address: UInt32, numBytes: UInt32, value: UInt32) {
        if loggedPeekAddresses.count >= Self.maxPeekAddressLogs { return }
        if loggedPeekAddresses.contains(address) { return }
        loggedPeekAddresses.insert(address)

        var sysRamSize: size_t = 0
        let hasSysRam = LibretroBridge.getMemoryDataUnsafe(0, size: &sysRamSize) != nil && sysRamSize > 0
        var vidRamSize: size_t = 0
        let hasVidRam = LibretroBridge.getMemoryDataUnsafe(2, size: &vidRamSize) != nil && vidRamSize > 0
        var saveRamSize: size_t = 0
        let hasSaveRam = LibretroBridge.getMemoryDataUnsafe(1, size: &saveRamSize) != nil && saveRamSize > 0

        let source: String
        let offsetUsed: Int
        if let map = memoryMap {
            let mapEnd = map.workRamBase &+ map.workRamSize
            let inWorkRam = address >= map.workRamBase && address < mapEnd
            let inMirror: Bool
            if let mirrorBase = map.mirrorBase {
                let mirrorEnd = mirrorBase &+ map.workRamSize
                inMirror = address >= mirrorBase && address < mirrorEnd
            } else {
                inMirror = false
            }
            if inWorkRam {
                source = "SYSTEM_RAM(mapped)"; offsetUsed = Int(address & (map.workRamSize - 1))
            } else if inMirror {
                source = "SYSTEM_RAM(mirror)"; offsetUsed = Int(address & (map.workRamSize - 1))
            } else if hasVidRam && Int(address) < Int(vidRamSize) {
                source = "VIDEO_RAM"; offsetUsed = Int(address)
            } else if hasSaveRam && Int(address) < Int(saveRamSize) {
                source = "SAVE_RAM"; offsetUsed = Int(address)
            } else {
                source = "unmapped"; offsetUsed = Int(address)
            }
        } else {
            let rawOffset = Int(address)
            if hasSysRam && rawOffset < Int(sysRamSize) {
                source = "SYSTEM_RAM(flat)"; offsetUsed = rawOffset
            } else if hasVidRam && rawOffset < Int(vidRamSize) {
                source = "VIDEO_RAM"; offsetUsed = rawOffset
            } else if hasSaveRam && rawOffset < Int(saveRamSize) {
                source = "SAVE_RAM"; offsetUsed = rawOffset
            } else {
                source = "unmapped"; offsetUsed = rawOffset
            }
        }

        LoggerService.info(category: "Rcheevos",
            "Peek addr=0x\(String(format: "%06X", address)) numBytes=\(numBytes) source=\(source) offset=0x\(String(format: "%X", offsetUsed)) value=0x\(String(format: "%X", value)) sysRam=\(hasSysRam ? "\(sysRamSize)B" : "none") vidRam=\(hasVidRam ? "\(vidRamSize)B" : "none") saveRam=\(hasSaveRam ? "\(saveRamSize)B" : "none")")
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
        case RCHEEVOS_EVENT_ACHIEVEMENT_ACTIVATED:
            LoggerService.debug(category: "Rcheevos", "Achievement ACTIVATED: \(achievementID)")
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

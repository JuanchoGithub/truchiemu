import Foundation

final class SharedMemoryManager {
    static let shared = SharedMemoryManager()

    private var fd: Int32 = -1
    private var mappedPtr: UnsafeMutableRawPointer?
    private var mappedSize: Int = 0
    private(set) var sharedName: String = ""

    var sharedMemory: UnsafeMutablePointer<XPCSharedMemory>? {
        mappedPtr?.assumingMemoryBound(to: XPCSharedMemory.self)
    }

    private init() {}

    func createSharedMemory(sessionID: String) -> Bool {
        sharedName = "\(XPC_SHM_NAME_PREFIX)\(sessionID)"

        let size = MemoryLayout<XPCSharedMemory>.size

        fd = xpc_shm_open(sharedName, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            LoggerService.error(category: "XPC-SHM", "shm_open failed: \(String(cString: strerror(errno)))")
            return false
        }

        guard ftruncate(fd, off_t(size)) == 0 else {
            LoggerService.error(category: "XPC-SHM", "ftruncate failed: \(String(cString: strerror(errno)))")
            close(fd)
            shm_unlink(sharedName)
            return false
        }

        mappedPtr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard let ptr = mappedPtr, ptr != MAP_FAILED else {
            LoggerService.error(category: "XPC-SHM", "mmap failed: \(String(cString: strerror(errno)))")
            close(fd)
            shm_unlink(sharedName)
            return false
        }

        mappedSize = size
        memset(ptr, 0, size)

        LoggerService.info(category: "XPC-SHM", "Created shared memory: \(sharedName) (\(size) bytes)")
        return true
    }

    func openExisting(name: String) -> Bool {
        sharedName = name
        let size = MemoryLayout<XPCSharedMemory>.size

        fd = xpc_shm_open(sharedName, O_RDWR, 0o600)
        guard fd >= 0 else {
            LoggerService.error(category: "XPC-SHM", "shm_open existing failed: \(String(cString: strerror(errno)))")
            return false
        }

        mappedPtr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard let ptr = mappedPtr, ptr != MAP_FAILED else {
            LoggerService.error(category: "XPC-SHM", "mmap existing failed: \(String(cString: strerror(errno)))")
            close(fd)
            return false
        }

        mappedSize = size
        LoggerService.info(category: "XPC-SHM", "Opened existing shared memory: \(name)")
        return true
    }

    func cleanup() {
        if let ptr = mappedPtr, ptr != MAP_FAILED {
            munmap(ptr, mappedSize)
            mappedPtr = nil
        }
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        if !sharedName.isEmpty {
            shm_unlink(sharedName)
            LoggerService.info(category: "XPC-SHM", "Cleaned up shared memory: \(sharedName)")
            sharedName = ""
        }
        mappedSize = 0
    }

    func writeInputStates(joypad: [Int: Bool],
                          analog: [[Int]],
                          analogButtons: [Int: Int32],
                          keyboard: [Int: Bool],
                          mouse: XPCMouseState,
                          pointer: XPCPointerState,
                          player: Int = 0) {
        guard let shm = sharedMemory else { return }

        for (id, pressed) in joypad {
            xpc_shm_set_input_state(shm, Int32(player), Int32(id), pressed ? 1 : 0)
        }
        for state in analog {
            guard state.count == 3 else { continue }
            let idx = state[0], id = state[1], val = state[2]
            xpc_shm_set_analog_state(shm, Int32(player), Int32(idx), Int32(id), Int16(val))
        }
        for (id, val) in analogButtons {
            xpc_shm_set_analog_button(shm, Int32(player), Int32(id), Int16(clamping: val))
        }
        for (id, pressed) in keyboard {
            xpc_shm_set_keyboard_state(shm, Int32(id), pressed)
        }
        shm.pointee.mouse = mouse
        shm.pointee.pointer = pointer
    }

    func setPaused(_ paused: Bool) {
        guard let shm = sharedMemory else { return }
        shm.pointee.isPaused = paused
    }

    func readAudioSamples(into buffer: UnsafeMutablePointer<Int16>, maxCount: Int) -> Int {
        guard let shm = sharedMemory else { return 0 }
        let readPos = Int(xpc_shm_load_audioReadPos(shm))
        let writePos = Int(xpc_shm_load_audioWritePos(shm))
        let capacity = Int(XPC_AUDIO_RING_CAPACITY)
        let available: Int
        if writePos >= readPos {
            available = writePos - readPos
        } else {
            available = capacity - readPos + writePos
        }
        let toRead = min(available, maxCount)
        var sample: Int16 = 0
        for i in 0..<toRead {
            let pos = (readPos + i) % capacity
            xpc_shm_read_audio(shm, pos, &sample)
            buffer[i] = sample
        }
        let newReadPos = (readPos + toRead) % capacity
        xpc_shm_store_audioReadPos(shm, newReadPos)
        return toRead
    }

    deinit {
        cleanup()
    }
}

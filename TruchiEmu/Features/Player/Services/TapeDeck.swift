import Foundation

@MainActor
class TapeDeck: ObservableObject {
    nonisolated static let maxSlots = 3
    nonisolated static let countdownFrames = 3

    @Published var slots: [TapeRecording?] = [nil, nil, nil]
    @Published var isRecording = false
    @Published var isCountingDown = false
    @Published var countdownRemaining: Int = 0
    @Published var activeSlot: Int = 0
    @Published var recordFrameCount: Int = 0

    private var recordingBuffer: [[Int: Bool]] = []

    private let p2Player = 1

    func startRecording(slot: Int) {
        guard slot >= 0, slot < Self.maxSlots else { return }
        activeSlot = slot
        recordingBuffer = []
        recordFrameCount = 0
        countdownRemaining = Self.countdownFrames
        isCountingDown = true
        isRecording = false
    }

    func advanceCountdown() -> Bool {
        guard isCountingDown else { return false }
        countdownRemaining -= 1
        if countdownRemaining <= 0 {
            isCountingDown = false
            isRecording = true
            return false
        }
        return true
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if activeSlot < slots.count {
            slots[activeSlot] = TapeRecording(frames: recordingBuffer)
        }
        recordingBuffer = []
    }

    func stopCountdown() {
        isCountingDown = false
        countdownRemaining = 0
    }

    func recordFrame(p1InputState: [Int: Bool]) {
        guard isRecording else { return }
        guard recordFrameCount < TapeRecording.maxFrames else {
            stopRecording()
            return
        }
        recordingBuffer.append(p1InputState)
        recordFrameCount += 1
    }

    func playbackFrame(at index: Int, slot: Int, adapter: XPCBridgeAdapter) -> Bool {
        guard slot >= 0, slot < slots.count,
              let recording = slots[slot],
              index < recording.frames.count else { return false }
        let frameData = recording.frames[index]
        for retroID in 0..<16 {
            let pressed = frameData[retroID] ?? false
            adapter.setKeyState(retroID: retroID, player: p2Player, pressed: pressed)
        }
        return true
    }

    func clearSlot(_ slot: Int) {
        guard slot >= 0, slot < slots.count else { return }
        slots[slot] = nil
    }
}

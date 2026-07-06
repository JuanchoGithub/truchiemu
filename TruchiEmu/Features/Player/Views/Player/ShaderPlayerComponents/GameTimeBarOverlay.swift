import SwiftUI

struct GameTimeBarOverlay: View {
    @ObservedObject var runner: EmulatorRunner
    @ObservedObject private var hotkeys = HotkeyConfigManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var oldestFrame: UInt64 = 0
    @State private var newestFrame: UInt64 = 0
    @State private var entryCount: Int = 0
    @State private var hasBuffer: Bool = false
    @State private var sliderValue: Double = 0
    @State private var isDragging: Bool = false
    @State private var overlayEnabled: Bool = true

    private let pollTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()
            // Only render the speed/scrub indicator bubble when something
            // is genuinely being shown. Gating on `hasBuffer` alone would
            // leave an empty rounded-rect background visible (an artifact
            // the user noticed after exiting rewind/normal-speed).
            let showBubble = overlayEnabled &&
                (runner.isRewinding || runner.speedMultiplier != 1.0)
            if showBubble {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        if runner.isRewinding {
                            Image(systemName: "backward.fill")
                                .foregroundStyle(.orange)
                            Text(verbatim: "Rewind Scrub")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Text(verbatim: scrubHint)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        } else if runner.speedMultiplier > 1.0 {
                            Image(systemName: "forward.fill")
                                .foregroundStyle(.green)
                            Text(verbatim: "\(Int(runner.speedMultiplier))x")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        } else if runner.speedMultiplier < 1.0 {
                            Image(systemName: "backward.fill")
                                .foregroundStyle(.orange)
                            Text(verbatim: "\(String(format: "%.2f", Double(runner.speedMultiplier)))x")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.7))
                    )

                    if hasBuffer && runner.isRewinding {
                        // Use the system Slider for actual scrubbing (its
                        // gesture/hit-testing already works), and overlay a
                        // GeometryReader-backed time-marker above so the
                        // thumb's current position has a label showing the
                        // playhead's time.
                        ZStack(alignment: .top) {
                            // Floating time label, positioned over the thumb.
                            GeometryReader { geo in
                                let trackWidth = geo.size.width
                                // Label tracks the visible thumb position:
                                // sliderValue during drag, scrubProgress when
                                // at rest. Otherwise the label would stick at
                                // the committed scrub frame while the thumb
                                // moved freely beneath it.
                                let thumbProgress = isDragging ? sliderValue : scrubProgress
                                let thumbX = CGFloat(thumbProgress) * trackWidth
                                // Thumb label is relative to oldest, matching
                                // the edge labels, so the displayed time tracks
                                // the actual reachable rewind window rather
                                // than absolute in-game time.
                                let relativeScrubFrame = runner.timeMachineScrubFrameIndex &- oldestFrame
                                let relativeSliderFrame = UInt64(sliderValue * Double(newestFrame - oldestFrame))
                                let labelFrame = isDragging ? relativeSliderFrame : relativeScrubFrame
                                Text(verbatim: formattedTime(from: labelFrame))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.black.opacity(0.85))
                                    )
                                    .fixedSize()
                                    .position(x: max(25, min(thumbX, trackWidth - 25)), y: 6)
                            }
                            .frame(height: 22)

                            Slider(
                                value: Binding(
                                    get: {
                                        // While dragging, the thumb should
                                        // track the user's gesture, not the
                                        // committed scrub position. Reading
                                        // scrubProgress here would spring the
                                        // thumb back to where the last
                                        // rewindToFrame landed (only on
                                        // drag start), preventing the user
                                        // from reaching the buffer's oldest
                                        // frames — the slider "rails" a few
                                        // seconds back from newest.
                                        isDragging ? sliderValue : scrubProgress
                                    },
                                    set: { newValue in sliderValue = newValue }
                                ),
                                in: 0...1,
                                onEditingChanged: { editing in
                                    isDragging = editing
                                    if editing {
                                        // Apply the new slider position immediately
                                        // so live-feedback works while dragging.
                                        seekToSliderPosition()
                                    } else {
                                        seekToSliderPosition()
                                    }
                                }
                            )
                            .frame(height: 20)
                            .offset(y: 22)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .tint(.white.opacity(0.85))

                        HStack {
                            // Labels are relative to the oldest retained
                            // frame, not absolute in-game time. Without this,
                            // a hold of only ~1s of states that happens to
                            // span game frames 2400..2406 would render as
                            // "0:40 ─ 0:41", which reads to users as "41
                            // seconds of rewind history" even though the
                            // buffer only reaches back one second. Anchoring
                            // the left edge to 0:00 makes the displayed span
                            // equal the actual reachable rewind duration.
                            Text(verbatim: formattedTime(from: 0))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(verbatim: "\(entryCount) snapshots")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                            Text(verbatim: formattedTime(from: newestFrame - oldestFrame))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 44 + 64)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: hasBuffer)
        .animation(.easeInOut(duration: 0.2), value: runner.speedMultiplier)
        .animation(.easeInOut(duration: 0.2), value: runner.isRewinding)
        .onReceive(pollTimer) { _ in
            updateBufferInfo()
        }
        .onChange(of: runner.isRewinding) { _, isRewinding in
            // Refresh buffer snapshot whenever TM scrub mode is entered/exited.
            // The pollTimer fires every 0.5s, but the user may re-enter scrub
            // mode immediately after resuming — without this the overlay still
            // shows the pre-truncate total (e.g., 20s instead of 10s) until the
            // next poll cycle.
            updateBufferInfo()
            if isRewinding {
                // Snap the slider's stored value to the live scrub position
                // when entering scrub mode, so dragging starts from the
                // current playhead rather than whatever the last slider
                // position was.
                sliderValue = scrubProgress
            }
        }
        .onAppear {
            overlayEnabled = AppSettings.getBool("timeMachine_overlayEnabled", defaultValue: true)
            updateBufferInfo()
        }
    }

    /// Hint text shown while in Time Machine scrub mode. Reads the user's
    /// actual rewind hotkey and the keyboard keys they've bound to the
    /// core's left/right (if any), so it always matches their config.
    private var scrubHint: String {
        let resumeKey = hotkeys.config[.rewind]?.primary.displayString
            ?? hotkeys.config[.rewind]?.secondary.displayString
            ?? "—"
        let leftName = runner.cachedKeyboardMapping.buttons[.left]
            .map { HotkeyBinding.keyName(for: $0) }
        let rightName = runner.cachedKeyboardMapping.buttons[.right]
            .map { HotkeyBinding.keyName(for: $0) }
        let moveHint: String
        if let l = leftName, let r = rightName {
            moveHint = "\(l) / \(r)"
        } else if let l = leftName {
            moveHint = "\(l) / →"
        } else if let r = rightName {
            moveHint = "← / \(r)"
        } else {
            moveHint = "← / →"
        }
        return "\(moveHint) to move, \(resumeKey) to resume"
    }

    /// Slider progress 0..1 based on the live scrub playhead rather than the
    /// newest captured frame. Reacts to timeMachineScrubFrameIndex changes.
    private var scrubProgress: Double {
        guard hasBuffer, newestFrame > oldestFrame else { return 1.0 }
        let scrub = runner.timeMachineScrubFrameIndex
        guard scrub >= oldestFrame else { return 0.0 }
        if scrub > newestFrame { return 1.0 }
        return Double(scrub - oldestFrame) / Double(newestFrame - oldestFrame)
    }

    private func updateBufferInfo() {
        let buf = runner.timeMachineBuffer
        oldestFrame = buf.oldestFrameIndex ?? 0
        newestFrame = buf.newestFrameIndex ?? 0
        entryCount = buf.entryCount
        hasBuffer = entryCount > 1
    }

    private func seekToSliderPosition() {
        guard hasBuffer, newestFrame > oldestFrame else { return }
        let target = oldestFrame + UInt64(sliderValue * Double(newestFrame - oldestFrame))
        Task { @MainActor in
            _ = runner.rewindToFrame(target)
        }
    }

    private func formattedTime(from frameIndex: UInt64) -> String {
        let seconds = Int(frameIndex / 60)
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

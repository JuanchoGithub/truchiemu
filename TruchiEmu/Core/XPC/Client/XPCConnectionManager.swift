import Foundation
import AppKit

final class XPCConnectionManager: ObservableObject {
    static let shared = XPCConnectionManager()

    // Set immediately on crash detection (from any thread) to short-circuit
    // NSHostingView layout in the vulnerable window between crash and cleanup.
    nonisolated(unsafe) static var isShuttingDown = false

    private var connection: NSXPCConnection?
    private let lock = NSLock()
    private var _hostProxy: CoreHostProtocol?
    private var _isConnected = false
    private(set) var lastCrashMessage: String?

    // Watchdog: if the XPC service doesn't respond to pings for 3+ seconds,
    // it's hung (core infinite loop) — send SIGKILL to trigger crash recovery.
    private var watchdogTimer: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "truchiemu.xpc.watchdog", qos: .background)
    private var lastPingResponse: Date = .distantPast
    private var servicePID: Int32 = 0

    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case interrupted
        case invalidated(error: String?)
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    var hostProxy: CoreHostProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return _hostProxy
    }

    private init() {}

    func connect() {
        Self.isShuttingDown = false

        // Tear down any stale connection first so we always get a fresh XPC service.
        // Prevents "Launch failed — XPC service not connected" after a core crash.
        disconnect()

        connectionState = .connecting

        let conn = NSXPCConnection(serviceName: "com.TruchiEmu.CoreHost")
        let hostInterface = NSXPCInterface(with: CoreHostProtocol.self)
        hostInterface.setClasses(NSSet(object: IOSurface.self) as Set, for: #selector(CoreHostProtocol.setIOSurfaceForVideo(_:reply:)), argumentIndex: 0, ofReply: false)
        conn.remoteObjectInterface = hostInterface
        conn.exportedInterface = NSXPCInterface(with: CoreClientProtocol.self)
        conn.exportedObject = CoreClientDelegate.shared

        conn.interruptionHandler = { [weak self] in
            self?.handleDisconnect(.interrupted)
        }

        conn.invalidationHandler = { [weak self] in
            self?.handleDisconnect(.invalidated(error: nil))
        }

        lock.lock()
        self.connection = conn
        lock.unlock()
        conn.resume()

        servicePID = 0

        let sem = DispatchSemaphore(value: 0)
        let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.handleDisconnect(.invalidated(error: error.localizedDescription))
            sem.signal()
        }) as! CoreHostProtocol

        lock.lock()
        self._hostProxy = proxy
        self._isConnected = true
        self.connectionState = .connected
        lock.unlock()
        sem.signal()
        startWatchdog()
        LoggerService.info(category: "XPC", "Connected to CoreHost service (PID \(servicePID))")
    }

    func disconnect() {
        stopWatchdog()
        lock.lock()
        let conn = connection
        connection = nil
        _hostProxy = nil
        _isConnected = false
        connectionState = .disconnected
        lock.unlock()
        conn?.invalidate()
    }

    var remoteProxy: CoreHostProtocol? {
        lock.lock()
        defer { lock.unlock() }
        guard _isConnected else { return nil }
        return _hostProxy
    }

    var synchronousProxy: CoreHostProtocol? {
        lock.lock()
        defer { lock.unlock() }
        guard _isConnected, let connection = connection else { return nil }
        return connection.synchronousRemoteObjectProxyWithErrorHandler({ _ in }) as? CoreHostProtocol
    }

    private func handleDisconnect(_ state: ConnectionState) {
        // Set immediately from this thread (XPC queue) so SafeHostingView can
        // short-circuit layout before the main-thread cleanup runs.
        Self.isShuttingDown = true
        stopWatchdog()

        lock.lock()
        let oldConnection = connection
        connection = nil
        _hostProxy = nil
        let wasConnected = _isConnected
        _isConnected = false
        lock.unlock()

        // Invalidate the stale NSXPCConnection so the next connect() call
        // can create a fresh one instead of returning early.
        oldConnection?.invalidate()

        if case .interrupted = state {
            LoggerService.warning(category: "XPC", "Connection interrupted — service may have crashed")
        } else {
            LoggerService.error(category: "XPC", "Connection invalidated — service terminated")
        }

        if wasConnected {
            lastCrashMessage = "Core service crashed unexpectedly"
        }

        // @Published property must be updated on main thread to avoid
        // SwiftUI re-rendering mid-layout with inconsistent state
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = state
            if wasConnected {
                self?.closeGameWindowsAfterCrash()
            }
        }
    }

    private func closeGameWindowsAfterCrash() {
        Task { @MainActor in
            let controllers = GameLauncher.shared.allActiveControllers()
            let hadGameWindows = !controllers.isEmpty

            // Show in-window error overlay on each active controller.
            // The overlay replaces game content and lets the user dismiss it,
            // which closes the window and cleans up the controller.
            for controller in controllers {
                controller.showErrorOverlay(.coreServiceCrashed)
            }

            // If no controllers have windows (edge case), clean up directly.
            if !hadGameWindows {
                GameLauncher.shared.closeAllGameWindows()
            }

            RunningGamesTracker.shared.resetAll()

            if !hadGameWindows {
                XPCBridgeAdapter.shared.stop()
            }
        }
    }

    // MARK: - PID Capture

    private func captureServicePID() {
        guard servicePID == 0 else { return }
        lock.lock()
        let conn = connection
        lock.unlock()
        guard let conn = conn else { return }
        let pid = conn.processIdentifier
        if pid > 0 {
            servicePID = pid
            LoggerService.info(category: "XPC", "Captured CoreHost service PID \(pid)")
        }
    }

    // MARK: - Watchdog

	private func startWatchdog() {
		stopWatchdog()
		lastPingResponse = Date.distantPast
		let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
		timer.schedule(deadline: .now() + 1, repeating: .seconds(1), leeway: .milliseconds(500))
		timer.setEventHandler { [weak self] in
			self?.watchdogTick()
		}
		timer.resume()
		watchdogTimer = timer
	}

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

	private func watchdogTick() {
		let elapsed = Date().timeIntervalSince(lastPingResponse)
		if elapsed > 6 && lastPingResponse != .distantPast {
			LoggerService.error(category: "XPC", "Watchdog: no ping response for \(Int(elapsed))s — killing service PID \(servicePID)")
			killService()
			return
		}
		remoteProxy?.ping { [weak self] in
			self?.lastPingResponse = Date()
			self?.captureServicePID()
		}
	}

    private func killService() {
        guard servicePID > 0 else { return }
        kill(servicePID, SIGKILL)
        LoggerService.warning(category: "XPC", "Sent SIGKILL to service PID \(servicePID)")
        cleanupAfterKillService()
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .interrupted
            self?.lastCrashMessage = "Core service killed by watchdog (unresponsive)"
            self?.closeGameWindowsAfterCrash()
        }
    }

    private func cleanupAfterKillService() {
        lock.lock()
        connection = nil
        _hostProxy = nil
        let wasConnected = _isConnected
        _isConnected = false
        lock.unlock()
        servicePID = 0
    }

    func forceKillServiceForAppExit() {
        lock.lock()
        let pid = servicePID
        let conn = connection
        lock.unlock()
        if pid > 0 {
            kill(pid, SIGKILL)
            LoggerService.info(category: "XPC", "App exiting — sent SIGKILL to service PID \(pid)")
        }
        conn?.invalidate()
    }
}

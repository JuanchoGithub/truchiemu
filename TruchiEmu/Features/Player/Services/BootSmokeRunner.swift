import Foundation
import AppKit

/// One-shot automated boot-smoke harness.
///
/// Triggered from `ContentView.task` only when the environment variable
/// `TRUCHI_SMOKE_ROM` is set to a path of a ROM file. Optionally
/// `TRUCHI_SMOKE_CORE` forces a libretro core ID; otherwise the core is
/// resolved through `ROMIdentifier` + `CoreManager` (the normal path).
/// Launches through the same `GameLauncher.shared.launchGame` pipeline the UI
/// uses, so a run exercises launch config resolution, the runner, the XPC
/// bridge, and the libretro core load. The companion `scripts/smoke_test.sh`
/// drives runs and asserts on the "First frame received" log line.
enum BootSmokeRunner {

    static func runIfNeeded(library: ROMLibrary) {
        guard let romPath = ProcessInfo.processInfo.environment["TRUCHI_SMOKE_ROM"],
              !romPath.isEmpty else { return }
        Task { @MainActor in
            await runBootSmoke(romPath: romPath, library: library)
        }
    }

    @MainActor
    private static func runBootSmoke(romPath: String, library: ROMLibrary) async {
        let url = URL(fileURLWithPath: romPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            LoggerService.info(category: "BootSmoke", "ROM not found: \(romPath)")
            return
        }

        var rom = ROM(name: url.lastPathComponent, path: url)
        rom.fileExtension = url.pathExtension.lowercased()
        rom.filenameWithoutExtension = url.deletingPathExtension().lastPathComponent
        rom.displayName = url.lastPathComponent

        var coreID: String?
        if let forced = ProcessInfo.processInfo.environment["TRUCHI_SMOKE_CORE"], !forced.isEmpty {
            coreID = forced
        }
        // MAME identification loads the full DAT (~30k entries, slow on a cold
        // process) and is not needed for a boot test — the dependency check
        // runs regardless. Skip it only for MAME-family cores.
        let isMAMECore = coreID.map(MAMEDependencyService.isMAMECore) ?? false
        if !isMAMECore,
           let system = await ROMIdentifier.identifySystem(url: url, extension: url.pathExtension) {
            rom.systemID = system.id
            if coreID == nil {
                coreID = CoreManager.shared.resolveCoreID(for: rom, system: system)
            }
        }
        guard let resolvedCoreID = coreID else {
            LoggerService.info(category: "BootSmoke", "No core resolved for \(romPath)")
            return
        }

        LoggerService.info(category: "BootSmoke", "Launching smoke ROM: \(url.path) core=\(resolvedCoreID)")
        await GameLauncher.shared.launchGame(rom: rom, coreID: resolvedCoreID, library: library)
    }
}
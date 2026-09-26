import Foundation

/// Provisions a Vulkan loader (MoltenVK) for cores that create their own
/// Vulkan instance, e.g. suyu which renders headless to a CPU buffer.
/// The loader must exist before the core loads; the bridge then exports it
/// via $LIBVULKAN_PATH (see VulkanLibraryHelper). Order: vendored copy,
/// well-known local app bundles, download of the MoltenVK release tarball.
final class VulkanLibraryService {
    static let shared = VulkanLibraryService()

    private let fm = FileManager.default

    var vendorDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TruchiEmu/Vendor/MoltenVK", isDirectory: true)
    }

    private let fileNames = ["libMoltenVK.dylib", "libvulkan.1.dylib", "libvulkan.dylib"]

    /// Well-known local bundles that ship a usable MoltenVK (checked in order).
    private let donorPaths = [
        "/Applications/eden.app/Contents/Frameworks/libMoltenVK.dylib",
        "/Applications/RetroArch.app/Contents/Frameworks/MoltenVK.framework/MoltenVK",
        "/Applications/Ryujinx.app/Contents/Frameworks/libMoltenVK.dylib",
        "/Applications/Cemu.app/Contents/Frameworks/libMoltenVK.dylib",
        "/Applications/RPCS3.app/Contents/Frameworks/libMoltenVK.dylib",
        "/Applications/Stremio.app/Contents/MacOS/libvulkan.1.dylib",
    ]

    /// Pinned MoltenVK release proven with the vendored suyu core lineage.
    private let moltenVKDownloadURL = URL(string: "https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.1/MoltenVK-all.tar")!

    func resolvedURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["LIBVULKAN_PATH"], !env.isEmpty,
           fm.fileExists(atPath: env) {
            return URL(fileURLWithPath: env)
        }
        for name in fileNames {
            let url = vendorDir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Ensures a Vulkan loader exists, provisioning it when needed.
    func ensureMoltenVK() async -> URL? {
        if let found = resolvedURL() { return found }
        try? fm.createDirectory(at: vendorDir, withIntermediateDirectories: true)
        if let copied = copyFromDonor() { return copied }
        return await downloadMoltenVK()
    }

    private func copyFromDonor() -> URL? {
        for path in donorPaths where fm.fileExists(atPath: path) {
            let src = URL(fileURLWithPath: path)
            let dest = vendorDir.appendingPathComponent("libMoltenVK.dylib")
            try? fm.removeItem(at: dest)
            do {
                try fm.copyItem(at: src, to: dest)
                adHocSign(path: dest.path)
                LoggerService.info(category: "Vulkan", "Vendored MoltenVK from \(path)")
                return dest
            } catch {
                LoggerService.warning(category: "Vulkan", "Donor copy failed for \(path): \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func downloadMoltenVK() async -> URL? {
        LoggerService.info(category: "Vulkan", "Downloading MoltenVK \(moltenVKDownloadURL.lastPathComponent)")
        do {
            let (tmpURL, response) = try await URLSession.shared.download(from: moltenVKDownloadURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                LoggerService.error(category: "Vulkan", "MoltenVK download HTTP \(http.statusCode)")
                return nil
            }
            // Find the macOS dynamic dylib member inside the tarball.
            let list = Process()
            list.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            list.arguments = ["-tf", tmpURL.path]
            let pipe = Pipe()
            list.standardOutput = pipe
            try list.run()
            list.waitUntilExit()
            let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard let member = listing.split(separator: "\n").map(String.init)
                .first(where: { $0.hasSuffix("macOS/libMoltenVK.dylib") || $0.hasSuffix("macOS/libvulkan.dylib") }) else {
                LoggerService.error(category: "Vulkan", "No macOS MoltenVK dylib in tarball")
                return nil
            }
            let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmpDir) }
            let extract = Process()
            extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            extract.arguments = ["-xf", tmpURL.path, "-C", tmpDir.path, member]
            try extract.run()
            extract.waitUntilExit()
            guard extract.terminationStatus == 0 else { return nil }
            let extracted = tmpDir.appendingPathComponent(member)
            let dest = vendorDir.appendingPathComponent("libMoltenVK.dylib")
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: extracted, to: dest)
            adHocSign(path: dest.path)
            LoggerService.info(category: "Vulkan", "Vendored downloaded MoltenVK")
            return dest
        } catch {
            LoggerService.error(category: "Vulkan", "MoltenVK download failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func adHocSign(path: String) {
        #if arch(arm64)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-s", "-", "--force", path]
        try? proc.run()
        proc.waitUntilExit()
        #endif
    }
}

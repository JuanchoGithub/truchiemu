import Foundation

struct InputButtonDescriptor: Codable {
    let id: Int
    let description: String
}

class InputDescriptorsManager {
    static let shared = InputDescriptorsManager()

    private let definitionsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TruchiEmu/InputDescriptors", isDirectory: true)
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: definitionsDirectory, withIntermediateDirectories: true)
    }

    nonisolated func loadFromDisk(for coreID: String) -> [InputButtonDescriptor]? {
        let defURL = definitionsDirectory.appendingPathComponent("\(coreID).json")
        guard let data = try? Data(contentsOf: defURL),
              let loaded = try? decoder.decode([InputButtonDescriptor].self, from: data) else {
            return nil
        }
        return loaded
    }

    func setDescriptors(_ newDescriptors: [InputButtonDescriptor], for coreID: String) {
        persistToDisk(newDescriptors, for: coreID)
    }

    private func persistToDisk(_ descs: [InputButtonDescriptor], for coreID: String) {
        let defURL = definitionsDirectory.appendingPathComponent("\(coreID).json")
        guard let data = try? encoder.encode(descs) else { return }
        try? data.write(to: defURL)
    }

    nonisolated func availableButtons(for systemID: String) -> [RetroButton]? {
        guard let defaultCoreID = SystemDatabase.system(forID: systemID)?.defaultCoreID,
              let descs = loadFromDisk(for: defaultCoreID) else {
            return nil
        }
        return convertToRetroButtons(descs)
    }

    private func convertToRetroButtons(_ inputDescriptors: [InputButtonDescriptor]) -> [RetroButton] {
        var result: [RetroButton] = []

        let buttonIDMapping: [Int: RetroButton] = [
            0: .b,
            1: .y,
            2: .select,
            3: .start,
            4: .up,
            5: .down,
            6: .left,
            7: .right,
            8: .a,
            9: .x,
            10: .l1,
            11: .r1,
            12: .l2,
            13: .r2,
            14: .l3,
            15: .r3
        ]

        for desc in inputDescriptors {
            if let button = buttonIDMapping[desc.id] {
                if !result.contains(button) {
                    result.append(button)
                }
            }
        }

        return result
    }
}

extension InputDescriptorsManager {
    @MainActor
    func discoverDescriptors(for coreID: String, dylibPath: String, romPath: String?) async {
        // Input descriptors are now captured during CoreOptionsManager.discoverOptions
        // Just load from disk here - if not found, that's ok (core may not have set any)
        LoggerService.debug(category: "InputDescriptorsManager", "Checking existing descriptors for core: \(coreID)")

        if let descriptors = loadFromDisk(for: coreID) {
            LoggerService.debug(category: "InputDescriptorsManager", "Found \(descriptors.count) input descriptors on disk for \(coreID)")
        } else {
            LoggerService.debug(category: "InputDescriptorsManager", "No input descriptors found on disk for \(coreID)")
        }
    }
}
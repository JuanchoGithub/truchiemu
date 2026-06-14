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

    nonisolated func descriptorLabel(for retroID: Int, coreID: String) -> String? {
        guard let descs = loadFromDisk(for: coreID) else { return nil }
        return descs.first(where: { $0.id == retroID })?.description
    }

    nonisolated func availableButtons(for systemID: String) -> [RetroButton]? {
        guard let defaultCoreID = SystemDatabase.system(forID: systemID)?.defaultCoreID,
              let descs = loadFromDisk(for: defaultCoreID) else {
            return nil
        }
        return convertToRetroButtons(descs, coreID: defaultCoreID)
    }

    nonisolated func retroID(for button: RetroButton, coreID: String) -> Int? {
        guard let descs = loadFromDisk(for: coreID) else { return nil }
        let expectedDesc = CoreButtonOverride.shared.label(for: button, coreID: coreID)
            ?? button.displayName(for: nil)
        return descs.first(where: { $0.description == expectedDesc })?.id
    }

    private func convertToRetroButtons(_ inputDescriptors: [InputButtonDescriptor], coreID: String) -> [RetroButton] {
        var result: [RetroButton] = []

        for desc in inputDescriptors {
            let matchingButton = RetroButton.allCases.first { button in
                let label = CoreButtonOverride.shared.label(for: button, coreID: coreID)
                    ?? button.displayName(for: nil)
                return label == desc.description
            }
            if let button = matchingButton, !result.contains(button) {
                result.append(button)
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
        #if LOG_DEBUG
        LoggerService.debug(category: "InputDescriptorsManager", "Checking existing descriptors for core: \(coreID)")
        #endif

        if let descriptors = loadFromDisk(for: coreID) {
            #if LOG_DEBUG
            LoggerService.debug(category: "InputDescriptorsManager", "Found \(descriptors.count) input descriptors on disk for \(coreID)")
            #endif
        } else {
            #if LOG_DEBUG
            LoggerService.debug(category: "InputDescriptorsManager", "No input descriptors found on disk for \(coreID)")
            #endif
        }
    }
}
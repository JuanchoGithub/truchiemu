//
//  SaveDirectoryBridge.swift
//  Bridge between SaveDirectoryManager and Objective-C++ code
//  

import Foundation

@objc(SaveDirectoryBridge) public class SaveDirectoryBridge: NSObject {
    #if XPC_SERVICE
    private static var _savePath: String = ""
    private static var _systemPath: String = ""

    @objc static func setSavePath(_ path: String) { _savePath = path }
    @objc static func setSystemPath(_ path: String) { _systemPath = path }

    @objc static func libretroSaveDirectoryPath() -> String { _savePath }
    @objc static func libretroSystemDirectoryPath() -> String { _systemPath }
    @objc static func ensureDirectoriesExist() {
        if !_savePath.isEmpty {
            try? FileManager.default.createDirectory(atPath: _savePath, withIntermediateDirectories: true)
        }
        if !_systemPath.isEmpty {
            try? FileManager.default.createDirectory(atPath: _systemPath, withIntermediateDirectories: true)
        }
    }
    #else
    @objc static func libretroSaveDirectoryPath() -> String {
        SaveDirectoryManager.shared.savefilesDirectory.path
    }

    @objc static func libretroSystemDirectoryPath() -> String {
        SaveDirectoryManager.shared.systemDirectory.path
    }

    @objc static func ensureDirectoriesExist() {
        _ = SaveDirectoryManager.shared
    }
    #endif
}
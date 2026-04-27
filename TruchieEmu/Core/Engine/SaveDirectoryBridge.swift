//
//  SaveDirectoryBridge.swift
//  Bridge between SaveDirectoryManager and Objective-C++ code
//  

import Foundation

/// Swift implementation of the Objective-C bridge for SaveDirectoryManager
@objc(SaveDirectoryBridge)
public class SaveDirectoryBridge: NSObject {
    
    @objc static func libretroSaveDirectoryPath() -> String {
        SaveDirectoryManager.shared.savefilesDirectory.path
    }
    
    @objc static func libretroSystemDirectoryPath() -> String {
        SaveDirectoryManager.shared.systemDirectory.path
    }

  // Called to ensure directory structure is created
  @objc static func ensureDirectoriesExist() {
    _ = SaveDirectoryManager.shared
  }
}
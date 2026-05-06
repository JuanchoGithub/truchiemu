#!/usr/bin/env swift
import Foundation

func testBundleAccess() {
    let testFiles = ["saturn_bios.bin", "mpr-17933.bin", "sega_101.bin"]
    
    print("Testing Bundle.main.url access for BIOS files...")
    print("Current directory: \(FileManager.default.currentDirectoryPath)")
    print()
    
    for file in testFiles {
        // Old method (incorrect)
        let oldUrl = Bundle.main.url(forResource: "System/\(file)", withExtension: nil)
        print("\(file) with old method (System/\(file)): \(oldUrl != nil ? "✅ FOUND" : "❌ NOT FOUND")")
        
        // New method (correct)
        let newUrl = Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "System")
        print("\(file) with new method (subdirectory: System): \(newUrl != nil ? "✅ FOUND" : "❌ NOT FOUND")")
        print()
    }
}

testBundleAccess()

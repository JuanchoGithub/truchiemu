//
//  EnvironmentDiagnostics.swift
//  TruchiEmu
//
//  Diagnostic tool for debugging environment propagation

import SwiftUI
import Foundation

/// Diagnostic wrapper that logs when systemDatabase is accessed
struct EnvironmentGuard<T: View>: View {
  let content: T
  let location: String
  
  init(location: String, @ViewBuilder content: () -> T) {
    self.location = location
    self.content = content()
    print("[ENV-DEBUG] Creating EnvironmentGuard at: \(location)")
  }
  
  var body: some View {
    Group {
      content
    }
    .onAppear {
      print("[ENV-DEBUG] ✅ EnvironmentGuard appeared at: \(location)")
    }
    .onDisappear {
      print("[ENV-DEBUG] ❌ EnvironmentGuard disappeared at: \(location)")
    }
  }
}

/// Diagnostic view that captures and verifies environment
struct SystemDatabaseEnvironmentCapture: View {
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  let location: String
  
  init(location: String) {
    self.location = location
  }
  
  var body: some View {
    VStack {
      Text("SystemDatabase captured at: \(location)")
        .font(.caption)
      Text("Available: YES")
        .font(.caption)
    }
    .onAppear {
      print("[ENV-DEBUG] ✅ SystemDatabase captured at: \(location)")
    }
  }
}

/// Diagnostic version of SaveDirectoriesSection with aggressive environment capture
public struct DebugSaveDirectoriesSection: View {
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  
  public init() {
    print("[ENV-DEBUG] Initializing DebugSaveDirectoriesSection")
  }
  
  public var body: some View {
    EnvironmentGuard(location: "DebugSaveDirectoriesSection.body") {
      VStack {
        SystemDatabaseEnvironmentCapture(location: "DebugSaveDirectoriesSection.inner")
        
        // Nested view hierarchy to test propagation
        Group {
          Text("Save Directories")
            .font(.headline)
          
          Button("Open Settings") {
            print("[ENV-DEBUG] Button tapped - systemDatabase available: YES")
          }
        }
        .onAppear {
          print("[ENV-DEBUG] ✅ Group appeared with systemDatabase")
        }
      }
    }
    .onAppear {
      print("[ENV-DEBUG] ✅ DebugSaveDirectoriesSection appeared")
    }
    .onDisappear {
      print("[ENV-DEBUG] ❌ DebugSaveDirectoriesSection disappeared")
    }
  }
}

/// Diagnostic wrapper that ensures environment is maintained
public struct PreventEnvironmentLoss<T: View>: View {
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  let content: T
  
  public init(@ViewBuilder content: () -> T) {
    self.content = content()
  }
  
  public var body: some View {
    Group {
      content
    }
    .environment(systemDatabase)
    .onAppear {
      print("[ENV-DEBUG] ✅ Environment re-propagated manually")
    }
  }
}
//
//  SaveDirectoriesSection.swift
//  TruchiEmu
//
//  Mechanical fix: Ensures SystemDatabaseWrapper environment is never lost

import SwiftUI

/// Mechanical fix: Forces environment propagation
public struct SaveDirectoriesSection: View {
  // CAPTURE environment at this level
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  
  public init() {
    print("[ENV-MECH] SaveDirectoriesSection initialized - captured systemDatabase")
  }
  
  public var body: some View {
    // RE-INJECT environment forcefully to ensure child views receive it
    SaveDirectorySettingsView()
      .environment(systemDatabase)
      .onAppear {
        print("[ENV-MECH] ✅ SaveDirectoriesSection appeared - environment re-injected")
      }
  }
}
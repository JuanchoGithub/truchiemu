#if LOG_DEBUG
import SwiftUI
import Foundation

struct EnvironmentGuard<T: View>: View {
  let content: T
  let location: String
  
  init(location: String, @ViewBuilder content: () -> T) {
    self.location = location
    self.content = content()
    LoggerService.debug(category: "EnvDiagnostics", "Creating EnvironmentGuard at: \(location)")
  }
  
  var body: some View {
    Group {
      content
    }
    .onAppear {
      LoggerService.debug(category: "EnvDiagnostics", "EnvironmentGuard appeared at: \(location)")
    }
    .onDisappear {
      LoggerService.debug(category: "EnvDiagnostics", "EnvironmentGuard disappeared at: \(location)")
    }
  }
}

struct SystemDatabaseEnvironmentCapture: View {
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  @ObservedObject private var loc = LocalizationManager.shared
  let location: String

  init(location: String) {
    self.location = location
  }

  var body: some View {
    VStack {
      Text(loc.localized("diagnostics.systemDatabaseCaptured") + " \(location)")
        .font(.caption)
      Text(loc.localized("diagnostics.availableYes"))
        .font(.caption)
    }
    .onAppear {
      LoggerService.debug(category: "EnvDiagnostics", "SystemDatabase captured at: \(location)")
    }
  }
}

public struct DebugSaveDirectoriesSection: View {
  @Environment(SystemDatabaseWrapper.self) private var systemDatabase
  @ObservedObject private var loc = LocalizationManager.shared

  public init() {
    LoggerService.debug(category: "EnvDiagnostics", "Initializing DebugSaveDirectoriesSection")
  }

  public var body: some View {
    EnvironmentGuard(location: "DebugSaveDirectoriesSection.body") {
      VStack {
        SystemDatabaseEnvironmentCapture(location: "DebugSaveDirectoriesSection.inner")

        Group {
          Text(loc.localized("saveDirectories.title"))
            .font(.headline)

          Button(loc.localized("app.openSettings")) {
            LoggerService.debug(category: "EnvDiagnostics", "Button tapped - systemDatabase available: YES")
          }
        }
        .onAppear {
          LoggerService.debug(category: "EnvDiagnostics", "Group appeared with systemDatabase")
        }
      }
    }
    .onAppear {
      LoggerService.debug(category: "EnvDiagnostics", "DebugSaveDirectoriesSection appeared")
    }
    .onDisappear {
      LoggerService.debug(category: "EnvDiagnostics", "DebugSaveDirectoriesSection disappeared")
    }
  }
}

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
      LoggerService.debug(category: "EnvDiagnostics", "Environment re-propagated manually")
    }
  }
}
#endif

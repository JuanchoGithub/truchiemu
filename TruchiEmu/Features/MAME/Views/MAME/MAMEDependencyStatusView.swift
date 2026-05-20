import SwiftUI

struct MAMEDependencyStatusView: View {
  let rom: ROM
  let coreID: String?

  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var loc = LocalizationManager.shared
  @State private var dependencies: [MAMEDependencyInfo] = []

  private var hasMissingDependencies: Bool {
    dependencies.contains { !$0.isAvailable }
  }

  var body: some View {
    ModernSectionCard(title: loc.localized("mame.dependencies.title"), icon: "folder.badge.gearshape") {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: AppSpacing.md) {
          Image(systemName: hasMissingDependencies ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .foregroundColor(hasMissingDependencies ? .orange : .green)
            .font(.title3)

          Text(hasMissingDependencies ? loc.localized("mame.dependencies.missingFiles") : loc.localized("mame.dependencies.allAvailable"))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(hasMissingDependencies ? .orange : .green)

          Spacer()
        }
        .padding(.vertical, AppSpacing.xs)

        Divider().overlay(AppColors.divider(colorScheme))

        if dependencies.isEmpty {
          Text(loc.localized("mame.dependencies.loading"))
            .font(.caption)
            .foregroundColor(AppColors.textSecondary(colorScheme))
            .padding(.vertical, AppSpacing.xs)
        } else {
          ForEach(dependencies) { dep in
            dependencyRow(dep)
          }
        }

        if hasMissingDependencies {
          Divider().overlay(AppColors.divider(colorScheme))

          VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc.localized("mame.dependencies.toFix"))
              .font(.caption)
              .fontWeight(.medium)
              .foregroundColor(AppColors.textSecondary(colorScheme))

            Text(loc.localized("mame.dependencies.fixInstructions"))
              .font(.caption)
              .foregroundColor(AppColors.textTertiary(colorScheme))
              .lineSpacing(2)
          }
          .padding(AppSpacing.md)
          .background(AppColors.cardBackgroundSubtle(colorScheme))
          .cornerRadius(AppRadius.md)
          .padding(.vertical, AppSpacing.xs)
        }
      }
    }
    .task(id: rom.id) {
      await loadDependencies()
    }
  }

  private func loadDependencies() async {
    let shortName = rom.shortNameForMAME
    let romsDirectory = rom.path.deletingLastPathComponent()

    var deps: [MAMEDependencyInfo] = []

    deps.append(MAMEDependencyInfo(
      name: "\(shortName).zip",
      description: loc.localized("mame.dependencies.mainROM"),
      isAvailable: FileManager.default.fileExists(atPath: rom.path.path),
      isRequired: true
    ))

    if let entry = MAMEUnifiedService.shared.lookup(shortName: shortName),
       let coreDeps = entry.coreDeps {
      for (_, dep) in coreDeps {
        if let cloneOf = dep.cloneOf, !cloneOf.isEmpty {
          let parentPath = romsDirectory.appendingPathComponent("\(cloneOf).zip")
          deps.append(MAMEDependencyInfo(
            name: "\(cloneOf).zip",
            description: loc.localized("mame.dependencies.parentROMClone"),
            isAvailable: FileManager.default.fileExists(atPath: parentPath.path),
            isRequired: true
          ))
        }

        if let romOf = dep.romOf, !romOf.isEmpty {
          let devicePath = romsDirectory.appendingPathComponent("\(romOf).zip")
          deps.append(MAMEDependencyInfo(
            name: "\(romOf).zip",
            description: loc.localized("mame.dependencies.deviceROM"),
            isAvailable: FileManager.default.fileExists(atPath: devicePath.path),
            isRequired: true
          ))
        }

        if let sampleOf = dep.sampleOf, !sampleOf.isEmpty {
          let samplePath = romsDirectory.appendingPathComponent("\(sampleOf).zip")
          deps.append(MAMEDependencyInfo(
            name: "\(sampleOf).zip",
            description: loc.localized("mame.dependencies.sampleROM"),
            isAvailable: FileManager.default.fileExists(atPath: samplePath.path),
            isRequired: false
          ))
        }

        if let merged = dep.mergedROMs {
          for mergedName in merged {
            let mergedPath = romsDirectory.appendingPathComponent("\(mergedName).zip")
            deps.append(MAMEDependencyInfo(
              name: "\(mergedName).zip",
              description: loc.localized("mame.dependencies.mergedROM"),
              isAvailable: FileManager.default.fileExists(atPath: mergedPath.path),
              isRequired: true
            ))
          }
        }
      }
    }

    await MainActor.run {
      self.dependencies = deps
    }
  }

  @ViewBuilder
  private func dependencyRow(_ dep: MAMEDependencyInfo) -> some View {
    HStack(spacing: AppSpacing.md) {
      Image(systemName: dep.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundColor(dep.isAvailable ? .green : .red)
        .font(.system(size: 14))
        .frame(width: 18)

      VStack(alignment: .leading, spacing: AppSpacing.xxs) {
        Text(dep.name)
          .font(.body)
          .foregroundColor(AppColors.textPrimary(colorScheme))
          .monospaced()

        Text(dep.description)
          .font(.caption)
          .foregroundColor(AppColors.textTertiary(colorScheme))
      }

      Spacer()

      Text(dep.isAvailable ? loc.localized("mame.dependencies.available") : loc.localized("mame.dependencies.missing"))
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(dep.isAvailable ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .foregroundColor(dep.isAvailable ? .green : .red)
        .cornerRadius(AppRadius.sm)
    }
    .padding(AppSpacing.sm)
    .background(dep.isAvailable ? AppColors.cardBackgroundSubtle(colorScheme) : Color.red.opacity(0.05))
    .cornerRadius(AppRadius.md)
    .padding(.vertical, AppSpacing.xxs)
  }
}

struct MAMEDependencyInfo: Identifiable {
  let id = UUID()
  let name: String
  let description: String
  let isAvailable: Bool
  let isRequired: Bool
}

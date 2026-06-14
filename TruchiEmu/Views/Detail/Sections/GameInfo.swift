import SwiftUI

extension GameDetailView {
    var gameInfoSection: some View {
        VStack(spacing: AppSpacing.lg) {
            gameInfoActionButtons

            if !screenshotImages.isEmpty { screenshotsRow }

            gameMetadataCard

            MAMEDependencyStatusView(rom: currentROM, coreID: activeCoreID)

            if let description = gameDescription {
                ModernSectionCard(showHeader: false) {
                    Text(description)
                        .font(.body)
                        .foregroundColor(AppColors.textPrimary(colorScheme).opacity(0.85))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var gameInfoActionButtons: some View {
        HStack(spacing: AppSpacing.sm) {
            identifyButton
            fetchBoxArtButton
            fetchMetadataButton
        }
    }

    var gameMetadataCard: some View {
        ModernSectionCard(showHeader: false) {
            VStack(alignment: .leading, spacing: 0) {
                gameSystemPicker
                Divider().overlay(AppColors.divider(colorScheme))
                MetadataRow(label: loc.localized("gameInfo.fileName"), value: currentROM.path.lastPathComponent)
                Divider().overlay(AppColors.divider(colorScheme))
                MetadataRow(
                    label: loc.localized("gameInfo.path"),
                    value: currentROM.path.deletingLastPathComponent().path,
                    copyAction: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(currentROM.path.path, forType: .string)
                    }
                )
                if let size = fileSize {
                    Divider().overlay(AppColors.divider(colorScheme))
                    MetadataRow(label: loc.localized("gameInfo.fileSize"), value: size)
                }
            if let crc = crcHash {
                Divider().overlay(AppColors.divider(colorScheme))
                MetadataRow(
                    label: loc.localized("gameInfo.crc32"),
                    value: crc,
                    isMonospaced: true,
                    copyAction: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(crc, forType: .string)
                    }
                )
            }
            if achievementsService.isEnabled, currentROM.raMatchStatus == "matched" {
                Divider().overlay(AppColors.divider(colorScheme))
                HStack {
                    Image(systemName: "trophy.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
                    Text(loc.localized("gameInfo.retroAchievements"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(AppColors.success(colorScheme))
                        Text(loc.localized("gameInfo.raSupported"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.success(colorScheme))
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColors.success(colorScheme).opacity(0.12))
                    .cornerRadius(AppRadius.xs)
                }
                .padding(.vertical, AppSpacing.xs)
            }
                if let meta = currentROM.metadata {
                    gameMetadataRows(meta: meta)
                }
            }
        }
    }

  var gameSystemPicker: some View {
    HStack {
      Image(systemName: "gamecontroller").foregroundColor(AppColors.brandAccent).frame(width: 20)
      Text(loc.localized("gameInfo.system"))
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(AppColors.textPrimary(colorScheme))
      Spacer()
      Button {
        showSystemPicker = true
      } label: {
        HStack(spacing: 4) {
          Text(systemName)
            .font(.subheadline)
            .foregroundColor(AppColors.textPrimary(colorScheme))
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
            .foregroundColor(AppColors.textSecondary(colorScheme))
        }
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, AppSpacing.xs)
  }

    @ViewBuilder
    func gameMetadataRows(meta: ROMMetadata) -> some View {
        if let original = meta.title, currentROM.customName != nil {
            Divider().overlay(AppColors.divider(colorScheme))
            MetadataRow(label: loc.localized("gameInfo.originalName"), value: original)
        }
        if let dev = meta.developer {
            Divider().overlay(AppColors.divider(colorScheme))
            MetadataRow(label: loc.localized("gameInfo.developer"), value: dev)
        }
        if let pub = meta.publisher {
            Divider().overlay(AppColors.divider(colorScheme))
            MetadataRow(label: loc.localized("gameInfo.publisher"), value: pub)
        }
        if meta.genre != nil {
            Divider().overlay(AppColors.divider(colorScheme))
            MetadataRow(label: loc.localized("gameInfo.genre"), value: GenreManager.shared.effectiveDisplayName(for: meta.genre))
        }
        playersRow
      if let esrb = meta.esrbRating {
        Divider().overlay(AppColors.divider(colorScheme))
        HStack {
          Image(systemName: "shield.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
          Text(loc.localized("gameInfo.esrb"))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(AppColors.textPrimary(colorScheme))
          Spacer()
          Text(esrb)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(AppColors.textPrimary(colorScheme))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(esrbBadgeColor(for: esrb))
            .cornerRadius(AppRadius.xs)
        }
        .padding(.vertical, AppSpacing.xs)
      }
    }

    var identifyButton: some View {
        Button {
            Task {
                manualActionStatus = .working("Identifying from No-Intro database…")
                let result = await library.identifyROM(currentROM, preferNameMatch: false)
                switch result {
                case .identified(let info):
                    showManualResult("Found: \(currentROM.name) → \(info.name)", tone: .success)
                    var updated = currentROM
                    updated.customName = info.name
                    library.updateROM(updated)
                    if !currentROM.hasBoxArt {
                        if let _ = await BoxArtService.shared.fetchBoxArt(for: currentROM) {
                            var u = currentROM
                            u.hasBoxArt = true
                            library.updateROM(u)
                            loadBoxArt()
                        }
                    }
                    loadSlotInfo()
                case .identifiedFromName(let info):
                    showManualResult("Found: \(currentROM.name) → \(info.name) (matched by filename)", tone: .success)
                    var updated = currentROM
                    updated.customName = info.name
                    library.updateROM(updated)
                    if !currentROM.hasBoxArt {
                        if let _ = await BoxArtService.shared.fetchBoxArt(for: currentROM) {
                            var u = currentROM
                            u.hasBoxArt = true
                            library.updateROM(u)
                            loadBoxArt()
                        }
                    }
                    loadSlotInfo()
                case .crcNotInDatabase(let crc):
                    showManualResult("Couldn't identify this game. Try downloading metadata manually.", tone: .warning)
                    #if LOG_DEBUG
                    LoggerService.debug(category: "Identity", "For: \(currentROM.name) — Unknown game — CRC: \(crc)")
                    #endif
                case .identificationCleared:
                    showManualResult("Identification cleared — game will use ROM filename", tone: .success)
                case .databaseUnavailable:
                    showManualResult("Identification database unavailable. Check your internet connection.", tone: .error)
                case .romReadFailed(let reason):
                    showManualResult("Could not read this game: \(reason)", tone: .error)
                case .noSystem:
                    showManualResult("Cannot identify — system is not set for this file.", tone: .error)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if case .working = manualActionStatus { ProgressView().controlSize(.small) } else { Image(systemName: "qrcode.viewfinder") }
Text(loc.localized("gameInfo.identifyGame"))
        }
        .font(.subheadline)
        .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.brandAccent)
            .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
        .disabled(isIdentifyWorking)
    }

    var fetchMetadataButton: some View {
        Group {
            switch fetchMetadataStatus {
            case .hidden:
                Button { Task { await fetchMetadata() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                        Text(loc.localized("gameInfo.fetchMetadata"))
                    }
                    .font(.subheadline)
                    .foregroundColor(AppColors.brandAccent)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.brandAccent.opacity(0.15))
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)
            case .working(_):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(loc.localized("gameInfo.searchingLaunchBox"))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accentTertiary.opacity(0.5))
                .cornerRadius(AppRadius.md)
            case .result(let msg, let tone):
                Button { clearFetchMetadataStatus() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(msg).font(.caption).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(tone.foregroundColor.opacity(0.15))
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func fetchMetadata() async {
        await MainActor.run { fetchMetadataStatus = .working(loc.localized("gameInfo.searchingLaunchBox")) }
        let success = await LaunchBoxGamesDBService.shared.fetchAndApplyMetadata(for: currentROM, library: library)
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            if case .result = fetchMetadataStatus { fetchMetadataStatus = .hidden }
        }
        if success {
            await MainActor.run { fetchMetadataStatus = .result(loc.localized("gameInfo.metadataUpdated"), tone: .success) }
        } else {
            await MainActor.run { fetchMetadataStatus = .result(loc.localized("gameInfo.noMetadataFound"), tone: .warning) }
        }
    }

    func clearFetchMetadataStatus() {
        fetchMetadataAutoDismiss?.cancel()
        fetchMetadataAutoDismiss = nil
        fetchMetadataStatus = .hidden
    }

    var fetchBoxArtButton: some View {
        Group {
            switch fetchBoxArtStatus {
            case .hidden:
                Button { Task { await fetchBoxArt() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text(loc.localized("gameInfo.fetchArt"))
                    }
                    .font(.subheadline)
                    .foregroundColor(AppColors.brandAccent)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.brandAccent.opacity(0.15))
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)
            case .working(let msg):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(msg).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accentTertiary.opacity(0.5))
                .cornerRadius(AppRadius.md)
            case .result(let msg, let tone):
                Button { clearFetchBoxArtStatus() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(msg).font(.caption).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(tone.foregroundColor.opacity(0.15))
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func fetchBoxArt() async {
        await MainActor.run { fetchBoxArtStatus = .working(loc.localized("gameInfo.searching")) }
        if await BoxArtService.shared.fetchBoxArt(for: currentROM) != nil {
            var u = currentROM
            u.hasBoxArt = true
            library.updateROM(u)
            loadBoxArt()
            fetchBoxArtAutoDismiss?.cancel()
            fetchBoxArtAutoDismiss = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                if case .result = fetchBoxArtStatus { fetchBoxArtStatus = .hidden }
            }
            await MainActor.run { fetchBoxArtStatus = .result(loc.localized("gameInfo.artFound"), tone: .success) }
        } else {
            await MainActor.run { fetchBoxArtStatus = .result(loc.localized("gameInfo.noCoverArtFound"), tone: .warning) }
        }
    }

    func clearFetchBoxArtStatus() {
        fetchBoxArtAutoDismiss?.cancel()
        fetchBoxArtAutoDismiss = nil
        fetchBoxArtStatus = .hidden
    }

    var screenshotsRow: some View {
        ModernSectionCard(title: loc.localized("gameInfo.screenshots"), icon: "photo.on.rectangle", showHeader: true) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(screenshotImages.indices, id: \.self) { index in
                        Image(nsImage: screenshotImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 180, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.md).stroke(AppColors.cardBorder(colorScheme), lineWidth: 1))
                    }
                }
            }
        }
    }

    func esrbBadgeColor(for rating: String) -> Color {
        switch rating.lowercased() {
        case "ec", "e": return AppColors.success(colorScheme).opacity(0.4)
        case "e10+": return Color.blue.opacity(0.4)
        case "t": return Color.yellow.opacity(0.4)
        case "m", "ao": return AppColors.error(colorScheme).opacity(0.4)
        default: return AppColors.cardBackgroundSubtle(colorScheme)
        }
    }

    var playersRow: some View {
        Group {
            if let meta = currentROM.metadata, meta.players > 0 {
                let playersIdentifiedFromLibretro = meta.userPlayerOverride == nil && meta.players > 1
                if playersIdentifiedFromLibretro {
                    Divider().overlay(AppColors.divider(colorScheme))
                    MetadataRow(label: loc.localized("gameInfo.players"), value: String(meta.players))
                    if meta.players > 1 {
                        Divider().overlay(AppColors.divider(colorScheme))
                        MetadataRow(label: loc.localized("gameInfo.coop"), value: meta.cooperative ? loc.localized("gameInfo.yes") : loc.localized("gameInfo.no"))
                    }
                } else {
                    Divider().overlay(AppColors.divider(colorScheme))
                    playersPickerView(meta: meta)
                }
            }
        }
    }

  private func playersPickerView(meta: ROMMetadata) -> some View {
    HStack {
      Image(systemName: "person.2").foregroundColor(AppColors.brandAccent).frame(width: 20)
      Text(loc.localized("gameInfo.players"))
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(AppColors.textPrimary(colorScheme))
      Spacer()
      Picker("", selection: Binding(
        get: { meta.userPlayerOverride ?? 1 },
        set: { newValue in
          guard newValue > 0 else { return }
          Task { @MainActor in
            var updated = self.currentROM
            if updated.metadata == nil { updated.metadata = ROMMetadata() }
            updated.metadata?.userPlayerOverride = newValue
            updated.metadata?.players = newValue
            self.library.updateROM(updated)
          }
        }
      )) {
        Text(loc.localized("gameInfo.single")).tag(1)
        Text(loc.localized("gameInfo.multi")).tag(2)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 160)
    }
    .padding(.vertical, AppSpacing.xs)
  }
}
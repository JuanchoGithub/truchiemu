import SwiftUI

struct BoxArtUndoState {
    let romID: UUID
    let snapshot: BoxArtUndoSnapshot
    let newURL: URL
}

extension GameDetailView {
    var technicalSection: some View {
        VStack(spacing: AppSpacing.lg) {
            technicalActionButtons

            gameMetadataCard

            MAMEDependencyStatusView(rom: currentROM, coreID: activeCoreID)
        }
    }

    var technicalActionButtons: some View {
        HStack(spacing: AppSpacing.sm) {
            identifyButton
            matchGameButton
            fetchBoxArtButton
            fetchMetadataButton
        }
    }

    var gameMetadataCard: some View {
        ModernSectionCard(showHeader: false) {
            VStack(alignment: .leading, spacing: 0) {
                gameSystemPicker
                Divider().overlay(AppColors.divider(colorScheme))
                if currentROM.metadata?.manualMatch == true {
                    matchSourceRow
                    Divider().overlay(AppColors.divider(colorScheme))
                }
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
                if achievementsService.isEnabled, let hash = raHash {
                    Divider().overlay(AppColors.divider(colorScheme))
                    MetadataRow(
                        label: loc.localized("gameInfo.raHash"),
                        value: hash,
                        isMonospaced: true,
                        copyAction: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hash, forType: .string)
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

    var matchSourceRow: some View {
        HStack {
            Image(systemName: "hand.raised.fill").foregroundColor(AppColors.brandAccent).frame(width: 20)
            Text(loc.localized("gameInfo.matchSource"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary(colorScheme))
            Spacer()
            Text(loc.localized("gameInfo.matchSourceManual"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.brandAccent)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    func gameMetadataRows(meta: ROMMetadata) -> some View {
        if let original = meta.title, let custom = currentROM.customName, custom != original {
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
                manualAction.showWorking("Identifying from No-Intro database…")
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
                            loadTitleScreen()
                            loadScreenshots()
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
                            loadTitleScreen()
                            loadScreenshots()
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
                if manualAction.isWorking { ProgressView().controlSize(.small) } else { Image(systemName: "qrcode.viewfinder") }
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

    var matchGameButton: some View {
        Button {
            showManualMatch = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                Text(loc.localized("gameInfo.matchGame"))
            }
            .font(.subheadline)
            .foregroundColor(AppColors.textOnAccent(colorScheme))
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.brandAccentSecondary)
            .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
        .disabled(isIdentifyWorking)
    }

    var fetchMetadataButton: some View {
        Group {
            switch fetchMetadata.status {
            case .hidden:
                Button { Task { await fetchMetadata() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                        Text(loc.localized("gameInfo.fetchMetadata"))
                    }
                    .font(.subheadline)
                    .foregroundColor(AppColors.textOnAccent(colorScheme))
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.brandAccent)
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
        fetchMetadata.showWorking(loc.localized("gameInfo.searchingLaunchBox"))
        let success = await LaunchBoxGamesDBService.shared.fetchAndApplyMetadata(for: currentROM, library: library)
        if success {
            await MainActor.run {
                fetchMetadata.showResult(loc.localized("gameInfo.metadataUpdated"), tone: .success, autoDismissAfter: 10_000_000_000)
                loadBoxArt()
                loadTitleScreen()
                loadScreenshots()
            }
        } else {
            await MainActor.run { fetchMetadata.showResult(loc.localized("gameInfo.noMetadataFound"), tone: .warning, autoDismissAfter: 10_000_000_000) }
        }
    }

    func clearFetchMetadataStatus() {
        fetchMetadata.clear()
    }

    var fetchBoxArtButton: some View {
        HStack(spacing: AppSpacing.xs) {
            Group {
                switch fetchBoxArt.status {
                case .hidden:
                    Button { startBoxArtFetch() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                            Text(loc.localized("gameInfo.fetchArt"))
                        }
                        .font(.subheadline)
                        .foregroundColor(AppColors.textOnAccent(colorScheme))
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.brandAccent)
                        .cornerRadius(AppRadius.md)
                    }
                    .buttonStyle(.plain)
                case .working(let msg):
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(verbatim: msg).font(.caption).foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentTertiary.opacity(0.5))
                    .cornerRadius(AppRadius.md)
                case .result(let msg, let tone):
                    HStack(spacing: 6) {
                        Image(systemName: tone.iconName).font(.caption).foregroundColor(tone.foregroundColor)
                        Text(verbatim: msg).font(.caption).foregroundColor(AppColors.textPrimary(colorScheme))
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(tone.foregroundColor.opacity(0.15))
                    .cornerRadius(AppRadius.md)
                }
            }

            if boxArtUndo?.romID == currentROM.id, !fetchBoxArt.isWorking {
                Button { startBoxArtUndo() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("app.undo")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.brandAccent)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.brandAccent.opacity(0.12))
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)
            }

            if case .result = fetchBoxArt.status {
                AppIconButton(icon: "xmark.circle.fill", help: loc.localized("search.dismiss")) {
                    dismissFetchBoxArtStatus()
                }
            }
        }
    }

    @MainActor
    func startBoxArtFetch() {
        boxArtOperationTask?.cancel()
        let operationID = UUID()
        boxArtOperationID = operationID
        boxArtOperationTask = Task { @MainActor in
            await performBoxArtFetch(operationID: operationID)
        }
    }

    @MainActor
    func performBoxArtFetch(operationID: UUID) async {
        defer { finishBoxArtOperation(operationID) }
        let rom = currentROM
        let previousUndo = boxArtUndo?.romID == rom.id ? boxArtUndo : nil
        fetchBoxArt.showWorking(loc.localized("gameInfo.searching"))

        let outcome = await BoxArtService.shared.replaceBoxArt(for: rom)
        switch outcome {
        case .replaced(let artURL, let snapshot):
            if Task.isCancelled || currentROM.id != rom.id {
                let restoreResult = await BoxArtService.shared.restoreBoxArt(snapshot, replacing: artURL)
                if currentROM.id == rom.id, restoreResult != .restored {
                    showBoxArtRestoreError(restoreResult)
                }
                return
            }

            BoxArtService.shared.invalidateResolvedBoxArtCache(for: rom.id)
            library.updateBoxArt(hasBoxArt: true, for: rom.id)
            BoxArtService.shared.signalBoxArtUpdated(for: rom.id, boxArtURL: artURL)
            boxArtUndo = BoxArtUndoState(romID: rom.id, snapshot: snapshot, newURL: artURL)
            loadBoxArt()
            loadTitleScreen()
            loadScreenshots()
            fetchBoxArt.showResult(
                loc.localized("gameInfo.artFound"),
                tone: .success,
                autoDismissAfter: nil
            )

        case .unchanged(let artURL):
            guard !Task.isCancelled, currentROM.id == rom.id else { return }
            BoxArtService.shared.invalidateResolvedBoxArtCache(for: rom.id)
            library.updateBoxArt(hasBoxArt: true, for: rom.id)
            BoxArtService.shared.signalBoxArtUpdated(for: rom.id, boxArtURL: artURL)
            boxArtUndo = previousUndo
            loadBoxArt()
            fetchBoxArt.showResult(
                loc.localized("gameInfo.artFound"),
                tone: .success,
                autoDismissAfter: 10_000_000_000
            )

        case .notFound(let previousArtExists):
            guard !Task.isCancelled, currentROM.id == rom.id else { return }
            boxArtUndo = previousUndo
            fetchBoxArt.showResult(
                loc.localized(previousArtExists ? "gameInfo.artSearchFailedPreviousKept" : "gameInfo.noCoverArtFound"),
                tone: .warning,
                autoDismissAfter: 10_000_000_000
            )

        case .captureUnavailable:
            guard !Task.isCancelled, currentROM.id == rom.id else { return }
            boxArtUndo = previousUndo
            fetchBoxArt.showResult(
                loc.localized("gameInfo.artUndoUnavailable"),
                tone: .error,
                autoDismissAfter: 10_000_000_000
            )

        case .cancelled:
            if currentROM.id == rom.id {
                fetchBoxArt.clear()
            }

        case .failed:
            guard !Task.isCancelled, currentROM.id == rom.id else { return }
            boxArtUndo = previousUndo
            fetchBoxArt.showResult(
                loc.localized("gameInfo.artReplaceFailed"),
                tone: .error,
                autoDismissAfter: 10_000_000_000
            )
        }
    }

    @MainActor
    func startBoxArtUndo() {
        guard boxArtUndo?.romID == currentROM.id else { return }
        boxArtOperationTask?.cancel()
        let operationID = UUID()
        boxArtOperationID = operationID
        boxArtOperationTask = Task { @MainActor in
            await performBoxArtUndo(operationID: operationID)
        }
    }

    @MainActor
    func performBoxArtUndo(operationID: UUID) async {
        defer { finishBoxArtOperation(operationID) }
        guard let undo = boxArtUndo, undo.romID == currentROM.id else { return }
        fetchBoxArt.showWorking(loc.localized("gameInfo.restoringArt"))

        let result = await BoxArtService.shared.restoreBoxArt(undo.snapshot, replacing: undo.newURL)
        switch result {
        case .restored:
            BoxArtService.shared.invalidateResolvedBoxArtCache(for: undo.romID)
            library.updateBoxArt(hasBoxArt: undo.snapshot.hasPreviousArt, for: undo.romID)
            BoxArtService.shared.signalBoxArtUpdated(
                for: undo.romID,
                boxArtURL: undo.snapshot.previousURL
            )
            if currentROM.id == undo.romID {
                boxArtUndo = nil
                loadBoxArt()
                fetchBoxArt.showResult(
                    loc.localized("gameInfo.artRestored"),
                    tone: .success,
                    autoDismissAfter: 5_000_000_000
                )
            }
        case .partial, .failed:
            if currentROM.id == undo.romID {
                showBoxArtRestoreError(result)
            }
        }
    }

    @MainActor
    func finishBoxArtOperation(_ operationID: UUID) {
        guard boxArtOperationID == operationID else { return }
        boxArtOperationID = nil
        boxArtOperationTask = nil
    }

    @MainActor
    func showBoxArtRestoreError(_ result: BoxArtRestoreResult) {
        let messageKey = result == .partial ? "gameInfo.artRestorePartial" : "gameInfo.artRestoreFailed"
        fetchBoxArt.showResult(
            loc.localized(messageKey),
            tone: .error,
            autoDismissAfter: 10_000_000_000
        )
    }

    @MainActor
    func dismissFetchBoxArtStatus() {
        fetchBoxArt.clear()
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

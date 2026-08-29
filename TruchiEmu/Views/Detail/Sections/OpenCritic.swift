import SwiftUI

extension GameDetailView {
    var openCriticSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            openCriticCard
        }
        .onAppear {
            if let key = OpenCriticService.shared.apiKey, !key.isEmpty,
               !(currentROM.metadata?.openCriticFetchAttempted ?? false),
               !openCriticFetching {
                fetchOpenCritic()
            }
        }
    }

    @ViewBuilder
    private var openCriticCard: some View {
        if OpenCriticService.shared.apiKey == nil || OpenCriticService.shared.apiKey!.isEmpty {
            ModernSectionCard(title: loc.localized("gameDetail.openCritic"), icon: "star.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(loc.localized("openCritic.noApiKey"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                    Text(loc.localized("openCritic.configureInSettings"))
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                    Button(loc.localized("settings.title")) {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } else if openCriticFetching {
            ModernSectionCard(title: loc.localized("gameDetail.openCritic"), icon: "star.fill") {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(loc.localized("openCritic.fetching"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
            }
        } else if let meta = currentROM.metadata,
                  let score = meta.openCriticScore,
                  let tier = meta.openCriticTier {
            ModernSectionCard(
                title: loc.localized("gameDetail.openCritic"),
                icon: "star.fill",
                headerTrailing: AnyView(
                    Button(action: { fetchOpenCritic() }) {
                        Label(loc.localized("openCritic.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                )
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(score)")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundColor(AppColors.textPrimary(colorScheme))
                            Text(loc.localized("openCritic.score"))
                                .font(.caption2)
                                .foregroundColor(AppColors.textMuted(colorScheme))
                        }
                        Divider().frame(height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tier)
                                .font(.headline)
                                .foregroundColor(AppColors.brandAccent)
                            if let pct = meta.openCriticPercentRecommended {
                                Text("\(pct)% \(loc.localized("openCritic.recommended"))")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.textSecondary(colorScheme))
                            }
                            if let count = meta.openCriticReviewCount {
                                Text("\(count) \(loc.localized("openCritic.reviews"))")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textMuted(colorScheme))
                            }
                        }
                        Spacer()
                    }
                    if let gameID = meta.openCriticID, gameID > 0 {
                        Link(loc.localized("openCritic.viewOnOpenCritic"),
                             destination: URL(string: "https://opencritic.com/game/\(gameID)")!)
                            .font(.caption)
                    }
                }
            }
        } else {
            ModernSectionCard(title: loc.localized("gameDetail.openCritic"), icon: "star.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    if let err = openCriticErrorMessage, !err.isEmpty {
                        Text("\(loc.localized("openCritic.error")) \(err)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else {
                        Text(loc.localized("openCritic.noData"))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    Button(loc.localized("openCritic.fetch")) {
                        fetchOpenCritic()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    func fetchOpenCritic() {
        guard let key = OpenCriticService.shared.apiKey, !key.isEmpty else { return }
        let rom = currentROM
        openCriticFetching = true
        openCriticErrorMessage = nil
        Task {
            await OpenCriticService.shared.fetchOpenCriticData(for: rom)
            await MainActor.run {
                openCriticFetching = false
                if let err = OpenCriticService.shared.lastError {
                    openCriticErrorMessage = err
                }
                // Mark as attempted so we never auto-refetch (saves API quota).
                // The manual Fetch/Refresh button can still override this.
                var updated = currentROM
                if updated.metadata == nil { updated.metadata = ROMMetadata() }
                updated.metadata?.openCriticFetchAttempted = true
                library.updateROM(updated)
            }
        }
    }
}

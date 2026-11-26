import SwiftUI

extension GameDetailView {
    var openCriticSection: some View {
        ModernSectionCard(
            title: loc.localized("gameDetail.openCritic"),
            icon: "star.fill"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if OpenCriticService.shared.apiKey == nil || OpenCriticService.shared.apiKey!.isEmpty {
                    noApiKeyState
                } else if openCriticFetching {
                    fetchingState
                } else if let meta = currentROM.metadata,
                          let score = meta.openCriticScore,
                          let tier = meta.openCriticTier {
                    scoreState(score: score, tier: tier, meta: meta)
                } else {
                    noDataState
                }
            }
        }
        .onAppear {
            if let key = OpenCriticService.shared.apiKey, !key.isEmpty,
               !(currentROM.metadata?.openCriticFetchAttempted ?? false),
               !openCriticFetching {
                fetchOpenCritic()
            }
        }
    }

    private var noApiKeyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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

    private var fetchingState: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView().controlSize(.small)
            Text(loc.localized("openCritic.fetching"))
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
    }

    private func scoreState(score: Int, tier: String, meta: ROMMetadata) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(AppColors.textPrimary(colorScheme))
                    Text(loc.localized("openCritic.score"))
                        .font(.caption2)
                        .foregroundColor(AppColors.textMuted(colorScheme))
                }

                Divider()
                    .frame(height: 48)
                    .overlay(AppColors.divider(colorScheme))

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

                Spacer(minLength: 0)
            }

            if let gameID = meta.openCriticID, gameID > 0 {
                Link(loc.localized("openCritic.viewOnOpenCritic"),
                     destination: URL(string: "https://opencritic.com/game/\(gameID)")!)
                    .font(.caption)
            }
        }
    }

    private var noDataState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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
                var updated = currentROM
                if updated.metadata == nil { updated.metadata = ROMMetadata() }
                updated.metadata?.openCriticFetchAttempted = true
                library.updateROM(updated)
            }
        }
    }
}

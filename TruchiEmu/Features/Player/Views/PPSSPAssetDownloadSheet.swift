import SwiftUI

struct PPSSPAssetDownloadSheet: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var assetService = PPSSPAssetService.shared
    @Environment(\.colorScheme) private var colorScheme

    private enum Phase {
        case prompt
        case downloading
        case error
    }

    @State private var phase: Phase = .prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            Divider()
            if phase == .downloading {
                progressSection
            } else {
                explanationSection
            }
            if phase == .error {
                errorSection
            }
            Divider()
            actionButtons
        }
        .padding(28)
        .frame(width: 460)
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .interactiveDismissDisabled()
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.brandAccent.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 26))
                    .foregroundStyle(AppColors.brandAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ppssppAsset.title")
                    .font(.title2.weight(.bold))
                Text("ppssppAsset.description")
                    .foregroundColor(AppColors.textSecondary(colorScheme))
                    .font(.subheadline)
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(Int(assetService.downloadProgress * 100))%")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                    .frame(width: 40, alignment: .trailing)
                Text(assetService.downloadStatus)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
                    .lineLimit(1)
                Spacer()
            }
            ProgressView(value: max(0, min(1, assetService.downloadProgress)))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(AppColors.brandAccentSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(12)
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(AppColors.brandAccent)
                    .font(.system(size: 18))
                Text("ppssppAsset.whatWhyTitle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary(colorScheme))
            }
            Text("ppssppAsset.explanation")
                .font(.callout)
                .foregroundColor(AppColors.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
        .cornerRadius(12)
    }

    private var errorSection: some View {
        Label("ppssppAsset.error", systemImage: "exclamationmark.triangle")
            .foregroundColor(AppColors.error(colorScheme))
            .font(.callout)
    }

    private var actionButtons: some View {
        HStack {
            if phase == .downloading {
                Spacer()
                ProgressView().scaleEffect(0.9)
                Text(loc.localized("coreDownload.status.downloading"))
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            } else {
                Button(loc.localized("ppssppAsset.cancel")) {
                    assetService.resolveAssetSheet(.cancelled)
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Spacer()

                Button(loc.localized("ppssppAsset.continueWithout")) {
                    assetService.resolveAssetSheet(.skipped)
                }
                .controlSize(.large)

                Button(phase == .error ? loc.localized("ppssppAsset.retry") : loc.localized("ppssppAsset.download")) {
                    beginDownload()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.brandAccent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }

    private func beginDownload() {
        phase = .downloading
        Task {
            let ok = await PPSSPAssetService.shared.downloadAssets()
            await MainActor.run {
                if ok {
                    PPSSPAssetService.shared.resolveAssetSheet(.downloaded)
                } else {
                    phase = .error
                }
            }
        }
    }
}

import SwiftUI

struct BoxArtDownloadSheet: View {
    @Binding var isPresented: Bool
    let onDownload: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var prefs = SystemPreferences.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedOption: DownloadOption = .missingOnly

    private enum DownloadOption {
        case missingOnly
        case reDownload
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text(loc.localized("boxArt.downloadSheet.title"))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(loc.localized("boxArt.downloadSheet.regionLabel"))
                    .font(.headline)

                Picker(loc.localized("library.gameRegion"), selection: $prefs.systemLanguage) {
                    ForEach(EmulatorLanguage.allCases) { lang in
                        Text("\(lang.flagEmoji) \(lang.name)").tag(lang)
                    }
                }
                .pickerStyle(.menu)

                Text(loc.localized("boxArt.downloadSheet.regionInfo"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            Divider()

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(loc.localized("boxArt.downloadSheet.downloadOption"))
                    .font(.headline)

                Button {
                    selectedOption = .missingOnly
                } label: {
                    HStack(spacing: AppSpacing.lg) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .frame(width: 24)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.localized("boxArt.downloadSheet.missingOnly"))
                                .font(.body)
                                .fontWeight(selectedOption == .missingOnly ? .semibold : .regular)
                            Text(loc.localized("boxArt.downloadSheet.missingOnlyDescription"))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        Spacer()

                        if selectedOption == .missingOnly {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.brandAccent)
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(selectedOption == .missingOnly ? AppColors.brandAccent.opacity(0.1) : Color.clear)
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)

                Button {
                    selectedOption = .reDownload
                } label: {
                    HStack(spacing: AppSpacing.lg) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title2)
                            .frame(width: 24)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.localized("boxArt.downloadSheet.reDownload"))
                                .font(.body)
                                .fontWeight(selectedOption == .reDownload ? .semibold : .regular)
                            Text(loc.localized("boxArt.downloadSheet.reDownloadDescription"))
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary(colorScheme))
                        }

                        Spacer()

                        if selectedOption == .reDownload {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.brandAccent)
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(selectedOption == .reDownload ? AppColors.brandAccent.opacity(0.1) : Color.clear)
                    .cornerRadius(AppRadius.md)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Button(loc.localized("boxArt.downloadSheet.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    isPresented = false
                    onDownload(selectedOption == .reDownload)
                } label: {
                    Text(loc.localized("boxArt.downloadSheet.download"))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

import SwiftUI

struct CoreDownloadSheet: View {
    @EnvironmentObject var coreManager: CoreManager
    let pending: CoreManager.PendingCoreDownload
    @State private var isDownloading = false
    @State private var downloadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: "cpu")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Core Download")
                        .font(.title2.weight(.bold))
                    Text("A new emulator core needs to be installed.")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Core details
            VStack(alignment: .leading, spacing: 12) {
                detailRow(label: "Core", value: pending.coreInfo.displayName)
                detailRow(label: "File", value: pending.coreInfo.fileName)
                detailRow(label: "Source", value: pending.coreInfo.downloadURL.host ?? "buildbot.libretro.com")
                if !pending.coreInfo.systemIDs.isEmpty {
                    let names = pending.coreInfo.systemIDs.compactMap { SystemDatabase.system(forID: $0)?.name }.joined(separator: ", ")
                    detailRow(label: "Systems", value: names)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)

            // Info box
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Cores are downloaded from the official **libretro buildbot**. Multiple versions can coexist — the current version will be preserved when updating.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            if let err = downloadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.callout)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    coreManager.pendingDownload = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                    Text("Downloading…")
                        .foregroundColor(.secondary)
                } else {
                    Button("Download & Install") {
                        isDownloading = true
                        downloadError = nil
                        Task {
                            await coreManager.downloadCore(pending.coreInfo)
                            isDownloading = false
                            coreManager.pendingDownload = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.body.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.body)
                .lineLimit(2)
        }
    }
}

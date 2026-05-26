import SwiftUI

struct BezelDownloadLogView: View {
    let logEntries: [BezelDownloadLogEntry]
    @State private var lastCount: Int = 0
    @State private var showDetails = false
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
Label(loc.localized("bezel.downloadHistory"), systemImage: "list.bullet")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(AppColors.textSecondary(colorScheme))
                
                Spacer()
                
                let successCount = logEntries.filter { $0.status.isSuccess }.count
                let failCount = logEntries.filter { $0.status.errorMessage != nil }.count
                
                if successCount > 0 {
Label("\(successCount)", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(AppColors.success(colorScheme))
                }
                if failCount > 0 {
Label("\(failCount)", systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundColor(AppColors.error(colorScheme))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(logEntries) { entry in
                            BezelLogEntryRow(entry: entry, showDetails: showDetails)
                        }
                    }
                    .onAppear {
                        lastCount = logEntries.count
                    }
                    .onChange(of: logEntries.count) { _, newCount in
                        // Auto-scroll to bottom when new entries are added
                        if newCount > lastCount, let lastId = logEntries.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                        lastCount = newCount
                    }
                }
                .background(Color.black.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Toggle details button
            Button {
                withAnimation {
                    showDetails.toggle()
                }
            } label: {
                Label(
                    showDetails ? loc.localized("bezel.hideDetails") : loc.localized("bezel.showDetails"),
                    systemImage: showDetails ? "chevron.up" : "chevron.down"
                )
                .font(.caption2)
                .foregroundColor(AppColors.brandAccent)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
}

// Single row in the bezel download log
struct BezelLogEntryRow: View {
    let entry: BezelDownloadLogEntry
    var showDetails: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var statusIcon: String {
        switch entry.status {
        case .inProgress:
            return "arrow.down.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    var statusColor: Color {
        switch entry.status {
        case .inProgress:
            return AppColors.brandAccent
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Status icon
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.system(size: 10))
                
                // System ID (if available)
                if !entry.systemID.isEmpty && showDetails {
Text("[\(entry.systemID)]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                }
                
                // File name (truncated if needed)
                Text(entry.fileName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                // Duration (if available)
if showDetails, let duration = entry.duration {
                Text(formatDuration(duration))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
                
                // Timestamp
Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
            }
            
            // Error message (if failed)
            if case .failed(let error) = entry.status {
                HStack(spacing: 4) {
Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(AppColors.error(colorScheme))
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.error(colorScheme))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%dms", Int(duration * 1000))
        }
        return String(format: "%.1fs", duration)
    }
}

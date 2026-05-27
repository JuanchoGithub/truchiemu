import SwiftUI

struct NotificationPopoverView: View {
    @Binding var showAll: Bool
    @ObservedObject private var historyManager = NotificationHistoryManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let maxVisible = 4

    var body: some View {
        VStack(spacing: 0) {
            if historyManager.entries.isEmpty {
                emptyState
            } else {
                let visible = Array(historyManager.entries.prefix(maxVisible))
                VStack(spacing: 2) {
                    ForEach(visible, id: \.id) { entry in
                        NotificationRowView(entry: entry, compact: true) {
                            historyManager.executeAction(entry)
                        } onDismiss: {
                            withAnimation(AppAnimations.quick) {
                                historyManager.dismiss(entry)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            historyManager.markAsRead(entry)
                        }
                    }
                }
                .padding(.top, 8)

                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                Button {
                    showAll = true
                } label: {
                    HStack {
                        Text(loc.localized("notifications.openAll"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.brandAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 20))
                .foregroundColor(AppColors.textTertiary(colorScheme))
            Text(loc.localized("notifications.empty"))
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary(colorScheme))
        }
        .padding(.vertical, 24)
        .frame(width: 300)
    }
}

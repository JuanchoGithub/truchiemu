import SwiftUI

struct NotificationCenterSheetView: View {
    @ObservedObject private var historyManager = NotificationHistoryManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if historyManager.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 28))
                            .foregroundColor(AppColors.textTertiary(colorScheme))
                        Text(loc.localized("notifications.empty"))
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary(colorScheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(historyManager.entries, id: \.id) { entry in
                                NotificationRowView(entry: entry) {
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(loc.localized("notifications.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.localized("app.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if historyManager.unreadCount > 0 {
                        Button(loc.localized("notifications.markAllRead")) {
                            withAnimation(AppAnimations.quick) {
                                historyManager.markAllAsRead()
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

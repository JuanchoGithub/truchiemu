import SwiftUI
import Combine

struct PillAction {
    let label: String
    let handler: () -> Void
}

struct PillNotification: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var subtitle: String?
    var rotatingMessages: [String]?
    var messageInterval: Double = 4
    var autoDismissDelay: TimeInterval?
    var action: PillAction?
    var secondaryAction: PillAction?

    var actions: [PillAction] {
        var result: [PillAction] = []
        if let a = action { result.append(a) }
        if let sa = secondaryAction { result.append(sa) }
        return result
    }

    var maxActions: Int { 2 }
}

@MainActor
class NotificationPillManager: ObservableObject {
    static let shared = NotificationPillManager()

    @Published private(set) var currentNotification: PillNotification?

    func post(_ notification: PillNotification) {
        currentNotification = notification
        if let delay = notification.autoDismissDelay {
            let id = notification.id
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if currentNotification?.id == id {
                    withAnimation(AppAnimations.smooth) {
                        currentNotification = nil
                    }
                }
            }
        }
    }

    func updateSubtitle(_ subtitle: String) {
        guard currentNotification != nil else { return }
        currentNotification?.subtitle = subtitle
    }

    func dismiss() {
        withAnimation(AppAnimations.smooth) {
            currentNotification = nil
        }
    }
}

struct NotificationPill: View {
    let notification: PillNotification
    @Environment(\.colorScheme) private var colorScheme
    @State private var messageIndex = 0
    @State private var isHovering = false
    @State private var cancellable: AnyCancellable?

    private var displayTitle: String {
        if let messages = notification.rotatingMessages, !messages.isEmpty {
            return messages[messageIndex % messages.count]
        }
        return notification.title
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notification.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppGradients.accent)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)

                if let subtitle = notification.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondaryNeutral(colorScheme))
                        .lineLimit(1)
                }
            }

            if !notification.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(notification.actions.enumerated()), id: \.offset) { index, act in
                        Button {
                            act.handler()
                        } label: {
                            Text(act.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(AppColors.brandAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(AppColors.brandAccent.opacity(isHovering ? 0.15 : 0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(AppAnimations.quick) {
                                isHovering = hovering
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(
                    Capsule()
                        .fill(AppColors.brandAccent.opacity(0.08))
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .contentShape(Capsule())
        .onTapGesture {
            NotificationPillManager.shared.dismiss()
        }
        .onAppear {
            startMessageRotation()
        }
        .onDisappear {
            cancellable?.cancel()
        }
        .onChange(of: notification.id) { _, _ in
            messageIndex = 0
            startMessageRotation()
        }
    }

    private func startMessageRotation() {
        cancellable?.cancel()
        guard let messages = notification.rotatingMessages, messages.count > 1 else { return }
        cancellable = Timer.publish(every: notification.messageInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    messageIndex = (messageIndex + 1) % messages.count
                }
            }
    }
}

import SwiftUI
import SwiftData

struct ROMActionPayload: Codable {
    let romID: UUID
}

struct TrashActionPayload: Codable {
    let romID: UUID
    let originalPath: String
    let romJSON: String
}

struct SaveDeleteActionPayload: Codable {
    let filePairs: [[String]]  // [[originalPath, tempUndoPath], ...]
}

private enum notificationLog {
    static func info(_ message: String) { LoggerService.info(category: "NotificationHistory", message) }
}

@MainActor
class NotificationHistoryManager: ObservableObject {
    static let shared = NotificationHistoryManager()

    @Published private(set) var entries: [NotificationEntry] = []
    @Published private(set) var unreadCount: Int = 0

    private var actionHandlers: [String: (NotificationEntry) -> Bool] = [:]
    private var hasLoaded = false

    weak var library: ROMLibrary?

    private init() {
        loadEntries()
        pruneExpired()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pruneExpired()
            }
        }
    }

    func registerActionHandler(type: String, handler: @escaping (NotificationEntry) -> Bool) {
        actionHandlers[type] = handler
    }

    func post(
        icon: String,
        title: String,
        subtitle: String? = nil,
        autoDismissDelay: TimeInterval? = 5,
        actionLabel: String? = nil,
        actionType: String? = nil,
        actionPayloadJSON: String? = nil
    ) {
        let entry = NotificationEntry(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actionLabel: actionLabel,
            actionType: actionType,
            actionPayloadJSON: actionPayloadJSON
        )

        let context = SwiftDataContainer.shared.mainContext
        context.insert(entry)
        try? context.save()

        entries.insert(entry, at: 0)
        updateUnreadCount()

        let pill = PillNotification(
            icon: icon,
            title: title,
            subtitle: subtitle,
            autoDismissDelay: autoDismissDelay,
            action: actionLabel != nil ? PillAction(label: actionLabel!) { [weak self] in
                _ = self?.executeAction(entry)
                NotificationPillManager.shared.dismiss()
            } : nil
        )
        NotificationPillManager.shared.post(pill)
    }

    @discardableResult
    func executeAction(_ entry: NotificationEntry) -> Bool {
        guard let actionType = entry.actionType,
              let handler = actionHandlers[actionType] else {
            notificationLog.info("No handler registered for action type: \(entry.actionType ?? "nil")")
            return false
        }
        let result = handler(entry)
        if result {
            dismiss(entry)
        }
        return result
    }

    func markAsRead(_ entry: NotificationEntry) {
        guard !entry.isRead else { return }
        entry.isRead = true
        try? SwiftDataContainer.shared.mainContext.save()
        updateUnreadCount()
    }

    func markAllAsRead() {
        for entry in entries where !entry.isRead {
            entry.isRead = true
        }
        try? SwiftDataContainer.shared.mainContext.save()
        updateUnreadCount()
    }

    func dismiss(_ entry: NotificationEntry) {
        let context = SwiftDataContainer.shared.mainContext
        context.delete(entry)
        try? context.save()
        entries.removeAll { $0.id == entry.id }
        updateUnreadCount()
    }

    func dismissAll() {
        let context = SwiftDataContainer.shared.mainContext
        for entry in entries {
            context.delete(entry)
        }
        try? context.save()
        entries.removeAll()
        updateUnreadCount()
    }

    func pruneExpired() {
        let context = SwiftDataContainer.shared.mainContext
        var pruned = false
        for entry in entries {
            if entry.isExpired {
                context.delete(entry)
                pruned = true
            }
        }
        if pruned {
            try? context.save()
            entries.removeAll { $0.isExpired }
            updateUnreadCount()
        }
    }

    private func loadEntries() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let context = SwiftDataContainer.shared.mainContext
        var descriptor = FetchDescriptor<NotificationEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        if let results = try? context.fetch(descriptor) {
            entries = results
        }
        updateUnreadCount()
    }

    private func updateUnreadCount() {
        unreadCount = entries.filter { !$0.isRead }.count
    }
}

extension NotificationHistoryManager {
    func post<T: Codable>(
        icon: String,
        title: String,
        subtitle: String? = nil,
        autoDismissDelay: TimeInterval? = 5,
        actionLabel: String? = nil,
        actionType: String,
        actionPayload: T
    ) {
        let payloadJSON: String? = {
            if let data = try? JSONEncoder().encode(actionPayload) {
                return String(data: data, encoding: .utf8)
            }
            return nil
        }()

        post(
            icon: icon,
            title: title,
            subtitle: subtitle,
            autoDismissDelay: autoDismissDelay,
            actionLabel: actionLabel,
            actionType: actionType,
            actionPayloadJSON: payloadJSON
        )
    }
}

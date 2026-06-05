import SwiftUI

struct SystemChangePayload: Codable {
    struct Entry: Codable {
        let romID: UUID
        let oldSystemID: String
    }
    let entries: [Entry]
    let newSystemID: String
}

struct SystemPickerView: View {
    let roms: [ROM]
    let library: ROMLibrary
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var pendingSystem: SystemInfo?
    @State private var isReverting = false
    @State private var showConfirmation = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var notificationHistory = NotificationHistoryManager.shared

    private var originalSystemIDs: Set<String> {
        Set(roms.compactMap { $0.originalSystemID ?? $0.systemID })
    }

    private var canRevert: Bool {
        roms.contains(where: { $0.systemID != $0.originalSystemID })
    }

    private var originalSystems: [SystemInfo] {
        SystemDatabaseWrapper.shared.systems
            .filter { originalSystemIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var otherSystems: [SystemInfo] {
        SystemDatabaseWrapper.shared.systems
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .filter { !originalSystemIDs.contains($0.id) }
    }

    private var filteredOriginalSystems: [SystemInfo] {
        if searchText.isEmpty { return originalSystems }
        return originalSystems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredOtherSystems: [SystemInfo] {
        if searchText.isEmpty { return otherSystems }
        return otherSystems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            systemList
        }
        .frame(width: 320, height: 420)
        .confirmationDialog(Text(verbatim: confirmationTitle), isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(loc.localized("app.move")) {
                applyChange(to: pendingSystem!)
                pendingSystem = nil
                isReverting = false
            }
            Button(loc.localized("app.cancel"), role: .cancel) {
                pendingSystem = nil
                isReverting = false
            }
        }
    }

    private var confirmationTitle: String {
        guard let system = pendingSystem else { return "" }
        if isReverting {
            if roms.count == 1 {
                return loc.localized("systemPicker.revertSingle")
                    .replacingOccurrences(of: "{0}", with: system.name)
            }
            return loc.localized("systemPicker.revertMultiple")
                .replacingOccurrences(of: "{0}", with: String(roms.count))
                .replacingOccurrences(of: "{1}", with: system.name)
        }
        if roms.count == 1 {
            return loc.localized("systemPicker.confirmSingle")
                .replacingOccurrences(of: "{0}", with: system.name)
        }
        return loc.localized("systemPicker.confirmMultiple")
            .replacingOccurrences(of: "{0}", with: String(roms.count))
            .replacingOccurrences(of: "{1}", with: system.name)
    }

    private func applyChange(to newSystem: SystemInfo) {
        let oldSystemNames = originalSystems.map { $0.name }.joined(separator: ", ")
        var entries: [SystemChangePayload.Entry] = []

        for rom in roms {
            entries.append(SystemChangePayload.Entry(
                romID: rom.id,
                oldSystemID: rom.systemID ?? ""
            ))
            var updated = rom
            if updated.originalSystemID == nil {
                updated.originalSystemID = updated.systemID
            }
            updated.systemID = newSystem.id
            library.updateROM(updated)
        }

        let payload = SystemChangePayload(entries: entries, newSystemID: newSystem.id)
        let title: String
        if roms.count == 1 {
            title = loc.localized("notification.movedSingle")
                .replacingOccurrences(of: "{0}", with: roms[0].displayName)
                .replacingOccurrences(of: "{1}", with: newSystem.name)
        } else {
            title = loc.localized("notification.movedMultiple")
                .replacingOccurrences(of: "{0}", with: String(roms.count))
                .replacingOccurrences(of: "{1}", with: newSystem.name)
        }

        notificationHistory.post(
            icon: "arrow.triangle.swap",
            title: title,
            subtitle: oldSystemNames,
            autoDismissDelay: 8,
            actionLabel: loc.localized("app.undo"),
            actionType: "undoSystemChange",
            actionPayload: payload
        )

        onDismiss()
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundColor(AppColors.textSecondary(colorScheme))
            TextField(loc.localized("systemPicker.searchPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.cardBackgroundSubtle(colorScheme))
    }

    private var systemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !filteredOriginalSystems.isEmpty {
                    ForEach(filteredOriginalSystems) { system in
                        systemRow(system: system, isOriginal: true)
                    }
                    Divider()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }

                ForEach(filteredOtherSystems) { system in
                    systemRow(system: system, isOriginal: false)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func systemRow(system: SystemInfo, isOriginal: Bool) -> some View {
        let isCurrent = roms.allSatisfy { $0.systemID == system.id }
        let rowDisabled = isOriginal ? !canRevert : isCurrent

        return Button {
            if isOriginal {
                isReverting = true
            }
            pendingSystem = system
            showConfirmation = true
        } label: {
             HStack(spacing: 10) {
                Image(systemName: system.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(isOriginal ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                    .frame(width: 24)
                Text(system.name)
                    .font(.body)
                    .foregroundColor(isOriginal ? AppColors.textPrimary(colorScheme) : AppColors.textPrimary(colorScheme).opacity(0.85))
                if isOriginal {
                    Text(loc.localized("systemPicker.originalLabel"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColors.brandAccent.opacity(0.1))
                        .cornerRadius(4)
                } else if isCurrent {
                    Text(loc.localized("systemPicker.currentLabel"))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColors.brandAccent.opacity(0.1))
                        .cornerRadius(4)
                }
                Spacer()
                if isOriginal && !canRevert {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .foregroundColor(AppColors.brandAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isOriginal ? AppColors.brandAccent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
            .opacity(rowDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(rowDisabled)
    }
}

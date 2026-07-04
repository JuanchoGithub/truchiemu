import SwiftUI

struct ResetSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    @Binding var searchText: String
    @Binding var focusedSectionID: String?
    @Binding var scopedSectionID: String?

    @State private var showResetConfirmation = false
    @State private var resetTarget: ResetTarget?
    @State private var resetMessage: String?

    init(searchText: Binding<String> = .constant(""), focusedSectionID: Binding<String?> = .constant(nil),
         scopedSectionID: Binding<String?> = .constant(nil)) {
        self._searchText = searchText
        self._focusedSectionID = focusedSectionID
        self._scopedSectionID = scopedSectionID
    }

    private enum ResetTarget: Identifiable {
        case section(String)
        case all

        var id: String {
            switch self {
            case .section(let name): return name
            case .all: return "all"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Text(loc.localized("settings.reset.intro"))
                    .font(.callout)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }

            Section(loc.localized("settings.reset.sections")) {
                row(.section("hotkeys"), title: loc.localized("settings.hotkeysGameplay"), description: loc.localized("settings.reset.hotkeys")) {
                    SettingsResetter.resetHotkeys()
                    resetMessage = loc.localized("settings.reset.hotkeysDone")
                }
                row(.section("saveDirectories"), title: loc.localized("settings.saves"), description: loc.localized("settings.reset.saveDirectories")) {
                    SettingsResetter.resetSaveDirectories()
                    resetMessage = loc.localized("settings.reset.saveDirectoriesDone")
                }
                row(.section("startupTab"), title: loc.localized("settings.reset.startupTab"), description: loc.localized("settings.reset.startupTabDescription")) {
                    SettingsResetter.resetSelectedTab()
                    resetMessage = loc.localized("settings.reset.startupTabDone")
                }
            }

            Section {
                Button(role: .destructive) {
                    resetTarget = .all
                    showResetConfirmation = true
                } label: {
                    Label(loc.localized("settings.reset.restoreAll"), systemImage: "exclamationmark.triangle.fill")
                }
            } footer: {
                Text(loc.localized("settings.reset.restoreAllDescription"))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary(colorScheme))
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .navigationTitle(loc.localized("settings.reset.title"))
        .alert(loc.localized("settings.reset.confirmTitle"), isPresented: $showResetConfirmation) {
            Button(loc.localized("settings.reset.confirmRestore"), role: .destructive) {
                if case .all = resetTarget {
                    SettingsResetter.resetAll()
                    resetMessage = loc.localized("settings.reset.restoreAllDone")
                }
            }
            Button(loc.localized("general.cancel"), role: .cancel) {}
        } message: {
            Text(loc.localized("settings.reset.confirmMessage"))
        }
        .onChange(of: searchText) { _, _ in }
        .overlay(alignment: .bottom) {
            if let message = resetMessage {
                AppToast(message: message, style: .success, duration: 3, onDismiss: { resetMessage = nil })
            }
        }
    }

    @ViewBuilder
    private func row(_ target: ResetTarget, title: String, description: String, onConfirm: @escaping () -> Void) -> some View {
        Button {
            onConfirm()
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(.body)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                }
                Spacer()
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(AppColors.brandAccent)
            }
        }
        .buttonStyle(.plain)
    }
}

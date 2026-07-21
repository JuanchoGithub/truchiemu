import SwiftUI

/// TV Mode settings panel. Shown via the Start button in TV Mode (or via the
/// parent toolbar). Self-contained — does not integrate with the standard
/// SettingsView to keep the change footprint minimal.
struct TVModeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var shownEntries: Set<TVModeSettings.SmartEntry>
    @State private var showSystems: Bool

    init() {
        _shownEntries = State(initialValue: Set(TVModeSettings.shownSmartEntries))
        _showSystems = State(initialValue: TVModeSettings.showSystems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(loc.localized("tvMode.settings.title"))
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }

            Toggle(loc.localized("tvMode.settings.launchInTVMode"), isOn: Binding(
                get: { TVModeSettings.launchInTVMode },
                set: { TVModeSettings.setLaunchInTVMode($0) }
            ))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(loc.localized("tvMode.settings.shownEntries"))
                    .font(.system(size: 14, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], alignment: .leading, spacing: 8) {
                    ForEach(TVModeSettings.SmartEntry.allCases) { entry in
                        Toggle(loc.localized(entry.locKey), isOn: Binding(
                            get: { shownEntries.contains(entry) },
                            set: { isOn in
                                if isOn { shownEntries.insert(entry) } else { shownEntries.remove(entry) }
                                TVModeSettings.setShownSmartEntries(Array(shownEntries).sorted { $0.rawValue < $1.rawValue })
                                NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    Toggle(loc.localized("tvMode.settings.systems"), isOn: Binding(
                        get: { showSystems },
                        set: { showSystems = $0; TVModeSettings.setShowSystems($0); NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil) }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            Spacer()
        }
        .padding(28)
        .frame(minWidth: 460, minHeight: 360)
    }
}

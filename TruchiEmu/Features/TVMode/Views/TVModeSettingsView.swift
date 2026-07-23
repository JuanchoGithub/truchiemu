import SwiftUI
import Combine

/// TV Mode settings panel. Shown via the Start button in TV Mode (or via the
/// parent toolbar). Self-contained — does not integrate with the standard
/// SettingsView to keep the change footprint minimal.
struct TVModeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tvModeScale) private var scale
    @ObservedObject private var loc = LocalizationManager.shared
    @StateObject private var nav = TVModeSettingsNav()
    @State private var settingsGeneration: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24 * scale) {
            HStack {
                Text(loc.localized("tvMode.settings.title"))
                    .font(.system(size: 22 * scale, weight: .bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22 * scale))
                        .foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                .overlay(focusRing(active: nav.focusID == .close))
            }

            HStack {
                Text(loc.localized("tvMode.settings.launchInTVMode"))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { TVModeSettings.launchInTVMode },
                    set: { TVModeSettings.setLaunchInTVMode($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .overlay(focusRing(active: nav.focusID == .launchInTVMode))

            Divider()

            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(loc.localized("tvMode.settings.shownEntries"))
                    .font(.system(size: 14 * scale, weight: .semibold))
                ForEach(TVModeSettings.SmartEntry.allCases) { entry in
                    let _ = settingsGeneration  // drives re-eval on change
                    HStack {
                        Text(loc.localized(entry.locKey))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { TVModeSettings.shownSmartEntries.contains(entry) },
                            set: { isOn in
                                var current = Set(TVModeSettings.shownSmartEntries)
                                if isOn { current.insert(entry) } else { current.remove(entry) }
                                TVModeSettings.setShownSmartEntries(Array(current).sorted { $0.rawValue < $1.rawValue })
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .overlay(focusRing(active: nav.focusID == .smartEntry(entry)))
                }
                let _ = settingsGeneration
                HStack {
                    Text(loc.localized("tvMode.settings.systems"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { TVModeSettings.showSystems },
                        set: { TVModeSettings.setShowSystems($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .overlay(focusRing(active: nav.focusID == .showSystems))
            }
            Spacer()
        }
        .padding(28 * scale)
        .frame(minWidth: 460 * scale, minHeight: 360 * scale)
        .onAppear {
            nav.bind(dismiss: { dismiss() })
        }
        .onDisappear { nav.unbind() }
        .onReceive(NotificationCenter.default.publisher(for: .tvModeSettingsChanged)) { _ in
            // Bump a generation counter so any Binding.get closures that re-
            // evaluate after this redraw see fresh values from TVModeSettings.
            settingsGeneration &+= 1
        }
    }

    @ViewBuilder
    private func focusRing(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 4 * scale)
                .stroke(AppColors.brandAccent, lineWidth: 2 * scale)
                .padding(-2 * scale)
                .allowsHitTesting(false)
        }
    }
}

@MainActor
final class TVModeSettingsNav: ObservableObject {
    enum FocusID: Hashable {
        case launchInTVMode
        case smartEntry(TVModeSettings.SmartEntry)
        case showSystems
        case close
    }

    @Published var focusID: FocusID = .launchInTVMode
    private(set) var itemIDs: [FocusID] = []
    private var context: GamepadSheetContext?
    private var dismissAction: (() -> Void)?
    private var focusSubscription: AnyCancellable?

    func bind(dismiss: @escaping () -> Void) {
        var ids: [FocusID] = [.launchInTVMode]
        ids.append(contentsOf: TVModeSettings.SmartEntry.allCases.map { .smartEntry($0) })
        ids.append(.showSystems)
        ids.append(.close)
        itemIDs = ids

        let ctx = GamepadSheetContext(itemCount: ids.count, columnCount: 1)
        ctx.onSelect = { [weak self] idx in self?.activate(index: idx) }
        ctx.onDismiss = { [weak self] in self?.dismissAction?() }
        GamepadNavContextStack.shared.push(ctx)
        context = ctx
        dismissAction = dismiss

        focusSubscription = ctx.$focusIndex
            .removeDuplicates()
            .sink { [weak self] idx in
                guard let self, self.itemIDs.indices.contains(idx) else { return }
                let newID = self.itemIDs[idx]
                if newID != self.focusID { self.focusID = newID }
            }
    }

    func unbind() {
        focusSubscription?.cancel()
        focusSubscription = nil
        if let context { GamepadNavContextStack.shared.remove(context) }
        context = nil
        itemIDs = []
        dismissAction = nil
    }

    private func activate(index: Int) {
        guard itemIDs.indices.contains(index) else { return }
        let id = itemIDs[index]
        switch id {
        case .launchInTVMode:
            TVModeSettings.setLaunchInTVMode(!TVModeSettings.launchInTVMode)
        case .smartEntry(let entry):
            var current = Set(TVModeSettings.shownSmartEntries)
            if current.contains(entry) { current.remove(entry) } else { current.insert(entry) }
            TVModeSettings.setShownSmartEntries(Array(current).sorted { $0.rawValue < $1.rawValue })
            NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
        case .showSystems:
            let next = !TVModeSettings.showSystems
            TVModeSettings.setShowSystems(next)
            NotificationCenter.default.post(name: .tvModeSettingsChanged, object: nil)
        case .close:
            dismissAction?()
        }
    }
}

import SwiftUI

struct CoreVersionPickerView: View {
    @EnvironmentObject var coreManager: CoreManager
    @ObservedObject private var loc = LocalizationManager.shared
    let core: LibretroCore
    @State private var selectedTag: String?

    var body: some View {
        HStack {
            Text(loc.localized("coreVersion.version"))
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            Picker(loc.localized("coreVersion.version"), selection: $selectedTag) {
                if selectedTag == nil {
                    Text(loc.localized("coreVersion.selectVersion")).tag(nil as String?)
                }
                ForEach(core.installedVersions.reversed()) { v in
                    Text(v.tag).tag(v.tag as String?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedTag) { _, tag in
                guard let tag else { return }
                coreManager.setActiveVersion(coreID: core.id, tag: tag)
            }
        }
        .onAppear { selectedTag = core.activeVersionTag }
    }
}
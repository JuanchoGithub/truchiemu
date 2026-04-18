import SwiftUI

// MARK: - Core Version Picker

struct CoreVersionPickerView: View {
    @EnvironmentObject var coreManager: CoreManager
    let core: LibretroCore
    @State private var selectedTag: String?

    var body: some View {
        HStack {
            Text("Version")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            Picker("Version", selection: $selectedTag) {
                if selectedTag == nil {
                    Text("Select Version...").tag(nil as String?)
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
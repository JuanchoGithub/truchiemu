import SwiftUI

struct IconPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @Binding var selectedIconName: String?
    @Binding var customIconPath: String?
    let defaultIconName: String
    let defaultIconImage: (() -> NSImage?)?
    let saveCustomIcon: (NSImage) -> String?

    @State private var showImagePicker = false
    @State private var showCropView = false
    @State private var pickedImage: NSImage?
    @State private var iconSearchText: String = ""
    @State private var showSFSymbolBrowser = false

    private var defaultIcons: [String] {
        let catalog = SFSymbolCatalog.shared
        if let gaming = catalog.categories.first(where: { $0.id == "gaming" }) {
            return Array(gaming.symbols.prefix(12))
        }
        return Array(catalog.allSymbols.prefix(12))
    }

    private var searchResults: [String] {
        SFSymbolCatalog.shared.search(iconSearchText)
    }

    var body: some View {
        Section(loc.localized("app.icon")) {
            HStack {
                previewIcon()
                    .frame(width: 32, height: 32)
                Text(loc.localized("app.currentIcon"))
                Spacer()
                Button {
                    resetIcon()
                } label: {
                    Text(loc.localized("app.reset"))
                }
                .disabled(selectedIconName == nil && customIconPath == nil)
            }

            TextField(loc.localized("app.searchIcons"), text: $iconSearchText)
                .textFieldStyle(.roundedBorder)

            if iconSearchText.isEmpty {
                iconGrid(for: defaultIcons)
            } else if searchResults.isEmpty {
                Text(loc.localized("app.noIconsFound"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondaryNeutral(colorScheme))
            } else {
                iconGrid(for: searchResults)
            }

            HStack(spacing: 12) {
                Button {
                    showImagePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                        Text(loc.localized("app.addYourIcon"))
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showSFSymbolBrowser = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                        Text(loc.localized("app.browseIcons"))
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.png, .jpeg, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let img = NSImage(contentsOf: url) {
                            pickedImage = img
                            showCropView = true
                        }
                    }
                }
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showCropView) {
            Group {
                if let pickedImage {
                    ImageCropView(sourceImage: pickedImage) { croppedImage in
                        if let path = saveCustomIcon(croppedImage) {
                            customIconPath = path
                            selectedIconName = nil
                        }
                    }
                }
            }
            .gamepadDismissable { showCropView = false }
        }
        .sheet(isPresented: $showSFSymbolBrowser) {
            SFSymbolBrowserView { selectedName in
                selectedIconName = selectedName
                customIconPath = nil
            }
            .gamepadDismissable { showSFSymbolBrowser = false }
        }
    }

    @ViewBuilder
    private func iconGrid(for icons: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(icons, id: \.self) { iconName in
                Button {
                    selectedIconName = iconName
                    customIconPath = nil
                } label: {
                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isIconSelected(iconName) ? AppColors.accentBackground(colorScheme) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isIconSelected(iconName) ? AppColors.brandAccent : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func previewIcon() -> some View {
        if let customPath = customIconPath,
           let img = NSImage(contentsOf: URL(fileURLWithPath: customPath)) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let name = selectedIconName, !name.isEmpty {
            Image(systemName: name)
                .foregroundStyle(AppColors.brandAccent)
        } else if let defaultImg = defaultIconImage?() {
            Image(nsImage: defaultImg)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if !defaultIconName.isEmpty {
            Image(systemName: defaultIconName)
                .foregroundStyle(AppColors.brandAccent)
        }
    }

    private func isIconSelected(_ iconName: String) -> Bool {
        selectedIconName == iconName && customIconPath == nil
    }

    private func resetIcon() {
        selectedIconName = nil
        customIconPath = nil
    }
}

// MARK: - Shared icon save utility

extension IconPickerView {
    static func saveCustomIcon(image: NSImage, directory: String, fileName: String) -> String? {
        let outputSize = NSSize(width: 32, height: 32)
        let resized = NSImage(size: outputSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: outputSize))
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let iconsDir = appSupport.appendingPathComponent("TruchiEmu/\(directory)")
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        let fileURL = iconsDir.appendingPathComponent(fileName)
        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            LoggerService.error(category: "IconPicker", "Failed to save custom icon: \(error)")
            return nil
        }
    }
}

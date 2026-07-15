import SwiftUI

// Dedicated sidebar row button component — replaces DragGesture(minimumDistance: 0) with
// a proper Button for instant, reliable click handling across the entire row area.
struct SidebarRowButton: View {
    let icon: String
    let label: String
    let system: SystemInfo?
    let count: Int
    let tint: Color
    let filter: LibraryFilter
    @Binding var selectedFilter: LibraryFilter
    var onRefresh: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var onSystemAction: ((SystemInfo, SystemAction, String?) -> Void)? = nil
    var onRename: ((SystemInfo) -> Void)? = nil
    var installedCores: [LibretroCore]? = nil
    var isGamepadFocused: Bool = false

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared
    
    var isSelected: Bool {
        selectedFilter.id == filter.id
    }
    
    var body: some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 6) {
                iconView
                    .frame(width: 22, height: 22)
                
                Text(label)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .medium : .regular)
                
                Spacer()
                
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? AppColors.accentBackground(colorScheme) : AppColors.cardBackgroundSubtle(colorScheme))
                    .cornerRadius(6)
                    .padding(.trailing, isHovered && system != nil ? 22 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if (isHovered || isSelected), system != nil {
                Menu {
                    sidebarContextMenuContent(for: system)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .menuIndicator(.hidden)
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
        .contextMenu {
            sidebarContextMenuContent(for: system)
        }
        .offset(y: isHovered ? -1 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AppColors.accentBackground(colorScheme) : (isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear))
        )
        .overlay {
            if isGamepadFocused {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.brandAccentSecondary)
                    .frame(width: 3, height: 20)
                    .padding(.leading, 2)
            }
        }
        .onHover { isHovered = $0 }
        .animation(AppMotion.micro, value: isHovered)
    }
    
    @ViewBuilder
    private func sidebarContextMenuContent(for system: SystemInfo?) -> some View {
        if let system = system {
            Button {
                onRename?(system)
            } label: {
                Label(loc.localized("contextMenu.rename"), systemImage: "pencil")
            }

            if let onSystemAction = onSystemAction {
                Button {
                    onSystemAction(system, .refresh, nil)
                } label: {
                    Label(loc.localized("contextMenu.refresh"), systemImage: "arrow.clockwise")
                }

                if installedCores?.isEmpty == false || system.defaultCoreID != nil {
                    if let internalIDs = SystemDatabase.multiSystemGroups()[system.id], internalIDs.count > 1 {
                        Menu {
                            ForEach(internalIDs, id: \.self) { id in
                                Button { onSystemAction(system, .settings(nil), id) } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gearshape")
                                }
                            }
                        } label: {
                            Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                        }
                    } else {
                        Button { onSystemAction(system, .settings(nil), nil) } label: {
                            Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                        }
                    }
                } else {
                    Button { onSystemAction(system, .selectCore(system), nil) } label: {
                        Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                    }
                }

                // MARK: - Action Buttons
                Group {
                    // ─── Shaders ───
                    if let internalIDs = SystemDatabase.multiSystemGroups()[system.id] {
                        Menu {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .shaders, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "wand.and.stars")
                                }
                            }
                        } label: {
                            Label(loc.localized("contextMenu.shaders"), systemImage: "wand.and.stars")
                        }
                    } else {
                        Button {
                            onSystemAction(system, .shaders, nil)
                        } label: {
                            Label(loc.localized("contextMenu.shaders"), systemImage: "wand.and.stars")
                        }
                    }

                    // ─── Bezels ───
                    if let internalIDs = SystemDatabase.multiSystemGroups()[system.id] {
                        Menu {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .bezels, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "rectangle.on.rectangle")
                                }
                            }
                        } label: {
                            Label(loc.localized("contextMenu.bezels"), systemImage: "rectangle.on.rectangle")
                        }
                    } else {
                        Button {
                            onSystemAction(system, .bezels, nil)
                        } label: {
                            Label(loc.localized("contextMenu.bezels"), systemImage: "rectangle.on.rectangle")
                        }
                    }

                    // ─── Cheats ───
                    if let internalIDs = SystemDatabase.multiSystemGroups()[system.id] {
                        Menu {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .cheats, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gamecontroller")
                                }
                            }
                        } label: {
                            Label(loc.localized("contextMenu.cheats"), systemImage: "gamecontroller")
                        }
                    } else {
                        Button {
                            onSystemAction(system, .cheats, nil)
                        } label: {
                            Label(loc.localized("contextMenu.cheats"), systemImage: "gamecontroller")
                        }
                    }

                    // ─── Controllers ───
                    if let internalIDs = SystemDatabase.multiSystemGroups()[system.id] {
                        Menu {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .controllers, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gamecontroller.fill")
                                }
                            }
                        } label: {
                            Label(loc.localized("contextMenu.controllers"), systemImage: "gamecontroller.fill")
                        }
                    } else {
                        Button {
                            onSystemAction(system, .controllers, nil)
                        } label: {
                            Label(loc.localized("contextMenu.controllers"), systemImage: "gamecontroller.fill")
                        }
                    }
                }

                Button {
                    onSystemAction(system, .library, nil)
                } label: {
                    Label(loc.localized("contextMenu.library"), systemImage: "book")
                }
            } else {
                Button {
                    onRefresh?()
                } label: {
                    Label(loc.localized("contextMenu.refresh"), systemImage: "arrow.clockwise")
                }
                Button {
                    onSettings?()
                } label: {
                    Label(loc.localized("contextMenu.settings"), systemImage: "gearshape")
                }
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let sys = system, let img = sys.emuImage(size: 132) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.system(size: 14))
        }
    }
}

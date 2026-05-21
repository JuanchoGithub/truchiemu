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
                    .foregroundColor(isSelected ? AppColors.brandAccent : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? AppColors.accentBackground(colorScheme) : Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
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

        if let cores = installedCores, cores.count > 1 {
                if let internalIDs = SystemDatabase.multiSystemGroups()[system.id] {
                    Menu {
                        ForEach(cores) { core in
                            if internalIDs.count > 1 {
                                Menu {
                                    ForEach(internalIDs, id: \.self) { id in
                                        Button { onSystemAction(system, .settings(core.id), id) } label: {
                                            Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "cpu")
                                        }
                                    }
                                } label: {
                                    Label(core.displayName, systemImage: "cpu")
                                }
                            } else {
                                Button { onSystemAction(system, .settings(core.id), nil) } label: {
                                    Label(core.displayName, systemImage: "cpu")
                                }
                            }
                        }
                    } label: {
                        Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                    }
                } else {
                    Menu {
                        ForEach(cores) { core in
                            Button { onSystemAction(system, .settings(core.id), nil) } label: {
                                Label(core.displayName, systemImage: "cpu")
                            }
                        }
                    } label: {
                        Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                    }
                }
            } else if let installedCore = installedCores?.first {
                if let internalIDs = SystemDatabase.multiSystemGroups()[system.id], internalIDs.count > 1 {
                    Menu {
                        ForEach(internalIDs, id: \.self) { id in
                            Button { onSystemAction(system, .settings(installedCore.id), id) } label: {
                                Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gearshape")
                            }
                        }
                    } label: {
                        Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                    }
                } else {
                    Button { onSystemAction(system, .settings(installedCore.id), nil) } label: {
                        Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                    }
                }
            } else if let coreID = system.defaultCoreID {
                if let internalIDs = SystemDatabase.multiSystemGroups()[system.id], internalIDs.count > 1 {
                    Menu {
                        ForEach(internalIDs, id: \.self) { id in
                            Button { onSystemAction(system, .settings(coreID), id) } label: {
                                Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gearshape")
                            }
                        }
                    } label: {
                        Label(loc.localized("contextMenu.coreOptions"), systemImage: "gearshape")
                    }
                } else {
                    Button { onSystemAction(system, .settings(coreID), nil) } label: {
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
        .offset(y: isHovered ? -1 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AppColors.accentBackground(colorScheme) : (isHovered ? Color.secondary.opacity(0.08) : .clear))
        )
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

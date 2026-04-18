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
    var onSystemAction: ((SystemInfo, SystemAction) -> Void)? = nil
    var installedCores: [LibretroCore]? = nil
    
    @State private var isHovered = false
    
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
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let system = system {
                if let onSystemAction = onSystemAction {
                    Button {
                        onSystemAction(system, .refresh)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    if let cores = installedCores, cores.count > 1 {
                        Menu {
                            ForEach(cores) { core in
                                Button {
                                    onSystemAction(system, .settings(core.id))
                                } label: {
                                    Label(core.displayName, systemImage: "cpu")
                                }
                            }
                        } label: {
                            Label("Core Options", systemImage: "gearshape")
                        }
                    } else if let installedCore = installedCores?.first {
                        Button {
                            onSystemAction(system, .settings(installedCore.id))
                        } label: {
                            Label("Core Options", systemImage: "gearshape")
                        }
                    } else if let coreID = system.defaultCoreID {
                        Button {
                            onSystemAction(system, .settings(coreID))
                        } label: {
                            Label("Core Options", systemImage: "gearshape")
                        }
                    } else {
                        Button {
                            onSystemAction(system, .selectCore(system))
                        } label: {
                            Label("Core Options", systemImage: "gearshape")
                        }
                    }

                     Button {
                         onSystemAction(system, .cheats)
                     } label: {
                         Label("Cheats", systemImage: "wand.and.stars")
                     }

                     Button {
                         onSystemAction(system, .shaders)
                     } label: {
                         Label("Shaders", systemImage: "wand.and.stars")
                     }

                    Button {
                        onSystemAction(system, .bezels)
                    } label: {
                        Label("Bezels", systemImage: "rectangle.on.rectangle")
                    }

                    Button {
                        onSystemAction(system, .controllers)
                    } label: {
                        Label("Controllers", systemImage: "gamecontroller")
                    }

                    Button {
                        onSystemAction(system, .library)
                    } label: {
                        Label("Library", systemImage: "book")
                    }
                } else {
                    Button {
                        onRefresh?()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        onSettings?()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.secondary.opacity(0.08) : .clear))
        )
        .onHover { isHovered = $0 }
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
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var loc = LocalizationManager.shared
    
    var isSelected: Bool {
        selectedFilter.id == filter.id
    }
    
    var body: some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 8) {
                iconBadgeView
                
                Text(label)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary : AppColors.textPrimary(colorScheme)))
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular, design: .rounded))
                
                Spacer()
                
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(
                        isSelected
                            ? AppColors.textOnAccent(for: AppColors.brandAccent, colorScheme: colorScheme)
                            : AppColors.textSecondary(colorScheme)
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? AppColors.brandAccent.opacity(0.85) : AppColors.cardBackgroundSubtle(colorScheme))
                    )

                // Gutter for the context-menu button that the trailing overlay
                // draws on hover/selection, so the ellipsis never lands on the
                // count. Only reserved when the button is actually visible so
                // other rows keep their full label width.
                if (isHovered || isSelected) && system != nil {
                    Color.clear
                        .frame(width: 20, height: 1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if (isHovered || isSelected), system != nil {
                Menu {
                    sidebarContextMenuContent(for: system)
                        .menuIconsAlwaysVisible()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.textSecondary(colorScheme))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .tint(AppColors.textSecondary(colorScheme))
                .fixedSize()
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
        .contextMenu {
            sidebarContextMenuContent(for: system)
                .menuIconsAlwaysVisible()
        }
        .offset(x: isHovered ? 1 : 0, y: isHovered ? -0.5 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    AppColors.brandAccent.opacity(colorScheme == .dark ? 0.24 : 0.16),
                                    AppColors.brandAccent.opacity(colorScheme == .dark ? 0.08 : 0.06)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(isHovered ? AppColors.cardBackgroundSubtle(colorScheme) : .clear)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? AppColors.brandAccent.opacity(0.30)
                        : (isHovered ? AppColors.cardBorder(colorScheme) : .clear),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if isGamepadFocused {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.brandAccent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColors.brandAccentSecondary, AppColors.brandAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 18)
                    .padding(.leading, 2)
                    .shadow(color: AppColors.brandAccent.opacity(0.6), radius: 3)
            }
        }
        .onHover { hovering in
            // Rows sweep under a stationary cursor while the list scrolls;
            // engaging hover per row re-renders each row mid-scroll (choppy).
            // Skip while a scroll gesture is active; state resets via the
            // scroll-activity transition notification (same pattern as the
            // library rows/cards).
            guard !ScrollActivity.isScrolling else { return }
            isHovered = hovering
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryScrollActivityChanged)) { _ in
            if ScrollActivity.isScrolling, isHovered {
                isHovered = false
            }
        }
        .animation(AppMotion.micro, value: isHovered)
        .animation(AppMotion.stateChange, value: isSelected)
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
                            Group {
                            ForEach(internalIDs, id: \.self) { id in
                                Button { onSystemAction(system, .settings(nil), id) } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gearshape")
                                }
                            }
                            }
                            .menuIconsAlwaysVisible()
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
                            Group {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .shaders, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "wand.and.stars")
                                }
                            }
                            }
                            .menuIconsAlwaysVisible()
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
                            Group {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .bezels, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "rectangle.on.rectangle")
                                }
                            }
                            }
                            .menuIconsAlwaysVisible()
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
                            Group {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .cheats, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gamecontroller")
                                }
                            }
                            }
                            .menuIconsAlwaysVisible()
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
                            Group {
                            ForEach(internalIDs, id: \.self) { id in
                                Button {
                                    onSystemAction(system, .controllers, id)
                                } label: {
                                    Label(SystemDatabase.system(forID: id)?.name ?? id, systemImage: "gamecontroller.fill")
                                }
                            }
                            }
                            .menuIconsAlwaysVisible()
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

    private var iconBadgeView: some View {
        iconView
            .frame(width: 16, height: 16)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        AppColors.brandAccent.opacity(0.30),
                                        AppColors.brandAccent.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(AppColors.cardBackgroundSubtle(colorScheme))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColors.brandAccent.opacity(0.30) : AppColors.cardBorder(colorScheme),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered && !reduceMotion ? 1.06 : 1)
            .animation(reduceMotion ? nil : AppMotion.micro, value: isHovered)
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
                .font(.system(size: 12, weight: .medium))
        }
    }
}

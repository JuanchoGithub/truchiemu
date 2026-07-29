import SwiftUI
import AppKit
import Combine

/// Overlay shown when entering TV mode with multiple screens attached (or
/// always, depending on `TVModeSettings.screenSelectionMode`). The user picks
/// a display with the D-pad / arrow keys; pressing A (or Return) confirms,
/// B (or Esc) cancels and falls back to the main display.
///
/// Why a custom view rather than a `.sheet`: TV mode opens the picker
/// BEFORE the host window goes fullscreen, so a SwiftUI sheet would attach
/// to a windowed window and then become invisible / detached when we move
/// and fullscreen the host. Keeping the picker as a regular overlay inside
/// `TVModeView` lets it stay mounted across the move-then-fullscreen dance.
struct TVModeScreenPickerView: View {
    let screens: [ScreenDescriptor]
    let initialFocusIndex: Int
    let onSelect: (ScreenDescriptor) -> Void
    let onCancel: () -> Void

    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tvModeScale) private var scale

    @StateObject private var nav: PickerNav

    init(screens: [ScreenDescriptor], initialFocusIndex: Int, onSelect: @escaping (ScreenDescriptor) -> Void, onCancel: @escaping () -> Void) {
        self.screens = screens
        self.initialFocusIndex = initialFocusIndex
        self.onSelect = onSelect
        self.onCancel = onCancel
        let initial = max(0, min(initialFocusIndex, max(screens.count - 1, 0)))
        _nav = StateObject(wrappedValue: PickerNav(count: screens.count, columnCount: 2, start: initial))
    }

    var body: some View {
        ZStack {
            AppColors.windowBackground(colorScheme, tinted: theme.tintedSurfacesEnabled)
                .opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 18 * scale) {
                header
                grid
                footerHint
            }
            .padding(28 * scale)
            .frame(maxWidth: 720 * scale)
            .background(
                RoundedRectangle(cornerRadius: 18 * scale)
                    .fill(AppColors.cardBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18 * scale)
                    .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1 * scale)
            )
            .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        }
        .onAppear {
            nav.bind(
                onSelect: { [self] idx in
                    guard screens.indices.contains(idx) else { return }
                    onSelect(screens[idx])
                },
                onCancel: { [self] in onCancel() }
            )
        }
        .onDisappear { nav.unbind() }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 4 * scale) {
            Text(loc.localized("tvMode.screenPicker.title"))
                .font(.system(size: 20 * scale, weight: .bold))
                .foregroundStyle(.primary)
            Text(loc.localized("tvMode.screenPicker.subtitle"))
                .font(.system(size: 13 * scale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var grid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 14 * scale),
            GridItem(.flexible(), spacing: 14 * scale)
        ]
        LazyVGrid(columns: columns, spacing: 14 * scale) {
            ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                ScreenTile(
                    screen: screen,
                    isFocused: nav.focusIndex == index,
                    mainLabel: loc.localized("tvMode.screenPicker.main"),
                    onSelect: { onSelect(screen) }
                )
                .overlay(focusRing(active: nav.focusIndex == index))
            }
        }
    }

    @ViewBuilder
    private func focusRing(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 12 * scale)
                .stroke(AppColors.brandAccent, lineWidth: 3 * scale)
                .padding(-4 * scale)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var footerHint: some View {
        HStack(spacing: 18 * scale) {
            hintChip(symbol: "a.circle.fill", label: loc.localized("tvMode.screenPicker.confirm"))
            hintChip(symbol: "b.circle.fill", label: loc.localized("tvMode.screenPicker.cancel"))
        }
    }

    @ViewBuilder
    private func hintChip(symbol: String, label: String) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 14 * scale, weight: .semibold))
            Text(label)
                .font(.system(size: 12 * scale, weight: .medium))
        }
        .foregroundStyle(.secondary)
    }
}

/// One display entry in the picker. Renders an aspect-ratio rectangle that
/// hints at the screen's geometry (16:9, 21:9, 4:3, etc.) plus its label and
/// summary. macOS doesn't expose a screen thumbnail from a non-ScreenCaptureKit
/// API, and ScreenCaptureKit would require an extra permission the user
/// hasn't granted for an emulator — so we mirror the geometry honestly.
private struct ScreenTile: View {
    let screen: ScreenDescriptor
    let isFocused: Bool
    let mainLabel: String
    let onSelect: () -> Void

    @Environment(\.tvModeScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10 * scale) {
                GeometryReader { proxy in
                    let tileWidth = proxy.size.width
                    let tileHeight = max(48 * scale, tileWidth / max(screen.aspectRatio, 0.4))
                    ZStack {
                        RoundedRectangle(cornerRadius: 8 * scale)
                            .fill(AppColors.windowBackground(colorScheme, tinted: false))
                        RoundedRectangle(cornerRadius: 8 * scale)
                            .strokeBorder(AppColors.divider(colorScheme), lineWidth: 1 * scale)
                    }
                    .frame(width: tileWidth, height: tileHeight)
                }
                .frame(height: 96 * scale)

                VStack(alignment: .leading, spacing: 2 * scale) {
                    HStack(spacing: 6 * scale) {
                        Text(screen.name)
                            .font(.system(size: 14 * scale, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if screen.isMain {
                            Text(mainLabel)
                                .font(.system(size: 9 * scale, weight: .bold))
                                .padding(.horizontal, 6 * scale).padding(.vertical, 2 * scale)
                                .background(Capsule().fill(AppColors.brandAccent.opacity(0.2)))
                                .foregroundStyle(AppColors.brandAccent)
                        }
                    }
                    Text(screen.summary)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                    Text("x=\(Int(screen.frame.origin.x)), y=\(Int(screen.frame.origin.y))")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14 * scale)
            .background(
                RoundedRectangle(cornerRadius: 12 * scale)
                    .fill(isFocused
                          ? AppColors.brandAccent.opacity(0.10)
                          : AppColors.cardBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12 * scale)
                    .strokeBorder(
                        isFocused ? AppColors.brandAccent : AppColors.cardBorder(colorScheme),
                        lineWidth: isFocused ? 2 * scale : 1 * scale
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class PickerNav: ObservableObject {
    @Published var focusIndex: Int
    let context: GamepadSheetContext
    private var focusSubscription: AnyCancellable?

    init(count: Int, columnCount: Int, start: Int) {
        self.context = GamepadSheetContext(itemCount: count, columnCount: columnCount)
        self.focusIndex = max(0, min(start, max(count - 1, 0)))
    }

    func bind(onSelect: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        context.onSelect = { [weak self] idx in
            guard self != nil else { return }
            onSelect(idx)
        }
        context.onDismiss = { onCancel() }
        context.focusIndex = focusIndex
        GamepadNavContextStack.shared.push(context)
        focusSubscription = context.$focusIndex
            .removeDuplicates()
            .sink { [weak self] idx in
                guard let self else { return }
                if idx != self.focusIndex { self.focusIndex = idx }
            }
    }

    func unbind() {
        focusSubscription?.cancel()
        focusSubscription = nil
        GamepadNavContextStack.shared.remove(context)
        context.onSelect = nil
        context.onDismiss = nil
    }
}

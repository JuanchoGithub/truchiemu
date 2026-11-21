import SwiftUI

// MARK: - Toolbar chrome
//
// Shared building blocks for the main-window toolbar. They keep the chrome
// consistent: one accent rule, one icon weight, one zoom control.

/// Applies the shared toolbar icon treatment. The user can turn the accent
/// tint off in Settings, so every icon reads the same flag.
struct ToolbarIconStyle: ViewModifier {
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        content.foregroundStyle(theme.toolbarAccentEnabled ? AppColors.brandAccent : .primary)
    }
}

extension View {
    func toolbarIconStyle() -> some View {
        modifier(ToolbarIconStyle())
    }
}

// MARK: - Grid zoom control

/// Compact grid-size control for the toolbar: `− 50% +`.
///
/// The two step buttons change the zoom by one slider step. The percent label
/// opens a popover with the full slider and a reset action. This replaces the
/// 248pt inline slider, so the toolbar keeps its space for the other groups.
struct ToolbarZoomControl: View {
    @Binding var zoom: Double
    /// Called after every change so the grid can recompute its column count.
    var onChange: () -> Void = {}

    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSlider = false
    @State private var hoveredStep: Step?

    private enum Step { case decrease, increase }

    /// Same step as the old inline slider.
    private let step = 1.0 / 7.0

    /// The slider runs 0...1, but the readout is a card scale: the saved
    /// default (0.5) reads as 100%, the smallest card as 50%, the largest as
    /// 150%. A raw 0...100 readout would show "0%" on a card that is still
    /// on screen.
    private var percent: Int {
        Int((50 + zoom * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 0) {
            stepButton(.decrease, systemImage: "minus", helpKey: "toolbar.zoomOut")

            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1, height: 12)

            Button {
                showSlider.toggle()
            } label: {
                Text(verbatim: "\(percent)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary(colorScheme))
                    .frame(width: 38, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.localized("toolbar.gridSize"))
            .popover(isPresented: $showSlider, arrowEdge: .bottom) {
                sliderPopover
            }

            Rectangle()
                .fill(AppColors.divider(colorScheme))
                .frame(width: 1, height: 12)

            stepButton(.increase, systemImage: "plus", helpKey: "toolbar.zoomIn")
        }
        .frame(height: 24)
        .background(
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ step: Step, systemImage: String, helpKey: String) -> some View {
        let isDisabled = step == .increase ? zoom >= 1 : zoom <= 0
        return Button {
            let delta = step == .increase ? self.step : -self.step
            if reduceMotion {
                zoom = min(1, max(0, zoom + delta))
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    zoom = min(1, max(0, zoom + delta))
                }
            }
            onChange()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                    isDisabled
                        ? AppColors.textMuted(colorScheme).opacity(0.5)
                        : (hoveredStep == step ? AppColors.brandAccent : AppColors.textSecondary(colorScheme))
                )
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            hoveredStep = hovering ? step : (hoveredStep == step ? nil : hoveredStep)
        }
        .help(loc.localized(helpKey))
    }

    private var sliderPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(loc.localized("toolbar.gridSize"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary(colorScheme))

                Spacer(minLength: 0)

                Text(verbatim: "\(percent)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }

            Slider(value: $zoom, in: 0...1, step: step, onEditingChanged: { editing in
                if !editing { onChange() }
            })
            .tint(AppColors.brandAccent)

            Text(loc.localized("toolbar.gridSizeHint"))
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer(minLength: 0)
                Button(loc.localized("app.reset")) {
                    zoom = 0.5
                    onChange()
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
        }
        .padding(12)
        .frame(width: 250)
    }
}

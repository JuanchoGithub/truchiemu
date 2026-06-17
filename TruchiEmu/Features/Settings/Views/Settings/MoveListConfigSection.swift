import SwiftUI

struct MoveListConfigSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var residualDelay: Double = AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25)
    @State private var inputTimeout: Double = AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0)
    @State private var chargeThreshold: Double = AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8)
    @State private var maxMoves: Int = AppSettings.getInt("moveListMaxMoves", defaultValue: 5)

    var body: some View {
        Group {
            Section(header: Label(loc.localized("settings.moveList.inputTiming"), systemImage: "timer")) {
                timingSlider(
                    label: loc.localized("settings.moveList.residualDelay"),
                    value: $residualDelay,
                    range: 0...0.5,
                    step: 0.01,
                    format: { "\(Int($0 * 1000)) ms" },
                    desc: loc.localized("settings.moveList.residualDelayDesc"),
                    key: "moveListResidualDelay"
                )
                timingSlider(
                    label: loc.localized("settings.moveList.inputTimeout"),
                    value: $inputTimeout,
                    range: 0.5...3.0,
                    step: 0.1,
                    format: { String(format: "%.1f s", $0) },
                    desc: loc.localized("settings.moveList.inputTimeoutDesc"),
                    key: "moveListInputTimeout"
                )
                timingSlider(
                    label: loc.localized("settings.moveList.chargeThreshold"),
                    value: $chargeThreshold,
                    range: 0.3...2.0,
                    step: 0.1,
                    format: { String(format: "%.1f s", $0) },
                    desc: loc.localized("settings.moveList.chargeThresholdDesc"),
                    key: "moveListChargeThreshold"
                )
            }

            Section(header: Label(loc.localized("settings.moveList.display"), systemImage: "eye")) {
                Stepper(value: $maxMoves, in: 3...10) {
                    Text(loc.localized("settings.moveList.maxMoves"))
                    Spacer()
                    Text("\(maxMoves)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary(colorScheme))
                }
                .onChange(of: maxMoves) { _, newValue in
                    AppSettings.setInt("moveListMaxMoves", value: newValue)
                }
                Text(loc.localized("settings.moveList.maxMovesDesc"))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
        }
        .onAppear {
            residualDelay = AppSettings.getDouble("moveListResidualDelay", defaultValue: 0.25)
            inputTimeout = AppSettings.getDouble("moveListInputTimeout", defaultValue: 1.0)
            chargeThreshold = AppSettings.getDouble("moveListChargeThreshold", defaultValue: 0.8)
            maxMoves = AppSettings.getInt("moveListMaxMoves", defaultValue: 5)
        }
    }

    @ViewBuilder
    private func timingSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        desc: String,
        key: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary(colorScheme))
            }
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, newValue in
                    AppSettings.setDouble(key, value: newValue)
                }
            Text(desc)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary(colorScheme))
        }
    }
}

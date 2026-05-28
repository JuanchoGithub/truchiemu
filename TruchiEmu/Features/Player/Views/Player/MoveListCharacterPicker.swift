import SwiftUI

struct MoveListCharacterPicker: View {
    @ObservedObject var viewModel: MoveListOverlayViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Text(loc.localized("movelist.selectCharacter"))
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.characters) { character in
                        Button(action: {
                            viewModel.selectCharacter(character)
                            dismiss()
                        }) {
                            HStack {
                                Text(character.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)

                                Spacer()

                                if viewModel.selectedCharacterName == character.name {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppColors.brandAccent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if character.name != viewModel.characters.last?.name {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
        .frame(width: 220, height: min(CGFloat(viewModel.characters.count) * 44 + 60, 400))
        .background(AppColors.windowBackground(colorScheme, tinted: ThemeManager.shared.tintedSurfacesEnabled))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

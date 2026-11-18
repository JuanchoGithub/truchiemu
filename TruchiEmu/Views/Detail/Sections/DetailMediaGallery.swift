import SwiftUI

/// Media viewer for game screenshots: one large frame plus a thumbnail rail.
/// Clicking a thumbnail swaps the frame; clicking the frame opens the existing
/// full-screen zoom viewer. Letterboxing is intentional — screenshots keep
/// their native aspect instead of being cropped to fill the card.
struct DetailMediaGallery: View {
    let images: [NSImage]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0
    @State private var showFullScreen = false

    private var safeIndex: Int {
        min(max(selected, 0), max(images.count - 1, 0))
    }

    var body: some View {
        VStack(spacing: 10) {
            frame
            if images.count > 1 {
                thumbnailRail
            }
        }
        .onChange(of: images.count) { _, newCount in
            if selected >= newCount {
                selected = max(0, newCount - 1)
            }
        }
    }

    private var frame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.10))

            if images.indices.contains(safeIndex) {
                Image(nsImage: images[safeIndex])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            }
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColors.cardBorder(colorScheme), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "\(safeIndex + 1) / \(images.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(.black.opacity(0.5)))
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.black.opacity(0.45)))
                .padding(8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard images.indices.contains(safeIndex) else { return }
            showFullScreen = true
        }
        .sheet(isPresented: $showFullScreen) {
            if images.indices.contains(safeIndex) {
                DetailZoomableFullScreenView(image: images[safeIndex], fullResolutionURL: nil, rom: nil)
                    .gamepadDismissable { showFullScreen = false }
                    .frame(minWidth: 900, minHeight: 675)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: safeIndex)
    }

    private var thumbnailRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images.indices, id: \.self) { index in
                    Button {
                        guard index != safeIndex else { return }
                        withAnimation(reduceMotion ? nil : AppMotion.stateChange) {
                            selected = index
                        }
                    } label: {
                        Image(nsImage: images[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 78, height: 56)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        index == safeIndex
                                            ? AppColors.brandAccent
                                            : AppColors.cardBorder(colorScheme),
                                        lineWidth: index == safeIndex ? 1.5 : 1
                                    )
                            )
                            .opacity(index == safeIndex ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

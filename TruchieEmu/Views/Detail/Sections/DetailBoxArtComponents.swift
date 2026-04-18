import SwiftUI

// MARK: - Detail Box Art Button

struct DetailBoxArtButton: View {
    let image: NSImage?
    let rom: ROM?
    let placeholder: () -> AnyView
    @State private var isPresented = false
    @State private var showPicker = false

    var body: some View {
        Button {
            if image != nil {
                isPresented = true
            } else {
                showPicker = true
            }
        } label: {
            Group {
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholder()
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            if let img = image {
                DetailZoomableFullScreenView(image: img)
            }
        }
        .sheet(isPresented: $showPicker) {
            if let rom = rom {
                BoxArtPickerView(rom: rom)
            }
        }
    }
}

// MARK: - Detail Zoomable Full Screen View

struct DetailZoomableFullScreenView: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(1.0, lastScale * value), 5.0)
                        }
                        .onEnded { _ in
                            if scale < 1.1 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastScale = 1.0
                                    lastOffset = .zero
                                }
                            } else {
                                lastScale = scale
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastScale = 1.0
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(showControls ? 1 : 0)
                }
                Spacer()
                Text("Pinch to zoom")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
                    .opacity(showControls ? 1 : 0)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
    }
}
import SwiftUI
import BoxArtLayers

// MARK: - Detail Box Art Button

struct DetailBoxArtButton: View {
    let image: NSImage?
    let imageURL: URL?
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
                DetailZoomableFullScreenView(image: img, fullResolutionURL: imageURL, rom: rom)
                    .gamepadDismissable { isPresented = false }
                    .frame(minWidth: 900, minHeight: 675)
            }
        }
        .sheet(isPresented: $showPicker) {
            if let rom = rom {
                BoxArtPickerView(rom: rom)
                    .gamepadDismissable { showPicker = false }
            }
        }
    }
}

// MARK: - Detail Zoomable Full Screen View

struct DetailZoomableFullScreenView: View {
    let image: NSImage
    let fullResolutionURL: URL?
    let rom: ROM?
    @Environment(\.dismiss) private var dismiss
    private var loc: LocalizationManager { LocalizationManager.shared }
    @State private var showControls = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
@State private var fullResImage: NSImage? = nil
    @State private var holoEnabled = false
    @State private var holoSeed: UInt64 = 0
    @State private var holoMasks: HoloMaskSet? = nil
    @State private var isLoadingHolo = false
    @State private var mousePosition: CGPoint? = nil
    @State private var artworkFrame: CGRect = .zero
    @State private var tiltRotationX: Double = 0
    @State private var tiltRotationY: Double = 0

    private var romID: String {
        rom?.id.uuidString ?? "detail_\(image.hash)"
    }

    private let maxTiltAngle: Double = 9
    private let tiltPerspective: CGFloat = 0.5

    private var normalizedMouseX: CGFloat {
        guard let mp = mousePosition, artworkFrame.width > 0 else { return 0.5 }
        return min(max((mp.x - artworkFrame.minX) / artworkFrame.width, 0), 1)
    }

    private var normalizedMouseY: CGFloat {
        guard let mp = mousePosition, artworkFrame.height > 0 else { return 0.5 }
        return min(max((mp.y - artworkFrame.minY) / artworkFrame.height, 0), 1)
    }

    private var tiltTargetRotationX: Double {
        (normalizedMouseY - 0.5) * 2 * maxTiltAngle
    }

    private var tiltTargetRotationY: Double {
        (0.5 - normalizedMouseX) * 2 * maxTiltAngle
    }

    private var tiltCombinedAngle: Double {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        let qw = cos(ay / 2) * cos(ax / 2)
        return 2 * acos(min(max(qw, -1), 1)) * 180 / .pi
    }

    private var tiltCombinedAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        let ax = tiltRotationX * .pi / 180
        let ay = tiltRotationY * .pi / 180
        var x = cos(ay / 2) * sin(ax / 2)
        var y = sin(ay / 2) * cos(ax / 2)
        var z = -sin(ay / 2) * sin(ax / 2)
        let len = sqrt(x * x + y * y + z * z)
        if len < 1e-6 { return (1, 0, 0) }
        return (x / len, y / len, z / len)
    }

    private var isOverArtwork: Bool {
        guard let mp = mousePosition else { return false }
        return artworkFrame.contains(mp)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let imageSize = fullResImage?.size ?? image.size
                let aspect = imageSize.width / imageSize.height
                let availableWidth = geo.size.width * 0.98
                let availableHeight = geo.size.height * 0.98
                let fittedWidth = min(availableWidth, availableHeight * aspect)
                let fittedHeight = min(availableHeight, availableWidth / aspect)
                // Stabilize to 0.5pt buckets to prevent cache fragmentation from floating-point variance
                let holoW = (fittedWidth * 2).rounded() / 2
                let holoH = (fittedHeight * 2).rounded() / 2

                ZStack {
                    Image(nsImage: fullResImage ?? image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedWidth, height: fittedHeight)
                        .scaleEffect(scale)
                        .offset(offset)
                        .rotation3DEffect(
                            .degrees(tiltCombinedAngle),
                            axis: tiltCombinedAxis,
                            anchor: .center,
                            perspective: tiltPerspective
                        )
                        .background(
                            GeometryReader { artworkGeo in
                                Color.clear
                                    .onAppear {
                                        artworkFrame = artworkGeo.frame(in: .global)
                                    }
                                    .onChange(of: artworkGeo.frame(in: .global)) { _, newFrame in
                                        artworkFrame = newFrame
                                    }
                            }
                        )
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

                    if holoEnabled, let masks = holoMasks {
                        let snapshot = HoloSettingsSnapshot(
                            from: HoloSettingsStore.shared,
                            romID: romID,
                            seed: holoSeed
                        )
                        let variant = snapshot.randomization?.variant ?? .regularHolo
                        let isSwiftHolo = variant == .reverseSwift
                        let useWebHolo = !isSwiftHolo && (snapshot.renderingEngine[variant] ?? .web) == .web

                        if useWebHolo {
                            HoloWebCardView(
                                image: fullResImage ?? image,
                                variantClass: variant.cssClass,
                                pointerX: normalizedMouseX,
                                pointerY: normalizedMouseY,
                                heroMask: masks.hero,
                                frameSize: CGSize(width: holoW, height: holoH),
                                fitMode: .contain,
                                isActive: true
                            )
                            .frame(width: holoW, height: holoH)
                            .scaleEffect(scale)
                            .offset(offset)
                            .rotation3DEffect(
                                .degrees(tiltCombinedAngle),
                                axis: tiltCombinedAxis,
                                anchor: .center,
                                perspective: tiltPerspective
                            )
                            .allowsHitTesting(false)
                        } else {
                            HoloFoilLayers(
                                masks: masks,
                                settings: snapshot,
                                w: holoW,
                                h: holoH,
                                pointerX: normalizedMouseX,
                                pointerY: normalizedMouseY,
                                tiltX: tiltRotationX,
                                tiltY: tiltRotationY,
                                isHovered: isOverArtwork,
                                allowBump: true
                            )
                            .frame(width: holoW, height: holoH)
                            .scaleEffect(scale)
                            .offset(offset)
                            .rotation3DEffect(
                                .degrees(tiltCombinedAngle),
                                axis: tiltCombinedAxis,
                                anchor: .center,
                                perspective: tiltPerspective
                            )
                            .allowsHitTesting(false)

                            HoloSheenEffect(pointerX: normalizedMouseX, pointerY: normalizedMouseY)
                                .frame(width: holoW, height: holoH)
                                .scaleEffect(scale)
                                .offset(offset)
                                .rotation3DEffect(
                                    .degrees(tiltCombinedAngle),
                                    axis: tiltCombinedAxis,
                                    anchor: .center,
                                    perspective: tiltPerspective
                                )
                                .allowsHitTesting(false)

                            HoloScratchLayer(w: holoW, h: holoH)
                                .frame(width: holoW, height: holoH)
                                .scaleEffect(scale)
                                .offset(offset)
                                .rotation3DEffect(
                                    .degrees(tiltCombinedAngle),
                                    axis: tiltCombinedAxis,
                                    anchor: .center,
                                    perspective: tiltPerspective
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        mousePosition = location
                        withAnimation(.interpolatingSpring(stiffness: 200, damping: 15)) {
                            tiltRotationX = tiltTargetRotationX
                            tiltRotationY = tiltTargetRotationY
                        }
                    case .ended:
                        mousePosition = nil
                        withAnimation(.interpolatingSpring(stiffness: 200, damping: 15)) {
                            tiltRotationX = 0
                            tiltRotationY = 0
                        }
                    }
                }
            }

            VStack {
                HStack {
                    if !isLoadingHolo {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                holoEnabled.toggle()
                                if holoEnabled {
                                    holoSeed = UInt64.random(in: 0...UInt64.max)
                                    loadHoloMasks()
                                } else {
                                    holoMasks = nil
                                }
                            }
                        } label: {
                            Image(systemName: holoEnabled ? "sparkles" : "sparkles.tv")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(holoEnabled ? .yellow : .white.opacity(0.7))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .overlay(
                                            Circle()
                                                .stroke(holoEnabled ? Color.yellow.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1.5)
                                        )
                                )
                                .shadow(color: holoEnabled ? .yellow.opacity(0.4) : .black.opacity(0.3), radius: holoEnabled ? 8 : 4)
                                .scaleEffect(holoEnabled ? 1.1 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.top, 10)
                        .help(holoEnabled ? loc.localized("boxArt.holoDisable") : loc.localized("boxArt.holoEnable"))
                        .accessibilityLabel(holoEnabled ? loc.localized("boxArt.holoDisable") : loc.localized("boxArt.holoEnable"))
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                            )
                            .padding(.leading, 20)
                            .padding(.top, 10)
                    }

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(showControls ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer()
                Text("boxArt.pinchToZoom")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 20)
                .opacity(showControls ? 1 : 0)
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
        .onAppear {
            if let url = fullResolutionURL {
                Task {
                    fullResImage = await ImageCache.shared.fullResolutionImage(for: url)
                }
            }
        }
        .onChange(of: fullResolutionURL) { _, _ in
            holoMasks = nil
            holoEnabled = false
        }
    }

    private func loadHoloMasks() {
        guard !isLoadingHolo else { return }
        isLoadingHolo = true
        Task.detached(priority: .utility) { [image = image, romID = romID] in
            let masks = await HoloSaliencyService.shared.holoMasks(romID: romID, image: image)
            await MainActor.run {
                self.holoMasks = masks
                self.isLoadingHolo = false
            }
        }
    }
}

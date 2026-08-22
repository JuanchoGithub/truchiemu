import BoxArtLayers
import Darwin
import Foundation

@main
struct BoxArtLayersCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let input = arguments.first else {
            fputs("Usage: boxart-layers <image> [output-dir]\n", stderr)
            exit(64)
        }

        let inputURL = URL(fileURLWithPath: input)
        let outputURL: URL
        if arguments.count >= 2 {
            outputURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
        } else {
            outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(
                inputURL.deletingPathExtension().lastPathComponent + "-layers",
                isDirectory: true
            )
        }

        do {
            let bundle = try await BoxArtDecomposer().decompose(contentsOf: inputURL)
            try LayerExporter.write(bundle, to: outputURL)

            let quality = bundle.manifest.quality
            print("Wrote \(outputURL.path)")
            print("instances: \(quality.instanceCount)")
            print("hero area: \(String(format: "%.1f%%", quality.heroAreaRatio * 100))")
            print("title: \(quality.titleDetected ? "yes" : "no")")
            if quality.needsReview {
                print("needs review: \(quality.reasons.joined(separator: ", "))")
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

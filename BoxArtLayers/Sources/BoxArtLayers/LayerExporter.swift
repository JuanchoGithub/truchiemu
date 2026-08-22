import CoreGraphics
import Foundation

public enum LayerExporter {
    /// Writes full-frame PNGs plus `manifest.json`. Safe to point a holographic compositor at.
    public static func write(_ bundle: LayerBundle, to directory: URL) throws {
        let masks = directory.appendingPathComponent("masks")
        let cutouts = directory.appendingPathComponent("cutouts")
        try FileManager.default.createDirectory(at: masks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cutouts, withIntermediateDirectories: true)

        try ImageIOSupport.writePNG(bundle.source, to: directory.appendingPathComponent("source.png"))
        try ImageIOSupport.writePNG(bundle.frontnessMap, to: directory.appendingPathComponent("frontness.png"))
        try ImageIOSupport.writePNG(bundle.preview, to: directory.appendingPathComponent("preview.png"))

        try ImageIOSupport.writePNG(bundle.masks.hero, to: masks.appendingPathComponent("hero.png"))
        try ImageIOSupport.writePNG(bundle.masks.title, to: masks.appendingPathComponent("title.png"))
        try ImageIOSupport.writePNG(bundle.masks.midground, to: masks.appendingPathComponent("midground.png"))
        try ImageIOSupport.writePNG(bundle.masks.background, to: masks.appendingPathComponent("background.png"))
        try ImageIOSupport.writePNG(bundle.masks.chrome, to: masks.appendingPathComponent("chrome.png"))
        try ImageIOSupport.writePNG(bundle.masks.frozen, to: masks.appendingPathComponent("frozen.png"))

        try ImageIOSupport.writePNG(bundle.cutouts.hero, to: cutouts.appendingPathComponent("hero.png"))
        try ImageIOSupport.writePNG(bundle.cutouts.title, to: cutouts.appendingPathComponent("title.png"))
        try ImageIOSupport.writePNG(bundle.cutouts.midground, to: cutouts.appendingPathComponent("midground.png"))
        try ImageIOSupport.writePNG(bundle.cutouts.background, to: cutouts.appendingPathComponent("background.png"))
        try ImageIOSupport.writePNG(bundle.cutouts.chrome, to: cutouts.appendingPathComponent("chrome.png"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bundle.manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))
    }
}

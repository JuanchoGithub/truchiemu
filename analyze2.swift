import AppKit
import Foundation
for f in ["p600_a8", "p600_a40", "p1_a8", "p100_a8"] {
    guard let img = NSImage(contentsOfFile: "/tmp/tiltgui/\(f).png"),
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { print("\(f): fail"); continue }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    // Count non-white, non-transparent pixels and find bbox
    var minX = w, maxX = 0, minY = h, maxY = 0, count = 0
    for y in 0..<h { for x in 0..<w {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent, a = c.alphaComponent
        if a < 0.1 { continue }
        if r < 0.9 || g < 0.9 || b < 0.9 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            count += 1
        }
    }}
    print("\(f): nonwhite bbox x \(minX)-\(maxX) y \(minY)-\(maxY) w=\(maxX-minX) h=\(maxY-minY) px=\(count) size=\(w)x\(h)")
}

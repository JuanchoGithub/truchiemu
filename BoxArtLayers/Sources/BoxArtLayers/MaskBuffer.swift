import CoreGraphics
import Foundation

/// Full-frame 8-bit grayscale mask, origin top-left. Internal working format.
struct MaskBuffer: Equatable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, fill: UInt8 = 0) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: fill, count: width * height)
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    func area(threshold: UInt8 = 32) -> Int {
        var count = 0
        for value in pixels where value >= threshold { count += 1 }
        return count
    }

    func areaRatio(threshold: UInt8 = 32) -> Double {
        let total = width * height
        guard total > 0 else { return 0 }
        return Double(area(threshold: threshold)) / Double(total)
    }

    func boundingBox(threshold: UInt8 = 32) -> CGRect {
        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] >= threshold {
                found = true
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
        guard found else { return .zero }
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX + 1),
            height: max(1, maxY - minY + 1)
        )
    }

    func centroid(threshold: UInt8 = 32) -> CGPoint {
        var sx = 0, sy = 0, n = 0
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] >= threshold {
                sx += x
                sy += y
                n += 1
            }
        }
        guard n > 0 else { return CGPoint(x: width / 2, y: height / 2) }
        return CGPoint(x: Double(sx) / Double(n), y: Double(sy) / Double(n))
    }

    func mean(of other: MaskBuffer, threshold: UInt8 = 32) -> Double {
        precondition(other.width == width && other.height == height)
        var sum = 0, n = 0
        for i in 0..<pixels.count where pixels[i] >= threshold {
            sum += Int(other.pixels[i])
            n += 1
        }
        guard n > 0 else { return 0 }
        return Double(sum) / Double(n) / 255.0
    }

    func union(_ other: MaskBuffer) -> MaskBuffer {
        combining(other) { a, b in max(a, b) }
    }

    func intersecting(_ other: MaskBuffer) -> MaskBuffer {
        combining(other) { a, b in min(a, b) }
    }

    func subtracting(_ other: MaskBuffer) -> MaskBuffer {
        combining(other) { a, b in
            let value = Int(a) - Int(b)
            return UInt8(clamping: value)
        }
    }

    func inverted() -> MaskBuffer {
        var copy = self
        for i in 0..<copy.pixels.count {
            copy.pixels[i] = 255 - copy.pixels[i]
        }
        return copy
    }

    func thresholded(_ cut: UInt8) -> MaskBuffer {
        var copy = self
        for i in 0..<copy.pixels.count {
            copy.pixels[i] = copy.pixels[i] >= cut ? 255 : 0
        }
        return copy
    }

    /// Square max-filter; expands letterforms and instance edges.
    func dilated(radius: Int) -> MaskBuffer {
        guard radius > 0 else { return self }
        var output = MaskBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                var best: UInt8 = 0
                let y0 = max(0, y - radius), y1 = min(height - 1, y + radius)
                let x0 = max(0, x - radius), x1 = min(width - 1, x + radius)
                for yy in y0...y1 {
                    let row = yy * width
                    for xx in x0...x1 {
                        let value = pixels[row + xx]
                        if value > best { best = value }
                    }
                }
                output.pixels[y * width + x] = best
            }
        }
        return output
    }

    mutating func fill(_ rect: CGRect, value: UInt8 = 255) {
        let x0 = max(0, Int(rect.minX.rounded(.down)))
        let y0 = max(0, Int(rect.minY.rounded(.down)))
        let x1 = min(width, Int(rect.maxX.rounded(.up)))
        let y1 = min(height, Int(rect.maxY.rounded(.up)))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 {
            let row = y * width
            for x in x0..<x1 {
                pixels[row + x] = max(pixels[row + x], value)
            }
        }
    }

    /// 4-connected components, largest first.
    func connectedComponents(threshold: UInt8 = 32, minArea: Int = 16) -> [MaskBuffer] {
        var visited = [Bool](repeating: false, count: pixels.count)
        var components: [MaskBuffer] = []
        for y in 0..<height {
            for x in 0..<width {
                let start = y * width + x
                if visited[start] || pixels[start] < threshold { continue }

                var queue = [(x, y)]
                var head = 0
                visited[start] = true
                var points: [(Int, Int)] = []
                while head < queue.count {
                    let (cx, cy) = queue[head]
                    head += 1
                    points.append((cx, cy))
                    let neighbors = [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                    for (nx, ny) in neighbors {
                        if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                        let ni = ny * width + nx
                        if visited[ni] || pixels[ni] < threshold { continue }
                        visited[ni] = true
                        queue.append((nx, ny))
                    }
                }
                guard points.count >= minArea else { continue }
                var component = MaskBuffer(width: width, height: height)
                for (px, py) in points {
                    component.pixels[py * width + px] = pixels[py * width + px]
                }
                components.append(component)
            }
        }
        return components.sorted { $0.area(threshold: threshold) > $1.area(threshold: threshold) }
    }

    private func combining(_ other: MaskBuffer, _ op: (UInt8, UInt8) -> UInt8) -> MaskBuffer {
        precondition(other.width == width && other.height == height)
        var output = MaskBuffer(width: width, height: height)
        for i in 0..<pixels.count {
            output.pixels[i] = op(pixels[i], other.pixels[i])
        }
        return output
    }
}

import XCTest
@testable import BoxArtLayers

final class MaskBufferTests: XCTestCase {
    func testUnionSubtractAndArea() {
        var a = MaskBuffer(width: 4, height: 4)
        var b = MaskBuffer(width: 4, height: 4)
        a.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        b.fill(CGRect(x: 1, y: 1, width: 2, height: 2))

        XCTAssertEqual(a.area(), 4)
        XCTAssertEqual(a.union(b).area(), 7)
        XCTAssertEqual(a.subtracting(b).area(), 3)
        XCTAssertEqual(a.intersecting(b).area(), 1)
        XCTAssertEqual(a.inverted().area(), 12)
    }

    func testConnectedComponents() {
        var mask = MaskBuffer(width: 10, height: 4)
        mask.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        mask.fill(CGRect(x: 7, y: 1, width: 3, height: 2))
        let parts = mask.connectedComponents(minArea: 2)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].area(), 6)
        XCTAssertEqual(parts[1].area(), 4)
    }

    func testCentroidAndDilation() {
        var mask = MaskBuffer(width: 8, height: 8)
        mask.fill(CGRect(x: 2, y: 2, width: 2, height: 2))
        let dilated = mask.dilated(radius: 1)
        XCTAssertGreaterThan(dilated.area(), mask.area())
        XCTAssertEqual(mask.centroid().x, 2.5, accuracy: 0.01)
        XCTAssertEqual(mask.centroid().y, 2.5, accuracy: 0.01)
    }
}

final class ChromeDetectorTests: XCTestCase {
    func testLeftSpineOnGreyBar() {
        let width = 100
        let height = 40
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if x < 12 {
                    rgba[i] = 180
                    rgba[i + 1] = 180
                    rgba[i + 2] = 185
                    rgba[i + 3] = 255
                } else {
                    rgba[i] = 240
                    rgba[i + 1] = 80
                    rgba[i + 2] = 40
                    rgba[i + 3] = 255
                }
            }
        }

        let edge = ChromeDetector.leftSpineEnd(
            rgba: rgba,
            width: width,
            height: height,
            maxFraction: 0.2
        )
        XCTAssertNotNil(edge)
        XCTAssertGreaterThanOrEqual(edge ?? 0, 9)
        XCTAssertLessThanOrEqual(edge ?? 0, 16)
    }

    func testNoSpineOnUniformArt() {
        let width = 80
        let height = 20
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgba[i] = 40
            rgba[i + 1] = 180
            rgba[i + 2] = 70
            rgba[i + 3] = 255
        }
        XCTAssertNil(
            ChromeDetector.leftSpineEnd(rgba: rgba, width: width, height: height, maxFraction: 0.14)
        )
    }
}

final class LayerAssignerTests: XCTestCase {
    func testHeroWinsOnLargestFrontInstance() {
        let width = 20
        let height = 20
        var hero = MaskBuffer(width: width, height: height)
        var extra = MaskBuffer(width: width, height: height)
        var front = MaskBuffer(width: width, height: height, fill: 40)
        hero.fill(CGRect(x: 6, y: 4, width: 10, height: 12))
        extra.fill(CGRect(x: 1, y: 14, width: 4, height: 4))
        for y in 4..<16 {
            for x in 6..<16 { front[x, y] = 220 }
        }

        let scene = SceneAnalysis(
            width: width,
            height: height,
            instances: [
                InstanceCandidate(
                    id: 1,
                    mask: extra,
                    boundingBox: extra.boundingBox(),
                    areaRatio: extra.areaRatio(),
                    frontness: 0.2,
                    centroid: extra.centroid()
                ),
                InstanceCandidate(
                    id: 2,
                    mask: hero,
                    boundingBox: hero.boundingBox(),
                    areaRatio: hero.areaRatio(),
                    frontness: 0.9,
                    centroid: hero.centroid()
                ),
            ],
            text: [
                TextHit(
                    string: "SUPER MARIO BROS. 3",
                    boundingBox: CGRect(x: 4, y: 1, width: 12, height: 3),
                    confidence: 0.8
                ),
            ],
            frontness: front,
            chromeHint: MaskBuffer(width: width, height: height)
        )

        let assigned = LayerAssigner.assign(scene, configuration: .default)
        XCTAssertTrue(assigned.roles.values.contains(.hero))
        XCTAssertGreaterThan(assigned.hero.area(), 0)
        XCTAssertTrue(assigned.title.area() > 0)
        XCTAssertTrue(assigned.quality.titleDetected)
        XCTAssertGreaterThan(assigned.hero.area(), assigned.midground.area())
    }
}

final class ImageOrientationTests: XCTestCase {
    func testFixtureIsUprightAfterRasterization() throws {
        let fixture = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/super-mario-advance-4.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path), fixture.path)

        let image = try ImageIOSupport.loadCGImage(from: fixture)
        let rgba = ImageIOSupport.rgbaBytes(from: image)
        let width = rgba.width
        let height = rgba.height

        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let i = (y * width + x) * 4
            return (rgba.pixels[i], rgba.pixels[i + 1], rgba.pixels[i + 2])
        }

        let spine = pixel(8, height / 2)
        let sky = pixel(width / 2, 18)
        let spineSat = ChromeDetector.saturationOf(r: spine.r, g: spine.g, b: spine.b)
        let skySat = ChromeDetector.saturationOf(r: sky.r, g: sky.g, b: sky.b)

        XCTAssertLessThan(
            spineSat,
            skySat - 0.08,
            "Left column should be the grey GBA bar; if this fails the buffer is flipped"
        )
        XCTAssertGreaterThan(Int(sky.r) + Int(sky.g), Int(sky.b) + 80, "Top-center should be warm sky, not brown ground")
    }
}

import Foundation

extension BoxArtDecomposer {
    public struct Configuration: Sendable {
        /// Minimum / maximum hero coverage of the full image. Outside this range → `needsReview`.
        public var heroMinAreaRatio: Double
        public var heroMaxAreaRatio: Double
        /// Normalized vertical band (0 = top) where titles usually sit.
        public var titleBand: ClosedRange<Double>
        /// Left-most fraction inspected for a hardware spine (GBA / DS / etc.).
        public var chromeLeftMaxFraction: Double
        public var maskThreshold: UInt8
        /// Dilate OCR boxes so stylized outlines are included.
        public var titleDilateRadius: Int
        public var instanceDilateRadius: Int

        public init(
            heroMinAreaRatio: Double = 0.06,
            heroMaxAreaRatio: Double = 0.50,
            titleBand: ClosedRange<Double> = 0.0...0.55,
            chromeLeftMaxFraction: Double = 0.14,
            maskThreshold: UInt8 = 28,
            titleDilateRadius: Int = 3,
            instanceDilateRadius: Int = 1
        ) {
            self.heroMinAreaRatio = heroMinAreaRatio
            self.heroMaxAreaRatio = heroMaxAreaRatio
            self.titleBand = titleBand
            self.chromeLeftMaxFraction = chromeLeftMaxFraction
            self.maskThreshold = maskThreshold
            self.titleDilateRadius = titleDilateRadius
            self.instanceDilateRadius = instanceDilateRadius
        }

        public static let `default` = Configuration()
    }
}

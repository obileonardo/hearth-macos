import XCTest
@testable import Hearth

final class ACAirAppearanceTests: XCTestCase {
    func testCoolerTargetsMakeMoreDefinedAirMonotonically() {
        let targets = [30.0, 27, 24, 21, 18, 16]
        let values = targets.map { ACAirAppearance.normalizedChill(target: $0, lowerBound: 16, upperBound: 30) }
        XCTAssertEqual(values.first, 0)
        XCTAssertEqual(values.last, 1)
        for (warmer, cooler) in zip(values, values.dropFirst()) {
            XCTAssertGreaterThan(cooler, warmer)
            XCTAssertGreaterThan(ACAirAppearance(chill: cooler).ribbonStrength, ACAirAppearance(chill: warmer).ribbonStrength)
            XCTAssertGreaterThan(ACAirAppearance(chill: cooler).coreStrength, ACAirAppearance(chill: warmer).coreStrength)
        }
    }

    func testOutOfRangeTargetsClampAtDeviceEndpoints() {
        XCTAssertEqual(ACAirAppearance.normalizedChill(target: -100, lowerBound: 16, upperBound: 30), 1)
        XCTAssertEqual(ACAirAppearance.normalizedChill(target: 200, lowerBound: 16, upperBound: 30), 0)
    }

    func testMissingNonfiniteAndInvalidCapabilitiesStayNeutral() {
        let invalid: [(Double?, Double?, Double?)] = [
            (nil, 16, 30), (24, nil, 30), (24, 16, nil),
            (.nan, 16, 30), (.infinity, 16, 30), (-.infinity, 16, 30),
            (24, .nan, 30), (24, 16, .infinity), (24, 30, 16), (24, 24, 24),
            (24, -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude),
        ]
        for (target, low, high) in invalid {
            XCTAssertEqual(ACAirAppearance.normalizedChill(target: target, lowerBound: low, upperBound: high), 0.5)
        }
    }

    func testCelsiusAndFahrenheitRangesProduceEquivalentChill() {
        for celsius in stride(from: 16.0, through: 30.0, by: 0.5) {
            let fahrenheit = celsius * 1.8 + 32
            let c = ACAirAppearance.normalizedChill(target: celsius, lowerBound: 16, upperBound: 30)
            let f = ACAirAppearance.normalizedChill(target: fahrenheit, lowerBound: 60.8, upperBound: 86)
            XCTAssertEqual(c, f, accuracy: 0.000001)
        }
    }

    func testNeutralDefaultPreservesOtherIllustrationCallersAndModulationIsRestrained() {
        let neutral = ACAirAppearance(chill: ACAirAppearance.neutralChill)
        XCTAssertEqual(neutral.ribbonStrength, 1)
        XCTAssertEqual(neutral.coreStrength, 1)
        XCTAssertEqual(neutral.mistStrength, 1)
        XCTAssertEqual(ACAirAppearance(chill: .nan).chill, 0.5)
        XCTAssertEqual(ACAirAppearance(chill: -.infinity).chill, 0.5)
        XCTAssertEqual(ACAirAppearance(chill: -1).chill, 0)
        XCTAssertEqual(ACAirAppearance(chill: 2).chill, 1)
        XCTAssertLessThanOrEqual(ACAirAppearance(chill: 1).coreStrength, 1.2)
        XCTAssertLessThanOrEqual(ACAirAppearance(chill: 1).mistStrength, 1.08)
    }

    func testEnlargedIllustrationFits404PointContentWidthAndMovesWholeFlowDown() {
        XCTAssertEqual(ClimateIllustrationLayout.bodyWidth, 282.9, accuracy: 0.000001)
        XCTAssertLessThan(ClimateIllustrationLayout.canvasWidth, 404)
        XCTAssertEqual(ClimateIllustrationLayout.topSpacing - 2, 8)
        // A natural VStack frame grows with the illustration, moving every
        // following control together rather than overlaying the temperature.
        let oldHeight = 16 + 246.0 * (0.265 + 0.46)
        let newHeight = 16 + Double(ClimateIllustrationLayout.bodyWidth) * (0.265 + 0.46)
        XCTAssertGreaterThan(newHeight, oldHeight)
    }
}

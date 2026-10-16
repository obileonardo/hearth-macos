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
        XCTAssertEqual(ACAirAppearance(chill: 0).coreStrength, 0.6, accuracy: 0.000001)
        XCTAssertEqual(ACAirAppearance(chill: 1).coreStrength, 2.0, accuracy: 0.000001)
        XCTAssertLessThanOrEqual(ACAirAppearance(chill: 1).mistStrength, 3.0)
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
    func testCoolingPaletteUsesPaleIceInsteadOfSaturatedBlue() throws {
        for mode in ["cool", "auto", "heat_cool"] {
            for dark in [true, false] {
                for core in [true, false] {
                    let cold = try XCTUnwrap(ACAirAppearance(chill: 1, mode: mode).palette(dark: dark, core: core))
                    let expected = dark
                        ? (core ? ACAirAppearance.RGB(red: 0.88, green: 0.96, blue: 1) : ACAirAppearance.RGB(red: 0.74, green: 0.88, blue: 1))
                        : (core ? ACAirAppearance.RGB(red: 0.26, green: 0.47, blue: 0.64) : ACAirAppearance.RGB(red: 0.34, green: 0.53, blue: 0.68))
                    XCTAssertEqual(cold.red, expected.red, accuracy: 0.000001)
                    XCTAssertEqual(cold.green, expected.green, accuracy: 0.000001)
                    XCTAssertEqual(cold.blue, expected.blue, accuracy: 0.000001)
                    XCTAssertGreaterThan(cold.blue, cold.green)
                    XCTAssertGreaterThan(cold.green, cold.red)
                    XCTAssertLessThanOrEqual(cold.blue - cold.red, dark ? 0.261 : 0.381)
                    for index in 51...100 {
                        let interpolated = try XCTUnwrap(ACAirAppearance(chill: Double(index) / 100, mode: mode).palette(dark: dark, core: core))
                        for channel in [interpolated.red, interpolated.green, interpolated.blue] {
                            XCTAssertTrue((0...1).contains(channel))
                        }
                    }
                }
            }
        }
    }

    func testNeutralAndNonCoolingModesPreserveOriginalColorAndStrength() {
        for mode in ["cool", "auto", "heat_cool", "heat", "dry", "fan_only", "off", "custom"] {
            let neutral = ACAirAppearance(chill: 0.5, mode: mode)
            XCTAssertNil(neutral.palette(dark: true))
            XCTAssertNil(neutral.palette(dark: false, core: true))
        }
        for mode in ["heat", "dry", "fan_only", "off", "custom"] {
            for chill in [0.0, 0.25, 0.75, 1] {
                let appearance = ACAirAppearance(chill: chill, mode: mode)
                XCTAssertEqual(appearance.chill, 0.5)
                XCTAssertEqual(appearance.coreStrength, 1)
                XCTAssertEqual(appearance.mistStrength, 1)
                XCTAssertNil(appearance.palette(dark: true, core: true))
                XCTAssertNil(appearance.palette(dark: false))
            }
        }
    }

    func testWarmEndIsSofterAndMistRemainsBoundedAsLanesStrengthen() {
        let warm = ACAirAppearance(chill: 0)
        let cold = ACAirAppearance(chill: 1)
        XCTAssertGreaterThan(cold.coreStrength / warm.coreStrength, 2.5)
        XCTAssertEqual(warm.mistStrength, 0.65)
        XCTAssertLessThanOrEqual(cold.mistStrength, 3.0)
        XCTAssertLessThan(cold.mistStrength / warm.mistStrength, 4.7)
        for index in 0...100 {
            let appearance = ACAirAppearance(chill: Double(index) / 100)
            XCTAssertTrue((0.6...2.0).contains(appearance.coreStrength))
            XCTAssertTrue((0.65...3.0).contains(appearance.mistStrength))
        }
    }

    func testColdWindPlumeAndLaneWidthIncreaseWithoutChangingTheirBounds() {
        let neutral = ACAirAppearance(chill: 0.5)
        XCTAssertEqual(neutral.windPace, 1)
        XCTAssertEqual(neutral.laneWidth, 1)
        XCTAssertEqual(neutral.tailExponent, 1.8)
        for index in 0..<100 {
            let warm = ACAirAppearance(chill: Double(index) / 100)
            let cool = ACAirAppearance(chill: Double(index + 1) / 100)
            XCTAssertGreaterThan(cool.windPace, warm.windPace)
            XCTAssertGreaterThan(cool.laneWidth, warm.laneWidth)
            XCTAssertLessThan(cool.tailExponent, warm.tailExponent)
            XCTAssertGreaterThan(cool.tailEnvelope(at: 0.65), warm.tailEnvelope(at: 0.65))
        }
        let cold = ACAirAppearance(chill: 1)
        XCTAssertEqual(cold.windPace, 1.45)
        XCTAssertEqual(cold.laneWidth, 1.3)
        XCTAssertEqual(cold.tailExponent, 1.1, accuracy: 0.000001)
        XCTAssertEqual(cold.tailEnvelope(at: 1), 0)
        XCTAssertEqual(cold.tailEnvelope(at: 0), 1)
        XCTAssertEqual(cold.tailEnvelope(at: .nan), 0)
        XCTAssertGreaterThan(cold.pace(fanIntensity: 1), cold.pace(fanIntensity: 0.3))
        XCTAssertEqual(cold.pace(fanIntensity: .nan), cold.pace(fanIntensity: 0.6))
        XCTAssertEqual(ACAirAppearance(chill: 1, mode: "heat").windPace, 1)
        XCTAssertEqual(ACAirAppearance(chill: 1, mode: "dry").laneWidth, 1)
    }

    func testPhaseClockChangesPaceContinuouslyInsteadOfMultiplyingEpochTime() {
        let clock = ACAirPhaseClock()
        let start = clock.sample(at: 800_000_000, rate: 1)
        let next = clock.sample(at: 800_000_000.1, rate: 1.45)
        XCTAssertEqual(next - start, 0.1225, accuracy: 0.000001)
        let third = clock.sample(at: 800_000_000.2, rate: 1.45)
        XCTAssertEqual(third - next, 0.145, accuracy: 0.000001)
        XCTAssertEqual(clock.sample(at: 800_000_000.2, rate: 1), third)
    }

    func testPhaseClockHandlesInvalidInputsPowerPauseAndLongGapsWithoutJumping() {
        let clock = ACAirPhaseClock()
        XCTAssertEqual(clock.sample(at: .nan, rate: 1), 0)
        XCTAssertEqual(clock.sample(at: 100, rate: 1), 100)
        XCTAssertEqual(clock.sample(at: 100.1, rate: .infinity), 100)
        XCTAssertEqual(clock.sample(at: 100.1, rate: -1), 100)
        XCTAssertEqual(clock.sample(at: 105, rate: 1), 100)
        XCTAssertEqual(clock.sample(at: 105.1, rate: 1), 100.1, accuracy: 0.000001)
        XCTAssertEqual(clock.sample(at: 105.2, rate: 1, running: false), 100.1, accuracy: 0.000001)
        XCTAssertEqual(clock.sample(at: 110, rate: 1), 100.1, accuracy: 0.000001)
        XCTAssertEqual(clock.sample(at: 110.1, rate: 1), 100.2, accuracy: 0.000001)
        XCTAssertEqual(clock.sample(at: 90, rate: 1), 100.2, accuracy: 0.000001)
        XCTAssertTrue(ACAirPhaseClock().sample(at: .greatestFiniteMagnitude, rate: 2).isFinite)
    }

    func testAirFooterFadeCompletesBeforeCanvasEdgeWithoutChangingLayout() throws {
        let width = Double(ClimateIllustrationLayout.bodyWidth)
        let height = 16 + width * (0.265 + 0.46)
        let fade = try XCTUnwrap(ACAirEdgeFade(width: width, height: height))
        XCTAssertEqual(height, 221.1025, accuracy: 0.000001)
        XCTAssertEqual(fade.end, height - 8)
        XCTAssertEqual(fade.end - fade.start, width * 0.17, accuracy: 0.000001)
        XCTAssertEqual(fade.alpha(at: fade.start), 1)
        XCTAssertEqual(fade.alpha(at: (fade.start + fade.end) / 2), 0.5, accuracy: 0.000001)
        XCTAssertEqual(fade.alpha(at: fade.end), 0)
        XCTAssertEqual(fade.alpha(at: height - 1), 0)
        XCTAssertEqual(fade.alpha(at: height), 0)
        XCTAssertEqual(fade.gradient.stops.first?.location, 0)
        XCTAssertEqual(fade.gradient.stops.last?.location, 1)
    }

    func testAirFooterFadeIsBoundedAndMonotonicAcrossIllustrationSizes() throws {
        for width in [1.0, 64, 160, 240, 282.9, 480, 1000] {
            let height = 16 + width * (0.265 + 0.46)
            let fade = try XCTUnwrap(ACAirEdgeFade(width: width, height: height))
            XCTAssertGreaterThan(fade.start, 0)
            XCTAssertLessThan(fade.start, fade.end)
            XCTAssertLessThan(fade.end, height)
            var previous = 1.0
            for index in 0...200 {
                let alpha = fade.alpha(at: height * Double(index) / 200)
                XCTAssertTrue((0...1).contains(alpha))
                XCTAssertLessThanOrEqual(alpha, previous)
                previous = alpha
            }
            XCTAssertEqual(fade.alpha(at: -10), 1)
            XCTAssertEqual(fade.alpha(at: height + 10), 0)
        }
    }

    func testAirFooterFadeRejectsInvalidGeometryAndNonfiniteSamples() throws {
        for (width, height) in [(0.0, 100.0), (-1, 100), (100, 0), (100, -1), (.nan, 100), (100, .infinity)] {
            XCTAssertNil(ACAirEdgeFade(width: width, height: height))
        }
        let fade = try XCTUnwrap(ACAirEdgeFade(width: 282.9, height: 221.1025))
        XCTAssertEqual(fade.alpha(at: .nan), 0)
        XCTAssertEqual(fade.alpha(at: .infinity), 0)
        XCTAssertEqual(fade.alpha(at: -.infinity), 0)
        XCTAssertEqual(fade.alpha(at: fade.start - 0.01), 1)
        XCTAssertGreaterThan(fade.alpha(at: fade.start + 0.01), 0.999)
        XCTAssertLessThan(fade.alpha(at: fade.end - 0.01), 0.001)
    }

}

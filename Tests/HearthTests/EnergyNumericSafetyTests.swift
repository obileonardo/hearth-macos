import Foundation
import XCTest
@testable import Hearth

final class EnergyNumericSafetyTests: XCTestCase {
    private func sensor(_ state: String, unit: String = "W") -> Entity {
        Entity(id: "sensor.energy_fixture", state: state, attributes: ["unit_of_measurement": unit])
    }

    func testNormalPowerAndEnergyUnitsRemainUnchanged() {
        XCTAssertEqual(EnergyUnits.watts(sensor("1.5", unit: "kW")), 1500)
        XCTAssertEqual(EnergyUnits.watts(sensor("2", unit: "MW")), 2_000_000)
        XCTAssertEqual(EnergyUnits.watts(sensor("500", unit: "mW")), 0.5)
        XCTAssertEqual(EnergyUnits.kilowattHours(sensor("500", unit: "Wh")), 0.5)
        XCTAssertEqual(EnergyUnits.kilowattHours(sensor("2", unit: "MWh")), 2000)
        XCTAssertEqual(EnergyUnits.power(-1500), "1.5 kW")
        XCTAssertEqual(EnergyUnits.energy(0.5), "500 Wh")
    }

    func testNonfiniteSensorStatesNeverBecomeEnergyReadings() {
        for invalid in ["NaN", "inf", "-inf", "unknown", "unavailable"] {
            XCTAssertNil(EnergyUnits.watts(sensor(invalid)))
            XCTAssertNil(EnergyUnits.kilowattHours(sensor(invalid, unit: "kWh")))
        }
    }

    func testUnitMultiplicationOverflowIsUnavailable() {
        for unit in ["kW", "MW"] {
            XCTAssertNil(EnergyUnits.watts(sensor("1e308", unit: unit)))
        }
        XCTAssertNil(EnergyUnits.kilowattHours(sensor("1e308", unit: "MWh")))
    }

    func testInvalidDisplayValuesUseDashWithoutIntegerTrap() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(EnergyUnits.power(invalid), "—")
            XCTAssertEqual(EnergyUnits.energy(invalid), "—")
            XCTAssertNil(EnergyNumeric.rounded(invalid))
        }
        XCTAssertEqual(EnergyUnits.energy(-Double.greatestFiniteMagnitude), "—")
        XCTAssertNil(EnergyNumeric.rounded(Double(Int.max)))
        XCTAssertNil(EnergyNumeric.rounded(Double.greatestFiniteMagnitude))
    }

    func testDurationPreservesNormalOutputAndRejectsOverflow() {
        XCTAssertEqual(EnergyUnits.duration(hours: 0.5), "30 min")
        XCTAssertEqual(EnergyUnits.duration(hours: 1), "1 h")
        XCTAssertEqual(EnergyUnits.duration(hours: 1.5), "1 h 30 min")
        XCTAssertEqual(EnergyUnits.duration(hours: 72), "3 days")
        for invalid in [Double.nan, Double.infinity, -Double.infinity, -1, Double.greatestFiniteMagnitude, Double(Int.max)] {
            XCTAssertEqual(EnergyUnits.duration(hours: invalid), "—")
        }
    }

    func testBatteryPercentRejectsInvalidRangeBeforeWidgetsOrMenuUseIt() {
        var system = EnergySystem()
        for invalid in ["NaN", "inf", "1e300", "-1", "101"] {
            system.charge = sensor(invalid, unit: "%")
            XCTAssertNil(system.chargePercent)
        }
        for value in [0.0, 44.5, 100] {
            system.charge = sensor(String(value), unit: "%")
            XCTAssertEqual(system.chargePercent, value)
        }
    }

    func testCapacityChecksEveryScaledResultAndVoltage() {
        var system = EnergySystem()
        for unit in ["kWh", "MWh", "Ah"] {
            system.batteryCapacity = sensor("1e308", unit: unit)
            system.batteryVoltage = sensor("52", unit: "V")
            XCTAssertNil(system.capacityWattHours)
        }
        system.batteryCapacity = sensor("100", unit: "Ah")
        system.batteryVoltage = sensor("NaN", unit: "V")
        XCTAssertNil(system.capacityWattHours)
        system.batteryVoltage = sensor("52", unit: "V")
        XCTAssertEqual(system.capacityWattHours, 5200)
    }

    func testTotalsRejectOverflowInsteadOfPassingInfinityToDrawing() {
        var system = EnergySystem()
        system.solar = [sensor("1e308"), sensor("1e308")]
        XCTAssertNil(system.solarWatts)
        system.solar = [sensor("1e308")]
        system.grid = sensor("1e308")
        XCTAssertNil(system.loadWatts)
        XCTAssertNil(EnergyNumeric.sum([1, Double.nan]))
        XCTAssertNil(EnergyNumeric.sum([]))
        XCTAssertEqual(EnergyNumeric.sum([100, 200]), 300)
    }

    func testInvalidSplitFlowDoesNotInventZeroReading() {
        var system = EnergySystem()
        system.batteryCharging = sensor("NaN")
        system.gridImport = sensor("inf")
        XCTAssertNil(system.batteryWatts)
        XCTAssertNil(system.gridWatts)
        system.batteryCharging = sensor("100")
        system.gridImport = sensor("250")
        XCTAssertEqual(system.batteryWatts, -100)
        XCTAssertEqual(system.gridWatts, 250)
    }

    func testTemperatureOutputUsesSafeRoundedConversion() {
        XCTAssertEqual(EnergyNumeric.temperature(sensor("23.6", unit: "°C")), "24°C")
        XCTAssertEqual(EnergyNumeric.temperature(sensor("-4.2", unit: "°C")), "-4°C")
        for invalid in ["NaN", "inf", "-inf", "1e300"] {
            XCTAssertNil(EnergyNumeric.temperature(sensor(invalid, unit: "°C")))
            XCTAssertNil(EnergyNumeric.rounded(EnergyNumeric.value(sensor(invalid, unit: "%"))))
        }
    }

    func testCellVoltageAndSpreadRejectNonfiniteAndOverflow() {
        XCTAssertEqual(EnergyNumeric.cellVoltage(sensor("3300", unit: "mV")), 3.3)
        XCTAssertNil(EnergyNumeric.cellVoltage(sensor("NaN", unit: "V")))
        XCTAssertEqual(EnergyNumeric.cellSpread(low: 3.3, high: 3.305), 5)
        XCTAssertNil(EnergyNumeric.cellSpread(low: .nan, high: 3.3))
        XCTAssertNil(EnergyNumeric.cellSpread(low: 3.4, high: 3.3))
        XCTAssertNil(EnergyNumeric.cellSpread(low: -1e308, high: 1e308))
        XCTAssertNil(EnergyNumeric.cellSpread(low: 0, high: 1e300))
    }
}

import Foundation
import XCTest
@testable import Hearth

final class NumericDeviceReadingsTests: XCTestCase {
    private func device(_ entities: [Entity]) -> HomeDevice {
        HomeDevice(info: DeviceInfo(id: "fixture", name: "Fixture", manufacturer: nil, model: nil), entities: entities)
    }
    private func sensor(_ key: String, _ state: String, unit: String? = nil, deviceClass: String? = nil) -> Entity {
        var attributes: JSON = [:]
        if let unit { attributes["unit_of_measurement"] = unit }
        if let deviceClass { attributes["device_class"] = deviceClass }
        return Entity(id: "sensor.fixture_" + key, state: state, attributes: attributes)
    }
    private func vehicle(_ entities: [Entity]) -> VehicleStatus { VehicleStatus(device(entities), kind: .electricCar) }
    private func printJob(progress: String = "42.5", remaining: String = "84", unit: String = "min", nozzle: String = "215.6", bed: String = "59.5") -> PrintJob {
        PrintJob(device([
            sensor("print_status", "running"), sensor("print_progress", progress),
            sensor("remaining_time", remaining, unit: unit),
            sensor("nozzle_temperature", nozzle), sensor("bed_temperature", bed)
        ]))
    }

    func testVehicleBatteryAndChargeLimitRejectInvalidPercentages() {
        for value in ["nan", "inf", "-inf", "1e300", "-1", "101"] {
            let status = vehicle([
                sensor("battery", value, unit: "%", deviceClass: "battery"),
                sensor("charge_limit", value, unit: "%")
            ])
            XCTAssertNil(status.battery, value)
            XCTAssertNil(status.percent, value)
            XCTAssertNil(status.chargeLimit, value)
        }
        let normal = vehicle([sensor("battery", "78.5", unit: "%", deviceClass: "battery"), sensor("charge_limit", "90", unit: "%")])
        XCTAssertEqual(normal.battery, 78.5)
        XCTAssertEqual(normal.percent, "79%")
        XCTAssertEqual(normal.chargeLimit, 90)
    }

    func testVacuumBatteryAttributeIsValidatedWithoutInventingZero() {
        for value in [Double.nan, .infinity, -.infinity, -1, 101, .greatestFiniteMagnitude] {
            let robot = Entity(id: "vacuum.fixture", state: "docked", attributes: ["battery_level": value])
            let status = VehicleStatus(device([robot]), kind: .robotVacuum)
            XCTAssertNil(status.battery)
            XCTAssertNil(status.percent)
            XCTAssertEqual(status.roverState, "Docked")
        }
        let robot = Entity(id: "vacuum.fixture", state: "docked", attributes: ["battery_level": 64.0])
        XCTAssertEqual(VehicleStatus(device([robot]), kind: .robotVacuum).percent, "64%")
    }

    func testVehicleRangeUsesSafeRoundedIntegerAndKeepsItsUnit() {
        for value in ["nan", "inf", "-inf", "1e300", "9223372036854775808", "-1"] {
            XCTAssertNil(vehicle([sensor("range", value, unit: "km")]).range, value)
        }
        XCTAssertEqual(vehicle([sensor("range", "312.6", unit: "km")]).range, "313 km")
        XCTAssertEqual(vehicle([sensor("range", "0", unit: "mi")]).range, "0 mi")
    }

    func testVehicleDurationValidatesAfterUnitScaling() {
        for unit in ["min", "h", "s"] {
            for value in ["nan", "inf", "-inf", "1e300", "-10"] {
                XCTAssertNil(VehicleStatus.timeLeft(sensor("time_to_full", value, unit: unit)), value + unit)
            }
        }
        XCTAssertNil(VehicleStatus.timeLeft(sensor("time_to_full", "9223372036854775808", unit: "min")))
        XCTAssertEqual(VehicleStatus.timeLeft(sensor("time_to_full", "1.4", unit: "h")), "1 h 24 min to full")
        XCTAssertEqual(VehicleStatus.timeLeft(sensor("time_to_full", "120", unit: "s")), "2 min to full")
    }

    func testPowerAndSessionEnergyExcludeInvalidNumbers() {
        for value in ["nan", "inf", "-inf", "1e300"] {
            XCTAssertNil(VehicleStatus.power(sensor("charger_power", value, unit: "W", deviceClass: "power")))
            XCTAssertNil(vehicle([sensor("session_energy", value, unit: "kWh", deviceClass: "energy")]).sessionEnergy)
        }
        XCTAssertEqual(VehicleStatus.power(sensor("charger_power", "735", unit: "W")), "735 W")
        XCTAssertEqual(VehicleStatus.power(sensor("charger_power", "7200", unit: "W")), "7.2 kW")
        XCTAssertEqual(vehicle([sensor("session_energy", "1.5", unit: "kWh", deviceClass: "energy")]).sessionEnergy, "1.5 kWh")
    }

    func testPrinterProgressRejectsInvalidValuesWithoutPretendingToFinish() {
        for value in ["nan", "inf", "-inf", "1e300", "-1", "101"] {
            let job = printJob(progress: value)
            XCTAssertNil(job.progress, value)
            XCTAssertEqual(job.summary, "Printing")
        }
        XCTAssertEqual(printJob(progress: "42.5").progress, 0.425)
        XCTAssertEqual(printJob(progress: "42.5").summary, "Printing, 43%")
        XCTAssertEqual(printJob(progress: "100").progress, 1)
    }

    func testPrinterDurationRejectsNonfiniteOverflowAndNegativeReadings() {
        for unit in ["min", "h", "s", "d"] {
            for value in ["nan", "inf", "-inf", "1e300", "-10"] {
                let job = printJob(remaining: value, unit: unit)
                XCTAssertNil(job.remainingMinutes, value + unit)
                XCTAssertNil(job.timeLeft, value + unit)
            }
        }
        XCTAssertNil(printJob(remaining: "9223372036854775808").remainingMinutes)
        XCTAssertEqual(printJob(remaining: "1.4", unit: "h").timeLeft, "1 h 24 min left")
        XCTAssertEqual(printJob(remaining: "120", unit: "s").timeLeft, "2 min left")
        XCTAssertEqual(printJob(remaining: "1", unit: "d").timeLeft, "24 h 0 min left")
    }

    func testPrinterTemperaturesSafelyRoundOnlyRepresentableValues() {
        for value in ["nan", "inf", "-inf", "1e300", "9223372036854775808"] {
            let job = printJob(nozzle: value, bed: value)
            XCTAssertNil(job.nozzle, value)
            XCTAssertNil(job.bed, value)
        }
        XCTAssertEqual(printJob().nozzle, "216°")
        XCTAssertEqual(printJob().bed, "60°")
        XCTAssertEqual(printJob(nozzle: "-2.5").nozzle, "-3°")
    }
}

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.const import PERCENTAGE, UnitOfEnergy, UnitOfLength, UnitOfPower, UnitOfSpeed, UnitOfTemperature

from . import CAR, CHARGER, DOMAIN, MOWER, Stand, soon


class Reading(Stand, SensorEntity):
    def __init__(self, world, device, key, name, value, *, device_class=None, unit=None, options=None):
        super().__init__(world, device, key, name)
        self._value = value
        self._attr_device_class = device_class
        self._attr_native_unit_of_measurement = unit
        if options:
            self._attr_options = options

    @property
    def native_value(self):
        return self._value(self.world)


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    D = SensorDeviceClass

    def charging(w):
        return w.car_charging == "charging"

    add([
        # Tesla Fleet names (translation keys charge_state_*, drive_state_*, climate_state_*)
        Reading(w, CAR, "battery_level", "Battery level", lambda w: w.battery, device_class=D.BATTERY, unit=PERCENTAGE),
        Reading(w, CAR, "battery_range", "Battery range", lambda w: 312, device_class=D.DISTANCE,
                unit=UnitOfLength.KILOMETERS),
        Reading(w, CAR, "est_battery_range", "Estimate battery range", lambda w: 290, device_class=D.DISTANCE,
                unit=UnitOfLength.KILOMETERS),
        Reading(w, CAR, "charging", "Charging", lambda w: w.car_charging, device_class=D.ENUM,
                options=["starting", "charging", "disconnected", "stopped", "complete", "no_power"]),
        Reading(w, CAR, "charger_power", "Charger power", lambda w: 7.2 if charging(w) else 0, device_class=D.POWER,
                unit=UnitOfPower.KILO_WATT),
        # Tesla's charge rate is range added per hour, not power.
        Reading(w, CAR, "charge_rate", "Charge rate", lambda w: 48 if charging(w) else 0, device_class=D.SPEED,
                unit=UnitOfSpeed.KILOMETERS_PER_HOUR),
        Reading(w, CAR, "charge_energy_added", "Charge energy added", lambda w: 12.3, device_class=D.ENERGY,
                unit=UnitOfEnergy.KILO_WATT_HOUR),
        Reading(w, CAR, "minutes_to_full_charge", "Time to full charge", lambda w: soon(84) if charging(w) else None,
                device_class=D.TIMESTAMP),
        Reading(w, CAR, "inside_temp", "Inside temperature", lambda w: 24.5, device_class=D.TEMPERATURE,
                unit=UnitOfTemperature.CELSIUS),
        # Wallbox names
        Reading(w, CHARGER, "status_description", "Status description", lambda w: w.charger_status),
        Reading(w, CHARGER, "charging_power", "Charging power",
                lambda w: 7.2 if w.charger_status == "Charging" else 0, device_class=D.POWER,
                unit=UnitOfPower.KILO_WATT),
        Reading(w, CHARGER, "added_energy", "Added energy", lambda w: 18.4, device_class=D.ENERGY,
                unit=UnitOfEnergy.KILO_WATT_HOUR),
        Reading(w, CHARGER, "added_range", "Added range", lambda w: 96, device_class=D.DISTANCE,
                unit=UnitOfLength.KILOMETERS),
        Reading(w, CHARGER, "state_of_charge", "State of charge", lambda w: w.battery, device_class=D.BATTERY,
                unit=PERCENTAGE),
        # Husqvarna Automower names
        Reading(w, MOWER, "battery", "Battery", lambda w: 64, device_class=D.BATTERY, unit=PERCENTAGE),
        Reading(w, MOWER, "mode", "Mode", lambda w: "main_area", device_class=D.ENUM,
                options=["main_area", "secondary_area", "home", "demo"]),
    ])

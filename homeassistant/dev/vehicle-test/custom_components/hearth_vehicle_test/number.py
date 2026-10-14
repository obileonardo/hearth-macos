from homeassistant.components.number import NumberEntity
from homeassistant.const import PERCENTAGE, UnitOfElectricCurrent

from . import CAR, CHARGER, DOMAIN, Stand


class Setting(Stand, NumberEntity):
    def __init__(self, world, device, key, name, field, lo, hi, unit):
        super().__init__(world, device, key, name)
        self._field = field
        self._attr_native_min_value = lo
        self._attr_native_max_value = hi
        self._attr_native_unit_of_measurement = unit

    @property
    def native_value(self):
        return getattr(self.world, self._field)

    async def async_set_native_value(self, value):
        setattr(self.world, self._field, value)
        self.world.changed()


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    add([
        Setting(w, CAR, "charge_limit_soc", "Charge limit", "limit", 50, 100, PERCENTAGE),
        Setting(w, CHARGER, "maximum_charging_current", "Maximum charging current", "amps", 6, 32,
                UnitOfElectricCurrent.AMPERE),
    ])

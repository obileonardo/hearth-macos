from homeassistant.components.climate import ClimateEntity, ClimateEntityFeature, HVACMode
from homeassistant.const import UnitOfTemperature

from . import CAR, DOMAIN, Stand


class Cabin(Stand, ClimateEntity):
    _attr_temperature_unit = UnitOfTemperature.CELSIUS
    _attr_current_temperature = 24.5
    _attr_target_temperature = 21

    def __init__(self, world, key, name, field, modes, on_mode):
        super().__init__(world, CAR, key, name)
        self._field = field
        self._attr_hvac_modes = modes
        self._on = on_mode
        self._attr_supported_features = (ClimateEntityFeature.TURN_ON | ClimateEntityFeature.TURN_OFF
                                         | ClimateEntityFeature.TARGET_TEMPERATURE)

    @property
    def hvac_mode(self):
        return getattr(self.world, self._field)

    async def async_set_hvac_mode(self, hvac_mode):
        setattr(self.world, self._field, hvac_mode)
        self.world.changed()

    async def async_turn_on(self):
        await self.async_set_hvac_mode(self._on)

    async def async_turn_off(self):
        await self.async_set_hvac_mode(HVACMode.OFF)

    async def async_set_temperature(self, **kwargs):
        self._attr_target_temperature = kwargs.get("temperature", self._attr_target_temperature)
        self.async_write_ha_state()


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    add([
        # Tesla Fleet has both; the overheat one sorts first by entity id.
        Cabin(w, "cabin_overheat_protection", "Cabin overheat protection", "overheat",
              [HVACMode.OFF, HVACMode.COOL, HVACMode.FAN_ONLY], HVACMode.COOL),
        Cabin(w, "driver_temp", "Climate", "climate", [HVACMode.HEAT_COOL, HVACMode.OFF], HVACMode.HEAT_COOL),
    ])

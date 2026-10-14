from homeassistant.components.lawn_mower import LawnMowerActivity, LawnMowerEntity, LawnMowerEntityFeature

from . import DOMAIN, MOWER, Stand


class Mower(Stand, LawnMowerEntity):
    _attr_supported_features = (LawnMowerEntityFeature.START_MOWING | LawnMowerEntityFeature.PAUSE
                                | LawnMowerEntityFeature.DOCK)

    @property
    def activity(self):
        return LawnMowerActivity(self.world.mower)

    async def _go(self, activity):
        self.world.mower = activity
        self.world.changed()

    async def async_start_mowing(self):
        await self._go("mowing")

    async def async_pause(self):
        await self._go("paused")

    async def async_dock(self):
        await self._go("returning")


async def async_setup_entry(hass, entry, add):
    add([Mower(hass.data[DOMAIN], MOWER, "mower", None)])

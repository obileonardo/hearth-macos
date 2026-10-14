from homeassistant.components.switch import SwitchEntity

from . import CAR, CHARGER, DOMAIN, Stand


class Toggle(Stand, SwitchEntity):
    """A switch on a world field, or (field None) one that only remembers itself."""

    def __init__(self, world, device, key, name, field, invert=False):
        super().__init__(world, device, key, name)
        self._field = field
        self._invert = invert
        self._own = False

    @property
    def is_on(self):
        v = bool(getattr(self.world, self._field)) if self._field else self._own
        return (not v) if self._invert else v

    async def async_turn_on(self, **kwargs):
        await self._set(True)

    async def async_turn_off(self, **kwargs):
        await self._set(False)

    async def _set(self, on):
        value = (not on) if self._invert else on
        if self._field:
            setattr(self.world, self._field, value)
            self.world.changed()
        else:
            self._own = value
            self.async_write_ha_state()


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    add([
        Toggle(w, CAR, "user_charge_enable_request", "Charge", "charge_requested"),
        Toggle(w, CAR, "defrost_mode", "Defrost", None),
        Toggle(w, CAR, "sentry_mode", "Sentry mode", None),
        # Wallbox's pause/resume switch is on while charging is allowed.
        Toggle(w, CHARGER, "pause_resume", "Pause/resume", "charger_paused", invert=True),
    ])

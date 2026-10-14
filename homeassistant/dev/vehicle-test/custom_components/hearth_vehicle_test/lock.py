from homeassistant.components.lock import LockEntity

from . import CAR, CHARGER, DOMAIN, Stand


class Latch(Stand, LockEntity):
    def __init__(self, world, device, key, name, field):
        super().__init__(world, device, key, name)
        self._field = field

    @property
    def is_locked(self):
        return getattr(self.world, self._field)

    async def async_lock(self, **kwargs):
        setattr(self.world, self._field, True)
        self.world.changed()

    async def async_unlock(self, **kwargs):
        setattr(self.world, self._field, False)
        self.world.changed()


class CableLatch(Stand, LockEntity):
    """Tesla's charge cable lock, which sorts before the door lock."""

    _attr_is_locked = True

    async def async_lock(self, **kwargs):
        self._attr_is_locked = True
        self.async_write_ha_state()

    async def async_unlock(self, **kwargs):
        self._attr_is_locked = False
        self.async_write_ha_state()


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    add([
        CableLatch(w, CAR, "charge_port_latch", "Charge cable lock"),
        Latch(w, CAR, "locked", "Lock", "locked"),
        Latch(w, CHARGER, "lock", "Lock", "charger_locked"),
    ])

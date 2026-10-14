from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity

from . import CAR, DOMAIN, Stand


class Flag(Stand, BinarySensorEntity):
    def __init__(self, world, device, key, name, value, device_class):
        super().__init__(world, device, key, name)
        self._value = value
        self._attr_device_class = device_class

    @property
    def is_on(self):
        return self._value(self.world)


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    add([
        Flag(w, CAR, "conn_charge_cable", "Charge cable", lambda w: w.cable, BinarySensorDeviceClass.CONNECTIVITY),
        Flag(w, CAR, "state", "Status", lambda w: True, BinarySensorDeviceClass.CONNECTIVITY),
    ])

from homeassistant.components.device_tracker import SourceType, TrackerEntity

from . import CAR, DOMAIN, Stand


class Where(Stand, TrackerEntity):
    _attr_source_type = SourceType.GPS
    _attr_location_accuracy = 10

    def __init__(self, world, key, name, at_home):
        super().__init__(world, CAR, key, name)
        self._home = at_home

    @property
    def latitude(self):
        return self.hass.config.latitude + (0 if self._home else 0.2)

    @property
    def longitude(self):
        return self.hass.config.longitude + (0 if self._home else 0.2)


async def async_setup_entry(hass, entry, add):
    w = hass.data[DOMAIN]
    add([Where(w, "location", "Location", True), Where(w, "route", "Route", False)])

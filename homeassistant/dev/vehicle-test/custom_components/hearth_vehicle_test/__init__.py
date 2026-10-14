"""Stand-in devices for testing Hearth's Vehicles page.

Three devices whose entities are named the way the real integrations name theirs, with
state that responds to the same services:
- a car shaped like Tesla Fleet (manufacturer Tesla, model Model Y)
- a charger shaped like Wallbox
- a mower shaped like Husqvarna Automower

It's a simulation, not a connection to any real vehicle.
"""

from __future__ import annotations

from datetime import timedelta

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity import Entity
from homeassistant.util import dt as dt_util

DOMAIN = "hearth_vehicle_test"
PLATFORMS = ["binary_sensor", "climate", "device_tracker", "lawn_mower", "lock", "number", "sensor", "switch"]

CAR = DeviceInfo(identifiers={(DOMAIN, "car")}, manufacturer="Tesla", model="Model Y", name="Test Model Y")
CHARGER = DeviceInfo(identifiers={(DOMAIN, "charger")}, manufacturer="Wallbox", model="PLP1-0-2-4-9-002-E",
                     name="Test Wallbox")
MOWER = DeviceInfo(identifiers={(DOMAIN, "mower")}, manufacturer="Husqvarna", model="HUSQVARNA AUTOMOWER® 450XH",
                   name="Test Automower")


class World:
    """Everything the stand-ins know, so one change shows up on every entity that depends on it."""

    def __init__(self) -> None:
        self.locked = True
        self.charge_requested = True  # Tesla's "Charge" switch
        self.cable = True
        self.climate = "off"
        self.overheat = "off"
        self.battery = 78.0
        self.limit = 90.0
        self.amps = 16
        self.charger_paused = False
        self.charger_locked = False
        self.mower = "docked"
        self.listeners: list = []

    @property
    def car_charging(self) -> str:
        """Tesla Fleet's charging state: starting, charging, stopped, complete, disconnected, no_power."""
        if not self.cable:
            return "disconnected"
        if self.battery >= self.limit:
            return "complete"
        return "charging" if self.charge_requested else "stopped"

    @property
    def charger_status(self) -> str:
        """Wallbox's status description."""
        if not self.cable:
            return "Ready"
        if self.charger_paused:
            return "Paused by user"
        return "Charging" if self.car_charging == "charging" else "Connected: waiting for car demand"

    def changed(self) -> None:
        for listener in list(self.listeners):
            listener()


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    hass.data.setdefault(DOMAIN, World())
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


class Stand(Entity):
    """An entity on one of the stand-in devices that redraws whenever the world changes."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, world: World, device: DeviceInfo, key: str, name: str | None) -> None:
        self.world = world
        self._attr_device_info = device
        self._attr_name = name
        device_key = next(iter(device["identifiers"]))[1]
        self._attr_unique_id = f"{device_key}_{key}"

    async def async_added_to_hass(self) -> None:
        @callback
        def redraw() -> None:
            self.async_write_ha_state()

        self.world.listeners.append(redraw)
        self.async_on_remove(lambda: self.world.listeners.remove(redraw))


def soon(minutes: float):
    return dt_util.utcnow() + timedelta(minutes=minutes)

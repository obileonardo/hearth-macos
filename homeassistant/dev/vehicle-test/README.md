# Vehicle test devices

A tiny Home Assistant integration that adds three stand-in devices to the demo Home Assistant, so the
Vehicles page can be tested without owning a car, a charger or a mower:

| Device | Shaped like | Entities |
|---|---|---|
| Test Model Y | Tesla Fleet (maker Tesla, model Model Y) | battery level, battery and estimated range, charging state, charger power, charge rate (km/h), energy added, time to full, charge limit, charge cable, door lock and charge cable lock, Charge, Defrost and Sentry switches, cabin Climate and Cabin overheat protection, Location and Route trackers |
| Test Wallbox | Wallbox | status description, charging power, added energy and range, the car's state of charge, lock, Pause/resume, maximum current |
| Test Automower | Husqvarna Automower | lawn mower, battery, mode |

Entity ids follow the real integrations' names (for example `sensor.test_model_y_battery_level`,
`switch.test_model_y_charge`, `sensor.test_wallbox_status_description`), and every action changes state
the way the real thing would: stopping the Charge switch turns the car's charging state to `stopped` and the
Wallbox to "Connected: waiting for car demand", and so on.

It's a simulation. It proves Hearth reads and drives these shapes of entity correctly, not that a real
Tesla, Wallbox or Automower account names everything exactly this way.

## Run it

```sh
docker-compose -f homeassistant/docker-compose.yml --profile dev up -d homeassistant-dev
docker exec homeassistant-dev mkdir -p /config/custom_components
docker cp homeassistant/dev/vehicle-test/custom_components/hearth_vehicle_test homeassistant-dev:/config/custom_components/
docker restart homeassistant-dev
```

Then in the demo Home Assistant (http://localhost:8124): **Settings, Devices & services, Add integration,
Hearth vehicle test**. Or with a token:

```sh
curl -X POST -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" \
  -d '{"handler":"hearth_vehicle_test"}' http://localhost:8124/api/config/config_entries/flow
```

Press the actions the cards use, through Hearth's own connection:

```sh
export HA_URL=http://localhost:8124 HA_TOKEN=...
build/Hearth.app/Contents/MacOS/Hearth --probe "call lock.unlock lock.test_model_y_lock; \
  call switch.turn_off switch.test_model_y_charge; call climate.turn_on climate.test_model_y_climate; \
  call lawn_mower.start_mowing lawn_mower.test_automower"
build/Hearth.app/Contents/MacOS/Hearth --window --snapshot /tmp/vehicles.png -open vehicles -snapshotHeight 1700
```

## Remove it

Delete the integration in Home Assistant, then
`docker exec homeassistant-dev rm -rf /config/custom_components/hearth_vehicle_test` and restart.

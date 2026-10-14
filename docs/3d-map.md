# The 3D map

Hearth can show your home in 3D, with every device where it really is: what each one is
using, and energy flowing from your inverter or battery to whatever is drawing power.

## What you see first

With no scan, Hearth shows a **demo house**: four rooms, some furniture, and demo devices
(an inverter, a battery, an air conditioner, a TV, a fridge and so on) whose power use is
simulated. It's labelled as a demo everywhere it appears. You can drag your real devices into
it too, and **Reset demo** puts the demo devices back where they started.

## Scanning your home

Hearth reads the files that LiDAR scanning apps on iPhone and iPad make. You need an iPhone
or iPad with a LiDAR sensor (Pro models since 2020).

1. Scan each room with an app that uses Apple's **RoomPlan** or exports **USDZ**. For example:
   Polycam, 3D Scanner App, or any RoomPlan-based scanner. RoomPlan scans give the cleanest
   result, because they come out as walls, doors, windows and furniture rather than a raw mesh.
2. Export the scan as **USDZ** (OBJ also works).
3. AirDrop it to your Mac.
4. In Hearth, open the 3D map and choose **Import a scan**.

Hearth copies the scan to `~/Library/Application Support/Hearth/maps/` and shows it in its
own clay style. **Textures** switches back to the scan's own colours, and **Walls cut** slices
every wall at waist height so you can look into the rooms from above.

### What isn't there yet

- **A Hearth app for iPhone.** Scanning straight into Hearth, live, needs an iPhone app built
  with Xcode on RoomPlan. That's a later step. Until then, any scanner app that exports USDZ
  does the job, with one AirDrop in between.
- **Multi-room merging.** If your scanner exports rooms separately, import the one that
  matters most, or combine them in the scanner first (RoomPlan can capture several rooms
  into one structure).

## Placing devices

Open the full map (**Open full map** in the panel). Every device from Home Assistant, plus
gadgets you've added by hand, is listed on the left. Drag one onto the floor or a wall and it's
pinned there. Click a pin to see what it's doing, use its main control, or take it off the
map. Pins are saved per map, next to the scan, in a `.pins.json` file.

## Energy on the map

- A device with a **power sensor** in Home Assistant glows in proportion to what it's using,
  and the full map labels it with the reading (for example "TV · 92 W").
- Place your **inverter** or **battery**, and energy flows from it to every device using
  power: a channel along the floor with motes moving down it, more and faster for bigger loads.
- Devices without a power sensor still show where they are; they just don't glow.
  Smart plugs with energy monitoring are the easiest way to add readings to anything.

## How it's built

- `Sources/Hearth/HomeMap.swift`: pins, the map store, power readings and the demo house.
- `Sources/Hearth/MapScene.swift`: the SceneKit scene, pins, flows and the view.
- `Sources/Hearth/Views/MapViews.swift`: the panel page and the full map window.

SceneKit is used because it runs on macOS 14 and loads USDZ directly. The panel preview runs at
30 frames a second without shadows; the full window adds shadows, ambient occlusion and bloom.
Both pause when they're not on screen.

For development: `--map-window` opens the full map on its own, `--map-panel` shows the panel's
map page, and `-mapFile <path>` shows a scan without importing it.

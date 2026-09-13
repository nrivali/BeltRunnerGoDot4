# Belt Runner — Godot 4 port

The browser game (`C:\Users\rival\Documents\BeltRunner\belt-runner-3d.html`, repo `nrivali/BeltRunner`) is being moved
to Godot 4. This is the Godot project (repo `nrivali/BeltRunnerGoDot4`), kept separate so the browser game is never
touched by the port. Open it with Godot 4.3 or newer (Project Manager → Import → pick `project.godot`) and press F5.

## Status

Runs on Godot 4.7.2. `godot --path . -- --smoke` is the unattended check through the whole loop: it starts docked,
launches, parks the ship at the nearest copper rock and cuts it through, flies back and asks approach control for a
docking, deposits the hold into the cargo ship's storage, departs again and quits, printing what happened at each stage
and saving screenshots (`smoke_launch`, `smoke_taxi`, `smoke_mine`, `smoke_approach`, `smoke_dock`, `smoke_pad`) under
`user://` (`%APPDATA%\Godot\app_userdata\Belt Runner\`). Run it after any change to the belt, ship, carrier or HUD.

## Milestone 2 — the cargo ship and docking

| Piece | Where | Status |
|---|---|---|
| The carrier: hull collision box, prow cone, through-hangar corridor, two bays with pads and mouths, orbit round the planet | `scripts/cargo_ship.gd` | ported from DEPOT / STATION / placeDepot / depotCollide; placeholder hull of boxes and cylinders |
| Hangar capture (fly slowly into a mouth) and hull collision with a knock costing plating | `scripts/ship.gd` | ported |
| Approach control (E within 2,250 m): in by the nearer mouth, along the deck, hover over the far pad, settle | `scripts/ship.gd` | ported, with letterbox bars and a camera by the mouth |
| The pad: refuel from the cargo ship's supply, repair from its parts, W departs after release, E deposits | `scripts/ship.gd` | ported |
| Departure taxi off the pad and out of the mouth, handed over under way, watched from the chase camera | `scripts/ship.gd` | ported |
| Cargo ship storage (50 slots), deposit all / take all, values at Hub prices | `scripts/game_state.gd` | ported |
| Services panel: storage, fuel supply and parts gauges, the hold, refit rows with buy buttons, Depart | `scripts/hud.gd` | rebuilt with Control nodes (no drag-and-drop inventory grid yet) |
| Cargo ship marker on the HUD, distance in the readout | `scripts/hud.gd` | rebuilt |
| Every start is on the pad in the dock that faces the planet | `scripts/main.gd` | ported |

Not in this milestone: the Blender carrier model, the dish turret and cargo ship upgrades (mining laser, collector
drones), the hangar's force fields and bay signs, the cinematic approach shot from the HTML's camera module (a fixed
camera by the mouth stands in), and the drag-and-drop inventory grid.

## Milestone 1 — one belt, flight, mining, HUD

| Piece | Where | Status |
|---|---|---|
| Static data: ores, refits, the Kessler zone and its belts | `scripts/data.gd` | ported one for one from the HTML constants |
| Pilot state, refit levels, hold, save/load | `scripts/game_state.gd` | ported; JSON save under `user://` with the browser's field names |
| Belt generation: base belts, ring belt, ore fields, rich pockets, size mix, barren share | `scripts/belt.gd` | ported, deterministic from a seed |
| Rock rendering | `scripts/belt.gd` | one MultiMesh per 50 km chunk, colour per ore, chunks culled by distance |
| Flight model: throttle, mouse steering, roll, drag, gravity, speed cap, afterburner, fuel | `scripts/ship.gd` | ported |
| Mining laser: nose-ray targeting, ore unlock by laser level, overcharge, break, pickups | `scripts/ship.gd`, `scripts/pickup.gd` | ported |
| Chase camera | `scripts/ship.gd` | ported |
| HUD: hull, fuel, throttle, cargo, speed, laser, radar, target panel, toasts | `scripts/hud.gd` | rebuilt with Control nodes |
| Floating origin so a 2,800 km zone stays precise in single-precision floats | `scripts/main.gd` | new (the browser relied on JS doubles) |

Not yet: the Hub and colony, traffic, drones, warp, the tutorial and voice lines, audio, rock shapes and textures
(rocks are faceted spheres for now), rocks drifting on their orbit rails, raiders, the nav map, the inventory grid.
The game logic for those exists in the HTML and ports the same way.

## Conventions

- Units are the HTML's world units; a readout metre is half a unit (`Data.METRE`), exactly as the browser game shows it.
- Rock data lives in packed arrays on `Belt`, never in nodes: 54,000 rocks as nodes would be far too slow.
- Everything that moves is positioned relative to the floating origin: `Main.world_offset` plus a node's `position`
  is its true world position. Rock positions in `Belt` are stored true and converted when drawn or queried.
- Multiplayer later: the belt is generated from a seed, so only changes (broken rocks, pickups, ships) will need replicating.

## Controls (same as the browser)

Mouse steers (cursor off centre yaws and pitches) · W / S throttle · X cut · A / D roll · Shift afterburner (needs the
refit) · LMB / Space / L mining laser · G laser overcharge (needs the refit) · R radar pulse · E within 2,250 m of the
cargo ship: approach control docks you (or fly slowly into either hangar mouth) · on the pad: E deposits the hold, W
departs · Space skips an approach · F5 quick-save · Esc quit.

# Belt Runner — Godot 4 port

The browser game (`C:\Users\rival\Documents\BeltRunner\belt-runner-3d.html`, repo `nrivali/BeltRunner`) is being moved
to Godot 4. This is the Godot project (repo `nrivali/BeltRunnerGoDot4`), kept separate so the browser game is never
touched by the port. Open it with Godot 4.3 or newer (Project Manager → Import → pick `project.godot`) and press F5.

## Milestone 1 — one belt, flight, mining, HUD (this commit)

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

Not yet: the cargo ship and hangar, docking, the Hub and colony, traffic, drones, warp, the tutorial and voice lines,
audio, rock shapes and textures (rocks are faceted spheres for now), rocks drifting on their orbit rails, raiders, the
nav map, the services panel and inventory UI. The game logic for those exists in the HTML and ports the same way.

## Conventions

- Units are the HTML's world units; a readout metre is half a unit (`Data.METRE`), exactly as the browser game shows it.
- Rock data lives in packed arrays on `Belt`, never in nodes: 54,000 rocks as nodes would be far too slow.
- Everything that moves is positioned relative to the floating origin: `Main.world_offset` plus a node's `position`
  is its true world position. Rock positions in `Belt` are stored true and converted when drawn or queried.
- Multiplayer later: the belt is generated from a seed, so only changes (broken rocks, pickups, ships) will need replicating.

## Controls (same as the browser)

Mouse steers (cursor off centre yaws and pitches) · W / S throttle · X cut · A / D roll · Shift afterburner (needs the
refit) · LMB / Space / L mining laser · G laser overcharge (needs the refit) · R radar pulse · F5 quick-save · Esc quit.

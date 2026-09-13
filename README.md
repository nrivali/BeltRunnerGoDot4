# Belt Runner — Godot 4 port

The browser game (`C:\Users\rival\Documents\BeltRunner\belt-runner-3d.html`, repo `nrivali/BeltRunner`) is being moved
to Godot 4. This is the Godot project (repo `nrivali/BeltRunnerGoDot4`), kept separate so the browser game is never
touched by the port. Open it with Godot 4.3 or newer (Project Manager → Import → pick `project.godot`) and press F5.

## Status

Runs on Godot 4.7.2. `godot --path . -- --smoke` is the unattended check through the whole loop: it starts docked,
launches, parks the ship at the nearest copper rock and cuts it through, flies back and asks approach control for a
docking, deposits the hold, departs, docks again, jumps to the Hub, arrives on station, sells everything, refuels and
restocks, jumps home onto the pad and quits, printing what happened at each stage and saving eleven screenshots
(`smoke_launch` … `smoke_home`) under `user://` (`%APPDATA%\Godot\app_userdata\Belt Runner\`). Run it after any change.

## Milestone 5 — the tutorial and the voice lines

| Piece | Where | Status |
|---|---|---|
| Flight Ops questline: 14 steps, each waiting for the real action or for Next (Enter), with Skip and Replay | `scripts/tutorial.gd` | ported from TUT; the lock step waits for a copper rock under the nose (no Q lock yet) |
| The card top-left and pulsing rings round the HUD piece each step talks about | `scripts/hud.gd` | rebuilt |
| Recorded voice lines: the tutorial's 14, five approach calls, colony control, warp ready | `scripts/audio.gd`, `sfx/*.mp3` | ported; radio squelch open and close round every line, one voice at a time |
| Hangar deck announcements over the intercom (band-pass, overdrive, big-room reverb, PA chime) | `scripts/audio.gd` | ported to an audio bus with Godot's own effects |
| One-shot effects: dock, chime, cash, stow, pickup, rock break, radar ping, laser on / bite / off | `scripts/audio.gd` | wired |
| Continuous loops: engine idle, thrust (pitch rises with the throttle), boost, retro hiss, laser beam and cut, the space hum | `scripts/audio.gd` | ported with the browser's gains and fade times; each loop faded toward its target every frame |
| Flight controls list bottom-left (C hides it), inventory panel (Tab / I) | `scripts/hud.gd` | rebuilt (a list, not the drag-and-drop grid) |
| Tutorial progress saved (`tut`, -1 once done); a new game starts on step 1 | `scripts/game_state.gd` | ported |

## Milestone 4 — Astra's Blender models

The GLB files under `assets/` are copies of the ones the browser game loads (from the BeltRunner repo's `assets/`
folder; Godot imports GLB natively, so no conversion). Each has a placeholder fallback if it is missing.

| Model | File | How it is used |
|---|---|---|
| Asteroid library: 14 shape families × A/B × LOD 1 and 2 | `assets/rocks/asteroids_lod1.glb`, `asteroids_lod2.glb` | one MultiMesh per (250 km chunk, shape); the ore-vein surface takes the instance colour; LOD 1 within 70 km |
| Cargo carrier (v3, with the dish rig) | `assets/carrier/cargo_carrier.glb` | the hull; pads, mouths, engines, dish mount and drone docks read from its named markers |
| Player ship (delta wings, level-1 fittings) | `assets/ship/player_ship.glb` | turned to face -Z and scaled ×3 as the browser's ship group is |
| Ferron terrain | `assets/planets/ferron.glb` | unit sphere scaled to the planet's radius |
| Meridian oceans, continents and cloud layer | `assets/planets/homeworld.glb` | the same, at the Hub |
| Garden habitat colony | `assets/colony/garden_habitat.glb` | Meridian Colony at ×1000; its Habitat_Rings turn |

Not yet: LOD 0 up close, the ship's wing and fitting variants and paint accent, the carrier's dish turret animation and
hull-profile collision (the box collision stays), Astra's lighting module, and the hyperspace effect.

## Milestone 3 — the Hub and selling

| Piece | Where | Status |
|---|---|---|
| Two charted zones (Kessler Belt, The Hub), zone data, chart distances | `scripts/data.gd` | ported |
| Zone loading: belt rebuilt from its seed, planet, colony, sun and sky per zone | `scripts/main.gd` | new |
| Meridian Colony: two habitat rings with modules, spokes, hub sphere, core, pads, dish, solar wings, cargo terminals, beacons | `scripts/colony.gd` | simplified port of buildColonyAt (plain meshes, no merged detail) |
| The homeworld hanging below the colony lanes | `scripts/main.gd` | a blue sphere for now |
| Holding station: the carrier parked off the colony, drifting gently, the ship aboard | `scripts/ship.gd`, `scripts/cargo_ship.gd` | ported |
| The arrival: the carrier flies in from deep space and eases onto station, camera riding behind it | `scripts/ship.gd` | ported (chase shot instead of the HTML's orbiting camera) |
| The jump: exterior shot, fade to black while the zone swaps, arrival; Space skips | `scripts/ship.gd` | new (the HTML's hyperspace tunnel is not ported) |
| The nav map (N): both zones with distance, tag, market or exclusive ores, and the Warp button | `scripts/hud.gd` | rebuilt as a panel (no chart drawing yet) |
| The market: drifting prices, exotics premium, sell everything / hold / storage, today's prices | `scripts/game_state.gd`, `scripts/hud.gd` | ported |
| Refuel the cargo ship's supply and restock its repair parts for credits | `scripts/game_state.gd` | ported |
| Zone remembered in the save | `scripts/game_state.gd` | ported |

Not in this milestone: the colony's traffic (72 ships), the Hub's voice lines, the hyperspace tunnel, the drawn chart,
and the homeworld's continents, clouds and night lights.

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

Not yet: traffic, drones and the dish turret, rocks drifting on their orbit rails, rock fragments, raiders, the tow, the
Q lock, the drag-and-drop inventory grid, a menu and settings (sound volume). The game logic for those exists in the
HTML and ports the same way. The browser's ambience beats were removed from the game by the user, so there are none.

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

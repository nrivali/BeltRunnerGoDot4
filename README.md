# Belt Runner — Godot 4 port

The browser game (`C:\Users\rival\Documents\BeltRunner\belt-runner-3d.html`, repo `nrivali/BeltRunner`) is being moved
to Godot 4. This is the Godot project (repo `nrivali/BeltRunnerGoDot4`), kept separate so the browser game is never
touched by the port. Open it with Godot 4.3 or newer (Project Manager → Import → pick `project.godot`) and press F5.

## Status

Runs on Godot 4.7.2. `godot --path . -- --smoke` is the unattended check through the whole loop: it starts docked,
launches, parks the ship at the nearest copper rock and cuts it through, flies back and asks approach control for a
docking, deposits the hold, departs, docks again, jumps to the Hub, arrives on station, sells everything, refuels and
restocks, jumps home onto the pad and quits, printing what happened at each stage and saving fifteen screenshots
(`smoke_launch` … `smoke_home`, plus the inventory, the nav map and the menu pages) under `user://`
(`%APPDATA%\Godot\app_userdata\Belt Runner\`). Run it after any change.

## Milestone 17 — the soundtrack

| Piece | Where | Status |
|---|---|---|
| The procedural music engine: eight tracks (Drift, Halcyon, Aurum, Frost, Sable, Cinder, Meridian, Umbra), each a pad colour of five chord voices through a slowly breathing lowpass, a sub, a tempo-locked echo, ambient layers (sparkle, wind, a wandering melody, a pulse, a choir swell) and a groove (kick, snare or clap, rim, hats, shaker, bass, arp, chord stabs, a lead). Ambient for two or three minutes, the groove for a minute or so, then on to the next track | `scripts/music.gd` (autoload `Music`) | ported from MUSIC_PROC: every recipe, pattern, envelope and gain copied; rendered sample by sample on its own thread into an `AudioStreamGenerator` (the pads resampled from loops rendered once per recipe, the noise hits rendered once per recipe) |
| The comm-channel toasts: "♪ Now drifting: …" when a track starts, "… · groove on the comm channel" when the groove comes in | `scripts/main.gd` | ported |
| Settings: Music on/off and a Music volume, separate from the sound-effects volume, saved with the game | `scripts/menu.gd`, `scripts/game_state.gd` | ported from the browser's sliders |

## Milestone 16 — the beam's heat, scorches, and the fitting variants

| Piece | Where | Status |
|---|---|---|
| The beam's spot heat: 30 s on a rock to white heat, cooling over 10 s once off it, half left behind on a change of rock; the stone's surface glow widens with it, a glowing spot and a light sit where the beam lands, and a shower of sparks streams off the surface, more and hotter as it heats | `scripts/ship.gd` (`_tick_spot`), `scripts/sparks.gd` (`emit`) | ported from heatFx / SPARKS.emit |
| The burn trail: once the spot is hot, a scorch decal is stamped where the beam is every 0.1 s, laid on the surface facing the rock's centre, up to 64 a rock, gone when the rock breaks | `scripts/belt.gd` (`scorch`) | ported from addBurn as Godot Decals on a per-rock holder |
| The ship's fitting variants: three tiers of laser barrel, cargo pod, engine nacelle and scanner dish, shown by refit level (tier = 1 + round(2 · level / top level)); they live in the model's second glTF scene, which the scene importer leaves out, so they are read from the glTF document at run time | `scripts/ship.gd` (`_load_variants`, `configure_model`) | ported from the assembler's configure() |

Not ported: the wing choices and hull/accent paint (the browser's customisation, which the port has no menu for; the
delta wings stay).

## Milestone 15 — the curved hull, the radar pulse, exhaust and navigation lights

| Piece | Where | Status |
|---|---|---|
| The cargo ship's curved pressure hull as the collision surface outside the passage: the profile exported with the model (18 stations of a superellipse cross-section and three engine envelopes) read from the glTF extras, the nearest surface point and normal found as hull-contact.js does; the box rules stay inside the bay | `scripts/cargo_ship.gd` (`hull_contact`) | ported from hull-contact.js rawContact |
| The radar pulse you can see: a faint sphere and a bright ring growing to scanner range over 2.6 s, and rocks marked only once the pulse reaches them | `scripts/ship.gd` (`_tick_pulse`), `scripts/belt.gd` (`mark_from`) | ported from pulseSphere / pulseRing |
| The engines' exhaust glows swell and brighten with thrust (wide open on the afterburner), the red and green navigation lights blink, the engine light comes on under thrust | `scripts/ship.gd` (`_tick_engine_fx`) | ported from the exhaust sprites, navLights and shipLight |

## Milestone 14 — fields, markers, the dish's effects, force fields, rock-on-rock

| Piece | Where | Status |
|---|---|---|
| The charted fields carry names (K1-A…, rich pockets KP-1…) and ride their rails; the FIELD readout names the one you are in; a marker points to the nearest field's edge while you are outside one | `scripts/belt.gd` (`field_at`, `nearest_field`), `scripts/hud.gd` | ported |
| A cyan marker on every collector drone with what it is doing, its load and its range; the cargo ship marker names the near dock within 4,500 m | `scripts/hud.gd` | ported from droneMarker / placeMarker |
| The ship's mining dish swings onto the beam's target (a few radians a second, forward half only) and settles forward when idle; its six rim emitters glow faintly, pulse while it slews onto a rock and flicker hard while it fires; six rim beams converge on the focus while the beam cuts; the beam starts at the focus | `scripts/ship.gd` (`_tick_dish`, `_build_dish_fx`) | ported from shipDishAnglesTo / animateDish, driving the model's own yaw and pitch rig |
| The cargo ship dish's beam gets its soft sheath and a glow where it lands, flickering | `scripts/cargo_ship.gd` | ported |
| Force fields across both hangar mouths: a shimmering drifting grid that flashes whenever the ship or a drone passes through | `scripts/cargo_ship.gd` (`_build_force_fields`, `flash_field`) | ported |
| Rock-on-rock contact for rocks that are adrift: overlap pushes both out, mass-weighted, with a soft bounce, knocking the other off its rail; scrap chunks bounce off one another through a coarse spatial hash | `scripts/belt.gd` (`_tick_pairs`, `_tick_scrap`) | ported from rockPair / collideDebris |

## Milestone 13 — collisions, sparks, scrap, heat, LOD 0, free look

| Piece | Where | Status |
|---|---|---|
| Ship–rock collision: the frame's path is swept in 24-unit steps against the rocks within reach (refreshed twice a second), resolved against a slightly generous sphere; a knock above 140 u/s costs plating (0.09 a unit over), shakes the camera, flashes, sparks and sounds; hull critical warning; plating gone → the tug | `scripts/ship.gd` (`_rock_contact`, `_impact`) | ported from the rock sweep and impact() (a sphere stands in for the browser's exact mesh surface) |
| bumpRock: a hit knocks the rock off its rail, small rocks taking the whole hit and big ones barely noticing, never faster than the ship hit it | `scripts/belt.gd` (`bump`) | ported |
| Sparks: a burst of glowing streaks on a rock break or a hull hit, each stretched along its own velocity and thinning as it dies | `scripts/sparks.gd` | ported from SPARKS (one MultiMesh of boxes) |
| Scrap: 5 to 16 small hot chunks off a breaking rock (4 to 12 % of its radius), coasting and spinning, cooling from white-hot over 30 s, bouncing off nearby rocks and the ship (which they shove), fading out after half an hour | `scripts/belt.gd` (`spawn_scrap`, `_tick_scrap`) | ported from spawnDebris / chunkRock |
| Heat: a damaged rock glows red, then orange, then near-white as its health goes (pulsing slightly); fresh fragments start hot and cool over 30 s; the laser's spot glows where the ship's beam or the dish's is cooking the stone | `scripts/belt.gd` (rock shader, `_write_custom`, `set_spot_heat`) | ported from heatable() / setRockHeat; the body heat rides in the instance custom data |
| LOD 0 up close: a rock nearer than six of its radii leaves its chunk's batch for its own node with Astra's finest mesh (back at eight); free rocks swap their node's mesh | `scripts/belt.gd` (`update_lod0`), `assets/rocks/asteroids_lod0.glb` | ported (the browser picks by projected size, 100 px) |
| Free look: hold the right mouse button to swing the camera without turning the ship; it eases back on release | `scripts/ship.gd` | ported |

Not ported: the ship's wing and fitting variants (they live in the GLB's second scene, which Godot's importer does
not bring in), the scorch decals the beam leaves on rocks, scrap-on-scrap bounces. The smoke run reports sparks,
scrap, LOD 0 rocks and the near-rock count at the cut.

## Milestone 12 — the Q lock and the tow tug

| Piece | Where | Status |
|---|---|---|
| Hover pick: every live rock within 120 km of the camera and the cargo ship are projected to the screen; the nearest whose disc (10 px minimum) holds the cursor is the hover, shown as a label beside the cursor with its range from the nose | `scripts/ship.gd` (`hover_pick`), `scripts/hud.gd` | ported from hoverPick / .hoverLbl (the pick runs at 10 Hz for the label, and afresh on Q) |
| Q: lock the hovered target, switch to a different hovered target, or release; the lock holds out to 50,000 m and lapses when the rock breaks up or falls out of range | `scripts/ship.gd` (`toggle_lock`, `_tick_lock`) | ported |
| Lock steering: the ship turns itself to put the locked object on the nose ray (proportional, full rate beyond about seven degrees off); the mouse is ignored, roll stays yours; the laser still only cuts what the crosshair is on | `scripts/ship.gd` (`_fly`) | ported |
| HUD: the target pane follows the lock (LOCKED TARGET; the cargo ship as a carrier with no health bar), the RANGE readout shows the lock's distance against the beam's reach, heavier reticle corners when the crosshair is on the lock, Q hints in the hint bar | `scripts/hud.gd` | ported |
| The tow tug: T with a dry tank calls it (a hull breach calls it by itself and disables the ship: no thrust, no steering, it drifts); the tug sets out from just off the nearer mouth, kills the drift and swings to the cargo ship's side while the beam locks, hauls the ship nose-first to the mouth and down the deck past the pad, where the bay's own capture docks it; then it carries on out of the far mouth and away | `scripts/ship.gd` (`request_tow`, `_tow_update`) | ported from requestTow / towUpdate with the browser's speeds and holds |
| Tow delivered: 15% of credits as the fee, a breached hull patched to 35%, an empty tank topped to 30% | `scripts/ship.gd` (`enter_hangar`) | ported |
| The tug model (body, lit cab, twin engines, clamps, emitter, amber strobe and light) and the tractor beam; the hint bar's tug status; the breach flash and sounds | `scripts/ship.gd`, `scripts/hud.gd` | rebuilt |
| Tutorial lock step: press Q on a copper rock, as the browser's | `scripts/tutorial.gd` | ported |

Not ported: the free look while towed or disabled (the browser lets the mouse swing the camera then; the port has no
free look yet). The smoke run locks the tutorial rock with Q, runs dry off the mouth, calls the tug and prints each
phase through to the fee.

## Milestone 11 — rocks on their rails, and fragments

| Piece | Where | Status |
|---|---|---|
| Every rock rides its orbit rail at 28 u/s, counter-clockwise seen from above (field rocks ride their field's rail, keeping their offset from its centre); the drift is applied on the GPU by the rock shader from per-instance rail data, so 54,000 moving rocks cost nothing per frame; gameplay reads positions analytically (`rock_pos`, `rock_vel`) | `scripts/belt.gd` | ported from the HTML's a.ang / a.orbit and orbitalVel |
| Astra's rock materials as one shader with the same maps and factors (albedo, roughness and metallic channels, normal map, emission), the ore veins still taking the instance colour | `scripts/belt.gd` (`ROCK_SHADER`, `_convert_material`) | rebuilt |
| Free rocks: knocked off the rail they coast in a straight line, bounce off the zone edge and come to rest on the planet, as their own one-instance nodes | `scripts/belt.gd` (`set_free`, `tick`) | ported |
| Fragments: colossal → giants → large → small; three to five pieces of the next class down, about half carrying three quarters of the parent's ore, the rest plain stone; a quarter of the ore comes loose at once; pieces start well apart with a shove; a broken fragment is gone for good | `scripts/main.gd` (`_split_rock`), `scripts/belt.gd` (`add_fragment`) | ported from splitRock / breakRock |
| Loose ore lumps drift with the rock's orbital velocity | `scripts/main.gd` | ported |
| A broken belt rock grows back after five minutes, in its own chunk, back on a rail, health and ore restored | `scripts/belt.gd` (`_respawn`) | ported (placed in the same chunk so its MultiMesh keeps drawing it correctly) |

Not ported with this: the residual heat glow on fresh fragments, the scrap debris and sparks, and rock-on-rock
collision (the browser only tests pairs once something is adrift; nothing in the port knocks rocks adrift yet).
The smoke run watches a rail rock drift, breaks a large copper rock and lists its fragments.

## Milestone 10 — the hyperspace jump

| Piece | Where | Status |
|---|---|---|
| The timeline: charge 1.6 s, launch 0.45 s, transit 2.45 s, arrival 1.15 s, settle 0.6 s (6.25 s in all), and the pose it gives each frame: the carrier's forward offset and stretch, engine gain, tunnel coverage and flash, star trails and their length, camera field of view | `scripts/hyperspace.gd` | ported from `assets/hyperspace/hyperspace.js` sample() |
| The tunnel: a full-screen canvas shader (noise clouds and filaments twisting down a depth field, a haze at the centre, the flash at launch and arrival) | `scripts/hyperspace.gd` | ported shader for shader |
| The star ribbons: 640 rays streaming from a point far down the carrier's nose, each a thin quad with a bright head and a blue tail, additive | `scripts/hyperspace.gd` (`Streaks`) | ported (drawn from a Control each frame instead of a vertex shader) |
| The carrier pushed forward and stretched from the engines, its engine glows gaining; render only, the pad and the orbit unmoved | `scripts/cargo_ship.gd` | ported (the model node carries the pose) |
| The exterior shot behind the carrier as it charges and jumps, ahead of it as it arrives, with the field of view following the pose; the zone swaps under the opaque tunnel; the covered edit into the hangar at the end of a belt arrival | `scripts/ship.gd` | ported (replaces the fade-to-black jump) |
| Sounds: the charge, the warp-ready call, the jump | `scripts/ship.gd`, `scripts/audio.gd` | wired |

The smoke run captures the launch, the tunnel and the arrival snap.

## Milestone 9 — the HUD and the menus

The browser HUD's stylesheet, rebuilt in Godot: `scripts/ui.gd` holds the palette, the three type families the browser
loads from Google Fonts (Chakra Petch, IBM Plex Sans, IBM Plex Mono, bundled under `assets/fonts`, Open Font Licence)
and the custom controls; `scripts/hud.gd` is the layout; `scripts/menu.gd` is the start and pause menu.

| Piece | Where | Status |
|---|---|---|
| Chamfered glass panes with cyan corner brackets, segmented glowing gauges, amber chamfered buttons, key chips, glowing mono readings | `scripts/ui.gd` | rebuilt from the CSS (.pane, .bar, .btn, kbd) |
| Status pane bottom-centre (hull, fuel, big speed, thrust, cargo), readouts top-right (zone, speed, cargo ship, field; laser, range, radar), target pane top-centre (name, size, range, health, warning) | `scripts/hud.gd` | rebuilt to the browser's layout |
| Boresight brackets on the rock under the nose (amber while cutting), the cargo ship's diamond marker with an edge arrow when off screen, radar blips in the ore's colour with name-and-range labels for the nearest four | `scripts/hud.gd`, `scripts/belt.gd` | ported (rocks now carry a radar mark for 25 s) |
| The hint bar above the status pane (approach control, auto-dock, hold to mine, cutting…), the cargo-full notice, toasts with an amber or red edge, the vignette, the red flash on a hull knock, the version tag | `scripts/hud.gd` | ported |
| Flight controls list bottom-left with key chips (C hides it, remembered in the save) | `scripts/hud.gd` | rebuilt |
| Cargo ship services: a glass side panel on the right with balance, gauges, the market table at the Hub, the hold, refit rows with level pips and price buttons, Depart / Warp to the Hub / Hide (F) and Reset save | `scripts/hud.gd` | rebuilt to #station |
| Inventory: a glass side panel on the left with credits, the hold's slot grid (ore colour along the top, ✕ jettisons) and the storage grid while docked | `scripts/hud.gd`, `scripts/game_state.gd` | rebuilt to #inv |
| Drag and drop: a hold stack dragged onto the storage grid is stowed, a storage stack dragged onto the hold grid comes back aboard, a hold stack let go anywhere else is jettisoned (it drifts off behind the ship and cannot be scooped up for a minute); a double-click moves a stack across too; the slots that would take the stack light up amber | `scripts/hud.gd` (`Hud.Slot`), `scripts/pickup.gd` | ported from wireInventoryDrag / stowStack / takeStack / jettisonSlot with Godot's own drag-and-drop (`_get_drag_data`, `_can_drop_data`, `_drop_data`, `NOTIFICATION_DRAG_END`) |
| Nav computer: the chart drawn as the browser's SVG (grid, dashed lanes with distances, zone nodes), the picked zone's details and the warp button | `scripts/hud.gd` (`Ui.Chart`) | rebuilt |
| Start menu at launch, pause menu on Escape: Continue / Resume, New game (click twice to wipe), Controls, Settings (sound, volume, music, music volume, HUD size, tutorial restart, wipe save), Quit | `scripts/menu.gd`, `scripts/main.gd` | rebuilt to #intro; settings saved with the game |

The smoke run now also captures the inventory, the nav map and the three menu pages (fifteen screenshots), and
drives the drag and drop the way the viewport would (storage to hold, hold to storage, a stack let go outside).

The hold grid is always sorted most valuable first with full stacks before part stacks, exactly as the browser re-sorts
its slot order on every read, so dragging a hold stack onto another hold slot needs no bookkeeping: the pour or swap the
browser does is undone by that sort a moment later in both games.

## Milestone 8 — lighting

| Piece | Where | Status |
|---|---|---|
| The sun per zone (colour, strength, disc size, exposure), ACES tone mapping at the browser's exposure, glow for the emissives and the sun | `scripts/lighting.gd` | ported from Astra's `space-lighting.js` profiles |
| Sky: nebula, dust band, stars and a sun disc with an optical glare, all in one sky shader; the sky lights the hulls' reflections, with a gentler disc in the reflection map so the metal ore veins do not mirror it as white blobs | `scripts/lighting.gd` | rebuilt (the browser paints a texture; here it is a shader, so it costs nothing to build) |
| Soft directional shadows focused round the ship, faint fill matching the browser's hemisphere bounce and ambient | `scripts/lighting.gd` | ported |
| The flashlight: the browser's torch under the nose, on by default, F toggles it in flight | `scripts/ship.gd` | ported (SpotLight 14000 cd / π, reach 7000, half-angle 22.5°, 1/d falloff) |
| The warm hangar lamps at the browser's strength (2600 cd / π, 1/d^1.25) | `scripts/cargo_ship.gd` | fixed: they were there at a thousandth of the strength |

Light energies follow one rule: Godot's Lambert has no 1/π and its omni/spot attenuation exponent is the same falloff
as three.js's `decay`, so a browser light of intensity I becomes energy I / π with the same decay, colour and range.
`tools/inspect_mats.gd` (run with `--script`) prints every model material's albedo, metallic, roughness and maps.

## Milestone 7 — the dish turret and the collector drones

| Piece | Where | Status |
|---|---|---|
| Cargo ship upgrades in the services panel: the mast mining laser (three levels) and collector drones (three levels) | `scripts/data.gd`, `scripts/game_state.gd`, `scripts/hud.gd` | ported |
| The dish: retargets every 0.6 s onto the nearest ore rock its level can open, in arc and clear of the hull; slews yaw and pitch at 0.45 rad/s; fires within a degree or so; breaks rocks and leaves the ore adrift | `scripts/cargo_ship.gd` | ported from updateDepot, driving the carrier model's own dish_yaw / dish_pitch / focus rig |
| Collector drones: dock off mouth 1, claim the nearest loose lump in range, gather to capacity, fly home in through the nearest mouth, down the lane to the drop-off pad, unload into storage, out the far mouth | `scripts/drones.gd` | ported from updateCollectors, with the same steering, speeds and waits |
| Rock breaks shared between the ship's laser and the dish; the dish's breaks are only announced every 20 s | `scripts/main.gd` | ported |

Not in this milestone: the dish's rim-emitter glow and converging beams, the hangar force fields flashing as a drone
passes, and the drone HUD markers.

## Milestone 6 — traffic at the Hub

| Piece | Where | Status |
|---|---|---|
| 72 ships of nine kinds (shuttles, couriers, tugs, tankers, miners, freighters, haulers, liners, patrols) plus eight cargo carriers, in the HTML's proportions | `scripts/traffic.gd` | ported; plain meshes with engine glows and navigation lights |
| 22 landing slots: six round each core pad, four on each terminal roof, the two berths | `scripts/traffic.gd` | ported |
| Flight plans: arrivals to pads, roofs and berths, lift-offs, hold loops when the berths are full, passes by the rings, patrol laps; per-kind speeds and waits | `scripts/traffic.gd` | ported from trafficPlan / updateTraffic |
| Half the landers and half the big ships already parked on arrival, the rest scattered along a first leg | `scripts/traffic.gd` | ported |

Not in this milestone: the HTML's merged static geometry for the ships (each ship is a handful of meshes) and
collision between traffic and the player, which the browser does not have either.

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
hull-profile collision (the box collision stays), and the hyperspace effect (lighting came in milestone 8).

## Milestone 3 — the Hub and selling

| Piece | Where | Status |
|---|---|---|
| Two charted zones (Kessler Belt, The Hub), zone data, chart distances | `scripts/data.gd` | ported |
| Zone loading: belt rebuilt from its seed, planet, colony, sun and sky per zone | `scripts/main.gd` | new |
| Meridian Colony: two habitat rings with modules, spokes, hub sphere, core, pads, dish, solar wings, cargo terminals, beacons | `scripts/colony.gd` | simplified port of buildColonyAt (plain meshes, no merged detail) |
| The homeworld hanging below the colony lanes | `scripts/main.gd` | a blue sphere for now |
| Holding station: the carrier parked off the colony, drifting gently, the ship aboard | `scripts/ship.gd`, `scripts/cargo_ship.gd` | ported |
| The arrival: the carrier flies in from deep space and eases onto station, camera riding behind it | `scripts/ship.gd` | ported (chase shot instead of the HTML's orbiting camera) |
| The jump: exterior shot, the hyperspace tunnel while the zone swaps, arrival; Space skips | `scripts/ship.gd` | ported (milestone 10) |
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

Every gameplay system of the browser game is now ported (the tow and the Q lock came in milestone 12). What remains
are the browser's extras: free look with the right mouse button, the scrap debris and sparks, rock-on-rock collision,
the fragment heat glow, LOD 0 rocks up close, and the ship's wing and fitting variants. The browser's ambience beats were removed from the game by the user, so there are none.

Scrapped, not just unported: the raiders (the browser's pirates, mines, threat readout and zone danger ratings). The
user dropped the concept on 2026-09-13, so the port carries no threat readout, no danger rating on the nav map, and
the tutorial's departure line no longer mentions them (re-recorded).

## Conventions

- Units are the HTML's world units; a readout metre is half a unit (`Data.METRE`), exactly as the browser game shows it.
- Rock data lives in packed arrays on `Belt`, never in nodes: 54,000 rocks as nodes would be far too slow.
- Everything that moves is positioned relative to the floating origin: `Main.world_offset` plus a node's `position`
  is its true world position. Rock positions in `Belt` are stored true and converted when drawn or queried.
- Multiplayer later: the belt is generated from a seed, so only changes (broken rocks, pickups, ships) will need replicating.

## Controls (same as the browser)

Mouse steers (cursor off centre yaws and pitches) · W / S throttle · X cut · A / D roll · Shift afterburner (needs the
refit) · LMB / Space / L mining laser · G laser overcharge (needs the refit) · R radar pulse · F flashlight · E within 2,250 m of the
cargo ship: approach control docks you (or fly slowly into either hangar mouth) · on the pad: E deposits the hold, W
departs, F hides the services · Q locks what the mouse is over · T calls a tow when dry · Tab / I inventory · N nav map · C hides the controls list · Space skips an approach ·
F5 quick-save · Esc pause menu (settings, controls, quit).

extends Node3D
## The zone: planet, belt, colony, cargo ship, ship, pickups and HUD, plus the floating origin and the zone changes.
## Every node's `position` is scene-local; add `world_offset` to get a true world coordinate. Whenever the ship drifts
## more than SHIFT_AT from the scene origin the whole scene is shifted so the ship sits at zero again, which keeps
## single-precision floats accurate across a zone 2,800 km wide (the browser game leaned on JavaScript doubles).

const SHIFT_AT := 20000.0
const SEED := 7

var world_offset := Vector3.ZERO
var zone: Dictionary = Data.ZONE_KESSLER
var belt: Belt
var carrier: CargoShip
var ship: Ship
var hud: Hud
var planet: MeshInstance3D
var planet_true := Vector3.ZERO
var colony: Colony
var pickups: Node3D
var drones: Drones
var tutorial: Tutorial
var _dish_toast_t := -100.0
var sun: DirectionalLight3D
var env: Environment
var lighting: Lighting
var hyperspace: Hyperspace
var sparks: Sparks
var menu: Menu
var started := false   # the pilot has left the start menu
var paused := false    # the pause menu is up: the world holds still, the HUD stays
var _cull_t := 0.0
var _save_t := 0.0


func _ready() -> void:
	_smoke = "--smoke" in OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	_setup_inputs()
	_setup_environment()
	belt = Belt.new()
	belt.name = "Belt"
	add_child(belt)
	planet = MeshInstance3D.new()
	planet.name = "Planet"
	add_child(planet)
	pickups = Node3D.new()
	pickups.name = "Pickups"
	add_child(pickups)
	sparks = Sparks.new()
	sparks.name = "Sparks"
	add_child(sparks)
	carrier = CargoShip.new()
	carrier.name = "CargoShip"
	carrier.main = self
	add_child(carrier)
	ship = Ship.new()
	ship.name = "Ship"
	ship.main = self
	ship.belt = belt
	ship.carrier = carrier
	add_child(ship)
	drones = Drones.new()
	drones.name = "Drones"
	drones.main = self
	drones.carrier = carrier
	add_child(drones)
	hyperspace = Hyperspace.new()
	hyperspace.name = "Hyperspace"
	add_child(hyperspace)
	hud = Hud.new()
	add_child(hud)
	hud.bind(ship)
	ship.toast.connect(hud.toast)
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	tutorial.main = self
	tutorial.ship = ship
	tutorial.hud = hud
	add_child(tutorial)
	hud.tutorial = tutorial
	var start := Data.zone_by_id("kessler" if _smoke else State.zone_id)
	load_zone(start)
	spawn_in_zone(false)
	ship.update_camera(1.0)
	print("belt: %d rocks in %d chunks, built in %d ms" % [belt.count, belt._mms.size(), Time.get_ticks_msec() - t0])
	# the menu, on its own layer above the HUD; the world is built and drawn behind it
	var ml := CanvasLayer.new()
	ml.layer = 10
	add_child(ml)
	menu = Menu.new()
	menu.name = "Menu"
	ml.add_child(menu)
	menu.start_requested.connect(_start_game)
	menu.resume_requested.connect(_resume)
	menu.new_game_requested.connect(_new_game)
	menu.wipe_requested.connect(wipe_save)
	menu.tutorial_restart.connect(func(): tutorial.restart())
	menu.setting_changed.connect(_setting_changed)
	menu.quit_requested.connect(_quit)
	get_window().content_scale_factor = float(State.settings.get("hud", 1.0))
	if _smoke:
		_start_game()
	else:
		paused = true
		menu.open(false, State.has_save)


# ---- start, pause, resume, new game (the browser's startGame / pauseGame / resumeGame / newGame / resetSave)
func _start_game() -> void:
	started = true
	paused = false
	menu.close()
	hud.started = true
	hud.tutorial_hidden(false)
	State.save_game()
	if not _smoke:
		hud.toast("Welcome aboard · W launches. In flight: mouse steers, W throttle, hold the left button to cut, R radar, E near the cargo ship to dock.", false)


func _pause() -> void:
	if not started or paused:
		return
	paused = true
	State.save_game()
	hud.tutorial_hidden(true)
	menu.open(true, true)


func _resume() -> void:
	if not paused:
		return
	paused = false
	menu.close()
	hud.tutorial_hidden(false)


## Escape: the pause menu comes down first, then whatever panel is open, then the pause menu goes up.
func _escape() -> void:
	if paused and started:
		_resume()
		return
	if paused:
		return
	if hud.inv_open:
		hud.toggle_inventory()
		return
	if hud.map_open:
		hud.close_map()
		return
	if ship.docked and hud.services_visible:
		hud.toggle_services()
		return
	if ship.cut.is_empty() and ship.warp.is_empty():
		_pause()


func _fresh_start() -> void:
	State.reset()
	tutorial.restart()
	ship.cut = {}
	ship.warp = {}
	ship.vel = Vector3.ZERO
	ship.throttle = 0.0
	if hud.inv_open:
		hud.toggle_inventory()
	hud.close_map()
	load_zone(Data.ZONE_KESSLER)
	spawn_in_zone(false)
	ship.update_camera(1.0)


func _new_game() -> void:
	_fresh_start()
	_start_game()


## Wipe the save (Settings, or the services panel's Reset save): a fresh pilot, back at the start menu.
func wipe_save() -> void:
	_fresh_start()
	started = false
	paused = true
	hud.started = false
	hud.tutorial_hidden(true)
	menu.open(false, false)


func _setting_changed(key: String, value: Variant) -> void:
	if State.settings.get(key) == value:
		return
	if _smoke:
		print("smoke: setting %s = %s (frame %d, phase %s)" % [key, str(value), _frame, _phase])
	State.settings[key] = value
	match key:
		"hud":
			get_window().content_scale_factor = float(value)
		"sound", "volume":
			Audio.apply_settings()
	State.save_game()


func _quit() -> void:
	if started:
		State.save_game()
	get_tree().quit()


func _setup_inputs() -> void:
	_key("throttle_up", KEY_W)
	_key("throttle_down", KEY_S)
	_key("throttle_cut", KEY_X)
	_key("roll_left", KEY_A)
	_key("roll_right", KEY_D)
	_key("pitch_up", KEY_UP)
	_key("pitch_down", KEY_DOWN)
	_key("afterburner", KEY_SHIFT)
	_key("fire", KEY_SPACE)
	_key("fire", KEY_L)
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_key("radar", KEY_R)
	_key("overcharge", KEY_G)
	_key("dock", KEY_E)
	_key("skip", KEY_SPACE)
	_key("map", KEY_N)
	_key("inventory", KEY_TAB)
	_key("inventory", KEY_I)
	_key("controls", KEY_C)
	_key("torch", KEY_F)
	_key("lock", KEY_Q)
	_key("tow", KEY_T)
	_key("tut_next", KEY_ENTER)
	_key("quicksave", KEY_F5)
	_key("menu", KEY_ESCAPE)


func _key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode = key
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	lighting = Lighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.setup(self)
	env = lighting.env
	sun = lighting.sun


# ---- zones
## Build a zone from its data: its belt (none at the Hub), its planet (central, or the homeworld hanging below the
## colony), the colony at the Hub, and the sun. Positions are true; `_apply_offsets` places them against the origin.
func load_zone(z: Dictionary) -> void:
	zone = z
	State.zone_id = z["id"]
	hud.zone = z
	for p in pickups.get_children():
		p.queue_free()
	if sparks:
		sparks.clear()
	ship.near_rocks = PackedInt32Array()   # rock ids from the zone being left
	if drones:
		drones.reset()
	carrier.dish["rock"] = -1
	carrier.dish["firing"] = false
	belt.clear()
	belt.build(z, SEED if z["id"] == "kessler" else SEED + 11)
	var pd: Dictionary = z["planet"]
	var r: float = pd["r"] * Data.PLANET_SCALE
	planet_true = pd.get("position", Vector3.ZERO)
	# Astra's planets are unit spheres (Ferron's terrain; Meridian's oceans and a cloud layer) scaled to the planet's radius
	for c in planet.get_children():
		c.queue_free()
	var ps = load("res://assets/planets/ferron.glb" if pd["name"] == "Ferron" else "res://assets/planets/homeworld.glb")
	if ps != null:
		var m: Node3D = ps.instantiate()
		m.scale = Vector3.ONE * r
		planet.add_child(m)
		planet.mesh = null
	else:
		var sph := SphereMesh.new()
		sph.radius = r
		sph.height = r * 2.0
		sph.radial_segments = 96
		sph.rings = 48
		planet.mesh = sph
		var pm := StandardMaterial3D.new()
		pm.albedo_color = pd["tint"]
		pm.roughness = 0.95 if pd.get("central", true) else 0.55
		planet.material_override = pm
	if colony:
		colony.queue_free()
		colony = null
	if z["hub"]:
		colony = Colony.new()
		colony.name = "Colony"
		add_child(colony)
	lighting.set_zone(z)


## Place the carrier and the ship for the zone: on the pad in the dock that faces the planet in a belt; at the Hub, at the
## holding point (or, `arriving`, out in deep space where the arrival flight starts).
func spawn_in_zone(arriving: bool) -> void:
	if zone["hub"]:
		carrier.hold = true
		var p: Vector3 = Data.HOLD_PARK
		if arriving:
			var start := p - Ship.hold_fwd() * 170000.0 + Ship.hold_side() * 70000.0 + Vector3(0, 26000, 0)
			world_offset = start
			carrier.set_pose(start, CargoShip.heading_along(p - start))
			ship.position = Vector3.ZERO
			ship.docked = false
			ship.hold = false
			ship.set_heading(Ship.level_heading(carrier.nose()))
			_apply_offsets()
		else:
			world_offset = p
			carrier.set_pose(p, CargoShip.heading_along(Data.HOLD_DIR))
			ship.position = Vector3.ZERO
			ship.set_heading(Ship.level_heading(carrier.nose()))
			_apply_offsets()
			ship.enter_berth()
	else:
		carrier.hold = false
		carrier.ang = PI / 2.0 if _smoke else randf() * TAU
		world_offset = Vector3.ZERO
		carrier.place()
		var side: int = carrier.planet_side()
		world_offset = carrier.to_true(CargoShip.park_local(side))
		ship.position = Vector3.ZERO
		ship.set_heading(Ship.level_heading(carrier.dir(CargoShip.face_local(side))))
		_apply_offsets()
		ship.enter_hangar(side)


func _apply_offsets() -> void:
	belt.apply_offset(world_offset)
	planet.position = planet_true - world_offset
	if colony:
		colony.position = -world_offset
	carrier.place()
	belt.cull(ship.true_pos())


## Mid-jump, under the fade: swap the zone and put the carrier where the arrival starts.
func warp_load(z: Dictionary) -> void:
	load_zone(z)
	spawn_in_zone(true)
	ship.update_camera(1.0)


## The jump is over: the Hub arrival flight starts; in a belt the ship is already on its pad.
func warp_done(z: Dictionary) -> void:
	if z["hub"]:
		ship.start_hold_approach()
	else:
		hud.toast("Arrived · %s" % z["name"], false)


func spawn_pickup(ore: String, units: float, at: Vector3, drift: Vector3) -> Pickup:
	var p := Pickup.make(ore, units, at, drift)
	pickups.add_child(p)
	return p


## A rock breaks (the ship's laser or the cargo ship's dish), the HTML's breakRock: big rocks break into smaller
## mineable rocks (colossal → giants → large → small), a quarter of their ore coming loose at once and the rest riding in
## the fragments; a small rock's ore all comes loose. The lumps drift with the rock's orbital velocity. The dish works on
## its own, so its breaks are only announced every 20 s or so; your own always are.
func break_rock(i: int, by_dish: bool) -> void:
	var rname := belt.rock_name(i)
	var ore_i := belt.ore[i]
	var c := belt.cls[i]
	var p: Vector3 = belt.rock_pos(i)
	var at: Vector3 = p - world_offset
	var r := belt.radius[i]
	var v := belt.rock_vel(i)
	var bi := belt.belt_of[i]
	var splits: bool = c > 0
	sparks.burst(p, min(600, 80 + roundi(r * 1.2)), 160.0 + r * 0.6, Color("#ffb060"), 1.5)
	if p.distance_to(ship.true_pos()) < 60000.0:
		belt.spawn_scrap(i, v)   # the scrap of a break the pilot can see
	var total := belt.kill(i)
	var loose: float = total * 0.25 if splits else total
	var near: bool = p.distance_to(ship.true_pos()) < 3000.0
	if near or not by_dish:
		Audio.sfx("rock_break", 0.0 if c > 0 else -4.0)
	if ore_i >= 0 and loose > 0.0:
		var k: int = clampi(roundi(loose / 40.0), 1, 8)
		var ore_key: String = Data.ORE_KEYS[ore_i]
		for n in k:
			var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			spawn_pickup(ore_key, loose / k, at + dir * r * randf_range(0.1, 0.5), v + dir * randf_range(20.0, 60.0))
	var k := 0
	if splits:
		k = _split_rock(c, r, ore_i, total, p, v, bi)
	var quiet: bool = by_dish and State.time - _dish_toast_t < 20.0
	if by_dish and not quiet:
		_dish_toast_t = State.time
	if not quiet:
		var who := "Cargo ship dish: " if by_dish else ""
		var ore_txt := (" · %d %s loose" % [roundi(loose), Data.ORES[Data.ORE_KEYS[ore_i]]["name"]]) if ore_i >= 0 and loose > 0.0 else ""
		if splits:
			hud.toast("%s%s broken into %d %s rocks%s" % [who, rname, k, Belt.CLS_NAME[c - 1].to_lower(), ore_txt], false)
		elif ore_i >= 0 and loose > 0.0:
			hud.toast("%s%s broken%s" % [who, rname, ore_txt], false)
		else:
			hud.toast("%s%s broken · scrap only" % [who, rname], false)


## splitRock: three to five fragments of the next class down, about half of them carrying three quarters of the parent's
## ore between them (always at least one), the rest plain stone; directions kept some 70 degrees apart so no two start
## inside each other; each about a third of the parent's radius, starting well out from the centre with a shove apart.
func _split_rock(c: int, r: float, ore_i: int, total: float, p: Vector3, v: Vector3, bi: int) -> int:
	var k: int = 3 + randi() % (3 if c == 1 else 2)
	var carry: Array = []
	for n in k:
		carry.append(ore_i >= 0 and randf() < 0.5)
	if ore_i >= 0 and not carry.has(true):
		carry[randi() % k] = true
	var n_carry := carry.count(true)
	var share: float = total * 0.75 / n_carry if n_carry > 0 else 0.0
	var dirs: Array = []
	var tries := 0
	while dirs.size() < k and tries < 200:
		tries += 1
		var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var apart := true
		for o in dirs:
			if (o as Vector3).dot(d) >= 0.35:
				apart = false
				break
		if apart:
			dirs.append(d)
	while dirs.size() < k:
		dirs.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized())
	var size0: float = float(belt._belts[bi]["size"][0]) if bi < belt._belts.size() else 16.0
	for n in k:
		var fr: float = max(size0 * 0.6, r * pow(0.12 / k, 1.0 / 3.0) * randf_range(0.85, 1.15))
		var barren: bool = not carry[n] or share < 1.5
		var d: Vector3 = dirs[n]
		belt.add_fragment(c - 1, fr, ore_i, barren, p + d * r * randf_range(0.6, 0.85), 0.0 if barren else share * randf_range(0.8, 1.2), v + d * randf_range(30.0, 70.0), bi)
	return k


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("menu"):
		_escape()
	if not started or paused:
		hud.update(ship, belt, carrier)
		if _smoke:
			_smoke_step()   # the run drives the pause menu too
		return
	if Input.is_action_just_pressed("torch") and ship.docked:
		hud.toggle_services()
	if Input.is_action_just_pressed("quicksave"):
		State.save_game()
		hud.toast("Saved", false)
	if Input.is_action_just_pressed("map") and ship.warp.is_empty():
		hud.toggle_map()
	if Input.is_action_just_pressed("inventory"):
		hud.toggle_inventory()
	if Input.is_action_just_pressed("controls"):
		hud.toggle_controls()
	State.time += dt
	State.tick_market(dt)
	# the carrier drifts round its orbit; a docked ship rides along with it (at the Hub it holds station instead)
	var moved: Vector3 = carrier.tick(dt)
	if ship.docked and not ship.hold:
		ship.position += moved
	ship.tick(dt)
	belt.tick(dt, ship.near_rocks)   # the rails' drift time for the rock shader, free rocks and scrap coasting, broken rocks growing back
	sparks.tick(dt, world_offset)
	if Engine.get_process_frames() % 10 == 0:
		belt.update_lod0(ship.true_pos(), ship.near_rocks)   # the rocks close to the ship draw their finest mesh
	# the dish's beam cooks the stone where it lands (the ship's own beam sets its point from the laser)
	var dr: int = carrier.dish["rock"]
	if carrier.dish["firing"] and dr >= 0 and dr < belt.count:
		belt.set_spot_heat(1, carrier.dish["hit"], 1.0, belt.radius[dr] * 0.45)
	else:
		belt.set_spot_heat(1, Vector3.ZERO, 0.0, 1.0)
	Audio.engine(ship.throttle, ship.afterburning, ship.braking, ship.docked or not ship.cut.is_empty() or not ship.warp.is_empty())
	Audio.laser(ship.firing and not ship.docked, ship.laser_on)
	if ship.warp.is_empty():
		carrier.tick_dish(dt, belt)
		drones.tick(dt)
	for p in pickups.get_children():
		if p.tick(dt, ship.position):
			p.queue_free()
	if colony:
		colony.tick(dt)
	# floating origin
	if ship.position.length() > SHIFT_AT:
		var delta := ship.position
		world_offset += delta
		ship.position = Vector3.ZERO
		belt.apply_offset(world_offset)
		planet.position = planet_true - world_offset
		if colony:
			colony.position = -world_offset
		carrier.place()
		for p in pickups.get_children():
			p.position -= delta
		ship.on_shift(delta)
	ship.update_camera(dt)
	_cull_t += dt
	if _cull_t > 0.25:
		_cull_t = 0.0
		belt.cull(ship.true_pos())
	_save_t += dt
	if _save_t > 30.0:
		_save_t = 0.0
		State.save_game()
	hud.update(ship, belt, carrier)
	tutorial.update(dt)
	if _smoke:
		_smoke_step()


## `godot --path . -- --smoke`: an unattended run through the whole loop, printing what happened at each stage and
## saving screenshots under user://. It launches from the pad, cuts the nearest copper rock through, watches the ore
## come aboard, flies back and docks, deposits the hold, departs, docks again, jumps to the Hub, arrives on station,
## sells, refuels, restocks, jumps home and lands on the pad, then quits. It is how the port gets checked from a terminal.
var _smoke := false
var _frame := 0
var _phase := "start"
var _phase_frame := 0
var _smoke_rock := -1
var _smoke_rail := -1
var _smoke_rail_p := Vector3.ZERO
var _smoke_rail_t := 0.0
var _smoke_count := 0
var _smoke_cr := 0.0
var _smoke_tow_phase := ""
var _smoke_tow_frame := 0
var _tut_last := -1
var _tut_frames := 0


## The tutorial runs alongside the smoke loop: its steps are driven the way a pilot would drive them (a turn, Next, R,
## Tab...) and every transition is printed, so the whole questline is exercised by the run.
func _smoke_tutorial() -> void:
	if not tutorial.active():
		if _tut_last >= 0:
			print("smoke: tutorial finished · voice plays: %s" % str(Audio.plays))
			_tut_last = -2
		return
	var st := tutorial.step()
	if st != _tut_last:
		print("smoke: tutorial -> %d %s" % [st + 1, Tutorial.STEPS[st]["id"]])
		_tut_last = st
		_tut_frames = 0
	_tut_frames += 1
	match Tutorial.STEPS[st]["id"]:
		"steer":
			if _tut_frames == 30:
				tutorial.flags["flown"] = true
		"hud", "hangar", "refit", "hub", "done":
			if _tut_frames == 30:
				tutorial.advance()
		"radar":
			if _tut_frames == 30:
				ship._radar()   # what R does (a scripted action_press is not a fresh press by the next frame)
		"lock":
			if _tut_frames == 30 and _smoke_rock >= 0:
				ship.lock_on_rock(_smoke_rock)   # what Q does with the mouse on the rock
				print("smoke: lock · %s · kind=%s dist=%.0f" % [ship.lock_name(), ship.lock_kind, ship.lock_dist])
		"inv":
			if _tut_frames == 30:
				hud.toggle_inventory()
		"return":
			if _tut_frames == 30 and hud.inv_open:
				hud.toggle_inventory()   # the inv step advances the moment the panel opens; close it again here


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://%s.png" % name)


func _smoke_step() -> void:
	_frame += 1
	_phase_frame += 1
	ship.mouse_steer = false
	if _frame > 20000:
		print("smoke: TIMEOUT in phase %s" % _phase)
		get_tree().quit()
		return
	_smoke_tutorial()
	match _phase:
		"start":
			if _frame == 5:
				State.tut = 0
				State.depot["laser"] = 1     # the cargo ship upgrades, so the dish and a drone get exercised
				State.depot["collectors"] = 1
			if _frame == 20:
				print("smoke: zone=%s rocks=%d chunks=%d docked=%s dock=%s" % [zone["id"], belt.count, belt._mms.size(), str(ship.docked), CargoShip.bay_name(ship.dock_side)])
				_shot("smoke_launch")
				ship.start_departure()
				_next("leaving")
		"leaving":
			if _phase_frame == 90:
				_shot("smoke_taxi")
			if _phase_frame == 60:
				print("smoke: taxi loops (idle) %s" % str(Audio.loop_state()))
			if ship.cut.is_empty() and not ship.docked:
				print("smoke: launched · speed=%.0f throttle=%.2f" % [ship.speed(), ship.throttle])
				var scan: Dictionary = belt.scan(ship.true_pos(), 200000.0, Data.ORE_KEYS.find("copper"))   # copper: the one ore a level-1 laser cuts
				_smoke_rock = scan["nearest"]
				belt.set_free(_smoke_rock, Vector3.ZERO)   # a rock knocked off its rail and at rest, so the parked ship keeps the beam on it
				var rp: Vector3 = belt.rock_pos(_smoke_rock) - world_offset
				var dir := (rp - ship.position).normalized()
				ship.position = rp - dir * (belt.radius[_smoke_rock] + 560.0)   # close enough for the finest mesh (under six radii)
				ship.look_at(rp, Vector3.UP)
				ship.vel = Vector3.ZERO
				ship.throttle = 0.0
				ship.update_camera(1.0)
				belt.hp[_smoke_rock] = 45.0   # nearly cut through already, so the run also sees it break and the ore come aboard
				ship.spot_heat = 0.8   # as if the beam had been on it a while (a new rock keeps half): hot enough to scorch and light the stone
				# a rail rock nearby to watch drifting: 28 u/s along its orbit
				_smoke_rail = -1
				for n in range(1, 200):
					var j: int = (_smoke_rock + n) % belt.count
					if belt.alive[j] == 1 and belt.free[j] == 0:
						_smoke_rail = j
						break
				_smoke_rail_p = belt.rock_pos(_smoke_rail)
				_smoke_rail_t = State.time
				_smoke_count = belt.count
				Input.action_press("fire")
				_next("mining")
		"mining":
			if _phase_frame == 60:
				_shot("smoke_mine")
				print("smoke: cutting %s · target=%d laser_on=%s hp=%.0f · lod0 rocks %d (target r=%.0f at %.0f) · sparks %d · spot heat %.2f · scorches %d" % [belt.rock_name(_smoke_rock), ship.target, str(ship.laser_on), belt.hp[_smoke_rock], belt.lod0_count(), belt.radius[_smoke_rock], belt.rock_pos(_smoke_rock).distance_to(ship.true_pos()), sparks.count(), ship.spot_heat, belt.burn_count()])
				print("smoke: laser loops %s" % str(Audio.loop_state()))
			if _phase_frame == 100:
				ship.throttle = 0.6   # a burst of throttle so the engine loops can be read
			if _phase_frame == 150:
				print("smoke: engine loops at throttle %.1f %s" % [ship.throttle, str(Audio.loop_state())])
				ship.throttle = 0.0
				var moved: float = belt.rock_pos(_smoke_rail).distance_to(_smoke_rail_p)
				var secs: float = State.time - _smoke_rail_t
				print("smoke: rails · rock %d drifted %.1f u in %.2f s (%.1f u/s) · free rocks %d" % [_smoke_rail, moved, secs, moved / max(0.01, secs), belt._free_ids.size()])
				var hc: Dictionary = carrier.hull_contact(Vector3(0.0, 0.0, 1200.0), Data.SHIP_R) if not carrier._hull.is_empty() else {}
				var hc2: Dictionary = carrier.hull_contact(Vector3(0.0, 0.0, 300.0), Data.SHIP_R) if not carrier._hull.is_empty() else {}
				print("smoke: hull profile %s · point 1,200 off the flank: %s · point 300 in (outside the passage rule): %s" % ["loaded" if not carrier._hull.is_empty() else "missing", "clear" if hc.is_empty() else "contact n=%s" % str((hc["n"] as Vector3).snapped(Vector3.ONE * 0.01)), "clear" if hc2.is_empty() else "contact"])
			if _phase_frame == 200 or _phase_frame == 400:
				print("smoke: dish %s · drones %s · stowed by drones %.0f · pickups %d" % [str(carrier.dish_stats()), str(drones.stats()), State.drone_units, pickups.get_child_count()])
			if (belt.alive[_smoke_rock] == 0 and _phase_frame > 420) or _phase_frame > 1200:
				Input.action_release("fire")
				print("smoke: mined · rock_alive=%d pickups_left=%d cargo=%.0f fuel=%.1f fps=%.0f" % [belt.alive[_smoke_rock], pickups.get_child_count(), State.cargo_total(), State.fuel, Engine.get_frames_per_second()])
				print("smoke: fx · sparks %d · scrap %d · lod0 rocks %d · near rocks %d · spot heat %.2f · scorches %d · fittings %s" % [sparks.count(), belt.scrap_count(), belt.lod0_count(), ship.near_rocks.size(), ship.spot_heat, belt.burn_count(), ship.variant_report()])
				var fld: Dictionary = belt.field_at(ship.true_pos())
				var nf: Dictionary = belt.nearest_field(ship.true_pos())
				print("smoke: fields %d · in %s · nearest %s at %.0f · dish aim yaw=%.2f pitch=%.2f aimed=%s" % [belt._fields.size(), str(fld.get("name", "-")), str(nf.get("name", "-")), float(nf.get("edge", 0.0)), ship.aim_yaw, ship.aim_pitch, str(ship.aimed)])
				var frags: Array = []
				for j in range(_smoke_count, belt.count):
					frags.append("%s r=%.0f ore=%.0f" % [belt.rock_name(j), belt.radius[j], belt.amount[j]])
				print("smoke: fragments %d · %s · nodes %d · dead awaiting respawn %d" % [belt.count - _smoke_count, ", ".join(frags), belt._frag_nodes.size(), belt._dead.size()])
				# back to the carrier with a hold worth depositing: park 3,000 off the nearer mouth and ask approach control for the ship
				State.add_cargo("copper", 120.0)
				State.add_cargo("gold", 30.0)
				var entry: int = carrier.nearest_side(ship.true_pos())
				var start_l := CargoShip.opening_local(entry) + Vector3(300.0, 120.0, entry * 3000.0)
				ship.position = carrier.to_true(start_l) - world_offset
				ship.vel = carrier.vel
				ship.set_heading(Ship.level_heading(carrier.dir(Vector3(0.0, 0.0, -entry))))
				ship.update_camera(1.0)
				ship.start_approach()
				print("smoke: approach requested · cut=%s dist=%.0f" % [str(not ship.cut.is_empty()), ship.true_pos().distance_to(carrier.true_pos)])
				_next("approach")
		"approach":
			if _phase_frame == 120:
				_shot("smoke_approach")
			if ship.docked:
				_shot("smoke_dock")
				var before := State.store_total()
				ship.deposit_all()
				print("smoke: docked in %s · store %.0f -> %.0f · hold=%.0f · fuel=%.1f/%.0f shipFuel=%.0f · force field flashes %d" % [CargoShip.bay_name(ship.dock_side), before, State.store_total(), State.cargo_total(), State.fuel, State.stat("tank")["cap"], State.ship_fuel, carrier.field_flashes])
				_next("docked")
		"docked":
			if _phase_frame == 60:
				print("smoke: dish %s · drones %s · stowed by drones %.0f · pickups %d" % [str(carrier.dish_stats()), str(drones.stats()), State.drone_units, pickups.get_child_count()])
				# two lumps of gold just off the drone dock, so a collector can finish a whole run while we sit on the pad
				for p in pickups.get_children():
					p.queue_free()   # the lumps left by the mining are kilometres out; this check wants a short run
				var dock_l: Vector3 = carrier.anchors.get("drone_dock_0", Vector3(760, -60, 1500))
				for n in 2:
					spawn_pickup("gold", 40.0, carrier.to_true(dock_l + Vector3(400.0 + n * 120.0, 60.0, 500.0)) - world_offset, Vector3.ZERO)
				drones.reset()
			if _phase_frame == 90:
				var lp := carrier.to_local_true(ship.true_pos())
				print("smoke: on the pad · local=(%.0f, %.0f, %.0f) park=%s" % [lp.x, lp.y, lp.z, str(CargoShip.park_local(ship.dock_side))])
				_shot("smoke_pad")
				hud.toggle_inventory()   # the inventory beside the services panel: both grids
			if _phase_frame == 100:
				# the drag and drop, driven as the viewport would: a storage stack dropped on the hold grid, then a hold stack
				# dropped on the storage grid, then a hold stack let go outside the grids (jettisoned into the hangar)
				var st: Array = get_tree().get_nodes_in_group("inv_store").filter(func(s): return not s.is_empty())
				var hs: Array = get_tree().get_nodes_in_group("inv_hold")
				if st.size() > 0 and hs.size() > 0:
					var h0 := State.cargo_total()
					hs[0]._drop_data(Vector2.ZERO, {"k": st[0].k, "u": st[0].u, "store": true})
					print("smoke: drag storage -> hold · hold %.0f -> %.0f · store=%.0f" % [h0, State.cargo_total(), State.store_total()])
			if _phase_frame == 110:
				var hs: Array = get_tree().get_nodes_in_group("inv_hold").filter(func(s): return not s.is_empty())
				var ss: Array = get_tree().get_nodes_in_group("inv_store")
				if hs.size() > 0 and ss.size() > 0:
					var s0 := State.store_total()
					ss[0]._drop_data(Vector2.ZERO, {"k": hs[0].k, "u": hs[0].u, "store": false})
					print("smoke: drag hold -> storage · store %.0f -> %.0f · hold=%.0f" % [s0, State.store_total(), State.cargo_total()])
			if _phase_frame == 115:
				var st: Array = get_tree().get_nodes_in_group("inv_store").filter(func(s): return not s.is_empty())
				var hs: Array = get_tree().get_nodes_in_group("inv_hold")
				if st.size() > 0 and hs.size() > 0:
					hs[0]._drop_data(Vector2.ZERO, {"k": st[0].k, "u": min(st[0].u, 10.0), "store": true})   # a small stack to throw away
			if _phase_frame == 118:
				# the fittings follow the refit tiers: a level-2 laser shows the second barrel, then back
				var was: int = State.up["laser"]
				State.up["laser"] = 2
				ship.configure_model()
				print("smoke: fittings at laser Lv3 · %s" % ship.variant_report())
				State.up["laser"] = was
				ship.configure_model()
			if _phase_frame == 120:
				_shot("smoke_inventory")
				var hs: Array = get_tree().get_nodes_in_group("inv_hold").filter(func(s): return not s.is_empty())
				if hs.size() > 0:
					var before := pickups.get_child_count()
					hud._jettison(hs[0].k, hs[0].u)   # what a drag let go outside the grids does
					print("smoke: jettison · hold=%.0f · lumps %d -> %d · no_pick=%.0f" % [State.cargo_total(), before, pickups.get_child_count(), pickups.get_child(pickups.get_child_count() - 1).no_pick])
				hud.toggle_inventory()
			if _phase_frame % 600 == 0:
				print("smoke: waiting on the drone · %s · stowed %.0f" % [str(drones.stats()), State.drone_units])
			if _phase_frame > 130 and (State.drone_units > 0.5 or _phase_frame > 6000):
				print("smoke: drone run %s · stowed by drones %.0f · store gold %.0f · force field flashes %d" % ["done" if State.drone_units > 0.5 else "TIMED OUT", State.drone_units, State.store["gold"], carrier.field_flashes])
				ship.start_departure()
				_next("depart")
		"depart":
			if ship.cut.is_empty() and not ship.docked and _phase_frame > 30:
				var lp := carrier.to_local_true(ship.true_pos())
				print("smoke: departed · speed=%.0f local_z=%.0f exit_pending=%s" % [ship.speed(), lp.z, str(ship.exit_pending)])
				# out of fuel just off the mouth: T calls the tug, which latches on and hauls the ship back in
				State.fuel = 0.0
				ship.vel = Vector3.ZERO
				_smoke_cr = State.credits
				ship.call_tow()
				_smoke_tow_phase = ""
				print("smoke: tow requested · tug phase=%s dist0=%.0f speed=%.0f" % [str(ship.tow.get("phase", "none")), ship.tow.get("dist0", 0.0), ship.tow_speed()])
				_next("tow")
		"tow":
			var ph: String = str(ship.tow.get("phase", "none"))
			if ph != _smoke_tow_phase:
				_smoke_tow_phase = ph
				_smoke_tow_frame = _phase_frame
				print("smoke: tug %s · %s · ship-tug %.0f" % [ph, ship.tow_status(), ship.true_pos().distance_to(ship.tow.get("pos", ship.true_pos())) if not ship.tow.is_empty() else 0.0])
			if ph == "haul" and _phase_frame == _smoke_tow_frame + 90:
				_shot("smoke_tow")   # under tow: the tug ahead with the beam on the nose
			if ship.docked or _phase_frame > 12000:
				if not ship.docked:
					print("smoke: tow TIMED OUT in phase %s" % ph)
					ship.enter_hangar(carrier.planet_side())
				print("smoke: towed home · dock=%s · credits %.0f -> %.0f · fuel=%.0f · disabled=%s · tug=%s" % [CargoShip.bay_name(ship.dock_side), _smoke_cr, State.credits, State.fuel, str(ship.disabled), str(ship.tow.get("phase", "gone"))])
				ship.start_warp(Data.ZONE_HUB)
				print("smoke: warp requested · warp=%s" % str(not ship.warp.is_empty()))
				_next("warping")
		"warping":
			if _phase_frame == 60:
				_shot("smoke_warp")
			# the jump runs at the frame rate: about 135 frames a second, so 245 frames is the launch (stretch and flash),
			# 480 is deep in the tunnel with the zone already swapped underneath, 615 is the arrival snap
			if _phase_frame == 245 and not ship.warp.is_empty():
				_shot("smoke_hyperspace_launch")
				print("smoke: hyperspace at %.1f s · %s · stretch=%.2f · fov=%.0f" % [ship.warp["t"], str(ship.warp["pose"]["phase"]), ship.warp["pose"]["stretch"], ship.cam.fov])
			if _phase_frame == 480 and not ship.warp.is_empty():
				_shot("smoke_hyperspace")
				print("smoke: hyperspace at %.1f s · %s · loaded=%s · coverage=%.2f · fov=%.0f" % [ship.warp["t"], str(ship.warp["pose"]["phase"]), str(ship.warp["loaded"]), ship.warp["pose"]["coverage"], ship.cam.fov])
			if _phase_frame == 615 and not ship.warp.is_empty():
				_shot("smoke_hyperspace_arrival")
				print("smoke: hyperspace at %.1f s · %s · stretch=%.2f · offset=%.0f" % [ship.warp["t"], str(ship.warp["pose"]["phase"]), ship.warp["pose"]["stretch"], ship.warp["pose"]["offset"]])
			if ship.warp.is_empty() and zone["hub"]:
				print("smoke: arrived at the Hub · cut=%s carrier_dist_to_hold=%.0f rocks=%d" % [str(ship.cut.get("mode", "none")), carrier.true_pos.distance_to(Data.HOLD_PARK), belt.count])
				_next("arrival")
		"arrival":
			if _phase_frame == 150:
				_shot("smoke_arrival")
			if _phase_frame == 300 and not ship.cut.is_empty():
				ship.skip_cut()
			if _phase_frame == 200 and colony and colony.traffic:
				print("smoke: traffic %s" % str(colony.traffic.stats()))
			if ship.docked and ship.hold:
				_shot("smoke_hub")
				if colony and colony.traffic:
					print("smoke: traffic on station %s" % str(colony.traffic.stats()))
				var cr0 := State.credits
				var aboard := State.cargo_total() + State.store_total()
				ship.sell(Data.ORE_KEYS, true, true)
				var cr1 := State.credits
				State.ship_fuel = 900.0
				ship.refuel_cargo_ship()
				ship.buy_parts()
				print("smoke: holding station · sold %.0f units for %.0f cr (%.0f -> %.0f) · after fuel and parts: %.0f cr, fuel %.0f, parts %.0f · store=%.0f hold=%.0f" % [aboard, cr1 - cr0, cr0, cr1, State.credits, State.ship_fuel, State.parts, State.store_total(), State.cargo_total()])
				_next("selling")
		"selling":
			if _phase_frame == 60:
				_shot("smoke_market")
				hud.open_map()
			if _phase_frame == 90:
				_shot("smoke_map")
				hud.close_map()
				_pause()   # the pause menu over the frozen game, then its settings and controls pages
			if _phase_frame == 120:
				_shot("smoke_menu")
				menu._show_page("settings")
			if _phase_frame == 140:
				_shot("smoke_settings")
				menu._show_page("controls")
			if _phase_frame == 160:
				_shot("smoke_controls")
				_resume()
			if _phase_frame == 180:
				ship.start_warp(Data.ZONE_KESSLER)
				print("smoke: warp home requested · warp=%s" % str(not ship.warp.is_empty()))
				_next("home")
		"home":
			if _phase_frame == 120 and not ship.warp.is_empty():
				ship.warp["skip"] = true
			if ship.warp.is_empty() and not zone["hub"] and ship.docked:
				var lp := carrier.to_local_true(ship.true_pos())
				print("smoke: home · zone=%s docked=%s hold=%s dock=%s local=(%.0f, %.0f, %.0f) rocks=%d" % [zone["id"], str(ship.docked), str(ship.hold), CargoShip.bay_name(ship.dock_side), lp.x, lp.y, lp.z, belt.count])
				_shot("smoke_home")
				print("smoke: screenshots in %s" % ProjectSettings.globalize_path("user://"))
				get_tree().quit()


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0

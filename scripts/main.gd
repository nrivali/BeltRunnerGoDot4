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
var sun: DirectionalLight3D
var env: Environment
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
	hud = Hud.new()
	add_child(hud)
	hud.bind(ship)
	ship.toast.connect(hud.toast)
	var start := Data.zone_by_id("kessler" if _smoke else State.zone_id)
	load_zone(start)
	spawn_in_zone(false)
	ship.update_camera(1.0)
	hud.toast("Welcome aboard · W launches. In flight: mouse steers, W throttle, hold the left button to cut, R radar, E near the cargo ship to dock. N opens the nav map.", false)
	print("belt: %d rocks in %d chunks, built in %d ms" % [belt.count, belt._chunk_nodes.size(), Time.get_ticks_msec() - t0])


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
	_key("quicksave", KEY_F5)
	_key("quit", KEY_ESCAPE)


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
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.027, 0.035, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.23, 0.29, 0.54)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#fff1dc")
	sun.light_energy = 2.2
	add_child(sun)


# ---- zones
## Build a zone from its data: its belt (none at the Hub), its planet (central, or the homeworld hanging below the
## colony), the colony at the Hub, and the sun. Positions are true; `_apply_offsets` places them against the origin.
func load_zone(z: Dictionary) -> void:
	zone = z
	State.zone_id = z["id"]
	hud.zone = z
	for p in pickups.get_children():
		p.queue_free()
	belt.clear()
	belt.build(z, SEED if z["id"] == "kessler" else SEED + 11)
	var pd: Dictionary = z["planet"]
	var r: float = pd["r"] * Data.PLANET_SCALE
	planet_true = pd.get("position", Vector3.ZERO)
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
	var dir: Vector3 = z["sunDir"]
	sun.look_at_from_position(Vector3.ZERO, -dir.normalized(), Vector3.UP)
	env.background_color = z["bg"]


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


func spawn_pickup(ore: String, units: float, at: Vector3, drift: Vector3) -> void:
	pickups.add_child(Pickup.make(ore, units, at, drift))


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("quit"):
		State.save_game()
		get_tree().quit()
	if Input.is_action_just_pressed("quicksave"):
		State.save_game()
		hud.toast("Saved", false)
	if Input.is_action_just_pressed("map") and ship.warp.is_empty():
		hud.toggle_map()
	State.time += dt
	State.tick_market(dt)
	# the carrier drifts round its orbit; a docked ship rides along with it (at the Hub it holds station instead)
	var moved: Vector3 = carrier.tick(dt)
	if ship.docked and not ship.hold:
		ship.position += moved
	ship.tick(dt)
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
	match _phase:
		"start":
			if _frame == 20:
				print("smoke: zone=%s rocks=%d chunks=%d docked=%s dock=%s" % [zone["id"], belt.count, belt._chunk_nodes.size(), str(ship.docked), CargoShip.bay_name(ship.dock_side)])
				_shot("smoke_launch")
				ship.start_departure()
				_next("leaving")
		"leaving":
			if _phase_frame == 90:
				_shot("smoke_taxi")
			if ship.cut.is_empty() and not ship.docked:
				print("smoke: launched · speed=%.0f throttle=%.2f" % [ship.speed(), ship.throttle])
				var scan: Dictionary = belt.scan(ship.true_pos(), 200000.0, Data.ORE_KEYS.find("copper"))   # copper: the one ore a level-1 laser cuts
				_smoke_rock = scan["nearest"]
				var rp: Vector3 = belt.pos[_smoke_rock] - world_offset
				var dir := (rp - ship.position).normalized()
				ship.position = rp - dir * (belt.radius[_smoke_rock] + 700.0)
				ship.look_at(rp, Vector3.UP)
				ship.vel = Vector3.ZERO
				ship.throttle = 0.0
				ship.update_camera(1.0)
				belt.hp[_smoke_rock] = 45.0   # nearly cut through already, so the run also sees it break and the ore come aboard
				Input.action_press("fire")
				_next("mining")
		"mining":
			if _phase_frame == 60:
				_shot("smoke_mine")
				print("smoke: cutting %s · target=%d laser_on=%s hp=%.0f" % [belt.rock_name(_smoke_rock), ship.target, str(ship.laser_on), belt.hp[_smoke_rock]])
			if (belt.alive[_smoke_rock] == 0 and _phase_frame > 420) or _phase_frame > 1200:
				Input.action_release("fire")
				print("smoke: mined · rock_alive=%d pickups_left=%d cargo=%.0f fuel=%.1f fps=%.0f" % [belt.alive[_smoke_rock], pickups.get_child_count(), State.cargo_total(), State.fuel, Engine.get_frames_per_second()])
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
				print("smoke: docked in %s · store %.0f -> %.0f · hold=%.0f · fuel=%.1f/%.0f shipFuel=%.0f" % [CargoShip.bay_name(ship.dock_side), before, State.store_total(), State.cargo_total(), State.fuel, State.stat("tank")["cap"], State.ship_fuel])
				_next("docked")
		"docked":
			if _phase_frame == 90:
				var lp := carrier.to_local_true(ship.true_pos())
				print("smoke: on the pad · local=(%.0f, %.0f, %.0f) park=%s" % [lp.x, lp.y, lp.z, str(CargoShip.park_local(ship.dock_side))])
				_shot("smoke_pad")
				ship.start_departure()
				_next("depart")
		"depart":
			if ship.cut.is_empty() and not ship.docked and _phase_frame > 30:
				var lp := carrier.to_local_true(ship.true_pos())
				print("smoke: departed · speed=%.0f local_z=%.0f exit_pending=%s" % [ship.speed(), lp.z, str(ship.exit_pending)])
				# straight back aboard and off to the Hub
				ship.enter_hangar(carrier.planet_side())
				ship.start_warp(Data.ZONE_HUB)
				print("smoke: warp requested · warp=%s" % str(not ship.warp.is_empty()))
				_next("warping")
		"warping":
			if _phase_frame == 60:
				_shot("smoke_warp")
			if _phase_frame == 200 and not ship.warp.is_empty():
				ship.warp["skip"] = true
			if ship.warp.is_empty() and zone["hub"]:
				print("smoke: arrived at the Hub · cut=%s carrier_dist_to_hold=%.0f rocks=%d" % [str(ship.cut.get("mode", "none")), carrier.true_pos.distance_to(Data.HOLD_PARK), belt.count])
				_next("arrival")
		"arrival":
			if _phase_frame == 150:
				_shot("smoke_arrival")
			if _phase_frame == 300 and not ship.cut.is_empty():
				ship.skip_cut()
			if ship.docked and ship.hold:
				_shot("smoke_hub")
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

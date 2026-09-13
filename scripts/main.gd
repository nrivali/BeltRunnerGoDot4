extends Node3D
## The zone: planet, belt, ship, pickups and HUD, plus the floating origin. Every node's `position` is scene-local; add
## `world_offset` to get a true world coordinate. Whenever the ship drifts more than SHIFT_AT from the scene origin the
## whole scene is shifted so the ship sits at zero again, which keeps single-precision floats accurate across a zone
## 2,800 km wide (the browser game leaned on JavaScript doubles for this).

const SHIFT_AT := 20000.0
const SEED := 7

var world_offset := Vector3.ZERO
var belt: Belt
var carrier: CargoShip
var ship: Ship
var hud: Hud
var planet: MeshInstance3D
var pickups: Node3D
var _cull_t := 0.0
var _save_t := 0.0


func _ready() -> void:
	_smoke = "--smoke" in OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	_setup_inputs()
	_setup_environment()
	var zone: Dictionary = Data.ZONE_KESSLER
	belt = Belt.new()
	belt.name = "Belt"
	add_child(belt)
	belt.build(zone, SEED)
	planet = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = belt.planet_r
	sph.height = belt.planet_r * 2.0
	sph.radial_segments = 96
	sph.rings = 48
	planet.mesh = sph
	var pm := StandardMaterial3D.new()
	pm.albedo_color = zone["planet"]["tint"]
	pm.roughness = 0.95
	planet.material_override = pm
	add_child(planet)
	pickups = Node3D.new()
	pickups.name = "Pickups"
	add_child(pickups)
	carrier = CargoShip.new()
	carrier.name = "CargoShip"
	carrier.main = self
	carrier.ang = PI / 2.0 if _smoke else randf() * TAU
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
	# every start is on the pad in the dock that faces the planet, so the first departure heads for the belt
	world_offset = Vector3.ZERO
	carrier.place()
	var side: int = carrier.planet_side()
	world_offset = carrier.to_true(CargoShip.park_local(side))
	carrier.place()
	ship.position = Vector3.ZERO
	ship.set_heading(Ship.level_heading(carrier.dir(CargoShip.face_local(side))))
	belt.apply_offset(world_offset)
	planet.position = -world_offset
	belt.cull(world_offset)
	ship.enter_hangar(side)
	ship.update_camera(1.0)
	hud.toast("Welcome aboard · W launches. In flight: mouse steers, W throttle, hold the left button to cut, R radar, E near the cargo ship to dock.", false)
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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.027, 0.035, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.23, 0.29, 0.54)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff1dc")
	sun.light_energy = 2.2
	var dir: Vector3 = Data.ZONE_KESSLER["sunDir"]
	sun.look_at_from_position(Vector3.ZERO, -dir.normalized(), Vector3.UP)
	add_child(sun)


func spawn_pickup(ore: String, units: float, at: Vector3, drift: Vector3) -> void:
	pickups.add_child(Pickup.make(ore, units, at, drift))


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("quit"):
		State.save_game()
		get_tree().quit()
	if Input.is_action_just_pressed("quicksave"):
		State.save_game()
		hud.toast("Saved", false)
	State.time += dt
	# the carrier drifts round its orbit; a docked ship (and one being taxied) rides along with it
	var moved: Vector3 = carrier.tick(dt)
	if ship.docked:
		ship.position += moved
	ship.tick(dt)
	for p in pickups.get_children():
		if p.tick(dt, ship.position):
			p.queue_free()
	# floating origin
	if ship.position.length() > SHIFT_AT:
		var delta := ship.position
		world_offset += delta
		ship.position = Vector3.ZERO
		belt.apply_offset(world_offset)
		planet.position = -world_offset
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
## saving screenshots under user:// (smoke_launch, smoke_mine, smoke_dock). It launches from the pad, parks in front of
## the nearest copper rock and cuts it through, watches the ore come aboard, flies back to the carrier and asks for an
## approach, deposits the ore in the storage once docked, departs again, then quits. It is how the port gets checked
## from a terminal (the same idea as the browser game's ?debug hook).
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
	if _frame > 6000:
		print("smoke: TIMEOUT in phase %s" % _phase)
		get_tree().quit()
		return
	match _phase:
		"start":
			if _frame == 20:
				print("smoke: rocks=%d chunks=%d docked=%s dock=%s" % [belt.count, belt._chunk_nodes.size(), str(ship.docked), CargoShip.bay_name(ship.dock_side)])
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
				var cl := carrier.to_local_true(ship.cam.global_position + world_offset)
				var to_ship := (ship.position - ship.cam.global_position).normalized()
				var cam_fwd := -ship.cam.global_transform.basis.z
				print("smoke: on the pad · local=(%.0f, %.0f, %.0f) park=%s cam_local=(%.0f, %.0f, %.0f) cam_on_ship=%.2f" % [lp.x, lp.y, lp.z, str(CargoShip.park_local(ship.dock_side)), cl.x, cl.y, cl.z, cam_fwd.dot(to_ship)])
				_shot("smoke_pad")
				ship.start_departure()
				_next("depart")
		"depart":
			if ship.cut.is_empty() and not ship.docked and _phase_frame > 30:
				var lp := carrier.to_local_true(ship.true_pos())
				print("smoke: departed · speed=%.0f local_z=%.0f exit_pending=%s" % [ship.speed(), lp.z, str(ship.exit_pending)])
				print("smoke: screenshots in %s" % ProjectSettings.globalize_path("user://"))
				get_tree().quit()


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0

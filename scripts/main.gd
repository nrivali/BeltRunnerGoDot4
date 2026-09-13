extends Node3D
## The zone: planet, belt, ship, pickups and HUD, plus the floating origin. Every node's `position` is scene-local; add
## `world_offset` to get a true world coordinate. Whenever the ship drifts more than SHIFT_AT from the scene origin the
## whole scene is shifted so the ship sits at zero again, which keeps single-precision floats accurate across a zone
## 2,800 km wide (the browser game leaned on JavaScript doubles for this).

const SHIFT_AT := 20000.0
const SEED := 7

var world_offset := Vector3.ZERO
var belt: Belt
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
	ship = Ship.new()
	ship.name = "Ship"
	ship.main = self
	ship.belt = belt
	add_child(ship)
	hud = Hud.new()
	add_child(hud)
	ship.toast.connect(hud.toast)
	# start in the inner belt, flying along it
	world_offset = Vector3(0.0, 0.0, belt.planet_r + 2200.0 * Data.WORLD_SCALE)
	ship.position = Vector3.ZERO
	ship.look_at(Vector3(-1000.0, 0.0, 0.0), Vector3.UP)
	belt.apply_offset(world_offset)
	planet.position = -world_offset
	belt.cull(world_offset)
	ship.update_camera(1.0)
	hud.toast("Welcome aboard · W throttle, mouse steers, hold the left button to cut. R pulses the radar.", false)
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
	hud.update(ship, belt)
	if _smoke:
		_smoke_step()


## `godot --path . -- --smoke`: an unattended run that parks the ship in front of the nearest ore rock, holds the laser on
## it, writes a screenshot to user://smoke.png and prints what happened, then quits. It is how the port gets checked
## from a terminal (the same idea as the browser game's ?debug hook).
var _smoke := false
var _frame := 0
var _smoke_rock := -1


func _smoke_step() -> void:
	_frame += 1
	ship.mouse_steer = false
	if _frame == 30:
		var scan: Dictionary = belt.scan(ship.true_pos(), 120000.0, Data.ORE_KEYS.find("copper"))   # copper: the one ore a level-1 laser cuts
		_smoke_rock = scan["nearest"]
		if _smoke_rock >= 0:
			var rp: Vector3 = belt.pos[_smoke_rock] - world_offset
			var dir := (rp - ship.position).normalized()
			ship.position = rp - dir * (belt.radius[_smoke_rock] + 700.0)
			ship.look_at(rp, Vector3.UP)
			ship.vel = Vector3.ZERO
			ship.update_camera(1.0)
			belt.hp[_smoke_rock] = 45.0   # nearly cut through already, so the run also sees it break and the ore come aboard
			Input.action_press("fire")
		print("smoke: rocks=%d chunks=%d nearest=%s hp=%.0f" % [belt.count, belt._chunk_nodes.size(), belt.rock_name(_smoke_rock) if _smoke_rock >= 0 else "none", belt.hp[_smoke_rock] if _smoke_rock >= 0 else 0.0])
	if _frame == 150:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://smoke.png")
	if _frame == 150 or _frame == 600 or _frame == 1000:
		var hp := belt.hp[_smoke_rock] if _smoke_rock >= 0 else 0.0
		print("smoke: target=%d laser_on=%s rock_hp=%.0f fuel=%.1f cargo=%.0f fps=%.0f" % [ship.target, str(ship.laser_on), hp, State.fuel, State.cargo_total(), Engine.get_frames_per_second()])
	if _frame == 1000:
		var nearest := INF
		for p in pickups.get_children():
			nearest = min(nearest, p.position.distance_to(ship.position))
		print("smoke: pickups=%d nearest=%.0f screenshot %s" % [pickups.get_child_count(), nearest if nearest < INF else -1.0, ProjectSettings.globalize_path("user://smoke.png")])
		get_tree().quit()

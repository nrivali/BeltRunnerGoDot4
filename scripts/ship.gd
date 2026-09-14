class_name Ship
extends Node3D
## The pilot's ship: the browser game's flight model, mining laser, chase camera, the docking with the cargo ship
## (approach control, the hangar, the departure taxi), holding station off the colony at the Hub, and the warp between
## zones. Forward is -Z (Godot's convention; the HTML used +Z). Positions are scene-local; `main.world_offset` turns them
## into true world coordinates for the belt queries, gravity and the carrier's frame.

signal toast(msg: String, bad: bool)
signal docked_changed(is_docked: bool)
signal map_requested

const TURN := 30.0 * PI / 180.0   # yaw and pitch: 30 degrees a second at full deflection
const REPAIR_RATE := 6.0
var _uncover_t := -1.0   # the short covered edit into the hangar after a belt arrival (cameraShots.uncover)

var vel := Vector3.ZERO
var throttle := 0.0
var overcharge := false
var afterburning := false
var thrusting := false
var braking := false
var target := -1
var laser_on := false
var firing := false
var radar_cd := 0.0
var radar_pulsed := false   # for the tutorial: R has been pressed since the step began
var last_scan := {}
var mouse_steer := true   # off in the smoke test, where no one is holding the mouse

# docking
var docked := false
var hold := false          # docked at the Hub's holding station rather than on a hangar pad
var dock_side := 0
var dep_wait := false      # W has to be released once after docking before it departs (you usually fly in holding it)
var exit_pending := false  # just left the hangar: the mouth cannot capture the ship until it is clear of the corridor
var flown_out := false
var cut := {}              # the approach, departure or Hub arrival: mode, pts, t, dur, and per-mode fields
var warp := {}             # the jump between zones: z, t, loaded, skip
var hangar_t := 0.0
var _fuel_dry_warned := false
var _parts_warned := false

var main                  # Main (world_offset, spawn_pickup, load_zone); untyped so its script members resolve
var belt: Belt
var carrier: CargoShip
var cam: Camera3D
var _cam_q := Quaternion.IDENTITY
var _laser: MeshInstance3D
var _hull_mesh: MeshInstance3D
var torch: SpotLight3D
var torch_on := true      # F in flight; not saved, as in the browser


func _ready() -> void:
	_build_body()
	cam = Camera3D.new()
	cam.top_level = true
	cam.near = 2.0
	cam.far = 4000000.0
	cam.fov = 62.0
	cam.current = true
	add_child(cam)
	_laser = MeshInstance3D.new()
	_laser.top_level = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 2.4
	cyl.height = 1.0
	cyl.radial_segments = 6
	_laser.mesh = cyl
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.55, 0.2, 0.85)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.5, 0.15)
	lm.emission_energy_multiplier = 3.0
	_laser.material_override = lm
	_laser.visible = false
	add_child(_laser)
	# the flashlight: the HTML's torch (SpotLight 0xfff1d6, 14000 cd, reach 7000, half-angle pi/8, decay 1), on by default,
	# just below the nose and aimed a touch down. Godot's spot attenuation of 1 is the same 1/d falloff, and its
	# diffuse has no 1/pi, so the energy is the browser's intensity over pi.
	torch = SpotLight3D.new()
	torch.name = "Torch"
	torch.light_color = Color("#fff1d6")
	torch.light_energy = 14000.0 / PI
	torch.spot_range = 7000.0
	torch.spot_attenuation = 1.0
	torch.spot_angle = 22.5
	torch.spot_angle_attenuation = 0.7
	torch.shadow_enabled = false
	torch.position = Vector3(0.0, -1.5, -21.0) * Data.SHIP_SCALE
	torch.look_at_from_position(torch.position, Vector3(0.0, -4.5, -2000.0), Vector3.UP)
	add_child(torch)


const MODEL := "res://assets/ship/player_ship.glb"
var model: Node3D


## Astra's player ship (delta wings, level-1 fittings), built with its nose along +Z as the HTML flies it, so it is turned
## round to face this node's -Z and scaled by SHIP_SCALE like the browser's ship group. The wedge placeholder stands in
## if the model is missing.
func _build_body() -> void:
	var ps = load(MODEL)
	if ps != null:
		model = ps.instantiate()
		model.name = "Model"
		model.scale = Vector3.ONE * Data.SHIP_SCALE
		model.rotation = Vector3(0.0, PI, 0.0)
		add_child(model)
		for n in ["engine_l", "engine_r"]:
			var a := model.find_child(n, true, false)
			if a is Node3D:
				var glow := OmniLight3D.new()
				glow.light_color = Color("#5ed3f0")
				glow.light_energy = 1.2
				glow.omni_range = 40.0
				(a as Node3D).add_child(glow)
		print("ship: model loaded")
		return
	_build_placeholder()


func _build_placeholder() -> void:
	var s := Data.SHIP_SCALE
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.72, 0.70, 0.66)
	hull.metallic = 0.4
	hull.roughness = 0.5
	var body := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(14.0 * s, 26.0 * s, 5.0 * s)   # width, length (the prism's tip is +Y before the turn), thickness
	body.mesh = prism
	body.material_override = hull
	body.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # tip forward (-Z), flat side up
	add_child(body)
	_hull_mesh = body
	for side in [-1.0, 1.0]:
		var pod := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.8 * s
		cyl.bottom_radius = 2.2 * s
		cyl.height = 12.0 * s
		pod.mesh = cyl
		pod.material_override = hull
		pod.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		pod.position = Vector3(side * 7.5 * s, -0.5 * s, 4.0 * s)
		add_child(pod)
		var glow := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.6 * s
		sph.height = 3.2 * s
		glow.mesh = sph
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(0.45, 0.85, 1.0)
		gm.emission_enabled = true
		gm.emission = Color(0.45, 0.85, 1.0)
		gm.emission_energy_multiplier = 4.0
		glow.material_override = gm
		glow.position = Vector3(side * 7.5 * s, -0.5 * s, 10.5 * s)
		add_child(glow)


func forward() -> Vector3:
	return -global_transform.basis.z


func up_dir() -> Vector3:
	return global_transform.basis.y


func true_pos() -> Vector3:
	return position + main.world_offset


func speed() -> float:
	return vel.length()


func heading() -> Quaternion:
	return global_transform.basis.get_rotation_quaternion()


func set_heading(q: Quaternion) -> void:
	transform.basis = Basis(q)


## A level heading along a world direction (yaw only, deck kept level), as the HTML's levelHeading.
static func level_heading(d: Vector3) -> Quaternion:
	var f := d
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	return Basis.looking_at(f.normalized(), Vector3.UP).get_rotation_quaternion()


static func hold_fwd() -> Vector3:
	var d: Vector3 = Data.HOLD_DIR
	return Vector3(d.x, 0.0, d.z).normalized()


static func hold_side() -> Vector3:
	return hold_fwd().cross(Vector3.UP)


static func _shape(v: float) -> float:
	var m := absf(v)
	var dz := 0.06
	if m < dz:
		return 0.0
	var t: float = min(1.0, (m - dz) / (1.0 - dz))
	return signf(v) * t * (0.4 + 0.6 * t)


func in_cinematic() -> bool:
	return not warp.is_empty() or (not cut.is_empty() and cut["mode"] != "depart")


func toggle_torch() -> void:
	torch_on = not torch_on
	toast.emit("Flashlight on" if torch_on else "Flashlight off", false)


func tick(dt: float) -> void:
	torch.visible = torch_on and not docked and warp.is_empty() and visible
	if _uncover_t >= 0.0:
		_uncover_t += dt
		if _uncover_t > 0.5:
			_uncover_t = -1.0
	if not warp.is_empty():
		if Input.is_action_just_pressed("skip"):
			warp["skip"] = true
		_warp_update(dt)
		return
	if not cut.is_empty():
		if Input.is_action_just_pressed("skip"):
			skip_cut()
		_cut_update(dt)
		return
	if docked:
		_dock_update(dt)
		return
	_fly(dt)
	_carrier_contact()
	if docked:
		return
	_tick_laser(dt, forward())
	radar_cd = max(0.0, radar_cd - dt)
	if Input.is_action_just_pressed("radar"):
		_radar()
	if Input.is_action_just_pressed("overcharge"):
		_toggle_overcharge()
	if Input.is_action_just_pressed("torch"):
		toggle_torch()
	if Input.is_action_just_pressed("dock"):
		start_approach()


func skip_cut() -> void:
	if cut.is_empty():
		return
	cut["t"] = cut["dur"]
	if cut["mode"] == "dock":
		cut["phase"] = "settle"
		cut["pt"] = 99.0
	toast.emit("Skipped", false)


func _fly(dt: float) -> void:
	var eng: Dictionary = State.stat("engine")
	# steering: the cursor's offset from screen centre yaws and pitches; A/D roll; arrow keys pitch
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	var sx := (m.x - size.x * 0.5) / (size.x * 0.5)
	var sy := (m.y - size.y * 0.5) / (size.y * 0.5)
	var yaw := -_shape(sx) if mouse_steer else 0.0
	var pitch := -_shape(sy) if mouse_steer else 0.0
	var roll := 0.0
	if Input.is_action_pressed("roll_left"):
		roll += 1.0
	if Input.is_action_pressed("roll_right"):
		roll -= 1.0
	if Input.is_action_pressed("pitch_up"):
		pitch += 1.0
	if Input.is_action_pressed("pitch_down"):
		pitch -= 1.0
	rotate_object_local(Vector3.UP, yaw * TURN * dt)
	rotate_object_local(Vector3.RIGHT, pitch * TURN * dt)
	rotate_object_local(Vector3.BACK, roll * 0.6 * dt)
	transform.basis = transform.basis.orthonormalized()

	# throttle: W raises, S lowers, X cuts; holding S at zero fires the retros
	if Input.is_action_pressed("throttle_up"):
		throttle = min(1.0, throttle + 0.7 * dt)
	if Input.is_action_pressed("throttle_down"):
		throttle = max(0.0, throttle - 0.9 * dt)
	if Input.is_action_pressed("throttle_cut"):
		throttle = 0.0
	var ab_mult: float = State.stat("thrusters")["mult"]
	afterburning = throttle > 0.0 and Input.is_action_pressed("afterburner") and ab_mult > 1.0 and State.fuel > 0.0
	var mult := ab_mult if afterburning else 1.0
	thrusting = false
	braking = false
	var fwd := forward()
	var sp_before := vel.length()
	if State.fuel > 0.0:
		if throttle > 0.0:
			vel += fwd * eng["thrust"] * throttle * mult * dt
			State.fuel = max(0.0, State.fuel - Data.FUEL_BURN * throttle * Data.burn_mult(mult) * dt)
			thrusting = true
		elif Input.is_action_pressed("throttle_down"):
			var sp := vel.length()
			if sp > 1.0:
				var f: float = min(sp, eng["thrust"] * 0.4 * dt)
				vel -= vel / sp * f
				State.fuel = max(0.0, State.fuel - Data.FUEL_BURN * 0.35 * dt)
				braking = true
	# the planet's pull: inverse-square from the surface value, always toward the origin (true coordinates)
	var tp := true_pos()
	var d := tp.length()
	if d > 1.0 and belt.planet_r > 0.0:
		var g: float = Data.GRAVITY_SURFACE * min(1.0, (belt.planet_r / d) * (belt.planet_r / d))
		vel -= tp / d * g * dt
	# drag, then the speed cap (thrust never pushes past it; anything above only falls away on drag)
	var drag_k := 0.32 if throttle > 0.0 else 1.28
	vel *= exp(-drag_k * dt)
	var sp2 := vel.length()
	var lim: float = max(eng["max"] * mult, sp_before * exp(-drag_k * dt))
	if sp2 > lim:
		vel *= lim / sp2
	position += vel * dt
	# the zone edge bounces you back; the planet stops you
	tp = true_pos()
	d = tp.length()
	if d > belt.world_r:
		vel = vel.bounce(tp / d)
		position -= tp / d * (d - belt.world_r)
	elif belt.planet_r > 0.0 and d < belt.planet_r + Data.SHIP_R:
		vel = Vector3.ZERO
		position += tp / d * (belt.planet_r + Data.SHIP_R - d)


# ---- the cargo ship: hangar capture and hull collision (ported from the capture rule and depotCollide)
func _carrier_contact() -> void:
	if carrier == null or carrier.hold:
		return
	var L := carrier.to_local_true(true_pos())
	var rel := vel - carrier.vel
	if not carrier.in_corridor(L):
		exit_pending = false   # fully clear of the bay: capture is armed again
	elif not exit_pending and absf(L.z) < CargoShip.BAY_Z_OUT - 150.0 and rel.length() < 520.0:
		enter_hangar(carrier.entry_side(L, carrier.basis_q.inverse() * rel))
		return
	var c := carrier.collide(L, Data.SHIP_R)
	if c.is_empty():
		return
	position = carrier.to_true(c["pos"]) - main.world_offset
	var n: Vector3 = carrier.dir(c["n"])
	var vn := rel.dot(n)
	if vn < 0.0:
		vel += n * (-vn * 1.4)
		if -vn > 120.0:
			State.hull = max(0.0, State.hull - (-vn - 120.0) * 0.08)   # a hard knock against the hull costs plating


## E near the carrier: approach control flies the ship in by the nearest mouth, along the deck, to a hover over the far
## pad already facing that pad's own mouth, then lets it down. Registered against the far bay.
func start_approach() -> void:
	if docked or not cut.is_empty() or carrier == null or carrier.hold:
		return
	if true_pos().distance_to(carrier.true_pos) >= Data.DOCK_RANGE:
		toast.emit("Too far from the cargo ship for an approach · close to %s m" % Data.fm(Data.DOCK_RANGE), true)
		return
	var l0 := carrier.to_local_true(true_pos())
	var entry := carrier.nearest_side(true_pos())
	var far := -entry
	var app := CargoShip.opening_local(entry) + Vector3(0.0, 0.0, entry * 1400.0)
	var mouth := CargoShip.opening_local(entry)
	var deck := Vector3(0.0, -40.0, 0.0)
	var hover := CargoShip.park_local(far) + Vector3(0.0, 90.0, 0.0)
	var pts: Array = [l0]
	if l0.distance_to(app) > 900.0:
		pts.append(app)
	pts.append(mouth)
	pts.append(deck)
	pts.append(hover)
	var len := _curve_length(pts)
	cut = {"mode": "dock", "side": far, "entry": entry, "pts": pts, "t": 0.0, "dur": clampf(len / 360.0, 6.0, 13.0), "phase": "fly", "pt": 0.0, "hover": hover, "park": CargoShip.park_local(far), "q_end": heading()}
	throttle = 0.0
	laser_on = false
	firing = false
	_laser.visible = false
	Audio.voice(["approach_control", "approach_1", "approach_2", "approach_3", "approach_4"][randi() % 5])   # one of five radio calls
	toast.emit("Approach control has the ship · %s" % CargoShip.bay_name(far), false)


## W on the pad or the Depart button: approach control taxis the ship off the pad and straight out of its own mouth, then
## hands it over already under way. Watched from the chase camera, no cutscene. At the Hub there is no flying: leaving
## means setting a course on the nav map.
func start_departure() -> void:
	if not docked or not cut.is_empty():
		return
	if hold:
		toast.emit("Set a course on the nav map to leave Meridian Colony", false)
		map_requested.emit()
		return
	var b := dock_side
	leave_hangar()
	var pts: Array = [CargoShip.park_local(b), Vector3(0.0, -112.0, b * 620.0), Vector3(0.0, -40.0, b * 1000.0), Vector3(0.0, 60.0, b * 2500.0)]
	cut = {"mode": "depart", "side": b, "pts": pts, "t": 0.0, "dur": 5.2}
	toast.emit("Departing · approach control has the ship · Space skips", false)


## Every arrival at the Hub: the cargo ship comes in from deep space behind its holding point, sweeps wide past the outer
## ring and eases onto station nose toward the hub. The path is in true world coordinates; the ship rides inside.
func start_hold_approach() -> void:
	if docked or not cut.is_empty():
		return
	var p: Vector3 = Data.HOLD_PARK
	var f := hold_fwd()
	var r := hold_side()
	var pts: Array = [carrier.true_pos, p - f * 95000.0 + r * 32000.0 + Vector3(0, 11000, 0), p - f * 34000.0 + r * 4000.0 + Vector3(0, 1500, 0), p]
	if carrier.true_pos.distance_to(pts[1]) < 20000.0:
		pts.remove_at(1)
	var len := _curve_length(pts)
	cut = {"mode": "hold", "pts": pts, "t": 0.0, "dur": clampf(len / 6500.0, 14.0, 28.0)}
	throttle = 0.0
	toast.emit("Arriving · Meridian Colony · Space skips", false)


func _cut_update(dt: float) -> void:
	var C := cut
	C["t"] = float(C["t"]) + dt
	var k: float = min(1.0, float(C["t"]) / float(C["dur"]))
	var mode: String = C["mode"]
	var u: float = (k * k * (2.0 - k) * 0.5 + k * 0.5 * k) if mode == "depart" else k * k * (3.0 - 2.0 * k)
	var pts: Array = C["pts"]
	var p := _curve_point(pts, min(1.0, u))
	var tan := _curve_tangent(pts, min(u, 0.999))
	if mode == "hold":
		# the carrier flies the path; the last stretch blends onto the holding heading
		var q := CargoShip.heading_along(tan)
		if k > 0.9:
			q = q.slerp(CargoShip.heading_along(Data.HOLD_DIR), (k - 0.9) / 0.1)
		carrier.set_pose(p, carrier.basis_q.slerp(q, 1.0 - exp(-1.8 * dt)))
		position = carrier.position
		set_heading(level_heading(carrier.nose()))
		vel = Vector3.ZERO
		if k >= 1.0:
			cut = {}
			carrier.set_pose(Data.HOLD_PARK, CargoShip.heading_along(Data.HOLD_DIR))
			position = carrier.position
			enter_berth()
		return
	if mode == "dock":
		vel = carrier.vel
		if C["phase"] == "fly":
			position = carrier.to_true(p) - main.world_offset
			set_heading(heading().slerp(level_heading(carrier.dir(tan)), 1.0 - exp(-5.0 * dt)))
			if k >= 1.0:
				C["phase"] = "settle"
				C["pt"] = 0.0
				C["q_end"] = heading()
			return
		C["pt"] = float(C["pt"]) + dt
		var tt: float = max(0.0, float(C["pt"]) - 0.5)
		var s: float = min(1.0, tt / 2.5)
		var e := s * s * (3.0 - 2.0 * s)
		var side: int = C["side"]
		var bay_q := level_heading(carrier.dir(CargoShip.face_local(side)))
		position = carrier.to_true((C["hover"] as Vector3).lerp(C["park"], e)) - main.world_offset
		set_heading((C["q_end"] as Quaternion).slerp(bay_q, e))
		if s >= 1.0:
			cut = {}
			enter_hangar(side)
		return
	position = carrier.to_true(p) - main.world_offset
	vel = carrier.vel
	set_heading(heading().slerp(level_heading(carrier.dir(tan)), 1.0 - exp(-5.0 * dt)))
	if k >= 1.0:
		cut = {}
		vel += carrier.dir(tan) * 340.0
		throttle = 0.35
		_cam_q = heading()
		toast.emit("You have the ship", false)


func enter_hangar(side: int) -> void:
	docked = true
	hold = false
	dock_side = side
	throttle = 0.0
	vel = Vector3.ZERO
	target = -1
	laser_on = false
	firing = false
	_laser.visible = false
	dep_wait = true
	exit_pending = false
	hangar_t = 0.0
	cut = {}
	Audio.sfx("dock")
	# the deck welcomes you back over the intercom, one of four announcements, once the clamps have clunked (not on a
	# session's first dock, and not during the tutorial, whose own line for this step would talk over it)
	if flown_out and State.tut < 0:
		get_tree().create_timer(0.8).timeout.connect(func(): if docked and not hold: Audio.intercom("hangar_%d" % (1 + randi() % 4)))
	toast.emit("Docked in %s · stow cargo from the services panel" % CargoShip.bay_name(side), false)
	docked_changed.emit(true)
	State.save_game()


## Holding station off the colony: the carrier is parked, you are aboard, and the market and services are open.
func enter_berth() -> void:
	docked = true
	hold = true
	dock_side = 1
	throttle = 0.0
	vel = Vector3.ZERO
	target = -1
	laser_on = false
	firing = false
	_laser.visible = false
	dep_wait = true
	hangar_t = 0.0
	cut = {}
	Audio.sfx("dock")
	get_tree().create_timer(0.9).timeout.connect(func(): if docked and hold: Audio.voice("colony_control"))
	toast.emit("Holding station off Meridian Colony · the market is open", false)
	docked_changed.emit(true)
	State.save_game()


func leave_hangar() -> void:
	if not docked:
		return
	docked = false
	hold = false
	exit_pending = true
	flown_out = true
	vel = carrier.vel
	_cam_q = heading()
	docked_changed.emit(false)
	State.save_game()


func _dock_update(dt: float) -> void:
	if hold:
		# aboard the carrier at its holding point: it drifts gently on station
		var t := State.time
		var drift := Vector3(sin(t * 0.21) * 320.0, sin(t * 0.17) * 240.0, cos(t * 0.13) * 320.0)
		var k := 1.0 - exp(-0.4 * dt)
		carrier.set_pose(carrier.true_pos.lerp(Data.HOLD_PARK + drift, k), carrier.basis_q)
		position = carrier.position
		set_heading(level_heading(carrier.nose()))
		vel = Vector3.ZERO
	else:
		# settle onto the pad and stay there, nose out of the mouth, riding along with the carrier
		var park: Vector3 = carrier.to_true(CargoShip.park_local(dock_side)) - main.world_offset
		var k2 := 1.0 - exp(-1.4 * dt)
		position = position.lerp(park, k2)
		set_heading(heading().slerp(level_heading(carrier.dir(CargoShip.face_local(dock_side))), k2))
		vel = carrier.vel
	# the tank fills from the cargo ship's supply for free; the hull mends from its repair parts, one part per point
	var tank: float = State.stat("tank")["cap"]
	if State.fuel < tank:
		var rate := 8.0 + 4.0 * float(State.up["tank"])
		var u: float = min(rate * dt, tank - State.fuel, State.ship_fuel)
		if u > 0.0:
			State.fuel += u
			State.ship_fuel -= u
		elif State.ship_fuel < 0.5 and not _fuel_dry_warned:
			_fuel_dry_warned = true
			toast.emit("Cargo ship fuel supply is dry · refuel at the Hub", true)
	var hp: float = State.stat("hull")["hp"]
	if State.hull < hp:
		var u2: float = min(REPAIR_RATE * dt, hp - State.hull, State.parts)
		if u2 > 0.0:
			State.hull += u2
			State.parts -= u2
		elif State.parts < 0.5 and not _parts_warned:
			_parts_warned = true
			toast.emit("No repair parts left · restock at the Hub", true)
	# W departs, once it has been released since docking; E deposits the hold into the storage
	if not Input.is_action_pressed("throttle_up"):
		dep_wait = false
	elif not dep_wait:
		dep_wait = true
		start_departure()
	if Input.is_action_just_pressed("dock"):
		deposit_all()


func deposit_all() -> void:
	var had := State.cargo_total()
	var moved := State.stow_all()
	if moved < 0.5:
		toast.emit("Cargo ship storage is full" if had > 0.5 else "Nothing in the hold to stow", true)
		return
	Audio.sfx("stow")
	toast.emit("Stowed %d aboard the cargo ship%s" % [roundi(moved), " · storage full, the rest stays in the hold" if State.cargo_total() > 0.5 else ""], false)
	State.save_game()
	docked_changed.emit(true)   # the panel re-reads the hold


func take_all() -> void:
	var moved := State.take_all()
	if moved < 0.5:
		toast.emit("No room in the hold" if State.store_total() > 0.5 else "Storage is empty", true)
		return
	Audio.sfx("stow")
	toast.emit("Took %d back aboard" % roundi(moved), false)
	State.save_game()
	docked_changed.emit(true)


# ---- the market, only while holding station at the Hub
func sell(keys: Array, from_hold: bool, from_store: bool) -> void:
	var r: Dictionary = State.sell(keys, from_hold, from_store)
	if r["units"] < 0.5:
		toast.emit("Nothing to sell", true)
		return
	Audio.sfx("cash")
	toast.emit("Sold %d · +%s cr" % [roundi(r["units"]), Data.fmt(r["credits"])], false)
	docked_changed.emit(true)


func refuel_cargo_ship() -> void:
	var r: Dictionary = State.refuel_cargo_ship()
	if r["units"] < 1.0:
		toast.emit(r["msg"], true)
		return
	_fuel_dry_warned = false
	toast.emit("Refuelled %d · %s cr%s" % [floori(r["units"]), Data.fmt(r["cost"]), " · out of credits before full" if r["partial"] else ""], false)
	docked_changed.emit(true)


func buy_parts() -> void:
	var r: Dictionary = State.buy_parts()
	if r["units"] < 1.0:
		toast.emit(r["msg"], true)
		return
	_parts_warned = false
	toast.emit("Restocked %d repair parts · %s cr%s" % [roundi(r["units"]), Data.fmt(r["cost"]), " · out of credits before full" if r["partial"] else ""], false)
	docked_changed.emit(true)


# ---- the warp: the cargo ship makes the jump, so you have to be aboard it. A held exterior shot, a fade to black while
# the zone swaps underneath, then the arrival (the Hub: the holding-station flight; a belt: on the pad in the dock that
# faces the planet). The HTML's hyperspace tunnel is not ported yet.
func start_warp(z: Dictionary) -> void:
	if not warp.is_empty():
		return
	if not docked:
		toast.emit("Dock with the cargo ship before warping · it makes the jump", true)
		return
	if z["id"] == main.zone["id"]:
		return
	warp = {"z": z, "t": 0.0, "loaded": false, "skip": false, "from_hold": hold, "pose": Hyperspace.sample(0.0), "voiced": false, "jumped": false, "ly": Data.zone_ly(main.zone, z)}
	docked_changed.emit(false)
	Audio.sfx("chime")
	Audio.sfx("warp_charge")
	toast.emit("Jump · %s · %s ly · Space skips" % [z["name"], str(Data.zone_ly(main.zone, z))], false)


## 0 = clear, 1 = black: the HUD's fade. The tunnel hides the zone swap itself; the fade is the covered edit from the
## exterior shot into the hangar at the end of a belt arrival, and the uncover once the ship is on its pad.
func warp_fade() -> float:
	if not warp.is_empty():
		var z: Dictionary = warp["z"]
		if z["hub"] or warp["skip"]:
			return 0.0
		return Hyperspace.cover(float(warp["t"]))
	if _uncover_t >= 0.0:
		return Hyperspace.uncover(_uncover_t)
	return 0.0


## The jump (warpCutUpdate): the charge, the warp_ready call, the jump itself, the zone swap under the opaque tunnel,
## the carrier's stretch and offset, then the arrival; Space skips straight to the arrival.
func _warp_update(dt: float) -> void:
	var W := warp
	W["t"] = float(W["t"]) + dt
	var t: float = W["t"]
	var pose := Hyperspace.sample(t)
	W["pose"] = pose
	var z: Dictionary = W["z"]
	if not W["skip"] and not W["voiced"] and t >= 0.4:
		W["voiced"] = true
		Audio.voice("warp_ready")
	if not W["skip"] and not W["jumped"] and t >= Hyperspace.CHARGE:
		W["jumped"] = true
		Audio.sfx("warp_jump")
	if not W["loaded"] and (W["skip"] or t >= Hyperspace.TRANSIT_AT):
		W["loaded"] = true
		docked = false
		hold = false
		cut = {}
		main.warp_load(z)   # swaps the zone and places the carrier and ship for the arrival; the tunnel is opaque here
	carrier.set_warp_pose(float(pose["offset"]), float(pose["stretch"]), float(pose["gain"]))
	if W["skip"] or bool(pose["done"]):
		carrier.clear_warp_pose()
		main.hyperspace.reset()
		cam.fov = 62.0
		if not z["hub"] and not W["skip"]:
			_uncover_t = 0.0
		warp = {}
		main.warp_done(z)


# ---- a uniform Catmull-Rom spline through the taxi waypoints (the HTML used three.js's centripetal variant)
static func _curve_point(pts: Array, u: float) -> Vector3:
	var n := pts.size() - 1
	var f: float = clampf(u, 0.0, 0.9999) * n
	var i := int(floor(f))
	var t := f - i
	var p0: Vector3 = pts[max(i - 1, 0)]
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[min(i + 1, n)]
	var p3: Vector3 = pts[min(i + 2, n)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


static func _curve_tangent(pts: Array, u: float) -> Vector3:
	var a := _curve_point(pts, max(0.0, u - 0.004))
	var b := _curve_point(pts, min(1.0, u + 0.004))
	var d := b - a
	return d.normalized() if d.length_squared() > 1e-9 else Vector3.FORWARD


static func _curve_length(pts: Array) -> float:
	var len := 0.0
	var prev := _curve_point(pts, 0.0)
	for i in range(1, 65):
		var p := _curve_point(pts, i / 64.0)
		len += prev.distance_to(p)
		prev = p
	return len


# ---- the mining laser
func _tick_laser(dt: float, fwd: Vector3) -> void:
	firing = Input.is_action_pressed("fire")
	var reach: float = State.stat("range")["reach"]
	var origin := true_pos() + fwd * 20.0
	target = belt.ray_hit(origin, fwd, reach)
	laser_on = false
	_laser.visible = false
	if not firing:
		return
	var end := origin + fwd * reach
	if target >= 0:
		var oc: float = State.stat("overcharge")["mult"] if (overcharge and State.fuel > 0.0) else 1.0
		var can_cut: bool = belt.ore[target] < 0 or int(Data.ORES[Data.ORE_KEYS[belt.ore[target]]]["unlock"]) <= int(State.up["laser"]) + 1
		end = belt.pos[target] - (belt.pos[target] - origin).normalized() * belt.radius[target] * 0.85
		if can_cut:
			laser_on = true
			var rate: float = State.stat("laser")["rate"] * oc
			belt.damage(target, rate * 5.0 * dt)
			if oc > 1.0:
				State.fuel = max(0.0, State.fuel - Data.OVER_BURN * oc * dt)
				if State.fuel <= 0.0:
					overcharge = false
					toast.emit("Overcharge off · fuel tank dry", true)
			if belt.hp[target] <= 0.0:
				_break(target)
				target = -1
	# the beam: a thin cylinder from the nose to wherever the ray ends, in scene space
	var a := position + fwd * 20.0
	var b: Vector3 = end - main.world_offset
	var mid: Vector3 = (a + b) * 0.5
	var len := a.distance_to(b)
	if len > 1.0:
		_laser.visible = true
		_laser.global_position = mid
		_laser.look_at(b, up_dir())
		_laser.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
		_laser.scale = Vector3(1.0, len, 1.0)


func _break(i: int) -> void:
	main.break_rock(i, false)


func _radar() -> void:
	if radar_cd > 0.0:
		return
	radar_cd = Data.PULSE_CD
	radar_pulsed = true
	Audio.sfx("radar_ping")
	var range: float = State.stat("scanner")["range"]
	last_scan = belt.scan(true_pos(), range)
	if last_scan["count"] == 0:
		toast.emit("Radar: no ore within %s m" % Data.fm(range), true)
	else:
		var n: int = last_scan["nearest"]
		toast.emit("Radar: %d ore rocks within %s m · nearest %s at %s m" % [last_scan["count"], Data.fm(range), belt.rock_name(n), Data.fm(last_scan["dist"])], false)


func _toggle_overcharge() -> void:
	var m: float = State.stat("overcharge")["mult"]
	if m <= 1.0:
		toast.emit("No laser overcharge fitted · it is a refit in the cargo ship services", true)
		return
	overcharge = not overcharge
	Audio.sfx("chime")
	if overcharge:
		toast.emit("Laser overcharge armed · ×%s damage · draws %.1f fuel/s while cutting" % [str(m), Data.OVER_BURN * m], false)
	else:
		toast.emit("Laser overcharge off", false)


# ---- cameras
## The chase camera in flight and during the departure taxi; a camera by the entry mouth during the approach; on the pad
## a slow walk round the ship inside the bay; behind the carrier on the Hub arrival and at its holding point; an exterior
## shot of the carrier during a jump.
func update_camera(dt: float) -> void:
	var s := Data.SHIP_SCALE
	if not warp.is_empty():
		# the exterior shot: behind and beside the carrier as it charges and jumps, ahead of it as it arrives
		var arriving: bool = warp["loaded"]
		var pose: Dictionary = warp["pose"]
		if arriving:
			_carrier_shot(Vector3(12500.0, 3600.0, 7200.0), Vector3(600.0, 0.0, 0.0))
		else:
			_carrier_shot(Vector3(-12000.0, 3200.0, 6900.0), Vector3(2400.0, 0.0, 0.0))
		cam.fov = float(pose["fov"])
		main.hyperspace.update(pose, float(warp["t"]), cam, carrier.nose())
		return
	if not cut.is_empty():
		var mode: String = cut["mode"]
		if mode == "hold":
			_carrier_shot(Vector3(-12500.0, 3600.0, 7200.0), Vector3(600.0, 0.0, 0.0))
			return
		if mode == "dock":
			var entry: int = cut["entry"]
			if cut["phase"] == "fly":
				var cp: Vector3 = carrier.to_true(Vector3(760.0, 320.0, entry * 1750.0)) - main.world_offset
				cam.global_position = cp
				cam.look_at(position + forward() * 60.0, Vector3.UP)
				return
			_hangar_camera(dt)
			return
	if docked:
		if hold:
			_holding_camera(dt)
		else:
			_hangar_camera(dt)
		return
	var q := heading()
	_cam_q = _cam_q.slerp(q, 1.0 - exp(-7.0 * dt)).normalized()
	var b := Basis(_cam_q)
	var f := -b.z
	var u := b.y
	var cam_pos := position - f * 88.0 * s + u * 30.0 * s
	var look := position + f * 140.0 * s + u * 10.0 * s
	cam.global_position = cam_pos
	cam.look_at(look, u)


## A camera fixed in the carrier's frame (offsets along nose, up, side), looking at a point ahead of it.
func _carrier_shot(offset: Vector3, look_ahead: Vector3) -> void:
	var nose := carrier.nose()
	var up := carrier.basis_q * Vector3.UP
	var side := carrier.basis_q * Vector3.BACK
	var cp: Vector3 = carrier.position + nose * offset.x + up * offset.y + side * offset.z
	cam.global_position = cp
	cam.look_at(carrier.position + nose * look_ahead.x + up * look_ahead.y + side * look_ahead.z, Vector3.UP)


func _hangar_camera(dt: float) -> void:
	hangar_t += dt
	var a := hangar_t * 0.16
	var side := dock_side if dock_side != 0 else int(cut.get("side", 1))
	var park := CargoShip.park_local(side)
	var cam_l := Vector3(190.0 * cos(a), park.y + 56.0 + 28.0 * sin(a * 0.7), park.z + 250.0 * sin(a))
	cam.global_position = carrier.to_true(cam_l) - main.world_offset
	cam.look_at(position + carrier.dir(Vector3(0.0, 6.0, 0.0)), carrier.dir(Vector3.UP))
	_cam_q = heading()


## Holding station: a slow swing round the carrier with the colony beyond it (the HTML's holding shot).
func _holding_camera(dt: float) -> void:
	hangar_t += dt
	var f := hold_fwd()
	var r := hold_side()
	var c: Vector3 = carrier.position
	cam.global_position = c - f * 15500.0 + r * (7000.0 + sin(hangar_t * 0.04) * 3500.0) + Vector3(0, 7000, 0)
	cam.look_at(c + f * 22000.0 + Vector3(0, -11000, 0), Vector3.UP)
	_cam_q = heading()


## Called by Main after a floating-origin shift so the smoothed camera does not lag a frame behind.
func on_shift(delta: Vector3) -> void:
	cam.global_position -= delta

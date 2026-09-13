class_name Ship
extends Node3D
## The pilot's ship: the browser game's flight model, mining laser and chase camera. Forward is -Z (Godot's convention;
## the HTML used +Z). Positions are scene-local; `main.world_offset` turns them into true world coordinates for the belt
## queries and gravity.

signal toast(msg: String, bad: bool)

const TURN := 30.0 * PI / 180.0   # yaw and pitch: 30 degrees a second at full deflection

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
var last_scan := {}
var mouse_steer := true   # off in the smoke test, where no one is holding the mouse

var main                  # Main (world_offset, spawn_pickup); untyped so its script members resolve
var belt: Belt
var cam: Camera3D
var _cam_q := Quaternion.IDENTITY
var _laser: MeshInstance3D
var _hull_mesh: MeshInstance3D


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


## A placeholder hull until the Blender ship comes across: a wedge body, two engine pods and a canopy.
func _build_body() -> void:
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


static func _shape(v: float) -> float:
	var m := absf(v)
	var dz := 0.06
	if m < dz:
		return 0.0
	var t: float = min(1.0, (m - dz) / (1.0 - dz))
	return signf(v) * t * (0.4 + 0.6 * t)


func tick(dt: float) -> void:
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
	if d > 1.0:
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
	elif d < belt.planet_r + Data.SHIP_R:
		vel = Vector3.ZERO
		position += tp / d * (belt.planet_r + Data.SHIP_R - d)

	_tick_laser(dt, fwd)
	radar_cd = max(0.0, radar_cd - dt)
	if Input.is_action_just_pressed("radar"):
		_radar()
	if Input.is_action_just_pressed("overcharge"):
		_toggle_overcharge()


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
	var rname := belt.rock_name(i)
	var ore_i := belt.ore[i]
	var at: Vector3 = belt.pos[i] - main.world_offset
	var r := belt.radius[i]
	var loose := belt.kill(i)
	if ore_i >= 0 and loose > 0.0:
		var k: int = clampi(roundi(loose / 40.0), 1, 8)
		var ore_key: String = Data.ORE_KEYS[ore_i]
		for n in k:
			var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			main.spawn_pickup(ore_key, loose / k, at + dir * r * randf_range(0.1, 0.5), dir * randf_range(20.0, 60.0))
		toast.emit("%s broken · %d %s loose" % [rname, roundi(loose), Data.ORES[ore_key]["name"]], false)
	else:
		toast.emit("%s broken · scrap only" % rname, false)


func _radar() -> void:
	if radar_cd > 0.0:
		return
	radar_cd = Data.PULSE_CD
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
	if overcharge:
		toast.emit("Laser overcharge armed · ×%s damage · draws %.1f fuel/s while cutting" % [str(m), Data.OVER_BURN * m], false)
	else:
		toast.emit("Laser overcharge off", false)


## The chase camera: rigidly offset from the ship, orientation smoothed so turns feel soft (the HTML's flight camera).
func update_camera(dt: float) -> void:
	var q := global_transform.basis.get_rotation_quaternion()
	_cam_q = _cam_q.slerp(q, 1.0 - exp(-7.0 * dt)).normalized()
	var b := Basis(_cam_q)
	var f := -b.z
	var u := b.y
	var s := Data.SHIP_SCALE
	var cam_pos := position - f * 88.0 * s + u * 30.0 * s
	var look := position + f * 140.0 * s + u * 10.0 * s
	cam.global_position = cam_pos
	cam.look_at(look, u)


## Called by Main after a floating-origin shift so the smoothed camera does not lag a frame behind.
func on_shift(delta: Vector3) -> void:
	cam.global_position -= delta

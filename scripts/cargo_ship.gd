class_name CargoShip
extends Node3D
## The pilot's cargo ship: the carrier with the through-hangar. Ported from DEPOT / STATION / placeDepot / depotCollide in
## belt-runner-3d.html. Its local frame is the HTML's: the keel runs along X with the nose at +X, decks stack in Y, and
## the hangar runs straight through the hull along Z, open on both flanks. Each "bay" is one mouth of that hangar; a ship
## docks on the pad just inside the FAR mouth, parked facing that mouth, so it leaves straight ahead without turning.
## The carrier orbits the planet at DEPOT_ORBIT; `true_pos` is its world position and the node sits at true_pos minus
## the floating origin. Geometry below is the placeholder hull until the Blender carrier is brought across.

const HALF := Vector3(3700.0, 540.0, 900.0)   # the hull's collision box
const PROW_X0 := 3700.0
const PROW_X1 := 4600.0
const PROW_R0 := 800.0
const BAY_X0 := -420.0
const BAY_X1 := 420.0
const BAY_Y0 := -150.0   # the model's deck is the collision floor
const BAY_Y1 := 176.0
const BAY_Z_OUT := 900.0

var true_pos := Vector3.ZERO
var vel := Vector3.ZERO
var basis_q := Quaternion.IDENTITY
var ang := PI / 2.0
var orbit := Data.DEPOT_ORBIT
var speed := Data.STATION_SPEED
var hold := false   # at the Hub the carrier does not orbit: it is flown to its holding point and parked there
var main   # Main, for world_offset


## The carrier heading whose nose (+X) points along a world direction, deck level.
static func heading_along(d: Vector3) -> Quaternion:
	var f := Vector3(d.x, 0.0, d.z)
	if f.length_squared() < 1e-6:
		f = Vector3.FORWARD
	return Basis.looking_at(f.normalized(), Vector3.UP).get_rotation_quaternion() * Quaternion(Vector3.UP, PI / 2.0)


func nose() -> Vector3:
	return basis_q * Vector3.RIGHT


## Put the carrier somewhere by hand (the Hub arrival flies it along a path; holding station parks it).
func set_pose(p_true: Vector3, q: Quaternion) -> void:
	true_pos = p_true
	basis_q = q
	position = true_pos - main.world_offset
	transform.basis = Basis(basis_q)


## A bay by its side (+1 or -1): where its pad and mouth are, in the carrier's frame. The pad sits just inside its own
## mouth (the model's pad_pos / pad_neg markers, 38 above the marker so the hull rests on the deck), facing that mouth.
static func park_local(side: int) -> Vector3:
	return Vector3(0.0, -100.0, side * 525.0)


static func opening_local(side: int) -> Vector3:
	return Vector3(0.0, 0.0, side * 1000.0)


## The direction a ship parked in this bay faces: out of its own mouth.
static func face_local(side: int) -> Vector3:
	return Vector3(0.0, 0.0, float(side))


static func bay_name(side: int) -> String:
	return "Dock 1" if side > 0 else "Dock 2"


const MODEL := "res://assets/carrier/cargo_carrier.glb"
var model: Node3D
var anchors := {}

# the mining dish on the mast: the model's own yaw and pitch rig, slewed onto rocks by the cargo ship laser upgrade
var dish_yaw: Node3D
var dish_pitch: Node3D
var pivot := Vector3(-40.0, 995.0, 0.0)     # dish_mount
var pitch_off := Vector3(40.0, 0.0, 0.0)    # the pitch group's offset from the yaw pivot
var focus_local := Vector3(158.0, 105.0, 0.0)   # the beam's origin within the pitch group
var dish := {"rock": -1, "yaw": 0.0, "pitch": 0.15, "firing": false, "retarget": 0.0, "hit": Vector3.ZERO}
var _beam: MeshInstance3D


func _ready() -> void:
	if not _load_model():
		_build_hull()


var _engine_lights: Array = []


## The hyperspace pose, applied to the rendered hull only (the HTML moves and stretches the station group the same way):
## pushed forward along the nose and stretched from the engines, never back toward the camera; the engine glows gain.
func set_warp_pose(offset: float, stretch: float, gain: float) -> void:
	if model:
		model.position = Vector3(offset + (stretch - 1.0) * 3550.0, 0.0, 0.0)
		model.scale = Vector3(stretch, 1.0, 1.0)
	for l in _engine_lights:
		l.light_energy = 3.0 * gain
		l.omni_range = 900.0 * min(2.0, gain)


func clear_warp_pose() -> void:
	set_warp_pose(0.0, 1.0, 1.0)


## Astra's carrier: the hull, interior, glass and emissive meshes plus named markers (pads, mouths, engines, dish mount,
## drone docks, drop pad, bridge windows), all in this node's frame (nose +X, hangar along Z). Two warm lights inside
## the hangar and the engine glows are added here, as the HTML does on install.
func _load_model() -> bool:
	var ps = load(MODEL)
	if ps == null:
		return false
	model = ps.instantiate()
	model.name = "Model"
	add_child(model)
	for n in ["hangar_mouth_pos", "hangar_mouth_neg", "pad_pos", "pad_neg", "drop_pad", "dish_mount", "engine_0", "engine_1", "engine_2", "drone_dock_0", "drone_dock_1", "drone_dock_2", "bridge_windows"]:
		var a := model.find_child(n, true, false)
		if a is Node3D:
			anchors[n] = (a as Node3D).position
	for z in [-525.0, 525.0]:
		# the HTML's warm hangar lamps: PointLight 0xffc98c, 2600 cd, reach 1150, decay 1.25. Godot's attenuation of 1.25
		# is the same 1/d^1.25 falloff and its diffuse has no 1/pi, so the energy is the browser's intensity over pi.
		var inner := OmniLight3D.new()
		inner.light_color = Color("#ffc98c")
		inner.light_energy = 2600.0 / PI
		inner.omni_range = 1150.0
		inner.omni_attenuation = 1.25
		inner.position = Vector3(0, 130, z)
		add_child(inner)
	for i in 3:
		var e: Vector3 = anchors.get("engine_%d" % i, Vector3(-3480, 0, 0))
		var glow := OmniLight3D.new()
		glow.light_color = Color("#5ed3f0")
		glow.light_energy = 3.0
		glow.omni_range = 900.0
		glow.position = e + Vector3(-100, 0, 0)
		model.add_child(glow)   # under the model, so the hyperspace stretch carries the engine glows with the hull
		_engine_lights.append(glow)
	var dy := model.find_child("dish_yaw", true, false)
	var dp := model.find_child("dish_pitch", true, false)
	var fc := model.find_child("focus", true, false)
	if dy is Node3D and dp is Node3D:
		dish_yaw = dy
		dish_pitch = dp
		pivot = dish_yaw.position
		pitch_off = dish_pitch.position
		if fc is Node3D:
			focus_local = (fc as Node3D).position
	_beam = MeshInstance3D.new()
	_beam.top_level = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 5.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	_beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 0.77, 0.4, 0.85)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.7, 0.3)
	bm.emission_energy_multiplier = 3.0
	_beam.material_override = bm
	_beam.visible = false
	add_child(_beam)
	print("carrier: model loaded, %d anchors, dish rig %s" % [anchors.size(), "found" if dish_yaw else "missing"])
	return true


# ---- the mast dish (the cargo ship mining laser upgrade), ported from updateDepot
## The yaw and pitch that would point the dish at a carrier-local point.
func turret_angles(local: Vector3) -> Vector2:
	var L := local - pivot
	return Vector2(atan2(-L.z, L.x), atan2(L.y - pitch_off.y, Vector2(L.x, L.z).length() - pitch_off.x))


## Where the beam starts, in the carrier's frame, for a given yaw and pitch.
func muzzle_local(yaw: float, pitch: float) -> Vector3:
	var f := focus_local.rotated(Vector3.BACK, pitch) + pitch_off
	return f.rotated(Vector3.UP, yaw) + pivot


static func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


## Reachable: within the pitch limits, and the beam from the mast top must not pass through the carrier's own hull box.
func _in_arc(ang: Vector2, local: Vector3) -> bool:
	if ang.y < Data.TURRET_PITCH_MIN or ang.y > Data.TURRET_PITCH_MAX:
		return false
	var origin := muzzle_local(ang.x, ang.y)
	var d := local - origin
	var len := d.length()
	if len < 1e-3:
		return false
	d /= len
	var s := 0.0
	while s < min(len, 7000.0):
		var p := origin + d * s
		if absf(p.x) < HALF.x and absf(p.y) < HALF.y and absf(p.z) < HALF.z:
			return false
		s += 150.0
	return true


## Slew onto the nearest ore rock the dish's level can open, fire once both axes are within a degree or so, cut it, and
## leave its ore adrift for the collector drones (or the ship) to gather.
func tick_dish(dt: float, belt: Belt) -> void:
	if dish_yaw == null:
		return
	var L = Data.DEPOT_UPGRADES["laser"]["levels"][State.depot["laser"]]
	var D := dish
	var slew := func(cur: float, want: float) -> float:
		return cur + clampf(want - cur, -Data.TURRET_SLEW * dt, Data.TURRET_SLEW * dt)
	var slew_yaw := func(cur: float, want: float) -> float:
		return _wrap(cur + clampf(_wrap(want - cur), -Data.TURRET_SLEW * dt, Data.TURRET_SLEW * dt))
	_beam.visible = false
	if L == null:
		D["rock"] = -1
		D["firing"] = false
		D["yaw"] = slew_yaw.call(D["yaw"], 0.0)
		D["pitch"] = slew.call(D["pitch"], 0.15)
	else:
		var range: float = L["range"]
		D["retarget"] = float(D["retarget"]) - dt
		var rock: int = D["rock"]
		if rock >= belt.count:
			rock = -1   # the belt was rebuilt under it (a zone change)
		if rock >= 0 and (belt.alive[rock] == 0 or belt.pos[rock].distance_to(true_pos) > range * 1.15):
			rock = -1
		if rock < 0 and float(D["retarget"]) <= 0.0:
			D["retarget"] = 0.6
			var best := -1
			var bd := range * range
			var scan: Dictionary = belt.scan(true_pos, range)
			if scan["count"] > 0:
				for ci in belt._chunk_centre.size():
					if (belt._chunk_centre[ci] as Vector3).distance_squared_to(true_pos) > (range + Belt.CHUNK * 0.87) * (range + Belt.CHUNK * 0.87):
						continue
					for i in belt._chunk_rocks[ci]:
						if belt.alive[i] == 0 or belt.ore[i] < 0 or belt.amount[i] <= 0.05:
							continue
						if int(Data.ORES[Data.ORE_KEYS[belt.ore[i]]]["unlock"]) > int(State.depot["laser"]) + 1:
							continue   # the dish only works ores its own level has opened
						var d2 := belt.pos[i].distance_squared_to(true_pos)
						if d2 >= bd:
							continue
						var local := to_local_true(belt.pos[i])
						if not _in_arc(turret_angles(local), local):
							continue
						bd = d2
						best = i
			rock = best
			D["firing"] = false
		D["rock"] = rock
		if rock >= 0:
			var local := to_local_true(belt.pos[rock])
			var want := turret_angles(local)
			if not _in_arc(want, local):
				D["rock"] = -1
				D["firing"] = false
			else:
				D["yaw"] = slew_yaw.call(D["yaw"], want.x)
				D["pitch"] = slew.call(D["pitch"], want.y)
				var err: float = max(absf(_wrap(want.x - float(D["yaw"]))), absf(want.y - float(D["pitch"])))
				D["firing"] = not (err > (0.06 if D["firing"] else 0.02))
				if D["firing"]:
					var muzzle := to_true(muzzle_local(D["yaw"], D["pitch"]))
					var hit: Vector3 = belt.pos[rock] + (muzzle - belt.pos[rock]).normalized() * belt.radius[rock] * 0.85
					D["hit"] = hit
					belt.damage(rock, float(L["rate"]) * 5.0 * dt)
					if belt.hp[rock] <= 0.0:
						main.break_rock(rock, true)
						D["rock"] = -1
						D["firing"] = false
					else:
						var a: Vector3 = muzzle - main.world_offset
						var b: Vector3 = hit - main.world_offset
						var mid: Vector3 = (a + b) * 0.5
						var len: float = a.distance_to(b)
						if len > 1.0:
							_beam.visible = true
							_beam.global_position = mid
							_beam.look_at(b, Vector3.UP)
							_beam.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
							_beam.scale = Vector3(1.0, len, 1.0)
		else:
			D["firing"] = false
			D["yaw"] = slew_yaw.call(D["yaw"], 0.0)
			D["pitch"] = slew.call(D["pitch"], 0.15)
	dish_yaw.rotation = Vector3(0.0, D["yaw"], 0.0)
	dish_pitch.rotation = Vector3(0.0, 0.0, D["pitch"])


func dish_stats() -> Dictionary:
	return {"rock": dish["rock"], "firing": dish["firing"], "yaw": snappedf(dish["yaw"], 0.01), "pitch": snappedf(dish["pitch"], 0.01)}


func to_local_true(p_true: Vector3) -> Vector3:
	return basis_q.inverse() * (p_true - true_pos)


func to_true(local: Vector3) -> Vector3:
	return basis_q * local + true_pos


func dir(local: Vector3) -> Vector3:
	return basis_q * local


## Advance the orbit and refresh the node. Returns how far the carrier moved this frame (a docked ship rides along).
func tick(dt: float) -> Vector3:
	if hold:
		vel = Vector3.ZERO
		place()
		return Vector3.ZERO
	var prev := true_pos
	ang -= (speed / orbit) * dt
	place()
	vel = (true_pos - prev) / max(dt, 1e-4)
	return true_pos - prev


func place() -> void:
	if not hold:
		true_pos = Vector3(cos(ang) * orbit, 0.0, sin(ang) * orbit)
		basis_q = Quaternion(Vector3.UP, PI / 2.0 - ang)   # nose (+X) along the direction of travel
	position = true_pos - main.world_offset
	transform.basis = Basis(basis_q)


## Inside the through-hangar corridor?
func in_corridor(local: Vector3) -> bool:
	return local.x > BAY_X0 - 16.0 and local.x < BAY_X1 + 16.0 and local.y > BAY_Y0 - 16.0 and local.y < BAY_Y1 + 16.0 and absf(local.z) < BAY_Z_OUT + 16.0


## The mouth a ship came in by, from its travel direction in the carrier's frame (falls back to which half it is in).
func entry_side(local: Vector3, rel_vel_local: Vector3) -> int:
	if absf(rel_vel_local.z) > 5.0:
		return -int(signf(rel_vel_local.z))
	return int(signf(local.z)) if local.z != 0.0 else 1


## The mouth nearer to a world point.
func nearest_side(p_true: Vector3) -> int:
	var d1 := to_true(opening_local(1)).distance_squared_to(p_true)
	var d2 := to_true(opening_local(-1)).distance_squared_to(p_true)
	return 1 if d1 <= d2 else -1


## The bay whose mouth faces the planet (the origin): every start is on that pad, so the first departure heads for the belt.
func planet_side() -> int:
	var to_planet := (-true_pos).normalized()
	return 1 if dir(face_local(1)).dot(to_planet) >= dir(face_local(-1)).dot(to_planet) else -1


## Collision with the hull for a ship of radius m at carrier-local position p. Inside the hangar corridor the ship is
## clamped to the walls; anywhere else inside the hull it is pushed out through the nearest face; the prow is a cone.
## Returns {} for no contact, else {pos: corrected local position, n: local surface normal}.
func collide(p: Vector3, m: float) -> Dictionary:
	if p.x > PROW_X0 and p.x < PROW_X1:
		var rr := Vector2(p.y, p.z).length()
		var allow := PROW_R0 * (PROW_X1 - p.x) / (PROW_X1 - PROW_X0) + m
		if rr < allow:
			var n := Vector3(0.0, 1.0, 0.0) if rr < 1e-3 else Vector3(0.0, p.y / rr, p.z / rr)
			return {"pos": Vector3(p.x, n.y * allow, n.z * allow), "n": n}
		return {}
	if absf(p.x) > HALF.x + m or absf(p.y) > HALF.y + m or absf(p.z) > HALF.z + m:
		return {}
	if in_corridor(p):
		var lx: float = clampf(p.x, BAY_X0 + m, BAY_X1 - m)
		var ly: float = clampf(p.y, BAY_Y0 + m, BAY_Y1 - m)
		var n := Vector3(lx - p.x, ly - p.y, 0.0)
		var len := n.length()
		if len < 1e-6:
			return {}
		return {"pos": Vector3(lx, ly, p.z), "n": n / len}
	var dxs := HALF.x + m - absf(p.x)
	var dys := HALF.y + m - absf(p.y)
	var dzs := HALF.z + m - absf(p.z)
	var q := p
	var nn: Vector3
	if dys <= dxs and dys <= dzs:
		nn = Vector3(0.0, signf(p.y) if p.y != 0.0 else 1.0, 0.0)
		q.y = nn.y * (HALF.y + m)
	elif dzs <= dxs:
		nn = Vector3(0.0, 0.0, signf(p.z) if p.z != 0.0 else 1.0)
		q.z = nn.z * (HALF.z + m)
	else:
		nn = Vector3(signf(p.x) if p.x != 0.0 else 1.0, 0.0, 0.0)
		q.x = nn.x * (HALF.x + m)
	return {"pos": q, "n": nn}


# ---- the placeholder hull: decks, mid-band slabs either side of the hangar, tapered bow and stern, engine bells, bridge
func _mat(c: Color, rough := 0.7, metal := 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


func _box(size: Vector3, mat: Material, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	add_child(mi)


## A cylinder or cone laid along the keel (+X), `top` being the +X end radius.
func _cyl_x(r_top: float, r_bottom: float, length: float, mat: Material, at: Vector3, flat := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = length
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = Vector3(0.0, 0.0, -90.0)   # the cylinder's +Y becomes +X
	mi.scale = Vector3(1.0, 1.0, flat) if flat != 1.0 else Vector3.ONE
	add_child(mi)


func _build_hull() -> void:
	var hull := _mat(Color("#9aa4bf"))
	var dark := _mat(Color("#56608a"))
	var metal := _mat(Color("#b4bccf"), 0.5, 0.5)
	var metal_dark := _mat(Color("#66709a"), 0.6, 0.4)
	var window := _glow(Color("#ffd9a0"))
	var cyan := _glow(Color("#5ed3f0"))
	_box(Vector3(4200, 360, 1800), hull, Vector3(0, 360, 0))     # upper deck
	_box(Vector3(4200, 360, 1800), hull, Vector3(0, -360, 0))    # lower deck
	_box(Vector3(1680, 360, 1800), hull, Vector3(1260, 0, 0))    # mid-band slabs: the hangar is the 840-wide gap between them
	_box(Vector3(1680, 360, 1800), hull, Vector3(-1260, 0, 0))
	_cyl_x(560, 900, 1500, hull, Vector3(2850, 0, 0), 0.62)      # bow
	_cyl_x(70, 560, 1000, hull, Vector3(4100, 0, 0), 0.62)
	_cyl_x(900, 700, 1200, hull, Vector3(-2700, 0, 0), 0.62)     # stern
	_box(Vector3(80, 880, 1480), dark, Vector3(-3320, 0, 0))
	for z in [-540.0, 0.0, 540.0]:
		_cyl_x(240, 210, 420, metal_dark, Vector3(-3480, 0, z))   # engine bells
		_cyl_x(120, 180, 60, cyan, Vector3(-3700, 0, z))
		var light := OmniLight3D.new()
		light.light_color = Color("#5ed3f0")
		light.light_energy = 3.0
		light.omni_range = 900.0
		light.position = Vector3(-3800, 0, z)
		add_child(light)
	_box(Vector3(700, 300, 560), metal, Vector3(900, 690, 0))    # bridge
	_box(Vector3(660, 26, 4), window, Vector3(900, 760, 281))
	_box(Vector3(660, 26, 4), window, Vector3(900, 760, -281))
	for side in [1.0, -1.0]:
		for y in [470.0, -470.0]:
			_box(Vector3(3900, 10, 4), window, Vector3(0, y, side * 902))   # window rows
		# hangar mouths: corner lights and a light inside the deck
		for x in [BAY_X0 - 6.0, BAY_X1 + 6.0]:
			for y in [BAY_Y0 + 14.0, BAY_Y1 - 14.0]:
				var l := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = 7.0
				s.height = 14.0
				l.mesh = s
				l.material_override = _glow(Color("#ff4a4a") if y < 0.0 else Color("#4aff7a"))
				l.position = Vector3(x, y, side * (BAY_Z_OUT + 4.0))
				add_child(l)
		var inner := OmniLight3D.new()
		inner.light_color = Color("#dce8ff")
		inner.light_energy = 60.0 / PI
		inner.omni_attenuation = 1.3
		inner.omni_range = 2000.0
		inner.position = Vector3(0, 60, side * 450)
		add_child(inner)
	# the deck floor and ceiling inside the hangar, so the pad reads as a room
	_box(Vector3(840, 12, 1800), dark, Vector3(0, BAY_Y0 - 6.0, 0))
	_box(Vector3(840, 12, 1800), dark, Vector3(0, BAY_Y1 + 6.0, 0))
	for side in [1, -1]:
		var pad := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(300, 6, 300)
		pad.mesh = pm
		pad.material_override = _mat(Color("#c8912e"), 0.8, 0.1)
		pad.position = park_local(side) + Vector3(0, -30, 0)
		add_child(pad)

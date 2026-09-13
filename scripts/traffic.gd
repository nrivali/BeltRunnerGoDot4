class_name Traffic
extends Node3D
## The Hub's traffic, ported from TRAFFIC_LIST / makeTrafficShip / buildTraffic / trafficPlan / updateTraffic in
## belt-runner-3d.html: 72 ships of nine kinds (shuttles, couriers, tugs, tankers, miners, freighters, haulers, liners,
## patrols, and eight cargo carriers of the player's class) that fly in from deep space, land on the colony's pads and
## terminal roofs or berth at its terminals, sit a while, and head back out; patrols lap the rings. Ships are simple
## meshes in the HTML's proportions, nose along +Z as there. This node is a child of the colony, so everything here is
## colony-local, which at the Hub is true world coordinates.

const KINDS := ["shuttle", "shuttle", "shuttle", "shuttle", "shuttle", "shuttle", "courier", "courier", "courier", "courier", "tug", "tug", "tug", "tanker", "tanker", "tanker", "miner", "miner", "miner", "freighter", "freighter", "freighter", "hauler", "hauler", "liner", "liner", "patrol", "patrol", "patrol", "patrol", "shuttle", "courier"]
const SHIP_LEN := {"shuttle": 560.0, "courier": 340.0, "tug": 420.0, "tanker": 1100.0, "miner": 820.0, "freighter": 1500.0, "hauler": 1900.0, "liner": 2200.0, "patrol": 640.0, "carrier": 8000.0}
const BERTH_KINDS := ["freighter", "hauler", "liner", "carrier"]   # the big ones berth at the terminals; everything else lands
const PAINTS := ["#d9def0", "#8e96b4", "#b33a3a", "#2f6f8f", "#6b8f3a", "#c07a2a", "#5a5f78", "#e0c070", "#4a7a6a"]

var ships: Array = []
var slots: Array = []
var _rng := RandomNumberGenerator.new()
var colony_r := 55000.0


func _ready() -> void:
	_rng.randomize()
	_build_slots()
	var list: Array = KINDS.duplicate()
	list.append_array(KINDS)
	for i in 8:
		list.append("carrier")
	for kind in list:
		var s := _make_ship(kind)
		ships.append(s)
		var far := _far()
		s["pos"] = far
		s["q"] = _level_heading((-far).normalized())
		_place(s)
	# half the landers and half the big ships start already parked, so the colony is busy on arrival
	var landers: Array = ships.filter(func(s): return not BERTH_KINDS.has(s["kind"]) and s["kind"] != "patrol")
	var bigs: Array = ships.filter(func(s): return BERTH_KINDS.has(s["kind"]))
	landers.shuffle()
	bigs.shuffle()
	for s in landers.slice(0, landers.size() / 2):
		var free: Array = slots.filter(func(x): return x["type"] == "pad" and x["busy"] == null and (not x["small"] or s["L"] <= 700.0))
		if free.is_empty():
			break
		_park(s, free[_rng.randi() % free.size()])
	for s in bigs.slice(0, (bigs.size() + 1) / 2):
		var free: Array = slots.filter(func(x): return x["type"] == "berth" and x["busy"] == null)
		if free.is_empty():
			break
		_park(s, free[_rng.randi() % free.size()])
	# everyone else is scattered along a first leg so the sky is never empty
	for s in ships:
		if s["phase"] == "idle":
			_plan(s)
			s["t"] = float(s["dur"]) * _rng.randf() * 0.8
	print("traffic: %d ships, %d landing slots, %d parked" % [ships.size(), slots.size(), slots.filter(func(x): return x["busy"] != null).size()])


## Landing slots: six round each core pad, four on each terminal roof, and the two terminal berths.
func _build_slots() -> void:
	var C: Dictionary = Data.COLONY
	for s in [1.0, -1.0]:
		for i in 6:
			var a := i * PI / 3.0 + PI / 6.0
			slots.append({"type": "pad", "side": s, "small": false, "pos": Vector3(cos(a) * 3500.0, s * (C["padY"] + 250.0), sin(a) * 3500.0), "busy": null})
		for x in [-2600.0, 2600.0]:
			for zz in [-1500.0, 1500.0]:
				slots.append({"type": "pad", "side": s, "small": true, "lx": x, "pos": Vector3(x, s * (C["berthY"] + C["termY"]), zz), "busy": null})
		slots.append({"type": "berth", "side": s, "small": false, "pos": Vector3(0.0, s * C["berthY"], C["termZ"] + 2160.0), "out": Vector3(0, 0, 1), "fwd": Vector3(1, 0, 0), "q": Quaternion(Vector3.UP, PI / 2.0), "busy": null})


func _far() -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(150000.0, 420000.0)
	return Vector3(cos(a) * r, _rng.randf_range(-70000.0, 70000.0), sin(a) * r)


## A heading with +Z along `dir` and the deck level (the HTML's levelHeading for ships built nose-forward along +Z).
static func _level_heading(dir: Vector3) -> Quaternion:
	var d := dir
	if d.length_squared() < 1e-6:
		d = Vector3.FORWARD
	var up := Vector3.FORWARD if absf(d.normalized().y) > 0.98 else Vector3.UP
	return Basis.looking_at(-d.normalized(), up).get_rotation_quaternion()


func _rest(s: Dictionary, sl: Dictionary) -> Vector3:
	if sl["type"] == "berth":
		return (sl["pos"] as Vector3) + (sl["out"] as Vector3) * (float(s["w"]) + 80.0)
	return (sl["pos"] as Vector3) + Vector3(0.0, float(sl["side"]) * (float(s["h"]) + 60.0), 0.0)


func _park(s: Dictionary, sl: Dictionary) -> void:
	sl["busy"] = s
	s["slot"] = sl
	s["pos"] = _rest(s, sl)
	s["q"] = sl["q"] if sl["type"] == "berth" else Quaternion(Vector3.UP, _rng.randf() * TAU)
	s["phase"] = "wait"
	s["wait"] = _rng.randf_range(5.0, 70.0)
	_place(s)


## A point out past the rings on the given side of the ring plane, in the direction the ship is coming from.
func _offside(s: Dictionary, side: float) -> Vector3:
	var d: Vector3 = s["pos"]
	d = Vector3(d.x, 0.0, d.z).normalized()
	return d * colony_r * 2.7 + Vector3(0.0, side * colony_r * 0.55, 0.0)


func _plan(s: Dictionary) -> void:
	var C: Dictionary = Data.COLONY
	var pts: Array = [s["pos"]]
	var kind: String = s["kind"]
	if kind == "patrol":
		# a patrol lap: a few points round the rings at a set radius and height, then another lap from wherever it ends
		var rel: Vector3 = s["pos"]
		var side := signf(rel.y) if rel.y != 0.0 else (1.0 if _rng.randf() < 0.5 else -1.0)
		var r := _rng.randf_range(58000.0, 72000.0)
		var y := side * _rng.randf_range(3500.0, 9000.0)
		var a0 := atan2(rel.z, rel.x)
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var rr := Vector2(rel.x, rel.z).length()
		if rr > r * 1.4 or rr < r * 0.7:
			pts.append(Vector3(cos(a0) * r, y, sin(a0) * r))
		for i in range(1, 5):
			var a := a0 + dir * i * 0.6
			pts.append(Vector3(cos(a) * r, y + sin(i * 1.7) * 1500.0, sin(a) * r))
	elif s["slot"] != null:
		# leaving: straight up off a pad, sideways off a roof, or out along the lane from a berth, then away to deep space
		var sl: Dictionary = s["slot"]
		var sd: float = sl["side"]
		sl["busy"] = null
		s["slot"] = null
		if sl["type"] == "berth":
			var rest := _rest(s, sl)
			pts.append(rest + Vector3(24000.0, 0.0, 0.0))
			pts.append(rest + Vector3(80000.0, sd * 5000.0, 10000.0))
		elif sl["small"]:
			var sx := signf(sl["lx"]) if sl["lx"] != 0.0 else 1.0
			pts.append((s["pos"] as Vector3) + Vector3(sx * 14000.0, sd * 1500.0, 0.0))
			pts.append((s["pos"] as Vector3) + Vector3(sx * 60000.0, sd * 9000.0, 0.0))
		else:
			var rel: Vector3 = s["pos"]
			pts.append(rel + Vector3(0.0, sd * 6000.0, 0.0))
			pts.append(Vector3(rel.x * 7.0, sd * (C["padY"] + 20000.0), rel.z * 7.0))
		pts.append(_far())
	else:
		var big := BERTH_KINDS.has(kind)
		var free: Array = slots.filter(func(x): return x["busy"] == null and ((x["type"] == "berth") if big else (x["type"] == "pad" and (not x["small"] or float(s["L"]) <= 700.0))))
		var dock = free[_rng.randi() % free.size()] if (not free.is_empty() and _rng.randf() < 0.75) else null
		if dock != null and dock["type"] == "berth":
			# a berth: come round to the far end of the lane if need be, then straight down it and in, nose first
			dock["busy"] = s
			s["slot"] = dock
			var sd: float = dock["side"]
			var rest := _rest(s, dock)
			if (s["pos"] as Vector3).dot(dock["fwd"]) > -colony_r:
				pts.append(rest + Vector3(-130000.0, sd * 8000.0, 24000.0))
			pts.append(rest + Vector3(-92000.0, sd * 3000.0, 6000.0))
			pts.append(rest + Vector3(-40000.0, 0.0, 0.0))
			pts.append(rest + Vector3(-12000.0, 0.0, 0.0))
			pts.append(rest)
		elif dock != null:
			# land on a pad or roof: get to its side of the ring plane far out, come in high over it, then straight down
			dock["busy"] = s
			s["slot"] = dock
			var sd: float = dock["side"]
			var rest := _rest(s, dock)
			if signf((s["pos"] as Vector3).y) != sd:
				pts.append(_offside(s, sd))
			if dock["small"]:
				var sx := signf(dock["lx"]) if dock["lx"] != 0.0 else 1.0
				pts.append(rest + Vector3(sx * 40000.0, sd * 7000.0, 0.0))
				pts.append(rest + Vector3(sx * 14000.0, sd * 1500.0, 0.0))
				pts.append(rest)
			else:
				var rel: Vector3 = dock["pos"]
				pts.append(Vector3(rel.x * 8.0, sd * (C["padY"] + 22000.0), rel.z * 8.0))
				pts.append(rest + Vector3(0.0, sd * 7000.0, 0.0))
				pts.append(rest)
		elif big and _rng.randf() < 0.6:
			# a big ship with nowhere to berth holds off in a wide loop out past the rings, then tries again
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var y := side * _rng.randf_range(12000.0, 20000.0)
			var r := colony_r + _rng.randf_range(30000.0, 50000.0)
			var a := _rng.randf() * TAU
			for i in 3:
				pts.append(Vector3(cos(a + i * 0.9) * r, y, sin(a + i * 0.9) * r))
		else:
			# a pass by the rings, above or below the ring plane, then back out
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var y := side * _rng.randf_range(7800.0, 9800.0)
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(24000.0, 46000.0)
			if signf((s["pos"] as Vector3).y) != side:
				pts.append(_offside(s, side))
			pts.append(Vector3(cos(a) * r, y, sin(a) * r))
			var a2 := a + _rng.randf_range(1.0, 2.2)
			pts.append(Vector3(cos(a2) * r * 1.4, y * 1.5, sin(a2) * r * 1.4))
			pts.append(_far())
	s["pts"] = pts
	var len := Ship._curve_length(pts)
	var speed: float
	match kind:
		"courier": speed = _rng.randf_range(4200.0, 5600.0)
		"shuttle", "patrol": speed = _rng.randf_range(2600.0, 3600.0)
		"tug", "miner": speed = _rng.randf_range(1800.0, 2600.0)
		"carrier": speed = _rng.randf_range(1100.0, 1500.0)
		_: speed = _rng.randf_range(1400.0, 2000.0)
	s["speed"] = speed
	s["dur"] = max(4.0, len / speed)
	s["t"] = 0.0
	s["phase"] = "fly"


func tick(dt: float) -> void:
	for s in ships:
		if s["phase"] == "idle":
			_plan(s)
		if s["phase"] == "fly":
			s["t"] = float(s["t"]) + dt
			var k: float = min(1.0, float(s["t"]) / float(s["dur"]))
			var u: float = k if s["kind"] == "patrol" else k * k * (3.0 - 2.0 * k)   # patrols cruise at a steady pace; everyone else eases in and out
			var pts: Array = s["pts"]
			s["pos"] = Ship._curve_point(pts, u)
			var tan := Ship._curve_tangent(pts, min(u, 0.999))
			if absf(tan.y) < 0.75:   # a vertical leg (landing, lift-off) keeps the last heading
				s["q"] = (s["q"] as Quaternion).slerp(_level_heading(tan), 1.0 - exp(-(1.2 if s["kind"] == "carrier" else 2.2) * dt))
			var thr: float = 0.6 if s["kind"] == "patrol" else min(1.0, 6.0 * k * (1.0 - k) + 0.2)
			_glow(s, 0.3 + 0.6 * thr)
			_place(s)
			if k >= 1.0:
				if s["slot"] != null:
					s["phase"] = "wait"
					s["wait"] = _rng.randf_range(40.0, 120.0) if s["kind"] == "carrier" else _rng.randf_range(12.0, 45.0)
				else:
					s["phase"] = "idle"
		elif s["phase"] == "wait":
			s["wait"] = float(s["wait"]) - dt
			_glow(s, 0.12)
			if float(s["wait"]) <= 0.0:
				_plan(s)


func _place(s: Dictionary) -> void:
	var n: Node3D = s["node"]
	n.position = s["pos"]
	n.transform.basis = Basis(s["q"] as Quaternion)


func _glow(s: Dictionary, a: float) -> void:
	for e in s["eng"]:
		(e as MeshInstance3D).scale = Vector3.ONE * (0.6 + 0.8 * a)


## A summary for the smoke test.
func stats() -> Dictionary:
	var phases := {}
	for s in ships:
		phases[s["phase"]] = phases.get(s["phase"], 0) + 1
	return {"ships": ships.size(), "slots": slots.size(), "parked": slots.filter(func(x): return x["busy"] != null).size(), "phases": phases}


# ---- the ships: the HTML's proportions in plain meshes, nose along +Z, engines astern
func _mat(c: Color, rough := 0.7, metal := 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


func _add(g: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	g.add_child(mi)
	return mi


func _box(g: Node3D, size: Vector3, mat: Material, at: Vector3) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(g, b, mat, at)


## A cylinder or cone laid along Z (its +Z end radius `r_front`).
func _cyl_z(g: Node3D, r_front: float, r_back: float, length: float, mat: Material, at: Vector3, flat := 1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_front
	c.bottom_radius = r_back
	c.height = length
	c.radial_segments = 12
	return _add(g, c, mat, at, Vector3(90.0, 0.0, 0.0), Vector3(flat, 1.0, 1.0))


func _make_ship(kind: String) -> Dictionary:
	var g := Node3D.new()
	g.name = kind
	add_child(g)
	var L: float = SHIP_LEN.get(kind, 560.0)
	var paint := Color(PAINTS[_rng.randi() % PAINTS.size()])
	var hull := _mat(paint)
	var dark := _mat(Color("#3a4058"))
	var trim := _mat(Color("#c8912e"))
	var win := _glow_mat(Color("#ffe6b0"))
	var cyan := _glow_mat(Color("#8fe8ff"))
	var h := L * 0.14
	var w := L * 0.15
	var eng_x: Array = [-L * 0.1, 0.0, L * 0.1]
	var eng_s := L * 0.12
	var eng_col := Color("#9fd8ff")
	match kind:
		"carrier":
			h = 540.0
			w = 900.0
			var dk := _mat(paint)
			var dark2 := _mat(Color("#56608a"))
			_box(g, Vector3(1800, 360, 4200), dk, Vector3(0, 360, 0))
			_box(g, Vector3(1800, 360, 4200), dk, Vector3(0, -360, 0))
			_box(g, Vector3(1800, 360, 1680), dk, Vector3(0, 0, 1260))
			_box(g, Vector3(1800, 360, 1680), dk, Vector3(0, 0, -1260))
			_cyl_z(g, 560, 900, 1500, dk, Vector3(0, 0, 2850), 0.62)
			_cyl_z(g, 70, 560, 1000, dk, Vector3(0, 0, 4100), 0.62)
			_cyl_z(g, 900, 700, 1200, dk, Vector3(0, 0, -2700), 0.62)
			_box(g, Vector3(1480, 880, 80), dark2, Vector3(0, 0, -3320))
			for x in [-540.0, 0.0, 540.0]:
				_cyl_z(g, 240, 210, 420, dark2, Vector3(x, 0, -3480))
			_box(g, Vector3(560, 300, 700), dk, Vector3(0, 690, 900))
			_box(g, Vector3(4, 26, 660), win, Vector3(281, 760, 900))
			_box(g, Vector3(4, 26, 660), win, Vector3(-281, 760, 900))
			for sx in [1.0, -1.0]:
				for y in [470.0, -470.0]:
					_box(g, Vector3(4, 10, 3900), win, Vector3(sx * 902.0, y, 0))
			eng_x = [-540.0, 0.0, 540.0]
			eng_s = 700.0
			eng_col = Color("#5ed3f0")
		"freighter":
			h = L * 0.12
			w = L * 0.17
			_box(g, Vector3(L * 0.18, L * 0.16, L * 0.92), dark, Vector3.ZERO)
			for i in 3:
				_box(g, Vector3(L * 0.34, L * 0.2, L * 0.22), hull, Vector3(0, L * 0.02, L * 0.22 - i * 0.26 * L))
			_box(g, Vector3(L * 0.26, L * 0.18, L * 0.16), hull, Vector3(0, L * 0.06, L * 0.42))
			_box(g, Vector3(L * 0.2, L * 0.03, L * 0.02), win, Vector3(0, L * 0.1, L * 0.505))
			_box(g, Vector3(L * 0.3, L * 0.22, L * 0.14), dark, Vector3(0, 0, -L * 0.44))
		"hauler":
			h = L * 0.16
			w = L * 0.27
			_box(g, Vector3(L * 0.22, L * 0.2, L * 0.9), dark, Vector3.ZERO)
			for i in 3:
				for sx in [-1.0, 1.0]:
					_box(g, Vector3(L * 0.16, L * 0.14, L * 0.24), trim if i % 2 else hull, Vector3(sx * L * 0.19, L * 0.01, L * 0.25 - i * 0.28 * L))
			_box(g, Vector3(L * 0.2, L * 0.12, L * 0.14), hull, Vector3(0, L * 0.16, L * 0.3))
			_box(g, Vector3(L * 0.16, L * 0.03, L * 0.02), win, Vector3(0, L * 0.19, L * 0.375))
			_box(g, Vector3(L * 0.5, L * 0.18, L * 0.12), dark, Vector3(0, 0, -L * 0.44))
			eng_x = [-L * 0.18, -L * 0.06, L * 0.06, L * 0.18]
			eng_s = L * 0.1
		"liner":
			h = L * 0.12
			w = L * 0.2
			_cyl_z(g, L * 0.08, L * 0.12, L * 0.9, hull, Vector3.ZERO, 1.6)
			for y in [-L * 0.03, 0.0, L * 0.03]:
				for sx in [-1.0, 1.0]:
					_box(g, Vector3(L * 0.01, L * 0.018, L * 0.62), win, Vector3(sx * L * 0.128, y, L * 0.02))
			_box(g, Vector3(L * 0.14, L * 0.08, L * 0.2), hull, Vector3(0, L * 0.12, L * 0.2))
			_box(g, Vector3(L * 0.1, L * 0.03, L * 0.02), win, Vector3(0, L * 0.14, L * 0.3))
			_box(g, Vector3(L * 0.02, L * 0.16, L * 0.2), trim, Vector3(0, L * 0.18, -L * 0.25))
			_box(g, Vector3(L * 0.3, L * 0.14, L * 0.1), dark, Vector3(0, 0, -L * 0.44))
			eng_col = Color("#7fb0ff")
			eng_s = L * 0.09
		"tanker":
			h = L * 0.14
			_cyl_z(g, L * 0.14, L * 0.14, L * 0.62, hull, Vector3(0, 0, -L * 0.04))
			_box(g, Vector3(L * 0.12, L * 0.1, L * 0.9), dark, Vector3(0, -L * 0.12, 0))
			_box(g, Vector3(L * 0.16, L * 0.14, L * 0.16), hull, Vector3(0, L * 0.02, L * 0.38))
			_box(g, Vector3(L * 0.12, L * 0.03, L * 0.02), win, Vector3(0, L * 0.05, L * 0.465))
			_box(g, Vector3(L * 0.22, L * 0.16, L * 0.1), dark, Vector3(0, -L * 0.02, -L * 0.42))
		"miner":
			h = L * 0.16
			_box(g, Vector3(L * 0.3, L * 0.22, L * 0.7), hull, Vector3(0, 0, -L * 0.05))
			_box(g, Vector3(L * 0.24, L * 0.14, L * 0.16), dark, Vector3(0, L * 0.04, L * 0.36))
			_box(g, Vector3(L * 0.18, L * 0.03, L * 0.02), win, Vector3(0, L * 0.08, L * 0.445))
			var dish := SphereMesh.new()
			dish.radius = L * 0.09
			dish.height = L * 0.09
			_add(g, dish, trim, Vector3(0, -L * 0.02, L * 0.5))
			for sx in [-1.0, 1.0]:
				_cyl_z(g, L * 0.06, L * 0.06, L * 0.5, dark, Vector3(sx * L * 0.2, -L * 0.1, -L * 0.05))
			_box(g, Vector3(L * 0.26, L * 0.16, L * 0.1), dark, Vector3(0, 0, -L * 0.44))
			eng_x = [-L * 0.08, L * 0.08]
		"tug":
			h = L * 0.2
			_box(g, Vector3(L * 0.36, L * 0.3, L * 0.5), hull, Vector3(0, 0, L * 0.08))
			_box(g, Vector3(L * 0.26, L * 0.03, L * 0.02), win, Vector3(0, L * 0.08, L * 0.335))
			_box(g, Vector3(L * 0.44, L * 0.36, L * 0.3), dark, Vector3(0, 0, -L * 0.28))
			_cyl_z(g, L * 0.03, L * 0.03, L * 0.3, trim, Vector3(0, L * 0.1, -L * 0.45))
			for sx in [-1.0, 1.0]:
				_box(g, Vector3(L * 0.06, L * 0.06, L * 0.2), trim, Vector3(sx * L * 0.24, L * 0.1, L * 0.05))
			eng_x = [-L * 0.14, L * 0.14]
			eng_s = L * 0.16
		"courier":
			h = L * 0.1
			_cyl_z(g, 0.0, L * 0.09, L * 0.9, hull, Vector3.ZERO)
			_box(g, Vector3(L * 0.08, L * 0.05, L * 0.16), cyan, Vector3(0, L * 0.06, L * 0.1))
			for sx in [-1.0, 1.0]:
				_box(g, Vector3(L * 0.36, L * 0.02, L * 0.14), hull, Vector3(sx * L * 0.14, 0, -L * 0.28))
			_box(g, Vector3(L * 0.02, L * 0.16, L * 0.14), trim, Vector3(0, L * 0.08, -L * 0.3))
			eng_x = [0.0]
			eng_s = L * 0.18
			eng_col = Color("#ffc080")
		"patrol":
			h = L * 0.1
			_box(g, Vector3(L * 0.34, L * 0.12, L * 0.7), hull, Vector3.ZERO)
			_box(g, Vector3(L * 0.14, L * 0.1, L * 0.3), dark, Vector3(0, 0, L * 0.45))
			_box(g, Vector3(L * 0.12, L * 0.03, L * 0.02), win, Vector3(0, L * 0.04, L * 0.5))
			for sx in [-1.0, 1.0]:
				_box(g, Vector3(L * 0.6, L * 0.03, L * 0.3), hull, Vector3(sx * L * 0.3, -L * 0.02, -L * 0.1))
				_cyl_z(g, L * 0.05, L * 0.05, L * 0.5, dark, Vector3(sx * L * 0.55, 0, -L * 0.15))
			var beacon := SphereMesh.new()
			beacon.radius = L * 0.03
			beacon.height = L * 0.06
			_add(g, beacon, _glow_mat(Color("#ff5a5a")), Vector3(0, L * 0.08, -L * 0.1))
			eng_x = [-L * 0.55, L * 0.55]
			eng_s = L * 0.09
			eng_col = Color("#ff9060")
		_:
			h = L * 0.15
			_box(g, Vector3(L * 0.3, L * 0.24, L * 0.8), hull, Vector3.ZERO)
			_box(g, Vector3(L * 1.1, L * 0.04, L * 0.28), hull, Vector3(0, -L * 0.04, -L * 0.12))
			_box(g, Vector3(L * 0.2, L * 0.16, L * 0.2), dark, Vector3(0, -L * 0.02, L * 0.48))
			_box(g, Vector3(L * 0.16, L * 0.03, L * 0.02), win, Vector3(0, L * 0.06, L * 0.405))
			eng_x = [-L * 0.08, L * 0.08]
	# navigation lights and the engine glows astern
	var wide := 1.1 if (kind == "shuttle" or kind == "patrol") else (0.22 if kind == "carrier" else 0.3)
	var nav := SphereMesh.new()
	nav.radius = 40.0 if kind == "carrier" else L * 0.012
	nav.height = nav.radius * 2.0
	_add(g, nav, _glow_mat(Color("#ff4040")), Vector3(-L * 0.5 * wide, 0, -L * 0.1))
	_add(g, nav, _glow_mat(Color("#40ff80")), Vector3(L * 0.5 * wide, 0, -L * 0.1))
	var eng: Array = []
	var em := _glow_mat(eng_col)
	for x in eng_x:
		var s := SphereMesh.new()
		s.radius = eng_s * 0.3
		s.height = eng_s * 0.6
		eng.append(_add(g, s, em, Vector3(x, 0, -L * 0.5)))
	return {"node": g, "kind": kind, "L": L, "h": h, "w": w, "phase": "idle", "pts": [], "t": 0.0, "dur": 0.0, "slot": null, "wait": 0.0, "eng": eng, "q": Quaternion.IDENTITY, "pos": Vector3.ZERO, "speed": 1000.0}

class_name Belt
extends Node3D
## The asteroid belt. Every rock lives in packed arrays (true world position, radius, ore, health...) and is drawn by one
## MultiMesh per 50 km chunk, so 54,000 rocks cost a few hundred draw calls and each chunk's instance transforms are
## small numbers relative to the chunk node, which keeps single-precision floats tight. Chunks beyond the draw distance
## are hidden. Generation is a port of loadZone/makeAsteroid/makeField from belt-runner-3d.html and is deterministic
## from a seed, so a future server and its clients can build the same belt and only replicate what changes.
##
## Milestone 1 simplifications: rocks are faceted spheres, they do not drift on their orbit rails, and a broken rock is
## hidden rather than split into fragments.

const CHUNK := 50000.0
const DRAW_DIST := 180000.0
const FIELDS_PER_BELT := [7, 7, 9, 0]
const COLOSSAL_LOOSE := 0.146
const BARREN_SHARE := 2.0 / 3.0
const COLOSSAL_ORE_SHARE := 0.001
const CLS_NAME := ["Small", "Large", "Giant", "Colossal"]

var pos := PackedVector3Array()      # true world position
var radius := PackedFloat32Array()
var ore := PackedInt32Array()        # index into Data.ORE_KEYS, -1 = barren
var hp := PackedFloat32Array()
var hp_max := PackedFloat32Array()
var amount := PackedFloat32Array()
var cls := PackedByteArray()
var alive := PackedByteArray()
var chunk_of := PackedInt32Array()
var slot_of := PackedInt32Array()
var count := 0

var _rng := RandomNumberGenerator.new()
var _chunk_nodes: Array = []        # MultiMeshInstance3D per chunk
var _chunk_centre: Array = []       # true world centre per chunk
var _chunk_rocks: Array = []        # Array of PackedInt32Array
var _chunk_key := {}                # "x,y,z" -> chunk index
var _mesh: Mesh
var _material: StandardMaterial3D
var planet_r := 0.0
var world_r := 0.0


## Throw the current belt away (zone change).
func clear() -> void:
	for n in _chunk_nodes:
		n.queue_free()
	_chunk_nodes = []
	_chunk_centre = []
	_chunk_rocks = []
	_chunk_key = {}
	pos = PackedVector3Array()
	radius = PackedFloat32Array()
	ore = PackedInt32Array()
	hp = PackedFloat32Array()
	hp_max = PackedFloat32Array()
	amount = PackedFloat32Array()
	cls = PackedByteArray()
	alive = PackedByteArray()
	chunk_of = PackedInt32Array()
	slot_of = PackedInt32Array()
	count = 0


func build(zone: Dictionary, seed: int) -> void:
	_rng.seed = seed
	var central: bool = zone["planet"].get("central", true)
	planet_r = zone["planet"]["r"] * Data.PLANET_SCALE if central else 0.0
	world_r = planet_r + Data.WORLD_EDGE_BASE * Data.WORLD_SCALE
	var density: float = zone["density"]
	var amount_mult: float = zone["amountMult"]
	if density <= 0.0:
		return   # a zone with no belts (the Hub)
	_mesh = SphereMesh.new()
	_mesh.radius = 1.0
	_mesh.height = 2.0
	_mesh.radial_segments = 9
	_mesh.rings = 5
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.metallic = 0.05
	_mesh.material = _material
	# the three base belts, scaled to world units and given this zone's ore weights, then the ring belt at its fixed radius
	var belts: Array = []
	for i in Data.BASE_BELTS.size():
		var b: Dictionary = Data.BASE_BELTS[i].duplicate()
		b["ores"] = zone["belts"][i]
		b["count"] = roundi(b["count"] * density * 0.65)
		b["rMin"] = planet_r + b["rMin"] * Data.WORLD_SCALE
		b["rMax"] = planet_r + b["rMax"] * Data.WORLD_SCALE
		b["spread"] = b["spread"] * Data.WORLD_SCALE
		b["amountMult"] = amount_mult
		belts.append(b)
	if Data.RING_BELT["rMin"] > planet_r + 20000.0:
		var r: Dictionary = Data.RING_BELT.duplicate()
		r["count"] = roundi(r["count"] * density)
		r["amountMult"] = amount_mult
		belts.append(r)
	for bi in belts.size():
		var b: Dictionary = belts[bi]
		for i in b["count"]:
			_make_rock(b, null)
		var nf: int = FIELDS_PER_BELT[bi] if bi < FIELDS_PER_BELT.size() else 0
		for f in nf:
			var fld := _make_field(b, density)
			for i in fld["count"]:
				_make_rock(b, fld)
	# rich pockets: tight clusters anywhere in the zone, every ore the zone offers, two and a half times the yield
	var all_ores := {}
	for i in Data.BASE_BELTS.size():
		for k in zone["belts"][i]:
			all_ores[k] = all_ores.get(k, 0.0) + zone["belts"][i][k]
	var pocket_belt := {"name": "Pocket", "rMin": planet_r + 40000.0, "rMax": world_r * 0.9, "size": [30, 96], "amount": [120, 360], "spread": 0.0, "ores": all_ores, "amountMult": amount_mult * 2.5}
	var np := roundi(30.0 * max(0.7, density))
	for i in np:
		var prad := _rng.randf_range(1500.0, 3500.0)
		var dist := _rng.randf_range(pocket_belt["rMin"], pocket_belt["rMax"])
		var ang := _rng.randf() * TAU
		var lat := asin(_rng.randf_range(-1.0, 1.0)) * 0.85
		var orbit: float = max(planet_r * 0.2, cos(lat) * dist)
		var centre := Vector3(cos(ang) * orbit, sin(lat) * dist, sin(ang) * orbit)
		var fld := {"radius": prad, "center": centre, "ores": all_ores, "count": roundi(_rng.randf_range(40.0, 90.0))}
		for k in fld["count"]:
			_make_rock(pocket_belt, fld)
	_build_chunks()


func _make_field(b: Dictionary, density: float) -> Dictionary:
	var rad := _rng.randf_range(900.0, 2200.0)
	var orbit := _rng.randf_range(b["rMin"] + rad, b["rMax"] - rad)
	var ang := _rng.randf() * TAU
	var y: float = _rng.randf_range(-0.5, 0.5) * float(b["spread"])
	var keys: Array = b["ores"].keys()
	var main_ore: String = keys[_rng.randi() % keys.size()]
	var w := {}
	var sum := 0.0
	for k in keys:
		w[k] = b["ores"][k] * (3.0 if k == main_ore else 1.0)
		sum += w[k]
	for k in w:
		w[k] /= sum
	return {"radius": rad, "center": Vector3(cos(ang) * orbit, y, sin(ang) * orbit), "ores": w, "count": roundi(_rng.randf_range(45.0, 85.0) * density)}


func _pick_ore(weights: Dictionary) -> String:
	var r := _rng.randf()
	var acc := 0.0
	var last := ""
	for k in weights:
		acc += weights[k]
		last = k
		if r <= acc:
			return k
	return last


func _make_rock(b: Dictionary, fld) -> void:
	var p: Vector3
	if fld != null:
		var d: Vector3 = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * float(fld["radius"]) * pow(_rng.randf(), 0.6)
		p = fld["center"] + d
	else:
		var tries := 0
		while true:
			var ang := _rng.randf() * TAU
			var orbit := _rng.randf_range(b["rMin"], b["rMax"])
			var y: float = (_rng.randf() + _rng.randf() - 1.0) * float(b["spread"])
			p = Vector3(cos(ang) * orbit, y, sin(ang) * orbit)
			tries += 1
			if tries >= 30 or p.length() > planet_r * 1.02:
				break
	# size mix: colossals come off the top of the roll for loose rocks only, then giant : large : small split 2 : 4 : 3
	var roll := _rng.randf()
	var c := 0
	var base_r: float
	var size: Array = b["size"]
	if fld == null:
		if roll < COLOSSAL_LOOSE:
			c = 3
		else:
			roll = (roll - COLOSSAL_LOOSE) / (1.0 - COLOSSAL_LOOSE)
	if c != 3:
		c = 2 if roll < 2.0 / 9.0 else (1 if roll < 6.0 / 9.0 else 0)
	match c:
		3: base_r = size[1] * _rng.randf_range(14.0, 24.0)
		2: base_r = size[1] * _rng.randf_range(5.0, 8.5)
		1: base_r = size[1] * _rng.randf_range(1.8, 3.2)
		_: base_r = size[0] + (size[1] - size[0]) * pow(_rng.randf(), 1.7)
	var ore_key := _pick_ore(fld["ores"] if fld != null else b["ores"])
	var barren := _rng.randf() < ((1.0 - COLOSSAL_ORE_SHARE) if c == 3 else BARREN_SHARE)
	var amt_range: Array = b["amount"]
	var t: float = clamp((base_r - size[0]) / float(size[1] - size[0]), 0.0, 1.0)
	var amt := roundf((amt_range[0] + (amt_range[1] - amt_range[0]) * t) * max(1.0, base_r / size[1]) * b["amountMult"] * _rng.randf_range(0.85, 1.15))
	var hpm := roundf(40.0 + 2.2 * pow(base_r, 1.15))
	pos.append(p)
	radius.append(base_r)
	ore.append(-1 if barren else Data.ORE_KEYS.find(ore_key))
	hp.append(hpm)
	hp_max.append(hpm)
	amount.append(0.0 if barren else amt)
	cls.append(c)
	alive.append(1)
	chunk_of.append(-1)
	slot_of.append(-1)
	count += 1


func _chunk_index(p: Vector3) -> int:
	var cx := floori(p.x / CHUNK)
	var cy := floori(p.y / CHUNK)
	var cz := floori(p.z / CHUNK)
	var key := "%d,%d,%d" % [cx, cy, cz]
	if _chunk_key.has(key):
		return _chunk_key[key]
	var idx := _chunk_centre.size()
	_chunk_key[key] = idx
	_chunk_centre.append(Vector3((cx + 0.5) * CHUNK, (cy + 0.5) * CHUNK, (cz + 0.5) * CHUNK))
	_chunk_rocks.append(PackedInt32Array())
	return idx


func _build_chunks() -> void:
	for i in count:
		var ci := _chunk_index(pos[i])
		chunk_of[i] = ci
		var arr: PackedInt32Array = _chunk_rocks[ci]
		slot_of[i] = arr.size()
		arr.append(i)
		_chunk_rocks[ci] = arr
	for ci in _chunk_centre.size():
		var rocks: PackedInt32Array = _chunk_rocks[ci]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh
		mm.instance_count = rocks.size()
		var centre: Vector3 = _chunk_centre[ci]
		for s in rocks.size():
			var i := rocks[s]
			mm.set_instance_transform(s, _rock_transform(i, centre))
			mm.set_instance_color(s, _rock_color(i))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.position = centre
		node.custom_aabb = AABB(Vector3(-CHUNK, -CHUNK, -CHUNK) * 0.6, Vector3(CHUNK, CHUNK, CHUNK) * 1.2)
		add_child(node)
		_chunk_nodes.append(node)


func _rock_transform(i: int, centre: Vector3) -> Transform3D:
	var basis := Basis.from_euler(Vector3(_rng.randf() * 6.0, _rng.randf() * 6.0, _rng.randf() * 6.0))
	var stretch := Vector3(_rng.randf_range(0.8, 1.25), _rng.randf_range(0.75, 1.2), _rng.randf_range(0.8, 1.25))
	basis = basis.scaled(stretch * radius[i])
	return Transform3D(basis, pos[i] - centre)


func _rock_color(i: int) -> Color:
	var stone := Color(0.30, 0.31, 0.36)
	if ore[i] < 0:
		return stone.lerp(Color(0.22, 0.22, 0.25), _rng.randf() * 0.5)
	var c: Color = Data.ORES[Data.ORE_KEYS[ore[i]]]["color"]
	return stone.lerp(c, 0.55)


## Move every chunk node so that true world coordinates minus `offset` land in scene space (floating origin).
func apply_offset(offset: Vector3) -> void:
	for ci in _chunk_nodes.size():
		_chunk_nodes[ci].position = _chunk_centre[ci] - offset


## Hide chunks well beyond the draw distance from the true world point `from`.
func cull(from: Vector3) -> void:
	var lim := DRAW_DIST + CHUNK
	for ci in _chunk_nodes.size():
		var c: Vector3 = _chunk_centre[ci]
		_chunk_nodes[ci].visible = c.distance_to(from) < lim


## The rock under the nose: a ray from `origin` along `dir` (true world coordinates), out to `reach`, with the browser
## game's aiming slack (about two degrees plus a few units). Returns the rock id, or -1.
func ray_hit(origin: Vector3, dir: Vector3, reach: float) -> int:
	var best := -1
	var best_t := INF
	var span := reach + CHUNK
	for ci in _chunk_centre.size():
		var c: Vector3 = _chunk_centre[ci]
		if c.distance_squared_to(origin) > span * span:
			continue
		var rocks: PackedInt32Array = _chunk_rocks[ci]
		for s in rocks.size():
			var i := rocks[s]
			if alive[i] == 0:
				continue
			var to := pos[i] - origin
			var t := to.dot(dir)
			if t < 0.0:
				continue
			var r := radius[i]
			if t - r > reach:
				continue
			var d2 := to.length_squared() - t * t
			var tol := r + 8.0 + t * 0.035
			if d2 < tol * tol and t - r < best_t:
				best_t = t - r
				best = i
	return best


## Ore-bearing live rocks within `range` of `from`: count and the nearest one's id. `only_ore` narrows it to one ore index.
func scan(from: Vector3, range: float, only_ore: int = -1) -> Dictionary:
	var n := 0
	var nearest := -1
	var nd := INF
	var r2 := range * range
	for ci in _chunk_centre.size():
		var c: Vector3 = _chunk_centre[ci]
		if c.distance_squared_to(from) > (range + CHUNK) * (range + CHUNK):
			continue
		for i in _chunk_rocks[ci]:
			if alive[i] == 0 or ore[i] < 0 or (only_ore >= 0 and ore[i] != only_ore):
				continue
			var d2 := pos[i].distance_squared_to(from)
			if d2 < r2:
				n += 1
				if d2 < nd:
					nd = d2
					nearest = i
	return {"count": n, "nearest": nearest, "dist": sqrt(nd) if nearest >= 0 else 0.0}


func damage(i: int, dmg: float) -> void:
	hp[i] -= dmg


## Break a rock: hide its instance and return the ore that comes loose (the fragments of a bigger rock are not modelled yet).
func kill(i: int) -> float:
	alive[i] = 0
	var mm: MultiMesh = _chunk_nodes[chunk_of[i]].multimesh
	mm.set_instance_transform(slot_of[i], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var loose: float = amount[i]
	amount[i] = 0.0
	hp[i] = 0.0
	return loose


func rock_name(i: int) -> String:
	var size: String = CLS_NAME[cls[i]] + " " if cls[i] > 0 else ""
	var what: String = "Barren" if ore[i] < 0 else Data.ORES[Data.ORE_KEYS[ore[i]]]["name"]
	return size + what + " rock"

class_name Belt
extends Node3D
## The asteroid belt. Every rock lives in packed arrays (true world position, radius, ore, health, shape...) and is drawn
## by MultiMeshes: one per (250 km chunk, rock shape) pair, so 54,000 rocks cost a few hundred draw calls where the ship
## is and nothing where it is not, and each chunk's instance transforms are small numbers relative to the chunk node,
## which keeps single-precision floats tight. The rock meshes are Astra's Blender asteroid library (14 shape families,
## two variants each, three LODs): chunks near the ship draw LOD 1, the rest LOD 2, and chunks beyond the draw distance
## are hidden. The ore veins on each mesh take the instance colour, so a rock reads as its ore; barren rocks get grey
## veins. If the library is missing, faceted spheres stand in.
##
## Generation is a port of loadZone/makeAsteroid/makeField from belt-runner-3d.html and is deterministic from a seed.
## Milestone simplifications: rocks do not drift on their orbit rails, and a broken rock is hidden rather than split.

const CHUNK := 250000.0
const DRAW_DIST := 180000.0
const LOD1_DIST := 70000.0
const FIELDS_PER_BELT := [7, 7, 9, 0]
const COLOSSAL_LOOSE := 0.146
const BARREN_SHARE := 2.0 / 3.0
const COLOSSAL_ORE_SHARE := 0.001
const CLS_NAME := ["Small", "Large", "Giant", "Colossal"]
const SHAPES := ["lumpy", "chunk", "potato", "shard", "pancake", "cratered", "cluster", "slab", "spindle", "bean", "boulder", "jagged", "wedge", "hollow"]
const BIG_SHAPES := ["cratered", "boulder", "potato", "bean"]
const ROCK_LIB := ["res://assets/rocks/asteroids_lod1.glb", "res://assets/rocks/asteroids_lod2.glb"]

var pos := PackedVector3Array()      # true world position
var radius := PackedFloat32Array()
var ore := PackedInt32Array()        # index into Data.ORE_KEYS, -1 = barren
var hp := PackedFloat32Array()
var hp_max := PackedFloat32Array()
var amount := PackedFloat32Array()
var cls := PackedByteArray()
var alive := PackedByteArray()
var shape := PackedInt32Array()      # index into _keys (shape_variant)
var chunk_of := PackedInt32Array()
var mm_of := PackedInt32Array()      # index into _mms
var slot_of := PackedInt32Array()
var count := 0
var mark_until := PackedFloat32Array()   # radar marks: State.time until which a rock shows as a blip
var _marked := PackedInt32Array()        # the rocks the last pulses reached
const MARK_TIME := 25.0

var _rng := RandomNumberGenerator.new()
var _chunk_centre: Array = []       # true world centre per chunk
var _chunk_key := {}                # "x,y,z" -> chunk index
var _chunk_mms: Array = []          # chunk index -> Array of mm indices
var _chunk_rocks: Array = []        # chunk index -> PackedInt32Array of rock ids
var _chunk_lod: PackedInt32Array = PackedInt32Array()
var _mms: Array = []                # MultiMeshInstance3D
var _mm_key: PackedInt32Array = PackedInt32Array()   # shape key index per mm
var _mm_chunk: PackedInt32Array = PackedInt32Array() # chunk index per mm
var _keys: Array = []               # "lumpy_A" ...
var _lib: Array = [{}, {}]          # per LOD: key -> Mesh
var _have_lib := false
var _fallback_mesh: Mesh
var planet_r := 0.0
var world_r := 0.0


func _ready() -> void:
	_load_library()


## Astra's asteroid library: every mesh is named <shape>_<A|B>_LOD<n>; the ore-vein surface is made to take the
## instance colour so one mesh serves every ore.
func _load_library() -> void:
	for lod in 2:
		var ps = load(ROCK_LIB[lod])
		if ps == null:
			continue
		var root: Node = ps.instantiate()
		for c in root.get_children():
			if c is MeshInstance3D and c.mesh:
				var parts: PackedStringArray = c.name.split("_")
				if parts.size() < 3:
					continue
				var key := parts[0] + "_" + parts[1]
				var m: Mesh = c.mesh
				for s in m.get_surface_count():
					var mat = m.surface_get_material(s)
					if mat is StandardMaterial3D and str(mat.resource_name).begins_with("Ore_"):
						mat.vertex_color_use_as_albedo = true
				_lib[lod][key] = m
				if not _keys.has(key):
					_keys.append(key)
		root.free()
	_have_lib = _lib[1].size() > 0
	if not _have_lib:
		_keys = []
		for s in SHAPES:
			for v in ["A", "B"]:
				_keys.append(s + "_" + v)
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		sph.radial_segments = 9
		sph.rings = 5
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		sph.material = mat
		_fallback_mesh = sph
	print("rocks: library %s (%d shape keys)" % ["loaded" if _have_lib else "missing, spheres stand in", _keys.size()])


## Throw the current belt away (zone change).
func clear() -> void:
	for n in _mms:
		n.queue_free()
	_mms = []
	_mm_key = PackedInt32Array()
	_mm_chunk = PackedInt32Array()
	_chunk_centre = []
	_chunk_key = {}
	_chunk_mms = []
	_chunk_rocks = []
	_chunk_lod = PackedInt32Array()
	pos = PackedVector3Array()
	radius = PackedFloat32Array()
	ore = PackedInt32Array()
	hp = PackedFloat32Array()
	hp_max = PackedFloat32Array()
	amount = PackedFloat32Array()
	cls = PackedByteArray()
	alive = PackedByteArray()
	shape = PackedInt32Array()
	chunk_of = PackedInt32Array()
	mm_of = PackedInt32Array()
	slot_of = PackedInt32Array()
	mark_until = PackedFloat32Array()
	_marked = PackedInt32Array()
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


## Which mesh a rock uses: giants and colossals are big rounded, pocked or blocky bodies; other large rocks are
## sometimes hollows; the rest draw from the whole library. A or B variant at random.
func _pick_shape(c: int) -> int:
	var fam: String
	if c >= 2:
		var q := _rng.randf()
		fam = "cratered" if q < 0.45 else ("boulder" if q < 0.7 else ("potato" if q < 0.85 else "bean"))
	elif c == 1 and _rng.randf() < 0.22:
		fam = "hollow"
	else:
		fam = SHAPES[_rng.randi() % (SHAPES.size() - 1)]   # everything but hollow
	var key := fam + "_" + ("A" if _rng.randf() < 0.5 else "B")
	var idx := _keys.find(key)
	return idx if idx >= 0 else 0


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
	shape.append(_pick_shape(c))
	chunk_of.append(-1)
	mm_of.append(-1)
	slot_of.append(-1)
	mark_until.append(0.0)
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
	_chunk_mms.append([])
	_chunk_rocks.append(PackedInt32Array())
	_chunk_lod.append(2)
	return idx


func _mesh_for(key_i: int, lod: int) -> Mesh:
	if not _have_lib:
		return _fallback_mesh
	var key: String = _keys[key_i]
	var lib: Dictionary = _lib[lod - 1]
	return lib.get(key, _lib[1].get(key))


func _build_chunks() -> void:
	# group rocks by (chunk, shape key), then one MultiMesh per group
	var groups := {}   # "chunk:key" -> PackedInt32Array
	var order: Array = []
	for i in count:
		var ci := _chunk_index(pos[i])
		chunk_of[i] = ci
		var cr: PackedInt32Array = _chunk_rocks[ci]
		cr.append(i)
		_chunk_rocks[ci] = cr
		var gk := "%d:%d" % [ci, shape[i]]
		if not groups.has(gk):
			groups[gk] = PackedInt32Array()
			order.append(gk)
		var arr: PackedInt32Array = groups[gk]
		arr.append(i)
		groups[gk] = arr
	for gk in order:
		var rocks: PackedInt32Array = groups[gk]
		var parts: PackedStringArray = gk.split(":")
		var ci := int(parts[0])
		var key_i := int(parts[1])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh_for(key_i, 2)
		mm.instance_count = rocks.size()
		var centre: Vector3 = _chunk_centre[ci]
		var mi := _mms.size()
		for s in rocks.size():
			var i := rocks[s]
			mm_of[i] = mi
			slot_of[i] = s
			mm.set_instance_transform(s, _rock_transform(i, centre))
			mm.set_instance_color(s, _rock_color(i))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.position = centre
		node.custom_aabb = AABB(Vector3(-CHUNK, -CHUNK, -CHUNK) * 0.6, Vector3(CHUNK, CHUNK, CHUNK) * 1.2)
		add_child(node)
		_mms.append(node)
		_mm_key.append(key_i)
		_mm_chunk.append(ci)
		var lst: Array = _chunk_mms[ci]
		lst.append(mi)


func _rock_transform(i: int, centre: Vector3) -> Transform3D:
	var basis := Basis.from_euler(Vector3(_rng.randf() * 6.0, _rng.randf() * 6.0, _rng.randf() * 6.0))
	var stretch := Vector3(_rng.randf_range(0.85, 1.2), _rng.randf_range(0.8, 1.15), _rng.randf_range(0.85, 1.2))
	basis = basis.scaled(stretch * radius[i])
	return Transform3D(basis, pos[i] - centre)


func _rock_color(i: int) -> Color:
	if ore[i] < 0:
		return Color(0.36, 0.34, 0.31).lerp(Color(0.26, 0.25, 0.24), _rng.randf())
	var c: Color = Data.ORES[Data.ORE_KEYS[ore[i]]]["color"]
	return c.lerp(Color.WHITE, 0.15)


## Move every chunk node so that true world coordinates minus `offset` land in scene space (floating origin).
func apply_offset(offset: Vector3) -> void:
	for mi in _mms.size():
		_mms[mi].position = _chunk_centre[_mm_chunk[mi]] - offset


## Hide chunks well beyond the draw distance from the true world point `from`; nearer chunks draw the finer LOD.
func cull(from: Vector3) -> void:
	var lim := DRAW_DIST + CHUNK * 0.87
	var near := LOD1_DIST + CHUNK * 0.87
	for ci in _chunk_centre.size():
		var c: Vector3 = _chunk_centre[ci]
		var d := c.distance_to(from)
		var vis := d < lim
		var lod := 1 if d < near else 2
		var swap := vis and _have_lib and _chunk_lod[ci] != lod
		for mi in _chunk_mms[ci]:
			var node: MultiMeshInstance3D = _mms[mi]
			node.visible = vis
			if swap:
				node.multimesh.mesh = _mesh_for(_mm_key[mi], lod)
		if swap:
			_chunk_lod[ci] = lod


## The rock under the nose: a ray from `origin` along `dir` (true world coordinates), out to `reach`, with the browser
## game's aiming slack (about two degrees plus a few units). Returns the rock id, or -1.
func ray_hit(origin: Vector3, dir: Vector3, reach: float) -> int:
	var best := -1
	var best_t := INF
	var span := reach + CHUNK * 0.87
	for ci in _chunk_centre.size():
		var c: Vector3 = _chunk_centre[ci]
		if c.distance_squared_to(origin) > span * span:
			continue
		for i in _chunk_rocks[ci]:
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
	for i in count:
		if alive[i] == 0 or ore[i] < 0 or (only_ore >= 0 and ore[i] != only_ore):
			continue
		var d2 := pos[i].distance_squared_to(from)
		if d2 < r2:
			n += 1
			if d2 < nd:
				nd = d2
				nearest = i
			if only_ore < 0:
				if mark_until[i] <= State.time:
					_marked.append(i)
				mark_until[i] = State.time + MARK_TIME
	return {"count": n, "nearest": nearest, "dist": sqrt(nd) if nearest >= 0 else 0.0}


## The rocks still carrying a radar mark, nearest first, as [id, distance, seconds left]; expired ones drop off the list.
func marked(now: float, from: Vector3, max_n: int) -> Array:
	var keep := PackedInt32Array()
	var out: Array = []
	for i in _marked:
		if alive[i] == 0 or mark_until[i] <= now:
			continue
		keep.append(i)
		out.append([i, pos[i].distance_to(from), mark_until[i] - now])
	_marked = keep
	out.sort_custom(func(a, b): return a[1] < b[1])
	if out.size() > max_n:
		out.resize(max_n)
	return out


func damage(i: int, dmg: float) -> void:
	hp[i] -= dmg


## Break a rock: hide its instance and return the ore that comes loose (the fragments of a bigger rock are not modelled yet).
func kill(i: int) -> float:
	alive[i] = 0
	var mm: MultiMesh = _mms[mm_of[i]].multimesh
	mm.set_instance_transform(slot_of[i], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var loose: float = amount[i]
	amount[i] = 0.0
	hp[i] = 0.0
	return loose


func rock_name(i: int) -> String:
	var size: String = CLS_NAME[cls[i]] + " " if cls[i] > 0 else ""
	var what: String = "Barren" if ore[i] < 0 else Data.ORES[Data.ORE_KEYS[ore[i]]]["name"]
	return size + what + " rock"

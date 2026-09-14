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
## Rocks ride their orbit rails (the drift is applied in the rock shader from per-instance rail data, so it costs
## nothing per frame), and big rocks break into smaller mineable fragments that coast as their own nodes.

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
# the orbit rails (the HTML's a.ang / a.orbit, or the field's): every rock rides its rail at ORBIT_SPEED counter-clockwise
# seen from above until something sets it adrift; then it coasts in a straight line for good. `pos` holds the position at
# the moment the belt was built; rock_pos() adds the drift since. Rail rocks drift on the GPU (the rock shader reads the
# rail from the instance's custom data), so the belt costs nothing per frame; free rocks are nodes moved here.
const ORBIT_SPEED := 28.0
const RESPAWN_AFTER := 300.0
var ang := PackedFloat32Array()          # the rail's angle at build time (the field's for a field rock)
var orbit := PackedFloat32Array()        # the rail's radius
var free := PackedByteArray()            # 1: off the rail, coasting with `vel`
var vel := PackedVector3Array()
var fragment := PackedByteArray()        # 1: a piece of a broken rock (gone for good when it breaks)
var belt_of := PackedInt32Array()        # index into _belts (for fragment sizing and respawns)
var respawn_at := PackedFloat32Array()   # a broken belt rock grows back near where it was after RESPAWN_AFTER
var amount_max := PackedFloat32Array()
var _basis: Array = []                   # each rock's rotation and stretch, kept so a moved rock draws the same
var _belts: Array = []
var _frag_nodes := {}                    # rock id -> MeshInstance3D for free rocks
var _free_ids := PackedInt32Array()
var _dead := PackedInt32Array()
var _t0 := 0.0
var _elapsed := 0.0
var _offset := Vector3.ZERO
var _respawn_t := 0.0
var _mats: Array = []                    # the rock ShaderMaterials, fed the drift time each frame
var _mat_cache := {}
static var _rock_shader: Shader

## The rock surfaces as a shader: Astra's PBR materials (albedo, roughness and metallic maps, normal map, emission)
## with the orbit drift added in the vertex stage from the instance's custom data (rail angle, rail radius, on-rail flag).
const ROCK_SHADER := """
shader_type spatial;
render_mode world_vertex_coords;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo_tex = false;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform sampler2D tex_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_orm = false;
uniform vec4 metal_mask = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 rough_mask = vec4(0.0, 1.0, 0.0, 0.0);
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D tex_emission : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool has_emission = false;
uniform bool has_emission_tex = false;
uniform float emission_energy = 1.0;
uniform bool vertex_albedo = false;
uniform float u_time = 0.0;


void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	if (cd.z > 0.5) {
		float th = 28.0 * u_time / max(cd.y, 1.0);
		float c = cos(th) - 1.0;
		float s = sin(th);
		float ca = cos(cd.x);
		float sa = sin(cd.x);
		VERTEX += vec3(cd.y * (ca * c + sa * s), 0.0, cd.y * (sa * c - ca * s));
	}
}

void fragment() {
	vec4 base = albedo;
	if (has_albedo_tex) {
		base *= texture(tex_albedo, UV);
	}
	vec3 col = base.rgb;
	if (vertex_albedo) {
		col *= COLOR.rgb;
	}
	ALBEDO = col;
	float m = metallic;
	float r = roughness;
	if (has_orm) {
		vec4 orm = texture(tex_orm, UV);
		m *= dot(orm, metal_mask);
		r *= dot(orm, rough_mask);
	}
	METALLIC = m;
	ROUGHNESS = r;
	if (has_normal) {
		NORMAL_MAP = texture(tex_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (has_emission) {
		vec3 e = emission.rgb;
		if (has_emission_tex) {
			e *= texture(tex_emission, UV).rgb;
		}
		EMISSION = e * emission_energy;
	}
}
"""

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
					if mat is StandardMaterial3D:
						m.surface_set_material(s, _convert_material(mat))
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
		sph.material = _convert_material(mat)
		_fallback_mesh = sph
	print("rocks: library %s (%d shape keys)" % ["loaded" if _have_lib else "missing, spheres stand in", _keys.size()])


## One of Astra's StandardMaterial3Ds as the rock shader with the same look: the maps and factors copied across, the
## ore-vein surfaces taking the instance colour as before.
func _convert_material(sm: StandardMaterial3D) -> ShaderMaterial:
	if _mat_cache.has(sm):
		return _mat_cache[sm]
	if _rock_shader == null:
		_rock_shader = Shader.new()
		_rock_shader.code = ROCK_SHADER
	var m := ShaderMaterial.new()
	m.shader = _rock_shader
	m.resource_name = sm.resource_name
	m.set_shader_parameter("albedo", sm.albedo_color)
	if sm.albedo_texture:
		m.set_shader_parameter("tex_albedo", sm.albedo_texture)
		m.set_shader_parameter("has_albedo_tex", true)
	m.set_shader_parameter("metallic", sm.metallic)
	m.set_shader_parameter("roughness", sm.roughness)
	var orm: Texture2D = sm.metallic_texture if sm.metallic_texture else sm.roughness_texture
	if orm:
		m.set_shader_parameter("tex_orm", orm)
		m.set_shader_parameter("has_orm", true)
		m.set_shader_parameter("metal_mask", _channel_mask(sm.metallic_texture_channel))
		m.set_shader_parameter("rough_mask", _channel_mask(sm.roughness_texture_channel))
	if sm.normal_enabled and sm.normal_texture:
		m.set_shader_parameter("tex_normal", sm.normal_texture)
		m.set_shader_parameter("has_normal", true)
		m.set_shader_parameter("normal_scale", sm.normal_scale)
	if sm.emission_enabled:
		m.set_shader_parameter("emission", sm.emission)
		m.set_shader_parameter("has_emission", true)
		m.set_shader_parameter("emission_energy", sm.emission_energy_multiplier)
		if sm.emission_texture:
			m.set_shader_parameter("tex_emission", sm.emission_texture)
			m.set_shader_parameter("has_emission_tex", true)
	m.set_shader_parameter("vertex_albedo", sm.vertex_color_use_as_albedo or str(sm.resource_name).begins_with("Ore_"))
	_mat_cache[sm] = m
	_mats.append(m)
	return m


static func _channel_mask(ch: int) -> Vector4:
	match ch:
		BaseMaterial3D.TEXTURE_CHANNEL_RED: return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0, 0, 0, 1)
	return Vector4(0.333, 0.333, 0.334, 0)


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
	ang = PackedFloat32Array()
	orbit = PackedFloat32Array()
	free = PackedByteArray()
	vel = PackedVector3Array()
	fragment = PackedByteArray()
	belt_of = PackedInt32Array()
	respawn_at = PackedFloat32Array()
	amount_max = PackedFloat32Array()
	_basis = []
	_belts = []
	for n in _frag_nodes.values():
		n.queue_free()
	_frag_nodes = {}
	_free_ids = PackedInt32Array()
	_dead = PackedInt32Array()
	_elapsed = 0.0
	count = 0


func build(zone: Dictionary, seed: int) -> void:
	_rng.seed = seed
	_t0 = State.time
	_elapsed = 0.0
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
	_belts = belts.duplicate()
	for bi in belts.size():
		var b: Dictionary = belts[bi]
		for i in b["count"]:
			_make_rock(b, null, bi)
		var nf: int = FIELDS_PER_BELT[bi] if bi < FIELDS_PER_BELT.size() else 0
		for f in nf:
			var fld := _make_field(b, density)
			for i in fld["count"]:
				_make_rock(b, fld, bi)
	# rich pockets: tight clusters anywhere in the zone, every ore the zone offers, two and a half times the yield
	var all_ores := {}
	for i in Data.BASE_BELTS.size():
		for k in zone["belts"][i]:
			all_ores[k] = all_ores.get(k, 0.0) + zone["belts"][i][k]
	var pocket_belt := {"name": "Pocket", "rMin": planet_r + 40000.0, "rMax": world_r * 0.9, "size": [30, 96], "amount": [120, 360], "spread": 0.0, "ores": all_ores, "amountMult": amount_mult * 2.5}
	_belts.append(pocket_belt)
	var pocket_bi := _belts.size() - 1
	var np := roundi(30.0 * max(0.7, density))
	for i in np:
		var prad := _rng.randf_range(1500.0, 3500.0)
		var dist := _rng.randf_range(pocket_belt["rMin"], pocket_belt["rMax"])
		var pang := _rng.randf() * TAU
		var lat := asin(_rng.randf_range(-1.0, 1.0)) * 0.85
		var porbit: float = max(planet_r * 0.2, cos(lat) * dist)
		var centre := Vector3(cos(pang) * porbit, sin(lat) * dist, sin(pang) * porbit)
		var fld := {"radius": prad, "center": centre, "ores": all_ores, "count": roundi(_rng.randf_range(40.0, 90.0)), "ang": pang, "orbit": porbit}
		for k in fld["count"]:
			_make_rock(pocket_belt, fld, pocket_bi)
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
	return {"radius": rad, "center": Vector3(cos(ang) * orbit, y, sin(ang) * orbit), "ores": w, "count": roundi(_rng.randf_range(45.0, 85.0) * density), "ang": ang, "orbit": orbit}


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


func _make_rock(b: Dictionary, fld, bi: int) -> void:
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
	# the rail: a field rock rides its field's rail (it keeps its offset from the centre); a loose rock has its own
	var ra: float = fld["ang"] if fld != null else atan2(p.z, p.x)
	var ro: float = fld["orbit"] if fld != null else sqrt(p.x * p.x + p.z * p.z)
	_append_rock(p, base_r, -1 if barren else Data.ORE_KEYS.find(ore_key), hpm, 0.0 if barren else amt, c, _pick_shape(c), ra, ro, bi, false, Vector3.ZERO)


## One row in every array. Rail rocks join a chunk's MultiMesh in _build_chunks; free ones (fragments) get a node now.
func _append_rock(p: Vector3, r: float, ore_i: int, hpm: float, amt: float, c: int, shape_i: int, ra: float, ro: float, bi: int, is_free: bool, v: Vector3) -> int:
	var i := count
	pos.append(p)
	radius.append(r)
	ore.append(ore_i)
	hp.append(hpm)
	hp_max.append(hpm)
	amount.append(amt)
	amount_max.append(amt)
	cls.append(c)
	alive.append(1)
	shape.append(shape_i)
	chunk_of.append(-1)
	mm_of.append(-1)
	slot_of.append(-1)
	mark_until.append(0.0)
	ang.append(ra)
	orbit.append(max(1.0, ro))
	free.append(1 if is_free else 0)
	vel.append(v)
	fragment.append(0)
	belt_of.append(bi)
	respawn_at.append(0.0)
	var basis := Basis.from_euler(Vector3(_rng.randf() * 6.0, _rng.randf() * 6.0, _rng.randf() * 6.0))
	basis = basis.scaled(Vector3(_rng.randf_range(0.85, 1.2), _rng.randf_range(0.8, 1.15), _rng.randf_range(0.85, 1.2)) * r)
	_basis.append(basis)
	count += 1
	return i


# ---- the rails: where a rock is now, and how fast it is going
## The drift since the belt was built for a rail with angle `a` and radius `o` (a rotation by 28 / o radians a second,
## counter-clockwise seen from above), written so nothing large is subtracted from anything large.
func _delta(a: float, o: float) -> Vector3:
	var th := ORBIT_SPEED * _elapsed / o
	var c := cos(th) - 1.0
	var s := sin(th)
	var ca := cos(a)
	var sa := sin(a)
	return Vector3(o * (ca * c + sa * s), 0.0, o * (sa * c - ca * s))


func rock_pos(i: int) -> Vector3:
	if free[i] == 1:
		return pos[i]
	return pos[i] + _delta(ang[i], orbit[i])


## The HTML's orbitalVel: 28 u/s along the rail (a free rock's own velocity).
func rock_vel(i: int) -> Vector3:
	if free[i] == 1:
		return vel[i]
	var a: float = ang[i] - ORBIT_SPEED * _elapsed / orbit[i]
	return Vector3(sin(a) * ORBIT_SPEED, 0.0, -cos(a) * ORBIT_SPEED)


## Knock a rock off its rail (setAdrift): from here on it is a node coasting with `v`.
func set_free(i: int, v: Vector3) -> void:
	if free[i] == 1:
		vel[i] = v
		return
	pos[i] = rock_pos(i)
	free[i] = 1
	vel[i] = v
	if mm_of[i] >= 0:
		var mm: MultiMesh = _mms[mm_of[i]].multimesh
		mm.set_instance_transform(slot_of[i], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_make_node(i)
	_free_ids.append(i)


## A free rock's own node: a one-instance MultiMesh, so it carries its ore colour the same way the chunks do (an
## instance uniform would cost a buffer slot on every chunk node instead).
func _make_node(i: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh_for(shape[i], 1)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(_basis[i], Vector3.ZERO))
	mm.set_instance_color(0, _rock_color(i))
	mm.set_instance_custom_data(0, Color(0.0, 1.0, 0.0, 0.0))   # off the rails: no drift in the shader
	var n := MultiMeshInstance3D.new()
	n.multimesh = mm
	n.position = pos[i] - _offset
	add_child(n)
	_frag_nodes[i] = n


## A piece of a broken rock (splitRock's fragments): a smaller rock of the next class down, adrift from the start.
func add_fragment(c: int, r: float, ore_i: int, barren: bool, p: Vector3, amt: float, v: Vector3, bi: int) -> int:
	var hpm := roundf(40.0 + 2.2 * pow(r, 1.15))
	var i := _append_rock(p, r, -1 if barren else ore_i, hpm, 0.0 if barren else amt, c, _pick_shape(c), 0.0, 1.0, bi, true, v)
	fragment[i] = 1
	var ci := _chunk_index(p)
	chunk_of[i] = ci
	var cr: PackedInt32Array = _chunk_rocks[ci]
	cr.append(i)
	_chunk_rocks[ci] = cr
	_make_node(i)
	_free_ids.append(i)
	return i


## Every frame: the drift time for the rock shader, free rocks coasting (bouncing off the zone edge, coming to rest on
## the planet), and broken belt rocks growing back.
func tick(dt: float) -> void:
	_elapsed = State.time - _t0
	for m in _mats:
		m.set_shader_parameter("u_time", _elapsed)
	if _free_ids.size() > 0:
		var keep := PackedInt32Array()
		for i in _free_ids:
			if alive[i] == 0:
				continue
			keep.append(i)
			var p: Vector3 = pos[i] + vel[i] * dt
			var d := p.length()
			if d > world_r:
				vel[i] = vel[i].reflect(p / d)
				p *= world_r / d
			elif planet_r > 0.0 and d < planet_r * 1.006 + radius[i]:
				vel[i] = Vector3.ZERO
				p *= (planet_r * 1.006 + radius[i]) / d
			pos[i] = p
			var n: Node3D = _frag_nodes.get(i)
			if n:
				n.position = p - _offset
		_free_ids = keep
	_respawn_t += dt
	if _respawn_t > 1.0 and _dead.size() > 0:
		_respawn_t = 0.0
		var still := PackedInt32Array()
		for i in _dead:
			if State.time >= respawn_at[i]:
				_respawn(i)
			else:
				still.append(i)
		_dead = still


## A broken belt rock grows back: a fresh rock in its belt, placed in the same chunk (so its MultiMesh still draws it
## in the right place) and back on a rail, with its health and ore restored.
func _respawn(i: int) -> void:
	var b: Dictionary = _belts[belt_of[i]] if belt_of[i] < _belts.size() else {}
	var centre: Vector3 = _chunk_centre[chunk_of[i]] if chunk_of[i] >= 0 else pos[i]
	var target: Vector3 = rock_pos(i)
	if not b.is_empty():
		for t in 30:
			var q := centre + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * CHUNK
			var o := sqrt(q.x * q.x + q.z * q.z)
			if o >= float(b["rMin"]) and o <= float(b["rMax"]) and q.length() > planet_r * 1.02:
				target = q
				break
	if free[i] == 1:
		free[i] = 0
		vel[i] = Vector3.ZERO
		var n: Node3D = _frag_nodes.get(i)
		if n:
			n.queue_free()
			_frag_nodes.erase(i)
	ang[i] = atan2(target.z, target.x)
	orbit[i] = max(1.0, sqrt(target.x * target.x + target.z * target.z))
	pos[i] = target - _delta(ang[i], orbit[i])
	hp[i] = hp_max[i]
	amount[i] = amount_max[i]
	alive[i] = 1
	respawn_at[i] = 0.0
	mark_until[i] = 0.0
	if mm_of[i] >= 0:
		var mm: MultiMesh = _mms[mm_of[i]].multimesh
		mm.set_instance_transform(slot_of[i], Transform3D(_basis[i], pos[i] - centre))
		mm.set_instance_custom_data(slot_of[i], Color(ang[i], orbit[i], 1.0, 0.0))


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
		mm.use_custom_data = true
		mm.mesh = _mesh_for(key_i, 2)
		mm.instance_count = rocks.size()
		var centre: Vector3 = _chunk_centre[ci]
		var mi := _mms.size()
		for s in rocks.size():
			var i := rocks[s]
			mm_of[i] = mi
			slot_of[i] = s
			mm.set_instance_transform(s, Transform3D(_basis[i], pos[i] - centre))
			mm.set_instance_color(s, _rock_color(i))
			mm.set_instance_custom_data(s, Color(ang[i], orbit[i], 1.0, 0.0))   # the rail, read by the rock shader
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.position = centre
		# rocks drift 100 km an hour, so the bounds allow for a long session before a chunk's rocks leave them
		node.custom_aabb = AABB(Vector3(-CHUNK, -CHUNK, -CHUNK) * 1.1, Vector3(CHUNK, CHUNK, CHUNK) * 2.2)
		add_child(node)
		_mms.append(node)
		_mm_key.append(key_i)
		_mm_chunk.append(ci)
		var lst: Array = _chunk_mms[ci]
		lst.append(mi)


func _rock_color(i: int) -> Color:
	if ore[i] < 0:
		return Color(0.36, 0.34, 0.31).lerp(Color(0.26, 0.25, 0.24), _rng.randf())
	var c: Color = Data.ORES[Data.ORE_KEYS[ore[i]]]["color"]
	return c.lerp(Color.WHITE, 0.15)


## Move every chunk node so that true world coordinates minus `offset` land in scene space (floating origin).
func apply_offset(offset: Vector3) -> void:
	_offset = offset
	for mi in _mms.size():
		_mms[mi].position = _chunk_centre[_mm_chunk[mi]] - offset
	for i in _frag_nodes:
		_frag_nodes[i].position = pos[i] - offset


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


## Every live rock in the chunks within `range` of `from` (true world coordinates), for the hover pick.
func rocks_near(from: Vector3, range: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var span: float = range + CHUNK * 0.87 + minf(ORBIT_SPEED * _elapsed, CHUNK)
	for ci in _chunk_centre.size():
		var c: Vector3 = _chunk_centre[ci]
		if c.distance_squared_to(from) > span * span:
			continue
		for i in _chunk_rocks[ci]:
			if alive[i] == 1:
				out.append(i)
	return out


## The rock under the nose: a ray from `origin` along `dir` (true world coordinates), out to `reach`, with the browser
## game's aiming slack (about two degrees plus a few units). Returns the rock id, or -1.
func ray_hit(origin: Vector3, dir: Vector3, reach: float) -> int:
	var best := -1
	var best_t := INF
	var span: float = reach + CHUNK * 0.87 + minf(ORBIT_SPEED * _elapsed, CHUNK)   # rocks drift out of their chunk over a long session
	for ci in _chunk_centre.size():
		var c: Vector3 = _chunk_centre[ci]
		if c.distance_squared_to(origin) > span * span:
			continue
		for i in _chunk_rocks[ci]:
			if alive[i] == 0:
				continue
			var to := rock_pos(i) - origin
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
		var d2 := rock_pos(i).distance_squared_to(from)
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
		out.append([i, rock_pos(i).distance_to(from), mark_until[i] - now])
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
	if mm_of[i] >= 0 and free[i] == 0:
		var mm: MultiMesh = _mms[mm_of[i]].multimesh
		mm.set_instance_transform(slot_of[i], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var n: Node3D = _frag_nodes.get(i)
	if n:
		n.queue_free()
		_frag_nodes.erase(i)
	var loose: float = amount[i]
	amount[i] = 0.0
	hp[i] = 0.0
	if fragment[i] == 0:
		respawn_at[i] = State.time + RESPAWN_AFTER   # a belt rock grows back; a fragment is simply gone
		_dead.append(i)
	return loose


func rock_name(i: int) -> String:
	var size: String = CLS_NAME[cls[i]] + " " if cls[i] > 0 else ""
	var what: String = "Barren" if ore[i] < 0 else Data.ORES[Data.ORE_KEYS[ore[i]]]["name"]
	return size + what + " rock"

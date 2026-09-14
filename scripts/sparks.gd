class_name Sparks
extends MultiMeshInstance3D
## The browser's SPARKS: short glowing streaks thrown out by a breaking rock or a hull hit, additive, each stretched
## along its own velocity (the streak is the last 60 ms of its travel) and thinning as it dies. One MultiMesh of boxes;
## positions are true world coordinates, placed against the floating origin each frame.

const MAX := 2000
const TRAIL := 0.06

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _col := PackedColorArray()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _mm: MultiMesh
var _high := 0   # the highest slot drawn since the last frame


func _init() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	box.material = mat
	_mm.mesh = box
	_mm.instance_count = MAX
	for s in MAX:
		_mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	multimesh = _mm
	custom_aabb = AABB(Vector3.ONE * -400000.0, Vector3.ONE * 800000.0)


## burst(p, count, spd, hex, sz): sparks fly out in every direction at a quarter to the whole of `spd`, live half a
## second to a second and a half, 1.4 to 3.2 units wide times `sz`.
func burst(p: Vector3, count: int, spd: float, c: Color, sz: float) -> void:
	for k in count:
		if _pos.size() >= MAX:
			_drop(0)
		var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(spd * 0.25, spd)
		_pos.append(p + Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)))
		_vel.append(d)
		_col.append(c)
		_age.append(0.0)
		_life.append(randf_range(0.5, 1.5))
		_size.append(randf_range(1.4, 3.2) * sz)


func _drop(s: int) -> void:
	_pos.remove_at(s)
	_vel.remove_at(s)
	_col.remove_at(s)
	_age.remove_at(s)
	_life.remove_at(s)
	_size.remove_at(s)


func clear() -> void:
	while _pos.size() > 0:
		_drop(0)


func count() -> int:
	return _pos.size()


func tick(dt: float, offset: Vector3) -> void:
	if _pos.size() == 0 and _high == 0:
		return
	var damp := exp(-0.9 * dt)
	var s := _pos.size() - 1
	while s >= 0:
		var age: float = _age[s] + dt
		if age >= _life[s]:
			_drop(s)
			s -= 1
			continue
		_age[s] = age
		var v: Vector3 = _vel[s] * damp
		_vel[s] = v
		var p: Vector3 = _pos[s] + v * dt
		_pos[s] = p
		var fade: float = age / _life[s]
		var w: float = _size[s] * (1.0 - 0.5 * fade)
		var len: float = max(v.length() * TRAIL, w)
		var dir: Vector3 = v.normalized() if v.length_squared() > 1e-6 else Vector3.FORWARD
		var side: Vector3 = dir.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up: Vector3 = side.cross(dir)
		var basis := Basis(side * w, up * w, dir * len)
		_mm.set_instance_transform(s, Transform3D(basis, p - offset))
		var c: Color = _col[s]
		c.a = 1.0 - fade
		_mm.set_instance_color(s, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
		s -= 1
	# slots freed this frame are zeroed once
	for k in range(_pos.size(), _high):
		_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_high = _pos.size()

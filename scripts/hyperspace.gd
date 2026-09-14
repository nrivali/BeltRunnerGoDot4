class_name Hyperspace
extends CanvasLayer
## The cargo ship's hyperspace jump, ported from assets/hyperspace/hyperspace.js: the timeline (charge 1.6 s, launch
## 0.45 s, transit 2.45 s, arrival 1.15 s, settle 0.6 s) with the pose it gives each frame (the carrier's forward offset
## and stretch, the engine gain, the tunnel's coverage and flash, the star trails and their length, the camera's field
## of view), and the two visuals: a full-screen tunnel shader and camera-space star ribbons with real length. The game
## applies the pose to the rendered carrier only; docking anchors and orbit stay where they are.

const CHARGE := 1.6
const LAUNCH := 0.45
const TRANSIT := 2.45
const ARRIVAL := 1.15
const SETTLE := 0.6
const TRANSIT_AT := CHARGE + LAUNCH
const ARRIVAL_AT := TRANSIT_AT + TRANSIT
const DURATION := ARRIVAL_AT + ARRIVAL + SETTLE
const STARS := 640

const TUNNEL_SHADER := """
shader_type canvas_item;
uniform float u_time = 0.0;
uniform float u_coverage = 0.0;
uniform float u_flash = 0.0;
uniform float u_aspect = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.13, 0.37, 0.73));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y), mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return 0.57 * vnoise(p) + 0.28 * vnoise(p * 2.03 + 8.7) + 0.15 * vnoise(p * 4.07 + 3.1);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(u_aspect, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	float depth = 1.0 / (r + 0.075);
	float twist = a + 0.10 * depth - 0.12 * u_time;
	vec3 q = vec3(cos(twist) * 3.0, sin(twist) * 3.0, depth * 1.15 - u_time * 2.5);
	float cloud = fbm(q);
	float filament = pow(max(0.0, fbm(q * 1.8 + 4.0) - 0.36), 2.0) * 3.0;
	float walls = smoothstep(0.055, 0.38, r);
	float haze = exp(-r * 9.0);
	vec3 color = vec3(0.004, 0.014, 0.042) + vec3(0.025, 0.22, 0.55) * cloud * walls + vec3(0.23, 0.52, 0.75) * filament * walls;
	color += vec3(0.12, 0.25, 0.34) * haze;
	color *= 1.0 - 0.48 * smoothstep(0.35, 1.0, r);
	float alpha = max(u_coverage, u_flash * 0.72);
	color = mix(color, vec3(0.65, 0.85, 1.0), u_flash);
	COLOR = vec4(color, alpha);
}
"""

var _tunnel: ColorRect
var _mat: ShaderMaterial
var _streaks: Streaks


static func smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## The pose at `time` seconds into the jump (hyperspace.js sample()).
static func sample(time: float) -> Dictionary:
	var t: float = max(0.0, time)
	var charge := clampf(t / CHARGE, 0.0, 1.0)
	var launch := clampf((t - CHARGE) / LAUNCH, 0.0, 1.0)
	var arrival := clampf((t - ARRIVAL_AT) / ARRIVAL, 0.0, 1.0)
	var phase := "depart" if t < TRANSIT_AT else ("transit" if t < ARRIVAL_AT else ("arrive" if t < DURATION else "done"))
	var leaving := phase == "depart"
	var in_transit := phase == "transit"
	var arriving := phase == "arrive"
	var snap := clampf((t - ARRIVAL_AT) / 0.42, 0.0, 1.0)
	var offset := 0.0
	var stretch := 1.0
	var gain := 1.0
	var coverage := 0.0
	var trails := 0.0
	var trail_len := 0.0
	var flash := 0.0
	var fov := 62.0
	if leaving:
		offset = 110000.0 * pow(launch, 3.0)
		stretch = 1.0 + 2.8 * smooth(launch / 0.45) * (1.0 - smooth((launch - 0.8) / 0.2))
		gain = 1.0 + 3.0 * charge + 2.0 * launch
		coverage = smooth((launch - 0.48) / 0.52)
		trails = smooth((t - CHARGE + 0.18) / 0.3)
		trail_len = 0.06 + 1.8 * smooth(launch)
		flash = sin(PI * clampf((launch - 0.25) / 0.75, 0.0, 1.0)) * 0.48
		fov = 56.0 - 5.0 * smooth(charge) + 18.0 * smooth(launch)
	elif in_transit:
		gain = 4.0
		coverage = 1.0
		trails = 1.0
		trail_len = 2.6
		fov = 69.0
	elif arriving:
		offset = -85000.0 * pow(1.0 - snap, 5.0)
		stretch = 1.0 + 2.6 * pow(1.0 - snap, 3.0)
		gain = 1.0 + 3.0 * (1.0 - arrival)
		coverage = 1.0 - smooth((t - ARRIVAL_AT) / 0.24)
		trails = 1.0 - smooth((t - ARRIVAL_AT) / 0.65)
		trail_len = 0.08 + 2.5 * (1.0 - arrival)
		flash = sin(PI * clampf((t - ARRIVAL_AT) / 0.32, 0.0, 1.0)) * 0.24
		fov = 62.0 + 7.0 * (1.0 - smooth(arrival))
	return {"phase": phase, "done": t >= DURATION, "offset": offset, "stretch": stretch, "gain": gain, "coverage": coverage, "trails": trails, "length": trail_len, "flash": flash, "fov": fov}


## The covered edit at the end of a belt arrival (cameraShots.cover) and the uncover once the ship is on its pad.
static func cover(time: float) -> float:
	return smooth((time - DURATION + 0.35) / 0.35)


static func uncover(time: float) -> float:
	return 1.0 - smooth(time / 0.5)


## Camera-space star ribbons: 640 rays at fixed angles and radii, each streaming toward the camera from a point far
## down the nose, drawn as a thin quad from its tail to its head with the head brighter (the browser's streak shader).
class Streaks extends Control:
	var rays: PackedVector4Array = PackedVector4Array()   # x, y, phase, speed
	var time := 0.0
	var trails := 0.0
	var length := 0.0
	var aspect := 1.0
	var center := Vector2.ZERO   # in NDC (-1..1), where the streaks converge

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		var seed := 23191
		for i in Hyperspace.STARS:
			seed = int((1664525 * seed + 1013904223) % 4294967296)
			var angle := seed / 4294967296.0 * TAU
			seed = int((1664525 * seed + 1013904223) % 4294967296)
			var radius := 140.0 + sqrt(seed / 4294967296.0) * 4000.0
			seed = int((1664525 * seed + 1013904223) % 4294967296)
			var phase := seed / 4294967296.0
			seed = int((1664525 * seed + 1013904223) % 4294967296)
			var speed := 0.65 + seed / 4294967296.0 * 0.65
			rays.append(Vector4(cos(angle) * radius, sin(angle) * radius, phase, speed))

	func _px(ndc: Vector2) -> Vector2:
		return Vector2((ndc.x * 0.5 + 0.5) * size.x, (0.5 - ndc.y * 0.5) * size.y)

	func _draw() -> void:
		if trails <= 0.001:
			return
		var tail_col := Color(0.12, 0.4, 0.85)
		var head_col := Color(0.86, 0.96, 1.0)
		for r in rays:
			var progress := fmod(r.z + time * r.w * 0.85, 1.0)
			var fade := trails * smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.92, 1.0, progress))
			if fade < 0.01:
				continue
			var z := 5200.0 - progress * 5000.0
			var tail_z := z + 50.0 + length * 1050.0
			var head := Vector2(r.x, r.y) / z
			var tail := Vector2(r.x, r.y) / tail_z
			head.x /= aspect
			tail.x /= aspect
			head += center
			tail += center
			var hp := _px(head)
			var tp := _px(tail)
			var d := hp - tp
			if d.length_squared() < 1e-6:
				continue
			d = d.normalized()
			var perp: Vector2 = Vector2(-d.y, d.x) * maxf(1.0, (1.2 + r.w * 0.7) * 0.6)
			var ta := Color(tail_col, 0.16 * fade)
			var ha := Color(head_col, fade)
			draw_polygon(PackedVector2Array([tp + perp, tp - perp, hp - perp, hp + perp]), PackedColorArray([ta, ta, ha, ha]))


func _ready() -> void:
	layer = 4   # under the HUD (5), over the world
	_tunnel = ColorRect.new()
	_tunnel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tunnel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = TUNNEL_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_tunnel.material = _mat
	add_child(_tunnel)
	_streaks = Streaks.new()
	add_child(_streaks)
	visible = false


## Drive the visuals from the pose: the tunnel's coverage and flash, the trails, and the point they stream from (a spot
## far down the carrier's nose, pulled to the screen centre as the tunnel closes in).
func update(pose: Dictionary, time: float, cam: Camera3D, nose: Vector3) -> void:
	visible = true
	var vp := cam.get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(1.0, vp.y)
	_mat.set_shader_parameter("u_time", time)
	_mat.set_shader_parameter("u_coverage", float(pose["coverage"]))
	_mat.set_shader_parameter("u_flash", float(pose["flash"]))
	_mat.set_shader_parameter("u_aspect", aspect)
	var far := cam.global_position + nose * 200000.0
	var c := Vector2.ZERO
	if not cam.is_position_behind(far):
		var sp := cam.unproject_position(far)
		c = Vector2(sp.x / vp.x * 2.0 - 1.0, 1.0 - sp.y / vp.y * 2.0)
	var blend: float = pose["coverage"]
	_streaks.center = Vector2(clampf(c.x, -1.5, 1.5), clampf(c.y, -1.5, 1.5)) * (1.0 - blend)
	_streaks.time = time
	_streaks.trails = pose["trails"]
	_streaks.length = pose["length"]
	_streaks.aspect = aspect
	_streaks.queue_redraw()


func reset() -> void:
	visible = false
	_streaks.trails = 0.0
	_streaks.queue_redraw()

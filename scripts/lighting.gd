class_name Lighting
extends Node
## The look of space, ported from Astra's lighting module (assets/lighting/space-lighting.js) and the browser's sky:
## an ACES-tonemapped sun at the zone's colour and exposure with soft shadows focused round the ship, a faint bounce
## and ambient from the sky, reflections off the hulls from the same sky, a visible sun disc with an optical glare,
## a nebula backdrop with a dust band, and a couple of thousand stars. The sky is a shader, so it costs nothing to
## build and the sun disc follows the zone's light automatically. Glow gives the emissive strips and engine glows
## their bloom.

## Per-zone sun profiles (the HTML's `profiles`): colour, strength, the disc's angular radius, and the exposure.
const PROFILES := {
	"hub":     {"color": Color("#fff6eb"), "intensity": 5.0, "radius": 0.0085, "exposure": 1.05},
	"kessler": {"color": Color("#fff3e3"), "intensity": 5.3, "radius": 0.0090, "exposure": 1.05},
}

const SKY_SHADER := """
shader_type sky;

uniform vec3 base_color : source_color = vec3(0.020, 0.027, 0.063);
uniform vec3 nebula_a : source_color = vec3(0.22, 0.125, 0.376);
uniform vec3 nebula_b : source_color = vec3(0.094, 0.188, 0.282);
uniform vec3 band_color : source_color = vec3(0.118, 0.125, 0.165);
uniform float sun_radius = 0.009;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float star_gain = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.0 + 7.0) * 0.3 + vnoise(p * 4.1 + 3.0) * 0.2;
}

void sky() {
	vec3 d = EYEDIR;
	// the nebula: two noise fields, a dust band round the ecliptic tilted by a slow wave, as the browser's sky texture
	float n1 = fbm(d * 2.2 + 3.0);
	float n2 = fbm(d * 3.1 + 13.0);
	float lon = atan(d.z, d.x);
	float band = exp(-pow((d.y - 0.07 * sin(lon + 1.2)) / 0.075, 2.0)) * (0.35 + 0.65 * n2);
	float neb = max(0.0, n1 - 0.52) * 2.2;
	float neb2 = max(0.0, n2 - 0.6) * 2.4;
	vec3 col = base_color + neb * nebula_a + neb2 * nebula_b + band * band_color;
	// stars: a sparse hash over direction cells, a brighter few among them
	vec3 sp = d * 240.0;
	vec3 cell = floor(sp);
	float h = hash(cell);
	if (h > 0.9955) {
		vec3 c = vec3(hash(cell + 1.0), hash(cell + 2.0), hash(cell + 3.0));
		float dist = length(fract(sp) - 0.5 - (c - 0.5) * 0.5);
		float bright = h > 0.9993 ? 2.4 : 0.9;
		float s = smoothstep(0.11, 0.0, dist) * bright * star_gain;
		col += s * mix(vec3(0.72, 0.76, 0.83), vec3(0.9, 0.92, 0.97), hash(cell + 5.0));
	}
	// the sun: a hard disc and a small optical glare, both in HDR so the glow pass picks them up
	if (LIGHT0_ENABLED) {
		float c = dot(d, LIGHT0_DIRECTION);
		float a = acos(clamp(c, -1.0, 1.0));
		float disc = 1.0 - smoothstep(sun_radius * 0.97, sun_radius, a);
		float r = a / sun_radius;
		float halo = 1.15 * exp(-r * 1.9) + 0.24 * exp(-r * 0.6);
		// the reflection map gets a gentler disc: at full strength every metal ore vein mirrors it as a white blob
		float disc_gain = AT_CUBEMAP_PASS ? 1.6 : 6.0;
		col += sun_color * (disc * disc_gain + halo * 0.35);
	}
	COLOR = col;
}
"""

const SHADOW_REACH := 3300.0          # the browser's 2,400 u shadow box round a focus 900 u ahead of the camera
const SHADOW_REACH_CARRIER := 6500.0  # 5,600 u near the carrier, so the hangar and the hull shadow properly
const CARRIER_NEAR := 11000.0

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial


func setup(root: Node3D) -> void:
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# the browser's fill is a faint hemisphere bounce (0xc9ced5 over 0x494139 at 0.16) and an ambient of 0.025, both
	# through a Lambert with 1/pi: a fixed colour of about that strength here, with the hulls' reflections from the sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.61, 0.60)
	env.ambient_light_energy = 0.06
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#fff4e4")
	sun.light_energy = 1.7
	sun.light_specular = 0.35   # the ore veins are near-mirror metal; a full point-sun highlight on them is a white blob
	# shadows as the browser casts them: one orthographic box round the ship (extent 2,400 u ahead of the focus, 5,600 near
	# the carrier), so the texels stay under a unit and no split seam or coarse far map ever lands on a rock face
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = SHADOW_REACH
	sun.directional_shadow_fade_start = 0.8
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = 0.5
	root.add_child(sun)


## The zone's sun: direction, colour, strength, disc size, exposure; and its sky colours.
func set_zone(z: Dictionary) -> void:
	var p: Dictionary = PROFILES.get(z["id"], PROFILES["kessler"])
	var dir: Vector3 = (z["sunDir"] as Vector3).normalized()
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	sun.light_color = p["color"]
	sun.light_energy = 1.7 * float(p["intensity"]) / 5.2
	env.tonemap_exposure = p["exposure"]
	sky_mat.set_shader_parameter("sun_radius", float(p["radius"]))
	sky_mat.set_shader_parameter("sun_color", (p["color"] as Color).lerp(Color.WHITE, 0.3))
	var bg: Color = z["bg"]
	sky_mat.set_shader_parameter("base_color", bg.lerp(Color(0.02, 0.027, 0.063), 0.5))


## Every frame: the shadow box grows near the carrier, as the browser's does.
func update(cam_pos: Vector3, carrier_pos: Vector3) -> void:
	var reach: float = SHADOW_REACH_CARRIER if cam_pos.distance_to(carrier_pos) < CARRIER_NEAR else SHADOW_REACH
	if sun.directional_shadow_max_distance != reach:
		sun.directional_shadow_max_distance = reach

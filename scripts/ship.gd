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

# the Q lock (the HTML's lock / hover / lockType / lockDist): Q locks whatever the mouse is over, switches to a different
# hovered target, or releases; the ship steers itself to keep the lock on the nose ray until it is released
const LOCK_RANGE := 100000.0   # a lock holds out to this distance (well beyond laser reach: it is for navigating to things too)
var lock_kind := ""            # "", "rock" or "station" (the cargo ship)
var lock_rock := -1
var lock_dist := 0.0
var hover := {}                # what the mouse is over this frame: kind, rock, dist, name
var _hover_frame := 0

# the tow tug (the HTML's tow / disabled): a hull breach disables the ship, which drifts with no thrust or steering until
# a tug from the cargo ship arrives, latches on with a tractor beam and hauls it nose-first into a hangar bay; running
# dry (T) calls the same tug. phase: approach, latch, haul, leave
var tow := {}
var disabled := false

# collisions with rocks and scrap (the HTML's rock sweep and impact): the rocks within reach are refreshed twice a
# second; each frame the ship's path is swept against them in short steps so a fast ship cannot skip through a rock
const IMPACT_SAFE := 140.0   # normal-speed below this is a harmless bump
var near_rocks := PackedInt32Array()
var _near_frame := 0
var _prev_pos := Vector3.ZERO
var hit_cd := 0.0
var shake := 0.0
var _low_hull_warned := false

# free look: with the right button held the mouse swings the camera instead of the ship; it eases back on release
var look_yaw := 0.0
var look_pitch := 0.0
var rdown := false

# the radar pulse's visuals (pulseSphere / pulseRing): a faint sphere and a bright ring growing to scanner range
var pulse := {}
var _pulse_sphere: MeshInstance3D
var _pulse_ring: MeshInstance3D
# the engines' exhaust glows, the navigation lights and the engine light (exhausts / navLights / shipLight)
var _exhausts: Array = []
var _exhaust_mat: StandardMaterial3D
var _nav_lights: Array = []
var _engine_lights: Array = []
var _tug: Node3D
var _tug_strobe: StandardMaterial3D
var _tug_light: OmniLight3D
var _tow_beam: MeshInstance3D


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
	_build_tug()


## The tow tug (the HTML's towGroup): a stubby cargo-ship tug with a lit cab, twin engines, an amber strobe and a
## tractor emitter at the rear. Built nose along -Z. Top level: it flies in true coordinates like the ship.
func _build_tug() -> void:
	_tug = Node3D.new()
	_tug.name = "Tug"
	_tug.top_level = true
	_tug.visible = false
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.64, 0.7)
	metal.metallic = 0.6
	metal.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.23, 0.25, 0.34)
	dark.metallic = 0.7
	dark.roughness = 0.5
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(0.5, 0.85, 1.0)
	window.emission_enabled = true
	window.emission = Color(0.5, 0.85, 1.0)
	window.emission_energy_multiplier = 2.0
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Ui.AMBER
	trim.emission_enabled = true
	trim.emission = Ui.AMBER
	trim.emission_energy_multiplier = 0.6
	_tug_box(Vector3(12, 7, 20), metal, Vector3(0, 0, 0))
	_tug_box(Vector3(8, 4, 7), dark, Vector3(0, 5, -4))
	_tug_box(Vector3(7, 1.6, 0.5), window, Vector3(0, 5.4, -7.6))
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.0
		cyl.bottom_radius = 2.4
		cyl.height = 8.0
		cyl.radial_segments = 10
		e.mesh = cyl
		e.material_override = dark
		e.rotation_degrees = Vector3(90, 0, 0)
		e.position = Vector3(sx * 6.5, -1, 8)
		_tug.add_child(e)
		var g := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 2.6
		sph.height = 5.2
		g.mesh = sph
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Ui.AMBER
		gm.emission_enabled = true
		gm.emission = Ui.AMBER
		gm.emission_energy_multiplier = 3.0
		g.material_override = gm
		g.position = Vector3(sx * 6.5, -1, 13.5)
		_tug.add_child(g)
		_tug_box(Vector3(1.2, 3, 4), dark, Vector3(sx * 5, -4.5, 9))
	var em := MeshInstance3D.new()
	var ec := CylinderMesh.new()
	ec.top_radius = 1.6
	ec.bottom_radius = 2.2
	ec.height = 3.0
	ec.radial_segments = 10
	em.mesh = ec
	em.material_override = trim
	em.rotation_degrees = Vector3(90, 0, 0)
	em.position = Vector3(0, -1, 11)
	_tug.add_child(em)
	var strobe := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 1.2
	ss.height = 2.4
	strobe.mesh = ss
	_tug_strobe = StandardMaterial3D.new()
	_tug_strobe.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tug_strobe.albedo_color = Ui.AMBER
	strobe.material_override = _tug_strobe
	strobe.position = Vector3(0, 8, 0)
	_tug.add_child(strobe)
	_tug_light = OmniLight3D.new()
	_tug_light.light_color = Ui.AMBER
	_tug_light.light_energy = 6.0 / PI
	_tug_light.omni_range = 400.0
	_tug_light.omni_attenuation = 1.4
	_tug_light.position = Vector3(0, 8, 0)
	_tug.add_child(_tug_light)
	add_child(_tug)
	# the tractor beam: a pale cyan cylinder from the emitter to the ship's nose, additive and faint
	_tow_beam = MeshInstance3D.new()
	_tow_beam.top_level = true
	var bc := CylinderMesh.new()
	bc.top_radius = 1.0
	bc.bottom_radius = 1.0
	bc.height = 1.0
	bc.radial_segments = 8
	_tow_beam.mesh = bc
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.56, 0.91, 1.0, 0.3)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tow_beam.material_override = bm
	_tow_beam.visible = false
	add_child(_tow_beam)


func _tug_box(size: Vector3, mat: Material, at: Vector3) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = mat
	b.position = at
	_tug.add_child(b)


const MODEL := "res://assets/ship/player_ship.glb"
var model: Node3D
var _dish_yaw: Node
var _dish_pitch: Node
var _focus: Node
var _dish_mount := Vector3(0.0, -3.4, 7.0)
var _rim_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _focus_mat: StandardMaterial3D
var _rim_beams: Array = []
var _focus_glow: MeshInstance3D
var aim_yaw := 0.0
var aim_pitch := 0.05
var aimed := false
var has_aim := false
var aim_point := Vector3.ZERO   # true coordinates: where the beam is going this frame
# the beam's heat effect (the browser's heatFx): the spot on the stone takes 30 s to reach white heat and cools off
# over 10 s; it glows, lights the rock, throws sparks and, once hot, stamps scorches
var spot_heat := 0.0
var _spot_key := -1
var _spot_pos := Vector3.ZERO   # true
var _burn_t := 0.0
var _spot: MeshInstance3D
var _spot_mat: StandardMaterial3D
var _spot_light: OmniLight3D
# the fitting variants (laser barrel, cargo pod, engine nacelle, scanner dish, three tiers each) from the model's
# second scene, brought in at run time and shown by refit level as the browser's assembler does
var _variants := {}   # name -> Node3D


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
		var soft := _soft_texture()
		_exhaust_mat = StandardMaterial3D.new()
		_exhaust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_exhaust_mat.albedo_color = Color(0.37, 0.83, 0.94, 0.15)
		_exhaust_mat.albedo_texture = soft
		_exhaust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_exhaust_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_exhaust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_exhaust_mat.no_depth_test = false
		for n in ["engine_l", "engine_r"]:
			var a := model.find_child(n, true, false)
			if a is Node3D:
				var glow := OmniLight3D.new()
				glow.light_color = Color("#5ed3f0")
				glow.light_energy = 0.0
				glow.omni_range = 140.0
				glow.omni_attenuation = 1.0
				(a as Node3D).add_child(glow)
				_engine_lights.append(glow)
				var q := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2.ONE
				q.mesh = qm
				q.material_override = _exhaust_mat
				q.position = Vector3(0.0, 0.0, -0.25)
				q.scale = Vector3.ONE * 5.0
				(a as Node3D).add_child(q)
				_exhausts.append(q)
		for pair in [["nav_l", Color("#ff5a5a")], ["nav_r", Color("#6bd69a")]]:
			var a := model.find_child(pair[0], true, false)
			if a is Node3D:
				var q := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2.ONE * 0.9
				q.mesh = qm
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = pair[1]
				m.albedo_color.a = 0.85
				m.albedo_texture = soft
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				q.material_override = m
				(a as Node3D).add_child(q)
				_nav_lights.append(q)
		_build_dish_fx()
		_build_pulse_fx()
		_build_spot_fx()
		_load_variants()
		configure_model()
		print("ship: model loaded")
		return
	_build_placeholder()


## The fitting variants live in the model's second glTF scene, which the scene importer leaves out; the glTF document
## itself still lists every node, so the alternatives are built from it here (the assembler's parts map). Laser
## barrels ride the dish's pitch group; everything else sits on the hull.
func _load_variants() -> void:
	for prefix in ["cargo_pod", "engine_nacelle", "scanner_dish", "wings", "laser_barrel"]:
		for c in model.get_children():
			if str(c.name).begins_with(prefix + "_"):
				_variants[str(c.name)] = c
		if _dish_pitch:
			for c in _dish_pitch.get_children():
				if str(c.name).begins_with(prefix + "_"):
					_variants[str(c.name)] = c
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(MODEL, st) != OK:
		return
	var pitch_in_model: Transform3D = model.global_transform.affine_inverse() * (_dish_pitch as Node3D).global_transform if _dish_pitch is Node3D else Transform3D.IDENTITY
	for i in st.nodes.size():
		var n: GLTFNode = st.nodes[i]
		var nm := str(n.original_name)
		if _variants.has(nm) or n.mesh < 0:
			continue
		var kind := ""
		for prefix in ["cargo_pod", "engine_nacelle", "scanner_dish", "wings", "laser_barrel"]:
			if nm.begins_with(prefix + "_"):
				kind = prefix
		if kind == "":
			continue
		var gm: GLTFMesh = st.meshes[n.mesh]
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = gm.mesh.get_mesh()
		if kind == "laser_barrel" and _dish_pitch is Node3D:
			mi.transform = pitch_in_model.affine_inverse() * n.xform   # attached to the pitch group, pose kept
			_dish_pitch.add_child(mi)
		else:
			mi.transform = n.xform
			model.add_child(mi)
		mi.visible = false
		_variants[nm] = mi


## playerVisualTier / configure: each fitting shows the tier its refit level has reached (1 to 3); the wings stay delta.
func configure_model() -> void:
	if _variants.is_empty():
		return
	var tiers := {}
	for key in ["laser", "cargo", "engine", "scanner"]:
		var levels: int = (Data.UPGRADES[key]["levels"] as Array).size()
		tiers[key] = 1 + roundi(2.0 * float(State.up[key]) / float(levels - 1))
	var want := {"laser_barrel": tiers["laser"], "cargo_pod": tiers["cargo"], "engine_nacelle": tiers["engine"], "scanner_dish": tiers["scanner"]}
	for nm in _variants:
		var node: Node3D = _variants[nm]
		var shown := false
		for prefix in want:
			if nm.begins_with(prefix + "_"):
				shown = nm == "%s_%d" % [prefix, int(want[prefix])]
		if nm.begins_with("wings_"):
			shown = nm == "wings_delta"
		node.visible = shown


func variant_report() -> String:
	var out: Array = []
	for nm in _variants:
		if (_variants[nm] as Node3D).visible:
			out.append(nm)
	out.sort()
	return ", ".join(out)


## The glow at the beam's spot and the light it throws on the rock (heatFx's spot sprite and point light).
func _build_spot_fx() -> void:
	_spot = MeshInstance3D.new()
	_spot.top_level = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	_spot.mesh = qm
	_spot_mat = StandardMaterial3D.new()
	_spot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spot_mat.albedo_color = Color(1.0, 0.18, 0.03, 0.0)
	_spot_mat.albedo_texture = _soft_texture()
	_spot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_spot.material_override = _spot_mat
	_spot.visible = false
	add_child(_spot)
	_spot_light = OmniLight3D.new()
	_spot_light.top_level = true
	_spot_light.omni_range = 220.0
	_spot_light.omni_attenuation = 1.4
	_spot_light.light_energy = 0.0
	_spot_light.visible = false
	add_child(_spot_light)


## heatFx.update: the beam takes a full 30 s on a rock to reach white heat and cools off over about 10 s once it comes
## off; moving to a new rock leaves half the heat behind. The stone's own surface glow, the spot glow, the light, the
## sparks and the scorches all follow the heat.
func _tick_spot(dt: float, active: bool, hit: Vector3) -> void:
	var key: int = target if active else -1
	if key >= 0 and key != _spot_key:
		spot_heat *= 0.5
	if key >= 0:
		_spot_key = key
		_spot_pos = hit
	spot_heat = clampf(spot_heat + (dt / 30.0 if active else -dt / 10.0), 0.0, 1.0)
	var h := spot_heat
	var on: bool = h > 0.01
	var r: float = belt.radius[_spot_key] if (_spot_key >= 0 and _spot_key < belt.count) else 40.0
	belt.set_spot_heat(0, _spot_pos, h if on else 0.0, min(r * 0.9, 8.0 + r * 0.05 + 22.0 * h))
	if _spot == null:
		return
	_spot.visible = on
	_spot_light.visible = on
	if not on:
		return
	var cold := Color(1.0, 0.18, 0.03)
	var warm := Color(1.0, 0.6, 0.23)
	var white := Color(1.0, 0.95, 0.82)
	var col: Color = cold.lerp(warm, h * 2.0) if h < 0.5 else warm.lerp(white, (h - 0.5) * 2.0)
	var flick := 0.92 + randf() * 0.16
	_spot.global_position = _spot_pos - main.world_offset
	_spot.scale = Vector3.ONE * (4.0 + 14.0 * h) * flick
	_spot_mat.albedo_color = Color(col, 0.2 + 0.6 * h)
	_spot_light.global_position = _spot_pos - main.world_offset
	_spot_light.light_color = col
	_spot_light.light_energy = h * h * 40.0 * flick / PI
	if active and _spot_key >= 0:
		var rock_centre := belt.rock_pos(_spot_key)
		var nrm := (_spot_pos - rock_centre).normalized()
		main.sparks.emit(_spot_pos, nrm, h, dt)   # a shower of streaks off the surface, more and hotter as the spot heats
		if h > 0.3:
			_burn_t += dt
			if _burn_t > 0.1:
				_burn_t = 0.0
				belt.scorch(_spot_key, _spot_pos, min(r * 0.5, 6.0 + r * 0.04 + 10.0 * h))


## A soft radial glow texture for the sprites (the browser's texSoft / exhaustTex).
static func _soft_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d: float = Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## The radar pulse: a faint sphere and a bright ring (in the XY plane, as the browser's) that grow to scanner range.
func _build_pulse_fx() -> void:
	_pulse_sphere = MeshInstance3D.new()
	_pulse_sphere.top_level = true
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	_pulse_sphere.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.37, 0.83, 0.94, 0.05)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pulse_sphere.material_override = m
	_pulse_sphere.visible = false
	add_child(_pulse_sphere)
	_pulse_ring = MeshInstance3D.new()
	_pulse_ring.top_level = true
	var tm := TorusMesh.new()
	tm.inner_radius = 0.985
	tm.outer_radius = 1.0
	tm.rings = 128
	tm.ring_segments = 6
	_pulse_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.56, 0.91, 1.0, 0.5)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pulse_ring.material_override = rm
	_pulse_ring.rotation_degrees = Vector3(90, 0, 0)
	_pulse_ring.visible = false
	add_child(_pulse_ring)


func _tick_pulse(dt: float) -> void:
	if pulse.is_empty():
		return
	pulse["t"] = float(pulse["t"]) + dt
	var t: float = pulse["t"]
	if t >= Data.PULSE_TIME + 0.4:
		pulse = {}
		_pulse_sphere.visible = false
		_pulse_ring.visible = false
		return
	var r: float = float(pulse["range"]) * min(1.0, t / Data.PULSE_TIME)
	var f: float = 1.0 - min(1.0, t / Data.PULSE_TIME)
	var at: Vector3 = (pulse["origin"] as Vector3) - main.world_offset
	_pulse_sphere.visible = true
	_pulse_sphere.global_position = at
	_pulse_sphere.scale = Vector3.ONE * max(1.0, r)
	(_pulse_sphere.material_override as StandardMaterial3D).albedo_color.a = 0.05 * f
	_pulse_ring.visible = true
	_pulse_ring.global_position = at
	_pulse_ring.scale = Vector3.ONE * max(1.0, r)
	(_pulse_ring.material_override as StandardMaterial3D).albedo_color.a = 0.55 * f


## The exhaust glows swell and brighten with thrust, the navigation lights blink, the engine light comes on under thrust.
func _tick_engine_fx() -> void:
	if _exhaust_mat:
		var ex: float = (0.35 + 0.6 * throttle + randf() * 0.1) if thrusting else 0.15
		var es: float = ((22.0 if afterburning else 5.0 + 9.0 * throttle) + randf() * 4.0) if thrusting else 5.0
		_exhaust_mat.albedo_color.a = ex
		for q in _exhausts:
			q.scale = Vector3.ONE * es
	var blink: bool = fmod(State.time, 1.2) < 0.12
	for l in _nav_lights:
		l.visible = blink
	for g in _engine_lights:
		g.light_energy = ((5.0 if afterburning else 2.5) / PI) if thrusting else 0.0


## The mining dish's rig in Astra's model (mining_dish_yaw / mining_dish_pitch, the focus lens and six rim emitters)
## and its effects: a faint idle glow on the emitters that pulses while it slews onto a rock and flickers hard while it
## fires, a glow at the focus, and six rim beams converging on the focus while the beam cuts (the browser's animateDish).
func _build_dish_fx() -> void:
	_dish_yaw = model.find_child("mining_dish_yaw", true, false)
	_dish_pitch = model.find_child("mining_dish_pitch", true, false)
	_focus = model.find_child("focus", true, false)
	var mount := model.find_child("dish_mount", true, false)
	if mount is Node3D:
		_dish_mount = (mount as Node3D).position
	if _dish_pitch == null or _focus == null:
		return
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = Color(0.56, 0.91, 1.0, 0.12)
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.albedo_color = Color(1.0, 0.77, 0.4, 0.8)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_focus_mat = StandardMaterial3D.new()
	_focus_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_focus_mat.albedo_color = Color(1.0, 0.77, 0.4, 0.1)
	_focus_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_focus_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var fp: Vector3 = (_focus as Node3D).position
	for k in 6:
		var rim := model.find_child("rim_%d" % k, true, false)
		if not (rim is Node3D):
			continue
		var rp: Vector3 = (rim as Node3D).position
		var g := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.22
		s.height = 0.44
		s.radial_segments = 8
		s.rings = 4
		g.mesh = s
		g.material_override = _rim_mat
		g.position = rp
		_dish_pitch.add_child(g)
		var beam := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.025
		c.bottom_radius = 0.025
		c.height = 1.0
		c.radial_segments = 6
		beam.mesh = c
		beam.material_override = _beam_mat
		var d := fp - rp
		beam.position = (rp + fp) * 0.5
		if d.length() > 1e-4:
			beam.look_at_from_position(beam.position, beam.position + d, Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT)
			beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		beam.scale = Vector3(1.0, d.length(), 1.0)
		beam.visible = false
		_dish_pitch.add_child(beam)
		_rim_beams.append(beam)
	_focus_glow = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.45
	fs.height = 0.9
	fs.radial_segments = 8
	fs.rings = 4
	_focus_glow.mesh = fs
	_focus_glow.material_override = _focus_mat
	_focus_glow.position = fp
	_dish_pitch.add_child(_focus_glow)


## The dish swings onto whatever the beam is going to (fast, a few radians a second) and settles forward when idle; it
## only covers the forward half, 90 degrees either side of the nose. Angles are taken in the model's own frame.
func _tick_dish(dt: float) -> void:
	if _dish_yaw == null or _dish_pitch == null:
		return
	var want_yaw := 0.0
	var want_pitch := 0.05
	if has_aim:
		var L: Vector3 = model.to_local(aim_point - main.world_offset) - _dish_mount
		want_yaw = atan2(-L.x, L.z)
		want_pitch = atan2(-L.y, Vector2(L.x, L.z).length())
	var in_arc: bool = absf(want_yaw) <= PI / 2.0
	want_yaw = clampf(want_yaw, -PI / 2.0, PI / 2.0)
	want_pitch = clampf(want_pitch, -0.7, 1.3)
	var rate := 3.5 * dt
	aim_yaw += clampf(want_yaw - aim_yaw, -rate, rate)
	aim_pitch += clampf(want_pitch - aim_pitch, -rate, rate)
	aimed = has_aim and in_arc and absf(want_yaw - aim_yaw) < 0.05 and absf(want_pitch - aim_pitch) < 0.05
	(_dish_yaw as Node3D).rotation = Vector3(0.0, -aim_yaw, 0.0)
	(_dish_pitch as Node3D).rotation = Vector3(aim_pitch, 0.0, 0.0)
	if _rim_mat == null:
		return
	var t := State.time
	var aiming: bool = not firing and has_aim
	_rim_mat.albedo_color.a = (0.7 + randf() * 0.3) if laser_on else ((0.3 + 0.25 * sin(t * 9.0)) if aiming else 0.12)
	_focus_mat.albedo_color.a = (0.85 + randf() * 0.15) if laser_on else ((0.2 + 0.15 * sin(t * 9.0)) if aiming else 0.1)
	_focus_glow.scale = Vector3.ONE * (1.55 if laser_on else 1.0)
	_beam_mat.albedo_color.a = 0.6 + randf() * 0.35
	for b in _rim_beams:
		b.visible = laser_on


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


func laser_origin() -> Vector3:
	return true_pos() + forward() * 20.0


# ---- the Q lock
## What the mouse is over (hoverPick): every live rock within 120 km of the camera and the cargo ship are projected to
## the screen, and the nearest one whose disc (with a 10 px minimum so distant rocks stay hoverable) contains the cursor
## wins. dist is measured from the nose to the surface, in the same units as laser reach.
func hover_pick() -> Dictionary:
	if docked or not cut.is_empty() or not warp.is_empty() or main.hud.inv_open or main.hud.map_open:
		return {}
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	if m.x < 0.0 or m.y < 0.0 or m.x > size.x or m.y > size.y:
		return {}
	var f := tan(deg_to_rad(cam.fov) * 0.5)
	var origin := laser_origin()
	var cam_true: Vector3 = cam.global_position + main.world_offset
	var best := {}
	var bd := INF
	for i in belt.rocks_near(cam_true, 120000.0):
		var p := belt.rock_pos(i)
		var cd := cam_true.distance_to(p)
		if cd > 120000.0 or cd >= bd:
			continue
		var sc: Vector3 = p - main.world_offset
		if cam.is_position_behind(sc):
			continue
		var sp := cam.unproject_position(sc)
		var r := belt.radius[i]
		var pr: float = max(10.0, r * (size.y * 0.5) / (cd * f)) * 1.15
		if sp.distance_squared_to(m) > pr * pr:
			continue
		bd = cd
		best = {"kind": "rock", "rock": i, "dist": max(0.0, origin.distance_to(p) - r), "name": belt.rock_name(i)}
	if carrier and not carrier.hold:
		var p := carrier.true_pos
		var cd := cam_true.distance_to(p)
		if cd < 120000.0 and cd < bd:
			var sc: Vector3 = p - main.world_offset
			if not cam.is_position_behind(sc):
				var sp := cam.unproject_position(sc)
				var pr: float = max(10.0, CargoShip.HALF.x * (size.y * 0.5) / (cd * f)) * 1.15
				if sp.distance_squared_to(m) <= pr * pr:
					best = {"kind": "station", "rock": -1, "dist": max(0.0, origin.distance_to(p) - CargoShip.HALF.x), "name": "Cargo ship"}
	return best


func _hover_is_lock(h: Dictionary) -> bool:
	return not h.is_empty() and h["kind"] == lock_kind and (lock_kind != "rock" or int(h["rock"]) == lock_rock)


## Q: lock the hovered target, switch to a different hovered target, or release the current lock.
func toggle_lock() -> void:
	hover = hover_pick()   # the cursor's position now, even if it moved since the last hover pass
	if not hover.is_empty() and not _hover_is_lock(hover):
		lock_kind = hover["kind"]
		lock_rock = int(hover["rock"])
		lock_dist = float(hover["dist"])
		toast.emit("Locked on %s" % str(hover["name"]), false)
	elif lock_kind != "":
		release_lock()
		toast.emit("Lock released", false)
	else:
		toast.emit("Nothing under the mouse to lock on", true)


## The smoke run's Q: a lock on a given rock.
func lock_on_rock(i: int) -> void:
	lock_kind = "rock"
	lock_rock = i
	lock_dist = max(0.0, belt.rock_pos(i).distance_to(laser_origin()) - belt.radius[i])
	toast.emit("Locked on %s" % belt.rock_name(i), false)


func release_lock() -> void:
	lock_kind = ""
	lock_rock = -1
	lock_dist = 0.0


func lock_pos() -> Vector3:
	if lock_kind == "rock":
		return belt.rock_pos(lock_rock)
	return carrier.true_pos


func lock_name() -> String:
	return belt.rock_name(lock_rock) if lock_kind == "rock" else "Cargo ship"


## The lock lapses when its rock breaks up or it falls far out of range (the cargo ship never goes away).
func _tick_lock() -> void:
	if lock_kind == "":
		return
	var gone: bool = lock_kind == "rock" and belt.alive[lock_rock] == 0
	var r: float = belt.radius[lock_rock] if lock_kind == "rock" else CargoShip.HALF.x
	lock_dist = max(0.0, lock_pos().distance_to(laser_origin()) - r)
	if gone or lock_dist > LOCK_RANGE:
		toast.emit("Lock lost · rock broke up" if gone else "Lock lost · out of range", true)
		release_lock()


# ---- the tow tug
func towed() -> bool:
	return not tow.is_empty() and (tow["phase"] == "latch" or tow["phase"] == "haul")


func can_fly() -> bool:
	return not disabled and not towed()


func tow_speed() -> float:
	return max(650.0, float(tow["dist0"]) / 80.0)   # a slow, deliberate tug: a rescue from the far edge of a zone takes well over a minute


func _tow_approach_point(side: int) -> Vector3:
	return carrier.to_true(CargoShip.opening_local(side)) + carrier.dir(Vector3(0.0, 0.0, float(side))) * 1500.0


## requestTow: the tug sets out from just off the nearer mouth. A breach disables the ship on the spot.
func request_tow(reason: String) -> void:
	if not tow.is_empty() or docked:
		return
	var side := carrier.nearest_side(true_pos())
	var start: Vector3 = carrier.to_true(CargoShip.opening_local(side)) + carrier.dir(Vector3(0.0, 0.0, float(side))) * 1800.0
	tow = {"phase": "approach", "reason": reason, "side": side, "pos": start, "dir": Vector3.FORWARD, "t": 0.0, "leg": 0, "dist0": max(1.0, start.distance_to(true_pos())), "hold": 0.0}
	_tug.visible = true
	_tug.position = start - main.world_offset
	if reason == "breach":
		disabled = true
		throttle = 0.0
		laser_on = false
		firing = false
		_laser.visible = false
		release_lock()
		main.hud.wreck_flash()
		Audio.sfx("boom_big")
		Audio.sfx("alarm")
		toast.emit("Hull breach · systems down · distress beacon sent", true)
	else:
		toast.emit("Tow requested · tug inbound", false)


## T: a dry tank calls the tug.
func call_tow() -> void:
	if docked or not tow.is_empty():
		return
	if State.fuel > 0.5:
		toast.emit("Fuel in the tank · the tug only comes for a dry ship", true)
		return
	request_tow("fuel")


func tow_status() -> String:
	if tow.is_empty():
		return ""
	match tow["phase"]:
		"approach": return "Tug inbound · %ds" % ceili(true_pos().distance_to(tow["pos"]) / tow_speed())
		"latch": return "Tug latching on"
		"haul": return "Under tow to %s · cargo ship" % CargoShip.bay_name(int(tow["side"]))
	return ""


## towUpdate: the tug flies to the ship, kills its drift and swings round to the cargo ship's side of it while the beam
## locks, then hauls it to the mouth and down the deck past the pad, where the bay's own capture docks it (enter_hangar
## charges the fee); afterwards it carries on out of the far mouth and away.
func _tow_update(dt: float) -> void:
	var T := tow
	T["t"] = float(T["t"]) + dt
	var sp := true_pos()
	var side: int = T["side"]
	var tpos: Vector3 = T["pos"]
	var tdir: Vector3 = T["dir"]
	match T["phase"]:
		"approach":
			var to := sp - tpos
			var d := to.length()
			if d <= 75.0:
				T["phase"] = "latch"
				T["t"] = 0.0
				toast.emit("Tug on station · latching", false)
				Audio.sfx("chime")
			else:
				to /= d
				tdir = to
				tpos += to * min(d - 70.0, tow_speed() * dt)
		"latch":
			vel *= exp(-3.0 * dt)
			position += vel * dt
			sp = true_pos()
			var want: Vector3 = sp + (_tow_approach_point(side) - sp).normalized() * 70.0
			var to := want - tpos
			var d := to.length()
			if d > 0.5:
				tpos += to / d * min(d, 480.0 * dt)
			tdir = (tpos - sp).normalized()
			T["hold"] = float(T["hold"]) + (dt if d < 4.0 else 0.0)
			if float(T["hold"]) > 1.5:
				T["phase"] = "haul"
				T["t"] = 0.0
				T["leg"] = 0
				toast.emit("Under tow to %s" % CargoShip.bay_name(side), false)
		"haul":
			var leg: int = T["leg"]
			var target: Vector3 = _tow_approach_point(side) if leg == 0 else carrier.to_true(CargoShip.park_local(side)) + carrier.dir(Vector3(0.0, 0.0, -float(side))) * 70.0   # past the pad, so the ship 70 behind lands on it
			var to := target - tpos
			var d := to.length()
			var spd: float = tow_speed() if leg == 0 else 160.0
			if d < 20.0:
				if leg == 0:
					T["leg"] = 1
			else:
				to /= d
				tdir = tdir.lerp(to, 1.0 - exp(-3.0 * dt)).normalized()
				tpos += to * min(d, spd * dt)
			position = tpos - tdir * 70.0 - main.world_offset
			vel = tdir * min(spd, d / max(dt, 1e-3))
			set_heading(heading().slerp(level_heading(tdir), 1.0 - exp(-2.0 * dt)))
		"leave":
			tpos += tdir * 520.0 * dt
			tpos.y += 50.0 * dt
			if float(T["t"]) > 6.0:
				tow = {}
				_tug.visible = false
				_tow_beam.visible = false
				return
	T["pos"] = tpos
	T["dir"] = tdir
	# the tug and its beam
	_tug.position = tpos - main.world_offset
	if tdir.length_squared() > 1e-6:
		_tug.look_at(_tug.position + tdir, Vector3.UP if absf(tdir.y) < 0.98 else Vector3.FORWARD)
	var blink: bool = fmod(float(T["t"]), 0.8) < 0.15
	_tug_strobe.albedo_color = Color("#ffe0a0") if blink else Color("#6a4a1a")
	_tug_light.light_energy = (12.0 if blink else 2.0) / PI
	var latched := towed()
	_tow_beam.visible = latched
	if latched:
		var from: Vector3 = tpos - tdir * 11.0 - main.world_offset
		var to: Vector3 = position + forward() * 22.0 * Data.SHIP_SCALE
		var mid := (from + to) * 0.5
		var len := from.distance_to(to)
		if len > 1.0:
			_tow_beam.global_position = mid
			_tow_beam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.FORWARD)
			_tow_beam.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
			var w := 3.5 + sin(float(T["t"]) * 20.0) * 0.6
			_tow_beam.scale = Vector3(w, len, w)


func tick(dt: float) -> void:
	torch.visible = torch_on and not docked and warp.is_empty() and visible
	_tick_pulse(dt)
	_tick_engine_fx()
	# passing through a mouth's force field flashes it, under approach control or on your own
	if carrier and not carrier.hold and warp.is_empty():
		var fl := carrier.to_local_true(true_pos())
		if absf(fl.x) < CargoShip.BAY_X1 + 40.0 and absf(fl.y) < CargoShip.BAY_Y1 + 40.0 and absf(absf(fl.z) - CargoShip.BAY_Z_OUT) < 70.0:
			carrier.flash_field(1 if fl.z > 0.0 else -1)
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
	if not tow.is_empty():
		_tow_update(dt)
		if tow.is_empty() or docked:
			return
	if Input.is_action_just_pressed("tow"):
		call_tow()
	if towed():
		_carrier_contact()   # the tug flies the ship; the bay's own capture docks it once it is pulled deep enough
		return
	_near_frame += 1
	if _near_frame % 30 == 1:
		near_rocks = belt.rocks_within(true_pos(), 12000.0)
	hit_cd = max(0.0, hit_cd - dt)
	_prev_pos = position
	_fly(dt)
	_carrier_contact()
	if docked:
		return
	_rock_contact()
	_tick_lock()
	_hover_frame += 1
	if _hover_frame % 6 == 0:
		hover = hover_pick()   # for the hover label and the hint bar; Q picks afresh
	if Input.is_action_just_pressed("lock") and not disabled:
		toggle_lock()
	if disabled:
		firing = false
		laser_on = false
		has_aim = false
		_laser.visible = false
		_tick_spot(dt, false, Vector3.ZERO)
		_tick_dish(dt)
		return
	_tick_laser(dt, forward())
	_tick_dish(dt)
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
	var yaw := 0.0
	var pitch := 0.0
	var roll := 0.0
	var flying := can_fly()   # nothing answers while disabled: the ship drifts until the tug comes
	rdown = mouse_steer and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not main.hud.inv_open and not main.hud.map_open
	if rdown:
		# free look: the mouse swings the camera instead of the ship (the ship holds its heading)
		look_yaw += -_shape(sx) * 2.2 * dt
		look_pitch = clampf(look_pitch - _shape(sy) * 1.8 * dt, -1.35, 1.35)
	else:
		# ease the free-look camera back to straight ahead once the button is released
		look_yaw *= exp(-4.0 * dt)
		look_pitch *= exp(-4.0 * dt)
	if flying and lock_kind != "":
		# Q lock: the ship turns itself to put the locked object on the nose ray (the laser's line, not the camera's); the
		# mouse is ignored until the lock is released (roll is still yours). Proportional: full rate beyond about seven
		# degrees off, easing in as the nose comes on.
		var L: Vector3 = global_transform.affine_inverse() * (lock_pos() - main.world_offset) - Vector3(0.0, 0.0, -20.0)
		var ey := atan2(-L.x, -L.z)
		var ep := atan2(L.y, Vector2(L.x, L.z).length())
		yaw = clampf(ey * 8.0, -1.0, 1.0) * 1.2
		pitch = clampf(ep * 8.0, -1.0, 1.0) * 1.0
	elif flying and mouse_steer and not rdown:
		yaw = -_shape(sx)
		pitch = -_shape(sy)
	if flying:
		if Input.is_action_pressed("roll_left"):
			roll += 1.0
		if Input.is_action_pressed("roll_right"):
			roll -= 1.0
		if Input.is_action_pressed("pitch_up"):
			pitch += 1.0
		if Input.is_action_pressed("pitch_down"):
			pitch -= 1.0
	yaw = clampf(yaw, -1.0, 1.0)
	pitch = clampf(pitch, -1.0, 1.0)
	rotate_object_local(Vector3.UP, yaw * TURN * dt)
	rotate_object_local(Vector3.RIGHT, pitch * TURN * dt)
	rotate_object_local(Vector3.BACK, roll * 0.6 * dt)
	transform.basis = transform.basis.orthonormalized()

	# throttle: W raises, S lowers, X cuts; holding S at zero fires the retros
	if flying:
		if Input.is_action_pressed("throttle_up"):
			throttle = min(1.0, throttle + 0.7 * dt)
		if Input.is_action_pressed("throttle_down"):
			throttle = max(0.0, throttle - 0.9 * dt)
		if Input.is_action_pressed("throttle_cut"):
			throttle = 0.0
	var ab_mult: float = State.stat("thrusters")["mult"]
	afterburning = flying and throttle > 0.0 and Input.is_action_pressed("afterburner") and ab_mult > 1.0 and State.fuel > 0.0
	var mult := ab_mult if afterburning else 1.0
	thrusting = false
	braking = false
	var fwd := forward()
	var sp_before := vel.length()
	if State.fuel > 0.0 and flying:
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


# ---- rocks and scrap: swept along this frame's path in short steps, then resolved against a slightly generous sphere
func _rock_contact() -> void:
	var off: Vector3 = main.world_offset
	var tp := true_pos()
	var prev: Vector3 = _prev_pos + off
	var step_len := prev.distance_to(tp)
	var k_steps: int = clampi(ceili(step_len / 24.0), 1, 64)
	var reach := 60.0 + step_len
	for i in near_rocks:
		if i >= belt.count or belt.alive[i] == 0:
			continue
		var rp := belt.rock_pos(i)
		var r: float = belt.radius[i] * 0.92
		if absf(rp.x - tp.x) > r * 1.5 + reach or absf(rp.y - tp.y) > r * 1.5 + reach or absf(rp.z - tp.z) > r * 1.5 + reach:
			continue
		var min_d: float = r + Data.SHIP_R
		for k in range(1, k_steps + 1):
			var wp: Vector3 = prev.lerp(tp, float(k) / k_steps)
			var to := wp - rp
			var d := to.length()
			if d < min_d and d > 0.0:
				var n := to / d
				tp = rp + n * min_d
				position = tp - off
				var vn: float = (vel - belt.rock_vel(i)).dot(n)
				if vn < 0.0:
					_impact(-vn, tp - n * Data.SHIP_R)
					vel -= n * vn * 1.4
					belt.bump(i, -n, -vn)
				break
	for s in belt.scrap_count():
		var sp := belt.scrap_pos(s)
		var sr: float = belt.scrap_r(s) * 0.9
		if absf(sp.x - tp.x) > sr + reach or absf(sp.y - tp.y) > sr + reach or absf(sp.z - tp.z) > sr + reach:
			continue
		var to := tp - sp
		var d := to.length()
		var min_d: float = sr + Data.SHIP_R
		if d < min_d and d > 0.0:
			var n := to / d
			tp = sp + n * min_d
			position = tp - off
			var vn := vel.dot(n)
			if vn < 0.0:
				_impact(-vn, tp - n * Data.SHIP_R)
				vel -= n * vn * 1.4
			belt.scrap_hit(s, n, vn, belt.scrap_vel(s).dot(n))


## impact: a knock above the safe speed costs plating, shakes the camera, sparks and sounds; at zero plating the tug comes.
func _impact(speed: float, at: Vector3) -> void:
	if hit_cd > 0.0 or speed < IMPACT_SAFE or disabled:
		return
	hit_cd = 0.5
	var dmg := roundi((speed - IMPACT_SAFE) * 0.09)
	State.hull = max(0.0, State.hull - dmg)
	shake = min(1.0, 0.3 + dmg / 60.0)
	Audio.sfx("hit")
	main.hud.damage_flash()
	main.sparks.burst(at, 60 + dmg * 2, 260.0, Color("#ffb060"), 1.2)
	toast.emit("Hull hit · −%d" % dmg, true)
	if State.hull <= 0.0:
		if tow.is_empty() and not docked:
			request_tow("breach")
		return
	if State.hull < float(State.stat("hull")["hp"]) * 0.25 and not _low_hull_warned:
		_low_hull_warned = true
		toast.emit("Hull critical · repair at the cargo ship", true)


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
			if State.hull <= 0.0 and not docked and tow.is_empty():
				request_tow("breach")   # plating gone: the ship is disabled and the tug comes for it


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
	release_lock()
	_low_hull_warned = false
	look_yaw = 0.0
	look_pitch = 0.0
	if not tow.is_empty() and tow["phase"] == "haul":
		# tow delivered: charge the fee, patch a breached hull enough to fly, top up an empty tank, send the tug home
		var fee := floori(State.credits * 0.15)
		State.credits -= fee
		if tow["reason"] == "breach":
			State.hull = max(State.hull, roundf(float(State.stat("hull")["hp"]) * 0.35))
		var tank: float = State.stat("tank")["cap"]
		if State.fuel < tank * 0.3:
			State.fuel = tank * 0.3
		disabled = false
		tow["phase"] = "leave"
		tow["t"] = 0.0
		tow["dir"] = carrier.dir(Vector3(0.0, 0.0, -float(side)))   # the tug carries on out of the far mouth
		tow["pos"] = true_pos() + Vector3(0.0, 45.0, 0.0)
		_tow_beam.visible = false
		toast.emit("Tow complete · %s cr fee%s" % [Data.fmt(fee), " · emergency hull patch applied" if tow["reason"] == "breach" else ""], false)
	else:
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
	has_aim = target >= 0
	if has_aim:
		aim_point = belt.rock_pos(target)
	if not firing:
		_tick_spot(dt, false, Vector3.ZERO)
		return
	var end := origin + fwd * reach
	if target >= 0:
		var oc: float = State.stat("overcharge")["mult"] if (overcharge and State.fuel > 0.0) else 1.0
		var can_cut: bool = belt.ore[target] < 0 or int(Data.ORES[Data.ORE_KEYS[belt.ore[target]]]["unlock"]) <= int(State.up["laser"]) + 1
		end = belt.rock_pos(target) - (belt.rock_pos(target) - origin).normalized() * belt.radius[target] * 0.85
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
	_tick_spot(dt, laser_on and target >= 0, end)
	# the beam: a thin cylinder from the dish's focus to wherever the ray ends, in scene space
	var a: Vector3 = (_focus as Node3D).global_position if _focus is Node3D else position + fwd * 20.0
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
	pulse = {"t": 0.0, "origin": true_pos(), "range": range}   # the visible pulse, expanding to scanner range over PULSE_TIME
	last_scan = belt.scan(true_pos(), range, -1, range / Data.PULSE_TIME)
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
	# free look turns the camera relative to the hull; the chase offset stays rigid on the ship's position
	var look_q := Quaternion(Vector3.UP, look_yaw) * Quaternion(Vector3.RIGHT, look_pitch)
	var b := Basis(_cam_q * look_q)
	var f := -b.z
	var u := b.y
	var cam_pos := position - f * 88.0 * s + u * 30.0 * s
	var look := position + f * 140.0 * s + u * 10.0 * s
	if shake > 0.0:
		shake = max(0.0, shake - dt * 1.8)
		var sh := shake * shake * 6.0
		cam_pos += Vector3(randf_range(-sh, sh), randf_range(-sh, sh), randf_range(-sh, sh))
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

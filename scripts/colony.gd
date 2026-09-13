class_name Colony
extends Node3D
## Meridian Colony, at the Hub's origin: two boxy habitat rings joined by spokes round a central hub sphere and core
## shaft, pads at both ends of the core, four solar wings, and the cargo terminals above and below the ring plane.
## A simplified port of buildColonyAt in belt-runner-3d.html: the same proportions (Data.COLONY) with plain meshes in
## place of the merged detail, and no traffic yet. The ring assembly turns slowly; the hub and terminals never move.

const MODEL := "res://assets/colony/garden_habitat.glb"

var _ring: Node3D
var _beacons: Array = []
var _t := 0.0
var model: Node3D


func _ready() -> void:
	if not _load_model():
		_build()


## Astra's garden habitat: Habitat_Rings, Civic_Core and Comms_Dish, authored at 1/1000 scale (the rings reach 55 units,
## so x1000 puts them at the colony's 55 km). The rings turn; the core stays put.
func _load_model() -> bool:
	var ps = load(MODEL)
	if ps == null:
		return false
	model = ps.instantiate()
	model.name = "Model"
	model.scale = Vector3.ONE * 1000.0
	add_child(model)
	var rings := model.find_child("Habitat_Rings", true, false)
	_ring = rings if rings is Node3D else model
	for p in [Vector3(0, 9000, 0), Vector3(0, -9000, 0), Vector3(40000, 2000, 0), Vector3(-40000, 2000, 0), Vector3(0, 2000, 40000), Vector3(0, 2000, -40000)]:
		var l := OmniLight3D.new()
		l.light_color = Color("#dce8ff")
		l.light_energy = 4.0
		l.omni_range = 30000.0
		l.omni_attenuation = 1.2
		l.position = p
		add_child(l)
	print("colony: garden habitat loaded")
	return true


func tick(dt: float) -> void:
	_t += dt
	_ring.rotate_y(0.012 * dt)
	var phase := int(_t * 1.6) % 3
	for i in _beacons.size():
		var b: MeshInstance3D = _beacons[i]
		b.visible = (i % 3) == phase or (i % 3) == (phase + 1) % 3


func _mat(c: Color, rough := 0.8, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, mat: Material, at: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, mat, at, rot_deg)


func _ring_mesh(parent: Node3D, r_mid: float, half_w: float, height: float, mat: Material) -> void:
	# a boxy ring approximated by a flattened torus: the same footprint and thickness
	var t := TorusMesh.new()
	t.inner_radius = r_mid - half_w
	t.outer_radius = r_mid + half_w
	t.rings = 96
	t.ring_segments = 12
	var mi := _mesh(parent, t, mat, Vector3.ZERO)
	mi.scale = Vector3(1.0, height / (2.0 * half_w), 1.0)


func _beacon(parent: Node3D, mat: Material, at: Vector3, r: float) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	_beacons.append(_mesh(parent, s, mat, at))


func _build() -> void:
	var C: Dictionary = Data.COLONY
	var hull := _mat(Color("#b8c0d4"))
	var dark := _mat(Color("#5a6488"))
	var plate := _mat(Color("#8a94b4"))
	var warm := _glow(Color("#ffd9a0"), 2.0)
	var green := _glow(Color("#6bd69a"))
	var red := _glow(Color("#ff5a5a"))
	var cyan := _glow(Color("#8fe8ff"))
	var solar := _mat(Color("#16234a"), 0.4, 0.6)
	_ring = Node3D.new()
	add_child(_ring)
	# the outer habitat ring with 24 modules on its outer wall and a beacon pylon at every third one
	var R: float = C["R"]
	var ring_w: float = C["ringW"]
	var ring_h: float = C["ringH"]
	_ring_mesh(_ring, R, ring_w, ring_h, hull)
	for i in 24:
		var a := i * PI / 12.0
		var n := Vector3(cos(a), 0.0, sin(a))
		_box(_ring, Vector3(1400, 2000, 3000), plate, n * (R + ring_w + 700.0), Vector3(0.0, -rad_to_deg(a), 0.0))
		_box(_ring, Vector3(60, 260, 2200), warm, n * (R + ring_w + 1430.0) + Vector3(0, -500, 0), Vector3(0.0, -rad_to_deg(a), 0.0))
		if i % 3 == 0:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 160.0
			cyl.bottom_radius = 220.0
			cyl.height = 2400.0
			_mesh(_ring, cyl, dark, n * (R + 1200.0) + Vector3(0, ring_h / 2.0 + 1200.0, 0))
			_beacon(_ring, red, n * (R + 1200.0) + Vector3(0, ring_h / 2.0 + 2600.0, 0), 240.0)
		_beacon(_ring, green if i % 2 else warm, n * (R + ring_w + 60.0), 200.0)
	# the inner ring, smaller, with twelve modules and a cyan band
	var R2: float = C["R2"]
	var ring2_w: float = C["ring2W"]
	var ring2_h: float = C["ring2H"]
	_ring_mesh(_ring, R2, ring2_w, ring2_h, plate)
	for i in 12:
		var a := i * PI / 6.0 + PI / 12.0
		var n := Vector3(cos(a), 0.0, sin(a))
		_box(_ring, Vector3(900, 1300, 1800), hull, n * (R2 + ring2_w + 450.0), Vector3(0.0, -rad_to_deg(a), 0.0))
	for i in 24:
		var a := i * PI / 12.0
		var n := Vector3(cos(a), 0.0, sin(a))
		_box(_ring, Vector3(60, 220, 2400), cyan, n * (R2 + ring2_w + 30.0), Vector3(0.0, -rad_to_deg(a), 0.0))
	# six spokes: hub to the inner ring, inner ring to the outer ring, with a lit lift car on each outer spoke
	for i in 6:
		var a := i * PI / 3.0
		var n := Vector3(cos(a), 0.0, sin(a))
		for seg in [[C["hub"] - 500.0, R2 - ring2_w + 300.0], [R2 + ring2_w - 300.0, R - ring_w + 300.0]]:
			var r0: float = seg[0]
			var r1: float = seg[1]
			var cyl := CylinderMesh.new()
			cyl.top_radius = 520.0
			cyl.bottom_radius = 520.0
			cyl.height = r1 - r0
			var mi := _mesh(_ring, cyl, dark, n * (r0 + r1) * 0.5)
			mi.look_at_from_position(mi.position, mi.position + n, Vector3.UP)
			mi.rotate_object_local(Vector3.RIGHT, -PI / 2.0)   # the cylinder's axis (+Y) now runs along the spoke
		_box(_ring, Vector3(1100, 1100, 1100), warm, n * (R2 + ring2_w + (R - ring_w - R2 - ring2_w) * 0.45))
	# the hub sphere with an equatorial walkway, the core shaft through it, pads at both ends of the core
	var hub_r: float = C["hub"]
	var sph := SphereMesh.new()
	sph.radius = hub_r
	sph.height = hub_r * 2.0
	sph.radial_segments = 48
	sph.rings = 28
	_mesh(self, sph, hull, Vector3.ZERO)
	var walk := TorusMesh.new()
	walk.inner_radius = hub_r - 80.0
	walk.outer_radius = hub_r + 440.0
	walk.rings = 96
	_mesh(self, walk, dark, Vector3.ZERO)
	var core := CylinderMesh.new()
	core.top_radius = C["coreR"]
	core.bottom_radius = C["coreR"]
	core.height = C["coreH"] * 2.0 + 12000.0
	_mesh(self, core, plate, Vector3.ZERO)
	for y in [-19500.0, -7500.0, 7500.0, 19500.0]:
		var rib := TorusMesh.new()
		rib.inner_radius = C["coreR"] - 50.0
		rib.outer_radius = C["coreR"] + 400.0
		_mesh(self, rib, dark, Vector3(0, y, 0))
	for s in [1.0, -1.0]:
		var y: float = s * C["padY"]
		var pad := CylinderMesh.new()
		pad.top_radius = C["padR"]
		pad.bottom_radius = C["padR"]
		pad.height = 500.0
		pad.radial_segments = 40
		_mesh(self, pad, hull, Vector3(0, y, 0))
		for i in 8:
			var a := i * PI / 4.0
			_beacon(self, red if i % 2 else green, Vector3(cos(a) * (C["padR"] - 500.0), y + s * 380.0, sin(a) * (C["padR"] - 500.0)), 160.0)
		# the docking arm beyond the pad, ending in a plate; the top one carries the comms dish
		var arm := CylinderMesh.new()
		arm.top_radius = 300.0
		arm.bottom_radius = 300.0
		arm.height = 6000.0
		_mesh(self, arm, dark, Vector3(0, s * (C["coreH"] + 3000.0), 0))
		_box(self, Vector3(2600, 200, 2600), plate, Vector3(0, s * (C["coreH"] + 6100.0), 0))
	var stalk := CylinderMesh.new()
	stalk.top_radius = 140.0
	stalk.bottom_radius = 140.0
	stalk.height = 5600.0
	var dish_base := Vector3(0, C["coreH"] + 6150.0, 0)
	_mesh(self, stalk, dark, dish_base + Vector3(0, 2800, 0), Vector3(0, 0, -20.0))
	var dish := CylinderMesh.new()
	dish.top_radius = 2600.0
	dish.bottom_radius = 1400.0
	dish.height = 400.0
	_mesh(self, dish, hull, dish_base + Vector3(-1900, 5300, 0), Vector3(0, 0, -20.0))
	var feed := SphereMesh.new()
	feed.radius = 360.0
	feed.height = 720.0
	_mesh(self, feed, cyan, dish_base + Vector3(-1950, 5700, 0))
	# four solar wings on booms from the core
	for y in [C["padY"] - 3000.0, -(C["padY"] - 3000.0)]:
		for dz in [1.0, -1.0]:
			var boom := CylinderMesh.new()
			boom.top_radius = 180.0
			boom.bottom_radius = 180.0
			boom.height = 9000.0
			_mesh(self, boom, dark, Vector3(0, y, dz * 4500.0), Vector3(90.0, 0, 0))
			_box(self, Vector3(14000, 90, 9000), solar, Vector3(0, y, dz * 13500.0))
			_box(self, Vector3(14000, 60, 60), cyan, Vector3(0, y + 60.0, dz * 9000.0))
			_box(self, Vector3(14000, 60, 60), cyan, Vector3(0, y + 60.0, dz * 18000.0))
	# the cargo terminals above and below the ring plane: a warehouse block round the core, a lit strip, a deck plate
	for s in [1.0, -1.0]:
		var y: float = s * C["berthY"]
		var T: float = C["termZ"]
		_box(self, Vector3(C["termX"] * 2.0, C["termY"] * 2.0, T * 2.0), plate, Vector3(0, y, 0))
		_box(self, Vector3(C["termX"] * 2.0 - 800.0, 400, 60), warm, Vector3(0, y + s * 700.0, T + 30.0))
		for x in [-2800.0, -1400.0, 0.0, 1400.0, 2800.0]:
			_box(self, Vector3(700, 500, 60), warm, Vector3(x, y - s * 300.0, T + 30.0))
			_box(self, Vector3(700, 500, 60), warm, Vector3(x, y, -T - 30.0))
		_box(self, Vector3(C["termX"] * 2.0 + 1600.0, 160, C["berthZ"] + 900.0 - T), hull, Vector3(0, y - s * 700.0, (T + C["berthZ"] + 900.0) * 0.5))
		for i in 7:
			_beacon(self, green if i % 2 else warm, Vector3(-1800.0 + i * 600.0, y - s * 560.0, T + 1400.0), 120.0)
	# a few lights so the structure reads on its night side
	for p in [Vector3(0, 9000, 0), Vector3(0, -9000, 0), Vector3(R * 0.7, 0, 0), Vector3(-R * 0.7, 0, 0), Vector3(0, 0, R * 0.7), Vector3(0, 0, -R * 0.7)]:
		var l := OmniLight3D.new()
		l.light_color = Color("#dce8ff")
		l.light_energy = 4.0
		l.omni_range = 26000.0
		l.omni_attenuation = 1.2
		l.position = p
		add_child(l)

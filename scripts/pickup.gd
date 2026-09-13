class_name Pickup
extends MeshInstance3D
## A loose lump of ore from a broken rock. It drifts, and once the ship is close it is pulled aboard (the browser game's
## spawnDrop / updateDrops). Positions here are scene-local (the floating origin shifts them along with everything else).

const PULL_RANGE := 900.0
const GRAB_RANGE := 106.0   # Data.SHIP_R * 2.2 (a literal: constants cannot read an autoload)
const LIFE := 240.0

var ore: String
var units: float
var vel := Vector3.ZERO
var age := 0.0

static var _mesh: SphereMesh


static func make(ore_key: String, ore_units: float, at: Vector3, drift: Vector3) -> Pickup:
	var p := Pickup.new()
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 6.0
		_mesh.height = 12.0
		_mesh.radial_segments = 8
		_mesh.rings = 4
	p.mesh = _mesh
	var mat := StandardMaterial3D.new()
	var c: Color = Data.ORES[ore_key]["color"]
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.0
	p.material_override = mat
	p.ore = ore_key
	p.units = ore_units
	p.position = at
	p.vel = drift
	return p


## Returns true when the pickup has been taken aboard (or has expired) and should be freed.
func tick(dt: float, ship_pos: Vector3) -> bool:
	age += dt
	var to_ship := ship_pos - position
	var d := to_ship.length()
	if d < GRAB_RANGE:
		var took: float = State.add_cargo(ore, units)
		if took > 0.0:
			return true
		# hold full: the lump bounces off and waits
		vel = -to_ship.normalized() * 60.0
	elif d < PULL_RANGE:
		vel = vel.lerp(to_ship / d * 320.0, 1.0 - exp(-4.0 * dt))
	else:
		vel *= exp(-0.4 * dt)
	position += vel * dt
	rotate_y(1.5 * dt)
	return age > LIFE

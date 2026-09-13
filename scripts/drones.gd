class_name Drones
extends Node3D
## Collector drones, a cargo ship upgrade, ported from makeDrone / updateCollectors in belt-runner-3d.html. Stubby cargo
## drones wait at their docks off the starboard corner of mouth 1, fly out to loose ore within range, gather it into
## their hold and bring it back: in through the nearest hangar mouth, down the starboard side to the drop-off pad, a
## pause to unload into the cargo ship's storage, and out the far mouth. Each drone claims the lump it is heading for so
## two never chase the same one; if the ship scoops a claimed lump first the drone just picks another. Drone positions
## are true world coordinates; the nodes are placed against the floating origin every frame.

const LANE_X := 250.0        # the drop-off pad's x: the run home follows this lane through the hangar
const MOUTH_Z := 1400.0      # BAY_Z_OUT + 500: the point outside a mouth the drones aim for

var main
var carrier: CargoShip
var drones: Array = []


func _dock(i: int) -> Vector3:
	var a: Vector3 = carrier.anchors.get("drone_dock_%d" % min(i, 2), Vector3(760.0 + i * 90.0, -60.0, 1500.0))
	if i > 2:
		a += Vector3((i - 2) * 90.0, 0.0, 0.0)
	return carrier.to_true(a)


func _drop_pad() -> Vector3:
	return carrier.anchors.get("drop_pad", Vector3(250.0, -130.0, 0.0))


func _make(i: int) -> Dictionary:
	var g := Node3D.new()
	g.name = "Drone%d" % i
	add_child(g)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#b4bccf")
	metal.metallic = 0.5
	metal.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#66709a")
	var win := StandardMaterial3D.new()
	win.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win.albedo_color = Color("#ffd9a0")
	var box := func(size: Vector3, mat: Material, at: Vector3) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
		mi.material_override = mat
		mi.position = at
		g.add_child(mi)
		return mi
	box.call(Vector3(10, 6, 18), metal, Vector3.ZERO)
	box.call(Vector3(12, 7, 9), dark, Vector3(0, -1, -2))
	box.call(Vector3(6, 3, 5), win, Vector3(0, 4, 5))
	var eng: Array = []
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color("#8fe8ff")
	em.emission_enabled = true
	em.emission = Color("#8fe8ff")
	em.emission_energy_multiplier = 3.0
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 2.5
		s.height = 5.0
		e.mesh = s
		e.material_override = em
		e.position = Vector3(sx * 5.0, 0.0, -11.0)
		g.add_child(e)
		eng.append(e)
	var strobe := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 1.2
	ss.height = 2.4
	strobe.mesh = ss
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color("#5ed3f0")
	strobe.material_override = sm
	strobe.position = Vector3(0, 5, -4)
	g.add_child(strobe)
	return {"node": g, "pos": _dock(i), "vel": carrier.vel, "eng": eng, "strobe": strobe, "phase": "idle", "target": null, "load": 0.0, "cargo": {}, "idx": i, "t": randf() * 6.0, "side": 0, "wait": 0.0}


## A drone on the pad stows what fits in the cargo ship's storage and keeps the rest aboard for the next visit.
func _unload(c: Dictionary) -> void:
	var units := 0.0
	var left := 0.0
	var cargo: Dictionary = c["cargo"]
	for k in cargo.keys():
		var u: float = cargo[k]
		if u <= 0.01:
			cargo.erase(k)
			continue
		var fit: float = min(u, State.store_room(k))
		if fit > 0.01:
			State.store[k] += fit
			cargo[k] -= fit
			units += fit
		if cargo[k] <= 0.01:
			cargo.erase(k)
		else:
			left += cargo[k]
	c["load"] = left
	if units > 0.5:
		State.drone_units += units
		Audio.sfx("stow")
		main.hud.toast("Collector %d stowed %d aboard the cargo ship%s" % [int(c["idx"]) + 1, roundi(units), (" · storage full, %d kept aboard" % roundi(left)) if left > 0.5 else ""], false)
		if main.ship.docked:
			main.hud.refresh_panel()
	elif left > 0.5:
		main.hud.toast("Collector %d · cargo ship storage is full" % (int(c["idx"]) + 1), true)


## Every drone back at its dock with an empty hold (a warp, a zone change).
func reset() -> void:
	for c in drones:
		c["phase"] = "idle"
		c["side"] = 0
		c["target"] = null
		c["cargo"] = {}
		c["load"] = 0.0
		c["pos"] = _dock(c["idx"])
		c["vel"] = carrier.vel
	for p in main.pickups.get_children():
		p.claimed = null


func tick(dt: float) -> void:
	var L = Data.DEPOT_UPGRADES["collectors"]["levels"][State.depot["collectors"]]
	var want: int = L["ships"] if L != null else 0
	while drones.size() < want:
		drones.append(_make(drones.size()))
	while drones.size() > want:
		var c: Dictionary = drones.pop_back()
		(c["node"] as Node).queue_free()
	if L == null:
		return
	var range: float = L["range"]
	var cap: float = L["cap"]
	var speed: float = L["speed"]
	var offset: Vector3 = main.world_offset
	var pickups: Array = main.pickups.get_children()
	for c in drones:
		c["t"] = float(c["t"]) + dt
		var pos: Vector3 = c["pos"]
		if c["phase"] == "idle" and pos.distance_to(_dock(c["idx"])) > 60000.0:   # left behind by a warp: it reappears at its dock
			pos = _dock(c["idx"])
			c["pos"] = pos
			c["vel"] = carrier.vel
		var target = c["target"]
		if target != null and (not is_instance_valid(target) or target.claimed != c or target.units <= 0.05):
			target = null
			c["target"] = null
		if c["phase"] == "idle" or (c["phase"] == "out" and target == null):
			# pick the nearest unclaimed lump in range; with a decent load and nothing close, head home instead.
			# nothing goes out while the storage is full: a full drone would only come back to wait
			var room := State.store_any_room()
			var best = null
			var bd := INF
			if room:
				for p in pickups:
					if p.claimed != null and p.claimed != c:
						continue
					var pt: Vector3 = p.position + offset
					if pt.distance_squared_to(carrier.true_pos) >= range * range:
						continue
					var q := pt.distance_squared_to(pos)
					if q < bd:
						bd = q
						best = p
			if best != null and float(c["load"]) < cap - 1.0:
				best.claimed = c
				c["target"] = best
				target = best
				c["phase"] = "out"
			elif float(c["load"]) > 0.5 and room:
				c["phase"] = "return"
			else:
				c["phase"] = "idle"
		# the run home goes in through the nearest mouth, down the starboard lane to the drop-off pad, and out the far mouth
		if c["phase"] == "return" and int(c["side"]) == 0:
			var lz := carrier.to_local_true(pos).z
			c["side"] = int(signf(lz)) if lz != 0.0 else 1
		var side: float = float(c["side"])
		var goal: Vector3
		var arrive := 40.0
		var vcap := speed
		var pad := _drop_pad()
		match c["phase"]:
			"out": goal = (target.position as Vector3) + offset
			"return":
				goal = carrier.to_true(Vector3(LANE_X, pad.y, side * MOUTH_Z))
				arrive = 80.0
			"enter":
				goal = carrier.to_true(pad)
				vcap = 140.0
			"unload":
				goal = carrier.to_true(pad)
				vcap = 60.0
			"exit":
				goal = carrier.to_true(Vector3(LANE_X, pad.y, -side * MOUTH_Z))
				arrive = 80.0
				vcap = 160.0
			_: goal = _dock(c["idx"])
		# steering: accelerate toward the goal, brake to arrive, cap at the drone's speed; ride the carrier's motion near home
		var to := goal - pos
		var dist := to.length()
		var base: Vector3 = Vector3.ZERO if c["phase"] == "out" else carrier.vel
		var want_speed: float = min(vcap, sqrt(2.0 * 260.0 * max(0.0, dist - arrive * 0.5)) + 8.0)
		var desired: Vector3 = (to / dist * want_speed + base) if dist > 1e-3 else base
		var vel: Vector3 = c["vel"]
		var dv := desired - vel
		var m := dv.length()
		if m > 1e-3:
			vel += dv / m * min(m, 320.0 * dt)
		pos += vel * dt
		c["vel"] = vel
		c["pos"] = pos
		if c["phase"] == "unload":
			c["wait"] = float(c["wait"]) - dt
			if float(c["wait"]) <= 0.0:
				_unload(c)
				c["phase"] = "exit"
		elif dist < arrive:
			match c["phase"]:
				"out":
					var take: float = min(target.units, cap - float(c["load"]))
					if take > 0.01:
						var cargo: Dictionary = c["cargo"]
						cargo[target.ore] = cargo.get(target.ore, 0.0) + take
						c["load"] = float(c["load"]) + take
						target.units -= take
					if target.units <= 0.05:
						target.queue_free()
					else:
						target.claimed = null
					c["target"] = null
					if float(c["load"]) >= cap - 1.0:
						c["phase"] = "return"
				"return": c["phase"] = "enter"
				"enter":
					c["phase"] = "unload"
					c["wait"] = 2.5
				"exit":
					c["phase"] = "idle"
					c["side"] = 0
		# face the way it is going (relative to the carrier when hovering home), engines bright under thrust
		var node: Node3D = c["node"]
		node.position = pos - offset
		var rel := vel - base
		if rel.length() > 5.0:
			var q := Basis.looking_at(-rel.normalized(), Vector3.UP).get_rotation_quaternion()   # nose is +Z on these hulls
			node.transform.basis = Basis(node.transform.basis.get_rotation_quaternion().slerp(q, min(1.0, 4.0 * dt)))
		var thr: float = min(1.0, rel.length() / speed)
		for e in c["eng"]:
			(e as MeshInstance3D).scale = Vector3.ONE * (0.6 + 0.9 * thr)
		(c["strobe"] as MeshInstance3D).visible = fmod(float(c["t"]), 1.0) < 0.15


func stats() -> Dictionary:
	var out := {}
	for c in drones:
		out["drone%d" % int(c["idx"])] = "%s load=%d" % [c["phase"], roundi(float(c["load"]))]
	return out

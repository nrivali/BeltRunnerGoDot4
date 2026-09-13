extends SceneTree
## `godot --headless --path . --script res://tools/inspect_glb.gd`: prints the node tree of each imported model, with
## mesh surface counts, materials, and the positions of empties, so the game code can be written against real names.

const FILES := ["res://assets/carrier/cargo_carrier.glb", "res://assets/ship/player_ship.glb", "res://assets/rocks/asteroids_lod2.glb", "res://assets/planets/ferron.glb", "res://assets/planets/homeworld.glb", "res://assets/colony/garden_habitat.glb"]


func _init() -> void:
	for f in FILES:
		print("==== ", f)
		var ps = load(f)
		if ps == null:
			print("  (not imported)")
			continue
		var root: Node = ps.instantiate()
		_dump(root, 0, 0)
		root.free()
	quit()


func _dump(n: Node, depth: int, count: int) -> void:
	if depth > 6:
		return
	var line := "  ".repeat(depth) + n.name + " [" + n.get_class() + "]"
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		if m:
			var tris := 0
			var mats: Array = []
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
				var mat = m.surface_get_material(s)
				mats.append(mat.resource_name if mat else "none")
			line += " surfaces=%d tris=%d mats=%s aabb=%s" % [m.get_surface_count(), tris, str(mats), str(m.get_aabb())]
	elif n is Node3D:
		line += " pos=%s" % str((n as Node3D).position)
	print(line)
	var i := 0
	for c in n.get_children():
		i += 1
		if i > 40:
			print("  ".repeat(depth + 1) + "... (%d children)" % n.get_child_count())
			break
		_dump(c, depth + 1, i)

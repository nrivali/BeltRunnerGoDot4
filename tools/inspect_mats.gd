extends SceneTree
## `godot --headless --path . --script res://tools/inspect_mats.gd`: prints every distinct material in the models
## with its albedo, metallic, roughness and which textures it carries, so lighting can be tuned against the real surfaces.

const FILES := ["res://assets/rocks/asteroids_lod1.glb", "res://assets/ship/player_ship.glb", "res://assets/carrier/cargo_carrier.glb", "res://assets/planets/ferron.glb", "res://assets/planets/homeworld.glb", "res://assets/colony/garden_habitat.glb"]


func _init() -> void:
	for f in FILES:
		print("==== ", f)
		var ps = load(f)
		if ps == null:
			print("  (not imported)")
			continue
		var root: Node = ps.instantiate()
		var seen := {}
		_walk(root, seen)
		root.free()
	quit()


func _walk(n: Node, seen: Dictionary) -> void:
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		if m:
			for s in m.get_surface_count():
				var mat = m.surface_get_material(s)
				if mat == null or seen.has(mat):
					continue
				seen[mat] = true
				if mat is StandardMaterial3D:
					var sm: StandardMaterial3D = mat
					print("  %s albedo=%s metal=%.2f rough=%.2f emis=%s tex(alb=%s mr=%s nrm=%s emis=%s) vcol=%s" % [sm.resource_name, str(sm.albedo_color), sm.metallic, sm.roughness, str(sm.emission_enabled), str(sm.albedo_texture != null), str(sm.metallic_texture != null or sm.roughness_texture != null), str(sm.normal_enabled), str(sm.emission_texture != null), str(sm.vertex_color_use_as_albedo)])
				else:
					print("  %s [%s]" % [mat.resource_name, mat.get_class()])
	for c in n.get_children():
		_walk(c, seen)

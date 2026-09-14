extends SceneTree
## `godot --headless --path . --script res://tools/inspect_ship.gd`: the player ship model's node names and which are meshes.
func _init() -> void:
	var ps = load("res://assets/ship/player_ship.glb")
	var root: Node = ps.instantiate()
	_dump(root, 0)
	root.free()
	quit()
func _dump(n: Node, d: int) -> void:
	print("  ".repeat(d) + n.name + (" [mesh]" if n is MeshInstance3D else "") + (" vis=%s" % str(n.visible) if n is Node3D else ""))
	for c in n.get_children():
		_dump(c, d + 1)

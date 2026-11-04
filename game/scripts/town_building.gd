@tool
class_name TownBuilding
extends Node3D

@export var room_site: String = ""
@export var show_interior := true:
	set(value):
		show_interior = value
		if is_inside_tree(): update_view(global_position+Vector3(5,4,8))

var parts: Dictionary = {}
const NORMALS := {"North":Vector3.FORWARD,"South":Vector3.BACK,"East":Vector3.RIGHT,"West":Vector3.LEFT}

func _ready() -> void:
	_collect(self)
	update_view(global_position+Vector3(5,4,8))

func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			for key in ["Floor","North","South","East","West","Roof"]:
				if str(child.name).ends_with("_"+key+"_LOD0"): parts[key] = child
		_collect(child)

func update_view(eye: Vector3) -> void:
	var toward := eye-global_position
	toward.y = 0
	toward = toward.normalized()
	for key in parts:
		var hidden: bool = show_interior and (key=="Roof" or (NORMALS.has(key) and NORMALS[key].dot(toward)>.15))
		parts[key].visible = not hidden

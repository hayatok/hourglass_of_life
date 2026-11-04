@tool
class_name SewingProp
extends Node3D

# Presentation only. The simulation owns material consumption, object identity,
# progress and completion; switching meshes never awards a product or result.
const STAGES := {"fabric":"Fabric", "cut":"Cut", "sewing":"Sewing", "finished":"Finished"}
const CONTACT_KEYS := {"GripLeft":"grip_left", "GripRight":"grip_right", "PinchCenter":"pinch_center",
	"SurfaceCenter":"surface_center", "CutPoint":"cut_point", "NeedlePoint":"needle_point"}
const SUPPORT_X := 0.075
const SUPPORT_Z := 0.025
var _surface_cache: Dictionary = {}
var _mesh_face_cache: Dictionary = {}

@export_enum("fabric", "cut", "sewing", "finished") var stage: String = "fabric":
	set(value):
		if not STAGES.has(value): return
		stage = value
		_apply_stage()
		_apply_progress()
@export_range(0.0, 1.0, 0.01) var progress: float = 0.0:
	set(value):
		if not is_finite(value): return
		progress = clampf(value, 0.0, 1.0)
		_apply_progress()

func _ready() -> void:
	_apply_stage()
	_apply_progress()

func set_stage(value: String) -> void:
	stage = value

func set_progress(value: float) -> void:
	progress = value

func _apply_stage() -> void:
	for key in STAGES:
		var group := get_node_or_null(NodePath(STAGES[key])) as Node3D
		if group != null: group.visible = key == stage

func _apply_progress() -> void:
	var seam := get_node_or_null("Sewing/SeamStitches")
	if seam == null: return
	var count := seam.get_child_count()
	for index in count:
		(seam.get_child(index) as Node3D).visible = index < ceili(progress * count)

func local_contacts(stage_name: String = "") -> Dictionary:
	var selected: String = stage if stage_name.is_empty() else stage_name
	if not STAGES.has(selected): return {}
	var group := get_node_or_null(NodePath(STAGES[selected]+"/Contacts"))
	if group == null: return {}
	var contacts := {}
	for name_key in CONTACT_KEYS:
		var marker := group.get_node_or_null(NodePath(name_key)) as Marker3D
		if marker != null: contacts[CONTACT_KEYS[name_key]] = _relative_transform(marker).origin
	for side in [-1.0, 1.0]:
		var support: Variant = surface_point(selected, side*SUPPORT_X, SUPPORT_Z)
		if support is Vector3: contacts["support_left" if side < 0 else "support_right"] = support
	return contacts

func surface_point(stage_name: String, x: float, z: float) -> Variant:
	# Query the rendered triangles at this XZ, including cloth hems and visible
	# thread. A stage's maximum AABB height is not its surface at a hand contact.
	# Relative transforms and mesh faces work before SceneTree attachment too.
	if not STAGES.has(stage_name) or not is_finite(x) or not is_finite(z): return null
	var group := get_node_or_null(NodePath(STAGES[stage_name]))
	if group == null: return null
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(group, meshes)
	var visible_ids := PackedStringArray()
	for instance in meshes: visible_ids.append(str(instance.get_instance_id()))
	# The visible mesh set distinguishes partial seam lengths. A completed
	# stitch appearing at this XZ must not reuse the earlier cloth-only result.
	var key: String = "%s|%.9f|%.9f|%s" % [stage_name, x, z, ",".join(visible_ids)]
	if _surface_cache.has(key): return _surface_cache[key]
	var bounds: AABB = geometry_bounds(stage_name)
	if x < bounds.position.x or x > bounds.end.x or z < bounds.position.z or z > bounds.end.z:
		_surface_cache[key] = null
		return null
	var origin := Vector3(x, bounds.end.y + 0.01, z)
	var end := Vector3(x, bounds.position.y - 0.01, z)
	var highest: Variant = null
	for instance in meshes:
		var mesh_id: int = instance.mesh.get_instance_id()
		if not _mesh_face_cache.has(mesh_id): _mesh_face_cache[mesh_id] = instance.mesh.get_faces()
		var faces: PackedVector3Array = _mesh_face_cache[mesh_id]
		var frame: Transform3D = _relative_transform(instance)
		var inverse: Transform3D = frame.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_end: Vector3 = inverse * end
		for index in range(0, faces.size(), 3):
			var intersection: Variant = Geometry3D.segment_intersects_triangle(local_origin, local_end, faces[index], faces[index+1], faces[index+2])
			if not intersection is Vector3: continue
			var point: Vector3 = frame * intersection
			if highest == null or point.y > highest.y: highest = point
	_surface_cache[key] = highest
	return highest

func clear_contact_cache() -> void:
	# Editing mesh transforms/resources can explicitly discard the per-instance
	# measurements. Runtime stage/progress changes are already separate keys.
	_surface_cache.clear()
	_mesh_face_cache.clear()

func geometry_bounds(stage_name: String = "") -> AABB:
	# A pure measurement of the saved mesh geometry in workpiece-local space.
	# Hidden future stitches do not enlarge an in-progress bound.
	var selected: String = stage if stage_name.is_empty() else stage_name
	if not STAGES.has(selected): return AABB()
	var group := get_node_or_null(NodePath(STAGES[selected]))
	if group == null: return AABB()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(group, meshes)
	var bounds := AABB()
	var found := false
	for instance in meshes:
		var measured: AABB = _relative_transform(instance) * instance.get_aabb()
		bounds = measured if not found else bounds.merge(measured)
		found = true
	return bounds

func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is Node3D and not child.visible: continue
		# local_contacts is also called on a fresh PackedScene before _ready.
		# Honour the exported progress even before the saved stitch nodes have
		# received their first visibility update.
		if node.name == &"SeamStitches" and child.get_index() >= ceili(progress*node.get_child_count()): continue
		if child is MeshInstance3D and child.mesh != null: meshes.append(child)
		_collect_meshes(child, meshes)

func _relative_transform(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node3D = node
	while cursor != self and cursor != null:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result

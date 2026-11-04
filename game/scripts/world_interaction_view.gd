class_name WorldInteractionView
extends Node3D

# Object roots use the simulation's world-space bottom centre. The unmodified
# furniture GLB has its lowest vertices 1 cm above its own origin.
const RADIO_SCENE := preload("res://game/assets/furniture/PR_Radio.glb")
const RADIO_MESH_OFFSET := Vector3(0, -.01, 0)
const LEGACY_RADIO_PATH := NodePath("ActivityLayout/Workshop/radio_workAssembly/Radio")

var town: Node3D
var avatars: Dictionary = {}
var simulation
var object_nodes: Dictionary = {}

func _ready() -> void:
	if simulation != null: sync(0)

func setup(owner_town: Node3D, resident_avatars: Dictionary, sim) -> void:
	town = owner_town
	avatars = resident_avatars
	simulation = sim
	_hide_legacy_radio()
	sync(0)

func sync(_delta: float) -> void:
	_hide_legacy_radio()
	var records: Dictionary = {}
	if simulation != null and simulation.interactions != null:
		records = simulation.interactions.objects
	var present := {}
	for id in records:
		var record: Dictionary = records[id]
		if record.get("kind", "") != "radio": continue
		present[id] = true
		var node := object_node(str(id))
		if not is_instance_valid(node):
			node = _make_radio(str(id))
			object_nodes[id] = node
		_apply_transform(node, record)
		node.set_meta("holder", record.get("holder", ""))
		node.set_meta("container", record.get("container", ""))
		node.set_meta("state", record.get("state", ""))
	for id in object_nodes.keys():
		if present.has(id): continue
		var stale: Node3D = object_nodes[id]
		object_nodes.erase(id)
		if is_instance_valid(stale):
			# Remove immediately: reset/restore may run again before queue_free.
			remove_child(stale)
			stale.queue_free()

func object_node(id: String) -> Node3D:
	return object_nodes.get(id) as Node3D

func _hide_legacy_radio() -> void:
	if not is_instance_valid(town): return
	var old_radio := town.get_node_or_null(LEGACY_RADIO_PATH) as Node3D
	if is_instance_valid(old_radio): old_radio.hide()

func _make_radio(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Object_" + id.validate_node_name()
	root.set_meta("interaction_object_id", id)
	root.set_meta("kind", "radio")
	add_child(root)
	var mesh := RADIO_SCENE.instantiate() as Node3D
	mesh.name = "Radio"
	mesh.position = RADIO_MESH_OFFSET
	root.add_child(mesh)
	return root

func _apply_transform(node: Node3D, record: Dictionary) -> void:
	var desired := Transform3D(Basis(Vector3.UP, float(record.get("yaw", 0.0))), record.position)
	var holder: String = record.get("holder", "")
	var avatar = avatars.get(holder)
	if not holder.is_empty() and is_instance_valid(avatar):
		var contacts = avatar.contacts
		if is_instance_valid(contacts) and is_instance_valid(contacts.interaction_motion):
			var motion = contacts.interaction_motion
			if motion.object_active and motion.object_id == record.id:
				desired = motion.object_transform
	if is_inside_tree():
		node.global_transform = desired
	else:
		# setup may be called before this view is attached to the scene tree.
		node.transform = transform.affine_inverse() * desired

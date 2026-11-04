class_name TabletopGameView
extends Node3D

# The saved world pool owns the pieces. Historical sessions never instantiate
# another set, and picking up/putting away a piece keeps this same visible node.
const BOARD_SCENE := preload("res://game/scenes/props/tabletop_board.tscn")
const PIECE_SCENE := preload("res://game/scenes/props/tabletop_piece.tscn")
const TRAY_SCENE := preload("res://game/scenes/props/tabletop_tray.tscn")
const BOARD_SIZE := Vector3(.30, .025, .30)
const CELL_PITCH := .065
const TRAY_FLOOR_HEIGHT := .025

var town: Node3D
var avatars: Dictionary = {}
var simulation
var board_node: Node3D
var trays: Dictionary = {}
var piece_nodes: Dictionary = {}
var color_materials: Dictionary = {}

func _ready() -> void:
	if simulation != null: sync(0)

func setup(owner_town: Node3D, resident_avatars: Dictionary, sim) -> void:
	town = owner_town
	avatars = resident_avatars
	simulation = sim
	sync(0)

func sync(_delta: float) -> void:
	if simulation == null or simulation.tabletop == null: return
	_sync_board()
	_sync_trays()
	var present := {}
	for id in simulation.tabletop.pieces:
		var record: Dictionary = simulation.tabletop.pieces[id]
		present[id] = true
		var node := piece_node(str(id))
		if not is_instance_valid(node):
			node = _make_piece(str(id), int(record.color))
			piece_nodes[id] = node
		_apply_piece_transform(node, record)
		for key in ["color", "holder", "container", "location", "reserved_by", "cell"]:
			node.set_meta(key, record.get(key))
	for id in piece_nodes.keys():
		if present.has(id): continue
		var stale: Node3D = piece_nodes[id]
		piece_nodes.erase(id)
		if is_instance_valid(stale):
			remove_child(stale)
			stale.queue_free()

func piece_node(id: String) -> Node3D:
	return piece_nodes.get(id) as Node3D

func _sync_board() -> void:
	if not is_instance_valid(board_node):
		board_node = BOARD_SCENE.instantiate() as Node3D
		board_node.name = "FourInRowBoard"
		add_child(board_node)
	var config: Dictionary = simulation.tabletop.config
	var size: Vector3 = config.board_size
	var display_scale := size / BOARD_SIZE
	var facing := Basis(Vector3.UP, float(config.board_yaw))
	var board_basis := Basis(facing.x * display_scale.x, facing.y * display_scale.y, facing.z * display_scale.z)
	_set_world(board_node, Transform3D(board_basis, config.board_origin))
	board_node.set_meta("tabletop_board_id", config.board_id)
	board_node.set_meta("cell_pitch", float(config.cell_pitch))
	var active: Dictionary = simulation.tabletop.active_session()
	board_node.set_meta("session_id", active.get("id", ""))
	board_node.set_meta("phase", active.get("phase", "idle"))
	# Cell centres match the logical board even if an authored board size/pitch
	# is tuned later; the root's physical scale must not apply the pitch twice.
	for index in 16:
		var tile: Node3D = board_node.get_node("Cells/Cell%02d" % index)
		tile.position.x = (index % 4 - 1.5) * float(config.cell_pitch) / display_scale.x
		tile.position.z = (int(index / 4) - 1.5) * float(config.cell_pitch) / display_scale.z
		tile.scale.x = float(config.cell_pitch) / (CELL_PITCH * display_scale.x)
		tile.scale.z = float(config.cell_pitch) / (CELL_PITCH * display_scale.z)

func _sync_trays() -> void:
	var config: Dictionary = simulation.tabletop.config
	for color in [1, 2]:
		var tray: Node3D = trays.get(color)
		if not is_instance_valid(tray):
			tray = TRAY_SCENE.instantiate() as Node3D
			tray.name = "PieceTray%d" % color
			tray.set_meta("interaction_container", "bank_%d" % color)
			add_child(tray)
			trays[color] = tray
			var lip: MeshInstance3D = tray.get_node("FrontLip")
			lip.material_override = _color_material(color)
		var floor_position: Vector3 = simulation.tabletop.bank_position(color, 1)
		var origin := floor_position - Vector3.UP * TRAY_FLOOR_HEIGHT
		_set_world(tray, Transform3D(Basis(Vector3.UP, float(config.board_yaw)), origin))

func _make_piece(id: String, color: int) -> Node3D:
	var node := PIECE_SCENE.instantiate() as Node3D
	node.name = "Piece_" + id.validate_node_name()
	node.set_meta("interaction_object_id", id)
	node.set_meta("tabletop_piece_id", id)
	for part_name in ["PaintedSide", "Face"]:
		var part: MeshInstance3D = node.get_node(part_name)
		part.material_override = _color_material(color)
	add_child(node)
	return node

func _color_material(color: int) -> StandardMaterial3D:
	if not color_materials.has(color):
		var material := StandardMaterial3D.new()
		material.resource_name = "VermilionCounter" if color == 1 else "IndigoCounter"
		material.albedo_color = Color("b34332") if color == 1 else Color("345b84")
		material.roughness = .70
		color_materials[color] = material
	return color_materials[color]

func _apply_piece_transform(node: Node3D, record: Dictionary) -> void:
	var desired := Transform3D(Basis(Vector3.UP, float(record.get("yaw", 0))), record.position)
	var holder: String = record.get("holder", "")
	var avatar = avatars.get(holder)
	if not holder.is_empty() and is_instance_valid(avatar):
		var contacts = avatar.contacts
		if is_instance_valid(contacts) and is_instance_valid(contacts.interaction_motion):
			var motion = contacts.interaction_motion
			if motion.object_active and motion.object_id == record.id:
				desired = motion.object_transform
	_set_world(node, desired)

func _set_world(node: Node3D, desired: Transform3D) -> void:
	if is_inside_tree():
		node.global_transform = desired
	else:
		node.transform = transform.affine_inverse() * desired

extends SceneTree

func _initialize() -> void: call_deferred("run")

func owned(parent: Node, child: Node, owner_node: Node) -> void:
	parent.add_child(child);child.owner = owner_node

func run() -> void:
	var town = load("res://game/scenes/town.tscn").instantiate()
	var old = town.get_node_or_null("ActivityLayout")
	if old: old.free()
	for room_name in ["OgawaHouse","SaekiHouse","SharedHouse","BakeryCafe","Workshop"]:
		var room = town.get_node(room_name)
		room.get_node("Floor").position.y = -.07
		for child in room.get_children():
			if child is MeshInstance3D and child.mesh is BoxMesh:
				var size: Vector3 = child.mesh.size
				if size in [Vector3(1.7,.15,.8),Vector3(.1,.8,.6),Vector3(1.2,.35,1.9),Vector3(.9,.16,.42)]: child.free()
	for child in town.get_children():
		if child.name in ["CafeCounter","Bread","WorkshopTable","Radio"]: child.free();continue
		if child is MeshInstance3D:
			if child.mesh is BoxMesh and child.mesh.size==Vector3(1.7,.9,.7): child.free()
			elif child.mesh is SphereMesh and is_equal_approx(child.mesh.height,.16): child.free()
	owned(town,load("res://game/scenes/activity_layout.tscn").instantiate(),town)
	var packed := PackedScene.new();assert(packed.pack(town)==OK)
	assert(ResourceSaver.save(packed,"res://game/scenes/town.tscn")==OK);town.free()
	var bench := Node3D.new();bench.name = "Bench"
	owned(bench,load("res://game/assets/furniture/PR_Bench.glb").instantiate(),bench)
	for side in 2:
		var seat := ActivitySpot.new();seat.name = "Seat%d"%side;seat.spot_id = seat.name
		seat.site = "square";seat.actions = PackedStringArray(["social","rest","meet"])
		seat.pose_kind = "seat";seat.position.x = -.48 if side==0 else .48;seat.group = "bench";seat.pair = "bench"
		owned(bench,seat,bench)
		for item in [["Approach",Vector3(0,0,.65)],["Contact",Vector3(0,.46,0)],
			["HandLeft",Vector3(.13,.76,.35)],["HandRight",Vector3(-.13,.76,.35)]]:
			var marker := Marker3D.new();marker.name = item[0];marker.position = item[1];owned(seat,marker,bench)
	packed = PackedScene.new();assert(packed.pack(bench)==OK)
	assert(ResourceSaver.save(packed,"res://game/scenes/bench.tscn")==OK);bench.free()
	print("Furniture installed in the editable town and bench scenes")
	quit()

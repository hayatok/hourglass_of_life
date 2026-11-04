extends SceneTree

var layout: Node3D
var serial := 0

func _initialize() -> void: call_deferred("run")

func add(parent: Node, child: Node) -> Node:
	parent.add_child(child)
	child.owner = layout
	return child

func marker(parent: Node3D, name: String, at: Vector3) -> void:
	var node := Marker3D.new();node.name = name;node.position = at
	add(parent,node)

func assembly(parent: Node3D, name: String, at: Vector3, yaw: float = 0) -> Node3D:
	var node := Node3D.new();node.name = name;node.position = at;node.rotation.y = yaw;add(parent,node)
	return node

func prop(parent: Node3D, name: String, asset: String, at: Vector3, yaw: float = 0, footprint := Vector2.ZERO) -> Node3D:
	var node: Node3D = load("res://game/assets/furniture/PR_"+asset+".glb").instantiate()
	node.name = name;node.position = at;node.rotation.y = yaw
	add(parent,node)
	if footprint!=Vector2.ZERO: node.set_meta("footprint",footprint)
	return node

func spot(parent: Node3D, id: String, site: String, at: Vector3, yaw: float, pose: String,
		actions: Array, approach: Vector3, contact: Vector3, group: String = "", pair: String = "", resident: String = "", hands_y: float = .78) -> ActivitySpot:
	var node := ActivitySpot.new();node.name = id;node.spot_id = id;node.site = site
	node.position = at;node.rotation.y = yaw;node.pose_kind = pose;node.actions = PackedStringArray(actions)
	node.group = group;node.pair = pair;node.resident = resident;add(parent,node)
	marker(node,"Approach",approach);marker(node,"Contact",contact)
	marker(node,"HandLeft",Vector3(.13,hands_y,.38 if pose=="seat" else .34))
	marker(node,"HandRight",Vector3(-.13,hands_y,.38 if pose=="seat" else .34))
	return node

func chair(parent: Node3D, id: String, site: String, at: Vector3, yaw: float, side: float,
		group: String = "", pair: String = "") -> void:
	var node := assembly(parent,id+"Assembly",at,yaw)
	prop(node,"Chair","Chair",Vector3.ZERO,0,Vector2(.51,.51))
	spot(node,id,site,Vector3.ZERO,0,"seat",["eat","rest","care","social","meet"],Vector3(side*.50,0,-.08),Vector3(0,.46,0),group,pair)

func workstation(parent: Node3D, id: String, site: String, at: Vector3, group: String,
		actions: Array = ["work","hobby","chores","joint_work","meet"]) -> Node3D:
	var node := assembly(parent,id+"Assembly",at)
	prop(node,"Worktable","Worktable",Vector3.ZERO,0,Vector2(1.55,.84))
	for i in 2:
		spot(node,id+"_%d"%i,site,Vector3(-.35 if i==0 else .35,0,.66),PI,"work",
			actions,Vector3.ZERO,Vector3.ZERO,group,id,"",.99)
	return node

func room(name: String, site: String, at: Vector3) -> Node3D:
	var node := Node3D.new();node.name = name;node.position = at;add(layout,node)
	node.set_meta("site",site);node.set_meta("room_size",Vector2(5.6,5.6))
	return node

func home(name: String, site: String, at: Vector3, residents: Array, group: String) -> void:
	var node := room(name,site,at)
	for i in residents.size():
		var x: float = [-1.85,-.25,1.35][i] if residents.size()==3 else [-1.75,.25][i]
		var bed_at := Vector3(x,0,-1.5)
		var sleeping := assembly(node,"Bed_"+residents[i]+"Assembly",bed_at)
		prop(sleeping,"Bed","Bed",Vector3.ZERO,0,Vector2(1,2.05))
		spot(sleeping,"sleep_"+residents[i],site,Vector3.ZERO,0,"bed",["sleep"],Vector3(.75,0,0),Vector3(0,.46,-.72),"","",residents[i])
	var dining := assembly(node,"DiningAssembly",Vector3(-1.45,0,1.3))
	prop(dining,"DiningTable","RoundTable",Vector3.ZERO,0,Vector2(1.10,1.10))
	chair(dining,site+"_dine_0",site,Vector3(-.4,0,.75),PI,1)
	chair(dining,site+"_dine_1",site,Vector3(.4,0,.75),PI,-1)
	if residents.size()==3: chair(dining,site+"_dine_2",site,Vector3(0,0,-.75),0,1)
	prop(dining,"Meal","BreadPlate",Vector3(0,.76,0))
	prop(dining,"Drink","Mug",Vector3(.27,.76,0))
	var desk := workstation(node,site+"_desk",site,Vector3(1.45,0,1.3),group)
	if group=="model": prop(desk,"TownModel","TownModel",Vector3(0,.95,.22))

func run() -> void:
	layout = Node3D.new();layout.name = "ActivityLayout"
	home("Ogawa","home_ogawa",Vector3(-9,0,6),["nagisa","ryo","rin"],"model")
	home("Saeki","home_saeki",Vector3(-9,0,-4),["osamu","fumi"],"home_saeki")
	home("Shared","home_shared",Vector3(9,0,6),["maho","ritsu","aoi"],"home_shared")
	var cafe := room("Cafe","bakery_cafe",Vector3(8,0,-5))
	var baking := workstation(cafe,"bakery_work","bakery_cafe",Vector3(0,0,-1.3),"bread")
	prop(baking,"Bread","BreadPlate",Vector3(0,.95,.23))
	for i in 2:
		var x := -1.4 if i==0 else 1.4
		var table := assembly(cafe,"CafeTable%dAssembly"%i,Vector3(x,0,1.2))
		prop(table,"Table","RoundTable",Vector3.ZERO,0,Vector2(1.10,1.10))
		chair(table,"cafe_%d_a"%i,"bakery_cafe",Vector3(-.8,0,0),PI/2,1,"cafe","cafe_pair_%d"%i)
		chair(table,"cafe_%d_b"%i,"bakery_cafe",Vector3(.8,0,0),-PI/2,1,"cafe","cafe_pair_%d"%i)
		prop(table,"Meal","BreadPlate",Vector3(0,.76,0))
		prop(table,"Drink","Mug",Vector3(0,.76,-.26))
	var workshop := room("Workshop","workshop",Vector3(0,0,-7))
	var radio := workstation(workshop,"radio_work","workshop",Vector3(0,0,-.7),"radio")
	prop(radio,"Radio","Radio",Vector3(0,.95,.24))
	# Small public shared tables give the remaining projects a physical surface.
	for entry in [["photo","garden",Vector3(-1.2,0,3.8)],["music","square",Vector3(2.8,0,4.5)]]:
		var node := Node3D.new();node.name = entry[0].capitalize();node.position = entry[2];add(layout,node)
		workstation(node,entry[0]+"_work",entry[1],Vector3.ZERO,entry[0])
		if entry[0]=="photo": prop(node,"PhotoMug","Mug",Vector3(0,.95,.2))
	# Keep the original board table and spot IDs dedicated to the physical game.
	var boards := assembly(layout,"Craft",Vector3(-2.8,0,6))
	workstation(boards,"craft_work","square",Vector3.ZERO,"tabletop",["play"])
	# The production table sits south of the z=7 street, clear of the homes.
	var art := assembly(layout,"CraftArt",Vector3(-2.8,0,8.3))
	workstation(art,"craft_art","square",Vector3.ZERO,"craft")
	var sewing_cabinet: Node3D=load("res://game/scenes/props/sewing_cabinet.tscn").instantiate()
	sewing_cabinet.name="SewingCabinet";sewing_cabinet.position=Vector3(-4.55,0,8.35);add(layout,sewing_cabinet)
	var packed := PackedScene.new()
	assert(packed.pack(layout)==OK)
	assert(ResourceSaver.save(packed,"res://game/scenes/activity_layout.tscn")==OK)
	print("Editable activity layout saved")
	layout.free()
	quit()

extends SceneTree

var town: Node3D

func _initialize() -> void: call_deferred("run")

func add(parent: Node, child: Node) -> Node:
	parent.add_child(child);child.owner = town;return child

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new();result.albedo_color = color;result.roughness = .85;return result

func box(parent: Node3D, name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size = size
	var node := MeshInstance3D.new();node.name = name;node.mesh = mesh;node.position = at;node.material_override = mat;add(parent,node);return node

func cylinder(parent: Node3D, name: String, radius: float, height: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new();shape.top_radius = radius;shape.bottom_radius = radius;shape.height = height;shape.radial_segments = 12
	var node := MeshInstance3D.new();node.name = name;node.mesh = shape;node.position = at;node.material_override = mat;add(parent,node);return node

func ground_material(color: Color, paving: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new();mat.shader = load("res://game/assets/town_ground.gdshader")
	mat.set_shader_parameter("main_color",color);mat.set_shader_parameter("paving",paving);return mat

func lamp(at: Vector3, index: int) -> void:
	var root := Node3D.new();root.name = "StreetLamp%d"%index;root.position = at;add(town,root)
	var metal := material(Color("334e4b"))
	cylinder(root,"Base",.16,.12,Vector3(0,.06,0),metal)
	cylinder(root,"Post",.045,2.6,Vector3(0,1.3,0),metal)
	box(root,"Arm",Vector3(.48,.06,.06),Vector3(.20,2.59,0),metal)
	box(root,"LanternRoof",Vector3(.34,.07,.30),Vector3(.42,2.50,0),metal)
	box(root,"LanternBase",Vector3(.27,.045,.24),Vector3(.42,2.18,0),metal)
	var glass := material(Color("ffe2a0"));glass.emission_enabled = true;glass.emission = Color("d8a052");glass.emission_energy_multiplier = .6
	box(root,"LanternGlow",Vector3(.20,.26,.18),Vector3(.42,2.34,0),glass)
	for side in [-1,1]:box(root,"LanternFrame",Vector3(.025,.31,.24),Vector3(.42+side*.125,2.34,0),metal)
	var light := OmniLight3D.new();light.name = "Light";light.position = Vector3(.42,2.25,0);light.light_color = Color("ffd18b");light.omni_range = 6;light.omni_attenuation = 1.4;light.shadow_enabled = false;add(root,light)

func rectangle(surface: SurfaceTool, rect: Rect2) -> void:
	var a := Vector3(rect.position.x,0,rect.position.y);var b := Vector3(rect.end.x,0,rect.position.y)
	var c := Vector3(rect.end.x,0,rect.end.y);var d := Vector3(rect.position.x,0,rect.end.y)
	for point in [a,b,c,a,c,d]: surface.set_normal(Vector3.UP);surface.add_vertex(point)

func subtract_rect(rect: Rect2, hole: Rect2) -> Array:
	if not rect.intersects(hole): return [rect]
	var cut := rect.intersection(hole)
	var pieces := [Rect2(rect.position,Vector2(cut.position.x-rect.position.x,rect.size.y)),
		Rect2(Vector2(cut.end.x,rect.position.y),Vector2(rect.end.x-cut.end.x,rect.size.y)),
		Rect2(Vector2(cut.position.x,rect.position.y),Vector2(cut.size.x,cut.position.y-rect.position.y)),
		Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,rect.end.y-cut.end.y))]
	return pieces.filter(func(piece): return piece.size.x>.00001 and piece.size.y>.00001)

func ground() -> void:
	# A single non-overlapping grid at y=0. Its paved routes follow the actual graph.
	var routes: Array = []
	for link in LifeSimulation.LINKS: routes.append([LifeSimulation.WAYPOINTS[link[0]],LifeSimulation.WAYPOINTS[link[1]]])
	var sim = root.get_node("Sim")
	for entry in LifeSimulation.OUTER_ENTRIES.values():
		var corner: Vector3 = sim._street_corner(entry)
		routes.append([entry,corner]);routes.append([corner,sim.graph.get_point_position(sim.graph.get_closest_point(corner))])
	var surfaces := [SurfaceTool.new(),SurfaceTool.new()]
	for surface in surfaces: surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var holes: Array = []
	for site in ["home_ogawa","home_saeki","home_shared","bakery_cafe","workshop"]:
		var style := "Cafe" if site=="bakery_cafe" else ("Workshop" if site=="workshop" else "Home")
		var asset = load("res://game/assets/architecture/AR_"+style+".glb").instantiate()
		var floor_mesh: MeshInstance3D = asset.find_children("*_Floor_LOD0","MeshInstance3D",true,false)[0]
		var bounds := floor_mesh.get_aabb();var at: Vector3 = LifeSimulation.SITES[site]
		holes.append(Rect2(Vector2(at.x+bounds.position.x,at.z+bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
		asset.free()
	for iz in 72:
		for ix in 84:
			var x := -21+ix*.5;var z := -18+iz*.5
			var center := Vector2(x+.25,z+.25)
			var paved := Rect2(-5.5,-2,11,10).has_point(center)
			for segment in routes:
				var a: Vector3 = segment[0];var b: Vector3 = segment[1]
				if center.distance_to(Geometry2D.get_closest_point_to_segment(center,Vector2(a.x,a.z),Vector2(b.x,b.z)))<.73: paved = true;break
			var surface: SurfaceTool = surfaces[1 if paved else 0]
			var pieces: Array = [Rect2(x,z,.5,.5)]
			for hole in holes:
				var remaining: Array = []
				for piece in pieces: remaining.append_array(subtract_rect(piece,hole))
				pieces = remaining
			for piece in pieces: rectangle(surface,piece)
	# Quiet outer ground removes the floating-board edge without overlapping the town mesh.
	for rect in [Rect2(-70,-60,49,120),Rect2(21,-60,49,120),Rect2(-21,-60,42,42),Rect2(-21,18,42,42)]:rectangle(surfaces[0],rect)
	var mesh := ArrayMesh.new()
	for i in 2:
		surfaces[i].set_material(ground_material(Color("c9bea7") if i else Color("8da66e"),i==1))
		surfaces[i].commit(mesh)
	var node := MeshInstance3D.new();node.name = "Ground";node.mesh = mesh;add(town,node)

func run() -> void:
	var old: Node3D = load("res://game/scenes/town.tscn").instantiate()
	town = Node3D.new();town.name = "Town";town.set_script(load("res://game/scripts/town_environment.gd"))
	ground()
	var sites := [["OgawaHouse","Home","home_ogawa","小川家"],["SaekiHouse","Home","home_saeki","佐伯家"],
		["SharedHouse","Home","home_shared","共同住宅"],["BakeryCafe","Cafe","bakery_cafe","パンと喫茶  こむぎ"],["Workshop","Workshop","workshop","佐伯修理工房"]]
	for entry in sites:
		var building := TownBuilding.new();building.name = entry[0];building.room_site = entry[2];building.position = LifeSimulation.SITES[entry[2]];add(town,building)
		var architecture = load("res://game/assets/architecture/AR_"+entry[1]+".glb").instantiate();architecture.name = "Architecture";add(building,architecture)
		var sign: Label3D = old.get_node(str(entry[0])+"/Sign").duplicate();sign.position = Vector3(0,4.55,0);sign.pixel_size = .007;add(building,sign)
	# Keep landscape until its separate foliage asset is ready; no duplicate old shell.
	for child in old.get_children():
		if child is MeshInstance3D and (child.mesh is CylinderMesh or child.mesh is SphereMesh):add(town,child.duplicate())
	var exit_sign: Label3D = old.get_node("ExitSign").duplicate();add(town,exit_sign)
	add(town,old.get_node("Sun").duplicate());add(town,old.get_node("WorldEnvironment").duplicate())
	add(town,load("res://game/scenes/activity_layout.tscn").instantiate())
	var positions := [Vector3(-5.9,0,-.25),Vector3(5.9,0,-.25),Vector3(-5.9,0,9.4),Vector3(5.9,0,9.4),Vector3(-1.2,0,-4.1)]
	for i in positions.size():lamp(positions[i],i)
	var packed := PackedScene.new();assert(packed.pack(town)==OK)
	assert(ResourceSaver.save(packed,"res://game/scenes/town.tscn")==OK)
	town.free();old.free();print("JRPG neighborhood installed with camera cutaways and day/night lighting");quit()

class_name HomeArt
extends RefCounted

# Visual production layer only. The plan and LivingHouse retain every collider,
# fixture root, use marker, door pivot and admission rule. Existing fixture
# meshes are hidden (not removed with their collision children), then replaced
# by an Art child. Decorative possessions are authored still life, not simulated
# food, inventory, completed work, or evidence of a resident's actual history.
const OAK = preload("res://game/assets/foundation/home/oak.gdshader")
const LINEN = preload("res://game/assets/foundation/home/linen.gdshader")
const TILES = preload("res://game/assets/foundation/home/tiles.gdshader")
const MUG := "res://game/assets/furniture/PR_Mug.glb"
const TOWN_MODEL := "res://game/assets/furniture/PR_TownModel.glb"
var _materials: Dictionary = {}

func _v(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])

func _paint(key: String, color: String, roughness: float = .8) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(color);material.roughness=roughness
	_materials[key]=material
	return material

func _wood(key: String, color: String = "b98759", boards: bool = false, vertical: bool = false) -> ShaderMaterial:
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new();material.shader=OAK
	material.set_shader_parameter("timber_color",Color(color))
	material.set_shader_parameter("floor_boards",boards);material.set_shader_parameter("vertical_grain",vertical)
	_materials[key]=material
	return material

func _cloth(key: String, color: String, stripes: float = 0.0) -> ShaderMaterial:
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new();material.shader=LINEN
	material.set_shader_parameter("cloth_color",Color(color));material.set_shader_parameter("stripe_amount",stripes)
	_materials[key]=material
	return material

func _tiles(key: String, color: String, width: float = .24) -> ShaderMaterial:
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new();material.shader=TILES
	material.set_shader_parameter("tile_color",Color(color));material.set_shader_parameter("tile_width",width)
	_materials[key]=material
	return material

func _node(parent: Node3D, label: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var result := Node3D.new();result.name=label;result.position=at;parent.add_child(result)
	return result

func _mesh(parent: Node3D, label: String, shape: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new();result.name=label;result.mesh=shape;result.material_override=material
	result.position=at;parent.add_child(result)
	return result

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new();shape.size=size
	return _mesh(parent,label,shape,at,material)

func _cylinder(parent: Node3D, label: String, at: Vector3, radius: float, height: float, material: Material, top: float = -1) -> MeshInstance3D:
	var shape := CylinderMesh.new();shape.bottom_radius=radius;shape.top_radius=radius if top<0 else top
	shape.height=height;shape.radial_segments=16
	return _mesh(parent,label,shape,at,material)

func _sphere(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := SphereMesh.new();shape.radius=.5;shape.height=1;shape.radial_segments=16;shape.rings=8
	var result := _mesh(parent,label,shape,at,material);result.scale=size
	return result

func _rod(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var result := _cylinder(parent,label,(a+b)*.5,radius,a.distance_to(b),material)
	result.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	return result

func _round_rect(width: float, depth: float, radius: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var half := Vector2(width,depth)*.5
	radius=minf(radius,minf(width,depth)*.48)
	for corner in 4:
		var angle := float(corner)*PI*.5
		var center := Vector2(half.x-radius,half.y-radius)
		if corner in [1,2]: center.x=-center.x
		if corner in [2,3]: center.y=-center.y
		for step in 4:
			var heading := angle+float(step)/3*PI*.5
			points.append(center+Vector2(cos(heading),sin(heading))*radius)
	return points

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# Godot front faces use clockwise winding; keep the explicit lighting normal
	# outward while allowing the same generator to make interior bowl surfaces.
	if (b-a).cross(c-a).dot(normal)>0:
		var swap := b;b=c;c=swap
	for vertex: Vector3 in [a,b,c]:
		surface.set_normal(normal);surface.set_uv(Vector2(vertex.x,vertex.z));surface.add_vertex(vertex)

func _slab(parent: Node3D, label: String, at: Vector3, size: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var perimeter := _round_rect(size.x,size.z,radius)
	var top := size.y*.5;var bottom := -top
	for index in perimeter.size():
		var first: Vector2=perimeter[index];var last: Vector2=perimeter[(index+1)%perimeter.size()]
		var a := Vector3(first.x,bottom,first.y);var b := Vector3(last.x,bottom,last.y)
		var c := Vector3(last.x,top,last.y);var d := Vector3(first.x,top,first.y)
		var side := Vector3(last.y-first.y,0,first.x-last.x).normalized()
		_triangle(surface,a,b,c,side);_triangle(surface,a,c,d,side)
		_triangle(surface,Vector3(0,top,0),d,c,Vector3.UP)
		_triangle(surface,Vector3(0,bottom,0),a,b,Vector3.DOWN)
	return _mesh(parent,label,surface.commit(),at,material)

func _recess(parent: Node3D, label: String, at: Vector3, outer: Vector2, mouth: Vector2, bottom: Vector2, drop: float, material: Material, closed_floor: bool = true) -> Node3D:
	var result := _node(parent,label,at)
	var outside := _round_rect(outer.x,outer.y,.04)
	var inside := _round_rect(mouth.x,mouth.y,.07)
	var floor_edge := _round_rect(bottom.x,bottom.y,.05)
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outside.size():
		var next: int=(index+1)%outside.size()
		var a := Vector3(outside[index].x,0,outside[index].y);var b := Vector3(outside[next].x,0,outside[next].y)
		var c := Vector3(inside[next].x,0,inside[next].y);var d := Vector3(inside[index].x,0,inside[index].y)
		_triangle(surface,a,b,c,Vector3.UP);_triangle(surface,a,c,d,Vector3.UP)
		var e := Vector3(floor_edge[next].x,-drop,floor_edge[next].y);var f := Vector3(floor_edge[index].x,-drop,floor_edge[index].y)
		var middle := (c+d)*.5
		var inward := Vector3(-middle.x,drop*1.8,-middle.z).normalized()
		_triangle(surface,d,c,e,inward);_triangle(surface,d,e,f,inward)
	_mesh(result,"RimAndInterior",surface.commit(),Vector3.ZERO,material)
	if closed_floor: _slab(result,"RecessFloor",Vector3(0,-drop-.008,0),Vector3(bottom.x,.016,bottom.y),.05,material)
	return result

func _outer_bowl(parent: Node3D, at: Vector3, upper: Vector2, lower: Vector2, depth: float, material: Material) -> void:
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := _round_rect(upper.x,upper.y,.10)
	var bottom := _round_rect(lower.x,lower.y,.07)
	for index in top.size():
		var next: int=(index+1)%top.size()
		var a := Vector3(top[index].x,0,top[index].y);var b := Vector3(top[next].x,0,top[next].y)
		var c := Vector3(bottom[next].x,-depth,bottom[next].y);var d := Vector3(bottom[index].x,-depth,bottom[index].y)
		var middle := (a+b)*.5
		var outward := Vector3(middle.x,-depth*.45,middle.z).normalized()
		_triangle(surface,a,b,c,outward);_triangle(surface,a,c,d,outward)
	_mesh(parent,"BowlOuterShell",surface.commit(),at,material)

func _asset(parent: Node3D, label: String, path: String, at: Vector3, amount: float = 1.0) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var packed := load(path) as PackedScene
	if packed==null: return null
	var result := packed.instantiate() as Node3D
	if result==null: return null
	result.name=label;result.position=at;result.scale=Vector3.ONE*amount;parent.add_child(result)
	result.set_meta("authored_decoration",true)
	_strip_collisions(result)
	return result

func _strip_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child);child.queue_free()
		else: _strip_collisions(child)

func _clear_art(parent: Node) -> void:
	for child in parent.get_children():
		if child.get_meta("home_art",false): parent.remove_child(child);child.queue_free()

func _hide_prototype(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D: child.visible=false
		_hide_prototype(child)

func add_visuals(house: LivingHouse) -> void:
	if house==null or house.definition.is_empty(): return
	_clear_art(house)
	var architecture := _node(house,"HomeArt");architecture.set_meta("home_art",true)
	architecture.set_meta("version",1)
	for child in house.get_children():
		if child is Label3D: child.visible=false
		if child is MeshInstance3D and str(child.name).begins_with("Floor_"):
			var id: String=str(child.name).trim_prefix("Floor_")
			if id in ["bathroom","washroom","toilet"]: child.material_override=_tiles("wet_floor","c4d1bf",.22)
			elif id=="entrance": child.material_override=_tiles("entry_floor","b5b3a1",.33)
			else: child.material_override=_wood("floor","bda174",true)
	for wall: Node3D in house.wall_nodes: _wall_details(wall,house.definition.house)
	for record in house.definition.doors: _door_details(house,architecture,record)
	for id in house.fixtures:
		var fixture: Dictionary=house.fixtures[id]
		_clear_art(fixture.node);_hide_prototype(fixture.node)
		var art := _node(fixture.node,"Art");art.set_meta("home_art",true)
		art.set_meta("fixture_id",id);art.set_meta("logical_inventory",false)
		_fixture(art,fixture.definition)
	_windows(house)
	_initial_wall_art(house)
	_pendant(architecture,Vector3(2.7,2.25,6.4))

func _wall_details(wall: Node3D, house: Dictionary) -> void:
	_clear_art(wall)
	var mesh := wall as MeshInstance3D
	if mesh==null or not mesh.mesh is BoxMesh: return
	mesh.material_override=_paint("plaster","e9ddc5",.96)
	var size: Vector3=mesh.mesh.size
	var art := _node(wall,"Timberwork");art.set_meta("home_art",true)
	var low: float=wall.position.y-size.y*.5
	var high: float=wall.position.y+size.y*.5
	if low<.03:
		_box(art,"Skirting",Vector3(0,-size.y*.5+.062,0),Vector3(size.x+.002,.124,size.z+.002),_wood("skirting","a47751"))
	if high>=float(house.get("wall_height",2.65))-.01:
		_box(art,"Cornice",Vector3(0,size.y*.5-.045,0),Vector3(size.x+.004,.09,size.z+.004),_wood("trim","95704e"))

func _door_details(house: LivingHouse, architecture: Node3D, record: Dictionary) -> void:
	var frame := _node(architecture,"Frame_"+str(record.id),_v(record.center))
	if record.axis=="z": frame.rotation.y=PI*.5
	var width: float=record.width;var height: float=record.get("height",2.1)
	var wood := _wood("trim","95704e")
	var thickness: float=house.definition.house.get("wall_thickness",.2)
	for sign in [-1,1]: _box(frame,"Jamb",Vector3(sign*(width*.5+.028),height*.5,0),Vector3(.055,height,thickness+.002),wood)
	_box(frame,"Lintel",Vector3(0,height+.03,0),Vector3(width+.11,.06,thickness+.002),wood)
	var panel: MeshInstance3D=house.doors[record.id].get("panel")
	if panel==null: return
	_clear_art(panel);_hide_prototype(panel)
	# Keep the original moving node and its physical shape; replacing its mesh
	# instead of hiding the parent lets the new artwork follow the exact pivot.
	panel.mesh=null;panel.visible=true
	var art := _node(panel,"DoorArt");art.set_meta("home_art",true)
	if record.axis=="z": art.rotation.y=PI*.5
	var leaf := _slab(art,"TimberLeaf",Vector3.ZERO,Vector3(width,.044,height),.035,_wood("door","bc9a71",false,true))
	leaf.rotation.x=PI*.5
	for side in [-1,1]:
		_box(art,"RecessedPanel",Vector3(0,.12,side*.024),Vector3(width-.15,height-.34,.006),_paint("door_panel","d9c7a8"))
		_box(art,"HandlePlate",Vector3(width*.31,-.05,side*.032),Vector3(.045,.16,.012),_paint("brass","99805a",.48))
		_rod(art,"DoorPull",Vector3(width*.31,-.095,side*.044),Vector3(width*.31,-.005,side*.044),.012,_paint("dark_metal","636962",.42))

func _window(house: LivingHouse, wall_id: String, label: String, center: Vector3, width: float, height: float, inward: Vector3, frosted: bool = false) -> void:
	var support: Node3D
	for wall: Node3D in house.wall_nodes:
		if not str(wall.name).begins_with("Wall_"+wall_id): continue
		var wall_mesh := wall as MeshInstance3D
		if wall_mesh==null or not wall_mesh.mesh is BoxMesh: continue
		var shape: BoxMesh=wall_mesh.mesh
		var local := center-wall.position
		if absf(local.x)<=shape.size.x*.5+.01 and absf(local.z)<=shape.size.z*.5+.01: support=wall;break
	if support==null: return
	var result := _node(support,label,center-support.position);result.set_meta("home_art",true)
	result.rotation.y=atan2(inward.x,inward.z)
	var glass := _paint("frosted_glass" if frosted else "blue_glass","c0d7cc" if frosted else "b6d0ce",.52)
	_box(result,"Glass",Vector3(0,0,.001),Vector3(width,height,.003),glass)
	var trim := _paint("window_ivory","e6d9be")
	for sign in [-1,1]:
		_box(result,"Upright",Vector3(sign*width*.5,0,.003),Vector3(.055,height+.08,.012),trim)
		_box(result,"Crosspiece",Vector3(0,sign*height*.5,.003),Vector3(width+.08,.055,.012),trim)
	_box(result,"Mullion",Vector3(0,0,.005),Vector3(.035,height,.008),trim)
	if not frosted:
		_box(result,"HorizonReflection",Vector3(0,-height*.13,.003),Vector3(width-.06,.018,.003),_paint("glass_reflection","d5e5d5",.65))
		for sign in [-1,1]:
			_box(result,"LinenCurtain",Vector3(sign*(width*.5-.055),.02,.011),Vector3(.10,height-.04,.008),_cloth("curtain","eee3cd",.3))

func _windows(house: LivingHouse) -> void:
	_window(house,"west","LivingWindow",Vector3(.201,1.65,7.45),1.8,1.1,Vector3.RIGHT)
	_window(house,"north","ParentsWindow",Vector3(2.6,1.77,.201),2.1,.9,Vector3.BACK)
	_window(house,"east","ChildWindow",Vector3(11.799,1.65,3.25),1.15,1.1,Vector3.LEFT)
	_window(house,"east","BathWindow",Vector3(11.799,2.0,5.35),.9,.5,Vector3.LEFT,true)
	_window(house,"south","LaundryWindow",Vector3(10.1,1.95,9.799),1.35,.65,Vector3.FORWARD,true)

func _initial_wall_art(house: LivingHouse) -> void:
	# Initial, authored possessions communicate interests. They are deliberately
	# named as initial still life, never recorded as a new work/history event.
	var wall: Node3D
	for candidate: Node3D in house.wall_nodes:
		if str(candidate.name).begins_with("Wall_north"): wall=candidate;break
	if wall==null: return
	for picture in [{"id":"InitialRinDrawing","at":Vector3(8.5,1.52,.202),"size":Vector2(.64,.46),"child":true},{"id":"InitialDesignStudy","at":Vector3(4.6,1.65,.202),"size":Vector2(.62,.42),"child":false}]:
		var root := _node(wall,picture.id,picture.at-wall.position);root.set_meta("home_art",true);root.set_meta("authored_decoration",true)
		var size: Vector2=picture.size
		_box(root,"TimberFrame",Vector3.ZERO,Vector3(size.x,size.y,.012),_wood("trim","95704e"))
		_box(root,"Paper",Vector3(0,0,.008),Vector3(size.x-.035,size.y-.035,.003),_paint("paper","f0e5cb"))
		if picture.child:
			_box(root,"DrawnHouse",Vector3(-.09,-.045,.011),Vector3(.16,.13,.002),_paint("drawing_sand","c8a56b"))
			var roof := SurfaceTool.new();roof.begin(Mesh.PRIMITIVE_TRIANGLES)
			_triangle(roof,Vector3(-.19,.02,.013),Vector3(-.09,.12,.013),Vector3(.01,.02,.013),Vector3.BACK)
			_mesh(root,"DrawnRoof",roof.commit(),Vector3.ZERO,_paint("drawing_red","bd775d"))
			_box(root,"DrawnDoor",Vector3(-.10,-.078,.013),Vector3(.031,.065,.002),_paint("drawing_blue","729394"))
			_box(root,"DrawnTreeTrunk",Vector3(.13,-.065,.012),Vector3(.018,.10,.002),_paint("drawing_trunk","a6885d"))
			_sphere(root,"DrawnTreeCrown",Vector3(.13,.015,.014),Vector3(.12,.14,.003),_paint("drawing_green","8b9d70"))
			_sphere(root,"DrawnSun",Vector3(.21,.125,.014),Vector3(.055,.055,.003),_paint("drawing_sun","d4b46c"))
		else:
			for index in 3:
				_box(root,"DesignSwatch",Vector3((index-1)*.15,.025,.012),Vector3(.12,.18,.002),_paint("swatch_%d"%index,["7f9f96","c49a6e","b8bca0"][index]))
			_box(root,"DesignRule",Vector3(0,-.115,.012),Vector3(.39,.012,.002),_paint("drawing_blue","729394"))

func _fixture(art: Node3D, record: Dictionary) -> void:
	var size := _v(record.size)
	var kind: String=record.type
	if kind=="bed": _bed(art,record,size);return
	var heading: float=deg_to_rad(float(record.get("use_facing",record.facing)))
	if kind not in ["chair","dining_seat","sofa"]:
		var toward := _v(record.interaction_point)-_v(record.position);toward.y=0
		if toward.length()>.02: heading=atan2(toward.x,toward.z)
	art.rotation.y=heading
	if absf(sin(heading))>.7: size=Vector3(size.z,size.y,size.x)
	match kind:
		"fridge": _fridge(art,size)
		"sink","washbasin": _sink(art,size,kind=="washbasin")
		"stove": _stove(art,size)
		"prep": _prep(art,size)
		"dining_table","desk": _table(art,size,record)
		"dining_seat","chair": _chair(art,size,float(record.get("seat_height",.45)),record.owner=="rin")
		"sofa": _sofa(art,size)
		"toilet": _toilet(art,size,float(record.get("seat_height",.43)))
		"bath": _bath(art,size)
		"shower": _shower(art,size)
		"washer": _washer(art,size)
		"storage","shoes": _storage(art,size,record)
		"drying_rack": _drying_rack(art,size)
		"changing_space": pass
		_: _slab(art,"Cabinet",Vector3(0,size.y*.5,0),size,.035,_wood("furniture"))

func _feet(parent: Node3D, size: Vector3, top: float, material: Material, inset: float = .07) -> void:
	for x in [-1,1]:
		for z in [-1,1]: _slab(parent,"Leg",Vector3(x*(size.x*.5-inset),top*.5,z*(size.z*.5-inset)),Vector3(.055,top,.055),.012,material)

func _cabinet(parent: Node3D, size: Vector3, material: Material) -> void:
	_slab(parent,"CabinetCase",Vector3(0,size.y*.5,-.010),Vector3(size.x-.008,size.y-.012,size.z-.036),.025,material)
	_box(parent,"Kickboard",Vector3(0,.045,size.z*.5-.018),Vector3(size.x-.07,.09,.022),_paint("shadow","55584e"))

func _pull(parent: Node3D, x: float, y: float, z: float, width: float = .12) -> void:
	var metal := _paint("brass","99805a",.48)
	_rod(parent,"Pull",Vector3(x-width*.5,y,z),Vector3(x+width*.5,y,z),.009,metal)

func _fridge(parent: Node3D, size: Vector3) -> void:
	var ivory := _paint("enamel","e5e4d4",.42)
	_slab(parent,"ApplianceBody",Vector3(0,size.y*.5,-.015),Vector3(size.x-.015,size.y,size.z-.07),.045,ivory)
	for section in [{"y":size.y*.77,"height":size.y*.42},{"y":size.y*.285,"height":size.y*.54}]:
		var door := _slab(parent,"FridgeDoor",Vector3(0,section.y,size.z*.5-.039),Vector3(size.x-.025,.028,section.height),.025,ivory)
		door.rotation.x=PI*.5
		_rod(parent,"FridgeHandle",Vector3(-size.x*.33,section.y-.09,size.z*.5-.014),Vector3(-size.x*.33,section.y+.09,size.z*.5-.014),.013,_paint("dark_metal","636962",.42))
	_box(parent,"DoorGasket",Vector3(0,size.y*.56,size.z*.5-.022),Vector3(size.x-.045,.013,.006),_paint("seal","8a8b7c"))
	_box(parent,"PinnedNote",Vector3(size.x*.13,size.y*.73,size.z*.5-.022),Vector3(.15,.19,.004),_paint("paper","f0e5cb"))
	_sphere(parent,"NoteMagnet",Vector3(size.x*.13,size.y*.79,size.z*.5-.012),Vector3(.025,.025,.012),_paint("terracotta","bd775d"))

func _tap(parent: Node3D, top: float, depth: float) -> void:
	var metal := _paint("steel","b4c3b9",.3)
	var z := -depth*.33
	_cylinder(parent,"TapFoot",Vector3(0,top+.012,z),.035,.025,metal)
	_rod(parent,"TapRiser",Vector3(0,top+.02,z),Vector3(0,top+.22,z),.021,metal)
	_rod(parent,"TapBend",Vector3(0,top+.22,z),Vector3(0,top+.245,z+.045),.021,metal)
	_rod(parent,"TapSpout",Vector3(0,top+.245,z+.045),Vector3(0,top+.245,z+.18),.021,metal)
	_rod(parent,"TapOutlet",Vector3(0,top+.245,z+.18),Vector3(0,top+.21,z+.18),.022,metal)
	_rod(parent,"TapLever",Vector3(.025,top+.12,z),Vector3(.10,top+.14,z),.012,metal)

func _sink(parent: Node3D, size: Vector3, vanity: bool) -> void:
	# The cabinet has real side/front panels rather than a solid box filling the
	# bowl cavity. The rim and sloping interior remain visible all the way down.
	var cabinet: Material=_paint("sage_cabinet","8fa89a") if vanity else _wood("kitchen_cabinet","c1a77f",false,true)
	_slab(parent,"CabinetBottom",Vector3(0,.05,0),Vector3(size.x,.10,size.z),.025,cabinet)
	for side in [-1,1]: _box(parent,"CabinetSide",Vector3(side*(size.x*.5-.018),size.y*.48,0),Vector3(.036,size.y*.94,size.z),cabinet)
	_box(parent,"CabinetBack",Vector3(0,size.y*.47,-size.z*.5+.012),Vector3(size.x,size.y*.92,.024),cabinet)
	_box(parent,"CabinetFront",Vector3(0,size.y*.46,size.z*.5-.025),Vector3(size.x-.05,size.y*.88,.025),cabinet)
	var surface: Material=_paint("porcelain","eeeade",.32) if vanity else _paint("steel","b4c3b9",.3)
	_recess(parent,"Basin",Vector3(0,size.y,0),Vector2(size.x,size.z),Vector2(size.x*.68,size.z*.57),Vector2(size.x*.47,size.z*.35),.14,surface)
	_cylinder(parent,"Drain",Vector3(0,size.y-.137,0),.022,.004,_paint("dark_metal","636962",.42))
	_tap(parent,size.y,size.z)
	_pull(parent,0,size.y*.72,size.z*.5-.010,size.x*.35)
	if vanity:
		var mirror := _node(parent,"Mirror",Vector3(0,size.y+.56,-size.z*.5+.015))
		_box(mirror,"MirrorFrame",Vector3.ZERO,Vector3(size.x*.90,.78,.03),_wood("trim","95704e"))
		_box(mirror,"MirrorSurface",Vector3(0,0,.017),Vector3(size.x*.82,.70,.004),_paint("mirror","abc5be",.24))
		_box(mirror,"ReflectedLight",Vector3(-size.x*.18,.04,.020),Vector3(.035,.61,.002),_paint("mirror_light","d6e3d3",.5))
		_cylinder(parent,"SoapBottle",Vector3(size.x*.35,size.y+.065,size.z*.23),.035,.13,_paint("soap_bottle","d1b68a",.45))
		_box(parent,"SoapPump",Vector3(size.x*.35,size.y+.14,size.z*.23),Vector3(.06,.022,.025),_paint("dark_metal","636962",.42))

func _stove(parent: Node3D, size: Vector3) -> void:
	_cabinet(parent,size,_paint("enamel","e5e4d4",.42))
	_box(parent,"Cooktop",Vector3(0,size.y-.005,0),Vector3(size.x-.025,.02,size.z-.025),_paint("stove_top","515c57",.45))
	for x in [-1,1]:
		_cylinder(parent,"Burner",Vector3(x*size.x*.24,size.y+.011,-size.z*.05),size.x*.125,.014,_paint("burner","343e3b",.55))
		for angle in [0.0,PI*.5]:
			var rest := _box(parent,"PanRest",Vector3(x*size.x*.24,size.y+.025,-size.z*.05),Vector3(size.x*.30,.014,.017),_paint("dark_metal","636962",.42));rest.rotation.y=angle
	_box(parent,"OvenWindow",Vector3(0,size.y*.43,size.z*.5-.009),Vector3(size.x*.73,size.y*.46,.016),_paint("oven_glass","3e4f4b",.4))
	_pull(parent,0,size.y*.72,size.z*.5-.010,size.x*.55)
	for x in [-.30,-.10,.10,.30]: _sphere(parent,"ControlDial",Vector3(size.x*x,size.y*.86,size.z*.5-.001),Vector3(.045,.045,.018),_paint("dark_metal","636962",.42))
	var pot := Vector3(-size.x*.24,size.y+.095,-size.z*.05)
	_cylinder(parent,"Saucepan",pot,.10,.13,_paint("clay_pot","b87558",.63))
	_cylinder(parent,"PotLid",pot+Vector3.UP*.071,.11,.018,_paint("clay_pot","b87558",.63))
	_sphere(parent,"LidGrip",pot+Vector3.UP*.095,Vector3(.035,.03,.035),_paint("dark_metal","636962",.42))
	_rod(parent,"PanHandle",pot+Vector3(.08,.015,0),pot+Vector3(.23,.015,0),.018,_wood("skirting","a47751"))

func _prep(parent: Node3D, size: Vector3) -> void:
	_cabinet(parent,size,_wood("kitchen_cabinet","c1a77f",false,true))
	_slab(parent,"Worktop",Vector3(0,size.y-.018,0),Vector3(size.x,.036,size.z),.025,_paint("countertop","dcd4ba",.72))
	_slab(parent,"CuttingBoard",Vector3(-size.x*.12,size.y+.012,0),Vector3(size.x*.48,.024,size.z*.55),.035,_wood("board","caa876"))
	_pull(parent,0,size.y*.75,size.z*.5-.010,size.x*.35)
	var jar := Vector3(size.x*.34,size.y+.07,-size.z*.25)
	_cylinder(parent,"UtensilCrock",jar,.058,.14,_paint("pottery","a6b5a1",.74))
	for index in 3:
		var x: float=(index-1)*.032
		_rod(parent,"WoodenUtensil",jar+Vector3(x,.03,0),jar+Vector3(x*1.3,.24,.01),.009,_wood("utensil","b18c5d"))
		_sphere(parent,"SpoonEnd",jar+Vector3(x*1.3,.24,.01),Vector3(.036,.066,.017),_wood("utensil","b18c5d"))

func _table(parent: Node3D, size: Vector3, record: Dictionary) -> void:
	var wood := _wood("furniture","b98759")
	_feet(parent,size,size.y-.06,wood)
	_slab(parent,"SolidTimberTop",Vector3(0,size.y-.03,0),Vector3(size.x,.06,size.z),.055,wood)
	for side in [-1,1]:
		_box(parent,"SideApron",Vector3(side*(size.x*.5-.06),size.y-.10,0),Vector3(.04,.12,size.z-.11),wood)
		_box(parent,"EndApron",Vector3(0,size.y-.10,side*(size.z*.5-.06)),Vector3(size.x-.11,.12,.04),wood)
	if record.type=="dining_table":
		_slab(parent,"TableRunner",Vector3(0,size.y+.003,0),Vector3(size.x*.25,.006,size.z*.92),.015,_cloth("runner","c4baa0",.55))
		_cylinder(parent,"CeramicVase",Vector3(0,size.y+.072,-size.z*.12),.045,.14,_paint("pottery","a6b5a1",.74),.028)
		for index in 3:
			var tip := Vector3((index-1)*.035,size.y+.31,-size.z*.12+.02*index)
			_rod(parent,"Stem",Vector3(0,size.y+.13,-size.z*.12),tip,.0025,_paint("stem","70846a"))
			_sphere(parent,"Leaf",tip,Vector3(.06,.025,.035),_paint("leaf","869b73"))
	elif record.id=="rin_desk":
		_asset(parent,"InitialTownModel",TOWN_MODEL,Vector3(size.x*.12,size.y+.005,-size.z*.08),.48)
		_slab(parent,"DrawingPaper",Vector3(-size.x*.28,size.y+.006,size.z*.13),Vector3(.28,.008,.20),.007,_paint("paper","f0e5cb"))
		for index in 4:
			var pencil := _cylinder(parent,"Crayon",Vector3(-size.x*.28+.032*index,size.y+.018,size.z*.28),.006,.09,_paint("crayon_%d"%index,["b96c56","6d9197","d2b264","819b72"][index]));pencil.rotation.z=PI*.5
		_desk_lamp(parent,Vector3(size.x*.36,size.y,-size.z*.25))
	else:
		var screen := _node(parent,"DesignWorkstation",Vector3(0,size.y,0))
		_box(screen,"ComputerFoot",Vector3(0,.012,-.10),Vector3(.22,.024,.13),_paint("dark_metal","636962",.42))
		_box(screen,"ComputerStand",Vector3(0,.13,-.13),Vector3(.04,.24,.035),_paint("dark_metal","636962",.42))
		_box(screen,"MonitorFrame",Vector3(0,.31,-.13),Vector3(.48,.29,.027),_paint("dark_metal","636962",.42))
		_box(screen,"BlankScreen",Vector3(0,.31,-.113),Vector3(.44,.25,.004),_paint("screen","809a96",.65))
		_box(screen,"DesignSheet",Vector3(-.055,.31,-.110),Vector3(.18,.19,.002),_paint("paper","f0e5cb"))
		_box(screen,"Keyboard",Vector3(0,.015,.15),Vector3(.36,.025,.11),_paint("keyboard","b7bcaa"))
		_asset(parent,"WorkMug",MUG,Vector3(-size.x*.35,size.y,-size.z*.04),.72)

func _desk_lamp(parent: Node3D, at: Vector3) -> void:
	var metal := _paint("lamp_enamel","879f91",.52)
	_cylinder(parent,"LampBase",at+Vector3.UP*.016,.065,.032,metal)
	_rod(parent,"LampStem",at+Vector3.UP*.03,at+Vector3(0,.32,-.015),.014,metal)
	_rod(parent,"LampNeck",at+Vector3(0,.32,-.015),at+Vector3(-.10,.34,.035),.014,metal)
	_cylinder(parent,"LampShade",at+Vector3(-.10,.30,.035),.075,.08,metal,.04)

func _chair(parent: Node3D, size: Vector3, seat_height: float, child: bool) -> void:
	var wood := _wood("furniture","b98759")
	_feet(parent,size,seat_height-.045,wood,.065)
	_slab(parent,"Seat",Vector3(0,seat_height-.046,0),Vector3(size.x,.044,size.z),.055,wood)
	_slab(parent,"SeatPad",Vector3(0,seat_height-.012,0),Vector3(size.x-.055,.024,size.z-.055),.055,_cloth("child_pad" if child else "seat_pad","c3a465" if child else "8ba295"))
	for side in [-1,1]: _rod(parent,"BackPost",Vector3(side*(size.x*.5-.04),seat_height,-size.z*.40),Vector3(side*(size.x*.5-.04),size.y-.05,-size.z*.40),.023,wood)
	_box(parent,"BackRail",Vector3(0,size.y-.10,-size.z*.40),Vector3(size.x,.13,.055),wood)
	if child: _box(parent,"ChildFootRest",Vector3(0,seat_height*.41,size.z*.29),Vector3(size.x-.08,.045,.08),wood)

func _bed(parent: Node3D, record: Dictionary, size: Vector3) -> void:
	var child: bool=record.owner=="rin"
	var wood := _wood("furniture","b98759")
	_feet(parent,size,.20,wood,.065)
	_slab(parent,"BedFrame",Vector3(0,.20,0),Vector3(size.x,.15,size.z),.045,wood)
	_slab(parent,"Mattress",Vector3(0,.335,0),Vector3(size.x-.055,.15,size.z-.055),.085,_cloth("mattress","eee6d4"))
	_slab(parent,"LinenSheet",Vector3(0,.416,0),Vector3(size.x-.065,.012,size.z-.065),.08,_cloth("sheet","e7ddc6"))
	_slab(parent,"Duvet",Vector3(0,.449,size.z*.13),Vector3(size.x-.07,.055,size.z*.66),.07,_cloth("rin_duvet" if child else "family_duvet","c5ac70" if child else "7f9f96",.35 if child else .10))
	_slab(parent,"TurnedCover",Vector3(0,.480,-size.z*.16),Vector3(size.x-.08,.012,.16),.035,_cloth("sheet","e7ddc6"))
	_sphere(parent,"Pillow",Vector3(0,.458,-size.z*.32),Vector3(size.x*.74,.083,.38),_cloth("pillow","eee5d0"))
	_box(parent,"LowHeadboard",Vector3(0,.36,-size.z*.5+.026),Vector3(size.x,.27,.052),wood)

func _sofa(parent: Node3D, size: Vector3) -> void:
	var cloth := _cloth("sofa","9aa994")
	_feet(parent,size,.12,_wood("trim","95704e"),.12)
	_slab(parent,"SofaBase",Vector3(0,.25,0),Vector3(size.x,.30,size.z),.08,cloth)
	for index in 3:
		var x: float=(index-1)*size.x*.30
		_slab(parent,"SeatCushion",Vector3(x,.38,size.z*.06),Vector3(size.x*.29,.10,size.z*.72),.07,cloth)
		var cushion := _slab(parent,"BackCushion",Vector3(x,.65,-size.z*.32),Vector3(size.x*.29,.17,.36),.08,cloth);cushion.rotation.x=PI*.40
	for sign in [-1,1]: _slab(parent,"SofaArm",Vector3(sign*(size.x*.5-.075),.48,0),Vector3(.15,.31,size.z),.065,cloth)
	var pillow := _sphere(parent,"LooseCushion",Vector3(size.x*.31,.59,-size.z*.04),Vector3(.36,.30,.12),_cloth("cushion","bd8d6b",.35));pillow.rotation.z=-.18

func _toilet(parent: Node3D, size: Vector3, seat_height: float) -> void:
	var ceramic := _paint("porcelain","eeeade",.32)
	var rim: float=seat_height-.022
	_slab(parent,"Foot",Vector3(0,.07,.015),Vector3(size.x*.54,.14,size.z*.62),.09,ceramic)
	_sphere(parent,"Pedestal",Vector3(0,.13,.02),Vector3(size.x*.56,.18,size.z*.52),ceramic)
	_recess(parent,"OpenBowl",Vector3(0,rim,.025),Vector2(size.x*.82,size.z*.78),Vector2(size.x*.56,size.z*.55),Vector2(size.x*.34,size.z*.33),.18,ceramic)
	_outer_bowl(parent,Vector3(0,rim,.025),Vector2(size.x*.82,size.z*.78),Vector2(size.x*.43,size.z*.46),.215,ceramic)
	_recess(parent,"SeatRing",Vector3(0,seat_height,.025),Vector2(size.x*.83,size.z*.79),Vector2(size.x*.58,size.z*.57),Vector2(size.x*.58,size.z*.57),.018,_paint("toilet_seat","dddcc8",.5),false)
	_cylinder(parent,"BowlDrain",Vector3(0,rim-.176,.025),.035,.004,_paint("drain_shadow","83918a",.65))
	_slab(parent,"Cistern",Vector3(0,.57,-size.z*.34),Vector3(size.x*.70,.39,size.z*.26),.035,ceramic)
	_cylinder(parent,"FlushButton",Vector3(size.x*.13,.771,-size.z*.34),.023,.008,_paint("steel","b4c3b9",.3))
	_box(parent,"ClosedLidBehindSeat",Vector3(0,.60,-size.z*.20),Vector3(size.x*.61,.31,.028),_paint("toilet_seat","dddcc8",.5))

func _bath(parent: Node3D, size: Vector3) -> void:
	var ceramic := _paint("porcelain","eeeade",.32)
	var apron := _paint("bath_apron","d9dbcb",.52)
	_slab(parent,"TubBase",Vector3(0,.05,0),Vector3(size.x,.10,size.z),.06,apron)
	for side in [-1,1]:
		_box(parent,"TubLongSide",Vector3(0,size.y*.48,side*(size.z*.5-.03)),Vector3(size.x,size.y*.94,.06),apron)
		_box(parent,"TubEnd",Vector3(side*(size.x*.5-.03),size.y*.48,0),Vector3(.06,size.y*.94,size.z),apron)
	_recess(parent,"OpenTub",Vector3(0,size.y,0),Vector2(size.x,size.z),Vector2(size.x-.17,size.z-.16),Vector2(size.x-.30,size.z-.26),size.y*.65,ceramic)
	# A static pale inner surface reads depth. Actual water/resource state stays
	# in the household model; no decorative surface asserts a filled bath.
	_slab(parent,"DryTubFloor",Vector3(0,size.y*.34+.004,0),Vector3(size.x-.31,.009,size.z-.27),.06,_paint("tub_interior","d3e0d5",.48))
	_rod(parent,"BathHandhold",Vector3(-size.x*.27,size.y+.012,-size.z*.41),Vector3(size.x*.27,size.y+.012,-size.z*.41),.012,_paint("steel","b4c3b9",.3))

func _shower(parent: Node3D, size: Vector3) -> void:
	var metal := _paint("steel","b4c3b9",.3)
	_rod(parent,"ShowerRail",Vector3(0,.08,-size.z*.29),Vector3(0,size.y-.12,-size.z*.29),.013,metal)
	_rod(parent,"ShowerArm",Vector3(0,size.y-.22,-size.z*.29),Vector3(0,size.y-.13,0),.012,metal)
	var head := _cylinder(parent,"ShowerHead",Vector3(0,size.y-.16,0),.058,.018,metal);head.rotation.x=.45
	_box(parent,"Mixer",Vector3(0,.25,size.z*.20),Vector3(size.x*.9,.055,.05),metal)
	for sign in [-1,1]: _sphere(parent,"MixerDial",Vector3(sign*size.x*.36,.25,size.z*.36),Vector3(.028,.04,.025),_paint("enamel","e5e4d4",.42))

func _washer(parent: Node3D, size: Vector3) -> void:
	_slab(parent,"ApplianceBody",Vector3(0,size.y*.5,0),size,.035,_paint("enamel","e5e4d4",.42))
	_box(parent,"Controls",Vector3(0,size.y*.85,size.z*.5+.001),Vector3(size.x*.86,size.y*.16,.004),_paint("washer_controls","ccd4c5",.55))
	var drum := _cylinder(parent,"DrumRim",Vector3(0,size.y*.45,size.z*.5-.015),size.x*.31,.025,_paint("steel","b4c3b9",.3));drum.rotation.x=PI*.5
	var glass := _cylinder(parent,"DrumGlass",Vector3(0,size.y*.45,size.z*.5+.001),size.x*.245,.009,_paint("drum_glass","647a75",.35));glass.rotation.x=PI*.5
	var dial := _cylinder(parent,"ProgramDial",Vector3(size.x*.27,size.y*.85,size.z*.5+.006),.034,.018,_paint("dark_metal","636962",.42));dial.rotation.x=PI*.5
	_box(parent,"ProgramScreen",Vector3(-size.x*.16,size.y*.85,size.z*.5+.004),Vector3(.15,.04,.004),_paint("screen","809a96",.65))
	_slab(parent,"FoldedTowel",Vector3(0,size.y+.032,-size.z*.08),Vector3(size.x*.68,.064,size.z*.58),.025,_cloth("towel","d5c9a9",.35))

func _storage(parent: Node3D, size: Vector3, record: Dictionary) -> void:
	var wood := _wood("storage","b5936a",false,true)
	var open_shelf: bool=record.id in ["rin_storage","linen_storage"]
	if open_shelf:
		_box(parent,"ShelfBack",Vector3(0,size.y*.5,-size.z*.5+.015),Vector3(size.x,size.y,.03),_paint("shelf_back","a78e66"))
		for side in [-1,1]:
			_box(parent,"ShelfSide",Vector3(side*(size.x*.5-.018),size.y*.5,0),Vector3(.036,size.y,size.z),wood)
			_box(parent,"ShelfCap",Vector3(0,size.y*.5+side*(size.y*.5-.018),0),Vector3(size.x,.036,size.z),wood)
		var shelf_count: int=3 if size.y<1.6 else 4
		for level in range(shelf_count):
			var y: float=.18+float(level)*(size.y-.27)/shelf_count
			_box(parent,"Shelf",Vector3(0,y,0),Vector3(size.x-.07,.035,size.z-.04),wood)
			if record.id=="rin_storage":
				for book in range(5 if level!=1 else 3):
					var x: float=-size.x*.31+float(book)*.12
					_box(parent,"Book",Vector3(x,y+.13,size.z*.37),Vector3(.07,.23+book*.01,.13),_paint("book_%d"%book,["9e8e65","6f9395","c3aa79","b47c63","8a9c77"][book]))
			else:
				for towel in 2: _slab(parent,"FoldedLinen",Vector3((towel-.5)*size.x*.40,y+.055,size.z*.29),Vector3(size.x*.32,.075,size.z*.32),.018,_cloth("linen_%d"%towel,"d6c6a4" if towel==0 else "9fac96",.2))
	else:
		_cabinet(parent,size,wood)
		for side in [-1,1]:
			_box(parent,"CupboardDoor",Vector3(side*size.x*.247,size.y*.53,size.z*.5-.025),Vector3(size.x*.48,size.y*.85,.018),wood)
			_pull(parent,side*size.x*.075,size.y*.55,size.z*.5-.010,minf(size.x*.12,.12))
	if record.type=="shoes":
		_slab(parent,"ShoeCabinetTop",Vector3(0,size.y-.016,0),Vector3(size.x,.032,size.z),.02,_wood("furniture","b98759"))
		_cylinder(parent,"KeyDish",Vector3(0,size.y+.012,0),minf(size.x,size.z)*.25,.022,_paint("pottery","a6b5a1",.74))

func _drying_rack(parent: Node3D, size: Vector3) -> void:
	var metal := _paint("rack","b0b9ab",.55)
	for side in [-1,1]:
		_rod(parent,"Post",Vector3(side*size.x*.46,.035,0),Vector3(side*size.x*.46,size.y-.04,0),.023,metal)
		_rod(parent,"Foot",Vector3(side*size.x*.46,.028,-size.z*.46),Vector3(side*size.x*.46,.028,size.z*.46),.022,metal)
	_rod(parent,"Rail",Vector3(-size.x*.48,size.y-.05,0),Vector3(size.x*.48,size.y-.05,0),.019,metal)

func _pendant(parent: Node3D, at: Vector3) -> void:
	var lamp := _node(parent,"DiningPendant",at)
	_cylinder(lamp,"Shade",Vector3.ZERO,.21,.18,_paint("lamp_enamel","879f91",.52),.09)
	_rod(lamp,"Cord",Vector3(0,.09,0),Vector3(0,.39,0),.008,_paint("cord","5b6257"))
	_cylinder(lamp,"WarmDiffuser",Vector3(0,-.09,0),.18,.008,_paint("lamp_linen","efe3bc",.72))

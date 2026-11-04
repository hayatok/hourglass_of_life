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
	architecture.set_meta("version",2)
	for assembly: Node3D in house.wall_roots.values():_clear_art(assembly)
	for child in house.get_children():
		if child is Label3D: child.visible=false
		if child is MeshInstance3D and str(child.name).begins_with("Floor_"):
			var id: String=str(child.name).trim_prefix("Floor_")
			if id in ["bathroom","washroom","toilet"]: child.material_override=_tiles("wet_floor","c4d1bf",.22)
			elif id=="entrance": child.material_override=_tiles("entry_floor","b5b3a1",.33)
			elif id=="outside": child.material_override=_tiles("patio_floor","b9b8a3",.42)
			elif house.definition.get("external_zones",[]).any(func(zone):return zone.id==id):child.material_override=_tiles("courtyard_stone","c6bda7",.30)
			else: child.material_override=_wood("floor","bda174",true)
	for wall: Node3D in house.wall_nodes: _wall_details(wall,house.definition.house)
	for record in house.definition.doors: _door_details(house,record)
	for id in house.fixtures:
		var fixture: Dictionary=house.fixtures[id]
		_clear_art(fixture.node);_hide_prototype(fixture.node)
		var art := _node(fixture.node,"Art");art.set_meta("home_art",true)
		art.set_meta("fixture_id",id);art.set_meta("logical_inventory",false)
		_fixture(art,fixture.definition)
	_windows(house)
	_initial_wall_art(house)
	for light in house.definition.get("ceiling_lights",[]):
		if light.get("kind","")=="pendant":_pendant(architecture,_v(light.at))
	_roof_details(house)
	_foundation_details(house)

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
	if high>=float(wall.get_meta("wall_height",house.get("wall_height",2.65)))-.01:
		_box(art,"Cornice",Vector3(0,size.y*.5-.045,0),Vector3(size.x+.004,.09,size.z+.004),_wood("trim","95704e"))

func _door_details(house: LivingHouse, record: Dictionary) -> void:
	var frame := _node(house.wall_roots[record.wall],"Frame_"+str(record.id),_v(record.center))
	frame.set_meta("home_art",true);frame.set_meta("wall_id",record.wall)
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

func _windows(house: LivingHouse) -> void:
	for entry: Dictionary in house.windows.values():
		var record: Dictionary=entry.definition
		var frame: Node3D=entry.node
		_clear_art(frame)
		for part: MeshInstance3D in entry.frame_pieces:part.material_override=_wood("window_frame","d5c2a0")
		var frosted: bool=bool(record.frosted)
		var glass := _paint("frosted_glass" if frosted else "clear_glass","bfcec6" if frosted else "b6d0ce",.80 if frosted else .18)
		glass.cull_mode=BaseMaterial3D.CULL_DISABLED
		if not frosted:
			glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;glass.albedo_color.a=.24
		entry.glass.material_override=glass
		var art := _node(frame,"WindowFinish");art.set_meta("home_art",true);art.set_meta("wall_id",record.wall)
		var width: float=float(record.width);var height: float=float(record.height)
		var inside: float=float(house.definition.house.wall_thickness)*.5
		_box(art,"InnerSill",Vector3(0,-height*.5,inside+.035),Vector3(width+.10,.045,.14),_wood("window_sill","bf9b70"))
		for side in [-1,1]:
			_box(art,"InnerCasing",Vector3(side*(width*.5+.018),0,inside+.012),Vector3(.045,height+.08,.024),_wood("window_frame","d5c2a0"))
		if not frosted:
			for side in [-1,1]:
				_box(art,"LinenCurtain",Vector3(side*(width*.5-.035),0,inside+.046),Vector3(.11,height-.04,.018),_cloth("curtain","eee3cd",.3))

func _initial_wall_art(house: LivingHouse) -> void:
	# Initial, authored possessions communicate interests. They are deliberately
	# named as initial still life, never recorded as a new work/history event.
	for picture in house.definition.get("initial_wall_art",[]):
		if not house.wall_roots.has(picture.wall):continue
		var wall: Node3D=house.wall_roots[picture.wall]
		var inward := _v(picture.inward)
		var at: Vector3=_v(picture.center)+inward*(float(house.definition.house.wall_thickness)*.5+.002)
		var root := _node(wall,picture.id,at)
		root.rotation.y=atan2(inward.x,inward.z)
		root.set_meta("home_art",true);root.set_meta("authored_decoration",true)
		root.set_meta("wall_id",picture.wall);root.set_meta("owner",picture.get("owner",""))
		var size := Vector2(picture.size[0],picture.size[1])
		_box(root,"TimberFrame",Vector3.ZERO,Vector3(size.x,size.y,.012),_wood("trim","95704e"))
		_box(root,"Paper",Vector3(0,0,.008),Vector3(size.x-.035,size.y-.035,.003),_paint("paper","f0e5cb"))
		if picture.get("kind","")=="child_house":
			_box(root,"DrawnHouse",Vector3(-.09,-.045,.011),Vector3(.16,.13,.002),_paint("drawing_sand","c8a56b"))
			var roof := SurfaceTool.new();roof.begin(Mesh.PRIMITIVE_TRIANGLES)
			_triangle(roof,Vector3(-.19,.02,.013),Vector3(-.09,.12,.013),Vector3(.01,.02,.013),Vector3.BACK)
			_mesh(root,"DrawnRoof",roof.commit(),Vector3.ZERO,_paint("drawing_red","bd775d"))
			_box(root,"DrawnDoor",Vector3(-.10,-.078,.013),Vector3(.031,.065,.002),_paint("drawing_blue","729394"))
			_box(root,"DrawnTreeTrunk",Vector3(.13,-.065,.012),Vector3(.018,.10,.002),_paint("drawing_trunk","a6885d"))
			_sphere(root,"DrawnTreeCrown",Vector3(.13,.015,.014),Vector3(.12,.14,.003),_paint("drawing_green","8b9d70"))
			_sphere(root,"DrawnSun",Vector3(.21,.125,.014),Vector3(.055,.055,.003),_paint("drawing_sun","d4b46c"))
		elif picture.get("kind","")=="design_study":
			for index in 3:
				_box(root,"DesignSwatch",Vector3((index-1)*.15,.025,.012),Vector3(.12,.18,.002),_paint("swatch_%d"%index,["7f9f96","c49a6e","b8bca0"][index]))
			_box(root,"DesignRule",Vector3(0,-.115,.012),Vector3(.39,.012,.002),_paint("drawing_blue","729394"))

func _fixture(art: Node3D, record: Dictionary) -> void:
	var size := _v(record.size)
	var kind: String=record.type
	if kind=="bed": _bed(art,record,size);return
	var heading: float=LivingHouse.fixture_basis(record).get_euler().y
	art.rotation.y=heading
	if absf(sin(heading))>.7: size=Vector3(size.z,size.y,size.x)
	match kind:
		"fridge": _fridge(art,size)
		"sink","washbasin": _sink(art,size,kind=="washbasin")
		"stove": _stove(art,size)
		"prep":
			if record.get("desk_content","")=="sewing_pattern":_table(art,size,record)
			else:_prep(art,size)
		"dining_table","desk": _table(art,size,record)
		"dining_seat","chair": _chair(art,size,float(record.get("seat_height",.45)),bool(record.get("child_foot_support_required",false)) or float(record.get("seat_height",.45))<.4)
		"sofa": _sofa(art,size)
		"toilet": _toilet(art,size,float(record.get("seat_height",.43)))
		"bath": _bath(art,size)
		"shower": _shower(art,size)
		"washer": _washer(art,size)
		"storage","shoes": _storage(art,size,record)
		"drying_rack": _drying_rack(art,size)
		"towel_basket": _towel_basket(art,size)
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
	var jar := Vector3(-size.x*.42,size.y+.07,-size.z*.35)
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
		var centerpiece := _node(parent,"Centerpiece",_v(record.get("centerpiece_offset",[0,0,-size.z*.12])))
		_cylinder(centerpiece,"CeramicVase",Vector3(0,size.y+.072,0),.045,.14,_paint("pottery","a6b5a1",.74),.028)
		for index in 3:
			var tip := Vector3((index-1)*.035,size.y+.31,.02*index)
			_rod(centerpiece,"Stem",Vector3(0,size.y+.13,0),tip,.0025,_paint("stem","70846a"))
			_sphere(centerpiece,"Leaf",tip,Vector3(.06,.025,.035),_paint("leaf","869b73"))
		return
	var content: String=str(record.get("desk_content",""))
	parent.set_meta("desk_content",content)
	if content=="drawing":
		if record.get("initial_model","")=="town_model_base":
			_asset(parent,"InitialTownModel",TOWN_MODEL,Vector3(size.x*.12,size.y+.005,-size.z*.08),.48)
		_slab(parent,"DrawingPaper",Vector3(-size.x*.28,size.y+.006,size.z*.13),Vector3(.28,.008,.20),.007,_paint("paper","f0e5cb"))
		for index in 4:
			var pencil := _cylinder(parent,"Crayon",Vector3(-size.x*.28+.032*index,size.y+.018,size.z*.28),.006,.09,_paint("crayon_%d"%index,["b96c56","6d9197","d2b264","819b72"][index]));pencil.rotation.z=PI*.5
		_desk_lamp(parent,Vector3(size.x*.36,size.y,-size.z*.25))
	elif content=="computer":
		var screen := _node(parent,"ComputerWorkstation",Vector3(0,size.y,0))
		_box(screen,"ComputerFoot",Vector3(0,.012,-.10),Vector3(.22,.024,.13),_paint("dark_metal","636962",.42))
		_box(screen,"ComputerStand",Vector3(0,.13,-.13),Vector3(.04,.24,.035),_paint("dark_metal","636962",.42))
		_box(screen,"MonitorFrame",Vector3(0,.31,-.13),Vector3(.48,.29,.027),_paint("dark_metal","636962",.42))
		_box(screen,"BlankScreen",Vector3(0,.31,-.113),Vector3(.44,.25,.004),_paint("screen","809a96",.65))
		if record.get("screen_content","")=="design":_box(screen,"DesignSheet",Vector3(-.055,.31,-.110),Vector3(.18,.19,.002),_paint("paper","f0e5cb"))
		_box(screen,"Keyboard",Vector3(0,.015,.15),Vector3(.36,.025,.11),_paint("keyboard","b7bcaa"))
		_asset(parent,"WorkMug",MUG,Vector3(-size.x*.35,size.y,-size.z*.04),.72)
	elif content=="tools":
		_box(parent,"RepairMat",Vector3(0,size.y+.004,0),Vector3(size.x*.65,.008,size.z*.68),_paint("work_mat","7e9686"))
		for index in 2:
			var at := Vector3((index-.5)*.21,size.y+.018,.045)
			_rod(parent,"ScrewdriverShaft",at,at+Vector3(.12,0,-.10),.008,_paint("tool_metal","a2aca5",.32))
			_rod(parent,"ScrewdriverGrip",at-Vector3(.065,0,-.055),at,.018,_paint("tool_grip","a17b5b"))
		_cylinder(parent,"PartsDish",Vector3(size.x*.28,size.y+.025,-size.z*.20),.065,.035,_paint("tool_metal","a2aca5",.32))
	elif content=="sewing":_sewing_machine(parent,size)
	elif content=="keyboard":_keyboard_instrument(parent,size)
	elif content in ["writing","music","sewing_pattern"]:
		var sheet := Vector3(minf(size.x*.68,.72),.007,minf(size.z*.70,.42))
		_slab(parent,"PatternPaper" if content=="sewing_pattern" else "WorkPaper",Vector3(0,size.y+.005,0),sheet,.008,_paint("paper","f0e5cb"))
		if content=="music":
			for row in 5:_box(parent,"MusicStaff",Vector3(0,size.y+.009,(row-2)*.017),Vector3(sheet.x*.83,.0015,.0018),_paint("ink","65746b"))
		elif content=="sewing_pattern":
			_box(parent,"PatternOutline",Vector3(0,size.y+.01,0),Vector3(sheet.x*.7,.002,.005),_paint("ink","65746b"))
			_box(parent,"ClothRuler",Vector3(0,size.y+.015,-size.z*.25),Vector3(minf(.6,size.x*.7),.012,.03),_wood("ruler","cbb281"))
		else:
			var pencil := _cylinder(parent,"Pencil",Vector3(.12,size.y+.017,size.z*.28),.006,.15,_paint("pencil","b18c5d"));pencil.rotation.z=PI*.5

func _sewing_machine(parent: Node3D, size: Vector3) -> void:
	# An authored machine, not a sewn item or a completed household outcome.
	var at := Vector3(0,size.y,0)
	var enamel := _paint("sewing_enamel","c8d3c7",.5)
	_slab(parent,"MachineBase",at+Vector3(0,.035,0),Vector3(.50,.07,.28),.035,enamel)
	_slab(parent,"MachinePillar",at+Vector3(.17,.19,-.01),Vector3(.12,.32,.23),.025,enamel)
	_slab(parent,"MachineArm",at+Vector3(.005,.33,-.01),Vector3(.43,.095,.20),.035,enamel)
	_box(parent,"NeedleHousing",at+Vector3(-.17,.25,-.01),Vector3(.072,.16,.095),enamel)
	_rod(parent,"Needle",at+Vector3(-.17,.09,.005),at+Vector3(-.17,.18,.005),.003,_paint("needle","aeb6ae",.25))
	_box(parent,"NeedlePlate",at+Vector3(-.13,.073,.005),Vector3(.19,.006,.16),_paint("tool_metal","a2aca5",.32))
	_cylinder(parent,"ThreadSpool",at+Vector3(.075,.415,-.01),.024,.07,_cloth("thread","c49d7e"))
	var wheel := _cylinder(parent,"Handwheel",at+Vector3(.24,.28,-.01),.062,.025,_paint("tool_metal","a2aca5",.32));wheel.rotation.z=PI*.5

func _keyboard_instrument(parent: Node3D, size: Vector3) -> void:
	var width: float=minf(size.x*.83,1.1)
	_box(parent,"KeyboardCase",Vector3(0,size.y+.035,0),Vector3(width,.07,.28),_paint("instrument","636e67"))
	for index in 21:
		var x: float=(float(index)/20-.5)*(width-.08)
		_box(parent,"IvoryKey",Vector3(x,size.y+.077,.04),Vector3((width-.08)/21*.92,.015,.17),_paint("ivory","e7e3d4"))
		if index%7 not in [2,6]:_box(parent,"BlackKey",Vector3(x+.015,size.y+.096,-.015),Vector3((width-.08)/21*.54,.022,.10),_paint("key_black","3f4843"))

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
	var bedding: String=str(record.get("bedding_color","7f9f96"))
	var wood := _wood("furniture","b98759")
	_feet(parent,size,.20,wood,.065)
	_slab(parent,"BedFrame",Vector3(0,.20,0),Vector3(size.x,.15,size.z),.045,wood)
	_slab(parent,"Mattress",Vector3(0,.335,0),Vector3(size.x-.055,.15,size.z-.055),.085,_cloth("mattress","eee6d4"))
	_slab(parent,"LinenSheet",Vector3(0,.416,0),Vector3(size.x-.065,.012,size.z-.065),.08,_cloth("sheet","e7ddc6"))
	_slab(parent,"Duvet",Vector3(0,.449,size.z*.13),Vector3(size.x-.07,.055,size.z*.66),.07,_cloth("duvet_"+bedding,bedding,float(record.get("bedding_stripes",.10))))
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
	var contents: String=str(record.get("display_contents",""))
	parent.set_meta("display_contents",contents)
	var open_shelf: bool=contents in ["books","linen","tools"]
	if open_shelf:
		_box(parent,"ShelfBack",Vector3(0,size.y*.5,-size.z*.5+.015),Vector3(size.x,size.y,.03),_paint("shelf_back","a78e66"))
		for side in [-1,1]:
			_box(parent,"ShelfSide",Vector3(side*(size.x*.5-.018),size.y*.5,0),Vector3(.036,size.y,size.z),wood)
			_box(parent,"ShelfCap",Vector3(0,size.y*.5+side*(size.y*.5-.018),0),Vector3(size.x,.036,size.z),wood)
		var shelf_count: int=3 if size.y<1.6 else 4
		for level in range(shelf_count):
			var y: float=.18+float(level)*(size.y-.27)/shelf_count
			_box(parent,"Shelf",Vector3(0,y,0),Vector3(size.x-.07,.035,size.z-.04),wood)
			if contents=="books":
				for book in range(5 if level!=1 else 3):
					var x: float=-size.x*.31+float(book)*.12
					_box(parent,"Book",Vector3(x,y+.13,size.z*.37),Vector3(.07,.23+book*.01,.13),_paint("book_%d"%book,["9e8e65","6f9395","c3aa79","b47c63","8a9c77"][book]))
			elif contents=="linen":
				for towel in 2: _slab(parent,"FoldedLinen",Vector3((towel-.5)*size.x*.40,y+.055,size.z*.29),Vector3(size.x*.32,.075,size.z*.32),.018,_cloth("linen_%d"%towel,"d6c6a4" if towel==0 else "9fac96",.2))
			elif contents=="tools":
				_box(parent,"ToolTray",Vector3(0,y+.035,0),Vector3(size.x*.72,.07,size.z*.63),_paint("tool_tray","87968b"))
				for tool in 3:
					var x: float=(tool-1)*size.x*.2
					_rod(parent,"ToolHandle",Vector3(x,y+.07,-size.z*.12),Vector3(x,y+.12,size.z*.17),.014,_wood("tool_handle","b18c5d"))
	else:
		_cabinet(parent,size,wood)
		for side in [-1,1]:
			_box(parent,"CupboardDoor",Vector3(side*size.x*.247,size.y*.53,size.z*.5-.025),Vector3(size.x*.48,size.y*.85,.018),wood)
			_pull(parent,side*size.x*.075,size.y*.55,size.z*.5-.010,minf(size.x*.12,.12))
	if record.type=="shoes":
		_slab(parent,"ShoeCabinetTop",Vector3(0,size.y-.016,0),Vector3(size.x,.032,size.z),.02,_wood("furniture","b98759"))
		_cylinder(parent,"KeyDish",Vector3(0,size.y+.012,0),minf(size.x,size.z)*.25,.022,_paint("pottery","a6b5a1",.74))

func _towel_basket(parent: Node3D, size: Vector3) -> void:
	var wicker := _wood("basket","b99b6e")
	_slab(parent,"BasketBottom",Vector3(0,.04,0),Vector3(size.x,.04,size.z),.025,wicker)
	for side in [-1,1]:
		for index in 5:
			var offset: float=(float(index)/4-.5)*.85
			_rod(parent,"WickerUpright",Vector3(side*size.x*.47,.055,offset*size.z),Vector3(side*size.x*.47,size.y,offset*size.z),.009,wicker)
			_rod(parent,"WickerUpright",Vector3(offset*size.x,.055,side*size.z*.47),Vector3(offset*size.x,size.y,side*size.z*.47),.009,wicker)
		for level in 6:
			var y: float=.08+float(level)*(size.y-.08)/5
			_rod(parent,"WickerWeave",Vector3(-size.x*.47,y,side*size.z*.47),Vector3(size.x*.47,y,side*size.z*.47),.008,wicker)
			_rod(parent,"WickerWeave",Vector3(side*size.x*.47,y,-size.z*.47),Vector3(side*size.x*.47,y,size.z*.47),.008,wicker)

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

func _roof_details(house: LivingHouse) -> void:
	if not is_instance_valid(house.roof_root):return
	for entry: Dictionary in house.roof_volumes.values():_roof_finish(house,entry)

func _roof_finish(house: LivingHouse, entry: Dictionary) -> void:
	var parent: Node3D=entry.node
	_clear_art(parent)
	var art := _node(parent,"RoofFinish");art.set_meta("home_art",true)
	var spec: Dictionary=entry.spec
	var roof: Dictionary=spec.roof
	var bounds: Array=spec.bounds
	var low := Vector2(bounds[0],bounds[1]);var high := low+Vector2(bounds[2],bounds[3])
	var height: float=float(spec.height)
	var rise: float=float(roof.rise);var eaves: float=float(roof.get("eaves",.35))
	var along_x: bool=roof.get("ridge_axis","x")=="x"
	var middle: float=(low.y+high.y)*.5 if along_x else (low.x+high.x)*.5
	var half: float=float(bounds[3] if along_x else bounds[2])*.5
	var eave_y: float=height-rise*eaves/half
	var base := Color(roof.get("color","7c8276"))
	var seams := _paint("roof_seams_"+base.to_html(false),base.darkened(.16).to_html(false),.87)
	var ridge := _paint("roof_ridge_"+base.to_html(false),base.lightened(.08).to_html(false),.87)
	var first := Vector3(low.x-eaves,height+rise+.035,middle) if along_x else Vector3(middle,height+rise+.035,low.y-eaves)
	var last := Vector3(high.x+eaves,height+rise+.035,middle) if along_x else Vector3(middle,height+rise+.035,high.y+eaves)
	for part in house.roof_edge_parts(spec,first,last):_rod(art,"RidgeCap",part[0],part[1],.055,ridge)
	if roof.get("style","")=="shingle":
		_shingle_roof(house,art,spec)
		return
	for side in [-1,1]:
		var edge: float=middle+side*(half+eaves)
		for row in range(7):
			var t: float=float(row)/7
			var across: float=lerpf(edge,middle,t)
			var y: float=lerpf(eave_y,height+rise,t)+.012
			var a := Vector3(low.x-eaves,y,across) if along_x else Vector3(across,y,low.y-eaves)
			var b := Vector3(high.x+eaves,y,across) if along_x else Vector3(across,y,high.y+eaves)
			_rod(art,"TileCourse",a,b,.009,seams)

func _shingle_roof(house: LivingHouse, parent: Node3D, spec: Dictionary) -> void:
	var roof: Dictionary=spec.roof;var b: Array=spec.bounds
	var along_x: bool=roof.get("ridge_axis","x")=="x"
	var low: float=float(b[0] if along_x else b[1])-float(roof.eaves)
	var high: float=float(b[0]+b[2] if along_x else b[1]+b[3])+float(roof.eaves)
	var middle: float=float(b[1]+b[3]*.5 if along_x else b[0]+b[2]*.5)
	var half: float=float(b[3] if along_x else b[2])*.5
	var extent: float=half+float(roof.eaves)
	var rise: float=float(roof.rise)
	var rows: int=ceili(sqrt(extent*extent+pow(rise*extent/half,2))/.32)
	var columns: int=ceili((high-low)/.31)
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(roof.color)
	for side in [-1,1]:
		var normal := Vector3(0,half,side*rise).normalized() if along_x else Vector3(side*rise,half,0).normalized()
		for row in rows:
			var near: float=middle+side*extent*(1-float(row)/rows)
			var far: float=middle+side*maxf(0,extent*(1-float(row+1)/rows)-.035)
			for column in range(-1,columns+1):
				var stagger: float=.5 if row%2 else 0.0
				var left: float=maxf(low,low+(column+stagger)*(high-low)/columns+.003)
				var right: float=minf(high,low+(column+stagger+1)*(high-low)/columns-.003)
				if right-left<.015:continue
				var pa := Vector2(left,near) if along_x else Vector2(near,left)
				var pb := Vector2(right,near) if along_x else Vector2(near,right)
				var pc := Vector2(right,far) if along_x else Vector2(far,right)
				var pd := Vector2(left,far) if along_x else Vector2(far,left)
				var a := Vector3(pa.x,house.roof_height_at(spec,pa)+.022,pa.y)
				var b3 := Vector3(pb.x,house.roof_height_at(spec,pb)+.022,pb.y)
				var c := Vector3(pc.x,house.roof_height_at(spec,pc)+.007,pc.y)
				var d := Vector3(pd.x,house.roof_height_at(spec,pd)+.007,pd.y)
				var shade: float=float(posmod(column*3+row*5,7)-3)*.012
				surface.set_color(base.lightened(shade) if shade>=0 else base.darkened(-shade))
				_roof_polygon(surface,house,spec,[a,b3,c,d],normal)
				var front := Vector3(0,0,side) if along_x else Vector3(side,0,0)
				_roof_polygon(surface,house,spec,[a-Vector3.UP*.017,b3-Vector3.UP*.017,b3,a],front)
	var material := _paint("shingle_vertex","ffffff",.92);material.vertex_color_use_as_albedo=true
	_mesh(parent,"IndividualShingles",surface.commit(),Vector3.ZERO,material)
	var timber := _wood("roof_fascia","81664d")
	for side in [-1,1]:
		var edge: float=middle+side*extent
		var at := Vector2((low+high)*.5,edge) if along_x else Vector2(edge,(low+high)*.5)
		var fa := Vector3(low,house.roof_height_at(spec,at)-.055,edge) if along_x else Vector3(edge,house.roof_height_at(spec,at)-.055,low)
		var fb := Vector3(high,fa.y,edge) if along_x else Vector3(edge,fa.y,high)
		for part in house.roof_edge_parts(spec,fa,fb):
			var length: float=part[0].distance_to(part[1])
			_box(parent,"EavesFascia",(part[0]+part[1])*.5,Vector3(length,.13,.065) if along_x else Vector3(.065,.13,length),timber)
		for index in range(ceili((high-low)/.85)+1):
			var along: float=lerpf(low+.08,high-.08,float(index)/maxi(1,ceili((high-low)/.85)))
			var outer := Vector2(along,edge) if along_x else Vector2(edge,along)
			var inner := Vector2(along,edge-side*.42) if along_x else Vector2(edge-side*.42,along)
			for part in house.roof_edge_parts(spec,Vector3(outer.x,house.roof_height_at(spec,outer)-.10,outer.y),Vector3(inner.x,house.roof_height_at(spec,inner)-.10,inner.y)):
				_rod(parent,"ExposedRafter",part[0],part[1],.022,timber)

func _foundation_details(house: LivingHouse) -> void:
	for foundation: MeshInstance3D in house.foundation_nodes:
		_clear_art(foundation)
		var art := _node(foundation,"StoneJoints");art.set_meta("home_art",true)
		var size: Vector3=foundation.mesh.size
		var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for axis in [0,2]:
			var length: float=size[2 if axis==0 else 0]
			for sign in [-1,1]:
				var normal := Vector3(sign,0,0) if axis==0 else Vector3(0,0,sign)
				for row in 2:
					var y: float=-size.y*.5+size.y*float(row+1)/3
					var a := Vector3(sign*(size.x*.5+.001),y,-length*.5) if axis==0 else Vector3(-length*.5,y,sign*(size.z*.5+.001))
					var b3 := Vector3(sign*(size.x*.5+.001),y,length*.5) if axis==0 else Vector3(length*.5,y,sign*(size.z*.5+.001))
					_triangle(surface,a,b3,b3+Vector3.UP*.008,normal);_triangle(surface,a,b3+Vector3.UP*.008,a+Vector3.UP*.008,normal)
				for index in range(ceili(length/.55)):
					var along: float=-length*.5+(index+.5)*length/ceili(length/.55)
					var a := Vector3(sign*(size.x*.5+.001),-size.y*.5,along) if axis==0 else Vector3(along,-size.y*.5,sign*(size.z*.5+.001))
					var b3: Vector3=a+Vector3.UP*size.y
					var offset := Vector3(0,0,.006) if axis==0 else Vector3(.006,0,0)
					_triangle(surface,a,b3,b3+offset,normal);_triangle(surface,a,b3+offset,a+offset,normal)
		_mesh(art,"MortarLines",surface.commit(),Vector3.ZERO,_paint("foundation_mortar","c2bba5",.98))

func _roof_polygon(surface: SurfaceTool, house: LivingHouse, spec: Dictionary, polygon: Array, normal: Vector3) -> void:
	for part in house.roof_polygon_parts(spec,polygon):
		for i in range(1,part.size()-1):
			if (part[i]-part[0]).cross(part[i+1]-part[0]).length_squared()>.000000000001:_triangle(surface,part[0],part[i],part[i+1],normal)

class_name LivingHouse
extends Node3D

# First spatial implementation of the rebuild. This generates a real multi-room
# house from its plan; it does not yet claim a completed household simulation.
signal door_changed(id: String, opened: bool)

var definition: Dictionary = {}
var doors: Dictionary = {}
var fixtures: Dictionary = {}
var rooms: Dictionary = {}
var wall_nodes: Array[Node3D] = []
var cutaway := true
var _materials := {}

func load_plan(path: String) -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or not raw.get("house") is Dictionary: return false
	for key in ["rooms","walls","doors","fixtures"]:
		if not raw.get(key) is Array: return false
	definition = raw.duplicate(true)
	for child in get_children(): remove_child(child);child.queue_free()
	doors.clear();fixtures.clear();rooms.clear();wall_nodes.clear()
	_build()
	return true

func _material(key: String, color: Color, roughness: float = .8) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color=color;material.roughness=roughness
	_materials[key]=material
	return material

func _box(parent: Node3D, label: String, position: Vector3, size: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new();mesh.name=label
	var shape := BoxMesh.new();shape.size=size
	mesh.mesh=shape;mesh.material_override=material;mesh.position=position;parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new();mesh.add_child(body)
		var collision := CollisionShape3D.new();var box := BoxShape3D.new();box.size=size
		collision.shape=box;body.add_child(collision)
	return mesh

func _cylinder(parent: Node3D, label: String, position: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new();mesh.name=label
	var shape := CylinderMesh.new();shape.top_radius=radius;shape.bottom_radius=radius;shape.height=height;shape.radial_segments=24
	mesh.mesh=shape;mesh.material_override=material;mesh.position=position;parent.add_child(mesh)
	return mesh

func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _label(parent: Node3D, text: String, at: Vector3, size: int = 36) -> void:
	var label := Label3D.new();label.text=text;label.position=at;label.font_size=size;label.pixel_size=.006
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true;label.modulate=Color("3d342e");label.outline_modulate=Color("fff6e7");label.outline_size=7
	parent.add_child(label)

func _build() -> void:
	var wood := _material("wood",Color("b77c4f"))
	var plaster := _material("plaster",Color("f1e2cb"))
	var trim := _material("trim",Color("705644"))
	for room in definition.rooms:
		rooms[room.id]=room.duplicate(true)
		var bounds: Array=room.bounds
		var color := Color("d9b88a")
		var kind: String=room.get("kind",room.id)
		if "bath" in kind or "toilet" in kind or "wash" in kind: color=Color("c8ded8")
		elif "child" in kind: color=Color("ead8a7")
		elif "entry" in kind: color=Color("b6b8ae")
		_box(self,"Floor_"+room.id,Vector3(float(bounds[0])+float(bounds[2])*.5,-.06,float(bounds[1])+float(bounds[3])*.5),Vector3(bounds[2],.12,bounds[3]),_material("floor_"+room.id,color),true)
		_label(self,room.get("label",room.id),Vector3(float(bounds[0])+float(bounds[2])*.5,.06,float(bounds[1])+float(bounds[3])*.5))
	var wall_height: float=float(definition.house.get("wall_height",2.65))
	var thickness: float=float(definition.house.get("wall_thickness",.20))
	for wall in definition.walls:
		var a := Vector2(float(wall.start[0]),float(wall.start[1]));var b := Vector2(float(wall.end[0]),float(wall.end[1]))
		var direction := (b-a).normalized();var length := a.distance_to(b)
		var openings: Array=[]
		for door in definition.doors:
			if door.wall!=wall.id: continue
			var center: Vector3=_v(door.center)
			var offset: float=(Vector2(center.x,center.z)-a).dot(direction)
			openings.append({"from":clampf(offset-float(door.width)*.5,0,length),"to":clampf(offset+float(door.width)*.5,0,length),"height":float(door.get("height",2.1))})
		openings.sort_custom(func(x,y):return x.from<y.from)
		var cursor := 0.0
		for opening in openings:
			_wall_piece(wall.id,a,direction,cursor,opening.from,0,wall_height,thickness,plaster)
			_wall_piece(wall.id,a,direction,opening.from,opening.to,opening.height,wall_height,thickness,plaster)
			cursor=opening.to
		_wall_piece(wall.id,a,direction,cursor,length,0,wall_height,thickness,plaster)
	for door in definition.doors:
		var width: float=float(door.width);var height: float=float(door.get("height",2.1))
		var horizontal: bool=door.axis=="x"
		var node := Node3D.new();node.name="Door_"+door.id
		node.position=_v(door.get("hinge",door.center));add_child(node)
		if door.kind=="opening":
			doors[door.id]={"definition":door.duplicate(true),"node":node,"panel":null,"opened":true,"occupant":""}
			continue
		var base_position: Vector3=_v(door.center)-node.position+Vector3.UP*height*.5
		var panel := _box(node,"Panel",base_position,Vector3(width,height,.055) if horizontal else Vector3(.055,height,width),wood,true)
		var knob_position:=Vector3(width*.35,1.0,.045) if horizontal else Vector3(.045,1.0,width*.35)
		_cylinder(panel,"Handle",knob_position-Vector3(0,height*.5,0),.035,.10,trim)
		var open_angle: float=PI*.5
		if door.has("hinge") and door.has("open_end"):
			var closed_end: Vector3=(_v(door.center)-node.position)*2
			var opened_end: Vector3=_v(door.open_end)-node.position
			open_angle=wrapf(atan2(opened_end.x,opened_end.z)-atan2(closed_end.x,closed_end.z),-PI,PI)
		doors[door.id]={"definition":door.duplicate(true),"node":node,"panel":panel,"base_position":base_position,"open_angle":open_angle,"opened":false,"occupant":""}
	for fixture in definition.fixtures: _build_fixture(fixture)
	for id in doors:
		set_door_open(id,doors[id].definition.get("default_state","closed")=="open")

func _wall_piece(id: String, origin: Vector2, direction: Vector2, from: float, to: float, bottom: float, top: float, thickness: float, material: Material) -> void:
	if to-from<.001 or top-bottom<.001:return
	var center: Vector2=origin+direction*(from+to)*.5
	var size:=Vector3(to-from,top-bottom,thickness) if absf(direction.x)>.5 else Vector3(thickness,top-bottom,to-from)
	var node := _box(self,"Wall_"+id,Vector3(center.x,(bottom+top)*.5,center.y),size,material,true)
	wall_nodes.append(node)

func _build_fixture(record: Dictionary) -> void:
	var node:=Node3D.new();node.name="Fixture_"+record.id;node.position=_v(record.position);add_child(node)
	var size: Vector3=_v(record.size)
	var type: String=record.type
	var wood:=_material("wood",Color("b77c4f"))
	var white:=_material("ceramic",Color("f8f4e9"),.35)
	var metal:=_material("metal",Color("a6b6b4"),.3)
	var dark:=_material("dark",Color("424e4c"))
	var textile:=_material("cloth",Color("8ba9a5"))
	if type=="drying_rack":
		for x in [-1,1]:
			_box(node,"Post",Vector3(x*size.x*.48,size.y*.5,0),Vector3(.055,size.y,.055),metal,true)
			_box(node,"Foot",Vector3(x*size.x*.48,.035,0),Vector3(.1,.07,size.z),metal,true)
		_box(node,"Rail",Vector3(0,size.y-.05,0),Vector3(size.x,.045,.045),metal)
	elif "bed" in type:
		_box(node,"Frame",Vector3(0,.18,0),Vector3(size.x,.36,size.z),wood,true)
		_box(node,"Mattress",Vector3(0,.43,0),Vector3(size.x-.08,.18,size.z-.08),white)
		_box(node,"Blanket",Vector3(0,.54,size.z*.10),Vector3(size.x-.08,.08,size.z*.68),textile)
		_box(node,"Pillow",Vector3(0,.57,-size.z*.33),Vector3(size.x*.7,.12,.4),white)
	elif "table" in type or "desk" in type or "prep" in type:
		_box(node,"Top",Vector3(0,size.y-.045,0),Vector3(size.x,.09,size.z),wood)
		for x in [-1,1]:
			for z in [-1,1]:_box(node,"Leg",Vector3(x*(size.x*.5-.07),(size.y-.09)*.5,z*(size.z*.5-.07)),Vector3(.09,size.y-.09,.09),wood,true)
	elif "chair" in type or "seat" in type:
		_box(node,"Seat",Vector3(0,.44,0),Vector3(size.x,.08,size.z),wood,true)
		var heading: float=deg_to_rad(float(record.facing))
		var face:=Vector3(sin(heading),0,cos(heading))
		var back_position:=Vector3(-face.x*size.x*.44,.72,-face.z*size.z*.44)
		_box(node,"Back",back_position,Vector3(.07,.48,size.z) if absf(face.x)>.5 else Vector3(size.x,.48,.07),wood)
		for x in [-1,1]:
			for z in [-1,1]:_box(node,"Leg",Vector3(x*size.x*.38,.21,z*size.z*.38),Vector3(.06,.42,.06),wood)
	elif "bath" in type or "tub" in type:
		_box(node,"Base",Vector3(0,.13,0),Vector3(size.x,.26,size.z),white,true)
		for sign in [-1,1]:
			_box(node,"Rim",Vector3(sign*(size.x*.5-.06),.35,0),Vector3(.12,.44,size.z),white)
			_box(node,"Rim",Vector3(0,.35,sign*(size.z*.5-.06)),Vector3(size.x,.44,.12),white)
		_box(node,"Water",Vector3(0,.39,0),Vector3(size.x-.25,.015,size.z-.25),_material("water",Color("8fc8c7"),.2))
	elif "toilet" in type:
		_cylinder(node,"Pedestal",Vector3(0,.19,0),.17,.38,white)
		_cylinder(node,"Bowl",Vector3(0,.40,-.08),.25,.12,white)
		_box(node,"Cistern",Vector3(0,.58,.22),Vector3(.46,.6,.18),white)
	elif "sink" in type or "washbasin" in type:
		_box(node,"Cabinet",Vector3(0,size.y*.46,0),Vector3(size.x,size.y*.92,size.z),wood,true)
		_box(node,"Basin",Vector3(0,size.y,0),Vector3(size.x,.10,size.z),white)
		_box(node,"Inset",Vector3(0,size.y+.055,0),Vector3(size.x*.7,.01,size.z*.6),metal)
		_box(node,"Tap",Vector3(0,size.y+.18,size.z*.35),Vector3(.055,.24,.055),metal)
	elif "stove" in type:
		_box(node,"Oven",Vector3(0,size.y*.5,0),size,white,true)
		for sign in [-1,1]:_cylinder(node,"Hob",Vector3(sign*size.x*.23,size.y+.012,0),size.x*.15,.025,dark)
	elif "fridge" in type or "washer" in type:
		_box(node,"Body",Vector3(0,size.y*.5,0),size,white,true)
		_box(node,"Door",Vector3(0,size.y*.55,-size.z*.5-.012),Vector3(size.x*.88,size.y*.65,.025),metal)
	else:
		_box(node,"Body",Vector3(0,size.y*.5,0),size,textile if "sofa" in type else wood,bool(record.get("blocking",true)))
	var anchor:=Marker3D.new();anchor.name="UsePoint";anchor.position=_v(record.interaction_point)-node.position;anchor.rotation.y=deg_to_rad(float(record.facing));node.add_child(anchor)
	fixtures[record.id]={"definition":record.duplicate(true),"node":node,"anchor":anchor,"reserved_by":""}

func set_door_open(id: String, opened: bool) -> bool:
	return set_door_fraction(id,1.0 if opened else 0.0)

func set_door_fraction(id: String, amount: float) -> bool:
	if not doors.has(id):return false
	if not is_finite(amount) or amount<0 or amount>1:return false
	var record: Dictionary=doors[id]
	if record.definition.kind=="opening":return amount==1
	var was_opened: bool=record.opened
	record.opened=amount>=.999;record.open_fraction=amount
	var node: Node3D=record.panel
	if record.definition.get("kind","")=="sliding":
		node.position=record.base_position+(Vector3.RIGHT if record.definition.axis=="x" else Vector3.BACK)*float(record.definition.width)*amount
	else: record.node.rotation.y=record.open_angle*amount
	if was_opened!=record.opened:door_changed.emit(id,record.opened)
	return true

func update_cutaway(eye: Vector3) -> void:
	var local_eye:=to_local(eye)
	var bounds: Array=definition.get("house",{}).get("bounds",[0,0,12,10])
	var center:=Vector3(float(bounds[0])+float(bounds[2])*.5,0,float(bounds[1])+float(bounds[3])*.5)
	for node in wall_nodes:
		# Occlusion only. Collision and spatial ownership remain intact.
		var toward: Vector3=node.position-center
		toward.y=0
		var viewing: Vector3=local_eye-center
		viewing.y=0
		node.visible=not cutaway or toward.dot(viewing)<0

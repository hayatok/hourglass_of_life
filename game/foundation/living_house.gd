class_name LivingHouse
extends Node3D

# Furniture keeps its authored front when an approach moves sideways to a
# burner, drawer or board. An actor's facing points into a cabinet; its visible
# front points back toward the actor. Seat facing already points out of a seat.
static func fixture_basis(record: Dictionary) -> Basis:
	var seat: bool=record.get("type","") in ["chair","dining_seat","sofa"]
	var angle: float=float(record.get("art_facing",record.get("use_facing",record.get("facing",0)) if seat else float(record.get("facing",0))+180.0))
	return Basis(Vector3.UP,deg_to_rad(angle))

# First spatial implementation of the rebuild. This generates a real multi-room
# house from its plan; it does not yet claim a completed household simulation.
signal door_changed(id: String, opened: bool)

var definition: Dictionary = {}
var doors: Dictionary = {}
var fixtures: Dictionary = {}
var rooms: Dictionary = {}
var wall_nodes: Array[Node3D] = []
var wall_roots: Dictionary = {}
var windows: Dictionary = {}
var thresholds: Dictionary = {}
var roof_root: Node3D
var cutaway := true
var _materials := {}

func load_plan(path: String) -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or not raw.get("house") is Dictionary: return false
	for key in ["rooms","walls","doors","fixtures"]:
		if not raw.get(key) is Array: return false
	definition = raw.duplicate(true)
	for child in get_children(): remove_child(child);child.queue_free()
	doors.clear();fixtures.clear();rooms.clear();wall_nodes.clear();wall_roots.clear();windows.clear();thresholds.clear()
	roof_root=null
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
		var body := StaticBody3D.new();body.name="Solid";mesh.add_child(body)
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
	for zone in definition.get("external_zones",[]):
		var bounds: Array=zone.bounds
		var floor_y: float=float(zone.get("floor_y",0))
		# The patio is an actual surface at the navigation floor height. The
		# surrounding grass is lower; residents must not hover above it.
		_box(self,"Floor_"+zone.id,Vector3(float(bounds[0])+float(bounds[2])*.5,floor_y-.075,float(bounds[1])+float(bounds[3])*.5),Vector3(bounds[2],.15,bounds[3]),_material("patio",Color("c4bea9")),true)
	var wall_height: float=float(definition.house.get("wall_height",2.65))
	var thickness: float=float(definition.house.get("wall_thickness",.20))
	for door in definition.doors:
		var rect: Rect2=HomeNavigation.threshold_rect(door,thickness)
		var floor_y: float=float(definition.house.get("floor_y",0))
		var threshold := _box(self,"Floor_Threshold_"+str(door.id),Vector3(rect.get_center().x,floor_y-.06,rect.get_center().y),Vector3(rect.size.x,.12,rect.size.y),wood,true)
		threshold.set_meta("floor_kind","threshold");threshold.set_meta("door_id",door.id)
		threshold.get_node("Solid").set_meta("floor_kind","threshold")
		threshold.get_node("Solid").set_meta("door_id",door.id)
		thresholds[door.id]={"rect":rect,"node":threshold,"floor_y":floor_y}
	for wall in definition.walls:
		var a := Vector2(float(wall.start[0]),float(wall.start[1]));var b := Vector2(float(wall.end[0]),float(wall.end[1]))
		var direction := (b-a).normalized()
		var assembly := Node3D.new();assembly.name="WallAssembly_"+str(wall.id)
		assembly.set_meta("wall_id",wall.id);assembly.set_meta("wall_center",Vector3((a.x+b.x)*.5,wall_height*.5,(a.y+b.y)*.5))
		add_child(assembly);wall_roots[wall.id]=assembly
		for solid: Rect2 in wall_solid_rects(wall):
			_wall_piece(wall.id,a,direction,solid.position.x,solid.end.x,solid.position.y,solid.end.y,thickness,plaster)
	for window in definition.get("windows",[]): _build_window(window,thickness)
	for door in definition.doors:
		var width: float=float(door.width);var height: float=float(door.get("height",2.1))
		var horizontal: bool=door.axis=="x"
		var node := Node3D.new();node.name="Door_"+door.id
		node.position=_v(door.get("hinge",door.center));wall_roots[door.wall].add_child(node)
		node.set_meta("wall_id",door.wall)
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
	_build_roof()

func wall_solid_rects(wall: Dictionary) -> Array[Rect2]:
	# Coordinates are distance along this wall / height. Split at every aperture
	# edge, then subtract the UNION of its vertical intervals in each band. This
	# retains sills and headers even with stacked or partially overlapping holes.
	var a := Vector2(float(wall.start[0]),float(wall.start[1]))
	var b := Vector2(float(wall.end[0]),float(wall.end[1]))
	var length := a.distance_to(b);var direction := (b-a).normalized()
	var height: float=float(definition.house.get("wall_height",2.65))
	var holes: Array[Rect2]=[];var cuts: Array[float]=[0.0,length]
	for kind: String in ["doors","windows"]:
		for record in definition.get(kind,[]):
			if record.wall!=wall.id:continue
			var center: Vector3=_v(record.center)
			var along: float=(Vector2(center.x,center.z)-a).dot(direction)
			var bottom: float=0.0 if kind=="doors" else center.y-float(record.height)*.5
			var top: float=float(record.get("height",2.1)) if kind=="doors" else center.y+float(record.height)*.5
			var left: float=clampf(along-float(record.width)*.5,0,length)
			var right: float=clampf(along+float(record.width)*.5,0,length)
			bottom=clampf(bottom,0,height);top=clampf(top,0,height)
			if right-left<.00001 or top-bottom<.00001:continue
			holes.append(Rect2(left,bottom,right-left,top-bottom));cuts.append(left);cuts.append(right)
	cuts.sort()
	var unique: Array[float]=[]
	for edge: float in cuts:
		if unique.is_empty() or edge-unique[-1]>.00001:unique.append(edge)
	var result: Array[Rect2]=[]
	for index in range(unique.size()-1):
		var left: float=unique[index];var right: float=unique[index+1]
		var middle: float=(left+right)*.5;var intervals: Array[Vector2]=[]
		for hole: Rect2 in holes:
			if middle>hole.position.x and middle<hole.end.x:intervals.append(Vector2(hole.position.y,hole.end.y))
		intervals.sort_custom(func(x: Vector2,y: Vector2):return x.x<y.x)
		var cursor := 0.0
		for interval: Vector2 in intervals:
			if interval.x-cursor>.00001:result.append(Rect2(left,cursor,right-left,interval.x-cursor))
			cursor=maxf(cursor,interval.y)
		if height-cursor>.00001:result.append(Rect2(left,cursor,right-left,height-cursor))
	return result

func _wall_piece(id: String, origin: Vector2, direction: Vector2, from: float, to: float, bottom: float, top: float, thickness: float, material: Material) -> void:
	if to-from<.001 or top-bottom<.001:return
	var center: Vector2=origin+direction*(from+to)*.5
	var size:=Vector3(to-from,top-bottom,thickness) if absf(direction.x)>.5 else Vector3(thickness,top-bottom,to-from)
	var node := _box(wall_roots[id],"Wall_"+id+"_"+str(wall_nodes.size()),Vector3(center.x,(bottom+top)*.5,center.y),size,material,true)
	node.set_meta("wall_id",id);node.set_meta("wall_rect",Rect2(from,bottom,to-from,top-bottom))
	node.get_node("Solid").set_meta("wall_id",id)
	wall_nodes.append(node)

func _build_window(record: Dictionary, thickness: float) -> void:
	var node := Node3D.new();node.name="Window_"+str(record.id)
	node.position=_v(record.center)
	var inward: Vector3=_v(record.inward);node.rotation.y=atan2(inward.x,inward.z)
	node.set_meta("wall_id",record.wall);node.set_meta("window_id",record.id)
	wall_roots[record.wall].add_child(node)
	var width: float=float(record.width);var height: float=float(record.height)
	var wood := _material("window_trim",Color("dfd0b4"))
	var frame: Array[MeshInstance3D]=[]
	for side in [-1,1]:
		frame.append(_box(node,"FrameSide",Vector3(side*(width*.5-.028),0,0),Vector3(.056,height,thickness+.028),wood,true))
		frame.append(_box(node,"FrameRail",Vector3(0,side*(height*.5-.028),0),Vector3(width-.112,.056,thickness+.028),wood,true))
	frame.append(_box(node,"Mullion",Vector3.ZERO,Vector3(.032,height-.112,thickness*.55),wood,true))
	var frosted: bool=bool(record.get("frosted",false))
	var material := _material("glass_frosted" if frosted else "glass_clear",Color("bdcfc7") if frosted else Color("b6d0ce"),.78 if frosted else .18)
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	if not frosted:
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a=.24
	var glass := _box(node,"Glass",Vector3.ZERO,Vector3(width-.112,height-.112,.014),material,true)
	var body := glass.get_node("Solid") as StaticBody3D
	body.set_meta("window_id",record.id);body.set_meta("wall_id",record.wall);body.set_meta("architecture_kind","glass")
	for part: MeshInstance3D in frame:
		part.set_meta("wall_id",record.wall)
		part.get_node("Solid").set_meta("window_id",record.id)
		part.get_node("Solid").set_meta("wall_id",record.wall)
	windows[record.id]={"definition":record.duplicate(true),"node":node,"glass":glass,"glass_body":body,"frame_pieces":frame}

func _roof_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b-a).cross(c-a).dot(normal)>0:
		var swap := b;b=c;c=swap
	for vertex: Vector3 in [a,b,c]:
		surface.set_normal(normal);surface.set_uv(Vector2(vertex.x,vertex.z));surface.add_vertex(vertex)

func _roof_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_roof_triangle(surface,a,b,c,normal);_roof_triangle(surface,a,c,d,normal)

func _build_roof() -> void:
	var roof: Dictionary=definition.house.get("roof",{})
	if roof.get("shape","")!="gable":return
	var bounds: Array=definition.house.bounds
	var low := Vector2(bounds[0],bounds[1]);var high := low+Vector2(bounds[2],bounds[3])
	var height: float=float(definition.house.get("wall_height",2.65))
	var rise: float=float(roof.rise);var eaves: float=float(roof.get("eaves",.35))
	var along_x: bool=roof.get("ridge_axis","x")=="x"
	var middle: float=(low.y+high.y)*.5 if along_x else (low.x+high.x)*.5
	var half: float=float(bounds[3] if along_x else bounds[2])*.5
	var eave_y: float=height-rise*eaves/half
	roof_root=Node3D.new();roof_root.name="Roof";roof_root.set_meta("architecture_kind","roof")
	roof_root.set_meta("rise",rise);roof_root.set_meta("ridge_axis",roof.get("ridge_axis","x"));add_child(roof_root)
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		var edge: float=middle+side*(half+eaves)
		var a := Vector3(low.x-eaves,eave_y,edge) if along_x else Vector3(edge,eave_y,low.y-eaves)
		var b := Vector3(high.x+eaves,eave_y,edge) if along_x else Vector3(edge,eave_y,high.y+eaves)
		var c := Vector3(high.x+eaves,height+rise,middle) if along_x else Vector3(middle,height+rise,high.y+eaves)
		var d := Vector3(low.x-eaves,height+rise,middle) if along_x else Vector3(middle,height+rise,low.y-eaves)
		var normal := Vector3(0,half,side*rise).normalized() if along_x else Vector3(side*rise,half,0).normalized()
		_roof_quad(surface,a,b,c,d,normal)
		var drop := Vector3.DOWN*.10
		_roof_quad(surface,d+drop,c+drop,b+drop,a+drop,-normal)
		_roof_quad(surface,a+drop,b+drop,b,a,Vector3(0,0,side) if along_x else Vector3(side,0,0))
		_roof_quad(surface,a,d,d+drop,a+drop,Vector3.LEFT if along_x else Vector3.FORWARD)
		_roof_quad(surface,b+drop,c+drop,c,b,Vector3.RIGHT if along_x else Vector3.BACK)
	var mesh := MeshInstance3D.new();mesh.name="RoofSlopes";mesh.mesh=surface.commit()
	mesh.material_override=_material("roof_"+str(roof.get("color","7c8276")),Color(roof.get("color","7c8276")),.87);roof_root.add_child(mesh)
	var body := StaticBody3D.new();body.name="Solid";mesh.add_child(body)
	var collision := CollisionShape3D.new();collision.shape=mesh.mesh.create_trimesh_shape()
	(collision.shape as ConcavePolygonShape3D).backface_collision=true;body.add_child(collision)
	body.set_meta("architecture_kind","roof")
	# Gable infill lies at the house ends, not at the protruding roof eaves.
	var caps := SurfaceTool.new();caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1,1]:
		var end: float=(low.x if side<0 else high.x) if along_x else (low.y if side<0 else high.y)
		var a := Vector3(end,height,low.y) if along_x else Vector3(low.x,height,end)
		var b := Vector3(end,height,high.y) if along_x else Vector3(high.x,height,end)
		var c := Vector3(end,height+rise,middle) if along_x else Vector3(middle,height+rise,end)
		_roof_triangle(caps,a,b,c,Vector3(side,0,0) if along_x else Vector3(0,0,side))
	var cap := MeshInstance3D.new();cap.name="GableInfill";cap.mesh=caps.commit()
	cap.material_override=_material("plaster",Color("f1e2cb"));roof_root.add_child(cap)
	var cap_body := StaticBody3D.new();cap.add_child(cap_body)
	var cap_shape := CollisionShape3D.new();cap_shape.shape=cap.mesh.create_trimesh_shape()
	(cap_shape.shape as ConcavePolygonShape3D).backface_collision=true;cap_body.add_child(cap_shape)
	roof_root.visible=not cutaway

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

func set_fixture_displacement(id: String, offset: Vector3) -> bool:
	if not fixtures.has(id) or not offset.is_finite() or offset.length()>2:return false
	var item: Dictionary=fixtures[id]
	if item.definition.type not in ["chair","dining_seat"]:return false
	item.node.position=_v(item.definition.position)+offset
	item.displacement=offset
	return true

func set_door_fraction(id: String, amount: float) -> bool:
	if not doors.has(id):return false
	if not is_finite(amount) or amount<0 or amount>1:return false
	var record: Dictionary=doors[id]
	if record.definition.kind=="opening":return amount==1
	var was_opened: bool=record.opened
	record.opened=amount>=.999;record.open_fraction=amount
	var node: Node3D=record.panel
	if record.definition.get("kind","")=="sliding":
		var pocket: Array=record.definition.pocket_interval
		var pocket_center: float=(float(pocket[0])+float(pocket[1]))*.5
		var closed_center: float=float(record.definition.center[0 if record.definition.axis=="x" else 2])
		node.position=record.base_position+(Vector3.RIGHT if record.definition.axis=="x" else Vector3.BACK)*(pocket_center-closed_center)*amount
	else: record.node.rotation.y=record.open_angle*amount
	if was_opened!=record.opened:door_changed.emit(id,record.opened)
	return true

func update_cutaway(eye: Vector3) -> void:
	var local_eye:=to_local(eye)
	var bounds: Array=definition.get("house",{}).get("bounds",[0,0,12,10])
	var center:=Vector3(float(bounds[0])+float(bounds[2])*.5,0,float(bounds[1])+float(bounds[3])*.5)
	for node: Node3D in wall_roots.values():
		# Occlusion only. Collision and spatial ownership remain intact.
		var toward: Vector3=node.get_meta("wall_center")-center
		toward.y=0
		var viewing: Vector3=local_eye-center
		viewing.y=0
		node.visible=not cutaway or toward.dot(viewing)<0
	if is_instance_valid(roof_root):roof_root.visible=not cutaway

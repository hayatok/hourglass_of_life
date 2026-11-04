class_name HouseholdProps
extends Node3D

# A derived view, never a resource simulation. Source IDs address quantity slots
# in inventory/jobs, not persistent item identity across the aggregate model.
# The controller alone creates food/results, spends stock, advances work/time,
# and decides cancellation. Reconfigure/resume reconstructs this same view.
const MAX_INDIVIDUAL := 24
const PLATE_RADIUS := .095
const TRAY_HANDLE_X := .30
const TRAY_HANDLE_Y := .105
const TRAY_HANDLE_RADIUS := .010
const LINEN = preload("res://game/assets/foundation/home/linen.gdshader")
var house: LivingHouse
var life: HouseholdDay
var actors: Dictionary = {}
var objects: Dictionary = {}
var diagnostics: Array = []
var sockets: Dictionary = {}
var socket_samples: Dictionary = {}
var _carry_frames: Dictionary = {}
var _carry_anchors: Dictionary = {}
var _definitions: Dictionary = {}
var _resident_places: Dictionary = {}
var _materials: Dictionary = {}
var _hidden: Array = []
var _connections: Array = []
var _hardware: Node3D
var _pan_lids: Array = []
var _initial_models: Array = []
var _wanted: Dictionary = {}
var _configured := false

func configure(home: LivingHouse, day: HouseholdDay, resident_actors: Dictionary) -> bool:
	if home==null or day==null or not is_inside_tree() or home.definition.is_empty() or day.plan.get("house",{}).get("id")!=home.definition.get("house",{}).get("id"): return false
	var candidates := {}
	for record in home.definition.fixtures: candidates[record.id]=record
	for id in ["fridge","prep","stove","sink","dining_table","washer","linen_storage","towel_basket"]:
		if not candidates.has(id): return false
		var support: Variant=candidates[id].get("support_point")
		if not support is Array or support.size()!=3 or support.any(func(value):return not (value is int or value is float) or not is_finite(float(value))): return false
	var other: int=int(home.get_meta("household_props_owner",0))
	if other!=0 and other!=get_instance_id() and is_instance_id_valid(other): return false
	_clear()
	house=home;life=day;actors=resident_actors.duplicate()
	house.set_meta("household_props_owner",get_instance_id())
	_definitions.clear();_resident_places.clear()
	for record in house.definition.fixtures: _definitions[record.id]=record
	for record in house.definition.residents: _resident_places[record.id]=record
	global_transform=house.global_transform
	_hardware=Node3D.new();_hardware.name="SourceFixtureHardware";add_child(_hardware)
	_hide_authored_stock()
	_build_pan();_build_washer_window()
	for id in actors: _bind_hands(id,actors[id])
	_configured=true;sync()
	return true

func _exit_tree() -> void: _clear()

func _clear() -> void:
	_configured=false
	for entry in _connections:
		if is_instance_valid(entry.skeleton) and entry.skeleton.skeleton_updated.is_connected(entry.callback): entry.skeleton.skeleton_updated.disconnect(entry.callback)
	_connections.clear()
	for id in objects.keys(): _delete_object(id)
	objects.clear()
	for anchor in _carry_anchors.values():
		if is_instance_valid(anchor):
			if anchor.get_parent()!=null: anchor.get_parent().remove_child(anchor)
			anchor.queue_free()
	_carry_anchors.clear();_carry_frames.clear()
	for hands in sockets.values():
		for record in hands.values():
			if is_instance_valid(record.node):
				if record.node.get_parent()!=null: record.node.get_parent().remove_child(record.node)
				record.node.queue_free()
	sockets.clear();socket_samples.clear()
	for entry in _hidden:
		if is_instance_valid(entry.node): entry.node.visible=entry.visible
	_hidden.clear();_pan_lids.clear();_initial_models.clear()
	if is_instance_valid(_hardware): remove_child(_hardware);_hardware.queue_free()
	_hardware=null
	if is_instance_valid(house) and int(house.get_meta("household_props_owner",0))==get_instance_id(): house.remove_meta("household_props_owner")
	house=null;life=null;actors.clear()

func _v(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])

func _front(id: String) -> Basis:
	return LivingHouse.fixture_basis(_definitions[id])

func _at(id: String, offset: Vector3 = Vector3.ZERO) -> Vector3:
	return _v(_definitions[id].position)+_front(id)*offset

func _surface(id: String) -> String:
	if not _definitions.has(id): return ""
	var result: String=_definitions[id].get("serves",id)
	return result if _definitions.has(result) else id

func _support(id: String) -> Vector3:
	# configure has checked the resource support points. No imaginary .95m
	# surface is supplied for appliances, storage or the drying rack.
	var definition: Dictionary=_definitions[id]
	return _v(definition.support_point)

func _paint(key: String, color: String) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var result := StandardMaterial3D.new();result.albedo_color=Color(color);result.roughness=.79
	_materials[key]=result;return result

func _cloth(wet: bool, dirty: bool, towel: bool) -> ShaderMaterial:
	var key := "cloth_%s_%s_%s"%[wet,dirty,towel]
	if _materials.has(key): return _materials[key]
	var result := ShaderMaterial.new();result.shader=LINEN
	result.set_shader_parameter("cloth_color",Color("7b948d" if wet else "a39b80" if dirty else "dfd0ad" if towel else "91a599"))
	result.set_shader_parameter("stripe_amount",.2 if towel else 0)
	_materials[key]=result;return result

func _mesh(parent: Node3D, label: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new();result.name=label;result.mesh=mesh;result.material_override=material
	result.position=at;parent.add_child(result);return result

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new();shape.size=size
	return _mesh(parent,label,shape,at,material)

func _sphere(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := SphereMesh.new();shape.radius=.5;shape.height=1;shape.radial_segments=12;shape.rings=6
	var result := _mesh(parent,label,shape,at,material);result.scale=size;return result

func _cylinder(parent: Node3D, label: String, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new();shape.top_radius=radius;shape.bottom_radius=radius;shape.height=height;shape.radial_segments=20
	return _mesh(parent,label,shape,at,material)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b-a).cross(c-a).dot(normal)>0:
		var swap := b;b=c;c=swap
	for vertex: Vector3 in [a,b,c]: surface.set_normal(normal);surface.add_vertex(vertex)

func _lathe(parent: Node3D, label: String, profile: Array, at: Vector3, material: Material) -> void:
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size()-1):
		var first: Vector2=profile[row];var last: Vector2=profile[row+1]
		for index in 24:
			var angle := float(index)*TAU/24;var next := float(index+1)*TAU/24
			var a := Vector3(cos(angle)*first.x,first.y,sin(angle)*first.x)
			var b := Vector3(cos(next)*first.x,first.y,sin(next)*first.x)
			var c := Vector3(cos(next)*last.x,last.y,sin(next)*last.x)
			var d := Vector3(cos(angle)*last.x,last.y,sin(angle)*last.x)
			var mid := angle+PI/24
			var normal := Vector3(cos(mid)*(first.y-last.y),last.x-first.x,sin(mid)*(first.y-last.y)).normalized()
			_triangle(surface,a,b,c,normal);_triangle(surface,a,c,d,normal)
	_mesh(parent,label,surface.commit(),at,material)

func _walk_nodes(parent: Node) -> Array:
	var result: Array=[]
	for child in parent.get_children(): result.append(child);result.append_array(_walk_nodes(child))
	return result

func _hide(node: Node3D) -> void:
	for entry in _hidden:
		if entry.node==node: return
	_hidden.append({"node":node,"visible":node.visible});node.visible=false

func _hide_authored_stock() -> void:
	for fixture in house.fixtures.values():
		for node in _walk_nodes(fixture.node):
			if node is Node3D and str(node.name)=="InitialTownModel": _initial_models.append(node)
	for id in ["linen_storage","washer","stove"]:
		if not house.fixtures.has(id): continue
		for node in _walk_nodes(house.fixtures[id].node):
			if not node is MeshInstance3D: continue
			var name: String=str(node.name)
			# Repeated procedural names may become @MeshInstance3D@... instead
			# of FoldedLinen2. In these two stock fixtures only, the linen material
			# identifies all folded stock meshes; furniture/curtains/books elsewhere
			# are deliberately outside this replacement scope.
			var cloth := node.material_override as ShaderMaterial
			if id in ["linen_storage","washer"] and (name.begins_with("FoldedLinen") or name=="FoldedTowel" or cloth!=null and cloth.shader==LINEN): _hide(node)
			if id=="stove" and name in ["Saucepan","PotLid","LidGrip"]:
				_hide(node)
				if name in ["PotLid","LidGrip"]: _pan_lids.append(node)
			if id=="washer" and name in ["ApplianceBody","DrumRim","DrumGlass"]: _hide(node)

func _build_pan() -> void:
	if not _definitions.has("stove"): return
	var f: Dictionary=_definitions.stove;var size := _v(f.size)
	var pan := Node3D.new();pan.name="OpenSourceSaucepan";_hardware.add_child(pan)
	pan.transform=Transform3D(_front("stove"),_support("stove")+_front("stove")*Vector3(-size.x*.24,.028,-size.z*.05))
	_lathe(pan,"OpenPot",[Vector2(0,.012),Vector2(.075,.012),Vector2(.098,.13),Vector2(.105,.13),Vector2(.088,0),Vector2(0,0)],Vector3.ZERO,_paint("pot","b87558"))

func _build_washer_window() -> void:
	if not _definitions.has("washer"): return
	var f: Dictionary=_definitions.washer;var size := _v(f.size)
	if absf(_front("washer").z.x)>.7: size=Vector3(size.z,size.y,size.x)
	var machine := Node3D.new();machine.name="HollowWasherHousing";_hardware.add_child(machine)
	machine.transform=Transform3D(_front("washer"),_at("washer"))
	var enamel := _paint("enamel","e5e4d4")
	for side in [-1,1]: _box(machine,"Side",Vector3(side*(size.x*.5-.012),size.y*.5,0),Vector3(.024,size.y,size.z),enamel)
	_box(machine,"Top",Vector3(0,size.y-.012,0),Vector3(size.x,.024,size.z),enamel)
	_box(machine,"Back",Vector3(0,size.y*.5,-size.z*.5+.012),Vector3(size.x,size.y,.024),enamel)
	var center := Vector2(0,size.y*.45);var radius: float=size.x*.245
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 32:
		var points: Array=[]
		for angle in [float(index)*TAU/32,float(index+1)*TAU/32]:
			var direction := Vector2(cos(angle),sin(angle))
			var tx: float=size.x*.5/absf(direction.x) if absf(direction.x)>.0001 else INF
			var ty: float=((size.y-center.y) if direction.y>0 else center.y)/absf(direction.y) if absf(direction.y)>.0001 else INF
			var outer := center+direction*minf(tx,ty);var inner := center+direction*radius
			points.append(Vector3(outer.x,outer.y,size.z*.5-.012));points.append(Vector3(inner.x,inner.y,size.z*.5-.012))
		_triangle(surface,points[0],points[2],points[3],Vector3.BACK);_triangle(surface,points[0],points[3],points[1],Vector3.BACK)
	_mesh(machine,"FrontWithRealOpening",surface.commit(),Vector3.ZERO,enamel)
	var drum := _cylinder(machine,"DrumBack",Vector3(0,center.y,size.z*.5-.14),radius,.012,_paint("drum","596b65"));drum.rotation.x=PI*.5
	var rim := Node3D.new();rim.name="WindowRim";machine.add_child(rim);rim.position=Vector3(0,center.y,size.z*.5-.012);rim.rotation.x=PI*.5
	_lathe(rim,"HollowRim",[Vector2(radius,0),Vector2(size.x*.31,0),Vector2(size.x*.31,.012),Vector2(radius,.012),Vector2(radius,0)],Vector3.ZERO,_paint("metal","b1bbae"))
	var glass := StandardMaterial3D.new();glass.albedo_color=Color(.63,.76,.71,.12);glass.roughness=.45;glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var pane := _cylinder(machine,"ClosedWindowGlass",Vector3(0,center.y,size.z*.5-.001),radius,.003,glass);pane.rotation.x=PI*.5

func _bind_hands(id: String, actor: Node) -> void:
	if not is_instance_valid(actor): return
	var model: Variant=actor.get("model")
	if not model is Node: return
	var skeleton: Variant=model.get("skeleton")
	if not skeleton is Skeleton3D: return
	sockets[id]={}
	for side in ["L","R"]:
		var hand: int=skeleton.find_bone("DEF-hand."+side)
		var finger: int=skeleton.find_bone("DEF-finger2."+side)
		if hand<0 or finger<0: continue
		var attachment := BoneAttachment3D.new();attachment.name="HouseholdSocket_"+side
		attachment.override_pose=false;attachment.bone_name="DEF-hand."+side;skeleton.add_child(attachment)
		var rest: Transform3D=skeleton.get_bone_global_rest(hand)
		var palm: Vector3=(rest.affine_inverse()*skeleton.get_bone_global_rest(finger).origin)*.5
		sockets[id][side]={"node":attachment,"palm_local":palm,"rest_basis":rest.basis}
	var callback: Callable=_observe_sockets.bind(id)
	skeleton.skeleton_updated.connect(callback);_connections.append({"skeleton":skeleton,"callback":callback})
	_observe_sockets(id)

func _observe_sockets(actor: String) -> void:
	# Capture inside the final skeleton signal: public bone poses may be restored
	# after modifiers run. The attachment never overrides or moves a bone.
	socket_samples[actor]={}
	for side in sockets.get(actor,{}):
		var attachment: BoneAttachment3D=sockets[actor][side].node
		attachment.on_skeleton_update()
		socket_samples[actor][side]=attachment.global_transform

func hand_socket(actor: String, side: String = "L") -> BoneAttachment3D:
	return sockets.get(actor,{}).get(side,{}).get("node")

func set_carry_frame(actor: String, world: Transform3D) -> bool:
	# The executor supplies the bottom-centre frame measured from the actor's
	# calibration. This anchor is a sibling of the model, never a hand child.
	if not _configured or not actors.get(actor) is Node3D or not is_instance_valid(actors[actor]) or not _rigid_frame(world): return false
	var anchor: Node3D=_carry_anchors.get(actor)
	if not is_instance_valid(anchor):
		anchor=Node3D.new();anchor.name="HouseholdCarryFrame";actors[actor].add_child(anchor);_carry_anchors[actor]=anchor
	anchor.global_transform=world;_carry_frames[actor]=world
	for record in objects.values():
		if record.holder==actor and is_instance_valid(record.node):
			if record.node.get_parent()!=anchor: record.node.reparent(anchor,false)
			record.node.transform=Transform3D.IDENTITY
	return true

func clear_carry_frame(actor: String) -> bool:
	if not _carry_frames.has(actor): return true
	_carry_frames.erase(actor)
	# Rebind the old derived objects before freeing their carrier parent.
	for id in objects.keys():
		if objects[id].holder==actor: _apply(id,objects[id])
	var anchor: Node3D=_carry_anchors.get(actor)
	if is_instance_valid(anchor):
		# Unsupported legacy actors must retain the same view node as well.
		for child in anchor.get_children():
			if child is Node3D: child.reparent(self,true)
		if anchor.get_parent()!=null: anchor.get_parent().remove_child(anchor)
		anchor.queue_free()
	_carry_anchors.erase(actor)
	return true

func has_carry_frame(actor: String) -> bool:
	return _carry_frames.has(actor) and is_instance_valid(_carry_anchors.get(actor))

func carry_anchor(actor: String) -> Node3D:
	return _carry_anchors.get(actor)

static func _rigid_frame(value: Transform3D) -> bool:
	if not value.origin.is_finite() or value.origin.length()>1000: return false
	var basis: Basis=value.basis
	for axis in [basis.x,basis.y,basis.z]:
		if not axis.is_finite() or absf(axis.length()-1)>.0001: return false
	return absf(basis.x.dot(basis.y))<.0001 and absf(basis.x.dot(basis.z))<.0001 and absf(basis.y.dot(basis.z))<.0001 and absf(basis.determinant()-1)<.0001

static func _grip_frame(at: Vector3, normal: Vector3, fingers: Vector3) -> Transform3D:
	var z: Vector3=normal.normalized()
	var y: Vector3=(fingers-z*fingers.dot(z)).normalized()
	return Transform3D(Basis(y.cross(z).normalized(),y,z),at)

static func grips_for(kind: String) -> Dictionary:
	# Local +Z is the palm's pressing normal; local +Y runs along the fingers.
	# L/R are anatomical hand labels, not a screen-left/right convention.
	var grips: Dictionary = {}
	match kind:
		"tray":
			# One unchanged contact for pickup/carry/place: the outer surface of
			# a real raised handle, not the inaccessible underside above a table.
			grips.L=_grip_frame(Vector3(TRAY_HANDLE_X+TRAY_HANDLE_RADIUS,TRAY_HANDLE_Y,0),Vector3.LEFT,Vector3.UP)
			grips.R=_grip_frame(Vector3(-TRAY_HANDLE_X-TRAY_HANDLE_RADIUS,TRAY_HANDLE_Y,0),Vector3.RIGHT,Vector3.UP)
		"basket":
			grips.L=_grip_frame(Vector3(.21,.16,0),Vector3.LEFT,Vector3.UP)
			grips.R=_grip_frame(Vector3(-.21,.16,0),Vector3.RIGHT,Vector3.UP)
		"textile","cloth":
			# FoldEdge centre(0,.022,.055), size(.20,.018,.035): front z=.0725.
			grips.R=_grip_frame(Vector3(.07,.022,.0725),Vector3.FORWARD,Vector3.LEFT)
		_: return {}
	var midpoint: Vector3=Vector3.ZERO
	for grip in grips.values(): midpoint+=grip.origin
	midpoint/=float(grips.size())
	return {"kind":kind,"local_grips":grips,"support_local":Vector3.ZERO,"grip_midpoint":midpoint,
		"axes":"Z=palm pressing normal; Y=finger length direction","contact_phase":"same_for_pickup_carry_place",
		"handle_clearance":TRAY_HANDLE_Y-TRAY_HANDLE_RADIUS-.035 if kind=="tray" else 0.0,"pose_accepted":false}

func _put(id: String, source_type: String, source_key: String, kind: String, position: Vector3, container: String, extra: Dictionary = {}) -> void:
	if _wanted.has(id): diagnostics.append({"kind":"duplicate_source_id","source_id":id});return
	var record := {"source_id":id,"source_type":source_type,"source_key":source_key,"kind":kind,"position":position,
		"container":container,"holder":"","parent_id":"","yaw":0.0,"quantity":1,"food_fraction":0.0,"state":"","progress":0.0,"style":"folded","textile":"garment","pose_accepted":false}
	record.merge(extra,true)
	if source_type in ["job","equipment"] and life.jobs.has(source_key):
		var batch: Dictionary=life.jobs[source_key]
		record.batch_id=batch.get("batch_id","");record.display_fixture=container
		record.container=batch.get("container","");record.source_holder=batch.get("holder","");record.last_fixture=batch.get("last_fixture","")
	_wanted[id]=record

func _indices(count: int, source: String) -> int:
	if count>MAX_INDIVIDUAL: diagnostics.append({"kind":"quantity_aggregation_not_individual_volume","source":source,"quantity":count})
	return mini(count,MAX_INDIVIDUAL)

func _overflow(count: int, visible: int, source_type: String, key: String, at: Vector3, container: String) -> void:
	if count<=visible: return
	_put(source_type+":"+key+":overflow",source_type,key,"storage_bundle",at,container,{"quantity":count-visible,"state":"aggregate_unreviewed"})

func _stock() -> void:
	var inv: Dictionary=life.inventory
	var count: int=int(inv.get("ingredients",0));var visible: int=_indices(count,"ingredients")
	for i in visible: _put("inventory:ingredients:%d"%i,"inventory","ingredients","ingredient",_support("fridge")+_front("fridge")*Vector3((i%3-1)*.17,.002+floori(i/3.0)*.095,0),"fridge",{"state":"stored_raw"})
	_overflow(count,visible,"inventory","ingredients",_at("fridge",Vector3(0,1.3,0)),"fridge")
	count=int(inv.get("prepared_servings",0));visible=_indices(count,"prepared_servings")
	for i in visible: _put("inventory:prepared_servings:%d"%i,"inventory","prepared_servings","food_portion",_pan_point(i),"stove",{"state":"prepared","food_fraction":1.0})
	_overflow(count,visible,"inventory","prepared_servings",_pan_point(0),"stove")
	var excluded: Array=[]
	for key in life.jobs:
		if life.jobs[key].kind=="eat": excluded.append(str(key).trim_prefix("eat:"))
	var seats: Array=[]
	for id in _resident_places:
		if id not in excluded: seats.append(_resident_places[id].dining_seat)
	count=int(inv.get("table_servings",0));visible=_indices(count,"table_servings")
	for i in visible:
		var at: Vector3=_plate_place(seats[i]) if i<seats.size() else _table_extra(i-seats.size())
		_put("inventory:table_servings:%d"%i,"inventory","table_servings","plate",at,"dining_table",{"state":"served","food_fraction":1.0})
	_overflow(count,visible,"inventory","table_servings",_table_extra(0),"dining_table")
	for key in ["clean_dishes","dirty_dishes"]:
		count=int(inv.get(key,0));visible=_indices(count,key)
		var washing: int=int(life.jobs.get("wash_dishes",{}).get("quantity",0)) if key=="dirty_dishes" else 0
		for i in visible:
			var at: Vector3=_dish_point(i+washing) if key=="dirty_dishes" else _clean_dish_point(i)
			_put("inventory:%s:%d"%[key,i],"inventory",key,"plate",at,"sink" if key=="dirty_dishes" else "prep",{"state":"dirty" if key=="dirty_dishes" else "clean"})
		_overflow(count,visible,"inventory",key,_dish_point(0) if key=="dirty_dishes" else _clean_dish_point(0),"sink" if key=="dirty_dishes" else "prep")
	for key in ["clean_laundry","dirty_laundry","washing_laundry","wet_laundry","drying_laundry","dry_laundry"]:
		count=int(inv.get(key,0));visible=_indices(count,key)
		var towel_key: String={"clean_laundry":"clean_towels","dirty_laundry":"dirty_towels","wet_laundry":"wet_towels","dry_laundry":"dry_towels"}.get(key,"")
		var towels: int=int(inv.get(towel_key,0))
		if key=="washing_laundry": towels=int(life.machines.get("wash_cycle",{}).get("towels",0))
		if key=="drying_laundry": towels=int(life.machines.get("dry_cycle",{}).get("towels",0))
		for i in visible:
			var rack: bool=key in ["drying_laundry","dry_laundry"]
			var machine: bool=key in ["washing_laundry","wet_laundry"]
			var dirty_towel: bool=key=="dirty_laundry" and i<towels
			var at: Vector3=_rack_point(i) if rack else _drum_point(i) if machine else _towel_basket_point(i) if dirty_towel else _linen_point(i,key=="dirty_laundry")
			_put("inventory:%s:%d"%[key,i],"inventory",key,"textile",at,"drying_rack" if rack else "washer" if machine else "towel_basket" if dirty_towel else "linen_storage",{"state":key,"style":"hanging" if rack else "loose" if machine else "folded","textile":"towel" if i<towels else "garment"})
		_overflow(count,visible,"inventory",key,_linen_point(0,false),"linen_storage")

func _pan_point(index: int) -> Vector3:
	var size := _v(_definitions.stove.size)
	return _support("stove")+_front("stove")*Vector3(-size.x*.24+(index%2-.5)*.065,.041+floori(index/4.0)*.012,-size.z*.05+(floori(index/2.0)%2-.5)*.065)

func _clean_dish_point(index: int) -> Vector3:
	var parking: Dictionary=_definitions.prep.get("operation_targets",{}).get("dishes",{})
	if parking.has("surface"):return _v(parking.surface)+Vector3.UP*(.003+index*.014)
	var size := _v(_definitions.prep.size)
	return _support("prep")+_front("prep")*Vector3(size.x*.31,.003+index*.014,size.z*.23)

func _dish_point(index: int) -> Vector3:
	return _support("sink")+Vector3(0,.002+index*.014,0)

func _plate_place(seat: String) -> Vector3:
	var table: Dictionary=_definitions.dining_table;var size := _v(table.size)
	var direction := _v(_definitions[seat].position)-_v(table.position);direction.y=0;direction=direction.normalized()
	return _support("dining_table")+Vector3(direction.x*(size.x*.5-PLATE_RADIUS-.06),.003,direction.z*(size.z*.5-PLATE_RADIUS-.04))

func _table_extra(index: int) -> Vector3:
	return _support("dining_table")+Vector3((index%2-.5)*.23,.003+floori(index/2.0)*.055,-.27)

func _drum_point(index: int) -> Vector3:
	var f: Dictionary=_definitions.washer;var size := _v(f.size)
	if absf(_front("washer").z.x)>.7: size=Vector3(size.z,size.y,size.x)
	return _support("washer")+_front("washer")*Vector3((index%2-.5)*.13,.010+floori(index/2.0)*.055,size.z*.5-.070)

func _linen_point(index: int, dirty: bool) -> Vector3:
	var f: Dictionary=_definitions.linen_storage
	var level: int=0 if dirty else 1+posmod(floori(index/4.0),3)
	var pitch: float=(float(f.size[1])-.27)/4
	return _support("linen_storage")+_front("linen_storage")*Vector3((index%2-.5)*float(f.size[0])*.40,.0025+(level-1)*pitch+(floori(index/2.0)%2)*.0325,0)

func _towel_basket_point(index: int) -> Vector3:
	return _support("towel_basket")+Vector3(0,.002+index*.0325,0)

func _rack_point(index: int) -> Vector3:
	var f: Dictionary=_definitions.drying_rack
	return _at("drying_rack",Vector3(-float(f.size[0])*.39+float(index%6)*float(f.size[0])*.156,float(f.size[1])-.065,(-.08 if index<6 else .08)))

func _active_job_task(key: String, job: Dictionary) -> Dictionary:
	var owner: String=job.get("reserved_by","")
	if owner.is_empty() or not life.people.has(owner): return {}
	var task: Dictionary=life.task_for(owner)
	return task if task.get("job_key")==key and task.get("started_effects",false) and task.get("status") not in ["cancelled","completed"] else {}

func _carrier(key: String, job: Dictionary, _task: Dictionary, kind: String, source: String) -> String:
	var id := "job:"+key+":carrier"
	# Holder/container/position belong to the real batch, including after cancel
	# and while the next owner is only travelling to pick it up.
	var holder: String=job.get("holder","")
	var at: Vector3=job.get("position",_at(source) if _definitions.has(source) else Vector3.ZERO)
	var framed: bool=has_carry_frame(holder)
	var supported: bool=not holder.is_empty() and (framed or sockets.has(holder) and sockets[holder].has("L"))
	if not holder.is_empty(): diagnostics.append({"kind":"carry_pose_not_accepted","actor":holder,"source":key,"bone_attachment":supported and not framed,"actor_frame":framed,"two_hand_pose":false,"grip":"local surface frames declared; skin contact not yet measured"})
	_put(id,"equipment",key,kind,at,source,{"quantity":0,"holder":holder if supported else "","requested_holder":holder,"hand":"L","state":"source_job_equipment","yaw":_front(source).get_euler().y if _definitions.has(source) else 0.0,
		"batch_id":job.get("batch_id",""),"render_visible":(holder.is_empty() or supported) and not (holder.is_empty() and source in ["dining_table","drying_rack"])})
	return id

func _tray_slot(index: int) -> Vector3:
	var slots: Array=[Vector3(-.12,.015,.075),Vector3(.12,.015,.075),Vector3(0,.015,-.105)]
	return slots[index%3]+Vector3.UP*floori(index/3.0)*.055

func _jobs() -> void:
	for key in life.jobs:
		var job: Dictionary=life.jobs[key]
		if not job.get("started_effects",false) or int(job.get("quantity",0))<=0: continue
		var count: int=int(job.quantity);var visible: int=_indices(count,"job:"+key)
		var task: Dictionary=_active_job_task(key,job)
		var source: String=job.get("container","")
		if source.is_empty(): source=job.get("last_fixture",job.get("source_fixture",""))
		var progress: float=clampf(float(job.phase_progress)/maxf(.001,float(life.rules.actions[job.kind].phases[int(job.phase_index)].minutes)),0,1)
		match str(job.kind):
			"cook":
				var hot: bool=int(job.phase_index)==2 and float(job.phase_progress)>0 and source=="stove" and str(job.get("holder","")).is_empty()
				var carrier := ""
				if not str(job.get("holder","")).is_empty(): carrier=_carrier(key,job,task,"basket",source if _definitions.has(source) else "prep")
				for i in visible:
					var at: Vector3=_pan_point(i) if hot else job.get("position",_at(source if _definitions.has(source) else "prep"))+_front(source if _definitions.has(source) else "prep")*Vector3((i%3-1)*.11,.025,0)
					_put("job:%s:%d"%[key,i],"job",key,"food_portion" if hot else "ingredient",at,source,{"parent_id":carrier,"parent_offset":Vector3((i%3-1)*.09,.05,0),"state":"cooking_not_edible" if hot else "raw_in_progress","food_fraction":1.0 if hot else 0.0,"progress":progress})
			"serve":
				var carrier := _carrier(key,job,task,"tray",source if _definitions.has(source) else "stove")
				var at_table: bool=source=="dining_table" and str(job.get("holder","")).is_empty()
				var placed: int=int(floor(progress*count)) if int(job.phase_index)==1 and at_table else 0
				var seats: Array=[]
				for id in _resident_places: seats.append(_resident_places[id].dining_seat)
				for i in visible:
					var at: Vector3=(_plate_place(seats[i]) if i<seats.size() else _table_extra(i-seats.size())) if i<placed else _table_extra(i)
					_put("job:%s:%d"%[key,i],"job",key,"plate",at,"dining_table" if at_table else source,{"parent_id":"" if at_table else carrier,"parent_offset":_tray_slot(i),"state":"served_pending_transfer" if i<placed else "plated_prepared","food_fraction":1.0,"progress":progress})
			"eat":
				var actor: String=str(key).trim_prefix("eat:")
				if not _resident_places.has(actor): continue
				_put("job:%s:0"%key,"job",key,"plate",_plate_place(_resident_places[actor].dining_seat),"dining_table",{"state":"partially_eaten","food_fraction":1.0-progress,"progress":progress,"meal_owner":actor})
			"wash_dishes":
				for i in visible: _put("job:%s:%d"%[key,i],"job",key,"plate",_dish_point(i),"sink",{"state":"washing","progress":progress})
			"laundry","hang_laundry":
				var carrier := _carrier(key,job,task,"basket",source if _definitions.has(source) else "washer")
				var held: bool=not str(job.get("holder","")).is_empty()
				var moved: int=int(floor(progress*count)) if int(job.phase_index)==1 and not held else 0
				for i in visible:
					var hanging: bool=not held and source=="drying_rack" and job.kind=="hang_laundry"
					var finished: bool=i<moved or hanging
					var at: Vector3=_rack_point(i) if hanging else _drum_point(i)
					_put("job:%s:%d"%[key,i],"job",key,"textile",at,"drying_rack" if hanging else "washer" if finished else source,{"parent_id":"" if finished else carrier,"parent_offset":Vector3((i%2-.5)*.15,.04+floori(i/2.0)*.045,0),"state":"wet_laundry" if job.kind=="hang_laundry" else "dirty_laundry","style":"hanging" if hanging else "folded","textile":"towel" if i<int(job.get("towels",0)) else "garment","progress":progress})
			"fold_laundry":
				for i in visible: _put("job:%s:%d"%[key,i],"job",key,"textile",_linen_point(i,false),"linen_storage",{"state":"folding","textile":"towel" if i<int(job.get("towels",0)) else "garment","progress":progress})
			"shop":
				var carrier := _carrier(key,job,task,"basket",source)
				for i in visible: _put("job:%s:%d"%[key,i],"job",key,"ingredient",job.get("position",Vector3.ZERO),source,{"parent_id":carrier,"parent_offset":Vector3((i%3-1)*.10,.04+floori(i/3.0)*.08,0),"state":"purchased_not_stored"})
			"bath":
				var holder: String=job.get("holder","")
				var supported: bool=not holder.is_empty() and (has_carry_frame(holder) or sockets.has(holder) and sockets[holder].has("R"))
				for i in visible: _put("job:%s:%d"%[key,i],"job",key,"textile",job.get("position",_support("towel_basket"))+Vector3.UP*i*.0325,source,{"state":"body_use_pose_pending","textile":"towel","holder":holder if supported else "","requested_holder":holder,"hand":"R","render_visible":holder.is_empty() or supported})
				if visible>0 and not holder.is_empty(): diagnostics.append({"kind":"bath_towel_pose_not_accepted","source":key,"bone_attachment":supported})
		_overflow(count,visible,"job",key,_at(source) if _definitions.has(source) else Vector3.ZERO,source)

func _projects() -> void:
	for actor in life.people:
		var p: Dictionary=life.people[actor]
		var history: Dictionary=p.get("life_history",{})
		var projects: Dictionary=history.get("projects",{})
		var items: Array=p.get("biography",{}).get("treasured_items",[])
		for item in items:
			var project: Dictionary={}
			for candidate in projects.values():
				if candidate.get("source_item_id")==item.id: project=candidate;break
			var location: String=_surface(project.get("fixture",item.fixture))
			if location.is_empty(): continue
			var model_base: bool=item.kind=="model_base"
			var f: Dictionary=_definitions[location];var size := _v(f.size)
			var support: float=float(f.get("seat_height",size.y))+.002
			if f.type=="storage": support=minf(.95,size.y*.55) # inside its real storage, not perched above the cupboard
			var offset := Vector3(0,support,0)
			if f.type=="desk": offset=Vector3(size.x*.12,support,-size.z*.08) if model_base else Vector3(-size.x*.30,support,size.z*.24)
			var at: Vector3=_at(location,offset)
			_put("item:"+str(item.id),"authored_item",str(item.id),"model_base" if model_base else "notebook",at,location,{"state":"initial_possession","quantity":1,"project_minutes":float(project.get("minutes",0)),"owner":actor})
			if model_base:
				for node in _initial_models:
					if is_instance_valid(node): _hide(node)
			var artifact: Dictionary=project.get("artifact",{})
			if not artifact.is_empty() and bool(project.get("completed",false)) and float(artifact.get("completed_at",INF))<=life.elapsed:
				_put("artifact:"+str(artifact.id),"artifact",str(artifact.id),"town_model" if artifact.kind=="town_model" else "project_sheet",at+Vector3(0,.011,0),location,{"state":"actually_completed","owner":actor,"source_project":artifact.get("source_project",""),"parent_id":"item:"+str(item.id) if model_base else "","parent_offset":Vector3(0,.018,0)})
		if history.get("tools_out",false):
			var location: String=_surface(history.get("tools_fixture",""))
			if not location.is_empty(): _put("tools:"+actor,"project_tools",str(history.get("tools_project","")),"tools",_at(location,Vector3(.18,float(_definitions[location].get("seat_height",_definitions[location].size[1]))+.035,.08)),location,{"quantity":0,"state":"actual_tools_out","owner":actor})

func sync(delta: float = 0.0) -> void:
	if not _configured or not is_instance_valid(house) or life==null or not is_finite(delta) or delta<0: return
	global_transform=house.global_transform
	diagnostics.clear();_wanted.clear()
	_stock();_jobs();_projects()
	for node in _pan_lids:
		if is_instance_valid(node): node.visible=int(life.inventory.get("prepared_servings",0))==0 and not life.jobs.has("cook")
	for id in objects.keys():
		if not _wanted.has(id): _delete_object(id)
	# Equipment parents first, followed by every actual quantity-slot object.
	var ids: Array=_wanted.keys()
	ids.sort_custom(func(a,b):
		var first: int=0 if _wanted[a].source_type=="equipment" else 1 if _wanted[a].source_type=="authored_item" else 2
		var last: int=0 if _wanted[b].source_type=="equipment" else 1 if _wanted[b].source_type=="authored_item" else 2
		return first<last if first!=last else str(a)<str(b))
	for id in ids: _apply(id,_wanted[id])

func _delete_object(id: String) -> void:
	if not objects.has(id): return
	var node: Node3D=objects[id].node
	if is_instance_valid(node):
		for other in objects:
			var child: Node3D=objects[other].node
			if other!=id and is_instance_valid(child) and child.get_parent()==node: child.reparent(self,true)
		if node.get_parent()!=null: node.get_parent().remove_child(node)
		node.queue_free()
	objects.erase(id)

func _apply(id: String, description: Dictionary) -> void:
	var appearance: String=str(description.kind)+":"+str(description.style)+":"+str(description.textile)+":"+str(description.state in ["wet_laundry","washing_laundry","drying_laundry"])+":"+str(description.state=="dirty_laundry")
	if objects.has(id) and objects[id].appearance!=appearance: _delete_object(id)
	var node: Node3D
	if objects.has(id): node=objects[id].node
	else:
		node=Node3D.new();node.name=id.replace(":","_").replace("/","_");add_child(node);_make_visual(node,description)
	var parent: Node3D=self
	var local := Transform3D(Basis(Vector3.UP,float(description.yaw)),description.position)
	if not str(description.holder).is_empty():
		if has_carry_frame(description.holder):
			parent=_carry_anchors[description.holder];local=Transform3D.IDENTITY
		elif sockets.get(description.holder,{}).has(description.hand):
			var socket: Dictionary=sockets[description.holder][description.hand]
			parent=socket.node
			var basis: Basis=socket.rest_basis.inverse()
			var contract: Dictionary=grips_for(description.kind)
			var grip: Vector3=contract.get("local_grips",{}).get(description.hand,Transform3D.IDENTITY).origin
			local=Transform3D(basis,socket.palm_local-basis*grip)
			var inherited: Vector3=parent.global_basis.get_scale()
			if minf(inherited.x,minf(inherited.y,inherited.z))>.0001: local.basis=local.basis.scaled(Vector3.ONE/inherited)
	elif not str(description.parent_id).is_empty() and objects.has(description.parent_id):
		parent=objects[description.parent_id].node;local=Transform3D(Basis.IDENTITY,description.get("parent_offset",Vector3.ZERO))
	if node.get_parent()!=parent: node.reparent(parent,false)
	node.transform=local;node.visible=bool(description.get("render_visible",true))
	node.set_meta("source_id",id);node.set_meta("source_type",description.source_type);node.set_meta("quantity",description.quantity)
	var record: Dictionary=description.duplicate(true);record.node=node;record.appearance=appearance;objects[id]=record
	if description.kind=="plate":
		var food: Node3D=node.get_node("Food");food.visible=float(description.food_fraction)>.0001
		var remaining: float=maxf(.001,float(description.food_fraction))
		food.scale=Vector3(sqrt(remaining),maxf(.05,remaining),sqrt(remaining))
		var stain: Node3D=node.get_node("Stains");stain.visible=description.state in ["dirty","washing"]
		stain.scale=Vector3.ONE*maxf(.001,1.0-float(description.progress)) if description.state=="washing" else Vector3.ONE

func _make_visual(node: Node3D, record: Dictionary) -> void:
	var ceramic := _paint("ceramic","e9dfc8")
	match str(record.kind):
		"plate":
			_lathe(node,"Dish",[Vector2(0,.006),Vector2(.064,.006),Vector2(PLATE_RADIUS,.018),Vector2(PLATE_RADIUS,.012),Vector2(.063,0),Vector2(0,0)],Vector3.ZERO,ceramic)
			var food := Node3D.new();food.name="Food";node.add_child(food)
			_sphere(food,"CookedPortion",Vector3(0,.024,0),Vector3(.13,.027,.12),_paint("meal","c9995e"))
			for index in 3: _sphere(food,"Vegetable",Vector3((index-1)*.028,.039,(index%2-.5)*.026),Vector3(.024,.018,.022),_paint("vegetable_%d"%index,["8b9f6d","c48255","d2ba7b"][index]))
			var stains := Node3D.new();stains.name="Stains";node.add_child(stains)
			for index in 3: _sphere(stains,"SauceTrace",Vector3((index-1)*.023,.010,(index%2-.5)*.035),Vector3(.026,.002,.016),_paint("stain","b39a6d"))
		"ingredient":
			_box(node,"PantryParcel",Vector3(0,.035,0),Vector3(.10,.07,.085),_paint("parcel","c9bb95"))
			_sphere(node,"Produce",Vector3(.016,.080,0),Vector3(.045,.052,.046),_paint("produce","8b9f6d"))
		"food_portion":
			_sphere(node,"Portion",Vector3(0,.009,0),Vector3(.055,.019,.05),_paint("cooking" if record.state=="cooking_not_edible" else "meal","b5ac71" if record.state=="cooking_not_edible" else "c9995e"))
		"textile":
			var cloth := _cloth(record.state in ["wet_laundry","washing_laundry","drying_laundry"],record.state=="dirty_laundry",record.textile=="towel")
			if record.style=="hanging":
				if record.textile=="towel": _box(node,"HangingTowel",Vector3(0,-.27,0),Vector3(.23,.54,.015),cloth)
				else:
					_box(node,"HangingShirt",Vector3(0,-.20,0),Vector3(.18,.35,.015),cloth)
					for side in [-1,1]:
						var sleeve := _box(node,"Sleeve",Vector3(side*.10,-.11,0),Vector3(.065,.12,.015),cloth);sleeve.rotation.z=side*.4
				_box(node,"RailFold",Vector3(0,-.015,0),Vector3(.23,.03,.045),cloth)
				for side in [-1,1]: _box(node,"Peg",Vector3(side*.075,-.015,.018),Vector3(.018,.052,.022),_paint("peg","b9956d"))
			elif record.style=="loose": _sphere(node,"LooseMachineCloth",Vector3(0,.03,0),Vector3(.13,.06,.11),cloth)
			else:
				_box(node,"FoldedCloth",Vector3(0,.016,0),Vector3(.20,.032,.14),cloth)
				_box(node,"FoldEdge",Vector3(0,.022,.055),Vector3(.20,.018,.035),cloth)
		"tray","basket":
			var size := Vector3(.56,.035,.40) if record.kind=="tray" else Vector3(.42,.23,.31)
			var wood := _paint("basket","b29164")
			_box(node,"Bottom",Vector3(0,.009,0),Vector3(size.x,.018,size.z),wood)
			for side in [-1,1]:
				_box(node,"Side",Vector3(side*(size.x*.5-.012),size.y*.5,0),Vector3(.024,size.y,size.z),wood)
				_box(node,"End",Vector3(0,size.y*.5,side*(size.z*.5-.012)),Vector3(size.x,size.y,.024),wood)
			if record.kind=="tray":
				for side in [-1,1]:
					var handle := Node3D.new();handle.name="RaisedHandleL" if side==1 else "RaisedHandleR";node.add_child(handle)
					for z in [-.095,.095]:
						_box(handle,"Mount",Vector3(side*.285,.027,z),Vector3(.060,.025,.030),wood)
						_box(handle,"Post",Vector3(side*TRAY_HANDLE_X,.0675,z),Vector3(.018,.095,.018),wood)
					var bar: MeshInstance3D=_cylinder(handle,"GripBar",Vector3(side*TRAY_HANDLE_X,TRAY_HANDLE_Y,0),TRAY_HANDLE_RADIUS,.21,wood)
					bar.rotation.x=PI*.5
		"model_base": _box(node,"OriginalModelBase",Vector3(0,.008,0),Vector3(.28,.016,.20),_paint("model_base","bbac83"))
		"town_model":
			for index in 4:
				var at := Vector3((index%2-.5)*.11,.028,(floori(index/2.0)-.5)*.08)
				_box(node,"CompletedModelHouse",at,Vector3(.06,.055,.05),_paint("paper","e5d6b4"))
				var roof := _box(node,"ModelRoof",at+Vector3.UP*.032,Vector3(.068,.016,.058),_paint("model_roof","a97b5b"));roof.rotation.z=.14 if index%2 else -.14
		"notebook","project_sheet":
			_box(node,"Paper",Vector3(0,.004,0),Vector3(.20,.008,.15),_paint("paper","e5d6b4"))
			if record.kind=="notebook": _box(node,"NotebookCover",Vector3(0,.001,0),Vector3(.21,.003,.16),_paint("cover","8b9f94"))
			else:
				for index in 3: _box(node,"ActualDesignMark",Vector3((index-1)*.052,.009,0),Vector3(.04,.002,.07),_paint("work_mark_%d"%index,["91a59a","c4a171","afa78b"][index]))
		"tools":
			for index in 3:
				var pencil := _cylinder(node,"Pencil",Vector3(index*.024,.008,0),.004,.12,_paint("pencil_%d"%index,["af785c","7c9991","bdab73"][index]));pencil.rotation.z=PI*.5
		"storage_bundle": _box(node,"AggregateSourceContainer",Vector3(0,.045,0),Vector3(.16,.09,.14),_paint("aggregate","b9ac8c"))

func manifest() -> Dictionary:
	var result := {}
	for id in objects:
		var record: Dictionary=objects[id].duplicate()
		record.erase("node");record.erase("appearance");result[id]=record
	return result

func represented_quantity(source_type: String, source_key: String) -> int:
	var count := 0
	for record in objects.values():
		if record.source_type==source_type and record.source_key==source_key: count+=int(record.quantity)
	return count

func pose_for(actor: String) -> Dictionary:
	for record in objects.values():
		if record.holder!=actor: continue
		var contract: Dictionary=grips_for(record.kind)
		if contract.is_empty(): continue
		var world: Transform3D=record.node.global_transform
		var local_grips: Dictionary=contract.local_grips
		var world_grips: Dictionary = {}
		for side in local_grips: world_grips[side]=world*local_grips[side]
		var framed: bool=has_carry_frame(actor)
		var result: Dictionary={"source_id":record.source_id,"job_key":record.source_key,"kind":record.kind,"holder":actor,"hand":record.hand,
			"object_transform":world,"object_world":world,"local_grips":local_grips,"grips":world_grips,"world_grips":world_grips.duplicate(),
			"support_local":contract.support_local,"grip_midpoint":contract.grip_midpoint,"attachment":"ActorCarryFrame" if framed else "BoneAttachment3D","override_pose":false,
			"pose_accepted":false,"reason":"Actor-frame carrying is declared; skin, supporting-hand and release contacts still require measurement." if framed else "Legacy socket attachment; surface grip frames alone do not prove skin contact."}
		if local_grips.has("L"): result.left_grip=local_grips.L.origin
		if local_grips.has("R"): result.right_grip=local_grips.R.origin
		return result
	return {}

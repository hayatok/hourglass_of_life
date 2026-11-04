class_name HouseholdKitchenFixtures
extends Node3D
const KITCHEN=preload("res://game/foundation/household_kitchen.gd")

# Moving kitchen hardware is rendered from HouseholdDay.access. It owns no
# clock, inventory, reservation or ready flag. Actual cavity/door geometry has
# matching box collisions, replacing the prototype's filled appliance body.
var house: LivingHouse
var life: HouseholdDay
var drawer: Node3D
var fridge_root: Node3D
var rack: Node3D
var _front := Basis.IDENTITY
var _open_offset := Vector3.ZERO
var _prior_art: Node3D
var _prior_art_visible := true
var _prior_shapes: Array = []
var _materials := {}
var navigation: HomeNavigation
var _closed_drawer_rect := Rect2()

func configure(home: LivingHouse, day: HouseholdDay, paths: HomeNavigation = null) -> bool:
	if home==null or day==null or not is_inside_tree() or not home.fixtures.has("fridge") or not home.fixtures.has("prep"):return false
	var record: Dictionary=home.fixtures.fridge.definition
	var spec: Variant=record.get("drawer_geometry")
	if not spec is Dictionary or not day.plan.get("household_access",{}).has("fridge:drawer"):return false
	for key in ["shelf_y","shelf_thickness","front_bottom_y","front_top_y","handle_y","handle_span","handle_radius","handle_z","case_thickness"]:
		if not (spec.get(key) is float or spec.get(key) is int) or not is_finite(float(spec[key])) or spec[key]<=0:return false
	if not (spec.get("grasp_pitch",0) is float or spec.get("grasp_pitch",0) is int) or not is_finite(float(spec.get("grasp_pitch",0))) or absf(float(spec.get("grasp_pitch",0)))>PI/6:return false
	if not spec.get("open_offset") is Array or spec.open_offset.size()!=3:return false
	if spec.open_offset!=day.plan.household_access["fridge:drawer"].open_offset:return false
	for value in spec.open_offset:
		if not (value is float or value is int) or not is_finite(float(value)):return false
	if is_instance_valid(fridge_root):return false
	house=home;life=day;navigation=paths;global_transform=home.global_transform
	_front=LivingHouse.fixture_basis(record);_open_offset=_front.inverse()*_v(spec.open_offset)
	_prior_art=home.fixtures.fridge.node.get_node_or_null("Art")
	if is_instance_valid(_prior_art):_prior_art_visible=_prior_art.visible;_prior_art.hide()
	var prototype: Node=home.fixtures.fridge.node.get_node_or_null("Body")
	if prototype!=null:
		for shape in prototype.find_children("*","CollisionShape3D",true,false):
			_prior_shapes.append({"shape":weakref(shape),"disabled":shape.disabled});shape.disabled=true
	fridge_root=Node3D.new();fridge_root.name="AccessibleFridge";add_child(fridge_root)
	fridge_root.transform=Transform3D(_front,_v(record.position))
	_build_fridge(_v(record.size),spec)
	_closed_drawer_rect=_projected_rect(drawer)
	_build_rack(home.fixtures.prep.definition)
	sync()
	return true

func _projected_rect(node: Node3D) -> Rect2:
	var result := Rect2();var begun := false
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var aabb: AABB=mesh.mesh.get_aabb()
		for index in 8:
			var corner: Vector3=house.to_local(mesh.to_global(aabb.get_endpoint(index)))
			var point := Vector2(corner.x,corner.z)
			if not begun:result=Rect2(point,Vector2.ZERO);begun=true
			else:result=result.expand(point)
	return result

func drawer_floor_rect() -> Rect2:
	var result: Rect2=_closed_drawer_rect
	var offset: Vector3=_front*drawer.position
	result.position+=Vector2(offset.x,offset.z)
	return result

func _exit_tree() -> void:
	if navigation!=null:navigation.clear_transient_rect("fridge:drawer")
	if not is_instance_valid(house) or not house.is_inside_tree() or house.is_queued_for_deletion():return
	if is_instance_valid(_prior_art):_prior_art.visible=_prior_art_visible
	for previous in _prior_shapes:
		var shape: CollisionShape3D=previous.shape.get_ref()
		if shape!=null:shape.set_deferred("disabled",previous.disabled)

func _v(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])

func _material(key: String, color: String, roughness: float = .75) -> StandardMaterial3D:
	if _materials.has(key):return _materials[key]
	var result := StandardMaterial3D.new();result.albedo_color=Color(color);result.roughness=roughness
	_materials[key]=result;return result

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size
	var node := MeshInstance3D.new();node.name=label;node.mesh=mesh;node.material_override=material;node.position=at;parent.add_child(node)
	var solid := StaticBody3D.new();solid.name="Solid";solid.set_meta("fixture_id","fridge" if parent!=rack else "prep");node.add_child(solid)
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=size;shape.shape=box;solid.add_child(shape)
	return node

func _rod(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=16
	var node := MeshInstance3D.new();node.name=label;node.mesh=mesh;node.material_override=material;node.position=(a+b)*.5
	node.quaternion=Quaternion(Vector3.UP,(b-a).normalized());parent.add_child(node)
	var solid := StaticBody3D.new();solid.name="Solid";solid.set_meta("fixture_id","fridge");node.add_child(solid)
	var collision := CollisionShape3D.new();var cylinder := CylinderShape3D.new();cylinder.radius=radius;cylinder.height=mesh.height;collision.shape=cylinder;solid.add_child(collision)
	return node

func _build_fridge(size: Vector3, spec: Dictionary) -> void:
	var enamel := _material("enamel","e5e4d4",.42)
	var liner := _material("liner","e1e4db",.60)
	var seal := _material("seal","7d8980")
	var steel := _material("steel","a4b1a8",.35)
	var t: float=spec.case_thickness
	for side in [-1,1]:_box(fridge_root,"Side",Vector3(side*(size.x-t)*.5,size.y*.5,0),Vector3(t,size.y,size.z),enamel)
	_box(fridge_root,"Back",Vector3(0,size.y*.5,-(size.z-t)*.5),Vector3(size.x-2*t,size.y,t),liner)
	for y in [t*.5,size.y-t*.5]:_box(fridge_root,"End",Vector3(0,y,0),Vector3(size.x-2*t,t,size.z-2*t),enamel)
	var bottom: float=spec.front_bottom_y;var top: float=spec.front_top_y
	for y in [bottom-.025,top+.025]:_box(fridge_root,"CompartmentDivider",Vector3(0,y,0),Vector3(size.x-2*t,.03,size.z-2*t),liner)
	_box(fridge_root,"LowerFreezerDoor",Vector3(0,bottom*.5,size.z*.5-.012),Vector3(size.x-.025,bottom-.04,.026),enamel)
	_box(fridge_root,"UpperRefrigeratorDoor",Vector3(0,(top+size.y)*.5,size.z*.5-.012),Vector3(size.x-.025,size.y-top-.025,.026),enamel)
	_box(fridge_root,"UpperHandle",Vector3(-size.x*.34,top+.22,size.z*.5+.013),Vector3(.025,.28,.022),steel)
	_box(fridge_root,"PinnedFamilyNote",Vector3(size.x*.10,top+.32,size.z*.5+.006),Vector3(.15,.19,.003),_material("paper","f0e5cb"))
	drawer=Node3D.new();drawer.name="RefrigeratedDrawer";fridge_root.add_child(drawer)
	var shelf: float=spec.shelf_y;var thick: float=spec.shelf_thickness
	_box(drawer,"ActualShelf",Vector3(0,shelf-thick*.5,0),Vector3(size.x-2*t-.012,thick,size.z-2*t-.012),liner)
	for side in [-1,1]:_box(drawer,"InnerSide",Vector3(side*(size.x-2*t-.025)*.5,shelf+.065,0),Vector3(.012,.13,size.z-2*t-.012),liner)
	_box(drawer,"InnerBack",Vector3(0,shelf+.065,-(size.z-2*t-.025)*.5),Vector3(size.x-2*t-.025,.13,.012),liner)
	_box(drawer,"InsulatedFront",Vector3(0,(bottom+top)*.5,size.z*.5-.012),Vector3(size.x-.025,top-bottom,.026),enamel)
	_box(drawer,"DrawerSeal",Vector3(0,top-.006,size.z*.5-.028),Vector3(size.x-.045,.012,.012),seal)
	var handle := Vector3(0,float(spec.handle_y),float(spec.handle_z))
	_rod(drawer,"Handle",handle-Vector3.RIGHT*float(spec.handle_span)*.5,handle+Vector3.RIGHT*float(spec.handle_span)*.5,float(spec.handle_radius),steel)
	for side in [-1,1]:_box(drawer,"HandleMount",handle+Vector3(side*float(spec.handle_span)*.40,0,-.019),Vector3(.016,.025,.04),steel)
	var lamp := OmniLight3D.new();lamp.name="DrawerLamp";lamp.position=Vector3(0,top-.07,-size.z*.30);lamp.omni_range=1.1;lamp.light_energy=.18;lamp.light_color=Color("fff0d2");fridge_root.add_child(lamp)

func _build_rack(record: Dictionary) -> void:
	var target: Dictionary=record.get("operation_targets",{}).get("dishes",{})
	if not target.get("surface") is Array or not target.get("unit_frames") is Array or target.unit_frames.is_empty():return
	rack=Node3D.new();rack.name="ActualPlateRack";add_child(rack)
	var center := _v(target.surface)
	var wood := _material("rack","b39470")
	# Actual rails touch each vertical plate's lower circular rim at .862m.
	_box(rack,"FrontRail",center+Vector3(0,.006,.055),Vector3(.30,.012,.018),wood)
	_box(rack,"BackRail",center+Vector3(0,.006,-.055),Vector3(.30,.012,.018),wood)
	_box(rack,"CradleRail",center+Vector3(0,.006,0),Vector3(.30,.012,.018),wood)
	var first: Vector3=_v(target.unit_frames[0].position)
	var pitch: float=absf(first.x-_v(target.unit_frames[1].position).x) if target.unit_frames.size()>1 else .027
	var profile: Array=KITCHEN.plate_profile()
	var thickness := 0.0
	for ring: Vector2 in profile:thickness=maxf(thickness,ring.y)
	var plate_basis: Basis=LivingHouse.fixture_basis(record)*Basis.from_euler(_v(target.unit_frames[0].rotation_degrees)*PI/180)
	var middle: float=first.x+(plate_basis*Vector3.UP*thickness*.5).x
	for i in range(target.unit_frames.size()+1):
		var x: float=middle+pitch*.5-float(i)*pitch
		_box(rack,"SlotSeparator",Vector3(x,center.y+.036,center.z),Vector3(.006,.072,.14),wood)

func sync() -> void:
	if drawer==null or life==null:return
	var fraction: float=float(life.access.get("fridge:drawer",0.0))
	drawer.position=_open_offset*clampf(fraction,0,1)
	if navigation!=null:navigation.set_transient_rect("fridge:drawer",drawer_floor_rect())
	var lamp: OmniLight3D=fridge_root.get_node("DrawerLamp");lamp.visible=fraction>.05

func handle_points() -> Dictionary:
	var result: Dictionary=handle_surface_points()
	if result.is_empty():return result
	# A wrist grasp frame is distinct from the cylinder's geometric normal.
	# Keep its actual surface point fixed; never shift the handle to fit a hand.
	var pitch: float=float(house.fixtures.fridge.definition.drawer_geometry.get("grasp_pitch",0.0))
	for side in result:result[side].basis=result[side].basis*Basis(Vector3.RIGHT,pitch)
	return result

func handle_surface_points() -> Dictionary:
	if drawer==null:return {}
	var spec: Dictionary=house.fixtures.fridge.definition.drawer_geometry
	var result := {}
	for pair in [["L",-.16],["R",.16]]:
		var local := Vector3(float(pair[1]),float(spec.handle_y),float(spec.handle_z)+float(spec.handle_radius))
		result[pair[0]]=Transform3D(drawer.global_basis*Basis(Vector3.UP,PI),drawer.to_global(local))
	return result

class_name HouseholdTools
extends RefCounted

# Native, metre-scale utensils. Root is near the handle grip; +Z points to the
# working end and +Y is up. No body, clock, holder or resource is owned here.
# Public specs are deep copies of private generated data, never mutable aliases.
const KINDS := ["spoon","child_spoon","knife","spatula"]
static var _cache: Dictionary = {}

static func kinds() -> Array:return KINDS.duplicate()

static func create(kind: String) -> Node3D:
	var data := _data(kind)
	if data.is_empty():return null
	var result := Node3D.new();result.name="HouseholdTool_"+kind
	result.set_meta("tool_kind",kind)
	result.set_meta("geometry_source","native_procedural_metres; no generated or paid asset")
	for part in data.parts:
		var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=part.vertices;arrays[Mesh.ARRAY_NORMAL]=part.normals;arrays[Mesh.ARRAY_TEX_UV]=part.uvs
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var instance := MeshInstance3D.new();instance.name=part.name;instance.mesh=mesh;instance.material_override=_material(part.material)
		result.add_child(instance)
	var contacts := Node3D.new();contacts.name="Contacts";result.add_child(contacts)
	for side in ["L","R"]:_marker(contacts,"Grip"+side,data.spec.local_grips[side])
	for feature in data.spec.working_frames:_marker(contacts,str(feature),data.spec.working_frames[feature])
	_marker(contacts,"ParkSupport",Transform3D(Basis.IDENTITY,data.spec.support_local))
	return result

static func spec(kind: String) -> Dictionary:
	var data := _data(kind)
	return data.spec.duplicate(true) if not data.is_empty() else {}

static func palm_target(kind: String, tool_world: Transform3D, side: String = "R") -> Variant:
	var description := spec(kind)
	if description.is_empty() or not _rigid(tool_world) or not description.local_grips.has(side):return null
	return tool_world*description.local_grips[side]

static func world_for_working(kind: String, feature: String, feature_world: Transform3D) -> Variant:
	var description := spec(kind)
	if description.is_empty() or not _rigid(feature_world) or not description.working_frames.has(feature):return null
	return feature_world*description.working_frames[feature].affine_inverse()

static func palm_for_working(kind: String, feature: String, feature_world: Transform3D, side: String = "R") -> Variant:
	var tool_world: Variant=world_for_working(kind,feature,feature_world)
	return palm_target(kind,tool_world,side) if tool_world is Transform3D else null

static func park_on(kind: String, support_world: Transform3D) -> Variant:
	var description := spec(kind)
	if description.is_empty() or not _rigid(support_world):return null
	# support_world is the actual contact anchor/plane, not a guessed tool
	# centre. The measured lowest mesh point maps exactly to this origin.
	return support_world*description.park_transform

static func _rigid(frame: Transform3D) -> bool:
	return frame.is_finite() and absf(frame.basis.determinant()-1)<.001 and absf(frame.basis.x.length()-1)<.001 and absf(frame.basis.y.length()-1)<.001 and absf(frame.basis.z.length()-1)<.001

static func _marker(parent: Node3D, label: String, frame: Transform3D) -> void:
	var marker := Marker3D.new();marker.name=label;marker.transform=frame;parent.add_child(marker)

static func _material(key: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	match key:
		"metal":result.albedo_color=Color("c5cdc7");result.metallic=.72;result.roughness=.32
		"bevel":result.albedo_color=Color("e2e4d7");result.metallic=.62;result.roughness=.27
		"brass":result.albedo_color=Color("ac9469");result.metallic=.45;result.roughness=.42
		"child_grip":result.albedo_color=Color("c98b60");result.roughness=.78
		"working_wood":result.albedo_color=Color("bf9b66");result.roughness=.79
		_:result.albedo_color=Color("805e42");result.roughness=.74
	return result

static func _part(name: String, material: String) -> Dictionary:
	return {"name":name,"material":material,"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uvs":PackedVector2Array()}

static func _triangle(part: Dictionary, a: Vector3, b: Vector3, c: Vector3, outside: Vector3) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared()<.000000000000000001:return
	# Godot uses clockwise front faces. Explicit outward normals remain the
	# lighting surface even for the spoon's inward-facing concave bowl.
	if cross.dot(outside)>0:
		var swap := b;b=c;c=swap
	var normal := outside.normalized()
	for point in [a,b,c]:part.vertices.append(point);part.normals.append(normal);part.uvs.append(Vector2(point.x,point.z))

static func _tube(parts: Array, name: String, material: String, rings: Array, segments: int = 12) -> void:
	var part := _part(name,material)
	for row in range(rings.size()-1):
		var a: Vector4=rings[row];var b: Vector4=rings[row+1]
		for segment in segments:
			var first: float=TAU*segment/segments;var last: float=TAU*(segment+1)/segments
			var aa := Vector3(cos(first)*a.y,a.w+sin(first)*a.z,a.x)
			var ab := Vector3(cos(last)*a.y,a.w+sin(last)*a.z,a.x)
			var ba := Vector3(cos(first)*b.y,b.w+sin(first)*b.z,b.x)
			var bb := Vector3(cos(last)*b.y,b.w+sin(last)*b.z,b.x)
			var mid := (first+last)*.5
			var normal := Vector3(cos(mid)/maxf(.0001,(a.y+b.y)*.5),sin(mid)/maxf(.0001,(a.z+b.z)*.5),0).normalized()
			_triangle(part,aa,ba,bb,normal);_triangle(part,aa,bb,ab,normal)
	for end in [0,rings.size()-1]:
		var ring: Vector4=rings[end];var normal := Vector3.BACK if end>0 else Vector3.FORWARD
		for segment in segments:
			var first: float=TAU*segment/segments;var last: float=TAU*(segment+1)/segments
			_triangle(part,Vector3(0,ring.w,ring.x),Vector3(cos(first)*ring.y,ring.w+sin(first)*ring.z,ring.x),Vector3(cos(last)*ring.y,ring.w+sin(last)*ring.z,ring.x),normal)
	parts.append(part)

static func _spoon_bowl(parts: Array, center_z: float, radius_x: float, radius_z: float, rim_y: float, depth: float, thickness: float) -> void:
	var part := _part("SpoonBowl","metal")
	for lower in [false,true]:
		for row in 4:
			var a: float=float(row)/4;var b: float=float(row+1)/4
			for segment in 20:
				var first: float=TAU*segment/20;var last: float=TAU*(segment+1)/20
				var aa := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,a,first,lower)
				var ab := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,a,last,lower)
				var ba := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,b,first,lower)
				var bb := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,b,last,lower)
				var normal := Vector3(-cos((first+last)*.5)*depth*(a+b)/radius_x,1,-sin((first+last)*.5)*depth*(a+b)/radius_z)
				if lower:normal=-normal
				_triangle(part,aa,ba,bb,normal);_triangle(part,aa,bb,ab,normal)
	for segment in 20:
		var first: float=TAU*segment/20;var last: float=TAU*(segment+1)/20
		var a := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,1,first,false)
		var b := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,1,last,false)
		var c := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,1,last,true)
		var d := _bowl_point(center_z,radius_x,radius_z,rim_y,depth,thickness,1,first,true)
		var normal := Vector3(cos((first+last)*.5),0,sin((first+last)*.5))
		_triangle(part,a,b,c,normal);_triangle(part,a,c,d,normal)
	parts.append(part)

static func _bowl_point(center_z: float, radius_x: float, radius_z: float, rim_y: float, depth: float, thickness: float, radius: float, angle: float, lower: bool) -> Vector3:
	return Vector3(cos(angle)*radius_x*radius,rim_y-depth*(1-radius*radius)-(thickness if lower else 0),center_z+sin(angle)*radius_z*radius)

static func _flat_paddle(parts: Array) -> void:
	var part := _part("SpatulaWorkingHead","working_wood")
	for segment in 20:
		var first: float=TAU*segment/20;var last: float=TAU*(segment+1)/20
		var a := Vector3(cos(first)*.027,.0045,.2025+sin(first)*.0475)
		var b := Vector3(cos(last)*.027,.0045,.2025+sin(last)*.0475)
		var c := Vector3(b.x,-.0045,b.z);var d := Vector3(a.x,-.0045,a.z)
		_triangle(part,Vector3(0,.0045,.2025),a,b,Vector3.UP)
		_triangle(part,Vector3(0,-.0045,.2025),c,d,Vector3.DOWN)
		var normal := Vector3(cos((first+last)*.5),0,sin((first+last)*.5))
		_triangle(part,a,d,c,normal);_triangle(part,a,c,b,normal)
	parts.append(part)

static func _blade(parts: Array) -> void:
	var face := _part("KnifeBlade","metal");var bevel := _part("KnifeCuttingBevel","bevel")
	# Profile points are (Y,Z). The true lower edge is only .6mm thick;
	# the spine is 3.6mm. Both grip regions stay on the separate wood handle.
	var profile := [Vector2(-.020,.050),Vector2(-.020,.200),Vector2(-.008,.235),Vector2(.025,.190),Vector2(.025,.050)]
	var halves := [.0003,.0003,.0003,.0018,.0018]
	for side in [-1,1]:
		var middle := Vector3(side*.0018,.007,.118)
		for index in profile.size():
			var next: int=(index+1)%profile.size()
			var a := Vector3(side*halves[index],profile[index].x,profile[index].y)
			var b := Vector3(side*halves[next],profile[next].x,profile[next].y)
			_triangle(bevel if index==0 else face,middle,a,b,Vector3.RIGHT*side)
	for index in profile.size():
		var next: int=(index+1)%profile.size()
		var a := Vector3(halves[index],profile[index].x,profile[index].y)
		var b := Vector3(halves[next],profile[next].x,profile[next].y)
		var c := Vector3(-b.x,b.y,b.z);var d := Vector3(-a.x,a.y,a.z)
		var normal := Vector3(0,-(b.z-a.z),b.y-a.y).normalized()
		_triangle(face,a,b,c,normal);_triangle(face,a,c,d,normal)
	parts.append(face);parts.append(bevel)

static func _data(kind: String) -> Dictionary:
	if kind not in KINDS:return {}
	if _cache.has(kind):return _cache[kind]
	var parts: Array=[];var working := {};var grip_z := 0.0;var grip_x := .0065
	var rear_support := Vector3.ZERO;var front_support := Vector3.ZERO;var lay := Basis.IDENTITY
	match kind:
		"spoon","child_spoon":
			var child: bool=kind=="child_spoon"
			var back := -.050 if child else -.075;var neck := .043 if child else .064
			grip_x=.0105 if child else .0065
			var grip_y := .007 if child else .0045
			_tube(parts,"GripHandle","child_grip" if child else "wood",[Vector4(back,grip_x*.70,grip_y*.70,0),Vector4(back+.012,grip_x,grip_y,0),Vector4(0,grip_x,grip_y,0),Vector4(neck,grip_x*.55,grip_y*.65,0)])
			_tube(parts,"SpoonNeck","metal",[Vector4(neck-.004,.0032,.0025,0),Vector4(neck+.014,.0030,.0025,.001)])
			var center := .074 if child else .110;var rx := .014 if child else .0185;var rz := .026 if child else .035
			var rim := .004 if child else .0045;var depth := .0078 if child else .0093;var thickness := .0012
			_spoon_bowl(parts,center,rx,rz,rim,depth,thickness)
			working={"tip":Transform3D(Basis.IDENTITY,Vector3(0,rim,center+rz)),"mouth_entry":Transform3D(Basis.IDENTITY,Vector3(0,rim,center+rz)),"food_anchor":Transform3D(Basis.IDENTITY,Vector3(0,rim-depth,center))}
			rear_support=Vector3(0,-grip_y,back+.012);front_support=Vector3(0,rim-depth-thickness,center)
		"knife":
			grip_x=.010;grip_z=-.025
			_tube(parts,"GripHandle","wood",[Vector4(-.075,.008,.010,0),Vector4(-.061,.010,.012,0),Vector4(grip_z,.010,.012,0),Vector4(.030,.009,.011,0)])
			_tube(parts,"KnifeBolster","brass",[Vector4(.030,.012,.014,0),Vector4(.045,.012,.014,0)])
			_blade(parts)
			working={"tip":Transform3D(Basis.IDENTITY,Vector3(0,-.008,.235)),"edge_start":Transform3D(Basis.IDENTITY,Vector3(0,-.020,.060)),"edge_end":Transform3D(Basis.IDENTITY,Vector3(0,-.020,.195)),"cut_edge":Transform3D(Basis.IDENTITY,Vector3(0,-.020,.125))}
			lay=Basis(Vector3.BACK,PI*.5);rear_support=Vector3(-.012,0,.045);front_support=working.tip.origin
		"spatula":
			grip_x=.009
			_tube(parts,"GripHandle","wood",[Vector4(-.090,.0065,.005,0),Vector4(-.074,.009,.0065,0),Vector4(0,.009,.0065,0),Vector4(.055,.0065,.005,0)])
			_tube(parts,"SpatulaShaft","working_wood",[Vector4(.050,.005,.004,0),Vector4(.170,.0065,.004,0)])
			_flat_paddle(parts)
			working={"tip":Transform3D(Basis.IDENTITY,Vector3(0,-.0045,.250)),"scrape":Transform3D(Basis.IDENTITY,Vector3(0,-.0045,.250))}
			rear_support=Vector3(0,-.0065,-.074);front_support=working.tip.origin
	var grips := {}
	for side in ["L","R"]:
		var normal := Vector3.LEFT if side=="L" else Vector3.RIGHT
		# Fingers/knuckles point along the handle toward its working end, so
		# the wrist remains behind the grip rather than below a worktop. This
		# differs deliberately from the raised tray handle's vertical grasp.
		grips[side]=Transform3D(Basis(Vector3.BACK.cross(normal),Vector3.BACK,normal),Vector3(grip_x if side=="L" else -grip_x,0,grip_z))
	var back_at: Vector3=lay*rear_support;var front_at: Vector3=lay*front_support
	var pitch := atan2(front_at.y-back_at.y,front_at.z-back_at.z)
	var parked_basis := Basis(Vector3.RIGHT,pitch)*lay
	var points := PackedVector3Array();var handle_points := PackedVector3Array();var blade_points := PackedVector3Array()
	for part in parts:
		points.append_array(part.vertices)
		if part.name=="GripHandle":handle_points.append_array(part.vertices)
		if str(part.name).begins_with("KnifeBlade") or str(part.name).begins_with("KnifeCutting"):blade_points.append_array(part.vertices)
	var support := Vector3.ZERO;var lowest := INF
	for point in points:
		var y: float=(parked_basis*point).y
		if y<lowest:lowest=y;support=point
	var park := Transform3D(parked_basis,-(parked_basis*support))
	var parked := PackedVector3Array()
	for point in points:parked.append(park*point)
	var description := {"kind":kind,"units":"metres; +Y up,+Z working end; root near real handle grip","local_grips":grips,"working_frames":working,
		"support_local":support,"park_transform":park,"bounds_local":_bounds(points),"parked_bounds":_bounds(parked),"grip_region":_bounds(handle_points),
		"unsafe_regions":{"blade":_bounds(blade_points)} if not blade_points.is_empty() else {},"triangles":points.size()/3,"parts":parts.size(),
		"bounds_method":"all actual generated triangle vertices; no AABB-height contact proxy","contact_status":"geometry only; real character grasp, utensil collision and eating are not certified",
		"mouth_target_contract":"caller supplies measured character mouth frame; palm_for_working composes actual mouth_entry and grip frames without a guessed hand offset"}
	_cache[kind]={"parts":parts,"spec":description}
	return _cache[kind]

static func _bounds(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():return {}
	var low := points[0];var high := points[0]
	for point in points:low=low.min(point);high=high.max(point)
	return {"position":low,"size":high-low,"min":low,"max":high}

extends RefCounted

# Read-only CPU skin probe. prepare() must precede settling frames: modifier
# poses are only final inside skeleton_updated, before Skeleton3D restores them.
# A 6 mm surface band is a separate criterion from reaching a saved pad centroid.
const MINIMUM_FINGER_WEIGHT: float = .85
var _observers: Dictionary = {}
var _geometry: Dictionary = {}

func prepare(actor: Node) -> bool:
	if not is_instance_valid(actor): return false
	var model: Node3D = actor.get("jrpg") as Node3D
	if not is_instance_valid(model) or not model.is_inside_tree(): return false
	var skeleton: Skeleton3D = model.get("skeleton") as Skeleton3D
	if not is_instance_valid(skeleton): return false
	var id: int = model.get_instance_id()
	if _observers.has(id): return true
	_observers[id] = {"model":weakref(model),"skeleton":weakref(skeleton),"poses":[],"worlds":{},"serial":0,"frame":-1}
	skeleton.skeleton_updated.connect(Callable(self,"_capture").bind(id))
	return true

func clear() -> void:
	for id in _observers:
		var skeleton: Skeleton3D = _observers[id].skeleton.get_ref() as Skeleton3D
		var callback: Callable = Callable(self,"_capture").bind(id)
		if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(callback):
			skeleton.skeleton_updated.disconnect(callback)
	_observers.clear()
	_geometry.clear()

func _capture(id: int) -> void:
	var entry: Dictionary = _observers.get(id,{})
	if entry.is_empty(): return
	var skeleton: Skeleton3D = entry.skeleton.get_ref() as Skeleton3D
	var model: Node3D = entry.model.get_ref() as Node3D
	if not is_instance_valid(skeleton) or not is_instance_valid(model): return
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): poses.append(skeleton.get_bone_global_pose(bone))
	entry.poses = poses
	entry.worlds = {}
	# The rendering palette is bone_global_pose * Skin.bind_pose. Its output is
	# mesh-local, so use each displayed MeshInstance3D's world transform once.
	for node in model.find_children("*","MeshInstance3D",true,false):
		var part: MeshInstance3D = node as MeshInstance3D
		entry.worlds[part.get_instance_id()] = part.global_transform
	entry.serial = int(entry.serial)+1
	entry.frame = Engine.get_process_frames()

func sample(actor: Node, finger_name: String, world_point: Vector3) -> Dictionary:
	if finger_name not in ["DEF-finger0.R","DEF-finger1.R"]: return _unsupported("unsupported_finger_name")
	if not world_point.is_finite() or not prepare(actor): return _unsupported("actor_or_query_unavailable")
	var model: Node3D = actor.get("jrpg") as Node3D
	if int(model.get("lod_level"))!=0: return _unsupported("displayed_mesh_is_not_lod0")
	var entry: Dictionary = _observers[model.get_instance_id()]
	if int(entry.serial)==0: return _unsupported("awaiting_post_modifier_pose")
	var skeleton: Skeleton3D = entry.skeleton.get_ref() as Skeleton3D
	var finger: int = skeleton.find_bone(finger_name)
	if finger<0: return _unsupported("missing_finger_bone")
	var nearest: Dictionary = {}
	var distance_squared: float = INF
	var triangle_count: int = 0
	var mesh_count: int = 0
	for node in model.find_children("*","MeshInstance3D",true,false):
		var part: MeshInstance3D = node as MeshInstance3D
		if not part.is_visible_in_tree() or part.mesh==null or part.skin==null: continue
		if part.get_node_or_null(part.skeleton)!=skeleton: continue
		var cache_key: String = "%d:%d:%d:%d"%[part.mesh.get_instance_id(),part.skin.get_instance_id(),skeleton.get_instance_id(),finger]
		if not _geometry.has(cache_key): _geometry[cache_key] = _collect(part.mesh,part.skin,skeleton,finger)
		var geometry: Dictionary = _geometry[cache_key]
		if geometry.surfaces.is_empty(): continue
		if not geometry.reason.is_empty(): return _unsupported(geometry.reason)
		for blend in part.get_blend_shape_count():
			if absf(part.get_blend_shape_value(blend))>.000001: return _unsupported("active_blend_shape_on_finger_mesh")
		if not entry.worlds.has(part.get_instance_id()): return _unsupported("mesh_has_no_final_pose_snapshot")
		var world: Transform3D = entry.worlds[part.get_instance_id()]
		var palette: Array[Transform3D] = []
		for bind in geometry.bones.size():
			var bone: int = geometry.bones[bind]
			if bone<0 or bone>=entry.poses.size(): return _unsupported("invalid_skin_bind")
			palette.append(entry.poses[bone] * part.skin.get_bind_pose(bind))
		mesh_count += 1
		for surface in geometry.surfaces:
			var deformed: Dictionary = {}
			for vertex in surface.vertices:
				var record: Dictionary = surface.vertices[vertex]
				var point: Vector3 = Vector3.ZERO
				# Preserve all original influences, including Haru's mixed weights.
				# Do not normalize or discard the influences of other bones.
				for influence in record.joints.size():
					point += (palette[record.joints[influence]] * record.position) * record.weights[influence]
				deformed[vertex] = world * point
			for triangle in surface.triangles:
				var a: Vector3 = deformed[triangle.indices[0]]
				var b: Vector3 = deformed[triangle.indices[1]]
				var c: Vector3 = deformed[triangle.indices[2]]
				var point: Vector3 = _closest_triangle(world_point,a,b,c)
				var error: float = point.distance_squared_to(world_point)
				triangle_count += 1
				if error>=distance_squared: continue
				distance_squared = error
				nearest = {"point":point,"triangle_world":[a,b,c],"mesh":str(part.name),"surface":surface.index,
					"triangle":triangle.ordinal,"vertex_indices":triangle.indices.duplicate(),
					"minimum_target_weight":triangle.minimum_weight}
	if nearest.is_empty(): return _unsupported("no_eligible_visible_finger_triangles")
	nearest.merge({"supported":true,"distance":sqrt(distance_squared),"triangle_count":triangle_count,"mesh_count":mesh_count,
		"finger_name":finger_name,"query":world_point,"pose_frame":entry.frame,"pose_serial":entry.serial,
		"metric":"unsigned_distance_to_selected_finger_triangles",
		"method":"All-weight CPU skin triangles captured at skeleton_updated; nearest world-space triangle point."})
	return nearest

func _collect(mesh: Mesh, skin: Skin, skeleton: Skeleton3D, finger: int) -> Dictionary:
	var result: Dictionary = {"surfaces":[],"bones":PackedInt32Array(),"reason":""}
	for bind in skin.get_bind_count():
		var bind_name: StringName = skin.get_bind_name(bind)
		result.bones.append(skeleton.find_bone(bind_name) if not bind_name.is_empty() else skin.get_bind_bone(bind))
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size()<=Mesh.ARRAY_INDEX: continue
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: Variant = arrays[Mesh.ARRAY_BONES]
		var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if positions.is_empty(): continue
		if not (joints is PackedInt32Array or joints is PackedFloat32Array): continue
		if not (weights is PackedFloat32Array or weights is PackedFloat64Array): continue
		var influences: int = int(joints.size()/positions.size())
		if influences not in [4,8] or joints.size()!=positions.size()*influences or weights.size()!=joints.size(): continue
		var eligible: Dictionary = {}
		for vertex in positions.size():
			var target_weight: float = 0.0
			var used_joints: PackedInt32Array = PackedInt32Array()
			var used_weights: PackedFloat64Array = PackedFloat64Array()
			var valid: bool = true
			for influence in influences:
				var offset: int = vertex*influences+influence
				var weight: float = float(weights[offset])
				if not is_finite(weight) or weight<0: valid=false;break
				if weight==0: continue
				var bind: int = int(joints[offset])
				if float(joints[offset])!=float(bind) or bind<0 or bind>=result.bones.size() or result.bones[bind]<0: valid=false;break
				used_joints.append(bind);used_weights.append(weight)
				if result.bones[bind]==finger: target_weight += weight
			if valid and target_weight>=MINIMUM_FINGER_WEIGHT:
				eligible[vertex] = {"position":positions[vertex],"joints":used_joints,"weights":used_weights,"target_weight":target_weight}
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array: indices=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for vertex in positions.size(): indices.append(vertex)
		var triangles: Array = []
		var used_vertices: Dictionary = {}
		for offset in range(0,indices.size()-2,3):
			var ids: Array[int] = [indices[offset],indices[offset+1],indices[offset+2]]
			if not eligible.has(ids[0]) or not eligible.has(ids[1]) or not eligible.has(ids[2]): continue
			var minimum: float = 1.0
			for vertex in ids:
				used_vertices[vertex] = eligible[vertex]
				minimum=minf(minimum,float(eligible[vertex].target_weight))
			triangles.append({"indices":ids,"ordinal":int(offset/3),"minimum_weight":minimum})
		if not triangles.is_empty(): result.surfaces.append({"index":surface,"vertices":used_vertices,"triangles":triangles})
	return result

static func _unsupported(reason: String) -> Dictionary:
	return {"supported":false,"reason":reason,"distance":-1.0,"point":Vector3.ZERO,"triangle_count":0}

static func _closest_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var edge: Vector3 = b-a
	var denominator: float = edge.length_squared()
	if denominator<1e-24: return a
	return a+edge*clampf((p-a).dot(edge)/denominator,0,1)

static func _closest_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var edge: Vector3 = b-a
	var other: Vector3 = c-a
	var normal: Vector3 = edge.cross(other)
	var normal_squared: float = normal.length_squared()
	# Project onto the triangle plane, then test barycentric coordinates. Outside
	# (or degenerate) triangles use the nearest of the three bounded edges.
	if normal_squared>1e-24:
		var projected: Vector3 = p-normal*((p-a).dot(normal)/normal_squared)
		var delta: Vector3 = projected-a
		var ee: float = edge.dot(edge)
		var ff: float = other.dot(other)
		var ef: float = edge.dot(other)
		var denominator: float = ee*ff-ef*ef
		if denominator>1e-24:
			var u: float = (delta.dot(edge)*ff-delta.dot(other)*ef)/denominator
			var v: float = (delta.dot(other)*ee-delta.dot(edge)*ef)/denominator
			if u>=0 and v>=0 and u+v<=1: return projected
	var nearest: Vector3 = _closest_segment(p,a,b)
	for candidate in [_closest_segment(p,b,c),_closest_segment(p,c,a)]:
		if p.distance_squared_to(candidate)<p.distance_squared_to(nearest): nearest=candidate
	return nearest

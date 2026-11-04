class_name FoundationHandContact
extends RefCounted

# Real imported Skin vertices provide contact observations. This is a hand
# position/frame adapter, not a claim of articulated fingertip opposition.
var skeleton: Skeleton3D
var actor: Node3D
var bones: Dictionary = {}
var pads: Dictionary = {}
var torso_front_actor := -INF
var torso_front_vertex: Dictionary = {}

func configure(body: Node3D, rig: Skeleton3D) -> bool:
	if body==null or rig==null:return false
	actor=body;skeleton=rig;bones.clear();pads.clear();torso_front_actor=-INF;torso_front_vertex.clear()
	for index in skeleton.get_bone_count():bones[skeleton.get_bone_name(index)]=index
	var candidates := {"L":[],"R":[]}
	for node in body.find_children("*","MeshInstance3D",true,false):
		var part: MeshInstance3D=node
		if part.mesh==null or part.skin==null or part.get_node_or_null(part.skeleton)!=rig:continue
		var palette: Array[int]=[]
		for bind in part.skin.get_bind_count():
			var name: StringName=part.skin.get_bind_name(bind)
			palette.append(rig.find_bone(name) if not name.is_empty() else part.skin.get_bind_bone(bind))
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var joints: Variant=arrays[Mesh.ARRAY_BONES];var weights: Variant=arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or normals.size()!=vertices.size() or joints==null or weights==null:continue
			var count: int=joints.size()/vertices.size()
			if count not in [4,8]:continue
			for vertex in vertices.size():
				var influences: Array=[];var strongest := -1;var strength := 0.0
				var position := Vector3.ZERO;var normal := Vector3.ZERO
				var torso_weight := 0.0
				for slot in count:
					var weight: float=weights[vertex*count+slot]
					if weight<=0:continue
					var bind: int=joints[vertex*count+slot];var bone: int=palette[bind]
					if bone<0:return false
					var bind_pose: Transform3D=part.skin.get_bind_pose(bind)
					var point: Vector3=bind_pose*vertices[vertex]
					influences.append({"bone":bone,"point":point,"weight":weight})
					var rest: Transform3D=rig.get_bone_global_rest(bone)
					position+=(rest*point)*weight;normal+=(rest.basis*bind_pose.basis*normals[vertex])*weight
					if weight>strength:strongest=bone;strength=weight
					var bone_name: String=rig.get_bone_name(bone)
					if bone_name in ["DEF-pelvis","DEF-spine_01","DEF-spine_02","DEF-chest","DEF-apron_front","DEF-apron_back"]:torso_weight+=weight
				if torso_weight>=.8:
					var point_actor: Vector3=actor.global_transform.affine_inverse()*(part.global_transform*position)
					var pelvis_actor: Vector3=actor.global_transform.affine_inverse()*(rig.global_transform*rig.get_bone_global_rest(bones["DEF-pelvis"])).origin
					var shoulder_actor: Vector3=actor.global_transform.affine_inverse()*(rig.global_transform*rig.get_bone_global_rest(bones["DEF-upper_arm.L"])).origin
					if point_actor.y>=pelvis_actor.y-.08 and point_actor.y<=shoulder_actor.y and point_actor.z>torso_front_actor:
						torso_front_actor=point_actor.z;torso_front_vertex={"surface":surface,"vertex":vertex,"position_actor":point_actor,"weight":torso_weight}
				if strength<.9999:continue
				for side in ["L","R"]:
					if strongest!=bones.get("DEF-hand."+side,-2):continue
					var hand: Transform3D=rig.global_transform*rig.get_bone_global_rest(strongest)
					var local: Vector3=hand.affine_inverse()*(part.global_transform*position)
					var span: float=rig.get_bone_rest(bones["DEF-forearm."+side]).origin.length()+rig.get_bone_rest(strongest).origin.length()
					if local.y<=.005 or local.y>=span*.16:continue
					var axis: Vector3=hand.basis.y.normalized()
					var front: Vector3=(part.global_basis*normal).normalized();front-=axis*axis.dot(front)
					if front.length()<.01:continue
					front=front.normalized()
					var right := axis.cross(front).normalized()
					var basis := Basis(right,front.cross(right).normalized(),front)
					candidates[side].append({"mesh":weakref(part),"surface":surface,"vertex":vertex,"influences":influences,"local":local,
						"basis_in_hand":hand.basis.inverse()*basis,"score":absf(local.y-span*.08)-local.z,"strong_weight":strength})
	for side in ["L","R"]:
		if candidates[side].is_empty():return false
		candidates[side].sort_custom(func(a,b):return a.score<b.score)
		pads[side]=candidates[side][0]
	return true

func palm(side: String) -> Transform3D:
	var hand := skeleton.global_transform*skeleton.get_bone_global_pose(bones["DEF-hand."+side])
	var point := Vector3.ZERO
	var record: Dictionary=pads[side]
	for influence in record.influences:point+=(skeleton.get_bone_global_pose(influence.bone)*influence.point)*float(influence.weight)
	var mesh: MeshInstance3D=record.mesh.get_ref()
	return Transform3D(hand.basis*record.basis_in_hand,mesh.global_transform*point)

func provenance(side: String) -> Dictionary:
	var record: Dictionary=pads[side]
	var weights := []
	for influence in record.influences:weights.append({"bone":skeleton.get_bone_name(influence.bone),"weight":influence.weight,"bind_local":influence.point})
	return {"method":"actual_imported_mesh_skin_vertex","surface":record.surface,"vertex":record.vertex,"weights":weights,"strong_weight":record.strong_weight,
		"frame":"actual imported normal and hand longitudinal axis; no fingertip accuracy claimed"}

func solve(side: String, target: Transform3D) -> float:
	var pad: Dictionary=pads[side]
	var wrist_basis: Basis=target.basis*pad.basis_in_hand.inverse()
	var wrist := Transform3D(wrist_basis,target.origin-wrist_basis*pad.local)
	var names := ["DEF-upper_arm."+side,"DEF-forearm."+side,"DEF-hand."+side]
	var a := skeleton.global_transform*skeleton.get_bone_global_pose(bones[names[0]])
	var b := skeleton.global_transform*skeleton.get_bone_global_pose(bones[names[1]])
	var c := skeleton.global_transform*skeleton.get_bone_global_pose(bones[names[2]])
	var upper := skeleton.get_bone_rest(bones[names[1]]).origin.length()
	var lower := skeleton.get_bone_rest(bones[names[2]]).origin.length()
	var offset := wrist.origin-a.origin
	if offset.length()<.000001:return upper+lower
	var axis := offset.normalized();var old_axis := (c.origin-a.origin).normalized()
	var bend := b.origin-a.origin;bend-=old_axis*old_axis.dot(bend)
	if bend.length()<.00001:bend=actor.global_basis.x*(1 if side=="L" else -1)
	bend=Quaternion(old_axis,axis)*bend.normalized()
	var distance := clampf(offset.length(),absf(upper-lower)+.00001,upper+lower-.00001)
	var along := (upper*upper+distance*distance-lower*lower)/(2*distance)
	var elbow := a.origin+axis*along+bend*sqrt(maxf(0,upper*upper-along*along))
	var end := a.origin+axis*distance
	_rotate(bones[names[0]],(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized())*a.basis.get_rotation_quaternion()).normalized())
	_rotate(bones[names[1]],(Quaternion((c.origin-b.origin).normalized(),(end-elbow).normalized())*b.basis.get_rotation_quaternion()).normalized())
	_rotate(bones[names[2]],wrist.basis.get_rotation_quaternion().normalized())
	return end.distance_to(wrist.origin)

func _rotate(index: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(index)
	var frame := skeleton.global_transform
	if parent>=0:frame*=skeleton.get_bone_global_pose(parent)
	skeleton.set_bone_pose_position(index,skeleton.get_bone_rest(index).origin)
	skeleton.set_bone_pose_scale(index,Vector3.ONE)
	skeleton.set_bone_pose_rotation(index,(frame.basis.get_rotation_quaternion().normalized().inverse()*rotation).normalized())

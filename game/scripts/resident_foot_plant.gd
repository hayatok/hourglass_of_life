class_name ResidentFootPlant
extends SkeletonModifier3D

# Runs before the leg solvers, after AnimationPlayer has supplied the current
# unmodified pose. Anchors belong only to presentation, never to Sim or saves.
var contacts: ResidentContacts
var walking := false
var anchors: Dictionary = {}
var support: Dictionary = {}
var previous_root := Vector3.ZERO
var previous_forward := Vector3.FORWARD
var initialized := false

func reset() -> void:
	anchors.clear()
	support.clear()
	initialized = false

func _process_modification() -> void:
	if not is_instance_valid(contacts): return
	var avatar := contacts.avatar
	var model := contacts.model
	if not walking or not model.walk_foot_plant:
		reset()
		return
	var root := avatar.global_position
	var forward: Vector3 = avatar.visual.global_basis.z.normalized()
	if initialized and (root.distance_to(previous_root)>model.rest_height*.5 or forward.dot(previous_forward)<.7):
		anchors.clear()
		support.clear()
	previous_root = root
	previous_forward = forward
	initialized = true
	var phase := fposmod(model.animator.current_animation_position/maxf(.01,model.animator.current_animation_length),1.0)
	var facing := Basis(Vector3.UP,avatar.visual.rotation.y)
	for side in ["L","R"]:
		var start: float = model.walk_plant_start.x if side=="L" else model.walk_plant_start.y
		var progress := fposmod(phase-start,1.0)
		var solver: TwoBoneIK3D = contacts.foot_ik[side]
		var bone_name: String = "DEF-foot."+side
		contacts.wrists.targets.erase(bone_name)
		if progress>=model.walk_plant_duration:
			anchors.erase(side)
			support.erase(side)
			solver.active = false
			continue
		# A skipped swing (low frame rate / fast playback) starts a new support.
		if support.has(side) and progress<float(support[side].progress): anchors.erase(side)
		var raw := contacts.point("foot."+side)
		var raw_pose := get_skeleton().get_bone_global_pose(get_skeleton().find_bone(bone_name))
		var raw_basis := (get_skeleton().global_basis*raw_pose.basis).orthonormalized()
		if not anchors.has(side):
			anchors[side] = {"position":Vector3(raw.x,root.y+contacts.rest_feet[side].origin.y*avatar.visual.scale.y,raw.z),"forward":forward}
		var anchor: Vector3 = anchors[side].position
		# Release an unreachable foot rather than stretching a leg through a turn,
		# abrupt route correction or a high-speed sample that skipped most of a step.
		var offset := Vector2(raw.x-anchor.x,raw.z-anchor.z).length()
		if offset>model.rest_height*.18 or forward.dot(anchors[side].forward)<.86:
			anchors.erase(side)
			support.erase(side)
			solver.active = false
			continue
		var fade := model.walk_plant_fade
		var weight := smoothstep(0.0,fade,progress)*(1.0-smoothstep(model.walk_plant_duration-fade,model.walk_plant_duration,progress))
		var target: Node3D = contacts.foot_targets[side]
		target.global_position = raw.lerp(anchor,weight)
		var flat: Basis = facing*contacts.rest_feet[side].basis.orthonormalized()
		target.global_basis = raw_basis.slerp(flat,weight)
		var sign_x := 1.0 if side=="L" else -1.0
		contacts.poles["foot"+side].global_position = avatar.visual.global_transform*Vector3(sign_x*.12,.45,.9)
		solver.active = weight>.0001
		if solver.active: contacts.wrists.targets[bone_name] = target
		support[side] = {"progress":progress,"weight":weight,"anchor":anchor,"raw":raw}

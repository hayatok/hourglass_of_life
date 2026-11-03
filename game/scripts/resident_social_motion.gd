class_name ResidentSocialMotion
extends SkeletonModifier3D

# The seated pelvis/feet remain on their contacts while the upper body shares
# the turn. This precedes head attention and hand IK in the modifier stack.
var turn := 0.0
var nod := 0.0
var action_lean := Vector3.ZERO
var facing := Basis.IDENTITY

func update(avatar: Node3D, attention: Vector3, attending: bool, listening: bool, clock: float, delta: float) -> void:
	var target := 0.0
	if attending:
		var direction: Vector3 = avatar.visual.global_basis.inverse()*(attention-avatar.head_position())
		target = clampf(atan2(direction.x,direction.z),-.95,.95)
	turn = move_toward(turn,target,delta*2.2)
	facing = Basis(Vector3.UP,avatar.visual.rotation.y)
	var phase := fposmod(clock,4.8)
	var target_nod := sin(phase/.65*TAU)*.045 if attending and listening and phase<.65 else 0.0
	nod = lerpf(nod,target_nod,minf(1,delta*12))

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton==null: return
	var up := (skeleton.global_basis.inverse()*Vector3.UP).normalized()
	var right := (skeleton.global_basis.inverse()*facing.x).normalized()
	var forward := (skeleton.global_basis.inverse()*facing.z).normalized()
	for setting in [["DEF-spine_01",.18],["DEF-spine_02",.25],["DEF-neck",.18]]:
		var index := skeleton.find_bone(setting[0])
		if index<0: continue
		var pose := skeleton.get_bone_global_pose(index)
		pose.basis = Basis(up,turn*float(setting[1]))*pose.basis
		if setting[0]!="DEF-neck":
			var weight := .45 if setting[0]=="DEF-spine_01" else .55
			pose.basis = Basis(right,action_lean.x*weight)*Basis(up,action_lean.y*weight)*Basis(forward,action_lean.z*weight)*pose.basis
		if setting[0]=="DEF-neck": pose.basis *= Basis(Vector3.RIGHT,nod)
		skeleton.set_bone_global_pose(index,pose)

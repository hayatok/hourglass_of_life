class_name ContactRotation
extends SkeletonModifier3D

var targets: Dictionary = {}
var eating := false

func _process_modification() -> void:
	var skeleton := get_skeleton()
	for bone_name in targets:
		var index := skeleton.find_bone(bone_name)
		var pose := skeleton.get_bone_global_pose(index)
		var target: Node3D = targets[bone_name]
		pose.basis = (skeleton.global_basis.inverse()*target.global_basis).orthonormalized()
		skeleton.set_bone_global_pose(index,pose)
	if eating:
		for finger in 5:
			var index := skeleton.find_bone("DEF-finger%d.R"%finger)
			skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.RIGHT,.55))

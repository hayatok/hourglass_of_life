class_name ContactRotation
extends SkeletonModifier3D

var targets: Dictionary = {}
var eating := false
var finger_curls: Dictionary = {}
# Explicit rotations are relative to each finger's measured bind/rest basis.
var finger_rotations: Dictionary = {}

func _process_modification() -> void:
	var skeleton := get_skeleton()
	for bone_name in targets:
		var index := skeleton.find_bone(bone_name)
		var pose := skeleton.get_bone_global_pose(index)
		var target: Node3D = targets[bone_name]
		pose.basis = (skeleton.global_basis.inverse()*target.global_basis).orthonormalized()
		skeleton.set_bone_global_pose(index,pose)
	for side in finger_curls:
		var setting = finger_curls[side]
		for finger in 5:
			var value: float = setting[finger] if setting is Array and setting.size()==5 else float(setting)
			var index := skeleton.find_bone("DEF-finger%d.%s"%[finger,side])
			if index>=0:
				var angle := clampf(value,0,1)*(.55 if finger==0 else .85)
				skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.RIGHT,angle))
	if eating:
		for finger in 5:
			var index := skeleton.find_bone("DEF-finger%d.R"%finger)
			skeleton.set_bone_pose_rotation(index,Quaternion(Vector3.RIGHT,.55))
	for side in finger_rotations:
		var rotations: Array = finger_rotations[side]
		for finger in mini(5,rotations.size()):
			var index := skeleton.find_bone("DEF-finger%d.%s"%[finger,side])
			if index>=0 and rotations[finger] is Quaternion:
				var rest_rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
				skeleton.set_bone_pose_rotation(index,rest_rotation*rotations[finger])

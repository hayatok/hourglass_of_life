@tool
class_name SewingScissorsProp
extends Node3D

# Display pose only: no automatic animation or authority over cutting progress.
@export_range(0.0, 1.0, 0.01) var opening: float = 0.0:
	set(value):
		if not is_finite(value): return
		opening = clampf(value, 0.0, 1.0)
		_apply_opening()

func _ready() -> void:
	_apply_opening()

func set_open(amount: float) -> void:
	opening = amount

func local_contacts() -> Dictionary:
	return {"grip_center": $GripCenter.position, "blade_pivot": $BladePivot.position,
		"cut_point": $CutPoint.position,
		"thumb_loop_center": _relative_transform($BladePivot/LeftHalf/ThumbLoopCenter).origin,
		"finger_loop_center": _relative_transform($BladePivot/RightHalf/FingerLoopCenter).origin,
		"thumb_contact": _relative_transform($BladePivot/LeftHalf/ThumbContact).origin,
		"finger_contact": _relative_transform($BladePivot/RightHalf/FingerContact).origin}

func _apply_opening() -> void:
	var left := get_node_or_null("BladePivot/LeftHalf") as Node3D
	var right := get_node_or_null("BladePivot/RightHalf") as Node3D
	if left != null: left.rotation.y = deg_to_rad(-3.0 - 20.0 * opening)
	if right != null: right.rotation.y = deg_to_rad(3.0 + 20.0 * opening)

func _relative_transform(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node3D = node
	while cursor != self and cursor != null:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result

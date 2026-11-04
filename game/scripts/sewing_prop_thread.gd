@tool
class_name SewingThreadProp
extends Node3D

# A single instanced draw for the short thread between needle and fabric. Inputs
# are thread-root-local positions. The caller owns the endpoint observations.
# This does not consume thread, advance sewing or move the needle/fabric.
const SEGMENTS := 16
var _start := Vector3(0.0, 0.04, 0.0)
var _end := Vector3(0.06, 0.0, 0.02)
var _slack := 0.018

func _ready() -> void:
	_update_segments()

func set_ends(start_local: Vector3, end_local: Vector3, slack: float = 0.018) -> void:
	if not start_local.is_finite() or not end_local.is_finite() or not is_finite(slack): return
	_start = start_local
	_end = end_local
	_slack = clampf(slack, 0.0, 0.2)
	_update_segments()

func _point(t: float) -> Vector3:
	var control := (_start + _end) * 0.5 + Vector3.DOWN * _slack
	return (1.0-t)*(1.0-t)*_start + 2.0*(1.0-t)*t*control + t*t*_end

func _update_segments() -> void:
	var renderer := get_node_or_null("ThreadSegments") as MultiMeshInstance3D
	if renderer == null or renderer.multimesh == null: return
	if renderer.multimesh.instance_count != SEGMENTS:
		# The saved resource has zero instances: duplicating an uninitialised
		# headless MultiMesh buffer can fail during PackedScene instantiation.
		var source_mesh: Mesh = renderer.multimesh.mesh
		var owned := MultiMesh.new()
		owned.transform_format=MultiMesh.TRANSFORM_3D;owned.mesh=source_mesh;owned.instance_count=SEGMENTS
		renderer.multimesh=owned
	renderer.visible = _start.distance_squared_to(_end) > 0.00000004
	if not renderer.visible: return
	var instances: MultiMesh = renderer.multimesh
	for index in SEGMENTS:
		var a := _point(float(index)/SEGMENTS)
		var b := _point(float(index+1)/SEGMENTS)
		var delta := b-a
		var length := delta.length()
		if length <= 0.000001: continue
		var y := delta/length
		var reference := Vector3.FORWARD if absf(y.z)<0.95 else Vector3.RIGHT
		var x := y.cross(reference).normalized()
		var z := x.cross(y).normalized()
		instances.set_instance_transform(index, Transform3D(Basis(x,y*length,z),(a+b)*0.5))

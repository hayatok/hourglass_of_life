@tool
class_name ActivitySpot
extends Node3D

@export var spot_id := ""
@export var site := ""
@export var actions := PackedStringArray()
@export_enum("seat","work","bed") var pose_kind := "seat"
@export var resident := ""
@export var group := ""
@export var pair := ""

func describe(world: Transform3D) -> Dictionary:
	var record := {"id":spot_id,"site":site,"actions":Array(actions),"pose":pose_kind,
		"resident":resident,"group":group,"pair":pair,"yaw":world.basis.get_euler().y}
	for key in ["Approach","Contact","HandLeft","HandRight"]:
		var marker := get_node_or_null(key) as Node3D
		if marker: record[key.to_snake_case()] = world*marker.position
	return record

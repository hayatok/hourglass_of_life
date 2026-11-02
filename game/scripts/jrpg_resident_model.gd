class_name JrpgResidentModel
extends Node3D

var animator: AnimationPlayer
var skeleton: Skeleton3D
var face: MeshInstance3D
var elapsed := 0.0
var fatigue := 0.0
var warmth := 0.0
var gaze := 0.0

func _ready() -> void:
	_collect(self)
	# Each actor owns its animation resources and loop settings.
	for library_name in animator.get_animation_library_list():
		var library := animator.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		animator.remove_animation_library(library_name)
		animator.add_animation_library(library_name,library)
		for clip in library.get_animation_list():
			library.get_animation(clip).loop_mode = Animation.LOOP_NONE if clip == "wave" or clip == "RESET" else Animation.LOOP_LINEAR
	animator.play("idle")

func _collect(node: Node) -> void:
	if node is AnimationPlayer:
		animator = node
	elif node is Skeleton3D:
		skeleton = node
	elif node is MeshInstance3D:
		var part := node as MeshInstance3D
		var is_face := "Face" in part.name
		if is_face:
			face = part
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in part.mesh.get_surface_count():
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original == null: continue
			var material := original.duplicate() as StandardMaterial3D
			material.resource_local_to_scene = true
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			if is_face:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				part.set_surface_override_material(surface,material)
			else:
				var toon := ShaderMaterial.new()
				toon.shader = preload("res://game/assets/models/resident_toon.gdshader")
				toon.set_shader_parameter("base_palette",original.albedo_texture)
				part.set_surface_override_material(surface,toon)
	for child in node.get_children(): _collect(child)

func set_expression(tiredness: float, friendliness: float, look: float = 0) -> void:
	fatigue = clampf(tiredness,0,1)
	warmth = clampf(friendliness,0,1)
	gaze = clampf(look,-1,1)

func _process(delta: float) -> void:
	if not is_instance_valid(animator) or not is_instance_valid(face): return
	elapsed += delta*animator.speed_scale
	var phase := fmod(elapsed+1.6,4.3)
	var blink := maxf(0,1-absf(phase-.11)/.11) if phase<.22 else 0.0
	_blend("Blink",1.0 if animator.current_animation=="sleep" else blink)
	_blend("Smile",warmth)
	_blend("Tired",clampf((fatigue-.55)/.45,0,.7))
	_blend("LookLeft",maxf(gaze,0))
	_blend("LookRight",maxf(-gaze,0))

func _blend(name: String, value: float) -> void:
	var index := face.find_blend_shape_by_name(name)
	if index>=0: face.set_blend_shape_value(index,value)

class_name JrpgResidentModel
extends Node3D

@export var rest_height := 1.65
@export var walk_speed := 1.6
@export var hair_cells := Vector3i(-1,-1,-1)
enum MaterialMode { PALETTE_TOON, TEXTURE_TOON, SOURCE_PBR }
enum ExpressionMode { BLEND_SHAPES, STATIC_ATLAS, TEXTURE_EYES }
@export var material_mode: MaterialMode = MaterialMode.PALETTE_TOON
@export var expression_mode: ExpressionMode = ExpressionMode.BLEND_SHAPES
@export_file("*.json") var face_layout_path := ""
const REQUIRED_CLIPS := ["eat","idle","rest","sit_talk","sleep","talk","walk","wave","work"]
const FACE_CONTROLS := ["Blink","Smile","Sad","Tired","LookLeft","LookRight"]
const REQUIRED_BONES := ["root","pelvis","apron_back","apron_front","spine_01","spine_02","chest","clavicle.L","upper_arm.L","forearm.L","hand.L","finger0.L","finger1.L","finger2.L","finger3.L","finger4.L","clavicle.R","upper_arm.R","forearm.R","hand.R","finger0.R","finger1.R","finger2.R","finger3.R","finger4.R","neck","head","thigh.L","shin.L","foot.L","toe.L","thigh.R","shin.R","foot.R","toe.R"]
var body_materials: Array[ShaderMaterial] = []
var animator: AnimationPlayer
var skeleton: Skeleton3D
var face: MeshInstance3D
var elapsed := 0.0
var fatigue := 0.0
var warmth := 0.0
var gaze := 0.0
var lod_level := 0
var lod_variants: Array[Dictionary] = []
var lod_parts: Dictionary = {}
var lod_prepared := false
var lod_resources_loaded := 0
var face_layout: Dictionary = {}

func _ready() -> void:
	if expression_mode==ExpressionMode.TEXTURE_EYES and FileAccess.file_exists(face_layout_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(face_layout_path))
		if parsed is Dictionary: face_layout = parsed
	_collect(self)
	for error in import_contract_errors(): push_error(name+": "+error)
	if not is_instance_valid(animator): return
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
		lod_parts[_lod_key(part.name)] = part
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
			if is_face and expression_mode==ExpressionMode.BLEND_SHAPES:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				part.set_surface_override_material(surface,material)
			elif material_mode==MaterialMode.SOURCE_PBR:
				part.set_surface_override_material(surface,material)
			else:
				var toon := ShaderMaterial.new()
				toon.shader = preload("res://game/assets/models/haru/haru_texture_eyes.gdshader") if expression_mode==ExpressionMode.TEXTURE_EYES else preload("res://game/assets/models/resident_toon.gdshader")
				toon.set_shader_parameter("base_palette",original.albedo_texture)
				toon.set_shader_parameter("hair_cells",hair_cells if uses_palette_swatches() else Vector3i(-1,-1,-1))
				if expression_mode==ExpressionMode.TEXTURE_EYES: _configure_texture_eyes(toon)
				body_materials.append(toon)
				part.set_surface_override_material(surface,toon)
	for child in node.get_children(): _collect(child)

func uses_palette_swatches() -> bool:
	return material_mode==MaterialMode.PALETTE_TOON

func _valid_pair(value: Variant, uv: bool) -> bool:
	if not value is Array or value.size()!=2: return false
	for component in value:
		if not component is float and not component is int: return false
		if not is_finite(float(component)): return false
		if uv and (component<0 or component>1): return false
	return true

func _texture_eye_errors() -> Array[String]:
	var errors: Array[String] = []
	if material_mode!=MaterialMode.TEXTURE_TOON: errors.append("texture eyes require texture toon material mode")
	var eyes = face_layout.get("eyes",{})
	for side in ["left","right"]:
		if not eyes is Dictionary or not eyes.get(side) is Dictionary:
			errors.append("missing texture-eye layout for "+side);continue
		var eye: Dictionary = eyes[side]
		for key in ["center","skin_uv","axis_x","axis_y"]:
			if not _valid_pair(eye.get(key),key in ["center","skin_uv"]): errors.append("invalid "+side+" texture-eye "+key)
		if _valid_pair(eye.get("axis_x"),false) and _valid_pair(eye.get("axis_y"),false):
			var x: Array = eye.axis_x;var y: Array = eye.axis_y
			if absf(x[0]*y[1]-x[1]*y[0])<.00000001: errors.append("degenerate "+side+" texture-eye UV basis")
	return errors

func _configure_texture_eyes(material: ShaderMaterial) -> void:
	if not _texture_eye_errors().is_empty(): return
	for side in ["left","right"]:
		var eye: Dictionary = face_layout.eyes[side]
		var prefix := "eye_l" if side=="left" else "eye_r"
		for pair in [["center",""],["axis_x","_x"],["axis_y","_y"],["skin_uv","_skin"]]:
			var value: Array = eye[pair[0]]
			material.set_shader_parameter(prefix+pair[1],Vector2(value[0],value[1]))
	material.set_shader_parameter("blink",0.0)
	material.set_shader_parameter("tired_eyes",0.0)

func import_contract_errors() -> Array[String]:
	var errors: Array[String] = []
	if not is_instance_valid(skeleton):
		errors.append("missing Skeleton3D; a static import is not an animated resident")
	else:
		for bone in REQUIRED_BONES:
			if skeleton.find_bone("DEF-"+bone)<0: errors.append("missing contact/animation bone DEF-"+bone)
	var skinned_meshes := 0
	for part in lod_parts.values():
		if part.skin==null or part.skin.get_bind_count()==0: continue
		skinned_meshes += 1
		if is_instance_valid(skeleton) and part.get_node_or_null(part.skeleton)!=skeleton:
			errors.append("mesh skin does not resolve to the resident skeleton: "+str(part.name))
	if skinned_meshes==0: errors.append("missing bound mesh skin; skeleton/clip names alone do not deform a resident")
	if not is_instance_valid(animator):
		errors.append("missing AnimationPlayer")
	else:
		for clip in REQUIRED_CLIPS:
			if not animator.has_animation(clip): errors.append("missing animation "+clip)
	if expression_mode==ExpressionMode.BLEND_SHAPES:
		if not is_instance_valid(face):
			errors.append("blend-shape mode requires a Face mesh; static atlas must be declared explicitly")
		else:
			for control in FACE_CONTROLS:
				if face.find_blend_shape_by_name(control)<0: errors.append("missing facial control "+control)
	elif expression_mode==ExpressionMode.TEXTURE_EYES:
		errors.append_array(_texture_eye_errors())
	return errors

func capabilities() -> Dictionary:
	var source := ""
	var controls: Array[String] = []
	for child in get_children():
		if child.scene_file_path.ends_with(".glb"):
			source = child.scene_file_path
			break
	if expression_mode==ExpressionMode.BLEND_SHAPES and is_instance_valid(face):
		for control in FACE_CONTROLS:
			if face.find_blend_shape_by_name(control)>=0: controls.append(control)
	elif expression_mode==ExpressionMode.TEXTURE_EYES and _texture_eye_errors().is_empty():
		controls.assign(["Blink","TiredEyes"])
	return {"source_model":source,"material_mode":MaterialMode.keys()[material_mode],"expression_mode":ExpressionMode.keys()[expression_mode],"facial_controls":controls,"face_layout":face_layout_path,"hair_aging":uses_palette_swatches() and hair_cells!=Vector3i(-1,-1,-1),"contract_errors":import_contract_errors()}

func _lod_key(part_name: String) -> String:
	for level in range(3): part_name = part_name.replace("_LOD%d"%level,"")
	return part_name

func _mesh_records(source: Node) -> Dictionary:
	var records := {}
	for part in source.find_children("*","MeshInstance3D",true,false):
		records[_lod_key(part.name)] = {"mesh":part.mesh,"skin":part.skin}
	return records

func prepare_lods() -> void:
	if lod_prepared: return
	lod_prepared = true
	lod_variants = [_mesh_records(self),{},{}]
	var path := ""
	for child in get_children():
		if child.scene_file_path.ends_with(".glb"):
			path = child.scene_file_path.trim_suffix(".glb")
			break
	if path.is_empty(): return
	for level in [1,2]:
		var asset_path := path+"_LOD%d.glb"%level
		if not ResourceLoader.exists(asset_path): continue
		var source = load(asset_path).instantiate()
		var records := _mesh_records(source)
		if _compatible_lod(records):
			lod_variants[level] = records
			lod_resources_loaded += 1
		source.free()

func _compatible_lod(records: Dictionary) -> bool:
	if records.size()!=lod_parts.size(): return false
	for key in lod_parts:
		if not records.has(key): return false
		var original: MeshInstance3D = lod_parts[key]
		var mesh: Mesh = records[key].mesh
		var skin: Skin = records[key].skin
		if mesh==null or skin==null or original.skin==null: return false
		if mesh.get_surface_count()!=original.mesh.get_surface_count(): return false
		if mesh.get_blend_shape_count()!=original.mesh.get_blend_shape_count(): return false
		for index in mesh.get_blend_shape_count():
			if mesh.get_blend_shape_name(index)!=original.mesh.get_blend_shape_name(index): return false
		if skin.get_bind_count()!=original.skin.get_bind_count(): return false
		for index in skin.get_bind_count():
			if skin.get_bind_name(index)!=original.skin.get_bind_name(index): return false
			if not skin.get_bind_pose(index).is_equal_approx(original.skin.get_bind_pose(index)): return false
	return true

func set_lod(level: int) -> bool:
	level = clampi(level,0,2)
	if level==lod_level: return true
	prepare_lods()
	if lod_variants[level].is_empty(): return false
	# Keep the original skeleton, animation player and modifier nodes. Mesh and
	# skin resources share the verified named binds; no pose or clock is restarted.
	for key in lod_parts:
		var part: MeshInstance3D = lod_parts[key]
		var record: Dictionary = lod_variants[level][key]
		var expressions := {}
		var materials := []
		for index in part.mesh.get_blend_shape_count():
			expressions[part.mesh.get_blend_shape_name(index)] = part.get_blend_shape_value(index)
		for surface in part.mesh.get_surface_count(): materials.append(part.get_surface_override_material(surface))
		part.mesh = record.mesh
		part.skin = record.skin
		for surface in materials.size(): part.set_surface_override_material(surface,materials[surface])
		for index in part.mesh.get_blend_shape_count():
			part.set_blend_shape_value(index,expressions.get(part.mesh.get_blend_shape_name(index),0.0))
	lod_level = level
	return true

func set_age(age: int) -> void:
	# Fictional cosmetic progression; no prediction of an individual's biological aging.
	# A generated atlas needs a real hair mask before the old palette-cell aging can apply.
	if not uses_palette_swatches(): return
	var silver := clampf((age-45.0)/30.0,0,.9)
	for material in body_materials: material.set_shader_parameter("hair_age",silver)

func set_expression(tiredness: float, friendliness: float, look: float = 0) -> void:
	fatigue = clampf(tiredness,0,1)
	warmth = clampf(friendliness,0,1)
	gaze = clampf(look,-1,1)

func _process(delta: float) -> void:
	# Explicit intermediate capability: head gaze and contact/body gestures still run in
	# ResidentContacts, but a painted static face does not pretend to blink or smile.
	if expression_mode==ExpressionMode.STATIC_ATLAS: return
	if not is_instance_valid(animator): return
	elapsed += delta*animator.speed_scale
	var phase := fmod(elapsed+1.6,4.3)
	var blink := maxf(0,1-absf(phase-.11)/.11) if phase<.22 else 0.0
	if expression_mode==ExpressionMode.TEXTURE_EYES:
		for material in body_materials:
			material.set_shader_parameter("blink",1.0 if animator.current_animation=="sleep" else blink)
			material.set_shader_parameter("tired_eyes",clampf((fatigue-.55)/.45,0,.7))
		return
	if not is_instance_valid(face): return
	_blend("Blink",1.0 if animator.current_animation=="sleep" else blink)
	_blend("Smile",warmth)
	_blend("Tired",clampf((fatigue-.55)/.45,0,.7))
	_blend("LookLeft",maxf(gaze,0))
	_blend("LookRight",maxf(-gaze,0))

func _blend(name: String, value: float) -> void:
	var index := face.find_blend_shape_by_name(name)
	if index>=0: face.set_blend_shape_value(index,value)

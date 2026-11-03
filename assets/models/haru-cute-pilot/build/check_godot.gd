extends SceneTree
## Reproducible static asset preview. Does not instantiate a game actor or replace a model.
## Run check_godot.py to build an isolated import project: assets/models is .gdignore'd.

const RAW := "res://assets/models/haru-cute-pilot/raw/CH_Haru_JRPG_Pilot_Raw.glb"
const CURRENT := "res://assets/models/haru-cute-pilot/build/fixtures/haru-placeholder.tscn"
const CURRENT_APPEARANCE := "res://assets/models/haru-cute-pilot/build/fixtures/haru-placeholder-appearance.json"
const OUT := "res://assets/models/haru-cute-pilot/review/godot"
const TARGET_HEIGHT := 1.71
const EXPECTED_SHA := "5b0d35cdace93c434abcee76f75c711a5970e52b16474fb9cd0147f66fbeac71"
var output_dir := OUT
var original_source := ""
var report: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var world: Node3D
var camera: Camera3D
var model_turntables: Array[Node3D] = []
var view_label: Label
var left_label: Label
var right_label: Label

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_dir = argument.trim_prefix("--output=")
		if argument.begins_with("--original-source="): original_source = argument.trim_prefix("--original-source=")
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func bounds_record(bounds: AABB) -> Dictionary:
	return {"min":xyz(bounds.position),"max":xyz(bounds.end),"size":xyz(bounds.size)}

func raw_document() -> Dictionary:
	var file := FileAccess.open(RAW,FileAccess.READ)
	if file==null: return {}
	expect(file.get_32()==0x46546c67,"Source has the GLB magic")
	expect(file.get_32()==2,"Source is GLB version 2")
	file.get_32()
	var size := file.get_32()
	expect(file.get_32()==0x4e4f534a,"Source starts with the GLB JSON chunk")
	var parsed = JSON.parse_string(file.get_buffer(size).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children(): result.append_array(all_nodes(child))
	return result

func model_bounds(model: Node3D) -> AABB:
	var found := false
	var bounds := AABB()
	for node in all_nodes(model):
		if not node is MeshInstance3D or node.mesh==null: continue
		var local: Transform3D = model.global_transform.affine_inverse()*node.global_transform
		var item: AABB = local*node.mesh.get_aabb()
		bounds = bounds.merge(item) if found else item
		found = true
	return bounds

func texture_record(texture: Texture2D) -> Dictionary:
	var source := texture.get_image()
	var readable := source!=null and not source.is_empty()
	return {"path":texture.resource_path,"width":texture.get_width(),"height":texture.get_height(),"readable":readable,"mipmaps":source.has_mipmaps() if readable else false}

func inspect(model: Node3D) -> Dictionary:
	var meshes := []
	var materials := []
	var unique_materials := {}
	var skeletons := []
	var clips := []
	var skins := 0
	var total_triangles := 0
	var total_vertices := 0
	for node in all_nodes(model):
		if node is Skeleton3D:
			skeletons.append({"path":str(model.get_path_to(node)),"bones":node.get_bone_count()})
		if node is AnimationPlayer:
			for clip in node.get_animation_list(): clips.append(str(clip))
		if not node is MeshInstance3D or node.mesh==null: continue
		if node.skin!=null: skins += 1
		var surfaces := []
		for index in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(index)
			var vertices: int = arrays[Mesh.ARRAY_VERTEX].size()
			var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else 0
			var triangles := int((indices if indices>0 else vertices)/3)
			total_vertices += vertices
			total_triangles += triangles
			surfaces.append({"vertices":vertices,"indices":indices,"triangles":triangles,"primitive":node.mesh.surface_get_primitive_type(index)})
			var material: Material = node.get_active_material(index)
			if material==null or unique_materials.has(material.get_instance_id()): continue
			unique_materials[material.get_instance_id()] = true
			var entry := {"name":material.resource_name,"class":material.get_class(),"textures":{}}
			if material is BaseMaterial3D:
				for role in ["albedo_texture","metallic_texture","roughness_texture","normal_texture","ao_texture"]:
					var texture: Texture2D = material.get(role)
					if texture!=null: entry.textures[role] = texture_record(texture)
				entry["normal_enabled"] = material.normal_enabled
				entry["roughness"] = material.roughness
				entry["metallic"] = material.metallic
			elif material is ShaderMaterial:
				var palette: Texture2D = material.get_shader_parameter("base_palette")
				if palette!=null: entry.textures["base_palette"] = texture_record(palette)
			materials.append(entry)
		meshes.append({"path":str(model.get_path_to(node)),"surfaces":surfaces,"blend_shapes":node.mesh.get_blend_shape_count(),"has_skin":node.skin!=null,"local_bounds":bounds_record(node.mesh.get_aabb())})
	return {"mesh_instances":meshes,"material_count":materials.size(),"materials":materials,"vertices":total_vertices,"triangles":total_triangles,"skeletons":skeletons,"skinned_meshes":skins,"animation_clips":clips,"rest_mesh_bounds":bounds_record(model_bounds(model))}

func apply_current_palette(model: JrpgResidentModel, appearance: Dictionary) -> void:
	# Same swatch mapping as ResidentAvatar._apply_variant_palette; only the old shared-rig model.
	# Never apply the 8x8 swatch override to the raw generated atlas.
	for material in model.body_materials:
		var original: Texture2D = material.get_shader_parameter("base_palette")
		if original==null: continue
		var source := original.get_image()
		if source.is_compressed(): source.decompress()
		var image := source.duplicate() as Image
		var width := image.get_width()/8
		var height := image.get_height()/8
		for swatch in appearance.palette:
			var index := int(swatch)
			image.fill_rect(Rect2i((index%8)*width,(7-index/8)*height,width,height),Color(appearance.palette[swatch]))
		image.generate_mipmaps()
		material.set_shader_parameter("base_palette",ImageTexture.create_from_image(image))

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = .85
	return result

func platform(x: float) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = .77;mesh.bottom_radius = .77;mesh.height = .05
	node.mesh = mesh
	node.material_override = material(Color("#3f4b5c"))
	node.position = Vector3(x,-.035,0)
	world.add_child(node)

func label(text: String, position: Vector2, width: float, size: int, color := Color("#e7edf3")) -> Label:
	var node := Label.new()
	node.text = text;node.position = position;node.size = Vector2(width,46)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	root.add_child(node)
	return node

func setup_stage() -> void:
	root.size = Vector2i(1600,1000)
	root.scaling_3d_scale = 1.0
	world = Node3D.new();world.name = "StaticAssetPreview";root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#202936")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .35
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(environment)
	var key := DirectionalLight3D.new();key.rotation_degrees = Vector3(-32,-30,0)
	key.light_energy = .8;key.shadow_enabled = true;world.add_child(key)
	var fill := DirectionalLight3D.new();fill.rotation_degrees = Vector3(-20,135,0)
	fill.light_energy = .2;fill.light_color = Color.WHITE;world.add_child(fill)
	var floor_node := MeshInstance3D.new();var floor_mesh := PlaneMesh.new();floor_mesh.size = Vector2(200,200)
	floor_node.mesh = floor_mesh;floor_node.material_override = material(Color("#293443"))
	floor_node.position.y = -.061;world.add_child(floor_node)
	camera = Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 3.4
	camera.position = Vector3(0,1.05,6);world.add_child(camera);camera.look_at(Vector3(0,.92,0));camera.current = true
	platform(-.93);platform(.93)
	label("GODOT STATIC ASSET PREVIEW",Vector2(0,30),1600,30)
	left_label = label("Previous Haru / shared rig",Vector2(150,850),560,24)
	right_label = label("Raw pilot / no rig or clips",Vector2(890,850),560,24)
	label("Both normalized to 1.71 m in this preview",Vector2(0,900),1600,20,Color("#aebccd"))
	view_label = label("",Vector2(0,76),1600,20,Color("#aebccd"))

func add_model(model: Node3D, x: float, body_scale: Vector3) -> Dictionary:
	var turntable := Node3D.new();turntable.position.x = x;world.add_child(turntable)
	var normalize := Node3D.new();turntable.add_child(normalize)
	normalize.add_child(model)
	model.scale = body_scale
	var local_bounds := model_bounds(model)
	var scaled_bounds := model.transform*local_bounds
	var factor := TARGET_HEIGHT/scaled_bounds.size.y
	normalize.scale = Vector3.ONE*factor
	model.position = Vector3(-scaled_bounds.get_center().x,-scaled_bounds.position.y,-scaled_bounds.get_center().z)
	model_turntables.append(turntable)
	return {"target_height_m":TARGET_HEIGHT,"body_scale":xyz(body_scale),"body_scaled_rest_height_m":scaled_bounds.size.y,"normalization_scale":factor,"normalized_height_m":scaled_bounds.size.y*factor,"model_offset_before_normalization":xyz(model.position),"stage_x":x,"measurement":"static rest mesh AABB, transformed into model root space; pose/cloth collision not validated"}

func capture(name: String, angle: float, description: String) -> void:
	for turntable in model_turntables: turntable.rotation_degrees.y = angle
	view_label.text = description
	await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var output := output_dir+"/"+name+".png"
	expect(root.get_texture().get_image().save_png(output)==OK,"Saved "+name+" GPU preview")
	report.renders.append({"file":output,"yaw_degrees":angle,"width":root.size.x,"height":root.size.y,"description":description})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var sha_before := FileAccess.get_sha256(RAW)
	report = {"purpose":"static imported material/mesh preview; not gameplay, animation, skinning or actor integration evidence","engine":Engine.get_version_info(),"display_server":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"source_glb":RAW,"source_sha256":sha_before,"reference":"res://assets/artwork/cute-cast-pilot/haru-concept-v2-jrpg.png","reference_sha256":FileAccess.get_sha256("res://assets/artwork/cute-cast-pilot/haru-concept-v2-jrpg.png"),"current_scene":CURRENT,"renders":[],"production_actor_replaced":false,"limitations":["Single front reference; unseen back/side are inferred by the generator.","The raw candidate has no rig, animation, facial controls or production LOD assets.","Both assets are frozen at rest. This does not validate deformation, contacts, crowds, game lighting or performance.","Current shared-rig model retains its own toon shader and palette; the raw candidate retains imported PBR materials. Same neutral lights, no claim of a final shared shading direction."]}
	report["isolated_import_project"] = ProjectSettings.globalize_path("res://")
	report["comparison_baseline_commit"] = "afb4c32"
	report["original_source"] = original_source
	expect(not original_source.is_empty() and FileAccess.get_sha256(original_source)==sha_before,"Staged GLB is byte-identical to the original source")
	expect(sha_before==EXPECTED_SHA,"Source SHA256 matches the preserved download")
	var document := raw_document()
	report["source_structure"] = {"mesh_count":document.get("meshes",[]).size(),"materials":document.get("materials",[]).size(),"images":document.get("images",[]).size(),"skins":document.get("skins",[]).size(),"animations":document.get("animations",[]).size(),"generator":document.get("asset",{}).get("generator","")}
	var packed := ResourceLoader.load(RAW,"PackedScene") as PackedScene
	expect(packed!=null,"ResourceLoader imports the raw GLB as a PackedScene")
	if packed==null:
		finish();return
	setup_stage()
	var raw := packed.instantiate() as Node3D
	world.add_child(raw)
	report["raw_import"] = inspect(raw)
	expect(report.raw_import.mesh_instances.size()==1,"Imported candidate has one mesh instance")
	expect(report.raw_import.material_count==1,"Imported candidate has one material")
	expect(report.raw_import.triangles==29046,"Imported mesh contains 29,046 triangles")
	expect(report.raw_import.skinned_meshes==0 and report.raw_import.skeletons.is_empty(),"Imported candidate has no skin or skeleton")
	expect(report.raw_import.animation_clips.is_empty(),"Imported candidate has no animation clips")
	expect(report.raw_import.mesh_instances[0].blend_shapes==0,"Imported candidate has no facial blend shapes")
	var raw_bounds := model_bounds(raw)
	expect(raw_bounds.size.is_finite() and raw_bounds.size.x>0 and raw_bounds.size.y>0 and raw_bounds.size.z>0,"Imported bounds are finite and nonzero")
	var textures: Dictionary = report.raw_import.materials[0].textures
	for role in ["albedo_texture","metallic_texture","roughness_texture","normal_texture"]:
		expect(textures.has(role),"Imported PBR material binds "+role)
		if textures.has(role): expect(textures[role].readable and textures[role].width==2048 and textures[role].height==2048,"Imported "+role+" is readable at 2048 x 2048")
	world.remove_child(raw)
	report["raw_normalization"] = add_model(raw,.93,Vector3.ONE)
	var current := (ResourceLoader.load(CURRENT,"PackedScene") as PackedScene).instantiate() as JrpgResidentModel
	world.add_child(current)
	current.set_process(false)
	current.animator.stop();current.animator.active = false
	current.skeleton.reset_bone_poses()
	var appearance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CURRENT_APPEARANCE)).residents.haru
	apply_current_palette(current,appearance)
	current.set_age(25)
	report["current_import"] = inspect(current)
	report["current_import"]["frozen_pose"] = "skeleton rest poses reset; animation mixer inactive; no animation playback"
	world.remove_child(current)
	var body: Array = appearance.body_scale
	report["current_normalization"] = add_model(current,-.93,Vector3(body[0],body[1],body[2]))
	for key in ["raw_normalization","current_normalization"]:
		expect(absf(report[key].normalized_height_m-TARGET_HEIGHT)<.00001,key+" reaches 1.71 m using scene transforms")
	await capture("front",0,"Front / rest pose")
	await capture("threequarter",-35,"Three-quarter / rest pose")
	await capture("side",-90,"Side / rest pose")
	await capture("back",180,"Back / generated side is not established by the front reference")
	# Compare the same raw UV/geometry under the intended texture-toon adapter and its
	# imported PBR. This is still a static material test, not a rig or actor test.
	model_turntables[1].hide()
	var raw_toon := packed.instantiate() as Node3D
	world.add_child(raw_toon)
	for node in all_nodes(raw_toon):
		if not node is MeshInstance3D: continue
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface) as StandardMaterial3D
			var toon := ShaderMaterial.new()
			toon.shader = load("res://game/assets/models/resident_toon.gdshader")
			toon.set_shader_parameter("base_palette",source.albedo_texture)
			toon.set_shader_parameter("hair_cells",Vector3i(-1,-1,-1))
			node.set_surface_override_material(surface,toon)
	world.remove_child(raw_toon)
	report["raw_toon_normalization"] = add_model(raw_toon,-.93,Vector3.ONE)
	left_label.text = "Raw / texture toon"
	right_label.text = "Raw / imported PBR"
	report["shader_compare"] = {"shader":"res://game/assets/models/resident_toon.gdshader","atlas_recolored":false,"hair_cells":[-1,-1,-1],"geometry":"same byte-identical imported raw GLB on both sides","lights":"same neutral key .8, fill .2, ambient .35; linear tonemap"}
	await capture("raw-pbr-vs-texturetoon-front",0,"Same raw mesh / front / static material comparison")
	await capture("raw-pbr-vs-texturetoon-threequarter",-35,"Same raw mesh / three-quarter / static material comparison")
	expect(FileAccess.get_sha256(RAW)==sha_before,"Source GLB remains byte-for-byte unchanged")
	expect(FileAccess.get_sha256(original_source)==sha_before,"Original source remains byte-for-byte unchanged")
	finish()

func finish() -> void:
	report["checks"] = checks
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var output := FileAccess.open(output_dir+"/import-check.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t")+"\n")
	print("HARU_GODOT_ASSET_CHECK ",checks-failures.size(),"/",checks," ",output_dir+"/import-check.json")
	quit(0 if failures.is_empty() else 1)

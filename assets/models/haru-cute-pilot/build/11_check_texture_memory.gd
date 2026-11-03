extends SceneTree
# Run in an isolated mini-project copied by 11_prepare_texture_probe.py.
# Each r1/r2/mode pair is a separate native GPU process, without simulation/save.
var variant := "r1"
var mode := "toon"
var checks := 0
var failed: Array[String] = []
var steps: Array[Dictionary] = []
var palette_hash := ""
var model: Node3D

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed.append(message);push_error(message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("variant="): variant = arg.trim_prefix("variant=")
		if arg.begins_with("mode="): mode = arg.trim_prefix("mode=")
	call_deferred("run")

func settle() -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw

func memory(label: String) -> Dictionary:
	var rec := {"label":label,"rendering_texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),"rendering_buffer_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),"performance_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"static_memory_bytes":OS.get_static_memory_usage()}
	steps.append(rec)
	return rec

func digest(image: Image) -> String:
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	var h := HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(image.get_data());return h.finish().hex_encode()

func textures(material: Material) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if material is ShaderMaterial:
		var palette = material.get_shader_parameter("base_palette")
		if palette is Texture2D: result.append(palette)
	elif material is StandardMaterial3D:
		for name in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:
			var texture = material.get(name)
			if texture is Texture2D and texture not in result: result.append(texture)
	return result

func inventory() -> Array[Dictionary]:
	var records := {}
	for level in model.lod_variants.size():
		for record in model.lod_variants[level].values():
			for surface in record.mesh.get_surface_count():
				for texture in textures(record.mesh.surface_get_material(surface)):
					var id := texture.get_instance_id()
					if not records.has(id): records[id] = {"rid":texture.get_rid().get_id(),"path":texture.resource_path,"width":texture.get_width(),"height":texture.get_height(),"levels":[]}
					records[id].levels.append(level)
	var result: Array[Dictionary] = []
	for record in records.values(): result.append(record)
	return result

func run() -> void:
	var world := Node3D.new();root.add_child(world)
	var camera := Camera3D.new();world.add_child(camera);camera.position=Vector3(2.5,1.6,4.5);camera.look_at(Vector3(0,.9,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.1;camera.current=true
	var light := DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=1.0
	var env := WorldEnvironment.new();world.add_child(env);env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.22,.25,.29);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.45
	await settle();memory("empty_viewport")
	model=load("res://game/scripts/jrpg_resident_model.gd").new();model.name="HaruTextureProbe";model.material_mode=1 if mode=="toon" else 2;model.expression_mode=1;model.rest_height=1.71
	var asset: PackedScene = load("res://models/%s/CH_Haru.glb"%variant)
	var imported := asset.instantiate();imported.name="Model";model.add_child(imported);world.add_child(model);model.set_process(false);model.animator.speed_scale=0
	await settle();memory("lod0_only")
	expect(model.import_contract_errors().is_empty(),"LOD0 satisfies skin/clip contract")
	var part: MeshInstance3D = model.lod_parts.values()[0]
	var original_override: Material = part.get_surface_override_material(0)
	var owned_texture: Texture2D = textures(original_override)[0]
	palette_hash=digest(owned_texture.get_image())
	var base_source: StandardMaterial3D = part.mesh.surface_get_material(0)
	expect(textures(base_source).size()==3,"LOD0 source PBR retains original three image resources")
	model.prepare_lods();await settle();memory("lods_prepared")
	expect(model.lod_resources_loaded==2,"Two distance LODs satisfy compatibility")
	var inventory_before := inventory()
	var animator = model.animator;var skeleton = model.skeleton
	animator.play("walk",0);animator.seek(.37,true);animator.advance(0)
	var phase: float = animator.current_animation_position
	var head: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("DEF-head"))
	var levels: Array[Dictionary] = []
	for level in [0,1,2,0]:
		expect(model.set_lod(level),"LOD%d selects"%level)
		await settle()
		var triangles: int = part.mesh.get_faces().size()/3
		expect(triangles==[29046,12199,3485][level],"LOD%d geometry count unchanged"%level)
		expect(part.skin.get_bind_count()==35,"LOD%d keeps skin"%level)
		expect(part.get_surface_override_material(0)==original_override,"LOD%d keeps the actor-owned material resource"%level)
		expect(textures(part.get_surface_override_material(0))[0]==owned_texture,"LOD%d keeps the exact atlas Texture2D instance"%level)
		expect(digest(owned_texture.get_image())==palette_hash,"LOD%d retains atlas pixels"%level)
		expect(skeleton==model.skeleton and animator==model.animator and is_equal_approx(phase,animator.current_animation_position),"LOD%d keeps rig/player/phase"%level)
		expect(head.is_equal_approx(skeleton.get_bone_global_pose(skeleton.find_bone("DEF-head"))),"LOD%d keeps animated joint pose"%level)
		var screenshot := "res://output/%s-%s-lod%d.png"%[variant,mode,level]
		root.get_texture().get_image().save_png(screenshot)
		levels.append({"level":level,"triangles":triangles,"bind_count":part.skin.get_bind_count(),"material_instance_id":original_override.get_instance_id(),"atlas_texture_rid":owned_texture.get_rid().get_id()})
	memory("lod_switch_cycle")
	var output := {"variant":variant,"mode":mode,"checks":checks,"failed":failed,"steps":steps,"texture_inventory":inventory_before,"unique_lod_source_textures":inventory_before.size(),"base_atlas_pixel_sha256":palette_hash,"source_pbr_images":textures(base_source).size(),"lods":levels,"display_server":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"method":"Isolated minimal project using a snapshot of the real JrpgResidentModel and real GLBs; separate native GPU process per variant/mode, empty viewport then actor/LOD load. Not town performance or human playtesting."}
	var file := FileAccess.open("res://output/%s-%s.json"%[variant,mode],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t")+"\n")
	print("HARU_TEXTURE_MEMORY ",variant," ",mode," ",checks-failed.size(),"/",checks," steps=",steps)
	quit(0 if failed.is_empty() else 1)

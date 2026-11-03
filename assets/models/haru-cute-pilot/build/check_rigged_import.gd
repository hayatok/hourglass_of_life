extends SceneTree
# Inspect the actual adapter scene and all three skinned LODs. No simulation decisions.
var checks := 0
var failed: Array[String] = []
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failed.append(message);push_error(message)
func image_digest(image: Image) -> String:
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
	return hash.finish().hex_encode()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var model := load("res://game/scenes/characters/haru.tscn").instantiate() as JrpgResidentModel
	root.add_child(model);model.set_process(false);model.animator.speed_scale = 0
	var capability := model.capabilities()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/models/haru/asset-manifest.json"))
	expect(manifest.face_controls.names==capability.facial_controls and manifest.face_controls.expression_mode==capability.expression_mode,"Manifest eye capabilities match the actual adapter")
	expect(capability.source_model=="res://game/assets/models/haru/CH_Haru.glb","Actual scene references the new Haru GLB")
	expect(capability.contract_errors.is_empty(),"New Haru satisfies the real bone/skin/clip contract")
	expect(model.material_mode==JrpgResidentModel.MaterialMode.TEXTURE_TOON and not model.uses_palette_swatches(),"New Haru uses texture toon without palette swatches")
	expect(model.expression_mode==JrpgResidentModel.ExpressionMode.TEXTURE_EYES and capability.facial_controls==["Blink","TiredEyes"],"Exactly two real UV eye controls are declared; mouth and morph limitations stay explicit")
	var palette: Texture2D = model.body_materials[0].get_shader_parameter("base_palette")
	var actual_hash := image_digest(palette.get_image())
	var expected_hash := image_digest(Image.load_from_file("res://assets/models/haru-cute-pilot/review/texture-face/source-basecolor.jpg"))
	var skeleton := model.skeleton;var player := model.animator
	model.prepare_lods()
	expect(model.lod_resources_loaded==2,"Both actual LOD resources are compatible and loaded")
	player.play("walk",0);player.seek(.37,true);player.advance(0)
	var phase := player.current_animation_position
	var head := skeleton.get_bone_global_pose(skeleton.find_bone("DEF-head"))
	var levels := []
	for level in [0,1,2,0]:
		expect(model.set_lod(level),"Real LOD%d selects successfully"%level)
		var triangles := 0;var binds := []
		for part in model.lod_parts.values():
			triangles += part.mesh.get_faces().size()/3;binds.append(part.skin.get_bind_count())
		expect(triangles==int(manifest.lods[level].tris),"LOD%d actual triangle count matches the current frozen delivery"%level)
		expect(model.import_contract_errors().is_empty() and binds==[35],"LOD%d keeps real 35-bind skin"%level)
		expect(model.skeleton==skeleton and model.animator==player and is_equal_approx(phase,player.current_animation_position),"LOD selection keeps skeleton/player/animation phase")
		expect(head.is_equal_approx(skeleton.get_bone_global_pose(skeleton.find_bone("DEF-head"))),"LOD selection keeps the actual animated head pose")
		levels.append({"level":level,"triangles":triangles,"skin_binds":binds})
	var output := FileAccess.open("res://assets/models/haru-cute-pilot/review/godot/rigged-import-check.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"purpose":"Actual skinned scene/resource/LOD import contract, not gameplay or deformation-quality approval","count_policy":"Functional import/LOD assertions only; source fingerprints excluded.","checks":checks,"failed":failed,"capabilities":capability,"lods":levels,"provenance":{"texture_pixel_sha256":actual_hash,"source_jpeg_pixel_sha256":expected_hash,"note":"Input identifiers only; not checks or pass/fail gates."},"display_server":DisplayServer.get_name()},"\t")+"\n")
	print("HARU_RIGGED_IMPORT_CHECK ",checks-failed.size(),"/",checks)
	quit(0 if failed.is_empty() else 1)

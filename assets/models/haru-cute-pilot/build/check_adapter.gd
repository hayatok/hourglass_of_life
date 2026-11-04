extends SceneTree
# GPU diagnostic for the material adapter using the pinned pre-renewal shared rig.
# Godot --path <project> --script res://assets/models/haru-cute-pilot/build/check_adapter.gd
# This is not a new-mesh actor or gameplay test.
var checks := 0
var failed: Array[String] = []
var provenance := {"note":"Input fingerprints only; not checks or gates."}
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failed.append(message);push_error(message)
func digest(texture: Texture2D) -> String:
	var source := texture.get_image()
	return source.get_data().hex_encode().sha256_text()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var camera := Camera3D.new();camera.position = Vector3(0,1,5);root.add_child(camera);camera.look_at(Vector3(0,1,0));camera.current = true
	var scene := load("res://assets/models/haru-cute-pilot/build/fixtures/haru-placeholder.tscn") as PackedScene
	for mode in [JrpgResidentModel.MaterialMode.PALETTE_TOON,JrpgResidentModel.MaterialMode.TEXTURE_TOON,JrpgResidentModel.MaterialMode.SOURCE_PBR]:
		var model := scene.instantiate() as JrpgResidentModel
		model.material_mode = mode
		if mode!=JrpgResidentModel.MaterialMode.PALETTE_TOON: model.expression_mode = JrpgResidentModel.ExpressionMode.STATIC_ATLAS
		root.add_child(model)
		await process_frame
		model.set_process(false);model.animator.speed_scale = 0
		expect(model.import_contract_errors().is_empty(),"existing rig imports in explicit material mode %d"%mode)
		expect(model.uses_palette_swatches()==(mode==0),"only palette mode authorizes swatch replacement")
		expect(model.capabilities().facial_controls.size()==(6 if mode==0 else 0),"static atlas does not advertise six facial controls")
		if mode==JrpgResidentModel.MaterialMode.TEXTURE_TOON:
			var material: ShaderMaterial = model.body_materials[0]
			var texture: Texture2D = material.get_shader_parameter("base_palette")
			var before := digest(texture)
			expect(material.get_shader_parameter("hair_cells")==Vector3i(-1,-1,-1),"texture atlas ignores legacy hair cells")
			material.set_shader_parameter("hair_age",0.0)
			model.set_age(72)
			expect(is_zero_approx(material.get_shader_parameter("hair_age")),"texture atlas cannot receive palette hair aging")
			var avatar = load("res://game/scenes/resident_avatar.tscn").instantiate()
			root.add_child(avatar);avatar.jrpg = model;avatar.resident_id = "haru"
			avatar.appearance = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/haru-cute-pilot/build/fixtures/haru-placeholder-appearance.json")).residents.haru
			avatar._apply_variant_palette()
			provenance["atlas_before_pixel_fingerprint"] = before
			provenance["atlas_after_pixel_fingerprint"] = digest(texture)
			avatar.jrpg = null;avatar.queue_free()
			await process_frame
		if mode==JrpgResidentModel.MaterialMode.PALETTE_TOON:
			model.set_age(72)
			expect(is_equal_approx(model.body_materials[0].get_shader_parameter("hair_age"),.9),"legacy model keeps its real aging behavior")
		if mode==JrpgResidentModel.MaterialMode.SOURCE_PBR:
			expect(model.body_materials.is_empty(),"PBR inspection does not create toon material wrappers")
			for part in model.lod_parts.values():
				for surface in part.mesh.get_surface_count(): expect(part.get_active_material(surface) is StandardMaterial3D,"PBR mode retains imported standard materials")
		await process_frame
		await RenderingServer.frame_post_draw
		root.remove_child(model);model.queue_free()
		await process_frame
	var invalid := JrpgResidentModel.new()
	expect(invalid.import_contract_errors().size()==4,"missing rig/skin/player/face is reported rather than silently accepted")
	invalid.free()
	var output := FileAccess.open("res://assets/models/haru-cute-pilot/review/godot/adapter-check.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"display_server":DisplayServer.get_name(),"count_policy":"Functional adapter assertions only; input identity excluded.","checks":checks,"failed":failed,"provenance":provenance,"fixture":"afb4c32 shared-rig Haru used to isolate material adapters before the new rig arrives; not new-mesh gameplay"},"\t")+"\n")
	print("HARU_ADAPTER_CHECK ",checks-failed.size(),"/",checks)
	quit(0 if failed.is_empty() else 1)

extends SceneTree
# Actual rigged Haru eye shader, kept separate from gameplay tests.
const OUT := "res://assets/models/haru-cute-pilot/review/godot/texture-eyes"
var checks := 0
var failed: Array[String] = []
var model: JrpgResidentModel
var camera: Camera3D
var images: Dictionary = {}
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failed.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
func eyes() -> ShaderMaterial: return model.body_materials[0]
func capture(name: String) -> void:
	var pose := model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.skeleton.find_bone("DEF-head"))
	var target: Vector3 = pose*Vector3(0,.10,0)
	camera.global_position = target+pose.basis.z.normalized()*3
	camera.look_at(target,pose.basis.y.normalized())
	await process_frame;await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	expect(image.save_png(OUT+"/"+name+".png")==OK,"Saved actual eye shader "+name)
	images[name] = image
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));root.size = Vector2i(640,640);root.content_scale_size = Vector2i(640,640)
	var stage := Node3D.new();root.add_child(stage)
	var env := WorldEnvironment.new();env.environment = Environment.new();env.environment.background_mode = Environment.BG_COLOR;env.environment.background_color = Color("#353f50")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color = Color.WHITE;env.environment.ambient_light_energy = .35;stage.add_child(env)
	var light := DirectionalLight3D.new();light.rotation_degrees = Vector3(-30,-30,0);light.light_energy = .8;stage.add_child(light)
	var fill := DirectionalLight3D.new();fill.rotation_degrees = Vector3(-20,135,0);fill.light_energy = .2;stage.add_child(fill)
	camera = Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = .43;stage.add_child(camera);camera.current = true
	model = load("res://game/scenes/characters/haru.tscn").instantiate();stage.add_child(model);model.set_process(false);model.animator.speed_scale = 0
	expect(model.import_contract_errors().is_empty(),"Actual rig has a valid calibrated texture-eye contract")
	expect(model.capabilities().facial_controls==["Blink","TiredEyes"],"Only the two actual UV controls are advertised")
	expect(eyes().shader.resource_path=="res://game/assets/models/haru/haru_texture_eyes.gdshader","Actual model uses the dedicated Haru eye shader")
	model.animator.play("idle",0);model.animator.seek(.6,true);model.animator.advance(0)
	model.elapsed = 0;model.set_expression(0,1);model._process(0)
	expect(is_zero_approx(eyes().get_shader_parameter("blink")),"Ordinary open state does not force eye closure")
	await capture("open-lod0")
	model.elapsed = 2.81;model._process(0)
	expect(is_equal_approx(eyes().get_shader_parameter("blink"),1),"Existing blink clock drives a real closed-eye shader state")
	await capture("blink-lod0")
	var original_material := eyes();var original_atlas: Texture2D = eyes().get_shader_parameter("base_palette")
	for level in [1,2,0]:
		expect(model.set_lod(level),"Actual LOD%d selects with texture eyes"%level)
		expect(eyes()==original_material and eyes().get_shader_parameter("base_palette")==original_atlas,"LOD retains the owned shader and source atlas")
		expect(is_equal_approx(eyes().get_shader_parameter("blink"),1),"LOD preserves active blink value")
		await capture("blink-lod%d"%level)
	model.elapsed = 0;model.set_expression(1,0);model._process(0)
	expect(is_equal_approx(eyes().get_shader_parameter("tired_eyes"),.7),"Actual fatigue drives TiredEyes within the established intensity limit")
	await capture("tired-lod0")
	for level in [1,2,0]:
		model.set_lod(level)
		expect(is_equal_approx(eyes().get_shader_parameter("tired_eyes"),.7),"LOD preserves nonzero TiredEyes intensity")
	model.set_expression(0,0);model.animator.play("sleep",0);model.animator.seek(.6,true);model.animator.advance(0);model._process(0)
	expect(is_equal_approx(eyes().get_shader_parameter("blink"),1),"Sleep forces full closure outside the periodic blink window")
	await capture("sleep")
	model.animator.play("idle",0);model.animator.seek(.6,true);model.animator.advance(0);model._process(0)
	expect(is_zero_approx(eyes().get_shader_parameter("blink")),"Waking restores ordinary open eyes")
	expect(is_zero_approx(eyes().get_shader_parameter("tired_eyes")),"Recovered fatigue clears TiredEyes")
	var pixels := 0;var bounds := Rect2i()
	var baseline: Image = images["open-lod0"]
	for y in baseline.get_height():
		for x in baseline.get_width():
			var a: Color = images["open-lod0"].get_pixel(x,y)
			var b: Color = images["blink-lod0"].get_pixel(x,y)
			if maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),absf(a.b-b.b))>.03:
				bounds = Rect2i(x,y,1,1) if pixels==0 else bounds.expand(Vector2i(x,y));pixels += 1
	expect(pixels>300,"Open and blink differ in actual GPU-rendered pixels")
	# The fixed pose/camera and unchanged atlas constrain differences to the eye strip.
	expect(bounds.size.y<160 and bounds.size.x<460,"Blink does not alter mouth, costume or the full image")
	var layout := model.face_layout;model.face_layout = {"eyes":{}}
	expect(not model.import_contract_errors().is_empty(),"Missing eye calibration is rejected rather than advertised as support")
	model.face_layout = layout
	FileAccess.open(OUT+"/checks.json",FileAccess.WRITE).store_string(JSON.stringify({"purpose":"Actual rigged resource/UV-eye GPU stage, not gameplay","checks":checks,"failed":failed,"capabilities":model.capabilities(),"blink_changed_pixels":pixels,"blink_difference_bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"source_atlas_unchanged":true,"mouth_smile_sad_look_controls_supported":false},"\t")+"\n")
	print("HARU_TEXTURE_EYES ",checks-failed.size(),"/",checks)
	quit(0 if failed.is_empty() else 1)

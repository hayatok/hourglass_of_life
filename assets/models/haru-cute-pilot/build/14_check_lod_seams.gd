extends SceneTree
var variant := "r2"
var model: Node3D
var camera: Camera3D
var checks := 0
var failed: Array[String] = []
var captures: Array[Dictionary] = []

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed.append(message);push_error(message)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("variant="): variant=arg.trim_prefix("variant=")
	call_deferred("run")
func settle() -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
func pose(name: String) -> void:
	model.animator.play("idle",0);model.animator.seek(.6,true);model.animator.advance(0)
	if name=="rest": model.animator.stop();model.skeleton.reset_bone_poses()
	if name=="head-turn":
		var head: int = model.skeleton.find_bone("DEF-head")
		model.skeleton.set_bone_pose_rotation(head,model.skeleton.get_bone_pose_rotation(head)*Quaternion(Vector3.UP,.60))
	model.skeleton.force_update_all_bone_transforms()
func capture(level: int, state: String, near: bool) -> void:
	pose(state);expect(model.set_lod(level),"LOD switches in "+state)
	var target := Vector3(0,1.50,0) if near else Vector3(0,.855,0)
	camera.position=target+Vector3(0,0,3) if near else target+Vector3(2,1.2,4)
	camera.look_at(target);camera.size=.60 if near else 1.71*640.0/(96.0 if level==1 else 40.0)
	await settle()
	var image:=root.get_texture().get_image();var filename: String="%s-lod%d-%s-%s.png"%[variant,level,state,"close" if near else "normal"]
	image.save_png("res://output/"+filename)
	var head_pose: Transform3D=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.skeleton.find_bone("DEF-head"))
	var roi:=Rect2i();var first:=true
	for x in [-.043,.043]:
		for y in [.040,.155]:
			var screen: Vector2=camera.unproject_position(head_pose*Vector3(x,y,.10))
			roi=Rect2i(Vector2i(screen),Vector2i.ONE) if first else roi.expand(Vector2i(screen));first=false
	var background:=image.get_pixel(0,0);var holes:=0
	if near:
		for y in range(maxi(0,roi.position.y),mini(640,roi.end.y)):
			for x in range(maxi(0,roi.position.x),mini(640,roi.end.x)):
				var c:=image.get_pixel(x,y)
				if maxf(maxf(absf(c.r-background.r),absf(c.g-background.g)),absf(c.b-background.b))<.002:holes+=1
	captures.append({"file":filename,"level":level,"state":state,"near":near,"face_inner_roi":[roi.position.x,roi.position.y,roi.size.x,roi.size.y],"background_pixels_in_face_inner_roi":holes,"camera_size":camera.size})
func run() -> void:
	root.size=Vector2i(640,640);root.content_scale_size=Vector2i(640,640)
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("#353f50");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.35;stage.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-30,0);light.light_energy=.8;stage.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,135,0);fill.light_energy=.2;stage.add_child(fill)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;stage.add_child(camera);camera.current=true
	model=load("res://game/scripts/jrpg_resident_model.gd").new();model.material_mode=1;model.expression_mode=2;model.face_layout_path="res://game/assets/models/haru/face-layout.json"
	var imported: Node3D=load("res://models/"+variant+"/CH_Haru.glb").instantiate();imported.name="Model";model.add_child(imported);stage.add_child(model);model.set_process(false);model.animator.speed_scale=0;model.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;model.body_materials[0].set_shader_parameter("blink",1.0)
	expect(model.import_contract_errors().is_empty(),"Current eye adapter satisfies source/rig contract")
	model.prepare_lods();expect(model.lod_resources_loaded==2,"Both geometry-only LODs remain compatible")
	for state in ["rest","idle","head-turn"]:
		for level in [0,1,2]: await capture(level,state,true)
		for level in [1,2]: await capture(level,state,false)
	FileAccess.open("res://output/"+variant+"-checks.json",FileAccess.WRITE).store_string(JSON.stringify({"variant":variant,"checks":checks,"failed":failed,"captures":captures,"purpose":"LOD crack comparison in current eye adapter, rest/idle .6s/head-turn .6rad; close forced LOD and 96px/40px approximate normal size. Face ROI counts are supporting evidence, not sole visual acceptance."},"\t")+"\n")
	print("LOD_SEAM_CHECK ",variant," ",checks-failed.size(),"/",checks)
	quit(0 if failed.is_empty() else 1)

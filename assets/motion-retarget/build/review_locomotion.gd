extends SceneTree

# Actual engine frames, fixed physical 60Hz and real-time playback. This stage
# diagnoses the whole body; render completion is not natural-gait acceptance.
var actor: FoundationResident
var camera: Camera3D
var label: Label
var angle := "normal"
var who := "nagisa"
var record_all := false
var out := ""
var frame := 0
var phase := "idle"
var samples: Array=[]
var errors: Array[String]=[]

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("GPU review needs a rendered viewport");quit(1);return
	if root.has_node("Sim"): root.get_node("Sim").set_process(false)
	Engine.max_fps=60
	var args := OS.get_cmdline_user_args()
	if args.size()>0: who=args[0]
	if args.size()>1: angle=args[1]
	record_all=args.has("--record")
	if angle not in ["normal","front","side"]: quit(1);return
	var run_id := Time.get_datetime_string_from_system().replace(":","")
	out="res://builds/motion-retarget/locomotion-review/"+run_id+"-"+who+"-"+angle
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out+"/frames"))
	print("LOCOMOTION GPU output "+out)
	root.size=Vector2i(960,900)
	var world := Node3D.new();root.add_child(world)
	var environment := Environment.new();environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("deded4");environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("fff4dc");environment.ambient_light_energy=.32
	var env := WorldEnvironment.new();env.environment=environment;world.add_child(env)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_energy=.55;sun.shadow_enabled=true;world.add_child(sun)
	var plane := MeshInstance3D.new();var mesh := PlaneMesh.new();mesh.size=Vector2(40,40);plane.mesh=mesh
	var floor_mat := StandardMaterial3D.new();floor_mat.albedo_color=Color("888c86")
	plane.material_override=floor_mat;world.add_child(plane)
	var grid_mat := StandardMaterial3D.new();grid_mat.albedo_color=Color("b2ab98")
	for index in range(-3,15):
		for along_x in [true,false]:
			var line := MeshInstance3D.new();var box := BoxMesh.new()
			box.size=Vector3(30,.001,.008) if along_x else Vector3(.008,.001,30)
			line.mesh=box;line.material_override=grid_mat
			line.position=Vector3(0,.001,index) if along_x else Vector3(index,.001,5)
			world.add_child(line)
	actor=FoundationResident.new();world.add_child(actor)
	if not actor.load_resident(who): errors.append("Model/library load failed");finish();return
	var speed := 1.1 if who=="nagisa" else float(actor.motion_contract.clips.walk.authored_speed_mps)
	if not actor.configure({"walk_speed":speed,"turn_speed":PI/2}) or not actor.enable_contact_locomotion():
		errors.append("Contact locomotion configure failed");finish();return
	camera=Camera3D.new();camera.fov=43 if angle=="normal" else 36;camera.current=true;world.add_child(camera)
	var canvas := CanvasLayer.new();world.add_child(canvas)
	label=Label.new();label.position=Vector2(18,16);label.add_theme_font_size_override("font_size",21);canvas.add_child(label)
	await hold("idle",60)
	phase="departure-walk-arrival";actor.follow_path([Vector3(0,0,10)])
	await until_settled(1500)
	await hold("stopped",30)
	phase="turn90"
	if not actor.face_heading(PI/2): errors.append("90-degree turn was not accepted")
	await until_settled(180)
	await hold("after90",30)
	phase="turn180"
	if not actor.face_heading(-PI/2): errors.append("180-degree turn was not accepted")
	await until_settled(240)
	await hold("after180",30)
	finish()

func tick_frame() -> void:
	if not actor.tick_body(1.0/60): errors.append("Body tick rejected")
	# Match the real household follow camera: yaw .45, pitch .88, distance10,
	# FOV43 and target half a metre above the motor. Front/side are close reviews.
	var offset := Vector3(sin(.45)*cos(.88),sin(.88),cos(.45)*cos(.88))*10
	var focus := Vector3(0,.5,0) if angle=="normal" else Vector3(0,actor.model.rest_height*.5,0)
	if angle=="front": offset=Vector3(0,1.15,4.2)
	elif angle=="side": offset=Vector3(4.2,1.15,0)
	camera.position=actor.global_position+offset+(focus if angle=="normal" else Vector3.ZERO)
	camera.look_at(actor.global_position+focus)
	label.text=who+" / "+angle+" / "+phase+" / "+actor.state()
	await process_frame
	await RenderingServer.frame_post_draw
	if record_all or frame%15==0:
		var image := root.get_texture().get_image()
		var target: String=out+"/frames/%06d.png"%frame if record_all else out+"/"+phase+"-%06d.png"%frame
		if image.save_png(target)!=OK: errors.append("Could not save "+target)
	if frame%15==0:
		samples.append({"frame":frame,"physical_seconds":frame/60.0,"phase":phase,"motor":actor.snapshot(),"presentation":actor.locomotion.snapshot()})
	frame+=1

func hold(name: String, frames: int) -> void:
	phase=name
	print("LOCOMOTION GPU "+who+"/"+angle+" "+phase+" at frame "+str(frame))
	for ignored in frames: await tick_frame()

func until_settled(limit: int) -> void:
	for ignored in limit:
		await tick_frame()
		if actor.body_is_settled(): return
	errors.append("Body failed to settle during "+phase)

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	FileAccess.open(out+"/review.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Actual GPU whole-body engine frames. Natural gait and ordinary-speed visual acceptance remain a review decision, not an export/test result.","target":who,"angle":angle,"viewport_pixels":[root.size.x,root.size.y],"fps":60,"frames":frame,"physical_seconds":frame/60.0,"recorded_every_frame":record_all,"errors":errors,"samples":samples},"\t"))
	print("Locomotion GPU frames: "+who+"/"+angle+" "+str(frame)+" frames; errors="+str(errors))
	quit(0 if errors.is_empty() else 1)

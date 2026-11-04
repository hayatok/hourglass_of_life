extends SceneTree

# Staged candidates on the real existing three skins; no FoundationWorld,
# HouseholdPose, controller or runtime animation library is modified or used.
# --validate-only is headless. GPU plays all nine clips at original speed,
# captures five whole-body samples and exits. This is an asset-motion review.
const TARGETS := ["nagisa","ryo","rin"]
const CLIPS := ["cmu_chop","cmu_mix","cmu_soup"]
var directory := "res://builds/motion-retarget/cmu"
var validate_only := false
var data: Dictionary = {}
var stage: Node3D
var camera: Camera3D
var clock_label: Label
var elapsed := 0.0
var duration := 0.0
var capture_busy := false
var next_capture := 0
var artifacts: Array = []
var checks := 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument=="--validate-only":validate_only=true
		elif argument.begins_with("--directory="):directory=argument.trim_prefix("--directory=")
	create_timer(50).timeout.connect(func():push_error("CMU retarget asset review timed out");quit(1))
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func read_json(path: String) -> Variant:return JSON.parse_string(FileAccess.get_file_as_string(path))

func add_target(id: String, key: String, column: int, row: int) -> bool:
	var contract: Variant=read_json(directory+"/"+id+"/candidate.contract.json")
	var observed: Variant=read_json(directory+"/"+id+"/"+key+".samples.json")
	var resource: Variant=load(directory+"/"+id+"/candidate.tres")
	if not contract is Dictionary or not observed is Dictionary or not resource is AnimationLibrary or not resource.has_animation(key):return false
	var scene: PackedScene=load("res://game/scenes/characters/"+id+".tscn")
	var model: Node3D=scene.instantiate();stage.add_child(model);model.position=Vector3((column-1)*2.5,0,(row-1)*3.0)
	model.set_process(false)
	var animator: AnimationPlayer=model.get("animator");var skeleton: Skeleton3D=model.get("skeleton")
	if animator==null or skeleton==null:return false
	animator.stop();animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var animation_root: Node=animator.get_node(animator.root_node)
	var path: String=str(animation_root.get_path_to(skeleton))
	var library := resource.duplicate(true) as AnimationLibrary
	for clip_name in library.get_animation_list():
		var animation: Animation=library.get_animation(clip_name)
		for track in animation.get_track_count():
			var original: NodePath=animation.track_get_path(track)
			if original.get_subname_count()!=1:return false
			animation.track_set_path(track,NodePath(path+":"+str(original.get_subname(0))))
	animator.add_animation_library("cmu_candidate",library)
	animator.play("cmu_candidate/"+key)
	var rest := {};var root_bone: int=skeleton.find_bone("DEF-root")
	for bone in skeleton.get_bone_count():rest[skeleton.get_bone_name(bone)]=skeleton.get_bone_rest(bone)
	var label := Label3D.new();label.text=id+"  "+key.trim_prefix("cmu_");label.font_size=34;label.pixel_size=.005;label.outline_size=0;label.modulate=Color("494439");label.position=Vector3(0,2.03,0);model.add_child(label)
	data[id+":"+key]={"model":model,"animator":animator,"skeleton":skeleton,"rest":rest,"root":root_bone,"clip":key,"id":id,
		"observations":observed.frames,"contract":contract.clips[key],"animation":library.get_animation(key),"root_pose":skeleton.get_bone_rest(root_bone)}
	duration=maxf(duration,float(contract.clips[key].length_seconds))
	return true

func pose(row: Dictionary, seconds: float) -> void:
	row.animator.seek(minf(seconds,float(row.contract.length_seconds)),true);row.animator.advance(0)
	row.skeleton.advance(0)

func actor_joint(row: Dictionary, name: String) -> Vector3:
	var skeleton: Skeleton3D=row.skeleton
	return row.model.global_transform.affine_inverse()*(skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(name))).origin

func check_target(row: Dictionary) -> void:
	var endpoints := 0.0;var offsets := 0.0;var root_drift := 0.0;var scale_error := 0.0
	var skin_count := 0;var skins_bound := true
	for node in row.model.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=node
		if mesh.skin==null:continue
		skin_count+=1;skins_bound=skins_bound and mesh.skin.get_bind_count()==35 and mesh.get_node_or_null(mesh.skeleton)==row.skeleton
	var first_hand := Vector3.ZERO;var moving_hand := Vector3.ZERO
	var middle: int=floori(float(row.observations.size())*.5)
	for index in [0,middle,row.observations.size()-1]:
		var observed: Dictionary=row.observations[int(index)];var at: float=float(observed.source_time_seconds)
		pose(row,at)
		for side in ["L","R"]:
			endpoints=maxf(endpoints,actor_joint(row,"DEF-hand."+side).distance_to(point(observed.target_hand_joint_m[side])))
			endpoints=maxf(endpoints,actor_joint(row,"DEF-foot."+side).distance_to(point(observed.target_ankle_joint_m[side])))
		for bone in row.skeleton.get_bone_count():
			var name: String=row.skeleton.get_bone_name(bone)
			if name!="DEF-pelvis":offsets=maxf(offsets,row.skeleton.get_bone_pose_position(bone).distance_to(row.rest[name].origin))
		var animation: Animation=row.animation
		for track in animation.get_track_count():
			if animation.track_get_type(track)!=Animation.TYPE_SCALE_3D:continue
			var name: String=str(animation.track_get_path(track).get_subname(0));var bone: int=row.skeleton.find_bone(name)
			scale_error=maxf(scale_error,row.skeleton.get_bone_pose_scale(bone).distance_to(animation.scale_track_interpolate(track,0)))
		root_drift=maxf(root_drift,row.skeleton.get_bone_pose_position(row.root).distance_to(row.root_pose.origin))
		if int(index)==0:first_hand=actor_joint(row,"DEF-hand.R")
		elif int(index)==middle:moving_hand=actor_joint(row,"DEF-hand.R")
	expect(endpoints<.00002,row.id+"/"+row.clip+": native imported hand/ankle joint positions match the CPU whole-body candidate at first, middle and last source sample")
	expect(offsets<.000002 and root_drift<.000002 and scale_error<.000002,row.id+"/"+row.clip+": actual rig keeps fixed nonpelvis local offsets, root and constant encoded scales")
	expect(skin_count>0 and skins_bound and first_hand.distance_to(moving_hand)>.025,row.id+"/"+row.clip+": actual imported skins bind to the driven skeleton and its hand motion is not static rest")
	measurements[row.id+":"+row.clip]={"max_joint_error_m":endpoints,"max_fixed_local_offset_error_m":offsets,"root_local_drift_m":root_drift,"constant_scale_error":scale_error,"skinned_parts":skin_count,"first_to_mid_hand_motion_m":first_hand.distance_to(moving_hand),"contact_verified":false}
	pose(row,0)

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	if DisplayServer.get_name()=="headless" and not validate_only:push_error("Use --validate-only or the coordinated GPU slot");quit(1);return
	root.size=Vector2i(1600,1100);stage=Node3D.new();root.add_child(stage)
	var world := WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("c5d0c9");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color("fff1da");world.environment.ambient_light_energy=.45;stage.add_child(world)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-30,0);sun.light_energy=.6;sun.shadow_enabled=true;stage.add_child(sun)
	var ground := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(12,12);ground.mesh=plane
	var paint := StandardMaterial3D.new();paint.albedo_color=Color("b7b69c");paint.roughness=1;ground.material_override=paint;stage.add_child(ground)
	for column in TARGETS.size():
		for row in CLIPS.size():
			if not add_target(TARGETS[column],CLIPS[row],column,row):push_error("Missing candidate/target "+TARGETS[column]+" "+CLIPS[row]);quit(1);return
	for value: Dictionary in data.values():check_target(value)
	FileAccess.open(directory+"/native-results.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Real imported skins driven by staged candidate AnimationLibrary; no household action, sole plant, finger grasp, props, cloth or human naturalness acceptance.","checks":checks,"failures":failures,"measurements":measurements},"\t"))
	print("CMU retarget native geometry: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	if not failures.is_empty():quit(1);return
	if validate_only:stage.free();quit(0);return
	camera=Camera3D.new();stage.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10.8
	camera.position=Vector3(8,10,15);camera.look_at(Vector3(0,.7,0))
	var canvas := CanvasLayer.new();root.add_child(canvas)
	var title := Label.new();title.position=Vector2(25,18);title.text="CMU → real DEF rigs • staged animation only • no prop/sole/finger contact acceptance";title.add_theme_font_size_override("font_size",25);title.add_theme_color_override("font_color",Color("494439"));canvas.add_child(title)
	clock_label=Label.new();clock_label.position=Vector2(25,55);clock_label.add_theme_font_size_override("font_size",22);clock_label.add_theme_color_override("font_color",Color("494439"));canvas.add_child(clock_label)
	capture_busy=true;next_capture=1;capture(0)

func _process(delta: float) -> bool:
	if not is_instance_valid(camera):return false
	if not capture_busy:elapsed=minf(duration,elapsed+delta)
	for value: Dictionary in data.values():pose(value,elapsed)
	clock_label.text="%.2f / %.2f s   |   rows: chop / mix / soup; columns: Nagisa / Ryo / Rin"%[elapsed,duration]
	if not capture_busy and next_capture<5 and elapsed>=duration*next_capture/4:capture_busy=true;capture(next_capture);next_capture+=1
	if elapsed>=duration and next_capture>=5 and not capture_busy:
		FileAccess.open(directory+"/native-review.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Staged actual-skin full-body motion review only; not game integration, prop contact, finger/sole/cloth or human play acceptance.","duration_s":duration,"clips":CLIPS,"targets":TARGETS,"artifacts":artifacts,"artifact_writes_are_not_functional_checks":true},"\t"))
		stage.free();quit(0)
	return false

func capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	var name: String="candidate-%02d.png"%index;var result: Error=root.get_texture().get_image().save_png(directory+"/"+name)
	artifacts.append({"path":name,"time_s":elapsed,"write_result":result});capture_busy=false

extends SceneTree

# Isolated real chair/rig fixture. RootMotor owns all body movement; the chair
# follows the same authored track. Actual house navigation/life is outside scope.
var actor: FoundationResident
var chair: Node3D
var camera: Camera3D
var caption: Label
var fixture: Dictionary
var source_fixture: Dictionary
var who := "nagisa"
var rendered := false
var record_all := false
var out := ""
var samples := 0
var frame := 0
var checks := 0
var failures: Array[String] = []
var phase_name := "idle"
var progress := 0.0
var before_motor := Transform3D.IDENTITY
var node_changed := false
var position_error := 0.0
var scale_error := 0.0
var results: Dictionary = {}
var observations: Array = []
var physical_root_start := Transform3D.IDENTITY
var physical_root_end := Transform3D.IDENTITY
var chair_start := Vector3.ZERO
var request: Dictionary = {}
var saved_once := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label);push_error(label)

func capture() -> void:
	samples+=1
	node_changed=node_changed or not actor.global_transform.is_equal_approx(before_motor)
	var skeleton: Skeleton3D=actor.model.skeleton
	for side in ["L","R"]:
		for part in ["thigh","shin","foot","upper_arm","forearm","hand"]:
			var index := skeleton.find_bone("DEF-"+part+"."+side)
			position_error=maxf(position_error,skeleton.get_bone_pose_position(index).distance_to(skeleton.get_bone_rest(index).origin))
			scale_error=maxf(scale_error,skeleton.get_bone_pose_scale(index).distance_to(Vector3.ONE))

func same(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<.00001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not same(a[i],b[i]): return false
		return true
	return a==b

func flush(delta: float) -> void:
	var prior := samples
	before_motor=actor.global_transform
	actor.tick_body(delta,false)
	var deadline := Time.get_ticks_msec()+2000
	while samples==prior and Time.get_ticks_msec()<deadline: await process_frame
	if samples==prior: check(false,"Actual skeleton callback watchdog");quit(1);return
	if rendered:
		camera.position=Vector3(3.0,1.9,3.0)
		camera.look_at(Vector3(0,.7,-.12))
		caption.text=who+" / "+phase_name+" / "+str(snappedf(progress,.01))
		await RenderingServer.frame_post_draw
		if record_all or frame%6==0:
			root.get_texture().get_image().save_png(out+"/%s-%05d.png"%[phase_name,frame])
	frame+=1

func read_observation() -> void:
	var value: Dictionary=actor.furniture_pose.telemetry()
	if value.is_empty(): return
	if not results.has(phase_name):results[phase_name]={"samples":0,"reach_m":0.0,"point_error_m":0.0,"support_y_error_m":0.0,"rail_penetration_m":0.0,"hand_error_m":0.0,"seat_error_m":0.0,"moving_without_floor":0,"tasks":{}}
	var row: Dictionary=results[phase_name];row.samples+=1
	row.reach_m=maxf(float(row.reach_m),float(value.feet.unreachable_peak_m))
	row.rail_penetration_m=maxf(float(row.rail_penetration_m),float(value.feet.rail_penetration_m))
	var floor_contact := false
	for side in value.feet.sides:
		var foot: Dictionary=value.feet.sides[side]
		row.tasks[foot.contact_task]=true
		if foot.required:
			row.point_error_m=maxf(float(row.point_error_m),float(foot.target_point_error_m))
			row.support_y_error_m=maxf(float(row.support_y_error_m),float(foot.support_error_m))
			floor_contact=floor_contact or (foot.support_kind=="floor" and foot.support_error_m<.03)
	if phase_name.begins_with("slide") and actor.pose().speed>.0001 and not floor_contact:row.moving_without_floor+=1
	if phase_name.begins_with("slide"):row.seat_error_m=maxf(float(row.seat_error_m),float(value.body_support_error_m))
	if progress>.18:
		for hand in value.hands.values():row.hand_error_m=maxf(float(row.hand_error_m),float(hand.error_m))
	if frame%12==0:observations.append({"phase":phase_name,"progress":progress,"body":actor.snapshot(),"chair":chair.position,"pose":value})

func make_request(name: String, at: float) -> Dictionary:
	var result := {"kind":"chair","phase":"chair_slide" if name.begins_with("slide") else name,"progress":at,"floor_y":0.0,
		"seat_point":chair.position+Vector3.UP*float(fixture.seat_height),"root_start":physical_root_start,"root_end":physical_root_end,"hands":{},"feet":{}}
	if fixture.has("footrest"):
		result.footrest=fixture.footrest.duplicate(true);result.footrest.center=fixture.footrest.center+chair.position
	if name in ["chair_pull","chair_push"]:
		var grip := chair.position+Vector3(0,float(fixture.size[1])-.1,-float(fixture.size[2])*.4)
		for side in ["L","R"]:result.hands[side]={"palm_transform":Transform3D(Basis.IDENTITY,grip+Vector3(.13 if side=="L" else -.13,0,0)),"grip":true}
	return result

func physical_step(index: int, count: int, chair_delta: Vector3, delta: float = 1.0/30.0) -> void:
	progress=float(index)/count
	actor.tick(delta)
	chair.position=chair_start+(actor.global_position-physical_root_start.origin) if chair_delta.length()>.001 else chair_start
	request=make_request(phase_name,progress)
	actor.use_furniture_pose(request)
	await flush(delta)
	read_observation()

func replay_checkpoint(index: int, count: int, chair_delta: Vector3) -> void:
	var packet: Dictionary=JSON.parse_string(JSON.stringify(actor.motion_state(),"",true,true))
	var saved_chair := chair.position
	await physical_step(index+1,count,chair_delta);await physical_step(index+2,count,chair_delta)
	var expected: Dictionary=actor.furniture_pose.snapshot()
	var expected_body: Dictionary=actor.snapshot()
	check(actor.restore_motion(packet),"A mid-chair floor stroke restores the actual motor and opaque body pose")
	chair.position=saved_chair
	await flush(0)
	await physical_step(index+1,count,chair_delta);await physical_step(index+2,count,chair_delta)
	check(same(expected.last_pose,actor.furniture_pose.snapshot().last_pose) and same(expected_body,actor.snapshot()),"The same two physical steps replay the same motor and real full-body pose after JSON resume")
	actor.restore_motion(packet);chair.position=saved_chair
	await flush(0)

func physical(name: String, seconds: float, target: Vector3, chair_delta: Vector3) -> void:
	phase_name=name;progress=0.0;chair_start=chair.position
	physical_root_start=actor.global_transform;physical_root_end=Transform3D(Basis.IDENTITY,target)
	var frames := [{"at":0.0,"position":actor.global_position,"heading":actor.heading},{"at":seconds,"position":target,"heading":0.0}]
	if name.begins_with("slide"):
		frames.insert(1,{"at":seconds*.22,"position":actor.global_position,"heading":0.0})
		frames.insert(2,{"at":seconds*.74,"position":target,"heading":0.0})
	check(actor.follow_interaction("moving-chair:"+name,frames),name+": bounded physical RootMotor track starts")
	var count := int(round(seconds*30))
	await physical_step(0,count,chair_delta,0)
	for index in range(1,count+1):
		await physical_step(index,count,chair_delta)
		if name=="slide_in" and not saved_once and index==int(count*.44):
			saved_once=true;await replay_checkpoint(index,count,chair_delta)
	print("MOVING CHAIR "+who+" "+name+" "+str(results.get(name,{})))

func route(points: Array, name: String) -> void:
	actor.clear_furniture_pose();phase_name=name
	check(actor.follow_path(points),name+": physical route begins around the actual chair")
	for ignored in 1200:
		actor.tick(1.0/30);await flush(1.0/30)
		if actor.body_is_settled(): break
	check(actor.body_is_settled(),name+": real walk stops before the next furniture phase")
	actor.face_heading(0)
	for ignored in 240:
		actor.tick(1.0/30);await flush(1.0/30)
		if actor.body_is_settled(): break

func hold() -> void:
	phase_name="sit_idle";physical_root_start=actor.global_transform;physical_root_end=actor.global_transform
	for ignored in 6:
		request=make_request("sit_idle",1.0);actor.use_furniture_pose(request);await flush(1.0/30)

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():who=args[0]
	record_all=args.has("--record");rendered=DisplayServer.get_name()!="headless"
	Engine.max_fps=30 if rendered else 0
	out="res://builds/motion-retarget/moving-chair/"+who+("-gpu" if rendered else "-headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var home: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	for record in home.fixtures:
		if record.type=="dining_seat" and record.owner==who:source_fixture=record.duplicate(true);fixture=record.duplicate(true);break
	if fixture.is_empty():push_error("No actual dining-chair fixture for "+who);quit(1);return
	if fixture.has("footrest"):
		var rail: Dictionary=fixture.footrest
		var centre := Vector3(rail.center[0]-fixture.position[0],rail.center[1]-fixture.position[1],rail.center[2]-fixture.position[2])
		centre=Basis(Vector3.UP,-deg_to_rad(float(fixture.facing)))*centre
		fixture.footrest={"center":centre,"support_y":centre.y,"half_width":rail.half_width,"half_depth":rail.half_depth,"support_kind":rail.support_kind,"yaw":0.0}
	var world := Node3D.new();root.add_child(world)
	if rendered:
		root.size=Vector2i(960,700)
		var env := WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("c4c2b5");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("fff6e2");env.environment.ambient_light_energy=.5;world.add_child(env)
		var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-30,0);sun.light_energy=.6;sun.shadow_enabled=true;world.add_child(sun)
		var floor_mesh := MeshInstance3D.new();var floor_shape := PlaneMesh.new();floor_shape.size=Vector2(10,10);floor_mesh.mesh=floor_shape;var mat := StandardMaterial3D.new();mat.albedo_color=Color("99998d");floor_mesh.material_override=mat;world.add_child(floor_mesh)
		camera=Camera3D.new();camera.fov=40;camera.current=true;world.add_child(camera)
		var canvas := CanvasLayer.new();world.add_child(canvas);caption=Label.new();caption.position=Vector2(15,15);caption.add_theme_font_size_override("font_size",22);canvas.add_child(caption)
	chair=Node3D.new();world.add_child(chair)
	var art := HomeArt.new();art._chair(chair,Vector3(fixture.size[0],fixture.size[1],fixture.size[2]),float(fixture.seat_height),fixture.has("footrest"))
	actor=FoundationResident.new();world.add_child(actor);actor.position=Vector3(0,0,-.60)
	check(actor.load_resident(who) and actor.configure({"walk_speed":1.0,"turn_speed":PI/2}) and actor.enable_contact_locomotion() and actor.enable_furniture_poses(),"Actual resident, locomotion, furniture solver and source-library adapter configure")
	if not failures.is_empty():quit(1);return
	actor.model.skeleton.skeleton_updated.connect(capture)
	for ignored in 12:await flush(1.0/30)
	await physical("chair_pull",1.8,actor.global_position-Vector3(0,0,.45),Vector3(0,0,-.45))
	var front := Vector3(0,0,chair.position.z+.53)
	await route([Vector3(.8,0,actor.position.z),Vector3(.8,0,front.z),front],"around_front")
	var calibration: Dictionary=actor.furniture_calibration()
	var seated := Vector3(chair.position.x-calibration.seated_pelvis_actor.x,0,chair.position.z-calibration.seated_pelvis_actor.z)
	await physical("sit_enter",1.3,seated,Vector3.ZERO)
	await physical("slide_in",2.4,actor.position+Vector3(0,0,.45),Vector3(0,0,.45))
	await hold()
	check(actor.furniture_contacts_ready(),"Actual seated frame after the inward slide rests on the seat and intended floor/rail")
	await physical("slide_out",2.4,actor.position-Vector3(0,0,.45),Vector3(0,0,-.45))
	await hold()
	await physical("sit_exit",1.3,front,Vector3.ZERO)
	await route([Vector3(.8,0,front.z),Vector3(.8,0,-1.05),Vector3(0,0,-1.05)],"around_back")
	await physical("chair_push",1.8,Vector3(0,0,-.60),Vector3(0,0,.45))
	for name in ["chair_pull","chair_push","slide_in","slide_out"]:
		var row: Dictionary=results.get(name,{})
		check(not row.is_empty() and row.reach_m<=.03 and row.point_error_m<=.03 and row.support_y_error_m<=.03 and row.rail_penetration_m<=.02,name+": actual moving body keeps required measured shoe contacts reachable within3cm")
		if name.begins_with("slide"):check(row.moving_without_floor==0 and row.seat_error_m<=.03,name+": seat carries the body and at least one real floor foot supports each moving frame")
		else:check(row.hand_error_m<=.04,name+": real palms reach the actual moving chair back within4cm")
	check(not node_changed and position_error<.000001 and scale_error<.000001,"Provider never moves motor/visual nodes or stretches any arm/leg local segment")
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(HouseholdDay._encode({"scope":"Controlled physical chair tracks with production chair dimensions/real skin contacts. Actual house navigation and ordinary-speed visual acceptance remain separate.","target":who,"source_fixture":source_fixture,"checks":checks,"failures":failures,"frames":frame,"samples":samples,"local_position_error_m":position_error,"local_scale_error":scale_error,"results":results,"observations":observations}),"\t"))
	print("Moving chair checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	world.free();quit(0 if failures.is_empty() else 1)

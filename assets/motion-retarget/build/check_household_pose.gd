extends SceneTree

# Controlled whole-body prototype. A missing source library fails by default;
# --allow-authored-fallback is explicitly a diagnostic of the unfinished path.
const HOUSEHOLD := preload("res://game/foundation/foundation_household_pose.gd")
var actor: FoundationResident
var provider
var tray: Node3D
var world: Node3D
var camera: Camera3D
var label: Label
var who := "nagisa"
var out := ""
var rendered := false
var count := 0
var samples := 0
var checks := 0
var clock_seconds := 0.0
var phase := "idle"
var failures: Array[String] = []
var rows: Array = []
var expected_root := Transform3D.IDENTITY
var mutated_node := false
var local_error := 0.0
var scale_error := 0.0
var contact_peak := 0.0
var lower_preserved := true
var carry_frames := 0
var carry_contact_peak := 0.0
var holder := false
var prop_frame := Transform3D.IDENTITY
var grip_basis := Basis(Vector3.LEFT,Vector3.BACK,Vector3.UP)
var carry_local := Transform3D.IDENTITY
var source_frame := Transform3D.IDENTITY
var target_frame := Transform3D.IDENTITY
var work_targets: Dictionary = {}
var current_request: Dictionary = {}
var grip_contacts: Dictionary = {}
var destination_bench: Node3D
var expect_unreachable := false

func _initialize() -> void:call_deferred("run")
func check(value: bool, text: String) -> void:
	checks+=1
	if not value:failures.append(text);push_error(text)

func capture() -> void:
	samples+=1;mutated_node=mutated_node or not actor.global_transform.is_equal_approx(expected_root)
	var skeleton: Skeleton3D=actor.model.skeleton
	for side in ["L","R"]:
		for part in ["thigh","shin","foot","upper_arm","forearm","hand"]:
			var index := skeleton.find_bone("DEF-"+part+"."+side)
			local_error=maxf(local_error,skeleton.get_bone_pose_position(index).distance_to(skeleton.get_bone_rest(index).origin))
			scale_error=maxf(scale_error,skeleton.get_bone_pose_scale(index).distance_to(Vector3.ONE))

func object_request(stage: String, progress: float) -> Dictionary:
	return {"action":"transfer","phase":stage,"progress":progress,"pose_seconds":clock_seconds,"posture":"stand",
		"source_world":source_frame,"target_world":target_frame,"support_point":target_frame.origin,
		"object":{"id":"fixture-tray","world":prop_frame,"support_local":grip_contacts.support_local,"local_grips":grip_contacts.local_grips}}

func sample_pose(request: Dictionary, delta: float) -> void:
	var prior := samples;expected_root=actor.global_transform
	clock_seconds+=delta;current_request=request.duplicate(true);current_request.pose_seconds=clock_seconds
	if not provider.present(current_request,delta):check(false,"Household present rejected "+phase);quit(1);return
	actor.tick_body(delta,false)
	var deadline := Time.get_ticks_msec()+2000
	while samples==prior and Time.get_ticks_msec()<deadline:await process_frame
	if samples==prior:check(false,"Actual postmodifier skeleton watchdog");quit(1);return
	var value: Dictionary=provider.telemetry()
	if not value.is_empty():
		contact_peak=maxf(contact_peak,float(value.contact_error_peak_m))
		if value.lower_body_preserved:
			lower_preserved=lower_preserved and value.lower_pose_unchanged
			if value.phase=="carry":carry_frames+=1;carry_contact_peak=maxf(carry_contact_peak,float(value.contact_error_peak_m))
	tray.global_transform=prop_frame
	if count%12==0:rows.append({"frame":count,"clock_seconds":clock_seconds,"holder_committed_by_fixture":holder,"motor":actor.snapshot(),"object":prop_frame,"pose":value})
	if rendered:
		camera.position=actor.global_position+Vector3(2.7,1.8,3.0);camera.look_at(actor.global_position+Vector3.UP*.75)
		label.text=who+" / "+phase+" / "+str(holder)
		await RenderingServer.frame_post_draw
		if count%6==0:root.get_texture().get_image().save_png(out+"/%s-%05d.png"%[phase,count])
	count+=1

func action_phase(stage: String, seconds: float, from: Transform3D, to: Transform3D) -> void:
	phase=stage
	var frames := int(round(seconds*30))
	for index in frames+1:
		var progress := float(index)/frames
		prop_frame=provider._rigid_blend(from,to,progress*progress*(3-2*progress))
		actor.tick(0.0 if index==0 else 1.0/30)
		await sample_pose(object_request(stage,progress),0.0 if index==0 else 1.0/30)

func carry_step(delta: float) -> void:
	actor.tick(delta);prop_frame=actor.global_transform*carry_local
	await sample_pose(object_request("carry",1.0),delta)

func same(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<.00001
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	return a==b

func replay() -> void:
	var body: Dictionary=JSON.parse_string(JSON.stringify(actor.motion_state(),"",true,true))
	var pose: Dictionary=JSON.parse_string(JSON.stringify(provider.snapshot(),"",true,true))
	var physical_clock := clock_seconds
	await carry_step(1.0/30);await carry_step(1.0/30)
	var expected: Dictionary=provider.snapshot();var motor_expected: Dictionary=actor.snapshot()
	check(actor.restore_motion(body) and provider.restore(pose) and not provider.contacts_ready(),"Mid-carry JSON restores semantic body/prop request and waits for a real fresh sample")
	clock_seconds=physical_clock;prop_frame=actor.global_transform*carry_local
	await sample_pose(provider.request_state(),0)
	await carry_step(1.0/30);await carry_step(1.0/30)
	check(same(expected.last,provider.snapshot().last) and same(motor_expected,actor.snapshot()),"Carried walk replays the same actual upper body and motor after resume")

func seated_work(plan: Dictionary, support_y: float) -> void:
	provider.clear();phase="sit_enter"
	destination_bench.visible=false;tray.visible=false
	var definition := {}
	for value in plan.fixtures:
		if value.type=="dining_seat" and value.owner==who:definition=value;break
	if definition.is_empty():check(false,"The real dining chair definition is available");return
	var chair := Node3D.new();chair.position=actor.global_position-Vector3(0,0,.53);world.add_child(chair)
	var art := HomeArt.new();art._chair(chair,Vector3(definition.size[0],definition.size[1],definition.size[2]),float(definition.seat_height),definition.has("footrest"))
	var seat := chair.position+Vector3.UP*float(definition.seat_height)
	var fit: Dictionary=actor.furniture_calibration()
	var end := Vector3(seat.x-fit.seated_pelvis_actor.x,0,seat.z-fit.seated_pelvis_actor.z)
	var rail := {}
	if definition.has("footrest"):
		var item: Dictionary=definition.footrest
		var relative := Vector3(item.center[0]-definition.position[0],item.center[1]-definition.position[1],item.center[2]-definition.position[2])
		relative=Basis(Vector3.UP,-deg_to_rad(float(definition.facing)))*relative
		rail={"center":chair.position+relative,"support_y":relative.y,"half_width":item.half_width,"half_depth":item.half_depth,"support_kind":item.support_kind,"yaw":0.0}
	check(actor.follow_interaction("meal-fixture-seat",[{"at":0.0,"position":actor.position,"heading":actor.heading},{"at":1.3,"position":end,"heading":0.0}]),"Meal fixture enters the actual chair through a physical body track")
	for index in 40:
		var p: float=float(index)/39
		actor.tick(0 if index==0 else 1.0/30)
		var request := {"kind":"chair","phase":"sit_enter","progress":p,"seat_point":seat,"floor_y":0.0}
		if not rail.is_empty():request.footrest=rail
		actor.use_furniture_pose(request)
		var prior := samples;expected_root=actor.global_transform;actor.tick_body(0 if index==0 else 1.0/30,false)
		var deadline := Time.get_ticks_msec()+2000
		while samples==prior and Time.get_ticks_msec()<deadline:await process_frame
		if samples==prior:check(false,"Seated preceding modifier watchdog");return
	# Pull-in is an actual body/chair track, with floor strokes and dwell to
	# return rail feet. This puts the seated body close enough to a real table
	# without spawning the tabletop through a standing character.
	var chair_start := chair.position
	var root_start := actor.global_transform
	var root_end := root_start;root_end.origin.z+=.45
	check(actor.follow_interaction("meal-fixture-slide",[{"at":0.0,"position":actor.position,"heading":0.0},{"at":2.4*.22,"position":actor.position,"heading":0.0},{"at":2.4*.74,"position":root_end.origin,"heading":0.0},{"at":2.4,"position":root_end.origin,"heading":0.0}]),"Meal body and real chair use the same physical pull-in track")
	for index in 73:
		actor.tick(0 if index==0 else 1.0/30)
		chair.position=chair_start+actor.position-root_start.origin;seat=chair.position+Vector3.UP*float(definition.seat_height)
		var request := {"kind":"chair","phase":"chair_slide","progress":float(index)/72,"seat_point":seat,"floor_y":0.0,"root_start":root_start,"root_end":root_end}
		if not rail.is_empty():
			var moving_rail := rail.duplicate(true);moving_rail.center=rail.center+chair.position-chair_start;request.footrest=moving_rail
		actor.use_furniture_pose(request)
		var prior := samples;expected_root=actor.global_transform;actor.tick_body(0 if index==0 else 1.0/30,false)
		var deadline := Time.get_ticks_msec()+2000
		while samples==prior and Time.get_ticks_msec()<deadline:await process_frame
		if samples==prior:check(false,"Meal pull-in actual skeleton watchdog");return
	if not rail.is_empty():rail.center+=chair.position-chair_start
	var table := Node3D.new();table.position=chair.position+Vector3(0,0,.70);world.add_child(table)
	var table_size := Vector3.ZERO
	for item in plan.fixtures:
		if item.id=="dining_table":table_size=Vector3(item.size[0],item.size[1],item.size[2])
	art._table(table,table_size,{"type":"desk","desk_content":""})
	var plate := Node3D.new();plate.position=chair.position+Vector3(0,support_y,.43);world.add_child(plate)
	var props := HouseholdProps.new();world.add_child(props);props._make_visual(plate,{"kind":"plate"})
	phase="seated_meal_preparation"
	var sit := {"kind":"chair","phase":"sit_idle","progress":1.0,"seat_point":seat,"floor_y":0.0}
	if not rail.is_empty():sit.footrest=rail
	actor.use_furniture_pose(sit)
	for index in 61:
		var targets := {}
		for side in ["L","R"]:targets[side]={"palm_transform":Transform3D(grip_basis,plate.position+Vector3(.12 if side=="L" else -.12,.03,0)),"grip":.3}
		await sample_pose({"action":"eat","phase":"work","progress":float(index)/60,"pose_seconds":clock_seconds,"posture":"sit","targets":targets},1.0/30)
	check(provider.telemetry().lower_body_preserved and provider.telemetry().lower_pose_unchanged,"Seated meal overlay retains the preceding furniture pelvis, legs, feet and real rail supports exactly")

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():who=args[0]
	expect_unreachable=args.has("--expect-unreachable")
	rendered=DisplayServer.get_name()!="headless";Engine.max_fps=30 if rendered else 0
	out="res://builds/motion-retarget/household/probe/"+who+("-gpu" if rendered else "-headless")+("-affordance" if expect_unreachable else "")
	for argument in args:
		if argument.begins_with("--output="):out=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var library_path := "res://game/assets/motion/household/"+who+".tres"
	var source_available := ResourceLoader.exists(library_path)
	if not source_available and not args.has("--allow-authored-fallback"):
		push_error("Retargeted household source library not generated. Run the approved Blender transfer before this fixture; no fallback pass is counted.");quit(2);return
	world=Node3D.new();root.add_child(world)
	if rendered:
		root.size=Vector2i(960,700)
		var env := WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("cfcec3");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;world.add_child(env)
		var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.shadow_enabled=true;light.light_energy=.6;world.add_child(light)
		var floor_mesh := MeshInstance3D.new();var shape := PlaneMesh.new();shape.size=Vector2(20,20);floor_mesh.mesh=shape;world.add_child(floor_mesh)
		camera=Camera3D.new();camera.fov=42;camera.current=true;world.add_child(camera)
		var canvas := CanvasLayer.new();world.add_child(canvas);label=Label.new();label.position=Vector2(15,15);label.add_theme_font_size_override("font_size",22);canvas.add_child(label)
	actor=FoundationResident.new();world.add_child(actor)
	check(actor.load_resident(who) and actor.configure({"walk_speed":.85,"turn_speed":PI/2}) and actor.enable_contact_locomotion() and actor.enable_furniture_poses(),"Real resident and preceding locomotion/furniture modifiers configure")
	provider=HOUSEHOLD.new();actor.model.skeleton.add_child(provider)
	check(provider.configure(actor,actor.model.animator.get_animation_library("foundation"),actor.motion_contract,actor.snapshot().profile),"Imported palm vertices/normals, real arm spans and household provider configure")
	if source_available:
		var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/motion/household/"+who+".contract.json"))
		check(provider.set_action_library(load(library_path),contract),"The separate actual four-source-clip library binds without replacing walking")
	if not failures.is_empty():quit(1);return
	actor.model.skeleton.skeleton_updated.connect(capture)
	var props := HouseholdProps.new();world.add_child(props)
	tray=Node3D.new();world.add_child(tray);props._make_visual(tray,{"kind":"tray"})
	grip_contacts=HouseholdProps.grips_for("tray")
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var support_y := 0.0
	var prep_size := Vector3.ZERO
	for fixture in plan.fixtures:
		if fixture.id=="prep":
			prep_size=Vector3(fixture.size[0],fixture.size[1],fixture.size[2])
			support_y=float(fixture.get("operation_targets",{}).get("carrier",{}).get("surface",[0,prep_size.y,0])[1])
	prep_size.y=support_y
	# A real native worktop is visible at both endpoints. A deliberately plain
	# table avoids treating the prep board's extra height as the countertop.
	var art := HomeArt.new()
	var source_bench := Node3D.new();source_bench.position=Vector3(0,0,.55);world.add_child(source_bench)
	art._table(source_bench,prep_size,{"type":"desk","desk_content":""})
	destination_bench=Node3D.new();destination_bench.position=Vector3(0,0,4.55);world.add_child(destination_bench)
	art._table(destination_bench,prep_size,{"type":"desk","desk_content":""})
	source_frame=Transform3D(Basis.IDENTITY,Vector3(0,support_y,.35));target_frame=source_frame;prop_frame=source_frame
	var fit: Dictionary=provider.calibration();carry_local=Transform3D(Basis.IDENTITY,fit.carry_grip_center_actor-grip_contacts.grip_midpoint)
	var bounds := AABB()
	var first := true
	for mesh_node in tray.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=mesh_node
		var local_bounds: AABB=(tray.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		bounds=local_bounds if first else bounds.merge(local_bounds);first=false
	carry_local.origin.z=maxf(carry_local.origin.z,float(fit.body_front_actor)-bounds.position.z+.025)
	# The source bench, not an arbitrary comfortable hand height, constrains
	# the initial lift. Keep this physical tray above the real top throughout
	# this first controlled route, including the smaller rig's higher carry.
	carry_local.origin.y=maxf(carry_local.origin.y,support_y+.08)
	for ignored in 6:
		var prior := samples;expected_root=actor.global_transform;actor.tick_body(1.0/30)
		var deadline := Time.get_ticks_msec()+2000
		while samples==prior and Time.get_ticks_msec()<deadline:await process_frame
		if samples==prior:check(false,"Initial actual skeleton callback watchdog");quit(1);return
	await action_phase("reach",.9,source_frame,source_frame)
	check(not holder,"Reaching does not transfer object ownership")
	await action_phase("grasp",.35,source_frame,source_frame)
	var grasp_ready: bool=provider.transfer_ready("grasp")
	check(not grasp_ready if expect_unreachable else grasp_ready,"Same-size carrier is rejected when real hand contact is unreachable" if expect_unreachable else "Only actual postmodifier closed palms at both tray surfaces permit a grasp")
	if expect_unreachable:
		check(not holder and tray.global_transform.is_equal_approx(source_frame),"Rejected affordance leaves the actual carrier at its source with no holder commit")
		FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(HouseholdDay._encode({"scope":"Explicit expected-unreachable affordance case. Success means no transfer, not completed carrying.","target":who,"source_available":source_available,"checks":checks,"failures":failures,"pickup_rejected":not grasp_ready,"holder":holder,"commit_count":0,"source_world_before":source_frame,"actual_prop_transform":tray.global_transform,"calibration":fit,"carry_local":carry_local,"prop_bounds":str(bounds),"actual":provider.telemetry(),"observations":rows}),"\t"))
		print("Household affordance checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
		world.free();quit(0 if failures.is_empty() else 1);return
	if not grasp_ready:
		# A physically unreachable carrier remains on the real worktop. Do not
		# keep animating a diagnostic lift while its holder was never committed.
		check(not holder and tray.global_transform.is_equal_approx(source_frame),"Unsupported pickup keeps the real prop on its source and commits no holder")
		FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(HouseholdDay._encode({"scope":"Physical pickup rejected before lift; this is not completed-carry acceptance.","target":who,"source_available":source_available,"checks":checks,"failures":failures,"pickup_rejected":true,"holder":holder,"calibration":fit,"carry_local":carry_local,"prop_bounds":str(bounds),"actual":provider.telemetry(),"observations":rows}),"\t"))
		print("Household pickup rejected before transfer: "+who+" / "+str(provider.telemetry().get("not_ready_reason","")))
		world.free();quit(1);return
	if provider.transfer_ready("grasp"):holder=provider.confirm_grasp("fixture-tray")
	await action_phase("lift",.75,source_frame,actor.global_transform*carry_local)
	var side_clearance := prep_size.x*.5+.30
	check(actor.follow_path([Vector3(side_clearance,0,0),Vector3(side_clearance,0,4),Vector3(0,0,4)]),"Carrying uses the continuous motor and goes around the real source counter")
	phase="carry"
	for index in 1200:
		await carry_step(1.0/30)
		if index==45:await replay()
		if actor.body_is_settled():break
	check(actor.body_is_settled() and carry_frames>30 and lower_preserved,"Carrying preserves the incoming locomotion pelvis, legs, feet and closing step on every actual frame")
	check(carry_contact_peak<=.01,"Both actual palms stay within1cm of the rigid real handles throughout the carried walk and turn")
	check(actor.face_heading(0),"The placed tray faces the real destination worktop")
	for ignored in 240:
		await carry_step(1.0/30)
		if actor.body_is_settled():break
	target_frame=Transform3D(Basis.IDENTITY,actor.global_position+Vector3(0,support_y,.35))
	await action_phase("lower",.85,prop_frame,target_frame)
	await action_phase("release",.6,target_frame,target_frame)
	check(provider.transfer_ready("release"),"Real prior grasp, open release pose and actual prop-bottom/support coincidence permit placement")
	if provider.transfer_ready("release"):
		holder=false;provider.confirm_release("fixture-tray")
	await action_phase("recover",.6,target_frame,target_frame)
	# Controlled semantic work targets expose whole-body paths, not a claim
	# that missing knife/spoon/cloth deformation assets are already complete.
	var authored := {}
	for action in ["prepare","stir","wash","fold","desk","eat"]:
		phase=action
		for index in 61:
			var targets := {}
			for side in ["L","R"]:targets[side]={"palm_transform":Transform3D(grip_basis,actor.global_position+Vector3(.12 if side=="L" else -.12,support_y+.04,.30)),"grip":.4}
			await sample_pose({"action":action,"phase":"work","progress":float(index)/60,"pose_seconds":clock_seconds,"targets":targets,"posture":"stand"},1.0/30)
		var value: Dictionary=provider.telemetry();authored[action]=value.authored_action_stage
	check(authored.size()==6 and "plate_preparation_only" in str(authored.eat) and not provider.contacts_ready(),"Every work path is explicit; absent utensil-to-mouth geometry cannot permit completed eating")
	var dining_y := 0.0
	for fixture in plan.fixtures:
		if fixture.id=="dining_table":dining_y=float(fixture.support_point[1])
	await seated_work(plan,dining_y)
	var saved: Dictionary=provider.snapshot();var bad: Dictionary=saved.duplicate(true);bad.request.progress=2.0
	var rejected: bool=not provider.restore(bad) and same(saved,provider.snapshot())
	bad=saved.duplicate(true);bad.feet={}
	rejected=not provider.restore(bad) and same(saved,provider.snapshot()) and rejected
	check(rejected,"Malformed progress or missing captured support state is rejected without presentation mutation")
	check(not mutated_node and local_error<.000001 and scale_error<.000001,"Provider never moves a Node3D root or stretches any arm/leg segment")
	FileAccess.open(out+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(HouseholdDay._encode({"scope":"Real-skeleton transfer/carry and explicit work-path prototype. Dedicated cooking/eating/cloth clips are absent; actual kitchen/meal tool and normal-camera acceptance pending.","source_available":source_available,"target":who,"checks":checks,"failures":failures,"frames":count,"calibration":fit,"carry_local":carry_local,"prop_bounds":str(bounds),"contact_peak_m":contact_peak,"carry_contact_peak_m":carry_contact_peak,"lower_preserved":lower_preserved,"local_position_error_m":local_error,"local_scale_error":scale_error,"authored_paths":authored,"observations":rows}),"\t"))
	print("Household pose checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	world.free();quit(0 if failures.is_empty() else 1)

extends SceneTree

# First skeletal/API fixture, not a natural-animation or production-room gate.
const MOTOR := preload("res://game/foundation/resident_motor.gd")
const LOCOMOTION := preload("res://game/foundation/foundation_locomotion_pose.gd")
const FURNITURE := preload("res://game/foundation/foundation_furniture_pose.gd")
const OUT := "res://builds/motion-retarget/furniture-probe"
var motor
var model
var locomotion
var furniture
var skeleton: Skeleton3D
var samples := 0
var checks := 0
var failures: Array[String] = []
var observations := {}
var max_local_position_error := 0.0
var max_local_scale_error := 0.0
var motor_pose_changed := false
var expected_motor := Transform3D.IDENTITY
var child_rail: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label);push_error(label)

func capture() -> void:
	samples+=1
	motor_pose_changed=motor_pose_changed or not motor.global_transform.is_equal_approx(expected_motor)
	for side in ["L","R"]:
		for part in ["thigh","shin","foot","upper_arm","forearm","hand"]:
			var index := skeleton.find_bone("DEF-"+part+"."+side)
			max_local_position_error=maxf(max_local_position_error,skeleton.get_bone_pose_position(index).distance_to(skeleton.get_bone_rest(index).origin))
			max_local_scale_error=maxf(max_local_scale_error,skeleton.get_bone_pose_scale(index).distance_to(Vector3.ONE))

func step(request: Dictionary, delta: float = 1.0/30.0) -> void:
	var before := samples
	motor.tick(delta)
	var body: Dictionary=motor.pose()
	if body.state=="interaction": body.state="idle";body.speed=0.0;body.normalized_speed=0.0
	locomotion.advance(body,delta,request.is_empty())
	if not request.is_empty(): furniture.present(request,delta)
	expected_motor=motor.global_transform
	skeleton.advance(delta)
	var deadline := Time.get_ticks_msec()+2000
	while samples==before and Time.get_ticks_msec()<deadline: await process_frame
	if samples==before: check(false,"Actual skeleton callback watchdog");quit(1)

func request(phase: String, progress: float, seat: Vector3) -> Dictionary:
	var value := {"kind":"chair","phase":phase,"progress":progress,"floor_y":0.0,"seat_point":seat,"pose_seconds":progress*1.4}
	if not child_rail.is_empty() and phase in ["sit_enter","sit_idle","sit_exit","chair_slide"]: value.footrest=child_rail
	return value

func phase(phase_name: String, seat: Vector3, frames: int = 15, extra: Dictionary = {}) -> void:
	for frame in frames+1:
		var value := request(phase_name,float(frame)/frames,seat)
		value.merge(extra,true)
		await step(value)
	observations[phase_name]=furniture.telemetry()

func run() -> void:
	if root.has_node("Sim"): root.get_node("Sim").set_process(false)
	var args := OS.get_cmdline_user_args()
	var who: String=args[0] if not args.is_empty() else "nagisa"
	if who=="rin":
		# Use the real dining-chair rail dimensions in the fixture's local frame.
		# This is a ball rest, not a platform supporting the entire shoe.
		var house: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
		for fixture in house.fixtures:
			if fixture.id!="dining_rin": continue
			var rail: Dictionary=fixture.footrest
			var origin := Vector3(fixture.position[0],fixture.position[1],fixture.position[2])
			var center := Vector3(rail.center[0],rail.center[1],rail.center[2])
			center=Basis(Vector3.UP,-deg_to_rad(float(rail.yaw_degrees)))*(center-origin)
			child_rail={"center":center,"support_y":center.y,"half_width":rail.half_width,"half_depth":rail.half_depth,"support_kind":rail.support_kind,"yaw":0.0}
	motor=MOTOR.new();root.add_child(motor);motor.position=Vector3(0,0,.53)
	motor.configure({"walk_speed":1.1,"turn_speed":PI/2})
	model=load("res://game/scenes/characters/"+who+".tscn").instantiate();motor.add_child(model)
	model.animator.stop();skeleton=model.skeleton
	skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	locomotion=LOCOMOTION.new();skeleton.add_child(locomotion)
	furniture=FURNITURE.new();skeleton.add_child(furniture)
	var library: AnimationLibrary=load("res://game/assets/motion/foundation/"+who+".tres")
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/motion/foundation/"+who+".contract.json"))
	var locomotion_ok: bool=locomotion.configure(motor,library,contract,motor.snapshot().profile)
	var furniture_ok: bool=furniture.configure(motor,library,contract,motor.snapshot().profile)
	if not furniture_ok:
		var counts := {}
		for key in furniture._skin_points: counts[key]=furniture._skin_points[key].size()
		print("FURNITURE configure diagnostics: "+str({"locomotion":locomotion_ok,"furniture":furniture_ok,"skin_regions":counts,"pelvis_rest":furniture._rest_globals[furniture._bones["DEF-pelvis"]],"skeleton_in_actor":furniture._skeleton_in_actor}))
	check(locomotion_ok and furniture_ok,"Real skeleton/source sitting clips/Skin support configure")
	if not failures.is_empty(): motor.free();quit(1);return
	skeleton.skeleton_updated.connect(capture)
	await step({})
	var calibration: Dictionary=furniture.calibration()
	check(calibration.seated_pelvis_actor is Vector3 and calibration.standing_pelvis_actor is Vector3 and calibration.seat_pelvis_offset_y>0 and calibration.seat_support_vertices>0,"Seat calibration comes from source sit_idle and actual butt-region skin")
	var seat := Vector3(0,.45,0)
	var end := Vector3(-calibration.seated_pelvis_actor.x,0,-calibration.seated_pelvis_actor.z)
	check(motor.follow_interaction("seat-fixture",[{"at":0.0,"position":motor.position,"heading":0.0},{"at":.5,"position":end,"heading":0.0}]),"Physical seat entry is owned by RootMotor track")
	await phase("sit_enter",seat)
	await phase("sit_idle",seat,2)
	check(furniture.contacts_ready(),"Actual final sitting sample supports seat and required feet within3cm")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(furniture.snapshot(),"",true,true))
	check(furniture.can_restore(saved) and furniture.restore(saved) and not furniture.contacts_ready(),"JSON restore validates opaque pose and waits for a fresh actual skeleton sample")
	await step(furniture.request_state(),0)
	check(furniture.contacts_ready(),"Zero-time post-restore sample restores seated readiness")
	var malformed: Dictionary=saved.duplicate(true);malformed.phase="fictional_sleep_source"
	var prior: Dictionary=furniture.snapshot()
	check(not furniture.restore(malformed) and prior==furniture.snapshot(),"Malformed furniture phase is rejected without state mutation")
	await phase("sit_exit",seat)
	# API smoke coverage for newly authored whole-body phases. Their actual-room
	# camera quality and moving-chair contacts remain a separate pending review.
	var track_end: Transform3D=motor.global_transform;track_end.origin.z+=.45
	await phase("chair_pull",seat,10,{"root_end":track_end})
	await phase("chair_push",seat,10,{"root_end":motor.global_transform})
	await phase("chair_slide",seat,4)
	await phase("bed_seat",seat,4)
	var bed := {"sheet_y":.422,"pelvis_point":Vector3(0,.52,0),"pillow_point":Vector3(0,.5,-.5),"head_direction":Vector3(0,0,-1)}
	for name in ["legs_in","lie_down","lie_idle","sit_up","legs_out"]:
		await phase(name,seat,5,{"kind":"bed","bed":bed})
		if name=="lie_idle":
			var body_before: Array=furniture.snapshot().last_pose
			var sample_before := samples
			var sleeping := request("lie_idle",1.0,seat);sleeping.kind="bed";sleeping.bed=bed;sleeping.pose_seconds=42.0
			await step(sleeping)
			var observation: Dictionary=furniture.telemetry()
			check(observation.profile_usec.static_pose_cache and samples>sample_before and observation.latest_sample_serial==observation.request_serial and furniture.snapshot().last_pose==body_before,"Static sleep pose is really reapplied and freshly observed without repeating the unchanged contact solve")
			var changed: Dictionary=sleeping.duplicate(true);changed.bed.pillow_point.y+=.01
			await step(changed)
			check(not furniture.telemetry().profile_usec.static_pose_cache,"An actual support target change invalidates the sleep-pose cache")
			var sleeping_saved: Dictionary=JSON.parse_string(JSON.stringify(furniture.snapshot(),"",true,true))
			check(furniture.restore(sleeping_saved) and not furniture.contacts_ready(),"Sleeping snapshot restores semantic pose but requires a fresh postmodifier contact sample")
			await step(furniture.request_state(),0)
			check(furniture.contacts_ready() and not furniture.telemetry().profile_usec.static_pose_cache,"First restored sleeping sample recomputes real supports before readiness")
	await phase("bed_stand",seat,5)
	check(observations.size()==13,"Every furniture phase applies an actual final skeleton sample")
	check(not motor_pose_changed,"Furniture pose never writes motor or visual-node world transforms")
	check(max_local_position_error<.000001 and max_local_scale_error<.000001,"Arm and leg local lengths/scales remain unchanged")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT+"/"+who+".json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"First real-skeleton API/phase/support fixture only. Not normal-camera natural-motion acceptance; root must review the production room.","target":who,"checks":checks,"failures":failures,"calibration":calibration,"samples":samples,"local_position_error_peak_m":max_local_position_error,"local_scale_error_peak":max_local_scale_error,"observations":observations},"\t"))
	print("Foundation furniture checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	motor.free();quit(0 if failures.is_empty() else 1)

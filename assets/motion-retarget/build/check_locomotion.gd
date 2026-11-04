extends SceneTree

# Small integration/replay probe. It observes real post-modifier Skeleton3D poses,
# not a natural-gait or human-viewing acceptance test. Run only in root's slot.
const MOTOR := preload("res://game/foundation/resident_motor.gd")
const LOCOMOTION := preload("res://game/foundation/foundation_locomotion_pose.gd")
const OUT := "res://builds/motion-retarget/locomotion-probe"
var failures: Array[String]=[]
var checks := 0
var motor
var model
var modifier
var skeleton: Skeleton3D
var observed: Dictionary={}
var bone_lengths: Dictionary={}
var length_error := 0.0
var processed_count := 0
var peak_support: Dictionary={}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)

func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<.00001
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

func capture_final_pose() -> void:
	# The signal is inside modifier processing, before Skeleton3D restores its
	# unmodified public bone poses. This is the pose the skin actually receives.
	processed_count+=1;observed=modifier.telemetry()
	for side in ["L","R"]:
		var points: Array[Vector3]=[]
		for part in ["thigh","shin","foot"]:
			points.append(skeleton.get_bone_global_pose(skeleton.find_bone("DEF-"+part+"."+side)).origin)
		for i in 2:
			length_error=maxf(length_error,absf(points[i].distance_to(points[i+1])-float(bone_lengths[side][i])))

func step() -> void:
	var prior := processed_count
	motor.tick(1.0/60)
	modifier.advance(motor.pose(),1.0/60,true)
	await flush_pose(prior,1.0/60)

func flush_pose(prior: int, delta: float) -> void:
	skeleton.advance(delta)
	# A signal may be delivered during the current deferred flush. Observe its
	# counter before waiting, and bound every wait so missing callbacks fail.
	var deadline := Time.get_ticks_msec()+2000
	while processed_count==prior and Time.get_ticks_msec()<deadline:
		await process_frame
	if processed_count==prior:
		check(false,"Skeleton modifier callback watchdog expired at motor "+motor.state()+" / input serial "+str(modifier.snapshot().serial))
		quit(1)
		return

func checkpoint(label: String) -> void:
	var body: Dictionary=JSON.parse_string(JSON.stringify(motor.snapshot(),"",true,true))
	var presentation: Dictionary=JSON.parse_string(JSON.stringify(modifier.snapshot(),"",true,true))
	await step();await step()
	var expected: Dictionary=modifier.snapshot()
	var restored: bool=motor.restore(body) and modifier.restore(presentation)
	await step();await step()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT+"/checkpoint-"+label+".json",FileAccess.WRITE).store_string(JSON.stringify({"saved":presentation,"motor_saved":body,"restored":restored,"can_restore":modifier.can_restore(presentation),"expected":expected,"actual":modifier.snapshot()},"\t"))
	check(restored and same(expected,modifier.snapshot()),label+": entry/support/landing state restores and replays the same later pose")

func run() -> void:
	if root.has_node("Sim"): root.get_node("Sim").set_process(false)
	var args := OS.get_cmdline_user_args()
	var who: String=args[0] if not args.is_empty() else "nagisa"
	motor=MOTOR.new();root.add_child(motor)
	motor.configure({"turn_speed":PI/2})
	model=load("res://game/scenes/characters/"+who+".tscn").instantiate();motor.add_child(model)
	model.animator.stop();skeleton=model.skeleton
	skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	modifier=LOCOMOTION.new();modifier.name="FoundationLocomotionPose";skeleton.add_child(modifier)
	var contract: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/motion/foundation/"+who+".contract.json"))
	check(modifier.configure(motor,load("res://game/assets/motion/foundation/"+who+".tres"),contract),"The real rig/library/measured shoe vertices configure together")
	if not failures.is_empty(): quit(1);return
	for side in ["L","R"]:
		var points: Array[Vector3]=[]
		for part in ["thigh","shin","foot"]: points.append(skeleton.get_bone_global_rest(skeleton.find_bone("DEF-"+part+"."+side)).origin)
		bone_lengths[side]=[points[0].distance_to(points[1]),points[1].distance_to(points[2])]
	modifier.modification_processed.connect(capture_final_pose)
	await step()
	print("LOCOMOTION probe initialized: "+who+" / Godot "+Engine.get_version_info().string)
	var clock: float=modifier.snapshot().machine.clock
	var prior := processed_count
	for ignored in 3:
		motor.tick(1.0/60);modifier.advance(motor.pose(),1.0/60,true)
	await flush_pose(prior,3.0/60)
	check(absf(float(modifier.snapshot().machine.clock)-clock-3.0/60)<.000001,"Three physical substeps before one deferred callback preserve all elapsed pose time")
	motor.follow_path([Vector3(0,0,10),Vector3(2,0,10),Vector3(0,0,10)])
	var modes := {};var saved := {};var turn_steps := {};var support_peak := 0.0;var swing_peak := 0.0
	for frame in 1500:
		await step()
		if frame%200==0: print("LOCOMOTION progress frame "+str(frame)+" motor="+motor.state()+" body="+str(observed.get("mode","no callback")))
		var record: Dictionary=modifier.snapshot()
		var mode: String=observed.get("mode","")
		modes[mode]=true
		if mode=="turn": turn_steps[int(observed.turn_step)]=true
		for value in observed.get("support_errors_m",{}).values():
			if float(value)>support_peak:
				support_peak=float(value);peak_support={"frame":frame,"motor":motor.snapshot(),"body":modifier.snapshot(),"side_errors":observed.support_errors_m}
		for side in ["L","R"]:
			if not observed.get("support",{}).get(side,{}).get("locked",true):
				var point: Vector3=observed.actual_shoe_points_world[side].ball
				swing_peak=maxf(swing_peak,point.y)
		if mode=="start" and not saved.has("start"):
			saved.start=true;await checkpoint("departure")
		if mode=="turn" and observed.turn_step==0 and not saved.has("turn"):
			saved.turn=true;await checkpoint("turn_with_support_and_swing")
		if mode=="turn" and observed.turn_step==1 and not saved.has("landing"):
			saved.landing=true;await checkpoint("turn_after_first_landing")
		if motor.state()=="idle" and modifier.is_settled(): break
	check(motor.state()=="idle" and modifier.is_settled() and modes.has("start") and modes.has("walk") and modes.has("stop") and modes.has("turn"),"Departure, walk, two turn sizes, closing step and final settle execute on the real rig")
	check(turn_steps.has(3) and swing_peak>.03,"The180-degree return has four foot stages and a raised free shoe rather than frozen idle-root rotation")
	check(support_peak<=.02,"World support contacts remain within2cm throughout departure/walk/stop/turn; unreachable support is a failure")
	check(length_error<.0001,"Actual final Skeleton3D thigh/shin lengths are retained throughout the transitions")
	var before: Dictionary=modifier.snapshot()
	var malformed: Dictionary=before.duplicate(true)
	malformed.machine.feet.L.point="unmeasured_offset"
	check(not modifier.restore(malformed) and same(before,modifier.snapshot()),"An invalid support surface is rejected without presentation mutation")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var report := {"scope":"Real skeleton locomotion modifier/load/replay observation only. Requires normal-camera video/human review for natural gait acceptance.","target":who,"checks":checks,"failures":failures,"modes":modes,"saved_checkpoints":saved,"turn_steps":turn_steps,"support_point_error_peak_m":support_peak,"support_peak_details":peak_support,"free_shoe_height_peak_m":swing_peak,"actual_bone_length_error_peak_m":length_error,"final":modifier.snapshot()}
	FileAccess.open(OUT+"/"+who+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Foundation locomotion checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	motor.free();quit(0 if failures.is_empty() else 1)

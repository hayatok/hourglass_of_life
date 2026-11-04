extends SceneTree

const MOTOR := preload("res://game/foundation/resident_motor.gd")
const OUT := "res://builds/resident-motor"
var checks := 0
var failures: Array[String] = []
var report := {"scope":"Continuous movement/controller tests in physical metres and render seconds. No source walk clips, AnimationTree, rendered feet, natural gait or human play quality are established.","cases":[]}

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)

func equal(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<.000000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equal(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equal(a[index],b[index]): return false
		return true
	return a==b

func create(profile: Dictionary = {}):
	var motor = MOTOR.new();root.add_child(motor)
	if not motor.configure(profile): failures.append("Valid fixture profile was rejected");push_error(failures[-1])
	return motor

func simulate(motor, seconds: float, deltas: Array) -> Dictionary:
	var elapsed := 0.0;var frame := 0
	var peak_speed := 0.0;var peak_acceleration := 0.0
	var valid := true
	while elapsed<seconds-.000000001:
		var delta: float = minf(float(deltas[frame%deltas.size()]),seconds-elapsed)
		var prior: Vector3 = motor.velocity
		var prior_remainder: float = motor.snapshot().remainder
		valid = motor.tick(delta) and valid
		# A render frame can consume one more/fewer fixed substeps than its own
		# delta. Acceleration belongs to the physical time actually integrated.
		var integrated_delta: float = delta + prior_remainder - float(motor.snapshot().remainder)
		peak_speed = maxf(peak_speed,motor.velocity.length())
		if integrated_delta>0:
			peak_acceleration = maxf(peak_acceleration,motor.velocity.distance_to(prior)/integrated_delta)
		else:
			valid = valid and motor.velocity==prior
		elapsed += delta;frame += 1
	return {"accepted_ticks":valid,"peak_speed":peak_speed,"peak_acceleration":peak_acceleration,"snapshot":motor.snapshot()}

func straight_delta_variants() -> void:
	var reference: Dictionary = {}
	for deltas in [[1.0/30],[1.0/60],[1.0/120],[.013,.027,.041,.019]]:
		var motor = create()
		var target := Vector3(0,0,10)
		motor.follow_path([target])
		var result := simulate(motor,14,deltas)
		if reference.is_empty(): reference=result.snapshot
		expect(motor.state()=="idle" and motor.global_position.distance_to(target)<=.1 and result.accepted_ticks,"A 10m path arrives within10cm for delta sequence "+str(deltas))
		expect(result.peak_speed<=1.100001 and result.peak_acceleration<=2.2001,"Actual velocity respects the physical speed/acceleration bounds for "+str(deltas))
		expect(equal(reference,result.snapshot),"The same14 render seconds produce the same controller state independently of tick partition")
		report.cases.append({"name":"straight_delta","deltas":deltas,"observed":result})
		motor.free()

func speed_profiles() -> void:
	var previous_arrival := INF
	var ordered := true
	for speed in [.65,1.1,1.5]:
		var motor = create({"walk_speed":speed})
		motor.follow_path([Vector3(0,0,10)])
		var elapsed := 0.0;var peak := 0.0
		while motor.state()!="idle" and elapsed<30:
			motor.tick(1.0/60);elapsed+=1.0/60;peak=maxf(peak,motor.velocity.length())
		ordered = ordered and elapsed<previous_arrival;previous_arrival=elapsed
		expect(motor.state()=="idle" and peak<=speed+.000001 and motor.global_position.distance_to(Vector3(0,0,10))<=.1,"The actual "+str(speed)+"m/s profile governs a complete10m journey")
		report.cases.append({"name":"physical_profile","walk_speed":speed,"arrival_seconds":elapsed,"peak_speed":peak})
		motor.free()
	expect(ordered,"Increasing physical walk speed shortens the actual journey without using a simulation-minute multiplier")

func corner_path() -> void:
	var motor = create()
	var corners: Array = [Vector3(0,0,3),Vector3(3,0,3),Vector3(3,0,0)]
	motor.follow_path(corners)
	var visits := [false,false]
	var on_corridor := true;var bounded_heading := true;var still_during_turn := true
	var braked_before_corner := false;var turn_entries := 0;var prior_state := motor.state()
	for frame in 3600:
		var before: Vector3 = motor.global_position
		var angle: float = motor.heading
		motor.tick(1.0/120)
		var p: Vector3 = motor.global_position
		if p.distance_to(corners[0])<.00001: visits[0]=true
		if p.distance_to(corners[1])<.00001: visits[1]=true
		var first: bool = absf(p.x)<.00001 and p.z>=-.00001 and p.z<=3.00001
		var second: bool = absf(p.z-3)<.00001 and p.x>=-.00001 and p.x<=3.00001
		var third: bool = absf(p.x-3)<.00001 and p.z>=-.00001 and p.z<=3.00001
		on_corridor = on_corridor and (first or second or third)
		bounded_heading = bounded_heading and absf(wrapf(motor.heading-angle,-PI,PI))<=2.4/120+.000011
		if prior_state=="turn": still_during_turn = still_during_turn and p.distance_to(before)<.000001
		if motor.state()=="turn" and prior_state!="turn": turn_entries+=1
		if motor.state()=="stop" and p.x<.00001 and p.z<2.99: braked_before_corner=true
		prior_state=motor.state()
		if motor.state()=="idle": break
	expect(on_corridor and visits.all(func(value):return value),"The closed90-degree corridor is followed through both exact corners without cutting across its inside")
	expect(braked_before_corner and turn_entries==2 and bounded_heading and still_during_turn,"The motor brakes before90-degree corners, turns at a bounded rate while stopped, then departs")
	expect(motor.state()=="idle" and motor.global_position.distance_to(corners[-1])<=.1,"The corner journey finishes at the actual destination")
	report.cases.append({"name":"closed_corner","visits":visits,"on_corridor":on_corridor,"turn_entries":turn_entries,"braked_before_corner":braked_before_corner,"snapshot":motor.snapshot()})
	motor.free()

func reverse_turn() -> void:
	var motor = create()
	motor.follow_path([Vector3(0,0,2),Vector3(0,0,-2)])
	var rotation_seconds := 0.0;var replant_seconds := 0.0
	var fixed_root := true;var bounded_heading := true
	for frame in 3000:
		var before: Vector3 = motor.global_position
		var angle: float = motor.heading
		var pose: Dictionary = motor.pose()
		motor.tick(1.0/120)
		bounded_heading = bounded_heading and absf(wrapf(motor.heading-angle,-PI,PI))<=2.4/120+.000011
		if pose.state=="turn":
			fixed_root = fixed_root and motor.global_position.distance_to(before)<.000001 and motor.velocity.length()<.000001
			if pose.turn_phase=="rotate": rotation_seconds+=1.0/120
			elif pose.turn_phase=="replant": replant_seconds+=1.0/120
		if motor.state()=="idle": break
	expect(fixed_root and bounded_heading and rotation_seconds>=PI/2.4-.04 and replant_seconds>=.10,"A180-degree reversal gradually turns at rest and keeps a replant window before moving again")
	expect(motor.state()=="idle" and motor.global_position.distance_to(Vector3(0,0,-2))<=.1,"The reversal reaches its return destination without teleporting the body")
	report.cases.append({"name":"180_turn","rotation_seconds":rotation_seconds,"replant_seconds":replant_seconds,"snapshot":motor.snapshot()})
	motor.free()

func pause_stop_restart() -> void:
	var motor = create()
	motor.follow_path([Vector3(0,0,10)]);simulate(motor,2,[1.0/60])
	var paused: Dictionary = motor.snapshot()
	for ignored in 20: motor.tick(0)
	expect(equal(paused,motor.snapshot()),"Zero elapsed time preserves path, velocity, heading, pose progress and distance exactly")
	var before: Vector3 = motor.global_position
	var speed: float = motor.velocity.length()
	motor.stop()
	var immediate: bool = motor.state()=="stop" and is_equal_approx(motor.velocity.length(),speed)
	var stopped := simulate(motor,2,[1.0/60])
	var stopping_distance: float = motor.global_position.distance_to(before)
	expect(immediate and motor.state()=="idle" and stopping_distance>0 and stopping_distance<=speed*speed/(2*2.2)+.005 and stopped.peak_acceleration<=2.2001,"stop() physically decelerates from the current velocity instead of teleporting or dropping velocity instantly")
	var resting: Vector3 = motor.global_position
	simulate(motor,2,[1.0/30])
	expect(motor.global_position.distance_to(resting)<.000001 and motor.velocity==Vector3.ZERO,"An idle motor has no position drift")
	motor.follow_path([Vector3(0,0,10)]);motor.tick(.1)
	expect(motor.state()=="start" and motor.velocity.length()>0 and motor.velocity.length()<1.1,"Restart enters bounded acceleration without an immediate full-speed step")
	simulate(motor,12,[1.0/60])
	expect(motor.state()=="idle" and motor.global_position.distance_to(Vector3(0,0,10))<=.1,"Restart preserves the destination and completes the physical journey")
	report.cases.append({"name":"pause_stop_restart","stopping_distance":stopping_distance,"snapshot":motor.snapshot()})
	motor.free()

func replay_checkpoint(motor, label: String) -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(motor.snapshot(),"",true,true))
	simulate(motor,.371,[.013,.027,.041,.019])
	var future: Dictionary = motor.snapshot()
	var restored: bool = motor.restore(saved)
	var exact: bool = equal(saved,motor.snapshot())
	simulate(motor,.371,[.013,.027,.041,.019])
	expect(restored and exact and equal(future,motor.snapshot()),label+": JSON snapshot restores every state field and deterministically replays the same later movement")
	report.cases.append({"name":"save_restore","checkpoint":label,"restored":restored,"exact_state":exact})

func save_restore_and_reject() -> void:
	var motor = create()
	motor.follow_path([Vector3(0,0,3),Vector3(3,0,3)])
	simulate(motor,1.111,[1.0/60]);replay_checkpoint(motor,"walk_with_fractional_remainder")
	for ignored in 1200:
		if motor.state()=="turn": break
		motor.tick(1.0/60)
	replay_checkpoint(motor,"corner_rotation")
	for ignored in 300:
		if motor.state()=="turn" and motor.pose().turn_phase=="replant": break
		motor.tick(1.0/120)
	replay_checkpoint(motor,"corner_replant")
	simulate(motor,.3,[1.0/60]);motor.stop();replay_checkpoint(motor,"requested_stop")
	var before: Dictionary = motor.snapshot()
	var invalid: Array = []
	var bad: Dictionary = before.duplicate(true);bad.version=99;invalid.append(bad)
	bad=before.duplicate(true);bad.profile.walk_speed=INF;invalid.append(bad)
	bad=before.duplicate(true);bad.position=[NAN,0,0];invalid.append(bad)
	bad=before.duplicate(true);bad.velocity=[1,2,3];invalid.append(bad)
	bad=before.duplicate(true);bad.progress=1e100;invalid.append(bad)
	bad=before.duplicate(true);bad.state="teleport";invalid.append(bad)
	bad=before.duplicate(true);bad.remainder=1;invalid.append(bad)
	bad=before.duplicate(true);bad.pending_path=[[INF,0,0]];invalid.append(bad)
	var rejected := true
	for packet in invalid: rejected = not motor.restore(packet) and equal(before,motor.snapshot()) and rejected
	expect(rejected,"Malformed/current-format, non-finite, contradictory velocity and overflowing progress snapshots are rejected without changing the controller")
	var inputs_safe: bool = not motor.tick(-1) and not motor.tick(INF) and not motor.follow_path([Vector3(INF,0,0)]) and equal(before,motor.snapshot())
	expect(inputs_safe,"Invalid tick and path inputs are rejected atomically")
	motor.stop();simulate(motor,2,[1.0/60]);before=motor.snapshot()
	expect(not motor.configure({"acceleration":0}) and not motor.configure({"turn_speed":NAN}) and equal(before,motor.snapshot()),"Invalid physical profiles are rejected without changing the stopped motor")
	motor.free()

func queued_route() -> void:
	var motor = create()
	motor.follow_path([Vector3(0,0,10)]);simulate(motor,1,[1.0/60])
	var before: Vector3 = motor.global_position
	var velocity: Vector3 = motor.velocity
	motor.follow_path([Vector3(0,0,5),Vector3(3,0,5)])
	expect(motor.global_position==before and motor.velocity==velocity and motor.state()=="stop","Replacing a live route queues it and starts braking without changing the current position or velocity")
	replay_checkpoint(motor,"queued_path_during_braking")
	simulate(motor,15,[1.0/60])
	expect(motor.state()=="idle" and motor.global_position.distance_to(Vector3(3,0,5))<=.1,"The queued route starts after the old segment's bounded stop and reaches its new destination")
	motor.free()

func furniture_facing() -> void:
	var motor=create()
	var origin: Vector3=motor.global_position
	expect(motor.face_heading(PI*.5) and motor.state()=="turn","Furniture alignment starts a bounded turn without creating a path")
	simulate(motor,.3,[1.0/60])
	replay_checkpoint(motor,"furniture_facing_turn")
	simulate(motor,2,[1.0/60])
	expect(motor.state()=="idle" and motor.global_position==origin and absf(motor.heading-PI*.5)<.00001,"Furniture alignment finishes at the requested heading without translating the body")
	motor.follow_path([Vector3(0,0,4)]);simulate(motor,2,[1.0/60])
	var before: Dictionary=motor.snapshot()
	expect(not motor.face_heading(0) and equal(before,motor.snapshot()),"A furniture alignment cannot overwrite a moving body")
	motor.free()

func orientation_keeps_scale() -> void:
	var motor=create({"turn_speed":12.0})
	for index in 180:
		motor.face_heading(wrapf(float(index)*2.3,-PI,PI))
		simulate(motor,1.0,[1.0/30.0])
	var scale: Vector3=motor.global_basis.get_scale()
	expect(scale.distance_to(Vector3.ONE)<.000001,"Repeated turns preserve a metre-sized body instead of retaining accumulated Euler decomposition scale")
	var saved: Dictionary=motor.snapshot()
	motor.global_basis=motor.global_basis.scaled(Vector3(.85,1,.85))
	expect(motor.restore(saved) and motor.global_basis.get_scale().distance_to(Vector3.ONE)<.000001,"Restoring the motor rebuilds its canonical unit world orientation without inheriting the later world's scale")
	motor.free()

func furniture_root_motion() -> void:
	var frames: Array=[{"at":0.0,"position":Vector3.ZERO,"heading":0.0},
		{"at":1.0,"position":Vector3(-.4,0,0),"heading":0.0},
		{"at":1.5,"position":Vector3(-.4,.2,0),"heading":.4}]
	var reference: Dictionary={}
	for deltas in [[1.0/30],[1.0/60],[.013,.027,.041,.019]]:
		var motor=create()
		expect(motor.follow_interaction("chair_pull_and_mount",frames),"A stopped body admits a bounded furniture root track")
		simulate(motor,.5,deltas)
		expect(motor.state()=="interaction" and motor.global_position.distance_to(Vector3(-.2,0,0))<.00001 and absf(motor.heading)<.00001 and motor.velocity.x<0,"Pulling moves the real body backward while preserving its forward-facing heading")
		var held: Dictionary=motor.snapshot()
		expect(not motor.stop() and not motor.follow_path([Vector3(0,0,5)]) and not motor.face_heading(PI) and equal(held,motor.snapshot()),"A walking intention cannot overwrite or stop a furniture transition at an unsafe intermediate pose")
		replay_checkpoint(motor,"furniture_root_track")
		motor.restore(held)
		simulate(motor,.7,deltas)
		if reference.is_empty():reference=motor.snapshot()
		expect(equal(reference,motor.snapshot()),"Furniture translation, heading and time agree across render delta partitions")
		var before: Dictionary=motor.snapshot()
		var bad: Dictionary=before.duplicate(true);bad.position[1]+=.1
		expect(not motor.restore(bad) and equal(before,motor.snapshot()),"A position contradicting the saved interaction track is rejected atomically")
		simulate(motor,1,deltas)
		expect(motor.state()=="idle" and motor.global_position.distance_to(Vector3(-.4,.2,0))<.00001 and absf(motor.heading-.4)<.00001 and motor.velocity==Vector3.ZERO,"The body finishes at the authored raised use point without a second visual follower")
		motor.free()
	var motor=create()
	var before: Dictionary=motor.snapshot()
	var invalid: Array=frames.duplicate(true);invalid[0].position=Vector3(1,0,0)
	expect(not motor.follow_interaction("wrong_entry",invalid) and equal(before,motor.snapshot()),"An interaction cannot snap a body to a different first point")
	invalid=frames.duplicate(true);invalid[1].at=0
	expect(not motor.follow_interaction("wrong_time",invalid) and equal(before,motor.snapshot()),"Non-monotonic furniture keyframes are rejected before any movement")
	invalid=frames.duplicate(true);invalid[1].position=Vector3(100,0,0)
	expect(not motor.follow_interaction("too_fast",invalid) and equal(before,motor.snapshot()),"A furniture track cannot move the body at an unbounded speed")
	motor.free()

func run() -> void:
	straight_delta_variants()
	speed_profiles()
	corner_path()
	reverse_turn()
	pause_stop_restart()
	save_restore_and_reject()
	queued_route()
	furniture_facing()
	orientation_keeps_scale()
	furniture_root_motion()
	report.checks=checks;report.failures=failures
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT+"/results.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Resident motor checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

# Controlled straight/turn/stop fixtures isolate presentation from life choices.
# Natural-town integration remains in test_haru_jrpg_gameplay and
# test_jrpg_renewal_gameplay. No hash is a functional result.
const IDS = ["haru","saki","tomo","yui"]
# From actual low/backward foot trajectories in each exported clip. These
# intervals do not use the older footstep markers (which have different times).
const WINDOWS = {"haru":[.25,.75,.25],"saki":[.25,.75,.38],"tomo":[7.0/26,20.0/26,7.0/26],"yui":[6.0/23,17.0/23,.38]}
const OUT = "res://builds/foot-plant"
var sim
var stage: Node3D
var camera: Camera3D
var checks := 0
var failures: Array[String] = []
var report := {"scope":"Controlled presentation fixtures, not natural behavior or human playtesting.","cases":{},"artifacts":[]}

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message);push_error(message)

func fixture(id: String) -> Dictionary:
	var p: Dictionary = sim.person(id).duplicate(true)
	p.moving = true;p.position = Vector3.ZERO;p.place = "square";p.action = "travel"
	p.meeting_id = "";p.activity_spot = ""
	var actor = load("res://game/scenes/resident_avatar.tscn").instantiate()
	stage.add_child(actor);actor.configure(p)
	actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return {"p":p,"actor":actor}

func step(f: Dictionary, motion: Vector3, delta: float) -> void:
	f.p.position += motion
	f.actor.update_state(f.p,delta,true)
	f.actor.animator.advance(delta)
	await process_frame

func dispose(f: Dictionary) -> void:
	stage.remove_child(f.actor);f.actor.free()

func capture(f: Dictionary, filename: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var target: Vector3 = f.actor.global_position+Vector3.UP*.8
	camera.global_position = target+Vector3(2.0,.65,2.4)
	camera.look_at(target)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT+"/"+filename+".png"
	root.get_texture().get_image().save_png(path)
	report.artifacts.append(path)

func measure(id: String, enabled: bool, speed: float, fps: float, images: bool = false) -> Dictionary:
	var f := fixture(id)
	f.actor.jrpg.walk_foot_plant = enabled
	var prior := {};var drift := [];var peak_error := 0.0;var peak_vertical := 0.0
	var captured := false
	var source_end := 0.0
	# The shortest calibrated Haru support at 30fps otherwise yields only seven
	# adjacent observations. Sample more cycles without widening the window or
	# relaxing the drift/reach requirements.
	for frame in int(fps*6.0):
		await step(f,Vector3(0,0,speed/fps),1.0/fps)
		var player: AnimationPlayer = f.actor.animator
		var phase := player.current_animation_position/player.current_animation_length
		for side in ["L","R"]:
			var progress := fposmod(phase-float(WINDOWS[id][0 if side=="L" else 1]),1)
			var foot: Vector3 = f.actor.contacts.observed["foot"+side]
			# Exclude blend-in/out. This is an independently measured world-space
			# displacement of the final bone, not the stored target or anchor.
			if frame>fps and progress>.07 and progress<float(WINDOWS[id][2])-.07 and prior.has(side) and prior[side].progress<progress and prior[side].progress>.07:
				var old: Vector3 = prior[side].foot
				drift.append(Vector2(foot.x-old.x,foot.z-old.z).length()*fps)
				peak_vertical = maxf(peak_vertical,absf(foot.y-old.y)*fps)
				peak_error = maxf(peak_error,f.actor.contacts.observed.get("foot_error"+side,0.0))
			prior[side] = {"progress":progress,"foot":foot}
			if images and not captured and frame>fps and side=="L" and progress>.11 and progress<.16:
				await capture(f,id+("-after" if enabled else "-before"))
				captured = true
		source_end = f.p.position.z
	var mean := 0.0
	for value in drift: mean += value
	mean /= maxf(1,drift.size())
	var result := {"mean_support_drift_mps":mean,"support_frame_pairs":drift.size(),"peak_ik_error_m":peak_error,"peak_vertical_speed_mps":peak_vertical,"source_end_z":source_end}
	dispose(f)
	return result

func edge_cases(id: String) -> void:
	var f := fixture(id)
	for frame in 130: await step(f,Vector3(0,0,.02),1.0/60)
	# Wait for the full support interval rather than freezing an unloaded leg.
	for frame in 80:
		await step(f,Vector3(0,0,.02),1.0/60)
		var ready := false
		for state in f.actor.contacts.foot_plant.support.values(): ready = ready or state.weight>.99
		if ready: break
	var phase: float = f.actor.animator.current_animation_position
	sim.running = false
	# Settle the root before measuring a paused pose. Pausing does not rewind
	# the existing display interpolation to the authoritative position.
	for frame in 45: await step(f,Vector3.ZERO,1.0/60)
	var settled: Dictionary = f.actor.contacts.observed.duplicate(true)
	for frame in 30: await step(f,Vector3.ZERO,1.0/60)
	var paused := is_equal_approx(phase,f.actor.animator.current_animation_position)
	for side in ["L","R"]: paused = paused and settled["foot"+side].distance_to(f.actor.contacts.observed["foot"+side])<.001
	expect(paused,id+": stopping time keeps the current walk phase and settled foot pose")
	sim.running = true
	# A large relocation must not retain an anchor in the old part of town.
	f.p.position += Vector3(8,0,0)
	f.actor.update_state(f.p,1,true);f.actor.animator.advance(.001)
	await process_frame
	var nearby := true
	for state in f.actor.contacts.foot_plant.support.values(): nearby = nearby and state.anchor.distance_to(f.actor.global_position)<1.0
	expect(nearby,id+": a large relocation discards old world anchors")
	# Turn while a support exists. Compare its retained heading, not just the
	# previous frame's tiny rotation, so gradual sharp corners also release.
	for frame in 40: await step(f,Vector3(.02,0,0),1.0/60)
	var turn_ok := true
	var heading: Vector3 = f.actor.visual.global_basis.z.normalized()
	for anchor in f.actor.contacts.foot_plant.anchors.values(): turn_ok = turn_ok and heading.dot(anchor.forward)>.85
	expect(turn_ok,id+": a turn does not drag a foot anchored in the previous heading")
	f.p.moving = false;f.p.action = "idle"
	await step(f,Vector3.ZERO,1.0/60)
	expect(f.actor.contacts.foot_plant.anchors.is_empty() and not f.actor.contacts.foot_ik.L.active and not f.actor.contacts.foot_ik.R.active,id+": stopping travel releases walking constraints before idle or another activity")
	dispose(f)

func create_stage() -> void:
	stage = Node3D.new();root.add_child(stage)
	var light := DirectionalLight3D.new();light.rotation_degrees = Vector3(-50,-30,0);light.light_energy = .8;stage.add_child(light)
	var environment := WorldEnvironment.new();var env := Environment.new()
	env.background_mode = Environment.BG_COLOR;env.background_color = Color("#d9e0df")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color = Color.WHITE;env.ambient_light_energy = .5
	environment.environment = env;stage.add_child(environment)
	var floor := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size = Vector2(50,50);floor.mesh = plane
	var material := StandardMaterial3D.new();material.albedo_color = Color("#bfc7bc");floor.material_override = material;stage.add_child(floor)
	for z in range(-1,12):
		var line := MeshInstance3D.new();var box := BoxMesh.new();box.size = Vector3(5,.002,.012);line.mesh = box;line.position = Vector3(0,.001,z*.5)
		var ink := StandardMaterial3D.new();ink.albedo_color = Color("#949e93");line.material_override = ink;stage.add_child(line)
	camera = Camera3D.new();camera.current = true;camera.fov = 35;stage.add_child(camera)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	sim = root.get_node("Sim");sim.set_process(false);sim.reset(711,12);sim.running = true
	var people_before: Array = sim._encode(sim.people).duplicate(true)
	var rng_before: int = sim.rng.state
	root.size = Vector2i(720,720)
	create_stage()
	for id in IDS:
		report.cases[id] = {}
		for condition in [[.65,60.0],[1.2,60.0],[2.16,30.0]]:
			var speed: float = condition[0];var fps: float = condition[1]
			var baseline := await measure(id,false,speed,fps,speed==1.2)
			var corrected := await measure(id,true,speed,fps,speed==1.2)
			var key := "%.2fmps-%dfps"%[speed,fps]
			report.cases[id][key] = {"baseline":baseline,"corrected":corrected}
			expect(corrected.support_frame_pairs>=12 and corrected.mean_support_drift_mps<baseline.mean_support_drift_mps*.2 and corrected.mean_support_drift_mps<.08,id+" "+key+": final support-foot drift is reduced by at least 80 percent and below 8cm/s")
			expect(corrected.peak_ik_error_m<.055,id+" "+key+": support targets remain within 5.5cm of the solved foot; residual reach error is reported")
		await edge_cases(id)
	expect(sim._encode(sim.people)==people_before and sim.rng.state==rng_before,"Presentation fixtures do not mutate the town's people or consume its random state")
	report.checks = checks;report.failures = failures
	var filename := "headless.json" if DisplayServer.get_name()=="headless" else "gpu.json"
	FileAccess.open(OUT+"/"+filename,FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("Resident foot plant checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

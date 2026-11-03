extends SceneTree

# Controlled presentation fixture, not natural emergence or human playtesting.
# Setup only: remove authored routines, lower needs and defer new autonomous
# plans. Keep the authored initial positions, skills, relationships and roster.
# After propose_project, only simulation time, animation time and camera move.
const OUT := "res://builds/interaction-presentation"
const SEED := 71103
const IDS := ["haru", "osamu"]
const OBJECT_ID := "workshop_radio"
const DT := 1.0 / 60.0
const MINUTES_PER_FRAME := 6.0 / 60.0
const LIMIT_MINUTES := 240
const CONTACT_LIMIT := .04
const PHASES := ["to_source", "take", "carry_to_target", "place", "working", "take_return", "carry_to_source", "return", "completed"]

var main
var sim
var checks: Array = []
var failures: Array[String] = []
var artifact_failures: Array[String] = []
var session_id := ""
var frame_number := 0
var run_directory := ""
var save_path := ""
var saved := false
var captured := {}
var initial_positions := {}
var prior_carry := {}
var carry_metrics := {"samples": 0, "missing_actual_samples": 0, "peak_palm_grip_error_m": 0.0, "peak_view_transform_error_m": 0.0, "object_distance_m": 0.0, "left_palm_distance_m": 0.0, "right_palm_distance_m": 0.0}
var contact_metrics := {}
var report := {"scope": "Controlled real-Main 12-person radio fixture. Not natural emergence, human playtesting or proof of fun.",
	"fixture": {"seed": SEED, "population": 12, "participants": IDS, "initial_positions": "authored, unchanged", "setup_changes": ["all authored routines empty", "fatigue/hunger/quiet 0.1", "next_plan_minute/support_next_attempt beyond the fixture horizon"], "proposal": "propose_project(haru,osamu,radio,true)", "mid_run_state_overrides": []},
	"sampling": {"fps": 60, "simulation_minutes_per_frame": MINUTES_PER_FRAME, "automatic_simulation_process": false, "animation_callback": "manual", "actual_pose": "ResidentContacts._observe at skeleton_updated after modifiers; no later FK point() reads", "wrist_and_palm_limit_m": CONTACT_LIMIT},
	"phase_order": [], "phases": {}, "artifacts": [], "save_restore": {}}

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> bool:
	checks.append({"ok": ok, "message": message})
	if not ok:
		failures.append(message)
		push_error(message)
	return ok

func encode(value: Variant) -> Variant:
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Transform3D: return {"origin": encode(value.origin), "basis": [encode(value.basis.x), encode(value.basis.y), encode(value.basis.z)]}
	if value is Array:
		var result := []
		for item in value: result.append(encode(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = encode(value[key])
		return result
	return value

func equivalent(a: Variant, b: Variant) -> bool:
	if a is Vector3 and b is Vector3: return a.distance_to(b) < 1e-8
	if (a is int or a is float) and (b is int or b is float): return absf(float(a) - float(b)) < 1e-8
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not equivalent(a[index], b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	return a == b

func session() -> Dictionary:
	return sim.interactions.sessions.get(session_id, {})

func object_record() -> Dictionary:
	return sim.interactions.objects.get(OBJECT_ID, {})

func visible_object() -> Node3D:
	return main.interaction_view.object_node(OBJECT_ID)

func object_count() -> int:
	var count := 0
	for child in main.interaction_view.get_children():
		if child.get_meta("interaction_object_id", "") == OBJECT_ID: count += 1
	return count

func motion_result(id: String) -> Dictionary:
	var contacts = main.avatars[id].contacts
	if not is_instance_valid(contacts.interaction_motion): return {}
	return contacts.interaction_motion.last_result

func actual_hand(id: String, side: String) -> Dictionary:
	# SkeletonModifier restores the FK pose outside its processing signal. The
	# contact observer captures actual bones/palms at skeleton_updated instead.
	# Missing observations are failures, never substituted with desired targets.
	var observed: Dictionary = main.avatars[id].contacts.observed
	if not observed.get("hand" + side) is Vector3 or not observed.get("palm" + side) is Vector3: return {}
	if not observed.get("hand_pose" + side) is Transform3D: return {}
	return {"wrist": observed["hand" + side], "palm": observed["palm" + side], "hand_pose": observed.get("hand_pose" + side)}

func manual_mode() -> void:
	sim.set_process(false)
	main.set_process(false)
	for actor in main.avatars.values():
		actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.jrpg.set_process(false)

func set_camera(reverse: bool = false) -> void:
	# The primary view is the workshop's front-left side; the reverse detail
	# shows faces and the working hands without moving a person or a prop.
	main.camera.h_offset = 0
	main.camera.fov = 46
	main.camera.global_position = Vector3(-2.8, 2.1, -9.7) if reverse else Vector3(-3.25, 2.05, -4.4)
	main.camera.look_at(Vector3(-.7, 1.05, -7.35))
	main.get_node("Town").update_view(main.camera.global_position)
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)

func frame(advance_simulation: bool = true) -> void:
	if advance_simulation: sim.advance_minutes(MINUTES_PER_FRAME)
	main._process(DT)
	for actor in main.avatars.values():
		actor.animator.advance(DT)
		actor.jrpg._process(DT)
	set_camera()
	await process_frame
	frame_number += 1

func prop_bounds() -> AABB:
	var node := visible_object()
	var points: Array[Vector3] = []
	for part in node.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var mesh_bounds: AABB = part.get_aabb()
		for corner in 8: points.append(part.global_transform * mesh_bounds.get_endpoint(corner))
	if points.is_empty(): return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	return bounds

func actor_snapshot(id: String) -> Dictionary:
	var actor = main.avatars[id]
	var p: Dictionary = sim.person(id)
	return {"position": p.position, "visible_position": actor.global_position, "path": p.path.duplicate(), "moving": p.moving,
		"clip": actor.animation_name, "role": sim.interactions.pose_for(id).get("role", ""), "motion": motion_result(id).duplicate(true), "contacts": actor.contacts.observed.duplicate(true)}

func snapshot() -> Dictionary:
	var actors := {}
	for id in IDS: actors[id] = actor_snapshot(id)
	var bounds := prop_bounds()
	return {"frame": frame_number, "minute": sim.elapsed, "remainder": sim.minute_remainder, "clock": sim.clock_text(),
		"session": session().duplicate(true), "object": object_record().duplicate(true), "object_transform": visible_object().global_transform,
		"world_bounds": {"minimum": bounds.position, "maximum": bounds.end}, "actors": actors, "rendered_object_count": object_count()}

func capture(label: String, reverse: bool = false) -> void:
	if DisplayServer.get_name() == "headless": return
	set_camera(reverse)
	await RenderingServer.frame_post_draw
	var path := run_directory + "/" + label + ".png"
	var error: int = root.get_texture().get_image().save_png(path)
	if error != OK: artifact_failures.append("Could not save " + path)
	report.artifacts.append({"file": path, "saved": error == OK, "frame": frame_number, "minute": sim.elapsed, "phase": session().get("phase", ""), "camera": "faces and work detail" if reverse else "workshop front-left"})
	set_camera()

func observe_phase() -> void:
	var current := session()
	if current.is_empty(): return
	var phase: String = current.phase
	if report.phase_order.is_empty() or report.phase_order[-1] != phase:
		report.phase_order.append(phase)
		report.phases[phase] = {"entered": snapshot(), "samples": 0}
	report.phases[phase].samples += 1
	if not contact_metrics.has(phase): contact_metrics[phase] = {"samples": 0, "missing_actual_samples": 0, "peak_wrist_error_m": 0.0, "peak_palm_error_m": 0.0, "worst": {}}
	for id in IDS:
		var actor = main.avatars[id]
		var result := motion_result(id)
		if not result.has("left") or not result.has("palm_local_left"): continue
		for side in ["L", "R"]:
			if not actor.contacts.hand_ik[side].active: continue
			var metrics: Dictionary = contact_metrics[phase]
			var actual := actual_hand(id, side)
			if actual.is_empty():
				metrics.missing_actual_samples += 1
				metrics.missing_at = {"frame": frame_number, "person": id, "side": side, "observed_keys": actor.contacts.observed.keys()}
				continue
			var word := "left" if side == "L" else "right"
			var target: Transform3D = result[word]
			var wrist: Vector3 = actual.wrist
			var palm: Vector3 = actual.palm
			var wrist_error := wrist.distance_to(target.origin)
			var palm_error: float = palm.distance_to(result["palm_" + word])
			metrics.samples += 1
			if wrist_error > metrics.peak_wrist_error_m or palm_error > metrics.peak_palm_error_m:
				metrics.worst = {"frame": frame_number, "person": id, "side": side, "phase_progress": sim.interactions.pose_for(id).get("phase_progress", 0), "wrist": wrist, "target": target.origin, "palm": palm, "palm_target": result["palm_" + word], "hand_pose": actual.hand_pose}
			metrics.peak_wrist_error_m = maxf(metrics.peak_wrist_error_m, wrist_error)
			metrics.peak_palm_error_m = maxf(metrics.peak_palm_error_m, palm_error)
	if phase in ["carry_to_target", "carry_to_source"]: sample_carry()

func sample_carry() -> void:
	var holder: String = object_record().holder
	if holder.is_empty() or not sim.person(holder).moving: return
	var actor = main.avatars[holder]
	var motion = actor.contacts.interaction_motion
	var result := motion_result(holder)
	if not motion.object_active or not result.has("palm_local_left"): return
	var transform: Transform3D = visible_object().global_transform
	var grips: Dictionary = motion.radio_grips()
	var measured := {"object": transform.origin}
	for side in ["L", "R"]:
		var word := "left" if side == "L" else "right"
		var actual := actual_hand(holder, side)
		if actual.is_empty():
			carry_metrics.missing_actual_samples += 1
			return
		var palm: Vector3 = actual.palm
		measured[word] = palm
		carry_metrics.peak_palm_grip_error_m = maxf(carry_metrics.peak_palm_grip_error_m, palm.distance_to(transform * grips[side]))
	carry_metrics.samples += 1
	carry_metrics.peak_view_transform_error_m = maxf(carry_metrics.peak_view_transform_error_m, transform.origin.distance_to(motion.object_transform.origin))
	if prior_carry.get("phase", "") == session().phase:
		carry_metrics.object_distance_m += measured.object.distance_to(prior_carry.object)
		carry_metrics.left_palm_distance_m += measured.left.distance_to(prior_carry.left)
		carry_metrics.right_palm_distance_m += measured.right.distance_to(prior_carry.right)
	measured.phase = session().phase
	prior_carry = measured

func maybe_capture() -> void:
	var phase: String = session().phase
	if phase == "completed" or captured.has(phase): return
	var progress: float = sim.interactions.pose_for("haru").get("phase_progress", 0)
	if phase == "to_source":
		if progress < .95: return
		captured[phase] = true
		report.phases[phase].middle = snapshot()
		await capture("00a-approach-source")
		return
	if progress < .42 or progress > .65: return
	captured[phase] = true
	report.phases[phase].middle = snapshot()
	await capture("%02d-" % PHASES.find(phase) + phase)
	if phase == "working":
		check_working()
		await capture("04-working-faces", true)

func check_working() -> void:
	var roles := {}
	var right_palms := {}
	var dial := visible_object().global_transform * Vector3(.112, .08, .112)
	for id in IDS:
		var pose: Dictionary = sim.interactions.pose_for(id)
		var result := motion_result(id)
		roles[pose.get("role", "")] = id
		if result.has("palm_local_right"):
			var actual := actual_hand(id, "R")
			if not actual.is_empty(): right_palms[id] = actual.palm
	var distinct: bool = roles.has("operator") and roles.has("support") and right_palms.size() == 2
	expect(distinct, "Working uses one operator and one supporting participant, with measured hands for both")
	if distinct:
		expect(right_palms[roles.operator].distance_to(dial) <= CONTACT_LIMIT, "The operator's actual right palm reaches the radio dial within 4cm")
		expect(right_palms[roles.operator].distance_to(right_palms[roles.support]) > .04, "The supporting participant holds a different point from the operator's adjusting hand")
	var bounds := prop_bounds()
	var table = main.get_node("Town/ActivityLayout/Workshop/radio_workAssembly/Worktable")
	expect(absf(bounds.position.y - float(sim.interactions.config.target_position.y)) < .001, "The visible radio bottom contacts the configured worktable top within 1mm")
	var local: Vector3 = table.to_local(visible_object().global_position)
	expect(absf(local.x) + .18 <= .775 and absf(local.z) + .109 <= .42, "The actual radio lies inside the worktable footprint, including its front dials")

func restore_during_carry() -> void:
	var before: Dictionary = sim.interactions.serialize().duplicate(true)
	var actor_instance: int = main.avatars.haru.get_instance_id()
	var old_node := visible_object()
	var before_state := snapshot()
	saved = true
	if not expect(sim.save_game(save_path), "A dedicated test save can be written during actual carrying"): return
	if not expect(sim.load_game(save_path), "The actual mid-carry save loads through LifeSimulation.load_game"): return
	manual_mode()
	expect(equivalent(before, sim.interactions.serialize()), "Save/load preserves the real object reservation, holder and in-progress workflow")
	expect(main.avatars.haru.get_instance_id() != actor_instance, "Loading rebuilds the actual Main residents instead of reusing the former actor")
	expect(object_count() == 1 and visible_object() == old_node, "Rebuilding Main retains one object node with the same logical ID")
	await frame(false)
	var motion = main.avatars.haru.contacts.interaction_motion
	expect(motion.object_active and motion.object_id == OBJECT_ID and object_record().holder == "haru", "The rebuilt carrier reconstructs the held object's presentation from the saved workflow")
	report.save_restore = {"before": before_state, "after": snapshot(), "save_path": save_path, "same_frame_presentation_sync_without_simulation_advance": true}
	await capture("03-restored-mid-carry")
	# Do not include a reconstruction's visual interpolation in traveled distance.
	prior_carry.clear()

func finish() -> void:
	report.contacts = contact_metrics
	report.carry = carry_metrics
	report.functional_checks = {"total": checks.size(), "passed": checks.size() - failures.size(), "failed": failures.size(), "results": checks}
	report.failures = failures
	report.artifact_failures = artifact_failures
	report.rendering = {"available": DisplayServer.get_name() != "headless", "driver": DisplayServer.get_name(), "size": [root.size.x, root.size.y], "artifacts_separate_from_functional_counts": true}
	report.status = "passed" if failures.is_empty() and artifact_failures.is_empty() else "failed"
	var mode := "headless" if DisplayServer.get_name() == "headless" else "gpu"
	FileAccess.open(OUT + "/" + mode + ".json", FileAccess.WRITE).store_string(JSON.stringify(encode(report), "\t") + "\n")
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if FileAccess.file_exists(save_path + ".tmp"): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + ".tmp"))
	print("World interaction presentation: %d passed, %d functional failures; %d artifact failures" % [checks.size() - failures.size(), failures.size(), artifact_failures.size()])
	quit(0 if failures.is_empty() and artifact_failures.is_empty() else 1)

func run() -> void:
	var mode := "headless" if DisplayServer.get_name() == "headless" else "gpu"
	run_directory = OUT + "/" + mode + "-" + str(OS.get_process_id())
	save_path = "user://test-world-interaction-presentation-%d.json" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_directory))
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = root.get_node("Sim")
	sim.set_process(false)
	main.set_process(false)
	sim.reset(SEED, 12)
	for p in sim.people:
		sim.definitions[p.id].routines = []
		p.fatigue = .1; p.hunger = .1; p.quiet = .1
		p.next_plan_minute = LIMIT_MINUTES + 1000
		p.support_next_attempt = LIMIT_MINUTES + 1000
		if p.id in IDS: initial_positions[p.id] = p.position
	main._start_play()
	sim.running = true
	main._select("haru", false)
	main.get_node("%CloseRoster").pressed.emit()
	main.following = false
	main.toast_left = 0
	main.get_node("%Toast").hide()
	manual_mode()
	await frame(false)
	var old_radio = main.get_node("Town/ActivityLayout/Workshop/radio_workAssembly/Radio")
	expect(not old_radio.is_visible_in_tree() and object_count() == 1, "The legacy static radio is hidden and exactly one state-owned radio is drawn")
	var source: Vector3 = sim.interactions.config.source_position
	var source_marker: Node3D = main.get_node("Town/ActivityLayout/Workshop/RadioShelf/RadioSurface")
	var approach_marker: Node3D = main.get_node("Town/ActivityLayout/Workshop/RadioShelf/Approach")
	expect(source_marker.global_position.distance_to(source) < .001 and approach_marker.global_position.distance_to(sim.interactions.config.source_approach) < .001, "The saved shelf surface and approach markers match the actual workflow coordinates")
	expect(sim.activities.walkable("workshop", sim.interactions.config.source_approach), "The shelf approach is walkable on the real indoor grid")
	var initial_bounds := prop_bounds()
	expect(absf(initial_bounds.position.y - source.y) < .001 and initial_bounds.size.x > .35 and initial_bounds.size.z > .17, "The visible full-size radio rests on the shelf top without floating or sinking")
	await capture("00-radio-on-shelf")
	var reply: Dictionary = sim.work_family.propose_project("haru", "osamu", "radio", true)
	report.reply = reply
	if not expect(reply.get("status", "") == "accept", "The two residents agree to the controlled radio project through the real proposal API"): finish(); return
	var meeting: Dictionary = sim.meetings[-1]
	session_id = meeting.get("interaction_id", "")
	if not expect(not session_id.is_empty() and not session().is_empty(), "The accepted real meeting owns a radio workflow"): finish(); return
	report.initial_positions = initial_positions
	observe_phase()
	while sim.elapsed < LIMIT_MINUTES and session().get("phase", "") not in ["completed", "interrupted"]:
		await frame()
		observe_phase()
		await maybe_capture()
		var pose: Dictionary = sim.interactions.pose_for("haru")
		if not saved and session().phase == "carry_to_target" and float(pose.get("phase_progress", 0)) > .25:
			await restore_during_carry()
	expect(report.phase_order == PHASES, "The same workflow follows real approach, take, carry, place, work and return phases in order")
	expect(saved, "The workflow reaches a real moving carry phase for save reconstruction")
	for phase in ["take", "carry_to_target", "place", "working", "take_return", "carry_to_source", "return"]:
		var metrics: Dictionary = contact_metrics.get(phase, {})
		expect(int(metrics.get("samples", 0)) >= 4 and int(metrics.get("missing_actual_samples", 0)) == 0 and float(metrics.get("peak_wrist_error_m", 99)) <= CONTACT_LIMIT and float(metrics.get("peak_palm_error_m", 99)) <= CONTACT_LIMIT, phase + ": final wrists and actual palms remain within 4cm of their respective contact targets")
	expect(carry_metrics.samples >= 4 and carry_metrics.object_distance_m > .2 and carry_metrics.left_palm_distance_m > .2 and carry_metrics.right_palm_distance_m > .2, "Carrying moves the visible object and both measured palms together along a real route")
	expect(carry_metrics.missing_actual_samples == 0 and carry_metrics.peak_palm_grip_error_m <= CONTACT_LIMIT and carry_metrics.peak_view_transform_error_m < .0001, "Both actual carrying palms stay within 4cm of the same visible object's grasp points")
	for id in IDS:
		expect(initial_positions[id].distance_to(sim.person(id).position) > 1, id + ": the participant actually travels from the authored initial location")
	await frame(false)
	var final: Dictionary = object_record()
	expect(session().get("phase", "") == "completed" and final.holder.is_empty() and final.container == "radio_shelf" and final.reserved_by.is_empty(), "The completed workflow returns the unreserved object to the shelf")
	expect(object_count() == 1 and visible_object().global_position.distance_to(source) < .001 and not old_radio.is_visible_in_tree(), "Exactly one radio remains at the source after work and cleanup")
	report.final = snapshot()
	await capture("08-radio-returned-to-shelf")
	finish()

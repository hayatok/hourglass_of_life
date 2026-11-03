extends SceneTree

# Controlled real-Main fixtures, not natural emergence or human playtesting.
# Initial constraints and two starting floor positions are declared below.
# No participant, board choice, piece, skill, body scale or phase is rewritten
# after propose_play. Child reach failures are reported with the same 4cm gate.
const DEFAULT_OUT := "res://builds/tabletop-presentation"
const DT := 1.0 / 60.0
const SIM_STEP := 6.0 / 60.0
const CONTACT_LIMIT := .04
const GRASP_LIMIT := .010
const HORIZON := 620
const CASES := {"adult": ["haru", "osamu"], "child": ["rin", "ryo"]}

var main
var sim
var output_dir := DEFAULT_OUT
var json_output := ""
var run_dir := ""
var fixture_name := ""
var ids: Array = []
var game_id := ""
var frame_index := 0
var checks: Array = []
var failures: Array[String] = []
var artifact_failures: Array[String] = []
var case_report := {}
var original_nodes := {}
var piece_ids: Array = []
var captured := {}
var previous_people := {}
var previous_token := ""
var restored := false
var save_path := ""
var report := {"scope": "Controlled 12-person Main fixtures; not natural behavior, human playtesting or proof of fun.",
	"sampling": {"fps": 60, "simulation_minutes_per_frame": SIM_STEP, "automatic_simulation": false, "animation_callback": "manual", "actual_contacts": "ResidentContacts.observed at skeleton_updated after modifiers; no later FK point() reads", "pinch_definition": "Actual thumb/index poses applied to distal mesh-cap pad measurements; midpoint and individual pad targets checked separately, then GPU mesh review", "contact_limit_m": CONTACT_LIMIT,"grasp_limit_m":GRASP_LIMIT,"finger_pad_limit_m":.006},
	"fixture_setup": {"routines": "all empty", "initial_needs": {"hunger": .02, "fatigue": .02, "quiet": .1, "connection": .5}, "new_autonomous_plans": "deferred beyond horizon", "unrelated_actions": "initial rest, long remaining duration", "participant_floor_positions": [[-4.5, 0, 7.2], [-1.5, 0, 7.2]], "mid_run_overrides": [], "skills_relationships_age_body_scale": "unchanged"},
	"cases": {}, "artifacts": []}

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> bool:
	checks.append({"fixture": fixture_name, "ok": ok, "message": message})
	if not ok:
		var text := fixture_name + ": " + message
		failures.append(text)
		push_error(text)
	return ok

func encode(value: Variant) -> Variant:
	if value is Quaternion: return [value.x,value.y,value.z,value.w]
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Basis: return [encode(value.x), encode(value.y), encode(value.z)]
	if value is Transform3D: return {"origin": encode(value.origin), "basis": encode(value.basis)}
	if value is Array:
		var result := []
		for item in value: result.append(encode(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = encode(value[key])
		return result
	return value

func same(a: Variant, b: Variant) -> bool:
	if a is Vector3 and b is Vector3: return a.distance_to(b) < 1e-8
	if (a is int or a is float) and (b is int or b is float): return absf(float(a) - float(b)) < 1e-8
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same(a[index], b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]): return false
		return true
	return a == b

func current() -> Dictionary:
	return sim.tabletop.sessions.get(game_id, {})

func motion(id: String) -> Dictionary:
	return main.avatars[id].contacts.interaction_motion.last_result

func piece_node(id: String) -> Node3D:
	return main.tabletop_view.piece_node(id)

func manual_mode() -> void:
	sim.set_process(false); main.set_process(false)
	for actor in main.avatars.values():
		actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.jrpg.set_process(false)

func camera_view(detail: bool = false) -> void:
	var center: Vector3 = sim.tabletop.config.board_origin + Vector3.UP * .09
	if detail and not current().get("selected_piece", "").is_empty():
		center = piece_node(current().selected_piece).global_position + Vector3.UP * .055
	main.camera.h_offset = 0
	main.camera.fov = 43 if not detail else 38
	main.camera.global_position = center + (Vector3(-1.30, .95, -2.10) if not detail else Vector3(-.62, .48, -.72))
	main.camera.look_at(center)
	main.get_node("Town").update_view(main.camera.global_position)
	# Name-label scale is camera-dependent: refresh after the test's camera.
	for id in main.avatars: main._update_resident_name_label(main.avatars[id], id)

func frame(advance_simulation: bool = true) -> void:
	if advance_simulation: sim.advance_minutes(SIM_STEP)
	main._process(DT)
	for actor in main.avatars.values():
		actor.animator.advance(DT)
		actor.jrpg._process(DT)
	camera_view()
	await process_frame
	frame_index += 1

func bounds_of(node: Node3D) -> AABB:
	var points: Array[Vector3] = []
	for part in node.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var local_box: AABB = part.get_aabb()
		for corner in 8: points.append(part.global_transform * local_box.get_endpoint(corner))
	if points.is_empty(): return AABB()
	var world_box := AABB(points[0], Vector3.ZERO)
	for point in points: world_box = world_box.expand(point)
	return world_box

func pool_snapshot() -> Array:
	var result := []
	for id in piece_ids:
		var p: Dictionary = sim.tabletop.pieces[id]
		result.append({"id": id, "location": p.location, "holder": p.holder, "container": p.container, "position": p.position, "visible_position": piece_node(id).global_position, "cell": p.cell})
	return result

func snapshot() -> Dictionary:
	var actors := {}
	for id in ids:
		var actor = main.avatars[id]
		var p: Dictionary = sim.person(id)
		actors[id] = {"age": p.age, "position": p.position, "moving": p.moving, "path": p.path.duplicate(), "clip": actor.animation_name, "motion": motion(id).duplicate(true), "observed": actor.contacts.observed.duplicate(true)}
	return {"frame": frame_index, "elapsed": sim.elapsed, "remainder": sim.minute_remainder, "clock": sim.clock_text(), "session": current().duplicate(true), "pieces": pool_snapshot(), "actors": actors}

func capture(label: String, detail: bool = false) -> void:
	if DisplayServer.get_name() == "headless": return
	camera_view(detail)
	await RenderingServer.frame_post_draw
	var path := run_dir + "/" + fixture_name + "-" + label + ".png"
	var error: int = root.get_texture().get_image().save_png(path)
	if error != OK: artifact_failures.append("Could not save " + path)
	report.artifacts.append({"file": path, "saved": error == OK, "fixture": fixture_name, "frame": frame_index, "elapsed": sim.elapsed, "phase": current().get("phase", "supply"), "turn": current().get("turn", 0), "camera": "hand detail" if detail else "board and faces", "roster_open": main.get_node("%HUD").residents_panel.visible})
	camera_view()

func rendered_count() -> int:
	var count := 0
	for child in main.tabletop_view.get_children():
		if not str(child.get_meta("tabletop_piece_id", "")).is_empty(): count += 1
	return count

func record_state() -> void:
	var state := current()
	var token := "%s:%d:%s:%s" % [state.phase, state.turn, state.selected_piece, state.get("align_stage", "")]
	case_report.seen_phases[state.phase] = true
	if token != previous_token:
		previous_token = token
		case_report.timeline.append({"frame": frame_index, "elapsed": sim.elapsed, "phase": state.phase, "turn": state.turn, "piece": state.selected_piece, "selected_cell": state.selected_cell, "moves": state.moves.size(), "align_stage": state.get("align_stage", "")})
	var current_ids: Array = sim.tabletop.pieces.keys(); current_ids.sort()
	case_report.same_pool_ids = case_report.same_pool_ids and current_ids == piece_ids and rendered_count() == 16
	for id in piece_ids:
		var node := piece_node(id)
		case_report.same_nodes = case_report.same_nodes and node == original_nodes[id] and is_instance_valid(node)
		var piece: Dictionary = sim.tabletop.pieces[id]
		var sequence: Array = case_report.piece_locations[id]
		if sequence.is_empty() or sequence[-1] != piece.location: sequence.append(piece.location)
		if piece.location == "board":
			var box := bounds_of(node)
			var cell: Vector3 = sim.tabletop.cell_centers()[piece.cell]
			case_report.peak_cell_position_error_m = maxf(case_report.peak_cell_position_error_m, node.global_position.distance_to(cell))
			case_report.peak_board_bottom_error_m = maxf(case_report.peak_board_bottom_error_m, absf(box.position.y - case_report.board_top_y))
	for id in ids:
		var position: Vector3 = sim.person(id).position
		if previous_people.has(id): case_report.travel_distance_m[id] += position.distance_to(previous_people[id])
		previous_people[id] = position
		measure_contact(id)

func measure_contact(id: String) -> void:
	var result := motion(id)
	var hand: String = result.get("active_hand", "")
	if hand not in ["L", "R"]: return
	var phase: String = current().phase
	if not case_report.contacts.has(phase): case_report.contacts[phase] = {"samples": 0, "missing_actual_samples": 0, "peak_wrist_error_m": 0.0, "peak_pinch_target_error_m": 0.0, "grasp_samples": 0, "peak_actual_piece_grasp_error_m": 0.0, "worst": {}}
	var metrics: Dictionary = case_report.contacts[phase]
	var observed: Dictionary = main.avatars[id].contacts.observed
	var suffix := "left" if hand == "L" else "right"
	if not observed.get("hand" + hand) is Vector3 or not observed.get("pinch" + hand) is Vector3:
		metrics.missing_actual_samples += 1
		metrics.missing_at = {"frame": frame_index, "person": id, "hand": hand, "observed_keys": observed.keys()}
		return
	var actual_wrist: Vector3 = observed["hand" + hand]
	var actual_pinch: Vector3 = observed["pinch" + hand]
	var wrist_target: Transform3D = result[suffix]
	var pinch_target: Vector3 = result["pinch_" + suffix]
	var wrist_error := actual_wrist.distance_to(wrist_target.origin)
	var pinch_error := actual_pinch.distance_to(pinch_target)
	metrics.samples += 1
	if wrist_error > metrics.peak_wrist_error_m or pinch_error > metrics.peak_pinch_target_error_m:
		metrics.worst = {"frame": frame_index, "person": id, "age": sim.person(id).age, "hand": hand, "piece": result.get("object_id", ""), "progress": result.phase_progress, "actual_wrist": actual_wrist, "wrist_target": wrist_target, "actual_pinch": actual_pinch, "pinch_target": pinch_target, "motion": result.duplicate(true)}
	metrics.peak_wrist_error_m = maxf(metrics.peak_wrist_error_m, wrist_error)
	metrics.peak_pinch_target_error_m = maxf(metrics.peak_pinch_target_error_m, pinch_error)
	# Reach/release legitimately separate the hand from the object. Their actual
	# wrist/pinch still obey the target gate above; only a fully closed grasp
	# additionally requires contact with the actual visible mesh's pinch centre.
	if float(result.get("grasp_weight", 0)) >= .9999:
		var node := piece_node(current().selected_piece)
		var mesh_grip: Vector3 = node.global_transform * Vector3(0, .008, 0)
		var grasp_error := actual_pinch.distance_to(mesh_grip)
		metrics.grasp_samples += 1
		if not metrics.has("pad_samples"): metrics.pad_samples=0;metrics.peak_pad_error_m=0.0;metrics.unsupported_pads=0
		var pads: Dictionary = main.avatars[id].contacts.observed.get("finger_pad"+hand,{})
		var word := "left" if hand=="L" else "right"
		var pad_targets: Dictionary = result.get("finger_pad_target_"+word,{})
		if not result.get("finger_pad_supported",false) or pads.is_empty() or pad_targets.is_empty():
			metrics.unsupported_pads += 1
		else:
			metrics.pad_samples += 1
			for finger in ["thumb","index"]: metrics.peak_pad_error_m=maxf(metrics.peak_pad_error_m,pads[finger].distance_to(pad_targets[finger]))
		metrics.peak_actual_piece_grasp_error_m = maxf(metrics.peak_actual_piece_grasp_error_m, grasp_error)
		if not case_report.grasp_people.has(id): case_report.grasp_people.append(id)
		if grasp_error > case_report.peak_grasp_error_m:
			case_report.peak_grasp_error_m = grasp_error
			case_report.worst_grasp = {"frame": frame_index, "person": id, "age": sim.person(id).age, "phase": phase, "piece": current().selected_piece, "actual_pinch": actual_pinch, "visible_mesh_grip": mesh_grip, "view_transform": node.global_transform, "motion": result.duplicate(true)}

func maybe_capture() -> void:
	var state := current()
	var pose: Dictionary = sim.tabletop.pose_for(ids[0])
	var phase: String = state.phase
	var progress: float = pose.get("phase_progress", 0)
	var key := phase
	if phase == "reach" and state.turn == 2: key = "reach-other-turn"
	if not captured.has(key) and phase not in ["completed", "interrupted"] and progress >= .40 and progress <= .70:
		captured[key] = true
		case_report.samples[key] = snapshot()
		await capture(key)
		if phase in ["reach", "place", "cleanup"]: await capture(key + "-pinch-detail", true)
	if state.moves.size() >= 4 and not captured.has("board-after-four-moves"):
		captured["board-after-four-moves"] = true
		case_report.samples.board_after_four_moves = snapshot()
		await capture("board-after-four-moves")
	if state.result_recorded and not captured.has("result"):
		captured.result = true
		case_report.samples.result = snapshot()
		await capture("result-before-cleanup")

func save_restore() -> void:
	restored = true
	var before: Dictionary = sim.tabletop.serialize().duplicate(true)
	var before_rng: int = sim.rng.state
	var old_actor: int = main.avatars[ids[0]].get_instance_id()
	var before_snapshot := snapshot()
	if not expect(sim.save_game(save_path), "Actual carrying/placement state saves to a dedicated test file"): return
	if not expect(sim.load_game(save_path), "The same real play save loads through LifeSimulation"): return
	manual_mode()
	expect(same(before, sim.tabletop.serialize()) and sim.rng.state == before_rng, "Save restoration preserves board, all pieces, selected move, phase and RNG")
	expect(main.avatars[ids[0]].get_instance_id() != old_actor, "Save loading rebuilds the actual Main actors")
	await frame(false)
	var piece: Dictionary = sim.tabletop.pieces[current().selected_piece]
	var actor_motion = main.avatars[piece.holder].contacts.interaction_motion
	expect(rendered_count() == 16 and actor_motion.object_active and actor_motion.object_id == piece.id, "Rebuilt Main reconstructs the same held token without spawning an extra piece")
	case_report.save_restore = {"success": true, "before": before_snapshot, "after": snapshot(), "save_path": save_path, "presentation_sync_without_simulation_advance": true}
	await capture("restored-placement")
	await capture("restored-placement-pinch-detail", true)

func verify_geometry() -> void:
	var view = main.tabletop_view
	var board := bounds_of(view.board_node)
	case_report.board_top_y = board.end.y
	expect(board.size.distance_to(Vector3(.30, .025, .30)) < .001 and absf(board.position.y - .95) < .001, "The actual wooden board mesh has the configured size and sits on the existing worktable")
	expect(view.board_node.get_node("Cells").get_child_count() == 16, "The visible board has sixteen real cell surfaces")
	var geometry_ok := true
	var supply_ok := true
	for id in piece_ids:
		var node := piece_node(id)
		var box := bounds_of(node)
		geometry_ok = geometry_ok and box.size.distance_to(Vector3(.036, .016, .036)) < .001
		var piece: Dictionary = sim.tabletop.pieces[id]
		supply_ok = supply_ok and piece.location == "supply" and piece.holder.is_empty() and node.global_position.distance_to(piece.position) < .001 and absf(box.position.y - piece.position.y) < .001
	expect(geometry_ok, "All sixteen actual visible wooden-disc meshes have the real 18mm radius, 16mm height and bottom origin")
	expect(supply_ok and rendered_count() == 16, "All sixteen saved pieces already exist in their trays before play, with no invented held prop")
	var tray_ok := true
	for color in [1, 2]:
		var floor: MeshInstance3D = view.trays[color].get_node("Floor")
		var surface: Vector3 = floor.global_transform * Vector3(0, floor.mesh.get_aabb().end.y, 0)
		tray_ok = tray_ok and surface.distance_to(sim.tabletop.bank_position(color, 1)) < .001
	expect(tray_ok, "The bottom token in each stack contacts the actual tray floor within 1mm")

func summarize_case(complete: bool) -> void:
	for phase in (["travel", "think", "align", "reach", "place", "react", "switch_turn", "cleanup", "completed"] if complete else ["travel", "think", "align", "reach", "place", "react"]):
		expect(case_report.seen_phases.has(phase), "The real workflow reaches " + phase)
	expect(case_report.same_pool_ids and case_report.same_nodes, "The same sixteen piece IDs and visible nodes survive every phase and rebuild")
	for phase in (["reach", "place", "cleanup"] if complete else ["reach", "place"]):
		var metrics: Dictionary = case_report.contacts.get(phase, {})
		expect(int(metrics.get("samples", 0)) >= 4 and int(metrics.get("missing_actual_samples", 0)) == 0 and float(metrics.get("peak_wrist_error_m", 99)) <= CONTACT_LIMIT and float(metrics.get("peak_pinch_target_error_m", 99)) <= CONTACT_LIMIT, phase + ": actual modifier-processed wrist and pinch stay within 4cm of their respective targets")
		expect(int(metrics.get("grasp_samples", 0)) >= 2 and float(metrics.get("peak_actual_piece_grasp_error_m", 99)) <= GRASP_LIMIT, phase + ": the fully grasping actual hand meets the same visible token within 1cm")
		expect(int(metrics.get("pad_samples",0))>=2 and int(metrics.get("unsupported_pads",99))==0 and float(metrics.get("peak_pad_error_m",99))<=.006,phase+": actual thumb and index pads reach opposite surfaces of the 36mm token within 6mm")
	expect(float(case_report.peak_cell_position_error_m) < .001 and float(case_report.peak_board_bottom_error_m) < .001, "Placed visible tokens contact their real selected cells and board top within 1mm")
	for id in ids:
		expect(float(case_report.travel_distance_m[id]) > .2, id + " follows a real path to the table or yields space to the other participant")
	if complete:
		var state := current()
		expect(state.phase == "completed" and state.result_recorded and state.moves.size() >= 7, "The same real match reaches an actual win/draw and completes cleanup")
		expect(case_report.grasp_people.size() == 2, "Both real participants take a physical turn with measured actual grasps")
		var turns_ok := true
		for index in state.moves.size(): turns_ok = turns_ok and int(state.moves[index].color) == index % 2 + 1
		expect(turns_ok, "Actual committed moves alternate colors instead of replaying a single placement")
		var sequences_ok := true
		for move in state.moves:
			sequences_ok = sequences_ok and case_report.piece_locations[move.piece] == ["supply", "hand", "board", "hand", "supply"]
		expect(sequences_ok, "Each played token travels from its tray through the actual hand and cell back to storage")
		var stored: bool = rendered_count() == 16 and state.board.count(0) == 16
		for piece in sim.tabletop.pieces.values(): stored = stored and piece.location == "supply" and piece.holder.is_empty() and piece.reserved_by.is_empty() and piece_node(piece.id).global_position.distance_to(sim.tabletop.bank_position(piece.color, piece.ordinal)) < .001
		expect(stored, "Cleanup returns every original token to a tray and releases reservations without making objects disappear")
		expect(case_report.save_restore.get("success", false), "A real held-token phase was saved and rebuilt within the same complete match")
	else:
		expect(case_report.grasp_people.has("rin") and current().moves.size() >= 1, "The actual child attempts and commits a first physical turn; reach errors remain subject to the same 4cm checks")
	case_report.final = snapshot()
	case_report.scope = "complete match including cleanup and save reconstruction" if complete else "child first-turn reach/place only; no claim of full child-match cleanup"
	report.cases[fixture_name] = case_report

func run_fixture(name: String, complete: bool) -> void:
	fixture_name = name; ids = CASES[name]
	game_id = ""; restored = false; captured = {}; previous_people = {}; previous_token = ""; original_nodes = {}
	save_path = "user://test-tabletop-presentation-%s-%d.json" % [name, OS.get_process_id()]
	sim.reset(711, 12)
	# All changes below belong to this declared initial engineering fixture.
	for p in sim.people:
		sim.definitions[p.id].routines = []
		p.next_plan_minute = 999999; p.support_next_attempt = 999999
		p.hunger = .02; p.fatigue = .02; p.quiet = .1; p.connection = .5
		p.meeting_id = ""; p.routine_id = ""; p.activity_spot = ""; p.action = "rest"; p.remaining = 999999
		p.target = p.position; p.destination = p.place; p.path = []; p.moving = false
	for index in 2:
		var p: Dictionary = sim.person(ids[index])
		p.position = Vector3(-4.5, 0, 7.2) if index == 0 else Vector3(-1.5, 0, 7.2)
		p.place = "square"; p.destination = "square"; p.target = p.position
	main._start_play(); sim.running = true
	main._select(ids[0], false); main.following = false
	main.get_node("%HUD")._show_residents(false)
	main.toast_left = 0; main.get_node("%Toast").hide()
	manual_mode()
	await frame(false)
	piece_ids = sim.tabletop.pieces.keys(); piece_ids.sort()
	case_report = {"participants": ids, "initial": {}, "seen_phases": {}, "timeline": [], "samples": {}, "contacts": {}, "piece_locations": {}, "same_pool_ids": piece_ids.size() == 16, "same_nodes": true, "travel_distance_m": {}, "peak_cell_position_error_m": 0.0, "peak_board_bottom_error_m": 0.0, "peak_grasp_error_m": 0.0, "grasp_people": [], "worst_grasp": {}, "save_restore": {}}
	for id in ids: case_report.travel_distance_m[id] = 0.0; previous_people[id] = sim.person(id).position
	for id in piece_ids:
		original_nodes[id] = piece_node(id)
		case_report.piece_locations[id] = ["supply"]
	verify_geometry()
	case_report.initial = snapshot()
	await capture("00-original-trays")
	var reply: Dictionary = sim.propose_play(ids[0], ids[1])
	case_report.proposal = reply
	if not expect(reply.get("status", "") == "accept", "The real consent and slot APIs accept propose_play for this fixture"):
		report.cases[name] = case_report; return
	game_id = sim.tabletop.active_session().id
	record_state()
	while sim.elapsed < HORIZON and current().get("phase", "") not in ["completed", "interrupted"]:
		await frame()
		record_state()
		await maybe_capture()
		if complete and not restored and current().phase == "place":
			var progress: float = sim.tabletop.pose_for(ids[0]).get("phase_progress", 0)
			if progress >= .20 and progress <= .40: await save_restore()
		if not complete and current().moves.size() >= 1 and current().phase=="react":
			case_report.samples.child_first_cell = snapshot()
			await capture("child-first-cell")
			await capture("child-first-cell-detail", true)
			break
	await frame(false)
	record_state()
	summarize_case(complete)
	await capture("final-stored-pool" if complete else "child-first-turn-end")
	for path in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	var requested := "all"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--json-output="): json_output = argument.trim_prefix("--json-output=")
		elif argument.begins_with("--fixture="): requested = argument.trim_prefix("--fixture=")
		elif argument.begins_with("--output="):
			var value := argument.trim_prefix("--output=")
			if value.ends_with(".json"): json_output = value
			else: output_dir = value
	var mode := "headless" if DisplayServer.get_name() == "headless" else "gpu"
	run_dir = output_dir + "/" + mode + "-" + str(OS.get_process_id())
	if json_output.is_empty(): json_output = output_dir + "/" + mode + ".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(run_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(json_output).get_base_dir())
	root.size = Vector2i(1440, 900); root.content_scale_size = Vector2i(1440, 900)
	main = load("res://game/scenes/main.tscn").instantiate(); root.add_child(main)
	await process_frame
	sim = root.get_node("Sim"); sim.set_process(false); main.set_process(false)
	if requested in ["all", "adult"]: await run_fixture("adult", true)
	if requested in ["all", "child"]: await run_fixture("child", false)
	if requested not in ["all", "adult", "child"]: expect(false, "Unknown --fixture option")
	report.requested_fixtures = requested
	report.functional_checks = {"total": checks.size(), "passed": checks.size() - failures.size(), "failed": failures.size(), "results": checks}
	report.failures = failures; report.artifact_failures = artifact_failures
	report.rendering = {"available": DisplayServer.get_name() != "headless", "display": DisplayServer.get_name(), "image_output_separate_from_functional_checks": true}
	report.status = "passed" if failures.is_empty() and artifact_failures.is_empty() else "failed"
	FileAccess.open(json_output, FileAccess.WRITE).store_string(JSON.stringify(encode(report), "\t") + "\n")
	print("Tabletop presentation: %d passed, %d functional failures; %d artifact failures" % [checks.size() - failures.size(), failures.size(), artifact_failures.size()])
	quit(0 if failures.is_empty() and artifact_failures.is_empty() else 1)

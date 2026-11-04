extends SceneTree

const DT := 1.0/60.0
const OUT := "res://builds/sewing-presentation"
var main
var sim
var checks := 0
var failures: Array[String] = []
var captures := {}
var session_id := ""
var object_id := ""
var maker := ""
var snapshots := {}
var saved := false
var first := "tomo"
var second := "yui"
var peak_details := {}
var peaks := {"carry_palm":0.0,"needle_pad":0.0,"scissors_pad":0.0,"support_palm":0.0}
var samples := {"carry_palm":0,"needle_pad":0,"scissors_pad":0,"support_palm":0}
var report := {"scope":"Controlled real Main twelve-person fixture; not natural emergence or human playtesting.","measurement":"Targets versus transformed measured finger landmarks. Distal cap centroids alone do not measure the full deformed skin surface; the separate rig matrix probes actual skin triangles.","phases":[],"artifacts":[],"participants":["tomo","yui"],"setup":"Authored starting positions and skills retained; routines emptied, needs .1 and new autonomous plans deferred before proposing craft."}
var saved_path := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--first="): first=argument.trim_prefix("--first=")
		if argument.begins_with("--second="): second=argument.trim_prefix("--second=")
	report.participants=[first,second]
	call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)

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


func manual() -> void:
	sim.set_process(false);main.set_process(false)
	for actor in main.avatars.values():
		actor.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.jrpg.set_process(false)

func frame(advance: bool=true) -> void:
	if advance: sim.advance_minutes(.1)
	main._process(DT)
	for actor in main.avatars.values():
		actor.animator.advance(DT);actor.jrpg._process(DT)
	main.camera.position=Vector3(-5.7,2.65,11.8);main.camera.fov=44
	main.camera.look_at(Vector3(-3.5,1.0,8.55))
	if not session_id.is_empty() and sim.sewing.sessions[session_id].phase in ["cut","sew","lift_show","show","lower"]:
		main.camera.position=Vector3(-2.8,2.65,6.1)
		main.camera.look_at(Vector3(-2.8,1.05,8.9));main.camera.fov=44
	main.get_node("Town").update_view(main.camera.position)
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	await process_frame

func observe() -> void:
	var session: Dictionary=sim.sewing.sessions[session_id]
	var phase: String=session.phase
	if phase not in report.phases:report.phases.append(phase)
	var actor=main.avatars[maker]
	var result: Dictionary=actor.contacts.interaction_result
	var actual: Dictionary=actor.contacts.observed
	if result.get("profile","")!="sewing":return
	if phase in ["carry_to_table","show","carry_to_store"] and not sim.person(maker).moving or phase in ["carry_to_table","carry_to_store"]:
		for setting in [["L","left"],["R","right"]]:
			var key: String="palm"+setting[0]
			if actual.get(key) is Vector3 and result.get("palm_"+setting[1]) is Vector3:
				samples.carry_palm+=1
				var error: float=actual[key].distance_to(result["palm_"+setting[1]])
				if error>peaks.carry_palm:
					peaks.carry_palm=error;peak_details.carry={"phase":phase,"side":setting[0],"progress":result.get("phase_progress"),"motion":sim._encode(result),"actual":sim._encode(actual)}
	var tool_phase: String=result.get("tool_phase","")
	if result.get("support_engaged",false) and tool_phase=="operate" and actual.get("palmL") is Vector3:
		samples.support_palm+=1
		var support_error: float=actual.palmL.distance_to(result.palm_left)
		if support_error>peaks.support_palm:
			peaks.support_palm=support_error;peak_details.support={"motion":sim._encode(result),"actual":sim._encode(actual),
				"upper_arm_left":sim._encode(actor.contacts.point("upper_arm.L")),"upper_arm_right":sim._encode(actor.contacts.point("upper_arm.R")),
				"visual_transform":str(actor.visual.global_transform),"action_lean":sim._encode(actor.contacts.social_motion.action_lean)}
	if phase in ["cut","sew"] and tool_phase=="operate" and float(result.get("tool_progress",0))>.15:
		var targets: Dictionary=result.get("finger_pad_target_right",{})
		var pads: Dictionary=actual.get("finger_padR",{})
		var label: String="needle_pad" if phase=="sew" else "scissors_pad"
		for finger in ["thumb","index"]:
			if targets.get(finger) is Vector3 and pads.get(finger) is Vector3:
				samples[label]+=1
				var error: float=targets[finger].distance_to(pads[finger])
				if error>peaks[label]:
					peaks[label]=error;peak_details[label]={"phase":phase,"progress":result.get("tool_progress"),"finger":finger,"motion":sim._encode(result),"actual":sim._encode(actual)}
		if not snapshots.has(phase):
			snapshots[phase]={"tool_supported":result.get("finger_pad_supported",false),"motion":sim._encode(result),"actual":sim._encode(actual)}
	if captures.has(phase):return
	var progress: float=result.get("tool_progress",0) if phase in ["cut","sew"] else result.get("phase_progress",0)
	if phase not in ["take","cut","sew","show","store"] or progress<.45 or progress>.60:return
	if phase in ["cut","sew"] and tool_phase!="operate":return
	captures[phase]=true
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var directory: String=OUT+"/gpu-%d"%OS.get_process_id()
		DirAccess.make_dir_recursive_absolute(directory)
		var path: String=directory+"/"+phase+".png"
		var result_code:=root.get_texture().get_image().save_png(path)
		report.artifacts.append({"path":path,"written":result_code==OK})
	if phase=="sew" and not saved:
		saved=true
		var before: Dictionary=sim.sewing.serialize()
		var node=main.sewing_view.object_node(object_id)
		expect(sim.save_game(saved_path) and sim.load_game(saved_path),"A real mid-sewing save restores through the town's validated current format")
		manual()
		expect(equivalent(sim.sewing.serialize(),before) and main.sewing_view.object_node(object_id)==node,"Restoring keeps the same workpiece ID, exact progress and one existing rendered object")

func run() -> void:
	root.size=Vector2i(1280,800)
	main=load("res://game/scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	sim=root.get_node("Sim");sim.reset(71103,12)
	for p in sim.people:
		sim.definitions[p.id].routines=[]
		p.next_plan_minute=999999;p.support_next_attempt=999999;p.hunger=.1;p.fatigue=.1;p.quiet=.1
		p.meeting_id="";p.routine_id="";p.activity_spot="";p.action="rest";p.remaining=999999;p.moving=false;p.path=[];p.target=p.position;p.destination=p.place
	main._start_play();sim.running=true;main._select(first,false);main.get_node("%HUD")._show_residents(false)
	main.toast_left=0;main.get_node("%Toast").hide();manual()
	main.proposals.open_for(first);main.proposals.choose_kind("project");main.proposals._select_partner(second);main.proposals.choose_activity("craft")
	await process_frame
	var confirmation: String=main.proposals.get_node("%Execute").text
	expect("布小物" in confirmation and sim.person(first).name in confirmation and sim.person(second).name in confirmation and main.proposals.get_node("%ProjectActivity").visible,"The real proposal names both people and the concrete cloth activity before execution")
	main.proposals.submit()
	expect(not sim.sewing.active_session().is_empty(),"The real UI proposal reaches the actual town's material and work-spot reservations")
	main.proposals.close_panel()
	if sim.sewing.active_session().is_empty():main.free();quit(1);return
	var session: Dictionary=sim.sewing.active_session();session_id=session.id;object_id=session.object_id;maker=session.maker
	saved_path="user://sewing-presentation-%d.json"%OS.get_process_id()
	var initial_ids: Array=sim.sewing.objects.keys()
	for tick in 3600:
		await frame()
		await observe()
		if sim.sewing.sessions[session_id].phase in ["completed","interrupted"]:break
	expect(sim.sewing.sessions[session_id].phase=="completed","Materials, cutting, stitching, actual display and storage all finish through the real simulation")
	expect(sim.sewing.objects.size()==initial_ids.size() and initial_ids.all(func(id):return sim.sewing.objects.has(id)) and main.sewing_view.object_nodes.size()==9,"Every source/tool ID retains one rendered node throughout production and restore")
	var item: Dictionary=sim.sewing.objects[object_id]
	expect(item.stage=="finished" and item.kind=="pouch" and not item.shown_to.is_empty() and item.container=="sewing_storage","The same actual material finishes as an owned, shown and stored pouch")
	expect(samples.carry_palm>0 and peaks.carry_palm<.04,"Actual modified palms follow the cloth/pouch grip surfaces during carrying and display within 4cm")
	expect(samples.needle_pad>0 and peaks.needle_pad<.006,"Post-modifier measured finger landmarks follow the needle's 4mm grip within 6mm")
	expect(samples.scissors_pad>0 and peaks.scissors_pad<.006,"Post-modifier measured finger landmarks follow the actual scissors handle contacts within 6mm")
	expect(samples.support_palm>0 and peaks.support_palm<.006,"The free hand follows the workpiece's actual mesh surface support within 6mm")
	for phase in ["to_source","take","carry_to_table","place","cut","sew","lift_show","show","lower","take_store","carry_to_store","store","completed"]:
		expect(phase in report.phases,"The continuous run observes "+phase)
	report.merge({"checks":checks,"failures":failures,"actual_contact_peaks_m":peaks,"actual_contact_samples":samples,"contact_peak_details":peak_details,"snapshots":snapshots,"finished_object":sim._encode(item),"observed_until":sim.elapsed},true)
	DirAccess.make_dir_recursive_absolute(OUT)
	var suffix: String="headless" if DisplayServer.get_name()=="headless" else "gpu-%d"%OS.get_process_id()
	if DisplayServer.get_name()=="headless" and [first,second]!=["tomo","yui"]:suffix+="-"+first+"-"+second
	FileAccess.open(OUT+"/"+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path));main.free()
	print("Sewing presentation checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

# Controlled rig/contact matrix, not natural resident choice, a complete
# workflow playtest, image review, or a human playtest. Production Main,
# ResidentAvatar, ResidentContacts, prop nodes and real Sim proposals are used.
const DT := 1.0/60.0
const OUT := "res://builds/sewing-rigs/results.json"
const LIMIT := .006
const SETTLE_FRAMES := 60
const MEASURE_FRAMES := 6
const RESIDENTS := ["nagisa","ryo","osamu","fumi","maho","ritsu","aoi","saki","haru","tomo","yui","rin"]
const PROGRESS := [.2,.5,.8]
const SkinProbe := preload("res://tests/helpers/sewing_skin_probe.gd")
var skin_probe=SkinProbe.new()
var main
var sim
var checks: int = 0
var failures: Array[String] = []
var session_id: String = ""
var maker_id: String = ""
var report: Dictionary = {"scope":"Controlled production Main/Avatar/Contacts rig and prop-contact fixture. Not natural emergence, a complete workflow, visual review or human playtesting.",
	"fixture":"Eleven currently eligible authored residents plus Rin explicitly aged to 12 to select her growth model. Authored positions and skills are retained; routines emptied, needs .1, and new plans deferred. No workpiece, progress, tool target or body pose is teleported or forged.",
	"measurement":"Post-skeleton-modifier observed measured skin points (distal or index-side), compared with contact targets and the displayed scissors loop markers or needle GripBand surface. Simulation clock is fixed while animation/contact frames settle.",
	"limit_m":LIMIT,"settle_frames":SETTLE_FRAMES,"measure_frames":MEASURE_FRAMES,"cases":[]}

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
	return ok

func manual() -> void:
	sim.set_process(false);main.set_process(false)
	for actor in main.avatars.values():
		actor.animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.jrpg.set_process(false)

func frame() -> void:
	# Production rendering/contact path, with no Sim.advance_minutes call.
	main._process(DT)
	for actor in main.avatars.values():
		actor.animator.advance(DT);actor.jrpg._process(DT)
	main.camera.position=Vector3(-2.8,2.65,6.1);main.camera.fov=44
	main.camera.look_at(Vector3(-2.8,1.05,8.9))
	await process_frame

func session() -> Dictionary:
	return sim.sewing.sessions.get(session_id,{})

func reach_work(phase: String, progress: float) -> bool:
	var required: int = ceili(float(sim.sewing.config[phase+"_minutes"])*progress)
	for ignored in 360:
		var current: Dictionary = session()
		if current.is_empty() or current.phase in ["interrupted","completed"]: return false
		var piece: Dictionary = sim.sewing.objects[current.object_id]
		if current.phase==phase and current.tool_phase=="operate" and int(piece[phase+"_minutes"])>=required: return true
		sim.advance_minutes(1)
	return false

func prop_contacts(phase: String, tool: Node3D, pads: Dictionary) -> Dictionary:
	if not is_instance_valid(tool): return {}
	if phase=="cut":
		if not tool.has_method("local_contacts"): return {}
		var local: Dictionary = tool.local_contacts()
		if not local.get("thumb_contact") is Vector3 or not local.get("finger_contact") is Vector3: return {}
		if not pads.get("thumb") is Vector3 or not pads.get("index") is Vector3: return {}
		var first: Vector3=tool.to_global(local.thumb_contact)
		var second: Vector3=tool.to_global(local.finger_contact)
		# The two real loops are symmetric. Require a one-to-one assignment of
		# the two fingers to the two surfaces, independent of the solver's labels.
		var direct: float=maxf(pads.thumb.distance_to(first),pads.index.distance_to(second))
		var swapped: float=maxf(pads.thumb.distance_to(second),pads.index.distance_to(first))
		return {"thumb":second if swapped<direct else first,"index":first if swapped<direct else second,"assignment":"swapped" if swapped<direct else "direct"}
	var band := tool.get_node_or_null("GripBand") as MeshInstance3D
	if not is_instance_valid(band) or not band.mesh is CylinderMesh: return {}
	var cylinder: CylinderMesh = band.mesh
	var targets: Dictionary = {}
	for finger in ["thumb","index"]:
		if not pads.get(finger) is Vector3: return {}
		var local: Vector3 = band.to_local(pads[finger])
		var radial: Vector2 = Vector2(local.x,local.z)
		var normal: Vector2 = radial.normalized() if radial.length()>.0000001 else Vector2.RIGHT
		var radius: float = float(cylinder.top_radius)
		var point: Vector3 = Vector3(normal.x*radius,clampf(local.y,-float(cylinder.height)*.5,float(cylinder.height)*.5),normal.y*radius)
		targets[finger]=band.to_global(point)
	return targets

func measure(phase: String, requested_progress: float) -> Dictionary:
	var current: Dictionary = session()
	var piece: Dictionary = sim.sewing.objects[current.object_id]
	var at: int = int(sim.elapsed)
	var remainder: float = float(sim.minute_remainder)
	var work_before: Array = [piece.cut_minutes,piece.sew_minutes]
	var actor = main.avatars[maker_id]
	skin_probe.prepare(actor)
	for ignored in SETTLE_FRAMES: await frame()
	var target_peaks: Dictionary = {"thumb":0.0,"index":0.0}
	var prop_peaks: Dictionary = {"thumb":0.0,"index":0.0}
	var skin_peaks: Dictionary = {"thumb":0.0,"index":0.0}
	var skin_supported: bool = true
	var skin_worst: Dictionary = {}
	var count: int = 0
	var supported: bool = true
	var worst: Dictionary = {}
	var worst_error: float = -1.0
	for ignored in MEASURE_FRAMES:
		await frame()
		var motion: Dictionary = actor.contacts.interaction_result
		var actual: Dictionary = actor.contacts.observed
		var targets: Dictionary = motion.get("finger_pad_target_right",{})
		var pads: Dictionary = actual.get("finger_padR",{})
		var tool: Node3D = main.sewing_view.object_node(motion.get("active_tool_id",""))
		var displayed: Dictionary = prop_contacts(phase,tool,pads)
		if not motion.get("finger_pad_supported",false) or targets.size()!=2 or displayed.size()<2:
			worst={"unsupported_frame":true,"motion":motion.duplicate(true),"actual":actual.duplicate(true),"displayed":displayed,
				"body_transform":str(actor.visual.global_transform),"upper_arm_right":actor.contacts.point("upper_arm.R"),"action_lean":actor.contacts.social_motion.action_lean}
		supported = supported and motion.get("profile","")=="sewing" and motion.get("phase","")==phase and motion.get("tool_phase","")=="operate" and bool(motion.get("finger_pad_supported",false)) and motion.get("pinch_source","") in ["measured_distal_mesh_caps","measured_sewing_side_mesh_surfaces"]
		for finger in ["thumb","index"]:
			if not targets.get(finger) is Vector3 or not pads.get(finger) is Vector3 or not displayed.get(finger) is Vector3:
				supported=false
				continue
			count += 1
			var target_error: float = pads[finger].distance_to(targets[finger])
			var prop_error: float = pads[finger].distance_to(displayed[finger])
			var skin: Dictionary=skin_probe.sample(actor,"DEF-finger0.R" if finger=="thumb" else "DEF-finger1.R",displayed[finger])
			if not skin.supported:
				skin_supported=false;skin_worst=skin
			else:
				skin_peaks[finger]=maxf(float(skin_peaks[finger]),float(skin.distance))
				if skin_worst.is_empty() or float(skin.distance)>float(skin_worst.get("distance",-1)):
					skin_worst=skin;skin_worst.finger=finger
			target_peaks[finger]=maxf(float(target_peaks[finger]),target_error)
			prop_peaks[finger]=maxf(float(prop_peaks[finger]),prop_error)
			if maxf(target_error,prop_error)>worst_error:
				worst_error=maxf(target_error,prop_error)
				worst={"finger":finger,"observed_pad":pads[finger],"motion_target":targets[finger],"displayed_prop_contact":displayed[finger],
					"displayed_loop_assignment":displayed.get("assignment","needle_surface"),
					"motion":motion.duplicate(true),"actual":actual.duplicate(true),"body_transform":str(actor.visual.global_transform),
					"upper_arm_right":actor.contacts.point("upper_arm.R"),"action_lean":actor.contacts.social_motion.action_lean}
	var frozen: bool = int(sim.elapsed)==at and is_equal_approx(float(sim.minute_remainder),remainder) and work_before==[piece.cut_minutes,piece.sew_minutes] and session().phase==phase and session().tool_phase=="operate"
	var complete: bool = supported and count==MEASURE_FRAMES*2
	var target_ok: bool = complete and float(target_peaks.thumb)<=LIMIT and float(target_peaks.index)<=LIMIT
	var prop_ok: bool = complete and float(prop_peaks.thumb)<=LIMIT and float(prop_peaks.index)<=LIMIT
	var label: String = maker_id+" "+phase+" "+str(requested_progress)
	expect(frozen,label+": contact settling leaves the actual simulation time and real work progress fixed")
	expect(complete,label+": measured thumb/index skin observations and tool contacts are present on every measured frame")
	expect(target_ok,label+": both actual pad errors from their intended contacts stay within 6mm")
	expect(prop_ok,label+": both actual pads stay within 6mm of the displayed scissors loops or needle GripBand")
	var skin_ok: bool=complete and skin_supported and float(skin_peaks.thumb)<=LIMIT and float(skin_peaks.index)<=LIMIT
	expect(skin_ok,label+": actual all-weight deformed finger triangles lie within 6mm of the displayed tool contacts")
	return {"phase":phase,"requested_progress":requested_progress,"actual_progress":sim.sewing.pose_for(maker_id).get("tool_progress",0),
		"minute":at,"tool_phase":session().tool_phase,"actual_pad_samples":count,"supported":complete,"clock_and_work_frozen":frozen,
		"target_peak_m":target_peaks,"displayed_prop_peak_m":prop_peaks,"skin_surface_peak_m":skin_peaks,"skin_surface_supported":skin_supported,"skin_surface_worst":skin_worst,"passed":target_ok and prop_ok and skin_ok and frozen,"worst":worst}

func rig_case(id: String) -> void:
	skin_probe.clear()
	sim.reset(71103,12)
	for p in sim.people:
		sim.definitions[p.id].routines=[]
		p.next_plan_minute=999999;p.support_next_attempt=999999;p.play_next_attempt=999999
		p.hunger=.1;p.fatigue=.1;p.quiet=.1;p.connection=.4
		p.meeting_id="";p.routine_id="";p.activity_spot="";p.action="rest";p.remaining=999999
		p.moving=false;p.path=[];p.target=p.position;p.destination=p.place
	if id=="rin":
		# Explicit age fixture, not a claim that five years were simulated.
		sim.person(id).age=12
		main.avatars[id].configure(sim.person(id))
	maker_id=id;session_id=""
	main._select(id,false);sim.running=true;manual()
	await process_frame
	var partner: String = "osamu" if id=="tomo" else "tomo"
	var first_skill: float = float(sim.person(id).skills.get("craft",0))
	var second_skill: float = float(sim.person(partner).skills.get("craft",0))
	var project: Dictionary = sim.resident_activities.definition(sim.person(id),sim.person(partner),"craft")
	var response: Dictionary = sim.propose_project(id,partner,"craft")
	var record: Dictionary = {"resident":id,"age":sim.person(id).age,"rin_age_12_fixture":id=="rin","first":id,"second":partner,
		"first_craft_skill":first_skill,"second_craft_skill":second_skill,"project_teacher":project.get("teacher",""),"project_learner":project.get("learner",""),
		"proposal_status":response.get("status",""),"proposal_text":response.get("text",""),"samples":[]}
	report.cases.append(record)
	if not expect(response.get("status","")=="accept",id+": the actual Sim craft proposal is accepted without changing authored skills"): return
	var current: Dictionary = sim.sewing.active_session()
	if not expect(not current.is_empty(),id+": the proposal allocates a real sewing session"): return
	session_id=current.id
	record.actual_maker=current.maker;record.maker_spot=current.targets[current.maker].spot
	record.maker_position=current.targets[current.maker].position;record.object_id=current.object_id
	if not expect(current.maker==id,id+": pair order and the actual project learner select the requested maker rig"): return
	record.model=main.avatars[id].displayed_model;record.model_scene=main.avatars[id].jrpg.scene_file_path
	expect(record.model==("rin_adult" if id=="rin" else id),id+": the production avatar uses the expected authored or age-12 growth model")
	var all_pass: bool = true
	for phase in ["cut","sew"]:
		for progress in PROGRESS:
			if not expect(reach_work(phase,float(progress)),id+": actual route, handling and processing reach "+phase+" operate near "+str(progress)):
				all_pass=false
				break
			var result: Dictionary = await measure(phase,float(progress))
			record.samples.append(result)
			all_pass=all_pass and bool(result.passed)
		if session().phase in ["interrupted","completed"]: break
	record.skills_after={"first":sim.person(id).skills.get("craft",0),"second":sim.person(partner).skills.get("craft",0)}
	expect(is_equal_approx(float(record.skills_after.first),first_skill) and is_equal_approx(float(record.skills_after.second),second_skill),id+": authored craft skills remain unchanged throughout this pre-completion contact fixture")
	record.passed=all_pass and record.samples.size()==6
	expect(record.passed,id+": the complete cut/sew pad-contact matrix passes at all three fixed-clock sample points")
	# No full display/storage claim: stop this owned fixture before resetting.
	for meeting in sim.meetings.duplicate():
		if meeting.id==current.meeting:
			sim._finish_meeting(meeting,false);sim.meetings.erase(meeting)
	await process_frame

func run() -> void:
	root.size=Vector2i(1280,800)
	main=load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	sim=root.get_node("Sim");main._start_play();manual()
	main.get_node("%HUD")._show_residents(false)
	main.toast_left=0;main.get_node("%Toast").hide()
	for id in RESIDENTS: await rig_case(id)
	var passed_rigs: int = 0
	for record in report.cases:
		if record.get("passed",false): passed_rigs+=1
	expect(report.cases.size()==12 and passed_rigs==12,"All eleven eligible current residents and the explicit age-12 Rin growth rig pass the measured contact matrix")
	report.merge({"checks":checks,"failures":failures,"rig_count":report.cases.size(),"passed_rigs":passed_rigs,"display_backend":DisplayServer.get_name()},true)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var output := FileAccess.open(OUT,FileAccess.WRITE)
	if output!=null: output.store_string(JSON.stringify(sim._encode(report),"\t"));output.close()
	else: expect(false,"The contact matrix writes its results report")
	skin_probe.clear();main.free()
	print("Sewing rig/contact checks: %d passed, %d failed; %d/12 rigs passed"%[checks-failures.size(),failures.size(),passed_rigs])
	quit(0 if failures.is_empty() else 1)

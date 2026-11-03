extends SceneTree

# This observes the ordinary town. Only time, seed and observation controls are used.
const SEEDS = [710,711,712,713,714,715,716,717,718,719]
const MINUTES_PER_SEED = 12*1440
const OUTPUT = "res://docs/verification/v0.6/social-chain"

var checks := 0
var failures: Array[String] = []
var main
var sim

func source_fingerprint() -> Dictionary:
	var result := {}
	for folder in ["game/scripts","data"]:
		var names := DirAccess.get_files_at("res://"+folder)
		names.sort()
		for name in names:
			if name.ends_with(".gd") or name.ends_with(".json"):
				var path: String = folder+"/"+name
				result[path] = FileAccess.get_sha256("res://"+path)
	for path in ["project.godot","game/scenes/main.tscn","tests/test_social_chain_presentation.gd"]:
		result[path] = FileAccess.get_sha256("res://"+path)
	return result

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func memories_about(p: Dictionary, other_id: String) -> Array:
	var result: Array = []
	for memory in p.get("memories",[]):
		if memory.get("other","")==other_id: result.append(memory.duplicate(true))
	return result.slice(maxi(0,result.size()-8))

func time_at(minute: int) -> Dictionary:
	var absolute: int = sim.start_minute+minute
	return {"minute":minute,"day":int(absolute/1440.0),"clock":"%02d:%02d"%[int((absolute%1440)/60.0),absolute%60]}

func resident_snapshot(p: Dictionary, skill: String) -> Dictionary:
	var other: String = p.cognition_plan.get("partner","")
	return {"id":p.id,"name":p.name,"skill":skill,"level":float(p.skills.get(skill,0)),
		"plan":p.cognition_plan.duplicate(true),"action":p.action,"reason":p.reason,
		"place":p.place,"moving":p.moving,"position":[p.position.x,p.position.y,p.position.z],
		"relationship_to_partner":p.relationships.get(other,{}).duplicate(true),
		"initial_profile_of_partner":p.known_profiles.get(other,{}).duplicate(true),
		"memories_about_partner":memories_about(p,other)}

func meeting_snapshot(meeting: Dictionary) -> Dictionary:
	var skill: String = meeting.project.skill
	return {"minute":sim.elapsed,"clock":sim.clock_text(),"day":sim.day_index(),"calendar":sim.calendar_text(),
		"state":meeting.state,"actors":[resident_snapshot(sim.person(meeting.a),skill),resident_snapshot(sim.person(meeting.b),skill)]}

func held(p: Dictionary, event_id: String) -> Dictionary:
	for known in p.knowledge:
		if known.get("event_id","")==event_id: return known
	return {}

func observe_introductions(cache: Dictionary) -> void:
	for event in sim.events:
		if event.get("fact","")!="introduction" or cache.has(event.event_id): continue
		var value: Dictionary = event.value
		var via: String = value.via
		var recipient := ""
		for id in event.get("participants",[]):
			if id!=via: recipient = id
		if recipient.is_empty(): continue
		var listener: Dictionary = sim.person(recipient)
		var known: Dictionary = held(listener,event.event_id)
		if known.is_empty(): continue
		cache[event.event_id] = {"event":event.duplicate(true),"recipient":recipient,
			"speaker":via,"subject":value.person,"skill":value.skill,
			"received_at":int(known.observed_at),"clock":sim.clock_text(),"day":sim.day_index(),
			"original_profile_minute":int(value.profile_minute),"profile":held(listener,value.profile_event).duplicate(true),
			"original_profile_time":time_at(int(value.profile_minute)),
			"knowledge":known.duplicate(true),"listener":resident_snapshot(listener,value.skill),
			"relation_to_subject":listener.relationships.get(value.person,{}).duplicate(true),
			"initial_profile_of_subject":listener.known_profiles.get(value.person,{}).duplicate(true),
			"memories_about_subject":memories_about(listener,value.person)}

func active_meeting(id: String) -> Dictionary:
	for meeting in sim.meetings:
		if meeting.id==id: return meeting
	return {}

func capture() -> Image:
	var elapsed_before: int = sim.elapsed
	# Synchronize rendered residents after skipped simulation minutes, then
	# let the ordinary follow camera read their updated focus positions.
	# These calls only refresh the view while simulation time is paused.
	main._process(1.0)
	main._process(1.0)
	main._refresh_ui()
	for frame in range(8): await process_frame
	expect(sim.elapsed==elapsed_before,"Observation controls do not advance or replace the simulated encounter")
	if DisplayServer.get_name()=="headless": return null
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func ui_snapshot() -> Dictionary:
	return {"activity":main.get_node("%Activity").text,"reason":main.get_node("%Reason").text,
		"next":main.get_node("%NextPlan").text,"detail":main.get_node("%DetailText").text,
		"proposal_partner":main.partner.get_selected_metadata()}

func select_actor(id: String) -> void:
	main._select(id)
	main.get_node("%NowTab").pressed.emit()
	main.get_node("%HistoryToggle").button_pressed = false
	if not main.following: main.get_node("%FollowButton").pressed.emit()
	main.toast_left = 0
	main.get_node("%Toast").visible = false

func both_visible(meeting: Dictionary) -> bool:
	var right: Control = main.get_node("%HUD").detail_panel
	for id in [meeting.a,meeting.b]:
		var focus: Vector3 = main.avatars[id].focus_position()
		if main.camera.is_position_behind(focus): return false
		var pixel: Vector2 = main.camera.unproject_position(focus)
		if pixel.x<18 or pixel.x>right.position.x-18 or pixel.y<80 or pixel.y>root.size.y-85: return false
	return true

func run() -> void:
	var wall_started: int = Time.get_ticks_msec()
	var source_before := source_fingerprint()
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if DisplayServer.get_name()!="headless":
		for name in ["01-referred-plan.png","02-actual-collaboration.png","03-completed-result.png"]:
			var path: String = OUTPUT+"/"+name
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = root.get_node("Sim")
	var report := {"seeds":SEEDS,"minutes_per_seed":MINUTES_PER_SEED,"ordinary_residents":8,
		"source_sha256":source_before,
		"player_interventions":[],"observation_controls":["select the referred initiator","follow","open the current person tab"],
		"renderer":DisplayServer.get_name(),"rendered":DisplayServer.get_name()!="headless",
		"scope":"Natural runs only. Introduction receipt and the later plan share an actual event ID. No counterfactual claim that the introduction alone caused the choice.",
		"searches":[],"interrupted_chains":[],"found":false,"screenshots":[]}
	var seen_meetings := {}
	for seed_value in SEEDS:
		sim.reset(seed_value)
		main._start_play()
		sim.running = false
		var cache := {}
		var tracked := {}
		var before := {}
		var engaged := {}
		var collaboration_observed := {}
		var first_image: Image
		var engaged_image: Image
		var first_ui := {}
		var engaged_ui := {}
		var introduction := {}
		var attempted := 0
		var inspected := 0
		for minute in MINUTES_PER_SEED:
			sim.advance_minutes(1)
			inspected = minute+1
			observe_introductions(cache)
			if tracked.is_empty():
				for meeting in sim.meetings:
					var key := "%s:%s"%[seed_value,meeting.id]
					if seen_meetings.has(key) or meeting.get("mode","")!="project" or not meeting.get("autonomous",false): continue
					var actor: Dictionary = sim.person(meeting.a)
					var plan: Dictionary = actor.cognition_plan
					var event_id: String = plan.get("introduction_event","")
					if event_id.is_empty() or not cache.has(event_id): continue
					seen_meetings[key] = true
					var known: Dictionary = cache[event_id]
					if known.recipient!=actor.id or known.subject!=meeting.b or known.skill!=meeting.project.skill: continue
					if meeting.state not in ["travel","waiting","engaged"]: continue
					if int(known.received_at)>int(plan.started): continue
					tracked = meeting.duplicate(true)
					introduction = known.duplicate(true)
					before = meeting_snapshot(meeting)
					engaged = before.duplicate(true) if meeting.state=="engaged" else {}
					collaboration_observed = {}
					engaged_ui = {}
					attempted += 1
					select_actor(actor.id)
					first_image = await capture()
					first_ui = ui_snapshot()
					break
			else:
				var current: Dictionary = active_meeting(tracked.id)
				if not current.is_empty() and current.state=="engaged" and engaged_ui.is_empty():
					collaboration_observed = meeting_snapshot(current)
					if engaged.is_empty(): engaged = collaboration_observed.duplicate(true)
					engaged_image = await capture()
					engaged_ui = ui_snapshot()
					expect(both_visible(tracked),"The two participants are visible beside the person panel in the actual collaboration image")
				elif current.is_empty():
					var actor: Dictionary = sim.person(tracked.a)
					var ended: Dictionary = meeting_snapshot(tracked)
					ended.state = actor.cognition_plan.get("stage","unknown")
					if actor.cognition_plan.get("meeting","")!=tracked.id or ended.state!="completed" or engaged.is_empty():
						report.interrupted_chains.append({"seed":seed_value,"meeting":tracked.id,"introduction":introduction,
							"before":before,"engaged":engaged,"ended":ended})
						tracked = {}
						if main.following: main.get_node("%FollowButton").pressed.emit()
						continue
					# Let the ordinary action selector resume after the finish hook;
					# the actual completion time remains in the preceding snapshot.
					sim.advance_minutes(1)
					var result_observed := meeting_snapshot(tracked)
					result_observed.state = actor.cognition_plan.get("stage","unknown")
					var result_image: Image = await capture()
					var result_ui := ui_snapshot()
					report.found = true
					report.seed = seed_value
					report.meeting = tracked.id
					report.activity = tracked.project.key
					report.skill = tracked.project.skill
					report.introduction = introduction
					report.before = before
					report.engaged = engaged
					report.collaboration_observed = collaboration_observed
					report.first_meeting_already_engaged = before.state=="engaged"
					report.completed = ended
					report.result_observed = result_observed
					report.ui = {"planned":first_ui,"engaged":engaged_ui,"completed":result_ui}
					expect(int(introduction.received_at)<=int(before.actors[0].plan.started) and int(before.actors[0].plan.started)<=int(before.minute) and int(before.minute)<=int(engaged.minute) and int(engaged.minute)<int(ended.minute),"The introduction, actual plan, collaboration and completion occur in order, including encounters created after arrival")
					expect(actor.cognition_plan.get("introduction_event","")==introduction.event.event_id,"The completed plan still refers to the actual introduction received by its initiator")
					expect(introduction.profile.get("event_id","")==introduction.event.value.profile_event and int(introduction.original_profile_minute)<=introduction.received_at,"The introduction retains the profile reference and its original observation time")
					expect(sim.person(introduction.speaker).name in first_ui.reason and sim.person(tracked.b).name in first_ui.detail,"The normal HUD distinguishes who introduced the information from the activity partner")
					expect("一緒に進めたこと" in result_ui.detail and actor.cognition_plan.reason in result_ui.detail,"The normal HUD retains the completed result and its introduction trigger")
					expect(first_ui.proposal_partner==tracked.b and result_ui.proposal_partner==tracked.b,"Selecting the initiator starts the proposal control with the real activity partner and refreshes preserve it")
					expect(both_visible(tracked),"The two actual participants remain inside the free observation area")
					var learned := false
					for i in 2: learned = learned or float(ended.actors[i].level)>float(before.actors[i].level)
					expect(learned,"Actual completed work changes at least one participant's practiced skill")
					var names := ["01-referred-plan.png","02-actual-collaboration.png","03-completed-result.png"]
					var images := [first_image,engaged_image,result_image]
					var moments := [before,collaboration_observed,result_observed]
					for i in 3:
						if images[i]!=null: images[i].save_png(OUTPUT+"/"+names[i])
						report.screenshots.append({"file":names[i],"minute":moments[i].minute,"state":moments[i].state,"rendered":images[i]!=null})
					break
			if minute%30==0: await process_frame
		if not tracked.is_empty() and not report.found:
			report.interrupted_chains.append({"seed":seed_value,"meeting":tracked.id,"introduction":introduction,
				"before":before,"engaged":engaged,"ended":{"minute":sim.elapsed,"state":"search horizon"}})
		report.searches.append({"seed":seed_value,"minutes":inspected,"introductions":cache.size(),"matching_projects_observed":attempted})
		print("Social chain search: seed=%d minutes=%d introductions=%d projects=%d found=%s"%[seed_value,inspected,cache.size(),attempted,report.found])
		if report.found: break
	expect(report.found,"At least one introduction-linked natural project completes inside the declared finite search")
	expect(source_before==source_fingerprint(),"The game sources and test remain unchanged during this continuous observation")
	report.outcome = "completed natural chain" if report.found else "not found within the declared seeds and time limits"
	report.wall_seconds = (Time.get_ticks_msec()-wall_started)/1000.0
	report.checks = checks
	report.failures = failures
	var filename := "continuous-chain-headless.json" if DisplayServer.get_name()=="headless" else "continuous-chain.json"
	var file := FileAccess.open(OUTPUT+"/"+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("Social chain presentation checks: %d passed, %d failed; %s"%[checks-failures.size(),failures.size(),report.outcome])
	print("Social chain presentation seconds: %.3f"%report.wall_seconds)
	main.free()
	quit(0 if failures.is_empty() else 1)

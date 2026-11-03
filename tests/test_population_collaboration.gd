extends SceneTree

const OUT := "res://docs/verification/v0.8/population"
const NEW_IDS := ["saki","haru","tomo","yui"]
const SEEDS := [710,711,712]
const MINUTES_PER_SEED := 3*1440
var sim: LifeSimulation
var main
var checks := 0
var failures: Array[String] = []
var record := {"scope":"Normal twelve-resident starts, no proposals or changes to people, schedules, needs, skills or relationships; finite search for a new/original pair's actual autonomous project, not a human playtest or a frequency estimate","seeds":SEEDS,"minutes_per_seed":MINUTES_PER_SEED,"searches":[],"player_interventions":[],"observation_controls":["select a new resident","follow","view current activity"],"screenshots":[],"interrupted_observations":[]}

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func people_before() -> Dictionary:
	var people := {}
	for p in sim.people:
		people[p.id] = {"id":p.id,"name":p.name,"skills":p.skills.duplicate(true),"expectations":p.expectations.size(),
			"knowledge":p.knowledge.size(),"position":p.position,"place":p.place,"action":p.action,"moving":p.moving,
			"cognition_plan":p.cognition_plan.duplicate(true)}
	return {"minute":sim.elapsed,"clock":sim.clock_text(),"day":sim.day_index(),"people":people}

func snapshot(meeting: Dictionary, previous: Dictionary = {}) -> Dictionary:
	var actors := []
	var skill: String = meeting.project.skill
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = previous.get("people",{}).get(id,sim.person(id))
		actors.append({"id":id,"name":p.name,"skill":skill,"level":p.skills.get(skill,0),
			"action":p.action,"moving":p.moving,"place":p.place,
			"position":[p.position.x,p.position.y,p.position.z],"knowledge":p.knowledge if p.knowledge is int else p.knowledge.size(),
			"expectations":p.expectations if p.expectations is int else p.expectations.size(),"plan":p.cognition_plan.duplicate(true)})
	return {"minute":previous.get("minute",sim.elapsed),"clock":previous.get("clock",sim.clock_text()),
		"day":previous.get("day",sim.day_index()),"state":"before_shared_time" if not previous.is_empty() else meeting.state,"actors":actors}

func current_meeting(id: String) -> Dictionary:
	for meeting in sim.meetings:
		if meeting.id==id: return meeting
	return {}

func mixed_pair(meeting: Dictionary) -> bool:
	return (meeting.a in NEW_IDS)!=(meeting.b in NEW_IDS)

func capture(stage: String, meeting: Dictionary) -> void:
	var name := "natural-seed%d-%s-%s"%[int(record.seed),meeting.id,stage]
	var selected: String = meeting.a if meeting.a in NEW_IDS else meeting.b
	if main.selected_id!=selected: main._select(selected)
	main.following = true
	main.distance = 10
	main.yaw = .42
	main.get_node("%NowTab").pressed.emit()
	for p in sim.people: main.avatars[p.id].update_state(p,1,p.id==selected)
	main._process(1)
	main._refresh_ui()
	for frame in 8: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"/"+name+".png")
	record.screenshots.append({"file":name+".png","seed":record.seed,"stage":stage,"minute":sim.elapsed,"clock":sim.clock_text(),"meeting":meeting.id})

func run() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	sim = root.get_node("Sim")
	var observed := {}
	var before := {}
	var engaged := {}
	var completed := {}
	for seed_value in SEEDS:
		sim.reset(seed_value,12)
		main._start_play()
		sim.running = false
		var pending := {}
		var candidates := 0
		var minute := 0
		while minute<MINUTES_PER_SEED:
			var previous := people_before()
			sim.advance_minutes(1)
			minute += 1
			for meeting in sim.meetings:
				if meeting.get("mode","")!="project" or not meeting.get("autonomous",false) or not mixed_pair(meeting): continue
				if not pending.has(meeting.id):
					pending[meeting.id] = snapshot(meeting,previous) if meeting.state=="engaged" else snapshot(meeting)
					candidates += 1
			if observed.is_empty():
				for meeting in sim.meetings:
					if not pending.has(meeting.id) or meeting.state!="engaged": continue
					observed = meeting.duplicate(true)
					before = pending[meeting.id]
					engaged = snapshot(meeting)
					record.seed = seed_value
					await capture("engaged",meeting)
					break
			elif current_meeting(observed.id).is_empty():
				var p: Dictionary = sim.person(observed.a)
				if p.cognition_plan.get("meeting","")==observed.id and p.cognition_plan.get("stage","")=="completed":
					completed = snapshot(observed)
					completed.state = "completed"
					await capture("completed",observed)
					break
				record.interrupted_observations.append({"seed":seed_value,"meeting":observed.id,"minute":sim.elapsed})
				observed = {}
			if minute%30==0: await process_frame
		record.searches.append({"seed":seed_value,"minutes":minute,"mixed_pair_project_proposals":candidates,"completed":not completed.is_empty()})
		print("Population collaboration search seed=%d minutes=%d completed=%s"%[seed_value,minute,not completed.is_empty()])
		if not completed.is_empty(): break
		observed = {}
	expect(sim.people.size()==12 and main.avatars.size()==12,"The observed normal town contains twelve actual residents and actors")
	expect(not completed.is_empty(),"A new/original resident pair completes an autonomous project within the declared finite search")
	if not completed.is_empty():
		expect(mixed_pair(observed) and observed.get("autonomous",false),"The completed encounter is a resident-initiated new/original combination")
		expect(before.minute<=engaged.minute and engaged.minute<completed.minute,"Proposal, actual participation and outcome remain in one continuous run")
		var learned := false
		for index in 2:
			learned = learned or float(completed.actors[index].level)>float(engaged.actors[index].level)
		expect(learned,"The completed real work changes at least one participant's actual practiced skill")
		var new_id: String = observed.a if observed.a in NEW_IDS else observed.b
		expect(main.selected_id==new_id and main.avatars[new_id].jrpg!=null,"The observed participant is the actual new resident with a JRPG model")
		record.meeting = observed.id
		record.activity = observed.project.key
		record.title = observed.project.title
		record.before = before
		record.engaged = engaged
		record.completed = completed
		record.final_screenshots = record.screenshots.filter(func(s): return s.seed==record.seed and s.meeting==observed.id)
		var filenames := {}
		for image in record.screenshots: filenames[image.file] = true
		expect(record.final_screenshots.size()==2 and filenames.size()==record.screenshots.size(),"Different searches keep distinct image files, and the final result references only its own engaged/completed pair")
	record.renderer = DisplayServer.get_name()
	record.rendered = DisplayServer.get_name()!="headless"
	record.checks = checks
	record.failures = failures
	record.source_sha256 = {}
	for path in ["data/residents.json","data/life-conditions.json","data/life-course.json","data/resident-activities.json","data/resident-appearance.json",
		"game/scripts/simulation.gd","game/scripts/main.gd","game/scripts/resident_avatar.gd","game/scripts/resident_agenda.gd","game/scripts/resident_planner.gd",
		"game/scripts/work_family.gd","game/scripts/life_course.gd","game/scripts/social_life.gd","game/scripts/resident_cognition.gd","game/scripts/resident_knowledge_exchange.gd"]:
		record.source_sha256[path] = FileAccess.get_sha256("res://"+path)
	var filename := "natural-collaboration-headless.json" if DisplayServer.get_name()=="headless" else "natural-collaboration.json"
	var file := FileAccess.open(OUT+"/"+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  "))
	file.close()
	print("Population collaboration checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	main.free()
	quit(0 if failures.is_empty() else 1)

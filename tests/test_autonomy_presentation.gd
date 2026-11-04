extends SceneTree

const SEED = 71103
const SEARCH_MINUTES = 2880
const OUTPUT = "res://docs/verification/v0.6/presentation"

var checks := 0
var failures: Array[String] = []
var main
var sim

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func capture(name: String) -> void:
	main._process(1.0)
	main._refresh_ui()
	for frame in range(8): await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")

func before_step() -> Dictionary:
	var people := {}
	for p in sim.people:
		people[p.id] = {"id":p.id,"name":p.name,"skills":p.skills.duplicate(),"knowledge":p.knowledge.duplicate(),
			"expectations":p.expectations.duplicate(),"position":p.position,"cognition_plan":p.cognition_plan.duplicate(true),"action":p.action,"moving":p.moving}
	return {"minute":sim.elapsed,"clock":sim.clock_text(),"people":people}

func snapshot(meeting: Dictionary, prior: Dictionary = {}) -> Dictionary:
	var actors := []
	var skill: String = meeting.project.skill
	for id in [meeting.a,meeting.b]:
		var person: Dictionary = prior.get("people",{}).get(id,sim.person(id))
		actors.append({"id":id,"name":person.name,"skill":skill,
			"action":person.action,"moving":person.moving,
			"level":float(person.skills.get(skill,0)),"knowledge":person.knowledge.size(),
			"expectations":person.expectations.size(),"position":[person.position.x,person.position.y,person.position.z],
			"plan":person.cognition_plan.duplicate(true)})
	return {"minute":prior.get("minute",sim.elapsed),"clock":prior.get("clock",sim.clock_text()),
		"state":"before_shared_time" if not prior.is_empty() else meeting.state,"actors":actors}

func active_meeting(id: String) -> Dictionary:
	for meeting in sim.meetings:
		if meeting.id==id: return meeting
	return {}

func both_visible(meeting: Dictionary) -> bool:
	var right_panel: Control = main.get_node("%HUD").detail_panel
	var available_right: float = right_panel.position.x if right_panel.visible else root.size.x
	for id in [meeting.a,meeting.b]:
		var point: Vector3 = main.avatars[id].focus_position()
		if main.camera.is_position_behind(point): return false
		var pixel: Vector2 = main.camera.unproject_position(point)
		if pixel.x<24 or pixel.x>available_right-24 or pixel.y<125 or pixel.y>root.size.y-85: return false
	return true

func run() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	sim = root.get_node("Sim")
	sim.reset(SEED)
	main._start_play()
	sim.running = false
	var pending := {}
	var observed := {}
	var before := {}
	var engaged := {}
	var completed := {}
	var capture_started := false
	for minute in SEARCH_MINUTES:
		var previous := before_step()
		sim.advance_minutes(1)
		for meeting in sim.meetings:
			if meeting.get("mode","")!="project" or not meeting.get("autonomous",false): continue
			if not pending.has(meeting.id):
				pending[meeting.id] = {"meeting":meeting.duplicate(true),"before":snapshot(meeting,previous) if meeting.state=="engaged" else snapshot(meeting)}
		if observed.is_empty():
			for meeting in sim.meetings:
				if not pending.has(meeting.id) or meeting.state!="engaged": continue
				observed = meeting.duplicate(true)
				before = pending[meeting.id].before
				engaged = snapshot(meeting)
				main._select(meeting.a)
				main.get_node("%FollowButton").pressed.emit()
				main.get_node("%NowTab").pressed.emit()
				await capture("01-resident-initiated-work")
				capture_started = true
				break
		elif active_meeting(observed.id).is_empty():
			var actor: Dictionary = sim.person(observed.a)
			if actor.cognition_plan.get("meeting","")==observed.id and actor.cognition_plan.get("stage","")=="completed":
				completed = snapshot(observed)
				completed.state = "completed"
				break
			# An interrupted encounter remains an actual event in this same play.
			# Continue observing without rewinding or forcing another outcome.
			observed = {}
			before = {}
			engaged = {}
			if main.following: main.get_node("%FollowButton").pressed.emit()
		if minute%15==0: await process_frame
	expect(not observed.is_empty() and not completed.is_empty(),"A resident-initiated project completes naturally within two representative days")
	var record := {"seed":SEED,"search_limit_minutes":SEARCH_MINUTES,"player_interventions":[],
		"observation_controls":["select the initiator","follow","open person / relations / history"],
		"renderer":DisplayServer.get_name(),"rendered":DisplayServer.get_name()!="headless",
		"completed_project_found":not completed.is_empty(),"elapsed":sim.elapsed,"screenshots":[]}
	if not completed.is_empty():
		record.meeting = observed.id
		record.activity = observed.project.key
		record.title = observed.project.title
		record.before = before
		record.engaged = engaged
		record.completed = completed
		record.started = engaged.actors[0].plan.started
		record.finished = completed.minute
		record.screenshots = [{"file":"01-resident-initiated-work.png","minute":engaged.minute,"stage":"engaged"}]
		expect(capture_started and before.minute<=engaged.minute and engaged.minute<completed.minute,"The images follow one continuous play and one actual meeting")
		expect(before.state in ["travel","waiting","before_shared_time"] and before.minute<engaged.minute and engaged.state=="engaged","The encounter is observed before the agreed shared time and after actual participation begins")
		var learned := false
		for index in 2:
			learned = learned or float(completed.actors[index].level)>float(engaged.actors[index].level)
		expect(learned,"At least one participant's practiced skill changes after completed work")
		sim.advance_minutes(1)
		main.get_node("%NowTab").pressed.emit()
		await capture("02-after-learning")
		record.screenshots.append({"file":"02-after-learning.png","minute":sim.elapsed,"stage":"after completion"})
		expect(both_visible(observed),"Both participants project inside the free observation area at the follow distance")
		expect("一緒に進めたこと" in main.get_node("%DetailText").text,"The normal person panel reports the completed plan")
		main.get_node("%RelationsTab").pressed.emit()
		main.get_node("%HistoryToggle").button_pressed = true
		await capture("03-relations-and-history")
		record.screenshots.append({"file":"03-relations-and-history.png","minute":sim.elapsed,"stage":"relations / history"})
		expect(sim.person(observed.b).name in main.get_node("%DetailText").text,"The other participant remains visible in the normal relationship panel")
	record.elapsed = sim.elapsed
	var record_name := "continuous-play-headless.json" if DisplayServer.get_name()=="headless" else "continuous-play.json"
	var file := FileAccess.open(OUTPUT+"/"+record_name,FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"\t"))
	file.close()
	print("Autonomy presentation checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	main.free()
	quit(0 if failures.is_empty() else 1)

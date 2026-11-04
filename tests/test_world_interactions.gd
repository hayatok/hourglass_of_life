extends SceneTree

var sim
var checks := 0
var failures: Array[String] = []
var save_path := "user://world-interactions-%d.json"%OS.get_process_id()
var bad_path := "user://world-interactions-bad-%d.json"%OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text);push_error(text)

func setup(population: int = 12) -> void:
	if is_instance_valid(sim): sim.free()
	sim = load("res://game/scripts/simulation.gd").new()
	root.add_child(sim)
	sim.reset(711,population)
	# Controlled engineering fixture, not a natural decision/playtest claim.
	for p in sim.people:
		sim.definitions[p.id].routines = []
		p.next_plan_minute = 999999;p.support_next_attempt = 999999
		p.fatigue = .1;p.hunger = .1;p.quiet = .1;p.connection = .4
		p.activity_spot = "";p.meeting_id = "";p.routine_id = ""
		p.action = "rest";p.remaining = 99999
		p.position = sim.SITES[sim.home_for(p)];p.place = sim.home_for(p)
		p.target = p.position;p.destination = p.place;p.path = [];p.moving = false
	for id in ["aoi","osamu"]:
		var p: Dictionary = sim.person(id)
		p.position = Vector3(0,0,-4.8) if id=="aoi" else Vector3(.9,0,-6.5)
		p.place = "workshop";p.destination = "workshop";p.target = p.position
	var reply: Dictionary = sim.work_family.propose_project("aoi","osamu","radio",true)
	expect(reply.status=="accept","The existing project consent API starts a real radio workflow")

func current() -> Dictionary:
	for session in sim.interactions.sessions.values(): return session
	return {}

func advance_to(phase: String, limit: int = 220) -> bool:
	for minute in limit:
		if current().get("phase","")==phase: return true
		if current().get("phase","")=="interrupted": return false
		sim.advance_minutes(1)
	return current().get("phase","")==phase

func state() -> Dictionary:
	return {"people":sim.people.duplicate(true),"meetings":sim.meetings.duplicate(true),
		"interactions":sim.interactions.serialize(),"households":sim.work_family.households.duplicate(true),
		"projects":sim.work_family.projects.duplicate(true),"events":sim.events.duplicate(true),
		"rng":str(sim.rng.state),"elapsed":sim.elapsed,"agenda":sim.agenda.serialize().duplicate(true)}

func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3: return a.distance_to(b)<.00001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not same(a[index],b[index]): return false
		return true
	return a==b

func add_work_now() -> void:
	sim.definitions.aoi.routines.append({"id":"work_shift","action":"work","place":"home","on_days":[sim.weekday()],"start_minute":sim.minute_of_day(),"duration_minutes":90})

func malformed(raw: Dictionary, label: String) -> void:
	var before := state()
	FileAccess.open(bad_path,FileAccess.WRITE).store_string(JSON.stringify(raw))
	expect(not sim.load_game(bad_path) and same(before,state()),label+" is rejected without changing the running world")

func run() -> void:
	setup()
	if current().is_empty(): sim.free();quit(1);return
	var session := current()
	var object: Dictionary = sim.interactions.objects.workshop_radio
	var a: Dictionary = sim.person("aoi")
	var m: Dictionary = sim.meetings[0]
	var starting_cash: float = sim.work_family.household(a).cash
	var skill: float = a.skills.repair
	expect(sim.activities.walkable("workshop",sim.interactions.config.source_approach),"Shelf approach is actually walkable against the scene's expanded furniture footprints")
	expect(object.owner=="town" and object.holder=="" and object.reserved_by==session.id,"Ownership, current holder and exclusive reservation are distinct")
	expect(advance_to("carry_to_target"),"The carrier reaches the real shelf and finishes taking the existing radio")
	expect(object.holder=="aoi" and object.container=="" and sim.interactions.objects.size()==1,"Taking relocates the same single object rather than creating a carried copy")
	var reply: Dictionary = sim.work_family.propose_project("haru","saki","radio",true)
	expect(reply.status!="accept" and sim.interactions.sessions.size()==1,"A reserved radio cannot be allocated to a second project")
	expect(advance_to("working"),"Actual route and placing finish before joint work begins")
	expect(m.remaining==45 and not m.materials_ready and is_equal_approx(sim.work_family.household(a).cash,starting_cash),"Preparation consumes no work minutes and charges no materials")
	expect(is_equal_approx(a.skills.repair,skill) and a.expectations.is_empty(),"Travelling and taking are not completed learning or skill practice")
	expect(object.container=="radio_table" and object.holder.is_empty() and object.position==sim.interactions.config.target_position,"Joint work uses the existing radio on its real target table")
	sim.advance_minutes(1)
	expect(m.remaining==44 and m.materials_ready and is_equal_approx(sim.work_family.household(a).cash,starting_cash-4),"Only actual working time charges materials once and advances the original work clock")
	expect(sim.interactions.pose_for("osamu").role=="operator" and sim.interactions.pose_for("aoi").role=="support","Known skill roles distinguish operating from supporting during work")
	expect(advance_to("take_return"),"Completing the real work enters cleanup rather than deleting the object")
	var progress: float = sim.work_family.projects.radio
	var earned_skill: float = a.skills.repair
	expect(m.remaining==0 and m.work_completed and m.project_result_recorded and progress>0 and earned_skill>skill,"Actual completed work records its result and skill before the return journey")
	var connection: float = a.connection
	sim.advance_minutes(2)
	expect(m.remaining==0 and is_equal_approx(a.connection,connection+2*.0006),"Cleanup does not consume additional work minutes or grant additional joint-work fulfilment")
	expect(advance_to("completed"),"The same radio is carried back and released at its source")
	expect(object.owner=="town" and object.holder.is_empty() and object.reserved_by.is_empty() and object.container=="radio_shelf" and object.position==sim.interactions.config.source_position,"Completion restores physical storage without transferring ownership")
	expect(sim.meetings.is_empty() and a.meeting_id.is_empty() and a.activity_spot.is_empty(),"Completion releases the meeting and real activity reservation")
	sim.work_family.finish_project(m);sim.interactions.worked(m)
	expect(is_equal_approx(sim.work_family.projects.radio,progress) and is_equal_approx(a.skills.repair,earned_skill),"Repeated completion cannot duplicate progress or skill effects")
	# External obligations interrupt immediately; no fake work effects are granted.
	setup();advance_to("carry_to_target");a = sim.person("aoi")
	starting_cash = sim.work_family.household(a).cash;skill = a.skills.repair
	add_work_now();sim.advance_minutes(1)
	expect(current().phase=="interrupted" and sim.meetings.is_empty(),"A newly active duty interrupts preparation under the existing routine rules")
	object = sim.interactions.objects.workshop_radio
	expect(object.holder.is_empty() and object.reserved_by.is_empty() and object.container=="radio_shelf" and is_equal_approx(a.skills.repair,skill) and is_equal_approx(sim.work_family.household(a).cash,starting_cash),"Forced preparation cleanup safely returns the existing object without a cost or invented experience")
	# Death removes meetings directly; orphan repair must not require an actor pose.
	setup();advance_to("carry_to_target");sim.life._end_life(sim.person("aoi"));sim.advance_minutes(1)
	expect(current().phase=="interrupted" and sim.interactions.objects.workshop_radio.holder.is_empty() and sim.interactions.available(),"Death of a holder releases the object and reservation even after direct meeting removal")
	setup();advance_to("carry_to_target");a = sim.person("aoi");a.destination = "off_map_home";sim.advance_minutes(1)
	expect(current().phase=="interrupted" and sim.interactions.available(),"Leaving town safely terminates a held-object workflow")
	setup();advance_to("take_return");progress = sim.work_family.projects.radio;skill = sim.person("aoi").skills.repair
	add_work_now();sim.advance_minutes(1)
	expect(current().phase=="interrupted" and is_equal_approx(sim.work_family.projects.radio,progress) and is_equal_approx(sim.person("aoi").skills.repair,skill),"Interrupting cleanup preserves real completed work without applying it twice")
	# Every nonterminal phase can be saved without a rendered actor or clip clock.
	for phase in WorldInteractions.ACTIVE_PHASES:
		setup(8)
		expect(advance_to(phase),"Reached real phase for save/resume: "+phase)
		expect(sim.save_game(save_path),"Saved logical object, holders and workflow during "+phase)
		var before := state()
		sim.advance_minutes(35)
		var expected := state()
		expect(sim.load_game(save_path) and same(before,state()),"Restored exact resident/object/phase state during "+phase)
		for minute in 35: sim.advance_minutes(1)
		expect(same(expected,state()),"Bulk and minute-wise replay agree, including RNG, after "+phase)
	for phase in ["take","place","take_return","return"]:
		setup();advance_to(phase)
		sim.advance_minutes(2 if phase in ["take","take_return"] else 5)
		object = sim.interactions.objects.workshop_radio
		var held: bool = phase in ["take","take_return"]
		expect((not object.holder.is_empty())==held and object.reserved_by==current().id,"Actual grasp/release boundary preserves holder and reservation inside "+phase)
		expect(sim.save_game(save_path),"Saved inside the grasp/release phase: "+phase)
		var before := state();sim.advance_minutes(25);var expected := state()
		expect(sim.load_game(save_path) and same(before,state()),"Midphase holder/container restore is exact: "+phase)
		sim.advance_minutes(25)
		expect(same(expected,state()),"Midphase grasp/release replays without duplicate ownership effects: "+phase)
	# Malformed state must never be partially restored into the current town.
	setup();advance_to("carry_to_target");sim.save_game(save_path)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var broken: Dictionary = raw.duplicate(true);broken.interactions.objects.workshop_radio.holder = "unknown";malformed(broken,"Unknown holder")
	broken = raw.duplicate(true);broken.interactions.objects.workshop_radio.reserved_by = "missing";malformed(broken,"Orphan reservation")
	broken = raw.duplicate(true);broken.interactions.objects.workshop_radio.container = "radio_table";malformed(broken,"Simultaneous carrier and table containment")
	broken = raw.duplicate(true);broken.interactions.sessions[current().id].phase = "invented";malformed(broken,"Unknown logical phase")
	broken = raw.duplicate(true);broken.interactions.sessions[current().id].effects = ["result"];malformed(broken,"Unearned completion effect")
	broken = raw.duplicate(true);broken.erase("interactions");malformed(broken,"Missing current-schema object state")
	# Unmodified natural town: no needs, relationships, routines or phase overrides.
	sim.free();sim = load("res://game/scripts/simulation.gd").new();root.add_child(sim);sim.reset(711,12)
	var natural_work := false
	var natural_completed := false
	for minute in 4320:
		sim.advance_minutes(1)
		for s in sim.interactions.sessions.values():
			natural_work = natural_work or int(s.worked_minutes)>0
			natural_completed = natural_completed or s.phase=="completed"
		if natural_completed: break
	expect(natural_work and natural_completed,"The normal twelve-person seed711 town autonomously uses the radio workflow through work and return")
	expect(sim.interactions.objects.size()==1,"Natural decisions do not manufacture additional radio props")
	for path in [save_path,bad_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	sim.free()
	print("World interaction checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

var sim: LifeSimulation
var checks := 0
var failures: Array[String] = []
var largest_step := 0.0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func prepare() -> void:
	sim.reset(811)
	for definition in sim.definitions.values(): definition.routines = []
	for p in sim.people:
		p.position = sim.SITES.square
		p.place = "square"; p.destination = "square"
		p.path.clear(); p.moving = false; p.meeting_id = ""; p.support_id = ""
		p.activity_spot = ""; p.routine_id = ""; p.action = "rest"
		p.action_elapsed = 0; p.remaining = 100000
		p.fatigue = .1; p.hunger = .1; p.quiet = .1
		p.next_plan_minute = 1000000; p.support_next_attempt = 1000000
	for household in sim.work_family.households.values():
		household.cash = 100.0; household.home_load = .1
	largest_step = 0

func advance(minutes: int) -> void:
	for minute in minutes:
		var positions := {}
		for p in sim.people: positions[p.id] = p.position
		sim.advance_minutes(1)
		for p in sim.people: largest_step = maxf(largest_step,positions[p.id].distance_to(p.position))

func finish(record: Dictionary, limit: int = 800) -> void:
	var elapsed := 0
	while record.state in ["planned","travel"] and elapsed<limit:
		advance(1); elapsed += 1

func state() -> Dictionary:
	return sim._encode({"people":sim.people,"events":sim.events,"meetings":sim.meetings,
		"agenda":sim.agenda.serialize(),"social":sim.social.serialize(),"work":sim.work_family.serialize(),
		"life":sim.life.serialize(),"elapsed":sim.elapsed,"rng":str(sim.rng.state)})

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-9
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b

func run() -> void:
	sim = LifeSimulation.new(); root.add_child(sim)
	prepare()
	var a: Dictionary = sim.person("aoi")
	var b: Dictionary = sim.person("fumi")
	var reply: Dictionary = sim.agenda.propose(a.id,b.id,"social",true,180)
	expect(reply.status=="accept","Residents can agree to a later time while leaving their earlier day free")
	var record: Dictionary = sim.agenda.records[0]
	sim._assign(a,"hobby",sim.home_for(a),1000,"約束までは自分のことを進めたい")
	var prepared := false
	while record.state=="planned" and sim.elapsed<record.start+20:
		advance(1)
		prepared = prepared or a.action=="prepare"
	expect(prepared,"A person who went home later starts a real preparation journey from that new position")
	expect(a.skills.get("communication",0)==0 and not a.memories.any(func(m): return m.kind=="shared_time"),"Preparation alone does not grant a skill or a shared-time memory")
	finish(record)
	expect(record.state=="kept" and record.revisions.is_empty(),"Considering the current journey keeps the original promise instead of discarding it for an outdated travel estimate")
	expect(largest_step<=sim.WALK_METERS_PER_MINUTE+.00001,"Preparing and joining use actual minute-by-minute movement without teleportation")

	prepare()
	a = sim.person("aoi"); b = sim.person("osamu")
	a.hunger = .55
	var skill: float = a.skills.repair
	sim.agenda.propose(a.id,b.id,"radio",true,240)
	record = sim.agenda.records[0]
	var ate := false
	var ate_minutes := 0
	while record.state in ["planned","travel"] and sim.elapsed<600:
		advance(1)
		if a.action=="eat" and not a.moving:
			ate = true; ate_minutes += 1
	expect(ate and ate_minutes>=20,"A resident actually reaches a meal and eats before the planned shared work")
	expect(record.state=="kept" and a.skills.repair>skill,"A meal and the later real project can both finish without overriding the person's need to eat")
	expect(record.revisions.is_empty(),"The original planned time includes enough preparation for a meal and both journeys")
	expect(a.hunger<.75,"The completed project does not leave the prepared participant urgently hungry")

	prepare()
	a = sim.person("aoi"); b = sim.person("osamu")
	a.hunger = .55
	sim.definitions.aoi.routines = [{"id":"temporary_work","on_days":[0,1,2,3,4,5,6],"start_minute":sim.start_minute,"duration_minutes":90,"place":"square","action":"work"}]
	sim.agenda.propose(a.id,b.id,"radio",true,120)
	record = sim.agenda.records[0]
	expect(int(record.departures[a.id])>=90,"The agreed time leaves a real preparation window after work, including food rather than just outbound travel")
	advance(60)
	expect(a.action=="work" and a.routine_id=="temporary_work","Preparation never interrupts the person's current duty")
	finish(record)
	expect(record.state=="kept" and record.revisions.is_empty(),"A person can finish work, eat and travel in time for the first agreed shared activity")

	prepare()
	a = sim.person("aoi"); b = sim.person("fumi")
	b.quiet = .95
	sim._relation(b,a.id).familiarity = .2
	sim.agenda.propose(a.id,b.id,"social",true,120)
	record = sim.agenda.records[0]
	expect(record.venue=="cafe" and record.duration==15,"A person's preference for a short conversation becomes the agreed cafe alternative")
	finish(record)
	expect(record.state=="kept" and b.memories.any(func(m): return m.kind=="shared_time" and m.other==a.id),"The confirmed short alternative is actually attended without asking the same counteroffer again: %s"%JSON.stringify(record))
	expect(record.revisions.is_empty(),"Entering the cafe during a journey does not invent a new trip back through the outdoor street")

	prepare()
	a = sim.person("aoi"); b = sim.person("fumi")
	sim.agenda.propose(a.id,b.id,"social",true,90)
	record = sim.agenda.records[0]
	var original_start: int = record.start
	var blockers: Array = [sim.person("ryo"),sim.person("nagisa")]
	for i in 2: blockers[i].activity_spot = "bench_0_%d"%i
	while record.revisions.is_empty() and record.state=="planned" and sim.elapsed<300: advance(1)
	expect(record.revisions.size()==1 and record.state=="planned" and record.start>original_start,"Two consenting residents can agree to a new time when the place remains unavailable")
	expect(record.revisions[0].from==original_start and record.revisions[0].reason=="seat_capacity" and not record.change_reason.is_empty(),"The revised promise retains its original time and the actual reason for changing it: %s"%JSON.stringify(record.revisions))
	expect(not a.memories.any(func(m): return m.kind=="shared_time") and a.skills.get("communication",0)==0,"A revised agreement still grants no fictitious attendance or practice")
	for p in blockers: p.activity_spot = ""
	var save_path := "user://test-agenda-preparation.json"
	expect(sim.save_game(save_path),"A revised promise and an actual preparation state can be saved")
	finish(record)
	expect(record.state=="kept" and record.revisions.size()==1,"The revised promise can be fulfilled after the real place becomes available")
	var future := state()
	expect(sim.load_game(save_path),"Revised promises restore through the ordinary save path")
	record = sim.agenda.records[0]
	finish(record)
	expect(equivalent(state(),future),"Resuming a revised promise preserves travel, learning, facts, later decisions and RNG")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var unchanged := state()
	for malformed in ["time","chain","limit","reason"]:
		var bad: Dictionary = raw.duplicate(true)
		match malformed:
			"time": bad.agenda.records[0].revisions[0].at = sim.elapsed+10000
			"chain": bad.agenda.records[0].revisions[0].to += 1
			"limit": bad.agenda.records[0].revisions.resize(3)
			"reason": bad.agenda.records[0].revisions[0].reason = null
		var file := FileAccess.open("user://test-agenda-preparation-invalid.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(bad)); file.close()
		expect(not sim.load_game("user://test-agenda-preparation-invalid.json") and equivalent(state(),unchanged),"An invalid revision (%s) is rejected without mutating the town"%malformed)

	prepare()
	a = sim.person("aoi"); b = sim.person("fumi")
	sim.agenda.propose(a.id,b.id,"social",true,90)
	record = sim.agenda.records[0]
	for i in 2: sim.person("ryo" if i==0 else "nagisa").activity_spot = "bench_0_%d"%i
	finish(record)
	expect(record.state=="postponed" and record.revisions.size()==2,"A permanently unavailable place reaches a finite conclusion after at most two mutually agreed new times")
	var serial: int = sim.agenda.serial
	advance(300)
	expect(sim.agenda.serial==serial and record.state=="postponed","An ended promise does not silently create endless replacement reservations")

	prepare()
	a = sim.person("aoi"); b = sim.person("fumi")
	sim.agenda.propose(a.id,b.id,"social",true,90)
	record = sim.agenda.records[0]
	var relation: Dictionary = sim._relation(b,a.id)
	relation.trust = .01; relation.unresolved_expectation = .95
	finish(record)
	expect(record.state=="postponed" and record.revisions.is_empty(),"A changed refusal cannot be bypassed by automatically accepting a later promise")
	expect(not b.memories.any(func(m): return m.kind=="shared_time"),"An unwilling participant is never recorded as having attended")

	prepare()
	a = sim.person("aoi"); b = sim.person("fumi")
	sim.agenda.propose(a.id,b.id,"social",true,180)
	record = sim.agenda.records[0]
	sim.elapsed = int(record.start)-10
	expect(sim.agenda.prepare(a) and a.preparing_agenda_id==record.id,"An actual staging journey identifies the promise it belongs to")
	var position: Vector3 = a.position
	sim.agenda._close(record,"postponed","場所が使えなくなった","missing_place")
	expect(a.preparing_agenda_id.is_empty() and not a.moving and a.path.is_empty() and a.remaining==0 and a.position==position,"Cancelling the promise releases only its preparation, without continuing to the cancelled place or moving the person instantly")
	advance(1)
	expect(a.action!="prepare","A cancelled preparer returns to an ordinary personal choice on the next simulation step")

	prepare()
	a = sim.person("aoi"); b = sim.person("fumi")
	sim.agenda.propose(a.id,b.id,"social",true,90)
	record = sim.agenda.records[0]
	sim.elapsed = int(record.departures[b.id])
	b.action = "rest"; b.fatigue = .80; b.remaining = 45
	sim.agenda.tick()
	expect(b.action=="rest" and b.meeting_id.is_empty() and record.state=="planned","Dispatch does not overwrite needed rest merely because fatigue is below the older invitation cutoff")
	for path in [save_path,"user://test-agenda-preparation-invalid.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Agenda preparation checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free(); quit(0 if failures.is_empty() else 1)

extends SceneTree

var sim: LifeSimulation
var agenda
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func prepare() -> void:
	sim.reset(811)
	agenda.reset()
	for definition in sim.definitions.values(): definition.routines = []
	for p in sim.people:
		p.position = sim.SITES.square
		p.place = "square"
		p.destination = "square"
		p.path.clear()
		p.moving = false
		p.meeting_id = ""
		p.support_id = ""
		p.activity_spot = ""
		p.action = "rest"
		p.routine_id = ""
		p.action_elapsed = 0
		p.remaining = 100000
		p.fatigue = .1
		p.hunger = .1
		p.quiet = .1
		p.next_plan_minute = 1000000
	for household in sim.work_family.households.values(): household.cash = 100.0

func advance(amount: int) -> void:
	for minute in amount:
		sim.advance_minutes(1)

func finish_record(record: Dictionary, limit: int = 360) -> void:
	var count := 0
	while record.state in ["planned","travel"] and count<limit:
		advance(1)
		count += 1

func routine(start: int, duration: int) -> Dictionary:
	return {"id":"temporary_work","on_days":[0,1,2,3,4,5,6],"start_minute":start,"duration_minutes":duration,"place":"square","action":"work"}

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	agenda = preload("res://game/scripts/resident_agenda.gd").new(sim)
	# Root integration may already own the agenda. Use the test instance for its hooks.
	if sim.get("agenda")!=null: sim.set("agenda",agenda)
	prepare()
	var a: Dictionary = sim.person("aoi")
	var b: Dictionary = sim.person("osamu")
	sim.definitions.aoi.routines = [routine(780,60)]
	sim.definitions.osamu.routines = [routine(840,60)]
	var goal_before: float = a.goal_progress
	var skill_before: float = a.skills.repair
	var funds: float = sim.work_family.household(a).cash
	var reply: Dictionary = agenda.propose(a.id,b.id,"radio",true)
	expect(reply.status=="accept" and agenda.records.size()==1,"Busy residents can agree on a later shared activity")
	var record: Dictionary = agenda.records[0]
	expect(int(record.start)>=120 and int(record.start)<=2880,"The agreed start follows both duties and stays within two representative days")
	expect(sim.meetings.is_empty() and not a.moving and a.goal_progress==goal_before and a.skills.repair==skill_before and sim.work_family.household(a).cash==funds,"A future agreement creates neither travel, learning, project progress nor a material charge")
	expect(agenda.next_commitment(a).minutes==int(record.departures[a.id])-sim.elapsed,"The next commitment includes the real preparation journey")
	expect(not agenda.reserved(a,0) and agenda.reserved(a,int(record.departures[a.id])) and not agenda.reserved(a,int(record.returns[a.id])),"Reservation boundaries leave the earlier day free and include outbound and return travel")
	expect(agenda.propose(a.id,b.id,"radio",true).status=="defer" and agenda.records.size()==1,"Repeating the same agreement does not create another reservation")
	var serialized: Dictionary = agenda.serialize()
	var decoded: Dictionary = sim._decode(JSON.parse_string(JSON.stringify(sim._encode(serialized))))
	agenda.restore(decoded)
	record = agenda.records[0]
	expect(record.state=="planned" and record.origin=="resident" and agenda.serial==1,"Saving and restoring preserves the agreed future time without starting it")
	expect(sim.save_game("user://test-resident-agenda.json"),"The ordinary town save includes the future agreement")
	var saved: Dictionary = agenda.serialize()
	agenda.reset()
	expect(sim.load_game("user://test-resident-agenda.json") and agenda.records.size()==1,"The ordinary town load restores the agenda and its reservations")
	a = sim.person("aoi")
	b = sim.person("osamu")
	record = agenda.records[0]
	expect(record.start==saved.records[0].start and agenda.reserved(a,int(record.departures[a.id])) and sim._next_commitment(a).id=="agenda","Restored preparation times remain real constraints in the simulation")
	var raw = JSON.parse_string(FileAccess.get_file_as_string("user://test-resident-agenda.json"))
	var unchanged := JSON.stringify(sim._encode({"people":sim.people,"events":sim.events,"meetings":sim.meetings,"elapsed":sim.elapsed,"rng":str(sim.rng.state),"agenda":agenda.serialize()}))
	for problem in ["missing","person","departure","return","serial","duration","activity","center","records"]:
		var malformed: Dictionary = raw.duplicate(true)
		match problem:
			"missing": malformed.agenda.records[0].erase("shared_before")
			"person": malformed.agenda.records[0].b = "nobody"
			"departure": malformed.agenda.records[0].departures.aoi = -1
			"return": malformed.agenda.records[0].returns.aoi = 0
			"serial": malformed.agenda.serial = 0
			"duration": malformed.agenda.records[0].duration = -5
			"activity": malformed.agenda.records[0].activity = "invented"
			"center": malformed.agenda.records[0].erase("center")
			"records": malformed.agenda.records = {}
		var file := FileAccess.open("user://test-resident-agenda-invalid.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(malformed))
		file.close()
		expect(not sim.load_game("user://test-resident-agenda-invalid.json") and JSON.stringify(sim._encode({"people":sim.people,"events":sim.events,"meetings":sim.meetings,"elapsed":sim.elapsed,"rng":str(sim.rng.state),"agenda":agenda.serialize()}))==unchanged,"Malformed agenda "+problem+" is rejected without changing the town")
	# The scheduler is stepped at its departure boundary; the actual journey and
	# work below run through the ordinary simulation one minute at a time.
	sim.elapsed = mini(int(record.departures[a.id]),int(record.departures[b.id]))-1
	agenda.tick()
	expect(sim.meetings.is_empty(),"The residents keep their own day until departure preparation begins")
	advance(5)
	expect(a.action=="prepare" or b.action=="prepare" or record.state=="travel","The agreed preparation window starts real individual journeys")
	var joining := 0
	while record.state=="planned" and joining<180:
		advance(1); joining += 1
	var actual: Dictionary = {}
	for meeting in sim.meetings:
		if meeting.get("agenda_id","")==record.id: actual = meeting
	expect(not actual.is_empty() and record.state=="travel","The shared meeting is created only after the participants actually reach the place")
	expect(agenda.person_text(a).is_empty() and agenda.next_commitment(a).id=="","A plan already under way is shown as the current activity rather than duplicated as a future promise")
	expect(not actual.is_empty() and actual.get("not_before",-1)==record.start and not actual.get("materials_ready",true),"Early arrival waits for the agreed start and spends no project materials")
	finish_record(record)
	expect(record.state=="kept" and a.skills.repair>skill_before and sim.elapsed>=int(record.start)+int(record.duration),"A kept agreement requires actual arrival and the full shared work time")
	expect(agenda.person_text(a).is_empty(),"Completed plans no longer appear as future appointments")

	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	var original_offer := {"a":"aoi","b":"fumi","start":1000,"duration":25,"location":"cafe","made_at":0}
	sim.social.offer = original_offer.duplicate(true)
	reply = agenda.propose(a.id,b.id,"social",true)
	expect(reply.status=="accept" and sim.social.offer==original_offer,"Residents' future negotiations preserve the player's pending conversation offer")
	record = agenda.records[0]
	finish_record(record)
	expect(record.state=="kept" and sim.social.offer==original_offer,"Dispatching an agreed conversation preserves the UI offer and records only the actual meeting")
	expect(a.cognition_plan.origin=="resident" and b.cognition_plan.origin=="resident","A resident-origin scheduled conversation stays resident-origin in both plans")
	expect(a.memories.any(func(m): return m.kind=="shared_time" and m.other==b.id),"A scheduled conversation leaves a real participant memory")

	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	var old := {"id":"appointment_old","a":a.id,"b":b.id,"location":"bench","state":"planned","start":120,"duration":25,"made_at":0}
	sim.social.appointments.append(old)
	reply = agenda.propose(a.id,b.id,"radio",true)
	expect(reply.status=="accept","A future project can be planned around an existing social appointment")
	record = agenda.records[0]
	expect(int(record.departures[a.id])>=160 and int(record.departures[b.id])>=160,"The new reservation includes the old conversation's preparation and completion window")
	expect(not agenda._window_free(a,int(record.departures[a.id]),int(record.returns[a.id])),"Another future plan cannot overlap the agenda's own reservation")
	expect(not sim.social._slot_free(a,b,int(record.start),25),"An old-style social booking cannot overlap an agenda reservation in the reverse direction")
	agenda.dispatch_id = record.id
	expect(not agenda.reserved(a,int(record.start)) and agenda.next_commitment(a).id=="","Synchronous dispatch excludes its own reservation from admission queries")
	agenda.dispatch_id = ""
	# The farther resident can travel while the nearer resident finishes work.
	prepare()
	a = sim.person("aoi")
	b = sim.person("osamu")
	a.position = sim.SITES.off_map_school
	a.place = "off_map_school"
	b.position = sim.SITES.workshop
	b.place = "workshop"
	var nearby_work := routine(780,80)
	nearby_work.place = "workshop"
	sim.definitions.osamu.routines = [nearby_work]
	reply = agenda.propose(a.id,b.id,"radio",true)
	expect(reply.status=="accept","People at different distances can negotiate a later meeting")
	record = agenda.records[0]
	expect(int(record.departures[a.id])<int(record.departures[b.id]) and int(record.departures[b.id])>=80,"Each person has an individual preparation window and the nearby person's duty is protected")
	advance(60)
	expect(a.action=="prepare" and b.action=="work" and b.routine_id=="temporary_work" and b.meeting_id.is_empty(),"The distant person travels without pulling the nearby person out of work")
	finish_record(record)
	expect(record.state=="kept","Both individual journeys can reach an actual shared activity after the duty ends")
	# A calendar gap that holds outbound travel and work still cannot be used
	# when the return journey would run into a scheduled obligation.
	prepare()
	a = sim.person("aoi")
	b = sim.person("osamu")
	var duty := routine(900,60)
	duty.place = "off_map_workplace"
	sim.definitions.aoi.routines = [duty]
	reply = agenda.propose(a.id,b.id,"radio",true)
	record = agenda.records[0]
	expect(reply.status=="accept" and int(record.departures[a.id])>=180,"Return travel prevents a superficially free pre-duty gap from being overbooked")

	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	agenda.propose(a.id,b.id,"social",true)
	record = agenda.records[0]
	while record.state=="planned": advance(1)
	var cancelled: Dictionary = sim.meetings[-1]
	sim.meetings.erase(cancelled)
	for p in [a,b]: p.meeting_id = ""
	agenda.tick()
	expect(record.state=="postponed" and not a.memories.any(func(m): return m.kind=="shared_time"),"A removed meeting with no real participation never becomes a kept promise")

	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	b.hunger = .99
	expect(agenda.propose(a.id,b.id,"social",true).status=="defer" and agenda.records.is_empty(),"Hunger can defer agreement before any reservation exists")
	b.hunger = .1
	b.fatigue = .9
	expect(agenda.propose(a.id,b.id,"radio",true).status=="decline" and agenda.records.is_empty(),"Exhaustion can decline the future activity")
	b.fatigue = .1
	var relation: Dictionary = sim._relation(b,a.id)
	relation.trust = .05
	relation.unresolved_expectation = .9
	expect(agenda.propose(a.id,b.id,"social",true).status=="decline" and agenda.records.is_empty(),"Unresolved mistrust cannot silently become a confirmed promise")

	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	agenda.propose(a.id,b.id,"social",false)
	record = agenda.records[0]
	for p in [sim.person("ryo"),sim.person("nagisa")]: p.activity_spot = "bench_0_%d"%[0 if p.id=="ryo" else 1]
	sim.social.offer = original_offer.duplicate(true)
	finish_record(record,600)
	expect(record.state=="postponed" and record.revisions.size()<=2 and int(record.attempts)<=3 and sim.meetings.is_empty(),"Unavailable seats cause a bounded conclusion after at most two mutually agreed new times")
	var offer_preserved: bool = sim.social.offer==original_offer if sim.elapsed<=int(original_offer.made_at)+180 else sim.social.offer.is_empty()
	expect(offer_preserved and record.meeting_id.is_empty(),"Failed resident dispatch preserves a pending UI offer until its normal expiry and never creates attendance for the failed appointment")
	var tries: int = record.attempts
	advance(30)
	expect(record.attempts==tries and agenda.propose(a.id,b.id,"social",false).status=="defer" and agenda.records.size()==1,"A postponed agreement stops retrying and cannot immediately create another promise")

	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	agenda.propose(a.id,b.id,"social",true)
	record = agenda.records[0]
	b.hunger = .99
	b.action = "eat"
	b.remaining = 100000
	sim.elapsed = int(record.departures[b.id])
	agenda.tick()
	expect(b.action=="eat" and b.meeting_id.is_empty() and record.state=="planned","A changed need for food prevents social dispatch from overwriting an actual meal")
	finish_record(record)
	var shared_after_meal: bool = b.memories.any(func(m): return m.kind=="shared_time" and m.other==a.id)
	expect((record.state=="kept" and shared_after_meal and b.hunger<.75) or (record.state=="postponed" and not shared_after_meal),"A deferred meal can lead to a kept promise only after actual participation with the hunger addressed")
	prepare()
	a = sim.person("aoi")
	b = sim.person("fumi")
	agenda.propose(a.id,b.id,"social",true)
	record = agenda.records[0]
	b.action = "eat"
	b.hunger = .99
	sim.elapsed = int(record.departures[b.id])
	agenda.tick()
	b.action = "rest"
	b.hunger = .1
	advance(15)
	expect(record.state=="travel","A meal finished before the next bounded attempt can release the agreed journey")
	finish_record(record)
	expect(record.state=="kept","A temporary defer can still lead to actual participation within the appointment grace period")

	prepare()
	a = sim.person("aoi")
	b = sim.person("osamu")
	agenda.propose(a.id,b.id,"radio",true)
	agenda.propose(a.id,"fumi","social",true)
	expect(agenda.records.size()==2 and agenda.propose(a.id,"ritsu","music",true).status=="defer" and agenda.records.size()==2,"A resident cannot fill their day with more than two pending agreements")

	prepare()
	a = sim.person("aoi")
	b = sim.person("osamu")
	agenda.propose(a.id,b.id,"radio",true)
	record = agenda.records[0]
	sim.life._end_life(b)
	agenda.tick()
	expect(record.state=="ended" and agenda.person_text(a).is_empty(),"A future agreement ends when a participant dies")
	expect(agenda.propose(a.id,b.id,"radio",true).status=="decline" and agenda.records.size()==1,"The agenda never makes a new promise with a departed resident")
	for path in ["user://test-resident-agenda.json","user://test-resident-agenda-invalid.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Resident agenda checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

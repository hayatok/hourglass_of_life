extends SceneTree

var sim: LifeSimulation
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func shared_count(p: Dictionary, other: String) -> int:
	var count = 0
	for memory in p.memories:
		if memory.kind=="shared_time" and memory.other==other: count += 1
	return count

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	# A Monday class and the following travel time rule out an instant meeting.
	sim.start_minute = 600
	sim.epoch_weekday = 0
	for p in sim.people:
		p.fatigue = .15
		p.quiet = .1
	var reply = sim.propose_meeting("aoi","fumi","cafe")
	expect(reply.status=="counteroffer" and not sim.social.offer.is_empty(),"A busy student proposes a concrete alternative")
	var promised_start = int(sim.social.offer.start)
	expect(promised_start>=420,"The suggested time allows classes and travel to finish")
	expect(sim.confirm_offer("aoi").status=="accept","The alternative can be made into an appointment")
	expect(sim.social.appointments.size()==1,"A dated commitment is stored")
	expect(shared_count(sim.person("aoi"),"fumi")==0,"Booking alone creates no shared experience")
	expect(sim._next_commitment(sim.person("fumi")).id=="appointment","A promise becomes a real constraint on other plans")
	sim.advance_minutes(promised_start-121)
	expect(sim.social.appointments[0].state=="planned","Residents keep their own day until preparation time")
	sim.advance_minutes(1)
	expect(sim.social.appointments[0].state=="on_the_way","Residents depart in time for a future appointment")
	sim.advance_minutes(119)
	expect(shared_count(sim.person("aoi"),"fumi")==0,"Arriving before the appointment does not grant a memory")
	sim.advance_minutes(27)
	expect(sim.social.appointments[0].state=="kept","The dated meeting is fulfilled by actual time together")
	expect(shared_count(sim.person("aoi"),"fumi")==1 and shared_count(sim.person("fumi"),"aoi")==1,"Both participants retain the fulfilled appointment")
	expect(not sim.person("aoi").memories.is_empty() and "写真" in sim.person("aoi").memories[-1].text,"The conversation reflects the other resident's interests")
	# Familiarity changes consent while the physical condition stays identical.
	sim.reset()
	var a = sim.person("aoi")
	var f = sim.person("fumi")
	a.quiet = .9
	var r = sim._relation(a,"fumi")
	r.familiarity = .1
	expect(sim.propose_meeting("aoi","fumi").status=="counteroffer","A reserved resident suggests a shorter familiar venue with a new acquaintance")
	expect(sim.social.offer.location=="cafe" and sim.social.offer.duration==15,"That alternative includes both a venue and a shorter duration")
	r.familiarity = .8
	expect(sim.propose_meeting("aoi","fumi").status=="accept","The same reserved resident accepts a familiar partner")
	# Trust, ease and past unresolved experiences affect selection and outcomes.
	sim.reset()
	a = sim.person("aoi")
	f = sim.person("fumi")
	r = sim._relation(a,"fumi")
	r.familiarity = .7
	r.ease = .8
	r.trust = .8
	var good_score = sim.social.partner_score(a,f)
	r.unresolved_expectation = .9
	expect(sim.social.partner_score(a,f)<good_score,"Unresolved experiences change how appealing a partner is")
	var old_trust = r.trust
	var other_view = sim._relation(f,"aoi")
	other_view.unresolved_expectation = 0
	var other_trust = other_view.trust
	sim._begin_meeting(a,f,sim.benches[0],"bench",false)
	var meeting = sim.meetings[0]
	sim._finish_meeting(meeting,true)
	expect(r.trust<old_trust and other_view.trust>other_trust,"The same encounter can have different effects in each direction")
	expect("言葉にできない" in a.memories[-1].text,"The resident can retain an uneasy interpretation")
	# A habit needs multiple distinct days, rather than repeated button clicks.
	sim.reset()
	var changed = {"id":"appointment_change","a":"aoi","b":"fumi","state":"on_the_way"}
	sim.social.appointments.append(changed)
	var before_changed = sim._relation(sim.person("aoi"),"fumi").unresolved_expectation
	sim.social._postpone(changed,"今日は疲れが強かった。")
	expect(sim._relation(sim.person("aoi"),"fumi").unresolved_expectation>before_changed,"A postponed promise leaves an unresolved wish to meet")
	expect(shared_count(sim.person("aoi"),"fumi")==0 and sim.person("aoi").memories[-1].kind=="promise_change","Rescheduling is remembered without claiming an encounter happened")
	sim.reset()
	a = sim.person("aoi")
	a.routine_id = ""
	a.action = "hobby"
	a.place = "home_shared"
	for day in [0,0,1,2]:
		sim.elapsed = day*1440
		a.action_elapsed = 19
		a.habit_recorded = false
		sim.social.activity_tick(a)
	expect(a.habits.size()==1 and a.habits[0].days.size()==3,"Repeated activity in three distinct days forms one habit")
	var option = {"kind":"hobby","place":"home_shared"}
	expect(sim.social.habit_bonus(a,option)>0,"A learned habit changes a future action's appeal")
	expect(sim.social.habit_bonus(a,{"kind":"hobby","place":"workshop"})==0,"A learned habit remains tied to its context")
	expect("習慣" in sim.social.person_text(a),"The reason behind repeated behavior is visible to the player")
	# Social commitments and learned habits are part of the save, including v0.1 migration.
	sim.social.offer = {"a":"aoi","b":"fumi","start":sim.elapsed+180,"location":"cafe","duration":25,"made_at":sim.elapsed}
	sim.confirm_offer("aoi")
	var appointment_count = sim.social.appointments.size()
	expect(sim.save_game("user://test-social.json"),"Social state can be saved")
	sim.reset()
	expect(sim.load_game("user://test-social.json"),"Social state can be loaded")
	expect(sim.person("aoi").habits[0].days.size()==3 and sim.social.appointments.size()==appointment_count,"Habits and appointments survive a round trip")
	# Construct a genuine schema-1 payload by removing the new social fields.
	var legacy = JSON.parse_string(FileAccess.get_file_as_string("user://test-social.json"))
	legacy.schema = 1
	legacy.erase("social")
	for p in legacy.people:
		p.erase("habits")
		p.erase("action_elapsed")
		p.erase("habit_recorded")
	var file = FileAccess.open("user://test-legacy.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	expect(sim.load_game("user://test-legacy.json"),"A v0.1 save remains playable")
	expect(sim.person("aoi").habits.is_empty() and sim.social.appointments.is_empty(),"Migration initializes new social fields without inventing past events")
	var time_before = sim.elapsed
	var bad_payloads = [{"schema":2},legacy.duplicate(true),legacy.duplicate(true),legacy.duplicate(true)]
	bad_payloads[1].people[1].id = bad_payloads[1].people[0].id
	bad_payloads[2].people[0].position = {"__vector3":[1]}
	bad_payloads[3].people[0].erase("path")
	for bad in bad_payloads:
		var invalid = FileAccess.open("user://test-invalid.json",FileAccess.WRITE)
		invalid.store_string(JSON.stringify(bad))
		invalid.close()
		expect(not sim.load_game("user://test-invalid.json") and sim.elapsed==time_before,"A malformed save is rejected without changing the current town")
	for path in ["user://test-social.json","user://test-legacy.json","user://test-invalid.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Social life checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

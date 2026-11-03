extends SceneTree

var sim: LifeSimulation
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func advance_to(day: int, minute: int = 0) -> void:
	sim.advance_minutes(maxi(0,day*1440+minute-sim.start_minute-sim.elapsed))

func has_memory(p: Dictionary, kind: String) -> bool:
	return p.memories.any(func(m): return m.kind==kind)

func live_state() -> Dictionary:
	return sim._encode({"people":sim.people,"definitions":sim.definitions,"events":sim.events,"meetings":sim.meetings,
		"elapsed":sim.elapsed,"start_minute":sim.start_minute,"epoch_weekday":sim.epoch_weekday,"remainder":sim.minute_remainder,
		"rng":str(sim.rng.state),"world_seed":sim.world_seed,"event_serial":sim.event_serial,"meeting_serial":sim.meeting_serial,
		"benches":sim.benches,"budget":sim.shared_budget,"social":sim.social.serialize(),"work":sim.work_family.serialize(),
		"life":sim.life.serialize(),"agenda":sim.agenda.serialize(),"interactions":sim.interactions.serialize(),"tabletop":sim.tabletop.serialize(),"weather":sim.weather.serialize()})

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	expect(sim.person("aoi").age==20 and sim.life.legacy.is_empty(),"A new town begins with authored ages and no invented achievements")
	expect(sim.person("maho").place=="bakery_cafe","The initial afternoon begins with the existing shift already at its workplace")
	sim.life._next_wish(sim.person("aoi"))
	expect("ラジオ" in sim.person("aoi").current_goal and sim.person("aoi").goal_kind=="creative","A student's next wish does not assume professional experience from a future job")
	sim.reset()
	var traits_before = sim.definitions.osamu.traits.duplicate(true)
	advance_to(12)
	expect(sim.person("aoi").age==21 and sim.person("osamu").age==69,"A representative year increments each living resident's age")
	expect(sim.weekday()==3,"The seven-day week continues across the twelve-day year")
	expect(sim.definitions.osamu.traits==traits_before,"Age alone does not rewrite the resident's personality")
	advance_to(18,600)
	expect(sim.life.announced.size()==2,"Residents learn about concrete future changes before they happen")
	var aoi = sim.person("aoi")
	expect("aoi_move" in aoi.known_plans and has_memory(aoi,"future_plan"),"The moving resident actually knows the coming time limit")
	var strangers = sim.people.filter(func(p): return p.id!="aoi" and sim.social.relation(aoi,p.id).familiarity<.3)
	expect(not strangers.is_empty() and not "aoi_move" in strangers[0].known_plans,"A private announcement is not made universal NPC knowledge")
	expect(sim.life.action_bonus(aoi,{"kind":"social"})>0,"A known departure changes the appeal of time with others")
	expect(not aoi.has("end_age"),"An internal authored life ending is not provided as the resident's decision knowledge")
	var announcement_count = sim.life.chronicle.size()
	sim.advance_minutes(60)
	expect(sim.life.chronicle.size()==announcement_count,"An announcement is not repeated every minute")
	advance_to(24,539)
	var before_move: Vector3 = aoi.position
	sim.advance_minutes(1)
	expect(aoi.age==22 and aoi.stage=="moved" and aoi.household_override=="aoi_apartment","Graduation changes age, role and actual household membership")
	expect(aoi.position.distance_to(before_move)<=sim.WALK_METERS_PER_MINUTE+.001 and aoi.moving,"Moving starts a real journey instead of teleporting the person out of town")
	expect(sim.work_family.household_id(aoi)=="aoi_apartment" and not aoi.goal_history.is_empty(),"The new living conditions preserve the previous wish and its progress")
	expect(sim.person("osamu").age==70 and sim.person("osamu").stage=="retired","The craftsman actually ends regular shop hours")
	expect(not sim.life.routines(sim.person("osamu")).any(func(r): return r.id=="workshop"),"Retirement removes the fixed shift instead of only changing dialogue")
	expect(sim._hobby_place(sim.person("osamu"))=="workshop","Retirement keeps the person's own workshop and creative possibilities")
	expect(sim._routine_at(aoi,840,0).id=="new_work","The graduate has a real weekday job instead of the old classes")
	expect(sim._routine_at(aoi,840,6).is_empty() and sim._routine_at(aoi,1140,6).id=="away_private","A moved resident can meet people during a bounded Sunday visit")
	advance_to(36)
	expect(sim.life.chapter_ready and not sim.running,"Three years reaches a genuine review point and pauses the live clock")
	expect("卒業" in sim.life.journal_text() and "定時" in sim.life.journal_text(),"The review reports the transitions that actually occurred")
	advance_to(60,960)
	expect(sim.person("rin").age==12,"The child also grows with the same calendar")
	expect(sim._authored_routine_at(sim.person("ryo"),960,0).is_empty(),"Growing independence changes the parent's real care obligation")
	expect(not sim.life.routines(sim.person("rin")).any(func(r): return r.id=="after_school_home"),"The older child is no longer confined to the initial after-school routine")
	# A real completed undertaking creates a placed record, not a proposed one.
	sim.reset()
	var osamu = sim.person("osamu")
	osamu.goal_progress = .999
	osamu.position = sim.SITES.workshop
	osamu.place = "workshop"
	sim._assign(osamu,"hobby","workshop",60,"自分のラジオを仕上げる",osamu.position)
	sim.advance_minutes(1)
	expect(sim.life.legacy.size()==1 and sim.life.legacy[0].owner=="osamu","Finishing an actual goal produces an accessible record")
	var item = sim.life.legacy[0]
	aoi = sim.person("aoi")
	var temperament = sim.definitions.aoi.traits.duplicate(true)
	sim._assign(aoi,"legacy",item.place,40,"修の記録を読む",item.position+Vector3(0,0,.6))
	aoi.legacy_read_id = item.id
	sim.advance_minutes(1)
	expect(item.uses==0 and not has_memory(aoi,"inheritance"),"Choosing a record without reaching it does not create inherited experience")
	var limit = 0
	while aoi.moving and limit<180:
		sim.advance_minutes(1)
		limit += 1
	sim.advance_minutes(19)
	expect(item.uses==0,"A glance on arrival is not the completed reading time")
	sim.advance_minutes(1)
	expect(item.uses==1 and has_memory(aoi,"inheritance"),"A real reader takes an experience from another person's record")
	expect(item.readers[0].id=="aoi" and aoi.private_project>=.05,"The artifact records the recipient and influences their own creative work")
	expect(sim.life.action_bonus(aoi,{"kind":"hobby"})>0 and aoi.inspiration.source=="osamu","The inherited experience makes a related future activity more appealing")
	expect(sim.definitions.aoi.traits==temperament,"A single inherited experience does not rewrite stable personality traits")
	# Memories and records remain meaningful after a farewell.
	sim.life._end_life(osamu)
	expect(not osamu.alive and has_memory(aoi,"farewell"),"A life ending changes the person's state and leaves a remembered farewell")
	expect(sim.propose_meeting("aoi","osamu").status=="decline" and sim.propose_project("aoi","osamu").status=="decline","A remembered person cannot be invited as though still present")
	expect(sim.life.legacy.size()==1 and "修理の記録" in sim.life.journal_text(),"The person's record outlasts their physical presence")
	expect(sim.save_game("user://test-life-course.json"),"The new calendar and legacy state can be saved")
	sim.reset()
	expect(sim.load_game("user://test-life-course.json"),"A farewell and inherited record can be loaded")
	expect(not sim.person("osamu").alive and sim.life.legacy[0].uses==1,"Loading preserves absence and actual use of the record")
	# Earlier development formats are rejected rather than inventing a calendar,
	# household role or historical encounter for their missing life-course state.
	var current_text := FileAccess.get_file_as_string("user://test-life-course.json")
	var old: Dictionary = JSON.parse_string(current_text)
	old.schema = 3
	old.erase("life")
	old.work_family.households.erase("aoi_apartment")
	for p in old.people:
		for key in ["base_age","alive","stage","current_goal","goal_kind","known_plans","goal_history","legacy_read_id","legacy_read_recorded","household_override","career_retired","inspiration"]: p.erase(key)
		p.age = sim.definitions[p.id].age_years
	var old_path := "user://test-life-course-old.json"
	var file = FileAccess.open(old_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var old_text := FileAccess.get_file_as_string(old_path)
	var before := live_state()
	expect(not sim.load_game(old_path) and not sim.load_error.is_empty(),"A schema-3 life-course save is rejected with a readable incompatible-format reason")
	expect(live_state()==before,"Rejecting an older life-course save preserves actual ages, roles, memories, records and RNG")
	expect(FileAccess.get_file_as_string("user://test-life-course.json")==current_text and FileAccess.get_file_as_string(old_path)==old_text,"Rejecting an older life-course save preserves both existing saved files")
	# Run the real authored calendar long enough to reach the first life ending.
	sim.reset()
	sim.advance_minutes(20*12*1440)
	expect(not sim.person("osamu").alive and sim.person("fumi").alive,"Long play reaches the authored farewell while other residents keep living")
	expect(sim.person("rin").age==27 and sim.person("rin").occupation=="町の模型工房で働く人","The child progresses through study to an adult working role")
	expect(sim.life.legacy.any(func(i): return i.owner=="osamu") and "見送った" in sim.life.journal_text(),"The ongoing town retains records and its actual farewell history")
	sim.save_game("user://test-life-course.json")
	expect(sim.load_game("user://test-life-course.json"),"The long-running town remains saveable and playable")
	sim.life.chapter_acknowledged = true
	sim.life.chapter_ready = false
	advance_to(35*12)
	expect(sim.person("ritsu").career_retired and not sim.life.routines(sim.person("ritsu")).any(func(r): return r.id=="night_shift"),"Later life also replaces the former night worker's actual shift")
	print("Long play: 35 representative years reached")
	advance_to(88*12)
	expect(not sim.people.any(func(p): return sim.life.is_alive(p)),"The full authored lives can reach their real endings")
	expect(sim.life.chapter_ready and sim.life.chapter_mode=="last","The last farewell reaches an actual final review")
	expect(not sim.life.legacy.is_empty() and sim.life.legacy.any(func(i): return i.uses>0),"The final town retains things that other people actually received")
	sim.save_game("user://test-life-course.json")
	expect(sim.load_game("user://test-life-course.json"),"A complete lifetime remains recoverable from its save")
	print("Long play: 88 representative years reached")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-life-course.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	print("Life course checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

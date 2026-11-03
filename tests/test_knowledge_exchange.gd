extends SceneTree

var sim: LifeSimulation
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-10
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	return a==b

func prepare(bridge: bool = true) -> void:
	sim.reset(933)
	for definition in sim.definitions.values(): definition.routines = []
	for p in sim.people:
		p.position = sim.SITES[sim.home_for(p)]
		p.place = sim.home_for(p)
		p.destination = p.place
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
	for id in ["fumi","aoi"]:
		var p: Dictionary = sim.person(id)
		p.place = "square"
		p.destination = "square"
		p.position = sim.SITES.square+Vector3(-1 if id=="fumi" else 1,0,0)
	var craftsperson: Dictionary = sim.person("osamu")
	craftsperson.place = "workshop"
	craftsperson.destination = "workshop"
	craftsperson.position = sim.SITES.workshop
	for household in sim.work_family.households.values(): household.cash = 100.0
	if not bridge:
		sim.person("fumi").known_profiles.erase("osamu")
		sim.person("fumi").knowledge.clear()

func profile(observer: Dictionary, subject: String, skill: String, level: float, origin: int = -1) -> Dictionary:
	sim._log(subject,"得意なことの観察","その時の取り組みについて話した。")
	var event: Dictionary = sim.events[-1]
	event.fact = "profile"
	var skills := {}
	skills[skill] = level
	event.value = {"person":subject,"skills":skills,"interests":[skill]}
	event.participants = [observer.id,subject]
	if origin>=0: event.origin_observed_at = origin
	sim.cognition.observe(observer,event)
	return event

func talk(a: String, b: String, verify_arrival: bool = false) -> void:
	var reply: Dictionary = sim.propose_meeting(a,b)
	expect(reply.status=="accept","The fixture's residents agree to an actual conversation")
	if reply.status!="accept": return
	var meeting: Dictionary = sim.meetings[-1]
	var elapsed := 0
	while meeting.state=="travel" and elapsed<180:
		sim.advance_minutes(1)
		elapsed += 1
	if verify_arrival:
		expect(meeting.state=="engaged","The conversation reaches its actual seats")
		expect(not sim.cognition.knows_person(sim.person("aoi"),"osamu"),"Arrival alone does not transmit a third person's profile")
	sim.advance_minutes(25)
	expect(not sim.meetings.has(meeting),"The actual conversation completes before information is exchanged")

func has_candidate(p: Dictionary, partner: String, activity: String) -> bool:
	return sim.resident_activities.candidates(p).any(func(c): return c.partner==partner and c.project.key==activity)

func knowledge(p: Dictionary, fact: String, subject: String) -> Array:
	return p.knowledge.filter(func(k): return k.fact==fact and k.value is Dictionary and k.value.get("person","")==subject)

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	prepare()
	var speaker: Dictionary = sim.person("fumi")
	var listener: Dictionary = sim.person("aoi")
	var other: Dictionary = sim.person("osamu")
	var exchange = sim.social.knowledge_exchange
	expect(speaker.known_profiles.has(other.id) and speaker.knowledge.is_empty(),"The bridge starts with a historical profile rather than a recent event")
	expect(not sim.cognition.knows_person(listener,other.id) and not has_candidate(listener,other.id,"radio"),"The distant craftsperson is unavailable to uninformed planning")
	var outsider_before: String = JSON.stringify(sim.person("nagisa").knowledge)
	var skill_before: float = listener.skills.repair
	# More recent information is not automatically the information worth sharing.
	sim.advance_minutes(3)
	profile(speaker,"ritsu","music",.7)
	var irrelevant_id: String = speaker.knowledge[-1].event_id
	expect(exchange.exchange(speaker,listener,speaker.knowledge.duplicate(true),listener.knowledge.duplicate(true)).is_empty(),"An API call outside a completed actual meeting cannot spread information")
	talk(speaker.id,listener.id,true)
	var received: Array = knowledge(listener,"profile",other.id)
	expect(received.size()==1,"An actual conversation can transmit one useful initial-profile account")
	if not received.is_empty():
		expect(received[0].mode=="told" and received[0].received_from==speaker.id and received[0].source=="initial_profile","Historical observation, latest speaker, and hearsay remain distinct")
		expect(received[0].origin_observed_at==0 and received[0].observed_at==sim.elapsed,"The initial observation time survives a later conversation")
	expect(is_equal_approx(sim.cognition.known_skill(listener,other.id,"repair"),.9),"The listener learns the historically observed repair skill")
	expect(not listener.knowledge.any(func(k): return k.event_id==irrelevant_id),"A recent music account does not displace advice relevant to a repair wish")
	expect(JSON.stringify(sim.person("nagisa").knowledge)==outsider_before,"An absent third person does not instantly receive the introduction")
	expect(listener.skills.repair==skill_before,"Hearing advice does not grant practical skill")
	var introduction: Dictionary = exchange.introduction(listener,other.id)
	expect(not introduction.is_empty() and introduction.via==speaker.id and introduction.origin_observed_at==0,"A planner can inspect the real intermediary and original observation time")
	expect(not introduction.is_empty() and not introduction.event_id.is_empty() and not introduction.profile_event.is_empty(),"An introduction retains both conversation and profile event references")
	expect(speaker.name in exchange.introduction_reason(listener,other.id),"A short reason identifies the actual intermediary")
	expect(has_candidate(listener,other.id,"radio"),"The actual introduction opens a previously absent shared repair candidate")
	var knowledge_before: Array = listener.knowledge.duplicate(true)
	expect(sim.save_game("user://test-knowledge-exchange.json"),"A town with an introduction can be saved")
	expect(sim.load_game("user://test-knowledge-exchange.json"),"A saved historical introduction passes actual save validation")
	listener = sim.person("aoi")
	other = sim.person("osamu")
	speaker = sim.person("fumi")
	expect(equivalent(listener.knowledge,knowledge_before) and not exchange.introduction(listener,other.id).is_empty(),"Load preserves source references and the actionable introduction")
	var expectations_before: int = listener.expectations.size()
	var reply: Dictionary = sim.work_family.propose_project(listener.id,other.id,"radio",true)
	expect(reply.status=="accept","The introduced pair can mutually agree to the newly available activity")
	expect(speaker.name in listener.cognition_plan.get("reason","") and listener.cognition_plan.get("introduction_event","")==introduction.event_id,"The actual activity retains the intermediary and source event that made this new partner known")
	expect(listener.skills.repair==skill_before and listener.expectations.size()==expectations_before,"Agreement alone awards no practice or completed-work expectation")
	if reply.status=="accept":
		var meeting: Dictionary = sim.meetings[-1]
		var elapsed := 0
		while meeting.state=="travel" and elapsed<180:
			sim.advance_minutes(1)
			elapsed += 1
		expect(meeting.state=="engaged" and listener.skills.repair==skill_before,"The new partners physically reach the worktable before receiving experience")
		sim.advance_minutes(45)
		expect(listener.skills.repair>skill_before and listener.expectations.size()>expectations_before,"Only completed joint work increases repair skill and a situated expectation")
		# The practical result is earned at the worktable, but the shared plan
		# includes carrying the same radio back and releasing its reservation.
		for minute in int(sim.interactions.config.timeout_minutes):
			if not sim.meetings.has(meeting): break
			sim.advance_minutes(1)
		var workflow: Dictionary = sim.interactions.sessions.get(meeting.get("interaction_id",""),{})
		var radio: Dictionary = sim.interactions.objects.get(workflow.get("object_id",""),{})
		expect(listener.cognition_plan.stage=="completed" and workflow.get("phase","")=="completed" and radio.get("state","")=="stored" and radio.get("container","")==sim.interactions.config.source_container and radio.get("holder","missing").is_empty() and radio.get("reserved_by","missing").is_empty(),"The introduced activity completes the real participant's plan after returning the actual radio")

	# Matched town: same people, interests, skills, needs and conversation; no bridge.
	prepare(false)
	listener = sim.person("aoi")
	talk("fumi","aoi")
	expect(not sim.cognition.knows_person(listener,"osamu") and not has_candidate(listener,"osamu","radio"),"The matched conversation without source knowledge creates no third-person opportunity")
	expect(listener.skills.repair==skill_before,"The no-bridge town receives no repair practice")
	expect(exchange.introduction(listener,"osamu").is_empty(),"Missing source knowledge cannot fabricate an introduction")

	# Historical snapshots do not inspect a third person's current private state.
	prepare()
	sim.person("osamu").skills.repair = .11
	sim.person("osamu").interests = ["music"]
	talk("fumi","aoi")
	listener = sim.person("aoi")
	expect(is_equal_approx(sim.cognition.known_skill(listener,"osamu","repair"),.9),"Unseen live skill changes cannot rewrite the speaker's initial account")
	expect("music" not in sim.cognition.known_interests(listener,"osamu"),"Unseen current interests do not leak through an introduction")
	prepare()
	sim.advance_minutes(20)
	profile(sim.person("fumi"),"osamu","repair",.6)
	talk("fumi","aoi")
	var updated: Array = knowledge(sim.person("aoi"),"profile","osamu")
	expect(updated.size()==1 and is_equal_approx(float(updated[0].value.skills.repair),.6) and updated[0].origin_observed_at==20,"A speaker's newer actual observation takes precedence over their own high initial estimate")

	# A receiver's later observation takes precedence over an old high estimate.
	prepare()
	sim.advance_minutes(20)
	listener = sim.person("aoi")
	profile(listener,"osamu","repair",.35)
	talk("fumi","aoi")
	expect(is_equal_approx(sim.cognition.known_skill(listener,"osamu","repair"),.35),"An older high estimate does not override a more recent direct observation")
	expect(not knowledge(listener,"introduction","osamu").any(func(k): return k.value.skill=="repair"),"An obsolete repair account is not repeatedly presented as new advice")
	# Explicit old hearsay still cannot displace fresh observations on another path.
	var old_event: Dictionary = profile(sim.person("fumi"),"osamu","repair",.9,0)
	expect(sim.cognition.share(sim.person("fumi"),listener,old_event.event_id),"An old account can retain its history when explicitly shared")
	expect(is_equal_approx(sim.cognition.known_skill(listener,"osamu","repair"),.35),"Late delivery of old hearsay preserves the newer observed skill")

	# Acquired information can travel again, retaining its origin and changing hop.
	prepare()
	talk("fumi","aoi")
	listener = sim.person("aoi")
	var next: Dictionary = sim.person("maho")
	next.interests = ["repair"]
	next.current_goal = "ラジオを直したい"
	next.known_profiles.erase("osamu")
	var original: Dictionary = knowledge(listener,"profile","osamu")[0]
	expect(not sim.cognition.knows_person(next,"osamu"),"A future listener remains uninformed before their own conversation")
	sim.propose_rest("fumi")
	talk("aoi","maho")
	var second_hop: Array = knowledge(next,"profile","osamu")
	expect(second_hop.size()==1 and second_hop[0].event_id==original.event_id,"A later conversation transmits the actual acquired account")
	if not second_hop.is_empty():
		expect(second_hop[0].received_from=="aoi" and second_hop[0].source=="initial_profile" and second_hop[0].origin_observed_at==0,"A second hop changes the last speaker while retaining source and observation time")
		expect(second_hop[0].confidence<original.confidence and second_hop[0].confidence>=.5,"Confidence declines on each actual hearsay hop")
	var copied_back: Array = knowledge(sim.person("fumi"),"profile","osamu")
	expect(copied_back.size()==1 and copied_back[0].mode=="observed","A two-way dialogue does not immediately bounce a newly received profile back as fresh evidence")

	# An explicitly empty current profile map stays empty after a relationship changes.
	prepare(false)
	sim.person("fumi").known_profiles = {}
	sim.person("fumi").relationships.osamu.familiarity = .99
	expect(sim.save_game("user://test-knowledge-exchange-empty.json") and sim.load_game("user://test-knowledge-exchange-empty.json"),"An explicitly empty current profile map survives actual save/load")
	talk("fumi","aoi")
	expect(sim.person("fumi").known_profiles.is_empty() and not sim.cognition.knows_person(sim.person("aoi"),"osamu"),"Increased friendship does not reconstruct unobserved profiles after load")

	# A failed or unfinished meeting has no exchange, regardless of API hints.
	prepare()
	reply = sim.propose_meeting("fumi","aoi")
	expect(reply.status=="accept","The interruption fixture starts actual travel")
	if reply.status=="accept":
		var meeting: Dictionary = sim.meetings[-1]
		expect(exchange.exchange(sim.person("fumi"),sim.person("aoi"),[],[],meeting).is_empty(),"A travelling meeting cannot be treated as completed conversation")
		var forged: Dictionary = meeting.duplicate(true)
		forged.state = "engaged"
		forged.remaining = 0
		expect(exchange.exchange(sim.person("fumi"),sim.person("aoi"),[],[],forged).is_empty(),"A caller's forged completion cannot replace the actual meeting state")
		sim._finish_meeting(meeting,false)
		sim.meetings.erase(meeting)
	expect(not sim.cognition.knows_person(sim.person("aoi"),"osamu"),"Interrupted travel does not award the absent introduction")

	# Weak or forged speaker accounts cannot create useful introductions.
	prepare(false)
	speaker = sim.person("fumi")
	var weak: Dictionary = profile(speaker,"osamu","repair",.9)
	speaker.knowledge[-1].confidence = .51
	talk("fumi","aoi")
	expect(not sim.cognition.knows_person(sim.person("aoi"),"osamu"),"A profile too weak to remain credible after hearsay is not introduced")
	expect(not sim.cognition.share(speaker,sim.person("aoi"),"invented_event"),"A nonexistent source event cannot be shared")
	expect(sim.events.any(func(e): return e.event_id==weak.event_id),"The weak-account fixture still has a canonical event, isolating confidence from forgery")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-knowledge-exchange.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-knowledge-exchange-empty.json"))
	print("Knowledge exchange checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

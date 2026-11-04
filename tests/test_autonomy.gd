extends SceneTree

var checks := 0
var failures: Array[String] = []
var sim: LifeSimulation

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func state() -> Dictionary:
	return sim._encode({"people":sim.people,"meetings":sim.meetings,
		"events":sim.events,"rng":str(sim.rng.state),"work":sim.work_family.serialize(),
		"life":sim.life.serialize(),"social":sim.social.serialize(),"agenda":sim.agenda.serialize(),"serial":sim.event_serial}).duplicate(true)

func equivalent(a: Variant, b: Variant) -> bool:
	# JSON round-trips can change the final binary floating-point bit. Decisions,
	# identities, plans and RNG must be exact; continuous values tolerate 1e-10.
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-10
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

func make_free() -> void:
	sim.start_minute = 13*60
	sim.epoch_weekday = 5
	for p in sim.people:
		p.fatigue = .15
		p.hunger = .15
		p.quiet = .1

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	make_free()
	# New combinations use the same activity, real slots, travel and learning.
	var a: Dictionary = sim.person("aoi")
	var b: Dictionary = sim.person("fumi")
	var before: float = b.skills.get("repair",0)
	var cash: float = sim.work_family.household(a).cash
	var reply: Dictionary = sim.work_family.propose_project(a.id,b.id,"radio")
	expect(reply.status=="accept","A different pair can agree to a data-defined repair activity")
	expect(b.skills.get("repair",0)==before and sim.work_family.household(a).cash==cash,
		"Agreement alone grants neither practice nor a material charge")
	var limit := 0
	while not sim.meetings.is_empty() and sim.meetings[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	expect(not sim.meetings.is_empty() and sim.meetings[0].state=="engaged","The new pair actually reaches the repair table")
	expect(a.cognition_plan.stage=="execute" and b.cognition_plan.stage=="execute","Both residents' plans follow actual execution")
	var introduced_meeting: Dictionary = sim.meetings[0]
	sim.advance_minutes(45)
	expect(b.skills.get("repair",0)>before,"Completed work changes the new participant's actual repair skill")
	for minute in int(sim.interactions.config.timeout_minutes):
		if not sim.meetings.has(introduced_meeting): break
		sim.advance_minutes(1)
	var workflow: Dictionary = sim.interactions.sessions.get(introduced_meeting.get("interaction_id",""),{})
	var radio: Dictionary = sim.interactions.objects.get(workflow.get("object_id",""),{})
	expect(b.cognition_plan.stage=="completed" and not b.expectations.is_empty() and workflow.get("phase","")=="completed" and radio.get("state","")=="stored" and radio.get("container","")==sim.interactions.config.source_container and radio.get("holder","missing").is_empty() and radio.get("reserved_by","missing").is_empty(),"The completed plan leaves a situated expectation after returning the actual radio")
	expect(sim.cognition.known_skill(a,b.id,"repair")>before,"Actual participation reveals the practiced skill")
	# Enjoying a craft does not magically complete an unrelated repair wish.
	sim.reset()
	make_free()
	a = sim.person("aoi")
	expect(sim.work_family.propose_project("aoi","osamu","craft").status=="accept","Two interested residents can choose a different craft")
	limit = 0
	while not sim.meetings.is_empty() and sim.meetings[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	var cloth_meeting: Dictionary = sim.meetings[0] if not sim.meetings.is_empty() else {}
	# The 45 work minutes now sit between real material/tool handling phases.
	# Wait for the actual finished object rather than assuming wall time equals work.
	for minute in int(sim.sewing.config.timeout_minutes):
		if cloth_meeting.get("work_completed",false) or not sim.meetings.has(cloth_meeting): break
		sim.advance_minutes(1)
	var cloth_session: Dictionary = sim.sewing.sessions.get(cloth_meeting.get("sewing_id",""),{})
	var cloth_item: Dictionary = sim.sewing.objects.get(cloth_session.get("object_id",""),{})
	expect(cloth_meeting.get("work_completed",false) and cloth_item.get("kind","")=="pouch" and a.goal_progress==0 and a.private_project>=.18,"An actually finished unrelated craft advances private work rather than the radio wish")
	sim.reset()
	make_free()
	sim.person("osamu").hunger = .99
	expect(sim.work_family.propose_project("aoi","osamu","radio",true).status=="defer" and sim.meetings.is_empty(),
		"Another resident's initiative does not override an urgent need to eat")
	sim.reset()
	make_free()
	sim.work_family.propose_project("aoi","osamu","radio")
	sim.life._end_life(sim.person("osamu"))
	expect(sim.meetings.is_empty() and sim.person("aoi").cognition_plan.stage=="interrupted",
		"A farewell closes the living participant's unfinished plan")
	expect(not "また相談" in sim.planner.person_text(sim.person("aoi")),
		"A departed partner is not presented as someone available for a new plan")
	# A saved, partially travelled plan must replay both facts and decisions.
	sim.reset(941)
	make_free()
	sim.work_family.propose_project("aoi","osamu","radio",true)
	sim.advance_minutes(7.25)
	expect(sim.save_game("user://test-autonomy.json"),"A plan in progress can be saved")
	sim.advance_minutes(400)
	var future := state()
	expect(sim.load_game("user://test-autonomy.json"),"A plan in progress can be resumed")
	sim.advance_minutes(400)
	expect(equivalent(state(),future),"Knowledge, learning, plans, RNG and facts replay after save/load")
	# A real conversation can carry a source-preserving fact to a third person.
	sim.reset()
	var owner: Dictionary = sim.person("osamu")
	a = sim.person("aoi")
	b = sim.person("ritsu")
	b.interests.append("repair")
	b.current_goal = "修理について教わりたい"
	sim._learn_profile(a,owner,"repair")
	var profile: Dictionary = a.knowledge[-1]
	expect(not b.knowledge.any(func(k): return k.event_id==profile.event_id),"A third person does not instantly learn another household's exchange")
	expect(sim.cognition.known_skill(b,owner.id,"repair")==0,"The third person starts without knowledge of the craftsperson's repair skill")
	make_free()
	expect(sim.propose_meeting(a.id,b.id).status=="accept","A resident can arrange to talk to a third person")
	limit = 0
	while not sim.meetings.is_empty() and sim.meetings[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	sim.advance_minutes(25)
	var transmitted: Array = b.knowledge.filter(func(k): return k.event_id==profile.event_id)
	expect(transmitted.size()==1,"An actual completed conversation transmits a previously learned third-person fact")
	expect(not transmitted.is_empty() and transmitted[0].source==owner.id and transmitted[0].received_from==a.id,
		"The original person and the latest information source remain distinguishable")
	expect(sim.cognition.known_skill(b,owner.id,"repair")>0,"Actual conversation makes the introduced person's skill available to future planning")
	# Natural runs and a matched intervention are written as evidence for review.
	var report: Array = []
	var signatures := {}
	var total_autonomous := 0
	var autonomous_pouches := 0
	for seed_value in range(710,720):
		for intervention in [false,true]:
			sim.reset(seed_value,12)
			if intervention: sim.work_family.propose_project("aoi","osamu","radio")
			sim.advance_minutes(12*1440-sim.start_minute)
			var pairs := {}
			var autonomous := 0
			var learned := 0
			var kept := 0
			var postponed := 0
			var completed_help := 0
			for record in sim.agenda.records:
				if record.origin!="resident": continue
				if record.state=="kept": kept += 1
				if record.state=="postponed": postponed += 1
			for help in sim.work_family.supports:
				if help.get("autonomous",false) and help.state=="completed": completed_help += 1
			for p in sim.people:
				learned += p.expectations.size()
				for entry in p.plan_history:
					if entry.completed:
						pairs["%s:%s:%s"%[p.id,entry.partner,entry.activity]] = true
				for memory in p.memories:
					if memory.kind=="shared_time" and "一緒に取り組んだ" in memory.text:
						autonomous += 1
			var keys: Array = pairs.keys()
			var sewing_items: Array = []
			for item in sim.sewing.objects.values():
				if not item.material_used: continue
				sewing_items.append(sim._encode(item).duplicate(true))
				if not intervention and item.kind=="pouch" and not item.shown_to.is_empty() and item.container=="sewing_storage": autonomous_pouches+=1
			keys.sort()
			var signature := ",".join(keys)
			if not intervention:
				signatures[signature] = true
				total_autonomous += autonomous
			report.append({"seed":seed_value,"intervention":intervention,"completed_participant_experiences":autonomous,
				"recent_collaborations":keys,"learned_contexts":learned,"event_serial":sim.event_serial,
				"sewing_items":sewing_items,"sewing_sessions":sim._encode(sim.sewing.sessions).duplicate(true),
				"retained_resident_agreements_kept":kept,"retained_resident_agreements_postponed":postponed,
				"retained_autonomous_support_completed":completed_help})
			print("Autonomy sample %d intervention=%s collaborations=%d"%[seed_value,intervention,pairs.size()])
	expect(total_autonomous>0,"Residents can complete joint work without player intervention")
	expect(signatures.size()>1,"Different seeds produce different actual collaborators or activities")
	expect(autonomous_pouches>0,"Unmodified natural towns create, actually show and store owned pouches without player proposals")
	var output := "res://builds/autonomy"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output+"/autonomy-comparison.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"10 seeds, twelve residents, 12 representative days, matched intervention; not a human playtest","population":12,
		"rules":"authored game hypotheses, not measured human behavior","autonomous_stored_shown_pouches":autonomous_pouches,"samples":report},"  "))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-autonomy.json"))
	print("Autonomy checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

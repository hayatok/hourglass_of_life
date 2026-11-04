extends SceneTree

const SupportPlans = preload("res://game/scripts/resident_support_plans.gd")
var sim
var plans
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _setup(seed_value: int = 944) -> void:
	if is_instance_valid(sim): sim.free()
	sim = load("res://game/scripts/simulation.gd").new()
	root.add_child(sim)
	sim.reset(seed_value)
	var integrated = sim.get("support_plans")
	plans = integrated if integrated!=null else SupportPlans.new(sim)
	plans.reset()
	sim.start_minute = 870
	sim.elapsed = 30
	sim.epoch_weekday = 0
	for p in sim.people:
		p.fatigue = .1
		p.quiet = .1
		p.hunger = .1
		p.next_plan_minute = 999999
		p.support_next_attempt = 999999
		sim._choose_action(p)
	for id in ["ryo","rin"]:
		var p: Dictionary = sim.person(id)
		p.position = sim.SITES.home_ogawa
		p.place = "home_ogawa"
		p.path.clear()
		p.moving = false
	var r: Dictionary = sim.person("ryo")
	r.fatigue = .65
	r.support_next_attempt = 0
	sim.work_family.household(r).home_load = .8
	var n: Dictionary = sim.person("nagisa")
	n.position = sim.SITES.bakery_cafe
	n.place = "bakery_cafe"
	n.path.clear()
	n.moving = false
	n.action = "rest"
	n.remaining = 600
	n.routine_id = ""

func _advance(minutes: int) -> void:
	for step in minutes:
		sim.advance_minutes(1)
		if sim.get("support_plans")==null: plans.tick()

func _history(p: Dictionary) -> int:
	var count := 0
	for entry in p.get("plan_history",[]):
		if entry.activity in ["support_care","support_chores"]: count += 1
	return count

func _equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3: return a.distance_to(b)<.00001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _equivalent(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key],b[key]): return false
		return true
	return a==b

func run() -> void:
	_setup()
	var r: Dictionary = sim.person("ryo")
	var n: Dictionary = sim.person("nagisa")
	plans.tick()
	expect(sim.work_family.supports.size()==1,"A burdened caregiver autonomously asks a known trusted adult for help")
	if sim.work_family.supports.is_empty():
		sim.free();quit(1);return
	var help: Dictionary = sim.work_family.supports[0]
	expect(help.autonomous and help.initiator=="ryo" and help.giver=="nagisa","Autonomous support keeps its initiator and consenting helper")
	expect(r.cognition_plan.stage=="travel" and n.cognition_plan.kind=="support","Both people retain a real support plan while the helper travels")
	expect(sim._routine_at(r).get("id","")=="after_school_care","Accepting help alone does not release the caregiver")
	expect(r.expectations.is_empty() and n.expectations.is_empty(),"A support promise does not count as completed learning")
	_advance(1)
	expect(help.state=="travel" and sim._routine_at(r).get("id","")=="after_school_care","Care continues throughout the actual journey")
	var limit := 0
	while help.state=="travel" and limit<180:
		_advance(1);limit += 1
	expect(help.state=="active" and r.cognition_plan.stage=="execute","Actual arrival starts the plan's execution stage")
	expect(sim._routine_at(r).is_empty() and n.place=="home_ogawa","The arrived helper creates real free time for the original caregiver")
	_advance(110)
	expect(help.state=="completed" and help.support_plan_recorded,"A real care handover reaches a recorded conclusion")
	expect(_history(r)==1 and _history(n)==1,"Both participants record the support once")
	expect(not r.expectations.is_empty() and not n.expectations.is_empty() and n.skills.care>.55,"Actual support creates experience and gentle caregiver skill practice")
	var count: int = sim.work_family.supports.size()
	plans.tick();plans.tick()
	expect(_history(r)==1 and sim.work_family.supports.size()==count,"Synchronizing a finished help record does not duplicate outcomes or immediately ask again")
	expect(r.support_next_attempt>=help.requested+1440,"Receiving help has a saved cooldown that prevents constant delegation")
	# Household chores also use actual work rather than a promise's instant effect.
	_setup()
	sim.epoch_weekday = 5
	r = sim.person("ryo")
	sim._assign(r,"rest","home_ogawa",180,"家でひと息つく",r.position)
	sim.work_family.household(r).home_load = .95
	plans.tick()
	help = sim.work_family.supports[0]
	expect(help.kind=="chores" and r.cognition_plan.activity=="support_chores","A resident can autonomously ask for household chores rather than care coverage")
	var before_load: float = sim.work_family.household(r).home_load
	expect(is_equal_approx(before_load,.95),"Accepting a household request does not instantly remove the workload")
	limit = 0
	while help.state=="travel" and limit<180:
		_advance(1);limit += 1
	_advance(110)
	expect(help.state=="completed" and sim.work_family.household(r).home_load<before_load,"Actually doing household work reduces the shared burden and completes the plan")
	# Unknown or weakly trusted people and children are not adult substitutes.
	_setup()
	r = sim.person("ryo")
	r.relationships = {"fumi":{"trust":.9,"familiarity":.05,"ease":.8}}
	r.known_profiles.clear()
	plans.tick()
	expect(sim.work_family.supports.is_empty(),"High nominal trust without personal familiarity does not authorize an unknown helper")
	_setup()
	r = sim.person("ryo")
	r.relationships = {"nagisa":{"trust":.2,"familiarity":.95,"ease":.8}}
	plans.tick()
	expect(sim.work_family.supports.is_empty(),"The requester does not delegate responsibility to somebody they do not trust")
	_setup()
	r = sim.person("ryo")
	r.relationships = {"rin":r.relationships.rin}
	plans.tick()
	expect(sim.work_family.supports.is_empty(),"A child's high family familiarity never makes them an adult care substitute")
	# A chosen person can be unavailable; the planner does not inspect everybody
	# else's hidden need values to replace them with a compliant helper.
	_setup()
	sim.definitions.nagisa.routines.append({"id":"extra_shift","on_days":[0],"start_minute":900,"duration_minutes":60,"place":"bakery_cafe"})
	var serial: int = sim.event_serial
	plans.tick()
	expect(sim.work_family.supports.is_empty() and sim.event_serial>serial,"A busy trusted adult can decline the autonomous request")
	var after_reply: int = sim.event_serial
	var cooldown: int = sim.person("ryo").support_next_attempt
	plans.tick();sim.elapsed += 30;plans.tick()
	expect(sim.event_serial==after_reply and sim.person("ryo").support_next_attempt==cooldown,"Repeated checks under unchanged conditions do not spam the same request")
	_setup()
	sim.person("nagisa").hunger = .95
	r = sim.person("ryo")
	r.relationships.fumi = {"trust":.6,"familiarity":.6,"ease":.7}
	r.known_profiles.fumi = {"skills":{},"interests":[],"source":"initial_profile","observed_at":0}
	plans.tick()
	expect(sim.work_family.supports.is_empty(),"A helper's meal takes priority and does not trigger an omniscient search for somebody more compliant")
	_setup()
	sim.person("nagisa").fatigue = .8
	plans.tick()
	expect(sim.work_family.supports.is_empty(),"A helper already taking needed rest is not pulled out of it")
	_setup()
	sim.person("nagisa").hunger = .69
	plans.tick()
	expect(sim.work_family.supports.is_empty(),"A helper near their meal time does not promise travel and ninety more minutes of care before eating")
	# A need that changes after consent starts a real handoff, rather than
	# abandoning the child or trapping the helper indefinitely in care.
	_setup()
	plans.tick()
	help = sim.work_family.supports[0]
	limit = 0
	while help.state=="travel" and limit<180:
		_advance(1);limit += 1
	_advance(5)
	r = sim.person("ryo")
	n = sim.person("nagisa")
	r.position = sim.SITES.garden
	r.place = "garden"
	r.path.clear()
	r.moving = false
	r.action = "rest"
	r.routine_id = ""
	r.remaining = 600
	n.hunger = .9
	_advance(1)
	expect(help.state=="handoff" and n.support_id==help.id,"A helper who now needs food waits for an actual replacement instead of leaving the child")
	expect(sim._routine_at(n).get("id","")=="support_care" and sim._routine_at(r).get("id","")=="after_school_care","The handoff retains the helper's coverage and the returning adult's responsibility")
	expect(n.place=="home_ogawa" and sim.person("rin").place=="home_ogawa" and r.moving,"The child stays with the helper while the original caregiver really travels home")
	limit = 0
	while help.state in ["travel","active","handoff"] and limit<180:
		_advance(1);limit += 1
	expect(help.state=="interrupted" and n.support_id.is_empty() and r.place=="home_ogawa","Actual arrival finishes the interrupted handoff and releases the hungry helper")
	_advance(2)
	expect(n.action=="eat" and _history(n)==1,"The released helper can eat and records the shortened support only once")
	# A journey interrupted before arrival cannot create learned success.
	_setup()
	plans.tick()
	help = sim.work_family.supports[0]
	sim.work_family._end_support(help,false,"予定が変わった")
	plans.tick()
	expect(help.state=="interrupted" and help.support_work_minutes==0,"An interrupted journey records that no actual support was done")
	expect(sim.person("ryo").expectations.is_empty() and sim.person("nagisa").expectations.is_empty(),"An unfulfilled support plan does not invent experiential learning")
	expect(_history(sim.person("ryo"))==1 and not sim.person("ryo").plan_history[-1].completed,"An interrupted request remains an unsuccessful plan history entry")
	# A departed helper cannot remain an active plan or free the caregiver.
	_setup()
	plans.tick()
	help = sim.work_family.supports[0]
	sim.life._end_life(sim.person("nagisa"))
	_advance(1)
	expect(help.state=="interrupted" and sim.person("nagisa").cognition_plan.stage=="interrupted","A helper's death interrupts the actual support and both saved plans")
	expect(sim._routine_at(sim.person("ryo")).get("id","")=="after_school_care" and sim.person("nagisa").action=="remembered","A departed helper neither performs care nor releases the original caregiver")
	expect(sim.person("nagisa").expectations.is_empty() and _history(sim.person("ryo"))==1,"An interrupted journey with a departed helper invents no work experience or duplicate history")
	# Free time can be used for another real activity. Finishing support must not
	# overwrite that activity's newer cognition plan with the old help plan.
	_setup()
	plans.tick()
	help = sim.work_family.supports[0]
	limit = 0
	while help.state=="travel" and limit<180:
		_advance(1);limit += 1
	r = sim.person("ryo")
	var project_reply: Dictionary = sim.propose_project("ryo","fumi")
	expect(project_reply.status=="accept" and r.cognition_plan.get("kind","")=="project","Actual care coverage lets its recipient begin another real shared activity")
	var newer_plan: String = r.cognition_plan.meeting
	limit = 0
	while help.state in ["travel","active","handoff"] and limit<240:
		_advance(1);limit += 1
	expect(help.state=="completed" and r.cognition_plan.meeting==newer_plan and r.cognition_plan.kind=="project","Finishing the older support records it without overwriting a newer project plan")
	expect(_history(r)==1 and _history(sim.person("nagisa"))==1,"Concurrent use of freed time still records the original support once per participant")
	# Save during travel and replay through the completed support and cooldown.
	_setup(1994)
	plans.tick()
	_advance(7)
	var save_path := "user://test-autonomous-support.json"
	expect(sim.work_family.supports[0].state=="travel" and sim.save_game(save_path),"An autonomous support journey can be saved before arrival")
	_advance(220)
	var future_people: Array = sim.people.duplicate(true)
	var future_family: Dictionary = sim.work_family.serialize().duplicate(true)
	var future_events: Array = sim.events.duplicate(true)
	var future_rng: int = sim.rng.state
	expect(sim.load_game(save_path),"A saved support plan and cooldown load successfully")
	_advance(220)
	expect(_equivalent(sim.people,future_people) and _equivalent(sim.work_family.serialize(),future_family) and _equivalent(sim.events,future_events) and sim.rng.state==future_rng,"Saving during support preserves the same arrival, work, histories, learning and later random choices")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Resident support plan checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

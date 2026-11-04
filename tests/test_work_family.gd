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

func support_count(p: Dictionary) -> int:
	var count = 0
	for memory in p.memories:
		if memory.kind=="support": count += 1
	return count

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3: return a.distance_to(b)<.00001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	return a==b

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	# Income only accrues while doing the work, after the real journey.
	var ryo = sim.person("ryo")
	var h = sim.work_family.household(ryo)
	var earned_before = ryo.earned_today
	sim._assign(ryo,"work","workshop",30,"仕事を進める")
	sim.advance_minutes(1)
	expect(is_equal_approx(ryo.earned_today,earned_before),"Travelling to work does not count as paid work")
	var limit = 0
	while ryo.moving and limit<180:
		sim.advance_minutes(1)
		limit += 1
	var cash_at_arrival = h.cash
	sim.advance_minutes(10)
	expect(h.cash>cash_at_arrival and ryo.earned_today>0,"Actual time spent working earns household income")
	expect(ryo.goal_progress>0,"Work can advance a resident's own professional goal")
	sim.reset()
	ryo = sim.person("ryo")
	ryo.action = "work"
	ryo.fatigue = .1
	ryo.work_satisfaction = .3
	for minute in range(50): sim.work_family.activity_tick(ryo)
	var rested_meaning = ryo.work_satisfaction
	expect(rested_meaning>.3,"Meaningful work can improve a rested resident's sense of fulfilment")
	sim.reset()
	ryo = sim.person("ryo")
	ryo.action = "work"
	ryo.fatigue = .95
	ryo.work_satisfaction = .3
	for minute in range(50): sim.work_family.activity_tick(ryo)
	expect(ryo.work_satisfaction<rested_meaning,"The same job feels different when the person is already exhausted")
	# Household tasks can be chosen by any resident with the same conditions.
	sim.reset()
	ryo = sim.person("ryo")
	h = sim.work_family.household(ryo)
	h.home_load = .9
	sim._assign(ryo,"chores","home_ogawa",30,"家の用事を片付ける",ryo.position)
	sim.advance_minutes(20)
	expect(h.home_load<.85,"Doing household tasks reduces the actual shared workload")
	var options: Array = []
	sim.work_family.add_options(ryo,options)
	expect(options.any(func(o): return o.kind=="chores"),"A father can choose household tasks")
	options.clear()
	sim.work_family.add_options(sim.person("nagisa"),options)
	expect(options.any(func(o): return o.kind=="chores"),"Household tasks are also available to the other parent")
	h.cash = 0
	options.clear()
	sim.work_family.add_options(ryo,options)
	expect(options.any(func(o): return o.kind=="work"),"Low household reserves change a flexible worker's options")
	# Material purchases have a real cost, while unaffordable projects can prepare.
	var rin = sim.person("rin")
	h.material_days.clear()
	expect(sim.work_family.hobby_progress(rin)==0 and h.cash==0,"Unavailable materials do not silently consume nonexistent funds")
	h.cash = 10
	sim.work_family.hobby_progress(rin)
	var after_materials = h.cash
	sim.work_family.hobby_progress(rin)
	expect(after_materials==7 and h.cash==after_materials,"The same day's project materials are only purchased once")
	# A caregiver remains responsible until the helper and child are both home.
	sim.reset()
	sim.start_minute = 900
	sim.epoch_weekday = 0
	for p in sim.people:
		p.fatigue = .1
		p.quiet = .1
		sim._choose_action(p)
	ryo = sim.person("ryo")
	rin = sim.person("rin")
	for p in [ryo,rin]:
		p.position = sim.SITES.home_ogawa
		p.place = "home_ogawa"
		p.path.clear()
		p.moving = false
	var nagisa = sim.person("nagisa")
	nagisa.position = sim.SITES.bakery_cafe
	nagisa.place = "bakery_cafe"
	nagisa.moving = false
	var reply = sim.propose_support("ryo","nagisa")
	expect(reply.status=="accept","A rested trusted parent can agree to a care handover")
	expect(sim._routine_at(ryo).get("id","")=="after_school_care","Agreement alone does not free the current caregiver")
	expect(support_count(ryo)==0,"Promising help does not create a completed support memory")
	sim.advance_minutes(1)
	expect(sim.work_family.supports[0].state=="travel" and sim._routine_at(ryo).get("id","")=="after_school_care","The caregiver continues until the helper actually arrives")
	limit = 0
	while sim.work_family.supports[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	expect(sim.work_family.supports[0].state=="active","The helper reaches the child at the home")
	expect(sim._routine_at(ryo).is_empty(),"Actual care coverage frees the other parent's time")
	expect(nagisa.place=="home_ogawa" and rin.place=="home_ogawa","The support is anchored to the child's actual location")
	sim.advance_minutes(100)
	expect(sim.work_family.supports[0].state=="completed","Time spent caring can complete a real handover")
	expect(support_count(ryo)==1 and support_count(nagisa)==1,"Both adults remember the time they shared responsibility")
	# Finishing early waits for the other adult to return instead of abandoning care.
	sim.reset()
	sim.start_minute = 900
	sim.epoch_weekday = 0
	for p in sim.people:
		p.fatigue = .1
		p.quiet = .1
		sim._choose_action(p)
	for id in ["ryo","rin","nagisa"]:
		var p = sim.person(id)
		p.position = sim.SITES.home_ogawa
		p.place = "home_ogawa"
		p.path.clear()
		p.moving = false
	sim.propose_support("ryo","nagisa")
	limit = 0
	while sim.work_family.supports[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	sim.advance_minutes(89)
	ryo = sim.person("ryo")
	ryo.position = sim.SITES.bakery_cafe
	ryo.place = "bakery_cafe"
	ryo.moving = false
	ryo.path.clear()
	sim.advance_minutes(1)
	expect(sim.work_family.supports[0].state=="handoff","The helper waits when the other caregiver is still away")
	expect(sim._routine_at(sim.person("nagisa")).get("id","")=="support_care" and sim._routine_at(ryo).get("id","")=="after_school_care","Coverage stays in place while the other adult returns")
	sim.advance_minutes(90)
	expect(sim.work_family.supports[0].state=="completed","The handover completes after return or the end of the care period")
	# A working or exhausted helper can still refuse; children are not substitutes.
	sim.reset()
	sim.person("nagisa").fatigue = .95
	sim.work_family.household(sim.person("ryo")).home_load = .9
	expect(sim.propose_support("ryo","nagisa").status=="decline","Exhaustion remains a reason to decline help")
	expect(sim.propose_support("ryo","rin").status=="decline","An adult cannot hand care responsibility to the child")
	# Joint work consumes time and materials; an invitation is not project progress.
	sim.reset()
	var aoi = sim.person("aoi")
	var osamu = sim.person("osamu")
	expect(sim.propose_project("aoi","osamu").status=="accept","A radio project can be initiated by two free interested residents")
	expect(aoi.goal_progress==0 and sim.work_family.projects.radio==0,"Proposing joint work does not advance the project")
	limit = 0
	while sim.interactions.pose_for("aoi").get("phase","") not in ["take","carry_to_target","place","working"] and limit<180:
		sim.advance_minutes(1)
		limit += 1
	expect(not sim.meetings[0].materials_ready,"Materials are not consumed during the journey")
	var spending_before = sim.work_family.household(aoi).spent_today
	limit = 0
	while sim.interactions.pose_for("aoi").get("phase","")!="working" and limit<240:
		sim.advance_minutes(1);limit += 1
	expect(sim.interactions.pose_for("aoi").get("phase","")=="working","The same radio reaches the table before actual joint repair begins")
	sim.advance_minutes(1) # Entered the working phase; now execute its first real minute.
	expect(sim.meetings[0].materials_ready and sim.work_family.household(aoi).spent_today-spending_before>=4,"Materials are consumed when actual work begins")
	sim.advance_minutes(int(sim.meetings[0].remaining)-1)
	expect(aoi.goal_progress==0 and osamu.goal_progress==0,"Incomplete work has not completed a shared project step")
	sim.advance_minutes(1)
	expect(aoi.goal_progress>=.18 and osamu.goal_progress>=.18 and sim.work_family.projects.radio>=.18,"Finishing real joint work advances both participants' relevant wishes")
	limit = 0
	while not sim.meetings.is_empty() and limit<120:
		sim.advance_minutes(1);limit += 1
	expect(aoi.memories.any(func(memory): return "ラジオ" in memory.text and "一緒に取り組んだ" in memory.text),"After returning the radio, a work memory describes the actual shared activity")
	# Making the model together is also a legitimate way to spend family care time.
	sim.reset()
	sim.start_minute = 900
	sim.epoch_weekday = 0
	for p in sim.people: sim._choose_action(p)
	# This case verifies care while modelling, with the shared desk actually available.
	# A third person's solo hobby may otherwise reserve one of its two places.
	sim._assign(sim.person("nagisa"),"rest","home_ogawa",90,"食卓でひと息つく")
	ryo = sim.person("ryo")
	rin = sim.person("rin")
	for p in [ryo,rin]:
		p.position = sim.SITES.home_ogawa
		p.place = "home_ogawa"
		p.path.clear()
		p.moving = false
	expect(sim.propose_project("ryo","rin").status=="accept","A parent and child can work together during their home care time")
	limit = 0
	while sim.meetings[0].state=="travel" and limit<40:
		sim.advance_minutes(1)
		limit += 1
	sim.advance_minutes(45)
	expect(rin.goal_progress>=.18 and ryo.private_project>=.18,"Shared model-making advances the child's wish and the parent's private project")
	expect(ryo.care_minutes>=45 and ryo.goal_progress==0,"Family work counts as care without claiming professional job progress")
	# A day's household ledger and the complete support state persist together.
	sim.advance_minutes(660)
	expect(not sim.work_family.households.ogawa.ledger.is_empty(),"Midnight settles household income, support and expenses")
	expect(sim.save_game("user://test-work-family.json"),"Household state can be saved")
	var balance = sim.work_family.households.ogawa.cash
	sim.reset()
	expect(sim.load_game("user://test-work-family.json"),"Household state can be loaded")
	expect(is_equal_approx(balance,sim.work_family.households.ogawa.cash),"Household balances survive a save round trip")
	# Save in the middle of a real journey, rather than after every task ended.
	sim.reset(944)
	sim.start_minute = 900
	sim.epoch_weekday = 0
	for p in sim.people:
		p.fatigue = .1
		p.quiet = .1
		sim._choose_action(p)
	for id in ["ryo","rin"]:
		var p = sim.person(id)
		p.position = sim.SITES.home_ogawa
		p.place = "home_ogawa"
		p.path.clear()
		p.moving = false
	sim.person("nagisa").position = sim.SITES.bakery_cafe
	sim.person("nagisa").place = "bakery_cafe"
	sim.propose_support("ryo","nagisa")
	sim.advance_minutes(7.25)
	expect(sim.work_family.supports[0].state=="travel" and sim.save_game("user://test-work-family.json"),"An in-progress care journey can be saved")
	sim.advance_minutes(500)
	var future_people = sim.people.duplicate(true)
	var future_households = sim.work_family.serialize().duplicate(true)
	var future_social = sim.social.serialize().duplicate(true)
	var future_rng = sim.rng.state
	sim.load_game("user://test-work-family.json")
	sim.advance_minutes(500)
	expect(equivalent(sim.people,future_people) and equivalent(sim.work_family.serialize(),future_households) and equivalent(sim.social.serialize(),future_social) and sim.rng.state==future_rng,"An in-progress save resumes the same care, finances, social history and random choices")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-work-family.json"))
	print("Work/family checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

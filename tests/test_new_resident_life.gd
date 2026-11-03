extends SceneTree

const NEW_IDS = ["saki","haru","tomo","yui"]
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

func quiet_start() -> void:
	sim.reset(811,12)
	for d in sim.definitions.values(): d.routines = []
	for p in sim.people:
		p.next_plan_minute = 999999;p.support_next_attempt = 999999
		p.fatigue = .1;p.hunger = .1;p.quiet = .1
		sim._assign(p,"rest",sim.home_for(p),10000,"家でひと息つく",p.position)

func state() -> Dictionary:
	return {"people":sim.people,"events":sim.events,"meetings":sim.meetings,"rng":str(sim.rng.state),"work_family":sim.work_family.serialize(),"life":sim.life.serialize(),"social":sim.social.serialize(),"agenda":sim.agenda.serialize()}.duplicate(true)

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
	sim.reset(811,8)
	expect(sim.people.size()==8 and sim.person("saki").is_empty(),"The eight-resident fixture excludes new people and their directional relations")
	var unchanged := true
	for p in sim.people:
		if p.skills!=ResidentCognition.DEFAULT_PROFILES[p.id].skills or p.interests!=ResidentCognition.DEFAULT_PROFILES[p.id].interests: unchanged = false
	expect(unchanged,"The original eight authored skill and interest values are unchanged")
	var north: Dictionary = sim.work_family.households.north_house
	var mori: Dictionary = sim.work_family.households.mori
	var north_cash: float = north.cash;var mori_cash: float = mori.cash
	sim.work_family._settle_day()
	expect(north.cash==north_cash and mori.cash==mori_cash and north.ledger.is_empty() and mori.ledger.is_empty(),"Unoccupied expansion households are not charged or credited each day")
	sim.reset(811,12)
	expect(sim.people.size()==12 and sim.definitions.size()==12,"The expanded town contains twelve actual resident states")
	for id in NEW_IDS:
		var p: Dictionary = sim.person(id)
		var d: Dictionary = sim.definitions[id]
		expect(p.skills==d.skills and p.interests==d.interests and p.current_goal==d.goals[0] and p.goal_kind==d.goal_kind,id+": initial cognition and the personal goal come from authored data")
		expect(sim.home_for(p)==sim.HOME[d.household_id] and sim.work_family.household(p).cash>0,id+": the resident belongs to a real initialized household")
		var job: Dictionary = d.routines.filter(func(r):return r.id=="work_shift")[0]
		var weekday: int = int(job.on_days[0])
		expect(sim._authored_routine_at(p,int(job.start_minute)+1,weekday).id=="work_shift",id+": a real working day uses the authored shift")
		expect(sim._routine_action(job)=="work" and sim._authored_routine_at(p,90,0).id=="sleep",id+": work and overnight sleep retain their life-clock meaning")
	expect(sim.person("saki").known_profiles.has("fumi") and sim.person("fumi").known_profiles.has("saki"),"Sparse old/new directional acquaintances supply an actual bridge between the casts")
	expect(not sim.person("saki").known_profiles.has("aoi") and sim.person("saki").relationships.size()<sim.people.size()-1,"New residents do not start knowing everybody's private profile")
	# Work only earns money after actual travel ends. New rates must not use the
	# old ID-only earnings map's zero fallback.
	for id in NEW_IDS:
		quiet_start()
		var p: Dictionary = sim.person(id)
		var d: Dictionary = sim.definitions[id]
		var original_cast = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
		var source: Dictionary = original_cast.residents.filter(func(r):return r.id==id)[0]
		var job: Dictionary = source.routines.filter(func(r):return r.id=="work_shift")[0]
		var place: String = sim._place_for(p,job.place)
		sim._assign(p,"work",place,60,"引き受けた仕事に向かう")
		var earned: float = p.earned_today
		if p.moving:
			sim.advance_minutes(1)
			expect(is_equal_approx(p.earned_today,earned),id+": travelling to work is not paid working time")
		var count := 0
		while p.moving and count<360:sim.advance_minutes(1);count += 1
		expect(not p.moving and p.place==place,id+": the resident really reaches the workplace")
		earned = p.earned_today
		sim.advance_minutes(1)
		expect(is_equal_approx(p.earned_today-earned,float(d.work_income_per_minute)),id+": actual work receives the authored income rate")
		var household: Dictionary = sim.work_family.household(p)
		household.cash = 100;household.material_days.clear()
		p.goal_progress = 0;p.private_project = 0
		var step: float = sim.work_family.hobby_progress(p)
		var after_materials: float = household.cash
		sim.work_family.hobby_progress(p)
		expect(step>0 and is_equal_approx(after_materials,100-float(d.project_material_cost)) and household.cash==after_materials,id+": personal materials are purchased once per representative day")
		var project := {"skill":d.goal_skills[0],"goal_words":[]}
		expect(sim.work_family._advances_goal(p,project),id+": matching declared project skills can advance the goal without a name branch")
	# Achievement, later wishes and artifacts are not indexed by the old cast.
	sim.reset(811,12)
	var positions := {}
	for id in NEW_IDS:
		var p: Dictionary = sim.person(id)
		var d: Dictionary = sim.definitions[id]
		p.goal_progress = 1
		sim.life.goal_completed(p)
		var item: Dictionary = sim.life.legacy[-1]
		expect(item.owner==id and item.label==d.legacy_label and item.place==d.legacy_place,id+": actual completed goals can leave the authored artifact")
		positions[str(item.position)] = true
		sim.life._next_wish(p)
		expect(p.current_goal==d.next_wish and p.goal_kind==d.next_goal_kind and p.goal_progress==0,id+": the next wish is read from the resident definition")
	expect(positions.size()==4,"The new household artifacts have distinct authored positions")
	# Tick at the authored retirement boundary; this is a rule boundary test,
	# not evidence of playing every intervening representative day.
	sim.reset(811,12)
	var tomo: Dictionary = sim.person("tomo")
	var retirement: Dictionary = sim.definitions.tomo.retirement
	var year: int = int(retirement.age)-int(tomo.base_age)
	sim.elapsed = year*12*1440-sim.start_minute+540
	sim.life.tick()
	expect(tomo.career_retired and tomo.occupation==retirement.occupation and tomo.current_goal==retirement.goal,"A new resident's authored retirement changes role and wish")
	expect(sim.life.routines(tomo).all(func(r):return r.get("action","")!="work") and sim.life.routines(tomo).any(func(r):return r.id=="sleep"),"Retirement removes the actual shift while preserving daily sleep")
	var account: Dictionary = sim.work_family.household(tomo)
	var balance: float = account.cash
	sim.work_family._settle_day()
	var condition: Dictionary = sim.work_family.config.households.mori
	var expenses: float = float(condition.daily_basics)+float(condition.season_housing)
	expect(is_equal_approx(account.cash,balance+float(retirement.support_per_day)-expenses),"Retirement household support uses the new resident's authored value")
	sim.reset(811,12)
	for id in NEW_IDS:sim.person(id).base_age=int(sim.definitions[id].end_age)-1
	sim.elapsed = 12*1440-sim.start_minute
	sim.life.tick()
	expect(NEW_IDS.all(func(id):return not sim.person(id).alive),"All new residents use their authored life ending without missing-ID lookups")
	expect(sim.people.slice(0,8).all(func(p):return p.alive),"New life boundaries do not rewrite the original residents' independent ages")
	# The current twelve-person state, including new finances and cognition,
	# resumes the same next few representative hours.
	sim.reset(1182,12)
	sim.advance_minutes(120.25)
	var path := "user://test-new-resident-life.json"
	expect(sim.save_game(path),"A current twelve-person town can be saved")
	sim.advance_minutes(240)
	var future := state()
	expect(sim.load_game(path) and sim.people.size()==12,"Current save loading restores all twelve resident states")
	sim.advance_minutes(240)
	expect(equivalent(state(),future),"The expanded town resumes the same lives, finances, relationships, facts and RNG")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("New resident life checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

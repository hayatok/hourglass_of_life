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

func _has(options: Array, partner: String, key: String = "") -> bool:
	return options.any(func(o): return o.partner==partner and (key.is_empty() or o.project.key==key))

func _clear_day() -> void:
	for d in sim.definitions.values(): d.routines = []
	for p in sim.people:
		p.position = sim.SITES.square
		p.place = "square"
		p.destination = "square"
		p.path.clear()
		p.moving = false
		p.meeting_id = ""
		p.support_id = ""
		p.activity_spot = ""
		p.fatigue = .1
		p.quiet = .1
	for household in sim.work_family.households.values(): household.cash = 100.0

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	var library = preload("res://game/scripts/resident_activities.gd").new(sim)
	for pairing in [["aoi","osamu","radio"],["ryo","rin","model"],["nagisa","maho","bread"],["fumi","aoi","photo"],["ritsu","aoi","music"],["fumi","ritsu","photo"]]:
		var definition: Dictionary = library.definition(sim.person(pairing[0]),sim.person(pairing[1]))
		expect(definition.key==pairing[2],"Authored interests and skills select "+pairing[2]+" without pair rules")
	var radio: Dictionary = library.definition(sim.person("aoi"),sim.person("osamu"))
	expect(radio.teacher=="osamu" and radio.learner=="aoi","Roles follow the current skill difference")
	var first: Dictionary = sim.person("aoi").duplicate(true)
	var second: Dictionary = sim.person("osamu").duplicate(true)
	first.id = "new_student"
	second.id = "new_maker"
	var renamed: Dictionary = library.definition(first,second)
	expect(renamed.key==radio.key and renamed.teacher=="new_maker","New identities use the same activity and role definitions")
	first.skills.repair = .99
	var reversed: Dictionary = library.definition(first,second,"radio")
	expect(reversed.teacher=="new_student","Learning can reverse which participant teaches")
	expect(library.definition(first,second,"unknown").is_empty(),"Unknown activity definitions are rejected")
	sim._log("aoi","模型を見せてもらった","広場で作った模型を一緒に眺めた。")
	var event: Dictionary = sim.events[-1]
	event.participants = ["aoi","fumi"]
	sim.cognition.observe(sim.person("aoi"),event)
	sim.cognition.observe(sim.person("fumi"),event)
	expect("模型を見せてもらった" in library.topic(sim.person("aoi"),sim.person("fumi")),"Conversation can return to an event both people actually know")

	_clear_day()
	var aoi: Dictionary = sim.person("aoi")
	var osamu: Dictionary = sim.person("osamu")
	var before := JSON.stringify(sim._encode(sim.people))
	var funds: float = sim.work_family.household(aoi).cash
	var rng_state: int = sim.rng.state
	var options: Array = library.candidates(aoi)
	expect(_has(options,"osamu","radio"),"A known available collaborator and an actual worktable create a candidate")
	expect(JSON.stringify(sim._encode(sim.people))==before and sim.work_family.household(aoi).cash==funds and sim.rng.state==rng_state,"Inspecting candidates changes no reservations, needs, finances, knowledge, or randomness")
	var candidate: Dictionary = options.filter(func(o): return o.partner=="osamu")[0]
	expect(candidate.project.perceived and candidate.duration==45 and candidate.travel_minutes>=0,"An option identifies the perceived plan and its real duration and journey")

	var original_site: String = sim.activities.spots.radio_work_0.site
	sim.activities.spots.radio_work_0.site = "square"
	expect(not _has(library.candidates(aoi),"osamu","radio"),"An activity cannot use a seat belonging to another site")
	sim.activities.spots.radio_work_0.site = original_site
	sim.person("fumi").activity_spot = "radio_work_0"
	expect(not _has(library.candidates(aoi),"osamu","radio"),"A third person's reservation removes that worktable from possible plans")
	sim.person("fumi").activity_spot = ""
	sim.work_family.household(aoi).cash = 0
	expect(library.candidates(aoi).is_empty(),"Plans requiring materials do not propose unaffordable work")
	sim.work_family.household(aoi).cash = funds
	aoi.fatigue = .9
	expect(library.candidates(aoi).is_empty(),"Exhaustion leaves room for resting instead of a joint plan")
	aoi.fatigue = .1
	osamu.meeting_id = "another_commitment"
	expect(not _has(library.candidates(aoi),"osamu"),"A partner already meeting somebody else cannot be claimed")
	osamu.meeting_id = ""

	# Neither global skills nor a newly changed profile are revealed by candidate inspection.
	aoi.relationships.erase("osamu")
	aoi.known_profiles.erase("osamu")
	aoi.knowledge.clear()
	osamu.position = sim.SITES.workshop
	osamu.place = "workshop"
	expect(not _has(library.candidates(aoi),"osamu"),"An unknown distant person is not found through global profile search")
	sim._learn_profile(sim.person("fumi"),osamu,"repair")
	var introduction: String = sim.person("fumi").knowledge[-1].event_id
	expect(sim.cognition.share(sim.person("fumi"),aoi,introduction),"A known person's sourced account can introduce a potential collaborator")
	expect(_has(library.candidates(aoi),"osamu","radio"),"An introduced skill creates an opportunity that was absent before the information arrived")
	var known_before: float = sim.cognition.known_skill(aoi,"ryo","repair")
	sim.person("ryo").skills.repair = 1.0
	library.candidates(aoi)
	expect(sim.cognition.known_skill(aoi,"ryo","repair")==known_before,"A private skill change does not silently update somebody else's knowledge")

	# There is too little time to travel, work, and reach the next actual responsibility.
	sim.definitions.aoi.routines = [{"id":"classes","on_days":[0,1,2,3,4,5,6],"start_minute":sim.minute_of_day()+20,"duration_minutes":60,"place":"off_map_school"}]
	expect(library.candidates(aoi).is_empty(),"A short gap before a real commitment cannot hold a 45-minute shared activity")
	print("Resident activity checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

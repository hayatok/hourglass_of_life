extends SceneTree

const Cognition = preload("res://game/scripts/resident_cognition.gd")

class TownFixture:
	extends RefCounted
	var people: Array = []
	var definitions: Dictionary = {}
	var events: Array = []
	var elapsed: int = 60
	func _init() -> void:
		var cast = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
		for definition in cast.residents:
			definitions[definition.id] = definition.duplicate(true)
			people.append({"id":definition.id,"name":definition.name,"place":"square","fatigue":.15,"quiet":.1,"relationships":{}})
		for relation in cast.relationship_seeds:
			person(relation.from).relationships[relation.to] = relation.duplicate(true)
	func person(id: String) -> Dictionary:
		for p in people:
			if p.id==id: return p
		return {}

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var town = TownFixture.new()
	var cognition = Cognition.new(town)
	cognition.reset()
	var a: Dictionary = town.person("aoi")
	var f: Dictionary = town.person("fumi")
	var o: Dictionary = town.person("osamu")
	expect(a.knowledge.is_empty() and a.expectations.is_empty() and a.cognition_plan.is_empty(),"New residents begin without invented personal experience")
	expect(o.skills.repair>a.skills.repair and "photography" in f.interests,"Authored starting skills and interests distinguish the cast")
	var stranger = {"id":"new_neighbor"}
	cognition.upgrade_person(stranger)
	expect(stranger.has("skills") and stranger.has("interests"),"Unknown resident IDs receive generic cognition defaults")
	var preserved = {"id":"aoi","knowledge":[],"expectations":{},"skills":{},"interests":[],"cognition_plan":{"reason":"自分で考えたい"}}
	cognition.upgrade_person(preserved)
	expect(preserved.skills.is_empty() and preserved.interests.is_empty() and preserved.cognition_plan.reason=="自分で考えたい","Upgrade preserves intentional empty state and an existing plan")
	# An actual private event can only be observed by its owner or witnesses.
	var event = {"event_id":"event_1","minute":30,"resident_id":"aoi","fact":"completed_repair","value":{"item":"radio","helper":"osamu"},"title":"修理した","text":"ラジオを直した。"}
	town.events.append(event)
	expect(cognition.observe(a,event),"An event's participant can retain the event that actually occurred")
	expect(a.knowledge.size()==1 and f.knowledge.is_empty() and o.knowledge.is_empty(),"Personal observation does not give every resident the same knowledge")
	expect(not cognition.observe(f,event),"A private fact cannot be observed by somebody who was absent")
	expect(not cognition.observe(a,{"event_id":"invented","minute":10,"fact":"married","value":true}),"A caller cannot observe an event absent from the simulation ledger")
	var future = {"event_id":"event_2","minute":90,"resident_id":"aoi","fact":"future_success","value":true}
	town.events.append(future)
	expect(not cognition.observe(a,future),"A future event does not become current personal knowledge")
	var replacement = event.duplicate(true)
	replacement.value = {"item":"imaginary_wealth"}
	cognition.observe(a,replacement)
	expect(a.knowledge.size()==1 and a.knowledge[0].value.item=="radio","Repeated observation uses canonical facts without duplicating or replacing them")
	expect(not cognition.share(f,o,"event_1"),"A speaker cannot share knowledge they never acquired")
	expect(cognition.share(a,f,"event_1"),"A speaker can tell another person a known fact")
	expect(f.knowledge[0].source=="aoi" and f.knowledge[0].received_from=="aoi" and f.knowledge[0].mode=="told","A heard fact keeps its original source and its immediate speaker")
	expect(cognition.share(f,o,"event_1") and o.knowledge[0].source=="aoi" and o.knowledge[0].received_from=="fumi","Multiple sharing hops retain the original source")
	expect(o.knowledge[0].confidence<f.knowledge[0].confidence and f.knowledge[0].confidence<a.knowledge[0].confidence,"Hearsay does not gain certainty through repetition")
	# Knowing a person is not permission to read their changing live state.
	expect(is_equal_approx(cognition.known_skill(o,"osamu","repair"),o.skills.repair),"A resident knows their own current skills")
	expect(is_equal_approx(cognition.known_skill(f,"osamu","repair"),.9),"An authored close relation knows the initial skill profile")
	o.skills.repair = .99
	expect(is_equal_approx(cognition.known_skill(f,"osamu","repair"),.9),"Another person's practice does not update an acquaintance's knowledge automatically")
	expect(cognition.known_skill(a,"osamu","repair")==0 and cognition.known_interests(a,"osamu").is_empty(),"An unfamiliar person has no omniscient profile access")
	a.relationships.osamu.familiarity = .8
	cognition.upgrade_person(a)
	expect(cognition.known_skill(a,"osamu","repair")==0,"A dynamically increased relationship does not invent profile observations")
	var partial_profile = {"event_id":"profile_partial","minute":43,"resident_id":"osamu","participants":["osamu","fumi"],"fact":"profile","value":{"person":"osamu","interests":["repair"]}}
	town.events.append(partial_profile)
	expect(cognition.observe(f,partial_profile) and "repair" in cognition.known_interests(f,"osamu") and "craft" in cognition.known_interests(f,"osamu"),"Observing one interest does not erase other interests already known from the initial profile")
	var profile_event = {"event_id":"profile_1","minute":45,"resident_id":"osamu","participants":["osamu","fumi"],"source":"osamu","fact":"profile","value":{"person":"osamu","skills":{"repair":.99},"interests":["repair","music"]}}
	town.events.append(profile_event)
	expect(cognition.observe(f,profile_event) and is_equal_approx(cognition.known_skill(f,"osamu","repair"),.99),"A real profile observation updates the observer's specific skill knowledge")
	expect(cognition.share(f,a,"profile_1") and "music" in cognition.known_interests(a,"osamu"),"A sourced account can convey another person's known skill and interests")
	var old_profile = {"event_id":"profile_old","minute":20,"resident_id":"osamu","participants":["aoi","osamu"],"fact":"profile","value":{"person":"osamu","skills":{"repair":.4},"interests":["craft"]}}
	town.events.append(old_profile)
	cognition.observe(a,old_profile)
	expect(is_equal_approx(cognition.known_skill(a,"osamu","repair"),.99) and "music" in cognition.known_interests(a,"osamu"),"Receiving an old account later does not overwrite a newer profile observation")
	var older_save_person = {"id":"fumi","relationships":f.relationships.duplicate(true)}
	cognition.upgrade_person(older_save_person)
	expect(older_save_person.known_profiles.is_empty(),"Old-save upgrades do not reconstruct initial knowledge from current relationships")
	# Retained personal information remains shareable after the recent town log rolls over.
	town.events.clear()
	f.knowledge.clear()
	expect(cognition.share(a,f,"event_1"),"A remembered actual event is not forgotten solely because the global recent log was trimmed")
	# An experience affects the same activity, partner, place and condition.
	var personality: Dictionary = town.definitions.aoi.traits.duplicate(true)
	var before: float = cognition.action_bonus(a,"social","square","fumi")
	var sample: Dictionary = cognition.experience(a,"fumi","meet",{"place":"square","fatigue":.15},{"enjoyment":1.0,"burden":.05,"familiarity":1.0,"skill":"communication","practice":.03})
	var after: float = cognition.action_bonus(a,"social","square","fumi")
	expect(after>before and after-before<.02,"One pleasant encounter makes a small, bounded change in expected appeal")
	expect(is_equal_approx(cognition.action_bonus(a,"social_plan","square","fumi"),after),"A future conversation consults the same person's situated social experience")
	var project_before: float = cognition.action_bonus(a,"planned_project","workshop","osamu")
	cognition.experience(a,"osamu","project",{"place":"workshop","fatigue":.15},{"enjoyment":1.0,"burden":.05,"familiarity":1.0})
	expect(cognition.action_bonus(a,"planned_project","workshop","osamu")>project_before,"Actual shared work affects both immediate and future project choices")
	expect(is_equal_approx(sample.enjoyment,.56) and sample.samples==1,"Experience updates expectations gradually rather than replacing them")
	expect(a.skills.communication>0 and a.skills.communication<=.03,"Actual practice can increase a skill gradually")
	expect(town.definitions.aoi.traits==personality,"An encounter does not rewrite stable personality traits")
	var elsewhere: float = cognition.action_bonus(a,"social","workshop","fumi")
	expect(after>elsewhere,"Expectations retain the venue in which the encounter happened")
	var other_partner: float = cognition.action_bonus(a,"social","square","osamu")
	expect(after>other_partner,"A positive encounter is not automatically assigned to every partner")
	for step in 12:
		town.elapsed += 1
		cognition.experience(a,"fumi","meet",{"place":"square","fatigue":.9},{"enjoyment":.1,"burden":1.0,"familiarity":.2})
	var rested_bonus: float = cognition.action_bonus(a,"social","square","fumi")
	a.fatigue = .9
	var tired_bonus: float = cognition.action_bonus(a,"social","square","fumi")
	expect(tired_bonus<rested_bonus,"The same person and partner can have different expectations when tired")
	expect(tired_bonus>=-Cognition.MAX_BONUS and rested_bonus<=Cognition.MAX_BONUS,"Learning cannot overpower the existing life constraints with an unlimited bonus")
	expect(not cognition.explain(a).is_empty(),"A recent experience has a concise Japanese explanation")
	a.cognition_plan = {"reason":"写真の話を聞いてから、自分でも試したい","steps":["talk","practice"]}
	expect(cognition.explain(a)==a.cognition_plan.reason,"An active plan can explain the current intention")
	# Cognition uses resident-owned data, so JSON save replay has no hidden counters.
	var saved = JSON.stringify(a)
	var restored: Dictionary = JSON.parse_string(saved)
	cognition.upgrade_person(restored)
	expect(restored.knowledge.size()==a.knowledge.size() and restored.knowledge[0].source==a.knowledge[0].source,"A save round trip retains personal knowledge and provenance")
	expect(restored.cognition_plan==a.cognition_plan and restored.interests==a.interests,"A save round trip retains plans and authored interests")
	expect(is_equal_approx(cognition.action_bonus(restored,"social","square","fumi"),tired_bonus),"A restored resident makes the same expectation-based choice correction")
	expect(is_equal_approx(cognition.known_skill(restored,"osamu","repair"),cognition.known_skill(a,"osamu","repair")),"A save round trip retains what a person learned about another person's skills")
	cognition.experience(a,"fumi","meet",{"place":"square"},{"enjoyment":.5,"burden":.4})
	cognition.experience(restored,"fumi","meet",{"place":"square"},{"enjoyment":.5,"burden":.4})
	expect(is_equal_approx(cognition.action_bonus(restored,"social","square","fumi"),cognition.action_bonus(a,"social","square","fumi")),"Subsequent learning continues identically after restoration")
	_save_checks()
	print("Cognition checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

func _save_checks() -> void:
	var simulation_script = load("res://game/scripts/simulation.gd")
	var sim = simulation_script.new()
	root.add_child(sim)
	var path := "user://test-cognition-save.json"
	expect(sim.save_game(path),"An integrated town with cognition can be saved")
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(sim.load_game(path),"Valid cognition, session, seed and event serial data load successfully")
	# Each old schema can omit all the newly added state without fabricating a past.
	for schema in [1,2,3,4]:
		var legacy: Dictionary = original.duplicate(true)
		legacy.schema = schema
		legacy.erase("world_seed")
		legacy.erase("event_serial")
		legacy.erase("agenda")
		for person in legacy.people:
			for field in ["knowledge","known_profiles","skills","interests","expectations","cognition_plan","cognition_session","plan_history","next_plan_minute","preparing_agenda_id","support_next_attempt"]:
				person.erase(field)
		_write(path,legacy)
		expect(sim.load_game(path),"An older schema-%d save without cognition fields remains compatible"%schema)
		expect(sim.person("fumi").known_profiles.is_empty() and sim.person("fumi").knowledge.is_empty(),"Schema-%d migration adds empty knowledge without inventing observations"%schema)
	var bad: Array = []
	var payload: Dictionary = original.duplicate(true)
	payload.people[0].skills = {"repair":"expert"};bad.append(payload)
	payload = original.duplicate(true);payload.people[0].interests = {};bad.append(payload)
	payload = original.duplicate(true);payload.people[0].known_profiles = {"osamu":{"skills":[],"interests":[],"source":"initial_profile","observed_at":0}};bad.append(payload)
	payload = original.duplicate(true);payload.people[0].knowledge = [{}];bad.append(payload)
	payload = original.duplicate(true);payload.people[0].knowledge = [{"event_id":"bad","fact":"profile","source":"osamu","mode":"told","observed_at":0,"confidence":.5,"value":{"person":"osamu","skills":{"repair":2}}}];bad.append(payload)
	payload = original.duplicate(true);payload.people[0].expectations = {"invalid":[]};bad.append(payload)
	payload = original.duplicate(true);payload.people[0].cognition_plan = [];bad.append(payload)
	payload = original.duplicate(true);payload.people[0].cognition_plan = {"meeting":"x","activity":"radio","title":"修理","partner":"osamu","stage":"teleport","origin":"resident","started":0,"steps":[]};bad.append(payload)
	payload = original.duplicate(true);payload.people[0].cognition_session = {"kind":"rest","place":"home_ogawa","fatigue":null,"quiet":.1};bad.append(payload)
	payload = original.duplicate(true);payload.people[0].plan_history = [{"activity":"radio","partner":"osamu","day":0,"minute":0,"completed":"yes"}];bad.append(payload)
	payload = original.duplicate(true);payload.people[0].next_plan_minute = -.5;bad.append(payload)
	payload = original.duplicate(true);payload.world_seed = "not-a-seed";bad.append(payload)
	payload = original.duplicate(true);payload.event_serial = -1;bad.append(payload)
	payload = original.duplicate(true);payload.events.append(payload.events[0].duplicate(true));bad.append(payload)
	payload = original.duplicate(true);payload.events[0].participants = ["imaginary_neighbor"];bad.append(payload)
	payload = original.duplicate(true);payload.people[0].knowledge = [{"event_id":"future","fact":"something","source":"osamu","mode":"told","observed_at":100,"confidence":.5,"value":true}];bad.append(payload)
	payload = original.duplicate(true);payload.people[0].cognition_session.__vector3 = [0,0,0];bad.append(payload)
	payload = original.duplicate(true);payload.__vector3 = [0,0,0];bad.append(payload)
	var intro := {"event_id":"test_introduction","fact":"introduction","source":"fumi","mode":"observed","observed_at":0,"confidence":.95,"value":{"person":"osamu","via":"fumi","skill":"repair","profile_event":"event_1","profile_minute":0}}
	for problem in ["missing","person","via","skill","reference","future","fraction"]:
		var invalid: Dictionary = intro.duplicate(true)
		match problem:
			"missing": invalid.value.erase("profile_minute")
			"person": invalid.value.person = "absent"
			"via": invalid.value.via = "absent"
			"skill": invalid.value.skill = null
			"reference": invalid.value.profile_event = ""
			"future": invalid.value.profile_minute = 10
			"fraction": invalid.value.profile_minute = .5
		payload = original.duplicate(true); payload.people[0].knowledge = [invalid]; bad.append(payload)
	payload = original.duplicate(true);payload.events[0].origin_observed_at = -1;bad.append(payload)
	var before := _town_snapshot(sim)
	for index in bad.size():
		_write(path,bad[index])
		expect(not sim.load_game(path),"Malformed cognition payload %d is rejected"%index)
		expect(_town_snapshot(sim)==before,"Rejecting malformed payload %d leaves the running town unchanged"%index)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	sim.free()

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _town_snapshot(sim) -> String:
	return JSON.stringify(sim._encode({"people":sim.people,"events":sim.events,"meetings":sim.meetings,"elapsed":sim.elapsed,"rng":str(sim.rng.state),"seed":sim.world_seed,"serial":sim.event_serial,"social":sim.social.serialize(),"households":sim.work_family.serialize(),"life":sim.life.serialize()}))

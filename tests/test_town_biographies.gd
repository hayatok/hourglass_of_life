extends SceneTree

# Controlled authored-data and common-rule fixtures. These do not execute new
# home activities, consume their specialist materials, render or prove G3 play.
var checks: int = 0
var failures: Array[String] = []
var history: FamilyHistory
var residents: Dictionary = {}
var homes: Dictionary = {}
var authored: Dictionary

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> bool:
	checks+=1
	if not ok: failures.append(message);push_error(message)
	return ok

func person(id: String) -> Dictionary:
	var p: Dictionary = residents[id].duplicate(true)
	p.age=int(p.age_years);p.at_home=true;p.active_task="";p.fatigue=.3
	expect(history.attach(p,240),"The common module attaches the authored biography for "+id)
	return p

func context(elapsed: float = 0) -> Dictionary:
	return {"elapsed":elapsed,"adult_helpers":1,"other_deadline":false,"independent_child":false,"quiet_requested":false}

func actual_task(p: Dictionary, id: String = "task_1", kind: String = "personal_project") -> Dictionary:
	var project: Dictionary = history.project_for(p)
	return {"id":id,"kind":kind,"activity":project.activity if kind=="personal_project" else "tidy_personal_tools",
		"project_id":project.id,"fixture":project.use_fixture,"performed":0.0}

func authoring_and_merge() -> void:
	var ogawa: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FamilyHistory.SOURCE))
	expect(history.load_errors.is_empty() and history.definitions.profiles.size()==12 and authored.profiles.size()==9,"The two source files compose twelve profiles without a load error")
	for id in ogawa.profiles:
		expect(FamilyHistory._same(ogawa.profiles[id],history.definitions.profiles[id]),"The original Ogawa profile is not overwritten: "+id)
	var collision := FamilyHistory.new()
	var before: Dictionary = collision.definitions.duplicate(true)
	collision._merge_profiles({"nagisa":{"project":{"id":"wrong"}}})
	expect(not collision.load_errors.is_empty() and FamilyHistory._same(before,collision.definitions),"A duplicate authoring key is reported and cannot overwrite an existing family")
	var activities: Array = [];var items: Array = []
	for id in authored.profiles:
		var definition: Dictionary = authored.profiles[id]
		var source: Dictionary = residents[id]
		expect(definition.authored_age_years==source.age_years and definition.household_id==source.household_id and definition.occupation==source.occupation,"Age, household and current work match the existing resident: "+id)
		expect(definition.episodes.size() in [2,3] and not definition.current_conflict.is_empty() and not definition.responsibilities.is_empty() and not definition.commitments.is_empty(),"The person has a past, responsibilities and a present conflict: "+id)
		for episode in definition.episodes:
			expect(id in episode.participants and not episode.when.is_empty() and not episode.summary.is_empty() and not episode.influence.is_empty(),"The authored episode has a time, participant and present influence")
			for member in episode.participants+episode.known_to:
				expect(residents.has(member),"An episode refers to an existing resident without inventing a runtime person")
		var home: Dictionary = homes[definition.home_id]
		var fixtures: Dictionary = {}
		for fixture in home.fixtures: fixtures[fixture.id]=fixture
		expect(home.residents.any(func(row):return row.id==id),"The biography binds to the person's actual new home")
		var project: Dictionary = definition.project
		for key in ["activity_fixture","use_fixture","storage_fixture"]:
			expect(fixtures.has(project[key]),"The project refers to an existing home fixture: "+id+" / "+key)
		expect(project.execution_status=="authored_contract_not_integrated" and not project.requirements.is_empty() and project.operations.size()>=3,"The specialist activity declares actual prerequisites and operations, without claiming integration")
		expect(project.activity not in activities,"Each resident has a distinct authored activity rather than a renamed common note task")
		activities.append(project.activity)
		var sources: Array = []
		for item in definition.treasured_items:
			expect(item.provenance=="authored_fiction" and fixtures.has(item.fixture) and item.id not in items,"Important possessions have explicit authored provenance, a real storage fixture and unique identity")
			items.append(item.id);sources.append(item.id)
		expect(project.source_item_id in sources,"A project uses an explicitly authored existing source possession")
		for commitment in definition.commitments:
			expect(not commitment.label.is_empty() and id in commitment.known_to,"A promise names its meaning and who knows it")
			for member in commitment.known_to: expect(residents.has(member),"Promise knowledge refers to the existing cast")
		var p: Dictionary = person(id)
		expect(FamilyHistory._same(p.skills,source.skills) and FamilyHistory._same(p.routines,source.routines),"Attaching a biography does not rewrite skills or routine times")
		expect(p.life_history.observed.is_empty() and p.life_history.experience_minutes.is_empty() and p.life_history.projects[project.id].minutes==0 and p.life_history.projects[project.id].artifact.is_empty(),"Authored history and existing possessions grant no observed project result")

func current_situations_change_common_choices() -> void:
	var p: Dictionary = person("maho")
	p.fatigue=.2
	var fresh_score: float = float(history.choice(p,"quiet",context()).score_delta)
	p.fatigue=.8
	expect(float(history.choice(p,"quiet",context()).score_delta)>fresh_score+.14 and "休" in history.choice(p,"quiet",context()).choice_reason,"The same tired host protects rest based on authored overcommitment experience")
	var maker: Dictionary = person("osamu")
	var initial: float = float(history.choice(maker,"personal_project",context()).score_delta)
	var work: Dictionary = actual_task(maker);work.performed=15
	history.performed(maker,work,15,15)
	expect(float(history.choice(maker,"personal_project",context(15)).score_delta)>initial+.07,"A real underway repair strengthens its maker's wish to finish checking that object")
	history.set_deadline(maker,"radio_finish",30)
	expect("ラジオ" in history.choice(maker,"personal_project",context(15)).choice_reason and "下書き" not in history.choice(maker,"personal_project",context(15)).choice_reason,"Deadline explanations refer to the person's actual work, not a universal draft")
	var sewer: Dictionary = person("tomo")
	initial=float(history.choice(sewer,"tidy_tools",context()).score_delta)
	work=actual_task(sewer);work.performed=15;history.performed(sewer,work,15,15)
	expect(float(history.choice(sewer,"tidy_tools",context(15)).score_delta)>initial+.13,"Actually exposed sewing tools change the common tidy choice through the authored responsibility")
	var listener: Dictionary = person("fumi")
	var before: Dictionary = listener.duplicate(true)
	var contract: Dictionary = history.project_execution(listener)
	contract.operations.append("changed only in copy")
	history.choice(listener,"personal_project",context());history.project_execution(listener)
	expect(FamilyHistory._same(before,listener),"Choice and execution-plan queries are pure copies with no fabricated practice or state change")

func explicit_quiet_knowledge() -> void:
	var night_worker: Dictionary = person("ritsu")
	var student: Dictionary = person("aoi")
	var cast: Dictionary = {"ritsu":night_worker,"aoi":student}
	var monday: Dictionary = history.context_for("aoi",cast,{},330)
	var tuesday: Dictionary = history.context_for("aoi",cast,{},1770)
	expect(not monday.quiet_requested and tuesday.quiet_requested,"The declared post-shift quiet window follows its authored weekdays, rather than silencing the house every day")
	var ordinary: float = float(history.choice(student,"personal_project",context(1770)).score_delta)
	expect(float(history.choice(student,"personal_project",tuesday).score_delta)<ordinary-.19 and "休" in history.choice(student,"personal_project",tuesday).choice_reason,"A known quiet request changes noisy repair choices while preserving an independent response")
	expect(not history.context_for("osamu",cast,{},1770).quiet_requested,"An undeclared outsider does not read the housemate's private schedule")
	var known: Dictionary = history.context_for("aoi",cast,{},1770)
	night_worker.biography.values.independence=0;night_worker.biography.experience.personal_project=0
	expect(FamilyHistory._same(known,history.context_for("aoi",cast,{},1770)),"Other-person context ignores their private values and past competence")
	var parent: Dictionary = person("tomo")
	var teacher: Dictionary = person("yui")
	var at_work: Dictionary = history.context_for("yui",{"tomo":parent,"yui":teacher},{},600)
	expect(at_work.quiet_requested and float(history.choice(teacher,"personal_project",at_work).score_delta)<float(history.choice(teacher,"personal_project",context(600)).score_delta)-.24,"An adult child respects an explicitly shared parent's concentrated work time without being treated as a dependent child")

func actual_credit_and_json() -> void:
	for id in authored.profiles:
		var p: Dictionary = person(id)
		var project: Dictionary = history.project_for(p)
		var work: Dictionary = actual_task(p)
		history.completed(p,work,0)
		expect(p.life_history.observed.is_empty() and p.life_history.projects[project.id].artifact.is_empty(),"An unperformed specialist intention cannot make experience or a result")
		work.performed=15;history.performed(p,work,15,15)
		var state: Dictionary = p.duplicate(true)
		history.performed(p,work,15,15)
		expect(FamilyHistory._same(state,p),"Repeated actual credit is idempotent for "+id)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(p))
		expect(history.valid_person(saved,15) and FamilyHistory._same(saved,p),"New biography and unfinished project serialize without inventing or losing an object")
		# This is an explicit controlled executor-receipt fixture. It verifies
		# accounting only, not that the authored specialist operations are live.
		var remaining: float = float(project.required_minutes)-15
		work.performed=float(project.required_minutes);history.performed(p,work,remaining,float(project.required_minutes));history.completed(p,work,float(project.required_minutes))
		var artifact: Dictionary = p.life_history.projects[project.id].artifact
		expect(not artifact.is_empty() and artifact.owner==id and artifact.source_item_id==project.source_item_id and artifact.result_mode==project.result_mode,"The accounting result retains its actual owner and source-identity semantics")
		expect(history.valid_person(JSON.parse_string(JSON.stringify(p)),float(project.required_minutes)),"The completed accounting state passes current-format validation")
		var corrupt: Dictionary = p.duplicate(true);corrupt.life_history.projects[project.id].artifact.source_item_id="different_object"
		expect(not history.valid_person(corrupt,float(project.required_minutes)),"A saved result cannot be silently rebound to another physical source")
	expect(authored.profiles.aoi.project.artifact_kind=="radio_diagnosis_record" and authored.profiles.osamu.project.artifact_kind=="restored_radio","A novice's diagnosis is distinct from the experienced repairer's restored object")

func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	for p in source.residents: residents[p.id]=p
	for file in ["saeki-home.json","shared-house.json","north-house.json","mori-home.json"]:
		var home: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/homes/"+file));homes[home.house.id]=home
	authored=JSON.parse_string(FileAccess.get_file_as_string(FamilyHistory.TOWN_SOURCE))
	history=FamilyHistory.new()
	authoring_and_merge();current_situations_change_common_choices();explicit_quiet_knowledge();actual_credit_and_json()
	print("Town biographies checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

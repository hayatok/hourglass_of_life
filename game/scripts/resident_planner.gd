class_name ResidentPlanner
extends RefCounted

# Plans describe actual actions. They do not grant outcomes before execution.
var sim

func _init(owner_sim) -> void:
	sim = owner_sim

func reset() -> void:
	for p in sim.people:
		upgrade_person(p)

func upgrade_person(p: Dictionary) -> void:
	if not p.has("cognition_plan"): p.cognition_plan = {}
	if not p.has("plan_history"): p.plan_history = []
	if not p.has("next_plan_minute"): p.next_plan_minute = 45

func add_options(p: Dictionary, options: Array) -> void:
	if sim.elapsed<int(p.next_plan_minute): return
	for candidate in sim.resident_activities.candidates(p):
		var repeated := false
		for entry in p.plan_history:
			if entry.day==sim.day_index() and entry.activity==candidate.project.key:
				repeated = true
				break
		if not repeated: options.append(candidate)

func begin(p: Dictionary, candidate: Dictionary) -> bool:
	var result: Dictionary = sim.work_family.propose_project(p.id,candidate.partner,candidate.project.key,true)
	if result.status=="accept": return true
	p.next_plan_minute = sim.elapsed+60
	return false

func track(meeting: Dictionary) -> void:
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = sim.person(id)
		var other: String = meeting.b if id==meeting.a else meeting.a
		p.cognition_plan = {
			"meeting":meeting.id,"activity":meeting.project.key,"title":meeting.project.title,
			"partner":other,"stage":"travel","started":sim.elapsed,
			"origin":"resident" if meeting.get("autonomous",false) else "player",
			"steps":["相談する","合流する","一緒に取り組む","経験を振り返る"]
		}

func engaged(meeting: Dictionary) -> void:
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = sim.person(id)
		if p.cognition_plan.get("meeting","")==meeting.id:
			p.cognition_plan.stage = "execute"

func finish(meeting: Dictionary, completed: bool) -> void:
	if meeting.get("mode","")!="project": return
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = sim.person(id)
		if p.cognition_plan.get("meeting","")!=meeting.id: continue
		p.cognition_plan.stage = "completed" if completed else "interrupted"
		p.cognition_plan.finished = sim.elapsed
		p.next_plan_minute = sim.elapsed+(120 if completed else 90)
		p.plan_history.append({"activity":meeting.project.key,"partner":p.cognition_plan.partner,
			"day":sim.day_index(),"minute":sim.elapsed,"completed":completed})
		while p.plan_history.size()>24: p.plan_history.pop_front()

func person_text(p: Dictionary) -> String:
	var plan: Dictionary = p.get("cognition_plan",{})
	if plan.is_empty(): return ""
	var other: Dictionary = sim.person(plan.get("partner",""))
	if other.is_empty(): return ""
	var label: String = {"travel":"合流して取り組む予定","execute":"一緒に取り組んでいること",
		"completed":"一緒に進めたこと","interrupted":"また相談したいこと"}.get(plan.get("stage",""),"")
	if not sim.life.is_alive(other) and plan.get("stage","")=="interrupted": label = "途中で終わった予定"
	return "%s\n%sさんと、%s"%[label,other.name,plan.title]

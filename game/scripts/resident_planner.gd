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
	var immediate := false
	for candidate in sim.resident_activities.candidates(p):
		var repeated := false
		for entry in p.plan_history:
			if entry.day==sim.day_index() and entry.activity==candidate.project.key:
				repeated = true
				break
		if not repeated:
			options.append(candidate)
			immediate = true
	for record in sim.agenda.records:
		if record.state in ["planned","travel"] and p.id in [record.a,record.b]: return
	var contacts := _known_contacts(p)
	if contacts.is_empty(): return
	sim.tabletop.add_options(p,options,contacts)
	var other: Dictionary = contacts[0].person
	var common := {"place":"square","partner":other.id,"need":p.connection,
		"goal":sim.definitions[p.id].values.belonging,"relation":clampf(contacts[0].score,0,1),
		"role":.3,"habit":.2,"fun":sim.definitions[p.id].traits.extraversion,
		"cost":clampf(p.quiet*.6+p.fatigue*.3,0,1)}
	var conversation: Dictionary = common.duplicate(true)
	conversation.kind = "social_plan"
	conversation.reason = "%sさんと、近況を話す時間を相談したい"%other.name
	options.append(conversation)
	if immediate: return
	# A known person being busy now is a reason to discuss another time.
	var perceived: Dictionary = sim.resident_activities._perceived_partner(p,other)
	var project: Dictionary = sim.resident_activities.definition(p,perceived)
	if project.is_empty() or project.interest not in p.interests: return
	var later: Dictionary = common.duplicate(true)
	later.kind = "planned_project"
	later.project = project
	later.goal = .65
	later.reason = "%sさんと、%sに取り組める日時を相談したい"%[other.name,project.title]
	options.append(later)

func _known_contacts(p: Dictionary) -> Array:
	var result: Array = []
	var recent := {}
	for memory in p.memories:
		if memory.kind=="shared_time" and int(memory.minute)>sim.elapsed-1440:
			recent[memory.other] = int(recent.get(memory.other,0))+1
	for other in sim.people:
		if other.id==p.id or not sim.life.is_alive(other) or not sim.resident_activities._known_partner(p,other): continue
		var relation: Dictionary = sim.social.relation(p,other.id)
		var score: float = .4*float(relation.trust)+.35*float(relation.ease)+.25*float(relation.familiarity)
		# Keep the same ordered subtractions while scanning the growing personal
		# history only once, rather than once per possible partner.
		for encounter in int(recent.get(other.id,0)): score -= .07
		result.append({"person":other,"score":score})
	result.sort_custom(func(a,b): return a.score>b.score if not is_equal_approx(a.score,b.score) else str(a.person.id)<str(b.person.id))
	return result

func begin(p: Dictionary, candidate: Dictionary) -> bool:
	if candidate.kind=="play":
		var play: Dictionary = sim.tabletop.propose(p.id,candidate.partner,true)
		p.next_plan_minute = sim.elapsed+120
		return play.status=="accept"
	if candidate.kind in ["social_plan","planned_project"]:
		var activity: String = candidate.project.key if candidate.kind=="planned_project" else "social"
		var agreed: Dictionary = sim.agenda.propose(p.id,candidate.partner,activity,true)
		p.next_plan_minute = sim.elapsed+120
		if agreed.status=="accept":
			sim._choose_action(p)
			return true
		return false
	var result: Dictionary = sim.work_family.propose_project(p.id,candidate.partner,candidate.project.key,true)
	if result.status=="accept": return true
	p.next_plan_minute = sim.elapsed+60
	return false

func track(meeting: Dictionary) -> void:
	var project: Dictionary = meeting.get("project",{})
	var activity: String = project.get("key","social")
	var title: String = project.get("title","近況を話す時間")
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = sim.person(id)
		var other: String = meeting.b if id==meeting.a else meeting.a
		p.cognition_plan = {
			"meeting":meeting.id,"activity":activity,"title":title,
			"partner":other,"stage":"travel","started":sim.elapsed,
			"origin":"resident" if meeting.get("autonomous",false) or meeting.get("spontaneous",false) else "player",
			"steps":["相談する","合流する","一緒に過ごす","経験を振り返る"],
			"kind":"project" if not project.is_empty() else "social"
		}
		var introduction: Dictionary = sim.social.knowledge_exchange.introduction(p,other)
		if not introduction.is_empty() and (project.is_empty() or introduction.skill==project.get("skill","")):
			if float(sim.social.relation(p,other).familiarity)<.4:
				p.cognition_plan.reason = sim.social.knowledge_exchange.introduction_reason(p,other)
				p.cognition_plan.introduction_event = introduction.event_id

func engaged(meeting: Dictionary) -> void:
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = sim.person(id)
		if p.cognition_plan.get("meeting","")==meeting.id:
			p.cognition_plan.stage = "execute"

func finish(meeting: Dictionary, completed: bool) -> void:
	for id in [meeting.a,meeting.b]:
		var p: Dictionary = sim.person(id)
		if p.cognition_plan.get("meeting","")!=meeting.id: continue
		p.cognition_plan.stage = "completed" if completed else "interrupted"
		p.cognition_plan.finished = sim.elapsed
		p.next_plan_minute = sim.elapsed+(120 if completed else 90)
		p.plan_history.append({"activity":p.cognition_plan.activity,"partner":p.cognition_plan.partner,
			"day":sim.day_index(),"minute":sim.elapsed,"completed":completed})
		while p.plan_history.size()>24: p.plan_history.pop_front()

func person_text(p: Dictionary) -> String:
	var plan: Dictionary = p.get("cognition_plan",{})
	if plan.is_empty(): return ""
	if plan.get("kind","")=="support": return sim.support_plans.person_text(p)
	var other: Dictionary = sim.person(plan.get("partner",""))
	if other.is_empty(): return ""
	var label: String = {"travel":"合流して取り組む予定","execute":"一緒に取り組んでいること",
		"completed":"一緒に進めたこと","interrupted":"また相談したいこと"}.get(plan.get("stage",""),"")
	if plan.get("kind","")=="social":
		label = {"travel":"会いに向かっている","execute":"一緒に話している","completed":"話して過ごした時間","interrupted":"また時間を相談したいこと"}.get(plan.get("stage",""),"")
	if plan.get("kind","")=="play":
		label = {"travel":"遊ぶ机へ向かっている","execute":"交互に考えながら遊んでいる","completed":"一緒に遊んだ時間","interrupted":"切り上げた遊び"}.get(plan.get("stage",""),"")
	if not sim.life.is_alive(other) and plan.get("stage","")=="interrupted": label = "途中で終わった予定"
	return "%s\n%sさんと、%s"%[label,other.name,plan.title]

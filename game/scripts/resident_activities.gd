class_name ResidentActivities
extends RefCounted

# Candidate inspection never reserves a seat, charges money, or consumes RNG.
var sim
var definitions: Array = []

func _init(simulation) -> void:
	sim = simulation
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/resident-activities.json"))
	definitions = data.activities

func definition(a: Dictionary, b: Dictionary, preferred_key: String = "") -> Dictionary:
	if a.is_empty() or b.is_empty() or a.get("id","")==b.get("id",""): return {}
	var best: Dictionary = {}
	var best_score := -INF
	for authored in definitions:
		if not preferred_key.is_empty() and authored.key!=preferred_key: continue
		var score := _fit(a,b,authored)
		if score<=best_score: continue
		best_score = score
		best = authored.duplicate(true)
	if best.is_empty(): return {}
	var offset: Array = best.center_offset
	best.center = sim.SITES[best.place]+Vector3(float(offset[0]),float(offset[1]),float(offset[2]))
	var first_skill := _skill(a,best.skill)
	var second_skill := _skill(b,best.skill)
	best.teacher = a.id if first_skill>second_skill+.08 else (b.id if second_skill>first_skill+.08 else "")
	best.learner = (b.id if best.teacher==a.id else a.id) if not best.teacher.is_empty() else ""
	best.fit = best_score
	best.roles = {a.id:"collaborator",b.id:"collaborator"}
	if not best.teacher.is_empty():
		best.roles[best.teacher] = "teacher"
		best.roles[best.learner] = "learner"
	return best

func candidates(p: Dictionary) -> Array:
	var result: Array = []
	if not _free(p): return result
	var partners: Array = sim.people.duplicate()
	partners.sort_custom(func(a,b): return str(a.id)<str(b.id))
	for other in partners:
		if p.id==other.id or not _free(other) or not _known_partner(p,other): continue
		var perceived := _perceived_partner(p,other)
		var best: Dictionary = {}
		var best_fit := -INF
		for authored in definitions:
			var project := definition(p,perceived,authored.key)
			if project.is_empty() or project.fit<=best_fit: continue
			if not _interested(p,project.interest) and not _interested(perceived,project.interest): continue
			var estimate := _feasible(p,other,project)
			if estimate.is_empty(): continue
			best_fit = float(project.fit)
			project.perceived = true
			var interest := .5*float(_interested(p,project.interest))+.5*float(_interested(perceived,project.interest))
			var relation: Dictionary = sim.social.relation(p,other.id)
			var reason := "%sさんと、%sを進めてみたい"%[other.name,project.title]
			if project.learner==p.id: reason = "%sさんに、%sを教わってみたい"%[other.name,project.title]
			elif project.teacher==p.id: reason = "%sさんと、知っていることを分け合いながら%sを進めたい"%[other.name,project.title]
			var introduction: Dictionary = sim.social.knowledge_exchange.introduction(p,other.id)
			if not introduction.is_empty() and introduction.skill==project.skill and relation.familiarity<.4:
				reason = sim.social.knowledge_exchange.introduction_reason(p,other.id)+"。"+reason
			best = {"kind":"joint_work","place":project.place,"partner":other.id,"project":project,
				"need":maxf(.3,float(p.get("connection",0))),"goal":clampf(.35+.35*interest+.2*_goal_match(p,project),0,1),
				"relation":clampf(float(relation.ease)*.5+float(relation.trust)*.5,0,1),"role":.5,
				"habit":.2,"fun":clampf(.35+.4*interest,0,1),
				"cost":clampf(float(p.get("fatigue",0))*.5+float(estimate.travel_minutes)/240.0,0,1),
				"reason":reason,"travel_minutes":estimate.travel_minutes,"duration":project.duration}
		if not best.is_empty(): result.append(best)
	return result

func topic(a: Dictionary, b: Dictionary) -> String:
	# A speaker may bring a fact they actually hold; a shared fact takes precedence.
	var other_facts := {}
	for fact in b.get("knowledge",[]): other_facts[fact.get("event_id","")] = true
	for fact in _recent_knowledge(a):
		if not other_facts.has(fact.get("event_id","")): continue
		var text := _fact_topic(fact)
		if not text.is_empty(): return text
	var project := definition(a,b)
	if not project.is_empty(): return project.topic
	return "最近の暮らしと、それぞれがやってみたいこと"

func _skill(p: Dictionary, skill: String) -> float:
	return clampf(float(p.get("skills",{}).get(skill,0)),0,1)

func _interested(p: Dictionary, interest: String) -> bool:
	return interest in p.get("interests",[])

func _goal_match(p: Dictionary, activity: Dictionary) -> float:
	var goal: String = p.get("current_goal","")
	for word in activity.goal_words:
		if word in goal: return 1.0
	return 0.0

func _fit(a: Dictionary, b: Dictionary, activity: Dictionary) -> float:
	var first := float(_interested(a,activity.interest))
	var second := float(_interested(b,activity.interest))
	var skill_a := _skill(a,activity.skill)
	var skill_b := _skill(b,activity.skill)
	var engaged := maxf(first,second)
	# Accessible activities get a small authored preference; shared interests dominate it.
	return .5*minf(first,second)+.3*engaged+.15*maxf(skill_a,skill_b)+.05*absf(skill_a-skill_b)+.2*maxf(_goal_match(a,activity),_goal_match(b,activity))+float(activity.selection_bonus)*engaged

func _free(p: Dictionary) -> bool:
	if float(p.get("hunger",1))>.75: return false
	if p.get("action","")=="eat" and float(p.get("action_elapsed",0))<20: return false
	return sim.life.is_alive(p) and not p.get("moving",false) and p.get("meeting_id","").is_empty() and p.get("support_id","").is_empty() and float(p.get("fatigue",1))<=.8

func _known_partner(p: Dictionary, other: Dictionary) -> bool:
	if float(sim.social.relation(p,other.id).familiarity)>=.1: return true
	if p.place==other.place and p.position.distance_to(other.position)<=2.8: return true
	for fact in p.get("knowledge",[]):
		if fact.get("fact","")=="profile" and fact.get("value",{}) is Dictionary:
			if fact.value.get("person","")==other.id and float(fact.get("confidence",0))>=.5:
				return true
		if fact.get("mode","")!="observed" or int(fact.get("observed_at",-1440))<sim.elapsed-720: continue
		if fact.get("source","")==other.id: return true
	return false

func _perceived_partner(p: Dictionary, other: Dictionary) -> Dictionary:
	var perceived := {"id":other.id,"name":other.name,"skills":{},"interests":[],"current_goal":""}
	var cognition = sim.get("cognition")
	if cognition==null: return perceived
	var known: Dictionary = cognition.known_profile(p,other.id)
	perceived.interests = known.interests
	for authored in definitions:
		perceived.skills[authored.skill] = float(known.skills.get(authored.skill,0))
	return perceived

func _feasible(a: Dictionary, b: Dictionary, project: Dictionary) -> Dictionary:
	var hypothetical := {"mode":"project","project":project}
	for p in [a,b]:
		if not sim.work_family.meeting_compatible(p,hypothetical): return {}
	if sim.work_family.household(a).cash<sim.work_family.project_material_cost(a,b,project): return {}
	if project.key=="craft" and not sim.sewing.available(a,b,project): return {}
	var pair: Array = sim.activities.pair_for(project.key,project.center,[a.id,b.id])
	if pair.size()!=2: return {}
	for spot in pair:
		if spot.site!=project.place or "joint_work" not in spot.actions: return {}
	var travel_times: Array = []
	for index in 2:
		var p: Dictionary = a if index==0 else b
		travel_times.append(_travel(p.position,p.place,pair[index].approach,project.place))
	var travel: int = maxi(travel_times[0],travel_times[1])
	for index in 2:
		var p: Dictionary = a if index==0 else b
		var next: Dictionary = sim._next_commitment(p)
		var return_minutes := 0
		if not next.get("id","").is_empty():
			var absolute: int = sim.start_minute+sim.elapsed+int(next.minutes)
			var routine: Dictionary = sim._routine_at(p,absolute%1440,(sim.epoch_weekday+int(absolute/1440.0))%7)
			if not routine.is_empty():
				var destination: String = sim._place_for(p,routine.place)
				return_minutes = _travel(pair[index].approach,project.place,sim.SITES[destination],destination)
		var duration: int=sim.sewing.planned_minutes(a,b,project) if project.key=="craft" else int(project.duration)
		var total: int=travel+duration+return_minutes+1
		if total>=int(next.minutes): return {}
		if project.key=="craft" and float(p.hunger)+total*sim.HUNGER_PER_MINUTE>.78: return {}
	return {"travel_minutes":travel,"spots":[pair[0].id,pair[1].id]}

func _travel(origin: Vector3, place: String, target: Vector3, destination: String) -> int:
	var distance := 0.0
	var previous := origin
	for point in sim.route(origin,place,target,destination):
		distance += previous.distance_to(point)
		previous = point
	return int(ceil(distance/sim.WALK_METERS_PER_MINUTE))

func _recent_knowledge(p: Dictionary) -> Array:
	var facts: Array = p.get("knowledge",[]).duplicate()
	facts.sort_custom(func(a,b): return int(a.get("observed_at",0))>int(b.get("observed_at",0)))
	return facts

func _fact_topic(fact: Dictionary) -> String:
	if int(fact.get("observed_at",0))>sim.elapsed or float(fact.get("confidence",0))<.5: return ""
	var title: String = str(fact.get("fact",""))
	if title.is_empty() or title in ["profile","activity","routine","greeting"]: return ""
	if fact.get("value") is Dictionary: title = str(fact.value.get("title",title))
	var readable := false
	for index in title.length():
		var character := title.unicode_at(index)
		if (character>=0x3040 and character<=0x30ff) or (character>=0x3400 and character<=0x9fff): readable = true
	if not readable: return ""
	return "この前の「%s」"%title.left(30)

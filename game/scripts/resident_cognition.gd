class_name ResidentCognition
extends RefCounted

# Knowledge is an individual's record of an event that already exists in the
# simulation. Expectations are authored, bounded learning rules, not measured
# models of real people. All mutable state lives on the resident for save replay.
const LEARNING_RATE = .12
const MAX_BONUS = .06
const KNOWLEDGE_LIMIT = 128
const EXPECTATION_LIMIT = 96
const DEFAULT_PROFILES = {
	"nagisa":{"skills":{"baking":.80,"craft":.30,"care":.55},"interests":["baking","family"]},
	"ryo":{"skills":{"design":.80,"model":.55,"care":.65},"interests":["design","model","family"]},
	"rin":{"skills":{"model":.20,"craft":.15},"interests":["model","discovery"]},
	"osamu":{"skills":{"repair":.90,"craft":.80},"interests":["repair","craft"]},
	"fumi":{"skills":{"photography":.25,"communication":.75},"interests":["photography","walking"]},
	"maho":{"skills":{"hospitality":.80,"baking":.35,"communication":.70},"interests":["hospitality","baking","community"]},
	"ritsu":{"skills":{"music":.70,"craft":.25},"interests":["music","solitude"]},
	"aoi":{"skills":{"repair":.20,"craft":.40},"interests":["repair","craft","learning"]}
}
const INTEREST_LABELS = {"baking":"パンづくり","family":"家族との時間","design":"デザイン","model":"模型づくり","discovery":"新しい発見","repair":"修理","craft":"ものづくり","photography":"写真","walking":"散歩","hospitality":"店で人を迎えること","community":"町の人との交流","music":"音楽","solitude":"静かな時間","learning":"学ぶこと"}
const ACTION_LABELS = {"social":"話した","hobby":"好きなことに取り組んだ","photo":"写真を撮った","work":"仕事をした","care":"家族と過ごした","rest":"休んだ","eat":"食事をした","chores":"家の用事をした","legacy":"記録を読んだ"}

var sim

func _init(simulation) -> void:
	sim = simulation

func reset() -> void:
	for p in sim.people:
		upgrade_person(p)
		# reset is called after the authored starting relationships are installed.
		# Later friendship must not silently reveal a person's live skills.
		for other_id in p.get("relationships",{}):
			if float(p.relationships[other_id].get("familiarity",0))<.1 or p.known_profiles.has(other_id): continue
			var profile := _initial_profile(other_id)
			p.known_profiles[other_id] = {"skills":profile.skills,"interests":profile.interests,"source":"initial_profile","observed_at":0}

func upgrade_person(p: Dictionary) -> void:
	var definition: Dictionary = sim.definitions.get(p.get("id",""),{})
	var profile: Dictionary = DEFAULT_PROFILES.get(p.get("id",""),{})
	# In particular, an intentionally empty collection in a save stays empty.
	if not p.has("knowledge"): p.knowledge = []
	if not p.has("expectations"): p.expectations = {}
	if not p.has("skills"): p.skills = definition.get("skills",profile.get("skills",{"craft":.10})).duplicate(true)
	if not p.has("interests"): p.interests = definition.get("interests",profile.get("interests",["discovery"])).duplicate(true)
	if not p.has("cognition_plan"): p.cognition_plan = {}
	# Old saves receive an empty map. Reconstructing from their current relations
	# would invent profile observations that never occurred in that saved town.
	if not p.has("known_profiles"): p.known_profiles = {}

func known_skill(observer: Dictionary, other_id: String, skill: String) -> float:
	upgrade_person(observer)
	if observer.get("id","")==other_id: return float(observer.skills.get(skill,0))
	var known := _known_profile(observer,other_id)
	return float(known.skills.get(skill,0))

func known_interests(observer: Dictionary, other_id: String) -> Array:
	upgrade_person(observer)
	if observer.get("id","")==other_id: return observer.interests.duplicate()
	return _known_profile(observer,other_id).interests.duplicate()

func known_profile(observer: Dictionary, other_id: String) -> Dictionary:
	upgrade_person(observer)
	if observer.id==other_id:
		return {"skills":observer.skills.duplicate(true),"interests":observer.interests.duplicate(true)}
	return _known_profile(observer,other_id)

func knows_person(observer: Dictionary, other_id: String) -> bool:
	upgrade_person(observer)
	if observer.id==other_id or observer.known_profiles.has(other_id): return true
	for known in observer.knowledge:
		if known.get("fact","")!="profile" or not known.get("value") is Dictionary: continue
		if known.value.get("person","")==other_id and float(known.confidence)>=.5 and int(known.observed_at)<=sim.elapsed: return true
	return false

func skill_evidence(observer: Dictionary, other_id: String, skill: String) -> Dictionary:
	upgrade_person(observer)
	var result: Dictionary = {}
	var initial: Dictionary = observer.known_profiles.get(other_id,{})
	if initial.get("skills",{}).has(skill):
		result = {"level":initial.skills[skill],"origin_observed_at":int(initial.get("observed_at",0)),"confidence":.95}
	for known in observer.knowledge:
		if known.get("fact","")!="profile" or not known.get("value") is Dictionary: continue
		if known.value.get("person","")!=other_id or not known.value.get("skills",{}).has(skill): continue
		if int(known.observed_at)>sim.elapsed: continue
		var origin: int = int(known.get("origin_observed_at",known.observed_at))
		if not result.is_empty():
			if origin<int(result.origin_observed_at): continue
			if origin==int(result.origin_observed_at) and float(known.confidence)<=float(result.confidence): continue
		result = {"level":known.value.skills[skill],"origin_observed_at":origin,"confidence":float(known.confidence)}
	return result

func observe(p: Dictionary, event: Dictionary) -> bool:
	upgrade_person(p)
	var actual := _existing_event(event)
	if actual.is_empty() or int(actual.get("minute",0))>int(sim.elapsed): return false
	var observer: String = p.get("id","")
	var owner: String = actual.get("resident_id",actual.get("source",""))
	if actual.has("witnesses"):
		if observer not in actual.witnesses and observer!=owner: return false
	elif not owner.is_empty() and observer!=owner and observer not in actual.get("participants",[]) and not actual.get("public",false):
		return false
	var event_id: String = actual.get("event_id","")
	if event_id.is_empty():
		# Old events have no serial; attach an ID once to their canonical record.
		event_id = "past_%d_%d_%d"%[int(actual.get("minute",0)),sim.events.find(actual),str(actual).hash()]
		actual.event_id = event_id
	var original_minute: int = int(actual.get("origin_observed_at",actual.get("minute",sim.elapsed)))
	if original_minute<0 or original_minute>int(actual.get("minute",sim.elapsed)): return false
	var knowledge = {
		"event_id":event_id,"fact":str(actual.get("fact",actual.get("kind",actual.get("title","出来事")))),
		"value":_copy(actual.get("value",actual.get("text",""))),
		"source":actual.get("source",owner if not owner.is_empty() else observer),
		"observed_at":int(sim.elapsed),"mode":"observed","confidence":.95,
		"received_from":"","origin_observed_at":original_minute
	}
	return _retain(p,knowledge)

func share(speaker: Dictionary, listener: Dictionary, event_id: String) -> bool:
	if speaker.get("id","")==listener.get("id",""): return false
	upgrade_person(speaker)
	upgrade_person(listener)
	for known in speaker.knowledge:
		if known.event_id!=event_id or int(known.observed_at)>int(sim.elapsed): continue
		# Sharing copies a known fact, never the caller's proposed replacement.
		# The original source survives multiple hops; received_from is the last hop.
		var received: Dictionary = known.duplicate(true)
		received.mode = "told"
		received.received_from = speaker.id
		received.observed_at = int(sim.elapsed)
		received.confidence = clampf(float(known.confidence)*.9,0,1)
		return _retain(listener,received)
	return false

func experience(p: Dictionary, other_id: String, activity: String, context: Dictionary, outcome: Dictionary) -> Dictionary:
	upgrade_person(p)
	var kind := _kind(activity)
	var place: String = context.get("place",p.get("place",""))
	var condition := _condition(p,context)
	var key := JSON.stringify([kind,place,other_id,condition])
	var estimate: Dictionary = p.expectations.get(key,{"activity":kind,"place":place,"other":other_id,"condition":condition,"enjoyment":.5,"burden":.3,"familiarity":.2,"samples":0,"updated_at":0})
	var completed: bool = outcome.get("completed",outcome.get("success",true))
	var enjoyment: float = clampf(float(outcome.get("enjoyment",.65 if completed else .25)),0,1)
	var burden: float = clampf(float(outcome.get("burden",context.get("fatigue",p.get("fatigue",.3)))),0,1)
	var familiarity: float = clampf(float(outcome.get("familiarity",.8 if completed else .2)),0,1)
	estimate.enjoyment = lerpf(float(estimate.enjoyment),enjoyment,LEARNING_RATE)
	estimate.burden = lerpf(float(estimate.burden),burden,LEARNING_RATE)
	estimate.familiarity = lerpf(float(estimate.familiarity),familiarity,LEARNING_RATE)
	estimate.samples = int(estimate.samples)+1
	estimate.updated_at = int(sim.elapsed)
	p.expectations[key] = estimate
	_trim_expectations(p,key)
	var skill: String = outcome.get("skill",context.get("skill",""))
	if completed and not skill.is_empty():
		estimate.skill = skill
		var current: float = clampf(float(p.skills.get(skill,0)),0,1)
		var practice: float = clampf(float(outcome.get("practice",.01)),0,.03)
		p.skills[skill] = minf(1,current+practice*(1-current))
	return estimate.duplicate(true)

func action_bonus(p: Dictionary, kind: String, place: String, other_id: String = "") -> float:
	upgrade_person(p)
	kind = _kind(kind)
	var tags := _relevant_tags(kind)
	var interest: float = 0
	var skill: float = 0
	for tag in tags:
		if tag in p.interests: interest = 1
		skill = maxf(skill,float(p.skills.get(tag,0)))
	var bonus: float = .014*interest+.012*clampf(skill,0,1)
	var condition := _condition(p,{})
	var weighted: float = 0
	var weight: float = 0
	for estimate in p.expectations.values():
		if estimate.activity!=kind or estimate.place!=place or estimate.condition!=condition: continue
		if not other_id.is_empty() and estimate.other not in ["",other_id]: continue
		# A venue candidate with no chosen partner uses a weak average of the
		# person's own encounters there, rather than adopting anybody's memory.
		var relevance: float = 1.0 if estimate.other==other_id else .5
		weighted += relevance*(.045*(float(estimate.enjoyment)-.5)-.040*(float(estimate.burden)-.3)+.015*(float(estimate.familiarity)-.2))
		weight += relevance
	if weight>0: bonus += weighted/weight
	return clampf(bonus,-MAX_BONUS,MAX_BONUS)

func explain(p: Dictionary) -> String:
	upgrade_person(p)
	var plan_reason: String = p.cognition_plan.get("reason","")
	if not plan_reason.is_empty(): return plan_reason
	var latest: Dictionary = {}
	for estimate in p.expectations.values():
		if latest.is_empty() or int(estimate.updated_at)>=int(latest.updated_at): latest = estimate
	if not latest.is_empty():
		var action: String = ACTION_LABELS.get(latest.activity,"過ごした")
		var other: Dictionary = sim.person(latest.other)
		var partner: String = other.get("name","")+"さんと" if not other.is_empty() else ""
		if latest.has("skill"): action = "%sに取り組んだ"%INTEREST_LABELS.get(latest.skill,latest.skill)
		var feeling: String = "自分のペースで続けたい"
		if float(latest.burden)>.4: feeling = "次は少し余裕を持ちたい"
		elif float(latest.enjoyment)>.53: feeling = "また同じような時間を持ちたい"
		return "前に%s%s経験から、%s。"%[partner,action,feeling]
	if not p.interests.is_empty(): return "%sに関心がある。"%INTEREST_LABELS.get(p.interests[0],p.interests[0])
	return "自分に合う過ごし方を探している。"

func _existing_event(event: Dictionary) -> Dictionary:
	var event_id: String = event.get("event_id","")
	for actual in sim.events:
		if not event_id.is_empty():
			if actual.get("event_id","")==event_id: return actual
		elif actual==event: return actual
	return {}

func _initial_profile(id: String) -> Dictionary:
	var definition: Dictionary = sim.definitions.get(id,{})
	var profile: Dictionary = DEFAULT_PROFILES.get(id,{})
	return {"skills":definition.get("skills",profile.get("skills",{})).duplicate(true),"interests":definition.get("interests",profile.get("interests",[])).duplicate(true)}

func _known_profile(observer: Dictionary, other_id: String) -> Dictionary:
	var initial: Dictionary = observer.known_profiles.get(other_id,{})
	var result = {"skills":initial.get("skills",{}).duplicate(true),"interests":initial.get("interests",[]).duplicate(true)}
	var skill_times: Dictionary = {}
	var skill_confidence: Dictionary = {}
	for skill in initial.get("skills",{}):
		skill_times[skill] = int(initial.get("observed_at",0))
		skill_confidence[skill] = .95
	for known in observer.knowledge:
		if known.fact!="profile" or not known.value is Dictionary: continue
		if known.value.get("person","")!=other_id or int(known.observed_at)>int(sim.elapsed): continue
		var occurred: int = int(known.get("origin_observed_at",known.observed_at))
		var confidence: float = float(known.confidence)
		for skill in known.value.get("skills",{}):
			if occurred<int(skill_times.get(skill,-1)): continue
			if occurred==int(skill_times.get(skill,-1)) and confidence<=float(skill_confidence.get(skill,-1)): continue
			result.skills[skill] = known.value.skills[skill]
			skill_times[skill] = occurred
			skill_confidence[skill] = confidence
		# A profile observation may reveal only the interest relevant to that
		# encounter. Omitted interests are unknown, rather than retracted facts.
		# An actual loss of interest needs its own future event type.
		for interest in known.value.get("interests",[]):
			if interest not in result.interests: result.interests.append(interest)
	return result

func _retain(p: Dictionary, knowledge: Dictionary) -> bool:
	for index in p.knowledge.size():
		var old: Dictionary = p.knowledge[index]
		if old.event_id!=knowledge.event_id or old.fact!=knowledge.fact: continue
		if float(old.confidence)>=float(knowledge.confidence): return false
		p.knowledge[index] = knowledge
		return true
	p.knowledge.append(knowledge)
	if p.knowledge.size()>KNOWLEDGE_LIMIT: p.knowledge.pop_front()
	return true

func _trim_expectations(p: Dictionary, keep: String) -> void:
	if p.expectations.size()<=EXPECTATION_LIMIT: return
	var oldest: String = ""
	var oldest_minute: int = 9223372036854775807
	for key in p.expectations:
		if key!=keep and int(p.expectations[key].updated_at)<oldest_minute:
			oldest = key
			oldest_minute = int(p.expectations[key].updated_at)
	if not oldest.is_empty(): p.expectations.erase(oldest)

func _kind(activity: String) -> String:
	return {"meet":"social","social_plan":"social","joint_work":"hobby","planned_project":"hobby","project":"hobby","support_care":"care","support_chores":"chores"}.get(activity,activity)

func _condition(p: Dictionary, context: Dictionary) -> String:
	if context.has("condition"): return str(context.condition)
	if float(context.get("fatigue",p.get("fatigue",0)))>.65: return "tired"
	if float(context.get("quiet",p.get("quiet",0)))>.65: return "quiet"
	return "rested"

func _relevant_tags(kind: String) -> Array:
	return {
		"photo":["photography","walking"],"hobby":["baking","design","model","repair","craft","music","learning"],
		"social":["communication","hospitality","family","community","learning"],
		"care":["care","family"],"chores":["care","craft"],"rest":["solitude"],
		"work":["baking","design","repair","craft","hospitality"],"legacy":["discovery","learning"]
	}.get(kind,[])

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

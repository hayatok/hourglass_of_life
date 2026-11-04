class_name ResidentSupportPlans
extends RefCounted

# A resident chooses whom to ask from their own experience. World-side consent
# and the existing arrival/handoff rules decide whether help actually happens.
# Timers and completion markers are saved on people and existing help records.
const CONSIDER_INTERVAL = 30
const DECLINE_COOLDOWN = 240
const ACCEPT_COOLDOWN = 1440
const ACTIVE_STATES = ["travel","active","handoff"]

var sim

func _init(simulation) -> void:
	sim = simulation

func reset() -> void:
	for p in sim.people: upgrade_person(p)

func upgrade_person(p: Dictionary) -> void:
	if not p.has("support_next_attempt"): p.support_next_attempt = 60

func tick() -> void:
	for help in sim.work_family.supports:
		if help.get("autonomous",false): _sync(help)
	if sim.elapsed%CONSIDER_INTERVAL!=0: return
	for p in sim.people:
		upgrade_person(p)
		if sim.elapsed<int(p.support_next_attempt) or not _needs_support(p): continue
		var candidate := _choose_known_adult(p)
		if candidate.is_empty():
			p.support_next_attempt = sim.elapsed+120
			continue
		# Once a person is selected, their own needs can make them decline. They
		# are not replaced by an omniscient search for the least tired neighbour.
		p.support_next_attempt = sim.elapsed+DECLINE_COOLDOWN
		if not _can_consider_request(candidate): continue
		var result: Dictionary = sim.work_family.propose_support(p.id,candidate.id)
		if result.get("status","")!="accept": continue
		var help: Dictionary = sim.work_family.supports[-1]
		help.autonomous = true
		help.initiator = p.id
		help.support_plan_recorded = false
		help.support_work_minutes = 0
		help.support_receiver_fatigue = float(p.fatigue)
		help.support_giver_fatigue = float(candidate.fatigue)
		p.support_next_attempt = sim.elapsed+ACCEPT_COOLDOWN
		_track(help)

func person_text(p: Dictionary) -> String:
	var plan: Dictionary = p.get("cognition_plan",{})
	if plan.get("kind","")!="support": return ""
	var label: String = {"travel":"暮らしの手助けを相談した","execute":"暮らしの時間を分け合っている","completed":"手助けを終えた","interrupted":"手助けの予定を見直した"}.get(plan.get("stage",""),"")
	return "%s\n%s"%[label,plan.get("title","")]

func _needs_support(p: Dictionary) -> bool:
	if not sim.life.is_alive(p) or int(p.age)<18: return false
	if p.get("moving",false) or not p.get("meeting_id","").is_empty() or not p.get("support_id","").is_empty(): return false
	if p.get("action","") in ["sleep","eat"] or float(p.get("hunger",0))>.75: return false
	for help in sim.work_family.supports:
		if help.state in ACTIVE_STATES and p.id in [help.giver,help.receiver]: return false
	var home: String = sim.HOME[sim.work_family.household_id(p)]
	if p.place!=home: return false
	var routine: Dictionary = sim._authored_routine_at(p)
	var care: bool = routine.get("id","")=="after_school_care"
	if not routine.is_empty() and not care: return false
	var fatigue: float = float(p.get("fatigue",0))
	var load: float = float(sim.work_family.household(p).home_load)
	var goal_waiting: bool = not p.get("current_goal","").is_empty() and float(p.get("goal_progress",0))<.95
	return (care and fatigue>=.45 and goal_waiting) or (load>=.7 and fatigue>=.45) or load>=.9 or fatigue>=.7

func _choose_known_adult(p: Dictionary) -> Dictionary:
	var candidates: Array = []
	# These are the requester's directional relationships, not the town roster.
	for other_id in p.get("relationships",{}):
		var relation: Dictionary = p.relationships[other_id]
		if float(relation.get("trust",0))<.55 or float(relation.get("familiarity",0))<.15: continue
		if not _known(p,other_id): continue
		var other: Dictionary = sim.person(other_id)
		if other.is_empty() or not sim.life.is_alive(other) or int(other.age)<18 or other.id==p.id: continue
		var score: float = float(relation.trust)+.2*float(relation.get("ease",0))+.1*float(relation.familiarity)
		# Remembering recent help favours sharing requests rather than always
		# relying on the same trusted person. No helper's hidden workload is read.
		for memory in p.get("memories",[]):
			if memory.get("other","")==other_id and memory.get("kind","")=="support" and int(memory.get("minute",0))>sim.elapsed-2880:
				score -= .35
		candidates.append({"person":other,"score":score})
	candidates.sort_custom(func(a,b): return a.score>b.score if not is_equal_approx(a.score,b.score) else str(a.person.id)<str(b.person.id))
	return candidates[0].person if not candidates.is_empty() else {}

func _known(p: Dictionary, other_id: String) -> bool:
	if p.get("known_profiles",{}).has(other_id): return true
	for memory in p.get("memories",[]):
		if memory.get("other","")==other_id and memory.get("kind","") in ["shared_time","support","creation"]: return true
	# A relationship actually developed through time together is also known
	# even if its old profile information has been forgotten.
	return float(p.relationships[other_id].get("familiarity",0))>=.4

func _can_consider_request(giver: Dictionary) -> bool:
	if giver.get("action","")=="sleep" or (giver.get("action","")=="rest" and float(giver.fatigue)>.55):
		sim._reply(giver,"decline","いまは自分も休みたい。落ち着いてから相談しよう。")
		return false
	if giver.get("action","")=="eat" or float(giver.get("hunger",0))>.7:
		sim._reply(giver,"decline","まずは食事にしたい。ひと息ついてから相談しよう。")
		return false
	return true

func _track(help: Dictionary) -> void:
	var activity := "support_care" if help.kind=="care" else "support_chores"
	var title := "家族と過ごす時間の交代" if help.kind=="care" else "家の用事の手助け"
	for id in [help.receiver,help.giver]:
		var p: Dictionary = sim.person(id)
		var other: String = help.giver if id==help.receiver else help.receiver
		p.cognition_plan = {"meeting":help.id,"activity":activity,"title":title,"partner":other,"stage":"travel","origin":"resident","started":sim.elapsed,"steps":["相談する","家で合流する","負担を分け合う","経験を振り返る"],"kind":"support"}

func _sync(help: Dictionary) -> void:
	if help.get("support_plan_recorded",false): return
	var began: int = int(help.get("began",-1))
	if help.state in ["active","handoff","completed"] and began>=0:
		help.support_work_minutes = maxi(int(help.get("support_work_minutes",0)),maxi(0,sim.elapsed-began))
	for id in [help.receiver,help.giver]:
		var p: Dictionary = sim.person(id)
		var plan: Dictionary = p.get("cognition_plan",{})
		if plan.get("meeting","")!=help.id or plan.get("kind","")!="support": continue
		if help.state in ["active","handoff"]: plan.stage = "execute"
		elif help.state in ["completed","interrupted"]:
			plan.stage = "completed" if help.state=="completed" else "interrupted"
			plan.finished = sim.elapsed
	if help.state not in ["completed","interrupted"]: return
	var completed: bool = help.state=="completed"
	var activity := "support_care" if help.kind=="care" else "support_chores"
	for id in [help.receiver,help.giver]:
		var p: Dictionary = sim.person(id)
		var other: String = help.giver if id==help.receiver else help.receiver
		if not p.has("plan_history"): p.plan_history = []
		p.plan_history.append({"activity":activity,"partner":other,"day":sim.day_index(),"minute":sim.elapsed,"completed":completed})
		while p.plan_history.size()>24: p.plan_history.pop_front()
		if int(help.get("support_work_minutes",0))<=0: continue
		var values: Dictionary = sim.definitions[p.id].values
		var initial: float = float(help.get("support_giver_fatigue",p.fatigue)) if id==help.giver else float(help.get("support_receiver_fatigue",p.fatigue))
		var enjoyment: float = .55+.15*float(values.get("care",.5)) if id==help.giver else .55+clampf(initial-float(p.fatigue),0,.3)
		var burden: float = clampf(.25+float(p.fatigue)-initial,0,1) if id==help.giver else float(p.fatigue)*.3
		var outcome := {"completed":completed,"enjoyment":enjoyment if completed else .4,"burden":burden}
		if id==help.giver and completed:
			outcome.skill = "care" if help.kind=="care" else "housework"
			outcome.practice = .008
		sim.cognition.experience(p,other,activity,{"place":help.place},outcome)
	help.support_plan_recorded = true

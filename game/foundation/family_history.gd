class_name FamilyHistory
extends RefCounted

# Author-written past and observed current life are deliberately separate.
# Choice is pure. Only the actual executor calls performed/completed/declined.
const SOURCE := "res://data/foundation/ogawa-biographies.json"
const TOWN_SOURCE := "res://data/foundation/town-biographies.json"
const CHORES := ["cook","serve","wash_dishes","shop","laundry","hang_laundry","fold_laundry"]
var definitions: Dictionary = {}
var load_errors: Array[String] = []

func _init(authored: Dictionary = {}) -> void:
	if not authored.is_empty(): definitions=authored.duplicate(true);return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if parsed is Dictionary and parsed.get("profiles") is Dictionary: definitions=parsed.duplicate(true)
	var town: Variant = JSON.parse_string(FileAccess.get_file_as_string(TOWN_SOURCE))
	if town is Dictionary and town.get("profiles") is Dictionary:
		_merge_profiles(town.profiles)
		definitions.source_files=[SOURCE,TOWN_SOURCE]
		definitions.note="Merged authored fiction; source files retain their own scope. No statistics-derived individual histories or G3 runtime acceptance are implied."
	else: load_errors.append("town biographies are missing or malformed")

func _merge_profiles(additional: Dictionary) -> void:
	if not definitions.get("profiles") is Dictionary: load_errors.append("primary biographies are missing");return
	for id in additional:
		if definitions.profiles.has(id): load_errors.append("duplicate biography: "+str(id));continue
		if not additional[id] is Dictionary: load_errors.append("malformed biography: "+str(id));continue
		definitions.profiles[id]=additional[id].duplicate(true)

func attach(p: Dictionary, start_minute: int) -> bool:
	var profile: Variant = definitions.get("profiles",{}).get(p.get("id",""))
	if not profile is Dictionary: return false
	p.biography=profile.duplicate(true)
	var project: Dictionary = profile.project
	var projects: Dictionary = {}
	projects[project.id]={"source_item_id":project.source_item_id,"minutes":0.0,"completed":false,"fixture":project.storage_fixture,"artifact":{}}
	var deadlines: Dictionary = {}
	for commitment in profile.commitments: deadlines[commitment.id]=float(posmod(int(commitment.due_minute)-start_minute,1440))
	p.life_history={"projects":projects,"experience_minutes":{},"observed":[],"credited_tasks":{},"completed_events":[],
		"deadlines":deadlines,"fulfilled":{},"tools_out":false,"tools_project":"","tools_fixture":"","start_minute":start_minute}
	return true

func set_deadline(p: Dictionary, id: String, due_elapsed: float) -> bool:
	if not _number(due_elapsed,0,10000000) or not p.get("life_history",{}).get("deadlines",{}).has(id): return false
	p.life_history.deadlines[id]=due_elapsed
	return true

func project_for(p: Dictionary) -> Dictionary:
	return p.get("biography",{}).get("project",{})

func project_execution(p: Dictionary) -> Dictionary:
	# Authored specialist contract only. A caller must still supply the actual
	# resources, fixture arrival and operations before claiming runtime support.
	return project_for(p).duplicate(true)

func project_remaining(p: Dictionary) -> float:
	var project: Dictionary = project_for(p)
	if project.is_empty(): return 0
	return maxf(0,float(project.required_minutes)-float(p.life_history.projects[project.id].minutes))

func deadline_pressure(p: Dictionary, elapsed: float, observer: String = "") -> float:
	var pressure: float = 0.0
	for commitment in p.biography.commitments:
		if commitment.kind!="project" or not observer.is_empty() and observer not in commitment.known_to: continue
		if p.life_history.projects.get(commitment.get("project_id",""),{}).get("completed",false): continue
		var left: float = float(p.life_history.deadlines[commitment.id])-elapsed
		if left>float(commitment.window_minutes): continue
		pressure=maxf(pressure,clampf(1-left/maxf(1,float(commitment.window_minutes)),.1,1))
	return pressure

func family_pressure(p: Dictionary, elapsed: float) -> float:
	var today: int = int(floor((float(p.life_history.start_minute)+elapsed)/1440.0))
	var pressure: float = 0.0
	for commitment in p.biography.commitments:
		if commitment.kind!="family" or int(p.life_history.fulfilled.get(commitment.id,-1))==today: continue
		var left: float = float(p.life_history.deadlines[commitment.id])-elapsed
		if left<float(-120) or left>float(commitment.window_minutes): continue
		pressure=maxf(pressure,clampf(1-left/maxf(1,float(commitment.window_minutes)),0,1))
	return pressure

# Context contains visible home/action state and only explicitly shared deadlines.
# It never uses another person's values, private experience or unannounced goals.
func context_for(actor: String, people: Dictionary, tasks: Dictionary, elapsed: float, weekday: int = 0) -> Dictionary:
	var context: Dictionary = {"elapsed":elapsed,"adult_helpers":0,"other_deadline":false,"independent_child":false,"quiet_requested":false}
	for other in people.values():
		if other.id==actor or not other.at_home: continue
		for commitment in other.biography.commitments:
			var day: int = posmod(weekday+int(floor((float(other.life_history.start_minute)+elapsed)/1440.0)),7)
			var allowed_day: bool = commitment.get("on_days",[0,1,2,3,4,5,6]).any(func(value):return (value is int or value is float) and float(value)==float(day))
			if commitment.kind=="quiet_window" and actor in commitment.known_to and allowed_day and _in_clock_window(other,elapsed,commitment.get("clock_window",[])): context.quiet_requested=true
		var task: Dictionary = tasks.get(other.active_task,{})
		if int(other.age)>=13:
			if deadline_pressure(other,elapsed,actor)>.1: context.other_deadline=true
			elif task.get("kind","") not in ["work","sleep"]: context.adult_helpers+=1
		elif task.get("kind","")=="personal_project" and task.get("status","") in ["arrived","working","phase_ready"] and float(task.get("performed",0))>0:
			context.independent_child=true
	return context

func choice(p: Dictionary, kind: String, context: Dictionary) -> Dictionary:
	var values: Dictionary = p.biography.values
	var state: Dictionary = p.life_history
	var project: Dictionary = project_for(p)
	var pressure: float = deadline_pressure(p,float(context.elapsed))
	var delta: float = 0.0
	var reason: String = "自分の必要と家の状況を確かめて選んだ"
	var activity: String = kind
	var project_id: String = ""
	if kind in CHORES:
		delta+=float(values.family_time)*.06+float(p.biography.experience.get(kind,0))*.05
		if bool(context.other_deadline):
			delta+=.16;reason="家族の共有された締切を考え、今は自分が家事を引き受ける"
		elif int(context.adult_helpers)==0:
			delta+=.12;reason="先に家にいる自分が、出来る家事を引き受ける"
		else: reason="これまでの分担と家族の暮らしを考えて家事を選ぶ"
		if pressure>.1 and int(context.adult_helpers)>0:
			delta-=.42*pressure;reason="自分の締切が近いので、家事は余裕のある家族に頼みたい"
	elif kind=="personal_project":
		activity=project.activity;project_id=project.id
		delta=.08+float(values.creative_pride)*.12+float(values.independence)*.06+pressure*.48
		if float(state.projects[project.id].minutes)>0: delta+=.035
		reason="約束した締切を守るため、"+str(project.label) if pressure>.1 else str(project.label)+"ために自分の時間を取る"
	elif kind=="tidy_tools":
		activity="tidy_personal_tools";project_id=str(state.tools_project)
		delta=.18+float(values.reliability)*.12+float(values.independence)*.09
		reason="自分が実際に使った道具を、自分で片付ける"
	elif kind in ["care","family_time"]:
		delta=float(values.family_time)*.08+family_pressure(p,float(context.elapsed))*.18-pressure*.48
		if kind=="family_time" and project_remaining(p)>0 and bool(project.independent):
			delta-=float(values.independence)*.61
			reason="まず自分の案を試したいので、誘いはあとで受けたい"
		elif kind=="care" and bool(context.independent_child):
			delta-=.45;reason="子どもが自分で取り組んでいるので、今は任せて見守る"
		else: reason="これまでの家族の時間と、交わした約束を大切にする"
		if pressure>.1: reason="締切のある作業を先に進め、家族の誘いはあとで受けたい"
	elif kind=="quiet":
		delta=float(values.independence)*.035
		reason="家の役割から少し離れ、自分の静かな時間を取る"
	elif kind in ["work","school"]:
		reason="引き受けた役割と、いまの勤務・通学の予定を守る"
	var household: Dictionary = _household_pressure(p,kind,float(context.elapsed))
	if float(household.delta)>0: delta+=float(household.delta);reason=household.reason
	var authored_delta: float = 0.0
	for rule in p.biography.get("choice_rules",[]):
		if _rule_matches(p,kind,context,rule):
			authored_delta+=clampf(float(rule.get("delta",0)),-.3,.3)
			if kind!="personal_project" or pressure<=.1: reason=str(rule.get("reason",reason))
			elif float(rule.get("delta",0))<0: reason+="。"+str(rule.get("reason",""))
	delta+=clampf(authored_delta,-.4,.4)
	return {"score_delta":delta,"activity":activity,"project_id":project_id,"choice_reason":reason}

func _in_clock_window(p: Dictionary, elapsed: float, window: Array) -> bool:
	if window.size()!=2: return false
	var now: float = fposmod(float(p.life_history.start_minute)+elapsed,1440)
	return now>=float(window[0]) and now<float(window[1]) if float(window[0])<=float(window[1]) else now>=float(window[0]) or now<float(window[1])

func _household_pressure(p: Dictionary, kind: String, elapsed: float) -> Dictionary:
	var result: Dictionary = {"delta":0.0,"reason":""}
	var today: int = int(floor((float(p.life_history.start_minute)+elapsed)/1440.0))
	for commitment in p.biography.commitments:
		if commitment.kind!="household" or kind not in commitment.actions or int(p.life_history.fulfilled.get(commitment.id,-1))==today: continue
		var left: float = float(p.life_history.deadlines[commitment.id])-elapsed
		if left< -120 or left>float(commitment.window_minutes): continue
		var weight: float = .1*clampf(1-left/maxf(1,float(commitment.window_minutes)),0,1)
		if weight>float(result.delta): result={"delta":weight,"reason":"引き受けた分担を守るため、"+str(commitment.label)}
	return result

func _rule_matches(p: Dictionary, kind: String, context: Dictionary, rule: Dictionary) -> bool:
	if kind not in rule.get("actions",[]): return false
	var project: Dictionary = project_for(p)
	if rule.has("project_noise") and project.get("noise","") not in rule.project_noise: return false
	match str(rule.get("when","")):
		"fatigued": return float(p.get("fatigue",0))>=float(rule.get("threshold",.65))
		"fresh": return float(p.get("fatigue",0))<=float(rule.get("threshold",.55))
		"project_underway": return float(p.life_history.projects[project.id].minutes)>0 and not bool(p.life_history.projects[project.id].completed)
		"tools_out": return bool(p.life_history.tools_out)
		"quiet_requested": return bool(context.get("quiet_requested",false))
		"shared_deadline": return bool(context.get("other_deadline",false))
	return false

func performed(p: Dictionary, task: Dictionary, amount: float, elapsed: float) -> void:
	var state: Dictionary = p.life_history
	var previous: float = float(state.credited_tasks.get(task.id,0))
	var credit: float = minf(amount,maxf(0,float(task.performed)-previous))
	if credit<=0: return
	state.credited_tasks[task.id]=float(task.performed)
	var activity: String = str(task.get("activity",task.kind))
	state.experience_minutes[activity]=float(state.experience_minutes.get(activity,0))+credit
	if task.kind=="personal_project":
		var project: Dictionary = project_for(p)
		var progress: Dictionary = state.projects[project.id]
		progress.minutes=minf(float(project.required_minutes),float(progress.minutes)+credit)
		progress.fixture=task.fixture
		state.tools_out=true;state.tools_project=project.id;state.tools_fixture=task.fixture

func completed(p: Dictionary, task: Dictionary, elapsed: float) -> void:
	var state: Dictionary = p.life_history
	var event_id: String = "completed:"+str(task.id)
	if event_id in state.completed_events or float(task.performed)<=0: return
	if task.kind=="personal_project":
		var project: Dictionary = project_for(p)
		var progress: Dictionary = state.projects[project.id]
		if not progress.completed and float(progress.minutes)>=float(project.required_minutes)-.000001:
			progress.completed=true
			progress.artifact={"id":"artifact:"+str(p.id)+":"+str(project.id),"kind":project.artifact_kind,"owner":p.id,
				"source_project":project.id,"fixture":task.fixture,"completed_at":elapsed}
			if project.has("result_mode"):
				progress.artifact.result_mode=project.result_mode
				progress.artifact.source_item_id=project.source_item_id
	elif task.kind=="tidy_tools":
		var project: Dictionary = project_for(p)
		var progress: Dictionary = state.projects[project.id]
		progress.fixture=project.storage_fixture
		if not progress.artifact.is_empty(): progress.artifact.fixture=project.storage_fixture
		state.tools_out=false;state.tools_project="";state.tools_fixture=""
	for commitment in p.biography.commitments:
		if task.kind in commitment.actions and float(task.performed)>=float(commitment.required_minutes):
			state.fulfilled[commitment.id]=int(floor((float(state.start_minute)+elapsed)/1440.0))
	_record(p,event_id,task,"completed",elapsed)

func declined(p: Dictionary, invitation_task: String, choice_task: Dictionary, elapsed: float) -> void:
	if invitation_task.is_empty(): return
	_record(p,"declined:"+invitation_task,choice_task,"declined_family_invitation",elapsed)

func _record(p: Dictionary, event_id: String, task: Dictionary, status: String, elapsed: float) -> void:
	var state: Dictionary = p.life_history
	if event_id in state.completed_events: return
	state.completed_events.append(event_id)
	if state.completed_events.size()>128: state.completed_events.pop_front()
	state.observed.append({"event_id":event_id,"task_id":task.id,"kind":task.kind,"activity":task.get("activity",task.kind),
		"project_id":task.get("project_id",""),"status":status,"at":elapsed,"actual_minutes":float(task.performed)})
	if state.observed.size()>128: state.observed.pop_front()

func valid_person(p: Dictionary, elapsed: float) -> bool:
	if not p.get("biography") is Dictionary or not _same(p.biography,definitions.get("profiles",{}).get(p.get("id"),{})): return false
	var state: Variant = p.get("life_history")
	if not state is Dictionary: return false
	for key in ["projects","experience_minutes","credited_tasks","deadlines","fulfilled"]:
		if not state.get(key) is Dictionary: return false
	if not state.get("observed") is Array or not state.get("completed_events") is Array or state.observed.size()>128 or state.completed_events.size()>128: return false
	if not state.get("tools_out") is bool or not state.get("tools_project") is String or not state.get("tools_fixture") is String or not _number(state.get("start_minute"),0,1439): return false
	var project: Dictionary = p.biography.project
	if state.projects.size()!=1 or not state.projects.get(project.id) is Dictionary: return false
	var progress: Dictionary = state.projects[project.id]
	if progress.get("source_item_id")!=project.source_item_id or not _number(progress.get("minutes"),0,float(project.required_minutes)) or not progress.get("completed") is bool or not progress.get("fixture") is String or not progress.get("artifact") is Dictionary: return false
	if bool(progress.completed)!=(not progress.artifact.is_empty()): return false
	if progress.completed:
		var artifact: Dictionary = progress.artifact
		if not is_equal_approx(float(progress.minutes),float(project.required_minutes)) or artifact.get("id")!="artifact:"+str(p.id)+":"+str(project.id) or artifact.get("kind")!=project.artifact_kind or artifact.get("owner")!=p.id or artifact.get("source_project")!=project.id or artifact.get("fixture")!=progress.fixture or not _number(artifact.get("completed_at"),0,elapsed): return false
		if project.has("result_mode") and (artifact.get("result_mode")!=project.result_mode or artifact.get("source_item_id")!=project.source_item_id): return false
	if state.tools_out:
		if state.tools_project!=project.id or state.tools_fixture!=progress.fixture or float(progress.minutes)<=0: return false
	elif not state.tools_project.is_empty() or not state.tools_fixture.is_empty(): return false
	if state.deadlines.size()!=p.biography.commitments.size(): return false
	for commitment in p.biography.commitments:
		if not _number(state.deadlines.get(commitment.id),0,10000000): return false
	for key in state.fulfilled:
		if not state.deadlines.has(key) or not _number(state.fulfilled[key],0,10000) or floorf(float(state.fulfilled[key]))!=float(state.fulfilled[key]): return false
	for key in ["experience_minutes","credited_tasks"]:
		if state[key].size()>10000: return false
		for id in state[key]:
			if not id is String or id.length()>100 or not _number(state[key][id],0,10000000): return false
	var seen: Array = []
	for event in state.completed_events:
		if not event is String or event.length()>128 or event in seen: return false
		seen.append(event)
	for event in state.observed:
		if not event is Dictionary or event.get("event_id") not in state.completed_events or not event.get("task_id") is String or not event.get("kind") is String or not event.get("activity") is String or not event.get("project_id") is String or event.get("status") not in ["completed","declined_family_invitation"] or not _number(event.get("at"),0,elapsed) or not _number(event.get("actual_minutes"),0,10000000): return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<.000000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _same(a[i],b[i]): return false
		return true
	return a==b

class_name WorkFamily
extends RefCounted

var sim
var config: Dictionary
var households: Dictionary = {}
var supports: Array = []:
	set(value):
		supports = value
		_invalidate_support_index()
var serial: int = 0
var projects: Dictionary = {}
var _support_index: Array = []
var _support_index_source: Array = []
var _support_index_minute: int = -1
var _support_index_size: int = -1

func _init(simulation) -> void:
	sim = simulation
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/life-conditions.json"))

func reset() -> void:
	households.clear()
	supports.clear()
	_invalidate_support_index()
	serial = 0
	projects = {"radio":0.0,"model":0.0,"bread":0.0,"photo":0.0,"music":0.0,"craft":0.0}
	for id in config.households:
		var d = config.households[id]
		households[id] = {"cash":float(d.cash),"home_load":.3,"earned_today":0.0,"spent_today":0.0,"material_days":{},"ledger":[]}
	for p in sim.people: upgrade_person(p)

func upgrade_person(p: Dictionary) -> void:
	var defaults = {"work_satisfaction":.45,"earned_today":0.0,"care_minutes":0,"private_project":0.0,"support_id":"","session_meal_paid":false}
	for key in defaults:
		if not p.has(key): p[key] = defaults[key]

func household_id(p: Dictionary) -> String:
	return p.household_override if not p.get("household_override","").is_empty() else sim.definitions[p.id].household_id

func household(p: Dictionary) -> Dictionary:
	return households[household_id(p)]

func worry(p: Dictionary) -> float:
	var d = config.households[household_id(p)]
	return clampf(1-household(p).cash/(d.daily_basics*4+d.season_housing),0,1)

func _invalidate_support_index() -> void:
	_support_index_minute = -1
	_support_index_size = -1
	# Assign new arrays; do not clear the array that an in-progress loop uses.
	_support_index = []
	_support_index_source = []

func _active_supports() -> Array:
	if _support_index_minute!=int(sim.elapsed) or _support_index_size!=supports.size() or not is_same(_support_index_source,supports):
		_support_index = []
		for help in supports:
			if help.state in ["travel","active","handoff"]: _support_index.append(help)
		_support_index_source = supports
		_support_index_size = supports.size()
		_support_index_minute = int(sim.elapsed)
	# Keep the original order and Dictionary references. A state changed during
	# iteration is still checked by each consumer before it has any effect.
	return _support_index

func add_options(p: Dictionary, options: Array) -> void:
	var d = sim.definitions[p.id]
	var home = sim.home_for(p)
	if household(p).home_load>.15 and home==sim.HOME[household_id(p)]:
		options.append({"kind":"chores","place":home,"need":household(p).home_load,"goal":d.values.care*.7,"relation":.5,"role":.9,"habit":d.traits.conscientiousness,"fun":.2,"cost":p.fatigue*.5,"reason":"家の用事を、できるところから片付けよう"})
	# Extra work is an option for these authored flexible jobs, not every role.
	if p.id in ["ryo","osamu"] and worry(p)>.3 and sim.minute_of_day()>=480 and sim.minute_of_day()<1080:
		options.append({"kind":"work","place":"workshop" if p.id=="osamu" else home,"need":worry(p),"goal":d.values.security,"relation":.3,"role":.7,"habit":.4,"fun":p.work_satisfaction,"cost":p.fatigue*.9,"reason":"暮らしの出費が気になる。無理のない範囲でもう少し仕事を進めたい"})

func tick() -> void:
	for id in households:
		var h = households[id]
		var members = 0
		for p in sim.people:
			if p.get("alive",true) and household_id(p)==id: members += 1
		h.home_load = minf(1,h.home_load+.00006*members)
	if sim.minute_of_day()==0: _settle_day()
	for help in _active_supports():
		if help.state not in ["travel","active","handoff"]: continue
		var giver = sim.person(help.giver)
		var receiver = sim.person(help.receiver)
		if not sim.life.is_alive(giver) or not sim.life.is_alive(receiver):
			help.state = "interrupted"
			_invalidate_support_index()
			giver.support_id = ""
			giver.routine_id = ""
			receiver.routine_id = ""
			continue
		var obligation = sim._authored_routine_at(giver)
		if help.state=="handoff":
			if sim._authored_routine_at(receiver).get("id","")!="after_school_care" or (not receiver.moving and receiver.place==help.place):
				_end_support(help,help.get("finish_completed",true),help.get("finish_reason",""))
			continue
		var meal_needed: bool = giver.hunger>.75
		if help.state=="active" and help.kind=="care":
			# Begin the handoff while there is still time for the responsible
			# adult to return. A need to eat must not leave the child alone.
			var return_minutes: int = sim.resident_activities._travel(receiver.position,receiver.place,sim.SITES[help.place],help.place)+10
			meal_needed = giver.hunger+return_minutes*sim.HUNGER_PER_MINUTE>.75
		if not obligation.is_empty() or giver.fatigue>.95 or meal_needed:
			_end_support(help,false,"自分の予定や休息、食事も必要になった")
			continue
		if help.state=="travel":
			var arrived = not giver.moving and giver.place==help.place
			if help.kind=="care":
				var child = sim.person("rin")
				arrived = arrived and not child.moving and child.place==help.place
			if arrived:
				help.state = "active"
				_invalidate_support_index()
				help.began = sim.elapsed
				receiver.routine_id = ""
				receiver.remaining = 0
				giver.routine_id = ""
				sim._log(giver.id,"手助けに来た","%sさんの家で、%sを引き受けた。"%[receiver.name,"凛と過ごす時間" if help.kind=="care" else "家の用事"])
			elif sim.elapsed-help.requested>180:
				_end_support(help,false,"合流できる時間が取れなかった")
		elif sim.elapsed-help.began>=90:
			_end_support(help,true,"")

func adjust_routine(p: Dictionary, base: Dictionary, minute: int, week: int) -> Dictionary:
	# Current temporary support does not erase the person's authored future schedule.
	if minute>=0 or week>=0: return base
	for help in _active_supports():
		if help.state not in ["travel","active","handoff"]: continue
		if help.giver==p.id:
			return {"id":"support_care" if help.kind=="care" else "support_chores","place":help.place}
		if help.receiver==p.id and help.kind=="care" and help.state=="active" and base.get("id","")=="after_school_care":
			return {}
	return base

func activity_tick(p: Dictionary) -> void:
	var h = household(p)
	var d = sim.definitions[p.id]
	if p.action=="work":
		var earned = .04 if p.id=="aoi" and p.stage=="moved" else (.035 if p.id=="rin" and p.age>=22 else config.earnings_per_work_minute.get(p.id,0))
		h.cash += earned
		h.earned_today += earned
		p.earned_today += earned
		var meaning = clampf(.2+.45*d.values.achievement+.25*d.values.care-.35*p.fatigue,.1,.9)
		p.work_satisfaction = lerpf(p.work_satisfaction,meaning,.002)
		p.fatigue = minf(1,p.fatigue+.0003)
		if p.goal_kind=="career" or (p.id=="rin" and p.age>=22): p.goal_progress = minf(1,p.goal_progress+.0004)
	elif p.action=="chores":
		for help in _active_supports():
			if help.giver==p.id and help.state=="active": h = household(sim.person(help.receiver))
		h.home_load = maxf(0,h.home_load-.005)
		p.fatigue = minf(1,p.fatigue+.0004)
	elif p.action=="care":
		p.care_minutes += 1
		p.fatigue = minf(1,p.fatigue+.00015)
	elif p.action=="eat" and not p.session_meal_paid:
		h.cash -= 1
		h.spent_today += 1
		p.session_meal_paid = true
	elif p.action=="own_life":
		# The off-map home aggregates ordinary household time; town visits do not
		# magically clean a different household.
		h.home_load = maxf(0,h.home_load-.00025)

func hobby_progress(p: Dictionary) -> float:
	var primary = p.goal_kind in ["creative","model"]
	if (primary and p.goal_progress>=1) or (not primary and p.private_project>=1): return 0
	var h = household(p)
	var cost = config.project_materials.get(p.id,0)
	var key = "%s:%d"%[p.id,sim.day_index()]
	if not h.material_days.has(key):
		if h.cash<cost:
			p.reason = "今ある道具で準備をしておこう。材料を買う前に、暮らしの出費も考えたい"
			return 0
		h.cash -= cost
		h.spent_today += cost
		h.material_days[key] = true
	if not primary:
		p.private_project = minf(1,p.private_project+.0015)
		return 0
	if p.id=="ryo": p.private_project = minf(1,p.private_project+.0015)
	return .0015

func propose_support(receiver_id: String, giver_id: String) -> Dictionary:
	var receiver = sim.person(receiver_id)
	var giver = sim.person(giver_id)
	if not sim.life.is_alive(receiver) or not sim.life.is_alive(giver) or receiver_id==giver_id:
		return {"status":"decline","text":"手助けを相談する相手を選んでください"}
	if giver.age<18:
		return sim._reply(giver,"decline","大人の代わりに世話を引き受けるのは難しい。自分の道具なら片付けるよ。")
	var care = sim._authored_routine_at(receiver).get("id","")=="after_school_care"
	for help in _active_supports():
		if help.state in ["travel","active","handoff"] and (receiver_id in [help.giver,help.receiver] or giver_id in [help.giver,help.receiver]):
			return sim._reply(giver,"defer","今の手助けが終わってから、次のことを相談したい。")
	if not sim._routine_at(giver).is_empty() or not giver.meeting_id.is_empty() or sim._next_commitment(giver).minutes<(360 if care else 180):
		return sim._reply(giver,"counteroffer","自分の予定がある。時間に余裕があるときに手伝いたい。")
	if giver.fatigue>.8:
		return sim._reply(giver,"decline","今日は自分も休む必要がある。落ち着いてからにしたい。")
	var support_place: String = sim.HOME[household_id(receiver)]
	var outward: int = sim.resident_activities._travel(giver.position,giver.place,sim.SITES[support_place],support_place)+10
	if giver.action in ["eat","sleep"] or giver.hunger+(outward+90+15)*sim.HUNGER_PER_MINUTE>.75:
		return sim._reply(giver,"decline","先に食事や休息を済ませたい。時間を取れるときに相談しよう。")
	if sim.social.relation(giver,receiver_id).trust<.4:
		return sim._reply(giver,"counteroffer","まだ慣れない家のことは分からない。まず一緒に過ごして、できることを知りたい。")
	if giver.quiet>.8:
		return sim._reply(giver,"counteroffer","今は自分の時間を取りたい。少し落ち着いてから、できることを相談したい。")
	if not care and household(receiver).home_load<.4 and receiver.fatigue<.6:
		return sim._reply(receiver,"decline","今は自分で回せている。必要になったら、こちらからも相談したい。")
	serial += 1
	var help = {"id":"support_%d"%serial,"giver":giver_id,"receiver":receiver_id,"kind":"care" if care else "chores","place":sim.HOME[household_id(receiver)],"state":"travel","requested":sim.elapsed,"began":-1}
	supports.append(help)
	_invalidate_support_index()
	giver.support_id = help.id
	giver.routine_id = ""
	sim._assign(giver,"care" if care else "chores",help.place,90,"%sさんの家で、できることを手伝いたい"%receiver.name)
	return sim._reply(giver,"accept","家へ向かうよ。着いてからしばらく、%sを引き受けよう。"%("凛と過ごす時間" if care else "家の用事"))

func _end_support(help: Dictionary, completed: bool, reason: String) -> void:
	var giver = sim.person(help.giver)
	var receiver = sim.person(help.receiver)
	if (completed or help.state in ["active","handoff"]) and help.kind=="care" and sim._authored_routine_at(receiver).get("id","")=="after_school_care" and (receiver.moving or receiver.place!=help.place):
		help.state = "handoff"
		_invalidate_support_index()
		help.finish_completed = completed
		help.finish_reason = reason
		receiver.routine_id = ""
		receiver.remaining = 0
		sim._log(giver.id,"交代して戻るのを待っている","%sさんが家に戻るまで、凛と一緒に過ごす。"%receiver.name)
		return
	help.state = "completed" if completed else "interrupted"
	_invalidate_support_index()
	giver.support_id = ""
	giver.routine_id = ""
	giver.remaining = 0
	receiver.routine_id = ""
	if completed:
		for pair in [[giver,receiver],[receiver,giver]]:
			var r = sim._relation(pair[0],pair[1].id)
			r.trust = minf(1,r.trust+.03)
			sim._remember(pair[0],pair[1].id,"暮らしの時間を分け合った","%sさんと相談して、%sを分担した。"%[pair[1].name,"凛と過ごす時間" if help.kind=="care" else "家の用事"],"support")
	else:
		sim._log(giver.id,"手助けの予定を見直した",reason+"。残りはまた相談することにした。")

func project_definition(a: Dictionary, b: Dictionary) -> Dictionary:
	return sim.resident_activities.definition(a,b)

func meeting_compatible(p: Dictionary, meeting: Dictionary) -> bool:
	var routine = sim._routine_at(p)
	if routine.is_empty(): return true
	return meeting.get("mode","")=="project" and meeting.get("project",{}).get("key","")=="model" and routine.id in ["after_school_care","after_school_home"]

func propose_project(first: String, second: String, preferred: String = "", autonomous: bool = false) -> Dictionary:
	var a = sim.person(first)
	var b = sim.person(second)
	if not sim.life.is_alive(a) or not sim.life.is_alive(b) or first==second:
		return {"status":"decline","text":"一緒に取り組む相手を選んでください"}
	var project: Dictionary = sim.resident_activities.definition(a,b,preferred)
	if project.is_empty(): return {"status":"decline","text":"一緒に取り組めることを、まず相談したい。"}
	var hypothetical = {"mode":"project","project":project}
	for p in [a,b]:
		if not p.meeting_id.is_empty() or not meeting_compatible(p,hypothetical):
			return sim._reply(p,"counteroffer","今は外せない予定がある。%sは、二人の空いた時間に進めたい。"%project.title)
		if p.fatigue>.8:
			return sim._reply(p,"decline","今日は休んでからにしたい。好きなことも、気持ちに余裕があるときに取り組みたい。")
		if p.hunger>.75 or (autonomous and p.action=="eat" and p.get("action_elapsed",0)<20):
			return sim._reply(p,"defer","まず食事を済ませてから、落ち着いて取り組みたい。")
		if p.quiet>.8 and sim.social.relation(p,(b if p.id==a.id else a).id).familiarity<.4:
			return sim._reply(p,"counteroffer","まずは少し話して、お互いのやりたいことを知ってからにしたい。")
		if autonomous and not _wants_to_join(p,b if p.id==a.id else a,project):
			return sim._reply(p,"defer","今は自分の取り組みを進めたい。また余裕があるときに相談しよう。")
	if household(a).cash<project.cost:
		return sim._reply(a,"defer","一緒に取り組みたいけれど、材料の用意を先に考えたい。")
	if not sim._begin_meeting(a,b,project.center,"project",false,45,0,"",project.place,project.key):
		return sim._reply(a,"defer","作業台が使われている。空いてから一緒に取り組みたい。")
	var meeting = sim.meetings[-1]
	meeting.mode = "project"
	meeting.project = project
	meeting.materials_ready = false
	meeting.autonomous = autonomous
	sim.planner.track(meeting)
	a.action = "joint_work"
	b.action = "joint_work"
	a.reason = "%sさんと、%sを一緒に進めたい"%[b.name,project.title]
	b.reason = "%sさんと、%sに取り組むことにした"%[a.name,project.title]
	return sim._reply(a,"accept","%sさんと、%sを進めよう。まずは道具を広げる場所へ。"%[b.name,project.title])

func _wants_to_join(p: Dictionary, other: Dictionary, project: Dictionary) -> bool:
	var values: Dictionary = sim.definitions[p.id].values
	var relation: Dictionary = sim.social.relation(p,other.id)
	var interest := 1.0 if project.interest in p.interests else 0.0
	if "learning" in p.interests and project.get("learner","")==p.id: interest = maxf(interest,.7)
	var teaching: float = p.skills.get(project.skill,0)*(.4+.6*float(sim.definitions[p.id].traits.open_mindedness))
	var willingness: float = .35*interest+.25*teaching+.4*float(relation.trust)+.25*float(values.care)+.15*float(values.belonging)-.3*p.quiet-.2*p.fatigue
	return willingness>=.25

func project_tick(meeting: Dictionary) -> bool:
	if meeting.get("mode","")!="project": return true
	var a = sim.person(meeting.a)
	var b = sim.person(meeting.b)
	if not meeting.materials_ready:
		var h = household(a)
		if h.cash<meeting.project.cost:
			sim._log(a.id,"まずは材料の用意から","暮らしの出費があった。制作は、材料を用意してから改めて進めたい。")
			return false
		h.cash -= meeting.project.cost
		h.spent_today += meeting.project.cost
		meeting.materials_ready = true
	for p in [a,b]:
		p.fatigue = minf(1,p.fatigue+.0004)
		if meeting.project.key=="model" and p.id=="ryo" and sim._authored_routine_at(p).get("id","")=="after_school_care":
			p.care_minutes += 1
	return true

func finish_project(meeting: Dictionary) -> void:
	if meeting.get("mode","")!="project": return
	var key = meeting.project.key
	var before = projects[key]
	projects[key] = minf(1,projects[key]+.18)
	for id in [meeting.a,meeting.b]:
		var p = sim.person(id)
		var other: Dictionary = sim.person(meeting.b if id==meeting.a else meeting.a)
		if _advances_goal(p,meeting.project):
			p.goal_progress = minf(1,p.goal_progress+.18)
		else:
			p.private_project = minf(1,p.private_project+.18)
		if before<1 and projects[key]>=1:
			sim._remember(p,meeting.b if id==meeting.a else meeting.a,"二人で形にしたもの",meeting.project.title+"が、ひとつの形になった。次の誰かにも見せてみたい。","creation")
		sim.cognition.experience(p,other.id,"joint_work",{"place":meeting.project.place},
			{"enjoyment":.75 if p.quiet<.75 else .45,"burden":p.fatigue*.6,
			"skill":meeting.project.get("skill",""),"practice":.025+maxf(0,float(other.skills.get(meeting.project.get("skill",""),0))-float(p.skills.get(meeting.project.get("skill",""),0)))*.04})

func _advances_goal(p: Dictionary, project: Dictionary) -> bool:
	if p.goal_kind=="career": return false
	for word in project.get("goal_words",[]):
		if word in p.current_goal: return true
	return false

func _settle_day() -> void:
	for id in households:
		var h = households[id]
		var d = config.households[id]
		if not sim.people.any(func(p): return p.get("alive",true) and household_id(p)==id): continue
		var expenses = d.daily_basics+(d.season_housing if sim.day_index()%3==0 else 0)
		var support = 0 if id=="shared_house" and sim.person("aoi").stage=="moved" else d.daily_support
		for p in sim.people:
			if p.get("alive",true) and household_id(p)==id and p.career_retired:
				support += sim.life.config.retirement_support_away if id=="aoi_apartment" else sim.life.config.retirement_support
		h.cash += support-expenses
		h.ledger.append({"day":sim.day_index(),"earned":h.earned_today,"support":support,"expenses":h.spent_today+expenses,"balance":h.cash})
		if h.ledger.size()>60: h.ledger.pop_front()
		h.earned_today = 0
		h.spent_today = 0
	for p in sim.people: p.earned_today = 0
	sim._log("","一日の暮らしの記録","働いた時間と生活の出費を、各世帯の記録に残しました。")

func person_text(p: Dictionary) -> String:
	var h = household(p)
	var d = config.households[household_id(p)]
	var text = "%sの暮らし\n\n生活費の残り：%.1f\n今日の収入：%.1f\n家の用事：%d%%\n\n本人の今日の仕事：%.1f\n世話をした時間：%d分\n仕事への手応え：%d%%\n"%[d.label,h.cash,h.earned_today,int(h.home_load*100),p.earned_today,p.care_minutes,int(p.work_satisfaction*100)]
	if worry(p)>.5: text += "\nしばらくの出費が気になっている。\n"
	if p.id=="ryo": text += "\n凛との模型づくり：%d%%\n"%int(p.private_project*100)
	var own_project = {"aoi":"radio","osamu":"radio","rin":"model","nagisa":"bread","maho":"bread","fumi":"photo","ritsu":"music"}.get(p.id,"model")
	text += "\n二人で進める制作：%d%%\n"%int(projects[own_project]*100)
	for help in _active_supports():
		if help.state in ["travel","active","handoff"] and p.id in [help.giver,help.receiver]:
			text += "\n%sさんが%s。\n"%[sim.person(help.giver).name,"家に向かっている" if help.state=="travel" else "暮らしの用事を引き受けている"]
	if not h.ledger.is_empty():
		var last = h.ledger[-1]
		text += "\n昨日の収入・支え：%.1f\n昨日の出費：%.1f"%[last.earned+last.support,last.expenses]
	return text

func reserved(p: Dictionary, minute: int) -> bool:
	for help in _active_supports():
		if help.state in ["travel","active","handoff"] and help.giver==p.id and minute>=help.requested and minute<help.requested+(360 if help.kind=="care" else 180):
			return true
	return false

func serialize() -> Dictionary:
	return {"households":households,"supports":supports,"serial":serial,"projects":projects}

func restore(data: Dictionary) -> void:
	if data.is_empty():
		reset()
		return
	households = data.households
	if not households.has("aoi_apartment"):
		households.aoi_apartment = {"cash":0.0,"home_load":.3,"earned_today":0.0,"spent_today":0.0,"material_days":{},"ledger":[]}
	supports = data.supports
	serial = int(data.serial)
	projects = data.get("projects",{"radio":0.0,"model":0.0,"bread":0.0,"photo":0.0,"music":0.0,"craft":0.0})
	for p in sim.people: upgrade_person(p)

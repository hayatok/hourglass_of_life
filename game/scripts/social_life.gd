class_name SocialLife
extends RefCounted

# Social state is saved with the town. Proposals are possibilities, not memories.
var sim
var appointments: Array = []
var offer: Dictionary = {}
var serial: int = 0
var knowledge_exchange

func _init(simulation) -> void:
	sim = simulation
	knowledge_exchange = preload("res://game/scripts/resident_knowledge_exchange.gd").new(sim)

func reset() -> void:
	appointments.clear()
	offer.clear()
	serial = 0
	for p in sim.people:
		upgrade_person(p)

func upgrade_person(p: Dictionary) -> void:
	for key in {"habits":[],"action_elapsed":0,"habit_recorded":false}:
		if not p.has(key):
			p[key] = {"habits":[],"action_elapsed":0,"habit_recorded":false}[key]

func relation(p: Dictionary, other: String) -> Dictionary:
	return p.relationships.get(other,{"familiarity":.05,"trust":.2,"ease":.25,"unresolved_expectation":0.0})

func partner_score(p: Dictionary, other: Dictionary) -> float:
	if not other.get("alive",true): return -1
	var r = relation(p,other.id)
	return .35*r.familiarity+.4*r.ease+.25*r.trust-.4*r.unresolved_expectation

func venue_interest(p: Dictionary, venue: String) -> float:
	var interest = .1
	for other in sim.people:
		if other.get("alive",true) and other.id!=p.id and not other.moving and other.place==venue and sim._routine_at(other).is_empty():
			interest = maxf(interest,partner_score(p,other))
	return interest

func _period() -> String:
	var m = sim.minute_of_day()
	return "朝" if m<720 else ("午後" if m<1080 else "夜")

func habit_bonus(p: Dictionary, option: Dictionary) -> float:
	for habit in p.habits:
		if habit.kind==option.kind and habit.place==option.place and habit.cue==_period() and habit.days.size()>=3:
			return .10*habit.strength
	return 0

func activity_tick(p: Dictionary) -> void:
	p.action_elapsed += 1
	if p.habit_recorded or p.action_elapsed<20 or not p.routine_id.is_empty():
		return
	if p.action not in ["hobby","photo","rest","eat","social"]:
		return
	p.habit_recorded = true
	var habit: Dictionary = {}
	for existing in p.habits:
		if existing.kind==p.action and existing.place==p.place and existing.cue==_period():
			habit = existing
			break
	if habit.is_empty():
		habit = {"kind":p.action,"place":p.place,"cue":_period(),"days":[],"strength":0.0}
		p.habits.append(habit)
	var today = sim.day_index()
	var seen = false
	for day in habit.days:
		if int(day)==today: seen = true
	if not seen:
		habit.days.append(today)
		habit.strength = minf(.8,habit.days.size()*.12)
		if habit.days.size()==3:
			sim._remember(p,"","いつもの時間になってきた","%sにこの場所で%sことが、暮らしの一部になってきた。"%[habit.cue,sim.ACTION_NAMES.get(p.action,p.action)],"habit")

func propose(first: String, second: String, location: String) -> Dictionary:
	var a = sim.person(first)
	var b = sim.person(second)
	if not sim.life.is_alive(a) or not sim.life.is_alive(b) or first==second:
		return {"status":"decline","text":"一緒に過ごす相手を選んでください"}
	if location not in ["bench","cafe","workshop"]:
		return {"status":"decline","text":"待ち合わせる場所を選んでください"}
	offer.clear()
	for p in [a,b]:
		var other = b if p.id==a.id else a
		if not p.meeting_id.is_empty():
			return sim._reply(p,"defer","いま誰かと過ごす予定がある。その時間を大切にしたい。")
		if not sim._routine_at(p).is_empty() or sim._next_commitment(p).minutes<90:
			return _counteroffer(a,b,location,p,"今は%s。"%sim.commitment_text(p))
		if p.fatigue>.82:
			return sim._reply(p,"decline","今日は疲れている。まずは一人で休みたい。")
		var r = relation(p,other.id)
		if r.trust<.12 and r.unresolved_expectation>.5:
			return sim._reply(p,"decline","前に話せなかったことが、まだ気になっている。今すぐ二人では会いづらい。")
		if p.quiet>.8 and r.familiarity<.4:
			return _counteroffer(a,b,"cafe",p,"まだ慣れていないから、今度いつもの喫茶店で短く話したい。",15)
	var center = _center(a,b,location)
	if center==null:
		return _counteroffer(a,b,location,a,"今はベンチが使われている。")
	if not sim._begin_meeting(a,b,center,location,false):
		return _counteroffer(a,b,location,a,"今は席が使われている。")
	return sim._reply(a,"accept","%sさんと話してみよう。まずは待ち合わせの場所へ。"%b.name)

func _center(a: Dictionary, b: Dictionary, location: String) -> Variant:
	if location=="bench": return sim._available_bench((a.position+b.position)*.5,[a.id,b.id])
	if location=="cafe": return sim.SITES.bakery_cafe+Vector3(0,0,1.2)
	return sim.SITES.workshop+Vector3(0,0,1)

func _counteroffer(a: Dictionary, b: Dictionary, location: String, speaker: Dictionary, reason: String, duration: int = 25) -> Dictionary:
	var slot = find_slot(a,b,duration)
	if slot<0:
		return sim._reply(speaker,"defer",reason+"しばらく二人の空き時間が合わない。予定が変わったら、また相談したい。")
	offer = {"a":a.id,"b":b.id,"start":slot,"location":location,"duration":duration,"made_at":sim.elapsed}
	return sim._reply(speaker,"counteroffer",reason+"%sならどうかな。"%when_text(slot))

func when_text(minute: int) -> String:
	var absolute = sim.start_minute+minute
	var days = int(absolute/1440.0)-sim.day_index()
	var label = "今日" if days==0 else ("明日" if days==1 else "%d日後"%days)
	return "%s %02d:%02d"%[label,int((absolute%1440)/60.0),absolute%60]

func find_slot(a: Dictionary, b: Dictionary, duration: int = 25) -> int:
	if not sim.life.is_alive(a) or not sim.life.is_alive(b): return -1
	var first = int(ceil((sim.start_minute+sim.elapsed+120)/30.0))*30-sim.start_minute
	for minute in range(first,sim.elapsed+2881,30):
		if _slot_free(a,b,minute,duration): return minute
	return -1

func _slot_free(a: Dictionary, b: Dictionary, start: int, duration: int) -> bool:
	for p in [a,b]:
		for offset in range(-120,duration+16,15):
			if sim.agenda!=null and sim.agenda.reserved(p,start+offset): return false
			if sim.work_family!=null and sim.work_family.reserved(p,start+offset): return false
			var absolute = sim.start_minute+start+offset
			if not sim._routine_at(p,absolute%1440,(sim.epoch_weekday+int(absolute/1440.0))%7).is_empty():
				return false
		for planned in appointments:
			if planned.state=="planned" and p.id in [planned.a,planned.b] and absf(start-planned.start)<180:
				return false
	return true

func confirm_offer(selected: String) -> Dictionary:
	if offer.is_empty() or offer.a!=selected:
		return {"status":"defer","text":"まず二人に話す機会を提案してください"}
	var a = sim.person(offer.a)
	var b = sim.person(offer.b)
	if not sim.life.is_alive(a) or not sim.life.is_alive(b):
		offer.clear()
		return {"status":"decline","text":"その約束を、新たに作ることはできない。残された時間を思い返したい。"}
	if sim.elapsed>offer.made_at+180 or offer.start-sim.elapsed<120 or not _slot_free(a,b,offer.start,offer.duration):
		offer.clear()
		return sim._reply(a,"defer","その後、予定が変わった。もう一度時間を相談したい。")
	serial += 1
	var planned = offer.duplicate(true)
	planned.id = "appointment_%d"%serial
	planned.state = "planned"
	appointments.append(planned)
	offer.clear()
	sim._log(a.id,"二人の約束","%sに%sさんと会う約束をした。"%[when_text(planned.start),b.name])
	return sim._reply(a,"accept","%sに会うことになった。それまでは、それぞれの時間を過ごそう。"%when_text(planned.start))

func next_commitment(p: Dictionary) -> Dictionary:
	var result = {"minutes":2880,"id":""}
	for planned in appointments:
		if planned.state=="planned" and p.id in [planned.a,planned.b]:
			var gap = int(planned.start)-120-sim.elapsed
			if gap>0 and gap<result.minutes:
				result = {"minutes":gap,"id":"appointment"}
	return result

func tick() -> void:
	if not offer.is_empty() and sim.elapsed>offer.made_at+180: offer.clear()
	for planned in appointments:
		if planned.state!="planned" or sim.elapsed<planned.start-120: continue
		if sim.elapsed>planned.start+45:
			_postpone(planned,"ほかの予定が長引き、会う時間が取れなかった。")
			continue
		var a = sim.person(planned.a)
		var b = sim.person(planned.b)
		if not a.meeting_id.is_empty() or not b.meeting_id.is_empty(): continue
		if a.fatigue>.94 or b.fatigue>.94 or not sim._routine_at(a).is_empty() or not sim._routine_at(b).is_empty():
			_postpone(planned,"疲れや外せない予定があり、今日は休むことにした。")
			continue
		var center = _center(a,b,planned.location)
		if center==null:
			if sim.elapsed>planned.start+15:
				_postpone(planned,"待ち合わせの場所が空かなかった。")
			continue
		if not sim._begin_meeting(a,b,center,planned.location,false,planned.duration,planned.start,planned.id):
			if sim.elapsed>planned.start+15: _postpone(planned,"待ち合わせの席が空かなかった。")
			continue
		planned.state = "on_the_way"
		sim._log(a.id,"約束の時間に向けて","%sさんと会うために、待ち合わせの場所へ向かった。"%b.name)

func finish(m: Dictionary, completed: bool) -> void:
	for planned in appointments:
		if planned.id==m.get("appointment_id",""):
			if completed: planned.state = "kept"
			else: _postpone(planned,"次の予定や移動の都合で、話す時間を取れなかった。")
	if not completed: return
	var a = sim.person(m.a)
	var b = sim.person(m.b)
	var previous_knowledge := {a.id:a.knowledge.duplicate(true),b.id:b.knowledge.duplicate(true)}
	var topic = _topic(a,b)
	for pair in [[a,b],[b,a]]:
		var p = pair[0]
		var other = pair[1]
		var r = sim._relation(p,other.id)
		var repeats = 0
		for memory in p.memories:
			if memory.other==other.id and memory.kind=="shared_time" and int((sim.start_minute+memory.minute)/1440.0)==sim.day_index():
				repeats += 1
		var scale = 1.0/(1+repeats*3)
		var uneasy = r.unresolved_expectation>.65
		r.familiarity = minf(1,r.familiarity+.04*(1-r.familiarity)*scale)
		r.ease = clampf(r.ease+(-.012 if uneasy else .025*(1-p.quiet))*scale,0,1)
		r.trust = clampf(r.trust+(-.005 if uneasy else (.035 if not m.get("appointment_id","").is_empty() else .012))*scale,0,1)
		if not uneasy:
			r.unresolved_expectation = maxf(0,r.unresolved_expectation-.04*scale)
		p.quiet = minf(1,p.quiet+.08*(1-sim.definitions[p.id].traits.extraversion))
		var text = "%sさんと、%sを話した。"%[other.name,topic]
		if m.get("mode","")=="project": text = "%sさんと、%sに一緒に取り組んだ。"%[other.name,m.project.title]
		if uneasy: text += "まだ言葉にできないことも残った。"
		elif r.familiarity>.6: text += "よく知る相手だから、近況を落ち着いて伝えられた。"
		else: text += "相手の好きなことを、少し知ることができた。"
		sim._remember(p,other.id,"約束して過ごした時間" if not m.get("appointment_id","").is_empty() else "一緒に過ごした時間",text,"shared_time")
		if m.get("mode","")!="project":
			sim.cognition.experience(p,other.id,"social",{"place":p.place},
				{"enjoyment":.3 if uneasy else .7,"burden":p.quiet*.6})
	knowledge_exchange.exchange(a,b,previous_knowledge[a.id],previous_knowledge[b.id],m)

func _postpone(planned: Dictionary, reason: String) -> void:
	planned.state = "postponed"
	for pair in [[planned.a,planned.b],[planned.b,planned.a]]:
		var p = sim.person(pair[0])
		var other = sim.person(pair[1])
		var r = sim._relation(p,other.id)
		r.unresolved_expectation = minf(1,r.unresolved_expectation+.05*(1-sim.definitions[p.id].traits.agreeableness))
		sim._remember(p,other.id,"会う日を改めることにした","%sさんとは、また時間を相談したい。%s"%[other.name,reason],"promise_change")

func _topic(a: Dictionary, b: Dictionary) -> String:
	return sim.resident_activities.topic(a,b)

func person_text(p: Dictionary) -> String:
	var text = ""
	for planned in appointments:
		if planned.state in ["planned","on_the_way"] and p.id in [planned.a,planned.b]:
			var other = planned.b if planned.a==p.id else planned.a
			text += "%s：%sさんと会う約束\n"%[when_text(planned.start),sim.person(other).name]
	for habit in p.habits:
		if habit.days.size()>=3:
			text += "%sの習慣：%s（別々の%d日で繰り返した）\n"%[habit.cue,sim.ACTION_NAMES.get(habit.kind,habit.kind),habit.days.size()]
	return text

func serialize() -> Dictionary:
	return {"appointments":appointments,"offer":offer,"serial":serial}

func restore(data: Dictionary) -> void:
	appointments = data.get("appointments",[])
	offer = data.get("offer",{})
	serial = int(data.get("serial",0))
	if not offer.is_empty() and sim.elapsed>offer.made_at+180: offer.clear()
	for p in sim.people: upgrade_person(p)

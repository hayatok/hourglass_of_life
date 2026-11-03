class_name ResidentAgenda
extends RefCounted

# A future agreement reserves time, not a completed experience or a piece of furniture.
const ACTIVE = ["planned","travel"]
const MAX_ACTIVE_PER_PERSON := 2
const MAX_RECORDS := 64
const HORIZON := 2880
const GRACE := 15
var sim
var records: Array = []
var serial := 0
# Synchronous admission checks must ignore the agreement being dispatched.
var dispatch_id := ""

func _init(simulation) -> void:
	sim = simulation

func reset() -> void:
	records.clear()
	serial = 0
	dispatch_id = ""

func propose(a_id: String, b_id: String, activity_key: String = "social", autonomous: bool = false) -> Dictionary:
	var a: Dictionary = sim.person(a_id)
	var b: Dictionary = sim.person(b_id)
	if a_id==b_id or not sim.life.is_alive(a) or not sim.life.is_alive(b):
		return {"status":"decline","text":"予定を相談する相手を選んでください"}
	for record in records:
		if a_id not in [record.a,record.b] or b_id not in [record.a,record.b] or record.activity!=activity_key: continue
		if record.state in ACTIVE:
			return _reply(a,"defer","その予定はもう相談できている。約束の時間を大切にしたい。",record)
		if sim.elapsed-int(record.get("finished_at",record.made_at))<180:
			return _reply(a,"defer","さっきの予定を振り返ってから、次の機会を相談したい。")
	for p in [a,b]:
		if _active_count(p.id)>=MAX_ACTIVE_PER_PERSON:
			return _reply(p,"defer","先に約束した時間を過ごしてから、次の予定を考えたい。")
	var activity := _activity(a,b,activity_key)
	if activity.is_empty(): return _reply(a,"defer","その活動を一緒にできる場所を、先に探したい。")
	for p in [a,b]:
		var other: Dictionary = b if p.id==a.id else a
		var agreement := _agreement(p,other,activity,autonomous)
		if agreement.status!="accept": return _reply(p,agreement.status,agreement.text)
		if agreement.get("shorter",false):
			activity.venue = "cafe"
			activity.place = "bakery_cafe"
			activity.group = "cafe"
			activity.center = sim.SITES.bakery_cafe+Vector3(0,0,1.2)
			activity.duration = 15
	var pair := _physical_pair(activity,[a.id,b.id])
	if pair.size()!=2: return _reply(a,"defer","二人で使える場所が見つからない。場所を整えてから相談したい。")
	var slot := _find_slot(a,b,activity,pair)
	if slot.is_empty(): return _reply(a,"defer","この二日では二人の時間が合わない。暮らしが落ち着いてから相談したい。")
	serial += 1
	var record := {"id":"agenda_%d"%serial,"a":a.id,"b":b.id,"activity":activity_key,
		"title":activity.title,"start":slot.start,"duration":int(activity.duration),
		"place":activity.place,"center":activity.center,"venue":activity.venue,
		"state":"planned","made_at":int(sim.elapsed),"origin":"resident" if autonomous else "player",
		"attempts":0,"last_try":-1,"meeting_id":"","departures":slot.departures,
		"returns":slot.returns,"shared_before":{},"finished_at":-1}
	records.append(record)
	_trim()
	var when: String = sim.social.when_text(record.start)
	return _reply(a,"accept","%sさんと相談して、%sに%s時間を取ることにした。それまでは、それぞれの暮らしを続けよう。"%[b.name,when,activity.title],record)

func tick() -> void:
	for record in records:
		if record.state not in ACTIVE: continue
		var a: Dictionary = sim.person(record.a)
		var b: Dictionary = sim.person(record.b)
		if not sim.life.is_alive(a) or not sim.life.is_alive(b):
			_close(record,"ended","この約束は、ここまでの時間として残しておこう。")
			continue
		if record.state=="travel":
			var meeting := _meeting(record.meeting_id)
			if not meeting.is_empty(): continue
			# The direct finish hook is authoritative. This handles a restored or
			# externally removed meeting without inventing a successful encounter.
			var shared := true
			for p in [a,b]:
				var other: String = b.id if p.id==a.id else a.id
				if _shared_count(p,other)<=int(record.shared_before.get(p.id,0)): shared = false
			_close(record,"kept" if shared else "postponed","約束の時間を過ごした。" if shared else "合流や予定の都合が変わった。次の機会は改めて相談したい。")
			continue
		if sim.elapsed>int(record.start)+GRACE:
			_close(record,"postponed","予定どおりに合流できなかった。次の機会は改めて相談したい。")
			continue
		var departure: int = mini(int(record.departures.get(a.id,record.start)),int(record.departures.get(b.id,record.start)))
		if sim.elapsed<departure or (record.last_try>=0 and sim.elapsed-int(record.last_try)<15): continue
		_dispatch(record,a,b)

func finish(meeting: Dictionary, completed: bool) -> void:
	var id: String = meeting.get("agenda_id","")
	if id.is_empty(): return
	for record in records:
		if record.id!=id or record.state not in ACTIVE: continue
		var alive: bool = sim.life.is_alive(sim.person(record.a)) and sim.life.is_alive(sim.person(record.b))
		_close(record,"kept" if completed else ("postponed" if alive else "ended"),
			"約束していた時間を過ごした。" if completed else ("予定が変わり、今回は途中で終えることにした。" if alive else "この約束は、ここまでの時間として残しておこう。"))
		return

func next_commitment(p: Dictionary) -> Dictionary:
	var result := {"minutes":HORIZON,"id":""}
	for record in records:
		if record.id==dispatch_id or record.state not in ACTIVE or p.id not in [record.a,record.b]: continue
		if not record.meeting_id.is_empty() and record.meeting_id==p.meeting_id: continue
		var gap: int = maxi(0,int(record.departures.get(p.id,record.start))-int(sim.elapsed))
		if gap<int(result.minutes): result = {"minutes":gap,"id":"agenda","agenda_id":record.id,"place":record.place,"start":record.start}
	return result

func reserved(p: Dictionary, minute: int) -> bool:
	for record in records:
		if record.id==dispatch_id or record.state not in ACTIVE or p.id not in [record.a,record.b]: continue
		if minute>=int(record.departures.get(p.id,record.start)) and minute<int(record.returns.get(p.id,int(record.start)+int(record.duration))): return true
	return false

func serialize() -> Dictionary:
	return {"records":records.duplicate(true),"serial":serial}

func restore(data: Dictionary) -> void:
	records = data.get("records",[]).duplicate(true)
	serial = int(data.get("serial",0))
	dispatch_id = ""
	for record in records:
		if str(record.id).begins_with("agenda_"): serial = maxi(serial,int(str(record.id).trim_prefix("agenda_")))
	_trim()

func person_text(p: Dictionary) -> String:
	var lines: Array[String] = []
	for record in records:
		if record.state not in ACTIVE or p.id not in [record.a,record.b]: continue
		if not record.meeting_id.is_empty() and record.meeting_id==p.meeting_id: continue
		var other: Dictionary = sim.person(record.b if record.a==p.id else record.a)
		if not sim.life.is_alive(other): continue
		lines.append("%s：%sさんと%s"%[sim.social.when_text(record.start),other.name,record.title])
	return "\n".join(lines)

func _activity(a: Dictionary, b: Dictionary, key: String) -> Dictionary:
	if key=="social":
		if sim.benches.is_empty(): return {}
		var center: Vector3 = sim.benches[0]
		var midpoint: Vector3 = (a.position+b.position)*.5
		for bench in sim.benches:
			if bench.distance_squared_to(midpoint)<center.distance_squared_to(midpoint): center = bench
		return {"key":"social","title":"ゆっくり話す","place":"square","center":center,"group":"bench","venue":"bench","duration":25}
	var activity: Dictionary = sim.resident_activities.definition(a,b,key)
	if activity.is_empty(): return {}
	activity.payer = a.id
	activity.group = activity.key
	activity.venue = "project"
	return activity

func _agreement(p: Dictionary, other: Dictionary, activity: Dictionary, autonomous: bool) -> Dictionary:
	if p.fatigue>.82: return {"status":"decline","text":"今は疲れている。まず休んでから予定を考えたい。"}
	if p.hunger>.75: return {"status":"defer","text":"まず食事を済ませてから、落ち着いて予定を相談したい。"}
	var relation: Dictionary = sim.social.relation(p,other.id)
	if relation.trust<.12 and relation.unresolved_expectation>.5:
		return {"status":"decline","text":"前の約束がまだ気になっている。今すぐ次の予定は決めづらい。"}
	if p.quiet>.8 and relation.familiarity<.4:
		if activity.key=="social": return {"status":"accept","shorter":true}
		return {"status":"defer","text":"まず短く話して、お互いのやりたいことを知ってから相談したい。"}
	if activity.key!="social":
		if not sim.work_family._wants_to_join(p,other,activity): return {"status":"defer","text":"今は自分の取り組みを進めたい。余裕ができたらまた相談したい。"}
		if p.id==activity.get("payer","") and sim.work_family.household(p).cash<float(activity.cost):
			return {"status":"defer","text":"材料を用意する前に、暮らしの出費を考えたい。"}
	elif autonomous:
		var values: Dictionary = sim.definitions[p.id].values
		if .35*float(values.belonging)+.35*float(relation.trust)+.3*float(relation.ease)-.2*p.fatigue-.2*p.quiet<.2:
			return {"status":"defer","text":"今は一人の時間を取りたい。落ち着いてから相談しよう。"}
	return {"status":"accept"}

func _physical_pair(activity: Dictionary, participants: Array) -> Array:
	var pairs := {}
	for spot in sim.activities.spots.values():
		if spot.group!=activity.group or spot.site!=activity.place: continue
		if activity.group=="bench" and spot.contact.distance_to(activity.center)>.9: continue
		if not spot.resident.is_empty() and spot.resident not in participants: continue
		if not pairs.has(spot.pair): pairs[spot.pair] = []
		pairs[spot.pair].append(spot)
	var choices: Array = []
	for pair in pairs.values():
		if pair.size()>=2: choices.append(pair)
	choices.sort_custom(func(a,b): return a[0].approach.distance_squared_to(activity.center)<b[0].approach.distance_squared_to(activity.center))
	return choices[0].slice(0,2) if not choices.is_empty() else []

func _find_slot(a: Dictionary, b: Dictionary, activity: Dictionary, pair: Array) -> Dictionary:
	var trips := {}
	for index in 2:
		var p: Dictionary = a if index==0 else b
		trips[p.id] = _travel(p.position,p.place,pair[index].approach,activity.place)+5
	var longest: int = maxi(trips[a.id],trips[b.id])
	var return_trips := {}
	var first: int = int(ceil(float(sim.start_minute+sim.elapsed+longest+10)/15.0))*15-int(sim.start_minute)
	for start in range(first,int(sim.elapsed)+HORIZON+1,15):
		var departures := {}
		var returns := {}
		var free := true
		for index in 2:
			var p: Dictionary = a if index==0 else b
			# The current meeting API sends both people together. Reserve that
			# common preparation window even for the nearer participant.
			departures[p.id] = start-longest
			var end: int = start+int(activity.duration)
			var next := _next_routine(p,end)
			if not next.is_empty():
				var route_key: String = p.id+":"+str(next.place)
				if not return_trips.has(route_key): return_trips[route_key] = _travel(pair[index].approach,activity.place,next.position,next.place)+5
				end += int(return_trips[route_key])
			if activity.key=="social": end = maxi(end,int(departures[p.id])+90)
			returns[p.id] = end
			if not _window_free(p,int(departures[p.id]),end): free = false;break
		if free: return {"start":start,"departures":departures,"returns":returns}
	return {}

func _window_free(p: Dictionary, begin: int, end: int) -> bool:
	if begin<int(sim.elapsed) or end<=begin or begin<_busy_until(p): return false
	var first_day: int = int(floor(float(sim.start_minute+begin)/1440.0))-1
	var last_day: int = int(floor(float(sim.start_minute+end)/1440.0))
	for day in range(first_day,last_day+1):
		var week: int = posmod(int(sim.epoch_weekday)+day,7)
		for routine in sim.life.routines(p):
			if week not in routine.on_days: continue
			var start: int = day*1440+int(routine.start_minute)-int(sim.start_minute)
			if begin<start+int(routine.duration_minutes) and start<end: return false
	for help in sim.work_family.supports:
		if help.get("giver","")!=p.id: continue
		var point: int = maxi(begin,int(help.requested))
		if point<end and sim.work_family.reserved(p,point): return false
	for planned in sim.social.appointments:
		if planned.state not in ["planned","on_the_way"] or p.id not in [planned.a,planned.b]: continue
		if begin<int(planned.start)+int(planned.duration)+15 and int(planned.start)-120<end: return false
	for record in records:
		if record.id==dispatch_id or record.state not in ACTIVE or p.id not in [record.a,record.b]: continue
		if begin<int(record.returns.get(p.id,int(record.start)+int(record.duration))) and int(record.departures.get(p.id,record.start))<end: return false
	return true

func _next_routine(p: Dictionary, after: int) -> Dictionary:
	var result: Dictionary = {}
	var first_day: int = int(floor(float(sim.start_minute+after)/1440.0))
	for day in range(first_day,first_day+3):
		var week: int = posmod(int(sim.epoch_weekday)+day,7)
		for routine in sim.life.routines(p):
			if week not in routine.on_days: continue
			var start: int = day*1440+int(routine.start_minute)-int(sim.start_minute)
			if start<after or (not result.is_empty() and start>=int(result.start)): continue
			var place: String = sim._place_for(p,routine.place)
			result = {"start":start,"place":place,"position":sim.SITES[place]}
	return result

func _busy_until(p: Dictionary) -> int:
	var meeting := _meeting(p.meeting_id)
	if meeting.is_empty(): return int(sim.elapsed)
	var remaining: int = int(meeting.remaining)
	if meeting.state in ["travel","waiting"]:
		var other: Dictionary = sim.person(meeting.b if meeting.a==p.id else meeting.a)
		remaining += maxi(_path_minutes(p),_path_minutes(other))
	return maxi(int(sim.elapsed),int(meeting.get("not_before",0)))+remaining+5

func _dispatch(record: Dictionary, a: Dictionary, b: Dictionary) -> void:
	record.attempts += 1
	record.last_try = int(sim.elapsed)
	for p in [a,b]:
		if p.action in ["eat","sleep"] or p.hunger>.75 or p.fatigue>.82:
			if record.attempts>=3 or sim.elapsed>=int(record.start)+GRACE:
				_close(record,"postponed","食事や休息を先にして、今回は見送ることにした。次の機会は改めて相談したい。")
			elif record.attempts==1:
				sim._log(p.id,"暮らしを先にする","約束の準備より、まず食事や休息を済ませたい。")
			return
	var activity := _activity(a,b,record.activity)
	if activity.is_empty():
		_close(record,"postponed","予定していた活動が変わった。次の機会を改めて相談したい。")
		return
	activity.place = record.place
	activity.center = record.center
	activity.group = record.venue if record.activity=="social" else record.activity
	var pair := _physical_pair(activity,[a.id,b.id])
	if pair.size()!=2:
		_close(record,"postponed","使う予定だった場所がなくなった。場所を整えてから改めて相談したい。")
		return
	var journey := 0
	for index in 2:
		var p: Dictionary = a if index==0 else b
		journey = maxi(journey,_travel(p.position,p.place,pair[index].approach,record.place))
	if sim.elapsed+journey>int(record.start)+GRACE:
		_close(record,"postponed","移動に必要な時間が変わった。無理に急がず、次の機会を相談したい。")
		return
	dispatch_id = record.id
	var saved_offer: Dictionary = sim.social.offer.duplicate(true)
	var reply: Dictionary
	if record.activity=="social": reply = sim.social.propose(a.id,b.id,record.venue)
	else: reply = sim.work_family.propose_project(a.id,b.id,record.activity,record.origin=="resident")
	sim.social.offer = saved_offer
	dispatch_id = ""
	if reply.status!="accept":
		if record.attempts>=3 or sim.elapsed>=int(record.start)+GRACE:
			_close(record,"postponed","その後の暮らしや予定が変わった。今回は見送り、次の機会を改めて相談したい。")
		return
	var meeting: Dictionary = sim.meetings[-1]
	meeting.agenda_id = record.id
	meeting.autonomous = record.origin=="resident"
	meeting.appointment_id = record.id
	meeting.not_before = record.start
	meeting.remaining = record.duration
	record.meeting_id = meeting.id
	record.state = "travel"
	record.shared_before = {a.id:_shared_count(a,b.id),b.id:_shared_count(b,a.id)}
	for p in [a,b]: p.remaining = record.duration
	sim.planner.track(meeting)
	sim._log(a.id,"約束の場所へ向かう","%sさんと約束した%sの時間に向けて、移動を始めた。"%[b.name,record.title])

func _close(record: Dictionary, state: String, text: String) -> void:
	if record.state not in ACTIVE: return
	record.state = state
	record.finished_at = int(sim.elapsed)
	sim._log(record.a,"約束を過ごした" if state=="kept" else "約束の区切り",text)

func _reply(p: Dictionary, status: String, text: String, record: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim._reply(p,status,text)
	if not record.is_empty():
		result.record_id = record.id
		result.start = record.start
		result.alternative = true
	return result

func _active_count(id: String) -> int:
	var count := 0
	for record in records:
		if record.state in ACTIVE and id in [record.a,record.b]: count += 1
	return count

func _meeting(id: String) -> Dictionary:
	if id.is_empty(): return {}
	for meeting in sim.meetings:
		if meeting.id==id: return meeting
	return {}

func _shared_count(p: Dictionary, other: String) -> int:
	var count := 0
	for memory in p.memories:
		if memory.kind=="shared_time" and memory.other==other: count += 1
	return count

func _travel(origin: Vector3, place: String, target: Vector3, destination: String) -> int:
	var distance := 0.0
	var previous := origin
	for point in sim.route(origin,place,target,destination):
		distance += previous.distance_to(point)
		previous = point
	return int(ceil(distance/sim.WALK_METERS_PER_MINUTE))

func _path_minutes(p: Dictionary) -> int:
	var distance := 0.0
	var previous: Vector3 = p.position
	for point in p.path:
		distance += previous.distance_to(point)
		previous = point
	return int(ceil(distance/sim.WALK_METERS_PER_MINUTE))

func _trim() -> void:
	while records.size()>MAX_RECORDS:
		var removed := false
		for index in records.size():
			if records[index].state in ACTIVE: continue
			records.remove_at(index)
			removed = true
			break
		if not removed: break

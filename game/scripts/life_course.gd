class_name LifeCourse
extends RefCounted

var sim
var config: Dictionary
var announced: Array = []
var applied: Array = []
var legacy: Array = []
var chronicle: Array = []
var year_seen: int = 0
var chapter_ready: bool = false
var chapter_acknowledged: bool = false
var chapter_mode: String = "three_years"
var final_reviewed: bool = false

const LEGACY_LABELS = {"nagisa":"季節のパンのレシピ", "ryo":"仕事と暮らしのスケッチ", "rin":"町の模型と作り方", "osamu":"ラジオと修理の記録", "fumi":"町の写真帖", "maho":"店に集まる人のノート", "ritsu":"音楽の録音とメモ", "aoi":"制作と暮らしの記録"}
const NEXT_WISHES = {"nagisa":"家族の休日に焼くパンを考えたい", "ryo":"凛と、今の年齢ならではの町の模型を作りたい", "rin":"自分で見つけた町の好きな場所を模型にしたい", "osamu":"工房で、自分のためのものをもう一つ作りたい", "fumi":"以前の景色と今の景色を、一冊に並べたい", "maho":"初めて来た人の居場所になる店を続けたい", "ritsu":"暮らしの変わった友人にも聴いてもらえる曲を作りたい", "aoi":"町外の仕事の経験と、町で過ごす時間をつなぎたい"}

func _init(simulation) -> void:
	sim = simulation
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/life-course.json"))

func reset() -> void:
	announced.clear()
	applied.clear()
	legacy.clear()
	chronicle.clear()
	year_seen = 0
	chapter_ready = false
	chapter_acknowledged = false
	chapter_mode = "three_years"
	final_reviewed = false
	for p in sim.people: upgrade_person(p)

func upgrade_person(p: Dictionary) -> void:
	var d = sim.definitions[p.id]
	var defaults = {"base_age":int(d.age_years),"alive":true,"stage":"initial","current_goal":d.goals[0],"goal_kind":"career" if p.id in ["ryo","maho"] else "creative","known_plans":[],"goal_history":[],"legacy_read_id":"","legacy_read_recorded":false,"household_override":"","career_retired":false,"inspiration":{}}
	for key in defaults:
		if not p.has(key): p[key] = defaults[key]

func is_alive(p: Dictionary) -> bool:
	return not p.is_empty() and p.get("alive",true)

func routines(p: Dictionary) -> Array:
	if not is_alive(p): return []
	if p.id=="aoi" and p.stage=="moved":
		var away: Array = [
			{"id":"sleep","on_days":[0,1,2,3,4,5,6],"start_minute":0,"duration_minutes":480,"place":"off_map_home"},
			{"id":"new_work","on_days":[0,1,2,3,4],"start_minute":540,"duration_minutes":540,"place":"off_map_workplace"},
			{"id":"away_private","on_days":[0,1,2,3,4,5],"start_minute":0,"duration_minutes":1440,"place":"off_map_home","action":"own_life"},
			{"id":"away_private","on_days":[6],"start_minute":0,"duration_minutes":720,"place":"off_map_home","action":"own_life"},
			{"id":"away_private","on_days":[6],"start_minute":1080,"duration_minutes":360,"place":"off_map_home","action":"own_life"}
		]
		if p.career_retired: away = away.filter(func(r): return r.id!="new_work")
		return away
	var result: Array = []
	if p.id=="ritsu" and p.career_retired:
		result.append({"id":"sleep","on_days":[0,1,2,3,4,5,6],"start_minute":1380,"duration_minutes":480,"place":"home"})
	for r in sim.definitions[p.id].routines:
		if p.career_retired and r.id in ["bakery_shift","remote_work","cafe_shift","night_shift","post_shift_sleep","off_shift_sleep","school"]: continue
		if p.id=="osamu" and p.stage=="retired" and r.id=="workshop": continue
		if p.id=="ryo" and sim.person("rin").age>=config.care_independence_age and r.id=="after_school_care": continue
		if p.id=="rin" and p.age>=config.care_independence_age:
			if r.id=="after_school_home": continue
			if r.id=="sleep":
				result.append({"id":"sleep","on_days":[0,1,2,3,4,5,6],"start_minute":1380,"duration_minutes":480,"place":"home"})
				continue
			if r.id=="school" and p.age>=18:
				result.append({"id":"model_work","on_days":[0,1,2,3,4],"start_minute":540,"duration_minutes":480,"place":"workshop"} if p.age>=22 else {"id":"classes","on_days":[0,1,3,4],"start_minute":600,"duration_minutes":360,"place":"off_map_school"})
				continue
		result.append(r)
	return result

func home_for(p: Dictionary) -> String:
	if p.id=="aoi" and p.stage=="moved":
		if sim.weekday()==6 and sim.minute_of_day()>=720 and sim.minute_of_day()<1080: return "home_shared"
		return "off_map_home"
	return sim.HOME[sim.definitions[p.id].household_id]

func tick() -> void:
	if not sim.people.any(func(p): return is_alive(p)):
		if not final_reviewed and not chapter_ready:
			chapter_mode = "last"
			chapter_ready = true
			sim.running = false
			sim.chapter_reached.emit()
		return
	var year = int(sim.day_index()/12.0)
	if year>year_seen:
		year_seen = year
		for p in sim.people:
			if not is_alive(p): continue
			p.age = int(p.base_age)+year
			if p.id=="rin" and p.age>=22: p.occupation = "町の模型工房で働く人"
			elif p.id=="rin" and p.age>=18: p.occupation = "町から専門学校へ通う学生"
			elif p.id=="rin" and p.age>=12: p.occupation = "自分で過ごす時間が増えた生徒"
			if p.age>=config.end_ages[p.id]:
				_end_life(p)
				continue
			if p.goal_notified: _next_wish(p)
		_record("year","町に一年が積もった","生活の週は続いたまま、住人が一つ歳を重ねた。")
		sim.town_changed.emit()
	var day = sim.day_index()
	var minute = sim.minute_of_day()
	if day>=config.announce_day and (day>config.announce_day or minute>=600):
		if not "aoi_move" in announced: _announce("aoi_move","aoi","卒業後の暮らしを考えている","次の春から町外の工房で働くことになった。帰ってくる日も、町の人と会いたい。")
		if not "osamu_retire" in announced: _announce("osamu_retire","osamu","工房の時間を変えようと思う","次の春で店の定時営業を終え、自分の制作や、引き受けたい修理に時間を使いたい。")
	if day>=config.transition_day and (day>config.transition_day or minute>=540):
		if not "aoi_move" in applied: _move_aoi()
		if not "osamu_retire" in applied: _retire_osamu()
	for id in config.career_changes:
		var p = sim.person(id)
		if not is_alive(p): continue
		var due = (int(config.career_changes[id])-int(p.base_age))*12
		var key = "career_"+id
		if day>=due-6 and not key in announced:
			_announce(key,id,"仕事に使う時間を変えたい","次の春で定時の勤務を終え、自分の制作や身近な人との時間を増やすことにした。")
		if day>=due and (day>due or minute>=540) and not key in applied: _retire_career(p,key)
	if day>=config.chapter_review_day and not chapter_acknowledged and not chapter_ready:
		chapter_mode = "three_years"
		chapter_ready = true
		sim.running = false
		sim.chapter_reached.emit()

func _announce(key: String, owner: String, title: String, text: String) -> void:
	announced.append(key)
	var p = sim.person(owner)
	p.known_plans.append(key)
	sim._remember(p,"",title,text,"future_plan")
	for other in sim.people:
		if other.id==owner or not is_alive(other): continue
		var r = sim.social.relation(p,other.id)
		if r.familiarity>=.3 and r.trust>=.4:
			other.known_plans.append(key)
			sim._remember(other,owner,"これからの予定を聞いた","%sさんから、%s"%[p.name,text],"future_plan")
	_record(key,title,text)

func _move_aoi() -> void:
	applied.append("aoi_move")
	var p = sim.person("aoi")
	if not is_alive(p): return
	var old_house = sim.work_family.household(p)
	var share = maxf(0,old_house.cash/3.0)
	old_house.cash -= share
	sim.work_family.households.aoi_apartment.cash += share
	p.household_override = "aoi_apartment"
	p.stage = "moved"
	p.occupation = "町外の工房で働き、日曜に帰省する人"
	p.goal_history.append({"goal":p.current_goal,"progress":p.goal_progress,"minute":sim.elapsed,"reason":"卒業と転居"})
	p.current_goal = "新しい仕事に慣れ、町の人に近況を伝えたい"
	p.goal_kind = "career"
	p.goal_progress = 0.0
	p.goal_notified = false
	p.routine_id = ""
	p.remaining = 0
	sim._remember(p,"","卒業して、新しい家へ","町外の工房で働く暮らしが始まった。日曜の昼から夕方には、町に帰ってこようと思う。","move")
	_record("aoi_moved","葵の暮らしが変わった","葵は卒業して転居した。町で会えるのは日曜12:00〜18:00になった。")
	sim.town_changed.emit()

func _retire_osamu() -> void:
	applied.append("osamu_retire")
	var p = sim.person("osamu")
	if not is_alive(p): return
	p.stage = "retired"
	p.career_retired = true
	p.occupation = "定時営業を終え、自分の制作を続ける職人"
	p.routine_id = ""
	p.remaining = 0
	sim._remember(p,"","工房の定時営業を終えた","引き受ける仕事と、自分のための制作を、そのつど考えて過ごしたい。","retirement")
	_record("osamu_retired","修の工房の時間が変わった","定時の修理受付を終えた。修は、工房で作りたいものや引き受けたい仕事を自分で選ぶ。")
	sim.town_changed.emit()

func _next_wish(p: Dictionary) -> void:
	p.goal_history.append({"goal":p.current_goal,"progress":p.goal_progress,"minute":sim.elapsed,"reason":"新しい年"})
	p.current_goal = NEXT_WISHES[p.id]
	if p.id=="aoi" and p.stage!="moved": p.current_goal = "直したラジオを通じて、もう少し道具のことを知りたい"
	p.goal_kind = "model" if p.id=="ryo" else ("career" if not p.career_retired and p.id in ["maho","aoi"] and (p.id!="aoi" or p.stage=="moved") else "creative")
	p.goal_progress = 0.0
	p.goal_notified = false
	sim._remember(p,"","次にやってみたいこと",p.current_goal,"new_wish")

func action_bonus(p: Dictionary, option: Dictionary) -> float:
	var bonus = 0.0
	if not p.inspiration.is_empty() and sim.elapsed<p.inspiration.until and option.kind==p.inspiration.kind:
		bonus += .06*sim.definitions[p.id].traits.open_mindedness
	if not p.known_plans.any(func(key): return key in announced and not key in applied): return bonus
	var values = sim.definitions[p.id].values
	if option.kind=="social": bonus += .09*values.belonging
	if option.kind=="hobby": bonus += .09*values.achievement
	return bonus

func _retire_career(p: Dictionary, key: String) -> void:
	applied.append(key)
	p.career_retired = true
	p.goal_history.append({"goal":p.current_goal,"progress":p.goal_progress,"minute":sim.elapsed,"reason":"働く時間の変更"})
	p.current_goal = "これまでの仕事や好きなことを、自分の手で記録にまとめたい" if p.id=="aoi" else NEXT_WISHES[p.id]
	p.goal_kind = "model" if p.id=="ryo" else "creative"
	p.goal_progress = 0.0
	p.goal_notified = false
	p.routine_id = ""
	p.remaining = 0
	p.occupation = {"nagisa":"朝の製造担当を終え、好きなパンを焼く人","ryo":"定時の受注を終え、模型と暮らしを続ける人","maho":"定時勤務を終え、町の集まりを楽しむ人","ritsu":"夜勤を終え、音楽と自分の暮らしを続ける人","rin":"模型工房の定時勤務を終えた人","aoi":"町外の定時勤務を終え、日曜には帰省する人"}[p.id]
	sim._remember(p,"","働く時間を変えた","定時の勤務を終えた。これから何に時間を使うか、自分のペースで考えたい。","retirement")
	_record(key,p.name+"の働き方が変わった","勤務に使っていた時間を、自分の取り組みや暮らしの時間として選べるようになった。")
	sim.town_changed.emit()

func goal_completed(p: Dictionary) -> void:
	var existing: Dictionary = {}
	for item in legacy:
		if item.owner==p.id:
			existing = item
			break
	if existing.is_empty():
		var place = "workshop" if p.id in ["aoi","osamu"] else ("bakery_cafe" if p.id in ["nagisa","maho"] else ("home_ogawa" if p.id in ["ryo","rin"] else "square"))
		var side = -1 if p.id in ["nagisa","ryo","osamu","fumi"] else 1
		var center: Vector3 = sim.SITES[place]+Vector3(side*(2.7 if place=="square" else 1.7),0,4.6 if place=="square" else 1.3)
		existing = {"id":"legacy_"+p.id,"owner":p.id,"label":LEGACY_LABELS[p.id],"place":place,"position":center,"created":sim.elapsed,"edition":0,"entries":[],"readers":[],"uses":0}
		legacy.append(existing)
	existing.edition += 1
	existing.entries.append({"goal":p.current_goal,"minute":sim.elapsed})
	_record(existing.id,"町に残るもの",p.name+"の「"+existing.label+"」を、ほかの人も見られる場所に置いた。")
	sim.town_changed.emit()

func add_options(p: Dictionary, options: Array) -> void:
	for item in legacy:
		if item.owner==p.id or _has_read(item,p.id): continue
		options.append({"kind":"legacy","place":item.place,"target":item.position+Vector3(0,0,.6),"legacy_id":item.id,"need":maxf(.3,p.connection*.5),"goal":sim.definitions[p.id].values.creativity,"relation":sim.social.relation(p,item.owner).familiarity,"role":.3,"habit":.3,"fun":.7,"cost":p.fatigue*.3,"reason":"%sさんの%sを、ゆっくり見てみたい"%[sim.person(item.owner).name,item.label]})

func _has_read(item: Dictionary, id: String) -> bool:
	for reader in item.readers:
		if reader.id==id and int(reader.edition)==int(item.edition): return true
	return false

func activity_tick(p: Dictionary) -> void:
	if p.action!="legacy" or p.legacy_read_recorded or p.action_elapsed<20: return
	for item in legacy:
		if item.id!=p.legacy_read_id or _has_read(item,p.id): continue
		item.readers.append({"id":p.id,"edition":item.edition,"minute":sim.elapsed})
		item.uses += 1
		p.legacy_read_recorded = true
		p.private_project = minf(1,p.private_project+.05)
		p.inspiration = {"kind":"photo" if item.owner=="fumi" else "hobby","source":item.owner,"title":item.label,"until":sim.elapsed+2880}
		sim._remember(p,item.owner,"誰かが残したものから","%sさんの%sを見た。作り方や、その人が気にかけていたことを、自分の取り組みの参考にしたい。"%[sim.person(item.owner).name,item.label],"inheritance")

func _end_life(p: Dictionary) -> void:
	p.alive = false
	p.stage = "remembered"
	p.occupation = "町に残る記憶"
	p.action = "remembered"
	p.reason = "一緒に過ごした時間と、残したものが町にある"
	p.moving = false
	p.path.clear()
	for m in sim.meetings.duplicate():
		if p.id not in [m.a,m.b]: continue
		for id in [m.a,m.b]:
			var participant = sim.person(id)
			participant.meeting_id = ""
			participant.remaining = 0
		sim.meetings.erase(m)
	for appointment in sim.social.appointments:
		if p.id in [appointment.a,appointment.b] and appointment.state in ["planned","on_the_way"]: appointment.state = "ended"
	for other in sim.people:
		if not is_alive(other): continue
		if sim.social.relation(other,p.id).familiarity>.2 or other.memories.any(func(m): return m.other==p.id):
			sim._remember(other,p.id,"一緒に過ごした時間を思う","%sさんと会うことは、もうできない。覚えていることや残されたものを、ときどき思い返したい。"%p.name,"farewell")
	_record("farewell_"+p.id,p.name+"を見送った","これまでの時間は、その人の記憶と、ほかの人が受け取った経験の中に残る。")

func _record(key: String, title: String, text: String) -> void:
	chronicle.append({"key":key,"day":sim.day_index(),"minute":sim.elapsed,"title":title,"text":text})
	sim._log("",title,text)

func journal_text() -> String:
	var text = "町に積もった時間\n\n"
	for entry in chronicle:
		text += "%d年目 · %s\n%s\n\n"%[int(entry.day/12.0)+1,entry.title,entry.text]
	text += "誰かが残し、誰かが受け取ったもの\n\n"
	for item in legacy:
		text += "%s · %s\n見た人：%s\n\n"%[sim.person(item.owner).name,item.label,"、".join(item.readers.map(func(r): return sim.person(r.id).name)) if not item.readers.is_empty() else "まだ、これから"]
	if legacy.is_empty(): text += "日々の取り組みから、少しずつ形になっていく。"
	return text

func serialize() -> Dictionary:
	return {"announced":announced,"applied":applied,"legacy":legacy,"chronicle":chronicle,"year_seen":year_seen,"chapter_ready":chapter_ready,"chapter_acknowledged":chapter_acknowledged,"chapter_mode":chapter_mode,"final_reviewed":final_reviewed}

func restore(data: Dictionary) -> void:
	for p in sim.people: upgrade_person(p)
	announced = data.get("announced",[])
	applied = data.get("applied",[])
	legacy = data.get("legacy",[])
	chronicle = data.get("chronicle",[])
	year_seen = int(data.get("year_seen",int(sim.day_index()/12.0)))
	chapter_ready = data.get("chapter_ready",false)
	chapter_acknowledged = data.get("chapter_acknowledged",false)
	chapter_mode = data.get("chapter_mode","three_years")
	final_reviewed = data.get("final_reviewed",false)
	if data.is_empty():
		for p in sim.people:
			p.age = int(p.base_age)+int(sim.day_index()/12.0)
			if p.goal_notified: goal_completed(p)
			if p.id=="rin":
				if p.age>=22: p.occupation = "町の模型工房で働く人"
				elif p.age>=18: p.occupation = "町から専門学校へ通う学生"
				elif p.age>=12: p.occupation = "自分で過ごす時間が増えた生徒"
			if p.age>=config.end_ages[p.id]: _end_life(p)
		if sim.day_index()>=config.transition_day:
			# Apply new roles at resumption without inventing old announcements or encounters.
			announced = ["aoi_move","osamu_retire"]
			_move_aoi()
			_retire_osamu()
		for id in config.career_changes:
			var p = sim.person(id)
			if is_alive(p) and p.age>=config.career_changes[id]:
				var key = "career_"+id
				announced.append(key)
				_retire_career(p,key)
		if sim.day_index()>=config.chapter_review_day:
			chapter_ready = true
			chapter_mode = "resumed" if sim.people.any(func(p): return is_alive(p)) else "last"

class_name ResidentKnowledgeExchange
extends RefCounted

# Profiles are accounts held by the speaker, never queries of a third person's
# current skills. The listener may use the account to decide whom to approach.
var sim

func _init(simulation) -> void:
	sim = simulation

func exchange(a: Dictionary, b: Dictionary, prior_a: Array, prior_b: Array, meeting: Dictionary = {}) -> Array:
	var transfers: Array = []
	if not _completed_meeting(a,b,meeting): return transfers
	for pair in [[a,b,prior_a],[b,a,prior_b]]:
		var speaker: Dictionary = pair[0]
		var listener: Dictionary = pair[1]
		var candidates := _profiles(speaker,listener,pair[2])
		var sent := false
		for candidate in candidates:
			var event_id: String = candidate.reference
			if candidate.kind=="initial": event_id = _materialize(speaker,listener,candidate)
			if event_id.is_empty() or not sim.cognition.share(speaker,listener,event_id): continue
			var subject: Dictionary = sim.person(candidate.subject)
			var label: String = ResidentCognition.INTEREST_LABELS.get(candidate.skill,candidate.skill)
			sim._log(speaker.id,"相談できる人の話","%sさんに、以前知った%sさんの%sのことを話した。"%[listener.name,subject.name,label])
			var event: Dictionary = sim.events[-1]
			event.fact = "introduction"
			event.source = speaker.id
			event.participants = [speaker.id,listener.id]
			event.value = {"person":subject.id,"via":speaker.id,"skill":candidate.skill,
				"profile_event":event_id,"profile_minute":candidate.origin}
			sim.cognition.observe(speaker,event)
			sim.cognition.observe(listener,event)
			transfers.append({"speaker":speaker.id,"listener":listener.id,"person":subject.id,
				"skill":candidate.skill,"profile_event":event_id,"event_id":event.event_id,
				"origin_observed_at":candidate.origin})
			sent = true
			break
		if not sent:
			var shared := _share_relevant_fact(speaker,listener,pair[2])
			if not shared.is_empty(): transfers.append(shared)
	return transfers

func introduction(p: Dictionary, partner_id: String) -> Dictionary:
	for index in range(p.get("knowledge",[]).size()-1,-1,-1):
		var known: Dictionary = p.knowledge[index]
		if known.get("fact","")!="introduction" or not known.get("value") is Dictionary: continue
		var value: Dictionary = known.value
		if value.get("person","")!=partner_id or int(known.observed_at)>sim.elapsed or float(known.confidence)<.5: continue
		var via: String = value.get("via","")
		if via.is_empty() or via==p.id or sim.person(via).is_empty(): continue
		return {"person":partner_id,"via":via,"skill":value.get("skill",""),
			"event_id":known.event_id,"profile_event":value.get("profile_event",""),
			"origin_observed_at":int(value.get("profile_minute",known.observed_at)),
			"received_at":int(known.observed_at)}
	return {}

func introduction_reason(p: Dictionary, partner_id: String) -> String:
	var known := introduction(p,partner_id)
	if known.is_empty(): return ""
	var label: String = ResidentCognition.INTEREST_LABELS.get(known.skill,"得意なこと")
	return "%sさんから、%sさんの%sについて聞いた。"%[sim.person(known.via).name,sim.person(partner_id).name,label]

func _completed_meeting(a: Dictionary, b: Dictionary, meeting: Dictionary) -> bool:
	if meeting.is_empty() or meeting.get("state","")!="engaged" or float(meeting.get("remaining",1))>0: return false
	if not sim.life.is_alive(a) or not sim.life.is_alive(b) or a.moving or b.moving: return false
	if a.meeting_id!=meeting.get("id","") or b.meeting_id!=meeting.get("id","") or a.place!=b.place: return false
	for actual in sim.meetings:
		if actual==meeting and actual.a==a.id and actual.b==b.id: return true
	return false

func _profiles(speaker: Dictionary, listener: Dictionary, prior: Array) -> Array:
	var candidates: Array = []
	var needs := _needs(listener)
	for subject in speaker.get("known_profiles",{}):
		var snapshot: Dictionary = speaker.known_profiles[subject]
		var value := {"person":subject,"skills":snapshot.get("skills",{}),"interests":snapshot.get("interests",[])}
		var candidate := _candidate(speaker,listener,needs,value,int(snapshot.get("observed_at",0)),.95,
			str(snapshot.get("source","initial_profile")),"initial_"+speaker.id+"_"+str(subject))
		if not candidate.is_empty():
			candidate.kind = "initial"
			candidates.append(candidate)
	for snapshot in prior:
		if snapshot.get("fact","")!="profile" or not snapshot.get("value") is Dictionary: continue
		var held := _held(speaker,str(snapshot.get("event_id","")))
		if held.is_empty() or held.value!=snapshot.value: continue
		var candidate := _candidate(speaker,listener,needs,held.value,
			int(held.get("origin_observed_at",held.observed_at)),float(held.confidence),
			str(held.source),str(held.event_id))
		if not candidate.is_empty():
			candidate.kind = "knowledge"
			candidates.append(candidate)
	candidates.sort_custom(func(a,b):
		if not is_equal_approx(a.score,b.score): return a.score>b.score
		if a.origin!=b.origin: return a.origin>b.origin
		return str(a.reference)<str(b.reference))
	return candidates

func _candidate(speaker: Dictionary, listener: Dictionary, needs: Dictionary, value: Dictionary, origin: int, confidence: float, source: String, reference: String) -> Dictionary:
	var subject: String = value.get("person","")
	if subject in [speaker.id,listener.id] or not sim.life.is_alive(sim.person(subject)): return {}
	if origin<0 or origin>sim.elapsed or confidence*.9<.5: return {}
	var best: Dictionary = {}
	var keys: Array = needs.keys()
	keys.sort()
	for skill in keys:
		var level: float = value.get("skills",{}).get(skill,0)
		if level<=.05: continue
		var speaker_evidence: Dictionary = sim.cognition.skill_evidence(speaker,subject,skill)
		if not speaker_evidence.is_empty():
			if origin<int(speaker_evidence.origin_observed_at): continue
			if origin==int(speaker_evidence.origin_observed_at) and confidence<float(speaker_evidence.confidence): continue
		var existing: Dictionary = sim.cognition.skill_evidence(listener,subject,skill)
		var new_interest: bool = skill in value.get("interests",[]) and skill not in sim.cognition.known_interests(listener,subject)
		if not existing.is_empty():
			# A high old estimate must not repeatedly masquerade as new advice.
			if origin<int(existing.origin_observed_at): continue
			if origin==int(existing.origin_observed_at):
				if confidence*.9<=float(existing.confidence) and not new_interest: continue
				if is_equal_approx(level,float(existing.level)) and not new_interest: continue
		var score: float = float(needs[skill])*(.6+.4*level)+.15*maxf(0,level-float(listener.skills.get(skill,0)))
		if best.is_empty() or score>float(best.score):
			best = {"subject":subject,"skill":str(skill),"level":level,"score":score,
				"value":value.duplicate(true),"origin":origin,"confidence":confidence,
				"source":source,"reference":reference}
	return best

func _needs(listener: Dictionary) -> Dictionary:
	var needs := {}
	for interest in listener.get("interests",[]): needs[str(interest)] = .35
	var goal: String = listener.get("current_goal","")
	for activity in sim.resident_activities.definitions:
		var score := .35 if activity.interest in listener.interests else 0.0
		for word in activity.goal_words:
			if word in goal: score += .65;break
		if score>0: needs[activity.skill] = maxf(float(needs.get(activity.skill,0)),score)
	return needs

func _materialize(speaker: Dictionary, listener: Dictionary, candidate: Dictionary) -> String:
	var subject: Dictionary = sim.person(candidate.subject)
	var label: String = ResidentCognition.INTEREST_LABELS.get(candidate.skill,candidate.skill)
	sim._log(speaker.id,"以前に知った得意なこと","以前に知った%sさんの%sのことを、%sさんに話した。"%[subject.name,label,listener.name])
	var event: Dictionary = sim.events[-1]
	event.fact = "profile"
	event.source = candidate.source
	event.origin_observed_at = candidate.origin
	event.participants = [speaker.id]
	var skills := {}
	skills[candidate.skill] = candidate.level
	var interests: Array = []
	if candidate.skill in candidate.value.get("interests",[]): interests.append(candidate.skill)
	event.value = {"person":candidate.subject,"skills":skills,"interests":interests}
	if not sim.cognition.observe(speaker,event): return ""
	return event.event_id

func _held(speaker: Dictionary, event_id: String) -> Dictionary:
	for known in speaker.get("knowledge",[]):
		if known.get("event_id","")==event_id and int(known.get("observed_at",sim.elapsed+1))<=sim.elapsed: return known
	return {}

func _share_relevant_fact(speaker: Dictionary, listener: Dictionary, prior: Array) -> Dictionary:
	var tokens: Array = []
	for interest in listener.get("interests",[]):
		var label: String = ResidentCognition.INTEREST_LABELS.get(interest,"")
		if not label.is_empty(): tokens.append(label)
	for index in range(prior.size()-1,-1,-1):
		var known: Dictionary = prior[index]
		if known.get("fact","") in ["profile","introduction"]: continue
		var text: String = str(known.get("fact",""))+str(known.get("value",""))
		var relevant := false
		for token in tokens:
			if token in text: relevant = true;break
		if relevant and sim.cognition.share(speaker,listener,str(known.get("event_id",""))):
			return {"speaker":speaker.id,"listener":listener.id,"event_id":known.event_id,"kind":"fact"}
	return {}

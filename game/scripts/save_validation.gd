class_name SaveValidation
extends RefCounted

# Furniture roles and the physical interaction pool are a current-format contract.
# Development saves from older layouts are intentionally not migrated.
const CURRENT_SCHEMA := 7

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func encoded(value: Variant, depth: int = 0) -> bool:
	if depth>32: return false
	if value is int or value is float: return number(value)
	if value is Dictionary:
		if value.has("__vector3"):
			# _decode treats this reserved wrapper as a Vector3. An otherwise
			# valid record must not turn into a vector after validation succeeds.
			if value.size()!=1: return false
			var xyz = value.__vector3
			if not xyz is Array or xyz.size()!=3: return false
			for coordinate in xyz:
				if not number(coordinate): return false
			return true
		for key in value:
			if not encoded(value[key],depth+1): return false
	if value is Array:
		if value.size()>10000: return false
		for entry in value:
			if not encoded(entry,depth+1): return false
	return true

static func vector(value: Variant) -> bool:
	return value is Dictionary and value.has("__vector3") and encoded(value)

static func record(value: Variant, text_keys: Array, numeric_keys: Array) -> bool:
	if not value is Dictionary: return false
	for key in text_keys:
		if not value.get(key) is String: return false
	for key in numeric_keys:
		if not number(value.get(key)): return false
	return true

static func whole(value: Variant, minimum: int = 0) -> bool:
	return number(value) and value>=minimum and value==int(value)

static func unit(value: Variant) -> bool:
	return number(value) and value>=0 and value<=1

static func strings(value: Variant, limit: int = 64) -> bool:
	if not value is Array or value.size()>limit: return false
	for entry in value:
		if not entry is String or entry.is_empty(): return false
	return true

static func skills(value: Variant) -> bool:
	if not value is Dictionary or value.size()>64: return false
	for key in value:
		if not key is String or key.is_empty() or not unit(value[key]): return false
	return true

static func profile(value: Variant, definitions: Dictionary) -> bool:
	if not value is Dictionary or not value.get("person") is String or not definitions.has(value.person): return false
	if not value.has("skills") and not value.has("interests"): return false
	if value.has("skills") and not skills(value.skills): return false
	if value.has("interests") and not strings(value.interests): return false
	return true

static func introduction(value: Variant, definitions: Dictionary, observed_at: float) -> bool:
	if not record(value,["person","via","skill","profile_event"],["profile_minute"]): return false
	if not definitions.has(value.person) or not definitions.has(value.via) or value.person==value.via: return false
	if value.skill.is_empty() or value.profile_event.is_empty(): return false
	return whole(value.profile_minute) and value.profile_minute<=observed_at

static func cognition(p: Dictionary, definitions: Dictionary, sites: Dictionary, elapsed: float) -> bool:
	if p.has("skills") and not skills(p.skills): return false
	if p.has("interests") and not strings(p.interests): return false
	if p.has("known_profiles"):
		if not p.known_profiles is Dictionary or p.known_profiles.size()>definitions.size(): return false
		for other in p.known_profiles:
			var known = p.known_profiles[other]
			if not definitions.has(other) or not record(known,["source"],["observed_at"]): return false
			if known.source!="initial_profile" or not whole(known.observed_at) or known.observed_at>elapsed: return false
			if not skills(known.get("skills")) or not strings(known.get("interests")): return false
	if p.has("knowledge"):
		if not p.knowledge is Array or p.knowledge.size()>128: return false
		for known in p.knowledge:
			if not record(known,["event_id","fact","source","mode"],["observed_at","confidence"]): return false
			if known.event_id.is_empty() or known.fact.is_empty() or not known.has("value"): return false
			if known.mode not in ["observed","told"] or not unit(known.confidence): return false
			if not whole(known.observed_at) or known.observed_at>elapsed: return false
			if known.has("received_from") and (not known.received_from is String or (not known.received_from.is_empty() and not definitions.has(known.received_from))): return false
			if known.has("origin_observed_at") and (not whole(known.origin_observed_at) or known.origin_observed_at>known.observed_at): return false
			if known.fact=="profile" and not profile(known.value,definitions): return false
			if known.fact=="introduction" and not introduction(known.value,definitions,known.observed_at): return false
	if p.has("expectations"):
		if not p.expectations is Dictionary or p.expectations.size()>96: return false
		for key in p.expectations:
			var estimate = p.expectations[key]
			if not key is String or not record(estimate,["activity","place","other","condition"],["enjoyment","burden","familiarity","samples","updated_at"]): return false
			var components = JSON.parse_string(key)
			if not components is Array or components!=[estimate.activity,estimate.place,estimate.other,estimate.condition]: return false
			if estimate.activity.is_empty() or not sites.has(estimate.place) or estimate.condition.is_empty(): return false
			if not estimate.other.is_empty() and not definitions.has(estimate.other): return false
			for dimension in ["enjoyment","burden","familiarity"]:
				if not unit(estimate[dimension]): return false
			if not whole(estimate.samples,1) or not whole(estimate.updated_at) or estimate.updated_at>elapsed: return false
			if estimate.has("skill") and (not estimate.skill is String or estimate.skill.is_empty()): return false
	if p.has("cognition_session"):
		var session = p.cognition_session
		if not session is Dictionary: return false
		if not session.is_empty():
			if not record(session,["kind","place"],["fatigue","quiet"]) or session.kind.is_empty() or not sites.has(session.place): return false
			if not unit(session.fatigue) or not unit(session.quiet): return false
	if p.has("cognition_plan"):
		var plan = p.cognition_plan
		if not plan is Dictionary: return false
		if not plan.is_empty():
			if not record(plan,["meeting","activity","title","partner","stage","origin"],["started"]): return false
			if plan.meeting.is_empty() or plan.activity.is_empty() or not definitions.has(plan.partner) or plan.partner==p.id: return false
			if plan.stage not in ["travel","execute","completed","interrupted"] or plan.origin not in ["resident","player"]: return false
			if not whole(plan.started) or plan.started>elapsed or not strings(plan.get("steps"),16): return false
			if plan.has("finished") and (not whole(plan.finished) or plan.finished<plan.started or plan.finished>elapsed): return false
			if plan.has("reason") and not plan.reason is String: return false
			if plan.has("kind") and plan.kind not in ["project","social","support","play"]: return false
			if plan.has("introduction_event") and (not plan.introduction_event is String or plan.introduction_event.is_empty()): return false
	if p.has("plan_history"):
		if not p.plan_history is Array or p.plan_history.size()>24: return false
		for entry in p.plan_history:
			if not record(entry,["activity","partner"],["day","minute"]) or not entry.get("completed") is bool: return false
			if entry.activity.is_empty() or not definitions.has(entry.partner) or entry.partner==p.id: return false
			if not whole(entry.day) or not whole(entry.minute) or entry.minute>elapsed: return false
	if p.has("next_plan_minute") and not whole(p.next_plan_minute): return false
	if p.has("support_next_attempt") and not whole(p.support_next_attempt): return false
	if p.has("play_next_attempt") and not whole(p.play_next_attempt): return false
	if p.has("preparing_agenda_id") and not p.preparing_agenda_id is String: return false
	return true

static func agenda(data: Variant, definitions: Dictionary, sites: Dictionary, elapsed: float) -> bool:
	if not data is Dictionary or not whole(data.get("serial")) or not data.get("records") is Array: return false
	if data.records.size()>64: return false
	var seen := {}
	for planned in data.records:
		if not record(planned,["id","a","b","activity","title","place","venue","state","origin","meeting_id"],["start","duration","made_at","attempts","last_try","finished_at"]): return false
		if not definitions.has(planned.a) or not definitions.has(planned.b) or planned.a==planned.b: return false
		if not planned.id.begins_with("agenda_") or seen.has(planned.id): return false
		var suffix: String = planned.id.trim_prefix("agenda_")
		if not suffix.is_valid_int() or not whole(int(suffix),1) or int(suffix)>data.serial: return false
		seen[planned.id] = true
		if planned.activity not in ["social","radio","model","bread","photo","music","craft"]: return false
		if not sites.has(planned.place) or not vector(planned.get("center")): return false
		if planned.venue not in ["bench","cafe","project"] or planned.origin not in ["resident","player"]: return false
		if planned.state not in ["planned","travel","kept","postponed","ended"]: return false
		if not whole(planned.start) or not whole(planned.made_at) or planned.made_at>elapsed or planned.start<planned.made_at: return false
		if not whole(planned.duration,1) or planned.duration>240 or not whole(planned.attempts): return false
		if planned.last_try!=-1 and (not whole(planned.last_try) or planned.last_try<planned.made_at or planned.last_try>elapsed): return false
		if planned.finished_at!=-1 and (not whole(planned.finished_at) or planned.finished_at<planned.made_at or planned.finished_at>elapsed): return false
		if planned.state in ["planned","travel"]:
			if planned.finished_at!=-1: return false
		elif planned.finished_at==-1: return false
		for key in ["departures","returns"]:
			if not planned.get(key) is Dictionary or planned[key].size()!=2: return false
			for id in [planned.a,planned.b]:
				if not whole(planned[key].get(id)): return false
		for id in [planned.a,planned.b]:
			if planned.departures[id]<planned.made_at or planned.departures[id]>planned.start: return false
			if planned.returns[id]<planned.start+planned.duration: return false
		if not planned.get("shared_before") is Dictionary: return false
		for id in planned.shared_before:
			if id not in [planned.a,planned.b] or not whole(planned.shared_before[id]): return false
		if planned.state=="travel" and (planned.meeting_id.is_empty() or planned.shared_before.size()!=2): return false
		for key in ["last_blocker","change_reason","outcome"]:
			if planned.has(key) and not planned[key] is String: return false
		if planned.has("revisions"):
			if not planned.revisions is Array or planned.revisions.size()>2: return false
			var previous := -1
			for revision in planned.revisions:
				if not record(revision,["reason"],["from","to","at"]): return false
				if not whole(revision.from) or not whole(revision.to) or not whole(revision.at): return false
				if revision.from<planned.made_at or revision.to<=revision.from or revision.at<planned.made_at or revision.at>elapsed: return false
				if previous>=0 and revision.from!=previous: return false
				previous = int(revision.to)
			if previous>=0 and previous!=planned.start: return false
	return true

static func world_interactions(data: Variant, raw: Dictionary, definitions: Dictionary) -> bool:
	if not data is Dictionary or data.get("version")!=1: return false
	if not data.get("objects") is Dictionary or data.objects.keys()!=["workshop_radio"]: return false
	if not data.get("sessions") is Dictionary or data.sessions.size()>64: return false
	var object = data.objects.workshop_radio
	if not record(object,["id","kind","owner","holder","container","reserved_by","state"],["yaw"]): return false
	if object.id!="workshop_radio" or object.kind!="radio" or object.owner!="town" or not vector(object.get("position")) or not unit(object.get("work_progress")): return false
	if object.state not in ["stored","held","on_table"] or object.container not in ["","radio_shelf","radio_table"]: return false
	if not object.holder.is_empty() and not definitions.has(object.holder): return false
	var meetings := {}
	for meeting in raw.meetings:
		meetings[meeting.id] = meeting
	var people := {}
	for p in raw.people: people[p.id] = p
	var active := 0
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world-interactions.json")).radio
	var source := Vector3(settings.source_position[0],settings.source_position[1],settings.source_position[2])
	var world_target := Vector3(settings.target_position[0],settings.target_position[1],settings.target_position[2])
	var coordinates: Array = object.position.__vector3
	var object_position := Vector3(coordinates[0],coordinates[1],coordinates[2])
	for id in data.sessions:
		var s = data.sessions[id]
		if not id is String or not record(s,["id","meeting","key","object_id","a","b","carrier","operator","phase","reason"],["started","phase_started","finished","worked_minutes","required_work","travel_distance","phase_object_yaw","carry_yaw","phase_carry_yaw"]): return false
		if s.id!=id or id!="interaction_"+s.meeting or s.key!="radio" or s.object_id!=object.id: return false
		if not definitions.has(s.a) or not definitions.has(s.b) or s.a==s.b or s.carrier not in [s.a,s.b] or s.operator not in [s.a,s.b]: return false
		if int(people[s.carrier].age)<int(settings.minimum_carrier_age): return false
		if s.phase not in WorldInteractions.PHASES or not vector(s.get("phase_object_position")): return false
		if not whole(s.started) or not whole(s.phase_started) or s.started>s.phase_started or s.phase_started>raw.elapsed: return false
		if not whole(s.required_work,1) or s.required_work>240 or not whole(s.worked_minutes) or s.worked_minutes>s.required_work or s.travel_distance<0: return false
		if not strings(s.get("effects"),1) or (s.effects.size()==1 and s.effects[0]!="result"): return false
		if ("result" in s.effects)!=(s.worked_minutes==s.required_work): return false
		if not s.get("targets") is Dictionary or s.targets.size()!=2: return false
		var target_spots := []
		for person_id in [s.a,s.b]:
			var target = s.targets.get(person_id)
			if not record(target,["spot"],[]) or not vector(target.get("position")) or target.spot not in ["radio_work_0","radio_work_1"] or target.spot in target_spots: return false
			target_spots.append(target.spot)
		if s.phase in WorldInteractions.ACTIVE_PHASES:
			active += 1
			if active>1 or s.finished!=-1 or object.reserved_by!=id or not meetings.has(s.meeting): return false
			var meeting: Dictionary = meetings[s.meeting]
			if meeting.get("interaction_id","")!=id or meeting.a!=s.a or meeting.b!=s.b or meeting.get("project",{}).get("key","")!="radio": return false
			if not whole(meeting.remaining) or int(meeting.remaining)!=int(s.required_work)-int(s.worked_minutes): return false
			for person_id in [s.a,s.b]:
				if not people[person_id].get("alive",true) or people[person_id].meeting_id!=s.meeting: return false
			var duration: float = settings.phase_minutes.get(s.phase,1)
			var progress := clampf((float(raw.elapsed)-float(s.phase_started))/duration,0,1)
			var held: bool = s.phase in ["carry_to_target","carry_to_source"] or (s.phase in ["take","take_return"] and progress>=.3) or (s.phase in ["place","return"] and progress<.75)
			var on_table: bool = s.phase=="working" or (s.phase=="take_return" and progress<.3) or (s.phase=="place" and progress>=.75)
			if object.holder!=(s.carrier if held else "") or object.state!=("held" if held else ("on_table" if on_table else "stored")): return false
			if object.container!=("" if held else ("radio_table" if on_table else "radio_shelf")): return false
			if s.phase=="to_source" and object_position.distance_to(source)>.0001: return false
			if s.phase=="working" and object_position.distance_to(world_target)>.0001: return false
			if s.phase in ["take_return","carry_to_source","return"] and not meeting.get("work_completed",false): return false
		else:
			if not whole(s.finished) or s.finished<s.started or s.finished>raw.elapsed: return false
			if s.phase=="completed" and s.worked_minutes!=s.required_work: return false
	if active==0 and (not object.reserved_by.is_empty() or not object.holder.is_empty() or object.container!="radio_shelf" or object.state!="stored"): return false
	if active==0 and object_position.distance_to(source)>.0001: return false
	for meeting in raw.meetings:
		if meeting.get("project",{}).get("key","")!="radio": continue
		var session = data.sessions.get(meeting.get("interaction_id",""),{})
		if session.is_empty() or session.phase not in WorldInteractions.ACTIVE_PHASES: return false
		if meeting.get("work_completed",false)!=("result" in session.effects) or meeting.get("project_result_recorded",false)!=("result" in session.effects): return false
	return true

static func tabletop_board(value: Variant) -> bool:
	if not value is Array or value.size()!=16: return false
	for color in value:
		if not whole(color) or color>2: return false
	return true

static func tabletop_boards_equal(first: Array, second: Array) -> bool:
	# JSON arrays contain float Variants. Compare the already-validated whole
	# colors, rather than Godot's type-sensitive Array equality.
	if first.size()!=second.size(): return false
	for cell in first.size():
		if int(first[cell])!=int(second[cell]): return false
	return true

static func tabletop(data: Variant, raw: Dictionary, definitions: Dictionary) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not whole(data.get("serial")): return false
	if not data.get("sessions") is Dictionary or data.sessions.size()>32 or not data.get("pieces") is Dictionary or data.pieces.size()!=16: return false
	for value in data.pieces.values():
		if not value is Dictionary: return false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tabletop-game.json"))
	var origin := Vector3(config.board_origin[0],config.board_origin[1],config.board_origin[2])
	var people := {};var meetings := {}
	for p in raw.people: people[p.id] = p
	for meeting in raw.meetings: meetings[meeting.id] = meeting
	var active: Dictionary = {}
	for id in data.sessions:
		var s = data.sessions[id]
		if not id is String or not record(s,["id","meeting","a","b","board_id","phase","selected_piece","align_stage","align_next","reason"],["started","phase_started","finished","turn","selected_cell","winner"]): return false
		if id!=s.id or not id.begins_with("tabletop_"): return false
		var suffix: String = id.trim_prefix("tabletop_")
		if not suffix.is_valid_int() or int(suffix)<1 or int(suffix)>data.serial: return false
		if not definitions.has(s.a) or not definitions.has(s.b) or s.a==s.b or s.board_id!=config.board_id or s.phase not in TabletopGame.PHASES: return false
		if not whole(s.started) or not whole(s.phase_started) or s.started>s.phase_started or s.phase_started>raw.elapsed: return false
		if not whole(s.turn,1) or s.turn>2 or not whole(s.winner) or s.winner>2 or not s.get("draw") is bool or not s.get("result_recorded") is bool or not s.get("interruption_recorded") is bool: return false
		if not tabletop_board(s.get("board")) or not s.get("final_board") is Array or (not s.final_board.is_empty() and not tabletop_board(s.final_board)): return false
		if not s.get("moves") is Array or s.moves.size()>16 or not strings(s.get("cleanup_queue"),16): return false
		if not s.get("targets") is Dictionary or s.targets.size()!=2: return false
		var spots := []
		for person_id in [s.a,s.b]:
			var target = s.targets.get(person_id)
			if not record(target,["spot"],[]) or target.spot not in ["craft_work_0","craft_work_1"] or target.spot in spots: return false
			if not vector(target.get("approach")) or not vector(target.get("standby")): return false
			var point: Array = target.approach.__vector3;var expected_point: Array = config.slots[target.spot]
			if Vector3(point[0],point[1],point[2]).distance_to(Vector3(expected_point[0],expected_point[1],expected_point[2]))>.001: return false
			point = target.standby.__vector3
			if Vector3(point[0],point[1],point[2]).distance_to(Vector3(expected_point[0],0,float(config.standby_z)))>.001: return false
			spots.append(target.spot)
		var replay: Array = [];replay.resize(16);replay.fill(0)
		var used := {};var last_at: int = int(s.started)
		for index in s.moves.size():
			var move = s.moves[index]
			if not record(move,["piece"],["cell","color","at"]) or not whole(move.cell) or move.cell>15 or move.color!=1+index%2 or not whole(move.at) or move.at<last_at or move.at>raw.elapsed: return false
			if TabletopGame.winner(replay)!=0 or replay[int(move.cell)]!=0 or used.has(move.piece) or not data.pieces.has(move.piece): return false
			if int(data.pieces[move.piece].get("color",0))!=int(move.color): return false
			replay[int(move.cell)] = int(move.color);used[move.piece] = true;last_at = int(move.at)
		var actual_winner: int = TabletopGame.winner(replay)
		var draw: bool = actual_winner==0 and TabletopGame.legal_cells(replay).is_empty()
		if s.winner!=actual_winner or s.draw!=draw or s.result_recorded!=(actual_winner!=0 or draw): return false
		if not s.final_board.is_empty() and not tabletop_boards_equal(s.final_board,replay): return false
		if s.result_recorded and not tabletop_boards_equal(s.final_board,replay): return false
		if s.phase in TabletopGame.ACTIVE:
			if not active.is_empty() or s.finished!=-1 or not meetings.has(s.meeting): return false
			active = s
			var meeting: Dictionary = meetings[s.meeting]
			if meeting.get("mode","")!="play" or meeting.get("game_id","")!=id or meeting.a!=s.a or meeting.b!=s.b: return false
			for person_id in [s.a,s.b]:
				if not people[person_id].get("alive",true) or people[person_id].meeting_id!=s.meeting or people[person_id].get("activity_spot","")!=s.targets[person_id].spot: return false
			if s.phase in ["travel","think"]:
				if s.selected_cell!=-1 or not s.selected_piece.is_empty(): return false
			else:
				if not whole(s.selected_cell) or s.selected_cell>15 or not data.pieces.has(s.selected_piece) or data.pieces[s.selected_piece].get("color")!=s.turn: return false
			if s.phase=="align" and (s.align_stage not in ["clear","approach"] or s.align_next not in ["reach","cleanup"]): return false
			if (s.phase=="cleanup" or (s.phase=="align" and s.align_next=="cleanup")) and not s.result_recorded: return false
			var progress := clampf((float(raw.elapsed)-float(s.phase_started))/float(config.phase_minutes.get(s.phase,1)),0,1)
			var next_turn: bool = s.phase in ["travel","think","reach"] or (s.phase=="align" and s.align_next=="reach") or (s.phase=="place" and progress<.75)
			if next_turn and s.turn!=1+s.moves.size()%2: return false
			if s.phase in ["react","switch_turn"] or (s.phase=="place" and progress>=.75):
				if s.moves.is_empty() or s.turn!=s.moves[-1].color: return false
			if not s.result_recorded and not tabletop_boards_equal(s.board,replay): return false
		else:
			if not whole(s.finished) or s.finished<s.started or s.finished>raw.elapsed or s.board.any(func(color): return color!=0): return false
			if s.phase=="completed" and not s.result_recorded: return false
		for piece_id in s.cleanup_queue:
			if not used.has(piece_id): return false
	var occupied := {}
	for color in [1,2]:
		for ordinal in range(1,9):
			var id := "craft_token_%d_%02d"%[color,ordinal]
			var piece = data.pieces.get(id)
			if not record(piece,["id","owner","holder","reserved_by","container","location"],["color","ordinal","cell","yaw"]) or piece.id!=id or piece.color!=color or piece.ordinal!=ordinal or piece.owner!="town" or not vector(piece.get("position")): return false
			if piece.location not in ["supply","hand","board"]: return false
			if piece.reserved_by!=(active.get("id","") if not active.is_empty() else ""): return false
			var xyz: Array = piece.position.__vector3;var position := Vector3(xyz[0],xyz[1],xyz[2])
			if piece.location=="supply":
				var bank: Array = config.bank_offsets[color-1]
				var expected := origin+Vector3(bank[0],bank[1]+(ordinal-1)*float(config.piece_stack_height),bank[2])
				if piece.cell!=-1 or not piece.holder.is_empty() or piece.container!="bank_%d"%color or position.distance_to(expected)>.0001: return false
			else:
				if active.is_empty(): return false
				if piece.location=="board":
					if not whole(piece.cell) or piece.cell>15 or occupied.has(int(piece.cell)) or active.board[int(piece.cell)]!=color or piece.container!=config.board_id or not piece.holder.is_empty(): return false
					var expected := origin+Vector3((int(piece.cell)%4-1.5)*float(config.cell_pitch),float(config.piece_bottom_offset),(int(int(piece.cell)/4)-1.5)*float(config.cell_pitch))
					if position.distance_to(expected)>.0001: return false
					occupied[int(piece.cell)] = color
				else:
					if piece.id!=active.selected_piece or piece.holder!=(active.a if active.turn==1 else active.b) or not piece.container.is_empty(): return false
					if active.phase not in ["reach","place","cleanup"] or position.distance_to(origin)>2: return false
	if not active.is_empty():
		for cell in 16:
			if active.board[cell]!=occupied.get(cell,0): return false
	for meeting in raw.meetings:
		if meeting.get("mode","")!="play": continue
		if active.is_empty() or active.meeting!=meeting.id or active.id!=meeting.get("game_id",""): return false
	return true

static func valid(raw: Variant, definitions: Dictionary, sites: Dictionary, household_ids: Array = []) -> bool:
	var required_households: Array = []
	for definition in definitions.values():
		if definition.household_id not in required_households: required_households.append(definition.household_id)
	if household_ids.is_empty():
		household_ids = JSON.parse_string(FileAccess.get_file_as_string("res://data/life-conditions.json")).households.keys()
	if not raw is Dictionary or not encoded(raw): return false
	if not record(raw,["rng_state"],["schema","elapsed","start_minute","epoch_weekday","budget","meeting_serial","remainder"]): return false
	if not whole(raw.schema,1) or int(raw.schema)!=CURRENT_SCHEMA or not raw.rng_state.is_valid_int(): return false
	if raw.has("route_layout") and (not number(raw.route_layout) or raw.route_layout<0 or raw.route_layout!=int(raw.route_layout)): return false
	if raw.has("world_seed") and not whole(raw.world_seed): return false
	if raw.has("event_serial") and not whole(raw.event_serial): return false
	if raw.elapsed<0 or raw.start_minute<0 or raw.start_minute>=1440 or raw.epoch_weekday<0 or raw.epoch_weekday>6: return false
	if raw.budget<0 or raw.remainder<0 or raw.remainder>=1: return false
	for key in ["people","events","meetings","benches"]:
		if not raw.get(key) is Array: return false
	if raw.people.size()!=definitions.size(): return false
	var seen = {}
	for p in raw.people:
		if not record(p,["id","name","occupation","place","destination","action","reason","meeting_id","routine_id"],["age","remaining","fatigue","hunger","connection","quiet","goal_progress","travel_minutes","activity_minutes"]): return false
		if not cognition(p,definitions,sites,raw.elapsed): return false
		if int(raw.schema)>=6 and not whole(p.get("play_next_attempt")): return false
		if not definitions.has(p.id) or seen.has(p.id): return false
		seen[p.id] = true
		if not sites.has(p.place) or not sites.has(p.destination): return false
		for key in ["position","target"]:
			if not vector(p.get(key)): return false
		for key in ["moving","supported","goal_notified"]:
			if not p.get(key) is bool: return false
		for key in ["work_satisfaction","earned_today","care_minutes","private_project","action_elapsed"]:
			if p.has(key) and not number(p[key]): return false
		for key in ["session_meal_paid","habit_recorded","career_retired"]:
			if p.has(key) and not p[key] is bool: return false
		if p.has("alive") and not p.alive is bool: return false
		if p.has("activity_spot") and not p.activity_spot is String: return false
		for key in ["base_age"]:
			if p.has(key) and not number(p[key]): return false
		for key in ["stage","current_goal","goal_kind","legacy_read_id","household_override"]:
			if p.has(key) and not p[key] is String: return false
		if p.has("goal_kind") and p.goal_kind not in ["creative","career","model"]: return false
		if p.has("household_override") and p.household_override!="" and p.household_override not in household_ids: return false
		if p.has("known_plans"):
			if not p.known_plans is Array: return false
			for plan in p.known_plans:
				if not plan is String: return false
		if p.has("goal_history"):
			if not p.goal_history is Array: return false
			for goal in p.goal_history:
				if not record(goal,["goal","reason"],["progress","minute"]): return false
		if p.has("legacy_read_recorded") and not p.legacy_read_recorded is bool: return false
		if p.has("inspiration"):
			if not p.inspiration is Dictionary: return false
			if not p.inspiration.is_empty() and (not record(p.inspiration,["kind","source","title"],["until"]) or not definitions.has(p.inspiration.source)): return false
		for key in ["path","memories"]:
			if not p.get(key) is Array: return false
		for point in p.path:
			if not vector(point): return false
		for memory in p.memories:
			if not record(memory,["other","title","text","kind"],["minute"]): return false
		if not p.get("relationships") is Dictionary: return false
		for other in p.relationships:
			if not definitions.has(other) or not record(p.relationships[other],["from","to"],["familiarity","trust","ease","unresolved_expectation"]): return false
		if p.has("habits"):
			if not p.habits is Array: return false
			for habit in p.habits:
				if not record(habit,["kind","place","cue"],["strength"]) or not habit.get("days") is Array: return false
				for day in habit.days:
					if not number(day): return false
	var event_ids = {}
	for e in raw.events:
		if not record(e,["clock","resident_id","title","text"],["minute","day"]): return false
		if e.has("event_id"):
			if not e.event_id is String or e.event_id.is_empty() or event_ids.has(e.event_id): return false
			event_ids[e.event_id] = true
			if e.event_id.begins_with("event_"):
				var suffix: String = e.event_id.trim_prefix("event_")
				if not suffix.is_valid_int() or int(suffix)<1: return false
				if raw.has("event_serial") and int(suffix)>raw.event_serial: return false
		for key in ["participants","witnesses"]:
			if e.has(key):
				if not strings(e[key],definitions.size()): return false
				for witness in e[key]:
					if not definitions.has(witness): return false
		if e.has("fact") and not e.fact is String: return false
		if e.get("fact","")=="profile" and not profile(e.get("value"),definitions): return false
		if e.get("fact","")=="introduction" and not introduction(e.get("value"),definitions,e.minute): return false
		if e.has("origin_observed_at") and (not whole(e.origin_observed_at) or e.origin_observed_at>e.minute): return false
		if e.has("source") and not e.source is String: return false
		if e.has("public") and not e.public is bool: return false
	for bench in raw.benches:
		if not vector(bench): return false
	for meeting in raw.meetings:
		if not record(meeting,["id","a","b","location","state"],["remaining","waited"]): return false
		if not definitions.has(meeting.a) or not definitions.has(meeting.b): return false
		if not meeting.get("spontaneous") is bool: return false
		if meeting.has("autonomous") and not meeting.autonomous is bool: return false
		for key in ["project_result_recorded","work_completed"]:
			if meeting.has(key) and not meeting[key] is bool: return false
		if meeting.has("duration") and not whole(meeting.duration,1): return false
		if meeting.has("agenda_id") and (not meeting.agenda_id is String or meeting.agenda_id.is_empty()): return false
		if meeting.get("mode","")=="project":
			if not record(meeting.get("project"),["key","title","place"],["cost"]): return false
			if not vector(meeting.project.get("center")) or not sites.has(meeting.project.place): return false
			if meeting.project.key not in ["radio","model","bread","photo","music","craft"] or not meeting.get("materials_ready") is bool: return false
			for key in ["skill","interest","topic","teacher","learner"]:
				if meeting.project.has(key) and not meeting.project[key] is String: return false
			for key in ["teacher","learner"]:
				if meeting.project.has(key) and not meeting.project[key].is_empty() and not definitions.has(meeting.project[key]): return false
	if int(raw.schema)>=5 and not raw.has("interactions"): return false
	if raw.has("interactions") and not world_interactions(raw.interactions,raw,definitions): return false
	if int(raw.schema)>=6 and not raw.has("tabletop"): return false
	if raw.has("tabletop") and not tabletop(raw.tabletop,raw,definitions): return false
	if raw.has("social"):
		var social = raw.social
		if not social is Dictionary or not social.get("appointments") is Array or not social.get("offer") is Dictionary or not number(social.get("serial")): return false
		for planned in social.appointments:
			if not record(planned,["id","a","b","location","state"],["start","duration","made_at"]): return false
			if not definitions.has(planned.a) or not definitions.has(planned.b): return false
		if not social.offer.is_empty():
			if not record(social.offer,["a","b","location"],["start","duration","made_at"]): return false
			if not definitions.has(social.offer.a) or not definitions.has(social.offer.b): return false
	if raw.has("agenda") and not agenda(raw.agenda,definitions,sites,raw.elapsed): return false
	for p in raw.people:
		if p.get("preparing_agenda_id","").is_empty(): continue
		if p.action!="prepare" or not raw.has("agenda"): return false
		var found := false
		for planned in raw.agenda.records:
			if planned.id==p.preparing_agenda_id and planned.state=="planned" and p.id in [planned.a,planned.b]: found = true
		if not found: return false
	if raw.has("work_family"):
		var life = raw.work_family
		if not life is Dictionary or not life.get("households") is Dictionary or not life.get("supports") is Array or not number(life.get("serial")): return false
		for p in raw.people:
			var override_id: String = p.get("household_override","")
			if not override_id.is_empty() and override_id not in required_households: required_households.append(override_id)
		for id in required_households:
			if not life.households.has(id): return false
		for id in life.households:
			if id not in household_ids: return false
			# Newly authored empty houses may already be present in an eight-person
			# save. Check every stored account, including unoccupied households.
			var h = life.households[id]
			if not record(h,[],["cash","home_load","earned_today","spent_today"]) or not h.get("material_days") is Dictionary or not h.get("ledger") is Array: return false
			for entry in h.ledger:
				if not record(entry,[],["day","earned","support","expenses","balance"]): return false
		for help in life.supports:
			if not record(help,["id","giver","receiver","kind","place","state"],["requested","began"]): return false
			if not definitions.has(help.giver) or not definitions.has(help.receiver): return false
			if help.has("autonomous") and not help.autonomous is bool: return false
			if help.has("initiator") and (not help.initiator is String or help.initiator!=help.receiver): return false
			if help.has("support_plan_recorded") and not help.support_plan_recorded is bool: return false
			if help.has("support_work_minutes") and not whole(help.support_work_minutes): return false
			for key in ["support_receiver_fatigue","support_giver_fatigue"]:
				if help.has(key) and not unit(help[key]): return false
		if life.has("projects"):
			if not life.projects is Dictionary: return false
			for key in ["radio","model","bread","photo","music","craft"]:
				if not number(life.projects.get(key)): return false
		if life.households.has("aoi_apartment"):
			if not record(life.households.aoi_apartment,[],["cash","home_load","earned_today","spent_today"]): return false
	if raw.has("life"):
		var course = raw.life
		if not course is Dictionary or not number(course.get("year_seen")): return false
		if not course.get("chapter_ready") is bool or not course.get("chapter_acknowledged") is bool: return false
		if course.has("final_reviewed") and not course.final_reviewed is bool: return false
		if course.has("chapter_mode") and course.chapter_mode not in ["three_years","resumed","last"]: return false
		for key in ["announced","applied","legacy","chronicle"]:
			if not course.get(key) is Array: return false
		for key in ["announced","applied"]:
			for value in course[key]:
				if not value is String: return false
		for entry in course.chronicle:
			if not record(entry,["key","title","text"],["day","minute"]): return false
		for item in course.legacy:
			if not record(item,["id","owner","label","place"],["created","edition","uses"]): return false
			if not definitions.has(item.owner) or not sites.has(item.place) or not vector(item.get("position")): return false
			if not item.get("entries") is Array or not item.get("readers") is Array: return false
			for entry in item.entries:
				if not record(entry,["goal"],["minute"]): return false
			for reader in item.readers:
				if not record(reader,["id"],["edition","minute"]) or not definitions.has(reader.id): return false
	return true

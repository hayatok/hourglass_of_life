class_name TabletopGame
extends RefCounted

const PHASES := ["travel","think","align","reach","place","react","switch_turn","cleanup","completed","interrupted"]
const ACTIVE := ["travel","think","align","reach","place","react","switch_turn","cleanup"]
const LINES := [[0,1,2,3],[4,5,6,7],[8,9,10,11],[12,13,14,15],[0,4,8,12],[1,5,9,13],[2,6,10,14],[3,7,11,15],[0,5,10,15],[3,6,9,12]]
var sim
var config: Dictionary
var sessions: Dictionary = {}
var pieces: Dictionary = {}
var serial := 0

func _init(simulation) -> void:
	sim = simulation
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/tabletop-game.json"))
	for key in ["board_origin","board_size"]:
		var value: Array = config[key]
		config[key] = Vector3(value[0],value[1],value[2])

func reset() -> void:
	sessions.clear();pieces.clear();serial = 0
	for p in sim.people: upgrade_person(p)
	for color in [1,2]:
		for ordinal in range(1,9):
			var id := "craft_token_%d_%02d"%[color,ordinal]
			pieces[id] = {"id":id,"color":color,"ordinal":ordinal,"owner":"town","holder":"","reserved_by":"",
				"container":"bank_%d"%color,"location":"supply","cell":-1,"position":bank_position(color,ordinal),"yaw":0.0}

func upgrade_person(p: Dictionary) -> void:
	if not p.has("play_next_attempt"): p.play_next_attempt = 0

func _interested(p: Dictionary) -> bool:
	return p.interests.any(func(tag): return tag in config.autonomy.interest_tags)

func _own_play_time(p: Dictionary, travel: int) -> bool:
	# The decision uses this person's own state. The other person runs the same
	# check when answering; candidate selection never inspects private needs.
	var window: int = travel+int(config.autonomy.minimum_free_window)
	if p.action in ["eat","sleep"] or p.quiet>float(config.autonomy.maximum_quiet): return false
	if p.hunger+window*sim.HUNGER_PER_MINUTE>.75 or p.fatigue+window*sim.FATIGUE_PER_MINUTE>.78: return false
	if p.connection<float(config.autonomy.minimum_connection) and not _interested(p): return false
	return sim.agenda._window_free(p,sim.elapsed,sim.elapsed+window)

func add_options(p: Dictionary, options: Array, contacts: Array) -> void:
	upgrade_person(p)
	if sim.elapsed<int(p.play_next_attempt) or not active_session().is_empty() or p.moving: return
	if not p.meeting_id.is_empty() or not p.get("support_id","").is_empty(): return
	# Playing is one possible use of shared public free time, not a summons
	# based on a town-wide search for whoever has the lowest fatigue.
	if p.place not in ["square","garden","bakery_cafe","workshop"]: return
	var travel: int = sim.resident_activities._travel(p.position,p.place,config.board_origin,config.site)
	if not _own_play_time(p,travel): return
	if sim.activities.pair_for(config.group,config.board_origin,[p.id]).size()!=2: return
	for contact in contacts:
		var other: Dictionary = contact.person
		if other.place!=p.place or other.moving or other.action not in ["rest","hobby","photo","social"]: continue
		if p.position.distance_to(other.position)>float(config.autonomy.max_partner_distance): continue
		# Co-presence can create an introduction elsewhere; this invitation uses
		# a relationship or information the resident actually already knows.
		if not _known(p,other.id): continue
		var d: Dictionary = sim.definitions[p.id]
		options.append({"kind":"play","place":config.site,"partner":other.id,"need":p.connection,
			"goal":d.values.belonging,"relation":clampf(float(contact.score),0,1),"role":.35,"habit":.15,
			"fun":clampf(.45+.25*d.traits.open_mindedness+.2*float(_interested(p))+.1*d.traits.extraversion,0,1),
			"cost":clampf(p.quiet*.5+p.fatigue*.3+travel*.002,0,1),"reason":"%sさんと、交互に考えながら四目並べで遊びたい"%other.name})
		return

func _known(p: Dictionary, other: String) -> bool:
	if float(sim.social.relation(p,other).familiarity)>=.1 or p.get("known_profiles",{}).has(other): return true
	for fact in p.get("knowledge",[]):
		if fact.get("fact","")=="profile" and fact.get("value",{}) is Dictionary and fact.value.get("person","")==other and float(fact.get("confidence",0))>=.5: return true
	for memory in p.memories:
		if memory.other==other and memory.kind in ["shared_time","play_result","project","support"]: return true
	return false

func active_session() -> Dictionary:
	for s in sessions.values():
		if s.phase in ACTIVE: return s
	return {}

func cell_centers() -> Array:
	var result: Array = []
	for cell in 16:
		result.append(config.board_origin+Vector3((cell%4-1.5)*float(config.cell_pitch),float(config.piece_bottom_offset),(int(cell/4)-1.5)*float(config.cell_pitch)))
	return result

func bank_position(color: int, ordinal: int) -> Vector3:
	var offset: Array = config.bank_offsets[color-1]
	return config.board_origin+Vector3(offset[0],offset[1]+(ordinal-1)*float(config.piece_stack_height),offset[2])

static func winner(board: Array) -> int:
	for line in LINES:
		var color: int = board[line[0]]
		if color!=0 and board[line[1]]==color and board[line[2]]==color and board[line[3]]==color: return color
	return 0

static func legal_cells(board: Array) -> Array:
	var result: Array = []
	for cell in board.size():
		if board[cell]==0: result.append(cell)
	return result

static func choices(board: Array, color: int) -> Array:
	var legal := legal_cells(board)
	for checked_color in [color,3-color]:
		var urgent: Array = []
		for cell in legal:
			var trial: Array = board.duplicate();trial[cell] = checked_color
			if winner(trial)==checked_color: urgent.append(cell)
		if not urgent.is_empty(): return urgent
	var best: Array = []
	var maximum := -1
	for cell in legal:
		var score := 3 if cell in [5,6,9,10] else 0
		for line in LINES:
			if cell not in line: continue
			var own := 0;var blocked := false
			for index in line:
				own += int(board[index]==color);blocked = blocked or board[index]==3-color
			if not blocked: score += 1+own*own*4
		if score>maximum: maximum = score;best = [cell]
		elif score==maximum: best.append(cell)
	return best

func handles(meeting: Dictionary) -> bool:
	return meeting.get("mode","")=="play"

func propose(first: String, second: String, autonomous: bool = false) -> Dictionary:
	var a: Dictionary = sim.person(first);var b: Dictionary = sim.person(second)
	if not sim.life.is_alive(a) or not sim.life.is_alive(b) or first==second:
		return {"status":"decline","text":"一緒に遊ぶ相手を選んでください。"}
	for p in [a,b]: upgrade_person(p)
	if autonomous:
		if sim.elapsed<int(a.play_next_attempt): return {"status":"defer","text":"遊びの相談は、少し時間を空けてからにしよう。"}
		a.play_next_attempt = sim.elapsed+int(config.autonomy.attempt_cooldown)
		if not _known(a,second): return sim._reply(a,"defer","まず相手を知ってから、遊びに誘いたい。")
	for s in sessions.values():
		if s.phase in ACTIVE: return sim._reply(a,"defer","今は盤が使われている。片付けが終わってからにしよう。")
	var pair: Array = sim.activities.pair_for(config.group,config.board_origin,[first,second])
	if pair.size()!=2: return sim._reply(a,"defer","遊べる机が空いてからにしよう。")
	for index in 2:
		var p: Dictionary = a if index==0 else b
		var other: Dictionary = b if index==0 else a
		var position: Array = config.slots.get(pair[index].id,[])
		if position.size()!=3 or pair[index].approach.distance_to(Vector3(position[0],position[1],position[2]))>.001:
			return sim._reply(a,"defer","遊ぶ机と立ち位置を整えてからにしよう。")
		if not p.meeting_id.is_empty() or not p.get("support_id","").is_empty() or not sim._routine_at(p).is_empty():
			return sim._reply(p,"defer","今は引き受けている予定を大切にしたい。")
		if p.action in ["eat","sleep"] or (autonomous and index==1 and sim.elapsed<int(p.play_next_attempt)):
			return sim._reply(p,"defer","今は自分の時間を大切にしたい。また余裕のあるときに遊ぼう。")
		var consent: Dictionary = sim.agenda._agreement(p,other,{"key":"social"},autonomous)
		if consent.status!="accept" or consent.get("shorter",false): return sim._reply(p,"defer","今は短く話すくらいにして、遊ぶのは余裕のあるときにしよう。")
		var travel: int = sim.resident_activities._travel(p.position,p.place,pair[index].approach,config.site)
		if autonomous and not _own_play_time(p,travel): return sim._reply(p,"defer","今は食事や自分の時間、次の予定を先にしたい。また余裕のあるときに遊ぼう。")
		if not sim.agenda._window_free(p,sim.elapsed,sim.elapsed+travel+int(config.minimum_free_window)):
			return sim._reply(p,"defer","次の予定までが短い。また時間の合うときに遊ぼう。")
	if not sim._begin_meeting(a,b,config.board_origin,"play",false,int(config.timeout_minutes),0,"",config.site,config.group):
		return sim._reply(a,"defer","机が使われている。空いてからにしよう。")
	serial += 1
	var id := "tabletop_%d"%serial
	var meeting: Dictionary = sim.meetings[-1]
	meeting.mode = "play";meeting.game_id = id;meeting.autonomous = autonomous
	var targets := {}
	for index in 2:
		var p: Dictionary = a if index==0 else b
		targets[p.id] = {"spot":pair[index].id,"approach":pair[index].approach,"standby":Vector3(pair[index].approach.x,0,float(config.standby_z))}
		p.action = "play";p.reason = "机へ向かって、色駒の四目並べを始めたい"
		p.play_next_attempt = sim.elapsed+int(config.autonomy.accepted_cooldown)
		p.cognition_plan = {"meeting":meeting.id,"activity":"four_in_row","title":config.title,"partner":(b if index==0 else a).id,
			"stage":"travel","origin":"resident" if autonomous else "player","started":int(sim.elapsed),"steps":["相談する","机へ向かう","交互に駒を置く","片付ける"],"kind":"play"}
	var board: Array = [];board.resize(16);board.fill(0)
	sessions[id] = {"id":id,"meeting":meeting.id,"a":first,"b":second,"board_id":config.board_id,"phase":"travel",
		"phase_started":int(sim.elapsed),"started":int(sim.elapsed),"finished":-1,"board":board,"final_board":[],
		"turn":1,"selected_cell":-1,"selected_piece":"","moves":[],"winner":0,"draw":false,"result_recorded":false,
		"interruption_recorded":false,"targets":targets,"align_stage":"","align_next":"reach","cleanup_queue":[],"reason":""}
	for piece in pieces.values(): piece.reserved_by = id
	_trim()
	return sim._reply(a,"accept","%sさんと四目並べで遊ぼう。机へ向かい、順番に駒を置く。"%b.name)

func _person(s: Dictionary, active: bool) -> Dictionary:
	return sim.person(s.a if (s.turn==1)==active else s.b)

func _arrived(p: Dictionary, target: Vector3) -> bool:
	return not p.moving and p.place==config.site and p.position.distance_to(target)<.08

func _route(p: Dictionary, target: Vector3) -> void:
	p.target = target;p.destination = config.site;p.path = sim.route(p.position,p.place,target,config.site);p.moving = not p.path.is_empty()
	if not p.moving: p.place = config.site

func _phase(s: Dictionary, phase: String) -> void:
	s.phase = phase;s.phase_started = int(sim.elapsed)

func _align(s: Dictionary, next: String) -> void:
	s.align_next = next;s.align_stage = "clear";_phase(s,"align")
	var observer := _person(s,false)
	_route(observer,s.targets[observer.id].standby)

func tick() -> void:
	for s in sessions.values():
		if s.phase not in ACTIVE: continue
		var found := false
		for meeting in sim.meetings:
			if meeting.id==s.meeting: found = true;break
		var unavailable := not found
		for id in [s.a,s.b]:
			var p: Dictionary = sim.person(id)
			unavailable = unavailable or not sim.life.is_alive(p) or p.get("meeting_id","")!=s.meeting or p.get("destination","").begins_with("off_map_")
		if unavailable: cancel(s.id,"参加者が退場したため、駒を保管した")

func advance(meeting: Dictionary) -> String:
	var s: Dictionary = sessions.get(meeting.get("game_id",""),{})
	if s.is_empty(): return "interrupted"
	if s.phase in ["completed","interrupted"]: return s.phase
	if sim.elapsed-s.started>int(config.timeout_minutes): cancel(s.id,"遊ぶ時間を切り上げた");return "interrupted"
	var active := _person(s,true);var observer := _person(s,false)
	for p in [active,observer]:
		if not sim._routine_at(p).is_empty() or p.hunger>.75 or p.fatigue>.82:
			cancel(s.id,"予定や食事、休息のために遊びを切り上げた");return "interrupted"
	meeting.remaining = maxi(0,int(config.timeout_minutes)-(sim.elapsed-int(s.started)))
	match s.phase:
		"travel":
			if _arrived(active,s.targets[active.id].approach) and _arrived(observer,s.targets[observer.id].approach):
				meeting.state = "engaged"
				for p in [active,observer]: p.cognition_plan.stage = "execute"
				_phase(s,"think")
		"think":
			if _progress(s)>=1:
				var options := choices(s.board,int(s.turn))
				if options.is_empty(): cancel(s.id,"置ける場所がない");return "interrupted"
				s.selected_cell = options[0] if options.size()==1 else options[sim.rng.randi_range(0,options.size()-1)]
				for ordinal in range(8,0,-1):
					var key := "craft_token_%d_%02d"%[int(s.turn),ordinal]
					if pieces[key].location=="supply": s.selected_piece = key;break
				_align(s,"reach")
		"align":
			if s.align_stage=="clear" and _arrived(observer,s.targets[observer.id].standby):
				s.align_stage = "approach"
				_route(active,Vector3(cell_centers()[s.selected_cell].x,0,float(config.front_z)))
			elif s.align_stage=="approach" and not active.moving:
				_phase(s,s.align_next)
		"reach":
			var piece: Dictionary = pieces[s.selected_piece]
			var lift := clampf((_progress(s)-.3)/.7,0,1)
			piece.position = bank_position(int(piece.color),int(piece.ordinal)).lerp(_held_position(active),lift)
			if _progress(s)>=.3: piece.holder = active.id;piece.container = "";piece.location = "hand"
			if _progress(s)>=1:
				_phase(s,"place")
		"place":
			var piece: Dictionary = pieces[s.selected_piece]
			piece.position = _held_position(active).lerp(cell_centers()[s.selected_cell],clampf(_progress(s)/.75,0,1))
			if _progress(s)>=.75 and piece.location=="hand":
				if s.board[s.selected_cell]!=0: cancel(s.id,"選んだ場所が使えなくなった");return "interrupted"
				s.board[s.selected_cell] = int(s.turn)
				piece.holder = "";piece.container = config.board_id;piece.location = "board";piece.cell = s.selected_cell
				s.moves.append({"cell":s.selected_cell,"color":int(s.turn),"piece":piece.id,"at":int(sim.elapsed)})
				for p in [active,observer]: p.connection = maxf(0,p.connection-.015)
				s.winner = winner(s.board);s.draw = s.winner==0 and legal_cells(s.board).is_empty()
				if s.winner!=0 or s.draw: _record_result(s)
			if _progress(s)>=1: _phase(s,"react")
		"react":
			if _progress(s)>=1:
				if s.result_recorded: _next_cleanup(s)
				else: _phase(s,"switch_turn")
		"switch_turn":
			if _progress(s)>=1:
				s.turn = 3-int(s.turn);s.selected_cell = -1;s.selected_piece = "";_phase(s,"think")
		"cleanup":
			var piece: Dictionary = pieces[s.selected_piece]
			if _progress(s)>=.3 and piece.location=="board":
				s.board[piece.cell] = 0;piece.location = "hand";piece.holder = active.id;piece.container = ""
			piece.position = cell_centers()[s.selected_cell].lerp(bank_position(int(piece.color),int(piece.ordinal)),clampf((_progress(s)-.3)/.45,0,1))
			if _progress(s)>=.75:
				piece.location = "supply";piece.holder = "";piece.container = "bank_%d"%int(piece.color);piece.cell = -1
			if _progress(s)>=1: _next_cleanup(s)
	return s.phase if s.phase in ["completed","interrupted"] else "pending"

func _held_position(p: Dictionary) -> Vector3:
	return p.position+Vector3(0,1.1,-.25)

func _record_result(s: Dictionary) -> void:
	if s.result_recorded: return
	s.result_recorded = true;s.final_board = s.board.duplicate()
	s.cleanup_queue = []
	for index in range(s.moves.size()-1,-1,-1): s.cleanup_queue.append(s.moves[index].piece)
	for id in [s.a,s.b]:
		var other: String = s.b if id==s.a else s.a
		var outcome: String = "盤が埋まり、引き分けになった" if s.draw else "%sさんの色駒が四つ並んだ"%sim.person(s.a if s.winner==1 else s.b).name
		sim._remember(sim.person(id),other,"四目並べを遊び終えた",outcome+"。実際に%d手を交互に置いた。"%s.moves.size(),"play_result")

func _next_cleanup(s: Dictionary) -> void:
	if s.cleanup_queue.is_empty():
		_store(s);_phase(s,"completed");s.finished = int(sim.elapsed);return
	s.selected_piece = s.cleanup_queue.pop_front()
	var piece: Dictionary = pieces[s.selected_piece]
	s.selected_cell = int(piece.cell);s.turn = int(piece.color)
	_align(s,"cleanup")

func cancel(id: String, reason: String) -> void:
	var s: Dictionary = sessions.get(id,{})
	if s.is_empty() or s.phase not in ACTIVE: return
	if s.final_board.is_empty(): s.final_board = s.board.duplicate()
	_store(s);s.phase = "interrupted";s.reason = reason;s.finished = int(sim.elapsed)
	if not s.interruption_recorded and not s.result_recorded and not s.moves.is_empty():
		s.interruption_recorded = true
		for person_id in [s.a,s.b]:
			var p: Dictionary = sim.person(person_id)
			if sim.life.is_alive(p): sim._remember(p,s.b if person_id==s.a else s.a,"遊びを切り上げた",reason+"。勝敗は決めず、駒を片付けた。","play_interrupted")

func _store(s: Dictionary) -> void:
	for piece in pieces.values():
		piece.holder = "";piece.reserved_by = "";piece.container = "bank_%d"%int(piece.color);piece.location = "supply";piece.cell = -1
		piece.position = bank_position(int(piece.color),int(piece.ordinal))
	s.board.fill(0);s.cleanup_queue = []
	for id in [s.a,s.b]:
		var p: Dictionary = sim.person(id)
		if p.get("meeting_id","")==s.meeting or (p.get("meeting_id","").is_empty() and p.get("activity_spot","")==s.targets[id].spot):
			p.activity_spot = ""
			if p.get("action","")=="play" and p.get("destination","")==config.site:
				p.path = [];p.moving = false;p.target = p.position

func end(meeting: Dictionary, completed: bool) -> void:
	if not completed: cancel(meeting.get("game_id",""),"次の予定を大切にして、遊びを切り上げた")

func leave(person_id: String) -> bool:
	var s := active_session()
	if s.is_empty() or person_id not in [s.a,s.b]: return false
	cancel(s.id,"本人が遊びを切り上げることにした")
	for meeting in sim.meetings.duplicate():
		if meeting.id==s.meeting: sim._finish_meeting(meeting,false);sim.meetings.erase(meeting)
	return true

func _progress(s: Dictionary, visual: bool = false) -> float:
	return clampf((sim.elapsed-int(s.phase_started)+(sim.minute_remainder if visual else 0.0))/float(config.phase_minutes.get(s.phase,1)),0,1)

func pose_for(id: String) -> Dictionary:
	for s in sessions.values():
		if s.phase not in ACTIVE or id not in [s.a,s.b]: continue
		var active := _person(s,true);var observer := _person(s,false)
		var piece: Dictionary = pieces.get(s.selected_piece,{})
		return {"id":s.id,"key":"four_in_row","phase":s.phase,"phase_progress":_progress(s,true),"role":"active" if id==active.id else "observer",
			"active_id":active.id,"speaker":active.id if s.phase in ["think","react"] else "","reactor":observer.id,
			"board_origin":config.board_origin,"board_yaw":config.board_yaw,"board_size":config.board_size,"cell_centers":cell_centers(),
			"board":s.board.duplicate(),"selected_cell":s.selected_cell,"piece_source_position":bank_position(int(piece.get("color",1)),int(piece.get("ordinal",1))),
			"object_position":piece.get("position",config.board_origin),"object_yaw":0.0,"object_id":s.selected_piece,
			"held_piece_id":s.selected_piece if not piece.get("holder","").is_empty() else "","holder":piece.get("holder",""),
			"actor_target_position":sim.person(id).target,"pieces":pieces,"winner":s.winner,"draw":s.draw,"move_count":s.moves.size()}
	return {}

func _trim() -> void:
	while sessions.size()>32:
		var oldest := ""
		for id in sessions:
			if sessions[id].phase in ACTIVE: continue
			if oldest.is_empty() or int(sessions[id].finished)<int(sessions[oldest].finished) or (sessions[id].finished==sessions[oldest].finished and str(id)<oldest): oldest = id
		if oldest.is_empty(): break
		sessions.erase(oldest)

func serialize() -> Dictionary:
	return {"version":1,"serial":serial,"sessions":sessions.duplicate(true),"pieces":pieces.duplicate(true)}

func restore(data: Dictionary) -> void:
	if data.is_empty(): reset();return
	serial = int(data.serial);sessions = data.sessions.duplicate(true);pieces = data.pieces.duplicate(true)
	# JSON numbers are floats in Godot; board indices and colors remain integers.
	for s in sessions.values():
		for key in ["turn","selected_cell","winner","started","phase_started","finished"]: s[key] = int(s[key])
		s.board = s.board.map(func(value): return int(value))
		s.final_board = s.final_board.map(func(value): return int(value))
		for move in s.moves:
			for key in ["cell","color","at"]: move[key] = int(move[key])
	for piece in pieces.values():
		for key in ["color","ordinal","cell"]: piece[key] = int(piece[key])

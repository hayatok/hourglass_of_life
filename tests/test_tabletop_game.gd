extends SceneTree

var sim
var checks := 0
var failures: Array[String] = []
var path := "user://tabletop-%d.json"%OS.get_process_id()
var bad_path := "user://tabletop-bad-%d.json"%OS.get_process_id()

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text);push_error(text)

func setup(first: String = "haru", second: String = "saki", start_game: bool = true) -> void:
	if is_instance_valid(sim): sim.free()
	sim = load("res://game/scripts/simulation.gd").new();root.add_child(sim);sim.reset(711,12)
	# Controlled engineering fixture. Only setup changes constraints; all board
	# choices, movements, handovers, results and cleanup then use normal minutes.
	for p in sim.people:
		sim.definitions[p.id].routines = []
		p.next_plan_minute = 999999;p.support_next_attempt = 999999
		p.hunger = .02;p.fatigue = .02;p.quiet = .1;p.connection = .5
		p.meeting_id = "";p.routine_id = "";p.activity_spot = "";p.action = "rest";p.remaining = 999999
		p.position = sim.SITES[sim.home_for(p)];p.place = sim.home_for(p);p.target = p.position;p.destination = p.place;p.path = [];p.moving = false
	for id in [first,second]:
		var p: Dictionary = sim.person(id)
		p.place = "square";p.destination = "square";p.position = Vector3(-4.5,0,7.2) if id==first else Vector3(-1.5,0,7.2);p.target = p.position
	if start_game:
		var reply: Dictionary = sim.propose_play(first,second)
		expect(reply.status=="accept","The existing consent, real craft slots and route admit a tabletop session")

func current() -> Dictionary:
	for s in sim.tabletop.sessions.values(): return s
	return {}

func advance_to(phase: String, limit: int = 600) -> bool:
	for minute in limit:
		if current().get("phase","")==phase: return true
		if current().get("phase","")=="interrupted": return false
		sim.advance_minutes(1)
	return current().get("phase","")==phase

func state() -> Dictionary:
	return {"people":sim.people.duplicate(true),"tabletop":sim.tabletop.serialize(),"meetings":sim.meetings.duplicate(true),"events":sim.events.duplicate(true),"rng":str(sim.rng.state),"elapsed":sim.elapsed,"world":sim.interactions.serialize()}

func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3: return a.distance_to(b)<.00001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not same(a[i],b[i]): return false
		return true
	return a==b

func difference(a: Variant, b: Variant, at: String = "state") -> String:
	if same(a,b): return ""
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): return at+" missing "+str(key)
			var found := difference(a[key],b[key],at+"."+str(key))
			if not found.is_empty(): return found
		return at+" extra keys "+str(b.keys())
	if a is Array and b is Array:
		if a.size()!=b.size(): return "%s size %d != %d"%[at,a.size(),b.size()]
		for index in a.size():
			var found := difference(a[index],b[index],at+"[%d]"%index)
			if not found.is_empty(): return found
	return "%s %s(%s) != %s(%s)"%[at,type_string(typeof(a)),str(a).left(160),type_string(typeof(b)),str(b).left(160)]

func result_memories(id: String) -> int:
	var count := 0
	for memory in sim.person(id).memories:
		if memory.kind=="play_result": count += 1
	return count

func reject(raw: Dictionary, text: String) -> void:
	var before := state();FileAccess.open(bad_path,FileAccess.WRITE).store_string(JSON.stringify(raw))
	expect(not sim.load_game(bad_path) and same(before,state()),text+" is rejected without partial mutation")

func play_options(id: String) -> Array:
	var options: Array = []
	sim.person(id).next_plan_minute = 0
	sim.planner.add_options(sim.person(id),options)
	return options.filter(func(option): return option.kind=="play")

func run() -> void:
	var board: Array = [1,1,1,0,2,0,2,0,0,0,0,0,0,0,0,0]
	expect(TabletopGame.choices(board,1)==[3],"AI takes an actual immediate winning row")
	board = [2,2,2,0,1,0,0,0,1,0,0,0,0,0,0,0]
	expect(TabletopGame.choices(board,1)==[3],"AI blocks an opponent's actual immediate win")
	board = [1,1,2,2,2,2,1,1,1,1,2,2,2,2,1,1]
	expect(TabletopGame.winner(board)==0 and TabletopGame.legal_cells(board).is_empty(),"A full nonwinning board is a real draw")
	board = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
	expect(TabletopGame.winner(board)==1,"Four identical diagonal cells win")
	setup()
	if current().is_empty(): sim.free();quit(1);return
	var s := current()
	var starting_skills: Dictionary = sim.person("haru").skills.duplicate(true)
	var starting_relation: Dictionary = sim.person("haru").relationships.duplicate(true)
	expect(sim.tabletop.pieces.size()==16 and s.board.size()==16 and s.board.count(0)==16,"A single physical pool and empty four-by-four board exist before play")
	expect(sim.person("haru").moving and sim.person("saki").moving and result_memories("haru")==0,"Acceptance starts real travel without inventing a result")
	expect(advance_to("place"),"Real travel, thinking, clearing, alignment and grasp precede placement")
	var selected: Dictionary = sim.tabletop.pieces[s.selected_piece]
	expect(selected.holder=="haru" and selected.location=="hand" and s.moves.is_empty(),"Reach transfers the existing selected token into the active hand")
	sim.advance_minutes(3)
	expect(selected.holder.is_empty() and selected.location=="board" and s.moves.size()==1 and s.board[s.selected_cell]==1,"Placing releases at contact and applies one legal board move")
	expect(advance_to("think") and s.turn==2,"A real reaction and turn switch give the other participant the next move")
	var reply: Dictionary = sim.propose_play("aoi","osamu")
	expect(reply.status!="accept" and sim.tabletop.sessions.size()==1,"Another pair cannot duplicate or occupy the same active board")
	expect(advance_to("completed"),"Legal alternating moves reach a win/draw, then every used token is physically returned")
	expect(s.result_recorded and (s.winner!=0 or s.draw) and TabletopGame.winner(s.final_board)==s.winner,"The result comes from the played final board rather than a random success label")
	expect(s.board.count(0)==16 and sim.tabletop.pieces.values().all(func(piece): return piece.location=="supply" and piece.holder.is_empty() and piece.reserved_by.is_empty()),"Normal cleanup returns all sixteen existing tokens and frees reservations")
	expect(result_memories("haru")==1 and result_memories("saki")==1,"Both participants remember the actual result exactly once")
	expect(same(starting_skills,sim.person("haru").skills) and same(starting_relation,sim.person("haru").relationships),"Playing does not fabricate skills or relationship closeness")
	sim.tabletop._record_result(s)
	expect(result_memories("haru")==1,"A repeated result callback cannot duplicate memories")
	# A child and an initially unknown adult can consent under ordinary conditions.
	setup("rin","haru")
	expect(not current().is_empty(),"Age and unfamiliarity do not create an arbitrary tabletop ban")
	sim.tabletop.leave("rin")
	expect(current().phase=="interrupted" and sim.meetings.is_empty() and sim.tabletop.pieces.values().all(func(piece): return piece.holder.is_empty() and piece.reserved_by.is_empty()),"A participant can stop and release the actual board and tokens")
	setup();advance_to("place");sim.life._end_life(sim.person("haru"));sim.advance_minutes(1)
	expect(current().phase=="interrupted" and sim.tabletop.active_session().is_empty() and result_memories("saki")==0,"A holder's death cleans up without inventing a winner")
	setup();advance_to("reach")
	sim.definitions.haru.routines.append({"id":"work_shift","action":"work","place":"home","on_days":[sim.weekday()],"start_minute":sim.minute_of_day(),"duration_minutes":90})
	sim.advance_minutes(1)
	expect(current().phase=="interrupted" and sim.person("haru").meeting_id.is_empty(),"An existing duty interrupts the game rather than being suppressed")
	# Save real physical/logical phases; bulk progression and single minutes agree.
	for phase in ["travel","think","align","reach","place","react","switch_turn","cleanup"]:
		setup();expect(advance_to(phase),"Reached live phase for persistence: "+phase)
		expect(sim.save_game(path),"Saved logical board and physical pool in "+phase)
		var before := state();sim.advance_minutes(25);var expected := state()
		var loaded: bool = sim.load_game(path)
		if loaded and not same(before,state()): print("TABLETOP_RESTORE_DIFF "+phase+" "+difference(before,state()))
		expect(loaded and same(before,state()),"Restored board, roles, holder and RNG in "+phase)
		for minute in 25: sim.advance_minutes(1)
		if not same(expected,state()): print("TABLETOP_REPLAY_DIFF "+phase+" "+difference(expected,state()))
		expect(same(expected,state()),"Phase replay is independent of elapsed-time batch size: "+phase)
	setup();advance_to("place");sim.save_game(path)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var broken: Dictionary = raw.duplicate(true);broken.tabletop.sessions[current().id].board[0] = 1;reject(broken,"Unplaced board token")
	broken = raw.duplicate(true);broken.tabletop.sessions[current().id].turn = 2;reject(broken,"Wrong next player")
	broken = raw.duplicate(true);broken.tabletop.sessions[current().id].winner = 1;reject(broken,"Invented winner")
	broken = raw.duplicate(true);broken.tabletop.pieces[current().selected_piece].holder = "unknown";reject(broken,"Unknown token holder")
	broken = raw.duplicate(true);broken.tabletop.pieces.erase(current().selected_piece);reject(broken,"Missing physical token")
	broken = raw.duplicate(true);broken.erase("tabletop");reject(broken,"Missing current-schema board state")
	broken = raw.duplicate(true);broken.people[0].play_next_attempt = -1;reject(broken,"Invalid play invitation cooldown")
	# Controlled public free-time fixture. The planner offers an alternative;
	# normal consent, routing and logical phases must still create the first move.
	setup("haru","saki",false)
	var options := play_options("haru")
	expect(options.size()==1 and options[0].partner=="saki","A resident can consider one known nearby partner without a player proposal")
	if not options.is_empty():
		expect(sim.planner.begin(sim.person("haru"),options[0]),"The planner dispatches a play candidate through both participants' consent")
		expect(current().phase=="travel" and sim.person("haru").cognition_plan.origin=="resident" and sim.meetings[0].autonomous,"The autonomous invitation records a real resident-origin journey")
		expect(advance_to("place"),"The autonomous plan reaches an actual selected token through travel, thought and alignment")
		sim.advance_minutes(3)
		expect(current().moves.size()==1 and current().board.count(1)==1,"Autonomous play commits its first legal physical move")
		sim.tabletop.leave("haru")
		expect(play_options("haru").is_empty(),"Acceptance cooldown prevents repeated same-day play invitations")
	setup("haru","saki",false)
	var haru: Dictionary = sim.person("haru")
	haru.relationships.erase("saki");haru.known_profiles.erase("saki");haru.knowledge = [];haru.memories = []
	expect(play_options("haru").is_empty(),"Autonomous invitations do not turn an unknown nearby person into a known friend")
	setup("haru","saki",false)
	sim.person("saki").action = "eat"
	var declined: Dictionary = sim.tabletop.propose("haru","saki",true)
	var invited_at: int = sim.person("haru").play_next_attempt
	expect(declined.status!="accept" and sim.tabletop.sessions.is_empty() and sim.person("saki").action=="eat","The invitee finishes an actual meal instead of being pulled into play")
	sim.tabletop.propose("haru","saki",true)
	expect(invited_at>sim.elapsed and sim.person("haru").play_next_attempt==invited_at,"A declined invitation uses a saved fixed cooldown rather than extending or retrying each minute")
	expect(sim.save_game(path) and sim.load_game(path) and sim.person("haru").play_next_attempt==invited_at,"Invitation cooldown survives a same-minute save and resume")
	setup("haru","saki",false)
	sim.definitions.saki.routines.append({"id":"work_shift","action":"work","place":"home","on_days":[sim.weekday()],"start_minute":sim.minute_of_day()+60,"duration_minutes":90})
	expect(sim.tabletop.propose("haru","saki",true).status!="accept" and sim.tabletop.sessions.is_empty(),"An upcoming personal duty can decline a long game even when the invitee is currently free")
	for file in [path,bad_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	sim.free()
	print("Tabletop checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

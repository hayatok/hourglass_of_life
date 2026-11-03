extends SceneTree

const OUT := "res://builds/social-motion"
var main
var sim
var failures: Array[String] = []
var checks := 0
var observations := []

func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message);push_error(message)

func settle() -> void:
	# LookAtModifier's own transition uses actual engine time. Advance the
	# animations by that same elapsed time instead of counting headless frames.
	var start := Time.get_ticks_usec();var previous := start
	while Time.get_ticks_usec()-start<2200000:
		await process_frame
		var now := Time.get_ticks_usec();var delta := (now-previous)/1000000.0;previous = now
		main._process(delta)
		for actor in main.avatars.values(): actor.animator.advance(delta)
	await process_frame

func fixture(a_id: String, b_id: String) -> Dictionary:
	sim.reset(71103,12)
	for p in sim.people:
		sim.definitions[p.id].routines = []
		p.fatigue = .1;p.hunger = .1;p.quiet = .1
		p.next_plan_minute = 999999;p.support_next_attempt = 999999
	main._start_play();sim.running = true
	for actor in main.avatars.values(): actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var a: Dictionary = sim.person(a_id);var b: Dictionary = sim.person(b_id)
	expect(sim._begin_meeting(a,b,sim.benches[0],"bench",false),"The actual bench has two available places for "+a_id+" and "+b_id)
	var m: Dictionary = sim.meetings[-1]
	for minute in 240:
		if m.state=="engaged": break
		sim.advance_minutes(1)
	for p in sim.people: main.avatars[p.id].update_state(p,1,p.id==a_id)
	main._select(a_id,false);main.following = false;main.camera_target = sim.benches[0];main.distance = 5.5
	main.get_node("%CloseRoster").pressed.emit();main.toast_left = 0;main.get_node("%Toast").hide()
	return m

func observe(m: Dictionary, label: String) -> void:
	await settle()
	var roles := [];var row := {"label":label,"minute":sim.elapsed,"remaining":m.remaining,"people":{}}
	for id in [m.a,m.b]:
		var actor = main.avatars[id]
		var other = main.avatars[m.b if id==m.a else m.a]
		var actual: Dictionary = actor.contacts.observed
		var toward: Vector3 = (other.contacts.observed.head-actual.head).normalized()
		var dot: float = actual.head_forward.dot(toward)
		roles.append(actor.conversation_role)
		var speaking: bool = actor.conversation_role=="speaker"
		expect(actor.animator.current_animation in (["talk","sit_talk"] if speaking else ["idle","rest"]),id+": the actual clip matches the speaking or listening role")
		expect(dot>.80,id+": the actual modified head attends to the partner with less than 37 degrees of deviation")
		for side in ["L","R"]: expect(actual.get("foot_error"+side,99)<.04,id+": upper-body attention keeps seated foot "+side+" on its floor contact")
		row.people[id] = {"role":actor.conversation_role,"clip":actor.animator.current_animation,"head_dot":dot,"torso_turn":actor.contacts.social_motion.turn,"pelvis":str(actual.pelvis)}
	roles.sort()
	expect(roles==["listener","speaker"],"The pair has one speaker and one listener, rather than two continuous speaking loops")
	observations.append(row)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"/"+label+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280,800)
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	sim = root.get_node("Sim");sim.set_process(false);main.set_process(false)
	for pair in [["haru","saki"],["tomo","yui"]]:
		var m := fixture(pair[0],pair[1])
		var before: Array = sim._encode(sim.people).duplicate(true);var random_state: int = sim.rng.state
		await observe(m,pair[0]+"-speaking")
		expect(sim._encode(sim.people)==before and sim.rng.state==random_state,"Presentation does not advance life state or consume random choices")
		var previous: String = main.avatars[pair[0]].conversation_role
		sim.advance_minutes(8)
		await observe(m,pair[1]+"-speaking")
		expect(main.avatars[pair[0]].conversation_role!=previous,"Real elapsed meeting time hands the turn to the other resident")
	var mode := "headless" if DisplayServer.get_name()=="headless" else "gpu"
	FileAccess.open(OUT+"/"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Controlled twelve-person town bench fixtures; no human playtest claim.","checks":checks,"failures":failures,"observations":observations},"\t")+"\n")
	print("Resident social motion checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

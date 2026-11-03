extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var sim: LifeSimulation

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3:
		return a.distance_to(b)<.00001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	return a==b

func run() -> void:
	sim = LifeSimulation.new()
	root.add_child(sim)
	sim.running = false
	expect(sim.people.size()==8,"Eight authored residents are loaded")
	expect(sim.person("aoi").relationships.has("osamu"),"Directional initial relationship exists")
	var a = sim.person("aoi")
	var b = sim.person("fumi")
	var before_a = a.memories.size()
	var before_b = b.memories.size()
	var reply = sim.propose_meeting("aoi","fumi")
	expect(reply.status=="accept","A free Saturday afternoon meeting is accepted")
	expect(a.memories.size()==before_a and b.memories.size()==before_b,"Accepting an invitation does not create a shared memory")
	sim.advance_minutes(1)
	expect(sim.meetings[0].state=="travel","Distant participants must actually travel")
	var limit = 0
	while sim.meetings.size()>0 and sim.meetings[0].state=="travel" and limit<181:
		sim.advance_minutes(1)
		limit += 1
	expect(sim.meetings.size()==1 and sim.meetings[0].state=="engaged","Both participants reach their seats")
	expect(a.position.distance_to(b.position)<1.3,"The participants share a physical location")
	expect(a.memories.size()==before_a,"Arrival alone does not create a shared memory")
	sim.advance_minutes(24)
	expect(a.memories.size()==before_a,"A conversation must last the required time")
	sim.advance_minutes(1)
	expect(a.memories.size()==before_a+1 and b.memories.size()==before_b+1,"A completed conversation gives each participant one memory")
	expect(a.memories[-1].other=="fumi" and b.memories[-1].other=="aoi","Memories retain the other person's identity")
	# Interrupting an invitation with a real obligation must not grant credit.
	sim.reset()
	sim.propose_meeting("aoi","fumi")
	sim.start_minute = 1380
	sim.advance_minutes(1)
	expect(sim.meetings.is_empty(),"A scheduled sleep obligation cancels an unfinished meeting")
	expect(sim.person("aoi").memories.is_empty(),"An interrupted meeting does not manufacture a memory")
	# Overnight routines are indexed by the weekday on which they began.
	sim.reset()
	var ritsu = sim.person("ritsu")
	expect(sim._routine_at(ritsu,120,1).id=="night_shift","Monday night shift continues into Tuesday morning")
	expect(sim._routine_at(ritsu,600,1).id=="post_shift_sleep","Night worker has daytime recovery sleep")
	sim.start_minute = 600
	sim.epoch_weekday = 1
	expect(sim.propose_meeting("ritsu","fumi").status=="counteroffer","A busy resident explains that a different time is needed")
	# The exact in-progress state and RNG survive save/load.
	sim.reset(8123)
	sim.propose_meeting("aoi","fumi")
	sim.advance_minutes(7.25)
	var snapshot = sim.people.duplicate(true)
	var minute = sim.elapsed
	expect(sim.save_game("user://test-life-save.json"),"Saving succeeds")
	sim.advance_minutes(400)
	var future = sim.people.duplicate(true)
	var future_rng = sim.rng.state
	expect(sim.load_game("user://test-life-save.json"),"Loading succeeds")
	expect(sim.elapsed==minute and is_equal_approx(sim.minute_remainder,.25),"Time and fractional progress round trip")
	expect(equivalent(sim.people,snapshot),"Positions, paths, memories and needs round trip")
	sim.advance_minutes(400)
	expect(equivalent(sim.people,future) and sim.rng.state==future_rng,"The same saved state produces the same subsequent choices")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-life-save.json"))
	sim.reset()
	# The public worktables now occupy the old (4,4) fixture's footprint.
	expect(sim.place_bench(Vector3(4,0,2.5)).status=="accept" and sim.shared_budget==80,"A valid place uses the shared budget")
	expect(sim.place_bench(Vector3(4,0,2.5)).status=="decline" and sim.shared_budget==80,"Overlapping furniture is rejected without charging")
	expect(sim.place_bench(Vector3(20,0,4)).status=="decline","A bench cannot be placed inside an out-of-bounds building")
	# A week crosses midnight and all seven routine start days.
	sim.reset(71103)
	sim.advance_minutes(1440*7)
	for p in sim.people:
		expect(p.position.is_finite() and absf(p.position.x)<20 and absf(p.position.z)<15,"%s remains in the navigable town"%p.id)
		expect(p.travel_minutes>0 and p.activity_minutes>0,"%s both travels and spends time on activities"%p.id)
		expect(p.fatigue>=0 and p.fatigue<=1 and p.hunger>=0 and p.hunger<=1,"%s needs remain bounded"%p.id)
	expect(sim.weekday()==5,"The seven-day week remains continuous across seasonal dates")
	for failure in failures:
		print("FAIL: "+failure)
	print("Simulation checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

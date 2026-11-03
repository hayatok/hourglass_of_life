extends SceneTree

# Returning the full archive reproduces the old traversal. Every production
# consumer still applies its original state check, so this is a reference with
# no index or skipped decisions.
class ArchiveReference:
	extends WorkFamily
	func _active_supports() -> Array:
		return supports

var failures: Array[String] = []
var checks := 0
var sim

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func town(reference: bool = false):
	var instance = load("res://game/scripts/simulation.gd").new()
	root.add_child(instance)
	if reference: instance.work_family = ArchiveReference.new(instance)
	instance.reset(944)
	instance.start_minute = 900
	instance.epoch_weekday = 0
	for p in instance.people:
		p.fatigue = .1;p.hunger = .1;p.quiet = .1
		p.next_plan_minute = 999999;p.support_next_attempt = 999999
		instance._choose_action(p)
	for id in ["ryo","rin"]:
		var p: Dictionary = instance.person(id)
		p.position = instance.SITES.home_ogawa;p.place = "home_ogawa";p.path.clear();p.moving = false
	var giver: Dictionary = instance.person("nagisa")
	giver.position = instance.SITES.bakery_cafe;giver.place = "bakery_cafe";giver.path.clear();giver.moving = false
	giver.action = "rest";giver.routine_id = "";giver.remaining = 600
	instance.work_family.household(instance.person("ryo")).home_load = .8
	return instance

func archived(index: int) -> Dictionary:
	return {"id":"archived_%d"%index,"giver":"fumi","receiver":"osamu","kind":"chores","place":"home_saeki","state":"completed","requested":0,"began":0}

func fixture(id: String, giver: String, receiver: String, kind: String, place: String, state: String = "active") -> Dictionary:
	return {"id":id,"giver":giver,"receiver":receiver,"kind":kind,"place":place,"state":state,"requested":int(sim.elapsed),"began":int(sim.elapsed)}

func compare_queries(label: String) -> void:
	var reference = ArchiveReference.new(sim)
	reference.restore(sim.work_family.serialize().duplicate(true))
	var matches := true
	for p in sim.people:
		var base: Dictionary = sim._authored_routine_at(p)
		if sim.work_family.adjust_routine(p,base,-1,-1)!=reference.adjust_routine(p,base,-1,-1): matches = false
		for offset in [0,179,180,359,360]:
			if sim.work_family.reserved(p,sim.elapsed+offset)!=reference.reserved(p,sim.elapsed+offset): matches = false
		if sim.work_family.person_text(p)!=reference.person_text(p): matches = false
	expect(matches,label+": current routines, reservation boundaries and descriptions match archive traversal")

func fingerprint(instance) -> String:
	return JSON.stringify(instance._encode({"people":instance.people,"events":instance.events,"meetings":instance.meetings,"elapsed":instance.elapsed,"remainder":instance.minute_remainder,"rng":str(instance.rng.state),"work_family":instance.work_family.serialize(),"social":instance.social.serialize(),"life":instance.life.serialize(),"agenda":instance.agenda.serialize()})).sha256_text()

func state(instance) -> Dictionary:
	return {"people":instance.people,"events":instance.events,"meetings":instance.meetings,"elapsed":instance.elapsed,"remainder":instance.minute_remainder,"rng":str(instance.rng.state),"work_family":instance.work_family.serialize(),"social":instance.social.serialize(),"life":instance.life.serialize(),"agenda":instance.agenda.serialize()}.duplicate(true)

func equivalent(a: Variant, b: Variant) -> bool:
	# JSON restores all numbers as floats and can round their final decimals.
	# IDs, event text, times, relationships, histories and RNG must still agree.
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Vector3 and b is Vector3: return a.distance_to(b)<.00001
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

func replay(reference: bool) -> String:
	var instance = town(reference)
	for index in 256: instance.work_family.supports.append(archived(index))
	instance.work_family.adjust_routine(instance.person("nagisa"),{},-1,-1)
	expect(instance.propose_support("ryo","nagisa").status=="accept","Reference=%s accepts the same real support after a long archive"%reference)
	instance.advance_minutes(7.25)
	var path := "user://test-support-index-%s.json"%reference
	expect(instance.save_game(path),"Reference=%s saves the in-progress journey"%reference)
	instance.advance_minutes(500)
	var result := fingerprint(instance)
	var future := state(instance)
	expect(instance.load_game(path),"Reference=%s restores support at the same minute with a populated derived index"%reference)
	instance.advance_minutes(500)
	expect(equivalent(state(instance),future),"Reference=%s save replay retains identical actual outcomes and RNG"%reference)
	expect(instance.work_family.serialize().supports.size()>=257,"Reference=%s serialization retains the entire completed support archive"%reference)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	instance.free()
	return result

func run() -> void:
	sim = town()
	var work = sim.work_family
	for index in 512: work.supports.append(archived(index))
	var empty: Array = work._active_supports()
	expect(empty.is_empty() and is_same(empty,work._active_supports()),"An unchanged minute and archive reuse the derived empty active list")
	var first := fixture("raw_first","fumi","ryo","chores","home_ogawa")
	work.supports.append(first)
	expect(work.adjust_routine(sim.person("fumi"),{},-1,-1).get("place","")=="home_ogawa","A raw append changes archive size and is visible in the same minute")
	compare_queries("Raw append")
	var second := fixture("raw_second","fumi","osamu","chores","home_saeki")
	work.supports.append(second)
	expect(work._active_supports().map(func(h):return h.id)==["raw_first","raw_second"],"Filtering keeps original support order and shared record references")
	expect(work.adjust_routine(sim.person("fumi"),{},-1,-1).place=="home_ogawa","The first applicable support retains precedence")
	compare_queries("Multiple records")
	# Fixture code can directly finish a shared record. Each consumer keeps the
	# original guard even if that record remains in the current minute's index.
	first.state = "completed"
	expect(work.adjust_routine(sim.person("fumi"),{},-1,-1).place=="home_saeki","Finishing a shared reference is observed immediately without a minute advance")
	compare_queries("Direct reference completion")
	# Array replacement must not be mistaken for the old same-sized archive.
	work.supports = [fixture("array_a","fumi","ryo","chores","home_ogawa")]
	work._active_supports()
	work.supports = [fixture("array_b","fumi","osamu","chores","home_saeki")]
	expect(work.adjust_routine(sim.person("fumi"),{},-1,-1).place=="home_saeki","A different same-sized array at the same minute invalidates the derived list")
	compare_queries("Same-minute array replacement")
	var restored: Dictionary = work.serialize().duplicate(true)
	restored.supports[0].place = "home_ogawa"
	work._active_supports()
	work.restore(restored)
	expect(work.adjust_routine(sim.person("fumi"),{},-1,-1).place=="home_ogawa","Same-minute restore with the same number of supports never reuses prior records")
	compare_queries("Same-minute restore")
	work.reset()
	expect(work._active_supports().is_empty() and not work.reserved(sim.person("fumi"),sim.elapsed),"Reset clears both the archive and any derived reservations")
	sim.free()
	# End one real agreement and accept another without changing elapsed time.
	sim = town();work = sim.work_family
	expect(sim.propose_support("ryo","nagisa").status=="accept","A real care request starts with the existing admission rules")
	var help: Dictionary = work.supports[-1]
	work.adjust_routine(sim.person("nagisa"),{},-1,-1)
	work._end_support(help,false,"予定を見直した")
	expect(not work.reserved(sim.person("nagisa"),sim.elapsed),"Ending an agreement removes its reservation in the same minute")
	expect(sim.propose_support("ryo","nagisa").status=="accept" and work.supports[-1].id!=help.id,"A new agreement in the same minute is not hidden behind the ended record")
	compare_queries("End then new consent")
	# Going to handoff is still active; it restores the original caregiver's duty.
	help = work.supports[-1]
	var limit := 0
	while help.state=="travel" and limit<180:sim.advance_minutes(1);limit += 1
	expect(help.state=="active" and sim._routine_at(sim.person("ryo")).is_empty(),"Real arrival alone grants the original caregiver free time")
	var receiver: Dictionary = sim.person("ryo")
	receiver.position = sim.SITES.garden;receiver.place = "garden";receiver.path.clear();receiver.moving = false
	work._active_supports()
	work._end_support(help,true,"")
	expect(help.state=="handoff" and sim._routine_at(receiver).get("id","")=="after_school_care" and sim._routine_at(sim.person("nagisa")).get("id","")=="support_care","Handoff retains the helper and immediately restores the receiver's responsibility")
	compare_queries("Active handoff")
	receiver.position = sim.SITES.home_ogawa;receiver.place = "home_ogawa";receiver.path.clear();receiver.moving = false
	work.tick()
	expect(help.state=="completed" and not work.reserved(sim.person("nagisa"),sim.elapsed),"The returned caregiver ends the handoff at the same elapsed minute")
	compare_queries("Handoff completion")
	sim.free()
	# Invalidation during the tick must not clear the array currently being read.
	sim = town();work = sim.work_family
	var n: Dictionary = sim.person("nagisa")
	n.position = sim.SITES.home_ogawa;n.place = "home_ogawa";n.moving = false;n.path.clear()
	var f: Dictionary = sim.person("fumi")
	f.position = sim.SITES.home_saeki;f.place = "home_saeki";f.moving = false;f.path.clear()
	work.supports = [fixture("first_arrival","nagisa","ryo","care","home_ogawa","travel"),fixture("second_arrival","fumi","osamu","chores","home_saeki","travel")]
	work.tick()
	expect(work.supports.all(func(h):return h.state=="active"),"Changing the first record does not drop later arrivals from the current tick")
	work._active_supports()
	sim.life._end_life(n)
	work.tick()
	expect(work.supports[0].state=="interrupted" and work.supports[1].state=="active","A death invalidates the first agreement without skipping an unrelated active one")
	compare_queries("Death and another active agreement")
	sim.free()
	var indexed := replay(false)
	var reference := replay(true)
	expect(indexed==reference,"Indexed and cache-free traversal produce identical people, facts, finances, meetings, histories and RNG from the same input")
	print("Support index checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

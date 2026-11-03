extends SceneTree

var main: Node3D
var sim: LifeSimulation
var errors: Array[String] = []
var checks := 0
var metrics: Dictionary = {}
const OUT := "res://docs/verification/v0.8/activities"

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> bool:
	checks += 1
	if not ok: errors.append(message);push_error(message)
	return ok

func frame(count: int = 1) -> void:
	for i in count:
		for p in sim.people: main.avatars[p.id].update_state(p,1.0/60.0,false)
		await process_frame

func arrive(people: Array) -> void:
	var limit := 0
	while people.any(func(p): return p.moving) and limit<180:
		sim.advance_minutes(1);limit += 1
	expect(not people.any(func(p): return p.moving),"People reach real furniture before performing its action")
	for p in sim.people: main.avatars[p.id].update_state(p,1,false)
	await frame(30)

func capture(name: String, target: Vector3) -> void:
	for actor in main.avatars.values(): actor.get_node("Name").hide()
	main.camera.position = target+Vector3(3.4,2.5,4.1)
	main.camera.look_at(target+Vector3.UP*.65)
	await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")

func clean_reset(population: int = LifeSimulation.BASE_POPULATION) -> void:
	sim.reset(71103,population);sim.running = true;sim.set_process(false)
	await process_frame

func free_activity_fixture() -> void:
	await clean_reset(LifeSimulation.EXPANDED_POPULATION)
	# These checks measure actual body/furniture contact. Each participant has
	# free time so a shift beginning during another person's journey cannot
	# replace the particular pose being measured. Daily life has separate tests.
	for definition in sim.definitions.values(): definition.routines = []
	for p in sim.people:
		p.routine_id = "";p.next_plan_minute = 999999;p.support_next_attempt = 999999

func run() -> void:
	root.size = Vector2i(1440,900)
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.set_process(false);sim = root.get_node("Sim");sim.set_process(false)
	main.get_node("%TitleScreen").hide();main.get_node("%HUD").hide()
	await clean_reset()
	expect(sim.activities.spots.size()==50,"The expanded town supplies 48 fixed places and two editable bench seats")
	for id in ["saki","haru","tomo","yui"]:
		var bed: Dictionary = sim.activities.spots.get("sleep_"+id,{})
		expect(bed.get("resident","")==id and "sleep" in bed.get("actions",[]),id+": the expanded town includes an actual assigned bed")
	for spot in sim.activities.spots.values():
		if sim.activities.rooms.has(spot.site): expect(sim.activities.walkable(spot.site,spot.approach),spot.id+": the furniture approach is walkable")
	# Seat claims are exclusive, including visitors and delayed arrival.
	var a = sim.person("aoi");var f = sim.person("fumi");var r = sim.person("ryo")
	sim._assign(a,"social","square",60,"ベンチで休む")
	sim._assign(f,"social","square",60,"ベンチで休む")
	expect(a.activity_spot!=f.activity_spot and not a.activity_spot.is_empty(),"Two people reserve different bench seats while travelling")
	var occupied = [a.activity_spot,f.activity_spot]
	sim._assign(r,"social","square",60,"空きを探す")
	expect(r.activity_spot.is_empty(),"A third person cannot occupy either reserved seat")
	sim._assign(a,"rest",sim.home_for(a),60,"家へ戻る")
	sim._assign(r,"social","square",60,"空いた席へ向かう")
	expect(r.activity_spot==occupied[0],"Changing plans releases the old place")
	var budget := sim.shared_budget
	expect(sim.place_bench(Vector3(2.8,0,4.5)).status=="decline" and sim.shared_budget==budget,"The player cannot place a bench through a public worktable")
	if expect(sim._begin_meeting(r,f,sim.benches[0],"bench",false),"Current seat occupants can use their own bench for a conversation"):
		await arrive([r,f])
		for p in [r,f]:
			var actor = main.avatars[p.id]
			var other = f if p.id==r.id else r
			var observed: Dictionary = actor.contacts.observed
			var direction: Vector3 = (main.avatars[other.id].head_position()-observed.head).normalized()
			expect(observed.head_forward.dot(direction)>.35,p.id+": the real head turns toward the conversation partner")
			expect(observed.handL.y>observed.head.y-.20,p.id+": greeting raises a hand while the seated body stays on the bench")
		await capture("06-bench-greeting",sim.benches[0])
	# The indoor route must go around furniture rather than through its occupied rectangle.
	var route := sim.activities.indoor_route("home_ogawa",Vector3(-9,0,8.8),Vector3(-10.1,0,4.5))
	var previous := Vector3(-9,0,8.8)
	var crossed := false
	for point in route:
		for i in 11:
			var sample := previous.lerp(point,i/10.0)
			if sim.activities.obstacles.home_ogawa.any(func(rect): return rect.has_point(Vector2(sample.x,sample.z))): crossed = true
		previous = point
	expect(not crossed and route.size()>2,"A real bedroom journey bends around furniture")
	# Both radio participants reach the same worktable before their hands are constrained.
	await clean_reset()
	sim._assign(sim.person("ryo"),"work","workshop",90,"一人で作業台を使う")
	var cash: float = sim.work_family.household(sim.person("aoi")).cash
	var busy_reply = sim.propose_project("aoi","osamu")
	expect(busy_reply.status=="defer" and sim.meetings.is_empty(),"A shared project waits when a third person holds one work place")
	expect(sim.work_family.household(sim.person("aoi")).cash==cash,"Waiting for a worktable does not consume project materials")
	sim._assign(sim.person("ryo"),"rest","home_ogawa",90,"作業台を離れる")
	var reply = sim.propose_project("aoi","osamu")
	if expect(reply.status=="accept","The available radio worktable supports joint work"):
		await arrive([sim.person("aoi"),sim.person("osamu")])
		for id in ["aoi","osamu"]:
			var actor = main.avatars[id]
			metrics[id+"_work"] = actor.contacts.observed.duplicate()
			expect(actor.animation_name=="work","Actual work starts after both people arrive")
			for side in ["L","R"]:
				expect(actor.contacts.observed.get("hand_error"+side,99)<.04,id+": the rendered wrist reaches its work target")
		await capture("01-radio-work",Vector3(0,0,-7))
	# A parent and child share the model table; the child's support has real geometry.
	await clean_reset()
	sim._assign(sim.person("nagisa"),"rest","home_ogawa",180,"食卓で休む")
	reply = sim.propose_project("ryo","rin")
	if expect(reply.status=="accept","The parent and child can use the free model table"):
		await arrive([sim.person("ryo"),sim.person("rin")])
		var child = main.avatars.rin
		expect(child.contacts.step.visible and child.visual.position.y>0,"A child stands on a visible step at an adult work surface")
		metrics.child_work = child.contacts.observed.duplicate()
		for side in ["L","R"]: expect(child.contacts.observed.get("hand_error"+side,99)<.04,"The child's hand reaches the shared work surface")
		await capture("02-family-model",Vector3(-7.55,0,7.3))
	# Every resident eats at a chair, adapts to its height, and carries a real cup.
	await free_activity_fixture()
	expect(sim.people.size()==12,"The chair and drinking contact audit includes all twelve residents")
	for p in sim.people: sim._assign(p,"eat",sim.home_for(p),600,"家で食事をする")
	await arrive(sim.people)
	for p in sim.people:
		var actor = main.avatars[p.id]
		var activity: Dictionary = sim.activities.for_person(p)
		expect(actor.animation_name=="eat" and activity.get("pose")=="seat",p.id+": food uses an actual dining chair")
		actor.jrpg.animator.seek(1.2,true);actor.jrpg.animator.advance(0)
	await frame(3)
	for p in sim.people:
		var actor = main.avatars[p.id]
		var activity: Dictionary = sim.activities.for_person(p)
		var actual: Dictionary = actor.contacts.observed
		metrics[p.id+"_eat"] = actual.duplicate()
		var expected_hip: float = activity.contact.y+.095*actor.jrpg.rest_height/1.65*actor.visual.scale.y
		expect(absf(actual.get("pelvis",Vector3.ZERO).y-expected_hip)<.03,p.id+": hips align with the seat surface")
		for side in ["L","R"]:
			expect(actual.get("hand_error"+side,99)<.04,p.id+": eating hand reaches its real target")
			expect(actual.get("foot_error"+side,99)<.04,p.id+": seated feet reach floor or child support")
		var cup = actor.contacts.mug
		expect(cup.visible,p.id+": the drinking hand has an actual cup")
		var rim: Vector3 = cup.global_position+Vector3.UP*.115
		expect(rim.distance_to(actual.get("mouth",Vector3.INF))<.12,p.id+": the cup rim reaches the mouth during a sip")
	await capture("03-family-meal",Vector3(-10.45,0,7.3))
	await capture("04-older-meal",Vector3(-10.45,0,-2.7))
	var grown = sim.person("rin")
	grown.age = 18
	main.avatars.rin.update_state(grown,1,false)
	# Let the new body's idle-to-eat blend finish before measuring a sip.
	await frame(20)
	main.avatars.rin.jrpg.animator.seek(1.2,true);main.avatars.rin.jrpg.animator.advance(0)
	await frame(3)
	var adult = main.avatars.rin
	expect(adult.displayed_model=="rin_adult" and not adult.contacts.step.visible,"Growing up uses the adult body and removes the child support")
	for side in ["L","R"]:
		expect(adult.contacts.observed.get("hand_error"+side,99)<.04,"The grown resident still reaches the dining target")
		expect(adult.contacts.observed.get("foot_error"+side,99)<.04,"The grown resident still reaches the floor")
	metrics.rin_adult_eat = adult.contacts.observed.duplicate()
	# Sleep is face up and anchored to each person's own mattress and pillow.
	await free_activity_fixture()
	for p in sim.people: sim._assign(p,"sleep",sim.home_for(p),600,"自分の寝床で眠る")
	await arrive(sim.people)
	for p in sim.people:
		var actor = main.avatars[p.id]
		var activity: Dictionary = sim.activities.for_person(p)
		var actual: Dictionary = actor.contacts.observed
		metrics[p.id+"_sleep"] = actual.duplicate()
		expect(actor.animation_name=="sleep" and activity.resident==p.id,p.id+": sleep uses the resident's own bed")
		var head: Vector3 = actual.get("head",Vector3.INF)
		var pillow_error := Vector2(head.x,head.z).distance_to(Vector2(activity.contact.x,activity.contact.z))
		expect(pillow_error<.03,"%s: the head aligns with the pillow (error %.4fm)"%[p.id,pillow_error])
		var head_bone: Transform3D = actor.jrpg.skeleton.get_bone_global_pose(actor.jrpg.skeleton.find_bone("DEF-head"))
		var front: Vector3 = actor.jrpg.skeleton.global_basis*head_bone.basis.z
		expect(front.normalized().dot(Vector3.UP)>.8,p.id+": the face is up while sleeping")
	await capture("05-family-beds",Vector3(-9,0,4.5))
	await capture("07-north-shared-beds",LifeSimulation.SITES.home_north_shared)
	await capture("08-mori-beds",LifeSimulation.SITES.home_mori)
	var save_path := "user://test-activity-furniture.json"
	var saved_ids: Array = sim.people.map(func(p): return p.activity_spot)
	expect(sim.save_game(save_path) and sim.load_game(save_path),"Occupied furniture survives an actual save and load")
	expect(sim.people.map(func(p): return p.activity_spot)==saved_ids,"Reloading keeps the same resident-to-furniture assignments")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	for p in raw.people: p.erase("activity_spot")
	var file := FileAccess.open(save_path,FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
	var positions: Array = sim.people.map(func(p): return p.position)
	expect(sim.load_game(save_path),"An older save without furniture assignments remains loadable")
	expect(sim.people.map(func(p): return p.position)==positions,"Adopting furniture does not teleport people from an old save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if DisplayServer.get_name()!="headless":
		var metrics_file := FileAccess.open(OUT+"/contact-metrics.json",FileAccess.WRITE)
		metrics_file.store_string(JSON.stringify(sim._encode(metrics),"\t"))
	print("Furniture and activity checks: %d passed, %d failed"%[checks-errors.size(),errors.size()])
	quit(0 if errors.is_empty() else 1)

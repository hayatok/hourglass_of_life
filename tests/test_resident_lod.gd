extends SceneTree

const CHARACTERS = ["nagisa","ryo","rin","rin_adult","osamu","fumi","maho","ritsu","aoi"]
const OUTPUT = "res://docs/verification/v0.5/lod"
var checks := 0
var failures: Array[String] = []
var evidence := {}
var camera: Camera3D
var stage: Node3D

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func triangles(model: JrpgResidentModel) -> int:
	var count := 0
	for part in model.lod_parts.values(): count += part.mesh.get_faces().size()/3
	return count

func capture(name: String, target: Vector3) -> void:
	camera.global_position = target+Vector3(2.6,1.5,3.8)
	camera.look_at(target+Vector3.UP*.3)
	await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")

func model_checks(id: String) -> void:
	var model: JrpgResidentModel = load("res://game/scenes/characters/"+id+".tscn").instantiate()
	stage.add_child(model)
	await process_frame
	model.set_process(false)
	model.set_age(72)
	model.set_expression(.9,.7,.3)
	model._process(.1)
	var skeleton := model.skeleton
	var player := model.animator
	var face := model.face
	var face_material := face.get_active_material(0)
	var materials := model.body_materials.duplicate()
	model.prepare_lods()
	expect(model.lod_variants.size()==3 and not model.lod_variants[1].is_empty() and not model.lod_variants[2].is_empty(),id+": both supplied LOD assets have compatible meshes, skins and expressions")
	var counts := []
	for level in [0,1,2]:
		expect(model.set_lod(level),id+": LOD%d can be selected"%level)
		counts.append(triangles(model))
	expect(counts[2]<counts[1] and counts[1]<counts[0],id+": distant meshes actually reduce triangle count")
	evidence[id] = {"triangles":counts,"bones":skeleton.get_bone_count(),"expressions":face.mesh.get_blend_shape_count()}
	for clip in ["walk","sit_talk","talk","work","sleep"]:
		player.play(clip,0)
		player.seek(player.current_animation_length*.37,true)
		player.advance(0)
		player.speed_scale = .73
		model._process(0)
		var phase := player.current_animation_position
		var pelvis := skeleton.get_bone_global_pose(skeleton.find_bone("DEF-pelvis"))
		var smile := face.get_blend_shape_value(face.find_blend_shape_by_name("Smile"))
		var tired := face.get_blend_shape_value(face.find_blend_shape_by_name("Tired"))
		for level in [1,2,0]:
			expect(model.set_lod(level),id+": switching during "+clip)
			expect(model.skeleton==skeleton and model.animator==player and model.face==face,id+": switching keeps the original skeleton/player/face objects")
			expect(player.current_animation==clip and is_equal_approx(player.current_animation_position,phase) and is_equal_approx(player.speed_scale,.73),id+": switching keeps animation, phase and playback speed")
			expect(skeleton.get_bone_global_pose(skeleton.find_bone("DEF-pelvis")).is_equal_approx(pelvis),id+": switching does not reset the actual pose")
			expect(is_equal_approx(face.get_blend_shape_value(face.find_blend_shape_by_name("Smile")),smile) and is_equal_approx(face.get_blend_shape_value(face.find_blend_shape_by_name("Tired")),tired),id+": switching preserves current expression values")
			var active_body_material = null
			for part in model.lod_parts.values():
				if part!=face: active_body_material = part.get_active_material(0)
			expect(model.body_materials==materials and active_body_material==materials[0] and face.get_active_material(0)==face_material and is_equal_approx(materials[0].get_shader_parameter("hair_age"),.9),id+": switching preserves active owned toon/face materials and aging")
	player.speed_scale = 0
	if id in ["nagisa","rin_adult"]:
		player.play("idle",0);player.seek(.5,true);player.advance(0)
		model.set_lod(0)
		await capture(id+"-lod0",Vector3(0,.8,0))
		model.set_lod(2)
		await capture(id+"-lod2",Vector3(0,.8,0))
	var loaded := model.lod_resources_loaded
	for iteration in 30:
		model.set_lod(iteration%3)
	expect(model.lod_resources_loaded==loaded and loaded==2,id+": cached LOD changes do not instantiate or load a new model every frame")
	stage.remove_child(model)
	model.free()

func avatar_checks() -> void:
	var sim = root.get_node("Sim")
	sim.reset(71103);sim.running = false
	var p: Dictionary = sim.person("rin")
	var avatar = load("res://game/scenes/resident_avatar.tscn").instantiate()
	stage.add_child(avatar);avatar.configure(p)
	var contacts = avatar.contacts
	var skeleton: Skeleton3D = avatar.jrpg.skeleton
	var before_state := JSON.stringify(sim._encode(sim.people))
	var before_rng: int = sim.rng.state
	avatar.update_lod(24,false)
	expect(avatar.jrpg.lod_level==1,"Moving beyond the first exit threshold selects LOD1")
	avatar.update_lod(19,false)
	expect(avatar.jrpg.lod_level==1,"The first hysteresis band avoids flicker on the way back")
	avatar.update_lod(16,false)
	expect(avatar.jrpg.lod_level==0,"Returning inside the near threshold restores LOD0")
	avatar.update_lod(38,false)
	expect(avatar.jrpg.lod_level==2,"A distant camera selects LOD2 directly")
	avatar.update_lod(33,false)
	expect(avatar.jrpg.lod_level==2,"The far hysteresis band avoids repeated switches")
	avatar.update_lod(30,false)
	expect(avatar.jrpg.lod_level==1,"Returning inside the distant threshold restores LOD1")
	avatar.update_lod(100,true)
	expect(avatar.jrpg.lod_level==0,"Selection always keeps the full-detail model")
	camera.global_position = avatar.global_position+Vector3(0,40,40)
	avatar.update_state(p,.1,false)
	expect(avatar.jrpg.lod_level==2,"The normal avatar update uses the actual active camera distance")
	expect(avatar.contacts==contacts and avatar.jrpg.skeleton==skeleton,"Automatic switching leaves contact and gaze modifiers bound to the same rig")
	expect(JSON.stringify(sim._encode(sim.people))==before_state and sim.rng.state==before_rng,"Changing detail and camera distance never modifies simulation state or randomness")
	p.age = 12;avatar.update_state(p,.1,false)
	expect(avatar.displayed_model=="rin_adult" and avatar.jrpg.lod_level==2,"A distant child can grow into the adult model and retain distance-based detail")
	var growth: Vector3 = avatar.visual.scale
	p.age = 72;avatar.update_state(p,.1,true)
	expect(avatar.jrpg.lod_level==0 and is_equal_approx(avatar.jrpg.body_materials[0].get_shader_parameter("hair_age"),.9),"Selecting the aged adult body restores detail without losing aging")
	expect(avatar.visual.scale.y>=growth.y,"LOD selection never substitutes a child's body for the grown resident")
	stage.remove_child(avatar);avatar.free()
	var legacy = load("res://game/scenes/resident_avatar.tscn").instantiate()
	stage.add_child(legacy)
	var guest: Dictionary = p.duplicate(true);guest.id = "legacy_guest";guest.name = "旧モデルの住人"
	legacy.configure(guest);legacy.update_lod(100,false)
	expect(legacy.jrpg==null and legacy.get_node("Visual/Hips").visible,"A legacy/procedural avatar without supplied LODs keeps its original visible model")
	stage.remove_child(legacy);legacy.free()

func contact_checks() -> void:
	var sim = root.get_node("Sim")
	var furniture = load("res://game/scenes/activity_layout.tscn").instantiate()
	stage.add_child(furniture)
	for entry in [{"id":"nagisa","kind":"eat","site":"home_ogawa"},{"id":"rin","kind":"hobby","site":"home_ogawa"},{"id":"nagisa","kind":"sleep","site":"home_ogawa"}]:
		sim.reset(71103);sim.running = false
		for resident in sim.people: resident.activity_spot = ""
		var p: Dictionary = sim.person(entry.id)
		var spot: Dictionary = sim.activities.reserve(p,entry.kind,entry.site)
		expect(not spot.is_empty(),"The contact fixture uses a real "+entry.kind+" activity place")
		if spot.is_empty(): continue
		p.position = spot.approach;p.place = entry.site;p.moving = false;p.path = []
		p.action = entry.kind;p.activity_spot = spot.id
		var avatar = load("res://game/scenes/resident_avatar.tscn").instantiate()
		stage.add_child(avatar);avatar.configure(p)
		avatar.update_state(p,1,true)
		avatar.animator.play(avatar.animation_name,0)
		avatar.animator.seek(.6,true)
		avatar.animator.advance(0)
		avatar.update_state(p,1,true)
		avatar.animator.advance(0)
		await process_frame
		var contacts = avatar.contacts
		var pelvis: Vector3 = contacts.point("pelvis")
		var head: Vector3 = contacts.point("head")
		var scale: Vector3 = avatar.visual.scale
		if entry.kind=="sleep":
			expect(absf(head.y-pelvis.y)<.35,"The sleep fixture is actually lying down before LOD switching")
		elif entry.kind=="eat":
			expect(absf(pelvis.y-spot.contact.y)<.2,"The eating fixture actually sits on its chair before LOD switching")
		var valid_contacts := true
		for level in [1,2,0]:
			expect(avatar.jrpg.set_lod(level),entry.id+": LOD switch with "+entry.kind+" contacts")
			avatar.contacts.update_contact(p,spot,avatar.animation_name,Vector3.ZERO,false,0)
			avatar.animator.advance(0)
			await process_frame
			valid_contacts = valid_contacts and avatar.contacts==contacts and avatar.visual.scale==scale
			valid_contacts = valid_contacts and contacts.point("pelvis").distance_to(pelvis)<.015 and contacts.point("head").distance_to(head)<.015
			if entry.kind=="eat": valid_contacts = valid_contacts and contacts.mug.visible and contacts.foot_ik.L.active and contacts.hand_ik.R.active
			if entry.id=="rin": valid_contacts = valid_contacts and contacts.step.visible and contacts.hand_ik.L.active
			if entry.kind=="sleep": valid_contacts = valid_contacts and not contacts.look.active and not contacts.mug.visible
			expect(valid_contacts,entry.id+": "+entry.kind+" keeps the measured body contact, scale, props and modifiers across LODs")
		avatar.jrpg.set_lod(2)
		await capture(entry.id+"-"+entry.kind+"-lod2",avatar.focus_position())
		stage.remove_child(avatar);avatar.free()
	stage.remove_child(furniture);furniture.free()

func run() -> void:
	root.size = Vector2i(1000,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if root.get_node_or_null("Sim")==null:
		expect(false,"The real simulation autoload is available before the LOD integration checks")
		print("Resident LOD checks: 0 passed, 1 failed")
		quit(1)
		return
	stage = Node3D.new();root.add_child(stage)
	camera = Camera3D.new();stage.add_child(camera);camera.current = true;camera.fov = 34
	var environment := WorldEnvironment.new();stage.add_child(environment)
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.82,.86,.84)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .6
	var light := DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees = Vector3(-45,-25,0);light.light_energy = .8
	for id in CHARACTERS: await model_checks(id)
	await avatar_checks()
	await contact_checks()
	var file := FileAccess.open(OUTPUT+"/checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"models":evidence,"renderer":DisplayServer.get_name()},"\t"));file.close()
	print("Resident LOD checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	stage.free()
	quit(0 if failures.is_empty() else 1)

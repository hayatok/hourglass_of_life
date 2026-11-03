extends SceneTree

const OUT := "res://docs/verification/v0.8/population"
const NEW_IDS := ["saki","haru","tomo","yui"]
const BASES := {"saki":"fumi","haru":"aoi","tomo":"ryo","yui":"maho"}
const NAMES := {"saki":"白井 咲","haru":"瀬戸 晴","tomo":"森 智","yui":"森 結衣"}
const AGES := {"saki":42,"haru":25,"tomo":52,"yui":27}
const RIG_BONE_COUNTS := {"saki":36,"haru":35,"tomo":35,"yui":36}
var sim: LifeSimulation
var checks := 0
var failures: Array[String] = []
var report := {"scope":"12-resident housing and dedicated resident bodies; agent verification, not a human playtest","rendered":false,"variants":{},"rooms":{},"images":[]}

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func person(id: String) -> Dictionary:
	if not sim.person(id).is_empty(): return sim.person(id).duplicate(true)
	var p: Dictionary = sim.person(BASES[id]).duplicate(true)
	p.id = id
	p.name = NAMES[id]
	p.age = AGES[id]
	return p

func actor(id: String, parent: Node) -> Node3D:
	var p: Dictionary = person(id) if id in NEW_IDS else sim.person(id).duplicate(true)
	p.position = Vector3.ZERO
	var avatar = load("res://game/scenes/resident_avatar.tscn").instantiate()
	parent.add_child(avatar)
	avatar.configure(p)
	avatar.name_label.hide()
	avatar.animator.play("idle",0)
	avatar.animator.seek(.4,true)
	avatar.animator.advance(0)
	avatar.animator.speed_scale = 0
	return avatar

func matches_deformation_contract(id: String, model: JrpgResidentModel) -> bool:
	# Exact counts retain DEF35; only the two skirt bodies add their real helper.
	var expected_count: int = RIG_BONE_COUNTS[id]
	if model.skeleton.get_bone_count()!=expected_count: return false
	var required_names: Array = []
	for bone in JrpgResidentModel.REQUIRED_BONES: required_names.append("DEF-"+bone)
	if id in ["saki","yui"]: required_names.append("DEF-skirt_middle")
	for name in required_names:
		if model.skeleton.find_bone(name)<0: return false
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/models/"+id+"/asset-manifest.json"))
	var contract: Dictionary = manifest.get("runtime_contract",{})
	if id!="haru" and (int(contract.get("bone_count",0))!=expected_count or int(contract.get("skin_bind_count",0))!=expected_count): return false
	var declared_names: Array = contract.get("skin_bind_names",[])
	if not contract.is_empty() and declared_names.size()!=expected_count: return false
	if model.lod_parts.is_empty(): return false
	for part in model.lod_parts.values():
		if part.skin==null or part.skin.get_bind_count()!=expected_count or part.get_node_or_null(part.skeleton)!=model.skeleton: return false
		for index in part.skin.get_bind_count():
			var bind_name: String = part.skin.get_bind_name(index)
			if bind_name not in required_names: return false
			if not declared_names.is_empty() and bind_name!=str(declared_names[index]): return false
	return true

func clear_route(site: String, target: Vector3) -> bool:
	var entry: Vector3 = sim.SITES[site]+Vector3(0,0,2.8)
	var previous := entry
	var points: Array = sim.activities.indoor_route(site,entry,target)
	if points.is_empty(): return false
	for point in points:
		for sample in 11:
			var at: Vector3 = previous.lerp(point,float(sample)/10)
			if not sim.activities.walkable(site,at): return false
		previous = point
	return previous.distance_to(target)<.02

func make_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e9e4db")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .65
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0)
	light.light_energy = .85
	viewport.add_child(light)
	return viewport

func save_viewport(viewport: SubViewport, path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)

func render_variants() -> void:
	var viewport := make_viewport(Vector2i(1800,900))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	viewport.add_child(camera)
	camera.position = Vector3(0,2.2,8)
	camera.look_at(Vector3(0,.95,0))
	var ids := ["fumi","saki","aoi","haru","ryo","tomo","maho","yui"]
	for index in ids.size():
		var id: String = ids[index]
		var avatar := actor(id,viewport)
		avatar.position = Vector3((index-3.5)*1.02,0,0)
		avatar.name_label.text = NAMES.get(id,sim.person(id).get("name",id))
		avatar.name_label.position.y = -.16
		avatar.name_label.font_size = 26
		avatar.name_label.pixel_size = .0035
		avatar.name_label.modulate = Color("33313b")
		avatar.name_label.outline_size = 0
		avatar.name_label.show()
	await save_viewport(viewport,OUT+"/cast-variants-and-source-models.png")
	report.images.append("cast-variants-and-source-models.png")
	viewport.free()
	# Portraits are rendered from these models, rather than copied atlas cells.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/assets/ui/portraits"))
	for id in NEW_IDS:
		viewport = make_viewport(Vector2i(400,470))
		var avatar := actor(id,viewport)
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = .93
		viewport.add_child(camera)
		camera.position = Vector3(.12,1.42,3)
		camera.look_at(Vector3(0,1.32,0))
		avatar.jrpg.set_expression(.12,.3)
		await save_viewport(viewport,"res://game/assets/ui/portraits/"+id+".png")
		viewport.free()
		report.images.append("res://game/assets/ui/portraits/"+id+".png")

func capture_housing(main: Node3D, name: String, target: Vector3, overview: bool = false) -> void:
	if DisplayServer.get_name()=="headless": return
	main.camera.position = target+(Vector3(24,29,34) if overview else Vector3(2.2,3.6,6.8))
	main.camera.look_at(target+Vector3.UP*.7)
	main.get_node("Town").update_view(main.camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")
	report.images.append(name+".png")

func arrive(main: Node3D) -> void:
	var steps := 0
	while NEW_IDS.any(func(id): return sim.person(id).moving) and steps<240:
		sim.advance_minutes(1)
		steps += 1
	expect(not NEW_IDS.any(func(id): return sim.person(id).moving),"The new residents actually reach their assigned furniture")
	for p in sim.people:
		var avatar = main.avatars[p.id]
		avatar.update_state(p,1,false)
		if p.id in NEW_IDS:
			avatar.animator.play("sleep" if p.action=="sleep" else "eat",0)
			avatar.animator.seek(.6,true)
			avatar.animator.advance(0)
			avatar.contacts.update_contact(p,sim.activities.for_person(p),"sleep" if p.action=="sleep" else "eat",Vector3.ZERO,false,1)
		avatar.name_label.hide()
	await process_frame

func housing_fixture() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	var main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.title.hide()
	main.get_node("%HUD").hide()
	sim.reset(71103,12)
	sim.running = false
	expect(sim.people.size()==12 and main.avatars.size()==12,"A twelve-person simulation has twelve actual resident actors")
	for id in ["NorthSharedHouse","MoriHouse"]:
		var house = main.get_node("Town/"+id)
		expect(house.parts.Floor.position.y>0 and house.parts.Floor.position.y<.05,id+": only the visible floor is raised less than five centimetres above terrain")
	await capture_housing(main,"housing-twelve-person-town",Vector3(0,0,-4),true)
	# Isolate furniture execution from authored schedules; this is an explicit fixture.
	for definition in sim.definitions.values(): definition.routines = []
	for p in sim.people:
		p.routine_id = ""
		p.next_plan_minute = 1000000
		p.remaining = 100000
		p.hunger = .2
		p.fatigue = .2
	for id in NEW_IDS:
		var p: Dictionary = sim.person(id)
		sim._assign(p,"sleep",sim.home_for(p),240,"新しい寝床の配置検査")
	await arrive(main)
	var assignments := {}
	for id in NEW_IDS:
		var p: Dictionary = sim.person(id)
		var spot: Dictionary = sim.activities.for_person(p)
		expect(spot.get("resident","")==id and spot.get("pose","")=="bed",id+": actual sleep uses their own real bed")
		expect(not assignments.has(p.activity_spot),id+": the bed is not shared with another simultaneous sleeper")
		assignments[p.activity_spot] = id
	await capture_housing(main,"housing-north-shared-sleep",sim.SITES.home_north_shared)
	await capture_housing(main,"housing-mori-sleep",sim.SITES.home_mori)
	for id in NEW_IDS:
		var p: Dictionary = sim.person(id)
		sim._assign(p,"eat",sim.home_for(p),30,"新しい食卓の配置検査")
	await arrive(main)
	assignments.clear()
	for id in NEW_IDS:
		var p: Dictionary = sim.person(id)
		var spot: Dictionary = sim.activities.for_person(p)
		expect(spot.get("pose","")=="seat" and "eat" in spot.get("actions",[]) and spot.get("site","")==sim.home_for(p),id+": actual eating uses a meal seat in their own household")
		expect(not assignments.has(p.activity_spot),id+": simultaneous meals use distinct real seats")
		assignments[p.activity_spot] = id
	await capture_housing(main,"housing-north-shared-meal",sim.SITES.home_north_shared)
	await capture_housing(main,"housing-mori-meal",sim.SITES.home_mori)
	report.housing_fixture = "12 actual people; routines temporarily cleared only in the test; real assignment, reservations, route and contact used"
	main.free()

func run() -> void:
	sim = root.get_node("Sim")
	sim.running = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var stage := Node3D.new()
	root.add_child(stage)
	for site in ["home_north_shared","home_mori"]:
		var members: Array = ["saki","haru"] if site=="home_north_shared" else ["tomo","yui"]
		var beds := 0
		var meals := 0
		var desks := 0
		expect(sim.activities.rooms.has(site),site+": the actual layout has an interior navigation grid")
		for spot in sim.activities.spots.values():
			if spot.site!=site: continue
			if "sleep" in spot.actions:
				beds += 1
				expect(spot.resident in members,site+": each real bed is assigned to one resident")
			if "eat" in spot.actions: meals += 1
			if "work" in spot.actions: desks += 1
			expect(clear_route(site,spot.approach),site+": "+spot.id+" is reachable from the actual door without crossing furniture")
		expect(beds==2 and meals==2 and desks==2,site+": two beds, two meal seats and two desk places exist")
		report.rooms[site] = {"beds":beds,"meal_seats":meals,"desk_places":desks}
	for id in NEW_IDS:
		var avatar := actor(id,stage)
		expect(avatar.jrpg!=null and not avatar.get_node("Visual/Hips").visible,id+": the resident uses a JRPG rig rather than a placeholder")
		expect(matches_deformation_contract(id,avatar.jrpg),id+": the exact declared deformation rig, required bones and connected skin binds are retained")
		expect(avatar.displayed_model==id,id+": presentation identity remains distinct from its source asset")
		var original_skeleton: int = avatar.jrpg.skeleton.get_instance_id()
		var palette: Texture2D = avatar.jrpg.body_materials[0].get_shader_parameter("base_palette")
		var capabilities: Dictionary = avatar.jrpg.capabilities()
		if avatar.jrpg.uses_palette_swatches():
			var expected: Dictionary = avatar.appearance.palette
			var pixels := palette.get_image()
			var swatch: String = expected.keys()[0]
			var index := int(swatch)
			var pixel := pixels.get_pixel((index%8)*128+64,(7-index/8)*128+64)
			expect(pixel.is_equal_approx(Color(expected[swatch])),id+": its own garment/hair palette is actually installed")
		else:
			expect(palette.get_width()==2048 and palette.get_height()==2048 and str(capabilities.source_model).begins_with("res://game/assets/models/"+id+"/"),id+": the dedicated imported model uses its own full-resolution texture")
			expect(avatar.jrpg.import_contract_errors().is_empty(),id+": the dedicated model has its declared real skeleton, skin and animation capabilities")
		expect(avatar.jrpg.set_lod(1) and avatar.jrpg.set_lod(2),id+": both supplied lower-detail meshes are usable")
		expect(avatar.jrpg.skeleton.get_instance_id()==original_skeleton,id+": LOD retains the same animation rig")
		expect(avatar.jrpg.body_materials[0].get_shader_parameter("base_palette")==palette,id+": changing LOD preserves the resident's appearance")
		var scalar: Array = avatar.appearance.body_scale
		expect(avatar.visual.scale.is_equal_approx(Vector3(scalar[0],scalar[1],scalar[2])),id+": its own authored body proportions are applied")
		report.variants[id] = {"source":capabilities.source_model,"material_mode":capabilities.material_mode,"scale":scalar,"height":avatar.jrpg.rest_height*avatar.visual.scale.y,"bone_count":avatar.jrpg.skeleton.get_bone_count(),"lod_resources":avatar.jrpg.lod_resources_loaded,"provisional":avatar.jrpg.uses_palette_swatches()}
		avatar.free()
	stage.free()
	if DisplayServer.get_name()!="headless":
		await render_variants()
		report.rendered = true
	await housing_fixture()
	report.checks = checks
	report.failures = failures
	var filename := "environment-checks-headless.json" if DisplayServer.get_name()=="headless" else "environment-checks.json"
	var file := FileAccess.open(OUT+"/"+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("Population environment checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

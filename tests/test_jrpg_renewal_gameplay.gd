extends SceneTree

# --discover observes the unchanged simulation only. It is deliberately not an
# asset acceptance: the old resident scenes cannot satisfy the normal run.
const Inspector = preload("res://tools/inspect_population.gd")
const IDS = ["saki","tomo","yui"]
const SEED = 711
const HORIZON = 3*1440
const CLIPS = ["eat","idle","rest","sit_talk","sleep","talk","walk","wave","work"]
const OUT = "res://docs/verification/v0.5/jrpg-renewal-gameplay"
const RAW_SHAS = {
	"saki":"f8b647466b582c4eb38bc318a287e47ced5231208f41ae3e157e3ad18bb7a8bd",
	"tomo":"dfa2f42235365fd8badd3053bef2a1a45f9718591229f1d7e2c35c19526edd65",
	"yui":"4cf28e49cd65fbb7550b25a18dbde831aa8e65406ba2828ab6d953942c29333e"}

var sim
var main
var recorder
var selected := "saki"
var checks := 0
var failures: Array[String] = []
var wall_started := 0
var project_starts := {}
var saved_minute := -1
var saved_resident := ""
var expected_future := {}
var focus_started_us := 0
var report := {"seed":SEED,"population":12,"search_limit_minutes":HORIZON,
	"player_interventions":[],"residents":{},"screenshots":[],
	"artifacts":{"scope":"Image output success is reported separately and is not a functional check.","images":[]},
	"provenance":{"scope":"SHA/hash and pixel-hash identity records do not affect functional check counts, failures or outcome.","source_sha256":{}},
	"scope":"Natural twelve-person town. No action, needs, knowledge, relationship, routine or participant rewrites. Save replay is a separate branch."}

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures.append(message);push_error(message)
	return value

func generation(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/jrpg-resident-renewal/"+id+"/generation.json"))

func model_path(id: String) -> String:
	return "res://game/assets/models/"+id+"/CH_"+id.capitalize()+".glb"

func save_path() -> String:
	return "user://test-jrpg-renewal-gameplay-%d.json"%OS.get_process_id()

func source_fingerprint(discover: bool = false) -> Dictionary:
	var paths: Array = ["res://data/residents.json","res://game/scripts/simulation.gd",
		"res://game/scripts/resident_cognition.gd","res://game/scripts/resident_planner.gd",
		"res://game/scripts/resident_agenda.gd","res://game/scripts/resident_knowledge_exchange.gd",
		"res://game/scripts/work_family.gd","res://game/scripts/social_life.gd",
		"res://game/scripts/life_course.gd","res://game/scripts/resident_support.gd","res://tools/inspect_population.gd",
		"res://tests/test_jrpg_renewal_gameplay.gd"]
	if not discover:
		paths.append_array(["res://game/scenes/main.tscn","res://game/scripts/main.gd",
			"res://game/scripts/resident_avatar.gd","res://game/scripts/jrpg_resident_model.gd",
			"res://game/scripts/resident_contacts.gd","res://data/resident-appearance.json",
			"res://game/assets/models/haru/haru_texture_eyes.gdshader"])
	for id in IDS:
		paths.append("res://assets/models/jrpg-resident-renewal/"+id+"/generation.json")
		if discover: continue
		paths.append("res://"+str(generation(id).output))
		paths.append("res://game/scenes/characters/"+id+".tscn")
		paths.append("res://game/assets/ui/portraits/"+id+".png")
		var folder: String = "res://game/assets/models/"+id
		if DirAccess.dir_exists_absolute(folder):
			for file in DirAccess.get_files_at(folder):
				if file.get_extension() in ["glb","json","gdshader"]: paths.append(folder+"/"+file)
	var hashes := {}
	for path in paths:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	return hashes

func state(id: String) -> Dictionary:
	var p: Dictionary = sim.person(id)
	return sim._encode({"minute":sim.elapsed,"clock":sim.clock_text(),"action":p.action,
		"position":p.position,"moving":p.moving,"place":p.place,"meeting_id":p.meeting_id,
		"activity":sim.activities.for_person(p),"plan":p.cognition_plan,"skills":p.skills,
		"fatigue":p.fatigue,"hunger":p.hunger}).duplicate(true)

func current_actor():
	return main.avatars[selected]

func travel_sample_available(p: Dictionary) -> bool:
	var distance := 0.0
	var previous: Vector3 = p.position
	for point in p.path:
		distance += previous.distance_to(point);previous = point
	# Wait for a naturally long enough journey; never extend or replace its route.
	return p.moving and distance>float(sim.WALK_METERS_PER_MINUTE)*4

func focus(id: String) -> void:
	focus_started_us = Time.get_ticks_usec()
	selected = id;main._select(id)
	main.camera_target = current_actor().focus_position();main.camera_target.y = 0
	main.following = true;main.distance = 7
	# Selecting a camera does not advance the actor's greeting/contact timers.
	main._process(0)
	await render(.12)

func verify_model(id: String) -> bool:
	selected = id
	var actor = current_actor()
	var model = actor.jrpg
	if not expect(model!=null,id+": the actual town actor has an imported model"): return false
	var manifest_path := model_path(id).get_base_dir()+"/asset-manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var metadata := generation(id)
	var raw_path := "res://"+str(metadata.output)
	var raw_albedo := source_albedo(raw_path)
	var imported: Node = model.get_node_or_null("Model")
	var source_valid: bool = imported!=null and imported.scene_file_path==model_path(id)
	var mesh_paths: Array = []
	var bound := false
	for part in meshes(model):
		mesh_paths.append(part.mesh.resource_path)
		source_valid = source_valid and (id+"/CH_"+id.capitalize()) in part.mesh.resource_path
		bound = bound or (part.skin!=null and part.get_node_or_null(part.skeleton)==model.skeleton)
	expect(source_valid and not mesh_paths.is_empty(),id+": the visible model is the new resident GLB, never the previous shared-rig variant")
	expect(not actor.get_node("Visual/Hips").is_visible_in_tree(),id+": the procedural fallback is hidden under the imported model")
	var raw_matches_recorded: bool = FileAccess.get_sha256(raw_path)==RAW_SHAS[id] and metadata.sha256==RAW_SHAS[id] and manifest.get("raw_source_sha256","")==RAW_SHAS[id]
	var export_matches_manifest: bool = FileAccess.get_sha256(model_path(id))==manifest.get("exported_glb_sha256","")
	var runtime: Dictionary = manifest.get("runtime_contract",{})
	var rig_valid: bool = bound and int(runtime.get("bone_count",0))==model.skeleton.get_bone_count()
	for bone in JrpgResidentModel.REQUIRED_BONES:
		rig_valid = rig_valid and model.skeleton.find_bone("DEF-"+bone)>=0 and ("DEF-"+bone) in runtime.get("required_named_bones",[])
	for part in meshes(model):
		rig_valid = rig_valid and part.skin!=null and part.skin.get_bind_count()==int(runtime.get("skin_bind_count",0))
	expect(rig_valid,id+": actual bound skin follows the manifest's rig size and preserves every required contact/animation bone")
	var lod_record := lod_structure(id,model,runtime)
	var lods_valid: bool = lod_record.valid
	expect(lods_valid,id+": all three LODs preserve the manifest's complete skeleton, named skin binds and mesh surfaces")
	report.residents[id].rig = lod_record
	var clips_valid := true
	for clip in CLIPS: clips_valid = clips_valid and model.animator.has_animation(clip) and model.animator.get_animation(clip).length>.5
	expect(clips_valid,id+": all nine existing action clips are available on this actual town actor")
	var capabilities: Dictionary = model.capabilities()
	var contracts_valid: bool = model.import_contract_errors().is_empty()
	expect(contracts_valid,id+": the adapter reports no missing skin, bone, clip or face-layout contracts")
	var controls_valid: bool = capabilities.get("expression_mode","")=="TEXTURE_EYES" and capabilities.get("facial_controls",[])==["Blink","TiredEyes"]
	expect(controls_valid,id+": the face explicitly exposes the implemented two eye controls")
	expect(not model.uses_palette_swatches(),id+": the generated source atlas is not recolored through old palette cells")
	var textures := runtime_texture_records(model)
	var atlas_pixels_match_raw := false
	for texture in textures: atlas_pixels_match_raw = atlas_pixels_match_raw or texture.pixels_sha256==raw_albedo.get("pixels_sha256","")
	report.residents[id].provenance = {"raw_path":raw_path,"raw_sha256":RAW_SHAS[id],"model_path":model_path(id),
		"model_sha256":FileAccess.get_sha256(model_path(id)),"raw_matches_recorded":raw_matches_recorded,"export_matches_manifest":export_matches_manifest,"runtime_atlas_pixels_match_raw":atlas_pixels_match_raw,"runtime_scene":imported.scene_file_path if imported!=null else "",
		"runtime_meshes":mesh_paths,"runtime_textures":textures,"raw_albedo":raw_albedo,"capabilities":capabilities,"manifest":manifest,
		"material_shaders":model.body_materials.map(func(material): return material.shader.resource_path if material is ShaderMaterial and material.shader!=null else "")}
	return source_valid and rig_valid and lods_valid and clips_valid and contracts_valid and controls_valid

func lod_structure(id: String, model: Node, contract: Dictionary) -> Dictionary:
	var valid := true
	var levels: Array = []
	var expected_bones: int = contract.get("bone_count",0)
	var expected_binds: int = contract.get("skin_bind_count",0)
	var expected_names: Array = contract.get("skin_bind_names",[])
	var expected_keys: Array = contract.get("mesh_part_keys",[])
	var surface_counts: Dictionary = contract.get("surface_counts",{})
	valid = expected_bones>0 and expected_binds>0 and expected_names.size()==expected_binds and not expected_keys.is_empty()
	for level in 3:
		var path: String = model_path(id) if level==0 else model_path(id).trim_suffix(".glb")+"_LOD%d.glb"%level
		if not ResourceLoader.exists(path): valid = false;levels.append({"level":level,"missing":true});continue
		var node: Node = load(path).instantiate()
		var skeletons := node.find_children("*","Skeleton3D",true,false)
		var skeleton: Skeleton3D = skeletons[0] if skeletons.size()==1 else null
		var same_skeleton: bool = skeleton!=null and skeleton.get_bone_count()==expected_bones and skeleton.get_bone_count()==model.skeleton.get_bone_count()
		if same_skeleton:
			for index in skeleton.get_bone_count():
				same_skeleton = same_skeleton and skeleton.get_bone_name(index)==model.skeleton.get_bone_name(index) and skeleton.get_bone_parent(index)==model.skeleton.get_bone_parent(index) and skeleton.get_bone_rest(index).is_equal_approx(model.skeleton.get_bone_rest(index))
		var parts := {}
		for part in node.find_children("*","MeshInstance3D",true,false):
			var key: String = model._lod_key(str(part.name))
			var names: Array = []
			var skin_valid: bool = part.skin!=null and part.skin.get_bind_count()==expected_binds and part.get_node_or_null(part.skeleton)==skeleton
			if part.skin!=null:
				for index in part.skin.get_bind_count():
					names.append(str(part.skin.get_bind_name(index)))
					if model.lod_parts.has(key) and model.lod_parts[key].skin!=null and index<model.lod_parts[key].skin.get_bind_count():
						skin_valid = skin_valid and part.skin.get_bind_pose(index).is_equal_approx(model.lod_parts[key].skin.get_bind_pose(index))
					else: skin_valid = false
			var surfaces: int = part.mesh.get_surface_count() if part.mesh!=null else 0
			valid = valid and skin_valid and names==expected_names and surfaces==int(surface_counts.get(key,-1)) and key in expected_keys
			parts[key] = {"bind_count":names.size(),"bind_names":names,"surfaces":surfaces,"skin_connected":skin_valid}
		valid = valid and same_skeleton and parts.size()==expected_keys.size()
		levels.append({"level":level,"bone_count":skeleton.get_bone_count() if skeleton!=null else 0,"same_skeleton_and_rest":same_skeleton,"parts":parts})
		node.free()
	return {"valid":valid,"required_named_bones":contract.get("required_named_bones",[]),"expected_bone_count":expected_bones,"expected_skin_bind_count":expected_binds,"levels":levels}

func world_snapshot() -> Dictionary:
	return sim._encode({"people":sim.people,"events":sim.events,"meetings":sim.meetings,"elapsed":sim.elapsed,
		"remainder":sim.minute_remainder,"rng":str(sim.rng.state),"serial":sim.event_serial,"meeting_serial":sim.meeting_serial,
		"budget":sim.shared_budget,"benches":sim.benches,"social":sim.social.serialize(),"agenda":sim.agenda.serialize(),
		"work":sim.work_family.serialize(),"life":sim.life.serialize()}).duplicate(true)

func observe_candidates() -> void:
	for id in IDS:
		var p: Dictionary = sim.person(id)
		var row: Dictionary = report.residents[id]
		var activity: Dictionary = sim.activities.for_person(p)
		if p.moving and not row.has("walk"): row.walk = state(id)
		if not p.moving:
			if p.action=="eat" and activity.get("pose","")=="seat" and not row.has("eat"): row.eat = state(id)
			if p.action=="sleep" and not row.has("sleep"): row.sleep = state(id)
			elif row.has("sleep") and p.action!="sleep" and not row.has("wake"): row.wake = state(id)
			if activity.get("pose","")=="work" and not row.has("work"): row.work = state(id)
			if activity.get("pose","")=="seat" and p.action!="eat" and not row.has("seat"): row.seat = state(id)
		for meeting in sim.meetings:
			if id not in [meeting.a,meeting.b]: continue
			var key := "project" if meeting.get("mode","")=="project" else "conversation"
			if meeting.state=="engaged" and not row.has(key):
				row[key] = {"state":state(id),"meeting":meeting.duplicate(true)}
		for meeting in recorder.finished.values():
			if meeting.kind=="project" and id in [meeting.a,meeting.b] and not row.has("project_finished"):
				row.project_finished = {"record":meeting.duplicate(true),"state":state(id)}

func write_report(name: String) -> void:
	var file := FileAccess.open(OUT+"/"+name,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()

func discover() -> void:
	report.mode = "natural-candidates-only"
	report.asset_acceptance = false
	report.provenance.source_sha256 = source_fingerprint(true)
	sim = root.get_node("Sim");sim.set_process(false);sim.reset(SEED,12);sim.running = true
	recorder = Inspector.Recorder.new(sim);sim.event_added.connect(recorder.on_event)
	for id in IDS: report.residents[id] = {}
	for minute in HORIZON:
		sim.advance_minutes(1);recorder.observe_minute();observe_candidates()
	report.observed_until = sim.elapsed
	report.meeting_totals = recorder.summary(HORIZON)
	report.wall_seconds = (Time.get_ticks_msec()-wall_started)/1000.0
	report.provenance.sources_unchanged = report.provenance.source_sha256==source_fingerprint(true)
	write_report("natural-candidates.json")
	print("JRPG renewal natural candidates: %d residents, %d minutes, asset acceptance not run"%[IDS.size(),HORIZON])
	for id in IDS:
		var times := {}
		for key in report.residents[id]:
			var row: Dictionary = report.residents[id][key]
			times[key] = row.get("minute",row.get("state",{}).get("minute",-1))
		print(id+": "+JSON.stringify(times))
	quit()

func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()


func image_sha(image: Image) -> String:
	var copy := image.duplicate() as Image
	if copy.is_compressed(): copy.decompress()
	if copy.has_mipmaps(): copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	return sha(copy.get_data())


func source_albedo(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size()<20 or bytes.decode_u32(0)!=0x46546c67: return {}
	var document: Dictionary = {}
	var binary := PackedByteArray()
	var offset := 12
	while offset+8<=bytes.size():
		var length: int = bytes.decode_u32(offset)
		var kind: int = bytes.decode_u32(offset+4)
		var chunk: PackedByteArray = bytes.slice(offset+8,offset+8+length)
		if kind==0x4e4f534a: document = JSON.parse_string(chunk.get_string_from_utf8().strip_edges())
		if kind==0x004e4942: binary = chunk
		offset += length+8
	if document.get("materials",[]).is_empty(): return {}
	var texture_index: int = document.materials[0].get("pbrMetallicRoughness",{}).get("baseColorTexture",{}).get("index",-1)
	if texture_index<0: return {}
	var image_index: int = document.textures[texture_index].source
	var entry: Dictionary = document.images[image_index]
	var view: Dictionary = document.bufferViews[entry.bufferView]
	var image_bytes: PackedByteArray = binary.slice(int(view.get("byteOffset",0)),int(view.get("byteOffset",0))+int(view.byteLength))
	var decoded := Image.new()
	var error: int = decoded.load_png_from_buffer(image_bytes) if entry.get("mimeType","")=="image/png" else decoded.load_jpg_from_buffer(image_bytes)
	if error!=OK: return {}
	return {"embedded_sha256":sha(image_bytes),"pixels_sha256":image_sha(decoded),"width":decoded.get_width(),"height":decoded.get_height()}


func meshes(model: Node) -> Array:
	var result: Array = []
	for node in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null and node.is_visible_in_tree(): result.append(node)
	return result


func runtime_texture_records(model: Node) -> Array:
	var result: Array = []
	for part in meshes(model):
		for surface in part.mesh.get_surface_count():
			var material = part.get_active_material(surface)
			var texture: Texture2D
			if material is StandardMaterial3D: texture = material.albedo_texture
			elif material is ShaderMaterial:
				for key in ["base_palette","albedo_tex","albedo_texture"]:
					var candidate = material.get_shader_parameter(key)
					if candidate is Texture2D: texture = candidate;break
			if texture!=null and texture.get_image()!=null:
				var image := texture.get_image()
				result.append({"mesh":part.mesh.resource_path,"texture":texture.resource_path,
					"pixels_sha256":image_sha(image),"width":image.get_width(),"height":image.get_height()})
	return result


func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<1e-10
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


func animation_manual_mode() -> void:
	for actor in main.avatars.values():
		actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func sync_view() -> void:
	for p in sim.people: main.avatars[p.id].update_state(p,1,p.id==selected)
	main.camera_target = current_actor().focus_position()
	main.camera_target.y = 0
	main._process(.05)


func render(seconds: float = .20) -> void:
	var frames: int = maxi(1,ceili(seconds*60))
	for frame in frames:
		main._process(1.0/60.0)
		for actor in main.avatars.values(): actor.animator.advance(1.0/60.0)
		await process_frame

func wait_for_attention(duration: float) -> void:
	# LookAtModifier3D retains its normal engine-time transition. A manual clip
	# advance is not evidence that this independent transition has completed.
	var previous := Time.get_ticks_usec()
	while (Time.get_ticks_usec()-focus_started_us)/1000000.0<duration:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta: float = (now-previous)/1000000.0
		previous = now
		main._process(delta)
		for actor in main.avatars.values(): actor.animator.advance(delta)
	await process_frame


func capture(name: String) -> void:
	await render(.12)
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	save_image(name+".png",{"file":name+".png","resident":selected,"minute":sim.elapsed,"clock":sim.clock_text(),"action":sim.person(selected).action,"clip":current_actor().animation_name})

func save_image(filename: String, observation: Dictionary) -> void:
	var error: int = root.get_texture().get_image().save_png(OUT+"/"+filename)
	report.artifacts.images.append({"file":filename,"saved":error==OK,"error":error})
	if error==OK: report.screenshots.append(observation)


func capture_face(name: String, sleeping: bool) -> void:
	# Only the observation camera changes; the same natural action and clock remain.
	if DisplayServer.get_name()=="headless": return
	await render(.12)
	var camera: Camera3D = main.camera
	var old_transform := camera.global_transform
	var old_fov := camera.fov
	var old_offset := camera.h_offset
	var head: Vector3 = current_actor().contacts.observed.head
	var forward: Vector3 = current_actor().contacts.observed.head_forward.normalized()
	camera.h_offset = 0
	camera.fov = 35
	camera.global_position = head+(Vector3(0,1.4,1.0) if sleeping else forward*1.35+Vector3.UP*.25)
	camera.look_at(head,Vector3.UP)
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	save_image(name+".png",{"file":name+".png","resident":selected,"minute":sim.elapsed,"clock":sim.clock_text(),"action":sim.person(selected).action,"clip":current_actor().animation_name,"camera":"face closeup only; no world-state change","name_pixel_size":current_actor().name_label.pixel_size,"name_camera_distance":camera.global_position.distance_to(current_actor().name_label.global_position)})
	camera.global_transform = old_transform;camera.fov = old_fov;camera.h_offset = old_offset
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)


func eye_values() -> Array:
	var values: Array = []
	for material in current_actor().jrpg.body_materials:
		values.append({"blink":material.get_shader_parameter("blink"),"tired_eyes":material.get_shader_parameter("tired_eyes")})
	return values


func eye_values_match(sleeping: bool) -> bool:
	var values := eye_values()
	var expected_tired: float = clampf((sim.person(selected).fatigue-.55)/.45,0,.7)
	if values.is_empty(): return false
	for value in values:
		if value.blink==null or value.tired_eyes==null: return false
		if sleeping and not is_equal_approx(float(value.blink),1.0): return false
		if not sleeping and float(value.blink)>=.999: return false
		if absf(float(value.tired_eyes)-expected_tired)>.001: return false
	return true


func selected_labels() -> Array:
	var visible: Array = []
	for id in main.avatars:
		if main.avatars[id].name_label.is_visible_in_tree(): visible.append(id)
	return visible


func actor_snapshot() -> Dictionary:
	var actor = current_actor()
	var p: Dictionary = sim.person(selected)
	return sim._encode({"minute":sim.elapsed,"clock":sim.clock_text(),"position":p.position,"moving":p.moving,
		"action":p.action,"plan":p.cognition_plan,"clip":actor.animation_name,"skills":p.skills,
		"contacts":actor.contacts.observed,"activity":sim.activities.for_person(p),"eyes":eye_values(),"fatigue":p.fatigue,"visible_labels":selected_labels()})


func baked_vertices() -> PackedVector3Array:
	var result := PackedVector3Array()
	if DisplayServer.get_name()=="headless": return result
	await RenderingServer.frame_post_draw
	for part in meshes(current_actor().jrpg):
		if part.skin==null: continue
		var baked: ArrayMesh = part.bake_mesh_from_current_skeleton_pose()
		if baked==null: continue
		for surface in baked.get_surface_count(): result.append_array(baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return result


func check_walk() -> void:
	var actor = current_actor()
	var rig: Skeleton3D = actor.jrpg.skeleton
	var origin: Vector3 = sim.person(selected).position
	var visual_origin: Vector3 = actor.global_position
	var bone := rig.find_bone("DEF-thigh.L")
	var before_rotation := rig.get_bone_pose_rotation(bone)
	var before_foot := rig.get_bone_global_pose(rig.find_bone("DEF-foot.L")).origin
	var before_mesh: PackedVector3Array = await baked_vertices()
	# Advance the same world clock ratio used by LifeSimulation._process, so
	# this sample includes actual locomotion, not a clip played on a fixed root.
	for frame in 24:
		sim.advance_minutes(sim.minutes_per_second/60.0)
		main._process(1.0/60.0)
		for resident in main.avatars.values(): resident.animator.advance(1.0/60.0)
		await process_frame
	var after_mesh: PackedVector3Array = await baked_vertices()
	var rotation_delta: float = before_rotation.angle_to(rig.get_bone_pose_rotation(bone))
	var foot_delta: float = before_foot.distance_to(rig.get_bone_global_pose(rig.find_bone("DEF-foot.L")).origin)
	expect(actor.animation_name=="walk" and rotation_delta>.03 and foot_delta>.005,"Real travel drives the imported leg bones and feet through a walking cycle")
	var mesh_delta := 0.0
	if not before_mesh.is_empty() and before_mesh.size()==after_mesh.size():
		for i in before_mesh.size(): mesh_delta = maxf(mesh_delta,before_mesh[i].distance_to(after_mesh[i]))
	if DisplayServer.get_name()!="headless": expect(mesh_delta>.005,"The new visible mesh itself deforms with the current walking skin pose")
	expect(origin.distance_to(sim.person(selected).position)>.05 and visual_origin.distance_to(actor.global_position)>.05,"The same real journey moves both simulation position and the visible actor root")
	report.residents[selected].natural.walk = {"before_position":[origin.x,origin.y,origin.z],"observed":actor_snapshot(),"leg_rotation_delta":rotation_delta,"foot_delta":foot_delta,"mesh_vertex_delta":mesh_delta,"mesh_deformation_rendered":DisplayServer.get_name()!="headless"}
	await capture(selected+"-01-walking")


func check_conversation(meeting: Dictionary) -> void:
	var actor = current_actor()
	main._select(selected)
	await render(.12)
	var observed: Dictionary = actor.contacts.observed
	var other: String = meeting.b if meeting.a==selected else meeting.a
	var target: Vector3 = main.avatars[other].head_position()
	var direction: Vector3 = (target-observed.head).normalized()
	var head_dot: float = observed.head_forward.dot(direction)
	var greeting_start: float = actor.contacts.greeting
	var attention_sample := {"partner":other,"partner_head":sim._encode(target),"actor_head":sim._encode(observed.head),
		"head_forward":sim._encode(observed.head_forward),"direction_to_partner":sim._encode(direction),
		"simulation_facing":sim.person(selected).get("facing",null),"visual_yaw":actor.visual.rotation.y,
		"activity_yaw":sim.activities.for_person(sim.person(selected)).get("yaw",null),
		"clip":actor.animator.current_animation,"clip_position":actor.animator.current_animation_position,
		"look_duration":actor.contacts.look.duration,"engine_process_delta":actor.get_process_delta_time(),
		"wall_seconds_since_focus":(Time.get_ticks_usec()-focus_started_us)/1000000.0,
		"neck_rest":bone_record(actor.jrpg.skeleton,"DEF-neck"),"head_rest":bone_record(actor.jrpg.skeleton,"DEF-head")}
	expect(actor.animation_name in ["talk","sit_talk"] and actor.contacts.look.active,selected+": an actual engaged conversation selects the conversation pose and head attention")
	var hand_start: Vector3 = observed.handL
	await render(.15)
	var raised: bool = actor.contacts.observed.handL.y>actor.contacts.observed.head.y-.25
	expect(raised and hand_start.distance_to(actor.contacts.observed.handL)>.003,selected+": the real encounter's greeting moves the visible hand near the face")
	expect(selected_labels()==[selected] and actor.name_label.global_position.y-actor.head_position().y>.35,"Only the selected resident's name is shown above the head while nearby faces and hands remain unlabeled")
	var greeting_observed := actor_snapshot()
	var greeting_after: float = actor.contacts.greeting
	var hand_movement: float = hand_start.distance_to(actor.contacts.observed.handL)
	await capture(selected+"-03-conversation-greeting")
	await wait_for_attention(float(actor.contacts.look.duration)+.05)
	var partner_head: Vector3 = main.avatars[other].contacts.observed.head
	var settled_direction: Vector3 = (partner_head-actor.contacts.observed.head).normalized()
	var settled_dot: float = actor.contacts.observed.head_forward.dot(settled_direction)
	var settled_sample := {"wall_seconds_since_focus":(Time.get_ticks_usec()-focus_started_us)/1000000.0,
		"required_wall_seconds":float(actor.contacts.look.duration)+.05,"engine_process_delta":actor.get_process_delta_time(),
		"actor_head":sim._encode(actor.contacts.observed.head),"partner_head":sim._encode(partner_head),
		"look_target":sim._encode(actor.contacts.look_target.global_position),"head_forward":sim._encode(actor.contacts.observed.head_forward),
		"clip_position":actor.animator.current_animation_position,"greeting":actor.contacts.greeting,
		"neck_rest":bone_record(actor.jrpg.skeleton,"DEF-neck"),"head_rest":bone_record(actor.jrpg.skeleton,"DEF-head")}
	expect(settled_dot>.35,selected+": the rendered head turns toward the actual conversation partner after the normal transition")
	report.residents[selected].natural.conversation = {"meeting":meeting.duplicate(true),"observed":actor_snapshot(),"head_dot":head_dot,
		"greeting_before":greeting_start,"greeting_after":greeting_after,"hand_before":sim._encode(hand_start),
		"hand_movement":hand_movement,"raised_near_head":raised,"attention_sample":attention_sample,
		"greeting_observed":greeting_observed,"settled_head_dot":settled_dot,"settled_attention_sample":settled_sample}
	await capture(selected+"-03-conversation")


func check_eat() -> void:
	var actor = current_actor()
	await render(.60)
	var observed: Dictionary = actor.contacts.observed
	var place: Dictionary = sim.activities.for_person(sim.person(selected))
	expect(actor.animation_name=="eat" and place.get("pose","")=="seat" and actor.contacts.mug.visible,"Actual food uses the existing dining seat and a real held cup with the new mesh")
	var desired: float = place.contact.y+.095*actor.jrpg.rest_height/1.65*actor.visual.scale.y
	expect(absf(observed.pelvis.y-desired)<.05 and observed.get("hand_errorR",99)<.06,"The new body's seated hip and drinking wrist reach the existing contact targets")
	report.residents[selected].natural.eat = actor_snapshot()
	await capture(selected+"-05-eating")


func check_sleep() -> void:
	var actor = current_actor()
	await render(.60)
	var observed: Dictionary = actor.contacts.observed
	var place: Dictionary = sim.activities.for_person(sim.person(selected))
	expect(actor.animation_name=="sleep" and place.get("resident","")==selected,selected+": actual sleep uses the resident's assigned bed rather than a standing idle pose")
	expect(absf(observed.head.y-observed.pelvis.y)<.35 and observed.head.distance_to(place.contact)<.30,"The new body actually lies along the bed with its head at the contact point")
	expect(eye_values_match(true),"Actual natural sleep fully closes the new model's eyes and applies its real fatigue value")
	report.residents[selected].natural.sleep = actor_snapshot()
	await capture(selected+"-06-sleeping")
	await capture_face(selected+"-08-sleep-face",true)
	if selected=="yui": await capture_sleep_side()

func bone_record(skeleton: Skeleton3D, name: String) -> Dictionary:
	var index := skeleton.find_bone(name)
	var rest := skeleton.get_bone_rest(index)
	var world_basis := skeleton.global_basis*skeleton.get_bone_global_pose(index).basis
	return {"name":name,"parent":skeleton.get_bone_name(skeleton.get_bone_parent(index)),
		"rest_origin":sim._encode(rest.origin),"rest_basis":sim._encode([rest.basis.x,rest.basis.y,rest.basis.z]),
		"world_basis_at_sample":sim._encode([world_basis.x,world_basis.y,world_basis.z])}

func capture_sleep_side() -> void:
	if DisplayServer.get_name()=="headless": return
	await render(.12)
	var camera: Camera3D = main.camera
	var old_transform := camera.global_transform
	var old_fov := camera.fov
	var old_offset := camera.h_offset
	var head: Vector3 = current_actor().contacts.observed.head
	camera.h_offset = 0;camera.fov = 40
	camera.global_position = head+Vector3(1.55,.42,.12)
	camera.look_at(head+Vector3(0,-.08,0),Vector3.UP)
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	save_image("yui-10-sleep-hair-side.png",{"file":"yui-10-sleep-hair-side.png","resident":selected,"minute":sim.elapsed,
		"clock":sim.clock_text(),"action":sim.person(selected).action,"clip":current_actor().animation_name,
		"camera":"actual sleeping head, hair and pillow from the side; no world-state change"})
	camera.global_transform = old_transform;camera.fov = old_fov;camera.h_offset = old_offset
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)


func check_wake() -> void:
	var reopened := false
	for frame in 30:
		await render(1.0/60.0)
		if eye_values_match(false): reopened = true;break
	expect(current_actor().animation_name!="sleep" and reopened,"After actual waking the sleep override releases and the painted eyes reopen with normal fatigue control")
	report.residents[selected].natural.wake = actor_snapshot()
	await capture_face(selected+"-09-wake-face",false)

func capture_project_front(meeting: Dictionary) -> void:
	if DisplayServer.get_name()=="headless": return
	await render(.12)
	var actor = current_actor()
	var partner = main.avatars[meeting.b if meeting.a==selected else meeting.a]
	var camera: Camera3D = main.camera
	var old_transform := camera.global_transform
	var old_fov := camera.fov
	var old_offset := camera.h_offset
	var center: Vector3 = (actor.contacts.observed.pelvis+partner.contacts.observed.pelvis)*.5
	var forward: Vector3 = actor.visual.global_basis.z
	forward.y = 0;forward = forward.normalized()
	camera.h_offset = 0;camera.fov = 40
	camera.global_position = center+forward*3+Vector3.UP*1.6
	camera.look_at(center+Vector3.UP*.25,Vector3.UP)
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var filename: String = selected+"-02-joint-work-front.png"
	save_image(filename,{"file":filename,"resident":selected,"minute":sim.elapsed,"clock":sim.clock_text(),
		"action":sim.person(selected).action,"clip":actor.animation_name,"meeting":meeting.id,
		"camera":"front of the actual work pair; no world-state change"})
	camera.global_transform = old_transform;camera.fov = old_fov;camera.h_offset = old_offset
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)

func record_project(meeting: Dictionary) -> void:
	var actor = current_actor()
	await render(.60)
	expect(actor.animation_name=="work" and sim.activities.for_person(sim.person(selected)).get("pose","")=="work",selected+": actual joint work uses a real work surface after both residents arrive")
	expect(actor.contacts.observed.get("hand_errorL",99)<.05 and actor.contacts.observed.get("hand_errorR",99)<.05,selected+": both new-model wrists reach the shared work contacts")
	var natural: Dictionary = report.residents[selected].natural
	natural.project_started = project_starts[selected][meeting.id]
	natural.project_engaged = {"observed":actor_snapshot(),"meeting":meeting.duplicate(true)}
	if saved_minute<0:
		expect(sim.save_game(save_path()),"A real ongoing project can be saved without sharing another process's test file")
		saved_minute = sim.elapsed;saved_resident = selected
	await capture_project_front(meeting)

func observe_actual_town() -> void:
	for id in IDS:
		var p: Dictionary = sim.person(id)
		var natural: Dictionary = report.residents[id].natural
		if travel_sample_available(p) and not natural.has("walk"):
			await focus(id);await check_walk()
		for meeting in sim.meetings:
			if id not in [meeting.a,meeting.b]: continue
			if meeting.get("mode","")=="project" and meeting.get("autonomous",false):
				if not project_starts[id].has(meeting.id):
					project_starts[id][meeting.id] = {"state":state(id),"meeting":meeting.duplicate(true)}
				if meeting.state=="engaged" and not natural.has("project_engaged"):
					await focus(id);await record_project(meeting)
			elif meeting.state=="engaged" and not natural.has("conversation"):
				await focus(id);await check_conversation(meeting)
		if natural.has("project_engaged") and not natural.has("project_finished"):
			var project: Dictionary = natural.project_engaged.meeting
			if recorder.finished.has(project.id):
				await focus(id)
				natural.project_finished = {"observed":actor_snapshot(),"completed":recorder.finished[project.id],"terminal_plan":recorder.terminal_snapshots[project.id].plan}
				var skill: String = project.project.skill
				var before: float = natural.project_started.state.skills.get(skill,0)
				var after: float = p.skills.get(skill,0)
				expect(after>before,id+": the same actual project completes and updates the participant's real skill")
				main._refresh_ui();await capture(id+"-04-project-result")
		if not p.moving and p.action=="eat" and not natural.has("eat"):
			await focus(id);await check_eat()
		if not p.moving and p.action=="sleep" and not natural.has("sleep"):
			await focus(id);await check_sleep()
		if natural.has("sleep") and not natural.has("wake") and p.action!="sleep":
			await focus(id);await check_wake()

func coverage_complete() -> bool:
	for id in IDS:
		for key in ["walk","conversation","project_engaged","project_finished","eat","sleep","wake"]:
			if not report.residents[id].natural.has(key): return false
	return not expected_future.is_empty()

func finish() -> void:
	if not report.provenance.source_sha256.is_empty():
		report.provenance.source_after_sha256 = source_fingerprint()
		report.provenance.sources_unchanged = report.provenance.source_sha256==report.provenance.source_after_sha256
	report.checks = checks;report.failures = failures
	report.outcome = "passed" if failures.is_empty() else "failed"
	report.asset_acceptance = failures.is_empty()
	report.wall_seconds = (Time.get_ticks_msec()-wall_started)/1000.0
	report.renderer = DisplayServer.get_name();report.rendered = DisplayServer.get_name()!="headless"
	report.artifacts.images_attempted = report.artifacts.images.size()
	report.artifacts.images_saved = report.artifacts.images.filter(func(record): return record.saved).size()
	report.artifacts.failed = report.artifacts.images.filter(func(record): return not record.saved)
	write_report("gameplay-headless.json" if DisplayServer.get_name()=="headless" else "gameplay.json")
	if FileAccess.file_exists(save_path()): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))
	print("JRPG renewal gameplay checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	print("JRPG renewal gameplay seconds: %.3f"%report.wall_seconds)
	if is_instance_valid(main): main.free()
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	wall_started = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if "--discover" in OS.get_cmdline_user_args(): await discover();return
	report.mode = "actual-town-asset-integration"
	report.provenance.source_sha256 = source_fingerprint()
	var files_ready := true
	for id in IDS:
		var folder: String = model_path(id).get_base_dir()
		files_ready = expect(FileAccess.file_exists(model_path(id)) and FileAccess.file_exists(folder+"/asset-manifest.json"),id+": production rigged GLB and manifest exist before acceptance") and files_ready
	if not files_ready: finish();return
	root.size = Vector2i(1440,900);root.content_scale_size = Vector2i(1440,900)
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	sim = root.get_node("Sim");sim.set_process(false);main.set_process(false)
	sim.reset(SEED,12);main._start_play();sim.running = true
	main.toast_left = 0;main.get_node("%Toast").hide()
	animation_manual_mode()
	var sources_valid := true
	for id in IDS:
		report.residents[id] = {"natural":{}}
		project_starts[id] = {}
		await focus(id)
		sources_valid = verify_model(id) and sources_valid
	if not sources_valid: finish();return
	if DisplayServer.get_name()!="headless":
		for file in DirAccess.get_files_at(OUT):
			if file.ends_with(".png"): DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT+"/"+file))
	recorder = Inspector.Recorder.new(sim);sim.event_added.connect(recorder.on_event)
	while sim.elapsed<HORIZON:
		sim.advance_minutes(1);sync_view();recorder.observe_minute()
		await observe_actual_town()
		if saved_minute>=0 and sim.elapsed==saved_minute+120: expected_future = world_snapshot()
		if coverage_complete(): break
		if sim.elapsed%30==0: await process_frame
	report.observed_until = sim.elapsed
	for id in IDS:
		var missing: Array = []
		for key in ["walk","conversation","project_engaged","project_finished","eat","sleep","wake"]:
			if not report.residents[id].natural.has(key): missing.append(key)
		report.residents[id].missing_conditions = missing
		expect(missing.is_empty(),id+": the finite natural run covers travel, actual talk, completed joint work, seated food, sleep and waking without forcing an outcome")
	report.completion_observer = {"shared_time_signals":recorder.shared_time_signals,"completed_meetings":recorder.finished.size(),"unmatched_shared_time_signals":recorder.unmatched_shared_time_signals}
	sim.event_added.disconnect(recorder.on_event)
	if saved_minute>=0 and not expected_future.is_empty():
		expect(sim.load_game(save_path()),"The real twelve-person ongoing-project save can be restored")
		animation_manual_mode()
		for id in IDS:
			await focus(id)
			expect(verify_model(id),id+": save restoration rebuilds the new resident model and its gameplay rig")
		await focus(saved_resident);await render(.20)
		expect(current_actor().animation_name=="work","The saved actual project restores its gameplay-selected work pose")
		report.save_replay = {"saved_minute":saved_minute,"saved_resident":saved_resident,"restored":actor_snapshot(),"minutes_replayed":120,"test_save_path":save_path()}
		await capture("saved-project-restored")
		sim.advance_minutes(120)
		expect(equivalent(expected_future,world_snapshot()),"Save replay reproduces all people's plans, knowledge, relationships, reservations, world state and RNG after 120 minutes")
	else:
		expect(false,"A real ongoing project and its next 120 minutes were available for save replay")
	finish()

extends SceneTree

# This audit runs the real town and its gameplay-selected animations. Render
# sampling uses a fixed animation delta while the simulation is stepped manually.
const SEED = 711
const HORIZON = 3*1440
const RAW = "res://assets/models/haru-cute-pilot/raw/CH_Haru_JRPG_Pilot_Raw.glb"
const RAW_SHA = "5b0d35cdace93c434abcee76f75c711a5970e52b16474fb9cd0147f66fbeac71"
const MODEL = "res://game/assets/models/haru/CH_Haru.glb"
const LODS = [MODEL,"res://game/assets/models/haru/CH_Haru_LOD1.glb","res://game/assets/models/haru/CH_Haru_LOD2.glb"]
const MANIFEST = "res://game/assets/models/haru/asset-manifest.json"
const PORTRAIT = "res://game/assets/ui/portraits/haru.png"
const OUT = "res://docs/verification/v0.5/haru-jrpg-gameplay"
const SAVE = "user://test-haru-jrpg-gameplay.json"
const CLIPS = ["eat","idle","rest","sit_talk","sleep","talk","walk","wave","work"]

var main
var sim
var checks := 0
var failures: Array[String] = []
var wall_started := 0
var evidence := {"revision":"r3-texture-eyes","seed":SEED,"population":12,"search_limit_minutes":HORIZON,"player_interventions":[],
	"scope":"Real 12-person town, natural seed-711 timeline. Camera/person selection and fixed-step rendering do not replace simulation actions. Save replay is recorded as a separate branch.",
	"render_sampling":"Gameplay chooses the clip. AnimationPlayer.advance samples its running clip with fixed render deltas; simulation time advances only through advance_minutes.",
	"screenshots":[],"natural":{},"capabilities":{},
	"provenance":{"scope":"SHA/hash and pixel-hash comparisons identify the observed files only; excluded from functional check counts, failures and outcome.","source":{}}}

func source_fingerprint() -> Dictionary:
	var result := {}
	for path in [RAW,LODS[0],LODS[1],LODS[2],MANIFEST,PORTRAIT,"res://game/assets/models/haru/animation-contract.json",
		"res://game/assets/models/haru/face-layout.json","res://game/assets/models/haru/haru_texture_eyes.gdshader",
		"res://game/scenes/characters/haru.tscn","res://game/scripts/main.gd",
		"res://game/scripts/resident_avatar.gd","res://game/scripts/jrpg_resident_model.gd","res://game/scripts/resident_contacts.gd",
		"res://game/scripts/simulation.gd","res://data/residents.json","res://tests/test_haru_jrpg_gameplay.gd"]:
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	return result

func _initialize() -> void:
	call_deferred("run")

func save_path() -> String:
	return SAVE.trim_suffix(".json")+"-%d.json"%OS.get_process_id()

func expect(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
	return ok

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

func current_actor():
	return main.avatars.haru

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

func verify_model() -> bool:
	var actor = current_actor()
	var model = actor.jrpg
	if not expect(model!=null,"The real Haru avatar has an imported model"): return false
	var imported: Node = model.get_node_or_null("Model")
	var correct_source: bool = imported!=null and imported.scene_file_path==MODEL
	var paths: Array = []
	var bound := false
	for part in meshes(model):
		paths.append(part.mesh.resource_path)
		correct_source = correct_source and "haru/CH_Haru" in part.mesh.resource_path
		bound = bound or (part.skin!=null and part.get_node_or_null(part.skeleton)==model.skeleton)
	evidence.provenance.source.runtime_scene = imported.scene_file_path if imported!=null else ""
	evidence.provenance.source.runtime_meshes = paths
	expect(correct_source and not paths.is_empty(),"The visible town mesh comes from CH_Haru.glb, not the old Aoi-derived body")
	expect(not actor.get_node("Visual/Hips").is_visible_in_tree(),"The procedural body is hidden instead of being drawn under the new imported mesh")
	var rig_valid: bool = bound and model.skeleton.get_bone_count()==35
	for bone in ["DEF-pelvis","DEF-head","DEF-thigh.L","DEF-foot.L","DEF-hand.L","DEF-hand.R"]:
		rig_valid = rig_valid and model.skeleton.find_bone(bone)>=0
	expect(rig_valid,"The new visible mesh is bound to the required gameplay skeleton")
	var animations := true
	for clip in CLIPS: animations = animations and model.animator.has_animation(clip) and model.animator.get_animation(clip).length>.5
	expect(animations,"All nine existing action clips are available on the actual imported Haru actor")
	var contracts_valid := true
	if model.has_method("import_contract_errors"):
		contracts_valid = model.import_contract_errors().is_empty()
		expect(contracts_valid,"The adapter reports no missing required rig or gameplay clip contracts")
	if model.has_method("capabilities"): evidence.capabilities = model.capabilities()
	expect(evidence.capabilities.get("expression_mode","")=="TEXTURE_EYES" and evidence.capabilities.get("facial_controls",[])==["Blink","TiredEyes"],"The real actor declares the two implemented eye controls without claiming a mouth or blend-shape face")
	if model.has_method("uses_palette_swatches"): expect(not model.uses_palette_swatches(),"The generated atlas is not recolored through the old palette cells")
	var records := runtime_texture_records(model)
	evidence.provenance.source.runtime_textures = records
	var atlas_matches := false
	for texture in records: atlas_matches = atlas_matches or texture.pixels_sha256==evidence.provenance.source.raw_albedo.get("pixels_sha256","")
	evidence.provenance.source.runtime_atlas_pixels_match_raw = atlas_matches
	return correct_source and rig_valid and animations and contracts_valid

func animation_manual_mode() -> void:
	for actor in main.avatars.values():
		actor.animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func sync_view() -> void:
	for p in sim.people: main.avatars[p.id].update_state(p,1,p.id=="haru")
	main.camera_target = current_actor().focus_position()
	main.camera_target.y = 0
	main._process(.05)

func render(seconds: float = .20) -> void:
	var frames: int = maxi(1,ceili(seconds*60))
	for frame in frames:
		main._process(1.0/60.0)
		for actor in main.avatars.values(): actor.animator.advance(1.0/60.0)
		await process_frame

func capture(name: String) -> void:
	await render(.12)
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")
	evidence.screenshots.append({"file":name+".png","minute":sim.elapsed,"clock":sim.clock_text(),"action":sim.person("haru").action,"clip":current_actor().animation_name})

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
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")
	evidence.screenshots.append({"file":name+".png","minute":sim.elapsed,"clock":sim.clock_text(),"action":sim.person("haru").action,"clip":current_actor().animation_name,"camera":"face closeup only; no world-state change","name_pixel_size":current_actor().name_label.pixel_size,"name_camera_distance":camera.global_position.distance_to(current_actor().name_label.global_position)})
	camera.global_transform = old_transform;camera.fov = old_fov;camera.h_offset = old_offset
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)

func eye_values() -> Array:
	var values: Array = []
	for material in current_actor().jrpg.body_materials:
		values.append({"blink":material.get_shader_parameter("blink"),"tired_eyes":material.get_shader_parameter("tired_eyes")})
	return values

func capture_work_front() -> void:
	if DisplayServer.get_name()=="headless": return
	await render(.12)
	var camera: Camera3D = main.camera
	var old_transform := camera.global_transform
	var old_fov := camera.fov
	var old_offset := camera.h_offset
	var actor = current_actor()
	var partner = main.avatars.osamu
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
	root.get_texture().get_image().save_png(OUT+"/10-natural-joint-work-front.png")
	evidence.screenshots.append({"file":"10-natural-joint-work-front.png","minute":sim.elapsed,"clock":sim.clock_text(),"action":sim.person("haru").action,"clip":actor.animation_name,"camera":"front of the actual work pair; no world-state change","name_pixel_size":actor.name_label.pixel_size,"name_camera_distance":camera.global_position.distance_to(actor.name_label.global_position)})
	camera.global_transform = old_transform;camera.fov = old_fov;camera.h_offset = old_offset
	for id in main.avatars: main._update_resident_name_label(main.avatars[id],id)
	main.get_node("Town").update_view(camera.global_position)

func eye_values_match(sleeping: bool) -> bool:
	var values := eye_values()
	var expected_tired: float = clampf((sim.person("haru").fatigue-.55)/.45,0,.7)
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
	var p: Dictionary = sim.person("haru")
	return sim._encode({"minute":sim.elapsed,"clock":sim.clock_text(),"position":p.position,"moving":p.moving,
		"action":p.action,"plan":p.cognition_plan,"clip":actor.animation_name,"skills":p.skills,
		"contacts":actor.contacts.observed,"activity":sim.activities.for_person(p),"eyes":eye_values(),"fatigue":p.fatigue,"visible_labels":selected_labels()})

func world_snapshot() -> Dictionary:
	return sim._encode({"people":sim.people,"events":sim.events,"meetings":sim.meetings,"elapsed":sim.elapsed,
		"rng":str(sim.rng.state),"serial":sim.event_serial,"meeting_serial":sim.meeting_serial,
		"social":sim.social.serialize(),"agenda":sim.agenda.serialize(),"work":sim.work_family.serialize(),"life":sim.life.serialize()}).duplicate(true)

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
	var origin: Vector3 = sim.person("haru").position
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
	expect(origin.distance_to(sim.person("haru").position)>.05 and visual_origin.distance_to(actor.global_position)>.05,"The same real journey moves both simulation position and the visible actor root")
	evidence.natural.walk = {"before_position":[origin.x,origin.y,origin.z],"observed":actor_snapshot(),"leg_rotation_delta":rotation_delta,"foot_delta":foot_delta,"mesh_vertex_delta":mesh_delta,"mesh_deformation_rendered":DisplayServer.get_name()!="headless"}
	await capture("01-natural-walking")

func check_conversation(meeting: Dictionary) -> void:
	var actor = current_actor()
	main._select("haru")
	await render(.12)
	var observed: Dictionary = actor.contacts.observed
	var other: String = meeting.b if meeting.a=="haru" else meeting.a
	var target: Vector3 = main.avatars[other].head_position()
	var direction: Vector3 = (target-observed.head).normalized()
	expect(actor.animation_name in ["talk","sit_talk"] and actor.contacts.look.active,"An actual engaged conversation selects the conversation pose and head attention")
	expect(observed.head_forward.dot(direction)>.35,"The rendered head turns toward the actual conversation partner")
	var hand_start: Vector3 = observed.handL
	await render(.15)
	var raised: bool = actor.contacts.observed.handL.y>actor.contacts.observed.head.y-.25
	expect(raised and hand_start.distance_to(actor.contacts.observed.handL)>.003,"The real encounter's greeting moves the visible hand near the face")
	expect(selected_labels()==["haru"] and actor.name_label.global_position.y-actor.head_position().y>.35,"Only the selected resident's name is shown above the head while nearby faces and hands remain unlabeled")
	evidence.natural.conversation = {"meeting":meeting.duplicate(true),"observed":actor_snapshot(),"head_dot":observed.head_forward.dot(direction)}
	await capture("03-natural-conversation")

func check_eat() -> void:
	var actor = current_actor()
	await render(.60)
	var observed: Dictionary = actor.contacts.observed
	var place: Dictionary = sim.activities.for_person(sim.person("haru"))
	expect(actor.animation_name=="eat" and place.get("pose","")=="seat" and actor.contacts.mug.visible,"Actual food uses the existing dining seat and a real held cup with the new mesh")
	var desired: float = place.contact.y+.095*actor.jrpg.rest_height/1.65*actor.visual.scale.y
	expect(absf(observed.pelvis.y-desired)<.05 and observed.get("hand_errorR",99)<.06,"The new body's seated hip and drinking wrist reach the existing contact targets")
	evidence.natural.eat = actor_snapshot()
	await capture("05-natural-eating")

func check_sleep() -> void:
	var actor = current_actor()
	await render(.60)
	var observed: Dictionary = actor.contacts.observed
	var place: Dictionary = sim.activities.for_person(sim.person("haru"))
	expect(actor.animation_name=="sleep" and place.get("resident","")=="haru","Actual sleep uses Haru's assigned bed rather than a standing idle pose")
	expect(absf(observed.head.y-observed.pelvis.y)<.35 and observed.head.distance_to(place.contact)<.30,"The new body actually lies along the bed with its head at the contact point")
	expect(eye_values_match(true),"Actual natural sleep fully closes the new model's eyes and applies its real fatigue value")
	evidence.natural.sleep = actor_snapshot()
	await capture("06-natural-sleeping")
	await capture_face("08-natural-sleep-face",true)

func check_wake() -> void:
	var reopened := false
	for frame in 30:
		await render(1.0/60.0)
		if eye_values_match(false): reopened = true;break
	expect(current_actor().animation_name!="sleep" and reopened,"After actual waking the sleep override releases and the painted eyes reopen with normal fatigue control")
	evidence.natural.wake = actor_snapshot()
	await capture_face("09-natural-wake-face",false)

func finish() -> void:
	if evidence.provenance.has("source_sha256"):
		evidence.provenance.source_after_sha256 = source_fingerprint()
		evidence.provenance.source_unchanged = evidence.provenance.source_sha256==evidence.provenance.source_after_sha256
	evidence.checks = checks;evidence.failures = failures
	evidence.outcome = "passed" if failures.is_empty() else "failed"
	evidence.wall_seconds = (Time.get_ticks_msec()-wall_started)/1000.0
	evidence.renderer = DisplayServer.get_name()
	evidence.rendered = DisplayServer.get_name()!="headless"
	var name := "gameplay-headless.json" if DisplayServer.get_name()=="headless" else "gameplay.json"
	var file := FileAccess.open(OUT+"/"+name,FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"));file.close()
	if FileAccess.file_exists(save_path()): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))
	print("Haru JRPG gameplay checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	print("Haru JRPG gameplay seconds: %.3f"%evidence.wall_seconds)
	if is_instance_valid(main): main.free()
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	wall_started = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not expect(FileAccess.file_exists(MODEL) and FileAccess.file_exists(MANIFEST),"Production Haru GLB and its source manifest are present before gameplay is accepted"):
		evidence.status = "production asset not available";finish();return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	evidence.provenance.source_sha256 = source_fingerprint()
	if DisplayServer.get_name()!="headless":
		for name in ["01-natural-walking","02-natural-joint-work","03-natural-conversation","04-natural-project-result","05-natural-eating","06-natural-sleeping","07-restored-joint-work","08-natural-sleep-face","09-natural-wake-face","10-natural-joint-work-front"]:
			var path: String = OUT+"/"+name+".png"
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	evidence.provenance.source = {"raw_sha256":FileAccess.get_sha256(RAW),"exported_glb_sha256":FileAccess.get_sha256(MODEL),"manifest":manifest,"raw_albedo":source_albedo(RAW)}
	evidence.provenance.source.raw_matches_recorded = evidence.provenance.source.raw_sha256==RAW_SHA and manifest.get("raw_source_sha256","")==RAW_SHA
	evidence.provenance.source.export_matches_manifest = manifest.get("exported_glb_sha256","")==evidence.provenance.source.exported_glb_sha256
	root.size = Vector2i(1440,900);root.content_scale_size = Vector2i(1440,900)
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	sim = root.get_node("Sim")
	sim.set_process(false);main.set_process(false)
	sim.reset(SEED,12);main._start_play();sim.running = true
	main._select("haru");main._toggle_follow();main.distance = 7
	main.toast_left = 0;main.get_node("%Toast").hide()
	animation_manual_mode();sync_view();await render(.10)
	if not verify_model(): evidence.status = "production model contract failed";finish();return
	var target_meeting := {}
	var project_started := {}
	var project_finished := {}
	var save_minute := -1
	var expected_future := {}
	var elapsed_limit: int = sim.elapsed+HORIZON
	while sim.elapsed<elapsed_limit:
		sim.advance_minutes(1);sync_view()
		var p: Dictionary = sim.person("haru")
		if not evidence.natural.has("walk") and p.moving:
			await check_walk()
		for meeting in sim.meetings:
			if "haru" not in [meeting.a,meeting.b]: continue
			if meeting.get("mode","")!="project" and meeting.state=="engaged" and not evidence.natural.has("conversation"):
				await check_conversation(meeting)
			if meeting.get("mode","")=="project" and meeting.get("autonomous",false) and "osamu" in [meeting.a,meeting.b]:
				if project_started.is_empty(): project_started = actor_snapshot();target_meeting = meeting.duplicate(true)
				if meeting.state=="engaged" and not evidence.natural.has("project_engaged"):
					main._select("haru");await render(.60)
					var actor = current_actor()
					expect(actor.animation_name=="work" and sim.activities.for_person(p).get("pose","")=="work","The natural joint project selects its real work surface and work animation after arrival")
					expect(actor.contacts.observed.get("hand_errorL",99)<.05 and actor.contacts.observed.get("hand_errorR",99)<.05,"Both new-model wrists reach the real shared work targets")
					evidence.natural.project_engaged = actor_snapshot()
					expect(sim.save_game(save_path()),"The actual ongoing new-model activity can be saved to a dedicated test save")
					save_minute = sim.elapsed
					await capture("02-natural-joint-work")
					await capture_work_front()
		if not target_meeting.is_empty() and project_finished.is_empty() and p.cognition_plan.get("meeting","")==target_meeting.id and p.cognition_plan.get("stage","")=="completed":
			project_finished = actor_snapshot()
			evidence.natural.project_started = project_started;evidence.natural.project_finished = project_finished
			expect(float(project_finished.skills.get(target_meeting.project.skill,0))>float(project_started.skills.get(target_meeting.project.skill,0)),"The same natural project finishes and Haru learns from actual participation")
			sim.advance_minutes(1);sync_view()
			evidence.natural.project_result_observed = actor_snapshot()
			main._refresh_ui();await capture("04-natural-project-result")
		if save_minute>=0 and sim.elapsed==save_minute+120: expected_future = world_snapshot()
		if not p.moving and p.action=="eat" and not evidence.natural.has("eat"): await check_eat()
		if not p.moving and p.action=="sleep" and not evidence.natural.has("sleep"): await check_sleep()
		if evidence.natural.has("sleep") and not evidence.natural.has("wake") and p.action!="sleep": await check_wake()
		if not project_finished.is_empty() and not expected_future.is_empty() and evidence.natural.has("conversation") and evidence.natural.has("eat") and evidence.natural.has("sleep") and evidence.natural.has("wake"): break
		if sim.elapsed%30==0: await process_frame
	expect(not project_finished.is_empty() and evidence.natural.has("conversation") and evidence.natural.has("eat") and evidence.natural.has("sleep"),"The declared natural run covers conversation, real joint work, food and sleep without rewriting actions or participants")
	if save_minute>=0 and not expected_future.is_empty():
		expect(sim.load_game(save_path()),"The actual 12-person save reloads with Haru's project in progress")
		animation_manual_mode();main._select("haru");sync_view();await render(.20)
		expect(verify_model() and current_actor().animation_name=="work","Save restoration rebuilds the new Haru mesh and current work pose")
		evidence.save_replay = {"saved_minute":save_minute,"restored":actor_snapshot(),"minutes_replayed":120,"test_save_path":save_path()}
		await capture("07-restored-joint-work")
		sim.advance_minutes(120)
		expect(equivalent(expected_future,world_snapshot()),"Restored play reproduces the same 120-minute future state, plans, knowledge and RNG")
	else:
		expect(false,"A real ongoing project and its following 120 minutes were available for save replay")
	evidence.status = "complete" if failures.is_empty() else "failed"
	finish()

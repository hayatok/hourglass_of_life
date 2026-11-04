extends SceneTree
# Production actor wiring/pose stage. Explicit clip sampling is not natural gameplay.
var resident:="tomo"
var portrait:=false
var output:=""
var checks:=0
var artifact_writes:=0
var artifact_failures:Array[String]=[]
var failures:Array[String]=[]
var evidence:Dictionary={}
var avatar
var model:JrpgResidentModel
var camera:Camera3D
var stage:Node3D
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resident="): resident=argument.trim_prefix("--resident=")
		if argument=="--portrait": portrait=true
	call_deferred("run")
func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)
func point(name:String) -> Vector3:
	return model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.skeleton.find_bone("DEF-"+name))*Vector3.ZERO
func pose(clip:String,phase:float) -> Dictionary:
	model.animator.play(clip,0);model.animator.seek(model.animator.current_animation_length*phase,true);model.animator.advance(0)
	var result:Dictionary={}
	for bone in ["head","hand.L","hand.R","foot.L","foot.R","pelvis"]: result[bone]=point(bone)
	return result
func record(values:Dictionary) -> Dictionary:
	var result:Dictionary={}
	for key in values:
		var value:Vector3=values[key];result[key]=[value.x,value.y,value.z]
	return result
func setup() -> void:
	stage=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e9e4db")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.65;stage.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=.85;stage.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.50;stage.add_child(camera);camera.current=true
func face_camera(yaw:=0.0) -> void:
	var target:Vector3=avatar.contacts.point("head",Vector3(0,.10,0))
	camera.global_position=target+Vector3(sin(yaw)*3,0,cos(yaw)*3);camera.look_at(target)
func capture(name:String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	write_image(output+"/"+name+".png")
func write_image(path:String) -> void:
	# Export success is operational evidence, not an actor-function test count.
	if root.get_texture().get_image().save_png(path)==OK: artifact_writes+=1
	else: artifact_failures.append(path);push_error("Could not save actor review image: "+path)
func run() -> void:
	output="res://assets/models/jrpg-resident-renewal/"+resident+"/review/actor-import";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(800,800);root.content_scale_size=Vector2i(800,800)
	var sim=root.get_node("Sim");sim.reset(711,12);sim.running=false
	var person:Dictionary=sim.person(resident).duplicate(true);person.position=Vector3.ZERO
	setup();avatar=load("res://game/scenes/resident_avatar.tscn").instantiate();stage.add_child(avatar);avatar.configure(person);avatar.name_label.hide()
	model=avatar.jrpg;model.set_process(false);model.animator.speed_scale=0
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://game/assets/models/"+resident+"/asset-manifest.json"))
	var capability:=model.capabilities();evidence={"resident":resident,"scope":"Actual production actor import/explicit pose stage. No simulation minutes or natural resident decisions are sampled.","rendered":DisplayServer.get_name()!="headless","capabilities":capability,"poses":{},"lods":[]}
	expect(capability.source_model=="res://game/assets/models/"+resident+"/CH_"+resident.capitalize()+".glb","Actual avatar references the new resident GLB")
	expect(avatar.visual.scale==Vector3.ONE and is_equal_approx(model.rest_height,float(manifest.target_height_m)),"Scene height and appearance scale match the canonical body")
	expect(model.import_contract_errors().is_empty(),"Head/hand/contact bones, real skin and action clips satisfy the adapter contract")
	expect(capability.facial_controls==["Blink","TiredEyes"] and capability.expression_mode=="TEXTURE_EYES","Only the two implemented UV eye controls are exposed")
	expect(capability.eye_charts==int(manifest.face_controls.eye_charts) and capability.eyelid_method==manifest.face_controls.eyelid_method,"Individual eye chart/method metadata matches the actual layout")
	expect(not model.uses_palette_swatches(),"Old variant swatch/aging policy is disabled for the new atlas")
	var runtime:Dictionary=manifest.runtime_contract
	expect(model.skeleton.get_bone_count()==int(runtime.bone_count),"Actual complete skeleton matches the body's declared bone count")
	var hands:=pose("idle",.25);var points_valid:=true
	for value in hands.values(): points_valid=points_valid and value.is_finite()
	expect(points_valid and hands["hand.L"].distance_to(hands["hand.R"])>.2 and hands.head.y>1.1,"Actual head and separated hands resolve to finite standing rig positions")
	evidence.standing=record(hands)
	for clip in JrpgResidentModel.REQUIRED_CLIPS:
		expect(model.animator.has_animation(clip) and model.animator.get_animation(clip).length>.5,"Actual action clip is available: "+clip)
		var before:=pose(clip,0);var after:=pose(clip,.37);var motion:=0.0
		for bone in before: motion=maxf(motion,before[bone].distance_to(after[bone]))
		if clip in ["walk","talk","work"]: expect(motion>.0001,"The actual "+clip+" clip changes head/hand/foot pose")
		evidence.poses[clip]={"sampled_motion_m":motion,"points":record(after),"length_s":model.animator.get_animation(clip).length}
	var middle:=model.skeleton.find_bone("DEF-skirt_middle")
	if int(runtime.bone_count)>35:
		expect(middle>=0,"The declared skirt-middle bone exists in the actual actor")
		if middle>=0:
			pose("idle",.25);var standing_rotation:=model.skeleton.get_bone_pose_rotation(middle)
			var middle_poses:Dictionary={}
			for clip in ["sit_talk","rest","eat"]:
				pose(clip,.25);var angle:=standing_rotation.angle_to(model.skeleton.get_bone_pose_rotation(middle))
				expect(angle>.1,"The actual "+clip+" rotates the baked skirt-middle bone from standing")
				middle_poses[clip]={"rotation_from_standing_rad":angle}
			var influenced_vertices:=0
			for part in model.lod_parts.values():
				var bind_index:=-1
				for bind in part.skin.get_bind_count():
					if part.skin.get_bind_name(bind)=="DEF-skirt_middle" or part.skin.get_bind_bone(bind)==middle: bind_index=bind
				for surface in part.mesh.get_surface_count():
					var arrays:Array=part.mesh.surface_get_arrays(surface)
					var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
					for index in bones.size():
						if bones[index]==bind_index and weights[index]>.001: influenced_vertices+=1
			expect(influenced_vertices>10,"The animated skirt-middle bone has actual nonzero vertex weights")
			evidence.skirt_middle={"poses":middle_poses,"weighted_vertices":influenced_vertices}
	pose("work",.3);var skeleton:=model.skeleton;var player:=model.animator;var phase:=player.current_animation_position;var held:=pose("work",.3)
	var material:ShaderMaterial=model.body_materials[0];material.set_shader_parameter("blink",.6);material.set_shader_parameter("tired_eyes",.4)
	for level in [0,1,2,0]:
		expect(model.set_lod(level),"Actual distance LOD selects: %d"%level)
		var triangles:=0;var binds:=true
		for part in model.lod_parts.values(): triangles+=part.mesh.get_faces().size()/3;binds=binds and part.skin!=null and part.skin.get_bind_count()==int(runtime.skin_bind_count)
		expect(triangles==int(manifest.lods[level].tris) and binds,"LOD retains its real triangles and complete skin bind set")
		var same:=model.skeleton==skeleton and model.animator==player and is_equal_approx(player.current_animation_position,phase)
		for bone in held: same=same and point(bone).distance_to(held[bone])<.00001
		expect(same and model.body_materials[0]==material,"LOD does not replace the rig/clock, pose or owned eye material")
		expect(is_equal_approx(material.get_shader_parameter("blink"),.6) and is_equal_approx(material.get_shader_parameter("tired_eyes"),.4),"LOD retains nonzero eye values")
		evidence.lods.append({"level":level,"triangles":triangles,"complete_skin":binds})
	pose("sleep",.2);model.elapsed=0;model.set_expression(0,0);model._process(0)
	expect(is_equal_approx(material.get_shader_parameter("blink"),1),"Actual sleep clip forces the eye shader closed")
	pose("idle",.2);model._process(0)
	expect(is_zero_approx(material.get_shader_parameter("blink")),"Returning from sleep restores the ordinary open state")
	model.set_expression(1,0);model._process(0)
	expect(is_equal_approx(material.get_shader_parameter("tired_eyes"),.7),"Actual fatigue reaches the calibrated TiredEyes input")
	if DisplayServer.get_name()!="headless":
		pose("idle",.2);model.elapsed=0;model.set_expression(0,0);model._process(0);face_camera();await capture("face-open")
		model.elapsed=2.81;model._process(0);await capture("face-blink")
		face_camera(-.52);await capture("face-blink-threequarter")
		model.elapsed=0;model.set_expression(1,0);model._process(0);face_camera();await capture("face-tired")
		for clip in ["talk","work","sit_talk"]:
			pose(clip,.3);model.set_expression(0,0);model._process(0);camera.size=2.1;camera.position=Vector3(2,1.3,4);camera.look_at(Vector3(0,.85,0));await capture("pose-"+clip)
		if portrait:
			pose("idle",.167);model.elapsed=0;model.set_expression(.12,.3);model._process(0)
			root.size=Vector2i(400,470);root.content_scale_size=Vector2i(400,470);camera.size=.93;camera.position=Vector3(.12,1.42,3);camera.look_at(Vector3(0,1.32,0))
			await process_frame;await RenderingServer.frame_post_draw
			var path:="res://game/assets/ui/portraits/"+resident+".png"
			write_image(path)
			evidence.portrait=path
	evidence.checks=checks;evidence.failures=failures;evidence.artifacts={"written":artifact_writes,"failures":artifact_failures};evidence.behaviors=["Production actor wiring and canonical scale","Finite head/hands and real clip motion","Complete LOD skin, clock, pose and eye-state retention","Sleep/wake/fatigue shader values"]
	var filename:="checks-headless.json" if DisplayServer.get_name()=="headless" else "checks-gpu.json"
	FileAccess.open(output+"/"+filename,FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t")+"\n")
	print("ACTOR_IMPORT ",resident," ",checks-failures.size(),"/",checks," rendered=",evidence.rendered)
	quit(0 if failures.is_empty() and artifact_failures.is_empty() else 1)

extends SceneTree

var errors: Array[String] = []
var visual_audits: Dictionary = {}
const OUT := "res://docs/verification/v0.5/cast"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func capture(name: String) -> void:
	await process_frame
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")

func pose(character: JrpgResidentModel, clip: String, phase: float) -> void:
	var player := character.animator
	player.speed_scale = 0
	player.stop()
	player.play(clip,0)
	player.seek(player.get_animation(clip).length*phase,true)
	player.advance(0)

func head_fraction(character: JrpgResidentModel) -> float:
	var head := character.skeleton.find_bone("DEF-head")
	return (character.rest_height-character.skeleton.get_bone_global_rest(head).origin.y)/character.rest_height

func audit_aging(before: Image, after: Image, box: Rect2i, resident: String) -> void:
	var hair := 0
	var other := 0
	for y in range(0,before.get_height(),2):
		for x in range(0,before.get_width(),2):
			var a := before.get_pixel(x,y)
			var b := after.get_pixel(x,y)
			var difference := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			if difference>.03:
				if box.has_point(Vector2i(x,y)): hair += 1
				else: other += 1
	visual_audits[resident] = {"hair_changed_samples":hair,"outside_head_changed_samples":other,"sampling_step":2}
	expect(hair>80,resident+": aging visibly changes rendered hair pixels")
	expect(other<40,resident+": aging preserves clothing and skin outside the head")

func run() -> void:
	root.size = Vector2i(1440,900)
	var stage = load("res://game/scenes/character_stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var child_fraction := 0.0
	var adult_fraction := 0.0
	for index in stage.CHARACTERS.size():
		stage.set_character(index)
		await process_frame
		var character: JrpgResidentModel = stage.character
		var resident: String = stage.CHARACTERS[index]
		expect(character.skeleton.get_bone_count()==35,resident+": actual deformation rig imported")
		expect(character.face.mesh.get_blend_shape_count()==6 and character.face.skin!=null,resident+": six skinned face controls")
		expect(character.walk_speed>1 and character.walk_speed<2,resident+": authored stride speed installed")
		var pelvis := character.skeleton.find_bone("DEF-pelvis")
		pose(character,"idle",0)
		await process_frame
		var standing := character.skeleton.get_bone_global_pose(pelvis).origin.y
		for clip in stage.CLIPS:
			expect(character.animator.has_animation(clip),resident+": clip "+clip)
			stage.show_clip(stage.CLIPS.find(clip))
			pose(character,clip,.25)
			await process_frame
			if clip=="sit_talk":
				var seated := character.skeleton.get_bone_global_pose(pelvis).origin.y
				expect(standing-seated>.2,resident+": pelvis actually bends into seated interaction")
			if clip=="wave":
				var hand := character.skeleton.get_bone_global_pose(character.skeleton.find_bone("DEF-hand.L")).origin.y
				var head := character.skeleton.get_bone_global_pose(character.skeleton.find_bone("DEF-head")).origin.y
				expect(hand>head-.18,resident+": greeting lifts the hand")
			if clip in ["idle","walk","work","sit_talk","wave"]:await capture(resident+"-"+clip)
		pose(character,"walk",0)
		await process_frame
		var thigh := character.skeleton.find_bone("DEF-thigh.L")
		var start := character.skeleton.get_bone_pose_rotation(thigh)
		pose(character,"walk",.25)
		await process_frame
		expect(start.angle_to(character.skeleton.get_bone_pose_rotation(thigh))>.2,resident+": imported walking moves leg bones")
		if resident=="rin": child_fraction = head_fraction(character)
		if resident=="rin_adult": adult_fraction = head_fraction(character)
		for lod in [1,2]:
			var model := JrpgResidentModel.new()
			var asset: String = {"nagisa":"Nagisa","ryo":"Ryo","rin":"Rin","rin_adult":"RinAdult", \
				"osamu":"Osamu","fumi":"Fumi","maho":"Maho","ritsu":"Ritsu","aoi":"Aoi"}[resident]
			model.add_child(load("res://game/assets/models/"+resident+"/CH_"+asset+"_LOD%d.glb"%lod).instantiate())
			root.add_child(model)
			await process_frame
			expect(model.skeleton.get_bone_count()==35 and model.face.mesh.get_blend_shape_count()==6,resident+": distant LOD%d retains skin and expression controls"%lod)
			pose(model,"walk",.25)
			model.queue_free()
		character.set_process(false)
		stage.show_clip(0)
		pose(character,"idle",0)
		await capture(resident+"-hair-before")
		var before: Image
		if DisplayServer.get_name()!="headless": before = root.get_texture().get_image()
		character.set_age(72)
		expect(is_equal_approx(character.body_materials[0].get_shader_parameter("hair_age"),.9),resident+": aging reaches the hair material")
		await capture(resident+"-age72")
		if DisplayServer.get_name()!="headless":
			var head := character.skeleton.find_bone("DEF-head")
			var world := character.skeleton.global_transform*character.skeleton.get_bone_global_pose(head).origin+Vector3(0,.13,0)
			var center: Vector2 = stage.get_node("Camera").unproject_position(world)
			var box := Rect2i(Vector2i(center)-Vector2i(90,110),Vector2i(180,220))
			audit_aging(before,root.get_texture().get_image(),box,resident)
	if not visual_audits.is_empty():
		var file := FileAccess.open(OUT+"/aging-pixels.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(visual_audits,"\t"))
	expect(child_fraction>adult_fraction+.04,"Growing up changes head/body proportions, not only overall scale")
	stage.queue_free()
	await process_frame
	var game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.get_node("%StartButton").pressed.emit()
	await process_frame
	var simulation = root.get_node("Sim")
	simulation.running = false
	for resident in ["nagisa","ryo","rin","osamu","fumi","maho","ritsu","aoi"]:
		expect(game.avatars[resident].jrpg!=null and not game.avatars[resident].get_node("Visual/Hips").visible,resident+": actual town uses the imported model")
	var person: Dictionary = simulation.person("rin")
	var avatar = game.avatars.rin
	person.age = 11
	avatar.update_state(person,.1,false)
	var young_height: float = avatar.jrpg.rest_height*avatar.visual.scale.y
	person.age = 12
	avatar.update_state(person,.1,false)
	expect(avatar.displayed_model=="rin_adult","The annual state change swaps to the adolescent/adult body")
	expect(avatar.jrpg.rest_height*avatar.visual.scale.y>young_height,"Growth does not shrink the resident at the body transition")
	person.age = 18
	avatar.update_state(person,.1,false)
	expect(is_equal_approx(avatar.visual.scale.y,1),"Adult stature is reached in the ongoing scene without reloading")
	person.age = 72
	avatar.update_state(person,.1,false)
	expect(is_equal_approx(avatar.jrpg.body_materials[0].get_shader_parameter("hair_age"),.9),"Aging updates in the ongoing town")
	await capture("town-grown-rin")
	print("Resident cast and growth checks: ","PASS" if errors.is_empty() else "FAIL",", errors=",errors)
	quit(0 if errors.is_empty() else 1)

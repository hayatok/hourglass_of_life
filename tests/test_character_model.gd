extends SceneTree

var errors: Array[String] = []
const OUT := "res://docs/verification/v0.5/nagisa"

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

func run() -> void:
	root.size = Vector2i(1440,900)
	var stage = load("res://game/scenes/character_stage.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var character: JrpgResidentModel = stage.character
	var pelvis_height := 0.0
	expect(character.skeleton.get_bone_count()==35,"The GLB contains the complete deformation skeleton")
	expect(character.face.mesh.get_blend_shape_count()==6,"Six face morphs arrived in Godot")
	expect(character.face.skin!=null,"Face geometry is actually bound to the skeleton")
	for index in stage.CLIPS.size():
		stage.show_clip(index)
		var player := character.animator
		var clip: String = stage.CLIPS[index]
		expect(player.has_animation(clip),"Imported animation: "+clip)
		expect(player.get_animation(clip).length>.5,"The clip has an actual time range: "+clip)
		player.speed_scale = 0
		player.stop()
		player.play(clip,0)
		player.seek(player.get_animation(clip).length*.25,true)
		player.advance(0)
		await process_frame
		var height := character.skeleton.get_bone_global_pose(character.skeleton.find_bone("DEF-pelvis")).origin.y
		if index==0: pelvis_height = height
		if index==4: expect(pelvis_height-height>.25,"Seated interaction lowers the actual skeleton to a seat")
		if index==6:
			var hand_height := character.skeleton.get_bone_global_pose(character.skeleton.find_bone("DEF-hand.L")).origin.y
			var head_height := character.skeleton.get_bone_global_pose(character.skeleton.find_bone("DEF-head")).origin.y
			expect(hand_height>head_height-.15,"The greeting actually raises a hand near the head")
		await capture("%02d-%s"%[index,clip])
	var player := character.animator
	player.play("walk")
	player.seek(0,true)
	await process_frame
	var leg := character.skeleton.find_bone("DEF-thigh.L")
	var before := character.skeleton.get_bone_pose_rotation(leg)
	player.seek(.2,true)
	await process_frame
	var after := character.skeleton.get_bone_pose_rotation(leg)
	expect(before.angle_to(after)>.2,"Walking changes an imported skeletal limb, not just the actor root")
	player.play("idle")
	player.stop()
	player.play("idle",0)
	player.seek(0,true)
	character.set_process(false)
	character._blend("Blink",1)
	expect(character.face.get_blend_shape_value(character.face.find_blend_shape_by_name("Blink"))==1,"Blink is an actual mesh morph")
	await capture("09-blink")
	character._blend("Blink",0)
	character.set_process(true)
	for lod in [1,2]:
		var replacement := JrpgResidentModel.new()
		replacement.name = "Model"
		replacement.add_child(load("res://game/assets/models/nagisa/CH_Nagisa_LOD%d.glb"%lod).instantiate())
		stage.remove_child(character)
		character.queue_free()
		stage.add_child(replacement)
		stage.character = replacement
		character = replacement
		stage.show_clip(1)
		replacement.animator.speed_scale = 0
		replacement.animator.stop()
		replacement.animator.play("walk",0)
		replacement.animator.seek(.2,true)
		await process_frame
		expect(replacement.skeleton.get_bone_count()==35 and replacement.face.mesh.get_blend_shape_count()==6,"Reduced model preserves motion and face controls: LOD%d"%lod)
		await capture("10-lod%d"%lod)
	stage.queue_free()
	await process_frame
	var game = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.get_node("%StartButton").pressed.emit()
	await process_frame
	root.get_node("Sim").running = false
	expect(game.avatars.nagisa.jrpg!=null,"The actual town uses the imported character")
	expect(not game.avatars.nagisa.get_node("Visual/Hips").visible,"The old proxy is hidden for the imported character")
	await capture("11-in-town")
	print("Character import and motion checks: ","PASS" if errors.is_empty() else "FAIL",", errors=",errors)
	quit(0 if errors.is_empty() else 1)

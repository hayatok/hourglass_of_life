extends SceneTree

# Unoccupied kit/architecture comparison only. The street is an inspection
# surface, not a connected town simulation or evidence of a lived family day.
var output := "res://builds/north-l-house-review"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	create_timer(100).timeout.connect(func():push_error("Town house review timed out");quit(1))
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Use the agreed single GPU slot for this stage");quit(1);return
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1600,1050)
	var stage := Node3D.new();root.add_child(stage)
	var world := WorldEnvironment.new();var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("b8d0d2")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("e6e0d0");environment.ambient_light_energy=.38
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;world.environment=environment;stage.add_child(world)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-30,0);sun.light_color=Color("fff5e7");sun.light_energy=.65;sun.shadow_enabled=true;stage.add_child(sun)
	var ground := MeshInstance3D.new();var grass := PlaneMesh.new();grass.size=Vector2(80,80)
	ground.mesh=grass;var ground_material := StandardMaterial3D.new();ground_material.albedo_color=Color("8ea77d");ground_material.roughness=1
	ground.material_override=ground_material;stage.add_child(ground)
	var street := MeshInstance3D.new();var pavement := BoxMesh.new();pavement.size=Vector3(55,.15,4.5)
	street.mesh=pavement;street.position=Vector3(0,-.075,14)
	var paving_material := StandardMaterial3D.new();paving_material.albedo_color=Color("b9b4a2");paving_material.roughness=1
	street.material_override=paving_material;stage.add_child(street)
	var houses: Array[LivingHouse]=[]
	for record in [{"path":"res://data/foundation/homes/north-house.json","at":Vector3(-7.7,0,0)},
		{"path":"res://data/foundation/homes/saeki-home.json","at":Vector3(-23,0,1.7)},
		{"path":"res://data/foundation/ogawa-home.json","at":Vector3(12,0,0)}]:
		var house := LivingHouse.new();stage.add_child(house);house.position=record.at
		if not house.load_plan(record.path):push_error("Could not load "+str(record.path));quit(1);return
		HomeArt.new().add_visuals(house);houses.append(house)
	var camera := Camera3D.new();camera.fov=56;camera.near=.1;camera.far=130;stage.add_child(camera);camera.current=true
	var canvas := CanvasLayer.new();root.add_child(canvas)
	var label := Label.new();label.position=Vector2(25,20);label.add_theme_font_size_override("font_size",25)
	label.add_theme_color_override("font_color",Color("473f32"));canvas.add_child(label)
	var report: Dictionary={"scope":"Unoccupied architecture kit review. No town route, motion, household time, life outcome or human play acceptance.",
		"sources":["data/foundation/homes/north-house.json","data/foundation/homes/saeki-home.json","data/foundation/ogawa-home.json"],"artifacts":[]}
	var views := [
		{"id":"north-street-eye","title":"北の住宅 — 街路の目線","at":Vector3(4.5,1.6,17),"target":Vector3(.2,2.,4.3),"all":false,"cut":false},
		{"id":"north-threequarter","title":"北の住宅 — 二翼と低い玄関","at":Vector3(17,10,20),"target":Vector3(0,1.2,4.7),"all":false,"cut":false},
		{"id":"north-cutaway","title":"北の住宅 — 実室と中庭","at":Vector3(15,20,22),"target":Vector3(0,.2,4.7),"all":false,"cut":true},
		{"id":"three-house-street-eye","title":"3棟の建築比較 — 生活シミュレーション未接続","at":Vector3(0,1.6,38),"target":Vector3(0,1.9,5),"all":true,"cut":false}]
	for view in views:
		camera.position=view.at;camera.look_at(view.target);label.text=view.title
		ground.position.y=-.46 if not view.all else -.16
		street.visible=view.all
		for index in houses.size():
			houses[index].visible=index==0 or view.all
			houses[index].cutaway=view.cut;houses[index].update_cutaway(camera.global_position)
		for ignored in 6:await process_frame
		await RenderingServer.frame_post_draw
		var file: String=view.id+".png";var error: Error=root.get_texture().get_image().save_png(output+"/"+file)
		report.artifacts.append({"path":file,"write_result":error,"camera":[camera.position.x,camera.position.y,camera.position.z],"cutaway":view.cut,"ground_y":ground.position.y})
		if error!=OK:push_error("Could not save "+file);quit(1);return
	FileAccess.open(output+"/review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("North L and three-house empty review artifacts saved; no gameplay checks inferred.")
	stage.free();canvas.free();quit(0)

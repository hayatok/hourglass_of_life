extends SceneTree

# Staged, unoccupied design renders. This does not advance daily life, validate
# body contacts, or count saved images as functional checks.
const PLANS := ["res://data/foundation/ogawa-home.json",
	"res://data/foundation/homes/saeki-home.json", "res://data/foundation/homes/shared-house.json",
	"res://data/foundation/homes/north-house.json", "res://data/foundation/homes/mori-home.json"]
var output := "res://builds/g2-home-architecture"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	create_timer(90).timeout.connect(func():push_error("House architecture review timed out");quit(1))
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This staged review needs the GPU rendering slot, not a dummy headless renderer");quit(1);return
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,1050)
	var stage := Node3D.new();root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("b8d0d2")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("e6e0d0");environment.ambient_light_energy=.38
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new();world.environment=environment;stage.add_child(world)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-35,0)
	sun.light_color=Color("fff5e7");sun.light_energy=.65;sun.shadow_enabled=true;stage.add_child(sun)
	var camera := Camera3D.new();camera.fov=43;camera.near=.1;camera.far=100
	stage.add_child(camera);camera.current=true
	var canvas := CanvasLayer.new();root.add_child(canvas)
	var heading := Label.new();heading.position=Vector2(25,18)
	heading.add_theme_font_size_override("font_size",26);heading.add_theme_color_override("font_color",Color("473f32"));canvas.add_child(heading)
	var report: Dictionary={"scope":"Unoccupied architecture design stage. Not real household play, route, body motion or full-day acceptance.","houses":[],"artifacts":[]}
	for path: String in PLANS:
		var house := LivingHouse.new();stage.add_child(house)
		if not house.load_plan(path):push_error("Could not load "+path);quit(1);return
		HomeArt.new().add_visuals(house)
		var bounds: Array=house.definition.house.bounds
		var center := Vector3(float(bounds[0])+float(bounds[2])*.5,0,float(bounds[1])+float(bounds[3])*.5)
		var ground := MeshInstance3D.new();var plane := PlaneMesh.new()
		plane.size=Vector2(float(bounds[2])+10,float(bounds[3])+10);ground.mesh=plane
		ground.position=center+Vector3.DOWN*.16
		var grass := StandardMaterial3D.new();grass.albedo_color=Color("8ea77d");grass.roughness=1
		ground.material_override=grass;stage.add_child(ground)
		var item: Dictionary={"source":path,"house":house.definition.house.id,"label":house.definition.house.label,
			"windows":house.windows.size(),"wall_panes":house.wall_nodes.size(),"views":[]}
		for view: String in ["exterior","cutaway"]:
			var length: float=maxf(float(bounds[2]),float(bounds[3]))
			camera.position=center+Vector3(length*.96,length*.74,length*1.22) if view=="exterior" else center+Vector3(length*.55,length*1.48,length*.72)
			camera.look_at(center+Vector3.UP*(1.25 if view=="exterior" else .12))
			house.cutaway=view=="cutaway";house.update_cutaway(camera.global_position)
			heading.text=str(house.definition.house.label)+(" — 外観" if view=="exterior" else " — 室内の設計")
			for ignored in 5:await process_frame
			await RenderingServer.frame_post_draw
			var filename: String=str(house.definition.house.id)+"-"+view+".png"
			var result: Error=root.get_texture().get_image().save_png(output+"/"+filename)
			item.views.append({"view":view,"image":filename,"roof_visible":house.roof_root.visible,"camera":[camera.position.x,camera.position.y,camera.position.z]})
			report.artifacts.append({"path":filename,"write_result":result})
			if result!=OK:push_error("Could not write architecture review image "+filename);quit(1);return
		report.houses.append(item)
		house.free();ground.free();await process_frame
	FileAccess.open(output+"/review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Five unoccupied house design stages captured. Images are artifacts, not gameplay checks.")
	stage.free();canvas.free();quit(0)

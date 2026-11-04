extends SceneTree
const PILOT := "res://assets/models/haru-cute-pilot"
var output := ""
var camera: Camera3D
var model: Node3D
var material: ShaderMaterial
var label: Label
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("run")
func vec2(values: Array) -> Vector2: return Vector2(values[0],values[1])
func capture(name: String, state: Vector3, angle := 0.0) -> void:
	model.rotation_degrees.y = angle
	material.set_shader_parameter("blink",state.x);material.set_shader_parameter("smile",state.y);material.set_shader_parameter("tired",state.z)
	label.text = name+" / shader-only prototype"
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+name+".png")
func run() -> void:
	root.size = Vector2i(1000,1000)
	var world := Node3D.new();root.add_child(world)
	var env := WorldEnvironment.new();env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR;env.environment.background_color = Color("#353f50")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color = Color.WHITE;env.environment.ambient_light_energy = .35
	world.add_child(env)
	var key := DirectionalLight3D.new();key.rotation_degrees = Vector3(-30,-30,0);key.light_energy = .8;world.add_child(key)
	var fill := DirectionalLight3D.new();fill.rotation_degrees = Vector3(-20,135,0);fill.light_energy = .2;world.add_child(fill)
	camera = Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = .24
	camera.position = Vector3(0,.887,.75);world.add_child(camera);camera.look_at(Vector3(0,.887,0));camera.current = true
	model = load(PILOT+"/raw/CH_Haru_JRPG_Pilot_Raw.glb").instantiate();world.add_child(model)
	material = ShaderMaterial.new();material.shader = load(PILOT+"/build/texture_face.gdshader")
	var landmarks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PILOT+"/production-inputs/texture-face/landmarks.json"))
	for side in ["left","right"]:
		var landmark: Dictionary = landmarks["eye_"+side];var prefix := "eye_l" if side=="left" else "eye_r"
		material.set_shader_parameter(prefix,vec2(landmark.center.uv));material.set_shader_parameter(prefix+"_x",vec2(landmark.axis_x)*1.18);material.set_shader_parameter(prefix+"_y",vec2(landmark.axis_y)*1.35);material.set_shader_parameter(prefix+"_skin",vec2(landmark.skin_uv))
	material.set_shader_parameter("mouth_center",vec2(landmarks.mouth.center.uv));material.set_shader_parameter("mouth_x",vec2(landmarks.mouth.axis_x));material.set_shader_parameter("mouth_y",vec2(landmarks.mouth.axis_y));material.set_shader_parameter("mouth_skin",vec2(landmarks.mouth.skin_uv))
	var counts := []
	for path_name in ["original_mouth","smile_mouth","tired_mouth"]:
		var segments := PackedVector4Array()
		for point in landmarks[path_name]: segments.append(Vector4(point[0],point[1],point[2],point[3]))
		counts.append(segments.size())
		while segments.size()<64: segments.append(Vector4.ZERO)
		material.set_shader_parameter(path_name,segments)
	material.set_shader_parameter("mouth_segment_counts",Vector3i(counts[0],counts[1],counts[2]))
	for part in model.find_children("*","MeshInstance3D",true,false):
		material.set_shader_parameter("base_palette",(part.get_active_material(0) as StandardMaterial3D).albedo_texture)
		part.set_surface_override_material(0,material)
	label = Label.new();label.position = Vector2(0,920);label.size = Vector2(1000,60);label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_size_override("font_size",25);root.add_child(label)
	await capture("open",Vector3.ZERO)
	await capture("blink",Vector3(1,0,0))
	await capture("smile",Vector3(0,1,0))
	await capture("tired",Vector3(0,0,1))
	await capture("blink-threequarter",Vector3(1,0,0),-30)
	var report := {"purpose":"Shader-only expression feasibility prototype; raw untouched; not integrated into actor","source_sha256":FileAccess.get_sha256(PILOT+"/raw/CH_Haru_JRPG_Pilot_Raw.glb"),"states":["open","blink","smile","tired","blink-threequarter"],"face_uv_landmarks":landmarks,"implementation":"UV-space eye paint compression, sampled skin fill and procedural eyelid/mouth curves","limits":["Not facial blend shapes; source atlas unchanged.","Local affine UV approximation and masks require visual quality review.","Mouth is on a separate UV island below the nose seam.","No rig, gaze, sleep, LOD or animation timing test in this prototype."]}
	FileAccess.open(output+"/prototype.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("FACE_SHADER_PROTOTYPE_DONE")
	quit()

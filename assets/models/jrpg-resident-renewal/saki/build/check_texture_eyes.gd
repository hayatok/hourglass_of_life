extends SceneTree
# Static raw-source calibration only: no actor, animation, skin or game state.
var output := ""
var resident := ""
var camera: Camera3D
var model: Node3D
var shader_material: ShaderMaterial
var checks := 0
var failures: Array[String] = []
var pictures: Dictionary = {}
var renders: Array = []
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--resident="): resident=argument.trim_prefix("--resident=")
	call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func uv(value: Array) -> Vector2: return Vector2(value[0],value[1])
func image_hash(image: Image) -> String:
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data());return hash.finish().hex_encode()
func difference(a: Image,b: Image) -> Dictionary:
	var pixels:=0;var bounds:=Rect2i()
	for y in a.get_height():
		for x in a.get_width():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if maxf(maxf(absf(p.r-q.r),absf(p.g-q.g)),absf(p.b-q.b))>.03:
				bounds=Rect2i(x,y,1,1) if pixels==0 else bounds.expand(Vector2i(x,y));pixels+=1
	return {"pixels":pixels,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}
func capture(view: String,yaw: float,state: String,blink: float,tired: float) -> void:
	model.rotation_degrees.y=yaw
	shader_material.set_shader_parameter("blink",blink);shader_material.set_shader_parameter("tired_eyes",tired)
	await process_frame;await RenderingServer.frame_post_draw
	var name:=view+"-"+state
	var image:=root.get_texture().get_image()
	expect(image.save_png(output+"/"+name+".png")==OK,"Saved "+name)
	pictures[name]=image
	renders.append({"file":name+".png","yaw_degrees":yaw,"blink":blink,"tired_eyes":tired,"width":image.get_width(),"height":image.get_height()})
func run() -> void:
	root.size=Vector2i(800,800);root.content_scale_size=Vector2i(800,800)
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("#353f50")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.35;stage.add_child(env)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-30,-30,0);key.light_energy=.8;stage.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,135,0);fill.light_energy=.2;stage.add_child(fill)
	var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://probe/layout.json"))
	var calibration:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://probe/calibration.json"))
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=calibration.camera_size;camera.position=Vector3(0,calibration.camera_y,1);stage.add_child(camera);camera.look_at(Vector3(0,calibration.camera_y,0));camera.current=true
	var packed:=ResourceLoader.load("res://probe/raw.glb","PackedScene") as PackedScene
	expect(packed!=null,"ResourceLoader imports this raw GLB")
	model=packed.instantiate();stage.add_child(model)
	shader_material=ShaderMaterial.new();shader_material.shader=load("res://probe/texture_eyes.gdshader")
	for side in ["left","right"]:
		var eye:Dictionary=layout.eyes[side];var prefix:="eye_l" if side=="left" else "eye_r"
		for pair in [["center",""],["axis_x","_x"],["axis_y","_y"],["skin_uv","_skin"]]: shader_material.set_shader_parameter(prefix+pair[1],uv(eye[pair[0]]))
	var extras:Array=layout.get("additional_eye_patches",[])
	shader_material.set_shader_parameter("extra_eye_count",extras.size())
	shader_material.set_shader_parameter("eyelid_occlusion",layout.get("eyelid_method","compress")=="occlusion")
	for pair in [["center","extra_eye_center"],["axis_x","extra_eye_x"],["axis_y","extra_eye_y"],["skin_uv","extra_eye_skin"]]:
		var values:=PackedVector2Array()
		for chart in extras: values.append(uv(chart[pair[0]]))
		while values.size()<4: values.append(Vector2.ZERO)
		shader_material.set_shader_parameter(pair[1],values)
	var source:Texture2D
	for part in model.find_children("*","MeshInstance3D",true,false):
		for surface in part.mesh.get_surface_count():
			source=(part.get_active_material(surface) as StandardMaterial3D).albedo_texture
			shader_material.set_shader_parameter("base_palette",source);part.set_surface_override_material(surface,shader_material)
	expect(source!=null and source.get_width()==2048 and source.get_height()==2048,"Original 2K atlas is bound")
	var expected_hash:=image_hash(Image.load_from_file(output+"/source-basecolor.jpg"))
	var actual_hash:=image_hash(source.get_image())
	expect(expected_hash==actual_hash,"Decoded runtime atlas pixels match the untouched source JPEG")
	expect(FileAccess.get_sha256("res://probe/raw.glb")==layout.source_raw_sha256,"Staged raw is byte-identical to the source")
	for view in [{"name":"front","yaw":0.0},{"name":"threequarter","yaw":-30.0}]:
		await capture(view.name,view.yaw,"open",0,0)
		await capture(view.name,view.yaw,"closed",1,0)
		# A half blink plus the maximum runtime fatigue value tests both mask/UV paths.
		await capture(view.name,view.yaw,"half",.5,.7)
	var differences:Dictionary={}
	for view in ["front","threequarter"]:
		for state in ["closed","half"]:
			var delta:=difference(pictures[view+"-open"],pictures[view+"-"+state]);differences[view+"-"+state]=delta
			expect(delta.pixels>500,"Expression changes actual rendered eye pixels: "+view+"/"+state)
			expect(delta.bounds[3]<280 and delta.bounds[2]<600,"Changes stay within a local face strip: "+view+"/"+state)
	var result:Dictionary={"resident":resident,"purpose":"Static raw-mesh GPU eye-layout candidate; not a rig or gameplay test","checks":checks,"failures":failures,"passed":failures.is_empty(),"layout":layout,"source_atlas_pixel_sha256":actual_hash,"renders":renders,"differences":differences,"limitations":["Per-character raw UV calibration; production rig/LOD/actor validation remains pending.","Half uses Blink=.5 and TiredEyes=.7 for inspection; it is not a claim that the fatigue driver alone closes eyes halfway.","No mouth/Smile/iris-gaze controls or source image edits."]}
	FileAccess.open(output+"/checks.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("RESIDENT_TEXTURE_EYES ",resident," ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)

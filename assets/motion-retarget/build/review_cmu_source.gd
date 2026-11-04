extends SceneTree

# Standalone original-source joint/axis playback, never the family runtime.
# Generate source-motion.json with cmu_kinematics.py first. No props/skin/floor
# correction are fabricated. CMU joint centres are not measured sole surfaces.
# Default plays four complete clips together at their original 60fps, captures
# five time samples as artifacts, then exits. --interactive keeps the viewer.
const REVIEW_IDS := ["79_10","79_13","79_42","79_25"]
var input_path := "res://builds/cmu-source-review/source-motion.json"
var output_path := "res://builds/cmu-source-review"
var interactive := false
var validate_only := false
var data: Dictionary = {}
var rigs: Dictionary = {}
var stage: Node3D
var camera: Camera3D
var clock_label: Label
var elapsed := 0.0
var duration := 0.0
var playback_paused := false
var capture_busy := false
var next_capture := 0
var artifact_rows: Array = []
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--input="):input_path=value.trim_prefix("--input=")
		elif value.begins_with("--output="):output_path=value.trim_prefix("--output=")
		elif value=="--interactive":interactive=true
		elif value=="--validate-only":validate_only=true
	create_timer(45 if not interactive else 1800).timeout.connect(func():quit(1))
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks+=1
	if not ok:failures.append(text);push_error(text)

func vector(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
func quaternion(value: Array) -> Quaternion:return Quaternion(value[0],value[1],value[2],value[3])

func material(color: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new();result.albedo_color=Color(color);result.roughness=.85
	return result

func rod(parent: Node3D, label: String, radius: float, paint: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new();result.name=label
	var shape := CylinderMesh.new();shape.height=1;shape.top_radius=radius;shape.bottom_radius=radius;shape.radial_segments=8;shape.rings=1
	result.mesh=shape;result.material_override=paint;parent.add_child(result);return result

func ball(parent: Node3D, label: String, radius: float, paint: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new();result.name=label
	var shape := SphereMesh.new();shape.radius=radius;shape.height=radius*2;shape.radial_segments=10;shape.rings=5
	result.mesh=shape;result.material_override=paint;parent.add_child(result);return result

func place_rod(node: Node3D, first: Vector3, last: Vector3) -> void:
	var offset: Vector3=last-first
	node.position=(first+last)*.5
	var rotation := Basis(Quaternion(Vector3.UP,offset.normalized()))
	# Length belongs to the cylinder's local +Y column, not global Y.
	node.basis=Basis(rotation.x,rotation.y*offset.length(),rotation.z)

func _build_rig(id: String, column: int) -> void:
	var clip: Dictionary=data.clips[id]
	var first: Dictionary=clip.frames[0]
	var rig := Node3D.new();rig.name="Source_"+id;stage.add_child(rig)
	# Only one constant XZ display offset per source clip. Root displacement,
	# root orientation, height, bone proportions and timing remain original.
	rig.position=Vector3((column-1.5)*2.25-float(first.root_m[0]),0,-float(first.root_m[2]))
	var center: Material=material("786450");var left: Material=material("6d9b8e");var right: Material=material("b27a57")
	var root_node: MeshInstance3D=ball(rig,"CapturedRoot",.027,center)
	var bones := {};var joints := {};var axes := {}
	for index in data.bone_order.size():
		var name: String=str(data.bone_order[index])
		if name in data.uncaptured_reference_only:continue
		var paint: Material=left if name.begins_with("l") and name!="lowerback" and name!="lowerneck" else right if name.begins_with("r") else center
		bones[name]=rod(rig,"Bone_"+name,.014,paint)
		joints[name]=ball(rig,"Joint_"+name,.022,paint)
		if name in ["lwrist","rwrist","thorax"]:
			axes[name]=[rod(rig,"AxisX_"+name,.004,material("b55d4e")),rod(rig,"AxisY_"+name,.004,material("659869")),rod(rig,"AxisZ_"+name,.004,material("577caa"))]
	var label := Label3D.new();label.text=id+"  "+str(clip.description)
	label.font_size=38;label.pixel_size=.005;label.modulate=Color("4c473a");label.outline_size=0
	label.position=Vector3(float(first.root_m[0]),2.04,float(first.root_m[2]));rig.add_child(label)
	rigs[id]={"node":rig,"bones":bones,"joints":joints,"axes":axes,"root":root_node,"index":0}
	duration=maxf(duration,float(clip.duration_s))

func _apply(id: String, source_frame: int) -> void:
	var clip: Dictionary=data.clips[id];var row: Dictionary=rigs[id]
	var at: int=clampi(source_frame,0,clip.frames.size()-1)
	var frame: Dictionary=clip.frames[at];row.index=at;row.root.position=vector(frame.root_m)
	for index in data.bone_order.size():
		var name: String=str(data.bone_order[index])
		if not row.bones.has(name):continue
		var first: Vector3=vector(frame.starts_m[index]);var last: Vector3=vector(frame.ends_m[index])
		place_rod(row.bones[name],first,last);row.joints[name].position=last
		if row.axes.has(name):
			var axes := Basis(quaternion(frame.world_axis_xyzw[index]))
			var vectors: Array=[axes.x,axes.y,axes.z]
			for axis in 3:place_rod(row.axes[name][axis],last,last+vectors[axis]*.075)

func _check_geometry() -> void:
	for id: String in REVIEW_IDS:
		var clip: Dictionary=data.clips[id];var row: Dictionary=rigs[id]
		var endpoints := true;var axes_match := true
		for index in [0,clip.frames.size()/2,clip.frames.size()-1]:
			_apply(id,int(index));var frame: Dictionary=clip.frames[int(index)]
			for bone in data.bone_order.size():
				var name: String=str(data.bone_order[bone])
				if not row.bones.has(name):continue
				var actual: Node3D=row.bones[name]
				var start: Vector3=vector(frame.starts_m[bone])+row.node.position
				var end: Vector3=vector(frame.ends_m[bone])+row.node.position
				endpoints=endpoints and actual.to_global(Vector3(0,-.5,0)).distance_to(start)<.000002 and actual.to_global(Vector3(0,.5,0)).distance_to(end)<.000002
				if row.axes.has(name):
					var basis := Basis(quaternion(frame.world_axis_xyzw[bone]));var targets: Array=[basis.x,basis.y,basis.z]
					for axis in 3:axes_match=axes_match and row.axes[name][axis].to_global(Vector3(0,.5,0)).distance_to(end+targets[axis]*.075)<.000002
		expect(endpoints,id+": native rod endpoints preserve original source joint positions/lengths/root displacement at beginning, middle and end")
		expect(axes_match,id+": native wrist and thorax axes follow the exported world calibration quaternion, including roll")
		expect(row.bones.size()==data.bone_order.size()-data.uncaptured_reference_only.size() and not row.bones.has("rfingers") and not row.bones.has("lthumb"),id+": uncaptured fingers are absent from the displayed source-motion evidence")
		_apply(id,0)

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	var decoded: Variant=JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if not decoded is Dictionary or decoded.get("schema")!=1 or decoded.get("bone_order",[]).size()!=30:
		push_error("Generate the validated subject79 source-motion.json first");quit(1);return
	data=decoded
	for id: String in REVIEW_IDS:
		if not data.get("clips",{}).has(id):push_error("Source clip missing: "+id);quit(1);return
	if DisplayServer.get_name()=="headless" and not validate_only:
		push_error("Use --validate-only headless or the agreed single GPU slot for playback");quit(1);return
	root.size=Vector2i(1600,950);stage=Node3D.new();root.add_child(stage)
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("c6d1cb")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("fff0d9");environment.environment.ambient_light_energy=.55;stage.add_child(environment)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.light_energy=.55;sun.shadow_enabled=true;stage.add_child(sun)
	var floor := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(12,6);floor.mesh=plane
	floor.material_override=material("c4bc9f");stage.add_child(floor)
	for column in REVIEW_IDS.size():_build_rig(REVIEW_IDS[column],column)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5.4;camera.position=Vector3(4.2,3.5,10);camera.look_at(Vector3(0,.95,.05))
	var canvas := CanvasLayer.new();root.add_child(canvas)
	var heading := Label.new();heading.text="CMU original source • whole-body joints / wrist axes • no captured fingers or prop contact";heading.position=Vector2(25,18);heading.add_theme_font_size_override("font_size",23);heading.add_theme_color_override("font_color",Color("4a453a"));canvas.add_child(heading)
	clock_label=Label.new();clock_label.position=Vector2(25,54);clock_label.add_theme_font_size_override("font_size",20);clock_label.add_theme_color_override("font_color",Color("4a453a"));canvas.add_child(clock_label)
	_check_geometry()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	FileAccess.open(output_path+"/native-geometry.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Native source joint/axis rendering composition only; not family retarget or skin/prop contact.","checks":checks,"failures":failures},"\t"))
	print("CMU source playback geometry: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	if not failures.is_empty():quit(1);return
	if validate_only:stage.free();canvas.free();quit(0);return
	root.window_input.connect(_input)
	capture_busy=true;next_capture=1;_capture_sample(0)

func _process(delta: float) -> bool:
	if not is_instance_valid(stage) or data.is_empty():return false
	if not playback_paused and not capture_busy:elapsed=minf(duration,elapsed+delta)
	for id: String in REVIEW_IDS:_apply(id,floori(elapsed*float(data.clips[id].fps)))
	clock_label.text="%.2f s  /  %.2f s   |   original 60 fps samples; short clips hold their final sample"%[elapsed,duration]
	if not capture_busy and next_capture<5 and elapsed>=duration*next_capture/4:
		capture_busy=true;_capture_sample(next_capture);next_capture+=1
	if elapsed>=duration and next_capture>=5 and not capture_busy and not interactive:
		_write_report();stage.free();quit(0)
	return false

func _capture_sample(index: int) -> void:
	await RenderingServer.frame_post_draw
	var file: String="source-%02d.png"%index
	var result: Error=root.get_texture().get_image().save_png(output_path+"/"+file)
	var indices := {}
	for id: String in REVIEW_IDS:indices[id]=int(rigs[id].index)+1
	artifact_rows.append({"path":file,"write_result":result,"source_frames":indices,"time_s":elapsed})
	capture_busy=false
	if interactive:_write_report()

func _write_report() -> void:
	FileAccess.open(output_path+"/review.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Original-source unskinned whole-body playback at recorded timing. No props, inferred grasp, soles, target rig, household action or human gameplay acceptance.","clips":REVIEW_IDS,"source_fps":60,"duration_s":duration,"constant_display_offset":"First source root XZ removed once per clip, plus column spacing; no per-frame root/height locking.","uncaptured_fingers_displayed":false,"floor_note":"y0 is a reference plane; recorded joint centres are not measured sole contacts.","artifacts":artifact_rows,"artifact_writes_are_not_functional_checks":true},"\t"))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_SPACE:playback_paused=not playback_paused
		elif event.keycode==KEY_HOME:elapsed=0
		elif event.keycode==KEY_RIGHT:playback_paused=true;elapsed=minf(duration,elapsed+1.0/60)
		elif event.keycode==KEY_LEFT:playback_paused=true;elapsed=maxf(0,elapsed-1.0/60)
		elif event.keycode==KEY_ESCAPE:_write_report();quit(0)

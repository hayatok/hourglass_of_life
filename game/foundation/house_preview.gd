extends Node3D

# Design review scene for the new spatial foundation. Household behaviours and
# replacement locomotion are integrated before this becomes a playable build.
var house: LivingHouse
var camera: Camera3D
var target := Vector3(6,0,5)
var yaw := .45
var pitch := .88
var distance := 19.0
var dragging := false
var wall_button: Button

func _ready() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("b8d0d2")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("e6e0d0");environment.ambient_light_energy=.28
	environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	world.environment=environment;add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-35,0);sun.light_color=Color("fff5e7");sun.light_energy=.65;sun.shadow_enabled=true;add_child(sun)
	house=LivingHouse.new();house.name="OgawaHome";add_child(house)
	if not house.load_plan("res://data/foundation/ogawa-home.json"):
		push_error("The authored Ogawa home plan could not be loaded");return
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(42,36)
	ground.mesh=plane;ground.position=Vector3(6,-.15,5)
	var grass:=StandardMaterial3D.new();grass.albedo_color=Color("8ea77d");grass.roughness=1;ground.material_override=grass;add_child(ground)
	camera=Camera3D.new();camera.fov=43;camera.near=.1;camera.far=100;add_child(camera);camera.current=true
	_build_ui();_update_camera()

func _build_ui() -> void:
	var canvas:=CanvasLayer.new();add_child(canvas)
	var top:=HBoxContainer.new();top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);top.offset_left=20;top.offset_right=-20;top.offset_top=18;top.offset_bottom=70;top.add_theme_constant_override("separation",12);canvas.add_child(top)
	var title:=Label.new();title.text="小川家";title.add_theme_font_size_override("font_size",30);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(title)
	var overview:=Button.new();overview.text="家を見渡す";overview.custom_minimum_size=Vector2(150,48);overview.pressed.connect(_show_overview);top.add_child(overview)
	wall_button=Button.new();wall_button.text="壁をすべて表示";wall_button.custom_minimum_size=Vector2(170,48);wall_button.pressed.connect(_toggle_walls);top.add_child(wall_button)
	var zoom:=HBoxContainer.new();zoom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);zoom.offset_left=-180;zoom.offset_right=-20;zoom.offset_top=-70;zoom.offset_bottom=-20;zoom.add_theme_constant_override("separation",10);canvas.add_child(zoom)
	for setting in [["−",1.15],["＋",1.0/1.15]]:
		var button:=Button.new();button.text=setting[0];button.custom_minimum_size=Vector2(70,48)
		button.pressed.connect(_zoom.bind(float(setting[1])));zoom.add_child(button)

func _zoom(factor: float) -> void:
	distance=clampf(distance*factor,8,30)

func _show_overview() -> void:
	target=Vector3(6,0,5);distance=19;yaw=.45;pitch=.88

func _toggle_walls() -> void:
	house.cutaway=not house.cutaway
	wall_button.text="壁をすべて表示" if house.cutaway else "手前の壁を隠す"

func _process(_delta: float) -> void:
	if is_instance_valid(camera): _update_camera()

func _update_camera() -> void:
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target)
	house.update_cutaway(camera.position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=clampf(distance/1.12,8,30)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=clampf(distance*1.12,8,30)
	elif event is InputEventMouseMotion and dragging:
		yaw-=event.relative.x*.008;pitch=clampf(pitch+event.relative.y*.005,.4,1.5)
	elif event is InputEventMagnifyGesture:distance=clampf(distance/maxf(.1,event.factor),8,30)
	elif event is InputEventPanGesture:
		target+=Basis(Vector3.UP,yaw)*Vector3(event.delta.x*.03,0,event.delta.y*.03)

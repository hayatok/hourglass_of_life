extends SceneTree

# v0.1 one-time authoring tool. Never runs in game. Later scene edits are in .tscn;
# running this archival tool overwrites them and is not an upgrade procedure.
var cream = Color("e9e2ce")
var wood = Color("886346")
var teal = Color("375f65")
var font: SystemFont

func _initialize() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans", "Yu Gothic", "Noto Sans CJK JP"])
	_make_bench()
	_make_avatar()
	_make_town()
	_make_main()
	print("Authored four editable scenes")
	quit()

func node(parent: Node, type: String, title: String) -> Node:
	var n = ClassDB.instantiate(type)
	n.name = title
	parent.add_child(n)
	return n

func material(color: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .85
	return m

func mesh(parent: Node3D, title: String, shape: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var m = node(parent,"MeshInstance3D",title)
	m.mesh = shape
	m.position = pos
	m.material_override = material(color)
	return m

func box(parent: Node3D, title: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var shape = BoxMesh.new()
	shape.size = size
	return mesh(parent,title,shape,pos,color)

func sphere(parent: Node3D, title: String, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var shape = SphereMesh.new()
	shape.radius = radius
	shape.height = height
	shape.radial_segments = 16
	shape.rings = 8
	return mesh(parent,title,shape,pos,color)

func cylinder(parent: Node3D, title: String, top: float, bottom: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var shape = CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = 12
	return mesh(parent,title,shape,pos,color)

func save_scene(root_node: Node, filename: String) -> void:
	_owners(root_node,root_node)
	var packed = PackedScene.new()
	assert(packed.pack(root_node)==OK)
	assert(ResourceSaver.save(packed,"res://game/scenes/"+filename+".tscn")==OK)
	root_node.free()

func _owners(current: Node, root_node: Node) -> void:
	for child in current.get_children():
		child.owner = root_node
		if child.scene_file_path.is_empty():
			_owners(child,root_node)

func label3(parent: Node3D, title: String, text: String, pos: Vector3, size: int = 32) -> Label3D:
	var label = node(parent,"Label3D",title)
	label.text = text
	label.position = pos
	label.font = font
	label.font_size = size
	label.pixel_size = .012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.modulate = Color("fff4d8")
	return label

func _make_bench() -> void:
	var root_node = Node3D.new()
	root_node.name = "Bench"
	for x in [-.75,.75]:
		box(root_node,"Leg",Vector3(.12,.5,.55),Vector3(x,.25,0),teal)
	box(root_node,"Seat",Vector3(2,.12,.65),Vector3(0,.55,0),wood)
	box(root_node,"Back",Vector3(2,.42,.1),Vector3(0,.94,-.3),wood)
	save_scene(root_node,"bench")

func _make_avatar() -> void:
	var root_node = Node3D.new()
	root_node.name = "Resident"
	root_node.set_script(load("res://game/scripts/resident_avatar.gd"))
	var visual = node(root_node,"Node3D","Visual")
	var hips = node(visual,"Node3D","Hips")
	hips.position.y = .94
	cylinder(hips,"Torso",.20,.16,.52,Vector3(0,.28,0),teal)
	box(hips,"Pelvis",Vector3(.34,.18,.24),Vector3.ZERO,teal)
	box(hips,"Apron",Vector3(.31,.56,.035),Vector3(0,.03,.16),wood)
	var skin = Color("e9c3a1")
	var head = node(hips,"Node3D","Head")
	head.position.y = .73
	sphere(head,"Face",.146,.29,Vector3.ZERO,skin)
	sphere(head,"Hair",.157,.21,Vector3(0,.087,-.025),Color("3b302d"))
	for x in [-.058,.058]:
		sphere(head,"EyeWhite",.034,.05,Vector3(x,.017,.132),Color("fff8e5"))
		sphere(head,"Eye",.019,.033,Vector3(x,.014,.157),Color("303a42"))
	for side in [-1,1]:
		var title = "Left" if side<0 else "Right"
		var leg = node(hips,"Node3D",title+"Leg")
		leg.position = Vector3(side*.115,-.02,0)
		cylinder(leg,"Thigh",.09,.075,.42,Vector3(0,-.21,0),teal)
		var knee = node(leg,"Node3D","Knee")
		knee.position.y = -.42
		cylinder(knee,"Shin",.072,.055,.41,Vector3(0,-.205,0),teal)
		box(knee,"Shoe",Vector3(.15,.12,.28),Vector3(0,-.43,.06),Color("494039"))
		var arm = node(hips,"Node3D",title+"Arm")
		arm.position = Vector3(side*.25,.48,0)
		cylinder(arm,"Sleeve",.085,.075,.27,Vector3(0,-.13,0),teal)
		cylinder(arm,"Forearm",.06,.045,.25,Vector3(0,-.36,0),skin)
		sphere(arm,"Hand",.055,.13,Vector3(0,-.5,0),skin)
	var ring = TorusMesh.new()
	ring.inner_radius = .29
	ring.outer_radius = .34
	ring.rings = 24
	var selection = mesh(root_node,"Selection",ring,Vector3(0,.04,0),Color("f3ca65"))
	selection.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	label3(root_node,"Name","住人",Vector3(0,2.1,0),22)
	var player = node(root_node,"AnimationPlayer","AnimationPlayer")
	var library = AnimationLibrary.new()
	for action in ["idle","walk","talk","work","sit_talk","sleep","wave"]:
		var clip = Animation.new()
		clip.length = .8 if action=="walk" else 2.4
		clip.loop_mode = Animation.LOOP_LINEAR
		var base_y = .56 if action=="sit_talk" else .94
		var hip_rotation = Vector3(0,0,PI/2) if action=="sleep" else Vector3.ZERO
		if action=="sleep": base_y = .25
		anim_track(clip,"Visual/Hips:position",[Vector3(0,base_y,0),Vector3(0,base_y+.012,0),Vector3(0,base_y,0)])
		anim_track(clip,"Visual/Hips:rotation",[hip_rotation,hip_rotation,hip_rotation])
		for side in [-1,1]:
			var title = "Left" if side<0 else "Right"
			var leg = Vector3(-1.42,0,0) if action=="sit_talk" else Vector3.ZERO
			var knee = Vector3(1.42,0,0) if action=="sit_talk" else Vector3.ZERO
			var arm = Vector3(-.6,0,side*-.08) if action in ["work","sit_talk"] else Vector3(0,0,side*-.08)
			if action=="wave" and side==1: arm = Vector3(-.2,0,-2.2)
			anim_track(clip,"Visual/Hips/"+title+"Leg:rotation",[Vector3(side*.48,0,0),Vector3(-side*.48,0,0),Vector3(side*.48,0,0)] if action=="walk" else [leg,leg,leg])
			anim_track(clip,"Visual/Hips/"+title+"Leg/Knee:rotation",[Vector3(.15,0,0),Vector3(.45,0,0),Vector3(.15,0,0)] if action=="walk" else [knee,knee,knee])
			anim_track(clip,"Visual/Hips/"+title+"Arm:rotation",[Vector3(-side*.35,0,0),Vector3(side*.35,0,0),Vector3(-side*.35,0,0)] if action=="walk" else [arm,arm+Vector3(-.12,0,.05) if action in ["talk","work","sit_talk","wave"] else arm,arm])
		anim_track(clip,"Visual/Hips/Head:rotation",[Vector3.ZERO,Vector3(.03,.08,0) if action in ["talk","work","sit_talk"] else Vector3.ZERO,Vector3.ZERO])
		library.add_animation(action,clip)
	player.add_animation_library("",library)
	save_scene(root_node,"resident_avatar")

func anim_track(clip: Animation, path: String, values: Array) -> void:
	var track = clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track,NodePath(path))
	for i in values.size():
		clip.track_insert_key(track,clip.length*i/float(values.size()-1),values[i])

func _house(parent: Node3D, title: String, pos: Vector3, roof: Color, sign_text: String) -> void:
	var house = node(parent,"Node3D",title)
	house.position = pos
	box(house,"Floor",Vector3(5.8,.14,5.8),Vector3(0,.01,0),Color("b7a17e"))
	box(house,"RearWall",Vector3(5.8,2.4,.15),Vector3(0,1.2,-2.8),cream)
	for x in [-2.8,2.8]:
		box(house,"SideWall",Vector3(.15,1.15,5.8),Vector3(x,.57,0),cream)
		box(house,"Pillar",Vector3(.15,2.5,.15),Vector3(x,1.25,-2.7),wood)
		box(house,"Window",Vector3(1.0,.9,.06),Vector3(x*.55,1.35,-2.7),Color("8ebac0"))
	box(house,"RoofStrip",Vector3(6.1,.25,1.2),Vector3(0,2.55,-2.7),roof)
	box(house,"Table",Vector3(1.7,.15,.8),Vector3(1,.8,-.5),wood)
	for x in [.4,1.6]:
		box(house,"TableLeg",Vector3(.1,.8,.6),Vector3(x,.4,-.5),wood)
	box(house,"Bed",Vector3(1.2,.35,1.9),Vector3(-1.8,.25,-1.2),Color("8eaa9c"))
	box(house,"Pillow",Vector3(.9,.16,.42),Vector3(-1.8,.5,-1.8),cream)
	label3(house,"Sign",sign_text,Vector3(0,2.85,-2.8),26)

func _make_town() -> void:
	var root_node = Node3D.new()
	root_node.name = "Town"
	box(root_node,"Ground",Vector3(42,.3,36),Vector3(0,-.2,0),Color("83a46b"))
	box(root_node,"Square",Vector3(11,.04,10),Vector3(0,-.02,3),Color("c9bc93"))
	for z in [-4,1,7]:
		box(root_node,"Street",Vector3(31,.05,1.45),Vector3(0,0,z),Color("d8cdb3"))
	for x in [-5,0,5]:
		box(root_node,"CrossStreet",Vector3(1.4,.055,12),Vector3(x,.005,1.5),Color("d8cdb3"))
	_house(root_node,"OgawaHouse",Vector3(-9,0,6),Color("a77155"),"小川家")
	_house(root_node,"SaekiHouse",Vector3(-9,0,-4),Color("657e83"),"佐伯家")
	_house(root_node,"SharedHouse",Vector3(9,0,6),Color("7b8a63"),"共同住宅")
	_house(root_node,"BakeryCafe",Vector3(8,0,-5),Color("b26e52"),"パンと喫茶  こむぎ")
	_house(root_node,"Workshop",Vector3(0,0,-7),Color("587c7d"),"佐伯修理工房")
	for x in [6.3,8.5,10.5]:
		box(root_node,"CafeCounter",Vector3(1.7,.9,.7),Vector3(x,.45,-6.8),wood)
		for z in [-.15,.15]:
			sphere(root_node,"Bread",.16,.16,Vector3(x+z,.97,-6.8),Color("d8aa64"))
	box(root_node,"WorkshopTable",Vector3(2.8,.16,1.2),Vector3(0,.82,-7.8),wood)
	box(root_node,"Radio",Vector3(.5,.35,.24),Vector3(.4,1.07,-7.8),Color("5d736e"))
	for pos in [Vector3(-15,0,-11),Vector3(14,0,-11),Vector3(-15,0,10),Vector3(15,0,11),Vector3(-3,0,3)]:
		cylinder(root_node,"TreeTrunk",.12,.2,1.8,pos+Vector3(0,.9,0),wood)
		sphere(root_node,"TreeCrown",1.3,2.4,pos+Vector3(0,2.5,0),Color("5f8a58"))
	label3(root_node,"ExitSign","学校・仕事場へ →",Vector3(14,1.5,6),24)
	var light = node(root_node,"DirectionalLight3D","Sun")
	light.rotation_degrees = Vector3(-52,-30,0)
	light.light_color = Color("fff1ce")
	light.light_energy = .75
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 70
	var world = node(root_node,"WorldEnvironment","WorldEnvironment")
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("9abccd")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c8da")
	environment.ambient_light_energy = .3
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	save_scene(root_node,"town")

func style(color: Color, border: Color = Color("a78e65")) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func unique(n: Node) -> Node:
	n.unique_name_in_owner = true
	return n

func layout(control: Control, anchors: Vector4, offsets: Vector4) -> void:
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = offsets.x
	control.offset_top = offsets.y
	control.offset_right = offsets.z
	control.offset_bottom = offsets.w

func panel(parent: Node, title: String, anchors: Vector4, offsets: Vector4) -> PanelContainer:
	var p = node(parent,"PanelContainer",title)
	layout(p,anchors,offsets)
	p.add_theme_stylebox_override("panel",style(Color("eeeadc")))
	return p

func label(parent: Node, title: String, value: String, size: int = 16) -> Label:
	var l = unique(node(parent,"Label",title))
	l.text = value
	l.add_theme_font_size_override("font_size",size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func button(parent: Node, title: String, value: String) -> Button:
	var b = unique(node(parent,"Button",title))
	b.text = value
	b.custom_minimum_size.y = 34
	return b

func column(parent: Node, title: String) -> VBoxContainer:
	var v = node(parent,"VBoxContainer",title)
	v.add_theme_constant_override("separation",7)
	return v

func row(parent: Node, title: String) -> HBoxContainer:
	var h = node(parent,"HBoxContainer",title)
	h.add_theme_constant_override("separation",7)
	return h

func meter(parent: Node, title: String, text: String) -> void:
	var h = row(parent,title+"Row")
	var l = label(h,title+"Caption",text,14)
	l.custom_minimum_size.x = 72
	var bar = unique(node(h,"ProgressBar",title))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 12
	bar.show_percentage = false

func _make_main() -> void:
	var root_node = Node3D.new()
	root_node.name = "LifeTown"
	root_node.add_child(load("res://game/scenes/town.tscn").instantiate())
	var camera = node(root_node,"Camera3D","Camera")
	camera.current = true
	# 48 degrees chosen and saved using the Godot inspector on 2026-11-03.
	camera.fov = 48
	node(root_node,"Node3D","Residents")
	node(root_node,"Node3D","PlacedBenches")
	var canvas = node(root_node,"CanvasLayer","Interface")
	var ui = node(canvas,"Control","InterfaceRoot")
	layout(ui,Vector4(0,0,1,1),Vector4.ZERO)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_color","Label",Color("2c3a3e"))
	theme.set_color("font_color","Button",Color("fff1d7"))
	theme.set_color("font_hover_color","Button",Color.WHITE)
	theme.set_color("font_disabled_color","Button",Color("9c9f99"))
	theme.set_stylebox("normal","Button",style(Color("375760")))
	theme.set_stylebox("hover","Button",style(Color("58757a"),Color("e2c783")))
	theme.set_stylebox("pressed","Button",style(Color("263f48"),Color("f3d79d")))
	theme.set_stylebox("disabled","Button",style(Color("667472")))
	theme.set_stylebox("background","ProgressBar",style(Color("d1c8b0")))
	theme.set_stylebox("fill","ProgressBar",style(Color("668880")))
	ui.theme = theme
	var hud = unique(node(ui,"Control","HUD"))
	layout(hud,Vector4(0,0,1,1),Vector4.ZERO)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top = row(panel(hud,"TimePanel",Vector4(0,0,1,0),Vector4(12,12,-12,68)),"TimeControls")
	label(top,"Calendar","1年目　春1日　土曜",19).custom_minimum_size.x = 260
	label(top,"Clock","13:00",26).custom_minimum_size.x = 85
	button(top,"PauseButton","一時停止")
	for speed in [1,3,6]: button(top,"Speed%d"%speed,"×%d"%speed)
	var space = node(top,"Control","Spacer")
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(top,"Budget","共有予算 100",16).custom_minimum_size.x = 160
	button(top,"MenuButton","メニュー")
	var left = column(panel(hud,"ResidentsPanel",Vector4(0,0,0,1),Vector4(12,80,222,-181)),"ResidentsColumn")
	label(left,"RosterTitle","町の人たち",20)
	var roster = unique(column(left,"Roster"))
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label(left,"CameraGuide","WASDで移動\n右ドラッグで回転\nホイールでズーム",12)
	var right = column(panel(hud,"DetailPanel",Vector4(1,0,1,1),Vector4(-346,80,-12,-181)),"DetailColumn")
	var identity = row(right,"Identity")
	var portrait = unique(node(identity,"TextureRect","Portrait"))
	portrait.custom_minimum_size = Vector2(85,98)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var names = column(identity,"IdentityText")
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(names,"ResidentName","高瀬 葵　20歳",20)
	label(names,"Occupation","学生",14)
	button(names,"FollowButton","この人を追う")
	label(right,"Activity","好きなことに取り組む",19)
	label(right,"Reason","「ラジオを直したい」",14).custom_minimum_size.y = 40
	label(right,"NextPlan","このあとは自由な時間",13)
	meter(right,"Fatigue","疲れ")
	meter(right,"Hunger","空腹")
	meter(right,"Connection","人恋しさ")
	label(right,"Goal","本人が気になっていること",14)
	var progress = unique(node(right,"ProgressBar","GoalProgress"))
	progress.show_percentage = false
	progress.custom_minimum_size.y = 9
	var tabs = row(right,"Tabs")
	button(tabs,"NowTab","いま")
	button(tabs,"RelationsTab","関係")
	button(tabs,"MemoriesTab","記憶")
	var scroll = node(right,"ScrollContainer","DetailScroll")
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var detail = label(scroll,"DetailText","町の暮らしを見守りましょう。",14)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bottom = column(panel(hud,"ActionsPanel",Vector4(0,1,1,1),Vector4(12,-169,-12,-12)),"ActionColumn")
	var actions = row(bottom,"Actions")
	button(actions,"RestButton","休むことを提案")
	button(actions,"GoalButton","やりたいことを応援")
	var partner = unique(node(actions,"OptionButton","Partner"))
	partner.custom_minimum_size.x = 154
	button(actions,"MeetButton","話す機会を作る")
	var flex = node(actions,"Control","Flex")
	flex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(actions,"BenchButton","ベンチを置く  20")
	label(bottom,"EventText","町の出来事がここに残ります。",14).size_flags_vertical = Control.SIZE_EXPAND_FILL
	label(bottom,"Version","v0.1 開発版 · 日常ときっかけ",11)
	var toast = unique(label(hud,"Toast","",17))
	layout(toast,Vector4(.17,0,.75,0),Vector4(0,80,0,130))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_stylebox_override("normal",style(Color("f4e6c7")))
	toast.visible = false
	var title = unique(node(ui,"Control","TitleScreen"))
	layout(title,Vector4(0,0,1,1),Vector4.ZERO)
	var background = node(title,"TextureRect","TitleArtwork")
	layout(background,Vector4(0,0,1,1),Vector4.ZERO)
	background.texture = load("res://game/assets/ui/title.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var shade = node(title,"ColorRect","Shade")
	layout(shade,Vector4(0,0,.38,1),Vector4.ZERO)
	shade.color = Color(.07,.16,.19,.91)
	var title_column = column(title,"TitleColumn")
	layout(title_column,Vector4(.04,.18,.33,.85),Vector4.ZERO)
	var name_label = label(title_column,"GameTitle","命の砂時計",42)
	name_label.add_theme_color_override("font_color",Color("f4e8c8"))
	var subtitle = label(title_column,"Subtitle","それぞれの時間が、\n同じ町で重なっていく。",20)
	subtitle.add_theme_color_override("font_color",Color("d6ddd1"))
	var title_spacer = node(title_column,"Control","TitleSpacer")
	title_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button(title_column,"StartButton","新しい町を始める")
	button(title_column,"ContinueButton","つづきから")
	button(title_column,"GuideButton","町を見守るには")
	button(title_column,"TitleQuit","終了する")
	var version = label(title_column,"TitleVersion","v0.1 開発版 · 日常ときっかけ",12)
	version.add_theme_color_override("font_color",Color("d6ddd1"))
	var pause = unique(node(ui,"Control","PauseMenu"))
	layout(pause,Vector4(0,0,1,1),Vector4.ZERO)
	var scrim = node(pause,"ColorRect","Scrim")
	layout(scrim,Vector4(0,0,1,1),Vector4.ZERO)
	scrim.color = Color(0,.08,.1,.65)
	var pause_column = column(panel(pause,"MenuPanel",Vector4(.35,.2,.65,.8),Vector4.ZERO),"PauseColumn")
	label(pause_column,"PauseTitle","町の時間をひと休み",24)
	button(pause_column,"ResumeButton","町に戻る")
	button(pause_column,"SaveButton","保存する")
	button(pause_column,"LoadButton","保存したところから再開")
	button(pause_column,"HelpButton","操作の案内")
	button(pause_column,"ReturnTitle","タイトルへ戻る")
	var dialog = unique(node(ui,"AcceptDialog","InfoDialog"))
	dialog.theme = theme
	root_node.set_script(load("res://game/scripts/main.gd"))
	save_scene(root_node,"main")

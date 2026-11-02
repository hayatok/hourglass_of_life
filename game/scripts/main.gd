extends Node3D

const AVATAR = preload("res://game/scenes/resident_avatar.tscn")
const BENCH = preload("res://game/scenes/bench.tscn")
var avatars: Dictionary = {}
var selected_id: String = "aoi"
var following: bool = false
var placement: bool = false
var camera_target = Vector3(0,0,0)
var yaw: float = .42
var distance: float = 31
var dragging: bool = false
var ui_timer: float = 0
var detail_tab: int = 0
var toast_left: float = 0
var running_before_menu: bool = false

@onready var camera: Camera3D = $Camera
@onready var roster: VBoxContainer = %Roster
@onready var partner: OptionButton = %Partner
@onready var portrait: TextureRect = %Portrait
@onready var title: Control = %TitleScreen
@onready var pause_menu: Control = %PauseMenu
@onready var info_dialog: AcceptDialog = %InfoDialog

func _ready() -> void:
	%StartButton.pressed.connect(_new_game)
	%ContinueButton.pressed.connect(_continue_game)
	%ContinueButton.disabled = not Sim.has_save()
	%GuideButton.pressed.connect(_show_guide)
	%TitleQuit.pressed.connect(func(): get_tree().quit())
	%PauseButton.pressed.connect(_toggle_pause)
	%Speed1.pressed.connect(func(): _set_speed(1))
	%Speed3.pressed.connect(func(): _set_speed(3))
	%Speed6.pressed.connect(func(): _set_speed(6))
	%MenuButton.pressed.connect(_open_menu)
	%ResumeButton.pressed.connect(_close_menu)
	%SaveButton.pressed.connect(_save)
	%LoadButton.pressed.connect(_continue_game)
	%HelpButton.pressed.connect(_show_guide)
	%ReturnTitle.pressed.connect(_to_title)
	%FollowButton.pressed.connect(func(): following = not following)
	%RestButton.pressed.connect(func(): _answer(Sim.propose_rest(selected_id)))
	%GoalButton.pressed.connect(func(): _answer(Sim.support_goal(selected_id)))
	%MeetButton.pressed.connect(_meet)
	%BenchButton.pressed.connect(func(): placement = not placement; _toast("広場の地面をクリックして、ベンチを置きます（共有予算20）" if placement else "配置を取り消しました"))
	%NowTab.pressed.connect(func(): detail_tab=0; _refresh_detail())
	%RelationsTab.pressed.connect(func(): detail_tab=1; _refresh_detail())
	%MemoriesTab.pressed.connect(func(): detail_tab=2; _refresh_detail())
	Sim.town_changed.connect(_rebuild)
	Sim.event_added.connect(func(_e): _refresh_events())
	_rebuild()
	_build_roster()
	_refresh_ui()
	title.visible = true
	pause_menu.visible = false
	%HUD.visible = false
	Sim.running = false

func _new_game() -> void:
	Sim.reset()
	_start_play()

func _start_play() -> void:
	title.visible = false
	pause_menu.visible = false
	%HUD.visible = true
	Sim.running = true
	_rebuild()
	_select(selected_id)
	_toast("気になる住人を選び、暮らしを見てみましょう。Spaceで一時停止できます。")

func _continue_game() -> void:
	if Sim.load_game():
		_start_play()
		_toast("保存した町の続きを開きました")
	else:
		_toast("保存データを読み込めませんでした")

func _rebuild() -> void:
	for a in $Residents.get_children():
		a.queue_free()
	avatars.clear()
	for p in Sim.people:
		var actor = AVATAR.instantiate()
		$Residents.add_child(actor)
		actor.configure(p)
		avatars[p.id] = actor
	for b in $PlacedBenches.get_children():
		b.queue_free()
	for position in Sim.benches:
		var bench = BENCH.instantiate()
		$PlacedBenches.add_child(bench)
		bench.position = position
	_refresh_events()

func _build_roster() -> void:
	for child in roster.get_children():
		child.queue_free()
	for p in Sim.people:
		var button = Button.new()
		button.text = "%s\n%s" % [p.name,p.occupation]
		button.custom_minimum_size = Vector2(188,55)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size",15)
		button.pressed.connect(_select.bind(p.id))
		roster.add_child(button)

func _select(id: String) -> void:
	selected_id = id
	partner.clear()
	for p in Sim.people:
		if p.id != id:
			partner.add_item(p.name)
			partner.set_item_metadata(partner.item_count-1,p.id)
	if id == "aoi":
		for i in partner.item_count:
			if partner.get_item_metadata(i) == "osamu":
				partner.select(i)
	var ids = ["nagisa","ryo","rin","osamu","fumi","maho","ritsu","aoi"]
	var x = [30,240,440,615,840,1060,1280,1505][ids.find(id)]
	var atlas = AtlasTexture.new()
	atlas.atlas = load("res://game/assets/ui/residents.png")
	atlas.region = Rect2(x,10,200,235)
	portrait.texture = atlas
	_refresh_detail()

func _process(delta: float) -> void:
	if following and not title.visible:
		camera_target = camera_target.lerp(Sim.person(selected_id).position,minf(1,delta*2))
	if not title.visible and not pause_menu.visible:
		var motion = Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): motion.z -= 1
		if Input.is_physical_key_pressed(KEY_S): motion.z += 1
		if Input.is_physical_key_pressed(KEY_A): motion.x -= 1
		if Input.is_physical_key_pressed(KEY_D): motion.x += 1
		if motion.length_squared()>0:
			following = false
			camera_target += motion.rotated(Vector3.UP,yaw)*delta*9
			camera_target.x = clampf(camera_target.x,-15,15)
			camera_target.z = clampf(camera_target.z,-10,13)
	var offset = Vector3(sin(yaw)*distance,distance*.85,cos(yaw)*distance)
	camera.position = camera_target+offset
	camera.look_at(camera_target+Vector3(0,.7,0))
	for p in Sim.people:
		if avatars.has(p.id):
			avatars[p.id].update_state(p,delta,selected_id==p.id)
	ui_timer -= delta
	if ui_timer<=0:
		ui_timer = .2
		_refresh_ui()
	if toast_left>0:
		toast_left -= delta
		%Toast.visible = toast_left>0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if placement:
				placement = false
			elif not title.visible:
				_close_menu() if pause_menu.visible else _open_menu()
		elif event.keycode == KEY_SPACE and not title.visible and not pause_menu.visible:
			_toggle_pause()
	if title.visible or pause_menu.visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(15,distance-2)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(48,distance+2)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if placement:
				var plane = Plane(Vector3.UP,0)
				var point = plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
				if point != null:
					_answer(Sim.place_bench(point))
					placement = false
			else:
				var closest = ""
				var best: float = 40
				for p in Sim.people:
					if camera.is_position_behind(p.position):
						continue
					var screen = camera.unproject_position(p.position+Vector3(0,1,0))
					var gap = screen.distance_to(event.position)
					if gap<best:
						best = gap
						closest = p.id
				if not closest.is_empty():
					_select(closest)
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x*.006

func _set_speed(value: float) -> void:
	Sim.speed = value
	Sim.running = true
	_refresh_ui()

func _toggle_pause() -> void:
	Sim.running = not Sim.running
	_refresh_ui()

func _open_menu() -> void:
	running_before_menu = Sim.running
	pause_menu.visible = true
	Sim.running = false

func _close_menu() -> void:
	pause_menu.visible = false
	Sim.running = running_before_menu

func _save() -> void:
	_toast("町の時間と出来事を保存しました" if Sim.save_game() else "保存できませんでした")
	%ContinueButton.disabled = not Sim.has_save()

func _to_title() -> void:
	Sim.running = false
	pause_menu.visible = false
	title.visible = true
	%HUD.visible = false
	%ContinueButton.disabled = not Sim.has_save()

func _meet() -> void:
	if partner.item_count == 0:
		return
	_answer(Sim.propose_meeting(selected_id,partner.get_selected_metadata(),"bench"))

func _answer(reply: Dictionary) -> void:
	_toast(reply.text)
	_refresh_detail()
	_refresh_events()

func _toast(text: String) -> void:
	%Toast.text = text
	%Toast.visible = true
	toast_left = 8

func _refresh_ui() -> void:
	%Calendar.text = Sim.calendar_text()
	%Clock.text = Sim.clock_text()
	%PauseButton.text = "再開" if not Sim.running else "一時停止"
	%Budget.text = "共有予算  %d" % Sim.shared_budget
	%FollowButton.text = "追従中" if following else "この人を追う"
	%Version.text = "v0.1 開発版 · 日常ときっかけ"
	if not title.visible:
		_refresh_detail()

func _refresh_detail() -> void:
	var p = Sim.person(selected_id)
	if p.is_empty():
		return
	%ResidentName.text = "%s  ·  %d歳" % [p.name,p.age]
	%Occupation.text = p.occupation
	%Activity.text = ("移動中 → " if p.moving else "")+Sim.ACTION_NAMES.get(p.action,p.action)
	%Reason.text = "「%s」" % p.reason
	%NextPlan.text = Sim.commitment_text(p)
	%Fatigue.value = p.fatigue*100
	%Hunger.value = p.hunger*100
	%Connection.value = p.connection*100
	%Goal.text = Sim.definitions[p.id].goals[0]
	%GoalProgress.value = p.goal_progress*100
	var text: String = ""
	if detail_tab == 0:
		text = "いま大切にしていること\n\n"+Sim.definitions[p.id].public_private_difference+"\n\n"+Sim.definitions[p.id].goals[1]
	elif detail_tab == 1:
		text = "親しみ / 信頼\n\n"
		for other_id in p.relationships:
			var rel = p.relationships[other_id]
			text += "%s  %d / %d\n" % [Sim.person(other_id).name,int(rel.familiarity*100),int(rel.trust*100)]
		if p.relationships.is_empty():
			text += "これから知っていく人たちがいる。"
	else:
		text = "この人に残った出来事\n\n"
		for memory in p.memories.slice(maxi(0,p.memories.size()-5)):
			text += "・%s\n%s\n\n" % [memory.title,memory.text]
		if p.memories.is_empty():
			text += "町で過ごす時間が、これから積もっていく。"
	%DetailText.text = text

func _refresh_events() -> void:
	if not is_node_ready():
		return
	var text: String = ""
	for e in Sim.events.slice(maxi(0,Sim.events.size()-3)):
		var who = Sim.person(e.resident_id).get("name","町") if not e.resident_id.is_empty() else "町"
		text += "%s  %s  ·  %s\n" % [e.clock,who,e.text]
	%EventText.text = text.strip_edges()

func _show_guide() -> void:
	info_dialog.title = "町を見守る操作"
	info_dialog.dialog_text = "住人一覧または町の人物をクリックすると、その人の事情が見られます。\n\n右ドラッグ：カメラ回転　 ホイール：ズーム\nWASD：町を見渡す　 Space：一時停止　 Escape：メニュー\n\n相手を選んで「話す機会を作る」を提案できます。\n二人が合流し、話す時間を過ごすと記憶が残ります。\n断られたときも、その人の予定や疲れに理由があります。\n\n「ベンチを置く」から広場の地面をクリックすると、場所を整えられます。\n\n開発版では仮の人物モデルを使っています。完成用のJRPG調モデルは後の版で組み込みます。"
	info_dialog.popup_centered(Vector2i(700,430))

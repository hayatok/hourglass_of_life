extends Node3D

const AVATAR = preload("res://game/scenes/resident_avatar.tscn")
const BENCH = preload("res://game/scenes/bench.tscn")
const LEGACY = preload("res://game/scenes/legacy_record.tscn")
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
var running_before_journal: bool = false
var bench_preview: Node3D
var event_focus := ""
var interaction_view: WorldInteractionView
var tabletop_view: TabletopGameView

@onready var camera: Camera3D = $Camera
@onready var roster: VBoxContainer = %Roster
@onready var proposals = %ProposalScreen
@onready var partner: OptionButton = proposals.partner
@onready var portrait: TextureRect = %Portrait
@onready var title: Control = %TitleScreen
@onready var pause_menu: Control = %PauseMenu
@onready var info_dialog: AcceptDialog = %InfoDialog

func _ready() -> void:
	TranslationServer.set_locale("ja")
	%StartButton.pressed.connect(_new_game)
	%ContinueButton.pressed.connect(_continue_game)
	%ContinueButton.disabled = not Sim.has_save()
	%GuideButton.pressed.connect(_show_guide)
	%TitleQuit.pressed.connect(func(): get_tree().quit())
	%ResidentSearch.text_changed.connect(_filter_roster)
	%PauseButton.pressed.connect(_toggle_pause)
	%Speed1.pressed.connect(func(): _set_speed(1))
	%Speed3.pressed.connect(func(): _set_speed(3))
	%Speed6.pressed.connect(func(): _set_speed(6))
	%Speed30.pressed.connect(func(): _set_speed(30))
	%SpeedHalf.pressed.connect(func(): _set_speed(.5))
	%JournalButton.pressed.connect(func(): _open_journal(false))
	%JournalContinueButton.pressed.connect(_close_journal)
	%JournalSaveButton.pressed.connect(_save)
	%MenuButton.pressed.connect(_open_menu)
	%ResumeButton.pressed.connect(_close_menu)
	%SaveButton.pressed.connect(_save)
	%LoadButton.pressed.connect(_continue_game)
	%HelpButton.pressed.connect(_show_guide)
	%ReturnTitle.pressed.connect(_to_title)
	%FollowButton.pressed.connect(_toggle_follow)
	%BuildingsButton.pressed.connect(_toggle_buildings)
	%ZoomIn.pressed.connect(func(): _zoom_by(1.2))
	%ZoomOut.pressed.connect(func(): _zoom_by(1.0/1.2))
	%TownOverview.pressed.connect(_show_town_overview)
	%ProposeButton.pressed.connect(func(): dragging = false; proposals.open_for(selected_id))
	%LatestEvent.pressed.connect(func(): event_focus = selected_id; _refresh_events(); %HUD._show_history(true))
	%HistoryToggle.toggled.connect(func(open):
		if open: event_focus = ""; _refresh_events())
	proposals.answered.connect(_answer)
	%BenchButton.pressed.connect(func(): _set_placement(true))
	%CancelPlacement.pressed.connect(func(): _set_placement(false))
	%NowTab.pressed.connect(func(): detail_tab=0; _refresh_detail())
	%RelationsTab.pressed.connect(func(): detail_tab=1; _refresh_detail())
	%MemoriesTab.pressed.connect(func(): detail_tab=2; _refresh_detail())
	%PlansTab.pressed.connect(func(): detail_tab=4; _refresh_detail())
	%LifeTab.pressed.connect(func(): detail_tab=3; _refresh_detail())
	Sim.town_changed.connect(_rebuild)
	Sim.chapter_reached.connect(func(): _open_journal(true))
	Sim.event_added.connect(func(_e): _refresh_events())
	_rebuild()
	interaction_view = WorldInteractionView.new();interaction_view.name = "WorldObjects";add_child(interaction_view)
	interaction_view.setup($Town,avatars,Sim)
	tabletop_view = TabletopGameView.new();tabletop_view.name = "TabletopObjects";add_child(tabletop_view)
	tabletop_view.setup($Town,avatars,Sim)
	_build_roster()
	_refresh_ui()
	title.visible = true
	pause_menu.visible = false
	%JournalScreen.visible = false
	%HUD.visible = false
	Sim.running = false

func _new_game() -> void:
	_set_placement(false)
	selected_id = "aoi";following = false;dragging = false
	camera_target = Vector3.ZERO;distance = 31;yaw = .42;event_focus = ""
	%ResidentSearch.text = ""
	%HUD.get_node("ResidentsPanel/ResidentsColumn/RosterScroll").scroll_vertical = 0
	var seed_value: int = int(Time.get_unix_time_from_system()*1000)^Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--world-seed=") and argument.trim_prefix("--world-seed=").is_valid_int():
			seed_value = maxi(0,int(argument.trim_prefix("--world-seed=")))
	Sim.reset(seed_value,Sim.EXPANDED_POPULATION)
	_start_play()

func _start_play() -> void:
	title.visible = false
	pause_menu.visible = false
	%HUD.visible = true
	Sim.running = Sim.people.any(func(p): return Sim.life.is_alive(p))
	_rebuild()
	_select(selected_id,false)
	%HUD.start_observing()
	_toast("町の住民をクリックするか、「住民を選ぶ」から見守る人を選べます。" if Sim.running else "町の記録から、ここまでの時間を読み返せます。")
	if Sim.life.chapter_ready: _open_journal(true)

func _continue_game(path: String = "") -> void:
	if Sim.load_game(Sim.SAVE_PATH if path.is_empty() else path):
		_start_play()
		_toast("保存した町の続きを開きました")
	else:
		# The observation HUD is hidden on the title screen. Its toast cannot
		# explain why Continue did nothing; show the reason on this screen.
		info_dialog.title = "保存した町を開けません"
		info_dialog.dialog_text = Sim.load_error if not Sim.load_error.is_empty() else "保存データを読み込めませんでした。"
		info_dialog.popup_centered(Vector2i(600,190))

func _rebuild() -> void:
	var selection_changed: bool = Sim.person(selected_id).is_empty()
	if selection_changed: selected_id = "aoi"
	for a in $Residents.get_children():
		$Residents.remove_child(a)
		a.queue_free()
	avatars.clear()
	for p in Sim.people:
		var actor = AVATAR.instantiate()
		$Residents.add_child(actor)
		actor.others = avatars
		actor.configure(p)
		avatars[p.id] = actor
	for b in $PlacedBenches.get_children():
		$PlacedBenches.remove_child(b)
		b.queue_free()
	for position in Sim.benches:
		var bench = BENCH.instantiate()
		$PlacedBenches.add_child(bench)
		bench.position = position
	for child in $LegacyRecords.get_children():
		$LegacyRecords.remove_child(child)
		child.queue_free()
	for item in Sim.life.legacy:
		var record = LEGACY.instantiate()
		$LegacyRecords.add_child(record)
		record.position = item.position
		record.get_node("Sign").text = item.label
	if is_instance_valid(interaction_view): interaction_view.setup($Town,avatars,Sim)
	if is_instance_valid(tabletop_view): tabletop_view.setup($Town,avatars,Sim)
	if is_node_ready():
		var preferred: String = partner.get_selected_metadata() if partner.item_count>0 else ""
		_build_roster()
		_update_partners(preferred)
		if not Sim.life.is_alive(Sim.person(selected_id)): following = false
		if selection_changed: _select(selected_id)
	_refresh_events()

func _build_roster() -> void:
	%RosterTitle.text = "住民 %d人"%Sim.people.size()
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	for p in Sim.people:
		var button = Button.new()
		button.text = "%s\n%s" % [p.name,p.occupation]
		button.icon = _resident_portrait(p.id,true)
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width",46)
		button.toggle_mode = true
		button.set_pressed_no_signal(p.id==selected_id)
		button.set_meta("resident_id",p.id)
		button.custom_minimum_size = Vector2(240,66)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.add_theme_font_size_override("font_size",15)
		button.pressed.connect(_select.bind(p.id))
		roster.add_child(button)
	_filter_roster(%ResidentSearch.text)

func _filter_roster(query: String) -> void:
	query = query.strip_edges().to_lower()
	for button in roster.get_children():
		button.visible = query.is_empty() or query in button.text.to_lower()
	%EmptySearch.visible = not roster.get_children().any(func(button): return button.visible)

func _update_partners(preferred: String = "") -> void:
	partner.clear()
	for p in Sim.people:
		if p.id != selected_id and Sim.life.is_alive(p):
			partner.add_item(p.name)
			partner.set_item_metadata(partner.item_count-1,p.id)
	for i in partner.item_count:
		if partner.get_item_metadata(i)==preferred: partner.select(i)

func _select(id: String, frame_person: bool = true) -> void:
	if Sim.person(id).is_empty(): return
	selected_id = id
	if frame_person and not title.visible and avatars.has(id):
		following = false
		camera_target = avatars[id].focus_position();camera_target.y = 0
		distance = 14
		toast_left = 0;%Toast.hide()
	_update_partners(_initial_partner(id))
	portrait.texture = _resident_portrait(id,true)
	for button in roster.get_children(): button.set_pressed_no_signal(button.get_meta("resident_id","")==id)
	portrait.modulate = Color.WHITE if Sim.life.is_alive(Sim.person(id)) else Color(.65,.65,.65)
	if %HUD.has_method("reveal_person"): %HUD.reveal_person()
	_refresh_detail()
	_refresh_events()

func _resident_portrait(id: String, crop: bool = false) -> Texture2D:
	return preload("res://game/scripts/resident_portraits.gd").texture(id,crop)

func _initial_partner(id: String) -> String:
	var p: Dictionary = Sim.person(id)
	for meeting in Sim.meetings:
		if meeting.id!=p.get("meeting_id","") or meeting.state not in ["travel","waiting","engaged"]: continue
		if id not in [meeting.a,meeting.b]: continue
		var other: String = meeting.b if meeting.a==id else meeting.a
		if other!=id and Sim.life.is_alive(Sim.person(other)): return other
	var plan: Dictionary = p.get("cognition_plan",{})
	var planned_other: String = plan.get("partner","")
	if plan.get("stage","") in ["travel","waiting","execute"] and planned_other!=id and Sim.life.is_alive(Sim.person(planned_other)):
		return planned_other
	return "osamu" if id=="aoi" else ""

func _process(delta: float) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var typing: bool = focused is LineEdit or focused is TextEdit
	if following and not title.visible:
		var target: Vector3 = avatars[selected_id].focus_position()
		target.y = 0
		camera_target = camera_target.lerp(target,minf(1,delta*2))
	if not typing and not title.visible and not pause_menu.visible and not %JournalScreen.visible and not proposals.visible:
		var motion = Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): motion.z -= 1
		if Input.is_physical_key_pressed(KEY_S): motion.z += 1
		if Input.is_physical_key_pressed(KEY_A): motion.x -= 1
		if Input.is_physical_key_pressed(KEY_D): motion.x += 1
		if motion.length_squared()>0:
			following = false
			camera_target += motion.rotated(Vector3.UP,yaw)*delta*9
			camera_target.x = clampf(camera_target.x,-15,15)
			camera_target.z = clampf(camera_target.z,-20,13)
	var offset = Vector3(sin(yaw)*distance,distance*.85,cos(yaw)*distance)
	camera.position = camera_target+offset
	camera.look_at(camera_target+Vector3(0,.7,0))
	var right_panel: Control = %HUD.get_node("DetailPanel")
	var left_panel: Control = %HUD.get_node("ResidentsPanel")
	var covered_right: float = right_panel.size.x+12 if right_panel.visible and not title.visible else 0.0
	var covered_left: float = left_panel.size.x+12 if left_panel.visible and not title.visible else 0.0
	var pixel_shift := (covered_right-covered_left)*.5
	var units_per_pixel := 2*camera.position.distance_to(camera_target)*tan(deg_to_rad(camera.fov)*.5)/maxf(1,get_viewport().get_visible_rect().size.y)
	camera.h_offset = lerpf(camera.h_offset,pixel_shift*units_per_pixel,minf(1,delta*5))
	$Town.update_view(camera.global_position)
	_update_placement_preview()
	for p in Sim.people:
		if avatars.has(p.id):
			var actor = avatars[p.id]
			actor.update_state(p,delta,selected_id==p.id)
			_update_resident_name_label(actor,p.id)
	if is_instance_valid(interaction_view): interaction_view.sync(delta)
	if is_instance_valid(tabletop_view): tabletop_view.sync(delta)
	ui_timer -= delta
	if ui_timer<=0:
		ui_timer = .2
		_refresh_ui()
	if toast_left>0:
		toast_left -= delta
		%Toast.visible = toast_left>0

func _update_resident_name_label(actor, resident_id: String) -> void:
	# Keep the selected person's face and nearby gestures readable in a crowd.
	actor.name_label.visible = not title.visible and selected_id==resident_id
	actor.name_label.global_position = actor.head_position()+Vector3.UP*.4
	var label_distance := camera.global_position.distance_to(actor.name_label.global_position)
	actor.name_label.pixel_size = .012*minf(1.0,label_distance/16.0)

func _input(event: InputEvent) -> void:
	# Release is observed before GUI consumes it over a panel.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
		dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed: dragging = false
	if proposals.visible: return
	var focused := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and (focused is LineEdit or focused is TextEdit):
		if event.pressed and event.keycode==KEY_ESCAPE: focused.release_focus()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if %JournalScreen.visible:
				_close_journal()
			elif placement:
				_set_placement(false)
			elif not title.visible and not pause_menu.visible and %HUD.close_top_panel():
				pass
			elif not title.visible:
				_close_menu() if pause_menu.visible else _open_menu()
		elif event.keycode == KEY_SPACE and not title.visible and not pause_menu.visible and not %JournalScreen.visible:
			_toggle_pause()
		elif event.keycode == KEY_V and not title.visible and not pause_menu.visible and not %JournalScreen.visible:
			_toggle_buildings()
		elif not title.visible and not pause_menu.visible and not %JournalScreen.visible:
			if event.keycode in [KEY_PLUS,KEY_EQUAL,KEY_KP_ADD]: _zoom_by(1.2)
			elif event.keycode in [KEY_MINUS,KEY_KP_SUBTRACT]: _zoom_by(1.0/1.2)
	if title.visible or pause_menu.visible or %JournalScreen.visible:
		return
	if event is InputEventMagnifyGesture:
		if not _camera_pointer_over_ui(event.position): _zoom_by(event.factor)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventPanGesture:
		if not _camera_pointer_over_ui(event.position):
			following = false
			camera_target += Vector3(event.delta.x,0,event.delta.y).rotated(Vector3.UP,yaw)*distance*.025
			camera_target.x = clampf(camera_target.x,-15,15);camera_target.z = clampf(camera_target.z,-20,13)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(pow(1.12,maxf(.1,event.factor)))
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(pow(1.12,-maxf(.1,event.factor)))
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if placement:
				var plane = Plane(Vector3.UP,0)
				var point = plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
				if point != null:
					var reply: Dictionary = Sim.place_bench(point)
					_answer(reply)
					if reply.status=="accept": _set_placement(false)
			else:
				var closest = ""
				var best: float = 40
				for p in Sim.people:
					if not avatars.has(p.id) or not avatars[p.id].visible: continue
					var focus: Vector3 = avatars[p.id].focus_position()
					if camera.is_position_behind(focus):
						continue
					var screen = camera.unproject_position(focus)
					var gap = screen.distance_to(event.position)
					if gap<best:
						best = gap
						closest = p.id
				if not closest.is_empty():
					_select(closest)
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x*.006

func _zoom_by(factor: float) -> void:
	if is_finite(factor) and factor>0: distance = clampf(distance/factor,3.5,48)

func _show_town_overview() -> void:
	following = false;camera_target = Vector3.ZERO;distance = 31

func _camera_pointer_over_ui(position: Vector2) -> bool:
	for control in %HUD.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		if control is PanelContainer or control is BaseButton or control is ScrollContainer or control is LineEdit:
			if control.get_global_rect().has_point(position): return true
	return false

func _toggle_buildings() -> void:
	$Town.cutaway = not $Town.cutaway
	$Town.update_view(camera.global_position)
	%BuildingsButton.text = "建物の外観を見る" if $Town.cutaway else "屋根と手前の壁を隠す"

func _toggle_follow() -> void:
	following = not following
	if following: distance = 10

func _set_speed(value: float) -> void:
	if not Sim.people.any(func(p): return Sim.life.is_alive(p)): return
	Sim.speed = value
	_refresh_ui()

func _toggle_pause() -> void:
	if not Sim.people.any(func(p): return Sim.life.is_alive(p)): return
	Sim.running = not Sim.running
	_refresh_ui()

func _open_menu() -> void:
	dragging = false
	_set_placement(false)
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
	_set_placement(false)
	Sim.running = false
	pause_menu.visible = false
	title.visible = true
	%HUD.visible = false
	%ContinueButton.disabled = not Sim.has_save()

func _open_journal(chapter: bool) -> void:
	dragging = false
	running_before_journal = true if chapter else Sim.running
	Sim.running = false
	%JournalScreen.visible = true
	%JournalHeading.text = {"last":"町に残った時間","resumed":"この町の年月を振り返る","three_years":"最初の三年を振り返る"}.get(Sim.life.chapter_mode,"町に積もった時間") if chapter else "町に積もった時間"
	%JournalBody.text = Sim.life.journal_text()

func _close_journal() -> void:
	%JournalScreen.visible = false
	if Sim.life.chapter_ready:
		Sim.life.chapter_acknowledged = true
		Sim.life.chapter_ready = false
		if Sim.life.chapter_mode=="last": Sim.life.final_reviewed = true
	Sim.running = running_before_journal and Sim.people.any(func(p): return Sim.life.is_alive(p))

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
	var weather = Sim.get("weather")
	%WeatherStatus.set_weather(weather.snapshot() if weather != null else {})
	%PauseButton.text = "時間を進める" if not Sim.running else "一時停止"
	%PauseButton.icon = load("res://game/assets/ui/icons/play.svg" if not Sim.running else "res://game/assets/ui/icons/pause.svg")
	%PauseButton.expand_icon = false
	%PauseButton.add_theme_constant_override("icon_max_width",18)
	%Budget.text = "共有予算  %d" % Sim.shared_budget
	%FollowButton.text = "追跡をやめる" if following else "この人を追いかける"
	%Version.text = "v0.6 開発版 · 個性と経験"
	var alive = Sim.life.is_alive(Sim.person(selected_id))
	var living_town = Sim.people.any(func(p): return Sim.life.is_alive(p))
	for action in [%PauseButton,%SpeedHalf,%Speed1,%Speed3,%Speed6,%Speed30]: action.disabled = not living_town
	%FollowButton.disabled = not alive
	%ProposeButton.disabled = not alive
	%BenchButton.disabled = Sim.shared_budget<20
	%BenchButton.tooltip_text = "共有予算を20使い、広場に住民が座れる場所を増やす" if Sim.shared_budget>=20 else "共有予算が足りません（必要：20）"
	if not title.visible:
		_refresh_detail()

func _refresh_detail() -> void:
	var p = Sim.person(selected_id)
	if p.is_empty():
		return
	%ResidentName.text = p.name
	%NotebookName.text = "%sの手帳"%p.name
	%ProposeButton.text = "%sに提案する"%p.name.split(" ")[-1]
	%Occupation.text = "%d歳・%s"%[p.age,p.occupation]
	%Occupation.tooltip_text = p.occupation
	%Activity.text = ("移動中 → " if p.moving else "")+Sim.ACTION_NAMES.get(p.action,p.action)
	var plan: Dictionary = p.get("cognition_plan",{})
	var plan_reason: String = plan.get("reason","")
	var active_plan: bool = plan.get("stage","") in ["travel","execute"]
	var shown_reason: String = plan_reason if active_plan and not plan_reason.is_empty() else str(p.reason)
	%Reason.text = "「%s」"%shown_reason
	%NextPlan.text = _next_agreement_text(p)
	%Fatigue.value = (1-p.fatigue)*100
	%Hunger.value = (1-p.hunger)*100
	%Connection.value = (1-p.connection)*100
	for meter in [%Fatigue,%Hunger,%Connection]: meter.get_parent().visible = Sim.life.is_alive(p)
	for meter in [%Fatigue,%Hunger,%Connection]:
		meter.modulate = Color(1,.65,.5) if meter.value<25 else Color.WHITE
		meter.tooltip_text = "%s %d%%"%[meter.get_parent().get_child(0).text,int(meter.value)]
	%Goal.text = p.current_goal
	%GoalProgress.value = p.goal_progress*100
	var text: String = ""
	if detail_tab == 0:
		text = Sim.planner.person_text(p)
		if not active_plan and not plan_reason.is_empty():
			text += ("\n" if not text.is_empty() else "")+plan_reason
		var learning: String = Sim.cognition.explain(p)
		if not learning.is_empty() and learning!=plan_reason:
			text += ("\n\n" if not text.is_empty() else "")+learning
	elif detail_tab == 1:
		text = ""
		for other_id in p.relationships:
			var rel = p.relationships[other_id]
			text += "%s\n親しさ %d　信頼 %d\n\n" % [Sim.person(other_id).name,int(rel.familiarity*100),int(rel.trust*100)]
		if p.relationships.is_empty():
			text += "これから知っていく人たちがいる。"
	elif detail_tab==2:
		text = "この人に残った出来事\n\n"
		for memory in p.memories.slice(maxi(0,p.memories.size()-5)):
			text += "・%s\n%s\n\n" % [memory.title,memory.text]
		if p.memories.is_empty():
			text += "町で過ごす時間が、これから積もっていく。"
	elif detail_tab==4:
		text = _appointments_text(p)
	else:
		text = Sim.work_family.person_text(p)
		var personal: String = Sim.social.person_text(p)
		if not personal.is_empty(): text += "\n\n"+personal
		text += "\n\n"+("暮らしの背景\n\n" if p.alive else "大切にしていたこと\n\n")+Sim.definitions[p.id].public_private_difference+"\n\n暮らしの始まりに気にかけていたこと\n"+Sim.definitions[p.id].goals[1]
	%DetailText.text = text
	var tabs := [%NowTab,%RelationsTab,%MemoriesTab,%LifeTab,%PlansTab]
	for index in tabs.size(): tabs[index].set_pressed_no_signal(index==detail_tab)
	for element in [%Reason,%NextPlan,%Goal,%GoalProgress,%GoalHeading]: element.visible = detail_tab==0
	%Reason.visible = detail_tab==0 and shown_reason.strip_edges()!=str(p.current_goal).strip_edges()

func _appointments_text(p: Dictionary) -> String:
	var records: Array = []
	for record in Sim.agenda.records+Sim.social.appointments:
		if record.state!="planned" or p.id not in [record.a,record.b] or int(record.start)<Sim.elapsed: continue
		var other: Dictionary = Sim.person(record.b if record.a==p.id else record.a)
		if Sim.life.is_alive(other): records.append(record)
	records.sort_custom(func(a,b): return int(a.start)<int(b.start))
	if records.is_empty(): return "これからの約束はまだありません。会話や共同制作を相談すると、決まった予定をここで読み返せます。"
	var places := {"bench":"広場のベンチ","cafe":"喫茶店","bakery_cafe":"パン屋・喫茶店","workshop":"工房","square":"広場","garden":"庭","home_ogawa":"小川家","home_saeki":"佐伯家","home_shared":"共同住宅","home_north_shared":"北側の共同住宅","home_mori":"森家"}
	var text := ""
	for record in records:
		var other: Dictionary = Sim.person(record.b if record.a==p.id else record.a)
		text += Sim.social.when_text(int(record.start))
		if int(record.get("duration",0))>0: text += "・%d分"%int(record.duration)
		text += "\n%sさんと %s"%[other.name,record.get("title","ゆっくり話す")]
		var place: String = places.get(record.get("location",record.get("place","")),"")
		if not place.is_empty(): text += "\n"+place
		text += "\n\n"
	return text.strip_edges()

func _next_agreement_text(p: Dictionary) -> String:
	if not Sim.life.is_alive(p): return Sim.commitment_text(p)
	var next: Dictionary = {}
	var commitment: Dictionary = Sim.agenda.next_commitment(p)
	for record in Sim.agenda.records:
		if record.id==commitment.get("agenda_id",""):
			next = record
			break
	for appointment in Sim.social.appointments:
		if appointment.state!="planned" or p.id not in [appointment.a,appointment.b]: continue
		if next.is_empty() or int(appointment.start)<int(next.start): next = appointment
	if next.is_empty(): return Sim.commitment_text(p)
	var other: Dictionary = Sim.person(next.b if next.a==p.id else next.a)
	if not Sim.life.is_alive(other): return Sim.commitment_text(p)
	return "%s · %sさんと%s"%[Sim.social.when_text(int(next.start)),other.name,next.get("title","ゆっくり話す")]

func _refresh_events() -> void:
	if not is_node_ready():
		return
	var text: String = ""
	var visible_events: Array = Sim.events.filter(func(e): return event_focus.is_empty() or e.resident_id==event_focus)
	%EventHeading.text = "町の出来事" if event_focus.is_empty() else "%sの出来事"%Sim.person(event_focus).get("name","")
	for e in visible_events.slice(maxi(0,visible_events.size()-8)):
		var who = Sim.person(e.resident_id).get("name","町") if not e.resident_id.is_empty() else "町"
		text += "%s　%s\n%s\n%s\n\n" % [e.clock,who,e.title,e.text]
	%EventText.text = text.strip_edges() if not text.is_empty() else "この町の出来事が、ここに残っていきます。"
	var recent: Dictionary = {}
	var priorities := {"二人で形にしたもの":3,"約束して過ごした時間":2,"一緒に過ごした時間":2,"得意なことを知った":0}
	for e in Sim.events:
		if e.resident_id!=selected_id: continue
		if recent.is_empty() or int(e.minute)>int(recent.minute) or (int(e.minute)==int(recent.minute) and priorities.get(e.title,1)>=priorities.get(recent.title,1)):
			recent = e
	%LatestEvent.set_meta("has_event",not recent.is_empty())
	if not recent.is_empty():
		var summary: String = str(recent.text).split("。")[0]+"。"
		if summary.length()>48: summary = summary.substr(0,47)+"…"
		%LatestEvent.text = "%s　%s　› 記録を読む\n%s"%[recent.clock,Sim.person(selected_id).name,summary]
		%LatestEvent.tooltip_text = recent.text+"\nクリックして記録を読む"


func _show_guide() -> void:
	info_dialog.title = "町を見守る操作"
	info_dialog.dialog_text = "住民をクリック、または『住民を選ぶ』から気になる人を選びます。\n『この人を追いかける』で近くから見守れます。\n\n選んだ人のカードから『提案する』を開くと、休息や交流を相談できます。相手と内容を選び、住民の返答を読んでください。予定や気持ちによって、断ったり別の日を提案したりします。\n\n『人物手帳』は願い・予定・人間関係・思い出・仕事。\n『出来事を見る』は最近の動き、『年月を振り返る』は町の歩みです。\n\nSpace：時間の停止／再開　WASD：カメラ移動\nピンチ・＋／−：拡大縮小　二本指：カメラ移動\n右ドラッグ：回転　ホイール：拡大縮小　Esc：閉じる\n『町を整える』から、広場にベンチを置けます。"
	info_dialog.popup_centered(Vector2i(700,430))

func _set_placement(active: bool) -> void:
	placement = active
	%HUD.get_node("PlacementHint").visible = active
	%HUD._show_build(false)
	if not active:
		if is_instance_valid(bench_preview): bench_preview.hide()
		return
	if not is_instance_valid(bench_preview):
		bench_preview = BENCH.instantiate();bench_preview.name = "BenchPreview";add_child(bench_preview)
		for mesh in bench_preview.find_children("*","MeshInstance3D",true,false):
			var material := StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bench_preview.show()

func _update_placement_preview() -> void:
	if not placement or not is_instance_valid(bench_preview): return
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if hit==null: bench_preview.hide();return
	bench_preview.show()
	var point := Vector3(snappedf(hit.x,.5),0,snappedf(hit.z,.5))
	bench_preview.position = point
	var valid: bool = Sim.shared_budget>=20 and absf(point.x)<=5 and point.z>=0 and point.z<=8 and not Sim.activities.bench_overlaps_furniture(point)
	for bench in Sim.benches: valid = valid and bench.distance_to(point)>=1.8
	for mesh in bench_preview.find_children("*","MeshInstance3D",true,false):
		mesh.material_override.albedo_color = Color(.25,.85,.65,.6) if valid else Color(1,.35,.25,.6)
	%PlacementText.text = "クリックしてベンチを置く（予算20）" if valid else "ここには置けません・広場の空いた地面を選ぶ"

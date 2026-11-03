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
	%RestButton.pressed.connect(func(): _answer(Sim.propose_rest(selected_id)))
	%GoalButton.pressed.connect(func(): _answer(Sim.support_goal(selected_id)))
	%MeetButton.pressed.connect(_meet)
	%AcceptOfferButton.pressed.connect(func(): _answer(Sim.confirm_offer(selected_id)))
	%SupportButton.pressed.connect(func(): _answer(Sim.propose_support(selected_id,partner.get_selected_metadata())))
	%ProjectButton.pressed.connect(func(): _answer(Sim.propose_project(selected_id,partner.get_selected_metadata())))
	%BenchButton.pressed.connect(func(): placement = not placement; _toast("広場の地面をクリックして、ベンチを置きます（共有予算20）" if placement else "配置を取り消しました"))
	%NowTab.pressed.connect(func(): detail_tab=0; _refresh_detail())
	%RelationsTab.pressed.connect(func(): detail_tab=1; _refresh_detail())
	%MemoriesTab.pressed.connect(func(): detail_tab=2; _refresh_detail())
	%LifeTab.pressed.connect(func(): detail_tab=3; _refresh_detail())
	Sim.town_changed.connect(_rebuild)
	Sim.chapter_reached.connect(func(): _open_journal(true))
	Sim.event_added.connect(func(_e): _refresh_events())
	_rebuild()
	_build_roster()
	_refresh_ui()
	title.visible = true
	pause_menu.visible = false
	%JournalScreen.visible = false
	%HUD.visible = false
	Sim.running = false

func _new_game() -> void:
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
	_select(selected_id)
	_toast("気になる住人を選び、暮らしを見てみましょう。Spaceで一時停止できます。" if Sim.running else "町の記録から、ここまでの時間を読み返せます。")
	if Sim.life.chapter_ready: _open_journal(true)

func _continue_game() -> void:
	if Sim.load_game():
		_start_play()
		_toast("保存した町の続きを開きました")
	else:
		_toast("保存データを読み込めませんでした")

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
	if is_node_ready():
		var preferred: String = partner.get_selected_metadata() if partner.item_count>0 else ""
		_build_roster()
		_update_partners(preferred)
		if not Sim.life.is_alive(Sim.person(selected_id)): following = false
		if selection_changed: _select(selected_id)
	_refresh_events()

func _build_roster() -> void:
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	for p in Sim.people:
		var button = Button.new()
		button.text = "%s\n%s" % [p.name,p.occupation]
		button.custom_minimum_size = Vector2(188,55)
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

func _update_partners(preferred: String = "") -> void:
	partner.clear()
	for p in Sim.people:
		if p.id != selected_id and Sim.life.is_alive(p):
			partner.add_item(p.name)
			partner.set_item_metadata(partner.item_count-1,p.id)
	for i in partner.item_count:
		if partner.get_item_metadata(i)==preferred: partner.select(i)

func _select(id: String) -> void:
	if Sim.person(id).is_empty(): return
	selected_id = id
	_update_partners(_initial_partner(id))
	var portrait_path := "res://game/assets/ui/portraits/%s.png"%id
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	else:
		var ids = ["nagisa","ryo","rin","osamu","fumi","maho","ritsu","aoi"]
		var index: int = ids.find(id)
		if index>=0:
			var atlas = AtlasTexture.new()
			atlas.atlas = load("res://game/assets/ui/residents.png")
			atlas.region = Rect2([30,240,440,615,840,1060,1280,1505][index],10,200,235)
			portrait.texture = atlas
		else: portrait.texture = null
	portrait.modulate = Color.WHITE if Sim.life.is_alive(Sim.person(id)) else Color(.65,.65,.65)
	if %HUD.has_method("reveal_person"): %HUD.reveal_person()
	_refresh_detail()

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
	if not typing and not title.visible and not pause_menu.visible and not %JournalScreen.visible:
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
	for p in Sim.people:
		if avatars.has(p.id):
			var actor = avatars[p.id]
			actor.update_state(p,delta,selected_id==p.id)
			_update_resident_name_label(actor,p.id)
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

func _unhandled_input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and (focused is LineEdit or focused is TextEdit):
		if event.pressed and event.keycode==KEY_ESCAPE: focused.release_focus()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if %JournalScreen.visible:
				_close_journal()
			elif placement:
				placement = false
			elif not title.visible:
				_close_menu() if pause_menu.visible else _open_menu()
		elif event.keycode == KEY_SPACE and not title.visible and not pause_menu.visible and not %JournalScreen.visible:
			_toggle_pause()
		elif event.keycode == KEY_V and not title.visible and not pause_menu.visible and not %JournalScreen.visible:
			_toggle_buildings()
	if title.visible or pause_menu.visible or %JournalScreen.visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(7,distance-2)
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

func _toggle_buildings() -> void:
	$Town.cutaway = not $Town.cutaway
	$Town.update_view(camera.global_position)
	%BuildingsButton.text = "建物：断面（V）" if $Town.cutaway else "建物：外観（V）"

func _toggle_follow() -> void:
	following = not following
	if following: distance = 10

func _set_speed(value: float) -> void:
	if not Sim.people.any(func(p): return Sim.life.is_alive(p)): return
	Sim.speed = value
	Sim.running = true
	_refresh_ui()

func _toggle_pause() -> void:
	if not Sim.people.any(func(p): return Sim.life.is_alive(p)): return
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

func _open_journal(chapter: bool) -> void:
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
	%PauseButton.text = "再開" if not Sim.running else "一時停止"
	%Budget.text = "共有予算  %d" % Sim.shared_budget
	%FollowButton.text = "追従中" if following else "この人を追う"
	%Version.text = "v0.6 開発版 · 個性と経験"
	var alive = Sim.life.is_alive(Sim.person(selected_id))
	var living_town = Sim.people.any(func(p): return Sim.life.is_alive(p))
	for action in [%PauseButton,%SpeedHalf,%Speed1,%Speed3,%Speed6,%Speed30]: action.disabled = not living_town
	for action in [%RestButton,%GoalButton,%FollowButton]: action.disabled = not alive
	for action in [%SupportButton,%ProjectButton,%MeetButton]: action.disabled = not alive or partner.item_count==0
	var offer = Sim.social.offer
	%OfferPanel.visible = not offer.is_empty() and offer.a==selected_id
	if %OfferPanel.visible:
		var place = {"bench":"広場のベンチ","cafe":"喫茶店","workshop":"工房"}.get(offer.location,"待ち合わせ場所")
		%OfferText.text = "%s · %sさんと\n%sで %d分ほど過ごす"%[Sim.social.when_text(offer.start),Sim.person(offer.b).name,place,offer.duration]
	if not title.visible:
		_refresh_detail()

func _refresh_detail() -> void:
	var p = Sim.person(selected_id)
	if p.is_empty():
		return
	%ResidentName.text = "%s  ·  %d歳" % [p.name,p.age]
	%Occupation.text = p.occupation
	%Activity.text = ("移動中 → " if p.moving else "")+Sim.ACTION_NAMES.get(p.action,p.action)
	var plan: Dictionary = p.get("cognition_plan",{})
	var plan_reason: String = plan.get("reason","")
	var active_plan: bool = plan.get("stage","") in ["travel","execute"]
	%Reason.text = "「%s」" % (plan_reason if active_plan and not plan_reason.is_empty() else p.reason)
	%NextPlan.text = _next_agreement_text(p)
	%Fatigue.value = p.fatigue*100
	%Hunger.value = p.hunger*100
	%Connection.value = p.connection*100
	for meter in [%Fatigue,%Hunger,%Connection]: meter.get_parent().visible = Sim.life.is_alive(p)
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
		text = "親しみ / 信頼\n\n"
		for other_id in p.relationships:
			var rel = p.relationships[other_id]
			text += "%s  %d / %d\n" % [Sim.person(other_id).name,int(rel.familiarity*100),int(rel.trust*100)]
		if p.relationships.is_empty():
			text += "これから知っていく人たちがいる。"
	elif detail_tab==2:
		text = "この人に残った出来事\n\n"
		for memory in p.memories.slice(maxi(0,p.memories.size()-5)):
			text += "・%s\n%s\n\n" % [memory.title,memory.text]
		if p.memories.is_empty():
			text += "町で過ごす時間が、これから積もっていく。"
	else:
		text = Sim.work_family.person_text(p)
		var personal: String = Sim.social.person_text(p)
		if not personal.is_empty(): text += "\n\n"+personal
		text += "\n\n"+("暮らしの背景\n\n" if p.alive else "大切にしていたこと\n\n")+Sim.definitions[p.id].public_private_difference+"\n\n暮らしの始まりに気にかけていたこと\n"+Sim.definitions[p.id].goals[1]
	%DetailText.text = text

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
	for e in Sim.events.slice(maxi(0,Sim.events.size()-3)):
		var who = Sim.person(e.resident_id).get("name","町") if not e.resident_id.is_empty() else "町"
		text += "%s  %s  ·  %s\n" % [e.clock,who,e.text]
	%EventText.text = text.strip_edges()

func _show_guide() -> void:
	info_dialog.title = "町を見守る操作"
	info_dialog.dialog_text = "町の人物や「住人」から選ぶと、その人の様子が見られます。\n\n右ドラッグ：カメラ回転　 ホイール：ズーム\nWASD：町を見渡す　 Space：一時停止　 Escape：メニュー\n\n相手を選んで、会話や共同制作を相談できます。\n住人は予定や疲れ、関心から返答し、自分から相談することもあります。\n実際に一緒に過ごした経験や教わったことが、その後の判断へ残ります。\n\n「この人を追う」で近くから見守れます。「住人」「人物」「履歴」で画面を畳めます。\n\n「ベンチを置く」から広場の地面をクリックすると、場所を整えられます。"
	info_dialog.popup_centered(Vector2i(700,430))

extends "res://game/foundation/house_preview.gd"

var occupancy: HomeOccupancy
var navigation: HomeNavigation
var household: HouseholdDay
var executor: FoundationLifeExecutor
var residents: Dictionary = {}
var running := true
var minutes_per_second := .5
var clock_label: Label
var pause_button: Button
var cards: Dictionary = {}
var followed := ""
var initialization_error := ""
var _ui_time := 0.0

func _show_overview() -> void:
	followed=""
	super._show_overview()

func _ready() -> void:
	super._ready()
	HomeArt.new().add_visuals(house)
	# The old town simulation is not a second source of time in this scene.
	if has_node("/root/Sim"):get_node("/root/Sim").set_process(false)
	occupancy=HomeOccupancy.new();navigation=HomeNavigation.new();household=HouseholdDay.new()
	if not occupancy.configure(house.definition) or not navigation.configure(house.definition) or not household.configure(house.definition,[],occupancy):
		initialization_error="住宅と家族の生活を読み込めませんでした";push_error(initialization_error);running=false;return
	for id in household.people:
		var actor:=FoundationResident.new();actor.name="Resident_"+id;add_child(actor)
		actor.global_position=household.people[id].position
		if not actor.load_resident(id):
			initialization_error=id+" の基盤モーションを読み込めませんでした";push_error(initialization_error);running=false;return
		var stride_speed: float=float(actor.motion_contract.clips.walk.authored_speed_mps)
		if not actor.configure({"walk_speed":stride_speed,"turn_speed":PI*.5}):initialization_error="身体制御を設定できませんでした";running=false;return
		residents[id]=actor
		var label:=Label3D.new();label.text=household.people[id].name;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y=actor.model.rest_height+.18;label.font_size=34;label.pixel_size=.004
		label.modulate=Color("fff5dd");label.outline_modulate=Color("413d3b");label.outline_size=7;actor.add_child(label)
	executor=FoundationLifeExecutor.new()
	if not executor.configure(house,household,occupancy,navigation,residents):initialization_error="生活動作を接続できませんでした";push_error(initialization_error);running=false;return
	_build_household_ui()

func _build_household_ui() -> void:
	var canvas:=CanvasLayer.new();canvas.name="HouseholdUI";add_child(canvas)
	var bar:=HBoxContainer.new();bar.position=Vector2(20,88);bar.add_theme_constant_override("separation",12);canvas.add_child(bar)
	clock_label=Label.new();clock_label.custom_minimum_size=Vector2(190,44);clock_label.add_theme_font_size_override("font_size",24);bar.add_child(clock_label)
	pause_button=Button.new();pause_button.text="一時停止";pause_button.custom_minimum_size=Vector2(120,44)
	pause_button.pressed.connect(func():running=not running;pause_button.text="一時停止" if running else "再開");bar.add_child(pause_button)
	var save_button:=Button.new();save_button.text="保存";save_button.custom_minimum_size=Vector2(85,44);save_button.pressed.connect(save_day);bar.add_child(save_button)
	var load_button:=Button.new();load_button.text="保存から再開";load_button.custom_minimum_size=Vector2(140,44);load_button.pressed.connect(load_day);bar.add_child(load_button)
	var row:=HBoxContainer.new();row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left=20;row.offset_top=-165;row.offset_right=790;row.offset_bottom=-20;row.add_theme_constant_override("separation",12);canvas.add_child(row)
	for id in residents:
		var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(240,140)
		var style:=StyleBoxFlat.new();style.bg_color=Color("f1e9d8");style.border_color=Color("9a8061")
		style.set_border_width_all(2);style.set_corner_radius_all(8)
		style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=10;style.content_margin_bottom=10
		panel.add_theme_stylebox_override("panel",style);row.add_child(panel)
		var column:=VBoxContainer.new();column.add_theme_constant_override("separation",6);panel.add_child(column)
		var name_button:=Button.new();name_button.text=household.people[id].name+"を見る";name_button.flat=true
		name_button.add_theme_color_override("font_color",Color("4e3c29"));name_button.add_theme_color_override("font_hover_color",Color("a35f2e"));name_button.add_theme_color_override("font_pressed_color",Color("805324"))
		name_button.pressed.connect(func():followed=id;distance=10);column.add_child(name_button)
		var action:=Label.new();action.text="暮らしを始める";action.add_theme_color_override("font_color",Color("3c3935"));column.add_child(action)
		var progress:=ProgressBar.new();progress.show_percentage=false;progress.custom_minimum_size.y=8;progress.max_value=1;column.add_child(progress)
		var detail:=Label.new();detail.add_theme_font_size_override("font_size",15);detail.add_theme_color_override("font_color",Color("655c50"));column.add_child(detail)
		cards[id]={"action":action,"progress":progress,"detail":detail}
	_update_household_ui()

func _process(delta: float) -> void:
	if not followed.is_empty() and residents.has(followed):target=target.lerp(residents[followed].global_position+Vector3(0,.5,0),minf(1,delta*4))
	super._process(delta)
	if executor==null:return
	if running:executor.step(minf(delta,.1),minf(delta,.1)*minutes_per_second)
	_ui_time+=delta
	if _ui_time>=.2:_ui_time=0;_update_household_ui()

func _update_household_ui() -> void:
	var minute: int=household.minute_of_day()
	clock_label.text="%d日目 %02d:%02d"%[1+int((household.start_minute+household.elapsed)/1440),minute/60,minute%60]
	for id in cards:
		var task: Dictionary=household.task_for(id)
		var entry: Dictionary=executor.execution[id]
		cards[id].action.text=task.get("label","次にすることを考える")
		cards[id].progress.value=float(task.get("phase_progress",0))/maxf(.001,float(task.get("phase_minutes",1)))
		var detail: String=task.get("phase_name","")
		if entry.state in ["wait","yield","door"]:detail=entry.reason
		elif entry.state=="walk":
			var destination: String=house.fixtures.get(task.get("fixture",""),{}).get("definition",{}).get("label","外" if task.get("room")=="outside" else "玄関")
			detail=destination+"へ向かっている"
		elif entry.state in ["align","settle"]:detail="支度中"
		cards[id].detail.text=detail

func snapshot_day() -> Dictionary:
	var bodies: Dictionary={}
	for id in residents:bodies[id]=residents[id].motion_state()
	var door_states: Dictionary={}
	for id in house.doors:door_states[id]=float(house.doors[id].get("open_fraction",1.0 if house.doors[id].opened else 0.0))
	return {"schema":2,"life":household.snapshot(),"bodies":bodies,"executor":executor.snapshot(),"doors":door_states}

func restore_day(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema")!=2 or not data.get("life") is Dictionary or not data.get("bodies") is Dictionary or data.bodies.size()!=residents.size() or not data.get("doors") is Dictionary or data.doors.size()!=house.doors.size():return false
	var probe_occupancy:=HomeOccupancy.new();var probe_life:=HouseholdDay.new()
	if not probe_occupancy.configure(house.definition) or not probe_life.configure(house.definition,[],probe_occupancy) or not probe_life.restore(data.life):return false
	if not executor.can_restore(data.get("executor"),probe_life):return false
	for id in residents:
		if not residents[id].can_restore_motion(data.bodies.get(id)):return false
		var at: Array=data.bodies[id].motor.position
		if Vector3(at[0],at[1],at[2]).distance_to(probe_life.people[id].position)>.00001:return false
	for id in house.doors:
		var value: Variant=data.doors.get(id)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>1:return false
		if house.doors[id].definition.kind=="opening" and value!=1:return false
	# All components have been checked in disposable state before the first
	# live mutation. Loading does not perform or finish a household action.
	household.restore(data.life)
	for id in residents:residents[id].restore_motion(data.bodies[id])
	executor.restore(data.executor,household)
	for id in house.doors:house.set_door_fraction(id,float(data.doors[id]))
	_update_household_ui()
	return true

func save_day() -> bool:
	# A staged write protects the last development save if writing is interrupted.
	# It never replaces an existing old-town save.
	var file:=FileAccess.open("user://foundation-day.json.tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(snapshot_day(),"\t"));file.flush()
	var saved: bool=file.get_error()==OK;file.close()
	if not saved:return false
	return DirAccess.rename_absolute("user://foundation-day.json.tmp","user://foundation-day.json")==OK

func load_day() -> bool:
	if not FileAccess.file_exists("user://foundation-day.json"):return false
	return restore_day(JSON.parse_string(FileAccess.get_file_as_string("user://foundation-day.json")))

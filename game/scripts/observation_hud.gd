class_name ObservationHUD
extends Control

@onready var residents_panel: Control = $ResidentsPanel
@onready var detail_panel: Control = $DetailPanel
@onready var actions_panel: Control = $SelectionPanel
@onready var roster_toggle: Button = %RosterToggle
@onready var detail_toggle: Button = %DetailToggle
@onready var history_toggle: Button = %HistoryToggle
@onready var speed_menu: MenuButton = %SpeedMenu
var history_open := false
const SPEEDS = [0.5,1,3,6,30]
const SPEED_LABELS = ["ゆっくり ×0.5", "ふつう ×1", "はやい ×3", "とてもはやい ×6", "年月を進める ×30"]

func _ready() -> void:
	roster_toggle.toggled.connect(_show_residents)
	detail_toggle.toggled.connect(_show_detail)
	history_toggle.toggled.connect(_show_history)
	%CloseRoster.pressed.connect(_show_residents.bind(false))
	%CloseDetail.pressed.connect(_show_detail.bind(false))
	%CloseHistory.pressed.connect(_show_history.bind(false))
	%BuildToggle.toggled.connect(_show_build)
	var popup := speed_menu.get_popup()
	for text in SPEED_LABELS: popup.add_radio_check_item(text)
	popup.id_pressed.connect(_choose_speed)
	resized.connect(_layout_panels)
	_show_residents(false);_show_detail(false);_show_history(false)
	_apply_icons()
	_layout_panels()

func _apply_icons() -> void:
	var names := {"RosterToggle":"residents","HistoryToggle":"history","JournalButton":"journal","MenuButton":"menu",
		"FollowButton":"follow","ProposeButton":"talk","DetailToggle":"journal","BuildToggle":"home","BenchButton":"home",
		"CloseRoster":"close","CloseDetail":"close","CloseHistory":"close"}
	for name in names:
		var button: Button = get_node("%"+name)
		button.icon = load("res://game/assets/ui/icons/"+names[name]+".svg")
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width",19)

func modal_open() -> bool:
	return %PauseMenu.visible or %JournalScreen.visible or %ProposalScreen.visible

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or modal_open(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or speed_menu.get_popup().visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_SPACE:
		if not %PauseButton.disabled:
			%PauseButton.pressed.emit()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var sim = get_node_or_null("/root/Sim")
	if sim==null: return
	var index := -1
	for candidate in SPEEDS.size():
		if is_equal_approx(float(SPEEDS[candidate]),float(sim.speed)): index = candidate;break
	speed_menu.text = (SPEED_LABELS[index] if index>=0 else "×%s"%sim.speed)+" ▾"
	for item in SPEEDS.size(): speed_menu.get_popup().set_item_checked(item,item==index)
	speed_menu.disabled = %Speed1.disabled
	%Toast.offset_top = 180 if $PlacementHint.visible else 100
	%Toast.offset_bottom = 248 if $PlacementHint.visible else 164
	%LatestEvent.visible = %LatestEvent.get_meta("has_event",false) and not detail_panel.visible and not history_open and not $BuildPanel.visible
	%TimeState.text = "提案中・時間を止めています" if %ProposalScreen.visible else ("時間が進んでいます" if sim.running else "時間を止めています")

func reveal_person() -> void:
	# A selection shows the short resident card; the notebook is a deliberate action.
	actions_panel.show()

func start_observing() -> void:
	_show_detail(false);_show_history(false);_show_build(false)
	_show_residents(true)

func _show_residents(open: bool) -> void:
	residents_panel.visible = open
	roster_toggle.set_pressed_no_signal(open)
	_layout_panels()

func _show_detail(open: bool) -> void:
	if open: _show_history(false);_show_build(false)
	detail_panel.visible = open
	detail_toggle.set_pressed_no_signal(open)
	$TownTools.visible = not open
	_layout_panels()

func _show_history(open: bool) -> void:
	if open: _show_detail(false);_show_build(false)
	history_open = open
	$HistoryPanel.visible = open
	history_toggle.set_pressed_no_signal(open)
	_layout_panels()

func _show_build(open: bool) -> void:
	if open: _show_detail(false);_show_history(false)
	$BuildPanel.visible = open
	%BuildToggle.set_pressed_no_signal(open)

func close_top_panel() -> bool:
	if detail_panel.visible: _show_detail(false);return true
	if history_open: _show_history(false);return true
	if $BuildPanel.visible: _show_build(false);return true
	if residents_panel.visible: _show_residents(false);return true
	return false

func _choose_speed(index: int) -> void:
	var names := ["SpeedHalf", "Speed1", "Speed3", "Speed6", "Speed30"]
	var button: Button = get_node("%"+names[index])
	if not button.disabled: button.pressed.emit()

func _layout_panels() -> void:
	if not is_node_ready(): return
	var small := size.x<1200
	var card_width := 352.0 if small else (400.0 if size.x<1360 else 446.0)
	%SpeedMenu.custom_minimum_size.x = 176 if small else 220
	%PauseButton.custom_minimum_size.x = 138 if small else 142
	%SpeedMenu.add_theme_font_size_override("font_size",14 if small else 16)
	%PauseButton.add_theme_font_size_override("font_size",14 if small else 16)
	$TimeDock.size.x = 368 if small else 424
	detail_panel.offset_bottom = -130 if small else -20
	actions_panel.offset_right = 20+card_width
	$TimeDock.position.x = maxf((size.x-$TimeDock.size.x)*.5,actions_panel.get_rect().end.x+12)
	residents_panel.offset_bottom = -290
	detail_panel.offset_left = -394.0 if size.x<1360 else -414.0
	$HistoryPanel.offset_bottom = minf(492,size.y-130)
	%Toast.offset_top = 180 if $PlacementHint.visible else 100
	%Toast.offset_bottom = 248 if $PlacementHint.visible else 164
	%Toast.offset_left = -280
	%Toast.offset_right = 280

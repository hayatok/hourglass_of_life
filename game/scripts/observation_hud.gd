class_name ObservationHUD
extends Control

@onready var residents_panel: Control = $ResidentsPanel
@onready var detail_panel: Control = $DetailPanel
@onready var actions_panel: Control = $ActionsPanel
@onready var roster_toggle: Button = %RosterToggle
@onready var detail_toggle: Button = %DetailToggle
@onready var history_toggle: Button = %HistoryToggle
@onready var speed_menu: MenuButton = %SpeedMenu

var history_open := false

func _ready() -> void:
	roster_toggle.toggled.connect(_show_residents)
	detail_toggle.toggled.connect(_show_detail)
	history_toggle.toggled.connect(_show_history)
	var popup := speed_menu.get_popup()
	for value in ["×0.5", "×1", "×3", "×6", "×30"]: popup.add_item(value)
	popup.id_pressed.connect(_choose_speed)
	resized.connect(_layout_panels)
	_show_residents(false)
	_show_detail(false)
	_show_history(false)
	_layout_panels()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or %PauseMenu.visible or %JournalScreen.visible: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or speed_menu.get_popup().visible: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_SPACE:
		if not %PauseButton.disabled:
			%PauseButton.pressed.emit()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var simulation = get_node_or_null("/root/Sim")
	if simulation!=null:
		speed_menu.text = "×%s ▾"%str(simulation.speed).trim_suffix(".0")
	speed_menu.disabled = %Speed1.disabled

func reveal_person() -> void:
	detail_toggle.set_pressed_no_signal(true)
	_show_detail(true)

func _show_residents(open: bool) -> void:
	residents_panel.visible = open
	roster_toggle.set_pressed_no_signal(open)
	_layout_panels()

func _show_detail(open: bool) -> void:
	detail_panel.visible = open
	detail_toggle.set_pressed_no_signal(open)
	_layout_panels()

func _show_history(open: bool) -> void:
	history_open = open
	%EventText.visible = open
	history_toggle.set_pressed_no_signal(open)
	_layout_panels()

func _choose_speed(index: int) -> void:
	var names := ["SpeedHalf", "Speed1", "Speed3", "Speed6", "Speed30"]
	var button: Button = get_node("%"+names[index])
	if not button.disabled: button.pressed.emit()

func _layout_panels() -> void:
	if not is_node_ready(): return
	var bottom := 185.0 if history_open else 77.0
	residents_panel.offset_bottom = -bottom
	detail_panel.offset_bottom = -bottom
	actions_panel.offset_top = -173.0 if history_open else -65.0
	detail_panel.offset_left = -334.0 if size.x>=1360 else -318.0
	%Toast.anchor_left = 0.0
	%Toast.anchor_right = 0.0
	%Toast.offset_left = 238.0 if residents_panel.visible else 18.0
	%Toast.offset_right = size.x-(350.0 if detail_panel.visible else 18.0)

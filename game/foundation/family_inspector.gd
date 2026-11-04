class_name FoundationFamilyInspector
extends PanelContainer

## Read-only view of a person's authored past, actual choices and lived events.
## Add beneath a CanvasLayer; refresh from the world's ordinary UI update loop.
signal closed

const INK := Color("473f32")
const MUTED := Color("75634b")
const RECENT_EVENTS := 8
const EVENT_TEXT := {
	"cook":"食事を作った。", "serve":"料理を食卓へ運んだ。", "eat":"食事をした。",
	"wash_dishes":"食器を洗った。", "laundry":"衣類を洗濯機に入れた。",
	"hang_laundry":"洗濯物を干した。", "fold_laundry":"乾いた衣類をたたんでしまった。",
	"hygiene":"顔と手を洗った。", "bath":"入浴して、着替えた。", "toilet":"トイレを使った。",
	"put_down":"運んでいた物を台へ置いた。", "quiet":"自分の時間を過ごした。",
	"care":"子どもと一緒に過ごした。", "family_time":"家族の誘いに応じて一緒に過ごした。",
	"work":"仕事に取り組んだ。", "school":"学校で過ごした。", "sleep":"寝床で休んだ。",
	"return_home":"家に帰った。", "wait_outside":"外出先で過ごした。",
	"shop":"食材を買い足した。", "tidy_tools":"使った道具を片付けた。"
}
const PROJECT_WORK := {
	"bread_notebook":"季節のパンの案をノートに書いた。",
	"design_draft":"受注の下書きを進めた。", "town_model":"町の模型を進めた。"
}
const PROJECT_RESULT := {
	"recipe_plan":"季節のパンの案がノートにまとまった。",
	"design_draft":"受注の下書きがまとまった。", "town_model":"町の模型を作り上げた。"
}

var selected_id := ""
var _day: HouseholdDay
var _heading: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _history_limit := RECENT_EVENTS
var _last_display: Dictionary = {}

func _init() -> void:
	visible=false
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_process_unhandled_key_input(true)

func _ready() -> void:
	_ensure_ui()
	if not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)
	_fit()

func configure(day: HouseholdDay) -> bool:
	if day==null: return false
	_day=day
	_ensure_ui()
	_last_display.clear()
	_fit()
	refresh()
	return true

func show_person(id: String) -> bool:
	if _day==null or not _day.people.has(id): return false
	_ensure_ui()
	if selected_id!=id:
		_history_limit=RECENT_EVENTS
		_scroll.scroll_vertical=0
		_last_display.clear()
	selected_id=id
	show()
	_fit()
	refresh()
	return true

func close_panel() -> void:
	if not visible: return
	hide()
	closed.emit()

func refresh() -> void:
	if not visible or _day==null or selected_id.is_empty(): return
	var person: Dictionary = _day.person(selected_id)
	if person.is_empty():
		close_panel()
		return
	var task: Dictionary = _day.task_for(selected_id)
	var biography: Dictionary = person.get("biography",{})
	var history: Dictionary = person.get("life_history",{})
	var project_states: Dictionary = {}
	for id in history.get("projects",{}):
		var progress: Dictionary = history.projects[id]
		var artifact: Dictionary = progress.get("artifact",{})
		project_states[id]={"begun":float(progress.get("minutes",0))>0,
			"completed":bool(progress.get("completed",false)),
			"artifact":artifact.duplicate(true)}
	# Store detached values: source dictionaries mutate in place during play.
	# Frame progress is deliberately absent because this panel never displays it.
	var display := {
		"name":person.get("name",""), "age":person.get("age",0),
		"task_label":task.get("label",""), "task_status":task.get("status",""),
		"phase":task.get("phase_name",""), "reason":task.get("reason",""),
		"choice":task.get("choice_reason",""), "project":biography.get("project",{}),
		"episodes":biography.get("episodes",[]), "projects":project_states,
		"observed":history.get("observed",[]), "limit":_history_limit,
		"start_minute":_day.start_minute
	}
	if display==_last_display: return
	_last_display=display.duplicate(true)
	_heading.text="%s　%d歳"%[str(display.name),int(display.age)]
	var previous_scroll := _scroll.scroll_vertical
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_build_current(display)
	_build_past(display.episodes)
	_build_observed(person,display.observed)
	_scroll.set_deferred("scroll_vertical",previous_scroll)

func _ensure_ui() -> void:
	if _body!=null: return
	var style := StyleBoxFlat.new()
	style.bg_color=Color("f4eddd")
	style.border_color=Color("9a8061")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left=16;style.content_margin_right=16
	style.content_margin_top=12;style.content_margin_bottom=14
	add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	column.mouse_filter=Control.MOUSE_FILTER_PASS
	add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",8)
	column.add_child(header)
	_heading=Label.new()
	_heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_heading.add_theme_font_size_override("font_size",21)
	_heading.add_theme_color_override("font_color",INK)
	_heading.mouse_filter=Control.MOUSE_FILTER_IGNORE
	header.add_child(_heading)
	var close := Button.new()
	close.text="×";close.tooltip_text="閉じる"
	close.custom_minimum_size=Vector2(34,34)
	close.flat=true
	close.add_theme_font_size_override("font_size",26)
	close.add_theme_color_override("font_color",INK)
	close.add_theme_color_override("font_hover_color",Color("a35f2e"))
	close.add_theme_color_override("font_pressed_color",Color("805324"))
	close.pressed.connect(close_panel)
	header.add_child(close)
	_scroll=ScrollContainer.new()
	_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus=true
	column.add_child(_scroll)
	_body=VBoxContainer.new()
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",12)
	_body.mouse_filter=Control.MOUSE_FILTER_PASS
	_scroll.add_child(_body)

func _build_current(display: Dictionary) -> void:
	_title("いま選んでいること")
	if str(display.task_label).is_empty():
		_paragraph("次にすることを考えている。")
	else:
		_paragraph(str(display.task_label))
		if not str(display.choice).is_empty(): _paragraph(str(display.choice),MUTED)
		# A requested task is only an intention; do not call walking/assignment work.
		if display.task_status=="blocked" and not str(display.reason).is_empty():
			_paragraph(str(display.reason),MUTED)
		elif display.task_status in ["arrived","working"] and not str(display.phase).is_empty():
			_paragraph(str(display.phase),MUTED)
	var project: Dictionary = display.project
	if project.is_empty(): return
	_gap()
	_title("取り組んでいること")
	_paragraph(str(project.get("label","自分の制作")))
	var progress: Dictionary = display.projects.get(project.get("id",""),{})
	if bool(progress.get("completed",false)) and not progress.get("artifact",{}).is_empty():
		_paragraph("ひとつの形にまとまった。",MUTED)
	elif bool(progress.get("begun",false)):
		_paragraph("少しずつ、手を動かして進めている。",MUTED)
	else:
		_paragraph("まだ、取りかかっていない。",MUTED)

func _build_past(episodes: Array) -> void:
	_gap()
	_title("物語が始まる前")
	if episodes.is_empty():
		_paragraph("まだ、この人の過去は語られていない。",MUTED)
	for episode in episodes:
		if not episode is Dictionary: continue
		var when := str(episode.get("when",""))
		if not when.is_empty(): _paragraph(when,MUTED,15)
		_paragraph(str(episode.get("summary","")))

func _build_observed(person: Dictionary, events: Array) -> void:
	_gap()
	_title("物語が始まってから")
	if events.is_empty():
		_paragraph("まだ、新しい出来事はない。",MUTED)
		return
	var first := maxi(0,events.size()-_history_limit)
	for index in range(events.size()-1,first-1,-1):
		var event: Dictionary = events[index]
		_paragraph(_event_time(float(event.get("at",0))),MUTED,15)
		_paragraph(_event_text(person,event))
	if first>0:
		var more := Button.new()
		more.text="前の出来事を読む"
		more.flat=true
		more.custom_minimum_size.y=38
		more.add_theme_font_size_override("font_size",16)
		more.add_theme_color_override("font_color",INK)
		more.add_theme_color_override("font_hover_color",Color("a35f2e"))
		more.add_theme_color_override("font_pressed_color",Color("805324"))
		more.pressed.connect(func():
			_history_limit+=RECENT_EVENTS
			refresh()
		)
		_body.add_child(more)

func _event_text(person: Dictionary, event: Dictionary) -> String:
	if event.get("status","")=="declined_family_invitation":
		# This event records a choice, not performed work, even if its task finishes later.
		return "家族の誘いをいったん見送った。"
	if event.get("status","")!="completed": return "暮らしの中で、新しい経験をした。"
	var kind := str(event.get("kind",""))
	if kind!="personal_project": return str(EVENT_TEXT.get(kind,"家での用事を一区切り進めた。"))
	var progress: Dictionary = person.get("life_history",{}).get("projects",{}).get(event.get("project_id",""),{})
	var artifact: Dictionary = progress.get("artifact",{})
	# A finished 15-minute task is not necessarily a finished project. Match the
	# actual artifact creation time to this particular performed event.
	if bool(progress.get("completed",false)) and not artifact.is_empty() \
		and artifact.get("source_project","")==event.get("project_id","") \
		and absf(float(artifact.get("completed_at",-1))-float(event.get("at",0)))<.001:
		return str(PROJECT_RESULT.get(artifact.get("kind",""),"自分の制作が、ひとつの形になった。"))
	return str(PROJECT_WORK.get(event.get("activity",""),"自分の制作を進めた。"))

func _event_time(at: float) -> String:
	var absolute := _day.start_minute+int(floor(at))
	var minute := posmod(absolute,1440)
	return "%d日目 %02d:%02d"%[1+int(floor(float(absolute)/1440.0)),int(minute/60),minute%60]

func _title(text: String) -> void:
	_paragraph(text,INK,18)

func _paragraph(text: String, color: Color=INK, font_size: int=17) -> void:
	if text.is_empty(): return
	var label := Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.add_theme_constant_override("line_spacing",4)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_body.add_child(label)

func _gap() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y=4
	spacer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_body.add_child(spacer)

func _fit() -> void:
	if not is_inside_tree(): return
	var viewport_size := get_viewport_rect().size
	var panel_width := minf(330,maxf(240,viewport_size.x-40))
	position=Vector2(viewport_size.x-panel_width-20,150)
	size=Vector2(panel_width,maxf(160,viewport_size.y-150-185))

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()

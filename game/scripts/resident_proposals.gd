class_name ResidentProposals
extends Control

const Portraits = preload("res://game/scripts/resident_portraits.gd")

signal answered(reply: Dictionary)
signal closed

@onready var partner: OptionButton = %Partner
@onready var dialog: PanelContainer = $Dialog
@onready var sim = get_node("/root/Sim")
var resident_id := ""
var proposal_kind := ""
var running_before_open := false
var owns_pause := false
var offered_pair := {}

func _ready() -> void:
	hide()
	%Close.pressed.connect(close_panel)
	%Done.pressed.connect(close_panel)
	%Back.pressed.connect(_show_choices)
	%Rest.pressed.connect(_execute.bind("rest"))
	%Goal.pressed.connect(_execute.bind("goal"))
	%Meet.pressed.connect(_choose_partner.bind("meet"))
	%Support.pressed.connect(_choose_partner.bind("support"))
	%Project.pressed.connect(_choose_partner.bind("project"))
	%Execute.pressed.connect(_execute_selected)
	%ConfirmOffer.pressed.connect(_confirm_offer)
	partner.item_selected.connect(func(_index): sync_partner_preview())
	%Close.focus_previous = %Close.get_path_to(%Done)
	%Done.focus_next = %Done.get_path_to(%Close)
	get_viewport().size_changed.connect(_fit_dialog)
	_fit_dialog()

func open_for(id: String) -> void:
	if not owns_pause:
		running_before_open = sim.running
		owns_pause = true
	sim.running = false
	var preferred := _partner_id()
	var changed := resident_id!=id
	resident_id = id
	if changed: _refresh_partners(preferred)
	%Title.text = "%sに提案する"%_name(id)
	show();_fit_dialog()
	_show_choices()
	if not _alive(id):
		_present_reply({"status":"decline","text":"この住民へは今は提案できません。","resident_id":id})
	else:
		var offer: Dictionary = sim.social.offer
		if not offer.is_empty() and offer.get("a","")==id and _alive(offer.get("b","")):
			proposal_kind = "meet"
			_select_partner(str(offer.b))
			_present_reply({"status":"counteroffer","text":"相談した日時の別案があります。","resident_id":id})
	%Close.grab_focus()

func close_panel() -> void:
	if not visible and not owns_pause: return
	partner.get_popup().hide()
	hide()
	_restore_running()
	closed.emit()

func _restore_running() -> void:
	if owns_pause and is_instance_valid(sim): sim.running = running_before_open
	owns_pause = false

func _exit_tree() -> void:
	_restore_running()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:
			get_viewport().set_input_as_handled();close_panel()

func _gui_input(_event: InputEvent) -> void:
	accept_event()

func _unhandled_input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()

func _fit_dialog() -> void:
	if not is_instance_valid(dialog): return
	var viewport := get_viewport_rect().size
	dialog.custom_minimum_size = Vector2.ZERO
	dialog.size = Vector2(minf(640,viewport.x-32),minf(660,viewport.y-32))
	dialog.position = (viewport-dialog.size)*.5
	_fit_partner_popup()

func _fit_partner_popup() -> void:
	if not is_instance_valid(partner): return
	var viewport := get_viewport_rect().size
	partner.get_popup().max_size = Vector2i(maxi(1,int(viewport.x-32)),maxi(1,mini(420,int(viewport.y-32))))

func _show_choices() -> void:
	proposal_kind = ""
	offered_pair = {}
	%Choices.show();%Target.hide();%Result.hide();%Back.hide()
	%Done.text = "町に戻る"
	%Done.theme_type_variation = &"QuietButton"
	%Rest.disabled = not _alive(resident_id)
	%Goal.disabled = not _alive(resident_id)
	for button in [%Meet,%Support,%Project]: button.disabled = not _alive(resident_id) or partner.item_count==0
	%Rest.grab_focus()

func _choose_partner(kind: String) -> void:
	proposal_kind = kind
	%Choices.hide();%Result.hide();%Target.show();%Back.show()
	%Back.text = "提案を選び直す"
	%Done.theme_type_variation = &"QuietButton"
	sync_partner_preview()
	partner.grab_focus()

func choose_kind(kind: String) -> void:
	if kind in ["rest","goal"]: _execute(kind)
	elif kind in ["meet","support","project"]: _choose_partner(kind)

func submit() -> void:
	_execute_selected()

func accept_offer() -> void:
	_confirm_offer()

func _refresh_partners(preferred: String) -> void:
	partner.clear()
	for person in sim.people:
		if person.id==resident_id or not sim.life.is_alive(person): continue
		partner.add_item(person.name)
		partner.set_item_metadata(partner.item_count-1,person.id)
	_select_partner(preferred)

func _select_partner(id: String) -> void:
	for index in partner.item_count:
		if str(partner.get_item_metadata(index))==id:
			partner.select(index);break
	sync_partner_preview()

func _partner_id() -> String:
	if not is_instance_valid(partner) or partner.selected<0 or partner.selected>=partner.item_count: return ""
	var metadata = partner.get_item_metadata(partner.selected)
	return str(metadata) if metadata!=null else ""

func sync_partner_preview() -> void:
	if not is_node_ready(): return
	var other := _partner_id()
	var who := _name(resident_id)
	var with_who := _name(other)
	var helping := proposal_kind=="support"
	%ResidentPortrait.texture = _portrait(other if helping else resident_id)
	%PartnerPortrait.texture = _portrait(resident_id if helping else other)
	%FirstName.text = with_who if helping else who
	%SecondName.text = who if helping else with_who
	%TargetHeading.text = {"meet":"%sさんを、誰との会話に誘いますか？"%who,
		"support":"誰に、%sさんの手助けを頼みますか？"%who,
		"project":"%sさんと、誰が一緒に制作しますか？"%who}.get(proposal_kind,"")
	%PairDirection.text = "手伝う →" if helping else ("会話" if proposal_kind=="meet" else "一緒に制作")
	%Execute.text = {"meet":"%sさんと%sさんを会話に誘う"%[who,with_who],
		"support":"%sさんに、%sさんの手助けを頼む"%[with_who,who],
		"project":"%sさんと%sさんに制作を提案する"%[who,with_who]}.get(proposal_kind,"提案する")
	%Execute.disabled = not _alive(resident_id) or not _alive(other) or resident_id==other
	%NoPartner.visible = partner.item_count==0
	partner.add_theme_constant_override("icon_max_width",30)
	var popup := partner.get_popup()
	for index in partner.item_count:
		partner.set_item_icon(index,_portrait(str(partner.get_item_metadata(index))))
		popup.set_item_icon_max_width(index,32)
	_fit_partner_popup()

func _execute_selected() -> void:
	_execute(proposal_kind)

func _execute(kind: String) -> void:
	if not owns_pause or not _alive(resident_id): return
	proposal_kind = kind
	var other := _partner_id()
	var reply: Dictionary
	match kind:
		"rest": reply = sim.propose_rest(resident_id)
		"goal": reply = sim.support_goal(resident_id)
		"meet": reply = sim.propose_meeting(resident_id,other,"bench")
		"support": reply = sim.propose_support(resident_id,other)
		"project": reply = sim.propose_project(resident_id,other)
		_: return
	_present_reply(reply)
	answered.emit(reply)

func _present_reply(reply: Dictionary) -> void:
	%Choices.hide();%Target.hide();%Result.show();%Back.show()
	%Back.text = "別の提案をする"
	%Done.text = "町に戻る"
	%Done.theme_type_variation = &"PrimaryButton"
	var speaker: String = str(reply.get("resident_id",resident_id))
	%ReplyPortrait.texture = _portrait(speaker)
	%ReplyName.text = _name(speaker)
	%ReplyHeading.text = {"accept":"受け入れました","decline":"今回は辞退しました","defer":"今は保留にしました","counteroffer":"別の案・希望があります"}.get(reply.get("status",""),"返事が届きました")
	%ReplyText.text = str(reply.get("text",""))
	offered_pair = {}
	var offer: Dictionary = sim.social.offer
	if proposal_kind=="meet" and reply.get("status","")=="counteroffer" and offer.get("a","")==resident_id and offer.get("b","")==_partner_id():
		offered_pair = offer.duplicate(true)
	%OfferDetails.visible = not offered_pair.is_empty()
	if not offered_pair.is_empty():
		%OfferWhen.text = "%s · %d分"%[sim.social.when_text(int(offered_pair.start)),int(offered_pair.duration)]
		%OfferWho.text = "%sさんと%sさん"%[_name(str(offered_pair.a)),_name(str(offered_pair.b))]
		%OfferWhere.text = {"bench":"広場のベンチ","cafe":"喫茶店","workshop":"工房"}.get(offered_pair.location,"待ち合わせ場所")
	%Done.grab_focus()

func _confirm_offer() -> void:
	if offered_pair.is_empty() or not owns_pause or not %OfferDetails.visible: return
	var reply: Dictionary = sim.confirm_offer(resident_id)
	_present_reply(reply)
	answered.emit(reply)

func _alive(id: String) -> bool:
	var person: Dictionary = sim.person(id)
	return not person.is_empty() and sim.life.is_alive(person)

func _name(id: String) -> String:
	return str(sim.person(id).get("name","住民"))

func _portrait(id: String) -> Texture2D:
	return Portraits.texture(id)

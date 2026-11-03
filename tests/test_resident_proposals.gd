extends SceneTree

const OUT = "res://docs/verification/ui-rebuild"
var sim
var direct
var panel
var checks := 0
var failures: Array[String] = []
var replies: Array = []
var closed_count := 0
var background_presses := 0
var report := {"scope":"Proposal modal over real seed-711 twelve-person simulation. Direct API calls on an independent identical world establish expected arguments/results; no needs, actions, relationships or replies are fabricated.","scenarios":[],"artifacts":[]}

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message);push_error(message)

func snapshot(world) -> Dictionary:
	return world._encode({"people":world.people,"elapsed":world.elapsed,"rng":str(world.rng.state),
		"events":world.events,"meetings":world.meetings,"event_serial":world.event_serial,"meeting_serial":world.meeting_serial,
		"social":world.social.serialize(),"agenda":world.agenda.serialize(),"work":world.work_family.serialize(),"life":world.life.serialize()}).duplicate(true)

func fresh(id: String, other: String, running: bool = true) -> void:
	panel.close_panel()
	sim.reset(711,12);sim.set_process(false);sim.running = running
	direct.reset(711,12);direct.set_process(false);direct.running = false
	replies.clear()
	panel.partner.clear()
	for person in sim.people:
		if person.id==id or not sim.life.is_alive(person): continue
		panel.partner.add_item(person.name)
		panel.partner.set_item_metadata(panel.partner.item_count-1,person.id)
	select_partner(other)
	panel.open_for(id)
	await process_frame

func select_partner(id: String) -> void:
	for index in panel.partner.item_count:
		if panel.partner.get_item_metadata(index)==id:
			panel.partner.select(index)
			panel.partner.item_selected.emit(index)
			break

func input_key(viewport: Viewport, code: Key, pressed: bool) -> void:
	var event := InputEventKey.new();event.keycode = code;event.physical_keycode = code;event.pressed = pressed
	if viewport is Window:
		event.window_id = viewport.get_window_id()
		Input.parse_input_event(event)
	else: viewport.push_input(event)

func internal_nodes(node: Node, type: String) -> Array:
	var found: Array = []
	for child in node.get_children(true):
		if child.is_class(type): found.append(child)
		found.append_array(internal_nodes(child,type))
	return found

func verify_partner_popup() -> void:
	await fresh("tomo","haru")
	panel.choose_kind("support")
	var before := snapshot(sim)
	panel.partner.grab_focus()
	input_key(root,KEY_SPACE,true)
	await process_frame
	input_key(root,KEY_SPACE,false)
	await process_frame;await process_frame
	var popup: PopupMenu = panel.partner.get_popup()
	expect(popup.visible,"Keyboard activation of the actual OptionButton opens its PopupMenu")
	expect(popup.item_count==11,"The opened partner menu contains all eleven other living residents")
	var scrolls := internal_nodes(popup,"ScrollContainer")
	var content_height := 0.0
	var scrolling := false
	if not scrolls.is_empty():
		var scroll: ScrollContainer = scrolls[0]
		content_height = scroll.get_v_scroll_bar().max_value
		scrolling = scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page
	var popup_position := popup.position if root.gui_embed_subwindows else popup.position-root.position
	var rect := Rect2(Vector2(popup_position),Vector2(popup.size))
	expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect) and popup.size.y<=420,"The actual popup remains within the viewport and its scroll-height limit")
	expect(content_height>0 and content_height/11.0<=64,"The opened menu's real content has compact portrait rows, not original 200-pixel portrait heights")
	var expected: String = str(panel.partner.get_item_metadata(10))
	popup.set_focused_item(10);popup.scroll_to_item(10)
	await process_frame;await process_frame
	report.partner_popup = {"items":popup.item_count,"position":sim._encode(Vector2(popup_position)),
		"size":sim._encode(Vector2(popup.size)),"content_height":content_height,"mean_row_height":content_height/11.0,"scroll_available":scrolling,
		"selected_before":"haru","last_item":expected,"native_window":not root.gui_embed_subwindows,"opened_by":"Space on focused OptionButton"}
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image() if root.gui_embed_subwindows else popup.get_texture().get_image()
		var error: int = image.save_png(OUT+"/proposal-partner-popup.png")
		report.artifacts.append({"file":"proposal-partner-popup.png","saved":error==OK,"error":error,"surface":"Actual open PopupMenu; parent viewport when embedded, popup viewport when native"})
	input_key(popup,KEY_ENTER,true)
	input_key(popup,KEY_ENTER,false)
	await process_frame
	expect(panel.partner.get_selected_metadata()==expected and not popup.visible,"The last resident remains reachable through the popup and can be selected through its GUI input")
	expect(snapshot(sim)==before and replies.is_empty(),"Opening, scrolling and choosing a popup partner never submits a proposal")
	panel.close_panel()

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame;await RenderingServer.frame_post_draw
	var error: int = root.get_texture().get_image().save_png(OUT+"/"+name+".png")
	report.artifacts.append({"file":name+".png","saved":error==OK,"error":error})

func verify_direct(kind: String, receiver: String, other: String) -> void:
	await fresh(receiver,other)
	var before := snapshot(sim)
	panel.choose_kind(kind)
	if kind in ["meet","support","project"]:
		expect(panel.get_node("%Target").visible and not panel.get_node("%Result").visible,kind+": choosing the action opens target confirmation")
		expect(snapshot(sim)==before and replies.is_empty(),kind+": selecting an action does not execute the simulation request")
		select_partner(other)
		expect(snapshot(sim)==before and replies.is_empty(),kind+": changing the partner only changes the preview")
		if kind=="support":
			expect(panel.get_node("%FirstName").text==sim.person(other).name and panel.get_node("%SecondName").text==sim.person(receiver).name,"Support preview puts the actual helper before the receiver")
		await capture("proposal-"+kind+"-confirm")
		panel.submit()
	var expected: Dictionary
	match kind:
		"rest": expected = direct.propose_rest(receiver)
		"goal": expected = direct.support_goal(receiver)
		"meet": expected = direct.propose_meeting(receiver,other,"bench")
		"support": expected = direct.propose_support(receiver,other)
		"project": expected = direct.propose_project(receiver,other)
	expect(replies.size()==1 and replies[-1]==expected,kind+": the modal returns the same actual answer as the real API with the intended IDs")
	expect(snapshot(sim)==snapshot(direct),kind+": the actual world effect matches the real API call, including participant direction")
	expect(panel.get_node("%Result").visible and panel.get_node("%ReplyText").text==expected.text,kind+": the actual reply is shown inside the modal")
	expect(not sim.running and panel.visible,kind+": the result stays paused and readable until the player closes it")
	report.scenarios.append({"kind":kind,"resident":receiver,"partner":other,"reply":expected})
	await capture("proposal-"+kind+"-result")
	panel.close_panel()
	expect(sim.running and not panel.visible,kind+": closing restores the original running state")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,800);root.content_scale_size = Vector2i(1280,800)
	sim = root.get_node("Sim");sim.set_process(false)
	direct = load("res://game/scripts/simulation.gd").new();root.add_child(direct);direct.set_process(false)
	var background := Button.new();background.text = "background";root.add_child(background)
	background.pressed.connect(func(): background_presses += 1)
	panel = load("res://game/scenes/ui/resident_proposals.tscn").instantiate();root.add_child(panel)
	panel.answered.connect(func(reply): replies.append(reply.duplicate(true)))
	panel.closed.connect(func(): closed_count += 1)
	await fresh("tomo","yui")
	expect(panel.visible and not sim.running and not paused,"Opening the modal pauses the simulation without pausing the SceneTree")
	expect(panel.partner.get_selected_metadata()=="yui","Opening preserves the main screen's preferred partner")
	expect("森 智" in panel.get_node("%Title").text,"The dialog states whose proposals are being considered")
	var unchanged := snapshot(sim)
	expect(panel.get_node("%Done").theme_type_variation==&"QuietButton","Returning to town is visually quiet on the choice page")
	panel.choose_kind("project");select_partner("haru")
	expect(panel.get_node("%Done").theme_type_variation==&"QuietButton","Returning to town stays quiet beside the explicit proposal-submit button")
	expect(snapshot(sim)==unchanged and replies.is_empty(),"Partner selection and target preview alone have no world side effect")
	panel.get_node("%Back").pressed.emit()
	expect(panel.get_node("%Choices").visible and snapshot(sim)==unchanged,"Back returns to five choices without sending a proposal")
	await capture("proposal-five-choices")
	panel.close_panel()
	expect(snapshot(sim)==unchanged and sim.running,"Cancel restores time while leaving the actual world unchanged")
	await fresh("saki","haru",false)
	panel.open_for("saki");panel.close_panel()
	expect(not sim.running,"Reopening an already open modal does not replace the original paused state")
	await fresh("tomo","yui")
	var escape := InputEventKey.new();escape.keycode = KEY_ESCAPE;escape.pressed = true
	panel._input(escape)
	expect(not panel.visible and sim.running,"Escape closes the modal and restores its saved running state")
	for row in [["rest","tomo","yui"],["goal","saki","haru"],["meet","tomo","yui"],["support","tomo","osamu"],["project","tomo","yui"]]:
		await verify_direct(row[0],row[1],row[2])
	expect(panel.get_node("%Done").theme_type_variation==&"PrimaryButton","Returning to town becomes the primary action after a reply")
	await verify_partner_popup()
	await fresh("tomo","yui")
	panel.choose_kind("meet");panel.submit()
	expect(sim.social.offer.get("a","")=="tomo" and sim.social.offer.get("b","")=="yui","The natural initial schedules produce a real dated counteroffer for the chosen pair")
	expect(panel.get_node("%OfferDetails").visible and panel.get_node("%Done").theme_type_variation==&"QuietButton" and panel.get_node("%Done").text=="保留して戻る" and not panel.get_node("%OfferWhen").text.is_empty() and not panel.get_node("%OfferWhere").text.is_empty(),"A real counteroffer shows time, location and the actual two people")
	await capture("proposal-counteroffer")
	var appointment_count: int = sim.social.appointments.size()
	panel.accept_offer()
	await capture("proposal-counteroffer-accepted")
	expect(sim.social.appointments.size()==appointment_count+1 and sim.social.appointments[-1].a=="tomo" and sim.social.appointments[-1].b=="yui","Accepting that time creates the actual appointment for the displayed pair")
	expect(replies[-1].status=="accept" and not panel.get_node("%OfferDetails").visible,"Accepted alternatives update the reply and remove the obsolete confirmation")
	panel.get_node("%Done").grab_focus()
	var space := InputEventKey.new();space.keycode = KEY_SPACE;space.physical_keycode = KEY_SPACE;space.pressed = true
	Input.parse_input_event(space);await process_frame
	var release := InputEventKey.new();release.keycode = KEY_SPACE;release.physical_keycode = KEY_SPACE;release.pressed = false
	Input.parse_input_event(release);await process_frame
	expect(background_presses==0 and not panel.visible and sim.running,"Space activates the modal button and restores time without activating the background button")
	expect(panel.get_node("%Done").focus_next==panel.get_node("%Done").get_path_to(panel.get_node("%Close")) and panel.get_node("%Close").focus_previous==panel.get_node("%Close").get_path_to(panel.get_node("%Done")),"Tab and reverse Tab wrap within the modal boundary")
	panel.close_panel()
	report.checks = checks;report.failures = failures;report.renderer = DisplayServer.get_name()
	var filename := "proposals-headless.json" if DisplayServer.get_name()=="headless" else "proposals-gpu.json"
	var file := FileAccess.open(OUT+"/"+filename,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Resident proposal UI checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	panel.free();direct.free();background.free()
	quit(0 if failures.is_empty() else 1)

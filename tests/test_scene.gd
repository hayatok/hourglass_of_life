extends SceneTree

var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)

func capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/verification/v0.5/integration"))
	var path = "res://docs/verification/v0.5/integration/"+filename+".png"
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.size = Vector2i(1440,900)
	var main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	expect(main.get_node("%TitleScreen").visible,"Title screen is shown on boot")
	expect(not main.get_node("%HUD").visible,"The observation HUD starts hidden")
	await capture("01-title")
	main.get_node("%StartButton").pressed.emit()
	await process_frame
	await process_frame
	var sim = root.get_node("Sim")
	sim.running = false
	expect(main.get_node("Residents").get_child_count()==8,"Eight real 3D actors are instantiated")
	expect(main.get_node("%Roster").get_child_count()==8,"The roster contains eight clickable residents")
	expect(main.get_node("%HUD").visible,"Starting reveals the observation HUD")
	var a = main.avatars.aoi
	var player = a.get_node("AnimationPlayer")
	expect(player.has_animation("walk") and player.has_animation("sit_talk"),"Walking and seated interaction clips are saved resources")
	player.play("walk")
	player.seek(.1,true)
	var leg = a.get_node("Visual/Hips/LeftLeg")
	expect(absf(leg.rotation.x)>.1,"Walking animation changes a real limb transform")
	main.get_node("%FollowButton").pressed.emit()
	expect(main.following,"The camera follow button changes the observation mode")
	main.get_node("%MenuButton").pressed.emit()
	expect(main.get_node("%PauseMenu").visible and not sim.running,"Menu pauses simulation")
	main.get_node("%ResumeButton").pressed.emit()
	expect(not sim.running,"Leaving the menu preserves an existing pause")
	main.following = false
	main.camera_target = Vector3.ZERO
	main._select("aoi")
	var reply = sim.propose_meeting("aoi","fumi")
	expect(reply.status=="accept","The visible example meeting can be accepted")
	var limit = 0
	while sim.meetings.size()>0 and sim.meetings[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	expect(sim.meetings.size()>0 and sim.meetings[0].state=="engaged","Actors meet before playing their conversation pose")
	for p in sim.people:
		main.avatars[p.id].update_state(p,1,p.id==main.selected_id)
	main._refresh_ui()
	await capture("02-conversation")
	expect(main.avatars.aoi.animation_name=="sit_talk","An actual seated meeting selects the seated animation")
	sim.advance_minutes(25)
	main.detail_tab = 2
	main._refresh_detail()
	expect("佐伯 文" in main.get_node("%DetailText").text,"The memory tab shows the completed shared experience")
	await capture("03-memory")
	sim.reset()
	sim.running = false
	await process_frame
	await process_frame
	main._select("maho")
	main.detail_tab = 0
	var partner = main.get_node("%Partner")
	for i in partner.item_count:
		if partner.get_item_metadata(i)=="fumi": partner.select(i)
	main.get_node("%MeetButton").pressed.emit()
	main._refresh_ui()
	expect(main.get_node("%OfferPanel").visible,"A concrete counteroffer is actionable in the observation UI")
	await capture("04-counteroffer")
	main.get_node("%AcceptOfferButton").pressed.emit()
	main._refresh_ui()
	expect(sim.social.appointments.size()==1 and not main.get_node("%OfferPanel").visible,"Confirming the displayed alternative records the appointment")
	expect("約束" in main.get_node("%DetailText").text,"A resident's upcoming promise is visible in their own panel")
	await capture("05-appointment")
	sim.reset()
	sim.running = false
	await process_frame
	await process_frame
	main._select("aoi")
	main.get_node("%ProjectButton").pressed.emit()
	expect(not sim.meetings.is_empty() and sim.meetings[0].get("mode","")=="project","The action bar can start actual joint work")
	limit = 0
	while sim.meetings.size()>0 and sim.meetings[0].state=="travel" and limit<180:
		sim.advance_minutes(1)
		limit += 1
	for p in sim.people: main.avatars[p.id].update_state(p,1,p.id==main.selected_id)
	expect(main.avatars.aoi.animation_name=="work","Joint work plays the work animation after arrival")
	main.get_node("%LifeTab").pressed.emit()
	main._refresh_ui()
	expect("生活費" in main.get_node("%DetailText").text,"The household panel explains the resident's living conditions")
	await capture("06-shared-work")
	sim.advance_minutes(45)
	main._refresh_ui()
	expect(sim.person("aoi").goal_progress>=.18,"Finishing shared work is reflected in the visible character goal")
	await capture("07-household")
	sim.reset()
	sim.running = false
	for day in range(36):
		sim.advance_minutes(1440,true)
		await process_frame
	main._refresh_ui()
	expect(main.get_node("%JournalScreen").visible and sim.life.chapter_ready,"Three years opens the actual review UI")
	expect("最初の三年" in main.get_node("%JournalHeading").text,"The review identifies the time that was played")
	await capture("08-three-years")
	main.get_node("%JournalContinueButton").pressed.emit()
	expect(sim.life.chapter_acknowledged and not main.get_node("%JournalScreen").visible,"The player can return to the continuing town")
	sim.running = false
	main._select("aoi")
	main.get_node("%LifeTab").pressed.emit()
	main._refresh_ui()
	expect("葵の新しい暮らし" in main.get_node("%DetailText").text,"A move is reflected in the actual household panel")
	expect(main.get_node("LegacyRecords").get_child_count()==sim.life.legacy.size() and not sim.life.legacy.is_empty(),"Records from actual achievements exist as 3D scene objects")
	await capture("09-changed-town")
	for year in range(4,89):
		sim.advance_minutes(maxi(0,year*12*1440-sim.start_minute-sim.elapsed),true)
		await process_frame
		if sim.life.chapter_ready and sim.life.chapter_mode=="last": break
	await process_frame
	main._refresh_ui()
	expect(main.get_node("%JournalScreen").visible and "町に残った時間" in main.get_node("%JournalHeading").text,"The complete lives reach the actual final review screen")
	expect(main.get_node("%Partner").item_count==0,"Absent residents are no longer offered as live partners")
	expect(main.get_node("Residents").get_children().all(func(actor): return not actor.visible),"Remembered people do not remain as living actors in the town")
	await capture("10-final-review")
	main.get_node("%JournalContinueButton").pressed.emit()
	expect(not sim.running and sim.life.final_reviewed,"Returning to the record-only town keeps its clock at rest")
	main._start_play()
	expect(not sim.running,"Opening a completed town does not restart an empty life simulation")
	print("Scene/UI smoke: %s"%("PASS" if errors.is_empty() else "FAIL"))
	quit(0 if errors.is_empty() else 1)

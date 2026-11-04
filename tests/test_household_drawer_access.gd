extends SceneTree

# Controlled arrival at the actual canonical fridge; afterwards the real
# motor, imported rig/Skin, moving hardware and fresh contact gates operate.
# This is not natural task selection or a full autonomous family-day test.
const Access = preload("res://game/foundation/household_drawer_access.gd")
const Fixtures = preload("res://game/foundation/household_kitchen_fixtures.gd")
var checks: int=0
var failures: Array[String]=[]
var observations: Dictionary={}
var home: LivingHouse
var day: HouseholdDay
var actor: FoundationResident
var hardware: HouseholdKitchenFixtures
var access
var nav: HomeNavigation
var occupancy: HomeOccupancy
var saved: Dictionary={}
var who := "nagisa"
var camera: Camera3D
var captures: Dictionary={}

func _initialize() -> void:
	create_timer(35).timeout.connect(func():push_error("Actual drawer fixture timed out");quit(1))
	call_deferred("run")
func expect(value: bool, reason: String) -> bool:
	checks+=1
	if not value:failures.append(reason);push_error(reason)
	return value

func diagnostic(stage: String) -> void:
	observations[stage]=FoundationLocomotionPose._encode({"access":access.snapshot(),"pose":actor.furniture_pose.telemetry(),"request":actor.furniture_pose.request_state(),"motor":actor.snapshot(),"handle":hardware.handle_points(),"handle_surface":hardware.handle_surface_points()})

func capture(stage: String, closeup: bool = true) -> void:
	if camera==null or captures.has(stage):return
	captures[stage]=true
	var points: Dictionary=hardware.handle_points();var center: Vector3=(points.L.origin+points.R.origin)*.5
	if closeup:camera.global_position=center+Vector3(.66,.50,.80);camera.look_at(center+Vector3.UP*.04)
	else:camera.global_position=actor.global_position+Vector3(1.6,1.9,1.9);camera.look_at(actor.global_position+Vector3.UP*.8)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/drawer-access/"+who+"-"+stage+".png")

func save_midpoint(task: String) -> void:
	saved={"day":JSON.parse_string(JSON.stringify(day.snapshot())),"actor":JSON.parse_string(JSON.stringify(actor.motion_state())),"access":JSON.parse_string(JSON.stringify(access.snapshot()))}
	expect(access.can_restore(saved.access,day,saved.actor),"The actual partial slide validates its same task, access fraction, physical motor token and body frame")
	var before: Dictionary=access.snapshot();var corrupt: Dictionary=saved.access.duplicate(true)
	corrupt.session.elapsed+=.1
	expect(not access.can_restore(corrupt,day,saved.actor) and access.snapshot()==before,"A replay clock cannot diverge from the actual saved motor and drawer")
	corrupt=saved.access.duplicate(true);corrupt.session.task="task_missing"
	expect(not access.can_restore(corrupt,day,saved.actor),"A drawer transaction cannot be attached to another task")
	var wrong_actor: Dictionary=saved.actor.duplicate(true);wrong_actor.motor.interaction.token="foreign_motor_owner"
	expect(not access.can_restore(saved.access,day,wrong_actor),"Another motor owner cannot be restored as this drawer's performer")
	expect(day.task_for(who).id==task and day.person(who).actual_minutes.is_empty(),"A real partial drawer movement grants no household work credit")

func execute(target: int, task: String, record_save: bool) -> bool:
	var description: Dictionary=day.kitchen.access_descriptor("fridge:drawer",target)
	if not expect(access.begin(task,description),"The settled real actor begins the attached-handle operation: "+access.reason):return false
	var moved: bool=false;var first_contact: bool=false;var moving_valid: bool=true
	var peak_hand: float=0;var peak_finger: float=0;var peak_feet: float=0;var peak_joint: float=0;var peak_penetration: float=0;var phases: Array=[]
	for frame in 420:
		if not access.active():break
		var previous: float=float(day.access["fridge:drawer"])
		var prior_contact: bool=access._contacts_ready()
		var ticked: bool=access.advance(1.0/30)
		await process_frame
		if not ticked:diagnostic("advance_rejected");expect(false,"The actual performer advances without another tick owner: "+access.reason);return false
		if access.active() and access.session.phase not in phases:phases.append(access.session.phase)
		var now: float=float(day.access["fridge:drawer"])
		if prior_contact and not moved:await capture("open-grasp" if target==1 else "close-grasp")
		if absf(now-previous)>.000001:
			if not moved:first_contact=prior_contact;moved=true
			if not access._contacts_ready():moving_valid=false
			var observed: Dictionary=actor.furniture_pose.telemetry()
			for side in ["L","R"]:
				var hand: Dictionary=observed.get("hands",{}).get(side,{})
				peak_hand=maxf(peak_hand,float(hand.get("error_m",INF)))
				for finger in ["thumb","index"]:
					var skin: Dictionary=hand.get("fingers",{}).get(finger,{})
					peak_finger=maxf(peak_finger,float(skin.get("distance_m",INF)))
					peak_joint=maxf(peak_joint,float(skin.get("observed_rotation",INF)))
					peak_penetration=maxf(peak_penetration,float(skin.get("penetration_m",INF)))
			peak_feet=maxf(peak_feet,float(observed.get("feet",{}).get("required_support_error_m",INF)))
			if record_save and saved.is_empty() and now>.35 and now<.65:save_midpoint(task)
			if now>.4 and now<.6:await capture("open-midpoint" if target==1 else "close-midpoint",false)
		if frame==200 and not moved:
			diagnostic("blocked_grasp");expect(false,"Both real palms and finger surfaces must actually contact the handle before any drawer movement: "+access.reason);return false
	if not expect(access.complete() and not access.active(),"Attached-handle movement, actual release and recovery finish: "+access.reason):diagnostic("unfinished");return false
	expect(moved and first_contact,"The first actual drawer displacement occurs only after a fresh palm-and-finger grip")
	expect(moving_valid and peak_hand<=.01 and peak_finger<=.01,"Actual palms and thumb/index skin remain within one centimetre of the moving real handle")
	expect(peak_joint<=FoundationFurniturePose.HANDLE_FINGER_LIMIT+.00001 and peak_penetration<=.004,"Actual handle fitting uses bounded joint rotations and rejects deep finger penetration")
	expect(peak_feet<=.03,"Two real stepping legs retain their required floor supports during the full root translation")
	expect(absf(float(day.access["fridge:drawer"])-target)<.000001 and actor.global_position.distance_to(home.to_global(access._approach(target)))<.00001,"The motor root and actual drawer finish at their matching authored endpoints")
	expect(actor._furniture_request.is_empty() and not actor.furniture_pose.snapshot().enabled,"Completion explicitly clears the attached-handle pose owner")
	observations["open" if target==1 else "close"]={"peak_hand_m":peak_hand,"peak_finger_m":peak_finger,"peak_floor_support_m":peak_feet,"peak_finger_rotation_rad":peak_joint,"peak_finger_penetration_m":peak_penetration,"phases":phases,"root":actor.snapshot().position}
	await capture("open-complete" if target==1 else "close-complete",false)
	return true

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty() and arguments[0] in ["nagisa","ryo"]:who=arguments[0]
	DirAccess.make_dir_recursive_absolute("res://builds/drawer-access")
	home=LivingHouse.new();root.add_child(home)
	if not home.load_plan("res://data/foundation/ogawa-home.json"):expect(false,"The actual canonical home loads");finish();return
	HomeArt.new().add_visuals(home)
	var authored: Array=[];var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	for person in source.residents:
		if person.id in ["nagisa","ryo","rin"]:
			var profile: Dictionary=person.duplicate(true);profile.routines=[];authored.append(profile)
	day=HouseholdDay.new();nav=HomeNavigation.new();occupancy=HomeOccupancy.new()
	if not day.configure(home.definition,authored,occupancy) or not nav.configure(home.definition) or not occupancy.configure(home.definition):expect(false,"Canonical household and access policies configure");finish();return
	hardware=Fixtures.new();root.add_child(hardware)
	if not hardware.configure(home,day,nav):expect(false,"The real moving drawer configures");finish();return
	actor=FoundationResident.new();root.add_child(actor);actor.position=Vector3(.7,0,4.7);actor.rotation.y=PI
	if not actor.load_resident(who) or not actor.configure({}) or not actor.enable_contact_locomotion() or not actor.enable_furniture_poses():expect(false,"The imported real actor, locomotion and furniture providers configure");finish();return
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1100,850)
		var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-25,0);light.light_energy=.8;light.shadow_enabled=true;root.add_child(light)
		var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b5c7bf");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("f8e8d3");environment.environment.ambient_light_energy=.4;root.add_child(environment)
		camera=Camera3D.new();camera.current=true;camera.fov=44;root.add_child(camera)
	for ignored in 15:actor.tick_body(1.0/30);await process_frame
	await physics_frame
	day.set_position(who,home.to_local(actor.global_position))
	var task: Dictionary=day.request(who,"cook").get("task",{})
	if task.is_empty():expect(false,"The controlled adult can form the canonical cooking intention");finish();return
	access=Access.new()
	if not expect(access.configure(home,day,nav,hardware,actor),"Attached-handle performer binds the real source actors"):finish();return
	var surface: Dictionary=hardware.handle_surface_points();var grips: Dictionary=hardware.handle_points();var geometry: Dictionary=access._handle_geometry();var surface_valid := true
	for side in ["L","R"]:
		surface_valid=surface_valid and absf(FoundationFurniturePose._handle_signed_distance(surface[side].origin,geometry))<.000001 and surface[side].origin==grips[side].origin
		surface_valid=surface_valid and absf(surface[side].basis.get_rotation_quaternion().angle_to(grips[side].basis.get_rotation_quaternion())-.35)<.00001
	expect(surface_valid,"Actual cylinder surface points remain fixed while an explicit 20-degree wrist grasp frame is authored separately")
	var inventory: Dictionary=day.inventory.duplicate(true);var elapsed: float=day.elapsed
	if not await execute(1,task.id,true):finish();return
	expect(day.inventory==inventory and day.elapsed==elapsed and day.person(who).actual_minutes.is_empty(),"Opening creates no recipe result, resource movement, life minutes or work")
	if not saved.is_empty():
		if not expect(day.restore(saved.day) and actor.restore_motion(saved.actor) and access.restore(saved.access,day,saved.actor),"The real partial slide restores through each owner's checked API"):finish();return
		var fraction: float=float(day.access["fridge:drawer"]);var position: Vector3=actor.global_position
		access.advance(1.0/30);await process_frame
		expect(day.access["fridge:drawer"]==fraction and actor.global_position==position,"The first resumed frame re-observes contact instead of replaying a saved ready flag or moving prematurely")
		for ignored in 240:
			if not access.active():break
			access.advance(1.0/30);await process_frame
		expect(access.complete() and day.access["fridge:drawer"]==1,"The actual restored feet, hands, body and drawer continue to the same open endpoint")
	for ignored in 15:actor.tick_body(1.0/30);await process_frame
	day.set_position(who,home.to_local(actor.global_position))
	await execute(0,task.id,false)
	expect(day.inventory==inventory and day.elapsed==elapsed and day.person(who).actual_minutes.is_empty(),"Closing also grants no household effects")
	finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/drawer-access")
	var file := FileAccess.open("res://builds/drawer-access/"+who+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"controlled real actor/Skin, actual handle and motor; not natural task choice or a family-day acceptance"},"\t"))
	print("Household drawer access checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	if is_instance_valid(actor):actor.free()
	if is_instance_valid(hardware):hardware.free()
	if is_instance_valid(home):home.free()
	quit(0 if failures.is_empty() else 1)

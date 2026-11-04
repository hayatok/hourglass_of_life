extends SceneTree

# Canonical real resident + hardware + material objects. Initial open access
# and the intention/inspection clock are controlled fixture setup; only the
# pickup, front-panel clearance, carrying and supported placement are exercised.
const Transfer=preload("res://game/foundation/household_transfer.gd")
const Hardware=preload("res://game/foundation/household_kitchen_fixtures.gd")
var world: Node3D
var home: LivingHouse
var day: HouseholdDay
var nav: HomeNavigation
var occupancy: HomeOccupancy
var props: HouseholdProps
var actor: FoundationResident
var hardware: HouseholdKitchenFixtures
var performer
var checks := 0
var failures: Array[String]=[]
var samples: Array=[]
var camera: Camera3D
var output := "res://builds/household-transfer"
var last_stage := ""

func _initialize() -> void:
	create_timer(50).timeout.connect(func():push_error("Actual transfer watchdog");quit(1))
	call_deferred("run")
func expect(value: bool, message: String) -> bool:
	checks+=1
	if not value:failures.append(message);push_error(message)
	return value
func finish() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output+"/results.json",FileAccess.WRITE).store_string(JSON.stringify(FoundationLocomotionPose._encode({"checks":checks,"failures":failures,"session":performer.session if performer!=null else {},"samples":samples,"final_pose":actor.household_pose.telemetry() if actor!=null else {},"final_furniture":actor.furniture_pose.telemetry() if actor!=null else {}}),"\t"))
	print("Actual household transfer: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	world.free();quit(0 if failures.is_empty() else 1)

func capture(name: String) -> void:
	if camera==null:return
	camera.global_position=actor.global_position+Vector3(.8,1.8,2.0);camera.look_at(actor.global_position+Vector3.UP*.8)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+name+".png")

func drawer_penetration() -> bool:
	var id: String=day.kitchen.role_id("ingredient_carrier")
	var source: Node3D=props.objects[id].node
	var front: MeshInstance3D=hardware.drawer.get_node("InsulatedFront")
	var into_front: Transform3D=front.global_transform.affine_inverse()
	var bounds: AABB=front.mesh.get_aabb().grow(-.001)
	for mesh in source.find_children("*","MeshInstance3D",true,false):
		for point in mesh.mesh.get_faces():
			if bounds.has_point(into_front*mesh.to_global(point)):return true
	return false

func loose_stock_supported() -> bool:
	var shelf: MeshInstance3D=hardware.drawer.get_node("ActualShelf")
	var bounds: AABB=shelf.mesh.get_aabb()
	for id in props.objects:
		if not str(id).begins_with("inventory:ingredients:side_"):continue
		var node: Node3D=props.objects[id].node;var low := INF
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			for point in mesh.mesh.get_faces():
				var local: Vector3=shelf.to_local(mesh.to_global(point))
				if local.x<bounds.position.x-.00001 or local.x>bounds.end.x+.00001 or local.z<bounds.position.z-.00001 or local.z>bounds.end.z+.00001:return false
				low=minf(low,local.y)
		if absf(low-bounds.end.y)>.00001:return false
	return true

func execute() -> bool:
	var penetration := false;var grasp_before_movement := true;var held := false
	var peak := 0.0;var carry_peak := 0.0;var carry_samples := 0;var stage_frames := 0
	for frame in 3000:
		if performer.complete():break
		var before: Transform3D=day.equipment[day.kitchen.role_id("ingredient_carrier")].frame
		if not performer.advance(1.0/30):
			expect(false,"Canonical actual transfer advances: "+performer.reason+" / "+str(performer.session.stage));return false
		await process_frame
		var observed: Dictionary=actor.household_pose.telemetry()
		var is_held: bool=not day.equipment[day.kitchen.role_id("ingredient_carrier")].holder.is_empty()
		if not held and not is_held:grasp_before_movement=grasp_before_movement and before.is_equal_approx(day.equipment[day.kitchen.role_id("ingredient_carrier")].frame)
		held=held or is_held
		penetration=penetration or drawer_penetration()
		if performer.session.stage!=last_stage:
			last_stage=performer.session.stage;stage_frames=0
			samples.append({"frame":frame,"stage":last_stage,"actor":actor.global_transform,"object":day.equipment[day.kitchen.role_id("ingredient_carrier")].frame,"observed":observed})
			if last_stage in ["lift","source_exit","walk_target","lower","release","complete"]:await capture(last_stage)
		stage_frames+=1
		if stage_frames>350:
			expect(false,"The physical transfer cannot stall in "+last_stage+": "+performer.reason);return false
		if is_held:
			peak=maxf(peak,float(observed.get("contact_error_peak_m",0)))
			if observed.get("phase")=="carry":carry_samples+=1;carry_peak=maxf(carry_peak,float(observed.get("contact_error_peak_m",0)))
	if not expect(performer.complete(),"The complete transfer reaches its explicit safe end"):return false
	expect(grasp_before_movement,"The existing basket does not move before the actual grasp transaction")
	expect(not penetration,"Actual moving basket vertices do not enter the fridge front panel")
	expect(carry_samples==0 or carry_peak<=.01,"Every observed load-carry sample retains both actual palms within 1cm")
	return true

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	world=Node3D.new();root.add_child(world)
	home=LivingHouse.new();world.add_child(home)
	if not expect(home.load_plan("res://data/foundation/ogawa-home.json"),"Canonical family home loads"):finish();return
	HomeArt.new().add_visuals(home);home.cutaway=true
	day=HouseholdDay.new();occupancy=HomeOccupancy.new();nav=HomeNavigation.new()
	if not expect(occupancy.configure(home.definition) and nav.configure(home.definition) and day.configure(home.definition,[],occupancy),"Real household and path ledger configure"):finish();return
	actor=FoundationResident.new();world.add_child(actor)
	actor.global_position=Vector3(.7,0,5.25);actor.global_rotation.y=PI
	if not expect(actor.load_resident("nagisa") and actor.configure({}) and actor.enable_contact_locomotion() and actor.enable_furniture_poses() and actor.enable_household_poses(),"All ordered real skin/pose providers configure"):finish();return
	var task: Dictionary=day.request("nagisa","cook").task
	day.set_position("nagisa",actor.global_position)
	# Explicit access endpoint setup; this fixture does not claim drawer motion.
	if not expect(day.set_access("nagisa",task.id,"fridge:drawer",1),"Controlled setup opens only access state"):finish();return
	hardware=Hardware.new();world.add_child(hardware)
	if not expect(hardware.configure(home,day,nav),"Actual fridge cavity and moving front install"):finish();return
	props=HouseholdProps.new();world.add_child(props)
	if not expect(props.configure(home,day,{"nagisa":actor}),"Same actual source food and basket install"):finish();return
	performer=Transfer.new()
	if not expect(performer.configure(home,day,nav,occupancy,props,actor),"Real transfer controller configures"):finish();return
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1100,850)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-25,0);light.light_energy=.8;light.shadow_enabled=true;world.add_child(light)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b5c7bf");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("f8e8d3");environment.environment.ambient_light_energy=.4;world.add_child(environment)
		camera=Camera3D.new();camera.current=true;camera.fov=44;world.add_child(camera)
	for ignored in 12:actor.tick_body(1.0/30,false);await process_frame
	var operation: Dictionary=day.next_operation("nagisa",task.id)
	if not expect(performer.begin(task.id,operation),"Initial pickup starts from an actual source object"):finish();return
	if not await execute():finish();return
	var id: String=day.kitchen.role_id("ingredient_carrier")
	expect(day.equipment[id].holder=="nagisa" and actor.household_grasped_objects().get(id)==["L","R"],"Both real hands retain the same existing basket after source pickup")
	expect(loose_stock_supported(),"All six remaining actual food meshes retain the real drawer shelf independently of the moved basket")
	expect(day.inventory.ingredients==6 and day.jobs.cook.quantity==3,"Only actual grasp spends exactly the three previously visible ingredient units")
	# Controlled inspection time, with fresh actual held pose on every render.
	for ignored in 130:
		day.advance_time(.5/30)
		if actor.household_contacts_ready():day.set_physical_work("nagisa",task.id,true);day.perform("nagisa",task.id,.5/30)
		performer.present_held(1.0/30);await process_frame
	if not expect(day.finish("nagisa",task.id).status=="next_phase","Controlled held inspection authorizes only the next transfer phase"):finish();return
	operation=day.next_operation("nagisa",task.id)
	if not expect(performer.begin(task.id,operation),"The same already-held transaction begins physical carry/place"):finish();return
	if not await execute():finish();return
	expect(day.equipment[id].holder.is_empty() and day.equipment[id].support_slot=="prep:carrier" and actor.household_grasped_objects().is_empty(),"Same basket is placed on the real preparation support before both hands open")
	expect(day.jobs.cook.quantity==3 and day.inventory.ingredients==6,"Actual movement cannot duplicate or spend the food batch again")
	finish()

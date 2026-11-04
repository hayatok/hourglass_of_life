extends SceneTree

# Real imported hands and real tool meshes in a controlled two-object fixture.
# No food, clock or recipe result is awarded by this presentation-only test.
const TOOLS=preload("res://game/foundation/household_tools.gd")
var checks := 0
var failures: Array[String]=[]
var actor: FoundationResident
var world: Node3D
var objects: Dictionary={}
var clock_seconds := 0.0
var who := "nagisa"
var camera: Camera3D

func _initialize() -> void:
	create_timer(40).timeout.connect(func():push_error("Bimanual fixture timed out");quit(1))
	call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func failed_at(stage: String) -> bool:
	if failures.is_empty():return false
	DirAccess.make_dir_recursive_absolute("res://builds/household-bimanual")
	FileAccess.open("res://builds/household-bimanual/"+who+"-"+stage+".json",FileAccess.WRITE).store_string(JSON.stringify(FoundationLocomotionPose._encode({"observed":actor.household_pose.telemetry(),"request":actor.household_pose.request_state(),"calibration":actor.household_calibration()}),"\t"))
	world.free();quit(1);return true

func item(id: String, frame: Transform3D) -> Dictionary:
	var record: Dictionary=objects[id]
	return {"id":id,"world":frame,"local_grips":{record.hand:record.spec.local_grips[record.hand]},"support_local":record.spec.support_local}

func capture(stage: String) -> void:
	if camera==null:return
	var folder := "res://builds/household-bimanual/"+who
	DirAccess.make_dir_recursive_absolute(folder)
	for view in [["front",Vector3(1.6,1.7,2.2)],["side",Vector3(2.1,1.3,.05)]]:
		camera.position=view[1];camera.look_at(Vector3(0,actor.model.rest_height*.5,.2))
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+stage+"-"+str(view[0])+".png")

func phase(id: String, name: String, seconds: float, from: Transform3D, to: Transform3D, other: Dictionary = {}) -> void:
	var count: int=maxi(1,roundi(seconds*30))
	for index in range(count+1):
		var p: float=float(index)/count;var frame := Transform3D(from.basis.slerp(to.basis,smoothstep(0,1,p)),from.origin.lerp(to.origin,smoothstep(0,1,p)))
		objects[id].node.global_transform=frame
		var request := {"action":"transfer","phase":name,"progress":p,"posture":"stand","pose_seconds":clock_seconds,
			"object":item(id,frame),"source_world":from,"target_world":to,"support_point":to*objects[id].spec.support_local,"held_objects":other}
		if not actor.use_household_pose(request):expect(false,"A valid two-hand object request is admitted: "+name);return
		actor.tick_body(1.0/30,false);clock_seconds+=1.0/30
		await process_frame

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] in ["nagisa","ryo","rin"]:who=args[0]
	world=Node3D.new();root.add_child(world)
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(960,760)
		var environment := WorldEnvironment.new();environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("b8c9c5")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("eee4cf");environment.environment.ambient_light_energy=.4;world.add_child(environment)
		var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-25,0);light.shadow_enabled=true;light.light_energy=.75;world.add_child(light)
		camera=Camera3D.new();camera.current=true;camera.fov=42;world.add_child(camera)
		var ground := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(12,12);ground.mesh=plane;world.add_child(ground)
	actor=FoundationResident.new();world.add_child(actor)
	if not actor.load_resident(who) or not actor.configure({}) or not actor.enable_contact_locomotion() or not actor.enable_furniture_poses() or not actor.enable_household_poses():
		expect(false,"The real resident and all three ordered pose providers configure");world.free();quit(1);return
	var height: float=actor.model.rest_height*.5
	var top := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(1,.10,.60);top.mesh=box;top.position=Vector3(0,height-.05,.60);world.add_child(top)
	for pair in [["left_spoon","L",.18],["right_spatula","R",-.18]]:
		var kind: String="child_spoon" if who=="rin" else ("spoon" if pair[1]=="L" else "spatula")
		var node: Node3D=TOOLS.create(kind);world.add_child(node)
		var frame: Transform3D=TOOLS.park_on(kind,Transform3D(Basis.IDENTITY,Vector3(pair[2],height,.48)))
		node.global_transform=frame
		objects[pair[0]]={"kind":kind,"hand":pair[1],"node":node,"spec":TOOLS.spec(kind),"source":frame}
	for ignored in 12:actor.tick_body(1.0/30,false);await process_frame
	var initial_root: Transform3D=actor.global_transform
	var left: Dictionary=objects.left_spoon;var right: Dictionary=objects.right_spatula
	var left_hold := Transform3D(left.source.basis,Vector3(.18,height+.22,.33))
	var right_hold := Transform3D(right.source.basis,Vector3(-.18,height+.22,.33))
	await phase("left_spoon","reach",.65,left.source,left.source)
	expect(actor.household_grasped_objects().is_empty(),"Reaching an actual tool leaves both hands uncommitted")
	await phase("left_spoon","grasp",.4,left.source,left.source)
	expect(actor.household_transfer_ready("grasp") and actor.confirm_household_grasp("left_spoon") and actor.household_grasped_objects().get("left_spoon")==["L"],"The actual left palm and closed fingers establish only the left tool grasp")
	if failed_at("left-grasp"):return
	await phase("left_spoon","lift",.65,left.source,left_hold)
	var held := {"left_spoon":item("left_spoon",left_hold)}
	await phase("right_spatula","reach",.65,right.source,right.source,held)
	await phase("right_spatula","grasp",.4,right.source,right.source,held)
	expect(actor.household_transfer_ready("grasp") and actor.confirm_household_grasp("right_spatula") and actor.household_grasped_objects().size()==2,"The right hand can grasp a second real object while the left one stays held")
	if failed_at("right-grasp"):return
	await phase("right_spatula","lift",.65,right.source,right_hold,held)
	var observed: Dictionary=actor.household_pose.telemetry()
	expect(observed.contacts_ready and observed.hands.L.error_m<=.01 and observed.hands.R.error_m<=.01,"Both final imported skin palms remain on their distinct real tool grips")
	if failed_at("two-objects"):return
	await capture("both-held")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(actor.motion_state(),"",true,true))
	var bad: Dictionary=saved.duplicate(true);bad.household.grasped_objects.right_spatula=["L"]
	expect(not actor.can_restore_motion(bad),"A save cannot assign the same hand to two objects")
	bad=saved.duplicate(true);bad.household.request.held_objects.left_spoon.local_grips.L="invalid"
	expect(not actor.can_restore_motion(bad),"Malformed secondary object geometry is rejected before transform multiplication")
	expect(actor.restore_motion(saved) and not actor.household_contacts_ready(),"JSON restores two held objects but cannot reuse a saved contact-ready sample")
	actor.tick_body(0,false);await process_frame
	expect(actor.household_contacts_ready() and actor.household_grasped_objects().size()==2,"A new actual skeleton update re-establishes both held contacts")
	var omitted: Dictionary=actor.household_pose.request_state();omitted.erase("held_objects")
	expect(not actor.use_household_pose(omitted),"Starting another action cannot silently discard the other hand's held object")
	await phase("right_spatula","lower",.65,right_hold,right.source,held)
	await phase("right_spatula","release",.65,right.source,right.source,held)
	observed=actor.household_pose.telemetry()
	expect(actor.household_transfer_ready("release") and observed.hands.L.actual_finger_closure>=.7 and observed.hands.R.actual_finger_closure<=.1,"Opening the active right hand retains the left grasp and permits supported right placement")
	await capture("release-right")
	expect(actor.confirm_household_release("right_spatula") and actor.household_grasped_objects()=={"left_spoon":["L"]},"Committing one release frees only that object's hand")
	await phase("right_spatula","recover",.5,right.source,right.source,held)
	await phase("left_spoon","lower",.65,left_hold,left.source)
	await phase("left_spoon","release",.65,left.source,left.source)
	expect(actor.confirm_household_release("left_spoon") and actor.household_grasped_objects().is_empty(),"The remaining object can be placed independently on its real measured tool support")
	expect(actor.global_transform.is_equal_approx(initial_root),"Neither tool or pose provider moves the motor-owned body root")
	print("Household bimanual contacts: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	world.free();quit(0 if failures.is_empty() else 1)

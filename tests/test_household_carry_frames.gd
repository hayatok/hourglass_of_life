extends SceneTree

# Controlled real Skeleton3D/view fixtures. This verifies the carrier's frame
# ownership and geometric metadata, not skin contact or accepted carry motion.
const Props = preload("res://game/foundation/household_props.gd")
class PropModel extends Node3D:
	var skeleton: Skeleton3D
class PropActor extends Node3D:
	var model: PropModel
class ShiftHands extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void:
		var rig := get_skeleton()
		if rig==null: return
		for side in ["L","R"]: rig.set_bone_pose_position(rig.find_bone("DEF-hand."+side),Vector3(.20,.15,.10))

var checks: int = 0
var failures: Array[String] = []
var day: HouseholdDay
var home: LivingHouse
var view: HouseholdProps
var actors: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> bool:
	checks+=1
	if not ok: failures.append(message);push_error(message)
	return ok

func near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin)<.000001 and (a.basis.x-b.basis.x).length()<.000001 and (a.basis.y-b.basis.y).length()<.000001 and (a.basis.z-b.basis.z).length()<.000001

func actor_for(id: String) -> PropActor:
	var actor := PropActor.new();root.add_child(actor);actor.position=day.people[id].position
	actor.model=PropModel.new();actor.add_child(actor.model)
	var rig := Skeleton3D.new();actor.model.add_child(rig);actor.model.skeleton=rig
	for side in ["L","R"]:
		var hand: int=rig.get_bone_count();rig.add_bone("DEF-hand."+side)
		rig.set_bone_rest(hand,Transform3D(Basis.IDENTITY,Vector3(-.30 if side=="L" else .30,1,.20)))
		var finger: int=rig.get_bone_count();rig.add_bone("DEF-finger2."+side);rig.set_bone_parent(finger,hand)
		rig.set_bone_rest(finger,Transform3D(Basis.IDENTITY,Vector3(0,.07,0)))
	rig.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	return actor

func begin(actor: String, kind: String) -> Dictionary:
	var response: Dictionary=day.request(actor,kind)
	expect(response.status=="requested","The real source can request controlled "+kind)
	return response.task

func phase(actor: String) -> Dictionary:
	var task: Dictionary=day.task_for(actor)
	actors[actor].position=task.target;day.set_position(actor,task.target)
	if not expect(day.arrive(actor,task.id).status in ["arrived","phase_ready"],"The controlled material operation actually reaches its fixture"): return {}
	var amount: float=float(task.phase_minutes)-float(task.phase_progress)
	if amount>0:
		day.advance_time(amount)
		if not expect(day.perform(actor,task.id,amount).status=="phase_ready","Only real elapsed source work completes material handling"): return {}
	var response: Dictionary=day.finish(actor,task.id);view.sync()
	return response

func geometric_grips() -> void:
	var before: Dictionary=day.snapshot()
	for kind in ["tray","basket","textile"]:
		var contract: Dictionary=Props.grips_for(kind)
		var visual := Node3D.new();root.add_child(visual)
		view._make_visual(visual,{"kind":kind,"style":"folded","textile":"towel","state":"clean_laundry"})
		expect(contract.support_local==Vector3.ZERO and not contract.pose_accepted,"Support metadata names the real bottom centre without accepting hand contact")
		for grip in contract.local_grips.values(): expect(Props._rigid_frame(grip),"Every local palm/finger frame is finite, orthonormal and right handed")
		if kind=="tray":
			var bar: MeshInstance3D=visual.get_node("RaisedHandleL/GripBar")
			var outer: float=bar.position.x+float(bar.mesh.top_radius)
			expect(contract.local_grips.L.origin==Vector3(outer,bar.position.y,0) and contract.local_grips.R.origin==Vector3(-outer,bar.position.y,0),"Anatomical L/R tray grips lie on the actual raised handle outer surfaces")
			expect(contract.local_grips.L.basis.z==Vector3.LEFT and contract.local_grips.R.basis.z==Vector3.RIGHT and contract.local_grips.L.basis.y==Vector3.UP and contract.local_grips.R.basis.y==Vector3.UP,"Tray handle palms press inward with the fingers above the real support plane")
			expect(is_equal_approx(contract.handle_clearance,.06) and contract.contact_phase=="same_for_pickup_carry_place","Raised handles leave sixty millimetres above the tray rim and keep one pickup/carry/place grip contract")
		elif kind=="basket":
			var side: MeshInstance3D=visual.find_children("Side*","MeshInstance3D",false,false)[0]
			var outer: float=absf(side.position.x)+float(side.mesh.size.x)*.5
			expect(is_equal_approx(outer,.21) and contract.local_grips.L.origin==Vector3(outer,.16,0) and contract.local_grips.R.origin==Vector3(-outer,.16,0),"Basket grips match the actual external side walls rather than internal ±.17m points")
			expect(contract.local_grips.L.basis.z==Vector3.LEFT and contract.local_grips.R.basis.z==Vector3.RIGHT and contract.local_grips.L.basis.y==Vector3.UP,"Basket palms press inward with fingers along the wall")
		else:
			var edge: MeshInstance3D=visual.get_node("FoldEdge")
			var front: float=edge.position.z+float(edge.mesh.size.z)*.5
			var on_edge: bool=contract.local_grips.size()==1 and contract.local_grips.has("R") and absf(float(contract.local_grips.R.origin.z)-front)<.000001 and absf(float(contract.local_grips.R.origin.y)-float(edge.position.y))<.000001
			if not on_edge: print("CLOTH_GRIP_DIAG ",contract.local_grips," edge=",edge.position," size=",edge.mesh.size," front=",front)
			expect(on_edge,"The single right-hand cloth grip lies on the actual folded edge")
		visual.free()
	var copy: Dictionary=Props.grips_for("tray");copy.local_grips.clear()
	expect(Props.grips_for("tray").local_grips.size()==2 and Props.grips_for("unknown").is_empty() and HouseholdDay._same(before,day.snapshot()),"Grip queries return independent metadata without objects, time or source changes")

func stable_carrier() -> void:
	begin("nagisa","cook")
	if not expect(phase("nagisa").status=="next_phase","The actual first pickup gives the actor one finite carried batch"): return
	var held: Dictionary=view.pose_for("nagisa")
	var carrier: Node3D=view.objects[held.source_id].node
	expect(held.attachment=="BoneAttachment3D" and carrier.get_parent()==view.hand_socket("nagisa"),"Without a provider frame the existing hand-socket path remains active")
	var logical: Dictionary=day.snapshot();var manifest: Dictionary=view.manifest()
	var frame := Transform3D(Basis(Vector3.UP,PI),actors.nagisa.global_position+Vector3(0,1,.3))
	expect(view.set_carry_frame("nagisa",frame),"The executor can commit a rigid actor-derived object frame")
	var anchor: Node3D=view.carry_anchor("nagisa")
	held=view.pose_for("nagisa")
	expect(anchor.get_parent()==actors.nagisa and carrier.get_parent()==anchor and near(carrier.global_transform,frame) and held.attachment=="ActorCarryFrame","The held object uses a real body child anchor independent of either hand bone")
	expect(not held.pose_accepted and HouseholdDay._same(logical,day.snapshot()) and manifest==view.manifest(),"Installing a frame accepts no contact and changes no clock, quantity, owner or source identity")
	await process_frame
	var rig: Skeleton3D=actors.nagisa.model.skeleton
	var socket_before: Transform3D=view.socket_samples.nagisa.L
	var modifier := ShiftHands.new();rig.add_child(modifier);rig.advance(.02)
	await process_frame
	view.sync()
	expect(view.socket_samples.nagisa.L.origin.distance_to(socket_before.origin+Vector3(.20,.15,.10))<.001,"The controlled modifier really changes the final skeletal hand position")
	expect(near(carrier.global_transform,frame) and HouseholdDay._same(logical,day.snapshot()),"Moving the real hands cannot pull the authoritative carried object back toward those hands")
	var moved := Transform3D(Basis(Vector3.UP,PI*.5),frame.origin+Vector3(.6,.1,-.2))
	expect(view.set_carry_frame("nagisa",moved) and near(carrier.global_transform,moved),"A newly committed root frame moves the same object immediately without interpolation")
	held=view.pose_for("nagisa")
	for side in held.local_grips:
		expect(near(held.grips[side],carrier.global_transform*held.local_grips[side]),"Returned world grips derive from the actual object transform and local surface frames")
	var invalid := Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),frame.origin)
	expect(not view.set_carry_frame("nagisa",invalid) and not view.set_carry_frame("missing",moved) and near(carrier.global_transform,moved),"Invalid scale or actor frames are rejected without moving the object")
	expect(manifest==view.manifest() and HouseholdDay._same(logical,day.snapshot()),"Hand changes and provider changes leave all source quantities and identities untouched")
	modifier.active=false;modifier.queue_free()
	expect(view.clear_carry_frame("nagisa") and not view.has_carry_frame("nagisa") and carrier.get_parent()==view.hand_socket("nagisa"),"Clearing the explicit frame restores the legacy binding without deleting its held object")
	# The other supported kinds expose exactly the same geometry contract to a
	# future provider; their actual source activities are tested separately.
	expect(view.objects[held.source_id].node==carrier and HouseholdDay._same(logical,day.snapshot()),"Switching frame ownership preserves the original view node and real batch")

func run() -> void:
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	var authored: Array=[]
	for record in data.residents:
		if record.id not in ["nagisa","ryo","rin"]: continue
		var copy: Dictionary=record.duplicate(true);copy.routines=[];authored.append(copy)
	day=HouseholdDay.new()
	if not expect(day.configure(plan,authored),"The real controlled household configures"): quit(1);return
	home=LivingHouse.new();root.add_child(home)
	if not expect(home.load_plan("res://data/foundation/ogawa-home.json"),"The actual support fixtures load"): quit(1);return
	for id in day.people: actors[id]=actor_for(id)
	view=Props.new();root.add_child(view)
	if not expect(view.configure(home,day,actors),"The production props layer binds actual skeletons and source state"): quit(1);return
	geometric_grips();await stable_carrier()
	view.free()
	for actor in actors.values(): actor.free()
	home.free()
	print("Household carry frame checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

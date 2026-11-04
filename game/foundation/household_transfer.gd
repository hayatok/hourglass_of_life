class_name HouseholdTransfer
extends RefCounted

# Real object presentation and transaction boundaries. HouseholdDay remains the
# sole material/ownership ledger; ResidentMotor remains the sole body transform
# owner. No life time, inventory, work, or source position is inferred here.
const POSE=preload("res://game/foundation/foundation_locomotion_pose.gd")
const PHASE_SECONDS={"reach":.65,"grasp":.40,"lift":.75,"lower":.75,"release":.65,"recover":.45,"clearance_lift":.65,"clearance_lower":.65,"clearance_slide":.55}
const STAGES=["walk_source","align_source","reserve","reach","grasp","lift","source_exit","clearance_lower","walk_target","align_target","clearance_lift","clearance_slide","target_enter","lower","release","recover","complete"]
var home: LivingHouse
var life: HouseholdDay
var paths: HomeNavigation
var occupancy: HomeOccupancy
var props: HouseholdProps
var actor: FoundationResident
var who := ""
var session: Dictionary={}
var carry_offsets: Dictionary={}
var grip_contracts: Dictionary={}
var reason := ""
var obstacles: Array=[]

func configure(house: LivingHouse, day: HouseholdDay, navigation: HomeNavigation, uses: HomeOccupancy, objects: HouseholdProps, resident: FoundationResident) -> bool:
	if house==null or day==null or navigation==null or uses==null or objects==null or resident==null or resident.household_pose==null:return false
	home=house;life=day;paths=navigation;occupancy=uses;props=objects;actor=resident;who=resident.resident_id
	return life.people.has(who)

func active() -> bool:return not session.is_empty() and session.stage!="complete"
func complete() -> bool:return not session.is_empty() and session.stage=="complete"

func begin(task_id: String, operation: Dictionary) -> bool:
	if active() or operation.get("kind")!="transfer" or operation.get("status")!="ready" or life.task_for(who).get("id")!=task_id:return false
	var id: String=operation.item_id
	props.sync(0)
	var actual: Dictionary=props.object_pose(id)
	if actual.is_empty():reason="取り上げる実物が見つからない";return false
	var source: Dictionary=operation.source.duplicate(true)
	if source.is_empty():
		var tx: Dictionary=life.task_for(who).physical.transfer
		if tx.get("item_id")==id:source=life.kitchen.slot(tx.source_slot)
	var contract: Dictionary=_contract(actual,operation.hands)
	if contract.is_empty():reason="この物を支える手を確認できない";return false
	if not actor.household_grasped_objects().has(id):grip_contracts[id]=contract
	var frame: Transform3D=home.global_transform*operation.object.frame
	if operation.already_held and not actor.household_grasped_objects().has(id):reason="持ち手の実接触を確認できない";return false
	session={"task":task_id,"item":id,"stage":"walk_source","seconds":0.0,"operation":operation.duplicate(true),"source":source,
		"from":frame,"to":frame,"frame":frame,"tx":str(operation.transfer_id),"route_started":false,"root_start":actor.global_transform,"root_end":actor.global_transform}
	if operation.already_held:
		if not carry_offsets.has(id):carry_offsets[id]=actor.global_transform.affine_inverse()*frame
		if _drawer_support(source):
			if not _start_exit():session.clear();return false
		else:_stage("walk_target")
	return true

func _contract(actual: Dictionary, hands: Array) -> Dictionary:
	var result := {};var source: Dictionary=actual.local_grips
	for side in hands:
		if not source.has(side):return {}
		result[side]=source[side]
	if hands==["L","R"]:
		# A symmetric handle can be approached from either end. Keep the real
		# object orientation and choose the anatomical, uncrossed assignment.
		var separation: Vector3=(actual.world*source.L).origin-(actual.world*source.R).origin
		if separation.dot(actor.global_basis.x)<0:result={"L":source.R,"R":source.L}
	return result

func _stage(value: String) -> void:
	session.stage=value;session.seconds=0.0;session.route_started=false

func _frame(id: String) -> Transform3D:
	var item: Dictionary=life.kitchen.object_descriptor(id)
	return home.global_transform*item.frame if not item.is_empty() else Transform3D.IDENTITY

func held_requests(except: String = "") -> Dictionary:
	var result := {}
	for id in actor.household_grasped_objects():
		if id==except:continue
		var item: Dictionary=life.kitchen.object_descriptor(id)
		if item.is_empty() or item.holder!=who:continue
		if not grip_contracts.has(id):
			var actual: Dictionary=props.object_pose(id)
			if actual.is_empty():continue
			grip_contracts[id]=_contract(actual,item.hands)
		result[id]={"id":id,"world":home.global_transform*item.frame,"local_grips":grip_contracts[id]}
	return result

func _object_request(id: String, frame: Transform3D) -> Dictionary:
	var support := Vector3.ZERO
	if not session.is_empty() and id==session.item:support=session.operation.target.get("support_local",Vector3.ZERO)
	return {"id":id,"world":frame,"local_grips":grip_contracts[id],"support_local":support}

func present_held(delta: float, update_body: bool = true) -> bool:
	if actor.household_grasped_objects().is_empty():
		if update_body:actor.tick_body(delta,false)
		return true
	var id: String=str(actor.household_grasped_objects().keys()[0])
	var moving: bool=actor.state()!="idle" or not actor._furniture_request.is_empty()
	var request := {"action":"transfer","phase":"carry" if moving else "work","progress":1.0,"pose_seconds":0.0,"object":_object_request(id,_frame(id)),"held_objects":held_requests(id),"targets_authoritative":true}
	if not actor.use_household_pose(request):return false
	if update_body:actor.tick_body(delta,false)
	return true

func update_carried() -> bool:
	for id in actor.household_grasped_objects():
		if not carry_offsets.has(id):continue
		if not life.update_held_frame(who,life.task_for(who).get("id",""),id,home.global_transform.affine_inverse()*actor.global_transform*carry_offsets[id]):return false
	return true

func set_carried_frame(id: String, frame: Transform3D) -> bool:
	if not life.update_held_frame(who,session.task if not session.is_empty() else life.task_for(who).get("id",""),id,home.global_transform.affine_inverse()*frame):return false
	carry_offsets[id]=actor.global_transform.affine_inverse()*frame
	return true

func _comfortable(id: String, source: Transform3D) -> Transform3D:
	var local: Transform3D=actor.global_transform.affine_inverse()*source
	var kind: String=life.kitchen.object_descriptor(id).kind
	if kind=="plate":local.basis=Basis.IDENTITY
	var midpoint := Vector3.ZERO
	for grip in grip_contracts[id].values():midpoint+=grip.origin
	midpoint/=grip_contracts[id].size()
	var target: Vector3=actor.household_calibration().carry_grip_center_actor
	# Small one-handed objects stay on their own side, leaving the other hand
	# free for a real second object. A bilateral tray stays centred.
	if grip_contracts[id].size()==1:target.x=.18 if grip_contracts[id].has("L") else -.18
	local.origin=target-local.basis*midpoint
	# Bound against actual object triangles and the measured clothed torso.
	var low := INF
	var node: Node3D=props.objects[id].node
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var into_object: Transform3D=node.global_transform.affine_inverse()*mesh.global_transform
		for vertex in mesh.mesh.get_faces():low=minf(low,(local*into_object*vertex).z)
	var front: float=float(actor.household_calibration().body_front_actor)
	if is_finite(low) and low<front+.035:local.origin.z+=front+.035-low
	return actor.global_transform*local

func _drawer_support(support: Dictionary) -> bool:return not str(support.get("moving_support","")).is_empty() and home.fixtures.get(support.get("fixture",""),{}).get("definition",{}).has("drawer_geometry")

func _clearance_frame(frame: Transform3D, support: Dictionary) -> Transform3D:
	var result: Transform3D=frame
	var top: float=float(home.fixtures[support.fixture].definition.drawer_geometry.front_top_y)+.035
	var low := INF;var node: Node3D=props.objects[session.item].node
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var into_object: Transform3D=node.global_transform.affine_inverse()*mesh.global_transform
		for vertex in mesh.mesh.get_faces():low=minf(low,home.to_local(result*into_object*vertex).y)
	if is_finite(low):result.origin+=home.global_basis*Vector3.UP*maxf(0,top-low)
	return result

func _exit_point(support: Dictionary) -> Vector3:
	var approach: Vector3=home.to_global(support.approach)
	var fixture: Dictionary=home.fixtures[support.fixture].definition
	return approach+home.global_basis*LivingHouse.fixture_basis(fixture)*Vector3.BACK*.40

func _start_exit() -> bool:
	session.from=_frame(session.item);session.to=_clearance_frame(session.from,session.source)
	if session.from.origin.distance_to(session.to.origin)>.001:_stage("clearance_lift");session.after_clearance="source_exit";return true
	return _begin_step("source_exit",_exit_point(session.source))

func _begin_step(stage: String, end: Vector3) -> bool:
	if actor.state()!="idle":reason="身体が停止するのを待っている";return false
	var start: Transform3D=actor.global_transform;var target := Transform3D(start.basis,end)
	var route: Dictionary=paths.route(home.to_local(start.origin),home.to_local(end),who,occupancy,obstacles)
	if route.status!="ready" or route.points.size()>1:reason="収納の前を安全に動けない";return false
	var token: String="household:"+stage+":"+session.item
	if not actor.follow_interaction(token,[{"at":0.0,"position":_xyz(start.origin),"heading":actor.heading},{"at":1.8,"position":_xyz(end),"heading":actor.heading}]):reason="収納前の身体動作を開始できない";return false
	_stage(stage);session.root_start=start;session.root_end=target;return true

func _xyz(value: Vector3) -> Array:return [value.x,value.y,value.z]

func advance(delta: float, other_bodies: Array = []) -> bool:
	if not active() or not is_finite(delta) or delta<0 or delta>.1:return false
	obstacles=other_bodies
	var stage: String=session.stage
	var observed: Dictionary=actor.household_pose.telemetry()
	var ready: bool=actor.household_contacts_ready()
	# Consume only the previously applied final-skin sample. Presenting a new
	# request below never supplies evidence for the transaction above it.
	if stage=="grasp" and session.seconds>=PHASE_SECONDS.grasp and actor.household_transfer_ready("grasp"):
		var reply: Dictionary=life.commit_grasp(who,session.task,session.tx,home.global_transform.affine_inverse()*session.frame)
		if reply.status!="grasped" or not actor.confirm_household_grasp(session.item):reason=reply.get("reason","取り上げる接触を確認できない");return false
		session.from=session.frame;session.to=_comfortable(session.item,session.frame)
		if _drawer_support(session.source):session.to=_clearance_frame(session.from,session.source)
		_stage("lift")
	elif stage=="release" and session.seconds>=PHASE_SECONDS.release and actor.household_transfer_ready("release"):
		var reply: Dictionary=life.commit_release(who,session.task,session.tx,home.global_transform.affine_inverse()*session.frame)
		if reply.status!="released" or not actor.confirm_household_release(session.item):reason=reply.get("reason","手放す接触を確認できない");return false
		carry_offsets.erase(session.item);_stage("recover")
	elif stage in ["lift","clearance_lift","clearance_lower","clearance_slide","lower"] and session.seconds>=PHASE_SECONDS[stage] and ready and observed.get("phase") in ["lift","lower"] and float(observed.get("progress",0))>=.999:
		if stage=="lift":
			if session.operation.get("grasp_only",false):_stage("complete")
			elif _drawer_support(session.source):_begin_step("source_exit",_exit_point(session.source))
			else:_stage("walk_target")
		elif stage=="lower":_stage("release")
		elif stage=="clearance_lower":_stage("walk_target")
		elif stage=="clearance_slide":
			session.from=session.to
			if session.after_slide=="clearance_lower":session.to=_comfortable(session.item,session.from);_stage("clearance_lower")
			else:session.to=home.global_transform*session.operation.target.object_frame;_stage("lower")
		elif session.get("after_clearance")=="source_exit":_begin_step("source_exit",_exit_point(session.source))
		else:_begin_step("target_enter",home.to_global(session.operation.target.approach))
	elif stage=="recover" and session.seconds>=PHASE_SECONDS.recover:
		_stage("complete")
		if actor.household_grasped_objects().is_empty():actor.clear_household_pose()
	if complete():present_held(delta);props.sync(0);return true
	stage=session.stage
	if stage in ["walk_source","walk_target"]:
		var support: Dictionary=session.source if stage=="walk_source" else session.operation.target
		var target: Vector3=home.to_global(support.approach)
		if stage=="walk_target" and _drawer_support(support):target=_exit_point(support)
		if not session.route_started:
			var route: Dictionary=paths.route(home.to_local(actor.global_position),home.to_local(target),who,occupancy,other_bodies)
			if route.status!="ready":reason=route.reason;return false
			var points: Array=[]
			for point in route.points:points.append(home.to_global(point))
			if not points.is_empty() and not actor.follow_path(points):return false
			session.route_started=true
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));update_carried()
		present_held(delta);props.sync(0)
		if actor.body_is_settled():
			var fixture: Dictionary=home.fixtures[support.fixture].definition
			if not actor.face_heading(home.global_rotation.y+deg_to_rad(float(fixture.get("use_facing",fixture.facing)))):return false
			_stage("align_source" if stage=="walk_source" else "align_target")
		return true
	if stage in ["align_source","align_target"]:
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));update_carried();present_held(delta);props.sync(0)
		if actor.body_is_settled():
			if stage=="align_source":_stage("reserve")
			elif _drawer_support(session.operation.target):
				session.from=_frame(session.item);session.to=_clearance_frame(session.from,session.operation.target);session.after_clearance="target_enter";_stage("clearance_lift")
			else:session.from=_frame(session.item);session.to=home.global_transform*session.operation.target.object_frame;_stage("lower")
		return true
	if stage=="reserve":
		if session.tx.is_empty():
			var reply: Dictionary=life.begin_transfer(who,session.task,session.item,session.operation.target.id)
			if reply.status!="ready":reason=reply.reason;return false
			session.tx=reply.transfer.id
		session.from=_frame(session.item);session.to=session.from;session.frame=session.from;_stage("reach");stage="reach"
	if stage in ["source_exit","target_enter"]:
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));update_carried()
		var progress: float=clampf(float(actor.pose().interaction.get("elapsed",1.8))/1.8,0,1) if actor.state()=="interaction" else 1.0
		var phase: String="step_back" if stage=="source_exit" else "step_forward"
		var hands := {}
		for side in grip_contracts[session.item]:hands[side]={"palm_transform":_frame(session.item)*grip_contracts[session.item][side],"grip":true}
		if not actor.use_furniture_pose({"phase":phase,"progress":progress,"seat_point":session.root_end.origin,"root_start":session.root_start,"root_end":session.root_end,"floor_y":home.global_position.y,"working_hands":hands}):return false
		var request := {"action":"transfer","phase":"carry","progress":1.0,"pose_seconds":0.0,"object":_object_request(session.item,_frame(session.item)),"held_objects":held_requests(session.item),"preserve_lower_body":true}
		if not actor.use_household_pose(request):return false
		actor.tick_body(delta,false);props.sync(0)
		if actor.state()=="idle" and ready:
			session.from=_frame(session.item)
			session.to=_clearance_frame(_comfortable(session.item,session.from),session.source) if stage=="source_exit" else _clearance_frame(home.global_transform*session.operation.target.object_frame,session.operation.target)
			session.after_slide="clearance_lower" if stage=="source_exit" else "lower"
			_stage("clearance_slide")
		return true
	var phase: String=stage
	if stage in ["clearance_lift","clearance_lower","clearance_slide"]:phase="lower" if stage=="clearance_lower" else "lift"
	session.seconds=minf(float(PHASE_SECONDS.get(stage,.1)),float(session.seconds)+delta)
	var progress: float=clampf(float(session.seconds)/float(PHASE_SECONDS.get(stage,.1)),0,1)
	if stage in ["lift","lower","clearance_lift","clearance_lower","clearance_slide"]:
		session.frame=session.from.interpolate_with(session.to,smoothstep(0,1,progress))
		if not set_carried_frame(session.item,session.frame):return false
	elif stage in ["release","recover"]:session.frame=session.to
	if stage=="reach" and progress>=1.0:_stage("grasp")
	var request := {"action":"transfer","phase":phase,"progress":progress,"pose_seconds":0.0,"object":_object_request(session.item,session.frame),
		"source_world":session.from,"target_world":session.to,"support_point":home.to_global(session.operation.target.support_point),"held_objects":held_requests(session.item),"targets_authoritative":true}
	if stage in ["reach","grasp"] and not session.source.is_empty():
		var clearance: float=float(session.source.position.y)+.06
		if _drawer_support(session.source):clearance=maxf(clearance,float(home.fixtures[session.source.fixture].definition.drawer_geometry.front_top_y)+.06)
		request.reach_clearance_y=home.to_global(Vector3(0,clearance,0)).y
	if not actor.use_household_pose(request):reason="実物と手の姿勢を接続できない";return false
	actor.clear_furniture_pose()
	actor.tick_body(delta,false);props.sync(0)
	return true

func snapshot() -> Dictionary:
	return POSE._encode({"schema":1,"session":session,"carry_offsets":carry_offsets,"grip_contracts":grip_contracts})

func can_restore(data: Variant, restored_life: HouseholdDay, body: Dictionary) -> bool:
	if not data is Dictionary or data.get("schema")!=1:return false
	var decoded: Variant=POSE._decode(data)
	if not decoded is Dictionary or not decoded.get("session") is Dictionary or not decoded.get("carry_offsets") is Dictionary or not decoded.get("grip_contracts") is Dictionary:return false
	var saved: Dictionary=decoded.session
	if not saved.is_empty():
		if saved.get("stage") not in STAGES or not saved.get("task") is String or not restored_life.tasks.has(saved.task) or restored_life.tasks[saved.task].actor!=who:return false
		if not saved.get("item") is String or restored_life.kitchen.object_descriptor(saved.item).is_empty() or not saved.get("tx") is String or not saved.get("operation") is Dictionary:return false
		if not saved.get("seconds") is float and not saved.get("seconds") is int:return false
		if not is_finite(float(saved.seconds)) or saved.seconds<0 or saved.seconds>2:return false
		for key in ["from","to","frame","root_start","root_end"]:
			if not POSE._valid_transform(saved.get(key)):return false
		if not saved.get("route_started") is bool or not saved.get("source") is Dictionary:return false
		var tx: Dictionary=restored_life.tasks[saved.task].physical.transfer
		if not saved.tx.is_empty() and tx.get("id")!=saved.tx:return false
	if not saved.is_empty() and saved.stage!="complete":
		var operation: Dictionary=saved.operation
		if operation.get("kind")!="transfer" or operation.get("status")!="ready" or operation.get("item_id")!=saved.item or not operation.get("target") is Dictionary or not operation.get("grasp_only",false) is bool:return false
		var expected: Dictionary=restored_life.transfer_descriptor(who,saved.task,saved.item,str(operation.target.get("id","")))
		if expected.get("status")!="ready":return false
		for key in ["object_frame","frame"]:
			if not POSE._valid_transform(operation.target.get(key)) or not operation.target[key].is_equal_approx(expected.target[key]):return false
		for key in ["approach","support_point","support_local"]:
			if not operation.target.get(key) is Vector3 or not operation.target[key].is_equal_approx(expected.target[key]):return false
		if operation.target.get("fixture")!=expected.target.fixture:return false
		var motor: Dictionary=body.get("motor",{})
		if motor.get("state")=="interaction":
			if saved.stage not in ["source_exit","target_enter"] or motor.interaction.get("token")!="household:"+saved.stage+":"+saved.item:return false
			var frames: Variant=motor.interaction.get("frames")
			if not frames is Array or frames.size()!=2 or float(frames[-1].at)!=1.8:return false
			if Vector3(frames[0].position[0],frames[0].position[1],frames[0].position[2]).distance_to(saved.root_start.origin)>.00001 or Vector3(frames[1].position[0],frames[1].position[1],frames[1].position[2]).distance_to(saved.root_end.origin)>.00001:return false
		elif saved.stage in ["source_exit","target_enter"]:
			if motor.get("state")!="idle" or Vector3(motor.position[0],motor.position[1],motor.position[2]).distance_to(saved.root_end.origin)>.00001:return false
	for id in decoded.carry_offsets:
		if not id is String or not POSE._valid_transform(decoded.carry_offsets[id]):return false
		var item: Dictionary=restored_life.kitchen.object_descriptor(id)
		if item.is_empty() or item.holder!=who:return false
	for id in decoded.grip_contracts:
		if not id is String or not decoded.grip_contracts[id] is Dictionary:return false
		for side in decoded.grip_contracts[id]:
			if side not in ["L","R"] or not POSE._valid_transform(decoded.grip_contracts[id][side]):return false
	# Body-level validation independently checks actual hand ownership. Require
	# every saved held object to agree with the Day ledger before live mutation.
	var held: Variant=body.get("household",{}).get("grasped_objects",{})
	for item in restored_life.equipment.values():
		if item.holder==who and not held.has(item.id):return false
	for job in restored_life.jobs.values():
		for field in ["plates","units"]:
			for item in job.get(field,[]):
				if item.holder==who and not held.has(item.id):return false
	for id in held:
		var item: Dictionary=restored_life.kitchen.object_descriptor(id)
		if item.is_empty() or item.holder!=who or not decoded.carry_offsets.has(id) or not decoded.grip_contracts.has(id):return false
	return true

func restore(data: Dictionary, restored_life: HouseholdDay, body: Dictionary) -> bool:
	if not can_restore(data,restored_life,body):return false
	var decoded: Dictionary=POSE._decode(data)
	session=decoded.session.duplicate(true);carry_offsets=decoded.carry_offsets.duplicate(true);grip_contracts=decoded.grip_contracts.duplicate(true);reason=""
	return true

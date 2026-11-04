class_name HouseholdPerformance
extends RefCounted

# One kitchen intention is expanded into physical primitives. This controller
# owns no clock, stock or body transform. It reads the next material operation,
# routes the body, and commits only after a matching final-skin observation.
const TRANSFER=preload("res://game/foundation/household_transfer.gd")
const WORK=preload("res://game/foundation/household_work.gd")
const DRAWER=preload("res://game/foundation/household_drawer_access.gd")
const TOOLS=preload("res://game/foundation/household_tools.gd")
const POSE=preload("res://game/foundation/foundation_locomotion_pose.gd")
var home: LivingHouse
var life: HouseholdDay
var paths: HomeNavigation
var occupancy: HomeOccupancy
var props: HouseholdProps
var fixtures: HouseholdKitchenFixtures
var actor: FoundationResident
var handling
var work
var drawer
var session: Dictionary={}
var reason := ""
var who := ""

func configure(house: LivingHouse, day: HouseholdDay, navigation: HomeNavigation, uses: HomeOccupancy, objects: HouseholdProps, hardware: HouseholdKitchenFixtures, resident: FoundationResident) -> bool:
	if house==null or day==null or navigation==null or uses==null or objects==null or hardware==null or resident==null:return false
	home=house;life=day;paths=navigation;occupancy=uses;props=objects;fixtures=hardware;actor=resident;who=actor.resident_id
	handling=TRANSFER.new();work=WORK.new();drawer=DRAWER.new()
	return handling.configure(home,life,paths,occupancy,props,actor) and work.configure(home,life,paths,occupancy,props,actor,handling) and drawer.configure(home,life,paths,fixtures,actor)

func active() -> bool:return handling.active() or work.active() or drawer.active() or not session.is_empty()
func owns_body() -> bool:return active() or not actor.household_grasped_objects().is_empty()

func advance(task: Dictionary, delta: float, minutes: float, obstacles: Array = []) -> Dictionary:
	if task.is_empty() or not life.kitchen.supports(task):return {"status":"invalid","reason":"本人の台所の作業が必要"}
	if handling.active():
		var ok: bool=handling.advance(delta,obstacles);reason=handling.reason
		return {"status":"progress" if ok else "blocked","reason":reason}
	if drawer.active():
		var ok: bool=drawer.advance(delta);reason=drawer.reason
		if drawer.complete():session.clear()
		return {"status":"progress" if ok else "blocked","reason":reason}
	if work.active():
		var reply: Dictionary=work.advance(delta,minutes,obstacles);reason=reply.get("reason",work.reason)
		return reply
	if handling.complete():handling.session.clear()
	if work.complete():work.session.clear()
	if not session.is_empty():
		if session.kind=="access":
			if _go(delta,session.approach,session.operation.fixture,obstacles):
				if not drawer.begin(task.id,session.operation):reason=drawer.reason;return {"status":"blocked","reason":reason}
				if drawer.complete():session.clear()
			return {"status":"progress","reason":reason}
		return _recipe(task,delta,obstacles)
	var operation: Dictionary=life.next_operation(who,task.id)
	if operation.get("status")!="ready":
		reason=operation.get("reason","作業場所が空くのを待っている");handling.present_held(delta)
		return {"status":"blocked","reason":reason}
	match str(operation.kind):
		"transfer":
			if not handling.begin(task.id,operation):reason=handling.reason;return {"status":"blocked","reason":reason}
			return {"status":"progress"}
		"work":
			if not work.begin(task.id,operation):return {"status":"invalid","reason":"実物を持って作業を始められない"}
			return {"status":"progress"}
		"access":
			var approach: Vector3=operation.approach_closed.lerp(operation.approach_open,float(operation.fraction))
			session={"task":task.id,"kind":"access","operation":operation.duplicate(true),"approach":approach,"stage":"walk","route_started":false}
		"recipe":
			session={"task":task.id,"kind":"recipe","operation":operation.duplicate(true),"stage":"walk","route_started":false,"seconds":0.0,"unit_started":false,
				"carrier_start":handling._frame(operation.get("carrier_id",operation.item_id)),"item_start":handling._frame(operation.item_id),"tool_start":Transform3D.IDENTITY,"unit_start":Transform3D.IDENTITY}
		"finish":
			var reply: Dictionary=life.finish(who,task.id)
			if actor.household_grasped_objects().is_empty():actor.clear_household_pose()
			return reply
	return {"status":"progress"}

func _go(delta: float, approach: Vector3, fixture_id: String, obstacles: Array) -> bool:
	if session.stage=="walk":
		if not session.route_started:
			var route: Dictionary=paths.route(home.to_local(actor.global_position),approach,who,occupancy,obstacles)
			if route.status!="ready":reason=route.reason;handling.present_held(delta);return false
			var points: Array=[]
			for point in route.points:points.append(home.to_global(point))
			if not points.is_empty() and not actor.follow_path(points):reason="作業場所への経路を開始できない";return false
			session.route_started=true
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));handling.update_carried();handling.present_held(delta);props.sync(0)
		if actor.body_is_settled():
			var fixture: Dictionary=home.fixtures[fixture_id].definition
			if actor.face_heading(home.global_rotation.y+deg_to_rad(float(fixture.get("use_facing",fixture.facing)))):session.stage="align"
		return false
	if session.stage=="align":
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));handling.update_carried();handling.present_held(delta);props.sync(0)
		if actor.body_is_settled():session.stage="position";session.seconds=0.0;return true
		return false
	return true

func _present(id: String, frame: Transform3D, phase: String, progress: float, delta: float) -> bool:
	if not handling.set_carried_frame(id,frame):return false
	var request := {"action":"transfer","phase":phase,"progress":progress,"pose_seconds":0.0,"object":handling._object_request(id,frame),"held_objects":handling.held_requests(id),"targets_authoritative":true}
	if not actor.use_household_pose(request):return false
	actor.tick_body(delta,false);props.sync(0);return true

func _recipe(task: Dictionary, delta: float, obstacles: Array) -> Dictionary:
	var operation: Dictionary=session.operation
	var target: Dictionary=operation.get("container_target",operation.target)
	if not _go(delta,target.approach,target.fixture,obstacles):return {"status":"progress","reason":reason}
	var ready: bool=actor.household_contacts_ready()
	var observed: Dictionary=actor.household_pose.telemetry()
	var id: String=operation.get("carrier_id",operation.item_id)
	var desired: Transform3D
	if operation.operation=="pour":
		# Align the actual container edge with the real pan opening. This is a
		# held/tipped container, never a pretend parking slot above the stove.
		var tilted := Basis(Vector3.RIGHT,-PI/3)
		desired=home.global_transform*Transform3D(tilted,operation.container_target.frame.origin-tilted*Vector3(0,.23,-.155))
	else:
		desired=home.global_transform*operation.target.frame
	if session.stage=="position":
		if session.seconds==0:session.carrier_start=handling._frame(id)
		session.seconds=minf(1.0,float(session.seconds)+delta)
		var actual: Transform3D=session.carrier_start.interpolate_with(desired,smoothstep(0,1,float(session.seconds)))
		if not _present(id,actual,"lift",float(session.seconds),delta):return {"status":"invalid","reason":"実物を鍋の作業位置へ運べない"}
		if session.seconds>=1.0 and ready and observed.get("phase")=="lift" and float(observed.get("progress",0))>=.999:
			session.stage="operate";session.seconds=0.0
		return {"status":"progress"}
	if operation.operation=="pour":
		if not ready:_present(id,desired,"work",1.0,delta);return {"status":"progress","reason":"材料容器を支える実接触を整えている"}
		if not session.unit_started:
			var unit: Dictionary=life.kitchen.object_descriptor(operation.item_id)
			session.unit_start=home.global_transform*unit.frame
			if not life.update_pour_unit(who,task.id,operation.unit_index,unit.frame,float(unit.pour_progress)):return {"status":"invalid","reason":"同じ食材の連続移動を開始できない"}
			session.unit_started=true
		session.seconds=minf(1.1,float(session.seconds)+delta)
		var p: float=float(session.seconds)/1.1
		var start: Transform3D=session.unit_start
		var end: Transform3D=home.global_transform*operation.target.object_frame
		var lip := Transform3D(start.basis,home.to_global(operation.container_target.position)+Vector3.UP*.035)
		var moving: Transform3D=start.interpolate_with(lip,smoothstep(0,1,p/.5)) if p<.5 else lip.interpolate_with(end,(p-.5)/.5)
		if p>=.5:moving.origin.y=lerpf(lip.origin.y,end.origin.y,pow((p-.5)/.5,2))
		if not life.update_pour_unit(who,task.id,operation.unit_index,home.global_transform.affine_inverse()*moving,lerpf(float(operation.pour_progress),1,p)):return {"status":"invalid","reason":"食材の実移動を継続できない"}
		_present(id,desired,"work",1.0,delta)
		if p>=1:
			var reply: Dictionary=life.commit_recipe_step(who,task.id,"pour",home.global_transform.affine_inverse()*moving,operation.unit_index)
			if reply.status!="recorded":return reply
			session.clear()
		return {"status":"progress"}
	# The left hand supports the existing plate throughout scooping. The right
	# hand carries an actual utensil from pan to plate before any serving credit.
	var tool_id: String=life.kitchen.role_id("cooking_tool")
	var tool_kind: String=life.equipment[tool_id].kind
	if session.seconds==0:session.tool_start=handling._frame(tool_id)
	var point: Vector3=home.to_global(life.kitchen.slot("stove:stir").position)
	var above: Vector3=desired.origin+Vector3.UP*.055
	var cycle: float=clampf(float(session.seconds)/2.4,0,1)
	var feature_point: Vector3=point.lerp(above,smoothstep(.1,.6,cycle))
	var basis: Basis=actor.global_basis*Basis(Vector3.RIGHT,.65+(smoothstep(.65,.9,cycle)*.75))
	var tool: Transform3D=TOOLS.world_for_working(tool_kind,"tip",Transform3D(basis,feature_point))
	if not handling.set_carried_frame(tool_id,tool):return {"status":"invalid","reason":"盛り付ける実物の道具を動かせない"}
	if ready:session.seconds=minf(2.4,float(session.seconds)+delta)
	_present(id,desired,"work",1.0,delta)
	if session.seconds>=2.4 and ready:
		var actual_tool: Transform3D=handling._frame(tool_id)
		var lip: Vector3=actual_tool*TOOLS.spec(tool_kind).working_frames.tip.origin
		if lip.distance_to(above)>.01:return {"status":"progress","reason":"器の上へ道具を運んでいる"}
		var reply: Dictionary=life.commit_recipe_step(who,task.id,"plate_one",home.global_transform.affine_inverse()*desired,operation.unit_index)
		if reply.status!="recorded":return reply
		session.clear()
	return {"status":"progress"}

func snapshot() -> Dictionary:
	return POSE._encode({"schema":1,"session":session,"handling":handling.snapshot(),"work":work.snapshot(),"drawer":drawer.snapshot()})

func can_restore(data: Variant, restored: HouseholdDay, body: Dictionary) -> bool:
	if not data is Dictionary or data.get("schema")!=1:return false
	var decoded: Variant=POSE._decode(data)
	if not decoded is Dictionary or not decoded.get("session") is Dictionary:return false
	if not handling.can_restore(data.get("handling"),restored,body) or not work.can_restore(data.get("work"),restored,body) or not drawer.can_restore(data.get("drawer"),restored,body):return false
	var transfer_active: bool=not decoded.handling.session.is_empty() and decoded.handling.session.get("stage")!="complete"
	var work_active: bool=not decoded.work.session.is_empty() and decoded.work.session.get("stage")!="complete"
	var drawer_active: bool=not decoded.drawer.session.is_empty()
	if int(transfer_active)+int(work_active)+int(drawer_active)>1:return false
	if (transfer_active or work_active) and not decoded.session.is_empty():return false
	if drawer_active and decoded.session.get("kind")!="access":return false
	var saved: Dictionary=decoded.session
	if saved.is_empty():return true
	if saved.get("kind") not in ["access","recipe"] or saved.get("stage") not in ["walk","align","position","operate"] or not saved.get("route_started") is bool or not saved.get("operation") is Dictionary:return false
	if not saved.get("task") is String or restored.task_for(who).get("id")!=saved.task:return false
	if saved.kind=="access":return saved.get("approach") is Vector3 and saved.approach.is_finite()
	for key in ["carrier_start","item_start","tool_start","unit_start"]:
		if not POSE._valid_transform(saved.get(key)):return false
	return POSE._finite_number(saved.get("seconds")) and saved.seconds>=0 and saved.seconds<=2.4 and saved.get("unit_started") is bool

func restore(data: Dictionary, restored: HouseholdDay, body: Dictionary) -> bool:
	if not can_restore(data,restored,body):return false
	handling.restore(data.handling,restored,body);work.restore(data.work,restored,body);drawer.restore(data.drawer,restored,body)
	session=POSE._decode(data).session.duplicate(true);reason="";return true

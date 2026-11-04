class_name HouseholdWork
extends RefCounted

# Tool motion is authored against actual working features. This is a physical
# prototype, not acceptance of natural full-body animation; CMU source timing
# and character-specific retargeting are reviewed separately.
const TOOLS=preload("res://game/foundation/household_tools.gd")
const FOOD=preload("res://game/foundation/household_food.gd")
const POSE=preload("res://game/foundation/foundation_locomotion_pose.gd")
var home: LivingHouse
var life: HouseholdDay
var paths: HomeNavigation
var occupancy: HomeOccupancy
var props: HouseholdProps
var actor: FoundationResident
var transfer: HouseholdTransfer
var who := ""
var session: Dictionary={}
var reason := ""

func configure(house: LivingHouse, day: HouseholdDay, navigation: HomeNavigation, uses: HomeOccupancy, objects: HouseholdProps, resident: FoundationResident, handling: HouseholdTransfer) -> bool:
	if house==null or day==null or navigation==null or uses==null or objects==null or resident==null or handling==null:return false
	home=house;life=day;paths=navigation;occupancy=uses;props=objects;actor=resident;transfer=handling;who=resident.resident_id
	return true

func active() -> bool:return not session.is_empty() and session.stage!="complete"
func complete() -> bool:return not session.is_empty() and session.stage=="complete"

func begin(task: String, operation: Dictionary) -> bool:
	if active() or operation.get("kind")!="work" or life.task_for(who).get("id")!=task:return false
	var id: String=operation.item_id
	if not id.is_empty() and life.kitchen.object_descriptor(id).get("holder")!=who:return false
	session={"task":task,"operation":operation.duplicate(true),"stage":"walk","route_started":false,"seconds":0.0,"work_seconds":0.0,"start":transfer._frame(id) if not id.is_empty() else Transform3D.IDENTITY,"scored":{},"cut_index":0,"cut_seconds":0.0}
	return true

func _cuts() -> Array:
	var result: Array=[];var task: Dictionary=life.task_for(who)
	for unit in life.jobs.get(task.get("job_key",""),{}).get("units",[]):
		var spec: Dictionary=FOOD.spec(unit.ingredient_kind,"whole")
		for cut in spec.cut_planes:
			result.append({"id":unit.id+":"+str(cut.id),"entry":home.global_transform*unit.frame*cut.entry_local,"core":float(spec.score.core_y),"unit":home.global_transform*unit.frame})
	return result

func _tool_frame(seconds: float) -> Transform3D:
	var operation: Dictionary=session.operation;var id: String=operation.item_id
	if operation.work_kind=="inspect_materials":return transfer._frame(id)
	var target: Transform3D=home.global_transform*operation.target.frame
	var feature := "tip";var kind: String=life.kitchen.object_descriptor(id).kind
	if operation.work_kind=="score_food":
		var cuts: Array=_cuts()
		if cuts.is_empty():return transfer._frame(id)
		var cut: Dictionary=cuts[int(session.cut_index)%cuts.size()]
		var unit: Transform3D=cut.unit
		var blade := Basis(unit.basis.z,unit.basis.y,-unit.basis.x)
		var progress: float=fposmod(float(session.cut_seconds)/.65,1.0)
		var down: float=smoothstep(0,.42,progress)*(1-smoothstep(.50,.92,progress))
		var low: float=(unit*Vector3(0,float(cut.core)+.002,0)).y
		var point: Vector3=cut.entry.origin
		point.y=lerpf(point.y+.035,low,down)
		target=Transform3D(blade,point);feature="cut_edge"
	else:
		# Tip follows a small circle inside the actual pan. The handle rises
		# away from the rim; moving a bare hand around a stationary tool is forbidden.
		target.basis=actor.global_basis*Basis(Vector3.RIGHT,.70)
		target.origin+=home.global_basis*Vector3(cos(seconds*TAU*.65)*.035,0,sin(seconds*TAU*.65)*.035)
	return TOOLS.world_for_working(kind,feature,target)

func advance(delta: float, minutes: float, obstacles: Array = []) -> Dictionary:
	if not active() or not is_finite(delta) or delta<0 or delta>.1:return {"status":"invalid","reason":"実作業の進行時間が不正"}
	var operation: Dictionary=session.operation
	var id: String=operation.item_id
	if life.task_for(who).get("id")!=session.task:return {"status":"invalid","reason":"作業中の本人の行動が変わった"}
	if session.stage=="walk":
		if not session.route_started:
			var route: Dictionary=paths.route(home.to_local(actor.global_position),operation.target.approach,who,occupancy,obstacles)
			if route.status!="ready":reason=route.reason;return {"status":"blocked","reason":reason}
			var points: Array=[]
			for point in route.points:points.append(home.to_global(point))
			if not points.is_empty() and not actor.follow_path(points):return {"status":"invalid","reason":"作業場所への経路を開始できない"}
			session.route_started=true
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));transfer.update_carried();transfer.present_held(delta);props.sync(0)
		if actor.body_is_settled():
			var fixture: Dictionary=home.fixtures[operation.target.fixture].definition
			if actor.face_heading(home.global_rotation.y+deg_to_rad(float(fixture.get("use_facing",fixture.facing)))):session.stage="align"
		return {"status":"progress"}
	if session.stage=="align":
		actor.tick(delta);life.set_position(who,home.to_local(actor.global_position));transfer.update_carried();transfer.present_held(delta);props.sync(0)
		if actor.body_is_settled():session.stage="position";session.seconds=0.0;session.start=transfer._frame(id)
		return {"status":"progress"}
	var observed: Dictionary=actor.household_pose.telemetry()
	var ready: bool=actor.household_contacts_ready()
	if session.stage=="position" and session.seconds>=.8 and ready:session.stage="work";session.seconds=0.0
	if session.stage=="work" and observed.get("phase")=="work" and ready:
		# Body and working feature must both have been rendered at this same
		# stage. A prior carry/lift sample cannot advance kitchen work.
		if operation.work_kind=="score_food":
			var cuts: Array=_cuts();var cycle: float=fposmod(float(session.cut_seconds)/.65,1.0)
			if cycle>=.40 and cycle<=.52:session.scored[cuts[int(session.cut_index)%cuts.size()].id]=true
			if session.cut_seconds+delta>=.65:
				session.cut_index+=1;session.cut_seconds=fposmod(float(session.cut_seconds)+delta,.65)
			else:session.cut_seconds+=delta
		if life.set_physical_work(who,session.task,true) and minutes>0:
			var reply: Dictionary=life.perform(who,session.task,minutes)
			if reply.status=="phase_ready":
				# Scoring is represented by connected food geometry. Do not
				# finish it after a partial set of visually attempted cuts.
				if operation.work_kind=="score_food" and session.scored.size()<_cuts().size():reason="切れ目を一つずつ入れている"
				else:session.stage="complete";return {"status":"complete"}
			elif reply.status not in ["working","waiting_for_time"]:return reply
		session.work_seconds+=delta
	var desired: Transform3D=_tool_frame(float(session.work_seconds)) if not id.is_empty() else Transform3D.IDENTITY
	if session.stage=="position":session.seconds=minf(.8,float(session.seconds)+delta);desired=session.start.interpolate_with(desired,smoothstep(0,1,float(session.seconds)/.8))
	if not id.is_empty() and not transfer.set_carried_frame(id,desired):return {"status":"invalid","reason":"実物の道具を動かせない"}
	var action: String="prepare" if operation.work_kind=="score_food" else "transfer" if operation.work_kind=="inspect_materials" else "stir"
	var request := {"action":action,"phase":"lift" if session.stage=="position" else "work","progress":clampf(float(session.seconds)/.8,0,1) if session.stage=="position" else 1.0,"pose_seconds":0.0,
		"object":transfer._object_request(id,desired) if not id.is_empty() else {},"held_objects":transfer.held_requests(id),"targets_authoritative":true}
	if operation.work_kind=="inspect_materials":request.gaze_point=desired.origin+Vector3.UP*.08
	if not actor.use_household_pose(request):return {"status":"invalid","reason":"実物の作業姿勢を接続できない"}
	actor.tick_body(delta,false);props.sync(0)
	return {"status":"progress"}

func snapshot() -> Dictionary:return POSE._encode({"schema":1,"session":session})
func can_restore(data: Variant, restored: HouseholdDay, _body: Dictionary) -> bool:
	if not data is Dictionary or data.get("schema")!=1:return false
	var decoded: Variant=POSE._decode(data)
	if not decoded is Dictionary or not decoded.get("session") is Dictionary:return false
	var saved: Dictionary=decoded.session
	if saved.is_empty():return true
	if saved.get("stage") not in ["walk","align","position","work","complete"] or not saved.get("operation") is Dictionary or not saved.get("scored") is Dictionary or not saved.get("route_started") is bool:return false
	if not saved.get("task") is String or not restored.tasks.has(saved.task) or restored.tasks[saved.task].actor!=who or not POSE._valid_transform(saved.get("start")):return false
	for key in ["seconds","work_seconds","cut_seconds","cut_index"]:
		if not POSE._finite_number(saved.get(key)) or saved[key]<0 or saved[key]>10000:return false
	return true
func restore(data: Dictionary, restored: HouseholdDay, body: Dictionary) -> bool:
	if not can_restore(data,restored,body):return false
	session=POSE._decode(data).session.duplicate(true);reason="";return true

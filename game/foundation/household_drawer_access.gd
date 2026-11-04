class_name HouseholdDrawerAccess
extends RefCounted

# One physical attached-handle transaction. The actor motor alone translates
# the body; the household access value alone translates the drawer. No life
# minute, work, inventory, need relief or successful contact is manufactured.
const PHASES := ["reach","grasp","slide","release","recover"]
const TIMES := {"reach":.6,"grasp":.25,"release":.4,"recover":.4}
const FORMAT := 1
const CONTACT := .01
var home: LivingHouse
var day: HouseholdDay
var navigation: HomeNavigation
var fixtures: HouseholdKitchenFixtures
var actor: FoundationResident
var session: Dictionary={}
var reason := ""
var _completed := false
var _restore_pending := false
var _pose_root := Transform3D.IDENTITY
var _pose_access := -1.0

func configure(house: LivingHouse, household: HouseholdDay, paths: HomeNavigation, hardware: HouseholdKitchenFixtures, resident: FoundationResident) -> bool:
	if house==null or household==null or paths==null or hardware==null or resident==null or not is_instance_valid(resident.furniture_pose):return false
	if hardware.house!=house or hardware.life!=household or not household.people.has(resident.resident_id):return false
	for side in ["L","R"]:
		if not resident.furniture_pose.handle_palm_local(side) is Transform3D:return false
	home=house;day=household;navigation=paths;fixtures=hardware;actor=resident
	return true

func active() -> bool:return not session.is_empty()
func complete() -> bool:return _completed

func begin(task_id: String, descriptor: Dictionary) -> bool:
	if actor==null or active():reason="別の実動作が進行している";return false
	if not actor.body_is_settled():reason="身体と足を実際の立ち位置へ落ち着かせる";return false
	if descriptor.get("kind")!="access" or descriptor.get("status")!="ready":reason="実行可能な収納操作を指定する";return false
	var task: Dictionary=day.task_for(actor.resident_id)
	if task.get("id")!=task_id or task.status in HouseholdDay.TERMINAL or not _number(descriptor.get("target"),0,1) or (float(descriptor.target)!=0 and float(descriptor.target)!=1):reason="本人の進行中の行動と開閉先を指定する";return false
	var key: String=str(descriptor.get("access_id",""))
	if key!="fridge:drawer" or not day.access.has(key) or not _hands_free():reason="両手を空けてから引き出しを使う";return false
	var current: float=float(day.access[key]);var target: float=float(descriptor.target)
	var local_start: Vector3=_approach(current);var expected: Vector3=home.to_global(local_start)
	if actor.global_position.distance_to(expected)>.02 or absf(wrapf(actor.heading-_heading(),-PI,PI))>.02:reason="引き出しの前で身体を止めて向きを合わせる";return false
	var start: Transform3D=actor.global_transform
	var end := Transform3D(Basis(Vector3.UP,_heading()),home.to_global(_approach(target)))
	if not _static_path_clear(start.origin,end.origin):reason="引き出し操作の身体経路が塞がっている";return false
	day.set_position(actor.resident_id,home.to_local(actor.global_position))
	if not day.set_access(actor.resident_id,task_id,key,current):reason="実際の引き出しを予約できない";return false
	if absf(current-target)<.000001:_completed=true;reason="";return true
	actor.clear_action();actor.clear_household_pose()
	var hands := {}
	for side in ["L","R"]:
		var bone: int=actor.model.skeleton.find_bone("DEF-hand."+side)
		var frame: Transform3D=actor.model.skeleton.global_transform*actor.model.skeleton.get_bone_global_pose(bone)
		frame=frame*actor.furniture_pose.handle_palm_local(side)
		hands[side]=actor.global_transform.affine_inverse()*frame
	session={"task":task_id,"access_id":key,"initial":current,"target":target,"phase":"reach","elapsed":0.0,"duration":float(TIMES.reach),
		"root_start":start,"root_end":end,"home_hands":hands,"token":"drawer:"+task_id+":"+("open" if target>current else "close")}
	_completed=false;_restore_pending=false;_pose_access=-1;reason="取っ手へ両手を伸ばす"
	return true

func advance(delta: float) -> bool:
	if not active() or not _number(delta,0,1):return false
	if not _owns_task():reason="引き出しの実動作が終わるまで元の行動を維持する";return false
	if _restore_pending:
		fixtures.sync();_render(0);_restore_pending=false;return true
	var phase: String=session.phase
	if phase=="grasp" and float(session.elapsed)>=float(session.duration):
		if _contacts_ready():
			if not _start_slide():return false
			_render(delta);return true
		reason="実際の両掌と指が取っ手に触れるのを待つ";_render(delta);return true
	if phase=="slide":
		if not _contacts_ready():reason="取っ手との実接触を保ってから動かす";_render(0);return true
		if float(session.elapsed)>=float(session.duration):
			_enter("release");actor.clear_furniture_pose();_render(delta);return true
		if not actor.tick(delta):return false
		session.elapsed=float(actor.pose().interaction.get("elapsed",session.duration))
		var fraction: float=lerpf(float(session.initial),float(session.target),_ease(float(session.elapsed)/float(session.duration)))
		day.set_position(actor.resident_id,home.to_local(actor.global_position))
		if not day.set_access(actor.resident_id,session.task,session.access_id,fraction):reason="身体と引き出しの実位置が一致しない";return false
		fixtures.sync();reason="両手を添えたまま足を運んで引き出しを動かす";_render(delta);return true
	if phase=="release" and float(session.elapsed)>=float(session.duration):
		if not _release_ready():_render(0);return true
		_enter("recover");reason="取っ手から手を離して立ち姿へ戻る";_render(delta);return true
	if phase=="recover" and float(session.elapsed)>=float(session.duration):
		if not _palms_ready(false):_render(0);return true
		actor.clear_furniture_pose();session.clear();_completed=true;_pose_access=-1;reason="";actor.tick_body(delta,false);return true
	session.elapsed=minf(float(session.duration),float(session.elapsed)+delta)
	_render(delta)
	if phase=="reach" and float(session.elapsed)>=float(session.duration):_enter("grasp")
	return true

func _start_slide() -> bool:
	var seconds: float=maxf(.1,1.8*absf(float(session.target)-float(session.initial)))
	var frames: Array=[{"at":0.0,"position":session.root_start.origin,"heading":atan2(session.root_start.basis.z.x,session.root_start.basis.z.z)},
		{"at":seconds,"position":session.root_end.origin,"heading":_heading()}]
	if not actor.follow_interaction(session.token,frames):reason="身体を動かす唯一のmotorを予約できない";return false
	session.phase="slide";session.elapsed=0.0;session.duration=seconds
	return true

func _enter(phase: String) -> void:
	session.phase=phase;session.elapsed=0.0;session.duration=float(TIMES[phase])
	_pose_access=-1

func _render(delta: float) -> void:
	var phase: String=session.phase;var p: float=clampf(float(session.elapsed)/float(session.duration),0,1)
	var grips: Dictionary=fixtures.handle_points();var hands := {}
	var amount: float=0 if phase=="reach" else p if phase=="grasp" else 1-p if phase=="release" else 0 if phase=="recover" else 1
	for side in ["L","R"]:
		var frame: Transform3D=grips[side]
		if phase=="recover":frame=frame.interpolate_with(actor.global_transform*session.home_hands[side],_ease(p))
		hands[side]={"palm_transform":frame,"grip":amount}
	var moving: bool=phase=="slide"
	var root_start: Transform3D=session.root_start if moving else actor.global_transform
	var root_end: Transform3D=session.root_end if moving else actor.global_transform
	var request := {"kind":"fixture","phase":"fixture_pull" if float(session.target)>float(session.initial) else "fixture_push",
		"progress":p if moving else p*.5 if phase=="reach" else .5 if phase=="grasp" else 1.0,"root_start":root_start,"root_end":root_end,
		"seat_point":(grips.L.origin+grips.R.origin)*.5,"floor_y":home.to_global(Vector3.ZERO).y,"hands":hands,"feet":{},"handle":_handle_geometry(),"keep_hand_contact":phase!="reach"}
	actor.use_furniture_pose(request)
	_pose_root=actor.global_transform;_pose_access=float(day.access[session.access_id])
	actor.tick_body(delta,false)

func _fresh() -> bool:
	if not active() or _pose_access<0 or not actor.global_transform.is_equal_approx(_pose_root) or absf(float(day.access[session.access_id])-_pose_access)>.000001:return false
	var observed: Dictionary=actor.furniture_pose.telemetry()
	return not observed.is_empty() and observed.get("request_serial",-2)==observed.get("latest_sample_serial",-1)

func _palms_ready(on_handle: bool = true) -> bool:
	if not _fresh():return false
	var observed: Dictionary=actor.furniture_pose.telemetry();var targets: Dictionary=fixtures.handle_points() if on_handle else actor.furniture_pose.request_state().hands
	for side in ["L","R"]:
		var hand: Dictionary=observed.get("hands",{}).get(side,{})
		var target: Vector3=targets[side].origin if on_handle else targets[side].palm_transform.origin
		if not hand.get("actual_palm") is Vector3 or hand.actual_palm.distance_to(target)>CONTACT or float(hand.get("reach_residual_m",INF))>CONTACT:return false
	var feet: Dictionary=observed.get("feet",{})
	return float(feet.get("required_support_error_m",INF))<=.03 and float(feet.get("unreachable_peak_m",INF))<=.03

func _contacts_ready() -> bool:
	if not _palms_ready():return false
	var observed: Dictionary=actor.furniture_pose.telemetry()
	for side in ["L","R"]:
		for finger in ["thumb","index"]:
			if not bool(observed.hands[side].get("fingers",{}).get(finger,{}).get("contact",false)):return false
	return true

func _release_ready() -> bool:
	if not _palms_ready():return false
	var observed: Dictionary=actor.furniture_pose.telemetry()
	for side in ["L","R"]:
		for finger in ["thumb","index"]:
			if float(observed.hands[side].get("fingers",{}).get(finger,{}).get("observed_rotation",INF))>.15:return false
	return true

func _hands_free() -> bool:
	return _hands_free_in(day,actor.household_grasped_objects())

func _hands_free_in(life: HouseholdDay, grasped: Dictionary) -> bool:
	for item in life.equipment.values():
		if item.holder==actor.resident_id:return false
	for job in life.jobs.values():
		for field in ["plates","units"]:
			for item in job.get(field,[]):
				if item.holder==actor.resident_id:return false
	return grasped.is_empty()

func _owns_task() -> bool:
	var task: Dictionary=day.task_for(actor.resident_id)
	return task.get("id")==session.task and task.status not in HouseholdDay.TERMINAL and _hands_free()

func _approach(fraction: float) -> Vector3:
	var definition: Dictionary=day.plan.household_access["fridge:drawer"]
	return _v(definition.approach_closed).lerp(_v(definition.approach_open),fraction)

func _heading() -> float:
	var front: Vector3=(home.global_basis*LivingHouse.fixture_basis(home.fixtures.fridge.definition)).z
	return atan2(-front.x,-front.z)

func _handle_geometry() -> Dictionary:
	var mesh: MeshInstance3D=fixtures.drawer.get_node("Handle")
	var cylinder: CylinderMesh=mesh.mesh
	return {"a":mesh.to_global(Vector3(0,-cylinder.height*.5,0)),"b":mesh.to_global(Vector3(0,cylinder.height*.5,0)),"radius":cylinder.top_radius}

func _static_path_clear(from: Vector3, to: Vector3) -> bool:
	# The drawer moves with the body and is checked by actual contact/fixture
	# tests; static cases and walls must not be crossed by the motor track.
	var query := PhysicsShapeQueryParameters3D.new();var body := CylinderShape3D.new();body.radius=.24;body.height=1.65
	query.shape=body;query.margin=0;query.transform=Transform3D(Basis.IDENTITY,from+Vector3.UP*.825);query.motion=to-from
	var excluded: Array[RID]=[]
	for collider in home.get_tree().root.find_children("*","CollisionObject3D",true,false):
		if fixtures.drawer.is_ancestor_of(collider):excluded.append(collider.get_rid());continue
		var floor_body: bool=false
		for shape in collider.find_children("*","CollisionShape3D",true,false):
			if shape.shape is BoxShape3D and shape.global_position.y+shape.shape.size.y*.5<=home.global_position.y+.05:floor_body=true
		if floor_body:excluded.append(collider.get_rid())
	query.exclude=excluded
	var space: PhysicsDirectSpaceState3D=home.get_world_3d().direct_space_state
	if not space.intersect_shape(query,4).is_empty():return false
	var motion: PackedFloat32Array=space.cast_motion(query)
	return motion.size()==2 and motion[0]>=.99999

func snapshot() -> Dictionary:
	return FoundationLocomotionPose._encode({"version":FORMAT,"house_id":home.definition.house.id,"resident_id":actor.resident_id,"completed":_completed,"session":session})

func can_restore(data: Variant, restored_day: HouseholdDay = null, actor_motion: Dictionary = {}) -> bool:
	return not _checked(data,restored_day,actor_motion).is_empty()

func restore(data: Variant, restored_day: HouseholdDay = null, actor_motion: Dictionary = {}) -> bool:
	var checked := _checked(data,restored_day,actor_motion)
	if checked.is_empty():return false
	if restored_day!=null:day=restored_day
	session=checked.session.duplicate(true);_completed=checked.completed;_restore_pending=not session.is_empty();_pose_access=-1;reason="再開後の実接触を確認している" if active() else ""
	fixtures.sync()
	return true

func _checked(data: Variant, restored_day: HouseholdDay, actor_motion: Dictionary) -> Dictionary:
	if home==null or actor==null or not data is Dictionary or data.size()!=5 or not FoundationLocomotionPose._finite_tree(data):return {}
	if data.get("version")!=FORMAT or data.get("house_id")!=home.definition.house.id or data.get("resident_id")!=actor.resident_id or not data.get("completed") is bool or not data.get("session") is Dictionary:return {}
	var decoded: Variant=FoundationLocomotionPose._decode(data)
	var life: HouseholdDay=restored_day if restored_day!=null else day
	var motion: Dictionary=actor_motion if not actor_motion.is_empty() else actor.motion_state()
	if not actor.can_restore_motion(motion):return {}
	var motor: Dictionary=motion.motor
	if decoded.session.is_empty():
		if motor.state=="interaction" and str(motor.interaction.get("token","")).begins_with("drawer:"):return {}
		return decoded
	if decoded.completed:return {}
	var s: Dictionary=decoded.session
	if s.size()!=11 or not s.get("task") is String or s.get("access_id")!="fridge:drawer" or s.get("phase") not in PHASES or not _number(s.get("initial"),0,1) or not _number(s.get("target"),0,1) or (float(s.target)!=0 and float(s.target)!=1) or s.initial==s.target or not _number(s.get("elapsed"),0,5) or not _number(s.get("duration"),.000001,5):return {}
	if not _rigid(s.get("root_start")) or not _rigid(s.get("root_end")) or not s.get("home_hands") is Dictionary or s.home_hands.size()!=2:return {}
	for side in ["L","R"]:
		if not _rigid(s.home_hands.get(side)):return {}
	var task: Dictionary=life.task_for(actor.resident_id)
	if task.get("id")!=s.task or task.status in HouseholdDay.TERMINAL or not life.access.has(s.access_id):return {}
	if not _hands_free_in(life,motion.household.get("grasped_objects",{})) or motion.household.get("enabled",false) or not motion.action.is_empty():return {}
	if s.get("token")!="drawer:"+s.task+":"+("open" if s.target>s.initial else "close"):return {}
	var expected_duration: float=maxf(.1,1.8*absf(float(s.target)-float(s.initial))) if s.phase=="slide" else float(TIMES[s.phase])
	if absf(float(s.duration)-expected_duration)>.000001 or s.elapsed>s.duration:return {}
	if s.root_start.origin.distance_to(home.to_global(_approach(float(s.initial))))>.02 or s.root_end.origin.distance_to(home.to_global(_approach(float(s.target))))>.00001:return {}
	var fraction: float=float(s.initial) if s.phase in ["reach","grasp"] else lerpf(float(s.initial),float(s.target),_ease(float(s.elapsed)/float(s.duration))) if s.phase=="slide" else float(s.target)
	if absf(float(life.access[s.access_id])-fraction)>.000001:return {}
	var body: Vector3=_v(motor.position)
	if body.distance_to(home.to_global(_approach(fraction)))>.02 or absf(wrapf(float(motor.heading)-_heading(),-PI,PI))>.02:return {}
	if life.people[actor.resident_id].position.distance_to(home.to_local(body))>.00001:return {}
	if s.phase=="slide" and float(s.elapsed)<float(s.duration)-.000001:
		if motor.state!="interaction" or motor.interaction.get("token")!=s.token or absf(float(motor.interaction.get("elapsed",-1))-float(s.elapsed))>.000001:return {}
		var frames: Array=motor.interaction.frames
		if frames.size()!=2 or _v(frames[0].position).distance_to(s.root_start.origin)>.00001 or _v(frames[1].position).distance_to(s.root_end.origin)>.00001 or absf(float(frames[1].at)-float(s.duration))>.000001:return {}
	elif motor.state!="idle":return {}
	return decoded

static func _v(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func _ease(value: float) -> float:return smoothstep(0,1,clampf(value,0,1))
static func _number(value: Variant, low: float, high: float) -> bool:return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high
static func _rigid(value: Variant) -> bool:return value is Transform3D and value.is_finite() and value.origin.length()<10000 and absf(value.basis.determinant()-1)<.001 and absf(value.basis.x.length()-1)<.001 and absf(value.basis.y.length()-1)<.001 and absf(value.basis.z.length()-1)<.001

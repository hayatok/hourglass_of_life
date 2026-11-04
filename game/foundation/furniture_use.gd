class_name FoundationFurnitureUse
extends RefCounted

# A furniture transaction owns entering and leaving, not the life clock. The
# ResidentMotor remains the sole owner of the body's world transform. A chair's
# mesh, collision body and routing obstacle always receive the same movement.
var home: LivingHouse
var navigation: HomeNavigation
var occupancy: HomeOccupancy
var actor
var session: Dictionary = {}
var reason := ""
var _obstacles: Array = []

func configure(house: LivingHouse, paths: HomeNavigation, policy: HomeOccupancy, resident) -> bool:
	if house==null or paths==null or policy==null or resident==null:return false
	home=house;navigation=paths;occupancy=policy;actor=resident
	return true

func supports(task: Dictionary) -> bool:
	return home.fixtures.get(task.get("fixture",""),{}).get("definition",{}).get("type","") in ["chair","dining_seat","sofa","bed"]

func active() -> bool:return not session.is_empty()
func ready() -> bool:return active() and session.phase=="ready"
func clear() -> bool:return session.is_empty()
func exit_ready() -> bool:return active() and session.phase=="exit_ready" and actor.body_is_settled()
func posture() -> String:return "lie" if active() and session.kind=="bed" else "sit"
func progress() -> float:return clampf(float(session.get("elapsed",0))/maxf(.001,float(session.get("duration",1))),0,1)

func workspace() -> Dictionary:
	if not active() or session.kind!="chair" or session.phase in ["ready","exit_ready"]:return {}
	return {"position":session.original-session.face*session.pull*.5,"radius":.9}

func begin(task: Dictionary, obstacles: Array = []) -> bool:
	if active() or not supports(task) or not actor.body_is_settled():return false
	_obstacles=obstacles
	var fit: Dictionary=actor.furniture_calibration()
	if fit.is_empty():reason="身体と家具の接触を準備している";return false
	var fixture: Dictionary=home.fixtures[task.fixture].definition
	var heading: float=deg_to_rad(float(fixture.get("use_facing",fixture.facing)))
	var face:=Vector3(sin(heading),0,cos(heading))
	var original: Vector3=_v(fixture.position)
	var kind: String="bed" if fixture.type=="bed" else ("sofa" if fixture.type=="sofa" else "chair")
	session={"task":task.id,"fixture":task.fixture,"kind":kind,"phase":"begin","elapsed":0.0,"duration":1.0,
		"approach":actor.global_position,"authored_approach":task.target,"original":original,"heading":heading,"face":face,
		"seated_offset":fit.seated_pelvis_actor,"pelvis_height":float(fit.seat_pelvis_offset_y),
		"pull":float(fixture.get("pull_distance",.45)) if kind=="chair" else 0.0,"chair_offset":Vector3.ZERO,
		"leaving":false,"walk_target":Vector3.ZERO,"retry":0.0,"phase_root_start":actor.global_position}
	if kind=="chair":
		var space: Dictionary=workspace()
		for obstacle in obstacles:
			var relative: Vector3=obstacle.position-space.position
			var extent: float=float(space.radius)+float(obstacle.radius)
			if absf(relative.x)<extent and absf(relative.z)<extent:
				session.clear();reason="椅子のまわりが空くのを待っている";return false
		session.seat=original+Vector3.UP*float(fixture.seat_height)
		session.front=original-face*session.pull+face*float(fixture.get("front_clearance",.53))
		session.pulled_behind=actor.global_position-face*session.pull
		return _phase("chair_pull",1.8,session.pulled_behind,heading)
	if kind=="sofa":
		session.seat=Vector3(task.target.x,original.y+float(fixture.seat_height),original.z)+face*.20
		session.front=Vector3(session.seat.x,0,session.seat.z)+face*.50
		return _walk("sofa_front",session.front)
	var side: float=signf(actor.global_position.x-original.x)
	if side==0:side=1
	session.edge_heading=PI*.5*side
	session.edge_seat=Vector3(original.x+side*.32,float(fixture.get("sheet_y",.422)),actor.global_position.z)
	session.seat=session.edge_seat
	session.front=actor.global_position
	var north: float=original.z-float(fixture.size[2])*.5
	session.lie_root=Vector3(original.x,float(fixture.get("sheet_y",.422)),north+.18+float(actor.model.rest_height))
	session.lie_pelvis=Vector3(original.x,float(fixture.get("sheet_y",.422))+.13,session.lie_root.z-float(fit.standing_pelvis_actor.y))
	return _phase("bed_face",maxf(.5,absf(wrapf(float(session.edge_heading)-actor.heading,-PI,PI))/.9),actor.global_position,session.edge_heading)

func begin_exit() -> bool:
	if not active():return true
	session.leaving=true
	if not ready():return true # Finish the current safe entrance before reversing.
	if session.kind=="chair":
		return _phase("chair_slide_out",1.5,actor.global_position-session.face*session.pull,session.heading)
	if session.kind=="sofa":return _phase("sit_exit",1.3,session.front,session.heading)
	return _phase("sit_up",1.5,actor.global_position,actor.heading)

func advance(delta: float, obstacles: Array = []) -> bool:
	if not active() or not is_finite(delta) or delta<0 or delta>1:return false
	_obstacles=obstacles
	session.retry=maxf(0,float(session.retry)-delta)
	if session.phase=="exit_ready":actor.tick_body(delta);return true
	if str(session.phase) in ["bed_face","chair_face","sofa_face"]:
		actor.tick_body(delta)
		if actor.body_is_settled():return _after_phase()
		return true
	if str(session.phase) in ["chair_around","chair_return","sofa_front","sofa_return"]:
		actor.tick_body(delta)
		if actor.state()!="idle":return true
		if actor.global_position.distance_to(session.walk_target)>.065:
			if session.retry==0:_walk(session.phase,session.walk_target)
			return true
		return _after_walk()
	if ready():
		actor.use_furniture_pose(_request("lie_idle" if session.kind=="bed" else "sit_idle",1.0))
		actor.tick_body(delta)
		return true
	if not actor.tick(delta):return false
	session.elapsed=float(actor.pose().interaction.get("elapsed",session.duration))
	var phase: String=session.phase
	var pose_phase: String=phase
	if phase in ["chair_slide_in","chair_slide_out"]:pose_phase="chair_slide"
	if phase in ["bed_face","chair_face","sofa_face"]:pose_phase=""
	if session.kind=="chair":
		var fraction: float=_ease(progress())
		if phase in ["chair_slide_in","chair_slide_out"]:fraction=_ease(clampf((progress()-.22)/.52,0,1))
		match phase:
			"chair_pull":_move_chair(-session.face*session.pull*fraction)
			"chair_slide_in","chair_push":_move_chair(-session.face*session.pull*(1-fraction))
			"chair_slide_out":_move_chair(-session.face*session.pull*fraction)
	if not pose_phase.is_empty():actor.use_furniture_pose(_request(pose_phase,progress()))
	actor.tick_body(delta,false)
	if progress()>=1 and actor.state()=="idle":return _after_phase()
	return true

func _seated_root(seat: Vector3, heading: float) -> Vector3:
	var offset: Vector3=Basis(Vector3.UP,heading)*session.seated_offset
	return Vector3(seat.x-offset.x,0,seat.z-offset.z)

func _phase(name: String, seconds: float, target: Vector3, heading: float) -> bool:
	if actor.state()!="idle":return false
	if name in ["chair_slide_in","chair_slide_out"]:seconds=2.4
	session.phase=name;session.elapsed=0.0;session.duration=seconds;session.phase_root_start=actor.global_position
	if name in ["bed_face","chair_face","sofa_face"]:
		actor.clear_furniture_pose()
		return actor.face_heading(heading)
	var frames: Array=[{"at":0.0,"position":actor.global_position,"heading":actor.heading},
		{"at":seconds,"position":target,"heading":wrapf(heading,-PI,PI)}]
	if name in ["chair_slide_in","chair_slide_out"]:
		frames.insert(1,{"at":seconds*.22,"position":actor.global_position,"heading":actor.heading})
		frames.insert(2,{"at":seconds*.74,"position":target,"heading":wrapf(heading,-PI,PI)})
	if not actor.follow_interaction("furniture:"+session.fixture+":"+name,frames):reason="家具へ入る安全な動作を開始できない";return false
	return true

func _walk(name: String, target: Vector3) -> bool:
	actor.clear_furniture_pose()
	session.phase=name;session.walk_target=target;session.retry=.5
	var route: Dictionary=navigation.route(actor.global_position,target,actor.resident_id,occupancy,_obstacles)
	if route.status!="ready":reason=route.reason;return true
	if not actor.follow_path(route.points):reason="家具の横を通る経路を開始できない";return false
	reason="椅子の横を回っている" if session.kind=="chair" else "座面の前へ寄っている"
	return true

func _after_walk() -> bool:
	match str(session.phase):
		"chair_around","sofa_front":return _phase("chair_face" if session.kind=="chair" else "sofa_face",maxf(.5,absf(wrapf(float(session.heading)-actor.heading,-PI,PI))/.9),actor.global_position,session.heading)
		"chair_return":return _phase("chair_push",1.8,session.approach,session.heading)
		"sofa_return":return _complete_exit()
	return false

func _after_phase() -> bool:
	match str(session.phase):
		"chair_pull":return _walk("chair_around",session.front)
		"chair_face","sofa_face":
			var seat: Vector3=session.seat-session.face*session.pull
			return _phase("sit_enter",1.3,_seated_root(seat,session.heading),session.heading)
		"sit_enter":
			if session.kind=="chair":return _phase("chair_slide_in",1.5,actor.global_position+session.face*session.pull,session.heading)
			return _become_ready()
		"chair_slide_in","lie_down":return _become_ready()
		"chair_slide_out":return _phase("sit_exit",1.3,session.front,session.heading)
		"sit_exit":
			return _walk("chair_return",session.pulled_behind) if session.kind=="chair" else _walk("sofa_return",session.approach)
		"chair_push":return _complete_exit()
		"bed_face":return _phase("bed_seat",1.3,_seated_root(session.edge_seat,session.edge_heading),session.edge_heading)
		"bed_seat":return _phase("legs_in",1.6,session.lie_root,session.heading)
		"legs_in":return _phase("lie_down",1.5,actor.global_position,actor.heading)
		"sit_up":return _phase("legs_out",1.6,_seated_root(session.edge_seat,session.edge_heading),session.edge_heading)
		"legs_out":return _phase("bed_stand",1.3,session.approach,session.edge_heading)
		"bed_stand":return _complete_exit()
	return false

func _become_ready() -> bool:
	session.phase="ready";session.elapsed=0;session.duration=1
	if session.leaving:return begin_exit()
	return true

func _complete_exit() -> bool:
	# Keep the transaction until HouseholdDay confirms the physical exit. A
	# rejected exit cannot turn back into a fresh approach/arrival transaction.
	actor.clear_furniture_pose();session.phase="exit_ready";session.elapsed=0;session.duration=1;session.leaving=true;reason=""
	return true

func finalize_exit() -> bool:
	if not exit_ready():return false
	session.clear();reason=""
	return true

func _move_chair(offset: Vector3) -> void:
	home.set_fixture_displacement(session.fixture,offset)
	navigation.move_fixture(session.fixture,session.original+offset)
	session.chair_offset=offset

func _request(phase: String, at: float) -> Dictionary:
	var fixture: Dictionary=home.fixtures[session.fixture].definition
	var request: Dictionary={"kind":session.kind,"phase":phase,"progress":at,"seat_point":session.seat+session.chair_offset,"floor_y":0.0,"feet":{},"hands":{}}
	request.allow_dangling_feet=session.kind=="sofa"
	var track: Dictionary=actor.pose().interaction
	if not track.is_empty():
		var start: Dictionary=track.frames[0]
		var end: Dictionary=track.frames[-1]
		request.root_start=Transform3D(Basis(Vector3.UP,float(start.heading)),_v(start.position))
		request.root_end=Transform3D(Basis(Vector3.UP,float(end.heading)),_v(end.position))
	else:request.root_start=actor.global_transform;request.root_end=actor.global_transform
	if fixture.has("footrest"):
		request.footrest={"center":_v(fixture.footrest.center)+session.chair_offset,"half_width":fixture.footrest.half_width,
			"half_depth":fixture.footrest.half_depth,"support_kind":fixture.footrest.support_kind,
			"yaw":deg_to_rad(float(fixture.footrest.yaw_degrees)),"support_y":float(fixture.footrest.center[1])}
	if phase in ["chair_pull","chair_push"]:
		var face: Vector3=session.face
		var side:=Vector3(face.z,0,-face.x)
		var grip: Vector3=session.original+session.chair_offset-face*float(fixture.size[2])*.4+Vector3.UP*(float(fixture.size[1])-.10)
		for pair in [["L",.13],["R",-.13]]:request.hands[pair[0]]={"palm_transform":Transform3D(Basis(Vector3.UP,session.heading),grip+side*float(pair[1])),"grip":true}
	if session.kind=="bed":
		var pelvis: Vector3=session.lie_pelvis
		var edge_pelvis: Vector3=session.edge_seat+Vector3.UP*float(session.pelvis_height)
		if phase=="legs_in":pelvis=edge_pelvis.lerp(session.lie_pelvis,_ease(at))
		elif phase=="legs_out":pelvis=session.lie_pelvis.lerp(edge_pelvis,_ease(at))
		request.bed={"sheet_y":float(fixture.get("sheet_y",.422)),"pillow_point":_v(fixture.pillow_point),
			"head_direction":Vector3.FORWARD,"pelvis_point":pelvis}
	return request

func snapshot() -> Dictionary:
	return {"schema":1,"session":HouseholdDay._encode(session),"reason":reason}

func can_restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema")!=1 or not data.get("session") is Dictionary or not data.get("reason") is String:return false
	var restored: Variant=HouseholdDay._decode(data.session)
	if not restored is Dictionary:return false
	if restored.is_empty():return true
	if not home.fixtures.has(restored.get("fixture","")) or restored.get("kind") not in ["chair","sofa","bed"] or not restored.get("task") is String:return false
	if restored.get("phase") not in ["chair_pull","chair_around","chair_face","sofa_face","sit_enter","chair_slide_in","ready","chair_slide_out","sit_exit","chair_return","chair_push","sofa_front","sofa_return","bed_face","bed_seat","legs_in","lie_down","sit_up","legs_out","bed_stand","exit_ready"]:return false
	for key in ["elapsed","duration","heading","pull","pelvis_height","retry"]:
		if not _finite(restored.get(key)):return false
	if restored.elapsed<0 or restored.duration<=0 or restored.duration>30 or restored.elapsed>restored.duration or restored.retry<0 or restored.retry>1 or absf(restored.heading)>PI+.001 or restored.pull<0 or restored.pull>1:return false
	for key in ["approach","authored_approach","original","face","seated_offset","chair_offset","walk_target","phase_root_start","seat","front"]:
		if not restored.get(key) is Vector3 or not restored[key].is_finite() or restored[key].length()>100:return false
	if not restored.get("leaving") is bool:return false
	var authored: Dictionary=home.fixtures[restored.fixture].definition
	var expected_heading: float=deg_to_rad(float(authored.get("use_facing",authored.facing)))
	var expected_face:=Vector3(sin(expected_heading),0,cos(expected_heading))
	if restored.original.distance_to(_v(authored.position))>.00001 or absf(wrapf(float(restored.heading)-expected_heading,-PI,PI))>.00001 or restored.face.distance_to(expected_face)>.00001:return false
	if restored.approach.distance_to(restored.authored_approach)>.18 or restored.chair_offset.length()>1:return false
	if restored.kind=="chair":
		if authored.type not in ["chair","dining_seat"] or absf(float(restored.pull)-float(authored.get("pull_distance",.45)))>.000001:return false
		var amount: float=restored.chair_offset.dot(-expected_face)
		if amount<-.00001 or amount>float(restored.pull)+.00001 or restored.chair_offset.distance_to(-expected_face*amount)>.00001:return false
	elif restored.kind!=authored.type or restored.pull!=0 or restored.chair_offset!=Vector3.ZERO:return false
	if restored.kind=="bed":
		if not _finite(restored.get("edge_heading")):return false
		for key in ["edge_seat","lie_root","lie_pelvis"]:
			if not restored.get(key) is Vector3 or not restored[key].is_finite() or restored[key].length()>100:return false
	else:
		if restored.kind=="chair" and (not restored.get("pulled_behind") is Vector3 or not restored.pulled_behind.is_finite()):return false
	return true

func can_restore_transaction(data: Dictionary, task: Dictionary, entry: Dictionary, motion: Dictionary) -> bool:
	if not can_restore(data):return false
	if not motion.get("motor") is Dictionary or ResidentMotor._checked_snapshot(motion.motor).is_empty():return false
	var saved: Dictionary=HouseholdDay._decode(data.session)
	var motor: Dictionary=motion.motor
	if saved.is_empty():
		if entry.state in ["enter","exit"] or motor.state=="interaction":return false
		return task.get("usage",{}).get("state","") not in ["using","exiting"]
	if task.is_empty() or task.id!=saved.task or task.fixture!=saved.fixture or entry.task!=saved.task or int(entry.phase)!=int(task.phase_index):return false
	if entry.state not in ["enter","use","exit"] or not task.get("usage",{}).get("required",false) or task.usage.state not in ["entering","using","exiting"]:return false
	if saved.authored_approach.distance_to(task.target)>.00001:return false
	if task.usage.state=="using" and saved.phase!="ready":return false
	if task.usage.state=="exiting" and not saved.leaving:return false
	if saved.phase=="exit_ready":return task.usage.state=="exiting" and motor.state=="idle"
	if saved.phase=="ready":return motor.state=="idle"
	if saved.phase in ["chair_around","chair_return","sofa_front","sofa_return","chair_face","sofa_face","bed_face"]:
		return motor.state!="interaction"
	if motor.state!="interaction" or motor.interaction.token!="furniture:"+saved.fixture+":"+saved.phase:return false
	if absf(float(motor.interaction.elapsed)-float(saved.elapsed))>.000001:return false
	var frames: Array=motor.interaction.frames
	var expected_count: int=4 if saved.phase in ["chair_slide_in","chair_slide_out"] else 2
	if frames.size()!=expected_count or absf(float(frames[-1].at)-float(saved.duration))>.000001 or _v(frames[0].position).distance_to(saved.phase_root_start)>.00001:return false
	if expected_count==4:
		if absf(float(frames[1].at)-float(saved.duration)*.22)>.000001 or absf(float(frames[2].at)-float(saved.duration)*.74)>.000001:return false
		if _v(frames[1].position).distance_to(_v(frames[0].position))>.00001 or _v(frames[2].position).distance_to(_v(frames[-1].position))>.00001:return false
	return true

func restore(data: Variant) -> bool:
	if not can_restore(data):return false
	if active() and session.kind=="chair":_move_chair(Vector3.ZERO)
	session=HouseholdDay._decode(data.session);reason=data.reason
	if active() and session.kind=="chair":_move_chair(session.chair_offset)
	return true

static func _v(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func _ease(value: float) -> float:return value*value*(3-2*value)
static func _finite(value: Variant) -> bool:return (value is float or value is int) and is_finite(float(value))

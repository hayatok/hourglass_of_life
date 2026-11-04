extends SceneTree

# Floor support only. The L fixture deliberately has no perimeter walls, so a
# bounds-as-floor shortcut cannot be hidden by otherwise-correct wall geometry.
# Real-house routing and actual downward collision rays are checked separately.
const RADIUS := .24
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:
	create_timer(35).timeout.connect(func():push_error("Home floor support timed out");quit(1))
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func point(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])

func reference_floors(plan: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for zone in plan.rooms+plan.external_zones:
		var b: Array=zone.bounds;result.append(Rect2(b[0],b[1],b[2],b[3]))
	for door in plan.doors:
		var width: float=float(door.width);var thickness: float=float(plan.house.wall_thickness)
		var size := Vector2(width,thickness) if door.axis=="x" else Vector2(thickness,width)
		result.append(Rect2(Vector2(door.center[0],door.center[2])-size*.5,size))
	return result

func on_floor(at: Vector2, floors: Array[Rect2]) -> bool:
	for rect: Rect2 in floors:
		if at.x>=rect.position.x-.00001 and at.x<=rect.end.x+.00001 and at.y>=rect.position.y-.00001 and at.y<=rect.end.y+.00001:return true
	return false

func supported(origin: Vector3, points: Array, floors: Array[Rect2]) -> bool:
	for target: Vector3 in points:
		var count: int=maxi(1,ceili(origin.distance_to(target)/.025))
		for i in range(count+1):
			var p: Vector3=origin.lerp(target,float(i)/count)
			for corner in [Vector2.ZERO,Vector2(-RADIUS,-RADIUS),Vector2(-RADIUS,RADIUS),Vector2(RADIUS,-RADIUS),Vector2(RADIUS,RADIUS)]:
				if not on_floor(Vector2(p.x,p.z)+corner,floors):return false
		origin=target
	return true

func l_plan() -> Dictionary:
	return {"house":{"id":"isolated_l_floor","household":"floor_fixture","bounds":[0,0,6,6],"width":6,"depth":6,"wall_thickness":.2,"wall_height":2.65,"floor_y":0},
		"rooms":[{"id":"north_wing","bounds":[.2,.2,5.6,1.6],"allowed_residents":["resident"],"private_scope":"household","occupancy_limit":2},
			{"id":"west_wing","bounds":[.2,2.,1.6,3.8],"allowed_residents":["resident"],"private_scope":"household","occupancy_limit":2}],
		"external_zones":[],"fixtures":[],"residents":[{"id":"resident"}],
		"walls":[{"id":"elbow","start":[.2,1.9],"end":[1.8,1.9]}],
		"doors":[{"id":"link","wall":"elbow","room_a":"north_wing","room_b":"west_wing","center":[1,0,1.9],"axis":"x","width":1.,"height":2.1,"kind":"opening","default_state":"open","approaches":{"north_wing":[1,0,1.2],"west_wing":[1,0,2.6]}}]}

func l_void() -> void:
	var plan := l_plan();var nav := HomeNavigation.new()
	expect(nav.configure(plan,RADIUS),"The isolated L floor fixture configures without inventing a rectangular room")
	var origin := Vector3(5,0,1);var target := Vector3(1,0,5)
	var floors: Array[Rect2]=reference_floors(plan)
	expect(not supported(origin,[target],floors),"The straight diagonal between L wings has no real floor support")
	var route: Dictionary=nav.route(origin,target,"resident")
	expect(route.status=="ready" and route.points.size()>1 and supported(origin,route.points,floors),"A full body follows the real L floor and threshold instead of smoothing across the unbuilt courtyard")
	expect(nav.route(origin,Vector3(4,0,4),"resident").status!="ready","A target in the house extent but outside every real floor is unreachable")
	var path := "user://home-floor-l-fixture.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(plan))
	var house := LivingHouse.new();root.add_child(house)
	expect(house.load_plan(path),"The native isolated floor stage loads the same authored L surfaces")
	await physics_frame;await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(4,.1,4),Vector3(4,-.3,4))
	expect(house.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"A downward physics ray sees no phantom floor in the unbuilt courtyard")
	query=PhysicsRayQueryParameters3D.create(Vector3(1,.1,1.9),Vector3(1,-.3,1.9))
	var hit: Dictionary=house.get_world_3d().direct_space_state.intersect_ray(query)
	expect(not hit.is_empty() and hit.collider.get_meta("door_id","")=="link" and absf(hit.position.y)<.00001,"The door's wall-thickness gap has an actual native threshold floor at exactly floor_y")
	house.free();DirAccess.remove_absolute(path);await process_frame

func g1_support() -> void:
	var path := "res://data/foundation/ogawa-home.json"
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var nav := HomeNavigation.new();var policy := HomeOccupancy.new()
	expect(nav.configure(plan,RADIUS) and policy.configure(plan),"The current G1 house configures with room and threshold floors")
	var floors: Array[Rect2]=reference_floors(plan)
	var origin: Vector3=point(plan.doors[0].approaches.outside)
	var members: Array=plan.residents.map(func(p):return p.id)
	var rooms: Dictionary={}
	for room in plan.rooms:rooms[room.id]=room
	var reached := true
	for fixture in plan.fixtures:
		var actor: String=str(fixture.owner) if fixture.get("private",false) and fixture.owner in members else str(members[0])
		if fixture.room!="outside" and actor not in rooms[fixture.room].allowed_residents:actor=rooms[fixture.room].allowed_residents[0]
		var target: Vector3=point(fixture.interaction_point)
		var route: Dictionary=nav.route(origin,target,actor,policy)
		if route.status!="ready" or not supported(origin,route.points,floors):
			print("FLOOR_ROUTE_FAILURE ",fixture.id," ",route.status);reached=false
	expect(reached,"Every current G1 fixture approach has a swept-body route supported by actual room, threshold and porch floors")
	var house := LivingHouse.new();root.add_child(house);house.load_plan(path)
	for id in house.doors:house.set_door_open(id,true)
	await physics_frame;await physics_frame
	var physical: bool=house.thresholds.size()==plan.doors.size()
	for door in plan.doors:
		var center: Vector3=point(door.center)
		var tangent := Vector3.RIGHT if door.axis=="x" else Vector3.BACK
		for offset in [-.3,0.,.3]:
			var at: Vector3=center+tangent*float(door.width)*offset
			var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*.04,at+Vector3.DOWN*.3)
			var hit: Dictionary=house.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or hit.collider.get_meta("door_id","")!=door.id or absf(hit.position.y-float(plan.house.floor_y))>.00001:physical=false
		house.cutaway=true;house.update_cutaway(Vector3(20,15,20))
		if not house.thresholds[door.id].node.is_visible_in_tree():physical=false
	expect(physical,"All G1 door gaps have real body-wide threshold colliders, aligned with both floors and retained through cutaway")
	house.free();await process_frame

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	await l_void();await g1_support()
	print("Home floor support: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

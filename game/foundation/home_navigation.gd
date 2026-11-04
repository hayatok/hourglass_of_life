class_name HomeNavigation
extends RefCounted

const Occupancy = preload("res://game/foundation/home_occupancy.gd")
const STEP := 0.1
const EPS := 0.00001
var _house_id := ""
var _radius := .24
var _floor_y := 0.0
var _zones: Dictionary = {}
var _doors: Dictionary = {}
var _floors: Array = []
var _solids: Array = []
var _free_cells: Dictionary = {}
var _wall_solids: Array = []
var _fixture_solids: Dictionary = {}
var _fixture_shapes: Dictionary = {}
var _transient_solids: Dictionary = {}
var _grid: AStarGrid2D
var _baseline

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value))<=1000

static func _vector(value: Variant, length: int) -> bool:
	if not value is Array or value.size()!=length: return false
	return value.all(func(component): return _number(component))

static func _rect(bounds: Array) -> Rect2:
	return Rect2(bounds[0],bounds[1],bounds[2],bounds[3])

static func _point(value: Array) -> Vector2:
	return Vector2(value[0],value[2])

static func _inside(point: Vector2, rect: Rect2) -> bool:
	return point.x>=rect.position.x-EPS and point.y>=rect.position.y-EPS and point.x<=rect.end.x+EPS and point.y<=rect.end.y+EPS

static func _clip(first: Vector2, last: Vector2, rect: Rect2) -> Variant:
	var low := 0.0;var high := 1.0;var delta := last-first
	for axis in 2:
		if absf(delta[axis])<EPS:
			if first[axis]<rect.position[axis]-EPS or first[axis]>rect.end[axis]+EPS: return null
		else:
			var a: float = (rect.position[axis]-first[axis])/delta[axis]
			var b: float = (rect.end[axis]-first[axis])/delta[axis]
			low = maxf(low,minf(a,b));high = minf(high,maxf(a,b))
			if low>high+EPS: return null
	return Vector2(low,high)

static func threshold_rect(door: Dictionary, thickness: float) -> Rect2:
	# This exact rectangle also creates the real threshold floor in LivingHouse.
	var center := _point(door.center)
	return Rect2(center-Vector2(float(door.width)*.5,thickness*.5),Vector2(door.width,thickness)) if door.axis=="x" else Rect2(center-Vector2(thickness*.5,float(door.width)*.5),Vector2(thickness,door.width))

func configure(plan: Variant, radius: float = .24) -> bool:
	var baseline = Occupancy.new()
	if not baseline.configure(plan) or not is_finite(radius) or radius<.05 or radius>1: return false
	if not _number(plan.house.get("wall_thickness")) or plan.house.wall_thickness<=0 or not _vector(plan.house.get("bounds"),4) or not _number(plan.house.get("floor_y",0)): return false
	if plan.house.bounds[2]<=0 or plan.house.bounds[3]<=0 or plan.house.bounds[2]>64 or plan.house.bounds[3]>64: return false
	if not plan.get("walls") is Array or plan.walls.is_empty() or plan.walls.size()>512: return false
	var walls := {};var zones := {};var doors := {};var solids: Array = []
	var thickness: float = plan.house.wall_thickness
	var house_bounds: Rect2 = _rect(plan.house.bounds)
	var floors: Array = []
	for room in plan.rooms:
		if not house_bounds.encloses(_rect(room.bounds)): return false
		floors.append(_rect(room.bounds))
	for zone in plan.external_zones: floors.append(_rect(zone.bounds))
	# bounds is an extent, never a substitute floor for a courtyard, a notch,
	# wall thickness or an unbuilt part of an L-shaped house.
	var envelope: Rect2 = house_bounds
	for floor_rect: Rect2 in floors: envelope = envelope.merge(floor_rect)
	if ceili(envelope.size.x/STEP+2)*ceili(envelope.size.y/STEP+2)>1000000: return false
	for room in plan.rooms+plan.external_zones: zones[room.id] = _rect(room.bounds)
	for wall in plan.walls:
		if not wall is Dictionary or not wall.get("id") is String or walls.has(wall.id) or not _vector(wall.get("start"),2) or not _vector(wall.get("end"),2): return false
		var first := Vector2(wall.start[0],wall.start[1]);var last := Vector2(wall.end[0],wall.end[1])
		if first.distance_to(last)<EPS or (absf(first.x-last.x)>EPS and absf(first.y-last.y)>EPS): return false
		walls[wall.id] = wall.duplicate(true)
	for authored in plan.doors:
		if not walls.has(authored.get("wall","")) or authored.get("axis","") not in ["x","z"] or not _vector(authored.get("center"),3) or not _number(authored.get("width")) or authored.width<=0: return false
		if authored.get("kind","") not in ["opening","hinged","sliding"] or not authored.get("approaches") is Dictionary or authored.approaches.size()!=2: return false
		for room in [authored.room_a,authored.room_b]:
			if not _vector(authored.approaches.get(room),3) or not _inside(_point(authored.approaches[room]),zones[room]): return false
		var wall: Dictionary = walls[authored.wall]
		var axis: int = 0 if authored.axis=="x" else 1
		var center := _point(authored.center)
		var low: float = center[axis]-float(authored.width)*.5;var high: float = center[axis]+float(authored.width)*.5
		if absf(float(wall.start[1-axis])-float(wall.end[1-axis]))>EPS or absf(float(wall.start[1-axis])-center[1-axis])>EPS: return false
		if low<minf(wall.start[axis],wall.end[axis])-EPS or high>maxf(wall.start[axis],wall.end[axis])+EPS: return false
		for room in [authored.room_a,authored.room_b]:
			var bounds: Rect2 = zones[room]
			if low<bounds.position[axis]-EPS or high>bounds.end[axis]+EPS: return false
			if absf(bounds.position[1-axis]-thickness*.5-center[1-axis])>EPS and absf(bounds.end[1-axis]+thickness*.5-center[1-axis])>EPS: return false
		if authored.get("kind","")=="sliding":
			if not _vector(authored.get("pocket_interval"),2): return false
			var pocket: Array = authored.pocket_interval
			if pocket[1]-pocket[0]<float(authored.width)-EPS or pocket[0]<minf(wall.start[axis],wall.end[axis])-EPS or pocket[1]>maxf(wall.start[axis],wall.end[axis])+EPS: return false
			if not (pocket[1]<=low+EPS or pocket[0]>=high-EPS): return false
		var door: Dictionary = authored.duplicate(true)
		door.navigation_rect = threshold_rect(door,thickness)
		door.narrow = float(door.width)<=2*radius+EPS
		doors[door.id] = door
		floors.append(door.navigation_rect)
	for wall in walls.values():
		var first := Vector2(wall.start[0],wall.start[1]);var last := Vector2(wall.end[0],wall.end[1])
		var axis: int = 0 if absf(first.y-last.y)<EPS else 1
		var low: float = minf(first[axis],last[axis]);var high: float = maxf(first[axis],last[axis])
		var cuts: Array = []
		for door in doors.values():
			if door.wall==wall.id:
				var center := _point(door.center)
				cuts.append(Vector2(center[axis]-float(door.width)*.5,center[axis]+float(door.width)*.5))
		cuts.sort_custom(func(a,b): return a.x<b.x)
		var cursor := low
		cuts.append(Vector2(high,high))
		for cut: Vector2 in cuts:
			if cut.x<cursor-EPS: return false
			if cut.x>cursor+EPS:
				var rect := Rect2(cursor,first.y-thickness*.5,cut.x-cursor,thickness) if axis==0 else Rect2(first.x-thickness*.5,cursor,thickness,cut.x-cursor)
				solids.append(rect.grow(radius))
			cursor = cut.y
	var fixture_solids := {};var fixture_shapes := {}
	for fixture in plan.fixtures:
		if not _vector(fixture.get("position"),3) or not _vector(fixture.get("size"),3) or not _vector(fixture.get("interaction_point"),3) or fixture.size.any(func(value): return value<=0): return false
		if fixture.has("blocking") and not fixture.blocking is bool: return false
		var rect := Rect2(_point(fixture.position)-Vector2(fixture.size[0],fixture.size[2])*.5,Vector2(fixture.size[0],fixture.size[2]))
		if not zones[fixture.room].encloses(rect): return false
		if fixture.get("blocking",true):
			fixture_solids[fixture.id]=rect.grow(radius)
			fixture_shapes[fixture.id]={"size":rect.size,"room":fixture.room}
	# Derived geometry is committed only after the authored plan is consistent.
	_house_id = plan.house.id;_radius = radius;_floor_y = float(plan.house.get("floor_y",0))
	_zones = zones;_doors = doors;_wall_solids = solids;_fixture_solids=fixture_solids;_fixture_shapes=fixture_shapes
	_transient_solids.clear();_solids=_wall_solids+_fixture_solids.values();_baseline = baseline
	_floors = floors
	_grid = AStarGrid2D.new();_grid.cell_size = Vector2(STEP,STEP)
	_grid.offset = Vector2(floorf(envelope.position.x/STEP)*STEP,floorf(envelope.position.y/STEP)*STEP)
	_grid.region = Rect2i(Vector2i.ZERO,Vector2i(ceili((envelope.end.x-_grid.offset.x)/STEP)+1,ceili((envelope.end.y-_grid.offset.y)/STEP)+1))
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_grid.update();_free_cells = {}
	for z in _grid.region.size.y:
		for x in _grid.region.size.x:
			var cell := Vector2i(x,z);var position: Vector2 = _grid.get_point_position(cell)
			var clear := _point_clear(position,[])
			_grid.set_point_solid(cell,not clear)
			if clear: _free_cells[cell]=true
	return true

func move_fixture(id: String, position: Vector3) -> bool:
	# Moving a dining chair moves its physical routing obstacle as well as its
	# rendered mesh. Only its affected cells are refreshed, including freed cells.
	if _grid==null or not _fixture_shapes.has(id) or not position.is_finite() or absf(position.y-_floor_y)>.01:return false
	var shape: Dictionary=_fixture_shapes[id]
	var rect:=Rect2(Vector2(position.x,position.z)-shape.size*.5,shape.size)
	if not _zones[shape.room].encloses(rect):return false
	var before: Rect2=_fixture_solids[id]
	var after:=rect.grow(_radius)
	if before==after:return true
	_fixture_solids[id]=after;_solids=_wall_solids+_fixture_solids.values()+_transient_solids.values()
	_refresh_changed_rect(before,after)
	return true

func set_transient_rect(id: String, footprint: Rect2) -> bool:
	# The caller supplies the actual hardware projection, without body padding.
	# Opening a drawer changes routing even when no body walks into its cabinet.
	if _grid==null or id.is_empty() or id.length()>96 or not footprint.position.is_finite() or maxf(absf(footprint.position.x),absf(footprint.position.y))>1000 or not footprint.size.is_finite() or not footprint.has_area() or maxf(footprint.size.x,footprint.size.y)>64:return false
	var before: Rect2=_transient_solids.get(id,Rect2())
	var after: Rect2=footprint.grow(_radius)
	if before==after:return true
	_transient_solids[id]=after;_solids=_wall_solids+_fixture_solids.values()+_transient_solids.values()
	_refresh_changed_rect(before,after)
	return true

func clear_transient_rect(id: String) -> bool:
	if not _transient_solids.has(id):return true
	var before: Rect2=_transient_solids[id];_transient_solids.erase(id)
	_solids=_wall_solids+_fixture_solids.values()+_transient_solids.values()
	_refresh_changed_rect(before,Rect2())
	return true

func _refresh_changed_rect(before: Rect2, after: Rect2) -> void:
	var affected: Rect2=before.merge(after).grow(STEP)
	if not before.has_area():affected=after.grow(STEP)
	elif not after.has_area():affected=before.grow(STEP)
	var first:=Vector2i(floori((affected.position.x-_grid.offset.x)/STEP),floori((affected.position.y-_grid.offset.y)/STEP))
	var last:=Vector2i(ceili((affected.end.x-_grid.offset.x)/STEP),ceili((affected.end.y-_grid.offset.y)/STEP))
	first=first.max(_grid.region.position);last=last.min(_grid.region.end-Vector2i.ONE)
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell:=Vector2i(x,z)
			if not _grid.is_in_boundsv(cell):continue
			var position: Vector2=_grid.get_point_position(cell)
			# Sub-grid hardware motion usually changes no cell's occupancy. Keep
			# exact geometry for segment checks while avoiding a full grid rebuild.
			if (before.has_area() and _inside(position,before))==(after.has_area() and _inside(position,after)):continue
			var clear:=_point_clear(position,[])
			_grid.set_point_solid(cell,not clear)
			if clear:_free_cells[cell]=true
			else:_free_cells.erase(cell)

func _point_clear(point: Vector2, additional: Array) -> bool:
	for rect: Rect2 in _solids+additional:
		if _inside(point,rect): return false
	for offset in [Vector2.ZERO,Vector2(-_radius,-_radius),Vector2(-_radius,_radius),Vector2(_radius,-_radius),Vector2(_radius,_radius)]:
		var on_floor := false
		for floor_rect: Rect2 in _floors:
			if _inside(point+offset,floor_rect): on_floor = true;break
		if not on_floor: return false
	return true

func _segment_clear(first: Vector2, last: Vector2, additional: Array) -> bool:
	for rect: Rect2 in _solids+additional:
		if _clip(first,last,rect)!=null: return false
	# Exact interval coverage of the square body's corners across the union of
	# house and porch floors prevents smoothing a corner into off-floor space.
	for offset in [Vector2.ZERO,Vector2(-_radius,-_radius),Vector2(-_radius,_radius),Vector2(_radius,-_radius),Vector2(_radius,_radius)]:
		var intervals: Array = []
		for floor_rect: Rect2 in _floors:
			var interval = _clip(first+offset,last+offset,floor_rect)
			if interval!=null: intervals.append(interval)
		intervals.sort_custom(func(a,b): return a.x<b.x)
		var covered := 0.0
		for interval: Vector2 in intervals:
			if interval.x>covered+EPS: return false
			covered = maxf(covered,interval.y)
		if covered<1-EPS: return false
	return true

func _zone_at(point: Vector2) -> String:
	for key in _zones:
		if _inside(point,_zones[key]): return key
	for door in _doors.values():
		if not _inside(point,door.navigation_rect): continue
		var best := "";var distance := INF
		for key in [door.room_a,door.room_b]:
			var approach := _point(door.approaches[key])
			if point.distance_squared_to(approach)<distance: best = key;distance = point.distance_squared_to(approach)
		return best
	return ""

func _nearest(point: Vector2, additional: Array) -> Vector2i:
	var center := Vector2i(roundi((point.x-_grid.offset.x)/STEP),roundi((point.y-_grid.offset.y)/STEP))
	var chosen := Vector2i(-1,-1);var distance := INF
	for z in range(-2,3):
		for x in range(-2,3):
			var cell := center+Vector2i(x,z)
			if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell): continue
			var candidate: Vector2 = _grid.get_point_position(cell)
			if point.distance_squared_to(candidate)<distance and _segment_clear(point,candidate,additional):
				chosen = cell;distance = point.distance_squared_to(candidate)
	return chosen

func _failure(status: String, reason: String) -> Dictionary:
	return {"status":status,"points":[],"doors":[],"rooms":[],"reason":reason}

func _blocked_reason(origin: String, target: String, person: String, occupancy) -> Dictionary:
	var queue: Array = [origin];var previous := {};var via := {}
	previous[origin] = ""
	while not queue.is_empty():
		var room: String = queue.pop_front()
		if room==target: break
		for door in _doors.values():
			var other: String = door.room_b if door.room_a==room else (door.room_a if door.room_b==room else "")
			if other.is_empty() or previous.has(other): continue
			previous[other] = room;via[other] = door.id;queue.append(other)
	if not previous.has(target): return _failure("unreachable","部屋同士がつながっていない。")
	var chain: Array = [];var current := target
	while current!=origin: chain.push_front({"room":current,"door":via[current]});current = previous[current]
	for entry in chain:
		var barrier: Dictionary = occupancy.door_status(entry.door,person)
		if barrier.status!="ready": return _failure(barrier.status,barrier.reason)
		if _doors[entry.door].narrow: return _failure("blocked","体の幅を確保できない開口がある。")
		var access: Dictionary = occupancy.room_status(entry.room,person)
		if access.status!="ready": return _failure(access.status,access.reason)
	return _failure("unreachable","壁や家具を避けて到達できる経路がない。")

func route(from: Vector3, to: Vector3, person: String, occupancy = null, obstacles: Array = []) -> Dictionary:
	if _grid==null: return _failure("unreachable","住宅の経路が準備されていない。")
	if not from.is_finite() or not to.is_finite() or absf(from.y-_floor_y)>.25 or absf(to.y-_floor_y)>.25: return _failure("unreachable","同じ階の有効な座標を指定する必要がある。")
	var policy = _baseline if occupancy==null else occupancy
	if not policy is Object or not policy.has_method("room_status") or policy.get("house_id")!=_house_id: return _failure("unreachable","この住宅の占有情報が必要。")
	var first := Vector2(from.x,from.z);var last := Vector2(to.x,to.z)
	var origin := _zone_at(first);var target := _zone_at(last)
	if origin.is_empty() or target.is_empty(): return _failure("unreachable","床や部屋の外に目的地がある。")
	var destination: Dictionary = policy.room_status(target,person)
	if destination.status!="ready": return _failure(destination.status,destination.reason)
	var additional: Array = []
	# Dynamic actors are read-only temporary masks. The caller excludes the
	# walking resident and remains responsible for predictive swept avoidance.
	if obstacles.size()>64: return _failure("unreachable","一時障害物の数が多すぎる。")
	for obstacle in obstacles:
		if not obstacle is Dictionary or not obstacle.get("position") is Vector3 or not _number(obstacle.get("radius")) or obstacle.radius<=0 or obstacle.radius>2: return _failure("unreachable","一時障害物の形が不正。")
		var position: Vector3 = obstacle.position
		if not position.is_finite() or absf(position.y-_floor_y)>.25: return _failure("unreachable","一時障害物には同じ階の座標が必要。")
		var extent: float = _radius+float(obstacle.radius)
		additional.append(Rect2(Vector2(position.x-extent,position.z-extent),Vector2.ONE*extent*2))
	for room in _zones:
		if room!=origin and policy.room_status(room,person).status!="ready": additional.append(_zones[room].grow(_radius))
	for door in _doors.values():
		if door.narrow or policy.door_status(door.id,person).status!="ready": additional.append(door.navigation_rect.grow(_radius))
	if not _point_clear(first,additional) or not _point_clear(last,additional):
		return _blocked_reason(origin,target,person,policy)
	if first.distance_to(last)<EPS: return {"status":"ready","points":[],"doors":[],"rooms":[origin],"reason":"すでに目的地にいる。"}
	var masked: Array = []
	for cell: Vector2i in _free_cells:
		var position: Vector2 = _grid.get_point_position(cell)
		for rect: Rect2 in additional:
			if _inside(position,rect): _grid.set_point_solid(cell,true);masked.append(cell);break
	var begin := _nearest(first,additional);var end := _nearest(last,additional)
	var cells: Array = []
	if begin.x>=0 and end.x>=0: cells = _grid.get_id_path(begin,end)
	for cell: Vector2i in masked: _grid.set_point_solid(cell,false)
	if cells.is_empty(): return _blocked_reason(origin,target,person,policy)
	var raw: Array[Vector3] = [from]
	for cell: Vector2i in cells:
		var position: Vector2 = _grid.get_point_position(cell)
		var point := Vector3(position.x,_floor_y,position.y)
		if raw[-1].distance_to(point)>EPS: raw.append(point)
	if raw[-1].distance_to(to)>EPS: raw.append(to)
	var points: Array[Vector3] = [];var index := 0
	while index<raw.size()-1:
		var next := raw.size()-1
		while next>index and not _segment_clear(Vector2(raw[index].x,raw[index].z),Vector2(raw[next].x,raw[next].z),additional): next-=1
		if next==index: return _failure("unreachable","経路区間の体幅を確保できない。")
		points.append(raw[next]);index = next
	var crossed: Array[String] = [];var rooms: Array[String] = [origin];var previous := from
	for point in points:
		var hits: Array = []
		for key in _doors:
			if key in crossed: continue
			var door: Dictionary = _doors[key]
			var normal: int = 2 if door.axis=="x" else 0
			var tangent: int = 0 if door.axis=="x" else 2
			var distance: float = point[normal]-previous[normal]
			if absf(distance)<EPS: continue
			var time: float = (float(door.center[normal])-previous[normal])/distance
			if time< -EPS or time>1+EPS: continue
			var at: Vector3 = previous.lerp(point,clampf(time,0,1))
			if absf(at[tangent]-float(door.center[tangent]))<=float(door.width)*.5+EPS: hits.append({"id":key,"time":time})
		hits.sort_custom(func(a,b): return a.time<b.time if not is_equal_approx(a.time,b.time) else a.id<b.id)
		for hit in hits:
			crossed.append(hit.id)
			var door: Dictionary = _doors[hit.id]
			var current: String = rooms[-1]
			var next_room: String = door.room_b if current==door.room_a else (door.room_a if current==door.room_b else "")
			if not next_room.is_empty() and next_room!=current: rooms.append(next_room)
		previous = point
	if rooms[-1]!=target: rooms.append(target)
	return {"status":"ready","points":points,"doors":crossed,"rooms":rooms,"reason":"通れる経路がある。"}

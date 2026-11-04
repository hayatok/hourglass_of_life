class_name ActivityPlaces
extends RefCounted

var sim: Node
var spots: Dictionary = {}
var rooms: Dictionary = {}
var obstacles: Dictionary = {}
var routes: Dictionary = {}
var bench_template: Array = []
var public_obstacles: Array = []

func _init(owner_sim: Node) -> void:
	sim = owner_sim
	var path := "res://game/scenes/activity_layout.tscn"
	if ResourceLoader.exists(path):
		var layout = load(path).instantiate()
		_read(layout,Transform3D.IDENTITY,"")
		layout.free()
		_build_grids()
	var bench = load("res://game/scenes/bench.tscn").instantiate()
	for child in bench.get_children():
		if child is ActivitySpot: bench_template.append(child.describe(child.transform))
	bench.free()

func _read(node: Node, parent_world: Transform3D, room: String) -> void:
	var world: Transform3D = parent_world*node.transform if node is Node3D else parent_world
	if node.has_meta("site"):
		room = str(node.get_meta("site"))
		var size: Vector2 = node.get_meta("room_size")
		var origin := Vector2(world.origin.x,world.origin.z)-size*.5
		rooms[room] = {"bounds":Rect2(origin,size)}
		obstacles[room] = []
	if node.has_meta("footprint"):
		var extent: Vector2 = node.get_meta("footprint")
		var yaw := world.basis.get_euler().y
		if absf(sin(yaw))>.7: extent = Vector2(extent.y,extent.x)
		var occupied := Rect2(Vector2(world.origin.x,world.origin.z)-extent*.5,extent).grow(.18)
		if room.is_empty(): public_obstacles.append(occupied)
		else: obstacles[room].append(occupied)
	if node is ActivitySpot:
		var record: Dictionary = node.describe(world)
		assert(not spots.has(record.id),"Duplicate activity spot "+record.id)
		spots[record.id] = record
	for child in node.get_children(): _read(child,world,room)

func _build_grids() -> void:
	for site in rooms:
		var room: Dictionary = rooms[site]
		var bounds: Rect2 = room.bounds
		var grid := AStarGrid2D.new()
		grid.cell_size = Vector2(.1,.1)
		grid.offset = bounds.position
		grid.region = Rect2i(0,0,roundi(bounds.size.x/.1)+1,roundi(bounds.size.y/.1)+1)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for y in grid.region.size.y:
			for x in grid.region.size.x:
				var point := grid.get_point_position(Vector2i(x,y))
				if obstacles[site].any(func(rect): return rect.has_point(point)):
					grid.set_point_solid(Vector2i(x,y))
		room.grid = grid

func configure_benches(benches: Array) -> void:
	for id in spots.keys():
		if str(id).begins_with("bench_"): spots.erase(id)
	for index in benches.size():
		var center: Vector3 = benches[index]
		for side in bench_template.size():
			var id := "bench_%d_%d"%[index,side]
			var record: Dictionary = bench_template[side].duplicate(true)
			record.id = id;record.pair = "bench_%d"%index
			for key in ["approach","contact","hand_left","hand_right"]: record[key] += center
			spots[id] = record

func busy(id: String, ignored: Array = []) -> bool:
	for p in sim.people:
		if p.id not in ignored and p.get("alive",true) and p.get("activity_spot","")==id: return true
	return false

func suitable(spot: Dictionary, p: Dictionary, kind: String, site: String) -> bool:
	return spot.site==site and kind in spot.actions and (spot.resident.is_empty() or spot.resident==p.id)

func reserve(p: Dictionary, kind: String, site: String) -> Dictionary:
	var old: String = p.get("activity_spot","")
	if spots.has(old) and suitable(spots[old],p,kind,site) and not busy(old,[p.id]): return spots[old]
	var choices: Array = []
	for spot in spots.values():
		if suitable(spot,p,kind,site) and not busy(spot.id,[p.id]): choices.append(spot)
	choices.sort_custom(func(a,b): return a.approach.distance_squared_to(p.position)<b.approach.distance_squared_to(p.position))
	return choices[0] if not choices.is_empty() else {}

func pair_for(group: String, center: Vector3, people: Array) -> Array:
	var pairs := {}
	for spot in spots.values():
		if spot.group!=group or busy(spot.id,people): continue
		if group=="bench" and Vector2(spot.contact.x-center.x,spot.contact.z-center.z).length()>.6: continue
		if not pairs.has(spot.pair): pairs[spot.pair] = []
		pairs[spot.pair].append(spot)
	var choices: Array = []
	for seats in pairs.values():
		if seats.size()>=2: choices.append(seats)
	choices.sort_custom(func(a,b): return a[0].approach.distance_squared_to(center)<b[0].approach.distance_squared_to(center))
	return choices[0].slice(0,2) if not choices.is_empty() else []

func for_person(p: Dictionary) -> Dictionary:
	return spots.get(p.get("activity_spot",""),{})

func inside(site: String, point: Vector3) -> bool:
	return rooms.has(site) and rooms[site].bounds.grow(.05).has_point(Vector2(point.x,point.z))

func bench_overlaps_furniture(point: Vector3) -> bool:
	var footprint := Rect2(Vector2(point.x-.95,point.z-.45),Vector2(1.9,1.3))
	return public_obstacles.any(func(occupied): return footprint.intersects(occupied))

func _cell(room: Dictionary, point: Vector3) -> Vector2i:
	var bounds: Rect2 = room.bounds
	return Vector2i(roundi((point.x-bounds.position.x)/.1),roundi((point.z-bounds.position.y)/.1))

func walkable(site: String, point: Vector3) -> bool:
	if not inside(site,point): return false
	var grid: AStarGrid2D = rooms[site].grid
	var cell := _cell(rooms[site],point)
	return grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)

func indoor_route(site: String, origin: Vector3, target: Vector3) -> Array:
	if not inside(site,origin) or not inside(site,target): return [target]
	var room: Dictionary = rooms[site]
	var grid: AStarGrid2D = room.grid
	var begin := _cell(room,origin)
	var end := _cell(room,target)
	# Old saves may begin on an old furniture location; let the resident step to the aisle.
	if not grid.is_in_boundsv(begin) or not grid.is_in_boundsv(end) or grid.is_point_solid(end): return [target]
	if grid.is_point_solid(begin):
		var best := INF
		var original := begin
		for y in grid.region.size.y:
			for x in grid.region.size.x:
				var cell := Vector2i(x,y)
				if not grid.is_point_solid(cell) and Vector2(cell).distance_squared_to(Vector2(original))<best:
					best = Vector2(cell).distance_squared_to(Vector2(original));begin = cell
	var key := "%s:%d,%d:%d,%d"%[site,begin.x,begin.y,end.x,end.y]
	if not routes.has(key):
		var cells := grid.get_id_path(begin,end)
		var corners: Array = []
		for i in cells.size():
			if i>0 and i<cells.size()-1 and cells[i]-cells[i-1]==cells[i+1]-cells[i]: continue
			var point := grid.get_point_position(cells[i]);corners.append(Vector3(point.x,0,point.y))
		routes[key] = corners
	var path: Array = routes[key].duplicate()
	if not path.is_empty() and path[0].distance_to(origin)<.11: path.pop_front()
	if path.is_empty() or path[-1].distance_to(target)>.01: path.append(target)
	return path

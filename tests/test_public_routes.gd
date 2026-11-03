extends SceneTree

var sim: LifeSimulation
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)

func length_of(origin: Vector3, path: Array) -> float:
	var total := 0.0
	for point: Vector3 in path:
		total += origin.distance_to(point);origin = point
	return total

func clears(origin: Vector3, path: Array, occupied: Array) -> bool:
	# An independent dense sweep of the returned segments tests body clearance,
	# not the production segment predicate or an imagined destination teleport.
	for point: Vector3 in path:
		var samples := maxi(1,ceili(origin.distance_to(point)/.005))
		for index in range(samples+1):
			var at := origin.lerp(point,float(index)/samples)
			for rect: Rect2 in occupied:
				if rect.has_point(Vector2(at.x,at.z)): return false
		origin = point
	return true

func journey(origin: Vector3, target: Vector3, occupied: Array, label: String) -> void:
	var path: Array = sim.route(origin,"square",target,"square")
	expect(not path.is_empty() and path[-1].distance_to(target)<.00001,label+": route retains the actual destination")
	expect(clears(origin,path,occupied),label+": every segment clears table, board and bench at body width")
	var p: Dictionary = sim.person("haru")
	p.position = origin;p.place = "square";p.destination = "square";p.target = target;p.path = path.duplicate();p.moving = not p.path.is_empty()
	for minute in 300:
		if not p.moving: break
		sim._move(p)
	expect(not p.moving and p.position.distance_to(target)<.00001,label+": the real movement consumes the route and arrives")

func run() -> void:
	sim = LifeSimulation.new();root.add_child(sim);sim.reset(711,12)
	expect(sim.place_bench(Vector3(-4,0,4.5)).status=="accept","The reported bench placement is legal")
	var origin: Vector3 = sim.activities.spots.bench_1_1.approach
	var target: Vector3 = sim.activities.spots.craft_work_0.approach
	expect(origin.distance_to(Vector3(-3.52,0,5.15))<.00001 and target.distance_to(Vector3(-3.15,0,6.66))<.00001,"The regression uses the actual placed seat and craft markers")
	var occupied: Array = sim.activities.public_obstacles.duplicate()
	# These independent raw furniture/board envelopes have the same body radius
	# as town navigation. The board sits within the table but is audited too.
	var craft := Rect2(Vector2(-3.575,5.58),Vector2(1.55,.84)).grow(.18)
	var board := Rect2(Vector2(-2.95,6.10),Vector2(.30,.30)).grow(.18)
	occupied.append(board)
	for bench in sim.benches:
		occupied.append(Rect2(Vector2(bench.x-.88,bench.z-.34),Vector2(1.76,.66)).grow(.18))
	expect(not clears(origin,[target],[craft]),"The old short straight route crosses the craft table's real footprint")
	var path: Array = sim.route(origin,"square",target,"square")
	expect(path.size()>1 and length_of(origin,path)>origin.distance_to(target),"A blocked short route becomes a real detour")
	journey(origin,target,occupied,"Placed bench to craft")
	journey(target,origin,occupied,"Craft to placed bench")
	# The opposite side of the table has a nearby street connection. Check it
	# too, so merely diverting through the closest waypoint cannot pass.
	journey(sim.activities.spots.bench_1_0.approach,sim.activities.spots.craft_work_1.approach,occupied,"Other placed seat to far craft spot")
	var clear_origin := Vector3(-4.5,0,7.2)
	var direct: Array = sim.route(clear_origin,"square",target,"square")
	expect(direct.size()==1 and direct[0]==target and clears(clear_origin,direct,occupied),"A genuinely clear near route keeps its direct shortcut")
	sim.free()
	print("Public route checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

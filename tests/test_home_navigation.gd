extends SceneTree

const Navigation = preload("res://game/foundation/home_navigation.gd")
const Occupancy = preload("res://game/foundation/home_occupancy.gd")
const PLAN_PATH := "res://data/foundation/ogawa-home.json"
const RADIUS := .24
const OUTSIDE := Vector3(6.5,0,11.25)
var checks := 0
var failures: Array[String] = []
var plan: Dictionary
var solids: Array = []
var floors: Array = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message);push_error(message)

func point(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])

func fixture(id: String) -> Dictionary:
	for record in plan.fixtures:
		if record.id==id: return record
	return {}

func destination(id: String) -> Vector3: return point(fixture(id).interaction_point)

func closed_contains(rect: Rect2, at: Vector2) -> bool:
	return at.x>=rect.position.x-.00001 and at.y>=rect.position.y-.00001 and at.x<=rect.end.x+.00001 and at.y<=rect.end.y+.00001

func reference_geometry(authored: Dictionary) -> Array:
	# This test constructs wall pieces from the raw opening spans independently
	# and densely sweeps the returned path. It never calls production predicates.
	var result: Array = []
	var half: float = float(authored.house.wall_thickness)*.5
	for wall in authored.walls:
		var axis: int = 0 if wall.start[1]==wall.end[1] else 1
		var spans: Array = [Vector2(minf(wall.start[axis],wall.end[axis]),maxf(wall.start[axis],wall.end[axis]))]
		for door in authored.doors:
			if door.wall!=wall.id: continue
			var center: float = door.center[0 if axis==0 else 2]
			var left: float = center-float(door.width)*.5
			var right: float = center+float(door.width)*.5
			var next: Array = []
			for span: Vector2 in spans:
				if right<=span.x or left>=span.y: next.append(span)
				else:
					if left>span.x: next.append(Vector2(span.x,left))
					if right<span.y: next.append(Vector2(right,span.y))
			spans = next
		for span: Vector2 in spans:
			var rect := Rect2(span.x,float(wall.start[1])-half,span.y-span.x,half*2) if axis==0 else Rect2(float(wall.start[0])-half,span.x,half*2,span.y-span.x)
			result.append(rect.grow(RADIUS))
	for record in authored.fixtures:
		if not record.get("blocking",true): continue
		var size := Vector2(record.size[0],record.size[2])
		result.append(Rect2(Vector2(record.position[0],record.position[2])-size*.5,size).grow(RADIUS))
	return result

func clears(origin: Vector3, route_points: Array, blockers: Array, extra: Array = []) -> bool:
	for target: Vector3 in route_points:
		if not target.is_finite(): return false
		var samples := maxi(1,ceili(origin.distance_to(target)/.01))
		for index in range(samples+1):
			var at: Vector3 = origin.lerp(target,float(index)/samples)
			var center := Vector2(at.x,at.z)
			for rect: Rect2 in blockers+extra:
				if closed_contains(rect,center): return false
			for offset in [Vector2(-RADIUS,-RADIUS),Vector2(-RADIUS,RADIUS),Vector2(RADIUS,-RADIUS),Vector2(RADIUS,RADIUS)]:
				var on_floor := false
				for floor_rect: Rect2 in floors:
					if closed_contains(floor_rect,center+offset): on_floor = true;break
				if not on_floor: return false
		origin = target
	return true

func ready(result: Dictionary, target: Vector3) -> bool:
	return result.status=="ready" and not result.points.is_empty() and result.points[-1].distance_to(target)<.00001

func reject_restore(occupancy, bad: Dictionary, label: String) -> void:
	var before: Dictionary = occupancy.snapshot()
	expect(not occupancy.restore(bad) and occupancy.snapshot()==before,label+": rejected atomically without losing current claims")

func run() -> void:
	plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	solids = reference_geometry(plan)
	var house_bounds: Array = plan.house.bounds
	floors.append(Rect2(house_bounds[0],house_bounds[1],house_bounds[2],house_bounds[3]))
	for zone in plan.external_zones: floors.append(Rect2(zone.bounds[0],zone.bounds[1],zone.bounds[2],zone.bounds[3]))
	var nav = Navigation.new();var occupancy = Occupancy.new()
	expect(nav.configure(plan,RADIUS) and occupancy.configure(plan),"The authored eight-room house configures geometry and admission separately")
	for record in plan.fixtures:
		var resident: String = record.owner if record.owner in ["nagisa","ryo","rin"] and record.get("private",false) else "nagisa"
		if record.room=="rin_bedroom": resident = "rin"
		var target := point(record.interaction_point)
		var result: Dictionary = nav.route(OUTSIDE,target,resident,occupancy)
		expect(ready(result,target) and clears(OUTSIDE,result.points,solids),record.id+": a real body-width path from the porch reaches the authored interaction point")
	var bath: Dictionary = nav.route(OUTSIDE,destination("bath"),"nagisa",occupancy)
	expect(bath.doors==["D01","D02","D07","D08"] and bath.rooms==["outside","entrance","hall","washroom","bathroom"],"Bath access follows actual openings and never cuts through a bedroom or LDK")
	var kitchen: Dictionary = nav.route(OUTSIDE,destination("fridge"),"nagisa",occupancy)
	expect(kitchen.doors==["D01","D02","D03"] and kitchen.rooms==["outside","entrance","hall","ldk"],"Kitchen access exposes required exterior and interior door passages in travel order")
	expect(not clears(OUTSIDE,[destination("bath")],solids) and bath.points.size()>1,"A wall-crossing direct shortcut is replaced by a clear route rather than a teleport")
	var same: Dictionary = nav.route(OUTSIDE,OUTSIDE,"rin",occupancy)
	expect(same.status=="ready" and same.points.is_empty() and same.doors.is_empty(),"Being at the target needs no invented movement or door traversal")
	var original: Dictionary = occupancy.snapshot()
	nav.route(OUTSIDE,destination("bath"),"ryo",occupancy)
	expect(occupancy.snapshot()==original,"Route queries do not reserve rooms, fixtures, or advance an activity")

	for resident in ["nagisa","ryo","rin"]:
		var parent_result: Dictionary = nav.route(OUTSIDE,destination("bed_ryo"),resident,occupancy)
		var child_result: Dictionary = nav.route(OUTSIDE,destination("bed_rin"),resident,occupancy)
		expect(parent_result.status==("private" if resident=="rin" else "ready") and child_result.status==("ready" if resident=="rin" else "private"),resident+": room entry respects authored parent and child privacy")
	expect(occupancy.fixture_status("bed_nagisa","ryo").status=="private" and occupancy.fixture_status("dining_nagisa","ryo").status=="ready","Shared room permission permits borrowing a family seat but not another resident's private bed")
	expect(occupancy.grant_room("rin_bedroom","ryo",true) and ready(nav.route(OUTSIDE,destination("bed_rin"),"ryo",occupancy),destination("bed_rin")) and occupancy.fixture_status("bed_rin","ryo").status=="private","An explicit room invitation permits entry without transferring ownership of the child's bed")
	occupancy.reserve_room("rin_bedroom","ryo")
	expect(not occupancy.grant_room("rin_bedroom","ryo",false) and occupancy.can_enter("rin_bedroom","ryo"),"An occupied invitation cannot be erased while its visitor is still admitted")
	occupancy.release_person("ryo")
	expect(occupancy.grant_room("rin_bedroom","ryo",false) and nav.route(OUTSIDE,destination("bed_rin"),"ryo",occupancy).status=="private","After safe departure, revoking an invitation restores privacy")
	expect(nav.route(OUTSIDE,destination("fridge"),"visitor",occupancy).status=="private","A stranger receives no household-wide permission from an outdoor start")

	for equipment in ["toilet","bath"]:
		expect(occupancy.reserve_fixture(equipment,"nagisa").status=="ready",equipment+": actual-arrival admission claims its private room and equipment")
		var held: Dictionary = occupancy.snapshot()
		expect(nav.route(OUTSIDE,destination(equipment),"ryo",occupancy).status=="occupied" and occupancy.reserve_fixture(equipment,"ryo").status=="occupied" and occupancy.snapshot()==held,equipment+": a second resident waits without stealing or clearing the first claim")
		occupancy.release_person("nagisa")
		var after_release: Dictionary = nav.route(OUTSIDE,destination(equipment),"ryo",occupancy)
		expect(ready(after_release,destination(equipment)) and clears(OUTSIDE,after_release.points,solids) and occupancy.reserve_fixture(equipment,"ryo").status=="ready",equipment+": release permits a real clear approach and subsequent use")
		occupancy.release_person("ryo")
	expect(occupancy.reserve_fixture("washbasin","nagisa").status=="ready" and occupancy.reserve_fixture("washer","ryo").status=="ready" and occupancy.fixture_status("changing_space","rin").status=="occupied","Shared washing is possible, while undressing waits until the room is actually empty")
	occupancy.release_person("nagisa");occupancy.release_person("ryo")
	expect(occupancy.reserve_fixture("changing_space","rin").status=="ready" and nav.route(OUTSIDE,destination("washbasin"),"nagisa",occupancy).status=="occupied" and occupancy.fixture_status("washer","ryo").status=="occupied","An active changing claim excludes unrelated use of the whole washroom")
	occupancy.release_person("rin")
	expect(occupancy.reserve_fixture("parents_desk","ryo").status=="ready" and occupancy.snapshot().fixture_users.parents_desk==["ryo"] and occupancy.snapshot().fixture_users.parents_desk_chair==["ryo"],"A desk request atomically claims its authored chair bundle")
	var desk_claim: Dictionary = occupancy.snapshot()
	expect(occupancy.reserve_fixture("parents_desk","ryo").status=="ready" and occupancy.snapshot()==desk_claim and occupancy.reserve_fixture("bed_nagisa","ryo").status=="private" and occupancy.snapshot()==desk_claim,"Repeated use is idempotent, and a failed private request retains the current desk claim")
	occupancy.release_person("ryo")
	for resident in ["nagisa","ryo","rin"]: occupancy.reserve_room("hall",resident)
	occupancy.grant_room("hall","visitor",true)
	expect(not occupancy.can_enter("hall","visitor") and occupancy.room_status("hall","visitor").status=="occupied","Authored room capacity applies to invited visitors too")
	for resident in ["nagisa","ryo","rin"]: occupancy.release_person(resident)

	occupancy.set_door_blocked("D08",true)
	var blocked: Dictionary = nav.route(OUTSIDE,destination("bath"),"nagisa",occupancy)
	expect(blocked.status=="blocked" and blocked.points.is_empty() and ready(nav.route(OUTSIDE,destination("washer"),"nagisa",occupancy),destination("washer")),"A blocked bath door prevents passage while leaving the separate laundry approach usable")
	occupancy.set_door_blocked("D08",false)
	expect(ready(nav.route(OUTSIDE,destination("bath"),"nagisa",occupancy),destination("bath")),"A closed but operable door is listed for the executor to open, and reopening a blockade restores routing")
	occupancy.set_door_blocked("D01",true)
	expect(nav.route(OUTSIDE,destination("fridge"),"rin",occupancy).status=="blocked","The blocked only exterior doorway has no illegal wall fallback")
	occupancy.set_door_blocked("D01",false)
	for bad_target in [Vector3(.1,0,5),Vector3(2.7,0,6.4),Vector3(13,0,11),Vector3(6.5,2,9)]:
		var result: Dictionary = nav.route(OUTSIDE,bad_target,"nagisa",occupancy)
		expect(result.status!="ready" and result.points.is_empty(),"Targets in a wall, furniture, outside floor, or another height do not receive fallback paths")

	# Live actors are optional temporary geometry; no persistent grid state may
	# retain a preceding query's masks or pretend to push a body out of the way.
	var walker := Vector3(4.65,0,5.15);var finish := Vector3(4.65,0,7.9)
	var obstacle := {"position":Vector3(4.65,0,7.0),"radius":.24}
	var obstacle_rect := Rect2(Vector2(4.17,6.52),Vector2(.96,.96))
	var detour: Dictionary = nav.route(walker,finish,"nagisa",occupancy,[obstacle])
	expect(ready(detour,finish) and clears(walker,detour.points,solids,[obstacle_rect]),"A temporary actor receives a full body-width detour, including the smoothed segments")
	var choke := {"position":Vector3(6.5,0,4.2),"radius":.24}
	var stopped: Dictionary = nav.route(OUTSIDE,destination("bed_ryo"),"ryo",occupancy,[choke])
	expect(stopped.status!="ready" and stopped.points.is_empty() and ready(nav.route(OUTSIDE,destination("bed_ryo"),"ryo",occupancy),destination("bed_ryo")),"An actor blocking the hall causes waiting without leaving a stale mask after it moves away")
	expect(nav.route(OUTSIDE,destination("fridge"),"nagisa",occupancy,[{"position":OUTSIDE,"radius":.24}]).points.is_empty(),"An overlapping initial body is rejected rather than snapped through another resident")

	var narrow_plan: Dictionary = plan.duplicate(true)
	for door in narrow_plan.doors:
		if door.id=="D08": door.width=.4
	var narrow = Navigation.new()
	expect(narrow.configure(narrow_plan,RADIUS) and narrow.route(OUTSIDE,destination("bath"),"nagisa").status=="blocked","A portal narrower than the body remains impassable despite graph connectivity")
	var furniture_plan: Dictionary = plan.duplicate(true)
	furniture_plan.fixtures.append({"id":"hall_blocker","room":"hall","position":[6.5,0,4.2],"size":[1.3,1,.5],"interaction_point":[6.5,0,4.9],"owner":"ogawa","private":false})
	var furniture_nav = Navigation.new()
	var furniture_ok: bool = furniture_nav.configure(furniture_plan,RADIUS)
	var no_route: Dictionary = furniture_nav.route(OUTSIDE,destination("bed_ryo"),"ryo")
	expect(furniture_ok and no_route.status=="unreachable" and no_route.points.is_empty(),"Furniture spanning the hall defeats a graph-only route and never falls back to a straight segment")

	occupancy.grant_room("rin_bedroom","ryo",true)
	occupancy.reserve_room("rin_bedroom","ryo")
	occupancy.reserve_fixture("bath","nagisa")
	occupancy.set_door_blocked("D03",true)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(occupancy.snapshot()))
	var restored = Occupancy.new();restored.configure(plan)
	expect(restored.restore(saved) and restored.snapshot()==occupancy.snapshot(),"Current room, equipment, consent and door claims survive an actual JSON save roundtrip")
	var before_route: Dictionary = nav.route(OUTSIDE,destination("bath"),"rin",occupancy)
	var after_route: Dictionary = nav.route(OUTSIDE,destination("bath"),"rin",restored)
	expect(before_route==after_route and after_route.status=="occupied" and ready(nav.route(OUTSIDE,destination("bed_rin"),"ryo",restored),destination("bed_rin")),"Restored claims yield the same waiting and invited-room paths")
	restored.release_person("nagisa")
	expect(ready(nav.route(OUTSIDE,destination("bath"),"rin",restored),destination("bath")),"A restored claim can be released normally so another person can approach")
	var bad: Dictionary = saved.duplicate(true);bad.room_users.unknown=[]
	reject_restore(restored,bad,"Unknown room reference")
	bad=saved.duplicate(true);bad.room_users.bathroom=["nagisa","rin"]
	reject_restore(restored,bad,"Exclusive room capacity overflow")
	bad=saved.duplicate(true);bad.room_users.hall=["ryo"]
	reject_restore(restored,bad,"One person admitted to two rooms")
	bad=saved.duplicate(true);bad.room_users.bathroom=[]
	reject_restore(restored,bad,"Equipment holder without its room claim")
	bad=saved.duplicate(true);bad.blocked_doors.append("missing")
	reject_restore(restored,bad,"Unknown blocked door")
	bad=saved.duplicate(true);bad.grants.rin_bedroom=[9]
	reject_restore(restored,bad,"Malformed visitor identity")
	bad=saved.duplicate(true);bad.room_users.rin_bedroom=[];bad.room_users.parents_bedroom=["ryo"];bad.fixture_users.parents_desk=["ryo"]
	reject_restore(restored,bad,"Incomplete desk and chair bundle")
	bad=saved.duplicate(true);bad.room_users.rin_bedroom=[];bad.room_users.parents_bedroom=["ryo"];bad.fixture_users.bed_nagisa=["ryo"]
	reject_restore(restored,bad,"Another person's private bed claim")
	bad=saved.duplicate(true);bad.schema=2
	reject_restore(restored,bad,"Unsupported occupancy schema")

	var invalid: Dictionary = plan.duplicate(true);invalid.doors[0].center[2]=9.6
	expect(not nav.configure(invalid,RADIUS) and ready(nav.route(OUTSIDE,destination("fridge"),"nagisa"),destination("fridge")),"A door off its authored wall is rejected without replacing a working navigation instance")
	invalid=plan.duplicate(true);invalid.doors[3].pocket_interval=[1.75,2.65]
	expect(not nav.configure(invalid,RADIUS),"A sliding pocket overlapping its own opening is invalid geometry")
	invalid=plan.duplicate(true);invalid.fixtures[0].use_via="missing"
	var kept: Dictionary = restored.snapshot()
	expect(not restored.configure(invalid) and restored.snapshot()==kept,"A broken equipment bundle cannot reset live occupancy during configure")
	print("Home navigation and occupancy: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

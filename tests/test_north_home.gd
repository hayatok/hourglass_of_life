extends SceneTree

# Native footprint, roof and routing acceptance for an unoccupied house. No
# natural resident day or human review is established by this controlled stage.
const PLAN := "res://data/foundation/homes/north-house.json"
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:
	create_timer(40).timeout.connect(func():push_error("North home checks timed out");quit(1))
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func point(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])

func down(house: LivingHouse, at: Vector3, top: float, bottom: float, exclude: Array[RID] = []) -> Dictionary:
	return house.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(house.to_global(Vector3(at.x,top,at.z)),house.to_global(Vector3(at.x,bottom,at.z)),1,exclude))

func collider_rids(node: Node) -> Array[RID]:
	var result: Array[RID]=[]
	if node is CollisionObject3D:result.append(node.get_rid())
	for child in node.get_children():result.append_array(collider_rids(child))
	return result

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	var house := LivingHouse.new();root.add_child(house)
	if not house.load_plan(PLAN):expect(false,"The real North plan loads");quit(1);return
	HomeArt.new().add_visuals(house)
	var p: Dictionary=house.definition
	var navigation := HomeNavigation.new();var occupancy := HomeOccupancy.new()
	expect(navigation.configure(p,.24) and occupancy.configure(p),"The L-shaped home configures actual rooms, exterior ground, portals and permissions")
	var ids: Array=p.residents.map(func(r):return r.id)
	expect(ids.size()==2 and "saki" in ids and "haru" in ids,"The rebuilt home retains the two existing residents")
	expect(p.house.volumes.size()==3 and house.roof_volumes.size()==5,"Two real wings, a lower link and the porch form independent native roof volumes")
	var roofs_fit := true
	for entry: Dictionary in house.roof_volumes.values():
		var spec: Dictionary=entry.spec
		var mesh: MeshInstance3D=entry.node.get_node("RoofSlopes")
		var own := Rect2(spec.bounds[0],spec.bounds[1],spec.bounds[2],spec.bounds[3])
		var envelope: Rect2=own.grow(float(spec.roof.eaves)+.0001)
		var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if not envelope.has_point(Vector2(vertex.x,vertex.z)):roofs_fit=false
			for volume in p.house.volumes:
				for rectangle in volume.get("footprint",[volume.bounds] if volume.has("bounds") else []):
					var other := Rect2(rectangle[0],rectangle[1],rectangle[2],rectangle[3])
					if other==own:continue
					if other.grow(-.0001).has_point(Vector2(vertex.x,vertex.z)) and vertex.y<float(volume.wall_height)-.0001:roofs_fit=false
	expect(roofs_fit,"Actual roof meshes stay within each wing's eaves and stop at neighbouring occupied solids, including the low gallery/clerestory join")
	var from: Vector3=point(p.house.street_connection.approach)
	var all_reached := true
	var rooms: Dictionary={}
	for room in p.rooms:rooms[room.id]=room
	for f in p.fixtures:
		var actor: String=str(f.owner) if f.get("private",false) and f.owner in ids else "saki"
		if rooms.has(f.room) and actor not in rooms[f.room].allowed_residents:actor=rooms[f.room].allowed_residents[0]
		var route: Dictionary=navigation.route(from,point(f.interaction_point),actor,occupancy)
		if route.status!="ready":print("NORTH_ROUTE_FAILURE ",f.id," ",route.status);all_reached=false
	expect(all_reached,"Every real fixture, including the porch posts, has an actual body-width route from the street approach")
	expect(navigation.route(from,point(house.fixtures.bed_haru.definition.interaction_point),"saki",occupancy).status=="private" and navigation.route(from,point(house.fixtures.bed_saki.definition.interaction_point),"haru",occupancy).status=="private","The public courtyard never grants access to the other resident's private room")
	for id in house.doors:house.set_door_open(id,true)
	await physics_frame;await physics_frame
	var court := Vector3(10.5,0,8.)
	var ground: Dictionary=down(house,court,.1,-.8)
	expect(not ground.is_empty() and absf(ground.position.y)<.00001 and ground.normal.y>.99,"The courtyard has a real level floor collider")
	expect(down(house,court,7.,.15).is_empty(),"No bounding-box roof or wall fills the open courtyard above its ground")
	expect(down(house,Vector3(12,0,10.8),.1,-.8).is_empty() and navigation.route(from,Vector3(12,0,10.8),"saki",occupancy).status!="ready","The unbuilt space beyond declared exterior floors gains neither a phantom slab nor a fallback route")
	var built := true
	for entry: Dictionary in house.roof_volumes.values():
		var b: Array=entry.spec.bounds
		for u in [.15,.5,.85]:
			for v in [.15,.5,.85]:
				var at := Vector3(float(b[0])+float(b[2])*u,0,float(b[1])+float(b[3])*v)
				if down(house,at,7.,2.0).is_empty():built=false
	expect(built,"Actual roof colliders cover the near edge, middle and far edge of each wing, lower link and entry canopy")
	var posts := true
	var roof_rids: Array[RID]=collider_rids(house.roof_root)
	for id in p.house.canopies[0].posts:
		var f: Dictionary=house.fixtures[id].definition
		var hit: Dictionary=down(house,point(f.position),3.,.05,roof_rids)
		if hit.is_empty() or hit.collider.get_parent().get_parent()!=house.fixtures[id].node:posts=false
	expect(posts,"The porch posts are native solids declared in the navigation plan")
	house.cutaway=true;house.update_cutaway(Vector3(22,18,22))
	expect(not house.roof_root.visible and house.thresholds.values().all(func(row):return row.node.visible),"Cutaway removes the roof assembly while keeping every real threshold floor")
	house.free()
	print("North home real-footprint checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

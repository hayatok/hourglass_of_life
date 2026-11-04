extends SceneTree

# Controlled canonical geometry/collision fixture. Access fractions are set
# explicitly; this does not prove a character opened a drawer, grasped a plate,
# walked the route, or kept real skin contacts during those actions.
const Fixtures = preload("res://game/foundation/household_kitchen_fixtures.gd")
const Props = preload("res://game/foundation/household_props.gd")
const Navigation = preload("res://game/foundation/home_navigation.gd")
const Occupancy = preload("res://game/foundation/home_occupancy.gd")
const RADIUS := .24
const HEIGHT := 1.65
var checks: int=0
var failures: Array[String]=[]
var observations: Dictionary={}
var home: LivingHouse
var day: HouseholdDay
var hardware: HouseholdKitchenFixtures
var props: HouseholdProps
var navigation
var occupancy

func _initialize() -> void:call_deferred("run")
func expect(ok: bool, reason: String) -> bool:
	checks+=1
	if not ok:failures.append(reason);push_error(reason)
	return ok

func point(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])
func vector(a: Vector3) -> Array:return [a.x,a.y,a.z]

func mesh_vertices(mesh: MeshInstance3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays: Array=mesh.mesh.surface_get_arrays(surface)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:result.append(mesh.to_global(vertex))
	return result

func projected_drawer() -> Rect2:
	# Independently project ACTUAL mesh vertices, not the cached Nav rectangle.
	var result := Rect2();var begun: bool=false
	for mesh in hardware.drawer.find_children("*","MeshInstance3D",true,false):
		for vertex in mesh_vertices(mesh):
			var local: Vector3=home.to_local(vertex);var p := Vector2(local.x,local.z)
			if not begun:result=Rect2(p,Vector2.ZERO);begun=true
			else:result=result.expand(p)
	return result

func exclusions(keep: Node) -> Array[RID]:
	var result: Array[RID]=[]
	for body in root.find_children("*","CollisionObject3D",true,false):
		if body!=keep and not keep.is_ancestor_of(body):result.append(body.get_rid())
	return result

func ray(from: Vector3, to: Vector3, keep: Node = null) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to)
	query.hit_from_inside=true
	if keep!=null:query.exclude=exclusions(keep)
	return home.get_world_3d().direct_space_state.intersect_ray(query)

func hit_mesh(hit: Dictionary) -> String:
	var body: Node=hit.get("collider")
	return str(body.get_parent().name) if body!=null and body.get_parent()!=null else ""

func body_segment(from: Vector3, to: Vector3) -> Dictionary:
	var shape := CylinderShape3D.new();shape.radius=RADIUS;shape.height=HEIGHT
	var query := PhysicsShapeQueryParameters3D.new();query.shape=shape;query.margin=0
	query.transform=Transform3D(Basis.IDENTITY,home.to_global(from)+Vector3.UP*(HEIGHT*.5))
	query.motion=home.global_basis*(to-from);query.exclude=exclusions(hardware.drawer)
	var space: PhysicsDirectSpaceState3D=home.get_world_3d().direct_space_state
	var initial: Array=space.intersect_shape(query,8)
	var collision: PackedFloat32Array=space.cast_motion(query)
	return {"clear":initial.is_empty() and collision.size()==2 and collision[0]>=.99999,"initial_overlaps":initial.size(),"safe_fraction":float(collision[0]) if collision.size()==2 else -1.0}

func access_geometry() -> void:
	var source: Dictionary=day.plan.household_access["fridge:drawer"]
	var closed_center: Vector3=point(day.plan.fixtures.filter(func(f):return f.id=="fridge")[0].position)
	var open_offset: Vector3=point(source.open_offset)
	var front_positions: Array=[]
	for fraction in [0.0,.5,1.0]:
		# Geometry fixture input, never a production permission/pose shortcut.
		day.access["fridge:drawer"]=fraction
		var before: Dictionary=day.snapshot()
		hardware.sync();props.sync()
		await physics_frame;await physics_frame
		expect(HouseholdDay._same(before,day.snapshot()),"Moving derived fixture geometry never changes resources, people, work or the authored access input")
		var shelf: MeshInstance3D=hardware.drawer.get_node("ActualShelf")
		var top: float=-INF
		for vertex in mesh_vertices(shelf):top=maxf(top,home.to_local(vertex).y)
		var target: Vector3=closed_center+open_offset*fraction;target.y=.8
		var support: Dictionary=ray(home.to_global(target+Vector3.UP*.20),home.to_global(target-Vector3.UP*.10),hardware.fridge_root)
		expect(absf(top-.8)<.00001 and hit_mesh(support)=="ActualShelf" and home.to_local(support.get("position",Vector3.ZERO)).distance_to(target)<.00001,"The actual shelf mesh and collision support stay at .8m while their real drawer offset follows fraction "+str(fraction))
		var front: Dictionary=ray(home.to_global(Vector3(.7,.9,5.4)),home.to_global(Vector3(.7,.9,3.85)),hardware.fridge_root)
		expect(hit_mesh(front)=="InsulatedFront","The real insulated drawer front remains collidable at access fraction "+str(fraction))
		front_positions.append(home.to_local(front.get("position",Vector3.ZERO)).z)
		var actual: Rect2=projected_drawer();var registered: Rect2=hardware.drawer_floor_rect()
		expect(actual.position.distance_to(registered.position)<.00001 and actual.size.distance_to(registered.size)<.00001,"Cached navigation footprint agrees with the actual drawer mesh at fraction "+str(fraction))
		observations["access_"+str(fraction)]={"shelf_top_y":top,"support":vector(home.to_local(support.get("position",Vector3.ZERO))),"front_z":front_positions.back(),"actual_footprint":[actual.position.x,actual.position.y,actual.size.x,actual.size.y]}
	expect(absf(float(front_positions[1])-float(front_positions[0])-.275)<.00001 and absf(float(front_positions[2])-float(front_positions[0])-.55)<.00001,"The actual front collider translates by the same half/full opening displacement")
	var cavity: Dictionary=ray(home.to_global(Vector3(.7,1,4.30)),home.to_global(Vector3(.7,1,3.86)),hardware.fridge_root)
	expect(cavity.is_empty(),"The open refrigerated cavity is physically empty where the prototype solid body used to block access")
	var above_shelf: Dictionary=ray(home.to_global(Vector3(.7,1.1,4.60)),home.to_global(Vector3(.7,.805,4.60)),hardware.fridge_root)
	expect(above_shelf.is_empty(),"The opened drawer provides real top access above its shelf without a hidden lid or solid volume")

func plate_supports() -> void:
	var rail: MeshInstance3D=hardware.rack.get_node("CradleRail")
	var rail_shape: BoxMesh=rail.mesh
	var separators: Array=[]
	for child in hardware.rack.get_children():
		if child is MeshInstance3D and child!=rail and child.position.y>rail.position.y+.01:separators.append(child)
	expect(separators.size()==7,"The actual six-plate rack has seven real dividers")
	var rail_top: float=-INF
	for vertex in mesh_vertices(rail):rail_top=maxf(rail_top,home.to_local(vertex).y)
	expect(absf(rail_top-.862)<.00001,"The real cradle mesh top is the authored .862m support")
	var margins: Array=[]
	for i in 6:
		var object: Node3D=props.objects["inventory:clean_dishes:"+str(i)].node
		var dish: MeshInstance3D=object.get_node("Dish")
		var vertices: PackedVector3Array=mesh_vertices(dish)
		var lowest := Vector3.ZERO;var bottom: float=INF
		for vertex in vertices:
			if vertex.y<bottom:bottom=vertex.y;lowest=vertex
		var contact: Vector3=rail.to_local(lowest)
		var supported: bool=absf(contact.y-rail_shape.size.y*.5)<.00001 and absf(contact.x)<=rail_shape.size.x*.5+.00001 and absf(contact.z)<=rail_shape.size.z*.5+.00001
		var hit: Dictionary=ray(lowest+Vector3.UP*.015,lowest-Vector3.UP*.015,hardware.rack)
		expect(supported and hit_mesh(hit)=="CradleRail" and absf(float(hit.get("position",Vector3.ZERO).y)-bottom)<.00001,"Rotated plate "+str(i)+" rests with its true ceramic rim on the actual cradle collision")
		var minimum: float=INF
		for divider in separators:
			var size: Vector3=divider.mesh.size;var left: float=INF;var right: float=-INF
			for vertex in vertices:
				var at: Vector3=divider.to_local(vertex)
				left=minf(left,at.x);right=maxf(right,at.x)
			# All actual triangle vertices lie on one side of this true divider
			# plane. Their linear faces therefore cannot cross the separator.
			var gap: float=maxf(left-size.x*.5,-size.x*.5-right)
			minimum=minf(minimum,gap)
		expect(minimum>.0005,"Plate "+str(i)+" actual 18mm ceramic profile clears both real separator faces")
		margins.append(minimum)
	observations.plate_divider_clearance_m=margins

func swept_route() -> void:
	var from := Vector3(.7,0,5.25);var target := Vector3(3.75,0,4.6)
	var direct: Dictionary=body_segment(from,target)
	expect(not direct.clear and direct.safe_fraction>=0 and direct.safe_fraction<1,"The actual open drawer colliders reject the tempting straight body-width shortcut")
	var route: Dictionary=navigation.route(from,target,"nagisa",occupancy)
	if not expect(route.status=="ready" and not route.points.is_empty() and route.points.back().distance_to(target)<.00001,"The canonical open-drawer approach has a real navigation detour to preparation"):return
	var current: Vector3=from;var casts: Array=[];var clear: bool=true
	for destination in route.points:
		var collision: Dictionary=body_segment(current,destination);casts.append(collision)
		if not collision.clear:clear=false
		current=destination
	expect(clear,"Every actual swept .24m-radius/1.65m-tall body segment clears real Drawer StaticBodies, independently of the routing rectangle")
	observations.route={"points":route.points.map(func(p):return vector(p)),"direct_cast":direct,"segment_casts":casts,"body_radius":RADIUS,"body_height":HEIGHT}

func run() -> void:
	home=LivingHouse.new();root.add_child(home)
	if not expect(home.load_plan("res://data/foundation/ogawa-home.json"),"Canonical actual house geometry loads"):quit(1);return
	HomeArt.new().add_visuals(home)
	day=HouseholdDay.new()
	if not expect(day.configure(home.definition),"The canonical household/equipment source configures"):home.free();quit(1);return
	navigation=Navigation.new();occupancy=Occupancy.new()
	if not expect(navigation.configure(home.definition,RADIUS) and occupancy.configure(home.definition),"Real house navigation and admission configure"):home.free();quit(1);return
	var prototype: Node3D=home.fixtures.fridge.node.get_node("Body")
	var original_shapes: Array=prototype.find_children("*","CollisionShape3D",true,false)
	expect(not original_shapes.is_empty() and original_shapes.all(func(shape):return not shape.disabled),"The original filled fridge has actual enabled prototype collision before replacement")
	hardware=Fixtures.new();root.add_child(hardware)
	if not expect(hardware.configure(home,day,navigation),"The actual hollow fridge, moving drawer and plate rack configure"):hardware.free();home.free();quit(1);return
	expect(original_shapes.all(func(shape):return shape.disabled),"Every original filled Body/Solid collision is truly disabled after replacement")
	props=Props.new();root.add_child(props)
	if not expect(props.configure(home,day,{}),"Real source plate meshes bind to the canonical household without invented actors"):props.free();hardware.free();home.free();quit(1);return
	await physics_frame;await physics_frame
	await access_geometry();plate_supports();swept_route()
	var before: Dictionary=day.snapshot();hardware.sync();props.sync()
	expect(HouseholdDay._same(before,day.snapshot()),"Derived geometry/collision synchronization grants no material, need recovery, work or elapsed time")
	props.free();hardware.free()
	await process_frame;await physics_frame
	expect(original_shapes.all(func(shape):return not shape.disabled),"Removing only this fixture layer restores its original physical colliders")
	expect(not navigation._transient_solids.has("fridge:drawer"),"Removing the actual drawer also removes its transient navigation obstacle")
	home.free()
	DirAccess.make_dir_recursive_absolute("res://builds/kitchen-fixtures")
	var file := FileAccess.open("res://builds/kitchen-fixtures/results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"canonical controlled static meshes, actual physics collisions and swept cylinder fixture; no skin or natural-motion proof"},"\t"))
	print("Kitchen actual fixture checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

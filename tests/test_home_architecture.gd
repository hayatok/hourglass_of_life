extends SceneTree

# Native geometry/physics acceptance for staged houses. No household clock,
# person, route or daily-life acceptance is implied by these checks.
const PLANS := ["res://data/foundation/ogawa-home.json",
	"res://data/foundation/homes/saeki-home.json", "res://data/foundation/homes/shared-house.json",
	"res://data/foundation/homes/north-house.json", "res://data/foundation/homes/mori-home.json"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30).timeout.connect(func():push_error("Home architecture checks timed out");quit(1))
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func v(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])

func ray(house: LivingHouse, at: Vector3, inward: Vector3, exclude: Array[RID] = []) -> Dictionary:
	var first: Vector3=house.to_global(at-inward*.4)
	var last: Vector3=house.to_global(at+inward*.4)
	var query := PhysicsRayQueryParameters3D.create(first,last,1,exclude)
	return house.get_world_3d().direct_space_state.intersect_ray(query)

func tagged(hit: Dictionary, key: String, value: String) -> bool:
	return not hit.is_empty() and hit.collider.get_meta(key,"")==value

func aperture_failure(id: String, stage: String, hit: Dictionary) -> bool:
	print("APERTURE_FAILURE ",id," ",stage," ","empty" if hit.is_empty() else str(hit.collider.get_path()))
	return false

func count_colliders(node: Node) -> int:
	var result := 1 if node is CollisionObject3D else 0
	for child in node.get_children():result+=count_colliders(child)
	return result

func collider_rids(node: Node) -> Array[RID]:
	var result: Array[RID]=[]
	if node is CollisionObject3D:result.append(node.get_rid())
	for child in node.get_children():result.append_array(collider_rids(child))
	return result

func wall_meshes_match(house: LivingHouse) -> bool:
	for wall in house.definition.walls:
		var height: float=float(wall.get("height",house.definition.house.wall_height))
		var a := Vector2(wall.start[0],wall.start[1]);var b := Vector2(wall.end[0],wall.end[1])
		var direction := (b-a).normalized();var length := a.distance_to(b)
		var panes: Array[Rect2]=[]
		for pane: MeshInstance3D in house.wall_nodes:
			if pane.get_meta("wall_id","")!=wall.id:continue
			if pane.get_parent()!=house.wall_roots[wall.id] or not pane.mesh is BoxMesh:return false
			var size: Vector3=pane.mesh.size
			var along: float=(Vector2(pane.position.x,pane.position.z)-a).dot(direction)
			var width: float=size.x if absf(direction.x)>.5 else size.z
			panes.append(Rect2(along-width*.5,pane.position.y-size.y*.5,width,size.y))
			var shape: BoxShape3D=pane.get_node("Solid").get_child(0).shape
			if shape.size.distance_to(size)>.00001:return false
		for ix in ceili(length/.13):
			for iy in ceili(height/.17):
				var point := Vector2((float(ix)+.37)/ceili(length/.13)*length,(float(iy)+.29)/ceili(height/.17)*height)
				var solid := true
				for kind: String in ["doors","windows"]:
					for opening in house.definition.get(kind,[]):
						if opening.wall!=wall.id:continue
						var center: Vector3=v(opening.center)
						var offset: float=(Vector2(center.x,center.z)-a).dot(direction)
						var low: float=0.0 if kind=="doors" else center.y-float(opening.height)*.5
						var high: float=float(opening.height) if kind=="doors" else center.y+float(opening.height)*.5
						if absf(point.x-offset)<float(opening.width)*.5 and point.y>low and point.y<high:solid=false
				var covering := 0
				for rect: Rect2 in panes:
					if rect.has_point(point):covering+=1
				if covering!=(1 if solid else 0):return false
	return true

func aperture_rays(house: LivingHouse) -> bool:
	# Exterior eaves can legitimately be the first hit above a high window.
	# Isolate plaster for sill/header probes; glass probes still include the roof,
	# and the roof has its own real ray acceptance below.
	var roof_excluded: Array[RID]=collider_rids(house.roof_root)
	for entry: Dictionary in house.windows.values():
		var record: Dictionary=entry.definition
		var center := v(record.center);var inward := v(record.inward)
		var tangent := Vector3(inward.z,0,-inward.x)
		var sample: Vector3=center+tangent*float(record.width)*.22+Vector3.UP*float(record.height)*.08
		var hit: Dictionary=ray(house,sample,inward)
		if not tagged(hit,"architecture_kind","glass"):return aperture_failure(record.id,"glass",hit)
		var excluded: Array[RID]=[entry.glass_body.get_rid()]
		hit=ray(house,sample,inward,excluded)
		if not hit.is_empty():return aperture_failure(record.id,"excluded glass",hit)
		var below: Vector3=sample;below.y=(center.y-float(record.height)*.5)*.5
		var wall_height: float=float(house.definition.house.wall_height)
		for wall in house.definition.walls:
			if wall.id==record.wall:wall_height=float(wall.get("height",wall_height))
		var above: Vector3=sample;above.y=lerpf(center.y+float(record.height)*.5,wall_height,.5)
		hit=ray(house,below,inward,roof_excluded)
		if not tagged(hit,"wall_id",record.wall):return aperture_failure(record.id,"below",hit)
		hit=ray(house,above,inward,roof_excluded)
		if not tagged(hit,"wall_id",record.wall):return aperture_failure(record.id,"above",hit)
		if entry.node.get_parent()!=house.wall_roots[record.wall] or entry.glass_body.get_meta("wall_id","")!=record.wall:return false
	return true

func door_pockets(house: LivingHouse) -> bool:
	for id in house.doors:
		var entry: Dictionary=house.doors[id];var door: Dictionary=entry.definition
		if door.kind!="sliding":continue
		for progress in [0.0,.5,1.0]:
			if not house.set_door_fraction(id,progress):return false
			var actual: Vector3=entry.node.position+entry.panel.position
			var axis: int=0 if door.axis=="x" else 2
			var center: float=(float(door.pocket_interval[0])+float(door.pocket_interval[1]))*.5
			if absf(actual[axis]-lerpf(float(door.center[axis]),center,progress))>.00001:return false
		house.set_door_open(id,door.get("default_state","")=="open")
	return true

func contents_match(house: LivingHouse) -> bool:
	for entry: Dictionary in house.fixtures.values():
		var record: Dictionary=entry.definition
		var computer: Node=entry.node.find_child("ComputerWorkstation",true,false)
		if is_instance_valid(computer)!=(record.get("desk_content","")=="computer"):return false
		if record.get("desk_content","")=="sewing" and not is_instance_valid(entry.node.find_child("NeedleHousing",true,false)):return false
		if record.get("desk_content","")=="keyboard" and not is_instance_valid(entry.node.find_child("KeyboardCase",true,false)):return false
		if record.get("display_contents","")=="tools" and not is_instance_valid(entry.node.find_child("ToolTray",true,false)):return false
	if house.definition.house.household!="ogawa":
		for id in ["InitialRinDrawing","InitialDesignStudy","InitialTownModel"]:
			if is_instance_valid(house.find_child(id,true,false)):return false
	return true

func stacked_apertures() -> void:
	var house := LivingHouse.new()
	house.definition={"house":{"wall_height":3.0},"doors":[{"wall":"test","center":[2,0,0],"width":1.0,"height":2.1}],
		"windows":[{"wall":"test","center":[2,2.55,0],"width":1.4,"height":.5},
			{"wall":"test","center":[2.5,1.8,0],"width":1.,"height":.7}]}
	var wall := {"id":"test","start":[0,0],"end":[4,0]}
	var panes: Array[Rect2]=house.wall_solid_rects(wall)
	var good := true
	for p in [Vector2(2,1),Vector2(2,2.5),Vector2(2.7,1.8)]:
		if panes.any(func(rect: Rect2):return rect.has_point(p)):good=false
	for p in [Vector2(2,2.2),Vector2(.5,1),Vector2(2.8,.5),Vector2(2,2.9)]:
		if not panes.any(func(rect: Rect2):return rect.has_point(p)):good=false
	expect(good,"Stacked and overlapping apertures retain the real header/sill instead of deleting an entire vertical strip")
	house.free()

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	stacked_apertures()
	for path: String in PLANS:
		var house := LivingHouse.new();root.add_child(house)
		house.position=Vector3(2,0,-3);house.rotation.y=.19
		if not house.load_plan(path):expect(false,path+": authored architecture loads");house.free();continue
		var label: String=house.definition.house.label
		expect(wall_meshes_match(house),label+": native wall meshes and BoxShape colliders match the full door/window aperture field")
		expect(house.windows.size()==house.definition.windows.size(),label+": each authored window owns a fixed glass body and stable wall assembly")
		HomeArt.new().add_visuals(house)
		await physics_frame;await physics_frame
		expect(aperture_rays(house),label+": real rays hit glass through the aperture, plaster below/above, and no opaque wall when glass is excluded")
		expect(door_pockets(house),label+": sliding leaves travel into the authored pocket, including pockets on the negative axis")
		expect(contents_match(house),label+": desks and shelves follow household metadata without borrowing another family's possessions")
		var collisions := count_colliders(house)
		HomeArt.new().add_visuals(house)
		expect(count_colliders(house)==collisions and contents_match(house),label+": rebuilding artwork preserves physical architecture and authored contents")
		var bounds: Array=house.definition.house.bounds
		var center := Vector3(float(bounds[0])+float(bounds[2])*.5,0,float(bounds[1])+float(bounds[3])*.5)
		house.cutaway=true;house.update_cutaway(house.to_global(center+Vector3(8,12,10)))
		var grouped := true
		for window: Dictionary in house.windows.values():
			if window.node.is_visible_in_tree()!=house.wall_roots[window.definition.wall].is_visible_in_tree():grouped=false
		expect(grouped and is_instance_valid(house.roof_root) and not house.roof_root.visible and aperture_rays(house),label+": cutaway hides the roof and wall-attached windows while keeping their physical colliders")
		house.cutaway=false;house.update_cutaway(house.to_global(center+Vector3(8,12,10)))
		expect(house.roof_root.visible and house.wall_roots.values().all(func(node: Node3D):return node.visible),label+": street view restores the complete house and pitched roof")
		var roof: Dictionary=house.definition.house.roof
		var roof_point := center+Vector3(0,float(house.definition.house.wall_height)+float(roof.rise)+1,0)
		var query := PhysicsRayQueryParameters3D.create(house.to_global(roof_point),house.to_global(center+Vector3.UP*2.5))
		expect(tagged(house.get_world_3d().direct_space_state.intersect_ray(query),"architecture_kind","roof"),label+": a real roof collision closes the envelope above the rooms")
		house.free();await process_frame
	print("Home architecture geometry/physics: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

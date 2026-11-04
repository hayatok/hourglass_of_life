extends SceneTree

# Actual generated mesh geometry/rigid transform contract only. No character
# skin grasp, collision-free cooking, mouth anchor or eating is certified here.
const TOOLS := preload("res://game/foundation/household_tools.gd")
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)

func faces(tool: Node3D, prefix: String = "") -> PackedVector3Array:
	var points := PackedVector3Array()
	for child in tool.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=child
		if not str(mesh.name).begins_with(prefix):continue
		var frame := tool.global_transform.affine_inverse()*mesh.global_transform
		for point in mesh.mesh.get_faces():points.append(frame*point)
	return points

func bounds(points: PackedVector3Array) -> Dictionary:
	var minimum := Vector3(INF,INF,INF);var maximum := Vector3(-INF,-INF,-INF)
	for point in points:
		minimum.x=minf(minimum.x,point.x);minimum.y=minf(minimum.y,point.y);minimum.z=minf(minimum.z,point.z)
		maximum.x=maxf(maximum.x,point.x);maximum.y=maxf(maximum.y,point.y);maximum.z=maxf(maximum.z,point.z)
	return {"min":minimum,"max":maximum,"size":maximum-minimum}

func nearest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Voronoi-region closest point, independent of the generator's contact data.
	var ab := b-a;var ac := c-a;var ap := point-a
	var d1 := ab.dot(ap);var d2 := ac.dot(ap)
	if d1<=0 and d2<=0:return a
	var bp := point-b;var d3 := ab.dot(bp);var d4 := ac.dot(bp)
	if d3>=0 and d4<=d3:return b
	var vc := d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0:return a+ab*(d1/(d1-d3))
	var cp := point-c;var d5 := ab.dot(cp);var d6 := ac.dot(cp)
	if d6>=0 and d5<=d6:return c
	var vb := d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0:return a+ac*(d2/(d2-d6))
	var va := d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0:return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))
	var inverse := 1.0/(va+vb+vc)
	return a+ab*(vb*inverse)+ac*(vc*inverse)

func surface_distance(point: Vector3, points: PackedVector3Array) -> float:
	var nearest := INF
	for index in range(0,points.size(),3):nearest=minf(nearest,point.distance_to(nearest_triangle(point,points[index],points[index+1],points[index+2])))
	return nearest

func highest_y_at(points: PackedVector3Array, x: float, z: float) -> float:
	var highest := -INF
	for index in range(0,points.size(),3):
		var a := points[index];var b := points[index+1];var c := points[index+2]
		var denominator := (b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if absf(denominator)<.0000000001:continue
		var u := ((b.z-c.z)*(x-c.x)+(c.x-b.x)*(z-c.z))/denominator
		var v := ((c.z-a.z)*(x-c.x)+(a.x-c.x)*(z-c.z))/denominator
		var w := 1-u-v
		if minf(u,minf(v,w))>=-.00001:highest=maxf(highest,u*a.y+v*b.y+w*c.y)
	return highest

func check_tool(kind: String) -> void:
	var tool: Node3D=TOOLS.create(kind);root.add_child(tool)
	var description: Dictionary=TOOLS.spec(kind)
	var actual := faces(tool);var handle := faces(tool,"GripHandle");var measured := bounds(actual)
	var triangles: int=actual.size()/3;var valid := actual.size()>0 and actual.size()%3==0
	for index in range(0,actual.size(),3):
		valid=valid and actual[index].is_finite() and actual[index+1].is_finite() and actual[index+2].is_finite() and (actual[index+1]-actual[index]).cross(actual[index+2]-actual[index]).length_squared()>.000000000000000001
	expect(valid and triangles<1200,kind+": real visible finite triangle meshes have volume detail within the modest utensil budget")
	expect(measured.min.distance_to(description.bounds_local.min)<.000001 and measured.max.distance_to(description.bounds_local.max)<.000001,kind+": reported local bounds match the actual instantiated mesh vertices")
	var grip_errors := {};var normal_valid := true
	for side in ["L","R"]:
		var frame: Transform3D=description.local_grips[side]
		grip_errors[side]=surface_distance(frame.origin,handle)
		normal_valid=normal_valid and absf(frame.basis.determinant()-1)<.00001 and frame.basis.z.dot(Vector3(-frame.origin.x,0,0))>0
	expect(float(grip_errors.L)<.000001 and float(grip_errors.R)<.000001 and normal_valid,kind+": both immutable palm frames touch the actual wood grip surface and face the handle")
	var work_error := 0.0
	for feature in description.working_frames:work_error=maxf(work_error,surface_distance(description.working_frames[feature].origin,actual))
	expect(work_error<.000002,kind+": every working tip/edge/food marker lies on actual visible tool geometry")
	var support_world := Transform3D(Basis(Vector3.UP,.43),Vector3(2,.86,-1))
	var parked_world: Transform3D=TOOLS.park_on(kind,support_world)
	var relative := support_world.affine_inverse()*parked_world
	var low := INF;var parked_points := PackedVector3Array()
	for point in actual:
		var value: Vector3=relative*point;low=minf(low,value.y);parked_points.append(value)
	var parked_bounds := bounds(parked_points)
	expect(absf(low)<.000001 and (parked_world*description.support_local).distance_to(support_world.origin)<.000001,kind+": actual parked geometry has bottom contact on the supplied surface without penetration or a fabricated centre offset")
	expect(parked_bounds.min.distance_to(description.parked_bounds.min)<.000001 and parked_bounds.max.distance_to(description.parked_bounds.max)<.000001,kind+": parked support envelope also matches independently transformed real mesh vertices")
	var original: Transform3D=description.local_grips.R
	var original_bounds: Vector3=description.bounds_local.min
	var original_features: int=description.working_frames.size()
	description.local_grips.R=Transform3D(Basis.IDENTITY,Vector3(99,99,99));description.working_frames.clear();description.bounds_local.min=Vector3(99,99,99)
	var fresh: Dictionary=TOOLS.spec(kind)
	expect(fresh.local_grips.R==original and fresh.working_frames.size()==original_features and fresh.bounds_local.min==original_bounds,kind+": mutating a returned nested spec cannot alter canonical tool geometry/contact metadata")
	observations[kind]={"triangles":triangles,"bounds":measured,"grip_surface_errors_m":grip_errors,"working_marker_error_m":work_error,"parked_min_y":low,"parked_bounds":parked_bounds,"handle_bounds":bounds(handle)}
	if kind in ["spoon","child_spoon"]:
		var food: Transform3D=fresh.working_frames.food_anchor
		var rim: Transform3D=fresh.working_frames.mouth_entry
		var actual_inner_y := highest_y_at(faces(tool,"SpoonBowl"),food.origin.x,food.origin.z)
		expect(absf(actual_inner_y-food.origin.y)<.000001 and rim.origin.y-actual_inner_y>.003,kind+": the actual bowl is open and concave at its food pocket rather than a solid ellipsoid or filled opening")
		# This supplied frame is an arbitrary fixture target, not a real mouth
		# measurement. The test only verifies exact tool-to-grip composition.
		var supplied_target := Transform3D(Basis(Vector3.UP,.7)*Basis(Vector3.RIGHT,-.12),Vector3(1.4,1.45,-.6))
		var tool_world: Transform3D=TOOLS.world_for_working(kind,"mouth_entry",supplied_target)
		var palm: Transform3D=TOOLS.palm_for_working(kind,"mouth_entry",supplied_target,"R")
		expect((tool_world*rim).is_equal_approx(supplied_target) and palm.is_equal_approx(tool_world*fresh.local_grips.R),kind+": utensil-to-mouth target composition uses only supplied target and actual tip/grip frames, with no guessed hand/mouth coordinate")
	if kind=="knife":
		var blade := faces(tool,"KnifeBlade");blade.append_array(faces(tool,"KnifeCutting"))
		var blade_bounds := bounds(blade)
		var safe := true
		for side in ["L","R"]:safe=safe and blade_bounds.min.z-fresh.local_grips[side].origin.z>.04 and surface_distance(fresh.local_grips[side].origin,blade)>.03
		expect(safe,kind+": grasp points remain on the separate handle, clear of the actual blade and cutting edge")
	tool.free()

func render_lineup() -> void:
	root.size=Vector2i(1080,720)
	var world := Node3D.new();root.add_child(world)
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("cbd1c7")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("fff2d9");environment.environment.ambient_light_energy=.30;world.add_child(environment)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-35,0);sun.light_energy=.55;sun.shadow_enabled=true;sun.directional_shadow_max_distance=4;world.add_child(sun)
	var table := MeshInstance3D.new();var shape := BoxMesh.new();shape.size=Vector3(1.25,.04,.56);table.mesh=shape;table.position=Vector3(0,-.02,-.12)
	var material := StandardMaterial3D.new();material.albedo_color=Color("9a7956");material.roughness=.83;table.material_override=material;world.add_child(table)
	var index := 0
	for kind in TOOLS.kinds():
		var tool: Node3D=TOOLS.create(kind);world.add_child(tool)
		var description: Dictionary=TOOLS.spec(kind)
		var center: Vector3=(description.parked_bounds.min+description.parked_bounds.max)*.5
		# Contact anchors differ by shape. Pack the real measured envelopes on
		# the actual table rather than leaving a long working end over its edge.
		tool.transform=TOOLS.park_on(kind,Transform3D(Basis.IDENTITY,Vector3((index-1.5)*.245-center.x,0,-.12-center.z)))
		index+=1
	var camera := Camera3D.new();camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.92
	camera.position=Vector3(.02,.83,.43);world.add_child(camera);camera.look_at(Vector3(0,0,-.12))
	for ignored in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/household-tools/lineup.png")
	FileAccess.open("res://builds/household-tools/render.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"One actual GPU image of parked tool geometry/materials only; no real character grasp or eating.","order_left_to_right":TOOLS.kinds(),"pixels":[root.size.x,root.size.y]},"\t"))
	world.free()

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	expect(TOOLS.create("imaginary_fork")==null and TOOLS.spec("imaginary_fork").is_empty() and TOOLS.world_for_working("spoon","unknown_tip",Transform3D.IDENTITY)==null,"Unknown utensils/features produce no fabricated geometry or origin target")
	for kind in TOOLS.kinds():check_tool(kind)
	var adult: Dictionary=observations.spoon;var child: Dictionary=observations.child_spoon
	expect(child.bounds.size.z<adult.bounds.size.z and child.handle_bounds.size.x>adult.handle_bounds.size.x and child.bounds.size.x<adult.bounds.size.x,"Child spoon has its own shorter bowl/shaft and thicker rounded handle, not a uniform scale of the adult utensil")
	expect(TOOLS.park_on("knife",Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO))==null and TOOLS.palm_target("spoon",Transform3D(Basis.IDENTITY,Vector3(INF,0,0)))==null,"Non-rigid or non-finite placement cannot silently scale utensils or invent a hand target")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/household-tools"))
	FileAccess.open("res://builds/household-tools/results.json",FileAccess.WRITE).store_string(JSON.stringify(HouseholdDay._encode({"scope":"Actual procedural utensil mesh/contact/bounds/park/rigid composition only. No real rig grasp, imported mouth anchor, collision-free action or eating acceptance.","checks":checks,"failures":failures,"tools":observations}),"\t"))
	print("Household tool geometry checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	if failures.is_empty() and OS.get_cmdline_user_args().has("--render") and DisplayServer.get_name()!="headless":await render_lineup()
	quit(0 if failures.is_empty() else 1)

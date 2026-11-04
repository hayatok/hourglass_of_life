extends SceneTree

# Generated food geometry/contact/connected-core contract only. This fixture
# does not certify a character's skin grasp, knife action, cooking or eating.
const FOOD := preload("res://game/foundation/household_food.gd")
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)

func encode(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result := {}
		for key in value:result[key]=encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(encode(item))
		return result
	return value

func faces(food: Node3D, solid_only: bool = false, prefix: String = "") -> PackedVector3Array:
	var points := PackedVector3Array()
	for node in food.find_children("*","MeshInstance3D",true,false):
		var instance: MeshInstance3D=node
		if not prefix.is_empty() and not str(instance.name).begins_with(prefix):continue
		if solid_only and instance.name not in ["CarrotSkin","PotatoSkin","CabbageLeafOutside","CabbageQuarterFaces"] and not str(instance.name).begins_with("ScoreInterior") and not str(instance.name).begins_with("FreshCutFaces"):continue
		var frame: Transform3D=food.global_transform.affine_inverse()*instance.global_transform
		# ArrayMesh.get_faces() goes through Godot's TriangleMesh weld/snap
		# representation, which rounds tiny food details at .1mm. Read the
		# actual rendered vertex/index arrays rather than that physics proxy.
		for surface in instance.mesh.get_surface_count():
			var arrays: Array=instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant=arrays[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array and not indices.is_empty():
				for index in indices:points.append(frame*vertices[index])
			else:
				for point: Vector3 in vertices:points.append(frame*point)
	return points

func measured_bounds(points: PackedVector3Array) -> Dictionary:
	var low := Vector3(INF,INF,INF);var high := Vector3(-INF,-INF,-INF)
	for point: Vector3 in points:low=low.min(point);high=high.max(point)
	return {"min":low,"max":high,"size":high-low}

func nearest_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b-a;var ac := c-a;var ap := p-a
	var d1 := ab.dot(ap);var d2 := ac.dot(ap)
	if d1<=0 and d2<=0:return a
	var bp := p-b;var d3 := ab.dot(bp);var d4 := ac.dot(bp)
	if d3>=0 and d4<=d3:return b
	var vc := d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0:return a+ab*d1/(d1-d3)
	var cp := p-c;var d5 := ab.dot(cp);var d6 := ac.dot(cp)
	if d6>=0 and d5<=d6:return c
	var vb := d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0:return a+ac*d2/(d2-d6)
	var va := d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0:return b+(c-b)*(d4-d3)/((d4-d3)+(d5-d6))
	return a+ab*vb/(va+vb+vc)+ac*vc/(va+vb+vc)

func surface_distance(point: Vector3, triangles: PackedVector3Array) -> float:
	var value := INF
	for i in range(0,triangles.size(),3):value=minf(value,point.distance_to(nearest_triangle(point,triangles[i],triangles[i+1],triangles[i+2])))
	return value

func top_y(triangles: PackedVector3Array, x: float, z: float) -> float:
	var top := -INF
	for i in range(0,triangles.size(),3):
		var a := triangles[i];var b := triangles[i+1];var c := triangles[i+2]
		var denominator: float=(b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if absf(denominator)<.00000000001:continue
		var u: float=((b.z-c.z)*(x-c.x)+(c.x-b.x)*(z-c.z))/denominator
		var v: float=((c.z-a.z)*(x-c.x)+(a.x-c.x)*(z-c.z))/denominator
		var w: float=1-u-v
		if minf(u,minf(v,w))>=-.00001:top=maxf(top,u*a.y+v*b.y+w*c.y)
	return top

func inside(triangles: PackedVector3Array, point: Vector3) -> bool:
	var direction := Vector3(.811,.337,.472).normalized();var hits: Array[float]=[]
	for i in range(0,triangles.size(),3):
		var a := triangles[i];var ab := triangles[i+1]-a;var ac := triangles[i+2]-a
		var cross: Vector3=direction.cross(ac);var det: float=ab.dot(cross)
		if absf(det)<.00000000001:continue
		var inverse: float=1.0/det;var offset: Vector3=point-a
		var u: float=offset.dot(cross)*inverse
		if u<-.0000001 or u>1.0000001:continue
		var q: Vector3=offset.cross(ab);var v: float=direction.dot(q)*inverse
		if v<-.0000001 or u+v>1.0000001:continue
		var t: float=ac.dot(q)*inverse
		if t>.0000001 and hits.all(func(value: float):return absf(value-t)>.0000001):hits.append(t)
	return hits.size()%2==1

func check_variant(kind: String, state: String) -> void:
	var node: Node3D=FOOD.create(kind,state);root.add_child(node)
	var description: Dictionary=FOOD.spec(kind,state)
	var actual: PackedVector3Array=faces(node);var envelope: Dictionary=measured_bounds(actual)
	var finite: bool=not actual.is_empty() and actual.size()%3==0
	for i in range(0,actual.size(),3):finite=finite and actual[i].is_finite() and actual[i+1].is_finite() and actual[i+2].is_finite() and (actual[i+1]-actual[i]).cross(actual[i+2]-actual[i]).length_squared()>.000000000000000001
	expect(finite and actual.size()/3<6000,kind+"/"+state+": actual finite nondegenerate native triangles stay within the food mesh budget")
	expect(envelope.min.distance_to(description.bounds_local.min)<.000001 and envelope.max.distance_to(description.bounds_local.max)<.000001 and absf(envelope.min.y)<.000001,kind+"/"+state+": reported bounds match actual child-transformed vertices with real bottom y0")
	var grips: Dictionary=FOOD.grips_for(kind,state,"R");var grip: Transform3D=grips.R
	var grip_error: float=surface_distance(grip.origin,actual)
	expect(grip_error<.000001 and grip.origin.y>envelope.size.y*.35 and absf(grip.basis.determinant()-1)<.00001 and grip.basis.z.dot(description.grip_outward)<-.999,kind+"/"+state+": the R palm frame contacts an accessible upper real surface with a rigid inward orientation")
	var lowest := INF;var park_error := 0.0;var contact_error := 0.0
	for orientation: Basis in [Basis.IDENTITY,Basis(Vector3.UP,.7)*Basis(Vector3.BACK,.33),Basis(Vector3.RIGHT,-.44)*Basis(Vector3.UP,-.2)]:
		var at := Vector3(.23,.746,-.18)
		var frame: Transform3D=FOOD.park_on(kind,state,Transform3D(orientation,at))
		var low := INF
		for vertex: Vector3 in actual:low=minf(low,(frame*vertex).y)
		park_error=maxf(park_error,absf(low-at.y));lowest=minf(lowest,low)
		var support: Vector3=FOOD.support_for(kind,state,orientation)
		contact_error=maxf(contact_error,surface_distance(support,actual))
		park_error=maxf(park_error,(frame*support).distance_to(at))
	expect(park_error<.000001 and contact_error<.000001,kind+"/"+state+": actual support vertices in three rigid orientations meet the supplied surface without penetration or a guessed height proxy")
	var original: Transform3D=description.local_grips.R
	var original_size: Vector3=description.bounds_local.size
	description.local_grips.R=Transform3D(Basis.IDENTITY,Vector3(99,99,99));description.pieces.clear();description.bounds_local.size=Vector3(99,99,99)
	var fresh: Dictionary=FOOD.spec(kind,state)
	expect(fresh.local_grips.R==original and not fresh.pieces.is_empty() and fresh.bounds_local.size==original_size,kind+"/"+state+": returned nested metadata cannot mutate the canonical unit geometry or contacts")
	observations[kind+":"+state]={"bounds":envelope,"triangles":actual.size()/3,"pieces":fresh.pieces.size(),"grip_surface_error_m":grip_error,"support_error_m":contact_error,"placement_error_m":park_error}
	node.free()

func check_preparation(kind: String) -> void:
	var whole: Node3D=FOOD.create(kind,"whole");var scored: Node3D=FOOD.create(kind,"scored");var cut: Node3D=FOOD.create(kind,"cut")
	root.add_child(whole);root.add_child(scored);root.add_child(cut)
	var description: Dictionary=FOOD.spec(kind,"whole");var score: Dictionary=FOOD.spec(kind,"scored")
	var whole_faces: PackedVector3Array=faces(whole,true);var scored_faces: PackedVector3Array=faces(scored,true)
	var outlines_valid := true;var kerf_valid := true;var bridge_valid := true
	var measured_slots: Array=[]
	for plane: Dictionary in description.cut_planes:
		var entry: Transform3D=plane.entry_local
		outlines_valid=outlines_valid and plane.outline_local.size()>=3 and surface_distance(entry.origin,whole_faces)<.000001
		for vertex: Vector3 in plane.outline_local:outlines_valid=outlines_valid and absf(vertex.z-plane.frame.origin.z)<.000001 and surface_distance(vertex,whole_faces)<.000001
		var x: float=-.018 if kind=="cabbage" else 0.0;var z: float=plane.frame.origin.z
		var before: float=top_y(whole_faces,x,z);var after: float=top_y(scored_faces,x,z)
		var core_y: float=score.score.core_y
		kerf_valid=kerf_valid and before>core_y+.005 and absf(after-core_y)<.000002
		# Probe the real retained solid on both sides and inside every kerf.
		# The exposed upper slot is empty, while the original lower core still
		# connects neighbouring lobes. No disconnected chunk is called held.
		for offset in [-.0018,0.0,.0018]:
			var probe := Vector3(x,core_y*.72,z+offset)
			bridge_valid=bridge_valid and inside(whole_faces,probe) and inside(scored_faces,probe)
		var cavity := Vector3(x,lerpf(core_y,before,.55),z)
		kerf_valid=kerf_valid and inside(whole_faces,cavity) and not inside(scored_faces,cavity)
		measured_slots.append({"z":z,"whole_top_y":before,"scored_kerf_floor_y":after,"core_y":core_y})
	expect(outlines_valid,kind+": knife entry frames and cut contours lie on actual original mesh intersections, rather than being guessed from bounds")
	expect(kerf_valid and bridge_valid and score.pieces.size()==1 and score.score.retained_height_fraction>=.30,kind+": scored geometry has real open kerfs with floors and a continuous retained lower core across every cut")
	var split: Dictionary=FOOD.spec(kind,"cut");var declared := true
	for piece: Dictionary in split.pieces:
		var child := cut.get_node(NodePath(str(piece.id))) as Node3D
		var part_faces: PackedVector3Array=faces(child)
		var envelope: Dictionary=measured_bounds(part_faces)
		declared=declared and child.transform.is_equal_approx(piece.local_frame) and envelope.min.distance_to(piece.bounds_local.min)<.000001 and envelope.max.distance_to(piece.bounds_local.max)<.000001
	expect(declared and split.pieces.size()>1 and not faces(cut,false,"FreshCutFaces").is_empty() and whole.transform==scored.transform and scored.transform==cut.transform,kind+": separated cut children have actual flesh faces and declared frames under the unchanged unit root; they are not new inventory units")
	observations[kind+":preparation"]={"slots":measured_slots,"whole_to_scored_connected_core":bridge_valid,"separated_children":split.pieces.size(),"grasp_limit":split.cut_transport_limit}
	whole.free();scored.free();cut.free()

func render_lineup() -> void:
	root.size=Vector2i(1200,1000)
	var stage := Node3D.new();root.add_child(stage)
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("c9d2c5")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("fff0d8");environment.environment.ambient_light_energy=.40;stage.add_child(environment)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-58,-35,0);sun.light_energy=.55;sun.shadow_enabled=true;sun.directional_shadow_max_distance=4;stage.add_child(sun)
	var table := MeshInstance3D.new();var box := BoxMesh.new();box.size=Vector3(.72,.025,.65)
	table.mesh=box;table.position=Vector3(0,-.0125,0);var wood := StandardMaterial3D.new();wood.albedo_color=Color("ad8e68");wood.roughness=.86;table.material_override=wood;stage.add_child(table)
	for column in FOOD.kinds().size():
		for row in FOOD.states().size():
			var kind: String=FOOD.kinds()[column];var state: String=FOOD.states()[row]
			var food: Node3D=FOOD.create(kind,state);stage.add_child(food)
			# Real unit roots stay horizontally centred. The actual measured
			# support vertex supplies only the necessary vertical translation.
			var support: Vector3=FOOD.support_for(kind,state)
			food.position=Vector3((column-1)*.20,-support.y,(row-1)*.19)
	var camera := Camera3D.new();stage.add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.70
	camera.position=Vector3(.10,.90,.62);camera.look_at(Vector3(0,.015,0))
	for ignored in 4:await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://builds/household-food"
	var error: Error=root.get_texture().get_image().save_png(output+"/lineup.png")
	FileAccess.open(output+"/render.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Empty food geometry/material stage; not actual character grasp, scoring or cooking.","columns":FOOD.kinds(),"rows_far_to_near":FOOD.states(),"image_write_result":error,"image_write_is_artifact_not_functional_check":true},"\t"))
	stage.free()

func run() -> void:
	if root.has_node("Sim"):root.get_node("Sim").set_process(false)
	expect(FOOD.create("imaginary_food")==null and FOOD.spec("carrot","cooked").is_empty() and FOOD.grips_for("potato","whole","X").is_empty(),"Unknown kinds/states/hands create neither food nor an invented origin grip")
	for kind: String in FOOD.kinds():
		for state: String in FOOD.states():check_variant(kind,state)
		check_preparation(kind)
	var carrot: Dictionary=observations["carrot:whole"].bounds;var potato: Dictionary=observations["potato:whole"].bounds;var cabbage: Dictionary=observations["cabbage:whole"].bounds
	expect(carrot.size.z>=.145 and carrot.size.z<=.17 and potato.size.x>=.06 and potato.size.x<=.07 and cabbage.size.z>=.085 and cabbage.size.z<=.095 and maxf(potato.size.x,cabbage.size.x)<=.075,"Actual metre-scale ingredients are a hand-sized carrot, potato and purchased cabbage quarter rather than oversized whole vegetables")
	expect(FOOD.park_on("carrot","whole",Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO))==null and FOOD.support_for("cabbage","scored",Basis(Vector3(1,0,0),Vector3(.4,1,0),Vector3(0,0,1)))==null and FOOD.palm_target("potato","whole",Transform3D(Basis.IDENTITY,Vector3(INF,0,0)))==null,"Scaling, shear and non-finite transforms are rejected instead of distorting food or fabricating support/hand targets")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://builds/household-food"))
	FileAccess.open("res://builds/household-food/results.json",FileAccess.WRITE).store_string(JSON.stringify(encode({"scope":"Actual generated food geometry, rigid support/contact frames and retained scored core only; real hand/finger contact and cooking are not certified.","checks":checks,"failures":failures,"observations":observations}),"\t"))
	print("Household food geometry checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	if failures.is_empty() and OS.get_cmdline_user_args().has("--render") and DisplayServer.get_name()!="headless":await render_lineup()
	quit(0 if failures.is_empty() else 1)

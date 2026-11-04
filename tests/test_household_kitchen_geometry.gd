extends SceneTree

# Actual generated food triangles against the actual casserole inner profile.
# Static geometry fixture only: no avatar, skin, gravity or lived-day claim.
const FOOD = preload("res://game/foundation/household_food.gd")
var checks: int=0
var failures: Array[String]=[]
var observations: Dictionary={}

func _initialize() -> void:call_deferred("run")
func expect(value: bool, reason: String) -> void:
	checks+=1
	if not value:failures.append(reason);push_error(reason)

func collect(node: Node3D, frame: Transform3D, result: Array) -> void:
	var current: Transform3D=frame*node.transform
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count: int=indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				var points: Array=[]
				for corner in 3:points.append(current*vertices[indices[i+corner] if not indices.is_empty() else i+corner])
				var low: Vector3=points[0].min(points[1]).min(points[2]);var high: Vector3=points[0].max(points[1]).max(points[2])
				result.append({"p":points,"min":low,"max":high})
	for child in node.get_children():
		if child is Node3D:collect(child,current,result)

func point_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab: Vector3=b-a;var ac: Vector3=c-a;var ap: Vector3=p-a
	var d1: float=ab.dot(ap);var d2: float=ac.dot(ap)
	if d1<=0 and d2<=0:return a
	var bp: Vector3=p-b;var d3: float=ab.dot(bp);var d4: float=ac.dot(bp)
	if d3>=0 and d4<=d3:return b
	var vc: float=d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0:return a+ab*(d1/(d1-d3))
	var cp: Vector3=p-c;var d5: float=ab.dot(cp);var d6: float=ac.dot(cp)
	if d6>=0 and d5<=d6:return c
	var vb: float=d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0:return a+ac*(d2/(d2-d6))
	var va: float=d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0:return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))
	var denominator: float=va+vb+vc
	if absf(denominator)<1e-20:return a
	return a+ab*(vb/denominator)+ac*(vc/denominator)

func segment_triangle(a: Vector3, b: Vector3, triangle: Array) -> bool:
	var direction: Vector3=b-a;var e1: Vector3=triangle[1]-triangle[0];var e2: Vector3=triangle[2]-triangle[0]
	var h: Vector3=direction.cross(e2);var determinant: float=e1.dot(h)
	if absf(determinant)<1e-12:return false
	var inverse: float=1/determinant;var s: Vector3=a-triangle[0];var u: float=inverse*s.dot(h)
	if u<0 or u>1:return false
	var q: Vector3=s.cross(e1);var v: float=inverse*direction.dot(q)
	if v<0 or u+v>1:return false
	var t: float=inverse*e2.dot(q)
	return t>=0 and t<=1

func segment_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	var first: Vector3=b-a;var second: Vector3=d-c;var r: Vector3=a-c
	var aa: float=first.dot(first);var ee: float=second.dot(second);var f: float=second.dot(r)
	var s: float=0;var t: float=0
	if aa<1e-20 and ee<1e-20:return a.distance_squared_to(c)
	if aa<1e-20:t=clampf(f/ee,0,1)
	else:
		var cc: float=first.dot(r)
		if ee<1e-20:s=clampf(-cc/aa,0,1)
		else:
			var bb: float=first.dot(second);var denominator: float=aa*ee-bb*bb
			if absf(denominator)>1e-20:s=clampf((bb*f-cc*ee)/denominator,0,1)
			t=(bb*s+f)/ee
			if t<0:t=0;s=clampf(-cc/aa,0,1)
			elif t>1:t=1;s=clampf((bb-cc)/aa,0,1)
	return (a+first*s).distance_squared_to(c+second*t)

func triangle_distance(a: Array, b: Array) -> float:
	var best: float=INF
	for i in 3:
		if segment_triangle(a[i],a[(i+1)%3],b) or segment_triangle(b[i],b[(i+1)%3],a):return 0
		best=minf(best,a[i].distance_squared_to(point_triangle(a[i],b[0],b[1],b[2])))
		best=minf(best,b[i].distance_squared_to(point_triangle(b[i],a[0],a[1],a[2])))
		for j in 3:best=minf(best,segment_distance(a[i],a[(i+1)%3],b[j],b[(j+1)%3]))
	return best

func surface_distance(a: Array, b: Array) -> Dictionary:
	var best: float=INF;var measured: int=0
	for first in a:
		for second in b:
			# Bounds prune only impossible contenders. Accepted separation always
			# comes from actual vertex/edge/triangle distance, never a box proxy.
			var gap: Vector3=(first.min-second.max).max(second.min-first.max).max(Vector3.ZERO)
			if gap.length_squared()>=best:continue
			measured+=1;best=minf(best,triangle_distance(first.p,second.p))
			if best<1e-18:return {"distance":0.0,"triangle_pairs":measured}
	return {"distance":sqrt(best),"triangle_pairs":measured}

func run() -> void:
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var day := HouseholdDay.new()
	if not day.configure(plan):push_error("Canonical kitchen failed to configure");quit(1);return
	var triangles: Array=[]
	var root_frame: Transform3D=day.kitchen.pan_root_frame()
	var local_pan: Transform3D=root_frame.affine_inverse()
	for i in 3:
		var kind: String=day.kitchen.INGREDIENT_KINDS[i]
		var unit: Node3D=FOOD.create(kind,"scored");root.add_child(unit);unit.transform=day.kitchen.pan_support_frame(i)
		var actual: Array=[];collect(unit,Transform3D.IDENTITY,actual);triangles.append(actual)
		var wall_margin: float=INF;var bottom_margin: float=INF;var rim_margin: float=INF
		for triangle in actual:
			for point in triangle.p:
				var p: Vector3=local_pan*point
				var radius: float=lerpf(.125,.153,clampf((p.y-.012)/(.13-.012),0,1))
				wall_margin=minf(wall_margin,radius-Vector2(p.x,p.z).length());bottom_margin=minf(bottom_margin,p.y-.012);rim_margin=minf(rim_margin,.13-p.y)
		observations[kind]={"actual_triangles":actual.size(),"wall_margin_m":wall_margin,"bottom_margin_m":bottom_margin,"rim_margin_m":rim_margin}
		expect(not actual.is_empty() and wall_margin>=-.000001 and bottom_margin>=-.000001 and rim_margin>=-.000001,kind+" actual food vertices fit the real inner frustum above its bottom and below its rim")
		unit.free()
	for i in 3:
		for j in range(i+1,3):
			var measurement := surface_distance(triangles[i],triangles[j]);observations["pair_%d_%d"%[i,j]]=measurement
			expect(measurement.triangle_pairs>0 and measurement.distance>.0005,"Actual food surfaces remain separated without interpenetration")
	var coincident := surface_distance(triangles[0],triangles[0])
	expect(coincident.distance==0 and coincident.triangle_pairs>0,"Actual-triangle comparison detects a deliberately coincident food surface")
	DirAccess.make_dir_recursive_absolute("res://builds/kitchen-state")
	var file := FileAccess.open("res://builds/kitchen-state/geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"scope":"static actual native food triangles and actual casserole profile; no skin/motion acceptance"},"\t"))
	print("Kitchen actual geometry checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

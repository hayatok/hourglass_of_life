class_name HouseholdFood
extends RefCounted

# Metre-scale geometry, not a recipe or inventory controller. A root represents
# one existing recipe unit; changing whole/cut never creates another unit ID.
# +Y is up, +Z is the long axis, and identity placement has real bottom y=0.
# "Whole cabbage" means a purchased quarter, not an entire two-hand cabbage.
const KINDS := ["carrot","potato","cabbage"]
const STATES := ["whole","scored","cut"]
static var _cache: Dictionary = {}

static func kinds() -> Array:return KINDS.duplicate()
static func states() -> Array:return STATES.duplicate()

static func create(kind: String, state: String = "whole") -> Node3D:
	var data: Dictionary=_data(kind,state)
	if data.is_empty():return null
	var root := Node3D.new();root.name="HouseholdFood_"+kind+"_"+state
	root.set_meta("ingredient_kind",kind);root.set_meta("food_state",state)
	root.set_meta("geometry_source","native_procedural_metres; one existing recipe unit")
	for piece: Dictionary in data.pieces:
		var child := Node3D.new();child.name=piece.id;child.transform=piece.local_frame;root.add_child(child)
		child.set_meta("piece_id",piece.id)
		for part: Dictionary in piece.parts:
			if part.vertices.is_empty():continue
			var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=part.vertices;arrays[Mesh.ARRAY_NORMAL]=part.normals;arrays[Mesh.ARRAY_TEX_UV]=part.uvs
			var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var instance := MeshInstance3D.new();instance.name=part.name;instance.mesh=mesh
			instance.material_override=_material(part.material);child.add_child(instance)
	var contacts := Node3D.new();contacts.name="Contacts";root.add_child(contacts)
	for hand: String in data.spec.local_grips:_marker(contacts,"Grip"+hand,data.spec.local_grips[hand])
	for feature: String in data.spec.working_frames:_marker(contacts,feature,data.spec.working_frames[feature])
	_marker(contacts,"Support",Transform3D(Basis.IDENTITY,data.spec.support_local))
	return root

static func spec(kind: String, state: String = "whole") -> Dictionary:
	var data: Dictionary=_data(kind,state)
	return data.spec.duplicate(true) if not data.is_empty() else {}

static func grips_for(kind: String, state: String = "whole", hand: String = "R") -> Dictionary:
	var description: Dictionary=spec(kind,state)
	return {hand:description.local_grips[hand]} if description.get("local_grips",{}).has(hand) else {}

static func palm_target(kind: String, state: String, food_world: Transform3D, hand: String = "R") -> Variant:
	var grips: Dictionary=grips_for(kind,state,hand)
	return food_world*grips[hand] if _rigid_frame(food_world) and grips.has(hand) else null

static func support_for(kind: String, state: String = "whole", orientation: Basis = Basis.IDENTITY) -> Variant:
	var data: Dictionary=_data(kind,state)
	if data.is_empty() or not _rigid_basis(orientation):return null
	var bottom := INF;var support := Vector3.ZERO
	for point: Vector3 in data.points:
		var y: float=(orientation*point).y
		if y<bottom:bottom=y;support=point
	return support

static func park_on(kind: String, state: String, support_world: Transform3D) -> Variant:
	if not _rigid_frame(support_world):return null
	var support: Variant=support_for(kind,state,support_world.basis)
	if not support is Vector3:return null
	return Transform3D(support_world.basis,support_world.origin-support_world.basis*support)

static func _rigid_basis(value: Basis) -> bool:
	return value.is_finite() and absf(value.determinant()-1)<.0001 and absf(value.x.length()-1)<.0001 and absf(value.y.length()-1)<.0001 and absf(value.z.length()-1)<.0001 and absf(value.x.dot(value.y))<.0001 and absf(value.x.dot(value.z))<.0001 and absf(value.y.dot(value.z))<.0001

static func _rigid_frame(value: Transform3D) -> bool:return value.origin.is_finite() and _rigid_basis(value.basis)

static func _marker(parent: Node3D, name: String, frame: Transform3D) -> void:
	var marker := Marker3D.new();marker.name=name;marker.transform=frame;parent.add_child(marker)

static func _material(key: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new();result.roughness=.88
	match key:
		"carrot_skin":result.albedo_color=Color("d88743")
		"carrot_flesh":result.albedo_color=Color("efa45b")
		"carrot_core":result.albedo_color=Color("e1b25d")
		"carrot_groove":result.albedo_color=Color("b96c35")
		"stem":result.albedo_color=Color("71875b")
		"potato_skin":result.albedo_color=Color("b59a71")
		"potato_eye":result.albedo_color=Color("8b7458")
		"potato_flesh":result.albedo_color=Color("e4d4a1")
		"cabbage_skin":result.albedo_color=Color("8aa36c")
		"cabbage_leaf":result.albedo_color=Color("aec085")
		"cabbage_flesh":result.albedo_color=Color("d6dcb3")
		"cabbage_core":result.albedo_color=Color("ece5c3")
		_:result.albedo_color=Color("b9c695")
	return result

static func _part(name: String, material: String) -> Dictionary:
	return {"name":name,"material":material,"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uvs":PackedVector2Array()}

static func _triangle(part: Dictionary, a: Vector3, b: Vector3, c: Vector3, outside: Vector3) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared()<.000000000000000001:return
	if cross.dot(outside)>0:
		var swap := b;b=c;c=swap
	var normal: Vector3=outside.normalized()
	for point: Vector3 in [a,b,c]:
		part.vertices.append(point);part.normals.append(normal);part.uvs.append(Vector2(point.x,point.z))

static func _quad(part: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_triangle(part,a,b,c,normal);_triangle(part,a,c,d,normal)

static func _loft(name: String, material: String, rings: Array, segments: int = 16) -> Dictionary:
	var part: Dictionary=_part(name,material)
	for row in range(rings.size()-1):
		var a: Vector4=rings[row];var b: Vector4=rings[row+1]
		for segment in segments:
			var first: float=TAU*segment/segments;var last: float=TAU*(segment+1)/segments
			var aa := Vector3(cos(first)*a.y,a.w+sin(first)*a.z,a.x)
			var ab := Vector3(cos(last)*a.y,a.w+sin(last)*a.z,a.x)
			var ba := Vector3(cos(first)*b.y,b.w+sin(first)*b.z,b.x)
			var bb := Vector3(cos(last)*b.y,b.w+sin(last)*b.z,b.x)
			var normal := Vector3(cos((first+last)*.5),sin((first+last)*.5),(a.y-b.y)/maxf(.0001,b.x-a.x)).normalized()
			_quad(part,aa,ba,bb,ab,normal)
	for end in [0,rings.size()-1]:
		var ring: Vector4=rings[end]
		for segment in segments:
			var first: float=TAU*segment/segments;var last: float=TAU*(segment+1)/segments
			_triangle(part,Vector3(0,ring.w,ring.x),Vector3(cos(first)*ring.y,ring.w+sin(first)*ring.z,ring.x),Vector3(cos(last)*ring.y,ring.w+sin(last)*ring.z,ring.x),Vector3.FORWARD if end==0 else Vector3.BACK)
	return part

static func _carrot() -> Array:
	var parts: Array=[]
	var rings := [Vector4(-.075,.009,.009,.015),Vector4(-.067,.016,.015,.016),Vector4(-.042,.015,.014,.015),Vector4(-.012,.0125,.012,.014),Vector4(.023,.009,.009,.012),Vector4(.053,.005,.005,.010),Vector4(.075,.0015,.0015,.008)]
	parts.append(_loft("CarrotSkin","carrot_skin",rings))
	# Tiny shallow growth bands are real native strips, not text or a parcel.
	for band in range(1,rings.size()-1):
		var ring: Vector4=rings[band]
		parts.append(_loft("GrowthBand%d"%band,"carrot_groove",[Vector4(ring.x-.00035,ring.y+.00008,ring.z+.00008,ring.w),Vector4(ring.x+.00035,ring.y+.00008,ring.z+.00008,ring.w)]))
	var stem: Dictionary=_part("StemEnds","stem")
	for i in 3:
		var at := Vector3((i-1)*.004,.018,-.074)
		var tip: Vector3=at+Vector3((i-1)*.002,.010,-.008)
		var width := Vector3(.0015,0,0)
		_quad(stem,at-width,tip-width,tip+width,at+width,Vector3.UP)
		_quad(stem,at+width,tip+width,tip-width,at-width,Vector3.DOWN)
	parts.append(stem)
	return parts

static func _potato() -> Array:
	var parts: Array=[];var rings: Array=[]
	for row in 13:
		var t: float=-PI*.5+PI*row/12
		var radius: float=cos(t)
		var z: float=.034*sin(t)
		rings.append(Vector4(z,.0325*radius*(1+.035*sin(t*3)),.027*radius,.028+.0015*sin(t*2)))
	parts.append(_loft("PotatoSkin","potato_skin",rings))
	# Eyes sit on actual surface triangle centroids, never below the support.
	var skin: Dictionary=parts[0]
	for target: Vector3 in [Vector3(-.019,.049,-.014),Vector3(.018,.047,.009),Vector3(.004,.054,.022)]:
		var surface: Dictionary=_surface_anchor(skin.vertices,target,Vector3.UP)
		var frame: Transform3D=surface.frame
		var eye: Dictionary=_part("PotatoEye%d"%parts.size(),"potato_eye")
		var normal: Vector3=-frame.basis.z
		var center: Vector3=frame.origin+normal*.00008
		for side in 8:
			var a: float=TAU*side/8;var b: float=TAU*(side+1)/8
			_triangle(eye,center,center+(frame.basis.x*cos(a)+frame.basis.y*sin(a))*.0011,center+(frame.basis.x*cos(b)+frame.basis.y*sin(b))*.0011,normal)
		parts.append(eye)
	return parts

static func _cabbage() -> Array:
	# A quarter-head wedge: two pale, flat radial cut faces and a curved green
	# leaf exterior. It is intentionally one-hand sized, not a whole .25m head.
	var outer: Dictionary=_part("CabbageLeafOutside","cabbage_skin")
	var face: Dictionary=_part("CabbageQuarterFaces","cabbage_flesh")
	var levels := 12;var arcs := 12
	for row in levels:
		var za: float=-PI*.5+PI*row/levels;var zb: float=-PI*.5+PI*(row+1)/levels
		var ra: float=cos(za);var rb: float=cos(zb)
		for segment in arcs:
			var a: float=PI*.5*segment/arcs;var b: float=PI*.5*(segment+1)/arcs
			var aa := Vector3(-.030+.060*cos(a)*ra,.056*sin(a)*ra,.045*sin(za))
			var ab := Vector3(-.030+.060*cos(b)*ra,.056*sin(b)*ra,.045*sin(za))
			var ba := Vector3(-.030+.060*cos(a)*rb,.056*sin(a)*rb,.045*sin(zb))
			var bb := Vector3(-.030+.060*cos(b)*rb,.056*sin(b)*rb,.045*sin(zb))
			var normal := Vector3(cos((a+b)*.5)/.060,sin((a+b)*.5)/.056,sin((za+zb)*.5)/.045).normalized()
			_quad(outer,aa,ba,bb,ab,normal)
		for side in [0,1]:
			var ca := Vector3(-.030,0,.045*sin(za));var cb := Vector3(-.030,0,.045*sin(zb))
			var aa := ca+Vector3(.060*ra,0,0) if side==0 else ca+Vector3(0,.056*ra,0)
			var bb := cb+Vector3(.060*rb,0,0) if side==0 else cb+Vector3(0,.056*rb,0)
			_quad(face,ca,cb,bb,aa,Vector3.DOWN if side==0 else Vector3.LEFT)
	var layers: Dictionary=_part("NestedCabbageLeaves","cabbage_leaf")
	for layer in range(1,8):
		var scale: float=float(layer)/8
		for side in [0,1]:
			for step in 16:
				var a: float=-PI*.5+PI*step/16;var b: float=-PI*.5+PI*(step+1)/16
				var aa := Vector3(-.0303,.056*scale*cos(a),.045*scale*sin(a)) if side else Vector3(-.030+.060*scale*cos(a),-.0003,.045*scale*sin(a))
				var bb := Vector3(-.0303,.056*scale*cos(b),.045*scale*sin(b)) if side else Vector3(-.030+.060*scale*cos(b),-.0003,.045*scale*sin(b))
				var inward := Vector3(0,-.00065,0) if side else Vector3(-.00065,0,0)
				_quad(layers,aa,bb,bb+inward,aa+inward,Vector3.LEFT if side else Vector3.DOWN)
	var core: Dictionary=_part("CabbageCoreFace","cabbage_core")
	for step in 12:
		var a: float=-PI*.5+PI*step/12;var b: float=-PI*.5+PI*(step+1)/12
		_triangle(core,Vector3(-.0304,0,0),Vector3(-.0304,.014*cos(a),.026*sin(a)),Vector3(-.0304,.014*cos(b),.026*sin(b)),Vector3.LEFT)
	return [outer,face,layers,core]

static func _surface_anchor(points: PackedVector3Array, target: Vector3, outward: Vector3) -> Dictionary:
	var best := INF;var origin := Vector3.ZERO;var normal := outward.normalized();var triangle_index := -1
	for i in range(0,points.size(),3):
		var a: Vector3=points[i];var b: Vector3=points[i+1];var c: Vector3=points[i+2]
		var n: Vector3=(c-a).cross(b-a).normalized()
		if n.dot(outward.normalized())<.30:continue
		var center: Vector3=(a+b+c)/3
		var score: float=center.distance_squared_to(target)+.0002*(1-n.dot(outward.normalized()))
		if score<best:best=score;origin=center;normal=n;triangle_index=i/3
	var z: Vector3=-normal;var y: Vector3=Vector3.BACK-z*Vector3.BACK.dot(z)
	if y.length_squared()<.00001:y=Vector3.UP-z*Vector3.UP.dot(z)
	y=y.normalized();var x: Vector3=y.cross(z).normalized();y=z.cross(x).normalized()
	return {"frame":Transform3D(Basis(x,y,z),origin),"outward":normal,"triangle_index":triangle_index}

static func _clip(polygon: Array, axis: int, edge: float, less: bool) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	if polygon.is_empty():return result
	var previous: Vector3=polygon[-1]
	var inside_before: bool=previous[axis]<=edge+.000000001 if less else previous[axis]>=edge-.000000001
	for point: Vector3 in polygon:
		var inside_now: bool=point[axis]<=edge+.000000001 if less else point[axis]>=edge-.000000001
		if inside_now!=inside_before:
			result.append(previous.lerp(point,(edge-previous[axis])/(point[axis]-previous[axis])))
		if inside_now:result.append(point)
		previous=point;inside_before=inside_now
	return result

static func _section(points: PackedVector3Array, axis: int, edge: float) -> PackedVector3Array:
	var found: Array[Vector3]=[]
	for i in range(0,points.size(),3):
		for k in 3:
			var a: Vector3=points[i+k];var b: Vector3=points[i+(k+1)%3]
			if absf(a[axis]-edge)<.0000001:
				if found.all(func(p: Vector3):return p.distance_squared_to(a)>.00000000000001):found.append(a)
			if (a[axis]<edge and b[axis]>edge) or (a[axis]>edge and b[axis]<edge):
				var point: Vector3=a.lerp(b,(edge-a[axis])/(b[axis]-a[axis]))
				if found.all(func(p: Vector3):return p.distance_squared_to(point)>.00000000000001):found.append(point)
	if found.size()<3:return PackedVector3Array()
	var center := Vector3.ZERO
	for point: Vector3 in found:center+=point
	center/=found.size()
	var first: int=2 if axis==0 else 0;var second: int=2 if axis==1 else 1
	found.sort_custom(func(a: Vector3,b: Vector3):return atan2(a[second]-center[second],a[first]-center[first])<atan2(b[second]-center[second],b[first]-center[first]))
	return PackedVector3Array(found)

static func _slice(parts: Array, low: float, high: float, axis: int, material: String) -> Array:
	var result: Array=[];var skin_points := PackedVector3Array()
	for original: Dictionary in parts:
		var clipped: Dictionary=_part(original.name,original.material)
		for i in range(0,original.vertices.size(),3):
			var polygon: Array=_clip([original.vertices[i],original.vertices[i+1],original.vertices[i+2]],axis,low,false)
			polygon=_clip(polygon,axis,high,true)
			for k in range(1,polygon.size()-1):_triangle(clipped,polygon[0],polygon[k],polygon[k+1],original.normals[i])
		if not clipped.vertices.is_empty():result.append(clipped)
		# Primary solid only. Decoration must not define fictitious cut caps.
		if original.name in ["CarrotSkin","PotatoSkin","CabbageLeafOutside","CabbageQuarterFaces"]:skin_points.append_array(original.vertices)
	var caps: Dictionary=_part("FreshCutFaces",material)
	for edge: float in [low,high]:
		var outline: PackedVector3Array=_section(skin_points,axis,edge)
		if outline.size()<3:continue
		var center := Vector3.ZERO
		for point: Vector3 in outline:center+=point
		center/=outline.size()
		var normal := Vector3.ZERO;normal[axis]=-1 if edge==low else 1
		for index in outline.size():_triangle(caps,center,outline[index],outline[(index+1)%outline.size()],normal)
	if not caps.vertices.is_empty():result.append(caps)
	return result

static func _cap_polygon(part: Dictionary, polygon: Array, normal: Vector3) -> void:
	if polygon.size()<3:return
	var center := Vector3.ZERO
	for point: Vector3 in polygon:center+=point
	center/=polygon.size()
	for index in polygon.size():_triangle(part,center,polygon[index],polygon[(index+1)%polygon.size()],normal)

static func _scored(parts: Array, solid: PackedVector3Array, cuts: Array, core_y: float, material: String) -> Array:
	var result: Array=parts.duplicate(true)
	# Remove a real 1.4mm kerf only above the retained lower 38% of the unit.
	# No separate upper chunk is spawned: the original solid core crosses
	# every slot. New interior walls and the kerf floor close the actual mesh.
	var half_gap := .0007
	for cut: float in cuts:
		var low: float=cut-half_gap;var high: float=cut+half_gap
		var next: Array=[]
		for original: Dictionary in result:
			var clipped: Dictionary=_part(original.name,original.material)
			for i in range(0,original.vertices.size(),3):
				var polygon: Array=[original.vertices[i],original.vertices[i+1],original.vertices[i+2]]
				var left: Array=_clip(polygon,2,low,true)
				var middle: Array=_clip(polygon,2,low,false)
				var right: Array=_clip(middle,2,high,false)
				middle=_clip(middle,2,high,true)
				var bottom: Array=_clip(middle,1,core_y,true)
				for keep: Array in [left,right,bottom]:
					for k in range(1,keep.size()-1):_triangle(clipped,keep[0],keep[k],keep[k+1],original.normals[i])
			if not clipped.vertices.is_empty():next.append(clipped)
		var interior: Dictionary=_part("ScoreInterior%d"%next.size(),material)
		for edge: float in [low,high]:
			var section: Array=Array(_section(solid,2,edge))
			section=_clip(section,1,core_y,false)
			_cap_polygon(interior,section,Vector3.BACK if edge==low else Vector3.FORWARD)
		var floor_section: Array=Array(_section(solid,1,core_y))
		floor_section=_clip(floor_section,2,low,false);floor_section=_clip(floor_section,2,high,true)
		_cap_polygon(interior,floor_section,Vector3.UP)
		if not interior.vertices.is_empty():next.append(interior)
		result=next
	return result

static func _points(parts: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for part: Dictionary in parts:result.append_array(part.vertices)
	return result

static func _bounds(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():return {}
	var minimum: Vector3=points[0];var maximum: Vector3=points[0]
	for point: Vector3 in points:minimum=minimum.min(point);maximum=maximum.max(point)
	return {"min":minimum,"max":maximum,"position":minimum,"size":maximum-minimum}

static func _data(kind: String, state: String) -> Dictionary:
	if kind not in KINDS or state not in STATES:return {}
	var key: String=kind+":"+state
	if _cache.has(key):return _cache[key]
	var originals: Array=[]
	match kind:
		"carrot":originals=_carrot()
		"potato":originals=_potato()
		"cabbage":originals=_cabbage()
	# Normalize once from real vertices; the same shift applies to whole/cut.
	var original_points: PackedVector3Array=_points(originals)
	var shift: float=float(_bounds(original_points).min.y)
	for part: Dictionary in originals:
		for i in part.vertices.size():part.vertices[i]-=Vector3.UP*shift
	original_points=_points(originals)
	var source_bounds: Dictionary=_bounds(original_points)
	var cuts: Array=[-.0375,0.0,.0375] if kind=="carrot" else [-.011, .011] if kind=="potato" else [-.015,.015]
	var cut_planes: Array=[];var whole_work := {};var solid := PackedVector3Array()
	for part: Dictionary in originals:
		if part.name in ["CarrotSkin","PotatoSkin","CabbageLeafOutside","CabbageQuarterFaces"]:solid.append_array(part.vertices)
	for i in cuts.size():
		var outline: PackedVector3Array=_section(solid,2,cuts[i])
		var center := Vector3.ZERO;var entry := Vector3(0,-INF,cuts[i])
		for vertex: Vector3 in outline:
			center+=vertex
			if vertex.y>entry.y:entry=vertex
		center/=maxi(1,outline.size())
		var id: String="Cut%d"%i;var frame := Transform3D(Basis.IDENTITY,center)
		var entry_frame := Transform3D(Basis.IDENTITY,entry)
		cut_planes.append({"id":id,"frame":frame,"axis":"z","normal":Vector3.BACK,"outline_local":outline,"entry_local":entry_frame})
		whole_work[id]=entry_frame
	var core_y: float=source_bounds.min.y+source_bounds.size.y*.38
	var pieces: Array=[]
	if state=="whole":pieces.append({"id":"Whole","local_frame":Transform3D.IDENTITY,"parts":originals})
	elif state=="scored":pieces.append({"id":"Scored","local_frame":Transform3D.IDENTITY,"parts":_scored(originals,solid,cuts,core_y,kind+"_flesh")})
	else:
		var limits: Array=[float(source_bounds.min.z)-.001];limits.append_array(cuts);limits.append(float(source_bounds.max.z)+.001)
		for i in range(limits.size()-1):
			var body: Array=_slice(originals,limits[i],limits[i+1],2,kind+"_flesh")
			var points: PackedVector3Array=_points(body)
			var piece_bounds: Dictionary=_bounds(points)
			var center: Vector3=(piece_bounds.min+piece_bounds.max)*.5
			# A small separation reveals real cut faces. It is a child frame,
			# never another inventory unit or an animated root replacement.
			var separation := Vector3(0,-piece_bounds.min.y,(i-float(limits.size()-2)*.5)*.0012)
			for part: Dictionary in body:
				for index in part.vertices.size():part.vertices[index]-=center
			pieces.append({"id":"Piece%02d"%i,"local_frame":Transform3D(Basis.IDENTITY,center+separation),"parts":body})
	var all := PackedVector3Array();var piece_specs: Array=[]
	for piece: Dictionary in pieces:
		var points: PackedVector3Array=_points(piece.parts)
		for point: Vector3 in points:all.append(piece.local_frame*point)
		var local_support := Vector3.ZERO;var local_low := INF
		for point: Vector3 in points:
			if point.y<local_low:local_low=point.y;local_support=point
		piece_specs.append({"id":piece.id,"local_frame":piece.local_frame,"bounds_local":_bounds(points),"support_local":local_support,"triangles":points.size()/3})
	var measured: Dictionary=_bounds(all)
	var target := Vector3(measured.min.x+measured.size.x*.15,measured.min.y+measured.size.y*.75,-.015 if kind=="carrot" else 0)
	var anchor: Dictionary=_surface_anchor(all,target,Vector3(-.8,.6,0))
	var grip: Transform3D=anchor.frame
	var support := Vector3.ZERO;var low := INF
	for point: Vector3 in all:
		if point.y<low:low=point.y;support=point
	var description := {"kind":kind,"state":state,"unit_description":"one purchased cabbage quarter" if kind=="cabbage" else "one ingredient",
		"units":"metres; +Y up,+Z long axis; common whole/cut root; identity bottom y0",
		"local_grips":{"R":grip},"grip_outward":anchor.outward,"grip_piece":"",
		"support_local":support,"bounds_local":measured,"source_bounds_local":source_bounds,
		"working_frames":whole_work if state=="whole" else {},"cut_planes":cut_planes,"cut_planes_source_state":"whole","pieces":piece_specs,"triangles":all.size()/3,
		"score":{"kerf_width":.0014,"core_y":core_y,"retained_height_fraction":.38,"cuts":cuts.duplicate(),"connected":state=="scored"},
		"geometry_method":"bounds/support/grip and cut contours measured from actual generated triangle vertices",
		"contact_status":"geometry only; actual skin palm/finger span and collision-free handling require character tests",
		"cut_transport_limit":"cut child frames represent one existing recipe unit; one surface palm anchor does not certify grasping every disconnected cut piece"}
	var first_triangle := 0
	for piece: Dictionary in pieces:
		var count: int=_points(piece.parts).size()/3
		if anchor.triangle_index>=first_triangle and anchor.triangle_index<first_triangle+count:description.grip_piece=piece.id
		first_triangle+=count
	_cache[key]={"pieces":pieces,"points":all,"spec":description}
	return _cache[key]

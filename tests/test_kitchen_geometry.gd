extends SceneTree

# Actual generated geometry, not merely two copies of the plan's metadata.
var failures: Array[String]=[]
var checks := 0

func _initialize() -> void:call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func point(a: Array) -> Vector3:return Vector3(a[0],a[1],a[2])

func run() -> void:
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	if not game.initialization_error.is_empty():expect(false,game.initialization_error);game.free();quit(1);return
	var prep: Dictionary=game.house.fixtures.prep
	var stove: Dictionary=game.house.fixtures.stove
	var board: MeshInstance3D=prep.node.find_child("CuttingBoard",true,false)
	var box: AABB=board.mesh.get_aabb()
	var top: Vector3=board.to_global(box.get_center()+Vector3.UP*box.size.y*.5)
	expect(top.distance_to(game.house.to_global(point(prep.definition.operation_targets.work.surface)))<.00001,"The actual cutting-board top matches the operation target despite the off-centre approach")
	var pot: Node3D=game.household_props._hardware.get_node("OpenSourceSaucepan")
	var burner: Vector3=game.house.to_global(Vector3(4.36,.878,3.9675))
	expect(pot.global_position.distance_to(burner)<.00001,"The actual open pot stays on the left burner while the resident approaches that burner")
	for fixture in [prep,stove]:
		var moved: Dictionary=fixture.definition.duplicate(true)
		moved.interaction_point[0]+=1.0;moved.interaction_point[2]+=.3
		expect(LivingHouse.fixture_basis(moved).is_equal_approx(fixture.node.get_node("Art").basis),"Moving an operation approach does not rotate the actual "+fixture.definition.id+" geometry")
	var stack: Node3D=game.household_props.objects["inventory:clean_dishes:0"].node
	var worktop: MeshInstance3D=prep.node.find_child("Worktop",true,false)
	box=worktop.mesh.get_aabb()
	var local: Vector3=worktop.to_local(stack.global_position)
	expect(absf(local.y-(box.end.y+.003))<.00001 and absf(local.x)<box.size.x*.5-.10 and absf(local.z)<box.size.z*.5-.10,"The clean dish stack rests on the real worktop, away from its outer edges")
	var jar: Node3D=prep.node.find_child("UtensilCrock",true,false)
	expect(Vector2(stack.global_position.x-jar.global_position.x,stack.global_position.z-jar.global_position.z).length()>.16,"The dish stack does not occupy the utensil crock")
	print("Kitchen geometry alignment: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	game.free();quit(0 if failures.is_empty() else 1)

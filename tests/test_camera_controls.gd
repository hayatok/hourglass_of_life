extends SceneTree

# Synthetic engine events exercise the input paths. Native +/- operation and
# a physical Mac trackpad are separate acceptance records.
var main
var sim
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message);push_error(message)

func magnify(factor: float, position: Vector2) -> void:
	var event := InputEventMagnifyGesture.new();event.factor = factor;event.position = position
	main._unhandled_input(event)

func pan(delta: Vector2, position: Vector2) -> void:
	var event := InputEventPanGesture.new();event.delta = delta;event.position = position
	main._unhandled_input(event)

func run() -> void:
	root.size = Vector2i(1280,800)
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.set_process(false);sim = root.get_node("Sim");sim.set_process(false)
	main._new_game();sim.running = false
	await process_frame
	var world := Vector2(800,350)
	main.distance = 31
	magnify(2,world)
	expect(is_equal_approx(main.distance,15.5) and not sim.running,"A magnifying gesture zooms a paused town without starting time")
	magnify(.5,world)
	expect(is_equal_approx(main.distance,31),"Reversing the gesture factor restores the previous viewing distance")
	for factor in [0.0,-1.0,INF,NAN]: magnify(factor,world)
	expect(is_equal_approx(main.distance,31),"Invalid gesture factors do not corrupt the camera")
	magnify(1000000,world);var close_distance: float = main.distance
	magnify(.000001,world);var far_distance: float = main.distance
	expect(close_distance>=3.5 and far_distance<=48 and far_distance>close_distance,"Continuous gestures stay within the useful near and far limits, including a close view of hands and faces")
	main.distance = 20
	main.get_node("%ZoomIn").pressed.emit()
	var closer: float = main.distance
	main.get_node("%ZoomOut").pressed.emit()
	expect(closer<20 and is_equal_approx(main.distance,20),"Visible plus and minus buttons use the same reversible zoom")
	main.following = true
	var before: Vector3 = main.camera_target
	pan(Vector2(2,1),world)
	expect(main.camera_target.distance_to(before)>.01 and not main.following,"A two-finger pan moves the town and releases resident tracking")
	var card: Control = main.get_node("%HUD").get_node("SelectionPanel")
	var card_point := card.get_global_rect().get_center()
	before = main.camera_target;var distance: float = main.distance
	pan(Vector2(5,5),card_point);magnify(2,card_point)
	expect(main.camera_target==before and main.distance==distance,"Gestures on a resident card do not move the camera behind it")
	var roster: Control = main.get_node("%HUD").get_node("ResidentsPanel")
	var list_point := roster.get_global_rect().get_center()
	pan(Vector2(5,5),list_point);magnify(2,list_point)
	expect(main.camera_target==before and main.distance==distance,"Scrolling the roster does not pan or magnify the town")
	main.proposals.open_for("haru")
	pan(Vector2(5,5),world);magnify(2,world)
	expect(main.camera_target==before and main.distance==distance,"A proposal shields the background from camera gestures")
	main.proposals.close_panel()
	var search: LineEdit = main.get_node("%ResidentSearch");search.grab_focus()
	var key := InputEventKey.new();key.pressed = true;key.keycode = KEY_EQUAL
	main._unhandled_input(key)
	expect(main.distance==distance,"Typing a plus in the resident search does not zoom")
	search.release_focus();main._unhandled_input(key)
	expect(main.distance<distance,"The plus key offers a keyboard alternative outside text fields")
	main.get_node("%TownOverview").pressed.emit()
	expect(not main.following and main.camera_target==Vector3.ZERO and main.distance==31,"The town overview action restores a useful whole-town view")
	for dimensions in [Vector2i(1024,768),Vector2i(1280,800),Vector2i(1440,900)]:
		root.size = dimensions;root.content_scale_size = dimensions
		await process_frame
		await process_frame
		for name in ["ZoomIn","ZoomOut","TownOverview"]:
			var button: Control = main.get_node("%"+name)
			expect(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(button.get_global_rect()),name+" is reachable at %d pixels"%dimensions.x)
	print("Camera control checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

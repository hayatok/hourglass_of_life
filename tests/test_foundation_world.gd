extends SceneTree

var failures: Array[String]=[]
var checks:=0

func _initialize() -> void:call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<.00001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index in a.size():
			if not same(a[index],b[index]):return false
		return true
	return a==b

func simulate(game, seconds: float) -> void:
	for ignored in int(round(seconds*30)):game.executor.step(1.0/30.0,1.0/60.0)

func run() -> void:
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	expect(game.initialization_error.is_empty(),"The actual household scene instantiates with three bound actors, rooms, motion libraries and life execution")
	if not game.initialization_error.is_empty():quit(1);return
	for ignored in 6000:
		game.executor.step(1.0/30.0,1.0/60.0)
		var task: Dictionary=game.household.task_for("nagisa")
		if task.get("kind")=="cook" and task.get("phase_index")==2 and task.get("status")=="working" and float(task.get("phase_progress",0))>1:break
	var cooking: Dictionary=game.household.task_for("nagisa")
	expect(cooking.get("kind")=="cook" and cooking.get("phase_index")==2 and game.household.inventory.prepared_servings==0,"Physical routes and real cooking work reach an unfinished batch at the stove without already producing a meal")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(game.snapshot_day(),"",true,true))
	simulate(game,90)
	var future: Dictionary=game.snapshot_day()
	expect(game.restore_day(saved),"A JSON household save restores bodies, work in progress, shared supplies, room claims, door positions and executor state together")
	expect(same(saved,game.snapshot_day()),"Loading grants no extra time, food, practice or money and preserves motor and action progress")
	simulate(game,90)
	expect(same(future,game.snapshot_day()),"The same later physical movement and work after restoring produces the same household and body state")
	var before: Dictionary=game.snapshot_day()
	var bad: Dictionary=saved.duplicate(true);bad.bodies.nagisa.motor.position[0]+=2
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"A body position contradicting the saved household position is rejected without changing live state")
	bad=saved.duplicate(true);bad.executor.execution.rin.state="teleport"
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"An invalid action executor cannot partly restore resources or move another person")
	bad=saved.duplicate(true);bad.doors.erase("D01")
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"Missing door state rejects the entire load without touching the current day")
	bad=saved.duplicate(true);bad.bodies.ryo.action_elapsed=-1
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"Malformed animation progress cannot partly restore the household")
	print("Foundation world checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	game.free();quit(0 if failures.is_empty() else 1)

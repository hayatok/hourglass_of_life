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
		if a.size()==1 and b.size()==1 and a.has("$transform") and b.has("$transform"):
			var u: Variant=FoundationLocomotionPose._decode(a)
			var v: Variant=FoundationLocomotionPose._decode(b)
			if not u is Transform3D or not v is Transform3D:return false
			# Re-solving float32 skeletal rotations after JSON is judged in
			# physical units: <=0.5mm and <=0.057 degrees, not matrix-bit equality.
			return u.origin.distance_to(v.origin)<=.0005 and u.basis.get_scale().distance_to(v.basis.get_scale())<=.00001 and u.basis.orthonormalized().get_rotation_quaternion().angle_to(v.basis.orthonormalized().get_rotation_quaternion())<=.001
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
	# Real modifier callbacks are deferred. Advancing thousands of motor ticks
	# without an engine frame cannot establish a performed skeletal contact.
	if game._pose_resume_frames>0:
		game._process(0);await process_frame;await process_frame
	for ignored in int(round(seconds*30)):
		game.executor.step(1.0/30.0,1.0/60.0)
		await process_frame

func meaningful_state(data: Dictionary) -> Dictionary:
	var copy: Dictionary=data.duplicate(true)
	for body in copy.bodies.values():
		for key in ["locomotion","furniture"]:
			for counter in ["serial","applied","sample_serial","rendered_serial"]:body[key].erase(counter)
	# Rendering a restored pose refreshes diagnostic sample IDs. They are not
	# movement, contact geometry, household time, resources or performed work.
	return copy

func replay_differences(a: Variant, b: Variant, path: String, out: Array) -> void:
	if out.size()>=24 or same(a,b):return
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):out.append({"path":path+"/"+str(key),"missing":true})
			else:replay_differences(a[key],b[key],path+"/"+str(key),out)
	elif a is Array and b is Array and a.size()==b.size():
		for index in a.size():replay_differences(a[index],b[index],path+"/"+str(index),out)
	else:out.append({"path":path,"before":a,"replayed":b})

func record_replay(saved: Dictionary, future: Dictionary, replayed: Dictionary) -> void:
	var folder: String="res://builds/foundation-world-replay"
	DirAccess.make_dir_recursive_absolute(folder)
	for pair in [["checkpoint",saved],["future",future],["replayed",replayed]]:
		FileAccess.open(folder+"/"+pair[0]+".json",FileAccess.WRITE).store_string(JSON.stringify(pair[1],"\t"))
	var differences: Array=[]
	replay_differences(meaningful_state(future),meaningful_state(replayed),"",differences)
	FileAccess.open(folder+"/differences.json",FileAccess.WRITE).store_string(JSON.stringify(differences,"\t"))
	if not differences.is_empty():print("Replay mismatches: ",differences)

func run() -> void:
	var diagnostic: bool="--probe-replay" in OS.get_cmdline_user_args()
	var game=load("res://game/foundation/foundation_world.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	expect(game.initialization_error.is_empty(),"The actual household scene instantiates with three bound actors, rooms, motion libraries and life execution")
	if not game.initialization_error.is_empty():quit(1);return
	for ignored in (300 if diagnostic else 6000):
		game.executor.step(1.0/30.0,1.0/60.0)
		await process_frame
		var task: Dictionary=game.household.task_for("nagisa")
		if task.get("kind")=="cook" and task.get("phase_index")==2 and task.get("status")=="working" and float(task.get("phase_progress",0))>1:break
	var cooking: Dictionary=game.household.task_for("nagisa")
	if not diagnostic:expect(cooking.get("kind")=="cook" and cooking.get("phase_index")==2 and game.household.inventory.prepared_servings==0,"Physical routes and real cooking work reach an unfinished batch at the stove without already producing a meal")
	if not diagnostic and not failures.is_empty():
		game.free();quit(1);return
	var saved: Dictionary=JSON.parse_string(JSON.stringify(game.snapshot_day(),"",true,true))
	await simulate(game,4 if diagnostic else 90)
	var future: Dictionary=game.snapshot_day()
	expect(game.restore_day(saved),"A JSON household save restores bodies, work in progress, shared supplies, room claims, door positions and executor state together")
	expect(same(meaningful_state(saved),meaningful_state(game.snapshot_day())),"Loading grants no extra time, food, practice or money and preserves motor, actual pose and action progress")
	await simulate(game,4 if diagnostic else 90)
	var replayed: Dictionary=game.snapshot_day()
	record_replay(saved,future,replayed)
	expect(same(meaningful_state(future),meaningful_state(replayed)),"The same later physical movement and work after restoring produces the same household, pose and body state")
	if diagnostic:
		print("Short replay diagnosis only: ","matched" if failures.is_empty() else "diverged")
		game.free();quit(0 if failures.is_empty() else 1);return
	var before: Dictionary=game.snapshot_day()
	var bad: Dictionary=saved.duplicate(true);bad.bodies.nagisa.motor.position[0]+=2
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"A body position contradicting the saved household position is rejected without changing live state")
	bad=saved.duplicate(true);bad.executor.execution.rin.state="teleport"
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"An invalid action executor cannot partly restore resources or move another person")
	bad=saved.duplicate(true);bad.doors.erase("D01")
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"Missing door state rejects the entire load without touching the current day")
	bad=saved.duplicate(true);bad.bodies.ryo.action_elapsed=-1
	expect(not game.restore_day(bad) and same(before,game.snapshot_day()),"Malformed animation progress cannot partly restore the household")
	bad=saved.duplicate(true)
	var changed:=false
	for id in bad.executor.furniture:
		if not bad.executor.furniture[id].session.is_empty():bad.executor.furniture[id].session={};changed=true;break
	expect(changed and not game.restore_day(bad) and same(before,game.snapshot_day()),"A furniture transaction cannot disappear while the household still owns its seat or sleeping posture")
	bad=saved.duplicate(true);changed=false
	for id in bad.executor.furniture:
		if not bad.executor.furniture[id].session.is_empty():bad.executor.furniture[id].session.fixture="dining_nagisa";changed=true;break
	expect(changed and not game.restore_day(bad) and same(before,game.snapshot_day()),"A furniture session referring to another task's equipment is rejected before any body or resource is restored")
	print("Foundation world checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	game.free();quit(0 if failures.is_empty() else 1)

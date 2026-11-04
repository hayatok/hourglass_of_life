extends SceneTree

# Controlled source-state and real Skeleton3D attachment fixtures. Helpers place
# actors at use points and usage anchors explicitly; this is not a natural-play,
# walking, seat-entry or exit-motion test. Physical motion is accepted elsewhere.
const Props = preload("res://game/foundation/household_props.gd")
class PropModel extends Node3D:
	var skeleton: Skeleton3D
class PropActor extends Node3D:
	var model: PropModel
class ShiftHand extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void:
		var rig := get_skeleton()
		if rig!=null: rig.set_bone_pose_position(rig.find_bone("DEF-hand.L"),Vector3(.20,.15,.10))

var checks := 0
var failures: Array[String] = []
var _home: LivingHouse
var _day: HouseholdDay
var _view: HouseholdProps
var _actors: Dictionary = {}
var _plan: Dictionary
var _authored: Array = []
var _fixed_linen: Array = []
var _preserved_decor: Array = []

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> bool:
	checks+=1
	if not ok: failures.append(message);push_error(message)
	return ok

func _dispose() -> void:
	if is_instance_valid(_view): _view.free()
	_view=null
	for actor in _actors.values(): actor.free()
	_actors.clear()

func _make_actor(id: String) -> PropActor:
	var actor := PropActor.new();actor.name="Fixture_"+id;root.add_child(actor)
	actor.position=_day.people[id].position
	actor.model=PropModel.new();actor.add_child(actor.model)
	var rig := Skeleton3D.new();actor.model.skeleton=rig;actor.model.add_child(rig)
	for side in ["L","R"]:
		var hand: int=rig.get_bone_count();rig.add_bone("DEF-hand."+side)
		rig.set_bone_rest(hand,Transform3D(Basis.IDENTITY,Vector3(-.30 if side=="L" else .30,1,.20)))
		var finger: int=rig.get_bone_count();rig.add_bone("DEF-finger2."+side);rig.set_bone_parent(finger,hand)
		rig.set_bone_rest(finger,Transform3D(Basis.IDENTITY,Vector3(0,.07,0)))
	rig.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	return actor

func fresh(saved: Dictionary = {}) -> bool:
	_dispose()
	_day=HouseholdDay.new()
	if not expect(_day.configure(_plan,_authored),"The controlled household source configures"): return false
	if not saved.is_empty() and not expect(_day.restore(saved),"The actual household JSON source restores before rebuilding visuals"): return false
	for id in _day.people: _actors[id]=_make_actor(id)
	_view=Props.new();root.add_child(_view)
	return expect(_view.configure(_home,_day,_actors),"Props bind the plan, source controller and actual skeletal sockets")

func begin(actor: String, kind: String) -> Dictionary:
	var result: Dictionary=_day.request(actor,kind)
	expect(result.status=="requested",actor+" requests controlled "+kind+": "+str(result.reason))
	_view.sync()
	return result.get("task",{})

func arrive(actor: String) -> bool:
	var task: Dictionary=_day.task_for(actor)
	if task.is_empty(): return false
	_actors[actor].position=task.target;_day.set_position(actor,task.target)
	var reply: Dictionary=_day.arrive(actor,task.id)
	if not expect(reply.status in ["arrived","phase_ready","entering"],"The source admits only the controlled actual approach"):return false
	if reply.status=="entering":
		var region: Dictionary=_day._usage_regions[task.fixture]
		var anchor: Vector3=_day._point(region.center)
		if _day._fixtures[task.fixture].type=="sofa":anchor.x=clampf(task.target.x,anchor.x-float(region.half_extents[0]),anchor.x+float(region.half_extents[0]))
		# Explicitly place this fixture body at the real authored usage region;
		# arrival alone never grants work, and this does not prove entry motion.
		_actors[actor].position=anchor;_day.set_position(actor,anchor)
		reply=_day.begin_use(actor,task.id,anchor,region.postures[0])
		if not expect(reply.status in ["arrived","phase_ready"],"The controlled actual position and posture enter the furniture usage region"):return false
	_view.sync()
	return true

func finish_phase(actor: String, task_id: String) -> Dictionary:
	var result: Dictionary=_day.finish(actor,task_id)
	if result.status!="leaving":return result
	var approach: Vector3=result.task.target
	_actors[actor].position=approach;_day.set_position(actor,approach)
	var ended: Dictionary=_day.end_use(actor,task_id,approach)
	if not expect(ended.status=="phase_ready","The controlled body exits to the walkable approach before committing completion"):return ended
	return _day.finish(actor,task_id)

func stop(actor: String, task_id: String, reason: String) -> Dictionary:
	var result: Dictionary=_day.cancel(actor,task_id,reason)
	if result.status!="leaving":return result
	var approach: Vector3=result.task.target
	_actors[actor].position=approach;_day.set_position(actor,approach)
	result=_day.end_use(actor,task_id,approach)
	expect(result.status=="cancelled","Controlled cancellation releases use only after the actual body returns to the approach")
	return result

func work(actor: String, minutes: float) -> Dictionary:
	var task: Dictionary=_day.task_for(actor)
	_day.advance_time(minutes)
	var reply: Dictionary=_day.perform(actor,task.id,minutes)
	_view.sync()
	return reply

func phase(actor: String) -> Dictionary:
	var task: Dictionary=_day.task_for(actor)
	if task.is_empty(): return {}
	if task.status not in ["arrived","working","phase_ready"] and not arrive(actor): return {}
	task=_day.task_for(actor)
	if task.status!="phase_ready":
		var remaining: float=float(task.phase_minutes)-float(task.phase_progress)
		var reply: Dictionary=work(actor,remaining)
		if not expect(reply.status=="phase_ready","Actual source work completes its present phase"): return {}
	var result: Dictionary=finish_phase(actor,task.id);_view.sync()
	return result

func complete(actor: String) -> bool:
	for ignored in 20:
		var result: Dictionary=phase(actor)
		if result.is_empty(): return false
		if result.status=="completed": return true
	return false

func count_type(source_type: String) -> int:
	var count := 0
	for record in _view.objects.values():
		if record.source_type==source_type: count+=1
	return count

func food_quantity() -> int:
	var count := 0
	for record in _view.objects.values():
		if record.kind=="food_portion" or record.kind=="plate" and float(record.food_fraction)>0: count+=int(record.quantity)
	return count

func unique_nodes() -> bool:
	var nodes: Array=[]
	for id in _view.objects:
		var node: Node3D=_view.objects[id].node
		if not is_instance_valid(node) or node in nodes or node.get_meta("source_id","")!=id: return false
		nodes.append(node)
	return true

func no_early_food() -> void:
	if not fresh(): return
	expect(_fixed_linen.size()==9 and _fixed_linen.all(func(entry):return not entry.node.visible),"All eight authored shelf linens and the washer towel are hidden, including auto-renamed duplicate meshes")
	expect(_preserved_decor.all(func(entry):return entry.node.visible==entry.visible),"Books, family wall drawings and work pictures keep their original visibility")
	var linen_support := _view._v(_plan.fixtures.filter(func(record):return record.id=="linen_storage")[0].support_point)
	expect(absf(_view.objects["inventory:clean_laundry:0"].node.position.y-linen_support.y-.0025)<.00001,"Real clean linens rest on the authored storage support plane rather than an imaginary .95m shelf")
	var before: Dictionary=_day.snapshot()
	var manifest: Dictionary=_view.manifest()
	for ignored in 5: _view.sync(.1)
	expect(HouseholdDay._same(before,_day.snapshot()) and _view.manifest()==manifest,"Repeated visual sync changes no clock, stock, work, household need or source identity")
	expect(food_quantity()==0 and _view.represented_quantity("inventory","ingredients")==9,"Initial ingredients are real stock and no cooked meal appears before work")
	expect(_view.represented_quantity("inventory","clean_laundry")==6 and not _view.objects.keys().any(func(id):return str(id).begins_with("inventory:clean_towels:")),"Six clean towels are a subset of six textiles, rather than twelve independent objects")
	begin("nagisa","cook")
	expect(food_quantity()==0 and _view.represented_quantity("job","cook")==0,"A cooking intention creates neither a material batch nor prepared food")
	if not arrive("nagisa"): return
	expect(food_quantity()==0 and _view.represented_quantity("inventory","ingredients")==9,"Arrival alone produces no food or ingredient debit")
	work("nagisa",1)
	expect(_view.represented_quantity("inventory","ingredients")==6 and _view.represented_quantity("job","cook")==3 and food_quantity()==0,"The actual first work debit transfers three raw units into a unique unfinished batch")
	expect(unique_nodes(),"Every source slot owns one distinct scene object")
	var initial: Dictionary=_day.snapshot();var old: Dictionary=_view.manifest()
	_view.configure(_home,_day,_actors)
	expect(_view.manifest()==old and HouseholdDay._same(initial,_day.snapshot()) and unique_nodes(),"Reconfiguring replaces its own layer without duplicating stock or changing the source")
	expect(_fixed_linen.all(func(entry):return not entry.node.visible) and _preserved_decor.all(func(entry):return entry.node.visible==entry.visible),"Rebuilding continues replacing only source-stock decoration")
	_view.free();_view=null
	expect(_fixed_linen.all(func(entry):return entry.node.visible==entry.visible) and _preserved_decor.all(func(entry):return entry.node.visible==entry.visible),"Removing the derived layer restores its own hidden artwork without changing family decoration")

func carry_cancel_and_resume() -> void:
	if not fresh(): return
	begin("nagisa","cook")
	if not expect(phase("nagisa").status=="next_phase","Taking materials completes before the carry starts"): return
	var batch: Dictionary=_day.batch_location("cook")
	var original_node: Node3D=_view.objects["job:cook:0"].node
	var held: Dictionary=_view.pose_for("nagisa")
	var socket: BoneAttachment3D=_view.hand_socket("nagisa")
	expect(batch.holder=="nagisa" and not held.is_empty() and _view.objects[held.source_id].node.get_parent()==socket and not socket.override_pose,"A real held batch is attached to the actual hand bone without overriding the skeleton")
	expect(not held.get("pose_accepted",true) and _view.diagnostics.any(func(row):return row.kind=="carry_pose_not_accepted"),"Bone attachment alone never claims accepted carrying, supporting-hand contact or full-body motion")
	var actor_position: Vector3=_actors.nagisa.position
	var source_before: Dictionary=_day.snapshot()
	var rig: Skeleton3D=_actors.nagisa.model.skeleton
	# Skeleton dirty/update notifications are deferred even with a manual
	# modifier clock. Flush initial attachments, then observe a completed frame.
	await process_frame
	var before: Transform3D=socket.global_transform
	var modifier := ShiftHand.new();rig.add_child(modifier)
	rig.advance(.02)
	await process_frame
	var observed: Transform3D=_view.socket_samples.nagisa.L
	if observed.origin.distance_to(before.origin+Vector3(.20,.15,.10))>=.001: print("PROPS_SOCKET_DIAG before=",before.origin," observed=",observed.origin," expected=",before.origin+Vector3(.20,.15,.10))
	expect(observed.origin.distance_to(before.origin+Vector3(.20,.15,.10))<.001,"Socket telemetry observes the actual post-modifier hand transform inside the skeleton signal")
	expect(_actors.nagisa.position==actor_position and HouseholdDay._same(source_before,_day.snapshot()),"Following the final hand moves neither the motor root nor any logical batch/need")
	modifier.active=false;modifier.queue_free()
	var current: Dictionary=_day.task_for("nagisa")
	stop("nagisa",current.id,"Controlled interruption during carry");_view.sync()
	expect(_day.batch_location("cook").holder=="nagisa" and not _view.pose_for("nagisa").is_empty() and _view.objects["job:cook:0"].node==original_node,"Cancelling an in-flight task retains its same real held batch and visual objects")
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(_day.snapshot()))
	var held_manifest: Dictionary=_view.manifest()
	if not fresh(snapshot): return
	expect(_view.manifest()==held_manifest and unique_nodes(),"A held-cancel JSON restore reconstructs the same sources and ownership exactly once")
	var blocked: Dictionary=_day.request("ryo","cook")
	expect(blocked.status!="requested","Another resident cannot silently acquire a batch still in the first resident's hands")
	var down: Dictionary=_day.request("nagisa","quiet");_view.sync()
	if not expect(down.task.get("kind")=="put_down" and complete("nagisa"),"Before changing activities, the source executes an actual safe put-down"): return
	var placed: Dictionary=_day.batch_location("cook")
	expect(placed.holder.is_empty() and not placed.container.is_empty() and _view.pose_for("nagisa").is_empty() and _view.represented_quantity("job","cook")==3,"Only the real put-down releases the holder and retains all three unfinished units")
	begin("ryo","cook")
	var pickup: Dictionary=_day.task_for("ryo")
	if not expect(pickup.phases[pickup.phase_index].get("transport")=="pickup","The replacement resident first targets the actual stored batch"): return
	expect(_view.pose_for("ryo").is_empty(),"An assigned pickup has no carried object before actual source pickup")
	phase("ryo")
	expect(_day.batch_location("cook").batch_id==batch.batch_id and _view.represented_quantity("job","cook")==3 and _view.pose_for("ryo").holder=="ryo","After actual pickup, the same batch transfers to the replacement's real hand")

func meal_and_dishes() -> void:
	if not fresh(): return
	begin("nagisa","cook")
	if not expect(complete("nagisa"),"All real cooking phases complete in the controlled source"): return
	expect(_view.represented_quantity("inventory","prepared_servings")==3 and _view.represented_quantity("inventory","table_servings")==0 and food_quantity()==3,"Completed cooking shows three prepared portions at the stove and no premature table meal")
	begin("ryo","serve")
	if not expect(complete("ryo"),"Actual serving and transport complete"): return
	expect(_view.represented_quantity("inventory","table_servings")==3 and _view.represented_quantity("inventory","clean_dishes")==3 and _view.represented_quantity("job","serve")==0,"Serving transfers one finite three-dish batch to actual table positions")
	begin("rin","eat")
	if not arrive("rin"): return
	work("rin",3)
	var plate: Dictionary=_view.objects["job:eat:rin:0"]
	expect(is_equal_approx(float(plate.food_fraction),.75) and _view.represented_quantity("inventory","table_servings")==2 and _view.represented_quantity("inventory","dirty_dishes")==0,"Only actual eating reduces the food remaining on that resident's real plate")
	var id: String=_day.task_for("rin").id;stop("rin",id,"Controlled pause");_view.sync()
	expect(_view.objects["job:eat:rin:0"].food_fraction==.75 and _view.represented_quantity("job","eat:rin")==1,"An interrupted meal remains as one partially eaten plate")
	begin("rin","eat")
	if not expect(complete("rin"),"Resumed actual eating completes"): return
	expect(_view.represented_quantity("inventory","dirty_dishes")==1 and not _view.objects.has("job:eat:rin:0"),"Only real eating completion replaces the unfinished meal with one dirty dish")
	begin("ryo","wash_dishes")
	if not arrive("ryo"): return
	work("ryo",3)
	expect(_view.represented_quantity("job","wash_dishes")==1 and _view.represented_quantity("inventory","dirty_dishes")==0 and _view.represented_quantity("inventory","clean_dishes")==3,"In-progress washing owns the dirty dish and grants no premature clean stock")
	if not expect(complete("ryo"),"Actual dish washing completes"): return
	expect(_view.represented_quantity("inventory","clean_dishes")==4 and _view.represented_quantity("job","wash_dishes")==0 and unique_nodes(),"Washing returns exactly the one real dish without duplication")

func textiles() -> void:
	if not fresh(): return
	begin("nagisa","laundry")
	if not arrive("nagisa"): return
	work("nagisa",1)
	var batch: Dictionary=_day.batch_location("laundry")
	var carrier: Dictionary=_view.objects["job:laundry:carrier"]
	expect(batch.container=="linen_storage" and carrier.node.global_position.distance_to(_home.to_global(batch.position))<.00001,"A resting laundry basket uses the controller's exact authored support point, with no renderer-side relocation")
	if not expect(complete("nagisa"),"Collecting and loading the actual dirty textiles completes"): return
	expect(_view.represented_quantity("inventory","washing_laundry")==3 and _view.represented_quantity("inventory","dirty_laundry")==0 and _view.represented_quantity("job","laundry")==0,"The running machine displays its three inflight textiles once, rather than once per machine and inventory")
	_day.advance_time(float(_day.rules.wash_cycle_minutes));_view.sync()
	expect(_view.represented_quantity("inventory","wet_laundry")==3 and _view.represented_quantity("inventory","washing_laundry")==0,"Only the real machine-ready state changes washing stock into wet textiles")
	begin("ryo","hang_laundry")
	if not expect(complete("ryo"),"Actual pickup and hanging complete"): return
	var hanging := true
	for record in _view.objects.values():
		if record.source_key=="drying_laundry": hanging=hanging and record.style=="hanging" and record.container=="drying_rack"
	expect(_view.represented_quantity("inventory","drying_laundry")==3 and hanging and _view.represented_quantity("inventory","dry_laundry")==0,"Real hanging leaves three wet textiles on the actual rack without declaring them dry")
	_day.advance_time(float(_day.rules.drying_minutes));_view.sync()
	expect(_view.represented_quantity("inventory","dry_laundry")==3 and _view.represented_quantity("inventory","drying_laundry")==0,"Only real elapsed drying produces dry rack contents")
	begin("ryo","fold_laundry")
	if not expect(complete("ryo"),"Actual folding and storage complete"): return
	expect(_view.represented_quantity("inventory","clean_laundry")==9 and _view.represented_quantity("inventory","dry_laundry")==0 and _day.inventory.clean_towels==6,"Folding returns three garments while preserving the six-towel subset and total textile quantity")

func projects_and_cleanup() -> void:
	if not fresh(): return
	begin("ryo","personal_project")
	expect(count_type("project_tools")==0 and count_type("artifact")==0,"Assigning a personal project creates no tools-out state or finished artifact")
	if not arrive("ryo"): return
	work("ryo",1)
	expect(count_type("project_tools")==1 and count_type("artifact")==0,"Actual project work exposes tools while keeping unfinished work distinct from an artifact")
	complete("ryo")
	for ignored in 10:
		if count_type("artifact")>0: break
		begin("ryo","personal_project")
		if not complete("ryo"): break
	expect(count_type("artifact")==1,"Only real accumulated work and completed finish reveal one completed design artifact")
	begin("ryo","tidy_tools")
	if not expect(complete("ryo"),"Actual tool cleanup completes"): return
	expect(count_type("project_tools")==0 and count_type("artifact")==1,"Cleanup stores the tools without erasing or duplicating the completed artifact")
	var logical: Dictionary=_day.snapshot()
	var manifest: Dictionary=_view.manifest()
	_view.sync(0)
	expect(HouseholdDay._same(logical,_day.snapshot()) and manifest==_view.manifest(),"Final source-derived presentation remains read-only and deterministic")

func bath_towel() -> void:
	if not fresh(): return
	_day.people.nagisa.hygiene=.8
	begin("nagisa","bath")
	expect(_view.represented_quantity("job","bath:nagisa")==0,"An unperformed bath intention takes no towel from the clean source")
	if not arrive("nagisa"): return
	work("nagisa",1)
	var batch: Dictionary=_day.batch_location("bath:nagisa")
	var towel: Dictionary=_view.objects["job:bath:nagisa:0"]
	expect(batch.container=="towel_basket" and towel.node.global_position.distance_to(_home.to_global(batch.position))<.00001 and _day.inventory.clean_towels==5,"A real bath preparation uses the physical basket support and transfers exactly one existing clean towel")
	phase("nagisa")
	if not arrive("nagisa"): return
	work("nagisa",1)
	towel=_view.objects["job:bath:nagisa:0"]
	var held: Dictionary=_view.pose_for("nagisa")
	expect(_day.batch_location("bath:nagisa").holder=="nagisa" and towel.container=="" and towel.source_holder=="nagisa" and towel.node.get_parent()==_view.hand_socket("nagisa","R"),"Showering keeps the real towel in its actual holder's hand, without an imaginary shower shelf")
	expect(not held.get("pose_accepted",true) and _view.diagnostics.any(func(row):return row.kind=="bath_towel_pose_not_accepted"),"Hand attachment does not claim an accepted wiping or bathing motion")
	if not expect(complete("nagisa"),"The actual remaining bath and changing phases finish"): return
	var dirty: Array=_view.objects.values().filter(func(record):return record.source_type=="inventory" and record.source_key=="dirty_laundry" and record.textile=="towel")
	expect(dirty.size()==1 and dirty[0].container=="towel_basket" and _view.represented_quantity("inventory","dirty_laundry")==4,"Only completed bathing returns the used towel to the actual basket, as one subset of four dirty textiles")

func run() -> void:
	_plan=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var parsed: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	for record in parsed.residents:
		if record.id in ["nagisa","ryo","rin"]:
			var person: Dictionary=record.duplicate(true);person.routines=[];_authored.append(person)
	_home=LivingHouse.new();root.add_child(_home)
	if not expect(_home.load_plan("res://data/foundation/ogawa-home.json"),"The actual house fixture nodes load"): quit(1);return
	HomeArt.new().add_visuals(_home)
	# Preserve unrelated artwork before the first derived layer is configured.
	for fixture in _home.fixtures.values():
		for node in fixture.node.find_children("*","MeshInstance3D",true,false):
			var material := node.material_override as ShaderMaterial
			if fixture.definition.id in ["linen_storage","washer"] and material!=null and material.shader==Props.LINEN: _fixed_linen.append({"node":node,"visible":node.visible})
			if fixture.definition.id=="rin_storage": _preserved_decor.append({"node":node,"visible":node.visible})
	for name in ["InitialRinDrawing","InitialDesignStudy"]:
		var picture: Node3D=_home.find_child(name,true,false)
		if is_instance_valid(picture): _preserved_decor.append({"node":picture,"visible":picture.visible})
	no_early_food();await carry_cancel_and_resume();meal_and_dishes();textiles();projects_and_cleanup();bath_towel()
	_dispose();_home.free()
	print("Household props source/attachment checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

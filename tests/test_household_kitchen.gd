extends SceneTree

# Controlled physical-state boundaries only. No real rig/skin, navigation or
# motion is exercised or certified by these explicit fixture placements.
const Fixture = preload("res://tests/controlled_kitchen_fixture.gd")
var checks: int=0
var failures: Array[String]=[]
var plan: Dictionary={}
var people: Array=[]

func _initialize() -> void:call_deferred("run")
func expect(value: bool, reason: String) -> bool:
	checks+=1
	if not value:failures.append(reason);push_error(reason)
	return value

func fresh() -> HouseholdDay:
	var day := HouseholdDay.new()
	expect(day.configure(plan,people),"Controlled kitchen metadata and authored residents configure")
	return day

func restore_copy(day: HouseholdDay, label: String) -> HouseholdDay:
	var encoded: Dictionary=JSON.parse_string(JSON.stringify(day.snapshot()))
	var other := fresh()
	expect(other.restore(encoded) and HouseholdDay._same(encoded,other.snapshot()),label+" preserves source frames, unit counts, claims and transfers through JSON")
	return other

func finish_controlled(day: HouseholdDay, actor: String) -> bool:
	var result: Dictionary=Fixture.complete(day,actor)
	return expect(result.status=="completed","Controlled explicit operations complete: "+str(result))

func actual_boundaries() -> void:
	var day := fresh();var ids: Array=day.equipment.keys();ids.sort()
	var basket: String=day.kitchen.role_id("ingredient_carrier")
	var tray: String=day.kitchen.role_id("serving_carrier")
	var rack_frame: Transform3D=day.kitchen.dish_frame(0)
	expect(absf((rack_frame*day.kitchen.plate_support_local(rack_frame)).y-.862)<.00001,"The canonical vertical plate's actual lowest rim meets the real cradle, rather than treating its centre as a support")
	expect(ids.size()==4 and day.equipment[basket].stock_loaded and day.equipment[tray].support_slot=="dining_table:carrier","Both empty carriers already exist before any assigned job; only the authored first ingredient carrier is filled")
	var before: Dictionary=day.snapshot()
	var requested: Dictionary=day.request("nagisa","cook");var task: Dictionary=requested.task
	expect(requested.status=="requested" and day.inventory.ingredients==9 and day.jobs.is_empty(),"A cooking intention neither creates a material batch nor consumes stock")
	var frame: Transform3D=day.equipment[basket].frame
	expect(day.begin_transfer("nagisa",task.id,basket,"prep:carrier").status=="not_ready" and day.equipment[basket].holder.is_empty(),"The closed real drawer prevents a source grasp without creating ownership")
	day.set_position("nagisa",Vector3(.7,0,4.975))
	expect(day.set_access("nagisa",task.id,"fridge:drawer",.5),"A controlled half-pull advances only the actual drawer access state")
	expect(day.equipment[basket].frame.origin.distance_to(frame.origin+Vector3(0,0,.275))<.00001 and day.inventory.ingredients==9,"The same resting basket follows its moving support exactly once without spending stock")
	day=restore_copy(day,"Mid-drawer save")
	Fixture.step(day,"nagisa") # Finish opening, still no holder.
	var begin: Dictionary=Fixture.step(day,"nagisa")
	expect(begin.status=="ready" and day.equipment[basket].holder.is_empty() and day.jobs.is_empty(),"Beginning a transfer reserves the existing source but does not yet grasp or consume it")
	expect(begin.transfer.grasp_only,"Initial pickup explicitly requests grasp/lift only before held material inspection")
	var tx: Dictionary=day.task_for("nagisa").physical.transfer
	before=day.snapshot();var wrong: Transform3D=day.equipment[basket].frame;wrong.origin.x+=.3
	expect(day.commit_grasp("nagisa",task.id,tx.id,wrong).status=="not_ready" and HouseholdDay._same(before,day.snapshot()),"A wrong source frame is rejected without moving or charging anything")
	Fixture.step(day,"nagisa")
	expect(day.jobs.cook.quantity==3 and day.inventory.ingredients==6 and day.equipment[basket].holder=="nagisa" and not day.equipment[basket].stock_loaded,"The first explicit actual-grip boundary transfers exactly the already visible three units into the sole material job")
	before=day.snapshot()
	expect(day.commit_grasp("nagisa",task.id,tx.id,day.equipment[basket].frame).status=="grasped" and HouseholdDay._same(before,day.snapshot()),"Repeating the same grasp cannot debit a second batch")
	day=restore_copy(day,"Held source save")
	var held_frame: Transform3D=day.equipment[basket].frame
	expect(Fixture.phase(day,"nagisa").status=="next_phase","The first controlled source work ends without auto-placing the held basket")
	expect(day.task_for("nagisa").physical.transfer.id==tx.id and day.task_for("nagisa").physical.transfer.state=="grasped" and not day.task_for("nagisa").physical.transfer.grasp_only and day.equipment[basket].frame==held_frame,"Inspection finish keeps the same held transaction and frame; the next phase now authorizes carry/place")
	var same_position: Vector3=day.jobs.cook.position
	day.set_position("nagisa",Vector3(1.4,0,4.8))
	expect(day.jobs.cook.position==same_position,"Body movement alone cannot invent a hand frame or move the canonical held item")
	day.cancel("nagisa",task.id,"controlled actual held interruption")
	day=restore_copy(day,"Cancelled held save")
	expect(day.request("ryo","cook").status=="unavailable","Another adult cannot steal the still-held batch")
	var put: Dictionary=day.request("nagisa","quiet")
	expect(put.task.kind=="put_down" and finish_controlled(day,"nagisa"),"A new intention first explicitly places the actual held carrier on a real support")
	var replacement: Dictionary=day.request("ryo","cook")
	expect(replacement.status=="requested" and replacement.task.started_effects and day.inventory.ingredients==6,"A different adult resumes the existing batch without refilling or recharging it")
	expect(finish_controlled(day,"ryo") and day.inventory.prepared_servings==3 and day.inventory.ingredients==6,"One controlled prepare/pour/stir chain conserves three portions and the remaining six raw stock units")
	var finished_ids: Array=day.equipment.keys();finished_ids.sort()
	expect(day.jobs.is_empty() and finished_ids==ids and day.equipment[basket].holder.is_empty() and day.access["fridge:drawer"]==0,"Completion leaves the same actual equipment and closed drawer in the world")
	day=restore_copy(day,"Completed cooking equipment save")
	var serve: Dictionary=day.request("nagisa","serve")
	if not expect(serve.status=="requested","An adult can now serve the single cooked batch"):return
	for ignored in 100:
		if not day.kitchen._held_plate("nagisa").is_empty():break
		var progress: Dictionary=Fixture.step(day,"nagisa")
		if progress.status in ["invalid","not_ready","unavailable","occupied","waiting_physical"]:expect(false,"Serving fixture stopped: "+str(progress));return
	var plate_id: String=day.kitchen._held_plate("nagisa")
	if not expect(not plate_id.is_empty(),"A real finite empty plate is explicitly grasped before food is placed in it"):return
	expect(day.equipment[day.kitchen.role_id("cooking_tool")].holder=="nagisa" and day.kitchen.object_descriptor(plate_id).hands==["L"],"The left-hand plate and right-hand utensil coexist without conflicting hand ownership")
	day=restore_copy(day,"Bimanual serving save")
	before=day.snapshot();var broken: Dictionary=before.duplicate(true);broken.jobs.serve.plates[0].hands=["R"]
	expect(not day.restore(broken) and HouseholdDay._same(before,day.snapshot()),"Forged overlapping hand claims are rejected atomically")
	expect(day.cancel("nagisa",serve.task.id,"controlled empty-plate interruption").status=="leaving" and not day.task_for("nagisa").is_empty(),"A held plate keeps its original task alive until safe placement")
	day=restore_copy(day,"Pending empty-plate cancellation save")
	for ignored in 20:
		if day.task_for("nagisa").is_empty():break
		Fixture.step(day,"nagisa")
	expect(day.kitchen._held_plate("nagisa").is_empty() and day.inventory.clean_dishes==3,"Cancelling returns the same reserved empty dish to its rack without duplicating clean stock")
	day.request("nagisa","quiet")
	finish_controlled(day,"nagisa") # Return the still-held right-hand tool.
	if not expect(day.request("ryo","serve").status=="requested","A replacement can continue the saved finite plating job"):return
	expect(finish_controlled(day,"ryo") and day.inventory.table_servings==3 and day.inventory.prepared_servings==0 and day.inventory.clean_dishes==3,"Explicit per-unit plating, tray carrying and distribution create exactly three table servings")
	finished_ids=day.equipment.keys();finished_ids.sort()
	expect(finished_ids==ids and day.equipment[tray].support_slot=="dining_table:carrier","The same empty tray remains after its job is deleted")
	day=restore_copy(day,"Final equipment and table save")
	before=day.snapshot()
	expect(day.request("nagisa","cook").status=="unavailable" and day.inventory.ingredients==6 and day.equipment[basket].stock_loaded==false,"The empty returned basket cannot silently refill itself for another cooking job")
	var no_op: Dictionary=day.snapshot();day.next_operation("nagisa","missing");day.kitchen.object_descriptor(tray)
	expect(HouseholdDay._same(no_op,day.snapshot()),"Object and next-operation queries are pure")

func finite_ingredient_transfers() -> void:
	var day := fresh();var first: Dictionary=day.request("nagisa","cook").task
	if not expect(Fixture.phase(day,"nagisa").status=="next_phase","Controlled source pickup reaches the actual finite-food preparation phase"):return
	for ignored in 15:
		var next: Dictionary=day.next_operation("nagisa",first.id)
		if next.get("kind")=="transfer" and next.get("object",{}).get("kind")=="ingredient":break
		Fixture.step(day,"nagisa")
	var job: Dictionary=day.jobs.cook;var ids: Array=[]
	for unit in job.units:ids.append(unit.id)
	expect(job.units.size()==int(job.quantity) and ids.size()==3 and job.units.map(func(unit):return unit.ingredient_kind)==["carrot","potato","cabbage"],"Exactly three authored food roots describe the single three-unit material batch")
	var knife_id: String=day.kitchen.role_id("preparation_tool")
	var knife: Dictionary=day.equipment[knife_id]
	var description: Dictionary=day.transfer_descriptor("nagisa",first.id,knife_id,knife.home_slot)
	day.set_position("nagisa",description.source.approach)
	var began: Dictionary=day.begin_transfer("nagisa",first.id,knife_id,knife.home_slot)
	day.commit_grasp("nagisa",first.id,began.transfer.id,knife.frame)
	day.set_position("nagisa",day.kitchen.slot("prep:work").approach)
	expect(not day.set_physical_work("nagisa",first.id,true) and job.units.all(func(unit):return unit.state=="basket"),"Even actually holding the knife cannot score food that is still inside the parked carrier")
	day.set_position("nagisa",description.target.approach);day.update_held_frame("nagisa",first.id,knife_id,description.target.object_frame)
	day.commit_release("nagisa",first.id,began.transfer.id,description.target.object_frame)
	var original: Array=[]
	for unit in job.units:original.append(unit.frame)
	Fixture.step(day,"nagisa") # Reserve one ingredient, not the whole batch.
	expect(job.units.all(func(unit):return unit.holder.is_empty()) and job.material_slot.begins_with("equipment:"),"A finite ingredient intention leaves all food on its actual support")
	Fixture.step(day,"nagisa") # Grasp the selected right-hand ingredient.
	expect(job.units[0].holder=="nagisa" and job.units[0].frame==original[0] and job.units[1].frame==original[1] and job.units[2].frame==original[2] and job.material_slot=="mixed:units","Grasp changes ownership of one existing food root without moving its siblings or the whole material batch")
	expect(day.cancel("nagisa",first.id,"controlled single-food interruption").status=="leaving","A held finite food keeps the original task until safe return")
	day=restore_copy(day,"Pending ingredient cancellation save")
	for ignored in 12:
		if day.task_for("nagisa").is_empty():break
		Fixture.step(day,"nagisa")
	expect(day.kitchen._held_ingredient("nagisa").is_empty() and day.jobs.cook.units.all(func(unit):return unit.state=="basket") and day.inventory.ingredients==6,"Cancellation returns the same food to the actual basket without returning or duplicating stock")
	var resumed: Dictionary=day.request("ryo","cook")
	if not expect(resumed.status=="requested" and Fixture.phase(day,"ryo").status=="next_phase","A replacement explicitly moves every food to the board, scores it, and returns each food"):return
	job=day.jobs.cook
	expect(job.units.map(func(unit):return unit.id)==ids and job.units.all(func(unit):return unit.state=="basket" and unit.food_state=="scored") and job.material_stage=="cut","Connected score geometry retains the same three food identities and uses no disconnected group carrying")
	var saved: Dictionary=day.snapshot();var broken: Dictionary=saved.duplicate(true)
	broken.jobs.cook.units.pop_back()
	expect(not day.restore(broken) and HouseholdDay._same(saved,day.snapshot()),"A missing material unit is atomically rejected against job.quantity")
	broken=saved.duplicate(true);broken.jobs.cook.units[1].id=broken.jobs.cook.units[0].id
	expect(not day.restore(broken) and HouseholdDay._same(saved,day.snapshot()),"A duplicate food identity cannot enter a restored material batch")
	broken=saved.duplicate(true);broken.jobs.cook.units[0].food_state="cut"
	expect(not day.restore(broken) and HouseholdDay._same(saved,day.snapshot()),"Disconnected cut-piece carrying cannot be forged into the first connected-score recipe")
	for ignored in 15:
		var next: Dictionary=day.next_operation("ryo",resumed.task.id)
		if next.get("kind")=="recipe" and next.get("operation")=="pour":break
		Fixture.step(day,"ryo")
	var pour: Dictionary=day.next_operation("ryo",resumed.task.id)
	if not expect(pour.get("operation")=="pour" and pour.unit_index==0,"Pouring addresses one finite food and its actual pan support"):return
	day.set_position("ryo",pour.target.approach)
	var basket_frame := Transform3D(Basis(Vector3.RIGHT,-PI/3),Vector3.ZERO)
	basket_frame.origin=pour.container_target.frame.origin-basket_frame.basis*Vector3(0,.23,-.155)
	day.update_held_frame("ryo",resumed.task.id,pour.carrier_id,basket_frame)
	var start: Transform3D=day.jobs.cook.units[0].frame
	saved=day.snapshot()
	expect(day.commit_recipe_step("ryo",resumed.task.id,"pour",pour.target.object_frame,0).status=="not_ready" and HouseholdDay._same(saved,day.snapshot()),"A recipe commit cannot pop food from the carrier into the pan")
	expect(day.update_pour_unit("ryo",resumed.task.id,0,start,0),"The real trajectory starts at the food's existing frame")
	var half: Transform3D=start.interpolate_with(pour.target.object_frame,.5)
	expect(day.update_pour_unit("ryo",resumed.task.id,0,half,.5) and day.jobs.cook.units[0].frame==half and day.jobs.cook.units[1].state=="basket","A partial pour stores one actual food trajectory and leaves other material attached to its carrier")
	saved=day.snapshot()
	expect(day.commit_recipe_step("ryo",resumed.task.id,"pour",half,0).status=="not_ready" and HouseholdDay._same(saved,day.snapshot()),"A still-falling food cannot be recorded as already supported in the pan")
	day=restore_copy(day,"Mid-food-trajectory JSON save")
	expect(day.cancel("ryo",resumed.task.id,"controlled mid-pour interruption").status=="leaving","An airborne food must settle before cancellation releases the original action")
	day=restore_copy(day,"Pending mid-pour cancellation JSON save")
	Fixture.step(day,"ryo")
	expect(day.task_for("ryo").is_empty() and day.jobs.cook.units[0].state=="pan" and day.jobs.cook.units[1].state=="basket" and day.jobs.cook.quantity==3,"Safe cancellation finishes only the already-detached trajectory and preserves the other two foods")
	day.request("ryo","quiet");finish_controlled(day,"ryo")
	if not expect(day.request("nagisa","cook").status=="requested","The partial pan/carrier batch remains resumable by another adult"):return
	expect(finish_controlled(day,"nagisa") and day.inventory.ingredients==6 and day.inventory.prepared_servings==3,"Partial pour, save, safe cancellation and handoff still finish exactly one three-serving recipe")

func distribution_contact_goal() -> void:
	var day := fresh()
	if not expect(day.request("nagisa","cook").status=="requested" and finish_controlled(day,"nagisa"),"Controlled setup creates one finite cooked batch"):return
	var request: Dictionary=day.request("nagisa","serve")
	if not expect(request.status=="requested" and Fixture.phase(day,"nagisa").status=="next_phase","Controlled plating reaches distribution with the same three actual plates"):return
	for ignored in 100:
		var operation: Dictionary=day.next_operation("nagisa",request.task.id)
		if operation.get("kind")=="finish":break
		var reply: Dictionary=Fixture.step(day,"nagisa")
		if reply.status in ["invalid","not_ready","unavailable","occupied","waiting_physical"]:expect(false,"Controlled contact goal blocked: "+str(reply));return
	var task: Dictionary=day.task_for("nagisa")
	var before: Dictionary=day.people.nagisa.duplicate(true)
	var elapsed: float=day.elapsed
	var performed: float=task.performed
	expect(day.jobs.serve.served_units==day.jobs.serve.quantity and task.phase_progress==0,"Distribution is complete from the three explicit supported release boundaries, without idle distribution work")
	expect(day.finish("nagisa",request.task.id).status=="completed" and day.elapsed==elapsed,"The last actual plate finishes the goal without waiting for another three minutes")
	expect(day.tasks[request.task.id].performed==performed and day.people.nagisa.actual_minutes==before.actual_minutes,"Contact completion grants no fictitious performed time")
	var needs_unchanged := true
	for need in HouseholdDay.NEEDS:needs_unchanged=needs_unchanged and day.people.nagisa[need]==before[need]
	expect(needs_unchanged,"Contact completion grants no idle need changes")
	restore_copy(day,"Contact-completed distribution JSON save")

func run() -> void:
	# Use the canonical authored house/equipment here; only body placement and
	# contact commits are controlled. No alternative kitchen layout is injected.
	plan=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	for person in source.residents:
		if person.id in ["nagisa","ryo","rin"]:
			var authored: Dictionary=person.duplicate(true);authored.routines=[];people.append(authored)
	actual_boundaries();finite_ingredient_transfers();distribution_contact_goal()
	print("Controlled kitchen state checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

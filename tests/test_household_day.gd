extends SceneTree

# Controlled state/action executor fixtures. Positions are explicitly placed at
# use points here; these tests do not demonstrate real 3D arrival or a lived day.
var checks: int = 0
var failures: Array[String] = []
var home_plan: Dictionary
var authored: Array = []

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> bool:
	checks+=1
	if not ok: failures.append(message);push_error(message)
	return ok

func fresh() -> HouseholdDay:
	var day := HouseholdDay.new()
	expect(day.configure(home_plan,authored),"The controlled home and three authored people configure")
	return day

func begin(day: HouseholdDay, actor: String, kind: String) -> Dictionary:
	var response: Dictionary = day.request(actor,kind)
	expect(response.status=="requested",actor+" can request "+kind+": "+response.reason)
	return response.task

func located(day: HouseholdDay, actor: String) -> bool:
	var task: Dictionary = day.task_for(actor)
	if task.is_empty(): return false
	day.set_position(actor,task.target)
	return expect(day.arrive(actor,task.id).status in ["arrived","phase_ready"],"Only reaching the controlled use point admits "+task.kind)

func phase(day: HouseholdDay, actor: String) -> Dictionary:
	if day.task_for(actor).is_empty(): return {}
	if day.task_for(actor).status not in ["arrived","working","phase_ready"] and not located(day,actor): return {}
	var task: Dictionary = day.task_for(actor)
	if task.status!="phase_ready":
		var remaining: float = float(task.phase_minutes)-float(task.phase_progress)
		day.advance_time(remaining)
		var response: Dictionary = day.perform(actor,task.id,remaining)
		if not expect(response.status=="phase_ready","Actual elapsed work completes only the current "+task.phase_name+" phase"): return response
	return day.finish(actor,task.id)

func complete(day: HouseholdDay, actor: String) -> bool:
	for ignored in 10:
		var result: Dictionary = phase(day,actor)
		if result.is_empty(): return false
		if result.status=="completed": return true
	return false

func intention_and_clock() -> void:
	var day: HouseholdDay = fresh()
	var before: Dictionary = day.snapshot()
	day.candidates("nagisa");day.candidates("ryo")
	expect(HouseholdDay._same(before,day.snapshot()),"Repeated candidate inspection changes no need, inventory, task, money or time")
	var task: Dictionary = begin(day,"nagisa","cook")
	expect(day.inventory.ingredients==9 and day.person("nagisa").hunger==.45,"Assignment creates only an intention, without ingredient consumption or relief")
	expect(day.perform("nagisa",task.id,20).status=="not_ready","Work cannot be performed before arrival")
	expect(day.arrive("nagisa",task.id).status=="not_arrived","Arrival cannot be asserted from the bedroom while the target is the refrigerator")
	if not located(day,"nagisa"): return
	var arrived: Dictionary = day.snapshot()
	expect(day.perform("nagisa",task.id,1).status=="waiting_for_time" and HouseholdDay._same(arrived,day.snapshot()),"Arrival alone and duplicate same-clock work grant no elapsed credit")
	day.advance_time(1)
	var hunger_before: float = float(day.person("nagisa").hunger)
	expect(day.perform("nagisa",task.id,100).task.phase_progress==1 and day.inventory.ingredients==6,"A large caller delta is capped by actual elapsed time; ingredients are consumed once on real work")
	var performed: Dictionary = day.snapshot()
	day.perform("nagisa",task.id,1)
	expect(HouseholdDay._same(performed,day.snapshot()) and day.person("nagisa").hunger==hunger_before,"Repeating work at the same time neither consumes twice nor relieves hunger while cooking")
	expect(day.finish("nagisa",task.id).status=="not_ready" and day.inventory.prepared_servings==0,"An incomplete phase cannot report food or completion")

func meal_chain() -> void:
	var day: HouseholdDay = fresh()
	expect(day.request("rin","cook").status=="unavailable","A seven-year-old is not assigned hot cooking")
	var cook: Dictionary = begin(day,"nagisa","cook")
	if cook.is_empty(): return
	expect(phase(day,"nagisa").status=="next_phase" and day.inventory.prepared_servings==0,"Taking ingredients does not already create prepared food")
	expect(day.task_for("nagisa").fixture=="prep" and day.perform("nagisa",cook.id,6).status=="not_ready","The next cooking phase requires a separate actual arrival")
	if not expect(complete(day,"nagisa"),"All ingredient, prep and heat phases physically complete in the controlled executor"): return
	expect(day.inventory.ingredients==6 and day.inventory.prepared_servings==3 and day.inventory.table_servings==0,"Cooking creates exactly three prepared servings and no food on the table")
	var finished: Dictionary = day.snapshot();day.finish("nagisa",cook.id)
	expect(HouseholdDay._same(finished,day.snapshot()),"Repeating an old completion cannot duplicate food or result records")
	var serve: Dictionary = begin(day,"ryo","serve")
	if not expect(complete(day,"ryo"),"Serving actually carries the prepared batch to the table"): return
	expect(day.inventory.prepared_servings==0 and day.inventory.table_servings==3 and day.inventory.clean_dishes==3,"Serving transfers a finite batch and reserves exactly its dishes")
	var eat: Dictionary = begin(day,"rin","eat")
	if eat.is_empty() or not located(day,"rin"): return
	var hungry: float = float(day.person("rin").hunger)
	day.advance_time(4);day.perform("rin",eat.id,4)
	expect(day.person("rin").hunger<hungry and day.inventory.table_servings==2 and day.inventory.dirty_dishes==0,"Real eating time reduces hunger and consumes one serving; the unfinished plate remains in use")
	day.cancel("rin",eat.id,"先にトイレへ行く")
	var after_cancel: Dictionary = day.snapshot()
	expect(day.request("rin","eat").status=="requested" and day.task_for("rin").phase_progress==4 and day.inventory.table_servings==2,"The same person's unfinished meal resumes without consuming another serving")
	if not expect(complete(day,"rin"),"The resumed meal actually finishes"): return
	expect(day.inventory.dirty_dishes==1 and day.inventory.table_servings==2,"Only finishing the actual meal creates one dirty dish")
	begin(day,"ryo","wash_dishes")
	if not expect(complete(day,"ryo"),"Washing the actual dirty dish finishes"): return
	expect(day.inventory.dirty_dishes==0 and day.inventory.clean_dishes==4,"Washing returns only the one consumed dirty dish to clean inventory")

func save_and_handoff() -> void:
	var day: HouseholdDay = fresh()
	var first: Dictionary = begin(day,"nagisa","cook")
	if first.is_empty() or not located(day,"nagisa"): return
	day.advance_time(1);day.perform("nagisa",first.id,1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(day.snapshot()))
	var restored: HouseholdDay = fresh()
	if not expect(restored.restore(saved) and HouseholdDay._same(restored.snapshot(),saved),"The complete current-format controller restores exact intermediate needs, resources, phase, clock and reservations"): return
	day.advance_time(1);day.perform("nagisa",first.id,1)
	restored.advance_time(1);restored.perform("nagisa",first.id,1)
	expect(HouseholdDay._same(day.snapshot(),restored.snapshot()),"A restored cooking phase evolves identically under the same actual-time inputs")
	day.cancel("nagisa",first.id,"勤務のため交代する")
	var second: Dictionary = begin(day,"ryo","cook")
	if not expect(not second.is_empty() and second.started_effects and day.inventory.ingredients==6,"A different adult takes the existing batch without a second ingredient debit"): return
	if not expect(complete(day,"ryo"),"The replacement adult finishes the actual remaining phases"): return
	expect(day.inventory.prepared_servings==3 and day.inventory.ingredients==6,"Cancelled and resumed cooking still produces exactly one batch")
	var before: Dictionary = day.snapshot()
	for bad in ["people","tasks","jobs","inventory"]:
		var corrupt: Dictionary = before.duplicate(true);corrupt[bad]=[]
		expect(not day.restore(corrupt) and HouseholdDay._same(before,day.snapshot()),"Malformed "+bad+" is rejected atomically")
	var corrupt: Dictionary = before.duplicate(true);corrupt.people.rin.bladder=NAN
	expect(not day.restore(corrupt) and HouseholdDay._same(before,day.snapshot()),"Nonfinite physiology cannot enter a restored home")
	corrupt=before.duplicate(true);corrupt.inventory.ingredients=-1
	expect(not day.restore(corrupt) and HouseholdDay._same(before,day.snapshot()),"Negative household supplies cannot enter a restored home")

func conditions_and_hygiene() -> void:
	var day: HouseholdDay = fresh()
	day.set_stock("ingredients",0)
	var options: Array = day.candidates("nagisa")
	expect(options.any(func(row):return row.kind=="cook" and row.status=="unavailable" and "食材" in row.reason) and options.any(func(row):return row.kind=="shop" and row.status=="ready"),"Missing ingredients change available actions to buying supplies rather than fabricating a meal")
	var shop: Dictionary = begin(day,"nagisa","shop")
	if shop.is_empty() or not located(day,"nagisa"): return
	var cash: float = day.cash
	day.advance_time(1);day.perform("nagisa",shop.id,1)
	expect(day.cash==cash-6 and day.inventory.ingredients==0,"An actual purchase spends once but ingredients are not in the refrigerator yet")
	if not expect(complete(day,"nagisa"),"Shopping finishes only after the purchased food is brought back and stored"): return
	expect(day.inventory.ingredients==6 and day.person("nagisa").at_home,"Stored purchases enter household stock only on real return")
	day.person("nagisa").hygiene=.8;day.person("ryo").hygiene=.8
	var bath: Dictionary = begin(day,"nagisa","bath")
	if bath.is_empty(): return
	phase(day,"nagisa")
	if not located(day,"nagisa"): return
	var queue: Array = day.candidates("ryo")
	expect(queue.any(func(row):return row.kind=="bath" and row.status=="ready"),"Changing and the shower are separate stages before the second person reaches their exclusive service room")
	var other: Dictionary = begin(day,"ryo","bath")
	if not other.is_empty():
		located(day,"ryo");day.advance_time(2);day.perform("ryo",other.id,2);day.finish("ryo",other.id)
		day.set_position("ryo",day.task_for("ryo").target)
		expect(day.arrive("ryo",other.id).status=="occupied","An occupied shower/bath room queues the other person without stealing the first claim")
		day.cancel("ryo",other.id,"先に別のことをする")
	var hygiene: float = day.person("nagisa").hygiene
	if not expect(complete(day,"nagisa"),"The first bather performs wash, soak and changing phases"): return
	expect(day.person("nagisa").hygiene<hygiene and day.inventory.dirty_towels==1,"Only actual washing restores hygiene; the used towel becomes real dirty laundry")
	day.person("rin").bladder=.9
	var toilet: Dictionary = begin(day,"rin","toilet")
	if not expect(complete(day,"rin"),"A controlled actual toilet use finishes"): return
	expect(day.person("rin").bladder<.1,"Actual toilet time relieves bladder pressure")

func sleep_care_and_routines() -> void:
	var ordinary := HouseholdDay.new();expect(ordinary.configure(home_plan),"The normal authored household configures without rewriting shifts")
	expect(ordinary.start_minute==240 and ordinary.candidates("ryo")[0].kind=="sleep", "At 04:00 the authored sleeping parent remains asleep while the early worker can wake")
	var day: HouseholdDay = fresh();day.person("ryo").fatigue=.9
	var bed: Dictionary = begin(day,"ryo","sleep")
	if bed.is_empty() or not located(day,"ryo"): return
	var tired: float = day.person("ryo").fatigue
	day.advance_time(10)
	expect(day.person("ryo").fatigue>=tired,"Being assigned or present at a bed does not itself restore fatigue")
	day.perform("ryo",bed.id,10)
	expect(day.person("ryo").fatigue<tired,"Only performed sleep time at the bed restores fatigue")
	day.cancel("ryo",bed.id)
	var care: Dictionary = begin(day,"ryo","care")
	if care.is_empty() or not located(day,"ryo"): return
	day.advance_time(5)
	var before: Dictionary = day.snapshot()
	expect(day.perform("ryo",care.id,5).status=="waiting_for_partner" and day.person("ryo").actual_minutes.get("care",0)==0,"A parent alone on the sofa earns no care time or shared experience")
	var child: Dictionary = begin(day,"rin","family_time")
	if child.is_empty() or not located(day,"rin"): return
	day.advance_time(1)
	expect(day.perform("ryo",care.id,1).status=="working" and day.perform("rin",child.id,1).status=="working", "The child independently accepts and both actually share time only after reaching distinct nearby sofa slots")
	day.cancel("ryo",care.id,"子どもが先に食事へ行く")
	day.advance_time(1)
	expect(day.perform("rin",child.id,1).status=="waiting_for_partner","Withdrawing the shared care activity immediately stops the child's shared-time effects")
	var outside: HouseholdDay = fresh()
	outside.person("nagisa").at_home=false;outside.set_position("nagisa",Vector3(6.5,0,11.25));outside.set_return_after("nagisa",90)
	expect(outside.request("nagisa").task.kind=="wait_outside","A late-home condition delays return without teleporting or granting a home activity")
	outside.advance_time(91);outside.cancel("nagisa",outside.person("nagisa").active_task)
	expect(outside.request("nagisa").task.kind=="return_home","When the external delay ends, actual return becomes the next intention")

func laundry_and_real_responsibilities() -> void:
	var day: HouseholdDay = fresh()
	# A controlled drying-rack fixture supplies the prerequisite absent from
	# the original design. This does not claim a rendered rack was tested.
	var extended: Dictionary = home_plan.duplicate(true)
	extended.fixtures.append({"id":"test_drying_rack","type":"drying_rack","room":"ldk","interaction_point":[1.0,0,8.5],"capacity":1})
	expect(day.configure(extended,authored),"The laundry fixture explicitly includes a real drying-place prerequisite")
	day.inventory.dirty_laundry=1;day.inventory.dirty_towels=1;day.inventory.clean_laundry=5;day.inventory.clean_towels=5
	begin(day,"ryo","laundry")
	if not expect(complete(day,"ryo"),"Actual loading starts a finite washing-machine cycle"): return
	expect(day.inventory.dirty_laundry==0 and day.inventory.washing_laundry==1 and day.inventory.wet_laundry==0,"Loading alone does not already produce washed or dry linen")
	var actual_minutes: float = float(day.person("ryo").actual_minutes.laundry)
	day.advance_time(45)
	expect(day.inventory.wet_laundry==1 and day.inventory.wet_towels==1 and day.person("ryo").actual_minutes.laundry==actual_minutes,"Only the started machine completes automatically, retaining towel subtype and granting no unattended human work minutes")
	begin(day,"ryo","hang_laundry")
	if not expect(complete(day,"ryo"),"Wet linen is actually retrieved and placed at the drying rack"): return
	expect(day.inventory.drying_laundry==1 and day.inventory.dry_laundry==0,"Hanging wet linen does not pretend it is already dry")
	day.advance_time(180)
	begin(day,"ryo","fold_laundry")
	if not expect(complete(day,"ryo"),"Only dry linen can be folded and stored"): return
	expect(day.inventory.clean_laundry==6 and day.inventory.clean_towels==6 and day.inventory.dry_laundry==0,"The same washed towel returns to clean supply without appearing twice or losing its type")
	day=fresh()
	day.person("ryo").routines=[{"id":"remote_work","place":"home","on_days":[0],"start_minute":240,"duration_minutes":60}]
	var work: Dictionary = begin(day,"ryo","work")
	if work.is_empty() or not located(day,"ryo"): return
	day.advance_time(5);day.perform("ryo",work.id,5)
	expect(is_equal_approx(day.person("ryo").earned,.175) and day.person("ryo").actual_minutes.work==5 and day.finish("ryo",work.id).status=="not_ready","A real five-minute desk-work interval earns only five minutes and cannot claim a complete shift")
	day.person("rin").routines=[{"id":"school","place":"off_map_school","on_days":[0],"start_minute":240,"duration_minutes":60}]
	var school: Dictionary = begin(day,"rin","school")
	expect(not school.is_empty() and day.person("rin").at_home,"A school intention alone does not move a child outside")
	if school.is_empty() or not located(day,"rin"): return
	day.advance_time(5);day.perform("rin",school.id,5)
	expect(not day.person("rin").at_home and day.person("rin").actual_minutes.school==5,"Only arrival at the explicit offsite boundary allows abstract school time to count")
	var alternate: HouseholdDay = fresh()
	alternate.person("nagisa").at_home=false;alternate.set_return_after("nagisa",120)
	expect(alternate.request("ryo").task.kind=="cook","The available adult can choose cooking when the other adult is late, without assigning the role by person ID")

func urgent_selection_and_wait_timeout() -> void:
	var day: HouseholdDay = fresh()
	day.inventory.table_servings=2;day.person("rin").hunger=.99;day.person("rin").bladder=.99
	var toilet: Dictionary = day.request("rin").task
	if not expect(not toilet.is_empty() and toilet.kind=="toilet","When both needs are acute, the child chooses a currently feasible highest-priority action"): return
	if not located(day,"rin"): return
	for ignored in 4:
		day.advance_time(1);day.perform("rin",toilet.id,1)
		var selected: Dictionary = day.request("rin").task
		expect(selected.get("id","")==toilet.id and day.serial==1,"Concurrent hunger cannot cancel and recreate the same active toilet action")
	day.advance_time(1);day.perform("rin",toilet.id,1);day.finish("rin",toilet.id)
	expect(day.request("rin").task.kind=="eat","After actual relief, the other acute need becomes the next action")
	day=fresh()
	var care: Dictionary = begin(day,"ryo","care")
	if care.is_empty() or not located(day,"ryo"): return
	day.advance_time(1);day.perform("ryo",care.id,1)
	day.advance_time(31)
	var changed: Dictionary = day.request("ryo")
	expect(day.tasks[care.id].status=="cancelled" and changed.task.get("kind","")!="care" and day.person("ryo").actual_minutes.get("care",0)==0,"An unanswered care invitation expires into another feasible activity, without fictional shared minutes or immediate reinvitation")

func run() -> void:
	home_plan=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	for p in source.residents:
		if p.id not in ["nagisa","ryo","rin"]: continue
		var copy: Dictionary = p.duplicate(true);copy.routines=[];authored.append(copy)
	intention_and_clock();meal_chain();save_and_handoff();conditions_and_hygiene();sleep_care_and_routines();laundry_and_real_responsibilities();urgent_selection_and_wait_timeout()
	print("Household day checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

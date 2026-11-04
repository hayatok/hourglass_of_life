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
	var arrival: Dictionary = day.arrive(actor,task.id)
	if not expect(arrival.status in ["arrived","phase_ready","entering"],"Only reaching the controlled approach admits "+task.kind): return false
	if arrival.status!="entering": return true
	var region: Dictionary = day._usage_regions[task.fixture]
	var anchor: Vector3 = day._point(region.center)
	if day._fixtures[task.fixture].type=="sofa": anchor.x=clampf(task.target.x,anchor.x-float(region.half_extents[0]),anchor.x+float(region.half_extents[0]))
	# Explicitly placed body/posture fixture. This is not a seat-entry motion test.
	day.set_position(actor,anchor)
	return expect(day.begin_use(actor,task.id,anchor,region.postures[0]).status in ["arrived","phase_ready"],"The controlled actual body/posture enters the authored usage region")

func finish_phase(day: HouseholdDay, actor: String, task_id: String) -> Dictionary:
	var response: Dictionary = day.finish(actor,task_id)
	if response.status!="leaving": return response
	day.set_position(actor,response.task.target)
	var ended: Dictionary = day.end_use(actor,task_id,response.task.target)
	if not expect(ended.status=="phase_ready","The controlled body exits to the actual walkable approach before finish"): return ended
	return day.finish(actor,task_id)

func stop(day: HouseholdDay, actor: String, task_id: String, reason: String = "本人の予定が変わった") -> Dictionary:
	var response: Dictionary = day.cancel(actor,task_id,reason)
	if response.status!="leaving": return response
	day.set_position(actor,response.task.target)
	return day.end_use(actor,task_id,response.task.target)

func phase(day: HouseholdDay, actor: String) -> Dictionary:
	if day.task_for(actor).is_empty(): return {}
	if day.task_for(actor).status not in ["arrived","working","phase_ready"] and not located(day,actor): return {}
	var task: Dictionary = day.task_for(actor)
	if task.status!="phase_ready":
		var remaining: float = float(task.phase_minutes)-float(task.phase_progress)
		day.advance_time(remaining)
		var response: Dictionary = day.perform(actor,task.id,remaining)
		if not expect(response.status=="phase_ready","Actual elapsed work completes only the current "+task.phase_name+" phase"): return response
	return finish_phase(day,actor,task.id)

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
	stop(day,"rin",eat.id,"先にトイレへ行く")
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
	stop(day,"nagisa",first.id,"勤務のため交代する")
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
		stop(day,"ryo",other.id,"先に別のことをする")
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
	stop(day,"ryo",bed.id)
	var care: Dictionary = begin(day,"ryo","care")
	if care.is_empty() or not located(day,"ryo"): return
	day.advance_time(5)
	var before: Dictionary = day.snapshot()
	expect(day.perform("ryo",care.id,5).status=="waiting_for_partner" and day.person("ryo").actual_minutes.get("care",0)==0,"A parent alone on the sofa earns no care time or shared experience")
	var child: Dictionary = begin(day,"rin","family_time")
	if child.is_empty() or not located(day,"rin"): return
	day.advance_time(1)
	expect(day.perform("ryo",care.id,1).status=="working" and day.perform("rin",child.id,1).status=="working", "The child independently accepts and both actually share time only after reaching distinct nearby sofa slots")
	stop(day,"ryo",care.id,"子どもが先に食事へ行く")
	day.advance_time(1)
	expect(day.perform("rin",child.id,1).status=="waiting_for_partner","Withdrawing the shared care activity immediately stops the child's shared-time effects")
	var outside: HouseholdDay = fresh()
	outside.person("nagisa").at_home=false;outside.set_position("nagisa",Vector3(6.5,0,11.25));outside.set_return_after("nagisa",90)
	expect(outside.request("nagisa").task.kind=="wait_outside","A late-home condition delays return without teleporting or granting a home activity")
	outside.advance_time(91);stop(outside,"nagisa",outside.person("nagisa").active_task)
	expect(outside.request("nagisa").task.kind=="return_home","When the external delay ends, actual return becomes the next intention")

func laundry_and_real_responsibilities() -> void:
	var day: HouseholdDay = fresh()
	# A controlled drying-rack fixture supplies the prerequisite absent from
	# the original design. This does not claim a rendered rack was tested.
	var extended: Dictionary = home_plan.duplicate(true)
	extended.fixtures.append({"id":"test_drying_rack","type":"drying_rack","room":"ldk","interaction_point":[1.0,0,8.5],"support_point":[1.0,0,8.5],"put_down_kinds":["laundry","hang_laundry","fold_laundry"],"capacity":1})
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
	if changed.status=="leaving":
		day.set_position("ryo",changed.task.target);day.end_use("ryo",care.id,changed.task.target);changed=day.request("ryo")
	expect(day.tasks[care.id].status=="cancelled" and changed.task.get("kind","")!="care" and day.person("ryo").actual_minutes.get("care",0)==0,"An unanswered care invitation expires into another feasible activity, without fictional shared minutes or immediate reinvitation")

func background_projects_and_decisions() -> void:
	var day: HouseholdDay = fresh()
	expect(day.person("nagisa").history.minutes.is_empty() and day.person("nagisa").life_history.observed.is_empty(),"Authored family episodes do not masquerade as minutes performed in the current day")
	var before: Dictionary = day.snapshot()
	day.candidates("rin");day.candidates("ryo")
	expect(HouseholdDay._same(before,day.snapshot()),"Biography-sensitive candidate queries remain completely pure")
	var project: Dictionary = begin(day,"rin","personal_project")
	expect(project.activity=="town_model" and project.project_id=="town_model" and not project.choice_reason.is_empty(),"The common task carries the actual personal activity, project and human-readable reason")
	expect(not day.person("rin").life_history.tools_out and day.person("rin").life_history.projects.town_model.minutes==0,"Assignment alone neither lays out tools nor advances the child's model")
	if not located(day,"rin"): return
	day.advance_time(5);day.perform("rin",project.id,5)
	expect(day.person("rin").life_history.tools_out and day.person("rin").life_history.projects.town_model.minutes==5 and day.person("rin").life_history.projects.town_model.artifact.is_empty(),"Only actual work at the desk produces practice and a real unfinished project")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(day.snapshot()))
	var restored: HouseholdDay = fresh()
	expect(restored.restore(saved) and HouseholdDay._same(saved,restored.snapshot()),"An unfinished personal project and its tool location restore atomically with the executor")
	day.advance_time(10);day.perform("rin",project.id,10);finish_phase(day,"rin",project.id)
	restored.advance_time(10);restored.perform("rin",project.id,10);finish_phase(restored,"rin",project.id)
	expect(HouseholdDay._same(day.snapshot(),restored.snapshot()),"The same post-load actual work produces identical project credit and observed history")
	for ignored in 3:
		begin(day,"rin","personal_project")
		if not expect(complete(day,"rin"),"The model grows only through repeated actual use of its desk"): return
	var progress: Dictionary = day.person("rin").life_history.projects.town_model
	expect(progress.completed and progress.minutes==60 and progress.artifact.owner=="rin","The child's own finished model appears only after sixty actual minutes and the final finish")
	begin(day,"rin","tidy_tools")
	if not expect(complete(day,"rin"),"The child can actually tidy the tools used for this project"): return
	expect(not day.person("rin").life_history.tools_out and progress.fixture=="rin_desk","Tidying stores the same personal project rather than making another model")
	var corrupt: Dictionary = day.snapshot();corrupt.people.rin.life_history.projects.town_model.artifact.owner="ryo"
	before=day.snapshot()
	expect(not day.restore(corrupt) and HouseholdDay._same(before,day.snapshot()),"A forged project owner is rejected without partially changing the day")
	day=fresh()
	expect(day.set_commitment_deadline("ryo","client_delivery",30),"A deadline scenario changes a declared commitment without granting work")
	var work: Dictionary = day.request("ryo").task
	expect(work.kind=="personal_project" and work.activity=="design_draft" and "締切" in work.choice_reason,"With the same needs a close deadline changes the available parent's choice toward the real draft")
	expect(day.request("nagisa").task.kind=="cook","The other adult picks up feasible meal preparation when the deadline holder chooses the draft")
	day=fresh()
	var care: Dictionary = begin(day,"ryo","care")
	var own: Dictionary = day.request("rin").task
	expect(own.kind=="personal_project" and day.person("rin").life_history.observed[0].status=="declined_family_invitation","A child with the same needs can actually decline an invitation to try an authored independent idea")
	expect(day.person("rin").actual_minutes.is_empty() and day.person("rin").life_history.projects.town_model.minutes==0,"The refusal and new intention grant no care or creative practice")
	day.request("ryo")
	expect(day.tasks[care.id].status=="cancelled" and day.person("ryo").actual_minutes.get("care",0)==0,"A declined invitation lets the parent choose again without fictional shared time or endless waiting")

func batch_transport_and_safe_handoff() -> void:
	var day: HouseholdDay = fresh()
	var cook: Dictionary = begin(day,"nagisa","cook")
	if cook.is_empty() or not expect(phase(day,"nagisa").status=="next_phase","Finishing actual refrigerator pickup begins transport"): return
	var batch: Dictionary = day.batch_location("cook")
	var identity: String = batch.batch_id
	expect(batch.holder=="nagisa" and batch.container.is_empty() and batch.last_fixture=="fridge" and day.inventory.ingredients==6,"A single debited batch is held, and remembers its last actual fixture")
	day.set_position("nagisa",Vector3(1.5,0,4.95))
	var moving: Dictionary = day.batch_location("cook")
	expect(moving.position==day.person("nagisa").position+Vector3(0,1,0) and moving.last_fixture=="fridge" and moving.position!=day._surface_position("prep"),"Movement follows the real holder and never changes to the unvisited preparation fixture")
	var before: Dictionary = day.snapshot();day.batch_locations();day.batch_location("cook")
	expect(HouseholdDay._same(before,day.snapshot()),"Batch inspection is pure and returns copies")
	stop(day,"nagisa",cook.id,"途中で用事ができた")
	expect(day.batch_location("cook").position==moving.position and day.batch_location("cook").holder=="nagisa","Mid-route cancellation leaves the same material in the actual carrier's hands")
	expect(day.request("ryo","cook").status=="unavailable","A different adult cannot remotely steal a batch still held by its previous actor")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(day.snapshot()))
	var restored: HouseholdDay = fresh()
	expect(restored.restore(saved) and HouseholdDay._same(saved,restored.snapshot()),"A cancelled but actually held batch resumes from JSON without moving or duplicating it")
	var put: Dictionary = day.request("nagisa","toilet").task
	expect(put.kind=="put_down" and day.batch_location("cook").holder=="nagisa","Another requested action first creates an actual safe put-down intention")
	if not located(day,"nagisa"): return
	expect(day.batch_location("cook").holder=="nagisa","Arrival at the safe surface alone does not put down the batch")
	day.advance_time(.5);day.perform("nagisa",put.id,.5)
	expect(day.batch_location("cook").holder=="nagisa","Half a put-down minute does not claim the completed placement")
	saved=JSON.parse_string(JSON.stringify(day.snapshot()))
	var checkpoint: HouseholdDay = fresh()
	expect(checkpoint.restore(saved) and HouseholdDay._same(saved,checkpoint.snapshot()),"A partially performed safe put-down restores the original holder, real position and its separate source job")
	day.advance_time(.5);day.perform("nagisa",put.id,.5);day.finish("nagisa",put.id)
	var placed: Dictionary = day.batch_location("cook")
	expect(placed.holder.is_empty() and placed.container==put.fixture and placed.position==day._surface_position(put.fixture) and placed.batch_id==identity,"Only actual completed placement changes the container, preserving the batch identity")
	var replacement: Dictionary = begin(day,"ryo","cook")
	expect(replacement.fixture==placed.container and replacement.phases[int(replacement.phase_index)].get("transport","")=="pickup" and day.inventory.ingredients==6,"The replacement first goes to the material's real current surface without consuming again")
	if not located(day,"ryo"): return
	day.advance_time(.5);day.perform("ryo",replacement.id,.5)
	saved=JSON.parse_string(JSON.stringify(day.snapshot()));checkpoint=fresh()
	expect(checkpoint.restore(saved) and HouseholdDay._same(saved,checkpoint.snapshot()),"A partial recovery pickup restores its own clock without advancing the saved real processing phase")
	if not expect(phase(day,"ryo").status=="next_phase","The replacement actually picks up the existing material"): return
	expect(day.batch_location("cook").holder=="ryo" and day.batch_location("cook").batch_id==identity,"Actual pickup transfers the same batch to the new carrier")
	var corrupt: Dictionary = day.snapshot();corrupt.jobs.cook.position=HouseholdDay._encode(day._surface_position("stove"))
	before=day.snapshot()
	expect(not day.restore(corrupt) and HouseholdDay._same(before,day.snapshot()),"A forged held-batch destination is rejected atomically rather than teleporting the material")
	if not located(day,"ryo"): return
	expect(day.batch_location("cook").container.is_empty(),"Arrival at the processing fixture does not teleport the held material onto it")
	day.advance_time(1);day.perform("ryo",replacement.id,1)
	expect(day.batch_location("cook").container=="prep" and day.batch_location("cook").holder.is_empty(),"The first actual placing minute puts the batch on the preparation surface")
	if not expect(complete(day,"ryo"),"The recovered batch finishes its real remaining preparation and heating"): return
	expect(day.inventory.ingredients==6 and day.inventory.prepared_servings==3 and day.batch_locations().is_empty(),"Cancellation, storage, recovery and handoff still produce one finite meal batch")

func authored_supports_and_carried_towel() -> void:
	var day: HouseholdDay = fresh()
	expect(day._surface_position("linen_storage")==day._point(day._fixtures.linen_storage.support_point),"The actual authored linen shelf replaces an invented .95m storage plane")
	expect(day._surface_position("drying_rack")==day._point(day._fixtures.drying_rack.support_point),"The rack batch uses its authored real basket/support location, not a fictional horizontal rack top")
	expect(day._batch_container("changing_space")=="towel_basket" and day._surface_position("changing_space")==day._surface_position("towel_basket"),"A changing-space use point refers to the distinct actual towel basket that supports its batch")
	day.set_position("nagisa",day._point(day._fixtures.prep.interaction_point))
	var safe: String = day._safe_fixture("nagisa",{"kind":"bath"})
	expect(not safe.is_empty() and "bath" in day._fixtures[safe].put_down_kinds and safe not in ["prep","dining_table"],"A bath towel can only be put down on a support explicitly allowing that batch kind, even beside the food-prep top")
	var unsupported: Dictionary = home_plan.duplicate(true)
	for fixture in unsupported.fixtures:
		if fixture.id=="linen_storage": fixture.erase("support_point")
	expect(day.configure(unsupported,authored),"An incomplete support authoring fixture can still be inspected safely")
	var before: Dictionary = day.snapshot()
	expect(day.request("nagisa","laundry").status=="unavailable" and day.batch_locations().is_empty() and HouseholdDay._same(before,day.snapshot()),"Undefined tall-storage support makes real material handling unavailable without fabricating a shelf or debiting clothes")
	unsupported=home_plan.duplicate(true)
	for fixture in unsupported.fixtures:
		if fixture.id=="drying_rack": fixture.erase("support_point")
	expect(day.configure(unsupported,authored),"A rack without a declared support can be inspected")
	day.inventory.wet_laundry=2
	expect(day.request("nagisa","hang_laundry").status=="unavailable" and day.inventory.wet_laundry==2,"An undefined rack support cannot consume wet linen or invent a .95m surface")
	day=fresh();day.person("nagisa").hygiene=.8
	var bath: Dictionary = begin(day,"nagisa","bath")
	if bath.is_empty() or not expect(phase(day,"nagisa").status=="next_phase","Actual changing/pickup starts the bath's carried towel"): return
	var identity: String = day.batch_location("bath:nagisa").batch_id
	if not located(day,"nagisa"): return
	day.advance_time(1);day.perform("nagisa",bath.id,1)
	var batch: Dictionary = day.batch_location("bath:nagisa")
	expect(batch.holder=="nagisa" and batch.container.is_empty() and batch.last_fixture=="towel_basket","The same towel stays held during actual shower time instead of moving to a fictional shower ledge")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(day.snapshot()))
	var restored: HouseholdDay = fresh()
	expect(restored.restore(saved) and HouseholdDay._same(saved,restored.snapshot()),"A towel held during the private bath phase restores at the actual carrier")
	if not expect(phase(day,"nagisa").status=="next_phase" and phase(day,"nagisa").status=="next_phase","The actual wash and soak phases finish without placing the towel on the shower or tub"): return
	batch=day.batch_location("bath:nagisa")
	expect(batch.holder=="nagisa" and batch.batch_id==identity and batch.last_fixture=="towel_basket","The bath carries the same batch back toward changing")
	if not located(day,"nagisa"): return
	day.advance_time(1);day.perform("nagisa",bath.id,1)
	batch=day.batch_location("bath:nagisa")
	expect(batch.holder.is_empty() and batch.container=="towel_basket" and batch.position==day._surface_position("towel_basket"),"Only a real final placing minute returns the towel to the physical basket support")
	expect(complete(day,"nagisa") and day.inventory.dirty_towels==1,"Actual remaining drying/changing completes exactly one used towel")

func furniture_usage_gates_and_delayed_cancel() -> void:
	for pair in [["ryo","sleep"],["ryo","personal_project"],["ryo","care"],["rin","eat"]]:
		var fixture_day: HouseholdDay = fresh()
		fixture_day.person("ryo").fatigue=.9;fixture_day.inventory.table_servings=3;fixture_day.person("rin").hunger=.8
		var intent: Dictionary = begin(fixture_day,pair[0],pair[1])
		if intent.is_empty(): continue
		fixture_day.set_position(pair[0],intent.target)
		expect(fixture_day.arrive(pair[0],intent.id).status=="entering","Bed/chair/sofa/dining arrival reserves only the approach, not actual furniture use")
		fixture_day.advance_time(3)
		expect(fixture_day.perform(pair[0],intent.id,3).status=="not_ready" and fixture_day.task_for(pair[0]).phase_progress==0 and fixture_day.person(pair[0]).actual_minutes.is_empty(),"Entering furniture grants no sleep, meal, work, care or project minutes")
	var room_use := HomeOccupancy.new()
	expect(room_use.configure(home_plan),"The usage test uses real room and fixture reservations")
	var day := HouseholdDay.new()
	expect(day.configure(home_plan,authored,room_use),"The controlled body executor connects to the real occupancy module")
	day.person("ryo").fatigue=.9
	var bed: Dictionary = begin(day,"ryo","sleep")
	var anchor: Vector3 = day._point(day._usage_regions[bed.fixture].center)
	day.set_position("ryo",anchor)
	expect(day.begin_use("ryo",bed.id,anchor,"lie").status=="not_ready","An arbitrary valid-looking anchor cannot bypass arrival and reservation")
	day.set_position("ryo",bed.target);day.arrive("ryo",bed.id)
	var enter_saved: Dictionary = JSON.parse_string(JSON.stringify(day.snapshot()))
	var enter_occupancy := HomeOccupancy.new();enter_occupancy.configure(home_plan)
	var enter_state := HouseholdDay.new();enter_state.configure(home_plan,authored,enter_occupancy)
	expect(enter_state.restore(enter_saved) and HouseholdDay._same(enter_saved,enter_state.snapshot()),"Entry before contact restores the reserved furniture without inventing a usage anchor or work")
	day.advance_time(3)
	expect(day.begin_use("ryo",bed.id,anchor,"lie").status=="not_in_usage","A passed-in anchor cannot replace the person's actual physical position")
	day.set_position("ryo",anchor)
	expect(day.begin_use("ryo",bed.id,anchor,"sit").status=="not_in_usage","The wrong posture cannot claim bed use")
	expect(day.begin_use("ryo",bed.id,anchor,"lie").status=="arrived" and day.perform("ryo",bed.id,100).status=="waiting_for_time","Actual begin_use resets the clock, so entry time can never be back-credited")
	day.advance_time(1);day.perform("ryo",bed.id,100)
	expect(day.task_for("ryo").phase_progress==1 and day.person("ryo").actual_minutes.sleep==1,"Only time after actual use began counts as performed sleep")
	var before: Dictionary = day.snapshot();day.begin_use("ryo",bed.id,anchor,"lie")
	expect(HouseholdDay._same(before,day.snapshot()),"Repeated begin_use is idempotent and does not reset the work clock")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(day.snapshot()))
	var second_occupancy := HomeOccupancy.new();second_occupancy.configure(home_plan)
	var restored := HouseholdDay.new();restored.configure(home_plan,authored,second_occupancy)
	expect(restored.restore(saved) and HouseholdDay._same(saved,restored.snapshot()),"In-use body anchor, posture, actual clock and occupancy survive JSON together")
	var leaving: Dictionary = day.cancel("ryo",bed.id,"先に朝の用事をする")
	expect(leaving.status=="leaving" and day.task_for("ryo").status=="exiting" and day.person("ryo").active_task==bed.id and "ryo" in room_use.snapshot().fixture_users[bed.fixture],"Cancelling an occupied bed keeps the old task active and the bed reserved during exit")
	var serial: int = day.serial
	expect(day.request("ryo","toilet").status=="leaving" and day.serial==serial,"A new intention cannot replace a body still entering or exiting furniture")
	day.advance_time(10)
	expect(day.perform("ryo",bed.id,10).status=="not_ready" and day.person("ryo").actual_minutes.sleep==1,"Exit time cannot turn into performed sleep")
	expect(day.end_use("ryo",bed.id,anchor).status=="not_at_exit","End-use cannot be asserted while the physical body remains on the bed")
	saved=JSON.parse_string(JSON.stringify(day.snapshot()))
	expect(restored.restore(saved) and HouseholdDay._same(saved,restored.snapshot()),"Pending cancellation during exit restores atomically without losing the old occupancy")
	var corrupt: Dictionary = saved.duplicate(true);corrupt.tasks[bed.id].usage.anchor_position=[999,999,999]
	before=restored.snapshot()
	expect(not restored.restore(corrupt) and HouseholdDay._same(before,restored.snapshot()),"A forged usage anchor outside the fixture region is rejected atomically")
	corrupt=saved.duplicate(true);corrupt.claims.erase("ryo")
	expect(not restored.restore(corrupt) and HouseholdDay._same(before,restored.snapshot()),"An exiting task cannot load with its occupancy already freed")
	day.set_position("ryo",bed.target)
	expect(day.end_use("ryo",bed.id,bed.target).status=="cancelled" and day.person("ryo").active_task.is_empty() and "ryo" not in room_use.snapshot().fixture_users[bed.fixture],"Only real return to the walkable approach finalises cancellation and releases occupancy")
	var full: Dictionary = begin(day,"ryo","sleep")
	if not located(day,"ryo"): return
	day.advance_time(60);day.perform("ryo",full.id,60)
	expect(day.finish("ryo",full.id).status=="leaving" and day.person("ryo").history.completed.get("sleep",0)==0 and "ryo" in room_use.snapshot().fixture_users[full.fixture],"Finishing real work begins exit and does not publish completion or free the furniture early")
	day.set_position("ryo",full.target)
	expect(day.end_use("ryo",full.id,full.target).status=="phase_ready" and "ryo" in room_use.snapshot().fixture_users[full.fixture],"A normal end_use retains occupancy until the final completion commits")
	enter_saved=JSON.parse_string(JSON.stringify(day.snapshot()))
	expect(enter_state.restore(enter_saved) and HouseholdDay._same(enter_saved,enter_state.snapshot()),"The normal exited-but-not-yet-finished state saves with its remaining reservation")
	expect(day.finish("ryo",full.id).status=="completed" and "ryo" not in room_use.snapshot().fixture_users[full.fixture],"Only finish after actual exit commits completion and releases the furniture")
	var incomplete: Dictionary = home_plan.duplicate(true)
	for fixture in incomplete.fixtures:
		if fixture.id=="bed_ryo": fixture.erase("usage_region")
	expect(day.configure(incomplete,authored,room_use),"An incomplete furniture definition remains inspectable")
	day.person("ryo").fatigue=.9
	expect(day.request("ryo","sleep").status=="unavailable","A bed without an authored usage region cannot promise actual sleep")

func continuous_scheduled_use() -> void:
	var day: HouseholdDay=fresh()
	day.person("ryo").routines=[{"id":"sleep","place":"home","on_days":[0],"start_minute":240,"duration_minutes":180}]
	var sleep: Dictionary=begin(day,"ryo","sleep")
	if not located(day,"ryo"):return
	day.advance_time(70);day.perform("ryo",sleep.id,70)
	expect(day.task_for("ryo").status=="working" and day.request("ryo").task.id==sleep.id and day._claims.get("ryo")==sleep.fixture,"A scheduled sleep remains in the same bed transaction after an hour instead of standing up and entering again")
	day.advance_time(120);day.perform("ryo",sleep.id,120)
	expect(day.task_for("ryo").status=="phase_ready" and is_equal_approx(day.person("ryo").actual_minutes.sleep,180),"A delayed callback credits only the part of actual sleep before the planned wake-up time")

	day=fresh()
	var shift: Array=[{"id":"remote_work","place":"home","on_days":[0],"start_minute":240,"duration_minutes":180}]
	day.person("ryo").routines=shift.duplicate(true)
	var work: Dictionary=begin(day,"ryo","work")
	day.advance_time(15)
	if not located(day,"ryo"):return
	expect(day.task_for("ryo").phase_minutes==165 and day.person("ryo").actual_minutes.is_empty(),"Desk entry consumes real schedule time without crediting the commute or furniture transition as work")
	day.advance_time(65);day.perform("ryo",work.id,65)
	expect(day.task_for("ryo").status=="working" and day.task_for("ryo").id==work.id,"A work block continues at the same desk after sixty actual minutes")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(day.snapshot()))
	var resumed: HouseholdDay=fresh();resumed.person("ryo").routines=shift.duplicate(true)
	expect(resumed.restore(saved) and HouseholdDay._same(saved,resumed.snapshot()),"A partly performed continuous schedule and its deadline survive JSON without changing time or earnings")
	var invalid: Dictionary=saved.duplicate(true);invalid.tasks[work.id].phases[0].scheduled_end+=60
	expect(not resumed.restore(invalid) and HouseholdDay._same(saved,resumed.snapshot()),"A saved schedule cannot extend the declared shift by forging its end time")
	var money: float=day.cash
	day.advance_time(120);day.perform("ryo",work.id,1)
	expect(day.task_for("ryo").status=="phase_ready" and day.person("ryo").actual_minutes.work==65 and day.cash==money,"Recovering contact after a shift ends does not backfill unattended work or earnings")

	day=fresh();day.person("rin").routines=[{"id":"school","place":"off_map_school","on_days":[0],"start_minute":240,"duration_minutes":180}]
	var school: Dictionary=begin(day,"rin","school")
	day.advance_time(20)
	if not located(day,"rin"):return
	day.advance_time(170);day.perform("rin",school.id,170)
	expect(day.task_for("rin").status=="phase_ready" and is_equal_approx(day.person("rin").actual_minutes.school,160),"A late school arrival uses only the remaining school day, without repeating an hourly departure or crediting travel")

func run() -> void:
	home_plan=JSON.parse_string(FileAccess.get_file_as_string("res://data/foundation/ogawa-home.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	for p in source.residents:
		if p.id not in ["nagisa","ryo","rin"]: continue
		var copy: Dictionary = p.duplicate(true);copy.routines=[];authored.append(copy)
	intention_and_clock();meal_chain();save_and_handoff();conditions_and_hygiene();sleep_care_and_routines();laundry_and_real_responsibilities();urgent_selection_and_wait_timeout();background_projects_and_decisions();batch_transport_and_safe_handoff();authored_supports_and_carried_towel();furniture_usage_gates_and_delayed_cancel();continuous_scheduled_use()
	print("Household day checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

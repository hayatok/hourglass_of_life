extends SceneTree

# Actual LifeSimulation and its saved state, with a controlled twelve-person
# engineering fixture. No natural-choice, visual-contact or human-play claim.
const PARTICIPANTS := ["tomo", "yui"]
var sim: LifeSimulation
var checks: int = 0
var failures: Array[String] = []
var session_id: String = ""
var object_id: String = ""
var save_path: String = "user://test-sewing-integration-%d.json" % OS.get_process_id()
var state_path: String = "user://test-sewing-integration-state-%d.json" % OS.get_process_id()
var report: Dictionary = {"scope":"Controlled actual LifeSimulation, saved files and route/movement. Not natural emergence, rendering or a human playtest.",
	"fixture":"Twelve authored starting positions/skills retained; routines, new autonomous plans and initial urgent needs controlled. Dedicated resumption cases set both selected cash balances to zero or choose a different authored adult learner.",
	"phase_roundtrips":[], "scenarios":[], "journeys":[]}

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
	return ok

func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b)) < 0.0000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same(a[index],b[index]): return false
		return true
	if a is Vector3 and b is Vector3: return a.distance_to(b) < 0.0000001
	return a == b

func setup() -> void:
	if is_instance_valid(sim): sim.free()
	sim = LifeSimulation.new()
	root.add_child(sim)
	sim.set_process(false)
	sim.reset(711,12)
	for person in sim.people:
		sim.definitions[person.id].routines = []
		person.next_plan_minute = 999999
		person.support_next_attempt = 999999
		person.play_next_attempt = 999999
		person.fatigue = .1; person.hunger = .1; person.quiet = .1; person.connection = .4
		person.activity_spot = ""; person.meeting_id = ""; person.routine_id = ""
		person.action = "rest"; person.remaining = 999999; person.action_elapsed = 0
		person.target = person.position; person.destination = person.place
		person.path = []; person.moving = false
	session_id = ""; object_id = ""

func begin_craft(first: String = "tomo", second: String = "yui") -> bool:
	var response: Dictionary = sim.propose_project(first,second,"craft")
	if not expect(response.get("status","") == "accept", "The real town's craft proposal is accepted: " + str(response.get("text",""))): return false
	var active: Dictionary = sim.sewing.active_session()
	if not expect(not active.is_empty(), "The accepted proposal allocates an actual sewing session and object reservation"): return false
	session_id = active.id; object_id = active.object_id
	return true

func current() -> Dictionary:
	return sim.sewing.sessions.get(session_id,{})

func item() -> Dictionary:
	return sim.sewing.objects.get(object_id,{})

func until(phase: String, tool_phase: String = "", min_cut: int = -1, min_sew: int = -1, limit: int = 360) -> bool:
	for ignored in limit:
		var session: Dictionary = current()
		if session.is_empty() or session.get("phase","") == "interrupted": return false
		var piece: Dictionary = item()
		if session.phase == phase and (tool_phase.is_empty() or session.tool_phase == tool_phase) and int(piece.get("cut_minutes",0)) >= min_cut and int(piece.get("sew_minutes",0)) >= min_sew: return true
		sim.advance_minutes(1)
	return false

func finish(limit: int = 360) -> bool:
	for ignored in limit:
		var session: Dictionary = current()
		if session.is_empty(): return false
		if session.phase == "completed": return sim.sewing.active_session().is_empty()
		if session.phase == "interrupted": return false
		sim.advance_minutes(1)
	return false

func snapshot() -> Dictionary:
	# Read the complete production payload rather than maintaining a partial
	# mirror that might silently omit weather, promises, RNG or physical objects.
	if not sim.save_game(state_path): return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	return raw if raw is Dictionary else {}

func roundtrip(label: String) -> bool:
	# Exercise the saved fractional clock as well as integer workflow phases.
	sim.advance_minutes(.25)
	if not expect(sim.save_game(save_path), label+": the current-format town is written to a dedicated file"): return false
	var before: Dictionary = snapshot()
	if not expect(not before.is_empty() and before.has("sewing") and before.has("weather") and before.has("tabletop") and before.has("interactions"), label+": the complete saved town includes sewing, weather and the other physical systems"): return false
	sim.advance_minutes(1.25)
	if not expect(sim.load_game(save_path), label+": the actually advanced town accepts its saved earlier state"): return false
	var restored: Dictionary = snapshot()
	var equal: bool = same(before,restored)
	expect(equal, label+": every saved field is restored, including people, money, memories, clocks, RNG, plans and object progress")
	report.phase_roundtrips.append({"label":label,"minute":sim.elapsed,"phase":current().get("phase",""),"tool_phase":current().get("tool_phase",""),"all_saved_fields_equal":equal})
	return equal

func skills(ids: Array = PARTICIPANTS) -> Dictionary:
	var result: Dictionary = {}
	for id in ids: result[id] = float(sim.person(id).skills.get("craft",0))
	return result

func memory_count(id: String, kind: String, linked_object: String = "") -> int:
	var count: int = 0
	for memory in sim.person(id).memories:
		if memory.kind == kind and (linked_object.is_empty() or memory.get("object_id","") == linked_object): count += 1
	return count

func shared_count() -> int:
	return memory_count("tomo","shared_time") + memory_count("yui","shared_time")

func display_count() -> int:
	return memory_count("tomo","creation_shown",object_id) + memory_count("tomo","seen_creation",object_id) + memory_count("yui","creation_shown",object_id) + memory_count("yui","seen_creation",object_id)

func relax_after_interruption(ids: Array = PARTICIPANTS) -> void:
	# This controlled resumption restores available time/needs, never relocates
	# either participant or replaces the partially made object.
	for id in ids:
		var person: Dictionary = sim.person(id)
		sim.definitions[id].routines = []
		person.hunger = .1; person.fatigue = .1; person.quiet = .1
		person.action = "rest"; person.remaining = 999999; person.action_elapsed = 0
		person.target = person.position; person.destination = person.place; person.path = []; person.moving = false
		person.activity_spot = ""; person.routine_id = ""

func add_work_now(id: String) -> void:
	sim.definitions[id].routines.append({"id":"work_shift","action":"work","place":"home","on_days":[sim.weekday()],"start_minute":sim.minute_of_day(),"duration_minutes":90})

func normal_completion() -> void:
	setup()
	var household: Dictionary = sim.work_family.household(sim.person("tomo"))
	var cash_before: float = float(household.cash)
	var spent_before: float = float(household.spent_today)
	var skills_before: Dictionary = skills()
	if not begin_craft(): return
	var original_id: String = object_id
	var owner_id: String = current().maker
	var viewer_id: String = current().viewer
	var cost: float = float(sim.meetings[0].project.cost)
	var original_ids: Array = sim.sewing.objects.keys()
	var checkpoints: Array = [
		{"phase":"to_source"}, {"phase":"take"}, {"phase":"carry_to_table"}, {"phase":"place"},
		{"phase":"cut","tool":"reach"}, {"phase":"cut","tool":"operate","cut":3}, {"phase":"cut","tool":"return"},
		{"phase":"sew","tool":"reach"}, {"phase":"sew","tool":"operate","sew":4}, {"phase":"sew","tool":"return"},
		{"phase":"lift_show"}, {"phase":"show"}, {"phase":"lower"}, {"phase":"take_store"}, {"phase":"carry_to_store"}, {"phase":"store"}]
	var completed_skills: Dictionary = {}
	var duration_estimates: Array = []
	for checkpoint in checkpoints:
		var label: String = str(checkpoint.phase)+"/"+str(checkpoint.get("tool",""))
		if not expect(until(checkpoint.phase,checkpoint.get("tool",""),int(checkpoint.get("cut",-1)),int(checkpoint.get("sew",-1))), "Actual routes and work reach "+label): return
		if checkpoint.phase == "lift_show":
			completed_skills = skills()
			expect(item().result_recorded and item().stage == "finished" and display_count() == 0 and shared_count() == 0, "Completing the physical pouch does not fabricate a display or completed conversation")
		if not roundtrip(label): return
		var live_meeting: Dictionary = sim.meetings[0]
		var remaining: int = sim.sewing.remaining_minutes(live_meeting)
		duration_estimates.append({"phase":current().phase,"tool_phase":current().tool_phase,"queried_at":sim.elapsed,"minutes":remaining,"estimated_end":int(sim.elapsed)+remaining})
		expect(object_id == original_id and sim.sewing.objects.size() == original_ids.size() and original_ids.all(func(id): return sim.sewing.objects.has(id)), label+": reload preserves the original material/tool IDs instead of making copies")
	if not expect(finish(), "The actual town completes showing and returns the same pouch to storage"): return
	expect(duration_estimates.all(func(record):return int(record.minutes)>0 and int(record.estimated_end)>=int(sim.elapsed)),"All actual phase and tool-subphase estimates remain positive and bound the original world's eventual storage time")
	report.scenarios.append({"name":"all_physical_phase_duration_estimates","actual_completed_at":sim.elapsed,"estimates":duration_estimates})
	household = sim.work_family.household(sim.person("tomo"))
	var pouch: Dictionary = item()
	expect(pouch.id == original_id and pouch.kind == "pouch" and pouch.owner == owner_id and pouch.container == "sewing_storage" and pouch.holder.is_empty(), "The original material ID ends as one owned, stored pouch")
	expect(int(pouch.cut_minutes) == int(sim.sewing.config.cut_minutes) and int(pouch.sew_minutes) == int(sim.sewing.config.sew_minutes), "Completion comes from all actual cutting and sewing minutes")
	expect(is_equal_approx(float(household.cash),cash_before-cost) and is_equal_approx(float(household.spent_today),spent_before+cost), "The real household pays the material fee exactly once")
	expect(is_equal_approx(float(sim.work_family.projects.craft),.18) and same(skills(),completed_skills), "Cleanup and save restoration do not award the completed project or skill a second time")
	expect(float(skills()[owner_id]) > float(skills_before[owner_id]) and float(skills()[viewer_id]) > float(skills_before[viewer_id]), "The completed shared work changes both actual craft skills")
	expect(pouch.shown_to == [viewer_id] and memory_count(owner_id,"creation_shown",original_id) == 1 and memory_count(viewer_id,"seen_creation",original_id) == 1, "Only the actual display creates one object-linked memory for each participant")
	expect(shared_count() == 2 and sim.sewing.objects.values().all(func(value): return value.reserved_by.is_empty() and value.holder.is_empty()), "Finishing frees every tool and reservation and records one completed encounter per participant")
	roundtrip("completed")
	report.scenarios.append({"name":"complete_with_phase_restores","object_id":original_id,"owner":owner_id,"material_cost":cost,"spent_delta":float(household.spent_today)-spent_before,"all_phases":true})

func interrupted_cut(cause: String) -> void:
	setup()
	var household: Dictionary = sim.work_family.household(sim.person("tomo"))
	var spent_before: float = float(household.spent_today)
	var skills_before: Dictionary = skills()
	if not begin_craft() or not expect(until("cut","operate",4), "The interruption fixture performs actual cutting before "+cause): return
	var original_id: String = object_id
	var owner_id: String = current().maker
	var viewer_id: String = current().viewer
	var cost: float = float(sim.meetings[0].project.cost)
	var cut_before: int = int(item().cut_minutes)
	if cause == "work": add_work_now(viewer_id)
	else: sim.person(viewer_id).hunger = .81
	sim.advance_minutes(1)
	expect(current().phase == "interrupted" and sim.sewing.active_session().is_empty() and sim.meetings.is_empty(), "An actual "+cause+" priority ends the live sewing meeting")
	expect(item().id == original_id and item().stage == "cut" and item().owner == owner_id and int(item().cut_minutes) == cut_before and item().container == "sewing_storage", "Interrupting for "+cause+" preserves the same unfinished, already paid cloth")
	expect(same(skills(),skills_before) and display_count() == 0 and shared_count() == 0 and is_equal_approx(float(sim.work_family.projects.craft),0), "Interrupted cutting grants no finished work, skill or fabricated shared-time memory")
	if not roundtrip("interrupted_cut_"+cause): return
	relax_after_interruption()
	if not begin_craft(): return
	expect(object_id == original_id and current().maker == owner_id and bool(sim.meetings[0].materials_ready), "Resuming after "+cause+" selects the original maker's paid unfinished item")
	if not expect(until("lift_show"), "Resumed actual work finishes after "+cause): return
	var completed_skills: Dictionary = skills()
	if not expect(finish(), "Resumed work is actually shown and stored after "+cause): return
	household = sim.work_family.household(sim.person("tomo"))
	expect(is_equal_approx(float(household.spent_today),spent_before+cost) and is_equal_approx(float(sim.work_family.projects.craft),.18) and same(skills(),completed_skills), "Resumption after "+cause+" charges once and awards one finished result, including cleanup")
	expect(item().id == original_id and item().shown_to == [viewer_id] and display_count() == 2 and shared_count() == 2, "The resumed "+cause+" workflow displays the same object once to the actual partner")
	report.scenarios.append({"name":"cut_interrupted_by_"+cause,"object_id":original_id,"cut_before_interruption":cut_before,"spent_delta":float(household.spent_today)-spent_before})

func show_only_resumption() -> void:
	setup()
	var household: Dictionary = sim.work_family.household(sim.person("tomo"))
	var spent_before: float = float(household.spent_today)
	if not begin_craft() or not expect(until("lift_show"), "The show-only fixture reaches an actual finished pouch before display"): return
	var original_id: String = object_id
	var viewer_id: String = current().viewer
	var completed_skills: Dictionary = skills()
	var cost: float = float(sim.meetings[0].project.cost)
	expect(item().result_recorded and display_count() == 0 and shared_count() == 0, "A finished but unseen pouch has skill progress and no display/shared-time memories")
	add_work_now(viewer_id); sim.advance_minutes(1)
	expect(current().phase == "interrupted" and item().kind == "pouch" and item().shown_to.is_empty() and display_count() == 0 and shared_count() == 0, "Leaving before showing keeps the product without fabricating an encounter")
	expect(same(skills(),completed_skills) and is_equal_approx(float(sim.work_family.projects.craft),.18), "Interrupting after completion does not repeat skill or project credit")
	if not roundtrip("finished_unshown_interrupted"): return
	relax_after_interruption()
	if not begin_craft(): return
	expect(object_id == original_id and bool(sim.meetings[0].sewing_resume_finished) and float(sim.meetings[0].remaining) == 0 and display_count() == 0 and shared_count() == 0, "A show-only restart uses the same finished item and grants no memory on acceptance")
	if not roundtrip("show_only_before_display") or not expect(until("show"), "The show-only plan physically reaches its real viewer"): return
	expect(display_count() == 0 and shared_count() == 0, "Lifting the object alone still gives no display or shared-time memory")
	if not expect(until("lower"), "The real display lasts its required time before lowering"): return
	expect(display_count() == 2 and item().shown_to == [viewer_id], "Only presenting the real finished pouch records the two object-linked memories")
	if not expect(finish(), "The show-only plan stores the finished pouch after its actual display"): return
	household = sim.work_family.household(sim.person("tomo"))
	expect(same(skills(),completed_skills) and is_equal_approx(float(sim.work_family.projects.craft),.18) and is_equal_approx(float(household.spent_today),spent_before+cost), "The show-only continuation never buys another cloth or repeats skill/project credit")
	expect(shared_count() == 2 and display_count() == 2, "A completed actual display records one encounter and one object memory per participant")
	report.scenarios.append({"name":"finished_before_display_then_show_only","object_id":original_id,"spent_delta":float(household.spent_today)-spent_before})

func household_accounts(ids: Array = PARTICIPANTS) -> Dictionary:
	var result: Dictionary = {}
	for id in ids:
		var person: Dictionary = sim.person(id)
		var household_id: String = sim.work_family.household_id(person)
		var household: Dictionary = sim.work_family.household(person)
		result[household_id] = {"cash":float(household.cash),"spent_today":float(household.spent_today)}
	return result

func zero_cash_resumption(finished_item: bool) -> void:
	setup()
	var new_project: Dictionary = sim.resident_activities.definition(sim.person("tomo"),sim.person("yui"),"craft")
	var new_duration: int = sim.sewing.planned_minutes(sim.person("tomo"),sim.person("yui"),new_project)
	expect(new_duration==120,"The new-cloth admission estimate includes 45 real work minutes and 75 handling minutes")
	if not begin_craft(): return
	if finished_item:
		if not expect(until("lift_show"),"The empty-wallet display fixture first makes a real completed pouch"): return
	else:
		if not expect(until("cut","operate",4),"The empty-wallet work fixture first pays for and cuts a real cloth"): return
	var original_id: String = object_id
	var owner_id: String = current().maker
	var viewer_id: String = current().viewer
	var before_resume_skills: Dictionary = skills()
	var total_minutes: int = int(item().cut_minutes)+int(item().sew_minutes)
	add_work_now(viewer_id);sim.advance_minutes(1)
	if not expect(current().phase=="interrupted" and item().material_used,"An actual work priority interrupts an already paid object before empty-wallet resumption"): return
	relax_after_interruption()
	# Both selected people have no money. Their shared household is represented
	# once in the account snapshot, rather than counted as two independent purses.
	for id in PARTICIPANTS: sim.work_family.household(sim.person(id)).cash=0.0
	var zero_accounts: Dictionary = household_accounts()
	var label: String = "paid_finished" if finished_item else "paid_partial"
	if not roundtrip(label+"_both_cash_zero"): return
	expect(PARTICIPANTS.all(func(id):return is_zero_approx(float(sim.work_family.household(sim.person(id)).cash))),"Both participants really have zero available cash after the saved town is restored")
	var project: Dictionary = sim.resident_activities.definition(sim.person("tomo"),sim.person("yui"),"craft")
	var before_time_query: Dictionary = snapshot()
	var planned_duration: int = sim.sewing.planned_minutes(sim.person("tomo"),sim.person("yui"),project)
	expect(planned_duration==45-total_minutes+75 and planned_duration<new_duration,"The paid object's admission estimate uses only its remaining work plus conservative handling time")
	expect(same(snapshot(),before_time_query),"Reading the paid object's planned duration changes no saved town field")
	expect(int(sim.agenda._activity(sim.person("tomo"),sim.person("yui"),"craft").get("duration",0))==planned_duration,"The real future-agreement activity uses the same selected object's planned duration")
	if finished_item:
		for id in PARTICIPANTS: sim.person(id).hunger=.63
		expect(planned_duration==75,"A finished unshown pouch reserves handling time without another 45 minutes of processing")
	expect(is_zero_approx(sim.sewing.material_cost(sim.person("tomo"),sim.person("yui"),project)) and not sim.resident_activities._feasible(sim.person("tomo"),sim.person("yui"),project).is_empty(),"The real candidate gate accepts the paid object without a new purchase or already-finished work time")
	if not begin_craft(): return
	if finished_item: expect(PARTICIPANTS.all(func(id):return is_equal_approx(float(sim.person(id).hunger),.63)),"The actual show-only proposal is accepted while both participants have hunger .63")
	expect(object_id==original_id and current().maker==owner_id and sim.meetings[0].materials_ready,"The zero-cash proposal selects the same paid object and its actual owner")
	if finished_item:
		expect(sim.meetings[0].sewing_resume_finished and sim.meetings[0].remaining==0 and display_count()==0 and shared_count()==0,"An empty-wallet finished item resumes only its real display and cleanup, without new work or memories on acceptance")
	else:
		expect(int(sim.meetings[0].remaining)==45-total_minutes and not sim.meetings[0].work_completed,"An empty-wallet unfinished item resumes exactly its remaining real processing minutes")
	if not expect(finish(),"The zero-cash "+label+" continuation physically finishes its display and storage"): return
	expect(same(household_accounts(),zero_accounts),"The resumed "+label+" workflow changes neither the zero cash nor the already recorded material spending")
	expect(item().id==original_id and item().owner==owner_id and item().container=="sewing_storage" and item().shown_to==[viewer_id] and display_count()==2 and shared_count()==2,"The zero-cash continuation preserves ownership and records only the real display to its actual participant")
	expect(is_equal_approx(float(sim.work_family.projects.craft),.18),"The zero-cash continuation retains exactly one finished project")
	if finished_item: expect(same(skills(),before_resume_skills),"A zero-cash show-only continuation grants no duplicate craft skill")
	roundtrip(label+"_zero_cash_completed")
	report.scenarios.append({"name":label+"_resumed_with_both_cash_zero","object_id":original_id,"owner":owner_id,"accounts_before":zero_accounts,"accounts_after":household_accounts(),"additional_material_cost":0})

func owner_with_different_learner() -> void:
	setup()
	if not begin_craft() or not expect(until("cut","operate",4),"The owner-selection fixture performs actual paid cutting"): return
	var original_id: String = object_id
	var owner_id: String = current().maker
	var previous_viewer: String = current().viewer
	add_work_now(previous_viewer);sim.advance_minutes(1)
	if not expect(current().phase=="interrupted" and item().owner==owner_id,"The real interruption leaves the partly made cloth with its maker"): return
	# Keep authored craft skills. Maho is an eligible adult with less craft
	# experience than the owner, so the new project's learner is another person.
	var new_viewer: String = "maho"
	var next_pair: Array = [owner_id,new_viewer]
	relax_after_interruption(next_pair)
	var project: Dictionary = sim.resident_activities.definition(sim.person(owner_id),sim.person(new_viewer),"craft")
	if not expect(project.get("learner","")==new_viewer and project.learner!=owner_id,"The actual authored skill difference selects a learner who is not the original object's owner"): return
	var before_selection: Dictionary = snapshot()
	var chosen: Dictionary = sim.sewing.selection(sim.person(owner_id),sim.person(new_viewer),project)
	expect(chosen.get("maker","")==owner_id and chosen.get("id","")==original_id and chosen.get("remaining_cost",-1)==0,"The real town's material selection preserves the original maker despite the new learner")
	expect(same(snapshot(),before_selection),"Inspecting the alternate-learner candidate does not rewrite the actual saved town")
	if not begin_craft(owner_id,new_viewer): return
	expect(object_id==original_id and current().maker==owner_id and current().viewer==new_viewer and sim.meetings[0].project.learner==new_viewer,"The accepted actual proposal uses that same object and owner while retaining the project's distinct learner")
	var consumed_before: int = sim.sewing.objects.values().filter(func(record):return record.kind not in ["scissors","needle","spool"] and record.material_used).size()
	if not expect(finish(),"The original maker and different learner carry out the remaining processing, display and storage"): return
	expect(item().owner==owner_id and item().id==original_id and item().shown_to==[new_viewer] and memory_count(owner_id,"creation_shown",original_id)==1 and memory_count(new_viewer,"seen_creation",original_id)==1,"The new learner sees the actual owner's finished item once")
	expect(sim.sewing.objects.values().filter(func(record):return record.kind not in ["scissors","needle","spool"] and record.material_used).size()==consumed_before and is_equal_approx(float(sim.work_family.projects.craft),.18),"Changing the learner neither consumes another cloth nor duplicates the completed project")
	roundtrip("owner_preserved_with_different_learner")
	report.scenarios.append({"name":"owner_preserved_when_project_learner_changes","object_id":original_id,"maker":owner_id,"project_learner":new_viewer,"previous_viewer":previous_viewer,"authored_skills_retained":true})

func reservation_duration(checkpoint: String) -> void:
	setup()
	if not begin_craft(): return
	if checkpoint=="cut":
		if not expect(until("cut","operate",4),"The busy-time cut fixture reaches actual partly processed cloth"): return
	elif checkpoint=="show_only":
		if not expect(until("lift_show"),"The busy-time show-only fixture first completes its real pouch"): return
		add_work_now(current().viewer);sim.advance_minutes(1)
		if not expect(current().phase=="interrupted","A real duty preserves the finished unshown object for the busy-time fixture"): return
		relax_after_interruption()
		if not begin_craft(): return
		if not expect(sim.meetings[0].remaining==0 and current().resume_finished,"The active show-only continuation has zero processing minutes but real handling still ahead"): return
	else:
		if not expect(until("carry_to_store"),"The busy-time cleanup fixture really carries the shown pouch back to its cabinet"): return
	sim.advance_minutes(.5)
	var meeting: Dictionary = {}
	for candidate in sim.meetings:
		if candidate.id==current().meeting: meeting=candidate;break
	if not expect(not meeting.is_empty(),"The busy-time fixture retains its actual live meeting"): return
	var started: int = int(sim.elapsed)
	var processing_remaining: int = int(meeting.remaining)
	var before: Dictionary = snapshot()
	var remaining: int = sim.sewing.remaining_minutes(meeting)
	var estimated_end: int = started+remaining
	var busy_ends: Dictionary = {}
	var pure_reads: bool = true
	for ignored in 3:
		if sim.sewing.remaining_minutes(meeting)!=remaining: pure_reads=false
		for id in PARTICIPANTS: busy_ends[id]=sim.agenda._busy_until(sim.person(id))
	expect(remaining>int(meeting.remaining) and remaining>0,"The "+checkpoint+" estimate reserves real handling and routes beyond the processing counter")
	expect(pure_reads and same(snapshot(),before),"Repeated "+checkpoint+" duration and busy-time reads change no world, money, reservations, clocks or RNG")
	for id in PARTICIPANTS:
		expect(int(busy_ends[id])>=estimated_end and not sim.agenda._window_free(sim.person(id),estimated_end-1,estimated_end+1),"The "+checkpoint+" calendar blocks another agreement through its conservative object-storage estimate for "+id)
	# Actually ask the production planner for another meeting. Its preparation
	# and travel must start after the current physical work, not its last stitch.
	var response: Dictionary = sim.agenda.propose(PARTICIPANTS[0],PARTICIPANTS[1],"social",false,started)
	if not expect(response.get("status","")=="accept","The actual "+checkpoint+" planner finds a later social agreement: "+str(response.get("text",""))): return
	var future: Dictionary = {}
	for record in sim.agenda.records:
		if record.id==response.get("record_id",""): future=record;break
	if not expect(not future.is_empty(),"The later "+checkpoint+" agreement is recorded by the actual planner"): return
	for id in PARTICIPANTS:
		expect(int(future.departures[id])>=int(busy_ends[id]),"The later "+checkpoint+" agreement cannot send "+id+" away during sewing display or cleanup")
	var occupied_until_done: bool = true
	for ignored in 360:
		if current().phase not in sim.sewing.ACTIVE: break
		for id in PARTICIPANTS:
			if sim.agenda._busy_until(sim.person(id))<=int(sim.elapsed) or sim.agenda._window_free(sim.person(id),int(sim.elapsed),int(sim.elapsed)+1): occupied_until_done=false
		if future.state!="planned": occupied_until_done=false
		sim.advance_minutes(1)
	var actual_end: int = int(sim.elapsed)
	expect(current().phase=="completed" and item().container=="sewing_storage","The original "+checkpoint+" world actually finishes and stores the same pouch while its later agreement waits")
	expect(occupied_until_done,"The real "+checkpoint+" calendar stays occupied on every actual tick through display and cleanup")
	expect(actual_end<=estimated_end,"The "+checkpoint+" physical workflow finishes no later than its earlier conservative estimate")
	for id in PARTICIPANTS: expect(actual_end<=int(future.departures[id]),"The actual "+checkpoint+" storage finishes before "+id+" must leave for the next agreement")
	expect(sim.sewing.remaining_minutes(meeting)==0,"Only the terminal "+checkpoint+" sewing session has zero remaining calendar time")
	report.scenarios.append({"name":"busy_until_"+checkpoint,"object_id":object_id,"phase_at_query":checkpoint,"queried_at":started,"processing_remaining":processing_remaining,
		"estimated_minutes":remaining,"estimated_end":estimated_end,"actual_end":actual_end,"next_agreement_departures":future.departures.duplicate(true),"occupied_until_complete":occupied_until_done})

func sweep(origin: Vector3, path: Array, occupied: Array) -> Dictionary:
	var samples: int = 0
	for endpoint: Vector3 in path:
		var count: int = maxi(1,ceili(origin.distance_to(endpoint)/.05))
		for index in range(count+1):
			var point: Vector3 = origin.lerp(endpoint,float(index)/count)
			samples += 1
			for rectangle: Rect2 in occupied:
				if rectangle.has_point(Vector2(point.x,point.z)): return {"clear":false,"samples":samples,"collision":point,"rectangle":str(rectangle)}
		origin = endpoint
	return {"clear":true,"samples":samples}

func journey(origin: Vector3, origin_place: String, target: Vector3, destination: String, occupied: Array, label: String) -> void:
	var path: Array = sim.route(origin,origin_place,target,destination)
	if not expect(not path.is_empty() and path[-1].distance_to(target) < .00001,label+": the actual route retains its destination"): return
	var observation: Dictionary = sweep(origin,path,occupied)
	expect(observation.clear,label+": the independent 5cm sweep clears public furniture and the cabinet at body width")
	var person: Dictionary = sim.person("haru")
	person.position = origin; person.place = origin_place; person.target = target; person.destination = destination
	person.path = path.duplicate(); person.moving = true
	for minute in 500:
		if not person.moving: break
		sim._move(person)
	expect(not person.moving and person.position.distance_to(target) < .00001 and person.place == destination,label+": actual movement consumes the route and arrives")
	report.journeys.append({"label":label,"origin":str(origin),"target":str(target),"route_points":path.size(),"sweep":observation})

func cabinet_routes() -> void:
	setup()
	var cabinet: Rect2 = Rect2(Vector2(-5.45,8.16),Vector2(1.80,.38)).grow(.18)
	var table: Rect2 = Rect2(Vector2(-3.575,7.88),Vector2(1.55,.84)).grow(.18)
	var occupied: Array = sim.activities.public_obstacles.duplicate()
	occupied.append(cabinet); occupied.append(table)
	for bench in sim.benches: occupied.append(Rect2(Vector2(bench.x-.88,bench.z-.34),Vector2(1.76,.66)).grow(.18))
	var included: bool = sim.activities.public_obstacles.any(func(value: Rect2): return value.position.distance_to(cabinet.position) < .00001 and value.size.distance_to(cabinet.size) < .00001)
	expect(included, "The cabinet's real scene footprint participates in public navigation")
	var table_target: Vector3 = sim.activities.spots.craft_art_0.approach
	var home: String = sim.home_for(sim.person("tomo"))
	for index in sim.sewing.config.storage_slots.size():
		var slot: Vector3 = sim.sewing.config.storage_slots[index]
		var approach: Vector3 = Vector3(slot.x,0,sim.sewing.config.source_approach.z)
		var inside_room: bool = sim.activities.rooms.keys().any(func(site: String): return sim.activities.inside(site,approach))
		expect(not inside_room and bool(sweep(approach,[approach],occupied).clear), "Cabinet slot %d has a public, body-clear source approach"%index)
		journey(approach,"square",table_target,"square",occupied,"Slot %d to cutting table"%index)
		journey(table_target,"square",approach,"square",occupied,"Cutting table to slot %d"%index)
		journey(approach,"square",sim.SITES[home],home,occupied,"Slot %d to maker household"%index)
		journey(approach,"square",sim.SITES.home_ogawa,"home_ogawa",occupied,"Slot %d to west household"%index)

func run() -> void:
	normal_completion()
	interrupted_cut("work")
	interrupted_cut("hunger")
	show_only_resumption()
	zero_cash_resumption(false)
	zero_cash_resumption(true)
	owner_with_different_learner()
	reservation_duration("cut")
	reservation_duration("show_only")
	reservation_duration("cleanup")
	cabinet_routes()
	report.checks = checks; report.failures = failures
	DirAccess.make_dir_recursive_absolute("res://builds/sewing-integration")
	FileAccess.open("res://builds/sewing-integration/results.json",FileAccess.WRITE).store_string(JSON.stringify(sim._encode(report),"\t"))
	for path in [save_path,state_path,save_path+".tmp",state_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if is_instance_valid(sim): sim.free()
	print("Sewing integration checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

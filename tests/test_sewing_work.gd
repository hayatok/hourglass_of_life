extends SceneTree

# Isolated workflow fixtures exercise ownership, time and effects. They are not
# evidence of natural resident choices, full town routes or rendered contact.
class Places extends RefCounted:
	var spots: Dictionary = {
		"craft_art_0":{"id":"craft_art_0","site":"square","group":"craft","approach":Vector3(-3.15,0,8.96)},
		"craft_art_1":{"id":"craft_art_1","site":"square","group":"craft","approach":Vector3(-2.45,0,8.96)}}
	func for_person(person: Dictionary) -> Dictionary: return spots.get(person.get("activity_spot",""),{})

class Life extends RefCounted:
	func is_alive(person: Dictionary) -> bool: return not person.is_empty() and person.get("alive",false)

class Work extends RefCounted:
	var charges: int = 0
	var results: int = 0
	var occupied: Dictionary = {}
	func meeting_compatible(person: Dictionary, _meeting: Dictionary) -> bool: return not occupied.get(person.id,false)
	func project_tick(meeting: Dictionary) -> void:
		if not meeting.materials_ready: charges+=1;meeting.materials_ready=true
	func finish_project(meeting: Dictionary) -> void:
		if meeting.get("project_result_recorded",false): return
		meeting.project_result_recorded=true;results+=1

class Town extends RefCounted:
	var elapsed: int = 0
	var minute_remainder: float = 0.0
	var people: Array = []
	var meetings: Array = []
	var definitions: Dictionary = {"first":{},"second":{},"child":{}}
	var activities := Places.new()
	var life := Life.new()
	var work_family := Work.new()
	func _init() -> void:
		for id in definitions:
			people.append({"id":id,"name":id,"age":24 if id!="child" else 9,"alive":true,"position":Vector3(-2.8,0,9.8),
				"place":"square","destination":"square","target":Vector3(-2.8,0,9.8),"path":[],"moving":false,
				"activity_spot":"","meeting_id":"","reason":"","hunger":.2,"fatigue":.2,"memories":[],"relationships":{}})
	func person(id: String) -> Dictionary:
		for value in people:
			if value.id==id: return value
		return {}
	func route(origin: Vector3, _place: String, target: Vector3, _destination: String) -> Array:
		return [] if origin.distance_to(target)<.001 else [target]
	func _remember(p: Dictionary, other: String, title: String, message: String, kind: String) -> void:
		p.memories.append({"other":other,"title":title,"text":message,"kind":kind,"minute":elapsed})
	func _relation(p: Dictionary, other: String) -> Dictionary:
		if not p.relationships.has(other): p.relationships[other]={"familiarity":.2,"ease":.2}
		return p.relationships[other]
	func move_people() -> void:
		for p in people:
			if not p.moving: continue
			var remaining: float = .36
			while remaining>0 and not p.path.is_empty():
				var distance: float = p.position.distance_to(p.path[0])
				if distance<=remaining: p.position=p.path.pop_front();remaining-=distance
				else: p.position=p.position.move_toward(p.path[0],remaining);remaining=0
			p.moving=not p.path.is_empty()
			if not p.moving: p.place=p.destination

var checks: int = 0
var failures: Array[String] = []
var town: Town
var sewing: SewingWork
var meeting_serial: int = 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)

func reset() -> void:
	town=Town.new();sewing=SewingWork.new(town);sewing.reset();meeting_serial=0

func begin(first: String = "first", second: String = "second", learner: String = "first") -> Dictionary:
	meeting_serial+=1
	var meeting: Dictionary={"id":"meeting_%d"%meeting_serial,"a":first,"b":second,"mode":"project","project":{"key":"craft","learner":learner},
		"remaining":45,"materials_ready":false,"state":"travel","not_before":0}
	var index: int=0
	for id in [first,second]:
		var p: Dictionary=town.person(id);p.meeting_id=meeting.id;p.activity_spot="craft_art_%d"%index
		p.target=town.activities.spots[p.activity_spot].approach;p.path=town.route(p.position,p.place,p.target,"square");p.moving=not p.path.is_empty();index+=1
	town.meetings.append(meeting)
	if not sewing.begin(meeting):
		town.meetings.erase(meeting)
		for id in [first,second]: town.person(id).meeting_id=""
		return {}
	return meeting

func step() -> String:
	town.elapsed+=1;sewing.tick();town.move_people()
	if town.meetings.is_empty(): return "none"
	var m: Dictionary=town.meetings[0]
	var status: String=sewing.advance(m)
	if status=="working":
		town.work_family.project_tick(m);m.remaining-=1;sewing.worked(m);m.remaining=sewing.work_remaining(m)
	if status in ["completed","interrupted"]:
		sewing.end(m,status=="completed");town.meetings.erase(m)
		for id in [m.a,m.b]: town.person(id).meeting_id=""
	return status

func until(phase: String, tool_phase: String = "", limit: int = 500) -> bool:
	for ignored in limit:
		var current: Dictionary=sewing.active_session()
		if not current.is_empty() and current.phase==phase and (tool_phase.is_empty() or current.tool_phase==tool_phase): return true
		step()
	return false

func finish(limit: int = 500) -> bool:
	for ignored in limit:
		if town.meetings.is_empty(): return sewing.active_session().is_empty()
		step()
	return false

func interrupt() -> void:
	var m: Dictionary=town.meetings[0]
	sewing.end(m,false);town.meetings.clear()
	for id in [m.a,m.b]: town.person(id).meeting_id=""

func encode(value: Variant) -> Variant:
	if value is Vector3: return {"__vector3":[value.x,value.y,value.z]}
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[key]=encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(encode(item))
		return result
	return value

func decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("__vector3"): return Vector3(value.__vector3[0],value.__vector3[1],value.__vector3[2])
		var result: Dictionary={}
		for key in value: result[key]=decode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(decode(item))
		return result
	return value

func packet() -> Dictionary:
	return encode({"people":town.people,"meetings":town.meetings,"elapsed":town.elapsed,"remainder":town.minute_remainder,"sewing":sewing.serialize()})

func valid() -> bool:
	var raw: Dictionary=packet()
	return SewingWork.valid_save(raw.sewing,raw,town.definitions)

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<.000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	return a==b

func run() -> void:
	reset()
	expect(sewing.objects.size()==9 and sewing.objects.values().filter(func(item):return item.kind=="fabric").size()==6,"The initial world has six finite cloth IDs and three shared tools")
	expect(valid(),"The untouched stock and tools form a valid saved world")
	var first: Dictionary=town.person("first");var second: Dictionary=town.person("second")
	expect(sewing.available(first,second),"Free materials and tools make a joint craft available without reserving them")
	var frozen: Dictionary=sewing.serialize()
	sewing.available(first,second)
	expect(sewing.serialize()==frozen,"Inspecting craft availability does not change object ownership or stock")
	var meeting: Dictionary=begin()
	expect(not meeting.is_empty() and not sewing.available(first,second),"Beginning the workflow reserves one shared workpiece and the tools")
	expect(town.work_family.charges==0 and town.work_family.results==0,"An invitation and travel do not consume material or grant progress")
	expect(until("cut","reach"),"The participants physically reach the workbench before tool preparation")
	var session: Dictionary=sewing.active_session();var item: Dictionary=sewing.objects[session.object_id]
	var item_id: String=item.id
	expect(not item.material_used and town.work_family.charges==0 and sewing.objects.sewing_scissors.holder.is_empty(),"The scissors remain on the table before their pickup, with the cloth unconsumed")
	expect(until("cut","operate"),"The tool reach finishes before actual cutting is eligible")
	for ignored in 100:
		if item.cut_minutes>=5: break
		step()
	expect(item.material_used and item.owner=="first" and item.cut_minutes==5 and item.sew_minutes==0 and town.work_family.charges==1,"Five real cutting minutes consume one cloth and one material fee")
	expect(valid(),"A real mid-cut hand/tool/material state validates")
	interrupt()
	expect(item.stage=="cut" and item.holder.is_empty() and item.reserved_by.is_empty() and item.container=="sewing_storage","Interrupted cutting preserves the same partially used cloth in storage")
	expect(town.work_family.results==0 and sewing.objects.values().all(func(value):return value.reserved_by.is_empty()),"Interrupting before completion grants no product and releases all reservations")
	expect(valid(),"The interrupted workflow and stored unfinished item validate")
	meeting=begin()
	expect(sewing.active_session().object_id==item_id and meeting.materials_ready and meeting.remaining==40,"The maker resumes the same unfinished item instead of consuming another cloth")
	expect(finish(),"The resumed workflow reaches display and storage through every remaining phase")
	expect(item.stage=="finished" and item.kind=="pouch" and item.owner=="first" and item.cut_minutes==12 and item.sew_minutes==33,"The original material ID becomes one actual completed pouch")
	expect(town.work_family.charges==1 and town.work_family.results==1,"Resuming and cleaning up do not charge again or duplicate the completed result")
	expect(item.shown_to==["second"] and first.memories.size()==1 and second.memories.size()==1 and first.memories[0].object_id==item_id and second.memories[0].object_id==item_id,"Showing the actual item creates one object-linked memory for each real participant")
	expect(valid(),"The completed pouch and returned shared tools validate")
	# Completion survives interruption before the display without granting another result.
	reset();meeting=begin();until("lift_show");session=sewing.active_session();item=sewing.objects[session.object_id];item_id=item.id
	expect(town.work_family.results==1 and item.result_recorded and item.shown_to.is_empty(),"Sewing completion is separate from showing the object")
	interrupt();meeting=begin()
	expect(sewing.active_session().object_id==item_id and meeting.remaining==0 and meeting.work_completed and meeting.project_result_recorded,"An unshown completed item resumes as a show-only plan")
	expect(town.person("first").memories.is_empty(),"Restarting a show-only plan does not fabricate a meeting or display memory")
	expect(finish() and town.work_family.results==1 and town.work_family.charges==1 and item.shown_to==["second"],"A later actual display stores the same pouch without repeating the material fee or skill result")
	var next: Dictionary=begin()
	expect(not next.is_empty() and sewing.active_session().object_id!=item_id and item.owner=="first","A displayed finished item stays owned while a later craft uses another finite material")
	# A participant's urgent meal or newly occupied duty interrupts safely.
	reset();begin();until("sew","operate");town.person("second").hunger=.81;step()
	expect(sewing.active_session().is_empty() and sewing.objects.values().all(func(value):return value.holder.is_empty() and value.reserved_by.is_empty()),"An urgent need interrupts sewing and safely releases tools and the unfinished item")
	reset();begin();until("cut","operate");town.work_family.occupied.second=true;step()
	expect(sewing.active_session().is_empty(),"A new non-negotiable duty takes priority over the craft")
	reset();begin();until("carry_to_table");town.person("first").alive=false;town.meetings.clear();sewing.tick()
	expect(sewing.active_session().is_empty() and sewing.objects.values().all(func(value):return value.holder.is_empty() and value.reserved_by.is_empty()),"Death or an orphaned meeting cannot leave an item attached to a departed participant")
	# Exercise the JSON boundary while a shared tool is returning to the table.
	reset();begin();until("cut","return")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(packet()))
	expect(SewingWork.valid_save(saved.sewing,saved,town.definitions),"A mid-tool-return JSON save validates without rounding-sensitive identity comparisons")
	finish();var future: Dictionary=packet();var future_charges: int=town.work_family.charges;var future_results: int=town.work_family.results
	town=Town.new();town.people=decode(saved.people);town.meetings=decode(saved.meetings);town.elapsed=int(saved.elapsed);town.minute_remainder=float(saved.remainder);town.work_family.charges=1
	sewing=SewingWork.new(town);sewing.restore(decode(saved.sewing))
	expect(finish() and equivalent(packet(),future) and town.work_family.charges==future_charges and town.work_family.results==future_results,"Restored tool return and unfinished material produce the same later world and one result")
	# Reject contradictory or overflowing encoded saves without touching a live workflow.
	var cases: Array=[]
	var broken: Dictionary=saved.duplicate(true);broken.sewing.objects[item_id].owner="missing";cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.objects.sewing_scissors.holder="second";cases.append(broken)
	broken=saved.duplicate(true);broken.meetings[0].remaining+=1;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.objects.erase("sewing_cloth_01");cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.objects.sewing_cloth_06.sew_minutes=10;cases.append(broken)
	broken=saved.duplicate(true);broken.meetings[0].sewing_presented="yes";cases.append(broken)
	broken=saved.duplicate(true);broken.meetings[0].sewing_resume_finished=true;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.sessions.values()[0].source_position.__vector3[0]+=1;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.sessions.values()[0].source_approach.__vector3[2]+=.1;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.objects.sewing_needle.pitch=0.0;cases.append(broken)
	broken=saved.duplicate(true);broken.meetings[0].project="invalid nested record";cases.append(broken)
	broken=saved.duplicate(true);broken.meetings[0].project=[];cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.serial=1e100;cases.append(broken)
	broken=saved.duplicate(true);broken.people[0].age=1e100;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.objects.sewing_cloth_06.ordinal=1e100;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.objects.sewing_cloth_06.cut_minutes=1e100;cases.append(broken)
	broken=saved.duplicate(true);broken.sewing.sessions.values()[0].started=1e100;cases.append(broken)
	broken=saved.duplicate(true);var old_key: String=broken.sewing.sessions.keys()[0];var bad_session: Dictionary=broken.sewing.sessions[old_key];broken.sewing.sessions.erase(old_key);bad_session.id="sewing_9999999999999999999999999";broken.sewing.sessions[bad_session.id]=bad_session;cases.append(broken)
	var refused: bool=true;var before_refusal: Dictionary=packet()
	for invalid in cases: refused=not SewingWork.valid_save(invalid.sewing,invalid,town.definitions) and refused
	expect(refused and packet()==before_refusal,"Malformed holders, work clocks, missing materials and overflowing IDs are rejected without mutating the live world")
	# The configured finite supply does not silently replenish after completion.
	reset()
	var six_completed: bool=true
	for ordinal in 6:
		var crafted: Dictionary=begin()
		six_completed=not crafted.is_empty() and finish() and six_completed
	expect(six_completed and town.work_family.charges==6 and town.work_family.results==6 and sewing.objects.size()==9,"All six original materials can become six owned pouches without creating extra IDs")
	expect(not sewing.available(town.person("first"),town.person("second")) and valid(),"After the finite cloth is exhausted, displayed pouches remain and a new recipe cannot consume imaginary stock")
	# Existing ownership takes precedence over assigning a different learner.
	reset();begin();until("cut","operate");interrupt()
	var owner_item_id: String="sewing_cloth_06"
	var changed_learner: Dictionary={"key":"craft","learner":"second","cost":1.0}
	var before_query: Dictionary=packet()
	var picked: Dictionary=sewing.selection(town.person("first"),town.person("second"),changed_learner)
	expect(picked.maker=="first" and picked.id==owner_item_id and picked.remaining_cost==0 and sewing.material_cost(town.person("first"),town.person("second"),changed_learner)==0,"An owned unfinished piece is selected at zero new material cost even when the proposed learner changes")
	picked.item.position=Vector3(99,99,99);picked.item.cut_minutes=1e100
	expect(packet()==before_query,"Selection and cost queries expose a copy without changing stock, ownership, clock or money")
	var invalid_person: Dictionary=town.person("first").duplicate(true);invalid_person.age=1e100
	expect(sewing.selection(invalid_person,town.person("second"),changed_learner).is_empty() and packet()==before_query,"A query rejects an overflowing age before conversion and cannot mutate live state through the copied inputs")
	meeting=begin("first","second","second")
	expect(not meeting.is_empty() and sewing.active_session().maker=="first" and sewing.active_session().object_id==owner_item_id and meeting.materials_ready,"Admission and begin use the same owner-preserving selection")
	# With all raw stock consumed, the remaining owned item still resumes.
	reset()
	for ordinal in 5: begin();finish()
	begin();until("cut","operate");interrupt()
	picked=sewing.selection(town.person("first"),town.person("second"),changed_learner)
	expect(picked.maker=="first" and picked.id=="sewing_cloth_01" and picked.remaining_cost==0 and sewing.available(town.person("first"),town.person("second"),changed_learner),"Exhausted new cloth does not prevent resuming an existing owner's item with another learner")
	var charged_before_resume: int=town.work_family.charges
	meeting=begin("first","second","second")
	expect(not meeting.is_empty() and finish() and town.work_family.charges==charged_before_resume and valid(),"The selected exhausted-stock item completes without purchasing replacement material")
	# If each person owns unfinished work, learner then party order is deterministic.
	reset()
	for setting in [["sewing_cloth_06","first"],["sewing_cloth_05","second"]]:
		var owned: Dictionary=sewing.objects[setting[0]];owned.owner=setting[1];owned.material_used=true;owned.cut_minutes=1;owned.stage="cut";owned.container="sewing_storage"
	picked=sewing.selection(town.person("first"),town.person("second"),changed_learner)
	expect(picked.maker=="second" and picked.id=="sewing_cloth_05" and sewing.selection(town.person("first"),town.person("second")).maker=="first","Two owners choose their own unfinished work in a stable learner-then-party order")
	# Either maker side uses the scissors' actual cutting point on the cloth.
	for maker in ["first","second"]:
		reset();begin("first","second",maker);until("cut","operate")
		var scissors: Dictionary=sewing.objects.sewing_scissors
		var actual_cut_point: Vector3=scissors.position+Basis(Vector3.UP,float(scissors.yaw))*Vector3(0,.008,-.055)
		var cloth_point: Vector3=sewing.config.target_position+Vector3(0,.006,.075)
		expect(actual_cut_point.distance_to(cloth_point)<.0026 and (scissors.yaw<0 if maker=="first" else scissors.yaw>0),"The %s-side maker brings the real scissors cutting marker to the cloth"%maker)
		until("sew","reach")
		expect(is_equal_approx(sewing.objects.sewing_needle.pitch,PI*.5),"The unused needle lies on the table at the start of pickup")
		until("sew","operate")
		expect(is_zero_approx(sewing.objects.sewing_needle.pitch) and sewing.objects.sewing_needle.holder==maker and valid(),"The actual needle operator holds it upright only after pickup")
	# The prop's local left/right grips keep their orientation relative to the
	# carrier, including the turn toward the viewer during the display.
	reset();begin();until("carry_to_table");step()
	var carrying: Dictionary=sewing.active_session()
	var carried_item: Dictionary=sewing.objects[carrying.object_id]
	expect(absf(wrapf(float(carried_item.yaw)-float(carrying.carry_yaw)-PI,-PI,PI))<.0001,"A carried item's yaw remains PI from the carrier heading, preserving its left/right grip sides")
	until("show")
	var showing: Dictionary=sewing.active_session()
	var shown_item: Dictionary=sewing.objects[showing.object_id]
	expect(absf(wrapf(float(shown_item.yaw)-float(showing.show_yaw)-PI,-PI,PI))<.0001,"Turning to show the pouch preserves the same prop-to-body yaw and hand assignment")
	# Fractional drawing advances neither tool ownership nor the recipe clock.
	reset();begin();until("cut","reach")
	for ignored in 3: step()
	var tool_at_tick: Dictionary=sewing.pose_for("first")
	town.minute_remainder=.5
	var visual_world: Dictionary=packet()
	var half_tool: Dictionary=sewing.pose_for("first")
	for ignored in 8: sewing.pose_for("first");sewing.pose_for("second")
	expect(half_tool.tool_progress>tool_at_tick.tool_progress and half_tool.tools.scissors.position.distance_to(tool_at_tick.tools.scissors.position)>.001 and half_tool.tools.scissors.holder==tool_at_tick.tools.scissors.holder,"A half-minute draws a smooth tool lift while retaining the tick-owned holder")
	expect(packet()==visual_world and town.work_family.charges==0,"Repeated fractional tool reads do not consume cloth, charge money, move the world or advance time")
	var visual_packet: Dictionary=JSON.parse_string(JSON.stringify(packet()))
	var restored_town: Town=Town.new();restored_town.people=decode(visual_packet.people);restored_town.meetings=decode(visual_packet.meetings)
	restored_town.elapsed=int(visual_packet.elapsed);restored_town.minute_remainder=float(visual_packet.remainder)
	var restored_sewing: SewingWork=SewingWork.new(restored_town);restored_sewing.restore(decode(visual_packet.sewing))
	expect(equivalent(encode(restored_sewing.pose_for("first")),encode(half_tool)),"Restoring the fractional town clock reproduces the same drawn tool phase")
	half_tool.tools.scissors.position=Vector3(99,99,99)
	expect(packet()==visual_world,"Changing a returned visual tool copy cannot move the authoritative tool")
	reset();begin();until("cut","operate")
	var work_at_tick: Dictionary=sewing.pose_for("first")
	town.minute_remainder=.5;visual_world=packet()
	var half_work: Dictionary=sewing.pose_for("first")
	expect(is_equal_approx(half_work.stage_progress-work_at_tick.stage_progress,.5/12.0) and half_work.tool_progress>work_at_tick.tool_progress,"Only the drawn cutting progress includes the fractional next work minute")
	for ignored in 8: sewing.pose_for("first")
	expect(packet()==visual_world and town.work_family.charges==1,"Fractional cutting reads cannot apply another logical work minute or fee")
	# Underage participants never become the operator of sharp shared tools.
	reset();town.person("first").age=9;town.person("second").age=10
	expect(not sewing.available(town.person("first"),town.person("second")) and begin().is_empty(),"Two participants below the maker age cannot begin tool work")
	reset();town.person("first").age=9;meeting=begin("first","second","first")
	expect(not meeting.is_empty() and sewing.active_session().maker=="second","A younger learner can participate while the eligible adult operates the tools")
	print("Sewing work checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

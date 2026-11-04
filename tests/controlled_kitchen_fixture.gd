extends RefCounted

# Explicit state-boundary fixture, NOT a skin, collision, animation or natural
# navigation test. Source slots here are authored test geometry contracts.
static func plan_with_metadata(source: Dictionary) -> Dictionary:
	var plan: Dictionary=source.duplicate(true);var fixtures := {}
	for item in plan.fixtures:fixtures[item.id]=item
	var prep: Dictionary=fixtures.prep;var fridge: Dictionary=fixtures.fridge;var table: Dictionary=fixtures.dining_table
	for fixture in [prep,fridge,table]:
		if not fixture.has("operation_targets"):fixture.operation_targets={}
	prep.operation_targets.knife_home={"surface":[2.55,.85,4],"approach":[2.55,0,4.6],"half_extents":[.08,0,.18],"kind":"real_worktop"}
	prep.operation_targets.spatula_home={"surface":[2.46,.85,4],"approach":[2.46,0,4.6],"half_extents":[.08,0,.18],"kind":"real_worktop"}
	prep.operation_targets.dishes={"surface":[3.6,.98,3.8],"approach":[3.6,0,4.6],"half_extents":[.3,0,.2],"kind":"controlled_vertical_rack","unit_frames":[]}
	for i in 6:prep.operation_targets.dishes.unit_frames.append({"position":[3.5+i*.035,.98,3.8],"rotation_degrees":[90,0,0]})
	fridge.operation_targets.basket={"surface":[.7,.8,4.05],"approach":[.7,0,4.7],"half_extents":[.3,0,.2],"kind":"controlled_drawer_shelf","moving_support":"fridge:drawer","open_offset":[0,0,.55]}
	table.operation_targets.carrier={"surface":[3.1,.74,6.15],"approach":[3.1,0,5.4],"half_extents":[.28,0,.2],"kind":"real_tabletop"}
	for i in 3:
		var points: Array=[[2.055,.74,6.4],[3.345,.74,6.4],[2.7,.74,6.715]]
		var approaches: Array=[[1.55,0,6.0],[3.85,0,6.0],[2.2,0,7.2]]
		table.operation_targets["plate_"+str(i)]={"surface":points[i],"approach":approaches[i],"half_extents":[.1,0,.1],"kind":"real_tabletop"}
	plan.household_access={"fridge:drawer":{"fixture":"fridge","approach_closed":[.7,0,4.7],"approach_open":[.7,0,5.25],"open_offset":[0,0,.55]}}
	plan.household_equipment=[
		{"id":"controlled:basket","kind":"basket","role":"ingredient_carrier","support_slot":"fridge:basket","initially_loaded":true},
		{"id":"controlled:tray","kind":"tray","role":"serving_carrier","support_slot":"dining_table:carrier"},
		{"id":"controlled:knife","kind":"knife","role":"preparation_tool","support_slot":"prep:knife_home"},
		{"id":"controlled:spatula","kind":"spatula","role":"cooking_tool","support_slot":"prep:spatula_home"}]
	return plan

static func step(day: HouseholdDay, actor: String) -> Dictionary:
	var task: Dictionary=day.task_for(actor)
	if task.is_empty():return {"status":"invalid","reason":"no task"}
	var operation: Dictionary=day.next_operation(actor,task.id)
	if operation.get("status")!="ready":return operation
	match str(operation.kind):
		"access":
			day.set_position(actor,operation.approach_open if float(operation.target)>0 else operation.approach_closed)
			return {"status":"progress" if day.set_access(actor,task.id,operation.access_id,operation.target) else "invalid","reason":"controlled drawer endpoint"}
		"transfer":
			if str(operation.transfer_id).is_empty():
				if not operation.already_held:day.set_position(actor,operation.source.approach)
				return day.begin_transfer(actor,task.id,operation.item_id,operation.target.id)
			if operation.transfer_state=="prepared":
				day.set_position(actor,operation.source.approach)
				return day.commit_grasp(actor,task.id,operation.transfer_id,operation.object.frame)
			day.set_position(actor,operation.target.approach)
			var object_frame: Transform3D=operation.target.object_frame
			if not day.update_held_frame(actor,task.id,operation.item_id,object_frame):return {"status":"invalid","reason":"controlled carried frame"}
			return day.commit_release(actor,task.id,operation.transfer_id,object_frame)
		"recipe":
			day.set_position(actor,operation.target.approach)
			if operation.operation=="pour":
				var frame := Transform3D(Basis(Vector3.RIGHT,-PI/3),Vector3.ZERO)
				frame.origin=operation.container_target.frame.origin-frame.basis*Vector3(0,.23,-.155)
				day.update_held_frame(actor,task.id,operation.carrier_id,frame)
				var unit: Dictionary=day.kitchen.object_descriptor(operation.item_id)
				var start: Transform3D=unit.frame
				var previous: float=float(unit.pour_progress)
				if unit.state=="basket" and not day.update_pour_unit(actor,task.id,operation.unit_index,start,0):return {"status":"invalid","reason":"controlled continuous pour start"}
				for i in range(1,5):
					var fraction: float=float(i)/4
					var progress: float=lerpf(previous,1,fraction)
					var actual: Transform3D=start.interpolate_with(operation.target.object_frame,fraction)
					if not day.update_pour_unit(actor,task.id,operation.unit_index,actual,progress):return {"status":"invalid","reason":"controlled pour sample"}
			return day.commit_recipe_step(actor,task.id,operation.operation,operation.target.frame,operation.unit_index)
		"work":
			day.set_position(actor,operation.target.approach)
			if not day.set_physical_work(actor,task.id,true):return {"status":"invalid","reason":"controlled work prerequisites"}
			var minutes: float=operation.work_minutes
			day.advance_time(minutes)
			if not day.set_physical_work(actor,task.id,true):return {"status":"invalid","reason":"controlled current-time gate"}
			return day.perform(actor,task.id,minutes)
		"finish":return day.finish(actor,task.id)
	return {"status":"invalid","reason":"unknown controlled operation"}

static func phase(day: HouseholdDay, actor: String) -> Dictionary:
	var first: Dictionary=day.task_for(actor)
	for ignored in 150:
		var reply := step(day,actor)
		if reply.status in ["invalid","unavailable","waiting_physical","not_ready","not_supported","not_arrived","occupied"]:return reply
		var current: Dictionary=day.task_for(actor)
		if reply.status=="completed" or current.is_empty() or current.phase_index!=first.phase_index:return reply
	return {"status":"invalid","reason":"controlled operation limit"}

static func complete(day: HouseholdDay, actor: String) -> Dictionary:
	for ignored in 10:
		var reply := phase(day,actor)
		if reply.status!="next_phase":return reply
	return {"status":"invalid","reason":"controlled phase limit"}

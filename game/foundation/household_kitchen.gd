class_name HouseholdKitchen
extends RefCounted

# Physical-state transactions only. HouseholdDay.jobs[*].quantity is the sole
# in-progress material count. This class never advances a clock or poses skin.
# The production executor must observe a fresh HouseholdPose contact sample
# before committing a grasp, release or recipe step. Controlled tests call these
# state boundaries explicitly; doing so is not proof of a real hand contact.
const TOOLS = preload("res://game/foundation/household_tools.gd")
const FOOD = preload("res://game/foundation/household_food.gd")
const INGREDIENT_KINDS := ["carrot","potato","cabbage"]
const ROLES := {"ingredient_carrier":"basket","serving_carrier":"tray","preparation_tool":"knife","cooking_tool":"spatula"}
const COOKING := ["cook","serve"]
const TRANSACTIONS := ["prepared","grasped","released"]
const PLATE_PROFILE := [Vector2(0,.006),Vector2(.064,.006),Vector2(.095,.018),Vector2(.095,.012),Vector2(.063,0),Vector2(0,0)]
const PAN_PROFILE := [Vector2(0,.012),Vector2(.125,.012),Vector2(.153,.13),Vector2(.160,.13),Vector2(.140,0),Vector2(0,0)]
const PAN_FOOD_XZ := [Vector2(-.060,0),Vector2(.035,-.035),Vector2(.035,.045)]
var _day_ref: WeakRef
var day:
	get:return _day_ref.get_ref() if _day_ref!=null else null
var equipment: Dictionary = {}
var _roles: Dictionary = {}
var _initial: Dictionary = {}
var _ready: Dictionary = {}
var access: Dictionary = {}
var _access_defs: Dictionary = {}

func _init(household = null) -> void:
	if household!=null:_day_ref=weakref(household)

func configure() -> bool:
	equipment.clear();_roles.clear();_initial.clear();_ready.clear();access.clear();_access_defs.clear()
	var doors: Variant=day.plan.get("household_access",{})
	if not doors is Dictionary:return false
	for key in doors:
		var entry: Variant=doors[key]
		if not key is String or not entry is Dictionary or not day._fixtures.has(entry.get("fixture")) or not _point_array(entry.get("approach_closed")) or not _point_array(entry.get("approach_open")) or not _point_array(entry.get("open_offset")):return false
		_access_defs[key]=entry.duplicate(true);access[key]=0.0
	var authored: Variant=day.plan.get("household_equipment",[])
	if not authored is Array:return false
	for raw in authored:
		if not raw is Dictionary or not raw.get("id") is String or raw.id.is_empty() or equipment.has(raw.id):return false
		var role: String=raw.get("role","")
		if not ROLES.has(role) or _roles.has(role) or (raw.get("kind")!=ROLES[role] and not (role=="cooking_tool" and raw.get("kind")=="ladle")) or not raw.get("support_slot") is String:return false
		var target := slot(raw.support_slot)
		if target.is_empty() or not target.set_down:return false
		var frame: Transform3D=target.frame
		if raw.kind in TOOLS.kinds():frame=TOOLS.park_on(raw.kind,frame)
		var item := {"id":raw.id,"kind":raw.kind,"role":role,"home_slot":raw.support_slot,"support_slot":raw.support_slot,
			"frame":frame,"holder":"","container":target.fixture,"last_fixture":target.fixture,"reserved_by":"","hands":["L","R"] if raw.kind in ["basket","tray"] else ["R"],"stock_loaded":bool(raw.get("initially_loaded",false)) if role=="ingredient_carrier" else false}
		equipment[raw.id]=item;_roles[role]=raw.id
	_initial=equipment.duplicate(true)
	return true

func supports(task: Dictionary) -> bool:
	return task.get("kind") in COOKING or task.get("kind")=="put_down" and not task.get("physical",{}).get("equipment_id","").is_empty()

func role_id(role: String) -> String:return str(_roles.get(role,""))

func held(actor: String) -> String:
	for id in equipment:
		if equipment[id].holder==actor:return str(id)
	return ""

func physical_for(actor: String, kind: String) -> Dictionary:
	if kind in COOKING:return {"equipment_id":"","transfer":{},"step_serial":0,"shared_started":false}
	if kind=="put_down" and not held(actor).is_empty():return {"equipment_id":held(actor),"transfer":{},"step_serial":0,"shared_started":false}
	return {}

func requirement(actor: String, kind: String) -> String:
	if kind not in COOKING:return ""
	for task in day.tasks.values():
		if task.actor!=actor and task.kind in COOKING and task.status not in day.TERMINAL and task.get("physical",{}).get("shared_started",false):return "ほかの人が台所の実作業を進めている"
	for role in ROLES:
		if not _roles.has(role):return "料理の実物・置き場所がまだ定義されていない"
		var item: Dictionary=equipment[_roles[role]]
		if not item.holder.is_empty() and item.holder!=actor:return "別の人が料理の道具を持っている"
	if kind=="cook" and not day.jobs.has("cook") and not equipment[role_id("ingredient_carrier")].stock_loaded:return "空の材料容器を実際に補充する工程はまだ実装されていない"
	if slot("prep:carrier").is_empty() or slot("prep:work").is_empty() or slot("stove:stir").is_empty() or slot("stove:pour").is_empty() or slot("dining_table:carrier").is_empty():return "料理の実作業面がまだ定義されていない"
	if kind=="serve":
		if slot("prep:dishes").is_empty():return "器を取り出す実ラックがまだない"
		for i in int(day.inventory.clean_dishes):
			if dish_frame(i)==Transform3D.IDENTITY:return "清潔な器の実ラック位置が足りない"
		for i in int(day.rules.recipe_servings):
			if slot("dining_table:plate_"+str(i)).is_empty():return "配膳する実位置がまだない"
	return ""

func next_operation(actor: String, task_id: String) -> Dictionary:
	var task := _task(actor,task_id)
	if task.is_empty():return _reply("invalid","進行中の本人の料理ではない")
	if not task.pending_cancel_reason.is_empty():
		var ingredient_id: String=_held_ingredient(actor)
		if not ingredient_id.is_empty():
			var ingredient: Dictionary=_ingredient(ingredient_id)
			return _move(task,ingredient_id,"equipment:"+role_id("ingredient_carrier") if ingredient.state=="basket" else "prep:work")
		for unit in day.jobs.get(task.job_key,{}).get("units",[]):
			if unit.state=="pouring":return _pour_operation(task,unit)
		var plate_id: String=_held_plate(actor)
		if not plate_id.is_empty():
			var plate: Dictionary=_plate(plate_id)
			return _move(task,plate_id,"prep:dishes" if plate.state=="empty" else "prep:carrier" if int(task.phase_index)==0 else "dining_table:carrier")
	if task.kind=="put_down":
		if equipment[task.physical.equipment_id].holder.is_empty():return {"status":"ready","kind":"finish"}
		var safe := safe_slot(actor,task.physical.equipment_id)
		return _move(task,task.physical.equipment_id,safe.get("id",""))
	var reason: String=requirement(actor,task.kind)
	if not reason.is_empty():return _reply("waiting_physical",reason)
	var basket: Dictionary=equipment[role_id("ingredient_carrier")]
	var tray: Dictionary=equipment[role_id("serving_carrier")]
	var knife: Dictionary=equipment[role_id("preparation_tool")]
	var spatula: Dictionary=equipment[role_id("cooking_tool")]
	var job: Dictionary=day.jobs.get(task.job_key,{})
	var worked: bool=float(task.phase_progress)>=float(task.phase_minutes)-.000001
	if task.kind=="cook":
		match int(task.phase_index):
			0:
				if job.is_empty():return _move(task,basket.id,"prep:carrier")
				if job.holder!=actor:return _move(task,basket.id,"prep:carrier")
				if worked:return {"status":"ready","kind":"finish"}
				return _work(task,"source",basket.id)
			1:
				if basket.support_slot=="prep:carrier" and float(access.get("fridge:drawer",0))>0:return access_descriptor("fridge:drawer",0)
				if basket.support_slot!="prep:carrier":return _move(task,basket.id,"prep:carrier")
				if not worked:
					for unit in job.units:
						if unit.state!="board" or not unit.holder.is_empty():return _move(task,unit.id,"prep:work")
					if knife.holder!=actor:return _move(task,knife.id,knife.home_slot)
					return _work(task,"prep:work",knife.id)
				if knife.holder==actor:return _move(task,knife.id,knife.home_slot)
				for unit in job.units:
					if unit.state!="basket" or not unit.holder.is_empty():return _move(task,unit.id,"equipment:"+basket.id)
				return {"status":"ready","kind":"finish"}
			2:
				if not _units_at(job,"pan"):
					if basket.holder!=actor:return _move(task,basket.id,basket.home_slot)
					for unit in job.units:
						if unit.state!="pan":return _pour_operation(task,unit)
				if basket.support_slot!=basket.home_slot:return _move(task,basket.id,basket.home_slot)
				if float(access.get("fridge:drawer",0))>0:return access_descriptor("fridge:drawer",0)
				if not worked:
					if spatula.holder!=actor:return _move(task,spatula.id,spatula.home_slot)
					return _work(task,"stove:stir",spatula.id)
				if spatula.holder==actor:return _move(task,spatula.id,spatula.home_slot)
				return {"status":"ready","kind":"finish"}
	else:
		if int(task.phase_index)==0:
			if tray.support_slot!="prep:carrier":return _move(task,tray.id,"prep:carrier")
			if job.is_empty() or not worked:
				if spatula.holder!=actor:return _move(task,spatula.id,spatula.home_slot)
				return _work(task,"stove:stir",spatula.id)
			if int(job.loaded_units)<int(job.quantity) and spatula.holder!=actor:return _move(task,spatula.id,spatula.home_slot)
			for plate in job.plates:
				if plate.state=="on_tray":continue
				if plate.holder!=actor:return _move(task,plate.id,"prep:carrier")
				if plate.state=="empty":return _recipe(task,"plate_one",int(plate.unit_index))
				return _move(task,plate.id,"prep:carrier")
			if spatula.holder==actor:return _move(task,spatula.id,spatula.home_slot)
			return {"status":"ready","kind":"finish"}
		if tray.support_slot!="dining_table:carrier":return _move(task,tray.id,"dining_table:carrier")
		for plate in job.plates:
			if plate.state!="on_table":return _move(task,plate.id,"dining_table:plate_"+str(int(plate.unit_index)))
		return {"status":"ready","kind":"finish"}
	return _reply("waiting_physical","定義済みの実工程を確認する")

func _move(task: Dictionary, item_id: String, target_slot: String) -> Dictionary:
	var result := transfer_descriptor(task.actor,task.id,item_id,target_slot)
	if result.status!="ready":return result
	for support in [result.source,result.target]:
		var key: String=str(support.get("moving_support",""))
		if not key.is_empty() and float(access.get(key,0))<.99999:return access_descriptor(key,1)
	result.kind="transfer";result.item_id=item_id;result.hands=result.object.hands.duplicate()
	var tx: Dictionary=task.physical.transfer
	result.transfer_id=tx.get("id","") if tx.get("item_id")==item_id and tx.get("state")!="released" else ""
	result.transfer_state=tx.get("state","") if not result.transfer_id.is_empty() else ""
	return result

func _work(task: Dictionary, key: String, item_id: String) -> Dictionary:
	var target: Dictionary=slot(key) if key!="source" else slot(equipment[item_id].home_slot)
	if target.is_empty():return _reply("waiting_physical","実際に作業する位置がまだない")
	return {"status":"ready","kind":"work","item_id":item_id,"target":target,"work_minutes":maxf(0,float(task.phase_minutes)-float(task.phase_progress)),"work_kind":"inspect_materials" if key=="source" else "score_food" if task.kind=="cook" and int(task.phase_index)==1 else "stir_food" if task.kind=="cook" else "serve_food"}

func _recipe(task: Dictionary, operation: String, index: int) -> Dictionary:
	var key: String="prep:work" if operation=="unload" else "prep:carrier" if operation=="gather" else "stove:pour"
	var target := slot(key)
	if target.is_empty():return _reply("waiting_physical","材料が到達する実位置がまだない")
	if operation=="gather":target.frame.origin=equipment[role_id("ingredient_carrier")].frame*Vector3(0,.03,0);target.position=target.frame.origin
	return {"status":"ready","kind":"recipe","operation":operation,"unit_index":index,"target":target,"item_id":day.jobs[task.job_key].plates[index].id if operation=="plate_one" else role_id("ingredient_carrier")}

func _pour_operation(task: Dictionary, unit: Dictionary) -> Dictionary:
	var target := _ingredient_target(task,"stove:stir",int(unit.unit_index))
	var container_target := slot("stove:pour")
	if target.is_empty() or container_target.is_empty():return _reply("waiting_physical","材料が実際に入る鍋の支持点がない")
	return {"status":"ready","kind":"recipe","operation":"pour","unit_index":int(unit.unit_index),"item_id":unit.id,"carrier_id":role_id("ingredient_carrier"),
		"source_frame":unit.frame,"target":target,"container_target":container_target,"pour_progress":unit.pour_progress}

func slot(key: String, access_values: Dictionary = {}) -> Dictionary:
	var parts: PackedStringArray=key.split(":",false)
	if parts.size()!=2 or not day._fixtures.has(parts[0]):return {}
	var fixture: Dictionary=day._fixtures[parts[0]]
	var target: Variant=fixture.get("operation_targets",{}).get(parts[1])
	if not target is Dictionary or not _point_array(target.get("surface")):return {}
	var approach: Variant=target.get("approach",fixture.get("interaction_point"))
	if not _point_array(approach):return {}
	var basis: Basis=LivingHouse.fixture_basis(fixture)
	if target.has("rotation_degrees"):
		if not _point_array(target.rotation_degrees):return {}
		basis=basis*Basis.from_euler(day._point(target.rotation_degrees)*PI/180)
	var offset := Vector3.ZERO
	var moving: String=str(target.get("moving_support",""))
	if not moving.is_empty():
		if not _access_defs.has(moving) or not _point_array(target.get("open_offset")):return {}
		var values: Dictionary=access_values if not access_values.is_empty() else access
		offset=day._point(target.open_offset)*float(values.get(moving,0))
		var moving_definition: Dictionary=_access_defs[moving]
		var approach_position: Vector3=day._point(moving_definition.approach_closed).lerp(day._point(moving_definition.approach_open),float(values.get(moving,0)))
		approach=[approach_position.x,approach_position.y,approach_position.z]
	var set_down: bool=str(target.get("kind","")) not in ["pour_into_pan_not_set_down","pan_interior_working_point"] and str(target.get("surface_kind",""))!="saucepan"
	var half := Vector3.ZERO
	var surface_name: String=str(target.get("support_surface",target.get("surface_kind",parts[1]+"_parking")))
	if not fixture.get("support_surfaces",{}).has(surface_name):surface_name=parts[1]+"_parking"
	var surface: Variant=fixture.get("support_surfaces",{}).get(surface_name,{})
	if surface is Dictionary and _point_array(surface.get("half_extents")):half=day._point(surface.half_extents)
	elif _point_array(target.get("half_extents")):half=day._point(target.half_extents)
	# A contact point alone cannot establish a carrier-sized clear support.
	if set_down and (half.x<=0 or half.z<=0):return {}
	return {"id":key,"fixture":parts[0],"room":fixture.room,"operation":parts[1],"frame":Transform3D(basis,day._point(target.surface)+offset),
		"position":day._point(target.surface)+offset,"approach":day._point(approach),"half_extents":half,"set_down":set_down,"moving_support":moving,"kind":str(target.get("kind",target.get("surface_kind","")))}

func safe_slot(actor: String, item_id: String) -> Dictionary:
	if not equipment.has(item_id):return {}
	var item: Dictionary=equipment[item_id]
	var options: Array=[item.home_slot,"prep:carrier","dining_table:carrier"]
	var best: Dictionary={};var distance: float=INF
	for key in options:
		var target := slot(key)
		if target.is_empty() or not target.set_down or not _fits(item.kind,target) or _slot_occupied(key,item_id) or day._status(actor,target.fixture,target.room).status!="ready":continue
		var value: float=day.people[actor].position.distance_squared_to(target.approach)
		if value<distance:distance=value;best=target
	return best

func access_descriptor(key: String, fraction: float) -> Dictionary:
	if not _access_defs.has(key):return _reply("waiting_physical","実際の収納の開閉位置がまだない")
	var definition: Dictionary=_access_defs[key]
	return {"status":"ready","kind":"access","access_id":key,"fraction":float(access[key]),"target":fraction,"fixture":definition.fixture,
		"approach_closed":day._point(definition.approach_closed),"approach_open":day._point(definition.approach_open),"hands":["L","R"]}

func set_access(actor: String, task_id: String, key: String, fraction: float) -> bool:
	var task := _task(actor,task_id)
	if task.is_empty() or not _access_defs.has(key) or not day._number(fraction,0,1) or _hand_conflict(actor,"",["L","R"]):return false
	var definition: Dictionary=_access_defs[key]
	var point: Vector3=day._point(definition.approach_closed).lerp(day._point(definition.approach_open),fraction)
	if day.people[actor].position.distance_to(point)>float(day.rules.arrival_distance):return false
	for other in day.tasks.values():
		var tx: Dictionary=other.get("physical",{}).get("transfer",{})
		if other.status in day.TERMINAL or tx.get("state")!="prepared":continue
		for support_key in [tx.source_slot,tx.target_slot]:
			if slot(support_key).get("moving_support","")==key:return false
	var target := {"fixture":definition.fixture,"room":day._fixtures[definition.fixture].room}
	if not _reserve(actor,target):return false
	var delta: Vector3=day._point(definition.open_offset)*(fraction-float(access[key]))
	access[key]=fraction;task.physical.shared_started=true
	for item in equipment.values():
		if not item.holder.is_empty() or slot(item.support_slot).get("moving_support","")!=key:continue
		item.frame.origin+=delta;_sync_material(item.id)
	_ready.erase(task_id)
	return true

func object_descriptor(item_id: String) -> Dictionary:
	if equipment.has(item_id):return equipment[item_id].duplicate(true)
	return _unit(item_id).duplicate(true)

func transfer_descriptor(actor: String, task_id: String, item_id: String, target_slot: String) -> Dictionary:
	var task := _task(actor,task_id)
	if task.is_empty():return _reply("invalid","本人の料理と実物を指定する")
	if not equipment.has(item_id):return _ingredient_descriptor(task,item_id,target_slot) if not _ingredient(item_id).is_empty() else _plate_descriptor(task,item_id,target_slot)
	var item: Dictionary=equipment[item_id];var target := slot(target_slot)
	if target.is_empty() or not target.set_down or not _fits(item.kind,target):return _reply("unavailable","その物を置ける実支持面がない")
	if item.reserved_by not in ["",actor] or item.holder not in ["",actor]:return _reply("occupied","ほかの人がこの実物を使っている")
	if _slot_occupied(target_slot,item_id):return _reply("occupied","置き場所に別の実物がある")
	target.object_frame=TOOLS.park_on(item.kind,target.frame) if item.kind in TOOLS.kinds() else target.frame
	target.support_point=target.position;target.support_local=TOOLS.spec(item.kind).support_local if item.kind in TOOLS.kinds() else Vector3.ZERO
	var source := slot(item.support_slot) if item.holder.is_empty() else {}
	return {"status":"ready","object":item.duplicate(true),"source":source,"target":target,"already_held":item.holder==actor,"grasp_only":_pickup_only(task,item)}

func _pickup_only(task: Dictionary, item: Dictionary) -> bool:
	if task.kind=="cook" and int(task.phase_index)==0 and item.get("role")=="ingredient_carrier":return true
	if not item.get("holder","").is_empty():return false
	if item.get("role") in ["preparation_tool","cooking_tool"]:return true
	if task.kind=="cook" and int(task.phase_index)==2 and item.get("role")=="ingredient_carrier":
		return not _units_at(day.jobs.get(task.job_key,{}),"pan")
	return task.kind=="serve" and int(task.phase_index)==0 and item.get("kind")=="plate" and item.get("state")=="empty"

func begin_transfer(actor: String, task_id: String, item_id: String, target_slot: String) -> Dictionary:
	var description := transfer_descriptor(actor,task_id,item_id,target_slot)
	if description.status!="ready":return description
	var task := _task(actor,task_id);var item: Dictionary=equipment[item_id] if equipment.has(item_id) else _unit(item_id)
	if task.kind in COOKING:
		var reason: String=requirement(actor,task.kind)
		if not reason.is_empty():return _reply("occupied",reason)
	var old: Dictionary=task.physical.transfer
	var holding_tool_for_plate: bool=not old.is_empty() and old.state=="grasped" and equipment.has(old.item_id) and equipment[old.item_id].role=="cooking_tool" and not equipment.has(item_id)
	if not old.is_empty() and old.state!="released" and not holding_tool_for_plate:return _reply("not_ready","先の取り上げと置き戻しを終える")
	if int(day.people[actor].age)<13:return _reply("unavailable","成人用の調理道具やトレーは大人に任せる")
	if _hand_conflict(actor,item.id,item.hands):return _reply("not_ready","実際に空いている手で持つ")
	var other: String=held(actor)
	var plate_with_tool: bool=not equipment.has(item_id) and other==role_id("cooking_tool")
	if not other.is_empty() and other!=item_id and not plate_with_tool:return _reply("not_ready","先に持っている道具を安全に置く")
	if not _held_plate(actor).is_empty() and _held_plate(actor)!=item_id:return _reply("not_ready","先に持っている器を置く")
	if not _held_ingredient(actor).is_empty() and _held_ingredient(actor)!=item_id:return _reply("not_ready","先に持っている食材を実支持面へ置く")
	var source: Dictionary=description.source
	for support in [source,description.target]:
		var access_key: String=str(support.get("moving_support",""))
		if not access_key.is_empty() and float(access.get(access_key,0))<.99999:return _reply("not_ready","引き出しを実際に開いてから実物へ手を伸ばす")
	if item.holder.is_empty():
		if source.is_empty() or day.people[actor].position.distance_to(source.approach)>float(day.rules.arrival_distance):return _reply("not_arrived","実物のある場所へ先に移動する")
		if not _reserve(actor,source):return _reply("occupied","実物のある設備が使われている")
	item.reserved_by=actor
	task.physical.shared_started=true
	task.physical.step_serial=int(task.physical.step_serial)+1
	task.physical.transfer={"id":task.id+":transfer:"+str(task.physical.step_serial),"item_id":item_id,"state":"grasped" if item.holder==actor else "prepared",
		"source_slot":item.support_slot,"source_frame":item.frame,"target_slot":target_slot,"target_frame":description.target.object_frame,"hands":item.hands.duplicate(),"item_type":"equipment" if equipment.has(item_id) else item.kind,"grasp_only":bool(description.get("grasp_only",false))}
	_ready.erase(task_id)
	return {"status":"ready","transfer":task.physical.transfer.duplicate(true),"object":item.duplicate(true),"target":description.target}

func commit_grasp(actor: String, task_id: String, transfer_id: String, actual_frame: Transform3D) -> Dictionary:
	var task := _task(actor,task_id);var tx := _transfer(task,transfer_id)
	if tx.is_empty() or not _rigid(actual_frame):return _reply("invalid","進行中の実物の取り上げではない")
	var item: Dictionary=equipment[tx.item_id] if tx.item_type=="equipment" else _unit(tx.item_id)
	if tx.state=="grasped":return _reply("grasped","同じ物をすでに持っている")
	if tx.state!="prepared" or item.holder!="" or item.reserved_by!=actor:return _reply("not_ready","元の物が取り上げ待ちではない")
	if _hand_conflict(actor,item.id,item.hands):return _reply("not_ready","ほかの物を持つ手ではつかめない")
	var source := _source_slot(item)
	if source.is_empty() or day.people[actor].position.distance_to(source.approach)>float(day.rules.arrival_distance) or day._claims.get(actor,"")!=source.fixture:return _reply("not_arrived","元の実物の前でつかむ")
	if not _near(actual_frame,item.frame,.03):return _reply("not_ready","取り上げる前に物を動かさない")
	if task.kind=="cook" and int(task.phase_index)==0 and item.role=="ingredient_carrier" and not task.started_effects:
		if int(day.inventory.ingredients)<int(day.rules.recipe_servings):return _reply("unavailable","取り出す食材が足りない")
		day._start_effect(task)
		item.stock_loaded=false
		var job: Dictionary=day.jobs[task.job_key]
		job.carrier_id=item.id;job.material_slot="equipment:"+item.id;job.material_stage="raw";job.loaded_units=0;job.served_units=0
		_create_ingredients(job,item)
	item.frame=actual_frame;item.holder=actor;item.container="";item.support_slot="";tx.state="grasped"
	if tx.item_type=="equipment":_sync_material(item.id)
	elif tx.item_type=="ingredient":day.jobs[task.job_key].reserved_by=actor;_sync_cook_summary(day.jobs[task.job_key])
	return _reply("grasped","実際につかんだ同じ物を持つ")

func update_held_frame(actor: String, task_id: String, item_id: String, actual_frame: Transform3D) -> bool:
	var task := _task(actor,task_id)
	var item: Dictionary=equipment.get(item_id,{}) if equipment.has(item_id) else _unit(item_id)
	if task.is_empty() or item.is_empty() or item.holder!=actor or not _rigid(actual_frame):return false
	if actual_frame.origin.distance_to(day.people[actor].position)>2:return false
	item.frame=actual_frame
	if equipment.has(item_id):_sync_material(item_id)
	elif item.kind=="ingredient":_sync_cook_summary(day.jobs[task.job_key])
	return true

func commit_release(actor: String, task_id: String, transfer_id: String, actual_frame: Transform3D) -> Dictionary:
	var task := _task(actor,task_id);var tx := _transfer(task,transfer_id)
	if tx.is_empty() or not _rigid(actual_frame):return _reply("invalid","進行中の置き戻しではない")
	if tx.state=="released":return _reply("released","同じ物をすでに置いた")
	var item: Dictionary=equipment[tx.item_id] if tx.item_type=="equipment" else _unit(tx.item_id)
	var target: Dictionary=slot(tx.target_slot) if tx.item_type=="equipment" else _ingredient_target(task,tx.target_slot,int(item.unit_index)) if tx.item_type=="ingredient" else _plate_target(task,tx.target_slot,int(item.unit_index))
	if tx.state!="grasped" or item.holder!=actor or target.is_empty() or not target.set_down or tx.item_type=="equipment" and _slot_occupied(target.id,item.id):return _reply("not_ready","持っている物と実際の置き場所を確認する")
	if day.people[actor].position.distance_to(target.approach)>float(day.rules.arrival_distance):return _reply("not_arrived","置く設備の前へ移動する")
	var expected: Transform3D=target.object_frame if tx.item_type=="ingredient" else target.frame
	if item.kind in TOOLS.kinds():expected=TOOLS.park_on(item.kind,expected)
	if not _near(actual_frame,expected,.015) or tx.item_type=="equipment" and not _fits(item.kind,target):return _reply("not_supported","実支持面へ静かに置いてから手を離す")
	if tx.item_type=="plate" and int(task.phase_index)==0 and item.state!="filled" and tx.target_slot!="prep:dishes":return _reply("not_ready","料理を盛ってからトレーへ置く")
	if not _reserve(actor,target):return _reply("occupied","置く設備の使用権が必要")
	item.frame=actual_frame;item.holder="";item.container=target.fixture;item.last_fixture=target.fixture;item.support_slot=target.id;item.reserved_by=""
	tx.state="released"
	if tx.item_type=="equipment":_sync_material(item.id)
	elif tx.item_type=="ingredient":
		item.state="board" if tx.target_slot=="prep:work" else "basket"
		if item.state=="basket":item.container="equipment:"+role_id("ingredient_carrier");item.support_slot=item.container
		_sync_cook_summary(day.jobs[task.job_key])
	else:
		var job: Dictionary=day.jobs[task.job_key]
		if tx.target_slot=="prep:dishes":item.state="empty"
		elif tx.target_slot in ["prep:carrier","dining_table:carrier"]:
			item.state="on_tray"
			if not item.loaded:item.loaded=true;job.loaded_units+=1
		else:item.state="on_table";job.served_units+=1
		if item.state=="on_tray":item.container="equipment:"+job.carrier_id;item.support_slot=item.container
		if int(job.loaded_units)==int(job.quantity):job.material_slot="equipment:"+job.carrier_id;_sync_material(job.carrier_id)
	_ready.erase(task_id)
	if task.kind=="put_down":
		task.phase_progress=task.phase_minutes;task.status="phase_ready"
		for job in day.jobs.values():
			if job.get("carrier_id","")==item.id:job.reserved_by=""
	if not task.pending_cancel_reason.is_empty() and _held_plate(actor).is_empty() and _held_ingredient(actor).is_empty():day._cancel_now(actor,task,task.pending_cancel_reason)
	return _reply("released","実支持面へ同じ物を置いた")

func set_work(actor: String, task_id: String, ready: bool) -> bool:
	_ready.erase(task_id)
	var task := _task(actor,task_id)
	if not ready:return not task.is_empty()
	if task.is_empty() or not work_requirement(task).is_empty():return false
	var operation := next_operation(actor,task_id)
	if operation.get("kind")!="work" or day.people[actor].position.distance_to(operation.target.approach)>float(day.rules.arrival_distance) or not _reserve(actor,operation.target):return false
	if task.status in ["requested","blocked"]:task.status="arrived";task.arrived_at=day.elapsed;task.last_performed_at=day.elapsed
	_ready[task_id]={"elapsed":day.elapsed,"phase":task.phase_index}
	return true

func work_allowed(task: Dictionary) -> bool:
	var gate: Dictionary=_ready.get(task.id,{})
	return gate.get("elapsed",-1)==day.elapsed and gate.get("phase",-1)==task.phase_index and work_requirement(task).is_empty()

func work_requirement(task: Dictionary) -> String:
	if task.kind=="put_down":return "物の接触と置き戻しを待つ"
	var reason: String=requirement(task.actor,task.kind)
	if not reason.is_empty():return reason
	var job: Dictionary=day.jobs.get(task.job_key,{})
	if task.kind=="cook":
		match int(task.phase_index):
			0:
				if job.is_empty() or job.get("material_stage","")!="raw" or equipment[_roles.ingredient_carrier].holder!=task.actor:return "実際に材料を取り出してから進める"
			1:
				if not _units_at(job,"board") or equipment[_roles.preparation_tool].holder!=task.actor:return "すべての食材をまな板へ置き、実際に包丁を持つ"
			2:
				if not _units_at(job,"pan") or equipment[_roles.cooking_tool].holder!=task.actor:return "すべての食材が実際に鍋へ入り、調理道具を持つ"
	elif task.kind=="serve":
		if int(task.phase_index)==0:
			if equipment[_roles.serving_carrier].support_slot!="prep:carrier" or equipment[_roles.cooking_tool].holder!=task.actor:return "実トレーを台へ置き、調理道具で盛り付ける"
		else:
			if job.is_empty() or equipment[_roles.serving_carrier].support_slot!="dining_table:carrier":return "実トレーを食卓へ置いてから配る"
	return ""

func prepare_job(task: Dictionary) -> void:
	if not day.jobs.has(task.job_key):return
	var job: Dictionary=day.jobs[task.job_key]
	if task.kind=="serve" and not job.has("material_slot"):
		job.carrier_id=role_id("serving_carrier");job.material_slot="stove:stir";job.material_stage="cooked";job.loaded_units=0;job.served_units=0
		_set_material_slot(job,"stove:stir")
		job.plates=[]
		for i in int(job.quantity):
			var dish_index: int=int(day.inventory.clean_dishes)+i
			var frame: Transform3D=dish_frame(dish_index)
			job.plates.append({"id":job.batch_id+":plate:"+str(i),"kind":"plate","unit_index":i,"dish_index":dish_index,"hands":["L"],"state":"empty","loaded":false,"frame":frame,"holder":"","container":"prep","last_fixture":"prep","reserved_by":"","support_slot":"prep:dishes"})

func recipe_step(actor: String, task_id: String, operation: String, actual_frame: Transform3D, unit_index: int = -1) -> Dictionary:
	var task := _task(actor,task_id)
	if task.is_empty() or not day.jobs.has(task.job_key) or not _rigid(actual_frame):return _reply("invalid","実際の料理工程と材料が必要")
	var job: Dictionary=day.jobs[task.job_key];var basket: Dictionary=equipment[_roles.ingredient_carrier]
	var target: Dictionary={}
	match operation:
		"unload","gather":return _reply("not_ready","各食材の実際の取り上げと置き戻しが必要")
		"pour":
			if task.kind!="cook" or int(task.phase_index)!=2 or unit_index<0 or unit_index>=int(job.quantity) or basket.holder!=actor:return _reply("not_ready","実際に鍋へ到達した食材を指定する")
			var unit: Dictionary=job.units[unit_index]
			if unit.state=="pan":return _reply("recorded","同じ食材はすでに鍋へ入った")
			target=_ingredient_target(task,"stove:stir",unit_index)
			if unit.state!="pouring" or float(unit.pour_progress)<1 or target.is_empty() or not _near(unit.frame,target.object_frame,.015) or not _near(actual_frame,unit.frame,.00001):return _reply("not_ready","同じ食材の連続した実移動が鍋へ到達してから確定する")
		"plate_one":
			target=slot("stove:pour")
			if task.kind!="serve" or int(task.phase_index)!=0 or unit_index<0 or unit_index>=int(job.quantity) or equipment[_roles.cooking_tool].holder!=actor:return _reply("not_ready","実際に器を持って盛り付ける")
			var plate: Dictionary=job.plates[unit_index]
			if plate.state in ["filled","on_tray","on_table"]:return _reply("recorded","その器にはすでに盛り付けた")
			if plate.holder!=actor:return _reply("not_ready","実在する器を持ってから盛り付ける")
		_:return _reply("invalid","未定義の料理工程")
	if target.is_empty() or day.people[actor].position.distance_to(target.approach)>float(day.rules.arrival_distance) or actual_frame.origin.distance_to(target.position)>.03:return _reply("not_arrived","実際の材料や器が指定の作業位置へ到達していない")
	if not _reserve(actor,target):return _reply("occupied","実際の作業面が使われている")
	match operation:
		"pour":
			var unit: Dictionary=job.units[unit_index]
			unit.state="pan";unit.container="stove";unit.last_fixture="stove";unit.support_slot="stove:stir";unit.reserved_by="";_sync_cook_summary(job)
		"plate_one":job.plates[unit_index].state="filled"
	task.physical.step_serial=int(task.physical.step_serial)+1;_ready.erase(task_id)
	if operation=="pour" and not task.pending_cancel_reason.is_empty():
		var falling: bool=false
		for unit in job.units:
			if unit.state=="pouring":falling=true
		if not falling:day._cancel_now(actor,task,task.pending_cancel_reason)
	return _reply("recorded","成立した実工程を一度進めた")

func update_pour_unit(actor: String, task_id: String, unit_index: int, actual_frame: Transform3D, progress: float) -> bool:
	var task := _task(actor,task_id)
	if task.is_empty() or task.kind!="cook" or int(task.phase_index)!=2 or not day.jobs.has(task.job_key) or not day._number(progress,0,1) or not _rigid(actual_frame):return false
	var job: Dictionary=day.jobs[task.job_key]
	if unit_index<0 or unit_index>=int(job.quantity):return false
	var unit: Dictionary=job.units[unit_index];var basket: Dictionary=equipment[role_id("ingredient_carrier")];var pour := slot("stove:pour")
	if basket.holder!=actor or unit.food_state!="scored" or unit.state not in ["basket","pouring"] or not unit.holder.is_empty() or progress<float(unit.pour_progress):return false
	if basket.frame.basis.y.dot(Vector3.UP)>.8 or (basket.frame*Vector3(0,.23,-.155)).distance_to(pour.position)>.03:return false
	if unit.state=="basket" and (progress!=0 or not _near(actual_frame,unit.frame,.00001)):return false
	var target := _ingredient_target(task,"stove:stir",unit_index)
	if actual_frame.origin.distance_to(pour.position)>1 or progress==1 and not _near(actual_frame,target.object_frame,.015):return false
	unit.frame=actual_frame;unit.state="pouring";unit.pour_progress=progress;unit.container="";unit.support_slot="";unit.reserved_by=actor
	_sync_cook_summary(job)
	return true

func after_work(task: Dictionary) -> void:
	if task.kind!="cook" or not day.jobs.has(task.job_key):return
	var job: Dictionary=day.jobs[task.job_key]
	if int(task.phase_index)==1 and float(task.phase_progress)>=float(task.phase_minutes)-.000001:
		for unit in job.units:unit.food_state="scored"
	_sync_cook_summary(job)

func phase_changed(task: Dictionary) -> void:
	var tx: Dictionary=task.get("physical",{}).get("transfer",{})
	if not tx.is_empty():tx.grasp_only=task.kind=="cook" and int(task.phase_index)==0 and tx.item_type=="equipment" and equipment[tx.item_id].role=="ingredient_carrier"

func contact_complete(task: Dictionary) -> bool:
	# Distribution is a finite contact goal. Three supported plate releases
	# complete it; idle time after the last plate adds no work or need relief.
	if task.get("kind")!="serve" or int(task.get("phase_index",-1))!=1:return false
	var job: Dictionary=day.jobs.get(task.get("job_key",""),{})
	return not job.is_empty() and int(job.get("served_units",-1))==int(job.quantity) and held(task.actor).is_empty() and equipment[role_id("serving_carrier")].support_slot=="dining_table:carrier"

func finish_requirement(task: Dictionary) -> String:
	if task.kind=="put_down":return "" if equipment[task.physical.equipment_id].holder.is_empty() else "実際に物を置いてから終える"
	var job: Dictionary=day.jobs.get(task.job_key,{})
	if job.is_empty():return "実際の材料がまだない"
	if task.kind=="cook":
		if int(task.phase_index)==0 and job.holder!=task.actor:return "取り出した材料を持って次へ進む"
		if int(task.phase_index)==1 and (job.get("material_stage","")!="cut" or not _units_at(job,"basket") or not held(task.actor).is_empty()):return "包丁を返し、切った食材を一つずつ容器へ戻す"
		if int(task.phase_index)==2 and (not _units_at(job,"pan") or not held(task.actor).is_empty()):return "食材が全て鍋へ入り、調理道具を実際に返してから料理を仕上げる"
	else:
		if int(task.phase_index)==0 and (int(job.loaded_units)!=int(job.quantity) or not held(task.actor).is_empty()):return "すべての器を盛り付け、道具を返す"
		if int(task.phase_index)==1 and (int(job.served_units)!=int(job.quantity) or not held(task.actor).is_empty()):return "すべての器を実際に配り終える"
	return ""

func cancel_task(task: Dictionary) -> void:
	_ready.erase(task.id)
	for item in equipment.values():
		if item.reserved_by==task.actor and item.holder.is_empty():item.reserved_by=""

func restore_items(value: Dictionary, saved_access: Dictionary) -> void:
	equipment.clear();equipment.merge(value.duplicate(true));access.clear();access.merge(saved_access.duplicate(true));_ready.clear()

func valid_state(items: Variant, saved: Dictionary) -> bool:
	if not items is Dictionary or items.size()!=_initial.size():return false
	if not saved.get("access") is Dictionary or saved.access.size()!=access.size():return false
	for key in access:
		if not day._number(saved.access.get(key),0,1):return false
	var occupied: Array=[];var holders: Array=[]
	for id in _initial:
		if not items.get(id) is Dictionary:return false
		var item: Dictionary=items[id];var initial: Dictionary=_initial[id]
		for key in ["id","kind","role","home_slot","hands"]:
			if item.get(key)!=initial[key]:return false
		if not _rigid(item.get("frame")):return false
		if not item.get("stock_loaded") is bool or item.role!="ingredient_carrier" and item.stock_loaded:return false
		for key in ["holder","container","last_fixture","reserved_by","support_slot"]:
			if not item.get(key) is String:return false
		if not day._fixtures.has(item.last_fixture) or item.reserved_by not in [""]+saved.people.keys():return false
		if item.holder.is_empty():
			var target := slot(item.support_slot,saved.access)
			if target.is_empty() or not target.set_down or item.container!=target.fixture or item.last_fixture!=target.fixture or item.support_slot in occupied:return false
			var expected: Transform3D=target.frame
			if item.kind in TOOLS.kinds():expected=TOOLS.park_on(item.kind,expected)
			if not _near(item.frame,expected,.015) or not _fits(item.kind,target):return false
			occupied.append(item.support_slot)
		else:
			if not saved.people.has(item.holder) or int(saved.people[item.holder].age)<13 or item.holder in holders or item.reserved_by!=item.holder or not item.container.is_empty() or not item.support_slot.is_empty() or item.frame.origin.distance_to(saved.people[item.holder].position)>2:return false
			holders.append(item.holder)
	for task in saved.tasks.values():
		var physical: Variant=task.get("physical")
		if not physical is Dictionary:return false
		if task.kind not in COOKING and not (task.kind=="put_down" and not physical.is_empty()):
			if not physical.is_empty():return false
			continue
		if not physical.get("equipment_id") is String or not physical.get("transfer") is Dictionary or not physical.get("shared_started") is bool or not day._whole(physical.get("step_serial"),0,100000):return false
		if task.kind=="put_down" and not items.has(physical.equipment_id):return false
		var tx: Dictionary=physical.transfer
		if tx.is_empty():continue
		if not tx.get("id") is String or not tx.id.begins_with(task.id+":transfer:") or not tx.get("item_id") is String or tx.get("item_type") not in ["equipment","plate","ingredient"] or tx.get("state") not in TRANSACTIONS or not tx.get("source_slot") is String or not _rigid(tx.get("source_frame")) or not tx.get("target_slot") is String or not _rigid(tx.get("target_frame")) or not tx.get("hands") is Array or not tx.get("grasp_only") is bool:return false
		if task.status in day.TERMINAL:continue
		var item: Dictionary=items.get(tx.item_id,{}) if tx.item_type=="equipment" else _ingredient_in(saved.jobs,tx.item_id) if tx.item_type=="ingredient" else _plate_in(saved.jobs,tx.item_id)
		if item.is_empty():return false
		if tx.item_type!="equipment" and not day._whole(item.get("unit_index"),0,99):return false
		if tx.hands!=item.hands:return false
		var target: Dictionary=slot(tx.target_slot,saved.access) if tx.item_type=="equipment" else _ingredient_target(task,tx.target_slot,int(item.unit_index),items,item) if tx.item_type=="ingredient" else _plate_target(task,tx.target_slot,int(item.unit_index),items,item)
		if target.is_empty() or not target.set_down:return false
		var object_frame: Transform3D=TOOLS.park_on(item.kind,target.frame) if item.kind in TOOLS.kinds() else target.object_frame if tx.item_type=="ingredient" else target.frame
		if tx.state!="released" and not _near(tx.target_frame,object_frame,.00001):return false
		if tx.state=="prepared" and (item.holder!="" or item.reserved_by!=task.actor or item.support_slot!=tx.source_slot or not _near(item.frame,tx.source_frame,.00001)):return false
		if tx.state=="grasped" and item.holder!=task.actor:return false
		if tx.state=="released" and (not item.holder.is_empty() or tx.item_type=="equipment" and item.support_slot!=tx.target_slot):return false
	var claimed_hands: Dictionary={}
	var all_items: Array=items.values()
	for job in saved.jobs.values():
		if not job is Dictionary:return false
		for field in ["plates","units"]:
			if not job.get(field,[]) is Array:return false
			for unit in job.get(field,[]):
				if not unit is Dictionary or not unit.get("holder") is String or not unit.get("id") is String or unit.get("hands")!=(["L"] if field=="plates" else ["R"]):return false
				all_items.append(unit)
	for item in all_items:
		if item.holder.is_empty():continue
		for side in item.hands:
			var key: String=item.holder+":"+side
			if claimed_hands.has(key):return false
			claimed_hands[key]=item.id
	return true

func _hand_conflict(actor: String, item_id: String, hands: Array) -> bool:
	var all_items: Array=equipment.values()
	for job in day.jobs.values():all_items.append_array(job.get("plates",[]));all_items.append_array(job.get("units",[]))
	for item in all_items:
		if item.id==item_id or item.holder!=actor:continue
		for side in hands:
			if side in item.hands:return true
	return false

func dish_frame(index: int) -> Transform3D:
	var target: Dictionary=day._fixtures.get("prep",{}).get("operation_targets",{}).get("dishes",{})
	var frames: Variant=target.get("unit_frames",[])
	if not frames is Array or index<0 or index>=frames.size() or not frames[index] is Dictionary or not _point_array(frames[index].get("position")) or not _point_array(frames[index].get("rotation_degrees")):return Transform3D.IDENTITY
	return Transform3D(LivingHouse.fixture_basis(day._fixtures.prep)*Basis.from_euler(day._point(frames[index].rotation_degrees)*PI/180),day._point(frames[index].position))

func _plate(item_id: String) -> Dictionary:return _plate_in(day.jobs,item_id)

func _ingredient(item_id: String) -> Dictionary:return _ingredient_in(day.jobs,item_id)

func _unit(item_id: String) -> Dictionary:
	var ingredient := _ingredient(item_id)
	return ingredient if not ingredient.is_empty() else _plate(item_id)

static func ingredient_id(carrier_id: String, index: int) -> String:return "ingredient:"+carrier_id+":"+str(index)

static func ingredient_offset(index: int) -> Vector3:return Vector3((index%3-1)*.11,.03,0)

func _create_ingredients(job: Dictionary, basket: Dictionary) -> void:
	job.units=[]
	for i in int(job.quantity):
		job.units.append({"id":ingredient_id(basket.id,i),"kind":"ingredient","ingredient_kind":INGREDIENT_KINDS[i%INGREDIENT_KINDS.size()],"food_state":"whole","unit_index":i,"hands":["R"],
			"state":"basket","frame":basket.frame*Transform3D(Basis.IDENTITY,ingredient_offset(i)),"holder":"","container":"equipment:"+basket.id,"last_fixture":basket.last_fixture,
			"reserved_by":"","support_slot":"equipment:"+basket.id,"pour_progress":0.0})

static func _ingredient_in(jobs: Dictionary, item_id: String) -> Dictionary:
	for job in jobs.values():
		if not job is Dictionary or not job.get("units",[]) is Array:continue
		for unit in job.get("units",[]):
			if unit is Dictionary and unit.get("id")==item_id:return unit
	return {}

func _held_ingredient(actor: String) -> String:
	for job in day.jobs.values():
		for unit in job.get("units",[]):
			if unit.holder==actor:return str(unit.id)
	return ""

static func _units_at(job: Dictionary, state: String) -> bool:
	if not job.get("units") is Array or job.units.size()!=int(job.quantity):return false
	for unit in job.units:
		if unit.state!=state or not unit.holder.is_empty():return false
	return true

func _ingredient_target(task: Dictionary, key: String, index: int, items: Dictionary = {}, saved_unit: Dictionary = {}) -> Dictionary:
	var unit: Dictionary=saved_unit
	if unit.is_empty() and day.jobs.has(task.job_key) and index>=0 and index<day.jobs[task.job_key].get("units",[]).size():unit=day.jobs[task.job_key].units[index]
	if unit.is_empty() or unit.get("ingredient_kind") not in INGREDIENT_KINDS or unit.get("food_state") not in ["whole","scored"]:return {}
	var states: Dictionary=equipment if items.is_empty() else items
	var basket: Dictionary=states[role_id("ingredient_carrier")]
	var target: Dictionary={};var contact := Transform3D.IDENTITY
	if key=="equipment:"+basket.id:
		if not basket.holder.is_empty():return {}
		target=slot(basket.support_slot)
		if target.is_empty():return {}
		contact=basket.frame*Transform3D(Basis.IDENTITY,ingredient_offset(index))
	elif key=="prep:work":
		target=slot(key)
		if target.is_empty():return {}
		contact=target.frame*Transform3D(Basis.IDENTITY,Vector3((index%3-1)*.11,0,0))
	elif key=="stove:stir":
		target=slot(key)
		if target.is_empty():return {}
		contact=pan_support_frame(index)
	else:return {}
	var frame: Transform3D=contact
	var support_local: Variant=FOOD.support_for(unit.ingredient_kind,unit.food_state,frame.basis)
	if not support_local is Vector3:return {}
	# The authored position is the food ROOT's XZ, while the plane fixes Y.
	# Do not shift its root sideways merely because the lowest actual vertex
	# is away from the root centre (Foodkit.park_on maps that full vertex).
	frame.origin.y-=(frame.basis*support_local).y
	target.id=key;target.set_down=true;target.frame=frame;target.object_frame=frame;target.position=frame.origin
	target.support_local=support_local;target.support_point=frame*support_local
	return target

func _ingredient_descriptor(task: Dictionary, item_id: String, target_slot: String) -> Dictionary:
	var unit := _ingredient(item_id)
	if task.kind!="cook" or int(task.phase_index)!=1 or unit.is_empty() or not day.jobs.has(task.job_key) or unit not in day.jobs[task.job_key].get("units",[]):return _reply("invalid","本人が進める料理の有限食材ではない")
	if unit.state not in ["basket","board"] or unit.holder not in ["",task.actor] or unit.reserved_by not in ["",task.actor]:return _reply("occupied","その食材は移送できる状態ではない")
	var worked: bool=float(task.phase_progress)>=float(task.phase_minutes)-.000001
	var expected: String="equipment:"+role_id("ingredient_carrier") if worked else "prep:work"
	if not task.pending_cancel_reason.is_empty():expected="equipment:"+role_id("ingredient_carrier") if unit.state=="basket" else "prep:work"
	if target_slot!=expected:return _reply("not_ready","この工程の実際の戻し先を指定する")
	var target := _ingredient_target(task,target_slot,int(unit.unit_index))
	if target.is_empty():return _reply("unavailable","食材の実支持面や実形状がまだない")
	return {"status":"ready","object":unit.duplicate(true),"source":_source_slot(unit) if unit.holder.is_empty() else {},"target":target,"already_held":unit.holder==task.actor}

func pan_root_frame() -> Transform3D:
	var fixture: Dictionary=day._fixtures.stove;var size: Vector3=day._point(fixture.size);var basis: Basis=LivingHouse.fixture_basis(fixture)
	return Transform3D(basis,day._point(fixture.support_point)+basis*Vector3(-size.x*.24,.028,-size.z*.05))

func pan_support_frame(index: int) -> Transform3D:
	# OpenPot inner bottom is the actual profile's y=.012m, not the stir point.
	var point: Vector2=PAN_FOOD_XZ[index%PAN_FOOD_XZ.size()]
	return pan_root_frame()*Transform3D(Basis.IDENTITY,Vector3(point.x,.012,point.y))

static func pan_profile() -> Array:return PAN_PROFILE.duplicate()

func _cook_summary(job: Dictionary, items: Dictionary) -> Dictionary:
	var basket: Dictionary=items[job.carrier_id]
	var summary := {"material_slot":"mixed:units","material_stage":"cut","holder":"","container":"prep","last_fixture":"prep","source_fixture":"prep","position":Vector3.ZERO}
	for unit in job.units:
		summary.position+=unit.frame.origin/float(job.quantity)
		if unit.food_state=="whole":summary.material_stage="raw"
	if _units_at(job,"basket"):
		summary.material_slot="equipment:"+job.carrier_id;summary.holder=basket.holder;summary.container=basket.container;summary.last_fixture=basket.last_fixture;summary.source_fixture=basket.last_fixture;summary.position=basket.frame.origin
	elif _units_at(job,"board"):
		summary.material_slot="prep:work";summary.position=slot("prep:work").position
	elif _units_at(job,"pan"):
		summary.material_slot="stove:stir";summary.container="stove";summary.last_fixture="stove";summary.source_fixture="stove";summary.position=slot("stove:stir").position
	elif int(job.phase_index)==2:summary.container="stove";summary.last_fixture="stove";summary.source_fixture="stove"
	return summary

func _sync_cook_summary(job: Dictionary) -> void:
	job.merge(_cook_summary(job,equipment),true)

static func _plate_in(jobs: Dictionary, item_id: String) -> Dictionary:
	for job in jobs.values():
		if not job is Dictionary or not job.get("plates",[]) is Array:continue
		for plate in job.get("plates",[]):
			if plate is Dictionary and plate.get("id")==item_id:return plate
	return {}

func _held_plate(actor: String) -> String:
	for job in day.jobs.values():
		for plate in job.get("plates",[]):
			if plate.holder==actor:return str(plate.id)
	return ""

func _source_slot(item: Dictionary) -> Dictionary:
	var key: String=item.support_slot
	if key.begins_with("equipment:"):
		var carrier: Dictionary=equipment.get(key.trim_prefix("equipment:"),{})
		if carrier.is_empty() or not carrier.holder.is_empty():return {}
		key=carrier.support_slot
	var source := slot(key)
	if source.is_empty():return {}
	source.frame=item.frame
	source.object_frame=item.frame
	source.support_local=FOOD.support_for(item.ingredient_kind,item.food_state,item.frame.basis) if item.kind=="ingredient" else plate_support_local(item.frame) if item.kind=="plate" else TOOLS.spec(item.kind).get("support_local",Vector3.ZERO) if item.kind in TOOLS.kinds() else Vector3.ZERO
	if not source.support_local is Vector3:return {}
	source.support_point=item.frame*source.support_local
	return source

func _plate_target(task: Dictionary, key: String, index: int, items: Dictionary = {}, saved_plate: Dictionary = {}) -> Dictionary:
	var target := slot(key)
	if target.is_empty():return {}
	if not task.get("pending_cancel_reason","").is_empty():
		if key=="prep:dishes":
			var unit: Dictionary=saved_plate if not saved_plate.is_empty() else _plate_in(day.jobs,str(day.jobs.get(task.job_key,{}).get("batch_id",""))+":plate:"+str(index))
			if unit.is_empty():return {}
			target.frame=dish_frame(int(unit.dish_index));target.position=target.frame.origin;return target
		if key=="dining_table:carrier":
			var states: Dictionary=items if not items.is_empty() else equipment
			target.frame=states[role_id("serving_carrier")].frame*Transform3D(Basis.IDENTITY,tray_slot(index));target.position=target.frame.origin;return target
	if int(task.phase_index)==0:
		if key!="prep:carrier":return {}
		var states: Dictionary=items if not items.is_empty() else equipment
		var tray: Dictionary=states[role_id("serving_carrier")]
		if tray.support_slot!="prep:carrier":return {}
		target.frame=tray.frame*Transform3D(Basis.IDENTITY,tray_slot(index));target.position=target.frame.origin
	elif key!="dining_table:plate_"+str(index):return {}
	return target

func _plate_descriptor(task: Dictionary, item_id: String, target_slot: String) -> Dictionary:
	var plate := _plate(item_id)
	if task.kind!="serve" or plate.is_empty() or not day.jobs.has(task.job_key) or plate not in day.jobs[task.job_key].get("plates",[]):return _reply("invalid","本人が進める料理の器ではない")
	var target := _plate_target(task,target_slot,int(plate.unit_index))
	if target.is_empty():return _reply("unavailable","器を置ける実際の位置がまだない")
	target.object_frame=target.frame
	target.support_local=plate_support_local(target.object_frame);target.support_point=target.object_frame*target.support_local
	if plate.holder not in ["",task.actor] or plate.reserved_by not in ["",task.actor]:return _reply("occupied","その器は別の人が持っている")
	if int(task.phase_index)==0 and plate.state not in ["empty","filled"] or int(task.phase_index)==1 and (plate.state!="on_tray" or not plate.loaded):return _reply("not_ready","その器はこの移送の対象ではない")
	return {"status":"ready","object":plate.duplicate(true),"source":_source_slot(plate) if plate.holder.is_empty() else {},"target":target,"already_held":plate.holder==task.actor,"grasp_only":_pickup_only(task,plate)}

func _valid_plates(job: Dictionary, items: Dictionary) -> bool:
	if not job.get("plates") is Array or job.plates.size()!=int(job.quantity):return false
	var loaded: int=0;var served: int=0;var held_by: Array=[]
	for i in job.plates.size():
		var plate: Variant=job.plates[i]
		if not plate is Dictionary or plate.get("id")!=job.batch_id+":plate:"+str(i) or plate.get("kind")!="plate" or plate.get("unit_index")!=i or plate.get("hands")!=["L"] or not day._whole(plate.get("dish_index"),0,99) or plate.get("state") not in ["empty","filled","on_tray","on_table"] or not plate.get("loaded") is bool or not _rigid(plate.get("frame")):return false
		for key in ["holder","container","last_fixture","reserved_by","support_slot"]:
			if not plate.get(key) is String:return false
		if plate.loaded:loaded+=1
		if plate.state=="on_table":served+=1
		if plate.state=="on_tray" and not plate.loaded or plate.state=="on_table" and not plate.loaded or plate.state in ["empty","filled"] and plate.loaded:return false
		if not plate.holder.is_empty():
			if not day.people.has(plate.holder) or plate.holder in held_by or plate.reserved_by!=plate.holder or not plate.container.is_empty() or not plate.support_slot.is_empty():return false
			held_by.append(plate.holder)
		else:
			var target: Dictionary={}
			if plate.state=="empty":
				target=slot("prep:dishes")
				if target.is_empty():return false
				target.frame=dish_frame(int(plate.dish_index))
			elif plate.state=="on_tray":
				var tray: Dictionary=items[role_id("serving_carrier")]
				# A carried tray supports the same actual plates; their independent
				# holder remains empty while the carrier owns the movement.
				if plate.support_slot!="equipment:"+job.carrier_id or plate.container!=plate.support_slot:return false
				target={"frame":tray.frame*Transform3D(Basis.IDENTITY,tray_slot(i)),"fixture":tray.container}
			elif plate.state=="on_table":target=slot("dining_table:plate_"+str(i))
			else:return false
			if target.is_empty() or not _near(plate.frame,target.frame,.015):return false
	return loaded==int(job.loaded_units) and served==int(job.served_units)

static func tray_slot(index: int) -> Vector3:
	# Actual tray Bottom is .018m high; plate bottom must rest on its top.
	var points: Array=[Vector3(-.12,.018,.075),Vector3(.12,.018,.075),Vector3(0,.018,-.105)]
	return points[index%3]+Vector3.UP*floori(index/3.0)*.055

static func plate_profile() -> Array:return PLATE_PROFILE.duplicate()

static func plate_support_local(frame: Transform3D) -> Vector3:
	# Lowest actual lathed rim/profile point for this orientation, not the plate
	# centre. In the vertical Z90 rack this maps to the real .862m cradle rail.
	var planar := Vector2(frame.basis.x.y,frame.basis.z.y)
	var direction: Vector2=-planar.normalized() if planar.length()>.0000001 else Vector2.ZERO
	var lowest: float=INF;var result := Vector3.ZERO
	for ring in PLATE_PROFILE:
		var point := Vector3(direction.x*ring.x,ring.y,direction.y*ring.x)
		var height: float=(frame.basis*point).y
		if height<lowest:lowest=height;result=point
	return result

func valid_job(job: Dictionary, items: Dictionary, _saved: Dictionary) -> bool:
	if not job.get("carrier_id") is String or not items.has(job.carrier_id) or not job.get("material_slot") is String or job.get("material_stage") not in ["raw","cut","cooked"]:return false
	if not day._whole(job.get("loaded_units"),0,float(job.quantity)) or not day._whole(job.get("served_units"),0,float(job.loaded_units)):return false
	if job.kind=="cook" and (job.loaded_units!=0 or job.served_units!=0):return false
	if items[job.carrier_id].role!=("ingredient_carrier" if job.kind=="cook" else "serving_carrier"):return false
	if job.kind=="cook":
		if job.quantity!=day.rules.recipe_servings or job.material_stage=="cooked" or not _valid_ingredients(job,items,_saved):return false
		var expected := _cook_summary(job,items)
		for field in expected:
			if field=="position":
				if job.position.distance_to(expected.position)>.00001:return false
			elif job.get(field)!=expected[field]:return false
		return true
	elif job.material_stage!="cooked" or int(job.phase_index)==1 and job.loaded_units!=job.quantity:return false
	if job.kind=="serve" and not _valid_plates(job,items):return false
	if job.material_slot.begins_with("equipment:"):
		var id: String=job.material_slot.trim_prefix("equipment:")
		if id!=job.carrier_id:return false
		var item: Dictionary=items[id]
		return job.holder==item.holder and job.container==item.container and job.last_fixture==item.last_fixture and job.position.distance_to(item.frame.origin)<.00001
	var target := slot(job.material_slot)
	return not target.is_empty() and job.material_slot in ["prep:work","stove:stir"] and job.holder.is_empty() and job.container==target.fixture and job.last_fixture==target.fixture and job.position.distance_to(target.position)<.00001

func _valid_ingredients(job: Dictionary, items: Dictionary, saved: Dictionary) -> bool:
	if not job.get("units") is Array or job.units.size()!=int(job.quantity):return false
	var basket: Dictionary=items[job.carrier_id]
	var phase: int=int(job.phase_index)
	for i in job.units.size():
		var unit: Variant=job.units[i]
		if not unit is Dictionary or unit.get("id")!=ingredient_id(job.carrier_id,i) or unit.get("kind")!="ingredient" or unit.get("ingredient_kind")!=INGREDIENT_KINDS[i%INGREDIENT_KINDS.size()] or unit.get("food_state") not in ["whole","scored"] or unit.get("unit_index")!=i or unit.get("hands")!=["R"] or unit.get("state") not in ["basket","board","pouring","pan"] or not _rigid(unit.get("frame")) or not day._number(unit.get("pour_progress"),0,1):return false
		for field in ["holder","container","last_fixture","reserved_by","support_slot"]:
			if not unit.get(field) is String:return false
		if not day._fixtures.has(unit.last_fixture) or unit.reserved_by not in [""]+saved.people.keys():return false
		if phase==0 and (unit.state!="basket" or unit.food_state!="whole" or not unit.holder.is_empty()):return false
		if phase==1 and (unit.state not in ["basket","board"] or unit.food_state!=("scored" if float(job.phase_progress)>=float(day.rules.actions.cook.phases[1].minutes)-.000001 else "whole")):return false
		if phase==2 and (unit.state not in ["basket","pouring","pan"] or unit.food_state!="scored"):return false
		if unit.state in ["basket","board"] and unit.pour_progress!=0:return false
		if not unit.holder.is_empty():
			if not saved.people.has(unit.holder) or int(saved.people[unit.holder].age)<13 or unit.reserved_by!=unit.holder or not unit.container.is_empty() or not unit.support_slot.is_empty() or unit.state not in ["basket","board"] or unit.frame.origin.distance_to(saved.people[unit.holder].position)>2:return false
			continue
		if unit.state=="basket":
			if unit.container!="equipment:"+job.carrier_id or unit.support_slot!=unit.container or unit.last_fixture!=basket.last_fixture or not _near(unit.frame,basket.frame*Transform3D(Basis.IDENTITY,ingredient_offset(i)),.00001):return false
		elif unit.state=="pouring":
			if not unit.container.is_empty() or not unit.support_slot.is_empty() or unit.reserved_by.is_empty() or basket.holder!=unit.reserved_by or unit.frame.origin.distance_to(slot("stove:pour").position)>1:return false
			var active_id: String=saved.people[unit.reserved_by].active_task
			if active_id.is_empty() or saved.tasks[active_id].get("job_key")!="cook" or saved.tasks[active_id].status in day.TERMINAL:return false
		else:
			var key: String="prep:work" if unit.state=="board" else "stove:stir"
			var target := _ingredient_target({"job_key":"cook"},key,i,items,unit)
			if target.is_empty() or unit.container!=target.fixture or unit.support_slot!=key or unit.last_fixture!=target.fixture or not _near(unit.frame,target.object_frame,.015):return false
			if unit.state=="pan" and unit.pour_progress!=1:return false
	return true

func _set_material_slot(job: Dictionary, key: String) -> void:
	var target := slot(key)
	job.material_slot=key;job.holder="";job.container=target.fixture;job.last_fixture=target.fixture;job.source_fixture=target.fixture;job.position=target.position

func _sync_material(item_id: String) -> void:
	var item: Dictionary=equipment[item_id]
	for job in day.jobs.values():
		if job.kind=="cook" and job.get("carrier_id","")==item_id and job.has("units"):
			for unit in job.units:
				if unit.state=="basket" and unit.holder.is_empty():unit.frame=item.frame*Transform3D(Basis.IDENTITY,ingredient_offset(int(unit.unit_index)));unit.last_fixture=item.last_fixture
			_sync_cook_summary(job);continue
		if job.get("material_slot","")!="equipment:"+item_id:continue
		job.holder=item.holder;job.container=item.container;job.last_fixture=item.last_fixture;job.source_fixture=item.last_fixture;job.position=item.frame.origin
		if not item.holder.is_empty():job.reserved_by=item.holder
		for plate in job.get("plates",[]):
			if plate.state=="on_tray" and plate.holder.is_empty():plate.frame=item.frame*Transform3D(Basis.IDENTITY,tray_slot(int(plate.unit_index)))

func _reserve(actor: String, target: Dictionary) -> bool:
	if day._status(actor,target.fixture,target.room).status!="ready":return false
	if day.occupancy!=null and day.occupancy.reserve_fixture(target.fixture,actor).status!="ready":return false
	day._claims[actor]=target.fixture
	return true

func _task(actor: String, task_id: String) -> Dictionary:
	var task: Dictionary=day._owned(actor,task_id)
	if day.jobs.has(task.get("job_key","")) and day.jobs[task.job_key].reserved_by not in ["",actor]:return {}
	return task if not task.is_empty() and task.status not in day.TERMINAL and supports(task) else {}

func defer_cancel(task: Dictionary, reason: String) -> bool:
	var ingredient_id: String=_held_ingredient(task.actor)
	if not ingredient_id.is_empty():
		task.pending_cancel_reason=reason
		var unit: Dictionary=_ingredient(ingredient_id);var tx: Dictionary=task.physical.transfer
		var key: String="equipment:"+role_id("ingredient_carrier") if unit.state=="basket" else "prep:work"
		var target := _ingredient_target(task,key,int(unit.unit_index))
		if not target.is_empty() and tx.get("item_id")==ingredient_id:tx.target_slot=key;tx.target_frame=target.object_frame
		_ready.erase(task.id);return true
	for unit in day.jobs.get(task.job_key,{}).get("units",[]):
		if unit.state=="pouring":task.pending_cancel_reason=reason;_ready.erase(task.id);return true
	var plate_id: String=_held_plate(task.actor)
	if plate_id.is_empty():return false
	task.pending_cancel_reason=reason
	var plate: Dictionary=_plate(plate_id);var tx: Dictionary=task.physical.transfer
	if tx.get("item_id")==plate_id and tx.get("state")=="grasped":
		var key: String="prep:dishes" if plate.state=="empty" else "prep:carrier" if int(task.phase_index)==0 else "dining_table:carrier"
		var target := _plate_target(task,key,int(plate.unit_index))
		if not target.is_empty():tx.target_slot=key;tx.target_frame=target.frame
	_ready.erase(task.id)
	return true

func _transfer(task: Dictionary, id: String) -> Dictionary:
	var tx: Dictionary=task.get("physical",{}).get("transfer",{})
	return tx if tx.get("id","")==id and (equipment.has(tx.get("item_id")) or not _unit(str(tx.get("item_id",""))).is_empty()) else {}

func _slot_occupied(key: String, except_id: String) -> bool:
	for item in equipment.values():
		if item.id!=except_id and item.support_slot==key:return true
	return false

static func _fits(kind: String, target: Dictionary) -> bool:
	var size := Vector2(.28,.20) if kind=="tray" else Vector2(.21,.155) if kind=="basket" else Vector2(.025,.17)
	return target.half_extents.x+.00001>=size.x and target.half_extents.z+.00001>=size.y

static func _point_array(value: Variant) -> bool:
	if not value is Array or value.size()!=3:return false
	for n in value:
		if not (n is int or n is float) or not is_finite(float(n)) or absf(float(n))>1000:return false
	return true

static func _rigid(value: Variant) -> bool:
	return value is Transform3D and value.is_finite() and value.origin.length()<1000 and absf(value.basis.determinant()-1)<.001 and absf(value.basis.x.length()-1)<.001 and absf(value.basis.y.length()-1)<.001 and absf(value.basis.z.length()-1)<.001 and absf(value.basis.x.dot(value.basis.y))<.001 and absf(value.basis.x.dot(value.basis.z))<.001 and absf(value.basis.y.dot(value.basis.z))<.001

static func _near(a: Transform3D, b: Transform3D, distance: float) -> bool:
	return a.origin.distance_to(b.origin)<=distance and a.basis.x.distance_to(b.basis.x)<.02 and a.basis.y.distance_to(b.basis.y)<.02 and a.basis.z.distance_to(b.basis.z)<.02

static func _reply(status: String, reason: String) -> Dictionary:return {"status":status,"reason":reason}

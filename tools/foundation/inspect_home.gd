extends SceneTree

const OUT := "res://builds/foundation-home"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size=Vector2i(1440,1000)
	var preview=load("res://game/foundation/house_preview.tscn").instantiate()
	root.add_child(preview)
	for ignored in 5: await process_frame
	var house: LivingHouse=preview.house
	var report: Dictionary={"scope":"Design-review prototype generated from one house plan; not a playable family day or accepted quality milestone.","rooms":house.rooms.keys(),"fixtures":house.fixtures.keys(),"doors":{},"artifacts":[],"errors":[]}
	for id in house.doors:
		var door: Dictionary=house.doors[id]
		report.doors[id]={"kind":door.definition.kind,"opened":door.opened,"has_panel":is_instance_valid(door.panel)}
		if door.definition.kind=="opening" and is_instance_valid(door.panel): report.errors.append("A plain opening has a blocking panel: "+id)
	DirAccess.make_dir_recursive_absolute(OUT)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var path: String=OUT+"/home-overview.png"
		var written: bool=root.get_texture().get_image().save_png(path)==OK
		report.artifacts.append({"path":path,"written":written})
	for id in house.doors:
		if house.doors[id].definition.kind!="opening": house.set_door_open(id,true)
	for ignored in 3:await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var path: String=OUT+"/home-doors-open.png"
		report.artifacts.append({"path":path,"written":root.get_texture().get_image().save_png(path)==OK})
	for id in house.fixtures:
		var fixture: Dictionary=house.fixtures[id]
		if not is_instance_valid(fixture.node) or not is_instance_valid(fixture.anchor): report.errors.append("Missing actual fixture/use point "+id)
	FileAccess.open(OUT+"/inspection.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Home spatial prototype inspection: "+str(report.errors))
	preview.free();quit(0 if report.errors.is_empty() else 1)

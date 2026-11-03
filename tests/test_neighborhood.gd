extends SceneTree

var main: Node3D
var sim: LifeSimulation
var checks := 0
var errors: Array[String] = []
var metrics: Dictionary = {}
const OUT := "res://docs/verification/v0.8/neighborhood"

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message);push_error(message)

func capture(name: String, eye: Vector3, target: Vector3) -> Image:
	main.camera.position = eye;main.camera.look_at(target)
	main.get_node("Town").update_view(eye)
	await process_frame
	if DisplayServer.get_name()=="headless": return null
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	image.save_png(OUT+"/"+name+".png")
	return image

func image_mean(image: Image) -> float:
	var total := 0.0;var count := 0
	for y in range(0,image.get_height(),8):
		for x in range(0,image.get_width(),8):
			var c := image.get_pixel(x,y);total += c.get_luminance();count += 1
	return total/maxi(1,count)

func run() -> void:
	root.size = Vector2i(1440,900)
	main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.set_process(false);sim = root.get_node("Sim");sim.set_process(false);sim.running = true
	sim.reset(71103,LifeSimulation.EXPANDED_POPULATION)
	main.get_node("%TitleScreen").hide();main.get_node("%HUD").hide()
	var town: TownEnvironment = main.get_node("Town");town.set_process(false)
	var building_sites: Array = town.buildings.map(func(building): return building.room_site)
	var expected_sites := ["home_ogawa","home_saeki","home_shared","bakery_cafe","workshop","home_north_shared","home_mori"]
	expect(town.buildings.size()==7,"Seven actual neighborhood buildings include the two added homes")
	expect(expected_sites.all(func(site): return site in building_sites),"Both new homes and every original building are included in the wall audit")
	for building in town.buildings:
		expect(building.parts.size()==6,building.room_site+": actual floor, four walls and roof imported independently")
		var target: Vector3 = LifeSimulation.SITES[building.room_site]
		expect(building.global_position.distance_to(target)<.001,building.room_site+": the model keeps the simulation's location")
		for side in TownBuilding.NORMALS:
			var body := StaticBody3D.new();var collision := CollisionShape3D.new()
			collision.shape = building.parts[side].mesh.create_trimesh_shape()
			building.parts[side].add_child(body);body.add_child(collision)
	# Test-only collision meshes make the route audit depend on actual exported walls.
	await physics_frame;await physics_frame
	var sites: Array = building_sites.duplicate()
	sites.append_array(["off_map_school","off_map_workplace","square"])
	metrics.audited_sites = sites.duplicate()
	metrics.directed_routes = sites.size()*(sites.size()-1)
	expect(metrics.directed_routes==90,"The seven buildings and three public destinations supply ninety directed route checks")
	var space := main.get_world_3d().direct_space_state
	var walls_crossed: Array = []
	for first in sites:
		for second in sites:
			if first==second: continue
			var previous: Vector3 = LifeSimulation.SITES[first]
			var path := sim.route(previous,first,LifeSimulation.SITES[second],second)
			var clear := true
			for point in path:
				var normal: Vector3 = (point-previous).cross(Vector3.UP).normalized()*.18
				for side in [-1,0,1]:
					var query := PhysicsRayQueryParameters3D.create(previous+Vector3.UP*1.15+normal*side,point+Vector3.UP*1.15+normal*side)
					var hit := space.intersect_ray(query)
					if not hit.is_empty(): clear = false;walls_crossed.append({"from":first,"to":second,"a":previous,"b":point,"hit":hit.position,"mesh":str(hit.collider.get_parent().name)})
				previous = point
			expect(clear,"The route from "+first+" to "+second+" clears actual wall meshes at body width")
	metrics.wall_crossings = sim._encode(walls_crossed)
	if not walls_crossed.is_empty(): print("Actual wall crossings: ",JSON.stringify(sim._encode(walls_crossed.slice(0,8))))
	var ground: MeshInstance3D = town.get_node("Ground")
	expect(ground.mesh.get_surface_count()==2 and is_zero_approx(ground.get_aabb().end.y),"Grass and paving share a non-overlapping ground at the walking height")
	# The same control in normal play selects exterior or cutaway, without changing routes.
	main.camera.position = Vector3(20,18,28)
	main.get_node("%BuildingsButton").pressed.emit()
	expect(not town.cutaway and town.buildings.all(func(b): return b.parts.Roof.visible),"The building control reveals actual complete roofs")
	await capture("01-exteriors",Vector3(23,22,29),Vector3(0,0,1))
	main.get_node("%BuildingsButton").pressed.emit()
	for direction in [Vector3(10,8,10),Vector3(-10,8,10),Vector3(-10,8,-10),Vector3(10,8,-10)]:
		var home: TownBuilding = town.get_node("OgawaHouse");home.update_view(home.global_position+direction)
		var toward := Vector3(direction.x,0,direction.z).normalized()
		expect(not home.parts.Roof.visible and home.parts.Floor.visible,"Rotating a cutaway preserves the actual floor and opens the roof")
		for key in TownBuilding.NORMALS:
			expect(home.parts[key].visible==(TownBuilding.NORMALS[key].dot(toward)<=.15),"The camera-facing "+key+" wall follows the observation angle")
	sim.start_minute = 12*60;sim.elapsed = 0;town.update_lighting()
	expect(town.daylight>.99 and town.lamps.all(func(l): return not l.visible),"Midday uses sunlight and turns off street lights")
	var daytime: Image = await capture("02-cutaway-day",Vector3(23,22,29),Vector3(0,0,1))
	await capture("03-cafe",Vector3(16,7,4),Vector3(8,1,-5))
	await capture("04-workshop",Vector3(8,7,1),Vector3(0,1,-7))
	await capture("07-north-shared",Vector3(-1,8,-5),Vector3(-9,1,-14))
	await capture("08-mori",Vector3(17,8,-6),Vector3(9,1,-15))
	# This is an entrance/furniture journey fixture. Give everyone free time,
	# and start the four added residents outdoors so both new doorways are used.
	for definition in sim.definitions.values(): definition.routines = []
	for p in sim.people:
		p.routine_id = "";p.next_plan_minute = 999999;p.support_next_attempt = 999999
		if p.id in ["saki","haru","tomo","yui"]:
			p.position = sim.SITES.square;p.place = "square";p.path.clear();p.moving = false
		sim._assign(p,"rest",sim.home_for(p),600,"家でひと息つく")
	var limit := 0
	while sim.people.any(func(p): return p.moving) and limit<240:sim.advance_minutes(1);limit += 1
	expect(sim.people.size()==12 and not sim.people.any(func(p): return p.moving),"All twelve residents can return through the entrances and reach furniture")
	for i in 30:
		for p in sim.people: main.avatars[p.id].update_state(p,1.0/60.0,false)
		await process_frame
	for actor in main.avatars.values(): actor.get_node("Name").hide()
	await capture("05-home-interior",Vector3(-2,6,14),Vector3(-9,1,6))
	sim.start_minute = posmod(22*60-sim.elapsed,1440);town.update_lighting()
	expect(town.daylight<.01 and town.lamps.all(func(l): return l.visible and l.light_energy>1),"Night uses cool light and turns on actual street lights")
	var nighttime: Image = await capture("06-cutaway-night",Vector3(23,22,29),Vector3(0,0,1))
	if daytime!=null and nighttime!=null:
		var day_mean := image_mean(daytime);var night_mean := image_mean(nighttime)
		metrics.rendered_brightness = {"day":day_mean,"night":night_mean}
		expect(night_mean<day_mean*.82 and night_mean>.015,"Rendered night differs from day while the town remains visible")
	# A saved route from the old street must not continue through the new shared house.
	var resident := sim.person("aoi")
	sim._assign(resident,"school","off_map_school",180,"町外へ向かう")
	resident.position = Vector3(5,0,7);resident.place = "home_shared"
	resident.path = [Vector3(13,0,7),resident.target];resident.moving = true
	var save_path := "user://test-old-neighborhood-route.json"
	sim.save_game(save_path)
	var raw = JSON.parse_string(FileAccess.get_file_as_string(save_path));raw.erase("route_layout")
	var file := FileAccess.open(save_path,FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
	expect(sim.load_game(save_path) and sim.person("aoi").position==Vector3(5,0,7),"Loading an old route keeps the actual resident position")
	resident = sim.person("aoi")
	expect(resident.path.any(func(point): return point.z>=10),"An old cross-house route is replanned around the shared house")
	var prior: Vector3 = resident.position
	var migrated_clear := true
	for point in resident.path:
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(prior+Vector3.UP*1.15,point+Vector3.UP*1.15)).is_empty(): migrated_clear = false
		prior = point
	expect(migrated_clear,"The migrated route clears the actual wall meshes")
	raw.route_layout = "invalid"
	file = FileAccess.open(save_path,FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
	expect(not sim.load_game(save_path),"A malformed route layout field is rejected before changing the town")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if DisplayServer.get_name()!="headless":
		var metrics_file := FileAccess.open(OUT+"/checks.json",FileAccess.WRITE);metrics_file.store_string(JSON.stringify(metrics,"  "));metrics_file.close()
	print("Neighborhood checks: %d passed, %d failed"%[checks-errors.size(),errors.size()])
	quit(0 if errors.is_empty() else 1)

class_name TownEnvironment
extends Node3D

@export var cutaway := true
var buildings: Array[TownBuilding] = []
var lamps: Array[OmniLight3D] = []
var lighting_timer := 0.0
var daylight := 1.0
var sky_material: ProceduralSkyMaterial
var simulation: LifeSimulation

func _ready() -> void:
	simulation = get_node("/root/Sim")
	for child in get_children():
		if child is TownBuilding: buildings.append(child)
	_collect_lamps(self)
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new();sky.sky_material = sky_material
	$WorldEnvironment.environment.sky = sky
	$WorldEnvironment.environment.background_mode = Environment.BG_SKY
	update_lighting()

func _collect_lamps(node: Node) -> void:
	for child in node.get_children():
		if child is OmniLight3D: lamps.append(child)
		_collect_lamps(child)

func _process(delta: float) -> void:
	lighting_timer -= delta
	if lighting_timer<=0:
		lighting_timer = .2
		update_lighting()

func update_view(eye: Vector3) -> void:
	for building in buildings:
		if building.show_interior!=cutaway: building.show_interior = cutaway
		building.update_view(eye)

func update_lighting() -> void:
	var phase := (simulation.minute_of_day()-360)/720.0*PI
	var height := sin(phase)
	daylight = smoothstep(-.08,.20,height)
	$Sun.light_energy = lerpf(.12,.78,daylight)
	var sun_color := Color("ffe5b5").lerp(Color("fff2da"),clampf(height,0,1))
	$Sun.light_color = Color("91add7").lerp(sun_color,daylight)
	$Sun.rotation_degrees = Vector3(-maxf(10,absf(height)*62),-35+cos(phase)*38,0)
	var env: Environment = $WorldEnvironment.environment
	env.ambient_light_color = Color("9fb6dc").lerp(Color("c6d7e7"),daylight)
	env.ambient_light_energy = lerpf(.22,.42,daylight)
	sky_material.sky_top_color = Color("172b53").lerp(Color("4d94cc"),daylight)
	sky_material.sky_horizon_color = Color("405578").lerp(Color("c4dfeb"),daylight)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = Color("172434").lerp(Color("6a8265"),daylight)
	for lamp in lamps:
		lamp.visible = daylight<.95
		lamp.light_energy = 1.6*(1-daylight)

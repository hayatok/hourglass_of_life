extends Node3D

var resident_id: String = ""
var last_position = Vector3.ZERO
var animation_name: String = ""
@onready var animator: AnimationPlayer = $AnimationPlayer
@onready var visual: Node3D = $Visual
@onready var name_label: Label3D = $Name
@onready var selection: MeshInstance3D = $Selection

const COLORS = {
	"nagisa": [Color("#87966f"),Color("#e6dfcb"),Color("#302a29"),Color("#b96842")],
	"ryo": [Color("#3a526e"),Color("#baac8d"),Color("#272629"),Color("#3a526e")],
	"rin": [Color("#d4ac42"),Color("#d1a23c"),Color("#44352b"),Color("#d4ac42")],
	"osamu": [Color("#c7b491"),Color("#535c60"),Color("#bbc1c5"),Color("#3d6661")],
	"fumi": [Color("#c79736"),Color("#827e76"),Color("#c2c1bc"),Color("#c79736")],
	"maho": [Color("#e4ddc8"),Color("#55565a"),Color("#664531"),Color("#c77c60")],
	"ritsu": [Color("#35475c"),Color("#343d50"),Color("#242931"),Color("#35475c")],
	"aoi": [Color("#647354"),Color("#4c4e4e"),Color("#332f2b"),Color("#647354")]
}

func configure(p: Dictionary) -> void:
	resident_id = p.id
	name_label.text = p.name
	global_position = p.position
	last_position = p.position
	var palette: Array = COLORS[p.id]
	_recolor($Visual/Hips/Torso, palette[0])
	_recolor($Visual/Hips/Pelvis, palette[1])
	_recolor($Visual/Hips/LeftLeg/Thigh, palette[1])
	_recolor($Visual/Hips/LeftLeg/Knee/Shin, palette[1])
	_recolor($Visual/Hips/RightLeg/Thigh, palette[1])
	_recolor($Visual/Hips/RightLeg/Knee/Shin, palette[1])
	_recolor($Visual/Hips/LeftArm/Sleeve, palette[0])
	_recolor($Visual/Hips/RightArm/Sleeve, palette[0])
	_recolor($Visual/Hips/Head/Hair, palette[2])
	_recolor($Visual/Hips/Apron, palette[3])
	$Visual/Hips/Apron.visible = p.id in ["nagisa","osamu","maho","rin"]
	if p.id == "rin":
		var growth = clampf(.72+(p.age-7)*.045,.72,1)
		visual.scale = Vector3.ONE*growth
		name_label.position.y = 2.1*growth
	selection.visible = false

func _recolor(mesh: MeshInstance3D, color: Color) -> void:
	var mat = mesh.material_override.duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mesh.material_override = mat

func update_state(p: Dictionary, delta: float, selected: bool) -> void:
	visible = p.get("alive",true) and (p.moving or not p.place.begins_with("off_map_"))
	global_position = global_position.lerp(p.position, minf(1,delta*12))
	var direction: Vector3 = p.position-last_position
	if direction.length_squared()>.00001:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(direction.x,direction.z),minf(1,delta*12))
	last_position = p.position
	selection.visible = selected
	name_label.modulate = Color("#fce7aa") if selected else Color("#fff6e2")
	var wanted = "walk" if p.moving else "idle"
	if not p.moving:
		if p.action == "work" or p.action == "hobby" or p.action == "care":
			wanted = "work"
		elif p.action == "sleep":
			wanted = "sleep"
		elif p.action in ["meet","joint_work"]:
			for meeting in Sim.meetings:
				if meeting.id == p.meeting_id and meeting.state == "engaged":
					wanted = "sit_talk" if meeting.location == "bench" else "talk"
					if meeting.get("mode","")=="project": wanted = "work"
					var other = Sim.person(meeting.b if meeting.a==p.id else meeting.a)
					var toward: Vector3 = other.position-p.position
					var face_angle = 0.0 if meeting.location=="bench" else atan2(toward.x,toward.z)
					if meeting.get("mode","")=="project": face_angle = PI
					visual.rotation.y = lerp_angle(visual.rotation.y,face_angle,minf(1,delta*5))
	if wanted != animation_name:
		animator.play(wanted,.2)
		animation_name = wanted
	animator.speed_scale = clampf(Sim.speed,.5,3) if Sim.running else 0


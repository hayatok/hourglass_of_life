extends Node3D

var resident_id: String = ""
var last_position = Vector3.ZERO
var animation_name: String = ""
var jrpg: JrpgResidentModel
var displayed_age := -1
var displayed_model := ""
var walk_rate := 1.0
var contacts: ResidentContacts
var others: Dictionary = {}
var greeted_meeting := ""
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
const MODELS = {
	"nagisa": preload("res://game/scenes/characters/nagisa.tscn"),
	"ryo": preload("res://game/scenes/characters/ryo.tscn"),
	"rin": preload("res://game/scenes/characters/rin.tscn"),
	"rin_adult": preload("res://game/scenes/characters/rin_adult.tscn"),
	"osamu": preload("res://game/scenes/characters/osamu.tscn"),
	"fumi": preload("res://game/scenes/characters/fumi.tscn"),
	"maho": preload("res://game/scenes/characters/maho.tscn"),
	"ritsu": preload("res://game/scenes/characters/ritsu.tscn"),
	"aoi": preload("res://game/scenes/characters/aoi.tscn")
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
	_update_body(p)
	selection.visible = false

func _update_body(p: Dictionary) -> void:
	displayed_age = int(p.age)
	var model_key: String = "rin_adult" if p.id=="rin" and p.age>=12 else p.id
	if MODELS.has(model_key):
		$Visual/Hips.hide()
		$AnimationPlayer.stop()
		if model_key != displayed_model:
			if is_instance_valid(contacts):
				contacts.detach();contacts.free()
			if is_instance_valid(jrpg):
				visual.remove_child(jrpg)
				jrpg.queue_free()
			jrpg = MODELS[model_key].instantiate()
			visual.add_child(jrpg)
			animator = jrpg.animator
			contacts = ResidentContacts.new();contacts.name = "Contacts";add_child(contacts)
			contacts.bind_model(self,jrpg)
			displayed_model = model_key
			animation_name = ""
		var growth := 1.0
		if model_key=="rin": growth = clampf(1+(p.age-7)*.035,1,1.14)
		if model_key=="rin_adult": growth = clampf(.88+(p.age-12)*.024,.88,1)
		visual.scale = Vector3.ONE*growth
		name_label.position.y = jrpg.rest_height*growth+.25
		jrpg.set_age(int(p.age))

func _recolor(mesh: MeshInstance3D, color: Color) -> void:
	var mat = mesh.material_override.duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mesh.material_override = mat

func update_state(p: Dictionary, delta: float, selected: bool) -> void:
	if int(p.age)!=displayed_age: _update_body(p)
	visible = p.get("alive",true) and (p.moving or not p.place.begins_with("off_map_"))
	var previous_position := global_position
	global_position = global_position.lerp(p.position, minf(1,delta*12))
	var actual_speed := global_position.distance_to(previous_position)/maxf(delta,.0001)
	var direction: Vector3 = p.position-last_position
	if direction.length_squared()>.00001:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(direction.x,direction.z),minf(1,delta*12))
	last_position = p.position
	selection.visible = selected
	name_label.modulate = Color("#fce7aa") if selected else Color("#fff6e2")
	var activity := Sim.activities.for_person(p) if not p.moving else {}
	var wanted := "walk" if p.moving else "idle"
	var attention := Vector3.ZERO
	var attend := false
	if not p.moving:
		if not activity.is_empty():
			if activity.pose=="bed" and p.action=="sleep": wanted = "sleep"
			elif activity.pose=="seat": wanted = "eat" if p.action=="eat" else "rest"
			elif activity.pose=="work" and p.action in ["work","hobby","chores"]: wanted = "work"
		if p.action=="care" and others.has("rin") and not Sim.person("rin").moving and Sim.person("rin").place==p.place:
			attention = others.rin.head_position();attend = true
		for meeting in Sim.meetings:
			if meeting.id!=p.meeting_id or meeting.state!="engaged": continue
			var other_id: String = meeting.b if meeting.a==p.id else meeting.a
			attention = others[other_id].head_position() if others.has(other_id) else Sim.person(other_id).position+Vector3.UP*1.5
			attend = true
			wanted = "sit_talk" if activity.get("pose","")=="seat" else "talk"
			if meeting.get("mode","")=="project":
				wanted = "work"
				attend = false
			elif greeted_meeting!=meeting.id and is_instance_valid(contacts):
				greeted_meeting = meeting.id;contacts.greet()
			if activity.is_empty():
				var toward: Vector3 = attention-global_position
				visual.rotation.y = lerp_angle(visual.rotation.y,atan2(toward.x,toward.z),minf(1,delta*5))
	if wanted != animation_name:
		animator.play(wanted,.2)
		animation_name = wanted
	animator.speed_scale = clampf(Sim.speed,.5,3) if Sim.running else 0
	if is_instance_valid(jrpg):
		if wanted=="walk" and Sim.running:
			var target := clampf(actual_speed/maxf(.1,jrpg.walk_speed*visual.scale.y),.35,6)
			walk_rate = lerpf(walk_rate,target,minf(1,delta*8))
			animator.speed_scale = walk_rate
		jrpg.set_expression(p.fatigue,.4 if wanted in ["talk","sit_talk"] else 0)
		contacts.update_contact(p,activity,wanted,attention,attend,delta)
		name_label.global_position = head_position()+Vector3.UP*.28

func head_position() -> Vector3:
	return contacts.point("head",Vector3(0,.12,0)) if is_instance_valid(contacts) else global_position+Vector3.UP*1.6

func focus_position() -> Vector3:
	return contacts.point("pelvis")+Vector3.UP*.18 if is_instance_valid(contacts) else global_position+Vector3.UP


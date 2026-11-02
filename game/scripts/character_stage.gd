extends Node3D

const CLIPS := ["idle","walk","talk","work","sit_talk","sleep","wave","eat","rest"]
const LABELS := ["待機","歩行","会話","作業","座って会話","睡眠","手を振る","食事","休息"]
var character: JrpgResidentModel
var clip_index := 0

func _ready() -> void:
	character = $Model
	$Camera.look_at(Vector3(0,.88,0))
	var bar := HBoxContainer.new()
	bar.position = Vector2(40,820)
	$Interface.add_child(bar)
	for i in CLIPS.size():
		var button := Button.new()
		button.text = LABELS[i]
		button.custom_minimum_size = Vector2(110,42)
		button.add_theme_font_override("font",$Interface/Label.get_theme_font("font"))
		button.pressed.connect(show_clip.bind(i))
		bar.add_child(button)
	show_clip(0)

func show_clip(index: int) -> void:
	clip_index = index
	character.animator.play(CLIPS[index],.15)
	$Interface/Label.text = "渚 — "+LABELS[index]+"　／　人物と動きの制作確認"
	character.set_expression(.15,.4 if index in [2,4,6] else 0)

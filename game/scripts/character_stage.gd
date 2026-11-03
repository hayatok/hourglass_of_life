extends Node3D

const CLIPS := ["idle","walk","talk","work","sit_talk","sleep","wave","eat","rest"]
const LABELS := ["待機","歩行","会話","作業","座って会話","睡眠","手を振る","食事","休息"]
const CHARACTERS := ["nagisa","ryo","rin","rin_adult"]
const NAMES := ["渚","亮","凛","凛（成長後）"]
var character: JrpgResidentModel
var clip_index := 0
var character_index := 0

func _ready() -> void:
	character = $Model
	$Camera.look_at(Vector3(0,.88,0))
	var picker := OptionButton.new()
	picker.name = "CharacterPicker"
	picker.position = Vector2(40,90)
	picker.custom_minimum_size = Vector2(220,42)
	for person in NAMES: picker.add_item(person)
	picker.item_selected.connect(set_character)
	$Interface.add_child(picker)
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

func set_character(index: int) -> void:
	if index == character_index: return
	remove_child(character)
	character.queue_free()
	character_index = index
	$Interface/CharacterPicker.select(index)
	character = load("res://game/scenes/characters/"+CHARACTERS[index]+".tscn").instantiate()
	character.name = "Model"
	add_child(character)
	show_clip(clip_index)

func show_clip(index: int) -> void:
	clip_index = index
	character.animator.play(CLIPS[index],.15)
	$Interface/Label.text = NAMES[character_index]+" — "+LABELS[index]+"　／　人物と動きの制作確認"
	character.set_expression(.15,.4 if index in [2,4,6] else 0)

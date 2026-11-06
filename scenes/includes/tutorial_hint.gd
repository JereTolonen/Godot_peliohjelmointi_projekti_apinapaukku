extends CanvasLayer
## Short hints at the top of the screen (tutorial text).
##
## Shows `steps[0]` when the level starts and moves to the next step after every shot.
## The last step fades out after `hide_delay` seconds. Edit the texts in the Inspector.

@export var steps: PackedStringArray = PackedStringArray()
## Seconds the last step stays on screen before it fades out.
@export var hide_delay: float = 8.0
@export var font_size: int = 30

var _label: Label = null
var _index: int = 0
var _tween: Tween = null
var _step_token: int = 0


const MenuStyle := preload("res://scenes/ui/menu_style.gd")
const UiIcon := preload("res://scenes/ui/ui_icon.gd")

var _bubble: Control = null


func _ready() -> void:
	layer = 5
	# Speech bubble below the HUD bar: info icon + text on cream paper.
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 112.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var panel := PanelContainer.new()
	var box := MenuStyle.box(MenuStyle.PAPER, MenuStyle.PAPER_EDGE, 22, 4, 8)
	box.content_margin_left = 18.0
	box.content_margin_right = 26.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 12.0
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon := UiIcon.new()
	icon.icon = "star"
	icon.color = MenuStyle.GOLD
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(420, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", MenuStyle.font())
	_label.add_theme_font_size_override("font_size", int(font_size * 0.8))
	_label.add_theme_color_override("font_color", MenuStyle.INK)
	row.add_child(_label)
	_bubble = panel

	if steps.is_empty():
		_bubble.visible = false
		return
	_show_step(0)
	_connect_slingshot.call_deferred()


func _connect_slingshot() -> void:
	var slingshot := get_tree().get_first_node_in_group("slingshot")
	if slingshot != null and slingshot.has_signal("character_shot"):
		slingshot.connect("character_shot", _on_shot)


func _on_shot(_scene: PackedScene, _instance: Node3D) -> void:
	_index += 1
	if _index < steps.size():
		_show_step(_index)
	else:
		_fade_out()


func _show_step(index: int) -> void:
	_step_token += 1
	var token := _step_token
	_label.text = steps[index]
	_bubble.visible = true
	_bubble.modulate.a = 0.0
	_bubble.pivot_offset = _bubble.size * 0.5
	_bubble.scale = Vector2(0.85, 0.85)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_bubble, "modulate:a", 1.0, 0.25)
	_tween.parallel().tween_property(_bubble, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if index == steps.size() - 1:
		get_tree().create_timer(hide_delay).timeout.connect(func() -> void:
			if token == _step_token:
				_fade_out())


func _fade_out() -> void:
	if _bubble == null or not _bubble.visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_bubble, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(func() -> void: _bubble.visible = false)

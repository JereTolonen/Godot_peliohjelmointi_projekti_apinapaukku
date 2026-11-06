extends CanvasLayer
## "+500" score popup. It pops in, floats up, fades out and frees itself.
##
## The look is edited in points.tscn: the Label (text style, outline, size) and the
## PopupSphere nodes behind it (position, radius, color).
##
## Set `points` and `world_position` before adding it to the scene tree:
##   var popup := preload("res://scenes/ui/points.tscn").instantiate()
##   popup.set("points", 500)
##   popup.set("world_position", enemy_position)
##   get_tree().current_scene.add_child(popup)

## Points shown in the popup.
@export var points: int = 500
## Seconds the popup stays on screen.
@export var lifetime: float = 1.3
## How many pixels the popup floats upwards.
@export var rise: float = 90.0
## The popup is tilted by a random angle between these two values (either direction).
@export var tilt_min_degrees: float = 6.0
@export var tilt_max_degrees: float = 11.0
## Random pixel offset applied to each sphere, so no two popups look the same.
@export var sphere_jitter: float = 6.0

## 3D position the popup appears over (converted to screen position with the current camera).
var world_position: Vector3 = Vector3.ZERO

@onready var _root: Control = $Popup
@onready var _label: Label = $Popup/Label


func _ready() -> void:
	# Valikon (50) ja HUD:n (40) alla. Popup häipyy loppuun myös kun peli on pausella.
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.text = "+%d" % points
	_apply_font()

	_root.position = _screen_position()
	var side := 1.0 if randf() < 0.5 else -1.0
	_root.rotation_degrees = side * randf_range(tilt_min_degrees, tilt_max_degrees)

	# Spheres (everything in the popup except the label) pop in one after another.
	var index := 0
	for child in _root.get_children():
		if child == _label or not (child is Control):
			continue
		var sphere := child as Control
		sphere.position += Vector2(randf_range(-sphere_jitter, sphere_jitter), randf_range(-sphere_jitter, sphere_jitter))
		sphere.scale = Vector2.ZERO
		var pop := sphere.create_tween()
		pop.tween_property(sphere, "scale", Vector2.ONE, 0.3).set_delay(0.04 * float(index)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		index += 1

	# Pop in with a little overshoot.
	_root.scale = Vector2.ZERO
	var scale_tween := _root.create_tween()
	scale_tween.tween_property(_root, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(_root, "scale", Vector2.ONE, 0.1)

	# Float up, then fade out and remove.
	var float_tween := _root.create_tween().set_parallel(true)
	float_tween.tween_property(_root, "position:y", _root.position.y - rise, lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(_root, "modulate:a", 0.0, 0.35).set_delay(maxf(lifetime - 0.35, 0.0))
	float_tween.chain().tween_callback(queue_free)


## Chunky system font, unless the label already has a font set in the scene.
func _apply_font() -> void:
	if _label.has_theme_font_override("font"):
		return
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Impact", "Arial"])
	font.font_weight = 900
	_label.add_theme_font_override("font", font)


func _screen_position() -> Vector2:
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var pos := size * 0.5
	var cam := viewport.get_camera_3d()
	if cam != null and not cam.is_position_behind(world_position):
		pos = cam.unproject_position(world_position)
	# Keep the whole popup on screen.
	var margin := Vector2(240.0, 110.0)
	return pos.clamp(margin, size - margin)

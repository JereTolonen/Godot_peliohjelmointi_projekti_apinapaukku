extends CanvasLayer
## "+500" score popup: large green text with a white outline, slightly tilted,
## with shiny spheres behind it. It pops in, floats up, fades out and frees itself.
##
## Set `points` and `world_position` before adding it to the scene tree.

## Points shown in the popup.
var points: int = 500
## 3D position the popup appears over (converted to screen position with the current camera).
var world_position: Vector3 = Vector3.ZERO
## Seconds the popup stays on screen.
var lifetime: float = 1.3
## How many pixels the popup floats upwards.
var rise: float = 90.0

const TEXT_COLOR := Color(0.2, 0.9, 0.25)
const SPHERE_COLORS: Array[Color] = [
	Color(0.25, 0.85, 0.35, 0.9),
	Color(0.55, 0.95, 0.35, 0.9),
	Color(0.15, 0.7, 0.45, 0.9),
	Color(0.7, 1.0, 0.6, 0.9),
]


## A single shaded sphere drawn around its own origin.
class PopupSphere extends Control:
	var radius: float = 40.0
	var color: Color = Color(0.25, 0.85, 0.35, 0.9)

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color.darkened(0.3))
		draw_circle(Vector2.ZERO, radius * 0.86, color)
		draw_circle(Vector2(-radius * 0.28, -radius * 0.3), radius * 0.26, Color(1.0, 1.0, 1.0, 0.55))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color.WHITE, 3.0, true)


func _ready() -> void:
	layer = 100

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.position = _screen_position()
	root.rotation_degrees = (1.0 if randf() < 0.5 else -1.0) * randf_range(6.0, 11.0)

	# Spheres behind the text: [offset, radius].
	var layout: Array = [
		[Vector2(-140.0, -5.0), 54.0],
		[Vector2(135.0, -25.0), 46.0],
		[Vector2(-45.0, -62.0), 34.0],
		[Vector2(40.0, 42.0), 42.0],
		[Vector2(-195.0, 38.0), 26.0],
		[Vector2(195.0, 35.0), 28.0],
	]
	for i in layout.size():
		var item: Array = layout[i]
		var sphere := PopupSphere.new()
		sphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sphere.position = (item[0] as Vector2) + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
		sphere.radius = item[1] as float
		sphere.color = SPHERE_COLORS[i % SPHERE_COLORS.size()]
		sphere.scale = Vector2.ZERO
		root.add_child(sphere)
		var pop := sphere.create_tween()
		pop.tween_property(sphere, "scale", Vector2.ONE, 0.3).set_delay(0.04 * float(i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	root.add_child(_make_label())

	# Pop in with a little overshoot.
	root.scale = Vector2.ZERO
	var scale_tween := root.create_tween()
	scale_tween.tween_property(root, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(root, "scale", Vector2.ONE, 0.1)

	# Float up, then fade out and remove.
	var float_tween := root.create_tween().set_parallel(true)
	float_tween.tween_property(root, "position:y", root.position.y - rise, lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(root, "modulate:a", 0.0, 0.35).set_delay(maxf(lifetime - 0.35, 0.0))
	float_tween.chain().tween_callback(queue_free)


func _make_label() -> Label:
	var label := Label.new()
	label.text = "+%d" % points
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(600.0, 200.0)
	label.position = -label.size * 0.5
	label.pivot_offset = label.size * 0.5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Impact", "Arial"])
	font.font_weight = 900
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 96)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 18)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.3, 0.05, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 6)
	return label


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

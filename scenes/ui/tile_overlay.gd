extends Control
## Piirtää tasoruudun päälle lukon ja/tai tähdet. Lisätään ruudun (Button) lapseksi.

## Lukittu taso: ruudulle piirretään valkoinen lukko.
@export var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()
## Ansaitut tähdet (0-3). Näkyvät vain jos `show_stars` on päällä.
@export_range(0, 3) var stars: int = 0:
	set(value):
		stars = value
		queue_redraw()
@export var show_stars: bool = false:
	set(value):
		show_stars = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if locked:
		_draw_lock(size * 0.5)
	if show_stars:
		_draw_stars()


func _draw_lock(center: Vector2) -> void:
	var white := Color.WHITE
	var shade := Color(0.55, 0.3, 0.1, 0.9)

	# Lukon sanka (yläkaari).
	var shackle_center := center + Vector2(0.0, -2.0)
	draw_arc(shackle_center, 12.0, PI, TAU, 24, shade, 9.0, true)
	draw_arc(shackle_center, 12.0, PI, TAU, 24, white, 5.0, true)
	draw_line(shackle_center + Vector2(-12.0, 0.0), shackle_center + Vector2(-12.0, 8.0), white, 5.0, true)
	draw_line(shackle_center + Vector2(12.0, 0.0), shackle_center + Vector2(12.0, 8.0), white, 5.0, true)

	# Lukon runko.
	var body := StyleBoxFlat.new()
	body.bg_color = white
	body.border_color = shade
	body.set_border_width_all(3)
	body.set_corner_radius_all(7)
	body.anti_aliasing = true
	draw_style_box(body, Rect2(center + Vector2(-19.0, 4.0), Vector2(38.0, 30.0)))

	# Avaimenreikä.
	draw_circle(center + Vector2(0.0, 15.0), 4.5, shade)
	draw_rect(Rect2(center + Vector2(-1.8, 17.0), Vector2(3.6, 9.0)), shade)


func _draw_stars() -> void:
	for i in 3:
		var star_center := Vector2(size.x * 0.5 + (float(i) - 1.0) * 26.0, size.y - 18.0)
		var earned := i < stars
		var fill := Color("ffd23f") if earned else Color(0.25, 0.2, 0.15, 0.55)
		var edge := Color("b45309") if earned else Color(0.1, 0.08, 0.05, 0.7)
		_draw_star(star_center, 11.0, fill, edge)


func _draw_star(center: Vector2, radius: float, fill: Color, edge: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI / 2.0 + float(i) * PI / 5.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, edge, 2.0, true)

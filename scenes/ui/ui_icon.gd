@tool
extends Control
## Vektori-ikoni, joka piirretään koodilla (ei tekstuureja): play, pause, restart, home,
## levels, settings, next, back, close, star, lock, check, monkey, sound, trophy.
## Valkoinen täyttö ja tumma ääriviiva, joten ikoni toimii kaikkien painikevärien päällä.

@export var icon: String = "play":
	set(value):
		icon = value
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()
@export var outline: Color = Color(0.16, 0.08, 0.02, 0.85):
	set(value):
		outline = value
		queue_redraw()
## 0..1, käytetään tähdessä (täyttöaste) ja himmennyksessä.
@export var fill: float = 1.0:
	set(value):
		fill = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	match icon:
		"play":
			_poly([c + Vector2(-0.24, -0.3) * s, c + Vector2(0.32, 0.0) * s, c + Vector2(-0.24, 0.3) * s])
		"pause":
			_rect(Rect2(c + Vector2(-0.26, -0.3) * s, Vector2(0.18, 0.6) * s))
			_rect(Rect2(c + Vector2(0.08, -0.3) * s, Vector2(0.18, 0.6) * s))
		"next":
			_poly([c + Vector2(-0.34, -0.28) * s, c + Vector2(0.02, 0.0) * s, c + Vector2(-0.34, 0.28) * s])
			_poly([c + Vector2(0.0, -0.28) * s, c + Vector2(0.36, 0.0) * s, c + Vector2(0.0, 0.28) * s])
		"back":
			_poly([c + Vector2(0.3, -0.3) * s, c + Vector2(-0.3, 0.0) * s, c + Vector2(0.3, 0.3) * s])
		"restart":
			_arc(c, s * 0.27, deg_to_rad(-60.0), deg_to_rad(230.0), s * 0.13)
			var tip := c + Vector2.from_angle(deg_to_rad(-60.0)) * s * 0.27
			_poly([tip + Vector2(-0.02, -0.2) * s, tip + Vector2(0.2, 0.06) * s, tip + Vector2(-0.14, 0.12) * s])
		"home":
			_poly([c + Vector2(0.0, -0.36) * s, c + Vector2(0.36, -0.02) * s, c + Vector2(0.24, -0.02) * s,
				c + Vector2(0.24, 0.32) * s, c + Vector2(0.07, 0.32) * s, c + Vector2(0.07, 0.1) * s,
				c + Vector2(-0.07, 0.1) * s, c + Vector2(-0.07, 0.32) * s, c + Vector2(-0.24, 0.32) * s,
				c + Vector2(-0.24, -0.02) * s, c + Vector2(-0.36, -0.02) * s])
		"levels":
			for y in 2:
				for x in 2:
					_rect(Rect2(c + (Vector2(-0.3, -0.3) + Vector2(x, y) * 0.33) * s, Vector2(0.27, 0.27) * s), s * 0.05)
		"settings":
			var pts := PackedVector2Array()
			for i in 32:
				var a := float(i) / 32.0 * TAU
				var r := 0.36 if (i / 2) % 2 == 0 else 0.27
				pts.append(c + Vector2.from_angle(a) * r * s)
			_poly(pts)
			draw_circle(c, s * 0.12, outline)
		"close":
			_line(c + Vector2(-0.25, -0.25) * s, c + Vector2(0.25, 0.25) * s, s * 0.14)
			_line(c + Vector2(-0.25, 0.25) * s, c + Vector2(0.25, -0.25) * s, s * 0.14)
		"check":
			_line(c + Vector2(-0.28, 0.02) * s, c + Vector2(-0.08, 0.24) * s, s * 0.14)
			_line(c + Vector2(-0.08, 0.24) * s, c + Vector2(0.3, -0.24) * s, s * 0.14)
		"star":
			_star(c, s * 0.46)
		"lock":
			draw_arc(c + Vector2(0.0, -0.08) * s, s * 0.17, PI, TAU, 20, outline, s * 0.14, true)
			draw_arc(c + Vector2(0.0, -0.08) * s, s * 0.17, PI, TAU, 20, color, s * 0.08, true)
			_rect(Rect2(c + Vector2(-0.26, -0.08) * s, Vector2(0.52, 0.42) * s), s * 0.07)
			draw_circle(c + Vector2(0.0, 0.1) * s, s * 0.06, outline)
		"monkey":
			draw_circle(c + Vector2(-0.3, -0.04) * s, s * 0.14 + 2.0, outline)
			draw_circle(c + Vector2(0.3, -0.04) * s, s * 0.14 + 2.0, outline)
			draw_circle(c, s * 0.34 + 2.0, outline)
			draw_circle(c + Vector2(-0.3, -0.04) * s, s * 0.14, Color("c98a52"))
			draw_circle(c + Vector2(0.3, -0.04) * s, s * 0.14, Color("c98a52"))
			draw_circle(c, s * 0.34, Color("a8673a"))
			draw_circle(c + Vector2(0.0, 0.08) * s, s * 0.22, Color("f2c9a0"))
			draw_circle(c + Vector2(-0.1, -0.04) * s, s * 0.05, Color("2a1a10"))
			draw_circle(c + Vector2(0.1, -0.04) * s, s * 0.05, Color("2a1a10"))
		"sound":
			_poly([c + Vector2(-0.34, -0.12) * s, c + Vector2(-0.16, -0.12) * s, c + Vector2(0.04, -0.3) * s,
				c + Vector2(0.04, 0.3) * s, c + Vector2(-0.16, 0.12) * s, c + Vector2(-0.34, 0.12) * s])
			_arc(c + Vector2(0.06, 0.0) * s, s * 0.2, -0.9, 0.9, s * 0.07)
			_arc(c + Vector2(0.06, 0.0) * s, s * 0.33, -0.9, 0.9, s * 0.07)
		"trophy":
			_poly([c + Vector2(-0.26, -0.3) * s, c + Vector2(0.26, -0.3) * s, c + Vector2(0.18, 0.04) * s,
				c + Vector2(0.06, 0.12) * s, c + Vector2(0.06, 0.22) * s, c + Vector2(0.18, 0.3) * s,
				c + Vector2(-0.18, 0.3) * s, c + Vector2(-0.06, 0.22) * s, c + Vector2(-0.06, 0.12) * s,
				c + Vector2(-0.18, 0.04) * s])


func _poly(points: Array) -> void:
	var pts := PackedVector2Array(points)
	var outline_pts := pts.duplicate()
	outline_pts.append(pts[0])
	draw_polyline(outline_pts, outline, maxf(size.x * 0.08, 3.0), true)
	draw_colored_polygon(pts, color)


func _rect(rect: Rect2, radius: float = 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = outline
	sb.set_border_width_all(int(maxf(size.x * 0.035, 2.0)))
	sb.set_corner_radius_all(int(radius if radius > 0.0 else size.x * 0.04))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)


func _line(a: Vector2, b: Vector2, width: float) -> void:
	draw_line(a, b, outline, width + 4.0, true)
	draw_circle(a, (width + 4.0) * 0.5, outline)
	draw_circle(b, (width + 4.0) * 0.5, outline)
	draw_line(a, b, color, width, true)
	draw_circle(a, width * 0.5, color)
	draw_circle(b, width * 0.5, color)


func _arc(center: Vector2, radius: float, from: float, to: float, width: float) -> void:
	draw_arc(center, radius, from, to, 28, outline, width + 4.0, true)
	draw_arc(center, radius, from, to, 28, color, width, true)


func _star(center: Vector2, radius: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + float(i) * PI / 5.0
		var r := radius if i % 2 == 0 else radius * 0.48
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	var outline_pts := pts.duplicate()
	outline_pts.append(pts[0])
	draw_colored_polygon(pts, Color(color.r * 0.35, color.g * 0.3, color.b * 0.25, 0.55) if fill < 0.5 else color)
	draw_polyline(outline_pts, outline, maxf(radius * 0.14, 2.5), true)
	if fill >= 0.5:
		# Shine.
		draw_circle(center + Vector2(-radius * 0.18, -radius * 0.2), radius * 0.13, Color(1, 1, 1, 0.55))

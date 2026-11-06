extends Control
## Yksi ammus HUD:ssa piirrettynä pienenä hahmona. Väri ja muoto kertovat tyypin,
## seuraava ammus on isompi, hehkuu ja keinuu, käytetty on pieni ja himmeä.

## Ammuksen nimi (hahmo-scenen tiedostonimi): "normal", "exploding" ...
@export var kind: String = "normal"
## 0 = käytetty, 1 = seuraava, 2 = odottaa
@export_range(0, 2) var state: int = 2

const KIND_COLORS := {
	"normal": Color("ffd23f"),
	"exploding": Color("e8452f"),
	"speedy": Color("bad94a"),
	"splitter": Color("ffd23f"),
	"heavy": Color("e0a526"),
	"bomber": Color("ffd23f"),
}

## Hahmon nimi ja kyky (työkaluvihje ja HUD-kehote).
const KIND_INFO := {
	"normal": ["Perus", ""],
	"exploding": ["Räjähtävä", "Napauta: räjähdä"],
	"speedy": ["Nopea", "Napauta: syöksy"],
	"splitter": ["Jakautuva", "Napauta: jakaudu kolmeksi"],
	"heavy": ["Painava", "Napauta: iskeydy alas"],
	"bomber": ["Pommittaja", "Napauta: pudota banaanipommi"],
}

const EDGE := Color(0.18, 0.08, 0.02)
const FLESH := Color("fff3c4")

var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(62.0, 62.0) if state == 1 else Vector2(48.0, 62.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info: Array = KIND_INFO.get(kind, [kind, ""])
	tooltip_text = "%s\n%s" % [info[0], info[1]] if info[1] != "" else String(info[0])
	set_process(state == 1)
	if state == 1:
		pivot_offset = custom_minimum_size * 0.5
		scale = Vector2(0.4, 0.4)
		var t := create_tween()
		t.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := 21.0 if state == 1 else (13.0 if state == 0 else 16.0)
	if kind == "heavy":
		radius *= 1.15
	if state == 1:
		center.y += sin(_time * 4.0) * 2.5
	var base: Color = KIND_COLORS.get(kind, Color("ffd23f"))
	var alpha := 0.4 if state == 0 else 1.0

	if state == 1:
		var glow := 0.35 + 0.15 * sin(_time * 5.0)
		draw_circle(center, radius + 11.0, Color(1.0, 0.95, 0.6, glow * 0.5))
		draw_circle(center, radius + 7.0, Color(1, 1, 1, 0.95))

	var length := radius * 2.3
	var thick := radius * (0.78 if kind == "heavy" else (0.48 if kind == "speedy" else 0.62))
	match kind:
		"speedy":
			for i in 3:
				var y := center.y + (float(i) - 1.0) * radius * 0.4
				draw_line(Vector2(center.x - radius - 12.0, y), Vector2(center.x - radius - 3.0, y), Color(1, 1, 1, 0.8 * alpha), 3.0, true)
		"splitter":
			for side in [-1.0, 1.0]:
				_draw_banana(center + Vector2(-2.0, side * radius * 0.42), length * 0.85, thick * 0.85, side * 0.35, base, alpha * 0.55, false)
		"bomber":
			var bomb := center + Vector2(radius * 0.5, radius * 0.95)
			draw_circle(bomb, radius * 0.3 + 2.0, Color(EDGE, alpha))
			draw_circle(bomb, radius * 0.3, Color(0.91, 0.27, 0.18, alpha))

	_draw_banana(center, length, thick, 0.0, base, alpha, kind == "bomber")

	if kind == "heavy":
		for p in [Vector2(-0.35, 0.2), Vector2(0.1, 0.35), Vector2(0.4, 0.05)]:
			draw_circle(center + p * radius, radius * 0.09, Color(0.45, 0.28, 0.1, alpha))
	elif kind == "exploding":
		var stem := _arc_point(center, length, 0.0, 0.0)
		var fuse_end := stem + Vector2(radius * 0.25, -radius * 0.75)
		draw_line(stem, fuse_end, Color(EDGE, alpha), 3.0, true)
		draw_circle(fuse_end, 4.0 if state != 0 else 2.0, Color(1.0, 0.85, 0.3, alpha))

	# Eyes.
	for side in [-1.0, 1.0]:
		var eye := center + Vector2(side * radius * 0.3, radius * 0.08)
		draw_circle(eye, radius * 0.17, Color(1, 1, 1, alpha))
		draw_circle(eye + Vector2(radius * 0.04, radius * 0.02), radius * 0.09, Color(EDGE, alpha))
	if kind == "exploding" or kind == "heavy":
		draw_line(center + Vector2(-radius * 0.5, -radius * 0.18), center + Vector2(-radius * 0.12, -radius * 0.06), Color(EDGE, alpha), 2.5, true)
		draw_line(center + Vector2(radius * 0.5, -radius * 0.18), center + Vector2(radius * 0.12, -radius * 0.06), Color(EDGE, alpha), 2.5, true)


## Banaanin keskiviivan piste kohdassa t (0 = varsi vasemmalla, 1 = kärki oikealla).
func _arc_point(center: Vector2, length: float, t: float, tilt: float) -> Vector2:
	var arc := 1.2
	var r := length / arc
	var theta := -arc * 0.5 + arc * t
	var sag := r * (1.0 - cos(arc * 0.5))
	var p := Vector2(r * sin(theta), -r * (1.0 - cos(theta)) + sag * 0.5)
	return center + p.rotated(tilt)


func _draw_banana(center: Vector2, length: float, thick: float, tilt: float, color: Color, alpha: float, peeled: bool) -> void:
	const STEPS := 14
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var outer_edge := PackedVector2Array()
	var inner_edge := PackedVector2Array()
	for i in STEPS + 1:
		var t := float(i) / float(STEPS)
		var p := _arc_point(center, length, t, tilt)
		var q := _arc_point(center, length, minf(t + 0.01, 1.0), tilt) - _arc_point(center, length, maxf(t - 0.01, 0.0), tilt)
		var n := Vector2(-q.y, q.x).normalized()
		var w := thick * 0.5 * maxf(0.22, pow(sin(PI * t), 0.6))
		outer.append(p + n * w)
		inner.append(p - n * w)
		outer_edge.append(p + n * (w + 2.5))
		inner_edge.append(p - n * (w + 2.5))
	inner.reverse()
	inner_edge.reverse()
	draw_colored_polygon(outer_edge + inner_edge, Color(EDGE, alpha))
	draw_colored_polygon(outer + inner, Color(color, alpha))
	if peeled:
		var tip := PackedVector2Array()
		for i in range(10, STEPS + 1):
			tip.append(outer[i])
		var inner_fwd := inner.duplicate()
		inner_fwd.reverse()
		for i in range(STEPS, 9, -1):
			tip.append(inner_fwd[i])
		draw_colored_polygon(tip, Color(FLESH, alpha))
	# Highlight along the top.
	var shine := PackedVector2Array()
	for i in range(3, STEPS - 3):
		shine.append(outer[i].lerp(inner[STEPS - i], 0.3))
	draw_polyline(shine, Color(1, 1, 1, 0.45 * alpha), 2.0, true)
	# Stem and tip.
	var stem := _arc_point(center, length, 0.0, tilt)
	draw_line(stem, stem + (stem - center).normalized() * 4.0, Color(0.35, 0.4, 0.12, alpha), 4.0, true)
	draw_circle(_arc_point(center, length, 1.0, tilt), 2.5, Color(EDGE, alpha))

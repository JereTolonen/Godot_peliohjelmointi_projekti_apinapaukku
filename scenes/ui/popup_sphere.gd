@tool
extends Control
## A shiny sphere drawn around its own origin (used behind the points text).
## Position it in the scene, and change `radius` and `color` in the Inspector.

@export var radius: float = 40.0:
	set(value):
		radius = value
		queue_redraw()
@export var color: Color = Color(0.25, 0.85, 0.35, 0.9):
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color.darkened(0.3))
	draw_circle(Vector2.ZERO, radius * 0.86, color)
	draw_circle(Vector2(-radius * 0.28, -radius * 0.3), radius * 0.26, Color(1.0, 1.0, 1.0, 0.55))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color.WHITE, 3.0, true)

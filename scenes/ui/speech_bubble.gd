extends Control
## Sarjakuvamainen puhekupla, joka seuraa 3D-hahmoa ruudulla.
##
## Käyttö: SpeechBubble.say(apina, "Oh noo...")
## Kuplat piirretään omalle CanvasLayerille, joten ne ovat aina terävät ja pelin
## käyttöliittymän tyylisiä. Liian monta kuplaa kerralla ei näytetä.

const MenuStyle := preload("res://scenes/ui/menu_style.gd")

## Enintään näin monta kuplaa ruudulla yhtä aikaa.
const MAX_BUBBLES := 3
const LAYER_NAME := "SpeechBubbles"
const TAIL := 14.0
const PAD := Vector2(16.0, 9.0)

var target: Node3D = null
## Kuplan kärjen paikka suhteessa hahmoon (maailman yksiköissä).
var offset: Vector3 = Vector3(0.0, 2.0, 0.0)
var duration: float = 2.2

var _label: Label = null
var _age: float = 0.0
var _last_world: Vector3 = Vector3.ZERO


## Näyttää kuplan hahmon päällä. Palauttaa kuplan tai null, jos ruutu on jo täynnä
## tai hahmolla on jo kupla.
static func say(who: Node3D, text: String, time: float = 2.2, height: float = 2.0, sound: String = "monkey_talk", pitch: float = 1.35) -> Control:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return null
	var layer := _layer(who)
	if layer == null:
		return null
	var count := 0
	for child in layer.get_children():
		if child.is_queued_for_deletion():
			continue
		count += 1
		if child.get("target") == who:
			return null
	if count >= MAX_BUBBLES:
		return null
	var bubble: Control = (load("res://scenes/ui/speech_bubble.gd") as GDScript).new()
	bubble.set("target", who)
	bubble.set("offset", Vector3(0.0, height, 0.0))
	bubble.set("duration", time)
	bubble.call("_setup", text)
	layer.add_child(bubble)
	# Kuplan "pop" ja apinan ääni (korkeammalla äänellä = apinamaisempi).
	var sounds := who.get_node_or_null("/root/SoundManager")
	if sounds != null:
		sounds.call("play", "bubble_pop", -12.0, 0.1, 0.05)
		if sound != "":
			sounds.call("play", sound, -5.0, 0.12, 0.15, pitch)
	return bubble


## True, jos hahmolla on parhaillaan kupla.
static func is_talking(who: Node3D) -> bool:
	var layer := _layer(who, false)
	if layer == null:
		return false
	for child in layer.get_children():
		if child.get("target") == who and not child.is_queued_for_deletion():
			return true
	return false


static func _layer(from: Node, create: bool = true) -> CanvasLayer:
	var scene := from.get_tree().current_scene
	if scene == null:
		return null
	var layer := scene.get_node_or_null(LAYER_NAME) as CanvasLayer
	if layer == null and create:
		layer = CanvasLayer.new()
		layer.name = LAYER_NAME
		layer.layer = 5
		scene.add_child(layer)
	return layer


func _setup(text: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.text = text
	_label.add_theme_font_override("font", MenuStyle.font())
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", MenuStyle.INK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _ready() -> void:
	var text_size := _label.get_minimum_size()
	size = text_size + PAD * 2.0
	_label.position = PAD
	_label.size = text_size
	pivot_offset = Vector2(size.x * 0.5, size.y + TAIL)
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.12)
	_follow()


func _process(delta: float) -> void:
	_age += delta
	_follow()
	if _age >= duration:
		set_process(false)
		var t := create_tween().set_parallel()
		t.tween_property(self, "scale", Vector2(0.6, 0.6), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(self, "modulate:a", 0.0, 0.18)
		t.chain().tween_callback(queue_free)


func _follow() -> void:
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		_last_world = target.global_position + offset
	elif _age < duration:
		# Hahmo hävisi: kupla häipyy pian.
		_age = maxf(_age, duration - 0.35)
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(_last_world):
		visible = false
		return
	visible = true
	var tip := cam.unproject_position(_last_world)
	# Pieni keinunta, ettei kupla ole jäykkä.
	tip.y += sin(_age * 6.0) * 2.0
	position = tip - Vector2(size.x * 0.5, size.y + TAIL)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var edge := MenuStyle.INK
	var fill := Color.WHITE
	var tail_x := size.x * 0.5
	var outer_tail := PackedVector2Array([
		Vector2(tail_x - 11.0, size.y - 3.0), Vector2(tail_x + 9.0, size.y - 3.0), Vector2(tail_x - 4.0, size.y + TAIL + 3.0)])
	var inner_tail := PackedVector2Array([
		Vector2(tail_x - 8.0, size.y - 4.0), Vector2(tail_x + 5.0, size.y - 4.0), Vector2(tail_x - 3.5, size.y + TAIL - 1.0)])
	var outline := StyleBoxFlat.new()
	outline.bg_color = edge
	outline.set_corner_radius_all(int(minf(size.y * 0.5, 22.0)) + 3)
	draw_style_box(outline, rect.grow(3.0))
	draw_colored_polygon(outer_tail, edge)
	var body := StyleBoxFlat.new()
	body.bg_color = fill
	body.set_corner_radius_all(int(minf(size.y * 0.5, 22.0)))
	draw_style_box(body, rect)
	draw_colored_polygon(inner_tail, fill)

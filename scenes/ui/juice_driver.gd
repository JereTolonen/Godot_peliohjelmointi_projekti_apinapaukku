extends Node
## Painikkeen lapsisolmu, joka hoitaa hover- ja painallusanimaation. Erillinen solmu
## (eikä lambdat) varmistaa, ettei vapautettu painike laukaise animaatiota.

var _button: BaseButton = null


func _ready() -> void:
	_button = get_parent() as BaseButton
	if _button == null:
		return
	_button.resized.connect(_on_resized)
	_button.mouse_entered.connect(_on_enter)
	_button.mouse_exited.connect(_on_exit)
	_button.button_down.connect(_on_down)
	_button.button_up.connect(_on_up)
	_on_resized()


func _on_resized() -> void:
	_button.pivot_offset = _button.size * 0.5


func _scale_to(target: Vector2, duration: float) -> void:
	if not _button.is_inside_tree():
		return
	var t := _button.create_tween()
	t.tween_property(_button, "scale", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_enter() -> void:
	if not _button.disabled:
		_scale_to(Vector2(1.05, 1.05), 0.12)


func _on_exit() -> void:
	_scale_to(Vector2.ONE, 0.12)


func _on_down() -> void:
	_scale_to(Vector2(0.92, 0.92), 0.06)


func _on_up() -> void:
	if not _button.is_inside_tree():
		return
	var t := _button.create_tween()
	t.tween_property(_button, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_button, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

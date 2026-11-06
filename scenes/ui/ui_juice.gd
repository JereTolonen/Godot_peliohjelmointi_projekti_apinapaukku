extends RefCounted
## Pienet UI-animaatiot: painikkeiden joustava painallus ja hover-kasvu, paneelien
## pomppiva sisääntulo ja häivytys. Animaatiot ovat lyhyitä eivätkä estä painalluksia.

const UiIcon := preload("res://scenes/ui/ui_icon.gd")
const MenuStyle := preload("res://scenes/ui/menu_style.gd")
const JuiceDriver := preload("res://scenes/ui/juice_driver.gd")


## Liittää painikkeeseen hover-/painallusanimaation.
static func attach(button: BaseButton) -> void:
	if button.has_meta("juiced"):
		return
	button.set_meta("juiced", true)
	var driver := JuiceDriver.new()
	driver.name = "JuiceDriver"
	button.add_child(driver)


static func _scale_to(control: Control, target: Vector2, duration: float) -> void:
	var t := control.create_tween()
	t.tween_property(control, "scale", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Pomppiva sisääntulo (skaalaus + häivytys).
static func pop_in(control: Control, delay: float = 0.0, from_scale: float = 0.6) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * from_scale
	control.modulate.a = 0.0
	var t := control.create_tween().set_parallel(true)
	t.tween_property(control, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(control, "modulate:a", 1.0, 0.18).set_delay(delay)


## Liukuu sisään alhaalta.
static func slide_in(control: Control, delay: float = 0.0, distance: float = 40.0) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return
	control.modulate.a = 0.0
	var t := control.create_tween().set_parallel(true)
	var offset := control.position.y
	control.position.y = offset + distance
	t.tween_property(control, "position:y", offset, 0.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(control, "modulate:a", 1.0, 0.2).set_delay(delay)


## Ikuisesti sykkivä korostus (esim. seuraava kenttä).
static func pulse(control: Control, amount: float = 0.06, period: float = 0.9) -> Tween:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return null
	control.pivot_offset = control.size * 0.5
	var t := control.create_tween().set_loops()
	t.tween_property(control, "scale", Vector2.ONE * (1.0 + amount), period * 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(control, "scale", Vector2.ONE, period * 0.5).set_trans(Tween.TRANS_SINE)
	return t


## Valmis painike: väri, teksti, ikoni ja animaatio.
static func make_button(text: String, variant: String = "primary", icon: String = "", font_size: int = 28, min_size: Vector2 = Vector2(0, 72)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	MenuStyle.style_button(button, font_size, 20, variant)
	if icon != "":
		var glyph := UiIcon.new()
		glyph.icon = icon
		var gs := min_size.y * 0.5
		glyph.custom_minimum_size = Vector2(gs, gs)
		glyph.size = Vector2(gs, gs)
		glyph.position = Vector2(18.0, (min_size.y - 4.0 - gs) * 0.5)
		button.add_child(glyph)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := button.get_theme_stylebox(state) as StyleBoxFlat
			if sb != null:
				sb.content_margin_left = gs + 30.0
	attach(button)
	return button


## Pyöreä pelkkä-ikoni-painike.
static func make_icon_button(icon: String, variant: String = "accent", diameter: float = 64.0) -> Button:
	var button := Button.new()
	MenuStyle.style_round_button(button, variant, diameter)
	var glyph := UiIcon.new()
	glyph.icon = icon
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = diameter * 0.22
	glyph.offset_right = -diameter * 0.22
	glyph.offset_top = diameter * 0.2
	glyph.offset_bottom = -diameter * 0.26
	button.add_child(glyph)
	attach(button)
	return button

extends Control
## Pelin aikainen HUD.
##
## Vasemmalla taukopainike ja kentän tunniste, keskellä ammusjono (seuraava korostettuna),
## oikealla pisteet ja jäljellä olevat apinat. HUD vain näyttää tilaa: pelin ohjain
## kutsuu bind(ritsa) kun taso alkaa, ja HUD kuuntelee ritsan ammo_changed-signaalia.
## Taukopainike lähettää saman ui_cancel-toiminnon kuin ESC-näppäin.

const MenuStyle := preload("res://scenes/ui/menu_style.gd")
const AmmoIcon := preload("res://scenes/ui/ammo_icon.gd")
const UiIcon := preload("res://scenes/ui/ui_icon.gd")
const Juice := preload("res://scenes/ui/ui_juice.gd")
const ArtStyle := preload("res://scenes/visual/art_style.gd")

var _slingshot: Node = null
var _refresh_left: float = 0.0
var _shown_score: float = 0.0
var _last_enemies: int = -1

var _bar: HBoxContainer = null
var _level_label: Label = null
var _world_label: Label = null
var _ammo_pill: PanelContainer = null
var _ammo_row: HBoxContainer = null
var _score_label: Label = null
var _enemies_label: Label = null
var _monkey_icon: Control = null
var _tap_prompt: PanelContainer = null
var _tap_label: Label = null
var _tap_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		child.queue_free()
	_build()
	visibility_changed.connect(func() -> void:
		if visible and _bar != null:
			# Fade only: moving the anchored bar would break its layout.
			_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_bar.modulate.a = 0.0
			var t := _bar.create_tween()
			t.tween_property(_bar, "modulate:a", 1.0, 0.3))


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0, 80)
	margin.add_child(holder)
	_bar = HBoxContainer.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.add_theme_constant_override("separation", 12)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_bar)

	# Left: pause + level chip.
	var pause := Juice.make_icon_button("pause", "accent", 66.0)
	pause.focus_mode = Control.FOCUS_NONE
	pause.tooltip_text = "Tauko (Esc)"
	pause.pressed.connect(_on_pause_pressed)
	pause.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_bar.add_child(pause)

	var level_pill := PanelContainer.new()
	MenuStyle.style_pill(level_pill)
	level_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	level_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_box := VBoxContainer.new()
	level_box.add_theme_constant_override("separation", -6)
	_level_label = Label.new()
	MenuStyle.style_label(_level_label, 26)
	level_box.add_child(_level_label)
	_world_label = Label.new()
	MenuStyle.style_label(_world_label, 14)
	_world_label.add_theme_color_override("font_color", MenuStyle.GOLD_LIGHT)
	level_box.add_child(_world_label)
	level_pill.add_child(level_box)
	_bar.add_child(level_pill)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(spacer_l)

	# Center: ammo queue.
	_ammo_pill = PanelContainer.new()
	MenuStyle.style_pill(_ammo_pill)
	_ammo_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_ammo_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_row = HBoxContainer.new()
	_ammo_row.add_theme_constant_override("separation", 2)
	_ammo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ammo_pill.add_child(_ammo_row)
	_bar.add_child(_ammo_pill)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(spacer_r)

	# Right: score + monkeys left.
	var score_pill := PanelContainer.new()
	MenuStyle.style_pill(score_pill)
	score_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	score_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", -6)
	var score_title := Label.new()
	score_title.text = "PISTEET"
	MenuStyle.style_label(score_title, 13)
	score_title.add_theme_color_override("font_color", MenuStyle.GOLD_LIGHT)
	score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_box.add_child(score_title)
	_score_label = Label.new()
	_score_label.text = "0"
	MenuStyle.style_label(_score_label, 28)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.custom_minimum_size = Vector2(110, 0)
	score_box.add_child(_score_label)
	score_pill.add_child(score_box)
	_bar.add_child(score_pill)

	var enemy_pill := PanelContainer.new()
	MenuStyle.style_pill(enemy_pill)
	enemy_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	enemy_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 6)
	var monkey := UiIcon.new()
	monkey.icon = "monkey"
	monkey.custom_minimum_size = Vector2(46, 46)
	_monkey_icon = monkey
	enemy_row.add_child(monkey)
	_enemies_label = Label.new()
	_enemies_label.text = "×0"
	MenuStyle.style_label(_enemies_label, 28)
	enemy_row.add_child(_enemies_label)
	enemy_pill.add_child(enemy_row)
	_bar.add_child(enemy_pill)

	# "Tap!" prompt shown while a character with an unused ability is flying.
	var holder_bottom := CenterContainer.new()
	holder_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder_bottom.offset_top = -120.0
	holder_bottom.offset_bottom = -40.0
	holder_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder_bottom)
	_tap_prompt = PanelContainer.new()
	var tap_box := MenuStyle.box(MenuStyle.GOLD, MenuStyle.GOLD_EDGE, 26, 3, 7)
	tap_box.content_margin_left = 22.0
	tap_box.content_margin_right = 22.0
	tap_box.content_margin_top = 6.0
	tap_box.content_margin_bottom = 8.0
	_tap_prompt.add_theme_stylebox_override("panel", tap_box)
	_tap_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_label = Label.new()
	MenuStyle.style_label(_tap_label, 24)
	_tap_label.add_theme_color_override("font_outline_color", MenuStyle.GOLD_EDGE.darkened(0.4))
	_tap_prompt.add_child(_tap_label)
	_tap_prompt.visible = false
	holder_bottom.add_child(_tap_prompt)


func _process(delta: float) -> void:
	var director := get_node_or_null("/root/VisualDirector")
	if director != null:
		var target := float(int(director.get("current_score")))
		if absf(target - _shown_score) > 0.5:
			_shown_score = move_toward(_shown_score, target, maxf(absf(target - _shown_score) * delta * 6.0, 20.0))
			_score_label.text = str(int(_shown_score))
		if _level_label.text == "" or delta > 0.0:
			_level_label.text = "TASO %d" % int(director.get("current_level_number"))
			var number := int(director.get("current_level_number"))
			_world_label.text = String(ArtStyle.world_for_level(number - 1)["title"])

	_update_tap_prompt(delta)

	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.2
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node.is_queued_for_deletion():
			count += 1
	_enemies_label.text = "×%d" % count
	if _last_enemies >= 0 and count < _last_enemies and _monkey_icon != null:
		_bump(_monkey_icon)
	_last_enemies = count


func _update_tap_prompt(delta: float) -> void:
	if _tap_prompt == null:
		return
	var kind := ""
	if is_instance_valid(_slingshot) and _slingshot.has_method("ability_ready_kind"):
		kind = String(_slingshot.call("ability_ready_kind"))
	var info: Array = AmmoIcon.KIND_INFO.get(kind, ["", ""])
	var show := kind != "" and String(info[1]) != ""
	if show and not _tap_prompt.visible:
		_tap_label.text = "%s!" % String(info[1]).to_upper()
		_tap_time = 0.0
	_tap_prompt.visible = show
	if show:
		_tap_time += delta
		_tap_prompt.pivot_offset = _tap_prompt.size * 0.5
		var s := 1.0 + 0.06 * sin(_tap_time * 10.0)
		_tap_prompt.scale = Vector2(s, s)


func _bump(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	var t := control.create_tween()
	t.tween_property(control, "scale", Vector2(1.4, 1.4), 0.08)
	t.tween_property(control, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_pause_pressed() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)


## Kytkee HUD:n tason ritsaan.
func bind(slingshot: Node) -> void:
	if is_instance_valid(_slingshot) and _slingshot.is_connected("ammo_changed", _on_ammo_changed):
		_slingshot.disconnect("ammo_changed", _on_ammo_changed)
	_slingshot = slingshot
	_shown_score = 0.0
	_last_enemies = -1
	if _score_label != null:
		_score_label.text = "0"
	if _slingshot != null:
		_slingshot.connect("ammo_changed", _on_ammo_changed)
	_rebuild()


func _on_ammo_changed(_remaining: int, _total: int) -> void:
	_rebuild()


func _rebuild() -> void:
	if _ammo_row == null:
		return
	for child in _ammo_row.get_children():
		child.queue_free()

	var uses_ammo := is_instance_valid(_slingshot) and bool(_slingshot.call("uses_ammo"))
	_ammo_pill.visible = uses_ammo
	if not uses_ammo:
		return

	var kinds: Array = _slingshot.call("ammo_kinds")
	var used := int(_slingshot.call("ammo_used"))
	for i in kinds.size():
		var icon := AmmoIcon.new()
		icon.kind = str(kinds[i])
		icon.state = 0 if i < used else (1 if i == used else 2)
		_ammo_row.add_child(icon)

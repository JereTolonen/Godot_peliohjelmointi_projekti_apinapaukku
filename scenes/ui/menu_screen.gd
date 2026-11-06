extends Control
## Päävalikko, kenttävalinta, asetukset, taukovalikko ja tulosruudut (sama scene kaikkiin).
##
## Valikko ei ohjaa peliä itse: se lähettää samat signaalit kuin ennenkin ja pelin
## ohjain (game_manager.gd) reagoi niihin. Rajapinta on ennallaan:
##   set_levels(nimet), set_in_game(bool), set_result(voitto, onko_seuraava)
##
## Näkymät rakennetaan koodissa, ulkoasu tulee menu_style.gd:stä ja animaatiot
## ui_juice.gd:stä. Tähdet ja ennätykset (progress_store.gd) ovat vain esitystä varten.

signal play_requested
signal continue_requested
signal restart_requested
signal next_requested
signal main_menu_requested
signal level_selected(index: int)
signal quit_requested

const MenuStyle := preload("res://scenes/ui/menu_style.gd")
const Juice := preload("res://scenes/ui/ui_juice.gd")
const UiIcon := preload("res://scenes/ui/ui_icon.gd")
const Progress := preload("res://scenes/ui/progress_store.gd")
const ArtStyle := preload("res://scenes/visual/art_style.gd")

enum Page { MAIN, LEVELS, SETTINGS, PAUSE, RESULT }

const TIPS := [
	"Vinkki: kaada tukipilarit, niin koko torni sortuu.",
	"Vinkki: kivi kestää paljon – ammu mieluummin puuta tai jäätä.",
	"Vinkki: räjähtävä ammus kannattaa säästää tiiviiseen rykelmään.",
	"Vinkki: dynamiitti laukaisee ketjureaktion.",
	"Vinkki: vedä täysille – kova osuma tekee enemmän vahinkoa.",
	"Vinkki: avaruudessa planeettojen painovoima kaartaa rataa.",
]

## Ruudukon sarakkeet kenttävalinnassa.
@export var columns: int = 5
## Kenttäruudun koko.
@export var tile_size: Vector2 = Vector2(100.0, 106.0)

var _names: PackedStringArray = PackedStringArray()
var _page: Page = Page.MAIN
var _in_game: bool = false
var _world_index: int = 0
var _current_index: int = 0
var _settings_return: Page = Page.MAIN
var _open_levels_after_menu: bool = false

var _dim: ColorRect = null
var _host: Control = null
var _page_root: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		child.queue_free()
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.03, 0.04, 0.12, 0.2)
	add_child(_dim)
	_host = Control.new()
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_host)
	Progress.apply_settings(get_tree())
	visibility_changed.connect(_on_visibility_changed)
	_ensure_page.call_deferred()


## Jos pelin ohjain ei ole vielä antanut kenttiä, näytetään silti päävalikko.
func _ensure_page() -> void:
	if _page_root == null:
		_show_page(Page.MAIN)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	# ESC palaa alivalikoista. Tauon sulkemisen hoitaa pelin ohjain.
	if _page == Page.LEVELS and not _in_game:
		_show_page(Page.MAIN)
		get_viewport().set_input_as_handled()
	elif _page == Page.SETTINGS:
		_show_page(_settings_return)
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	if visible and _page_root != null:
		_pop_later(_page_root, 0.0, 0.9, 1)


# --- Public interface (game_manager.gd) ---------------------------------------------

## Kenttien nimet. Jokaisesta tulee numeroitu ruutu kenttävalintaan.
func set_levels(names: PackedStringArray) -> void:
	_names = names
	if _page == Page.LEVELS or _page == Page.MAIN:
		_show_page(_page)


## Pelin aikana (tauko) näytetään taukovalikko, muuten päävalikko.
func set_in_game(value: bool) -> void:
	_in_game = value
	if value:
		_show_page(Page.PAUSE)
	elif _open_levels_after_menu:
		_open_levels_after_menu = false
		_show_page(Page.LEVELS)
	else:
		_show_page(Page.MAIN)


## Tulosruutu tason päätyttyä. `has_next`: onko voiton jälkeen seuraavaa tasoa.
func set_result(won: bool, has_next: bool) -> void:
	_in_game = false
	_build_result(won, has_next)


# --- Navigation ---------------------------------------------------------------------

func _director() -> Node:
	return get_node_or_null("/root/VisualDirector")


func _start(index: int) -> void:
	_current_index = index
	var director := _director()
	if director != null:
		director.set("current_level_index", index)
	level_selected.emit(index)


func _show_page(page: Page) -> void:
	_page = page
	match page:
		Page.MAIN:
			_set_dim(0.12)
			_build_main()
		Page.LEVELS:
			_set_dim(0.35)
			_world_index = _world_of(Progress.next_unfinished(_names.size()))
			_build_levels()
		Page.SETTINGS:
			_set_dim(0.5)
			_build_settings()
		Page.PAUSE:
			_set_dim(0.55)
			_build_pause()


func _set_dim(alpha: float) -> void:
	var t := _dim.create_tween()
	t.tween_property(_dim, "color:a", alpha, 0.25)


func _replace_page(root: Control) -> void:
	if _page_root != null and is_instance_valid(_page_root):
		_page_root.queue_free()
	_page_root = root
	_host.add_child(root)


func _centered() -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return center


## Puukehys + kermapaperi + otsikkonauha. Palauttaa [ulkosäiliö, sisältö-VBox].
func _panel(title: String, variant: String = "accent", min_width: float = 420.0) -> Array:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", -34)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ribbon := Label.new()
	ribbon.text = title
	MenuStyle.style_header(ribbon, variant)
	outer.add_child(ribbon)
	var frame := PanelContainer.new()
	MenuStyle.style_frame(frame)
	frame.custom_minimum_size = Vector2(min_width, 0.0)
	outer.add_child(frame)
	var paper := PanelContainer.new()
	MenuStyle.style_inner(paper)
	frame.add_child(paper)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	paper.add_child(content)
	return [outer, content]


func _stagger(buttons: Array) -> void:
	var i := 0
	for b in buttons:
		var control := b as Control
		var delay := 0.05 + 0.05 * float(i)
		_pop_later(control, delay, 0.7)
		i += 1


## Kutsuu `callable` kahden ruudun päästä, kun asettelu on valmis (pivotit oikein).
func _later(callable: Callable, frames: int = 2, guard: Object = null) -> void:
	var guard_ref: WeakRef = weakref(guard) if guard != null else null
	for f in frames:
		await get_tree().process_frame
	if guard_ref != null and guard_ref.get_ref() == null:
		return
	if guard_ref != null and not (guard_ref.get_ref() as Node).is_inside_tree():
		return
	callable.call()


## Viivästetty pomppu ilman lambdaa (turvallinen, vaikka sivu vaihtuisi välissä).
func _pop_later(control: Control, delay: float, from_scale: float, frames: int = 2) -> void:
	var ref: WeakRef = weakref(control)
	for f in frames:
		await get_tree().process_frame
	var c := ref.get_ref() as Control
	if c != null and c.is_inside_tree():
		Juice.pop_in(c, delay, from_scale)


func _pulse_later(control: Control, amount: float, period: float, frames: int) -> void:
	var ref: WeakRef = weakref(control)
	for f in frames:
		await get_tree().process_frame
	var c := ref.get_ref() as Control
	if c != null and c.is_inside_tree():
		Juice.pulse(c, amount, period)


func _focus_first(button: Control) -> void:
	if button != null:
		button.grab_focus.call_deferred()


# --- Main menu ------------------------------------------------------------------

func _game_title() -> String:
	var raw := String(ProjectSettings.get_setting("application/config/name", "Peli"))
	return raw.replace("_", " ").strip_edges().to_upper()


func _build_main() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(column)

	# Logo.
	var logo := Label.new()
	logo.text = _game_title()
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_font_override("font", MenuStyle.font())
	logo.add_theme_font_size_override("font_size", 84)
	logo.add_theme_color_override("font_color", MenuStyle.GOLD_LIGHT)
	logo.add_theme_color_override("font_outline_color", MenuStyle.TEXT_OUTLINE)
	logo.add_theme_constant_override("outline_size", 22)
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	logo.add_theme_constant_override("shadow_offset_y", 8)
	column.add_child(logo)
	var tag := Label.new()
	tag.text = "Kaada kaikki apinat!"
	MenuStyle.style_ribbon(tag, 24, "danger")
	var tag_row := CenterContainer.new()
	tag_row.add_child(tag)
	column.add_child(tag_row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	column.add_child(spacer)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	var button_row := CenterContainer.new()
	button_row.add_child(buttons)
	column.add_child(button_row)

	var next := Progress.next_unfinished(_names.size())
	var play := Juice.make_button("PELAA", "primary", "play", 42, Vector2(380, 92))
	play.disabled = _names.is_empty()
	play.pressed.connect(func() -> void: _start(next))
	buttons.add_child(play)
	var levels := Juice.make_button("KENTÄT", "secondary", "levels", 30, Vector2(380, 72))
	levels.pressed.connect(func() -> void: _show_page(Page.LEVELS))
	buttons.add_child(levels)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var settings := Juice.make_button("ASETUKSET", "wood", "settings", 22, Vector2(250, 64))
	settings.pressed.connect(func() -> void:
		_settings_return = Page.MAIN
		_show_page(Page.SETTINGS))
	row.add_child(settings)
	var quit := Juice.make_icon_button("close", "danger", 64.0)
	quit.tooltip_text = "Poistu"
	quit.pressed.connect(quit_requested.emit)
	row.add_child(quit)
	buttons.add_child(row)

	# Star total (bottom left) and "next level" hint.
	var chip := PanelContainer.new()
	MenuStyle.style_pill(chip, 0.6)
	chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chip.position = Vector2(24, -84)
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	var star := UiIcon.new()
	star.icon = "star"
	star.color = MenuStyle.STAR
	star.custom_minimum_size = Vector2(44, 44)
	chip_row.add_child(star)
	var stars_label := Label.new()
	stars_label.text = "%d / %d   •   %d / %d kenttää" % [Progress.total_stars(_names.size()), _names.size() * 3, Progress.completed_count(_names.size()), _names.size()]
	MenuStyle.style_label(stars_label, 26)
	chip_row.add_child(stars_label)
	chip.add_child(chip_row)
	root.add_child(chip)
	chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chip.offset_left = 24
	chip.offset_bottom = -24
	chip.offset_top = -84

	_replace_page(root)
	_pop_later(logo, 0.0, 0.4)
	_pop_later(tag, 0.12, 0.5)
	_stagger([play, levels, row])
	_pulse_later(play, 0.035, 1.4, 30)
	_focus_first(play)


# --- Level selection ---------------------------------------------------------------

func _build_levels() -> void:
	var center := _centered()
	var parts := _panel("VALITSE KENTTÄ", "accent", 640.0)
	var outer: Control = parts[0]
	var content: VBoxContainer = parts[1]
	center.add_child(outer)

	# World pager: < world name >
	var worlds := _worlds()
	_world_index = clampi(_world_index, 0, maxi(worlds.size() - 1, 0))
	var world: Dictionary = worlds[_world_index] if not worlds.is_empty() else {"title": "", "subtitle": "", "from": 0, "to": _names.size(), "color": MenuStyle.GOLD, "edge": MenuStyle.GOLD_EDGE, "theme": "meadow"}
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 16)
	var prev := Juice.make_icon_button("back", "wood", 60.0)
	prev.disabled = _world_index <= 0
	prev.pressed.connect(func() -> void:
		_world_index -= 1
		_build_levels())
	pager.add_child(prev)
	var title := Label.new()
	title.text = String(world["title"])
	title.custom_minimum_size = Vector2(340, 0)
	MenuStyle.style_ribbon(title, 30, "accent")
	var rb := title.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	rb.bg_color = world["color"]
	rb.border_color = world["edge"]
	title.add_theme_stylebox_override("normal", rb)
	title.add_theme_color_override("font_outline_color", (world["edge"] as Color).darkened(0.35))
	pager.add_child(title)
	var nxt := Juice.make_icon_button("play", "wood", 60.0)
	nxt.disabled = _world_index >= worlds.size() - 1
	nxt.pressed.connect(func() -> void:
		_world_index += 1
		_build_levels())
	pager.add_child(nxt)
	content.add_child(pager)

	# Dots showing which world page this is.
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 8)
	for i in worlds.size():
		var dot := Panel.new()
		var on := i == _world_index
		dot.custom_minimum_size = Vector2(22, 12) if on else Vector2(12, 12)
		dot.add_theme_stylebox_override("panel", MenuStyle.box((worlds[i]["color"] as Color) if on else MenuStyle.PAPER_EDGE, MenuStyle.INK_SOFT, 6, 2))
		dots.add_child(dot)
	content.add_child(dots)

	var sub := Label.new()
	var from := int(world["from"])
	var to := mini(int(world["to"]), _names.size())
	var got := 0
	for i in range(from, to):
		got += Progress.stars(i)
	sub.text = "%s  •  %s  •  ★ %d / %d" % [String(ArtStyle.THEMES.get(world.get("theme", "meadow"), {"title": ""})["title"]), world["subtitle"], got, (to - from) * 3]
	MenuStyle.style_ink(sub, 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var grid_row := CenterContainer.new()
	grid_row.add_child(grid)
	content.add_child(grid_row)

	var next := Progress.next_unfinished(_names.size())
	var tiles: Array = []
	var focus: Control = null
	for i in range(from, to):
		var tile := _make_tile(i, world, i == next)
		grid.add_child(tile)
		tiles.append(tile)
		if focus == null or i == next:
			focus = tile

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	var back := Juice.make_button("TAKAISIN", "wood", "back", 22, Vector2(220, 60))
	back.pressed.connect(func() -> void:
		_show_page(Page.PAUSE if _in_game else Page.MAIN))
	bottom.add_child(back)
	content.add_child(bottom)

	_replace_page(center)
	_pop_later(outer, 0.0, 0.85, 1)
	_stagger(tiles)
	_focus_first(focus)


## Maailman indeksi (valikon sivu), johon kenttä kuuluu.
func _world_of(level_index: int) -> int:
	var list := _worlds()
	for i in list.size():
		if level_index >= int(list[i]["from"]) and level_index < int(list[i]["to"]):
			return i
	return 0


func _worlds() -> Array:
	var list: Array = []
	for w in ArtStyle.WORLDS:
		if int(w["from"]) < _names.size():
			list.append(w)
	return list


func _make_tile(index: int, world: Dictionary, is_next: bool) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = tile_size
	tile.text = str(index + 1)
	tile.tooltip_text = _names[index] if index < _names.size() else ""
	var completed := Progress.is_completed(index)
	var unlocked := Progress.is_unlocked(index)
	var variant := "wood"
	MenuStyle.style_button(tile, 44, 22, variant)
	if completed or is_next:
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var wsb := tile.get_theme_stylebox(state) as StyleBoxFlat
			if wsb != null:
				wsb.bg_color = (world["color"] as Color).lightened(0.12 if state == "hover" else 0.0)
				wsb.border_color = world["edge"]
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := tile.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null:
			sb.content_margin_bottom += 26.0
	tile.pressed.connect(func() -> void: _start(index))
	Juice.attach(tile)
	if not unlocked:
		tile.disabled = true
		tile.text = ""
		tile.tooltip_text = "Lukittu – läpäise ensin kenttä %d" % index
		var lock := UiIcon.new()
		lock.icon = "lock"
		lock.color = Color(1, 1, 1, 0.9)
		lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lock.offset_left = tile_size.x * 0.25
		lock.offset_right = -tile_size.x * 0.25
		lock.offset_top = tile_size.y * 0.16
		lock.offset_bottom = -tile_size.y * 0.3
		tile.add_child(lock)
		var small := Label.new()
		small.text = str(index + 1)
		MenuStyle.style_label(small, 16)
		small.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		small.offset_top = -30
		small.offset_bottom = -8
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(small)
		return tile

	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", 0)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stars.offset_top = -40
	stars.offset_bottom = -12
	var earned := Progress.stars(index)
	for s in 3:
		var star := UiIcon.new()
		star.icon = "star"
		star.color = MenuStyle.STAR
		star.fill = 1.0 if s < earned else 0.0
		star.custom_minimum_size = Vector2(28, 28)
		stars.add_child(star)
	tile.add_child(stars)

	if completed:
		var badge := UiIcon.new()
		badge.icon = "check"
		badge.color = Color.WHITE
		badge.size = Vector2(30, 30)
		badge.position = Vector2(tile_size.x - 26, -8)
		var bg := Panel.new()
		var sb := MenuStyle.box(MenuStyle.GREEN, MenuStyle.GREEN_EDGE, 16, 3)
		bg.add_theme_stylebox_override("panel", sb)
		bg.size = Vector2(32, 32)
		bg.position = Vector2(tile_size.x - 27, -9)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(bg)
		tile.add_child(badge)
	if is_next:
		_pulse_later(tile, 0.07, 1.0, 25)
	return tile


# --- Settings ------------------------------------------------------------------------

func _build_settings() -> void:
	var center := _centered()
	var parts := _panel("ASETUKSET", "secondary", 480.0)
	var outer: Control = parts[0]
	var content: VBoxContainer = parts[1]
	center.add_child(outer)

	# Volume.
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 14)
	var vol_icon := UiIcon.new()
	vol_icon.icon = "sound"
	vol_icon.color = MenuStyle.BLUE
	vol_icon.custom_minimum_size = Vector2(44, 44)
	vol_row.add_child(vol_icon)
	var vol_label := Label.new()
	vol_label.text = "Äänet"
	MenuStyle.style_ink(vol_label, 24)
	vol_label.custom_minimum_size = Vector2(150, 0)
	vol_row.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Progress.get_setting("volume", 0.8))
	slider.custom_minimum_size = Vector2(200, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(slider)
	slider.value_changed.connect(func(v: float) -> void:
		Progress.set_setting("volume", v)
		Progress.apply_settings(get_tree()))
	vol_row.add_child(slider)
	content.add_child(vol_row)

	content.add_child(_toggle_row("Koko näyttö", "fullscreen", false))
	content.add_child(_toggle_row("Varjot", "shadows", true))

	var reset := Juice.make_button("NOLLAA EDISTYMINEN", "danger", "restart", 20, Vector2(0, 56))
	reset.pressed.connect(func() -> void:
		Progress.reset()
		reset.text = "NOLLATTU!"
		reset.disabled = true)
	content.add_child(reset)

	var back := Juice.make_button("TAKAISIN", "wood", "back", 24, Vector2(0, 62))
	back.pressed.connect(func() -> void: _show_page(_settings_return))
	content.add_child(back)

	_replace_page(center)
	_pop_later(outer, 0.0, 0.85, 1)
	_focus_first(back)


func _toggle_row(text: String, key: String, default: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = text
	MenuStyle.style_ink(label, 24)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var on := bool(Progress.get_setting(key, default))
	var toggle := Juice.make_button("PÄÄLLÄ" if on else "POIS", "primary" if on else "wood", "", 20, Vector2(140, 52))
	toggle.pressed.connect(func() -> void:
		var value := not bool(Progress.get_setting(key, default))
		Progress.set_setting(key, value)
		Progress.apply_settings(get_tree())
		toggle.text = "PÄÄLLÄ" if value else "POIS"
		MenuStyle.style_button(toggle, 20, 20, "primary" if value else "wood"))
	row.add_child(toggle)
	return row


func _style_slider(slider: HSlider) -> void:
	var track := MenuStyle.box(MenuStyle.PAPER_EDGE, MenuStyle.INK_SOFT, 10, 2)
	track.content_margin_top = 8.0
	track.content_margin_bottom = 8.0
	var fill := MenuStyle.box(MenuStyle.BLUE, MenuStyle.BLUE_EDGE, 10, 2)
	fill.content_margin_top = 8.0
	fill.content_margin_bottom = 8.0
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := Image.create(36, 36, false, Image.FORMAT_RGBA8)
	knob.fill(Color(0, 0, 0, 0))
	for y in 36:
		for x in 36:
			var d := Vector2(x - 17.5, y - 17.5).length()
			if d < 17.0:
				knob.set_pixel(x, y, MenuStyle.BLUE_EDGE if d > 13.0 else Color.WHITE)
	var tex := ImageTexture.create_from_image(knob)
	slider.add_theme_icon_override("grabber", tex)
	slider.add_theme_icon_override("grabber_highlight", tex)


# --- Pause ------------------------------------------------------------------------------

func _build_pause() -> void:
	var center := _centered()
	var parts := _panel("TAUKO", "secondary", 420.0)
	var outer: Control = parts[0]
	var content: VBoxContainer = parts[1]
	center.add_child(outer)

	var level := Label.new()
	var director := _director()
	var number := int(director.get("current_level_number")) if director != null else _current_index + 1
	var theme := String(director.get("current_theme")) if director != null else "meadow"
	level.text = "TASO %d  •  %s" % [number, String(ArtStyle.THEMES.get(theme, {"title": ""})["title"]).to_upper()]
	MenuStyle.style_ink(level, 20)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(level)

	var resume := Juice.make_button("JATKA", "primary", "play", 34, Vector2(340, 84))
	resume.pressed.connect(continue_requested.emit)
	content.add_child(resume)
	var restart := Juice.make_button("ALOITA ALUSTA", "secondary", "restart", 24, Vector2(340, 66))
	restart.pressed.connect(restart_requested.emit)
	content.add_child(restart)
	var levels := Juice.make_button("KENTÄT", "purple", "levels", 24, Vector2(340, 66))
	levels.pressed.connect(func() -> void:
		_open_levels_after_menu = true
		main_menu_requested.emit())
	content.add_child(levels)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var settings := Juice.make_icon_button("settings", "wood", 66.0)
	settings.tooltip_text = "Asetukset"
	settings.pressed.connect(func() -> void:
		_settings_return = Page.PAUSE
		_show_page(Page.SETTINGS))
	row.add_child(settings)
	var home := Juice.make_icon_button("home", "wood", 66.0)
	home.tooltip_text = "Päävalikko"
	home.pressed.connect(main_menu_requested.emit)
	row.add_child(home)
	content.add_child(row)

	_replace_page(center)
	_pop_later(outer, 0.0, 0.85, 1)
	_focus_first(resume)


# --- Result ------------------------------------------------------------------------------

func _build_result(won: bool, has_next: bool) -> void:
	_page = Page.RESULT
	_set_dim(0.55)
	var director := _director()
	var number := int(director.get("current_level_number")) if director != null else _current_index + 1
	var index := number - 1 if number > 0 else _current_index
	_current_index = index

	var slingshot := get_tree().get_first_node_in_group("slingshot")
	var remaining := 0
	var uses_ammo := false
	if slingshot != null and slingshot.has_method("ammo_remaining"):
		remaining = int(slingshot.call("ammo_remaining"))
		uses_ammo = bool(slingshot.call("uses_ammo"))
	var stars := clampi(1 + remaining, 1, 3) if uses_ammo else 3
	var base_score := int(director.get("current_score")) if director != null else 0
	var bonus := remaining * 1000
	var score := base_score + bonus

	var center := _centered()
	var parts := _panel("TASO LÄPÄISTY!" if won else "EPÄONNISTUIT", "primary" if won else "danger", 480.0)
	var outer: Control = parts[0]
	var content: VBoxContainer = parts[1]
	center.add_child(outer)

	var level := Label.new()
	level.text = "TASO %d" % number
	MenuStyle.style_ink(level, 22)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(level)

	var star_icons: Array = []
	var focus: Control = null
	if won:
		var improved := Progress.record(index, stars, score)
		var star_row := HBoxContainer.new()
		star_row.alignment = BoxContainer.ALIGNMENT_CENTER
		star_row.add_theme_constant_override("separation", 6)
		for s in 3:
			var star := UiIcon.new()
			star.icon = "star"
			star.color = MenuStyle.STAR
			star.fill = 0.0
			var big := 112.0 if s == 1 else 92.0
			star.custom_minimum_size = Vector2(big, big)
			star.size_flags_vertical = Control.SIZE_SHRINK_END if s == 1 else Control.SIZE_SHRINK_CENTER
			star_row.add_child(star)
			star_icons.append(star)
		content.add_child(star_row)

		var score_label := Label.new()
		score_label.text = "0"
		MenuStyle.style_label(score_label, 46)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(score_label)
		var detail := Label.new()
		detail.text = "Apinat %d  +  säästetyt ammukset %d" % [base_score, bonus] if uses_ammo else "Pisteet"
		MenuStyle.style_ink(detail, 16)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(detail)
		if improved:
			var record := Label.new()
			record.text = "UUSI ENNÄTYS!"
			MenuStyle.style_ribbon(record, 20, "danger")
			var rr := CenterContainer.new()
			rr.add_child(record)
			content.add_child(rr)
			_pulse_later(record, 0.08, 0.7, 4)

		var count := score_label.create_tween()
		count.tween_interval(0.35)
		count.tween_method(func(v: float) -> void: score_label.text = _format_score(int(v)), 0.0, float(score), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_animate_stars(star_icons, stars)
		_confetti()
	else:
		var monkeys := get_tree().get_nodes_in_group("enemies").size()
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		var monkey := UiIcon.new()
		monkey.icon = "monkey"
		monkey.custom_minimum_size = Vector2(84, 84)
		row.add_child(monkey)
		var left := Label.new()
		left.text = "× %d jäi pystyyn" % monkeys
		MenuStyle.style_ink(left, 28)
		row.add_child(left)
		content.add_child(row)
		var tip := Label.new()
		tip.text = TIPS[randi() % TIPS.size()]
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(380, 0)
		MenuStyle.style_ink(tip, 18)
		tip.add_theme_color_override("font_color", MenuStyle.INK_SOFT)
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(tip)
		var t := monkey.create_tween().set_loops()
		monkey.pivot_offset = Vector2(42, 42)
		t.tween_property(monkey, "rotation", 0.15, 0.4).set_trans(Tween.TRANS_SINE)
		t.tween_property(monkey, "rotation", -0.15, 0.4).set_trans(Tween.TRANS_SINE)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	var home := Juice.make_icon_button("home", "wood", 72.0)
	home.tooltip_text = "Päävalikko"
	home.pressed.connect(main_menu_requested.emit)
	buttons.add_child(home)
	var levels := Juice.make_icon_button("levels", "purple", 72.0)
	levels.tooltip_text = "Kentät"
	levels.pressed.connect(func() -> void:
		_open_levels_after_menu = true
		main_menu_requested.emit())
	buttons.add_child(levels)
	if won:
		var again := Juice.make_icon_button("restart", "secondary", 72.0)
		again.tooltip_text = "Pelaa uudelleen"
		again.pressed.connect(restart_requested.emit)
		buttons.add_child(again)
		if has_next:
			var next := Juice.make_button("SEURAAVA", "primary", "next", 30, Vector2(230, 76))
			next.pressed.connect(func() -> void:
				_current_index += 1
				var d := _director()
				if d != null:
					d.set("current_level_index", _current_index)
				next_requested.emit())
			buttons.add_child(next)
			focus = next
		else:
			focus = again
	else:
		var retry := Juice.make_button("YRITÄ UUDELLEEN", "primary", "restart", 26, Vector2(290, 76))
		retry.pressed.connect(restart_requested.emit)
		buttons.add_child(retry)
		focus = retry
	content.add_child(buttons)

	_replace_page(center)
	_pop_later(outer, 0.0, 0.6, 1)
	_focus_first(focus)


func _animate_stars(icons: Array, earned: int) -> void:
	for i in icons.size():
		var star := icons[i] as Control
		star.ready.connect(func() -> void:
			star.pivot_offset = star.custom_minimum_size * 0.5
			star.scale = Vector2(0.4, 0.4)
			var t := star.create_tween()
			t.tween_interval(0.45 + 0.28 * float(i))
			if i < earned:
				t.tween_callback(func() -> void:
					star.set("fill", 1.0)
					var sm := get_node_or_null("/root/SoundManager")
					if sm != null:
						sm.call("play", "star_%d" % (i + 1) if i < 3 else "star", 0.0, 0.0))
				t.tween_property(star, "scale", Vector2(1.35, 1.35), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				t.tween_property(star, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				t.tween_callback(func() -> void: _sparkle(star))
			else:
				t.tween_property(star, "scale", Vector2.ONE, 0.2), CONNECT_ONE_SHOT)


func _sparkle(target: Control) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = MenuStyle.STAR
	p.position = target.custom_minimum_size * 0.5
	target.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0, true).timeout.connect(p.queue_free)


func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 90
	p.lifetime = 2.4
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(get_viewport_rect().size.x * 0.5, 10.0)
	p.position = Vector2(get_viewport_rect().size.x * 0.5, -20.0)
	p.direction = Vector2(0, 1)
	p.spread = 30.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 260)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 11.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Color("ff5d73"), Color("ffd23f"), Color("3ddc97"), Color("4da6ff"), Color("b67dff")])
	p.color_initial_ramp = g
	_host.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0, true).timeout.connect(p.queue_free)


func _format_score(value: int) -> String:
	var s := str(value)
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = " " + out
	return out

extends RefCounted
## Käyttöliittymän visuaalinen suunnittelujärjestelmä: värit, paneelit, painikkeet,
## otsikkonauhat ja tekstityylit. Kaikki UI:n värit ja muodot ovat tässä, joten ulkoasua
## voi muuttaa yhdestä paikasta.
##
## Tyyli: puukehyksiset kermanväriset paneelit (sopivat palikkamaailmaan), kirkkaat
## pyöristetyt painikkeet paksulla alareunalla (syvyys), kultainen otsikkonauha ja
## valkoinen teksti tummalla ääriviivalla.

# --- Palette ------------------------------------------------------------------

const GREEN := Color("6fd13a")
const GREEN_LIGHT := Color("8ee35c")
const GREEN_EDGE := Color("2f8a1c")
const BLUE := Color("3fa9f5")
const BLUE_LIGHT := Color("66bdff")
const BLUE_EDGE := Color("1d64b0")
const GOLD := Color("ffc12e")
const GOLD_LIGHT := Color("ffd45e")
const GOLD_EDGE := Color("c0700c")
const CORAL := Color("ff6a5a")
const CORAL_LIGHT := Color("ff8b7c")
const CORAL_EDGE := Color("b2352a")
const WOOD := Color("c57f45")
const WOOD_LIGHT := Color("d8975b")
const WOOD_EDGE := Color("6b3b17")
const PURPLE := Color("9a6cff")
const PURPLE_EDGE := Color("4a2aa0")

const FRAME := Color("9b5e2e")
const FRAME_EDGE := Color("5a3215")
const PAPER := Color("fff3d6")
const PAPER_EDGE := Color("e8c48a")
const INK := Color("5a3215")
const INK_SOFT := Color("8a6440")
const TEXT_OUTLINE := Color("3a1f0c")
const DISABLED := Color("b9ab98")
const DISABLED_EDGE := Color("857761")
const STAR := Color("ffd23f")
const STAR_EDGE := Color("b45309")

# Old names kept for scripts that still use them.
const ORANGE := GOLD
const ORANGE_LIGHT := GOLD_LIGHT
const ORANGE_DARK := Color("e8a21c")
const ORANGE_EDGE := GOLD_EDGE
const LOCKED_ORANGE := DISABLED
const LOCKED_EDGE := DISABLED_EDGE
const INNER := PAPER
const INNER_EDGE := PAPER_EDGE

const VARIANTS := {
	"primary": [GREEN, GREEN_LIGHT, GREEN_EDGE],
	"secondary": [BLUE, BLUE_LIGHT, BLUE_EDGE],
	"accent": [GOLD, GOLD_LIGHT, GOLD_EDGE],
	"danger": [CORAL, CORAL_LIGHT, CORAL_EDGE],
	"wood": [WOOD, WOOD_LIGHT, WOOD_EDGE],
	"purple": [PURPLE, Color("b291ff"), PURPLE_EDGE],
}

static var _font: Font = null
static var _font_regular: Font = null


## Paksu fontti (jos järjestelmästä ei löydy, käytetään oletusfonttia).
static func font() -> Font:
	if _font == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Arial Black", "Impact", "Roboto", "Arial"])
		system_font.font_weight = 900
		_font = system_font
	return _font


static func font_regular() -> Font:
	if _font_regular == null:
		var system_font := SystemFont.new()
		system_font.font_names = PackedStringArray(["Segoe UI", "Roboto", "Arial"])
		system_font.font_weight = 700
		_font_regular = system_font
	return _font_regular


static func box(bg: Color, edge: Color, radius: int, border: int, bottom: int = -1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(border)
	if bottom >= 0:
		b.border_width_bottom = bottom
	b.set_corner_radius_all(radius)
	b.anti_aliasing = true
	b.corner_detail = 10
	return b


static func _box(bg: Color, edge: Color, radius: int, border: int, bottom: int = -1) -> StyleBoxFlat:
	return box(bg, edge, radius, border, bottom)


## Valkoinen teksti tummalla ääriviivalla.
static func _style_text(control: Control, size: int, outline: int, outline_color: Color = TEXT_OUTLINE) -> void:
	control.add_theme_font_override("font", font())
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", Color.WHITE)
	control.add_theme_color_override("font_outline_color", outline_color)
	control.add_theme_constant_override("outline_size", outline)
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	control.add_theme_constant_override("shadow_offset_y", 3)
	control.add_theme_constant_override("shadow_offset_x", 0)


## Värillinen painike. `variant`: primary, secondary, accent, danger, wood, purple.
static func style_button(button: Button, font_size: int = 28, radius: int = 18, variant: String = "accent") -> void:
	var v: Array = VARIANTS.get(variant, VARIANTS["accent"])
	var base: Color = v[0]
	var light: Color = v[1]
	var edge: Color = v[2]
	var normal := box(base, edge, radius, 3, 9)
	normal.shadow_color = Color(0, 0, 0, 0.22)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 4)
	normal.content_margin_left = 22.0
	normal.content_margin_right = 22.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 10.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = light
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base.darkened(0.08)
	pressed.border_width_bottom = 4
	pressed.content_margin_top = 11.0
	pressed.content_margin_bottom = 5.0
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2(0, 1)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = DISABLED
	disabled.border_color = DISABLED_EDGE
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", _focus_box(radius))
	_style_text(button, font_size, 7, edge.darkened(0.35))
	for color_name in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.7))
	button.add_theme_color_override("icon_normal_color", Color.WHITE)


## Valkoinen teksti ääriviivalla (esim. HUD:n tekstit).
static func style_label(label: Label, size: int = 22) -> void:
	_style_text(label, size, 6)


## Tumma teksti kermanvärisellä paperilla.
static func style_ink(label: Label, size: int = 20) -> void:
	label.add_theme_font_override("font", font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_constant_override("outline_size", 0)


## Kenttäruutu (vanha nimi, käytetään yhä joissain paikoissa).
static func style_tile(button: Button) -> void:
	style_button(button, 40, 20, "accent")


static func _focus_box(radius: int) -> StyleBoxFlat:
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1, 1, 1, 0.95)
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(radius + 3)
	focus.expand_margin_left = 4.0
	focus.expand_margin_right = 4.0
	focus.expand_margin_top = 4.0
	focus.expand_margin_bottom = 4.0
	focus.anti_aliasing = true
	return focus


## Kultainen otsikkonauha, joka istuu paneelin yläreunan päällä.
static func style_header(label: Label, variant: String = "accent") -> void:
	style_ribbon(label, 34, variant)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.z_index = 1


static func style_ribbon(label: Label, size: int = 34, variant: String = "accent") -> void:
	var v: Array = VARIANTS.get(variant, VARIANTS["accent"])
	var b := box(v[0], v[2], 20, 4, 9)
	b.content_margin_left = 44.0
	b.content_margin_right = 44.0
	b.content_margin_top = 6.0
	b.content_margin_bottom = 10.0
	b.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	b.shadow_size = 8
	b.shadow_offset = Vector2(0.0, 5.0)
	label.add_theme_stylebox_override("normal", b)
	_style_text(label, size, 9, (v[2] as Color).darkened(0.35))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Puukehys (ulompi paneeli).
static func style_frame(panel: PanelContainer) -> void:
	var b := box(FRAME, FRAME_EDGE, 30, 6, 12)
	b.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	b.shadow_size = 18
	b.shadow_offset = Vector2(0.0, 10.0)
	b.content_margin_left = 14.0
	b.content_margin_right = 14.0
	b.content_margin_top = 14.0
	b.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", b)


## Kermanvärinen sisäpaneeli kehyksen sisällä.
static func style_inner(panel: PanelContainer) -> void:
	var b := box(PAPER, PAPER_EDGE, 20, 4)
	b.content_margin_left = 26.0
	b.content_margin_right = 26.0
	b.content_margin_top = 34.0
	b.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", b)


## Tumma läpikuultava HUD-pilleri.
static func style_pill(panel: PanelContainer, alpha: float = 0.55) -> void:
	var b := box(Color(0.08, 0.06, 0.16, alpha), Color(1, 1, 1, 0.18), 28, 3)
	b.content_margin_left = 16.0
	b.content_margin_right = 16.0
	b.content_margin_top = 6.0
	b.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", b)


## Pyöreä ikonipainike (tauko, takaisin, sulje...).
static func style_round_button(button: Button, variant: String = "accent", diameter: float = 64.0) -> void:
	style_button(button, 24, int(diameter * 0.5), variant)
	button.custom_minimum_size = Vector2(diameter, diameter + 4.0)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := button.get_theme_stylebox(state) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 0.0
			sb.content_margin_right = 0.0

extends Control
## Päävalikko ja taukovalikko (sama scene molempiin).
##
## Päävalikossa näkyy tasoruudukko ja oikealla paneeli (Pelaa, Poistu).
## Pelin aikana (tauko) näkyy vain oikea paneeli: Jatka, Aloita alusta, Päävalikkoon, Poistu.
##
## Valikko ei tee itse mitään: se lähettää signaalin kun painiketta painetaan ja
## pelin ohjain (game_manager.gd) reagoi niihin. Värit ja muodot ovat menu_style.gd:ssä.

signal play_requested
signal continue_requested
signal restart_requested
signal main_menu_requested
signal level_selected(index: int)
signal quit_requested

const MenuStyle := preload("res://scenes/ui/menu_style.gd")
const TileOverlay := preload("res://scenes/ui/tile_overlay.gd")

## Tasoruudukon vähimmäispaikkamäärä. Tyhjät paikat näytetään lukittuina.
@export var minimum_slots: int = 12
## Ruudukon sarakkeet.
@export var columns: int = 4
## Tasoruudun koko.
@export var tile_size: Vector2 = Vector2(96.0, 96.0)

@onready var _levels_frame: Control = %LevelsFrame
@onready var _levels_title: Label = %LevelsTitle
@onready var _levels_panel: PanelContainer = %LevelsPanel
@onready var _levels_inner: PanelContainer = %LevelsInner
@onready var _level_grid: GridContainer = %LevelGrid
@onready var _menu_title: Label = %MenuTitle
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _continue_button: Button = %ContinueButton
@onready var _play_button: Button = %PlayButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton

var _in_game: bool = false


func _ready() -> void:
	_apply_styles()
	_continue_button.pressed.connect(continue_requested.emit)
	_play_button.pressed.connect(play_requested.emit)
	_restart_button.pressed.connect(restart_requested.emit)
	_main_menu_button.pressed.connect(main_menu_requested.emit)
	_quit_button.pressed.connect(quit_requested.emit)
	set_in_game(false)


func _apply_styles() -> void:
	MenuStyle.style_header(_levels_title)
	MenuStyle.style_header(_menu_title)
	MenuStyle.style_frame(_levels_panel)
	MenuStyle.style_frame(_menu_panel)
	MenuStyle.style_inner(_levels_inner)
	for button in [_continue_button, _play_button, _restart_button, _main_menu_button, _quit_button]:
		MenuStyle.style_button(button as Button, 28)
	_level_grid.columns = columns


## Täyttää tasoruudukon. Jokaisesta nimestä tulee numeroitu ruutu, joka lähettää
## level_selected(indeksi). Loput paikat ovat lukittuja.
func set_levels(names: PackedStringArray) -> void:
	for child in _level_grid.get_children():
		child.queue_free()

	var slots := maxi(names.size(), minimum_slots)
	slots = int(ceil(float(slots) / float(columns))) * columns

	for i in slots:
		var tile := Button.new()
		tile.custom_minimum_size = tile_size
		MenuStyle.style_tile(tile)
		if i < names.size():
			tile.text = str(i + 1)
			tile.tooltip_text = names[i]
			tile.pressed.connect(level_selected.emit.bind(i))
		else:
			tile.disabled = true
			tile.focus_mode = Control.FOCUS_NONE
			var overlay := TileOverlay.new()
			overlay.locked = true
			tile.add_child(overlay)
		_level_grid.add_child(tile)

	_play_button.disabled = names.is_empty()


## Pelin aikana (tauko) näytetään Jatka / Aloita alusta / Päävalikkoon,
## päävalikossa tasoruudukko ja Pelaa.
func set_in_game(value: bool) -> void:
	_in_game = value
	_levels_frame.visible = not value
	_continue_button.visible = value
	_restart_button.visible = value
	_main_menu_button.visible = value
	_play_button.visible = not value
	_menu_title.text = "TAUKO" if value else "PÄÄVALIKKO"
	var first: Button = _continue_button if value else _play_button
	first.grab_focus.call_deferred()

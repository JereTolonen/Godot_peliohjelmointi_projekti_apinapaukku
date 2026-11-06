extends Node3D
## Pelin ohjain: listaa tasot, käynnistää ne ja hoitaa päävalikon.
##
## Missä tasot ovat:
##  1. Tähän sceneen suoraan asetetut solmut, joiden nimi alkaa sanalla "Level"
##     (esim. Level1). Ne siirretään pois pelistä alussa ja otetaan käyttöön vasta kun
##     pelaaja valitsee tason.
##  2. `levels`-listaan raahatut scenet (Inspector).
##  3. Kaikki scenet kansiossa `levels_folder` (aakkosjärjestyksessä).
##
## Ohjaus: ESC avaa tauko-/päävalikon ja sulkee sen. Valikon painikkeet:
## Jatka, Pelaa, Aloita alusta, Valitse taso, Päävalikkoon, Poistu.

const MainMenuScene := preload("res://scenes/ui/mainmenu.tscn")

## Lisätasot (scenet), jotka listataan valikkoon.
@export var levels: Array[PackedScene] = []
## Kansio, josta kaikki scenet haetaan automaattisesti tasoiksi.
@export_dir var levels_folder: String = "res://scenes/levels"
## Näytetäänkö päävalikko pelin alussa. Jos ei, ensimmäinen taso alkaa heti.
@export var open_menu_on_start: bool = true

var _menu_layer: CanvasLayer = null
var _menu: Control = null
## Jokainen taso: {"name": String, "scene": PackedScene tai null, "template": Node tai null}
var _entries: Array[Dictionary] = []
var _baseline: Array[Node] = []
var _level_node: Node = null
var _level_index: int = -1


func _ready() -> void:
	# Ohjain toimii myös tauolla, jotta ESC ja valikko toimivat.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Puun muokkaus vanhemman valmistuessa ei ole sallittua, joten tehdään alustus hetken päästä.
	_setup.call_deferred()


func _exit_tree() -> void:
	for entry in _entries:
		var template := entry["template"] as Node
		if template != null and is_instance_valid(template):
			template.free()


func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or not event.is_action_pressed("ui_cancel"):
		return
	if _menu.visible:
		if is_instance_valid(_level_node):
			resume()
	elif is_instance_valid(_level_node):
		_show_menu()
	get_viewport().set_input_as_handled()


# --- Alustus ----------------------------------------------------------------

func _setup() -> void:
	_collect_levels()
	_build_menu()

	# Muistetaan mitä pelin juuressa on ennen kuin yksikään taso on käynnissä,
	# jotta tason vaihdossa voidaan siivota ampumat kappaleet, roskat ja ponnahdukset.
	_baseline.clear()
	for child in get_parent().get_children():
		_baseline.append(child)

	if open_menu_on_start or _entries.is_empty():
		_show_menu()
	else:
		start_level(0)


func _collect_levels() -> void:
	var world := get_parent()
	var seen := {}

	# 1) Tähän sceneen suoraan asetetut tasot.
	for child in world.get_children():
		if child == self or not String(child.name).to_lower().begins_with("level"):
			continue
		_entries.append({
			"name": _pretty_name(String(child.name)),
			"scene": null,
			"template": child.duplicate(),
		})
		world.remove_child(child)
		child.queue_free()

	# 2) Inspectorissa annetut scenet.
	for scene in levels:
		if scene != null and not seen.has(scene.resource_path):
			seen[scene.resource_path] = true
			_entries.append({
				"name": _pretty_name(scene.resource_path.get_file().get_basename()),
				"scene": scene,
				"template": null,
			})

	# 3) Kansion scenet.
	for path in _scan_folder():
		if seen.has(path):
			continue
		seen[path] = true
		var scene := load(path) as PackedScene
		if scene != null:
			_entries.append({
				"name": _pretty_name(path.get_file().get_basename()),
				"scene": scene,
				"template": null,
			})


func _scan_folder() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(levels_folder)
	if dir == null:
		return found
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if clean.ends_with(".tscn") or clean.ends_with(".scn"):
			found.append(levels_folder.path_join(clean))
	found.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return found


## "Level1" -> "Taso 1", "level_2" -> "Taso 2", muut nimet saavat ison alkukirjaimen.
func _pretty_name(raw: String) -> String:
	var text := raw.replace("_", " ").replace("-", " ").strip_edges()
	if text.to_lower().begins_with("level"):
		var rest := text.substr(5).strip_edges()
		text = "Taso %s" % rest if not rest.is_empty() else "Taso"
	return text.substr(0, 1).to_upper() + text.substr(1)


func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 50
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu_layer)

	_menu = MainMenuScene.instantiate() as Control
	_menu_layer.add_child(_menu)

	var names := PackedStringArray()
	for entry in _entries:
		names.append(entry["name"] as String)
	_menu.call("set_levels", names)

	_menu.connect("play_requested", start_level.bind(0))
	_menu.connect("continue_requested", resume)
	_menu.connect("restart_requested", restart_level)
	_menu.connect("main_menu_requested", back_to_main_menu)
	_menu.connect("level_selected", start_level)
	_menu.connect("quit_requested", quit_game)


# --- Toiminnot (valikon painikkeet kutsuvat näitä) ---------------------------

## Käynnistää tason listan indeksillä.
func start_level(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_unload_level()

	var level := _create_level(_entries[index])
	if level == null:
		return
	level.name = "CurrentLevel"
	get_parent().add_child(level)
	_level_node = level
	_level_index = index
	_hide_menu()
	_reframe_camera()


func restart_level() -> void:
	start_level(_level_index)


## Sulkee valikon ja jatkaa peliä.
func resume() -> void:
	if is_instance_valid(_level_node):
		_hide_menu()


func back_to_main_menu() -> void:
	_unload_level()
	_show_menu()


func quit_game() -> void:
	get_tree().quit()


# --- Apufunktiot ------------------------------------------------------------

func _create_level(entry: Dictionary) -> Node:
	var scene := entry["scene"] as PackedScene
	if scene != null:
		return scene.instantiate()
	var template := entry["template"] as Node
	if template != null:
		return template.duplicate()
	return null


## Poistaa käynnissä olevan tason ja kaiken mitä peli on sen aikana lisännyt juureen
## (ammutut kappaleet, savut, hajonneiden palikoiden palat, pistepopupit).
func _unload_level() -> void:
	var world := get_parent()
	if is_instance_valid(_level_node):
		world.remove_child(_level_node)
		_level_node.queue_free()
	_level_node = null
	_level_index = -1

	for child in world.get_children():
		if not _baseline.has(child):
			child.queue_free()


func _show_menu() -> void:
	var in_game := is_instance_valid(_level_node)
	_menu.call("set_in_game", in_game)
	_menu.visible = true
	get_tree().paused = in_game


func _hide_menu() -> void:
	_menu.visible = false
	get_tree().paused = false


## Kamera asetetaan heti katsomaan uuden tason kaikkia vihollisia ja palikoita.
func _reframe_camera() -> void:
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.has_method("reframe_now"):
		cam.call("reframe_now", true)

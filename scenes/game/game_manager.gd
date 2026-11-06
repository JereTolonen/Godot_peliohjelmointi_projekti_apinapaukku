extends Node3D
## Pelin ohjain: listaa tasot, käynnistää ne, antaa ritsalle tason ammukset ja
## seuraa voittoa ja häviötä.
##
## Missä tasot ovat:
##  1. Tähän sceneen suoraan asetetut solmut, joiden nimi alkaa sanalla "Level"
##     (esim. Level1). Ne siirretään pois pelistä alussa ja otetaan käyttöön vasta kun
##     pelaaja valitsee tason. Jos sama taso löytyy myös omana scenenään, käytetään
##     sitä ja tähän sceneen jäänyt kopio ohitetaan.
##  2. `levels`-listaan raahatut scenet (Inspector).
##  3. Kaikki scenet kansiossa `levels_folder` (aakkosjärjestyksessä).
##
## Ammukset: jos tason juuressa on level.gd, sen `ammo`-lista määrää ammusten järjestyksen
## (esim. normal, normal, normal, exploding). Ilman listaa ammuksia on loputtomasti.
##
## Voitto: kaikki apinat (ryhmä "enemies") on kaadettu.
## Häviö: ammukset on käytetty, mikään ei enää lennä eikä vedä, ja apinoita on yhä jäljellä.
##
## Ohjaus: ESC avaa tauko-/päävalikon ja sulkee sen.

enum State { MENU, PLAYING, WON, LOST }

const MainMenuScene := preload("res://scenes/ui/mainmenu.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")

## Lisätasot (scenet), jotka listataan valikkoon.
@export var levels: Array[PackedScene] = []
## Kansio, josta kaikki scenet haetaan automaattisesti tasoiksi.
@export_dir var levels_folder: String = "res://scenes/levels"
## Näytetäänkö päävalikko pelin alussa. Jos ei, ensimmäinen taso alkaa heti.
@export var open_menu_on_start: bool = true
## Sekuntia viimeisen apinan kaatumisesta voittoruutuun (ehtii näkyä pistepopup).
@export var win_delay: float = 1.2
## Sekuntia siitä kun ammukset on käytetty eikä mikään enää liiku, häviöruutuun.
@export var lose_delay: float = 2.5

var state: State = State.MENU

var _menu_layer: CanvasLayer = null
var _menu: Control = null
var _hud_layer: CanvasLayer = null
var _hud: Control = null
## Jokainen taso: {"name": String, "scene": PackedScene tai null, "template": Node tai null}
var _entries: Array[Dictionary] = []
var _baseline: Array[Node] = []
var _level_node: Node = null
var _level_index: int = -1
var _slingshot: Node = null
var _level_age: float = 0.0
var _win_timer: float = 0.0
var _idle_time: float = 0.0


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
	# Tauon voi avata ja sulkea vain kesken pelin (ei tulosruudussa eikä päävalikossa).
	if state == State.PLAYING:
		if _menu.visible:
			resume()
		else:
			_show_menu()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state != State.PLAYING or get_tree().paused:
		return

	_level_age += delta
	if _level_age < 1.0:
		return

	# Voitto: kaikki apinat kaadettu.
	if _count_enemies() == 0:
		_win_timer += delta
		if _win_timer >= win_delay:
			_finish(true)
		return

	# Häviö: ammukset loppu, mikään ei lennä eikä vedä, apinoita jäljellä.
	if is_instance_valid(_slingshot) \
			and not bool(_slingshot.call("has_ammo")) \
			and not bool(_slingshot.call("is_busy")):
		_idle_time += delta
		if _idle_time >= lose_delay:
			_finish(false)
	else:
		_idle_time = 0.0


# --- Alustus ----------------------------------------------------------------

func _setup() -> void:
	_collect_levels()
	_build_menu()
	_build_hud()

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

	# 1) Tähän sceneen suoraan asetetut tasot. Ne otetaan aina pois pelistä alussa.
	# Jos sama taso löytyy myös omana scenenään, käytetään sitä eikä tähän sceneen
	# jäänyttä kopiota.
	var scene_names := _scene_level_names()
	for child in world.get_children():
		if child == self or not String(child.name).to_lower().begins_with("level"):
			continue
		var pretty := _pretty_name(String(child.name))
		if not scene_names.has(pretty):
			_entries.append({
				"name": pretty,
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


## Valikossa näkyvät nimet kaikista scene-tiedostoina olevista tasoista.
func _scene_level_names() -> Dictionary:
	var names := {}
	for scene in levels:
		if scene != null:
			names[_pretty_name(scene.resource_path.get_file().get_basename())] = true
	for path in _scan_folder():
		names[_pretty_name(path.get_file().get_basename())] = true
	return names


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
	_menu.connect("next_requested", next_level)
	_menu.connect("main_menu_requested", back_to_main_menu)
	_menu.connect("level_selected", start_level)
	_menu.connect("quit_requested", quit_game)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 40
	_hud_layer.visible = false
	add_child(_hud_layer)

	_hud = HudScene.instantiate() as Control
	_hud_layer.add_child(_hud)


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

	state = State.PLAYING
	_level_age = 0.0
	_win_timer = 0.0
	_idle_time = 0.0
	_give_ammo(level)
	_hide_menu()
	_reframe_camera()


func restart_level() -> void:
	start_level(_level_index)


func next_level() -> void:
	start_level(_level_index + 1)


## Sulkee valikon ja jatkaa peliä.
func resume() -> void:
	if state == State.PLAYING and is_instance_valid(_level_node):
		_hide_menu()


func back_to_main_menu() -> void:
	_unload_level()
	state = State.MENU
	_show_menu()


func quit_game() -> void:
	get_tree().quit()


# --- Voitto ja häviö ---------------------------------------------------------

func _count_enemies() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node.is_queued_for_deletion():
			count += 1
	return count


func _finish(won: bool) -> void:
	state = State.WON if won else State.LOST
	var has_next := won and _level_index + 1 < _entries.size()
	_menu.call("set_result", won, has_next)
	_menu.visible = true
	_hud_layer.visible = false
	get_tree().paused = true


## Antaa ritsalle tason ammukset (level.gd:n `ammo`-lista) ja kytkee HUD:n siihen.
func _give_ammo(level: Node) -> void:
	_slingshot = get_tree().get_first_node_in_group("slingshot")
	var names := PackedStringArray()
	var configured: Variant = level.get("ammo")
	if configured is PackedStringArray:
		names = configured
	if _slingshot != null:
		_slingshot.call("set_ammo", names)
	_hud.call("bind", _slingshot)


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
	_slingshot = null
	_hud.call("bind", null)

	for child in world.get_children():
		if not _baseline.has(child):
			child.queue_free()


func _show_menu() -> void:
	var in_game := state == State.PLAYING and is_instance_valid(_level_node)
	_menu.call("set_in_game", in_game)
	_menu.visible = true
	_hud_layer.visible = false
	get_tree().paused = in_game


func _hide_menu() -> void:
	_menu.visible = false
	_hud_layer.visible = is_instance_valid(_level_node)
	get_tree().paused = false


## Kamera asetetaan heti katsomaan uuden tason kaikkia vihollisia ja palikoita.
func _reframe_camera() -> void:
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.has_method("reframe_now"):
		cam.call("reframe_now", true)

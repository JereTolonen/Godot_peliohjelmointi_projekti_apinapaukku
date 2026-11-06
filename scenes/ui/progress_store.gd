extends RefCounted
## Tallennus: kenttien parhaat tähdet ja pisteet, läpäistyt kentät ja asetukset.
## Tallennetaan user://-kansioon (Windowsissa %APPDATA%/Godot/app_userdata/Apinapaukku).
##
## Kentät aukeavat järjestyksessä: ensimmäinen on aina auki, ja kenttä aukeaa kun
## edellinen on läpäisty.

const PATH := "user://progress.cfg"
const SETTINGS_PATH := "user://settings.cfg"

static var _config: ConfigFile = null
static var _settings: ConfigFile = null


static func _load() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(PATH)
	return _config


static func stars(index: int) -> int:
	return int(_load().get_value("stars", str(index), 0))


static func best_score(index: int) -> int:
	return int(_load().get_value("score", str(index), 0))


static func is_completed(index: int) -> bool:
	return stars(index) > 0


## Onko kenttä pelattavissa (ensimmäinen aina, muut kun edellinen on läpäisty).
static func is_unlocked(index: int) -> bool:
	return index <= 0 or is_completed(index - 1) or is_completed(index)


## Läpäistyjen kenttien määrä.
static func completed_count(count: int) -> int:
	var n := 0
	for i in count:
		if is_completed(i):
			n += 1
	return n


static func total_stars(count: int) -> int:
	var total := 0
	for i in count:
		total += stars(i)
	return total


## Ensimmäinen kenttä, jota ei ole vielä läpäisty (tai viimeinen, jos kaikki on).
static func next_unfinished(count: int) -> int:
	for i in count:
		if not is_completed(i):
			return i
	return maxi(count - 1, 0)


## Tallentaa tuloksen. Palauttaa true, jos tähtiä tai pisteitä tuli enemmän kuin ennen.
static func record(index: int, new_stars: int, score: int) -> bool:
	var config := _load()
	var improved := false
	if new_stars > stars(index):
		config.set_value("stars", str(index), new_stars)
		improved = true
	if score > best_score(index):
		config.set_value("score", str(index), score)
		improved = true
	if improved:
		config.save(PATH)
	return improved


static func reset() -> void:
	_config = ConfigFile.new()
	_config.save(PATH)


# --- Settings -------------------------------------------------------------------

static func _load_settings() -> ConfigFile:
	if _settings == null:
		_settings = ConfigFile.new()
		_settings.load(SETTINGS_PATH)
	return _settings


static func get_setting(key: String, default: Variant) -> Variant:
	return _load_settings().get_value("settings", key, default)


static func set_setting(key: String, value: Variant) -> void:
	_load_settings().set_value("settings", key, value)
	_settings.save(SETTINGS_PATH)


## Ottaa tallennetut asetukset käyttöön (äänenvoimakkuus, koko näyttö, varjot).
static func apply_settings(tree: SceneTree) -> void:
	var volume := float(get_setting("volume", 0.8))
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
		AudioServer.set_bus_mute(bus, volume <= 0.001)
	if not OS.has_feature("mobile") and not OS.has_feature("editor_hint"):
		var fullscreen := bool(get_setting("fullscreen", false))
		var mode := DisplayServer.window_get_mode()
		var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen != is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var shadows := bool(get_setting("shadows", true))
	for light in tree.root.find_children("*", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).shadow_enabled = shadows

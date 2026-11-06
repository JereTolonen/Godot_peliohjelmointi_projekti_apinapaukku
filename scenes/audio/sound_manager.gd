extends Node
## Äänet (autoload "SoundManager").
##
## Soittaa tiedostoja kansiosta res://assets/sounds tapahtuman nimen mukaan:
##   <tapahtuma>.ogg / .wav / .mp3      esim. launch.ogg
##   <tapahtuma>_2.ogg, _3.ogg ...      vaihtoehtoja, joista arvotaan yksi (vaihtelua)
## Puuttuva tiedosto ei ole virhe: tapahtuma on silloin vain hiljaa.
##
## Kytkeytyy peliin itse (kuten VisualDirector): ritsa, palikat, apinat, räjähdykset,
## painikkeet ja kentän alku/loppu. Pelilogiikkaa ei muuteta, äänet vain kuuntelevat
## olemassa olevia signaaleja.
##
## Tapahtumat (tiedostonimet): katso SOUNDS.md projektin juuresta.

const DIR := "res://assets/sounds/"
const EXTENSIONS := ["ogg", "wav", "mp3"]
const ArtStyle := preload("res://scenes/visual/art_style.gd")
const EXPLOSION_SCRIPT := "res://scenes/includes/explosion.gd"

## Äänenvoimakkuudet (dB) tapahtumaryhmittäin.
const VOLUMES := {"ui": -6.0, "music": -14.0, "default": -3.0}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _music: AudioStreamPlayer = null
var _music_name: String = ""
var _last_played: Dictionary = {}
var _slingshots: Array = []
var _dragging: Dictionary = {}
var _last_state: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = VOLUMES["music"]
	add_child(_music)
	_music.finished.connect(func() -> void: _music.play())
	get_tree().node_added.connect(_on_node_added)


## Soittaa tapahtuman äänen (jos tiedosto on olemassa).
## `min_interval` estää saman äänen toistumisen liian tiheään (sekunteina).
func play(event: String, volume_db: float = 0.0, pitch_spread: float = 0.08, min_interval: float = 0.04, pitch: float = 1.0) -> void:
	var stream := _stream(event)
	if stream == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last_played.get(event, -10.0)) < min_interval:
		return
	_last_played[event] = now
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	var group := "ui" if event.begins_with("ui_") else "default"
	p.volume_db = float(VOLUMES[group]) + volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_spread, pitch_spread))
	p.play()


## Vaihtaa taustamusiikin (sama nimi = jatkaa soittamista).
func play_music(event: String) -> void:
	if event == _music_name:
		return
	_music_name = event
	var stream := _stream(event)
	if stream == null:
		_music.stop()
		return
	_music.stream = stream
	_music.play()


## Kaikki tiedostot, jotka löytyvät tapahtumalle (päänimi + _2, _3 ...). Välimuistissa.
func _stream(event: String) -> AudioStream:
	if not _cache.has(event):
		var list: Array = []
		for suffix in ["", "_2", "_3", "_4", "_5"]:
			for ext in EXTENSIONS:
				var path := "%s%s%s.%s" % [DIR, event, suffix, ext]
				if ResourceLoader.exists(path):
					var s := load(path) as AudioStream
					if s != null:
						list.append(s)
					break
		_cache[event] = list
	var streams: Array = _cache[event]
	if streams.is_empty():
		return null
	return streams[randi() % streams.size()]


# --- Hooks ---------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.pressed.connect(func() -> void: play("ui_click"))
		button.mouse_entered.connect(func() -> void:
			if is_instance_valid(button) and not button.disabled:
				play("ui_hover", -4.0, 0.05, 0.08))
		return
	if node.has_signal("ability_activated") and node.has_signal("character_shot"):
		node.connect("character_shot", func(_scene: PackedScene, _instance: Node3D) -> void: play("launch"))
		node.connect("character_impact", func(_instance: Node3D, _pos: Vector3) -> void: play("bird_hit", -2.0, 0.1, 0.12))
		node.connect("ability_activated", _on_ability)
		_slingshots.append(weakref(node))
		return
	if node.has_signal("broken") and "debris_color" in node:
		var kind := ArtStyle.block_kind(node)
		node.connect("broken", func() -> void: play("break_" + kind, 0.0, 0.1, 0.06))
		node.connect("damaged", func(_health: float) -> void: play("hit_" + kind, -4.0, 0.12, 0.1))
		return
	if node.has_signal("died"):
		node.connect("died", func(_points: int) -> void: play("monkey_pop", 0.0, 0.12, 0.05))
		if node.has_signal("hurt"):
			node.connect("hurt", func(_h: int, _m: int) -> void:
				play("boss_hit")
				play("boss_hurt", -4.0, 0.08, 0.3, 1.25))
		return
	var script := node.get_script() as Script
	if script != null and script.resource_path == EXPLOSION_SCRIPT:
		play("explosion", 0.0, 0.1, 0.05)
	elif node.name == &"CurrentLevel" and node.get_parent() == get_tree().current_scene:
		play("level_start")


func _on_ability(kind: String, _position: Vector3) -> void:
	if _stream("ability_" + kind) != null:
		play("ability_" + kind)
	else:
		play("ability")


func _process(_delta: float) -> void:
	# Rubber band stretch when a drag starts.
	for ref in _slingshots.duplicate():
		var s: Node = (ref as WeakRef).get_ref()
		if s == null:
			_slingshots.erase(ref)
			continue
		var dragging := bool(s.get("_dragging"))
		var id := s.get_instance_id()
		if dragging and not bool(_dragging.get(id, false)):
			play("stretch", -2.0, 0.05)
		_dragging[id] = dragging

	# Music and win/lose jingles from the game state.
	var root := get_tree().current_scene
	if root == null:
		return
	var in_level := root.get_node_or_null("CurrentLevel") != null
	var gm := root.get_node_or_null("GameController")
	var state := int(gm.get("state")) if gm != null and "state" in gm else 0
	# 2 = won, 3 = lost (game_manager.gd): the jingle plays instead of music.
	if state != 2 and state != 3:
		play_music("music_game" if in_level else "music_menu")
	if gm != null:
		if state != _last_state:
			if state == 2:
				_music.stop()
				_music_name = ""
				play("win", 0.0, 0.0)
			elif state == 3:
				_music.stop()
				_music_name = ""
				play("lose", 0.0, 0.0)
			_last_state = state

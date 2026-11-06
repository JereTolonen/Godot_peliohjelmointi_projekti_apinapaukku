extends Node
## Apinan "aivot": pelko, puhekuplat ja AFK-kaaos. Vain apinan MALLI liikkuu, ei
## fysiikkakappale, joten linnoitukset eivät kaadu. enemy_plain.gd lisää tämän
## automaattisesti jokaiselle tavalliselle apinalle.
##
##  - Pelko: kun banaania tähdätään tai se lentää kohti, apina tärisee, kyyristyy ja
##    kallistuu poispäin. Mitä lähempänä banaani, sitä kovempi pelko.
##  - Puhekuplat: välillä apina sanoo jotain (lentävä banaani, tähtäys, ohi mennyt
##    laukaus, kaveri kaatui, tylsistynyt jutustelu, AFK-bileet).
##  - AFK-kaaos: jos pelaaja ei tee mitään `afk_delay` sekuntiin, apinat alkavat
##    pyöriä, pomppia ja tanssia yhä hullummin.

const SpeechBubble := preload("res://scenes/ui/speech_bubble.gd")

## Sekunteja ilman syötettä ennen kuin kaaos alkaa.
@export var afk_delay: float = 6.0
## Sekunteja, joiden aikana kaaos yltyy täysille.
@export var ramp_time: float = 12.0
## Etäisyys (m), jolta apina alkaa pelätä lentävää banaania.
@export var fear_radius: float = 9.0
## Kuplan korkeus apinan jalkojen yläpuolella.
@export var bubble_height: float = 2.1

const LINES_SCARED := ["Voi ei...", "Apuaa!", "Banaani tulee!", "Äitiii!", "AAAAH!", "Ei banaania!", "Väistä!", "Ei naamaan!"]
const LINES_AIM := ["Älä ammu!", "Voi ei...", "Ei kai se...?", "Laske se alas!", "Me ollaan kilttejä!", "Oho...", "Ei tänään, kiitos."]
const LINES_AIM_TARGETED := ["Ei mua!", "Voi ei...", "Tähtää jotain muuta!", "Miks aina minä?!", "Mä oon liian nuori!", "Pertti, vaihdetaan paikkaa!"]
const LINES_RELIEF := ["Huh! Ohi meni.", "Hah, ohi!", "Ei osunut!", "Huhhuh...", "Liian lähellä!", "Tähtää paremmin!"]
const LINES_FRIEND := ["Ei! Pertti!", "Voi ei...", "Se sai Pertin!", "Kuka on seuraava?", "Lepää rauhassa...", "Mä haluun kotiin!"]
const LINES_IDLE := ["Banaaneja? Yäk.", "Mitähän tuo ritsa tekee?", "Hih hih.", "Ollaan hiljaa...", "Kuka söi mun banaanin?", "Tylsää...", "Onks tää turvallista?"]
const LINES_AFK := ["Jihuu!", "Pelaaja nukahti!", "Bileet!", "Jippii!", "Kukaan ei katso!", "Tanssitaan!"]

const MOVES := ["spin", "spin", "hop", "flip", "wiggle", "dance", "tornado"]

## Yhteistä kaikille apinoille.
static var _last_input_msec: int = -1
static var _next_chatter_msec: int = 0
static var _last_line_msec: int = 0
static var _death_count: int = 0
static var _death_pos: Vector3 = Vector3.ZERO

var _monkey: Node3D = null
var _model: Node3D = null
var _rest: Transform3D = Transform3D.IDENTITY
## Pyörähdysten keskipiste (mallin keskikohta), jotta voltit eivät pyöri jalkojen ympäri.
var _pivot: Vector3 = Vector3(0.0, 0.8, 0.0)
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0

var _fear: float = 0.0
var _fear_side: float = 1.0
var _was_scared: bool = false
var _scared_line_said: bool = false
var _aim_line_said: bool = false
var _relief_timer: float = -1.0
var _seen_deaths: int = 0

var _move: String = ""
var _move_time: float = 0.0
var _move_length: float = 1.0
var _turns: float = 1.0
var _cooldown: float = 0.0


## Sekunteja edellisestä pelaajan syötteestä.
static func afk_seconds() -> float:
	if _last_input_msec < 0:
		_last_input_msec = Time.get_ticks_msec()
	return float(Time.get_ticks_msec() - _last_input_msec) / 1000.0


static func register_input() -> void:
	_last_input_msec = Time.get_ticks_msec()


## enemy_plain.gd kutsuu tätä, kun apina kaatuu: lähellä olevat kaverit reagoivat.
static func on_monkey_died(at: Vector3) -> void:
	_death_count += 1
	_death_pos = at


func _ready() -> void:
	_rng.randomize()
	afk_seconds()
	_seen_deaths = _death_count
	_monkey = get_parent() as Node3D
	_model = _find_model()
	if _model == null or _monkey == null:
		set_process(false)
		return
	_rest = _model.transform
	var shape := _monkey.get_node_or_null("CollisionShape3D") as Node3D
	if shape != null:
		_pivot = shape.position
	_cooldown = _rng.randf_range(0.0, 1.5)
	var now := Time.get_ticks_msec()
	if _next_chatter_msec < now:
		_next_chatter_msec = now + _rng.randi_range(5000, 9000)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventScreenTouch or event is InputEventScreenDrag \
			or event is InputEventKey or event is InputEventJoypadButton:
		register_input()


func _find_model() -> Node3D:
	for child in get_parent().get_children():
		if child is Node3D and not (child is CollisionShape3D) and not (child is Label3D):
			return child as Node3D
	return null


func _process(delta: float) -> void:
	_time += delta
	_update_fear(delta)
	_update_chatter(delta)

	# Pelko menee kaiken muun edelle.
	if _fear > 0.03:
		_move = ""
		var tremble := sin(_time * 47.0) * 0.07 * _fear
		var rot := Vector3(0.0, sin(_time * 31.0) * 0.05 * _fear, -_fear_side * 0.38 * _fear + tremble)
		_apply(rot, 0.0, 1.0 - 0.18 * _fear)
		return

	var afk := afk_seconds()
	# Pelaaja on paikalla: liu'utaan nopeasti takaisin lepoasentoon.
	if afk < afk_delay:
		if _move != "" or not _model.transform.is_equal_approx(_rest):
			_move = ""
			_model.transform = _model.transform.interpolate_with(_rest, 1.0 - exp(-14.0 * delta))
		return

	_update_chaos(delta, clampf((afk - afk_delay) / ramp_time, 0.0, 1.0))


# --- Pelko --------------------------------------------------------------------

func _update_fear(delta: float) -> void:
	var target := 0.0
	var aiming := false
	var me := _monkey.global_position + _pivot
	for node in get_tree().get_nodes_in_group("bananas"):
		var banana := node as RigidBody3D
		if banana == null or not is_instance_valid(banana):
			continue
		var to_me := me - banana.global_position
		to_me.z = 0.0
		var dist := to_me.length()
		if banana.freeze:
			# Banaania tähdätään ritsassa: pelko kasvaa vedon voimakkuuden mukaan, ja
			# apina, jota tähtäyslinja osoittaa, panikoi kunnolla.
			aiming = true
			var aim := _aim_fear(banana, me)
			if aim > target:
				target = aim
				_fear_side = signf(to_me.x) if absf(to_me.x) > 0.01 else 1.0
			continue
		if dist > fear_radius:
			continue
		var closeness := 1.0 - dist / fear_radius
		var approaching := banana.linear_velocity.dot(to_me) > 0.0
		var f := closeness * (1.0 if approaching else 0.45)
		if f > target:
			target = f
			_fear_side = signf(to_me.x) if absf(to_me.x) > 0.01 else 1.0

	var rate := 10.0 if target > _fear else 3.0
	_fear = lerpf(_fear, target, 1.0 - exp(-rate * delta))

	# Kuplat pelon mukaan. Tähtäyksen kohteeksi joutunut apina sanoo jotain herkemmin.
	if aiming and not _aim_line_said:
		if target > 0.65:
			_aim_line_said = true
			if _rng.randf() < 0.5:
				_say_from(LINES_AIM_TARGETED, 0.4, 1.6, "monkey_ooh")
		elif target > 0.3 and _rng.randf() < 0.004:
			_aim_line_said = true
			_say_from(LINES_AIM, 0.8)
	if not aiming:
		_aim_line_said = false
	if target > 0.55 and not aiming:
		_was_scared = true
		_relief_timer = -1.0
		if not _scared_line_said:
			_scared_line_said = true
			if _rng.randf() < 0.45:
				_say_from(LINES_SCARED, 0.6, 1.4, "monkey_scared")
	elif _was_scared and target < 0.1:
		# Banaani meni ohi ja apina on yhä pystyssä.
		_was_scared = false
		_scared_line_said = false
		_relief_timer = _rng.randf_range(0.6, 1.2)
	if _relief_timer >= 0.0:
		_relief_timer -= delta
		if _relief_timer < 0.0 and _rng.randf() < 0.4:
			_say_from(LINES_RELIEF, 0.8)


## Pelko tähtäyksen aikana: 0.2 aina, lisää vedon voimakkuuden mukaan ja paljon lisää,
## jos ennustettu lentorata kulkee apinan läheltä.
func _aim_fear(banana: RigidBody3D, me: Vector3) -> float:
	var sling := get_tree().get_first_node_in_group("slingshot")
	if sling == null or not sling.has_method("_launch_velocity"):
		return 0.3
	var max_pull := maxf(float(sling.get("max_pull")), 0.01)
	var pull := clampf((sling.get("_pull") as Vector3).length() / max_pull, 0.0, 1.0)
	if pull < 0.1:
		return 0.2
	var velocity: Vector3 = sling.call("_launch_velocity")
	var g := float(sling.get("gravity"))
	# Ennustetaan lentorata ja katsotaan, kuinka läheltä se ohittaa apinan.
	# Laukaus lähtee ritsan haarukasta (slingshot_controller._anchor), ei banaanin kohdasta.
	var start: Vector3 = sling.call("_anchor") if sling.has_method("_anchor") else banana.global_position
	var closest := INF
	var t := 0.0
	while t < 3.0:
		var p := start + velocity * t + Vector3(0.0, -0.5 * g * t * t, 0.0)
		closest = minf(closest, Vector2(p.x - me.x, p.y - me.y).length())
		if p.y < me.y - 6.0:
			break
		t += 0.04
	var targeted := clampf(1.0 - (closest - 0.6) / 2.5, 0.0, 1.0)
	return clampf(0.2 + 0.25 * pull + 0.6 * targeted * pull, 0.0, 1.0)


# --- Puhekuplat -------------------------------------------------------------

func _update_chatter(_delta: float) -> void:
	# Kaveri kaatui lähellä.
	if _death_count != _seen_deaths:
		_seen_deaths = _death_count
		var d := (_death_pos - _monkey.global_position).length()
		if d < 7.0 and _rng.randf() < 0.45:
			_say_from(LINES_FRIEND, 1.0, 2.2, "monkey_scared")

	var now := Time.get_ticks_msec()
	if now < _next_chatter_msec:
		return
	# Ensimmäinen apina, joka huomaa ajan tulleen, saa puheenvuoron.
	_next_chatter_msec = now + _rng.randi_range(7000, 14000)
	if _fear > 0.1:
		return
	if afk_seconds() > afk_delay:
		_say_from(LINES_AFK, 0.0)
	elif _rng.randf() < 0.6:
		_say_from(LINES_IDLE, 2.0, 2.6)


## Sanoo satunnaisen repliikin, jos edellisestä kuplasta on kulunut `min_gap` sekuntia.
func _say_from(lines: Array, min_gap: float, time: float = 2.2, sound: String = "monkey_talk") -> void:
	var now := Time.get_ticks_msec()
	if float(now - _last_line_msec) / 1000.0 < min_gap:
		return
	if SpeechBubble.say(_monkey, lines[_rng.randi() % lines.size()], time, bubble_height, sound, _rng.randf_range(1.25, 1.5)) != null:
		_last_line_msec = now


# --- AFK-kaaos ----------------------------------------------------------------

func _update_chaos(delta: float, chaos: float) -> void:
	if _move == "":
		_cooldown -= delta * (1.0 + chaos * 3.0)
		# Odottaessa pientä levotonta heilumista.
		var fidget := Vector3(0.0, sin(_time * 3.0) * 0.25 * (0.3 + chaos), sin(_time * 5.0) * 0.06)
		_apply(fidget, 0.0, 1.0)
		if _cooldown <= 0.0:
			_start_move(chaos)
		return

	_move_time += delta
	var p := clampf(_move_time / _move_length, 0.0, 1.0)
	var e := p * p * (3.0 - 2.0 * p)
	var rot := Vector3.ZERO
	var lift := 0.0
	var squash := 1.0
	match _move:
		"spin":
			rot.y = TAU * _turns * e
		"hop":
			lift = sin(PI * p) * (0.5 + chaos * 0.5)
			rot.y = TAU * 0.5 * e * _turns
			squash = 1.0 + sin(PI * p) * 0.15
		"flip":
			lift = sin(PI * p) * (0.7 + chaos * 0.5)
			rot.x = TAU * e
		"wiggle":
			rot.z = sin(_move_time * 28.0) * 0.35 * (1.0 - p * 0.5)
			squash = 1.0 + sin(_move_time * 20.0) * 0.12
		"dance":
			rot.y = sin(_move_time * 8.0) * 0.9
			rot.z = sin(_move_time * 8.0 + 1.5) * 0.25
			lift = absf(sin(_move_time * 8.0)) * 0.25
		"tornado":
			# Kiihtyvä pyörre: kierrosnopeus kasvaa loppua kohti.
			rot.y = TAU * _turns * p * p
			rot.z = sin(_move_time * 14.0) * 0.15
			lift = sin(PI * p) * 0.3
	_apply(rot, lift, squash)

	if p >= 1.0:
		_move = ""
		_model.transform = _rest
		_cooldown = _rng.randf_range(0.4, 2.8) * (1.0 - chaos * 0.75)


func _start_move(chaos: float) -> void:
	_move = MOVES[_rng.randi() % MOVES.size()]
	# Alussa vain pyörähdyksiä, hullummat liikkeet tulevat kun kaaos yltyy.
	if chaos < 0.25 and _move in ["flip", "tornado"]:
		_move = "spin"
	_move_time = 0.0
	var speed := 1.0 + chaos * 0.8
	_turns = (1.0 if _rng.randf() < 0.5 else -1.0) * float(_rng.randi_range(1, 2 + int(chaos * 3.0)))
	match _move:
		"spin":
			_move_length = 0.7 * absf(_turns) / speed
		"hop":
			_move_length = 0.6 / speed
		"flip":
			_move_length = 0.75 / speed
		"wiggle":
			_move_length = 0.8
		"dance":
			_move_length = 1.6
		"tornado":
			_turns *= 3.0
			_move_length = 2.0
			if _rng.randf() < 0.3:
				_say_from(LINES_AFK, 1.5, 1.6)


## Lepoasento + kierto keskipisteen ympäri + nosto + litistys.
func _apply(rot: Vector3, lift: float, squash: float) -> void:
	var spin := Basis.from_euler(rot)
	var pivot := Transform3D(Basis.IDENTITY, _pivot)
	var offset := Transform3D(spin, Vector3(0.0, lift, 0.0))
	var stretch := Transform3D(Basis.from_scale(Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))), Vector3.ZERO)
	_model.transform = pivot * offset * pivot.affine_inverse() * stretch * _rest

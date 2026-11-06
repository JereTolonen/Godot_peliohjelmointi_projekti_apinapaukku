extends "res://scenes/includes/characters/enemy_plain.gd"
## Boss enemy: survives several hits.
##
## Every shot or blast that would kill a normal enemy only takes away health here.
## Stronger hits (faster shots, blasts) do more damage. The kill zone still kills it
## at once. Needs a "Visual" Node3D (scaled for the hit punch) and optionally a
## "HealthLabel" Label3D.

signal hurt(health: int, max_health: int)

const SpeechBubble := preload("res://scenes/ui/speech_bubble.gd")
const GridWall := preload("res://scenes/visual/grid_wall.gd")
const BOSS_HURT_LINES := ["Auts!", "Grrr!", "Tuo sattui!", "Et voita minua!", "Mun hattu!", "Banaaneja?! Taas?!"]
const BOSS_LOW_LINES := ["Voi ei...", "Armoa!", "Okei, okei!", "Mä luovutan... ehkä."]

## Health of the boss.
@export var max_health: int = 6
## Seconds after a hit during which further hits are ignored (so one blast is one hit).
@export var hit_cooldown: float = 0.35
## Hit strength per extra point of damage (a shot of speed 21 does 2 damage by default).
@export var damage_speed_step: float = 10.0

@export_group("Jumping")
## Pomo hyppii itsekseen.
@export var jumping: bool = true
## Odotusaika hyppyjen välillä (sekunteina, satunnainen väliltä).
@export var jump_interval: Vector2 = Vector2(1.6, 3.2)
## Tavallisen hypyn lähtönopeus ylöspäin (m/s).
@export var jump_speed: float = 6.5
## Ison pyörähdyshypyn lähtönopeus.
@export var big_jump_speed: float = 9.5
## Kuinka kauas aloituspaikasta pomo saa hyppiä sivusuunnassa (m).
@export var hop_range: float = 0.9
## Ensimmäinen hyppy vasta tämän jälkeen (kenttä ehtii asettua).
@export var first_jump_delay: float = 2.5

var health: int = 0
## Kun true, osumat eivät vahingoita (kristallikilpi).
var shielded: bool = false

var _hit_cooldown_left: float = 0.0
var _visual: Node3D = null
var _wobble: Node3D = null
var _label: Label3D = null
var _punch_tween: Tween = null

var _home_x: float = 0.0
var _jump_wait: float = 0.0
var _crouch_left: float = -1.0
var _pending_speed: float = 0.0
var _pending_spin: bool = false
var _extra_hops: int = 0
## Oman hypyn aikana kovat nopeudenmuutokset (lähtö, lasku) eivät vahingoita.
var _self_jump_left: float = 0.0
var _in_air: bool = false
var _air_time: float = 1.0
var _air_elapsed: float = 0.0
var _afk_laughed: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	health = max_health
	_visual = get_node_or_null("Visual") as Node3D
	_wobble = get_node_or_null("Visual/Wobble") as Node3D
	_label = get_node_or_null("HealthLabel") as Label3D
	_update_label()
	_rng.randomize()
	_home_x = global_position.x
	# Hyppivä pomo pysyy pystyssä (ei kierähdä kyljelleen laskeutuessaan).
	if jumping:
		axis_lock_angular_z = true
		rotation.z = 0.0
	_jump_wait = first_jump_delay + _rng.randf_range(0.0, 1.0)


func _physics_process(delta: float) -> void:
	_hit_cooldown_left = maxf(_hit_cooldown_left - delta, 0.0)
	if _alive and jumping:
		_update_jumping(delta)
	if _self_jump_left > 0.0:
		_self_jump_left -= delta
		# Ohitetaan pohjaluokan "kova isku" -tarkistus oman hypyn ajan.
		_last_velocity = linear_velocity
		_age += delta
		return
	super._physics_process(delta)


func _update_jumping(delta: float) -> void:
	var grounded := absf(linear_velocity.y) < 0.15 and _age > grace_time

	if _in_air:
		_air_elapsed += delta
		# Suoja pysyy koko lennon ajan, myös jos pomo laskeutuu odotettua alemmas.
		if _air_elapsed < 3.0:
			_self_jump_left = maxf(_self_jump_left, 0.1)

	# Lasku (ei lakipisteessä, jossa pystynopeus on myös nolla).
	if _in_air and grounded and _air_elapsed > _air_time * 0.6:
		_in_air = false
		_call_wobble("land")
		_sound("boss_land", -3.0, 0.85)
		# Shokkiaalto taustan neonruudukkoon.
		GridWall.splash(get_tree(), global_position, 1.0)
		_self_jump_left = maxf(_self_jump_left, 0.15)
		if _extra_hops > 0:
			_extra_hops -= 1
			_start_crouch(jump_speed * 0.6, false, 0.08)
			return
		_jump_wait = _rng.randf_range(jump_interval.x, jump_interval.y)
		if MonkeyAntics.afk_seconds() > 6.0:
			_jump_wait = _rng.randf_range(0.2, 0.7)

	# Kyykky ennen hyppyä.
	if _crouch_left >= 0.0:
		_crouch_left -= delta
		if _crouch_left < 0.0:
			_launch(_pending_speed, _pending_spin)
		return

	if _in_air or not grounded:
		return
	_jump_wait -= delta
	if _jump_wait > 0.0:
		return

	var roll := _rng.randf()
	# AFK-kaaos: pelaajan ollessa poissa pomo tekee pelkkiä pyörähdyshyppyjä tiuhaan tahtiin.
	var afk := MonkeyAntics.afk_seconds()
	if afk > 6.0:
		roll = 0.0
		_jump_wait = 0.0
		if not _afk_laughed:
			_afk_laughed = true
			_sound("boss_laugh", -2.0, 1.15)
			SpeechBubble.say(self, "Bileet alkaa!", 1.8, popup_offset.y, "")
	else:
		_afk_laughed = false
	if roll < 0.25:
		_start_crouch(big_jump_speed, true, 0.4)
	elif roll < 0.45:
		_extra_hops = 2
		_start_crouch(jump_speed * 0.6, false, 0.2)
	else:
		_start_crouch(jump_speed * _rng.randf_range(0.8, 1.1), false, 0.28)


func _start_crouch(speed: float, spin: bool, duration: float) -> void:
	_pending_speed = speed
	_pending_spin = spin
	_crouch_left = duration
	_call_wobble("crouch", [duration])


func _launch(speed: float, spin: bool) -> void:
	var default_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var g := maxf(default_gravity * gravity_scale, 0.1)
	var air_time := 2.0 * speed / g
	# Pomppu kohti satunnaista kohtaa kotipaikan lähellä, ettei pomo hypi pois saarelta.
	var target_x := _home_x + _rng.randf_range(-hop_range, hop_range)
	var vx := clampf((target_x - global_position.x) / air_time, -2.0, 2.0)
	linear_velocity = Vector3(vx, speed, 0.0)
	angular_velocity = Vector3.ZERO
	_last_velocity = linear_velocity
	_self_jump_left = air_time + 0.3
	_in_air = true
	_air_time = air_time
	_air_elapsed = 0.0
	_call_wobble("jump", [air_time, spin])
	_sound("boss_jump", -6.0, 0.9 if spin else 1.05)
	if spin and _rng.randf() < 0.35:
		_sound("boss_laugh", -4.0, 1.2)


func _sound(event: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var sounds := get_node_or_null("/root/SoundManager")
	if sounds != null:
		sounds.call("play", event, volume_db, 0.08, 0.1, pitch)


func _call_wobble(method: String, args: Array = []) -> void:
	if _wobble != null and _wobble.has_method(method):
		_wobble.callv(method, args)


## Shots and blasts. Damage grows with the strength of the hit.
func take_hit(strength: float, _hit_position: Vector3 = Vector3.ZERO, _direction: Vector3 = Vector3.ZERO) -> void:
	if strength >= min_hit_strength:
		_damage(maxi(1, int(strength / damage_speed_step)))


## The base class calls die() for hard impacts: for a boss that is one point of damage.
func die() -> void:
	_damage(1)


## Used by kill zones: the boss dies at once.
func kill() -> void:
	if not _alive:
		return
	health = 0
	_update_label()
	super.die()


func _damage(amount: int) -> void:
	if not _alive or _hit_cooldown_left > 0.0:
		return
	# Kristallikilpi (boss_ability.gd "shield") torjuu osumat.
	if shielded:
		_hit_cooldown_left = hit_cooldown
		_call_wobble("hurt")
		SpeechBubble.say(self, "Kilpi!", 0.9, popup_offset.y, "")
		var sounds := get_node_or_null("/root/SoundManager")
		if sounds != null:
			sounds.call("play", "hit_ice", 0.0, 0.1, 0.1, 1.3)
		return
	_hit_cooldown_left = hit_cooldown
	health -= amount
	_update_label()
	hurt.emit(maxi(health, 0), max_health)
	if health <= 0:
		super.die()
		return
	_punch()


func _punch() -> void:
	if _visual == null:
		return
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	_visual.scale = Vector3.ONE * 1.12
	_call_wobble("hurt")
	if _rng.randf() < 0.6:
		var lines := BOSS_HURT_LINES if health > 2 else BOSS_LOW_LINES
		# Ääni tulee jo hurt-signaalista (SoundManager: boss_hurt), joten kupla on hiljaa.
		SpeechBubble.say(self, lines[_rng.randi() % lines.size()], 1.6, popup_offset.y, "")
	_punch_tween = create_tween()
	_punch_tween.tween_property(_visual, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_label() -> void:
	if _label != null:
		_label.text = "HP %d/%d" % [maxi(health, 0), max_health]

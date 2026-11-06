extends "res://scenes/includes/characters/ability_character.gd"
## KIMPOAVA: kumibanaani, joka pomppii kaikesta kuin kumipallo. Jokainen pomppu kuuluu ja
## näkyy taustan ruudukossa. Napautus tekee superpompun: banaani loikkaa ylös ja eteenpäin.
##
## Ritsa lukee `bounce` ja `friction` arvot ammuksen fysiikkamateriaaliin.

const GridWall := preload("res://scenes/visual/grid_wall.gd")

## Pomppuisuus (0 = ei pomppaa, 1 = täydellinen kimmoisuus).
@export_range(0.0, 1.0, 0.05) var bounce: float = 0.88
@export_range(0.0, 1.0, 0.05) var friction: float = 0.15
## Superpompun nopeus ylöspäin ja vauhti eteenpäin.
@export var super_jump: float = 13.0
@export var forward_boost: float = 4.0

var _body: RigidBody3D = null
var _last_boing_ms: int = 0


func _ready() -> void:
	_attach.call_deferred()


## Ammus luodaan ritsassa ennen puuhun lisäämistä, joten runko haetaan vasta nyt.
func _attach() -> void:
	_body = get_parent() as RigidBody3D
	if _body != null and not _body.body_entered.is_connected(_on_bounce):
		_body.body_entered.connect(_on_bounce)


func _on_activate(body: RigidBody3D, _slingshot: Node) -> void:
	var dir := signf(body.linear_velocity.x) if absf(body.linear_velocity.x) > 0.5 else 1.0
	body.linear_velocity = Vector3(body.linear_velocity.x + dir * forward_boost, super_jump, 0.0)
	Vfx.speed_trail(body, ability_color, 0.5)
	GridWall.splash(get_tree(), body.global_position, 0.8, ability_color)


func _on_bounce(_other: Node) -> void:
	if not is_instance_valid(_body) or _body.linear_velocity.length() < 2.5:
		return
	var now := Time.get_ticks_msec()
	if now - _last_boing_ms < 120:
		return
	_last_boing_ms = now
	var sounds := get_node_or_null("/root/SoundManager")
	if sounds != null:
		sounds.call("play", "boss_jump", -8.0, 0.1, 0.08, 1.6)
	GridWall.splash(get_tree(), _body.global_position, 0.35, ability_color)

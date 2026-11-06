extends "res://scenes/includes/characters/ability_character.gd"
## PAINAVA: napautus pysäyttää hahmon ilmaan ja iskee sen suoraan alas. Ensimmäinen
## kosketus sen jälkeen lähettää iskuaallon, joka vahingoittaa ja työntää kaikkea lähellä.

@export var slam_speed: float = 26.0
@export var mass_multiplier: float = 3.0
@export var shock_radius: float = 2.8
@export var shock_damage: float = 40.0
@export var shock_force: float = 10.0

var _slamming: bool = false


func _on_activate(body: RigidBody3D, _slingshot: Node) -> void:
	_slamming = true
	body.mass *= mass_multiplier
	body.linear_velocity = Vector3(body.linear_velocity.x * 0.15, -slam_speed, 0.0)
	body.angular_velocity = Vector3(0, 0, 12.0)
	Vfx.speed_trail(body, ability_color, 0.6)
	if not body.body_entered.is_connected(_on_body_entered):
		body.body_entered.connect(_on_body_entered.bind(body))


func _on_body_entered(_other: Node, body: RigidBody3D) -> void:
	if not _slamming or not is_instance_valid(body):
		return
	_slamming = false
	var at := body.global_position
	# Physics callback: do the area query on the next frame.
	_shock.call_deferred(at)


func _shock(at: Vector3) -> void:
	if not is_inside_tree():
		return
	Vfx.shockwave(_world(), at + Vector3(0, -0.4, 0), shock_radius)
	_area_hit(at, shock_radius, shock_damage, shock_force)

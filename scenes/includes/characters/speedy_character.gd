extends "res://scenes/includes/characters/ability_character.gd"
## NOPEA: napautus syöksäyttää hahmon suoraan lentosuuntaan kovalla vauhdilla.
## Kova vauhti = kova osuma (vahinko lasketaan osumanopeudesta).

@export var dash_speed: float = 24.0
## Painovoima on pienempi syöksyn ajan, jotta rata on suora.
@export var dash_time: float = 0.45


func _on_activate(body: RigidBody3D, _slingshot: Node) -> void:
	var dir := body.linear_velocity
	dir.z = 0.0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3.RIGHT
	body.linear_velocity = dir * maxf(dash_speed, body.linear_velocity.length() * 1.8)
	var old_gravity := body.gravity_scale
	body.gravity_scale = old_gravity * 0.15
	get_tree().create_timer(dash_time, false).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.gravity_scale = old_gravity)
	Vfx.speed_trail(body, ability_color, dash_time + 0.2)

extends "res://scenes/includes/characters/ability_character.gd"
## JAKAUTUVA: napautus jakaa hahmon kolmeksi viuhkaksi lentäväksi kopioksi.

## Kulma (asteina) jolla kopiot lähtevät ylös ja alas.
@export var spread_degrees: float = 14.0
@export var copy_scale: float = 0.8


func _on_activate(body: RigidBody3D, slingshot: Node) -> void:
	if slingshot == null or not slingshot.has_method("add_projectile") or scene_file_path == "":
		return
	var scene := load(scene_file_path) as PackedScene
	if scene == null:
		return
	var velocity := body.linear_velocity
	var family: Array = [body]
	for side in [-1.0, 1.0]:
		var copy := scene.instantiate() as Node3D
		copy.set("ability_used", true)
		copy.scale = Vector3.ONE * copy_scale
		var v := velocity.rotated(Vector3.BACK, deg_to_rad(spread_degrees) * side)
		var copy_body: Variant = slingshot.call("add_projectile", copy, body.global_position + Vector3(0, side * 0.5, 0), v, family)
		if copy_body is PhysicsBody3D:
			family.append(copy_body)
	Vfx.star_burst(_world(), body.global_position, 10)

extends Area3D
## Kill zone: any enemy that enters this area dies.
##
## Place it outside the play area (beyond the walls and below the ground).
## Enemies are RigidBody3D nodes in the "enemies" group with a `die()` method
## (see enemy_plain.gd), so they get the normal smoke and points popup.

## If true, other physics bodies (not enemies, not static) are removed too.
@export var remove_other_bodies: bool = false


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies"):
		if body.has_method("kill"):
			body.call("kill")
		elif body.has_method("die"):
			body.call("die")
		else:
			body.queue_free()
	elif remove_other_bodies and body is RigidBody3D:
		body.queue_free()

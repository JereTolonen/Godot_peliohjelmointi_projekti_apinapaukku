extends Node3D
## Shootable character that explodes when it hits something.
## The slingshot calls `on_impact()` when this character collides with the world.

const Explosion := preload("res://scenes/includes/explosion.gd")

## Scale of the visual explosion.
@export var explosion_size: float = 1.0
## Radius in which RigidBody3D nodes get pushed away by the blast.
@export var blast_radius: float = 4.0
## Impulse applied at the center of the blast (fades out with distance).
@export var blast_force: float = 12.0
## Damage strength at the center of the blast, passed to take_hit() (like a shot speed in m/s).
## It fades with distance but never drops below 25%, so enemies anywhere in the radius still die.
@export var blast_damage: float = 60.0


func on_impact(hit_position: Vector3, _hit_normal: Vector3) -> void:
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()

	var fx := Explosion.new()
	fx.size = explosion_size
	world.add_child(fx)
	fx.global_position = hit_position

	_apply_blast(hit_position)
	queue_free()


func _apply_blast(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collide_with_bodies = true

	var handled: Array[int] = []
	for hit in space.intersect_shape(query, 32):
		var collider := hit["collider"] as Object
		if collider == null or not is_instance_valid(collider):
			continue
		if handled.has(collider.get_instance_id()):
			continue
		handled.append(collider.get_instance_id())

		var target := collider as Node3D
		var offset := Vector3.ZERO
		if target != null:
			offset = target.global_position - center

		var falloff := clampf(1.0 - offset.length() / blast_radius, 0.0, 1.0)

		# Push physics bodies away (fades out with distance).
		if collider is RigidBody3D:
			(collider as RigidBody3D).apply_central_impulse(offset.normalized() * blast_force * falloff)

		# Damage anything that can be hurt (enemies die from any hit inside the blast,
		# blocks take more damage the closer they are).
		if collider.has_method("take_hit"):
			collider.call("take_hit", blast_damage * maxf(falloff, 0.25), center, offset.normalized())


## Napautus ilmassa räjäyttää hahmon heti (ei tarvitse odottaa osumaa).
func activate_ability(body: RigidBody3D, _slingshot: Node) -> bool:
	if not is_instance_valid(body) or not is_inside_tree():
		return false
	on_impact(body.global_position, Vector3.UP)
	body.queue_free()
	return true

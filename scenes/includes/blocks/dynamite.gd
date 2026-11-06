extends RigidBody3D
## Dynamite block.
##
## It explodes when:
##  - a shot hits it (the slingshot calls `take_hit()`),
##  - another blast reaches it (chain reaction), or
##  - its velocity changes too much in one physics frame (a hard hit or landing).
##
## The blast pushes nearby RigidBody3D nodes away and calls `take_hit()` on everything
## in range, so enemies die and other dynamite blocks go off too.

const Explosion := preload("res://scenes/includes/explosion.gd")

## Scale of the visual explosion.
@export var explosion_size: float = 1.4
## Radius in which bodies are pushed and hurt.
@export var blast_radius: float = 4.5
## Impulse at the center of the blast (fades out with distance).
@export var blast_force: float = 16.0
## Minimum strength of a direct hit (shot speed) needed to set it off. 0 = any hit.
@export var min_hit_strength: float = 0.0
## The dynamite explodes if its velocity changes by more than this (m/s) in one frame.
@export var death_velocity_change: float = 9.0
## Seconds after spawning during which velocity changes are ignored (physics settling).
@export var grace_time: float = 0.5
## Short delay before a triggered dynamite goes off, so chain reactions ripple.
@export var fuse_delay: float = 0.08
## Keep the block in the X/Y plane (must match the slingshot's plane).
@export var lock_to_side_view: bool = true

var _exploded: bool = false
var _triggered: bool = false
var _age: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("dynamite")
	_last_velocity = linear_velocity
	continuous_cd = true
	if lock_to_side_view:
		axis_lock_linear_z = true
		axis_lock_angular_x = true
		axis_lock_angular_y = true


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	var velocity_change := linear_velocity.distance_to(_last_velocity)
	_last_velocity = linear_velocity
	if _age >= grace_time and velocity_change >= death_velocity_change:
		trigger()


## Called by the slingshot and by other blasts.
func take_hit(strength: float, _hit_position: Vector3 = Vector3.ZERO, _direction: Vector3 = Vector3.ZERO) -> void:
	if strength >= min_hit_strength:
		trigger()


## Starts the (very short) fuse.
func trigger() -> void:
	if _triggered:
		return
	_triggered = true
	if fuse_delay <= 0.0:
		explode()
	else:
		get_tree().create_timer(fuse_delay).timeout.connect(explode)


func explode() -> void:
	if _exploded:
		return
	_exploded = true

	var center := global_position
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()

	var fx := Explosion.new()
	fx.size = explosion_size
	world.add_child(fx)
	fx.global_position = center

	_apply_blast(center)
	queue_free()


func _apply_blast(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collide_with_bodies = true
	# Walls (layer 2) should not be affected, only the normal physics layer.
	query.collision_mask = 1

	var handled: Array[int] = []
	for hit in space.intersect_shape(query, 32):
		var collider := hit["collider"] as Object
		if collider == null or not is_instance_valid(collider) or collider == self:
			continue
		if handled.has(collider.get_instance_id()):
			continue
		handled.append(collider.get_instance_id())

		var target := collider as Node3D
		var offset := Vector3.ZERO
		if target != null:
			offset = target.global_position - center
		offset.z = 0.0
		var direction := offset.normalized() if offset.length() > 0.001 else Vector3.UP

		if collider is RigidBody3D:
			var falloff := clampf(1.0 - offset.length() / blast_radius, 0.0, 1.0)
			(collider as RigidBody3D).apply_central_impulse(direction * blast_force * falloff)

		if collider.has_method("take_hit"):
			collider.call("take_hit", blast_force, center, direction)

extends RigidBody3D
## Destructible building part.
##
## It takes damage from:
##  - shots and blasts (they call `take_hit(strength, position, direction)`), and
##  - hard impacts (its velocity changes a lot in one physics frame, for example when
##    it is hit by a falling block or lands hard).
##
## Damage shows up as cracks that grow on the block. When its health runs out it breaks
## into debris chunks and a dust puff, and removes itself.

signal damaged(health: float)
signal broken

const DeathSmoke := preload("res://scenes/includes/death_smoke.gd")

## Health of a fresh block.
@export var max_health: float = 40.0
## Damage per unit of hit strength (shots pass their speed in m/s as strength).
@export var damage_per_speed: float = 1.0
## Velocity change in one physics frame (m/s) above which an impact hurts the block.
@export var min_impact_speed: float = 5.0
## Damage per m/s of velocity change for those impacts.
@export var impact_damage_per_speed: float = 1.0
## Seconds after spawning during which impacts are ignored (physics settling).
@export var grace_time: float = 0.7
## Start asleep so stacks stand still until something disturbs them.
@export var start_asleep: bool = true
## Keep the block in the X/Y plane it spawned in (no Z movement, no tumbling around X/Y).
@export var lock_to_side_view: bool = true

@export_group("Break effect")
## Number of debris chunks.
@export var debris_count: int = 8
## Seconds the debris stays before shrinking away.
@export var debris_lifetime: float = 3.0
## Debris color, used when the block mesh has no material of its own.
@export var debris_color: Color = Color(0.85, 0.75, 0.6)
## Scale of the dust puff.
@export var dust_size: float = 0.9

var health: float = 0.0

static var _crack_texture: ImageTexture = null

var _age: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO
var _broken: bool = false
var _mesh: MeshInstance3D = null
var _crack_material: StandardMaterial3D = null
var _punch_tween: Tween = null


func _ready() -> void:
	health = max_health
	add_to_group("destructibles")
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	_last_velocity = linear_velocity
	if lock_to_side_view:
		axis_lock_linear_z = true
		axis_lock_angular_x = true
		axis_lock_angular_y = true
	if start_asleep:
		sleeping = true


func _physics_process(delta: float) -> void:
	if _broken:
		return
	_age += delta
	var velocity_change := linear_velocity.distance_to(_last_velocity)
	_last_velocity = linear_velocity
	if _age >= grace_time and velocity_change >= min_impact_speed:
		_apply_damage(velocity_change * impact_damage_per_speed, global_position, Vector3.ZERO)


## Called by shots and blasts. `strength` is usually the speed of the hit in m/s.
func take_hit(strength: float, hit_position: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.ZERO) -> void:
	_apply_damage(strength * damage_per_speed, hit_position, direction)


func _apply_damage(amount: float, hit_position: Vector3, direction: Vector3) -> void:
	if _broken or amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		_break(direction)
		return

	damaged.emit(health)
	_show_damage()
	if amount >= 4.0:
		_spawn_dust(hit_position, dust_size * 0.4)


# --- Damage look ------------------------------------------------------------

func _show_damage() -> void:
	if _mesh == null:
		return
	var fraction := clampf(1.0 - health / max_health, 0.0, 1.0)
	if _crack_material == null:
		_crack_material = _make_crack_material()
		_mesh.material_overlay = _crack_material
	var color := _crack_material.albedo_color
	color.a = clampf(fraction * 1.3, 0.0, 0.95)
	_crack_material.albedo_color = color

	# Little punch so the hit is felt.
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	_mesh.scale = Vector3.ONE * 1.07
	_punch_tween = create_tween()
	_punch_tween.tween_property(_mesh, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_crack_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _get_crack_texture()
	material.albedo_color = Color(0.08, 0.05, 0.03, 0.0)
	material.roughness = 1.0
	# A box mesh has an atlas-style UV layout, so project the cracks onto each face instead.
	var size := Vector3.ONE
	if _mesh.mesh is BoxMesh:
		size = (_mesh.mesh as BoxMesh).size
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(1.0 / size.x, 1.0 / size.y, 1.0 / size.z)
	material.uv1_offset = Vector3(0.5, 0.5, 0.5)
	return material


## White cracks radiating from the center on a transparent texture (made once, shared).
static func _get_crack_texture() -> ImageTexture:
	if _crack_texture != null:
		return _crack_texture

	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var center := Vector2(size, size) * 0.5
	var crack_count := 7

	for c in crack_count:
		var angle := TAU * float(c) / float(crack_count) + rng.randf_range(-0.3, 0.3)
		var pos := center + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		var length := rng.randf_range(45.0, 80.0)
		var walked := 0.0
		while walked < length:
			angle += rng.randf_range(-0.5, 0.5)
			var step := rng.randf_range(4.0, 8.0)
			var next := pos + Vector2.from_angle(angle) * step
			_draw_crack_line(image, pos, next)
			# Small side branches.
			if rng.randf() < 0.25:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var branch_angle := angle + side * rng.randf_range(0.6, 1.2)
				_draw_crack_line(image, next, next + Vector2.from_angle(branch_angle) * rng.randf_range(6.0, 14.0))
			pos = next
			walked += step

	_crack_texture = ImageTexture.create_from_image(image)
	return _crack_texture


static func _draw_crack_line(image: Image, from: Vector2, to: Vector2) -> void:
	var steps := maxi(int(from.distance_to(to)), 1)
	for s in steps + 1:
		var point := from.lerp(to, float(s) / float(steps))
		for ox in 2:
			for oy in 2:
				var x := int(point.x) + ox
				var y := int(point.y) + oy
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, Color.WHITE)


# --- Breaking ---------------------------------------------------------------

func _break(direction: Vector3) -> void:
	_broken = true
	broken.emit()
	_spawn_dust(global_position, dust_size)
	_spawn_debris(direction)
	queue_free()


func _spawn_dust(at: Vector3, dust_scale: float) -> void:
	var dust := DeathSmoke.new()
	dust.size = dust_scale
	dust.show_sparks = false
	dust.show_ring = false
	_world().add_child(dust)
	dust.global_position = at


func _spawn_debris(direction: Vector3) -> void:
	var world := _world()
	var block_size := _block_size()
	var material := _debris_material()
	var push := direction
	push.z = 0.0
	var basis := global_transform.basis.orthonormalized()

	for i in debris_count:
		var chunk_size := block_size * Vector3(
			randf_range(0.2, 0.4), randf_range(0.2, 0.4), randf_range(0.4, 0.8))

		var chunk := RigidBody3D.new()
		chunk.mass = 0.2
		# Debris collides with the world but is not hit by shots.
		chunk.collision_layer = 2
		chunk.collision_mask = 1
		chunk.axis_lock_linear_z = true
		chunk.axis_lock_angular_x = true
		chunk.axis_lock_angular_y = true

		var mesh := BoxMesh.new()
		mesh.size = chunk_size
		mesh.material = material
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		chunk.add_child(visual)

		var box := BoxShape3D.new()
		box.size = chunk_size
		var shape := CollisionShape3D.new()
		shape.shape = box
		chunk.add_child(shape)

		world.add_child(chunk)
		var offset := Vector3(
			randf_range(-0.4, 0.4) * block_size.x, randf_range(-0.4, 0.4) * block_size.y, 0.0)
		chunk.global_position = global_position + basis * offset
		chunk.global_rotation = global_rotation
		chunk.linear_velocity = push * randf_range(2.0, 5.0) \
			+ Vector3(randf_range(-3.0, 3.0), randf_range(1.0, 5.0), 0.0)
		chunk.angular_velocity = Vector3(0.0, 0.0, randf_range(-8.0, 8.0))

		# Shrink away at the end of its life, then remove.
		var tween := chunk.create_tween()
		tween.tween_interval(maxf(debris_lifetime - 0.5, 0.0))
		tween.tween_property(visual, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(chunk.queue_free)


func _block_size() -> Vector3:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var size := Vector3.ONE
	if shape_node != null and shape_node.shape is BoxShape3D:
		size = (shape_node.shape as BoxShape3D).size
	return size * global_transform.basis.get_scale()


func _debris_material() -> Material:
	if _mesh != null:
		var material := _mesh.get_active_material(0)
		if material != null:
			return material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = debris_color
	return fallback


func _world() -> Node:
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()
	return world

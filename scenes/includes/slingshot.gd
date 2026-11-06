extends Node3D
## Slingshot that launches character scenes as real physics projectiles.
##
## Controls (while this scene is running):
##   Hold left mouse on the slingshot, drag back, release  - shoot
##   Q / Left arrow                                        - previous character
##   E / Right arrow                                       - next character
##
## Every shot becomes a RigidBody3D with a sphere collider that is locked to the
## X/Y plane (no Z movement), so the physics engine handles all collisions:
##  - Character scenes whose root is a RigidBody3D are used directly.
##  - Any other character scene (for example a Node3D) is wrapped in a RigidBody3D.
##  - The character's own StaticBody3D colliders are disabled, they can't collide
##    properly while the shot moves.
##
## When a shot touches something:
##  - If it has `take_hit(strength, position, direction)`, that is called (enemies die).
##  - If the character has `on_impact(hit_position, hit_normal)`, that is called and the
##    shot is removed (the exploding character uses it).
##  - Otherwise the shot stays for `landed_lifetime` seconds and then disappears.
##
## The scene needs a Camera3D so the mouse can be projected into the world, and the
## level needs colliders (ground, blocks, enemies) on the same Z plane as the slingshot.

signal character_selected(index: int, scene: PackedScene)
signal character_shot(scene: PackedScene, instance: Node3D)
signal character_impact(instance: Node3D, hit_position: Vector3)

## List of characters the slingshot can shoot.
@export var shootable_characters: Array[PackedScene] = [
	preload("res://scenes/includes/characters/normal.tscn"),
	preload("res://scenes/includes/characters/exploding.tscn"),
]
## Index into `shootable_characters` of the character that is shot next.
@export var selected_index: int = 0

@export_group("Aiming")
## Shots fly towards +X when true, towards -X when false.
@export var shoot_towards_positive_x: bool = true
## Rest position of the character in the slingshot, relative to the slingshot.
@export var spawn_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
## How close (in world units) the mouse must be to the rest position to grab it.
@export var grab_radius: float = 2.5
## Maximum distance the character can be pulled back.
@export var max_pull: float = 3.0
## Pulls shorter than this cancel the shot.
@export var min_pull: float = 0.4
## Launch speed per unit of pull distance.
@export var power: float = 7.0
## Seconds before a new shot can be started.
@export var cooldown: float = 0.4
@export var show_trajectory: bool = true
@export var trajectory_dots: int = 18
## Seconds of flight between two trajectory dots.
@export var trajectory_step: float = 0.08

@export_group("Projectile")
## Radius of the sphere collider given to shots. 0 measures it from the character's meshes.
@export var projectile_radius: float = 0.0
@export_range(0.0, 1.0, 0.05) var projectile_bounce: float = 0.2
@export_range(0.0, 2.0, 0.05) var projectile_friction: float = 0.8

@export_group("Flight")
## Gravity used for the shot and for the trajectory preview.
@export var gravity: float = 9.8
## The shot is removed after this many seconds.
@export var max_lifetime: float = 8.0
## The shot is removed when it falls below this world Y height.
@export var kill_height: float = -20.0
## Spin applied at launch (radians per second). Only Z is used (side view).
@export var spin: Vector3 = Vector3(0.0, 0.0, 3.0)
## Seconds a shot that landed without exploding stays before it is removed.
@export var landed_lifetime: float = 4.0

var _projectiles: Array[Dictionary] = []
var _pending_hits: Array[Dictionary] = []
var _cooldown_left: float = 0.0
var _dragging: bool = false
var _drag_body: RigidBody3D = null
var _drag_character: Node3D = null
var _pull: Vector3 = Vector3.ZERO
var _dots: Array[MeshInstance3D] = []
var _band: MeshInstance3D = null


func _ready() -> void:
	add_to_group("slingshot")
	selected_index = clampi(selected_index, 0, maxi(shootable_characters.size() - 1, 0))
	_build_aim_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_begin_drag()
		else:
			_release_drag()
	elif event is InputEventKey and event.pressed and not event.echo and not _dragging:
		match event.keycode:
			KEY_Q, KEY_LEFT:
				select_character(selected_index - 1)
			KEY_E, KEY_RIGHT:
				select_character(selected_index + 1)


func _process(_delta: float) -> void:
	if not _dragging:
		return

	# Safety net: mouse released outside the window, or the preview vanished.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_release_drag()
		return
	if not is_instance_valid(_drag_body):
		_dragging = false
		_pull = Vector3.ZERO
		_set_aim_visuals(false)
		return

	var hit: Variant = _mouse_on_plane()
	if hit != null:
		var offset: Vector3 = (hit as Vector3) - _anchor()
		offset.z = 0.0
		if offset.length() > max_pull:
			offset = offset.normalized() * max_pull
		_pull = offset

	_drag_body.global_position = _anchor() + _pull
	_update_band()
	_update_trajectory()


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_process_pending_hits()

	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var body_variant: Variant = p["body"]
		if not is_instance_valid(body_variant):
			_projectiles.remove_at(i)
			continue
		var body: RigidBody3D = body_variant

		# Remember the velocity from before this physics step: that is the speed of the
		# impact if the shot hits something during the step.
		body.set_meta("slingshot_velocity", body.linear_velocity)
		# Gravity wells pull gently on top of the normal physics.
		body.apply_central_force(_gravity_well_pull(body.global_position) * body.mass)

		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= max_lifetime or body.global_position.y < kill_height:
			body.queue_free()
			_projectiles.remove_at(i)


## Selects a character from the list (wraps around).
func select_character(index: int) -> void:
	if shootable_characters.is_empty():
		return
	selected_index = posmod(index, shootable_characters.size())
	var scene := shootable_characters[selected_index]
	print("Slingshot: selected ", scene.resource_path.get_file().get_basename())
	character_selected.emit(selected_index, scene)


# --- Dragging and launching -------------------------------------------------

func _try_begin_drag() -> void:
	if _dragging or _cooldown_left > 0.0 or shootable_characters.is_empty():
		return

	var hit: Variant = _mouse_on_plane()
	if hit == null:
		return
	if (hit as Vector3).distance_to(_anchor()) > grab_radius:
		return

	var scene := shootable_characters[selected_index]
	if scene == null:
		return
	var character := scene.instantiate() as Node3D
	if character == null:
		push_warning("Slingshot: shootable character is not a Node3D: %s" % scene.resource_path)
		return

	var body := _make_projectile(character)
	_world().add_child(body)
	body.global_position = _anchor()
	_drag_body = body
	_drag_character = character
	_pull = Vector3.ZERO
	_dragging = true
	_set_aim_visuals(true)


func _release_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_set_aim_visuals(false)

	var body := _drag_body
	var character := _drag_character
	_drag_body = null
	_drag_character = null
	if not is_instance_valid(body):
		_pull = Vector3.ZERO
		return

	# Too short a pull cancels the shot.
	if _pull.length() < min_pull:
		body.queue_free()
		_pull = Vector3.ZERO
		return

	var scene := shootable_characters[selected_index]
	_launch(body, _launch_velocity())
	body.body_entered.connect(_on_projectile_body_entered.bind(body, character))
	_projectiles.append({"body": body, "age": 0.0})
	_cooldown_left = cooldown
	_pull = Vector3.ZERO
	character_shot.emit(scene, body)


## Turns a character into a physics projectile (frozen until launched).
func _make_projectile(character: Node3D) -> RigidBody3D:
	var body := character as RigidBody3D
	if body == null:
		body = RigidBody3D.new()
		body.name = "Projectile"
		body.add_child(character)

	# The character's own StaticBody3D / trimesh colliders can't work on a moving shot.
	for node in character.find_children("*", "CollisionObject3D", true, false):
		var collider := node as CollisionObject3D
		if collider != body:
			collider.collision_layer = 0
			collider.collision_mask = 0

	# A simple sphere collider is the most reliable shape for a thrown object.
	var has_shape := false
	for child in body.get_children():
		if child is CollisionShape3D:
			has_shape = true
			break
	if not has_shape:
		var sphere := SphereShape3D.new()
		sphere.radius = projectile_radius if projectile_radius > 0.0 else _visual_radius(character)
		var shape := CollisionShape3D.new()
		shape.shape = sphere
		body.add_child(shape)

	if body.physics_material_override == null:
		var material := PhysicsMaterial.new()
		material.bounce = projectile_bounce
		material.friction = projectile_friction
		body.physics_material_override = material

	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	# Side view: no movement along Z, no tumbling around X/Y.
	body.axis_lock_linear_z = true
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true

	# While it is being dragged the shot just floats in the slingshot.
	body.set_meta("slingshot_layer", body.collision_layer)
	body.set_meta("slingshot_mask", body.collision_mask)
	body.collision_layer = 0
	body.collision_mask = 0
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	return body


func _launch(body: RigidBody3D, velocity: Vector3) -> void:
	body.collision_layer = int(body.get_meta("slingshot_layer", 1))
	body.collision_mask = int(body.get_meta("slingshot_mask", 1))
	var default_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	body.gravity_scale = gravity / default_gravity
	body.freeze = false
	body.sleeping = false
	body.apply_central_impulse(velocity * body.mass)
	body.angular_velocity = spin


## Radius of a sphere that covers the character's meshes.
func _visual_radius(root: Node3D) -> float:
	var radius := 0.0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var size := mesh_instance.mesh.get_aabb().size * mesh_instance.scale
		radius = maxf(radius, maxf(size.x, maxf(size.y, size.z)) * 0.5)
	return radius if radius > 0.0 else 0.5


## Launch velocity from the current pull. Always in the X/Y plane, always towards the shoot direction.
func _launch_velocity() -> Vector3:
	var dir_sign := 1.0 if shoot_towards_positive_x else -1.0
	var v := -_pull * power
	v.z = 0.0
	v.x = maxf(v.x * dir_sign, 0.0) * dir_sign
	return v


func _anchor() -> Vector3:
	return to_global(spawn_offset)


## Mouse position projected onto the X/Y plane that contains the slingshot, or null.
func _mouse_on_plane() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var plane := Plane(Vector3.BACK, _anchor().z)
	return plane.intersects_ray(origin, dir)


# --- Hits -------------------------------------------------------------------

## Physics callback: only queue the hit, it is handled safely in _physics_process.
func _on_projectile_body_entered(hit_body: Node, projectile: RigidBody3D, character: Node3D) -> void:
	if not is_instance_valid(projectile):
		return
	var velocity: Vector3 = projectile.get_meta("slingshot_velocity", Vector3.ZERO)
	_pending_hits.append({
		"hit_body": hit_body,
		"projectile": projectile,
		"character": character,
		"velocity": velocity,
	})


func _process_pending_hits() -> void:
	if _pending_hits.is_empty():
		return
	var hits := _pending_hits.duplicate()
	_pending_hits.clear()

	for h in hits:
		var projectile_variant: Variant = h["projectile"]
		if not is_instance_valid(projectile_variant):
			continue
		var projectile: RigidBody3D = projectile_variant
		var hit_position := projectile.global_position
		var velocity: Vector3 = h["velocity"]

		# Damage whatever was hit (enemies implement take_hit()).
		var hit_variant: Variant = h["hit_body"]
		if is_instance_valid(hit_variant):
			var hit_object := hit_variant as Object
			if hit_object.has_method("take_hit"):
				hit_object.call("take_hit", velocity.length(), hit_position, velocity.normalized())

		character_impact.emit(projectile, hit_position)

		# Characters with on_impact (the exploding one) react once and are removed.
		var character_variant: Variant = h["character"]
		if is_instance_valid(character_variant) and (character_variant as Object).has_method("on_impact"):
			(character_variant as Object).call("on_impact", hit_position, Vector3.UP)
			projectile.queue_free()
		elif not projectile.has_meta("slingshot_landed"):
			projectile.set_meta("slingshot_landed", true)
			get_tree().create_timer(landed_lifetime).timeout.connect(projectile.queue_free)


## Combined pull of all gravity wells (nodes in the "gravity_wells" group) at a position.
## Kept in the X/Y plane so shots never drift along Z.
func _gravity_well_pull(world_pos: Vector3) -> Vector3:
	var pull := Vector3.ZERO
	for well in get_tree().get_nodes_in_group("gravity_wells"):
		if well.has_method("get_pull_acceleration"):
			pull += well.call("get_pull_acceleration", world_pos) as Vector3
	pull.z = 0.0
	return pull


func _world() -> Node:
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()
	return world


# --- Aim visuals (rubber band + trajectory dots) ----------------------------

func _build_aim_visuals() -> void:
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1.0, 1.0, 1.0)
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.08
	dot_mesh.height = 0.16
	dot_mesh.material = dot_mat
	for i in trajectory_dots:
		var dot := MeshInstance3D.new()
		dot.mesh = dot_mesh
		dot.top_level = true
		dot.visible = false
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dot)
		_dots.append(dot)

	var band_mat := StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.albedo_color = Color(0.45, 0.28, 0.12)
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.04
	band_mesh.bottom_radius = 0.04
	band_mesh.height = 1.0
	band_mesh.radial_segments = 8
	band_mesh.rings = 1
	band_mesh.material = band_mat
	_band = MeshInstance3D.new()
	_band.mesh = band_mesh
	_band.top_level = true
	_band.visible = false
	_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_band)


func _set_aim_visuals(active: bool) -> void:
	if _band != null:
		_band.visible = active
	if not active:
		for dot in _dots:
			dot.visible = false


func _update_band() -> void:
	var length := _pull.length()
	_band.visible = length > 0.01
	if length <= 0.01:
		return
	_band.global_position = _anchor() + _pull * 0.5
	_band.global_rotation = Vector3(0.0, 0.0, atan2(-_pull.x, _pull.y))
	_band.scale = Vector3(1.0, length, 1.0)


func _update_trajectory() -> void:
	var enough_pull := _pull.length() >= min_pull
	var vel := _launch_velocity()
	var start := _anchor() + _pull
	for i in _dots.size():
		var t := trajectory_step * float(i + 1)
		var point := start + vel * t + Vector3(0.0, -0.5 * gravity * t * t, 0.0)
		var dot := _dots[i]
		dot.global_position = point
		dot.scale = Vector3.ONE * (1.0 - 0.7 * float(i) / float(_dots.size()))
		dot.visible = show_trajectory and enough_pull

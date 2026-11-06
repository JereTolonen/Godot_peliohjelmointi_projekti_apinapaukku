@tool
extends Node3D
## Magnet-like gravity well.
##
## Anything inside the sphere is pulled towards its center. The pull is a gentle
## acceleration that is added to the object's own movement (it never overrides it),
## and it gets stronger the closer the object is to the center.
##
## Works with:
##  - RigidBody3D nodes inside the PullArea (a force is applied every physics frame).
##  - Objects that are moved by script (like the slingshot's characters): they call
##    `get_pull_acceleration(world_position)` on every node in the "gravity_wells" group.
##
## The PullArea ignores this node's scale (Jolt does not support non-uniform scale on
## bodies), so you can freely stretch the sphere. The pull zone is a true sphere whose
## radius follows the largest scale axis.

const GROUP := &"gravity_wells"

## Pull acceleration at the very center, in meters per second squared.
## For comparison, normal gravity is 9.8.
@export var strength: float = 30.0
## How quickly the pull fades towards the edge. 1 = linear, 2 = quadratic (soft edge,
## strong center), higher = even more concentrated at the center.
@export_range(0.5, 6.0, 0.1) var falloff_exponent: float = 2.0
## Radius of the pull zone in world units. 0 uses the size of the sphere mesh.
@export var pull_radius: float = 0.0
## Pull RigidBody3D nodes that enter the sphere.
@export var affect_rigid_bodies: bool = true

var _area: Area3D = null
var _shape: CollisionShape3D = null
var _bodies: Array[RigidBody3D] = []


func _ready() -> void:
	_area = get_node_or_null("PullArea") as Area3D
	if _area != null:
		# Detach from our transform so a scaled parent can't break the physics shape.
		_area.top_level = true
		_shape = _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_sync_area()

	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	if _area != null:
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	# Keep the area following the sphere while editing.
	if Engine.is_editor_hint():
		_sync_area()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sync_area()
	if not affect_rigid_bodies:
		return
	for i in range(_bodies.size() - 1, -1, -1):
		var body := _bodies[i]
		if not is_instance_valid(body):
			_bodies.remove_at(i)
			continue
		# Force = acceleration * mass, so heavy and light bodies are pulled equally hard.
		var accel := get_pull_acceleration(body.global_position)
		body.apply_central_force(accel * body.mass)


## Radius of the pull zone in world units.
func get_world_radius() -> float:
	if pull_radius > 0.0:
		return pull_radius
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh is SphereMesh:
		var sphere := mesh_instance.mesh as SphereMesh
		var s := mesh_instance.global_transform.basis.get_scale()
		return sphere.radius * maxf(maxf(absf(s.x), absf(s.y)), absf(s.z))
	return 1.0


## Acceleration (world space) this well applies at `world_position`.
## Zero outside the sphere, strongest at the center.
func get_pull_acceleration(world_position: Vector3) -> Vector3:
	var radius := get_world_radius()
	var to_center := global_position - world_position
	var dist := to_center.length()
	if dist >= radius or dist < 0.001:
		return Vector3.ZERO
	var closeness := 1.0 - dist / radius
	return (to_center / dist) * strength * pow(closeness, falloff_exponent)


## Moves the unscaled area to the sphere's position and matches its radius.
func _sync_area() -> void:
	if _area == null:
		return
	_area.global_transform = Transform3D(Basis.IDENTITY, global_position)
	if _shape != null and _shape.shape is SphereShape3D:
		var sphere := _shape.shape as SphereShape3D
		var radius := get_world_radius()
		if not is_equal_approx(sphere.radius, radius):
			sphere.radius = radius


func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and not _bodies.has(body):
		_bodies.append(body as RigidBody3D)


func _on_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		_bodies.erase(body as RigidBody3D)

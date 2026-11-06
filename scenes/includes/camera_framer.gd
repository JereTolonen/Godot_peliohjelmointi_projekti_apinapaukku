extends Camera3D
## Positions the camera so that every enemy and block is visible, without being restless.
##
## Only the camera's POSITION changes. Its rotation and field of view are never touched:
## it slides sideways/up/down to center the targets and moves back along its viewing
## direction until they all fit, leaving free space around them.
##
## Behaviour:
##  1. At the start the camera frames all targets at once.
##  2. After that it stays still. It only considers moving when some target gets too close
##     to the screen edge (or leaves the screen).
##  3. It then waits `decision_delay` seconds. If the problem is gone by then (for example
##     the block fell back into view) nothing happens. If it is still there, the camera
##     re-frames everything with a slow, gentle move.
##
## Targets are the nodes in `target_groups` (enemies, blocks and the slingshot by default)
## plus anything in `extra_targets`. Enemies add themselves to the "enemies" group and
## blocks to the "destructibles" group.

## Nodes in these groups are kept in view. The slingshot is included so the player can
## always reach it; remove "slingshot" from the list if you don't want that.
@export var target_groups: Array[StringName] = [&"enemies", &"destructibles", &"slingshot"]
## Extra nodes that are always kept in view.
@export var extra_targets: Array[Node3D] = []
## Free space left between the targets and the screen edge when framing, as a fraction of
## the screen (0.2 = 20% on every side).
@export_range(0.0, 0.5, 0.01) var margin: float = 0.2
## After the start, the camera only considers moving when a target is closer to the edge
## than this fraction of the screen (or outside it). Keep it well below `margin`.
@export_range(0.0, 0.4, 0.01) var edge_tolerance: float = 0.08
## Seconds a target has to stay too close to the edge before the camera decides to move.
@export var decision_delay: float = 5.0
## The framed area is never smaller than this (world units, in the camera's view plane),
## so the camera doesn't zoom in too far when only a few targets are left.
@export var min_framing_size: Vector2 = Vector2(10.0, 6.0)
## How quickly the camera glides to its new spot (higher = faster, 0 = jump).
@export var smoothing: float = 1.5
## How often (in seconds) the targets are checked.
@export var refresh_interval: float = 0.25
## When false the camera only ever moves back, never closer, when it re-frames.
@export var allow_zoom_in: bool = false
@export var enabled: bool = true
@export_group("Out of world")
## Targets more than this far below the lowest point of the starting view are ignored
## (a block that fell off the edge must not drag the camera down after it).
@export var fall_limit: float = 4.0
## Targets more than this far left/right/above the starting view are ignored too.
@export var side_limit: float = 12.0
@export_group("Limits")
## How far (m) the camera may pull back from where it framed the level at the start.
## 0 = never further back than the starting view.
@export var max_zoom_out: float = 3.0
## How far (m) the camera may slide sideways or up/down from its starting spot.
@export var max_pan: float = 4.0

var _goal: Vector3 = Vector3.ZERO
## Camera position chosen at the start of the level (limits are measured from here).
var _start_position: Vector3 = Vector3.ZERO
## Area framed at the start (in world space). Targets far outside it are ignored.
var _world_bounds: AABB = AABB()
var _has_bounds: bool = false
var _started: bool = false
var _moving: bool = false
var _uncomfortable: bool = false
var _uncomfortable_time: float = 0.0
var _time_left: float = 0.0


func _process(delta: float) -> void:
	if not enabled:
		return

	# Gliding to a new spot: nothing else to decide until we arrive.
	if _moving:
		_glide(delta)
		return

	if _uncomfortable:
		_uncomfortable_time += delta

	_time_left -= delta
	if _time_left > 0.0:
		return
	_time_left = refresh_interval
	_check_targets()


## Frames all targets right now (for example after the level was rebuilt).
## With `snap` the camera jumps there, otherwise it glides.
func reframe_now(snap: bool = false) -> void:
	# A snapping reframe (level start / rebuild) measures the play area again.
	if snap:
		_has_bounds = false
	var points := _collect_points()
	if points.is_empty():
		return
	if not _has_bounds:
		_world_bounds = AABB(points[0], Vector3.ZERO)
		for p in points:
			_world_bounds = _world_bounds.expand(p)
		_has_bounds = true
	_goal = _frame_points(points)
	if snap:
		_start_position = _goal
	else:
		_goal = _limit_goal(_goal)
	_uncomfortable = false
	_uncomfortable_time = 0.0
	_started = true
	if snap or smoothing <= 0.0:
		global_position = _goal
		_moving = false
	else:
		_moving = true


func _check_targets() -> void:
	var points := _collect_points()
	if points.is_empty():
		_uncomfortable = false
		_uncomfortable_time = 0.0
		return

	# Start: frame everything once, immediately.
	if not _started:
		reframe_now(true)
		return

	if _is_comfortable(points):
		_uncomfortable = false
		_uncomfortable_time = 0.0
		return

	if not _uncomfortable:
		_uncomfortable = true
		_uncomfortable_time = 0.0
		return

	# Only move once the problem has lasted for `decision_delay` seconds.
	if _uncomfortable_time >= decision_delay:
		var new_goal := _frame_points(points)
		if not allow_zoom_in:
			var forward := -global_transform.basis.z
			var closer := (new_goal - global_position).dot(forward)
			if closer > 0.0:
				new_goal -= forward * closer
		_goal = _limit_goal(new_goal)
		_uncomfortable = false
		_uncomfortable_time = 0.0
		_moving = true


func _glide(delta: float) -> void:
	if smoothing <= 0.0:
		global_position = _goal
	else:
		global_position = global_position.lerp(_goal, 1.0 - exp(-smoothing * delta))
	if global_position.distance_to(_goal) < 0.02:
		global_position = _goal
		_moving = false
		_uncomfortable = false
		_uncomfortable_time = 0.0


# --- Measuring the targets --------------------------------------------------

func _collect_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var seen := {}
	for group in target_groups:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and not seen.has(node.get_instance_id()):
				seen[node.get_instance_id()] = true
				if group != &"slingshot" and _out_of_world((node as Node3D).global_position):
					continue
				_add_node_points(node as Node3D, points)
	for target in extra_targets:
		if is_instance_valid(target) and not seen.has(target.get_instance_id()):
			seen[target.get_instance_id()] = true
			_add_node_points(target, points)
	return points


## Keeps a new camera spot within `max_zoom_out` / `max_pan` of the starting view.
func _limit_goal(goal: Vector3) -> Vector3:
	var basis := global_transform.basis.orthonormalized()
	var forward := -basis.z
	var offset := goal - _start_position
	var depth := clampf(offset.dot(forward), -max_zoom_out, INF if allow_zoom_in else 0.0)
	var side := clampf(offset.dot(basis.x), -max_pan, max_pan)
	var up := clampf(offset.dot(basis.y), -max_pan, max_pan)
	return _start_position + forward * depth + basis.x * side + basis.y * up


## True for targets that fell off the level or flew far away from the starting view.
func _out_of_world(p: Vector3) -> bool:
	if not _has_bounds:
		return false
	var lo := _world_bounds.position
	var hi := _world_bounds.end
	return p.y < lo.y - fall_limit \
		or p.y > hi.y + side_limit \
		or p.x < lo.x - side_limit \
		or p.x > hi.x + side_limit


## Adds the corners of the node's visible meshes (or a small box around it).
func _add_node_points(node: Node3D, points: PackedVector3Array) -> void:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)

	var found := false
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		for i in 8:
			points.append(box.get_endpoint(i))
		found = true

	if not found:
		var center := node.global_position
		for i in 8:
			var corner := Vector3(
				0.5 if i & 1 else -0.5,
				0.5 if i & 2 else -0.5,
				0.5 if i & 4 else -0.5)
			points.append(center + corner)


## How far the view reaches sideways (x) and upwards (y) per unit of depth, shrunk by
## `free_space` (a fraction of the screen that must stay empty at the edges).
func _view_tangents(free_space: float) -> Vector2:
	var view_size := get_viewport().get_visible_rect().size
	var aspect := view_size.x / maxf(view_size.y, 1.0)
	var half_fov := tan(deg_to_rad(fov) * 0.5)
	var tan_x := half_fov * aspect
	var tan_y := half_fov
	if keep_aspect == Camera3D.KEEP_WIDTH:
		tan_x = half_fov
		tan_y = half_fov / aspect
	return Vector2(tan_x, tan_y) * (1.0 - free_space)


## True if every point is visible with at least `edge_tolerance` of free space to the edge.
func _is_comfortable(points: PackedVector3Array) -> bool:
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		return true
	var basis := global_transform.basis.orthonormalized()
	var tangents := _view_tangents(minf(edge_tolerance, margin))
	for p in points:
		var rel := p - global_position
		var depth := rel.dot(-basis.z)
		if depth <= near:
			return false
		if absf(rel.dot(basis.x)) > tangents.x * depth or absf(rel.dot(basis.y)) > tangents.y * depth:
			return false
	return true


# --- Solving for the camera position ----------------------------------------

## Returns the camera position (same rotation, same FOV) that shows all points.
func _frame_points(points: PackedVector3Array) -> Vector3:
	var basis := global_transform.basis.orthonormalized()
	var right := basis.x
	var up := basis.y
	var forward := -basis.z

	# Every point in camera axes: x = right, y = up, z = depth along the view direction.
	var coords: Array[Vector3] = []
	var min_c := Vector3(INF, INF, INF)
	var max_c := Vector3(-INF, -INF, -INF)
	for p in points:
		var c := Vector3(p.dot(right), p.dot(up), p.dot(forward))
		coords.append(c)
		min_c = min_c.min(c)
		max_c = max_c.max(c)

	# Never frame an area smaller than min_framing_size.
	var center := (min_c + max_c) * 0.5
	var half := min_framing_size * 0.5
	coords.append(Vector3(center.x - half.x, center.y - half.y, center.z))
	coords.append(Vector3(center.x + half.x, center.y - half.y, center.z))
	coords.append(Vector3(center.x - half.x, center.y + half.y, center.z))
	coords.append(Vector3(center.x + half.x, center.y + half.y, center.z))
	min_c.x = minf(min_c.x, center.x - half.x)
	max_c.x = maxf(max_c.x, center.x + half.x)
	min_c.y = minf(min_c.y, center.y - half.y)
	max_c.y = maxf(max_c.y, center.y + half.y)

	# Orthogonal cameras have no perspective: just center the targets.
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		var current_depth := global_position.dot(forward)
		return right * ((min_c.x + max_c.x) * 0.5) + up * ((min_c.y + max_c.y) * 0.5) + forward * current_depth

	var tangents := _view_tangents(margin)
	var tan_x := tangents.x
	var tan_y := tangents.y

	# Find the smallest distance behind the nearest point where everything fits.
	var near_depth := min_c.z
	for c in coords:
		near_depth = minf(near_depth, c.z)

	var t_low := 0.5
	var t_high := 500.0
	var t := t_low
	if not _fits(coords, near_depth, t_low, tan_x, tan_y):
		if not _fits(coords, near_depth, t_high, tan_x, tan_y):
			t = t_high
		else:
			for i in 24:
				var mid := (t_low + t_high) * 0.5
				if _fits(coords, near_depth, mid, tan_x, tan_y):
					t_high = mid
				else:
					t_low = mid
			t = t_high

	# Center the targets sideways and vertically at that distance.
	var lo_x := -INF
	var hi_x := INF
	var lo_y := -INF
	var hi_y := INF
	for c in coords:
		var depth := (c.z - near_depth) + t
		lo_x = maxf(lo_x, c.x - tan_x * depth)
		hi_x = minf(hi_x, c.x + tan_x * depth)
		lo_y = maxf(lo_y, c.y - tan_y * depth)
		hi_y = minf(hi_y, c.y + tan_y * depth)

	var cam_x := (lo_x + hi_x) * 0.5
	var cam_y := (lo_y + hi_y) * 0.5
	var cam_depth := near_depth - t
	return right * cam_x + up * cam_y + forward * cam_depth


## True if a camera `t` behind the nearest point can see all points.
func _fits(coords: Array[Vector3], near_depth: float, t: float, tan_x: float, tan_y: float) -> bool:
	var lo_x := -INF
	var hi_x := INF
	var lo_y := -INF
	var hi_y := INF
	for c in coords:
		var depth := (c.z - near_depth) + t
		lo_x = maxf(lo_x, c.x - tan_x * depth)
		hi_x = minf(hi_x, c.x + tan_x * depth)
		lo_y = maxf(lo_y, c.y - tan_y * depth)
		hi_y = minf(hi_y, c.y + tan_y * depth)
	return lo_x <= hi_x and lo_y <= hi_y

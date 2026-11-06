extends RigidBody3D
## The main enemy.
##
## It dies when:
##  - the player hits it (the slingshot calls `take_hit()`), or
##  - its velocity changes too much in one physics frame (a hard hit, a hard landing,
##    a blast).
##
## On death it spawns a smoke burst and a "+500" popup, emits `died` and removes itself.

signal died(points: int)

const DeathSmoke := preload("res://scenes/includes/death_smoke.gd")
const PointsScene := preload("res://scenes/ui/points.tscn")
const MonkeyAntics := preload("res://scenes/includes/characters/monkey_antics.gd")

## Points awarded for killing this enemy.
@export var points: int = 500
## The enemy dies if its velocity changes by more than this (m/s) within one physics frame.
## Gravity alone adds about 0.16 per frame, so only real impacts reach this.
@export var death_velocity_change: float = 4.0
## Minimum strength of a direct hit (shot speed) needed to kill it. 0 = any hit kills.
@export var min_hit_strength: float = 0.0
## Seconds after spawning during which velocity changes are ignored (physics settling).
@export var grace_time: float = 0.5
## Scale of the smoke burst.
@export var smoke_size: float = 1.0
## Where the popup appears, relative to the enemy's center.
@export var popup_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
## Keep the enemy in the X/Y plane it spawned in (no Z movement, no tumbling around X/Y).
## Must match the plane the slingshot shoots in.
@export var lock_to_side_view: bool = true

var _alive: bool = true
var _age: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("enemies")
	# AFK-kaaos: tavalliset apinat alkavat riehua, kun pelaaja ei tee mitään.
	# (Pomoilla on omat hyppynsä, ne lukevat AFK-ajan suoraan.)
	if not has_node("Visual") and not Engine.is_editor_hint():
		var antics := MonkeyAntics.new()
		antics.name = "Antics"
		add_child(antics)
	# Level walls are on physics layer 3 (value 4): enemies collide with them, shots and
	# block debris (layer 2) do not.
	collision_mask |= 4
	_last_velocity = linear_velocity
	# Fast shots must not tunnel through a thin enemy.
	continuous_cd = true
	if lock_to_side_view:
		axis_lock_linear_z = true
		axis_lock_angular_x = true
		axis_lock_angular_y = true


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_age += delta
	var velocity_change := linear_velocity.distance_to(_last_velocity)
	_last_velocity = linear_velocity
	if _age >= grace_time and velocity_change >= death_velocity_change:
		die()


## Called by the slingshot when a shot hits this enemy.
func take_hit(strength: float, _hit_position: Vector3 = Vector3.ZERO, _direction: Vector3 = Vector3.ZERO) -> void:
	if strength >= min_hit_strength:
		die()


## Used by kill zones: dies at once (bosses override this).
func kill() -> void:
	die()


func die() -> void:
	if not _alive:
		return
	_alive = false

	var center := _center()
	MonkeyAntics.on_monkey_died(center)
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_parent()

	var smoke := DeathSmoke.new()
	smoke.size = smoke_size
	world.add_child(smoke)
	smoke.global_position = center

	var popup := PointsScene.instantiate()
	popup.set("points", points)
	popup.set("world_position", center + popup_offset)
	world.add_child(popup)

	died.emit(points)
	queue_free()


func _center() -> Vector3:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		return shape.global_position
	return global_position

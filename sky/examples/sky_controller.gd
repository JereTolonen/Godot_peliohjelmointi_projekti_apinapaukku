extends Node3D
## Makes the stylized sky dynamic: cloud density slowly changes and the clouds drift
## with a wandering wind.
##
## Attach to the root of the sky scene. It needs a WorldEnvironment whose sky material
## is a ShaderMaterial using res://sky/stylized_sky.gdshader.
##
## From other scripts:
##   sky.set_density(0.9, 5.0)                    # clouds thicken over 5 seconds
##   sky.set_cloud_position(Vector2(0.2, 0.0), 4.0)
##   sky.set_wind(45.0, 0.004)                    # direction in degrees, speed

const DEFAULT_DRIFT := Vector2(0.001, 0.001)

## The WorldEnvironment to control. Found automatically if it is a child named "WorldEnvironment".
@export var world_environment: WorldEnvironment

@export_group("Density")
## Let the density change slowly on its own between min and max.
@export var animate_density: bool = true
## Current cloud density. Edit it directly when `animate_density` is off.
@export_range(0.0, 1.0, 0.01) var density: float = 0.5
@export_range(0.0, 1.0, 0.01) var density_min: float = 0.25
@export_range(0.0, 1.0, 0.01) var density_max: float = 0.75
## How fast the density changes (higher = faster).
@export_range(0.001, 1.0, 0.001) var density_change_speed: float = 0.03

@export_group("Cloud position")
## Extra offset added on top of the drift. Change it with set_cloud_position() to slide the clouds.
@export var cloud_offset: Vector2 = Vector2.ZERO
## Let the clouds drift with the wind.
@export var animate_wind: bool = true
## Wind direction in degrees (0 = +X).
@export_range(0.0, 360.0, 1.0) var wind_direction_degrees: float = 45.0
## Cloud drift speed. The original sky drifted at about 0.0014.
@export_range(0.0, 0.02, 0.0001) var wind_speed: float = 0.0015
## The wind direction wanders by up to this many degrees. 0 keeps it constant.
@export_range(0.0, 180.0, 1.0) var wind_wander_degrees: float = 25.0
## How fast the wind direction wanders.
@export_range(0.001, 1.0, 0.001) var wind_wander_speed: float = 0.02

var _material: ShaderMaterial = null
var _drift: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _density_noise := FastNoiseLite.new()
var _wind_noise := FastNoiseLite.new()
var _density_tween: Tween = null
var _position_tween: Tween = null


func _ready() -> void:
	if world_environment == null:
		world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment != null and world_environment.environment != null \
			and world_environment.environment.sky != null:
		_material = world_environment.environment.sky.sky_material as ShaderMaterial
	if _material == null:
		push_warning("SkyController: no ShaderMaterial sky found, nothing to animate.")
		set_process(false)
		return

	_density_noise.seed = randi()
	_density_noise.frequency = 1.0
	_wind_noise.seed = randi()
	_wind_noise.frequency = 1.0

	# This script moves the clouds itself, so turn off the shader's built-in drift.
	_material.set_shader_parameter("clouds_drift", Vector2.ZERO)


func _exit_tree() -> void:
	# Give the shared material its default behaviour back.
	if _material != null:
		_material.set_shader_parameter("clouds_drift", DEFAULT_DRIFT)
		_material.set_shader_parameter("clouds_offset", Vector2.ZERO)


func _process(delta: float) -> void:
	_time += delta

	if animate_density:
		var n := clampf(_density_noise.get_noise_1d(_time * density_change_speed) * 1.6, -1.0, 1.0)
		density = lerpf(density_min, density_max, n * 0.5 + 0.5)

	if animate_wind:
		var wander := _wind_noise.get_noise_1d(_time * wind_wander_speed) * wind_wander_degrees
		var angle := deg_to_rad(wind_direction_degrees + wander)
		_drift += Vector2.from_angle(angle) * wind_speed * delta

	_material.set_shader_parameter("clouds_density", clampf(density, 0.0, 1.0))
	_material.set_shader_parameter("clouds_offset", _drift + cloud_offset)


## Smoothly changes the cloud density. Turns off automatic density changes
## (set `animate_density = true` again to resume them).
func set_density(target: float, duration: float = 3.0) -> void:
	animate_density = false
	if _density_tween != null and _density_tween.is_valid():
		_density_tween.kill()
	_density_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_density_tween.tween_property(self, "density", clampf(target, 0.0, 1.0), maxf(duration, 0.01))


## Smoothly slides the clouds to a new offset (on top of the wind drift).
func set_cloud_position(target: Vector2, duration: float = 3.0) -> void:
	if _position_tween != null and _position_tween.is_valid():
		_position_tween.kill()
	_position_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_position_tween.tween_property(self, "cloud_offset", target, maxf(duration, 0.01))


## Changes the wind and turns wind drift on.
func set_wind(direction_degrees: float, speed: float) -> void:
	wind_direction_degrees = direction_degrees
	wind_speed = speed
	animate_wind = true

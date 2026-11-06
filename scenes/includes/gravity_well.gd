@tool
extends Node3D
## Gravity well with a planet attached.
##
## The slingshot asks every node in the "gravity_wells" group for `get_pull_acceleration()`
## and bends the flight of shots with it. A positive `strength` attracts shots (blue),
## a negative `strength` pushes them away (red).

## Pull acceleration (m/s^2) at the center of the planet. Negative = repels.
@export var strength: float = 9.0:
	set(value):
		strength = value
		_update_visuals()
## Distance from the center in which the well affects shots.
@export var field_radius: float = 7.0:
	set(value):
		field_radius = maxf(value, 0.5)
		_update_visuals()
## Size of the planet mesh.
@export var planet_radius: float = 1.2:
	set(value):
		planet_radius = maxf(value, 0.1)
		_update_visuals()
@export var planet_color: Color = Color(0.35, 0.6, 1.0):
	set(value):
		planet_color = value
		_update_visuals()
## Show the faint sphere that marks the area of effect.
@export var show_field: bool = true:
	set(value):
		show_field = value
		_update_visuals()

var _planet_material: StandardMaterial3D = null
var _field_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("gravity_wells")
	_update_visuals()


## Acceleration applied to a shot at `world_pos`. Kept in the X/Y plane.
func get_pull_acceleration(world_pos: Vector3) -> Vector3:
	var offset := global_position - world_pos
	offset.z = 0.0
	var distance := offset.length()
	if distance > field_radius or distance < 0.05:
		return Vector3.ZERO
	var falloff := 1.0 - distance / field_radius
	return offset / distance * strength * falloff


func _update_visuals() -> void:
	if not is_node_ready():
		return

	var planet := get_node_or_null("Planet") as MeshInstance3D
	if planet != null:
		planet.scale = Vector3.ONE * planet_radius * 2.0
		if _planet_material == null:
			_planet_material = StandardMaterial3D.new()
			_planet_material.roughness = 0.8
			_planet_material.emission_enabled = true
			planet.material_override = _planet_material
		_planet_material.albedo_color = planet_color
		_planet_material.emission = planet_color
		_planet_material.emission_energy_multiplier = 0.35

	var field := get_node_or_null("Field") as MeshInstance3D
	if field != null:
		field.visible = show_field
		field.scale = Vector3.ONE * field_radius * 2.0
		if _field_material == null:
			_field_material = StandardMaterial3D.new()
			_field_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_field_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			field.material_override = _field_material
		var tint := planet_color if strength >= 0.0 else Color(1.0, 0.3, 0.25)
		_field_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.07)

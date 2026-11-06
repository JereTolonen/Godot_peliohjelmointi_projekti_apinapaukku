extends Node3D
## Pohja hahmoille, joilla on erikoiskyky. Ritsa kutsuu activate_ability(), kun pelaaja
## napauttaa (hiiri tai kosketus) hahmon ollessa ilmassa. Kyky toimii kerran per laukaus.
##
## Aliluokka toteuttaa _on_activate(body, slingshot). Pohja hoitaa yhteisen
## välähdysefektin teeman värillä.

const Vfx := preload("res://scenes/visual/vfx.gd")

## Kyvyn väri efekteissä.
@export var ability_color: Color = Color(1.0, 0.9, 0.4)

var ability_used: bool = false


func activate_ability(body: RigidBody3D, slingshot: Node) -> bool:
	if ability_used or not is_instance_valid(body):
		return false
	ability_used = true
	Vfx.ability_flash(_world(), body.global_position, ability_color)
	_on_activate(body, slingshot)
	return true


func _on_activate(_body: RigidBody3D, _slingshot: Node) -> void:
	pass


func _world() -> Node:
	var world: Node = get_tree().current_scene
	return world if world != null else get_parent()


## Vahinko ja työntö kaikkiin kappaleisiin `radius`-säteellä (sama periaate kuin räjähdyksessä).
func _area_hit(center: Vector3, radius: float, damage: float, force: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	var seen: Array[int] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var collider := hit["collider"] as Object
		if collider == null or not is_instance_valid(collider) or seen.has(collider.get_instance_id()):
			continue
		seen.append(collider.get_instance_id())
		var target := collider as Node3D
		if target == null or target.is_ancestor_of(self):
			continue
		var offset := target.global_position - center
		offset.z = 0.0
		var falloff := clampf(1.0 - offset.length() / radius, 0.0, 1.0)
		if collider is RigidBody3D:
			(collider as RigidBody3D).apply_central_impulse((offset.normalized() + Vector3.UP * 0.4) * force * falloff)
		if collider.has_method("take_hit"):
			collider.call("take_hit", damage * maxf(falloff, 0.3), center, offset.normalized())

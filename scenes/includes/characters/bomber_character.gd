extends "res://scenes/includes/characters/ability_character.gd"
## POMMITTAJA: napautus pudottaa räjähtävän munan suoraan alas ja ponnauttaa hahmon
## ylös ja eteenpäin.

const ExplodingCharacter := preload("res://scenes/includes/characters/exploding_character.gd")
const BananaModel := preload("res://scenes/includes/characters/banana_model.gd")

@export var egg_speed: float = 12.0
@export var hop_speed: float = 9.0


func _on_activate(body: RigidBody3D, slingshot: Node) -> void:
	if slingshot != null and slingshot.has_method("add_projectile"):
		var egg := _make_egg()
		slingshot.call("add_projectile", egg, body.global_position + Vector3(0, -0.9, 0),
			Vector3(body.linear_velocity.x * 0.2, -egg_speed, 0.0), [body])
	body.linear_velocity = Vector3(maxf(body.linear_velocity.x, 5.0) * 1.15, hop_speed, 0.0)
	Vfx.feather_puff(_world(), body.global_position)


## Pieni banaanipommi, joka räjähtää osuessaan (sama räjähdys kuin räjähtävällä hahmolla).
func _make_egg() -> Node3D:
	var egg := Node3D.new()
	egg.name = "BananaBomb"
	egg.set_script(ExplodingCharacter)
	egg.set("explosion_size", 0.8)
	egg.set("blast_radius", 3.0)
	egg.set("blast_damage", 45.0)
	var banana := Node3D.new()
	banana.set_script(BananaModel)
	banana.set("length", 0.6)
	banana.set("thickness", 0.13)
	banana.set("peel_color", Color(0.91, 0.27, 0.18))
	banana.set("fuse", true)
	banana.rotation.z = -PI * 0.5
	egg.add_child(banana)
	return egg

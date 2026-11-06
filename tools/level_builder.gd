@tool
extends Node
## One-off generator for levels 1-20 (res://scenes/levels/levelN.tscn).
##
## Call `build_all()` from the editor (the MCP does this). It opens every level scene,
## rebuilds the ground, walls, kill zones, enemies, blocks, dynamite, gravity wells and
## hints, and saves the scene again. The generated nodes are ordinary nodes: edit them by
## hand afterwards. Running it again REPLACES those nodes, so edits are lost.
##
## Levels 1-5 plains (tutorial), 6-10 snow, 11-20 space. Bosses on 10, 15 and 20.

const LEVEL_PATH := "res://scenes/levels/level%d.tscn"
const LEVEL_COUNT := 60
const ENEMY_SCENE := "res://scenes/includes/characters/enemy_plain.tscn"
const BLOCK_SCENE := "res://scenes/includes/blocks/block.tscn"
const DYNAMITE_SCENE := "res://scenes/includes/blocks/dynamite.tscn"
const GROUND_PLAINS_SCENE := "res://scenes/includes/grounds/ground_plains.tscn"
const GROUND_SNOW_SCENE := "res://scenes/includes/grounds/ground_snowy.tscn"
const WELL_SCENE := "res://scenes/includes/gravity_well.tscn"
const BOSS_SNOW_SCENE := "res://scenes/includes/characters/boss_snow.tscn"
const BOSS_SPACE_SCENE := "res://scenes/includes/characters/boss_space.tscn"
const BOSS_FINAL_SCENE := "res://scenes/includes/characters/boss_final.tscn"
const LEVEL_SCRIPT := "res://scenes/game/level.gd"
const KILLZONE_SCRIPT := "res://scenes/includes/killzone.gd"
const HINT_SCRIPT := "res://scenes/includes/tutorial_hint.gd"
const WELL_SCRIPT := "res://scenes/includes/gravity_well.gd"
const BOSS_SCRIPT := "res://scenes/includes/characters/enemy_boss.gd"

## Top of the ground in all levels.
const GY := 0.5
const CONTAINERS := ["Enemies", "Blocks", "Platforms", "Wells", "Hints", "Walls", "KillZones"]

const BLOCK_TYPES := {
	"wood": {"color": Color(0.72, 0.5, 0.28), "hp": 40.0, "density": 0.8, "friction": 0.8, "bounce": 0.05},
	"stone": {"color": Color(0.55, 0.56, 0.62), "hp": 90.0, "density": 2.0, "friction": 0.9, "bounce": 0.0},
	"ice": {"color": Color(0.62, 0.86, 1.0), "hp": 25.0, "density": 0.7, "friction": 0.03, "bounce": 0.1},
}

var _counts: Dictionary = {}


func build_all() -> String:
	var report: PackedStringArray = []
	report.append("well scene: %d" % _make_well_scene())
	report.append("boss scenes: %d" % _make_boss_scenes())
	for n in range(1, 21):
		var err := _build_level(n)
		report.append("level%d: %s" % [n, "ok" if err == OK else "error %d" % err])
	EditorInterface.get_resource_filesystem().scan()
	for path in EditorInterface.get_open_scenes():
		if path.begins_with("res://scenes/levels/"):
			EditorInterface.reload_scene_from_path(path)
	return "\n".join(report)


## Rebuilds only the 20 level scenes (well and boss scenes are left untouched).
func build_levels() -> String:
	var report: PackedStringArray = []
	for n in range(1, LEVEL_COUNT + 1):
		_ensure_level_file(n)
		var err := _build_level(n)
		report.append("level%d: %s" % [n, "ok" if err == OK else "error %d" % err])
	EditorInterface.get_resource_filesystem().scan()
	for path in EditorInterface.get_open_scenes():
		if path.begins_with("res://scenes/levels/"):
			EditorInterface.reload_scene_from_path(path)
	return "\n".join(report)


# --- Level assembly ----------------------------------------------------------------

func _build_level(n: int) -> int:
	var path := LEVEL_PATH % n
	if not ResourceLoader.exists(path):
		return ERR_FILE_NOT_FOUND
	_counts.clear()
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var root := packed.instantiate()
	# 1-5 plains, 6-10 snow, 11-20 space, 21-52 ground worlds (beach, cave, volcano,
	# exoplanet: the look comes from the visual theme), 53-60 floating sky islands.
	var kind := "plains"
	if n > 52:
		kind = "space"
	elif n > 20:
		kind = "plains"
	elif n > 10:
		kind = "space"
	elif n > 5:
		kind = "snow"

	_reset(root, kind)
	if root.get_script() == null:
		root.set_script(load(LEVEL_SCRIPT))
	_setup_ground(root, kind)
	_add_walls(root)
	_add_killzones(root)
	var ammo := _mix_characters(root, _fill_level(root, n), n)
	var ammo_names := PackedStringArray()
	for c in ammo:
		ammo_names.append(AMMO_LETTERS.get(c, "normal"))
	root.set("ammo", ammo_names)

	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	return err


## Ammusjonon kirjaimet -> hahmo-scenet (scenes/includes/characters/<nimi>.tscn).
const AMMO_LETTERS := {
	"n": "normal", "e": "exploding", "s": "speedy", "p": "splitter", "h": "heavy", "b": "bomber",
}
## Erikoishahmot: [kirjain, esittelykenttä, esittelyvihje].
const SPECIAL_CHARACTERS := [
	["s", 4, "UUSI HAHMO: Nopea! Napauta ruutua lennon aikana, niin se syöksyy suoraan eteenpäin."],
	["p", 8, "UUSI HAHMO: Jakautuva! Napauta lennon aikana, niin se jakautuu kolmeksi."],
	["h", 12, "UUSI HAHMO: Painava! Napauta, niin se iskeytyy suoraan alas ja lähettää iskuaallon."],
	["b", 16, "UUSI HAHMO: Pommittaja! Napauta, niin se pudottaa räjähtävän munan ja pomppaa ylös."],
]


## Vaihtaa osan perusammuksista erikoishahmoiksi sitä mukaa kuin ne on esitelty.
## Ensimmäinen ammus pysyy perushahmona. Esittelykentässä uusi hahmo on toisena ja
## kentän alkuun tulee vihje.
func _mix_characters(root: Node, ammo: String, n: int) -> String:
	if n == 2:
		_intro_hint(root, "Vinkki: napauta räjähtävää ammusta lennon aikana, niin se räjähtää heti.", false)
	var unlocked: Array = []
	var intro := ""
	for spec in SPECIAL_CHARACTERS:
		if n >= int(spec[1]):
			unlocked.append(spec[0])
		if n == int(spec[1]):
			intro = spec[0]
			_intro_hint(root, spec[2], true)
	if unlocked.is_empty():
		return ammo
	var chars := ammo.split("")
	var normals: Array[int] = []
	for i in range(1, chars.size()):
		if chars[i] == "n":
			normals.append(i)
	# Leave at least one extra plain shot after the first.
	var count := mini(mini(unlocked.size(), 2 + n / 25), normals.size() - 1)
	for k in maxi(count, 0):
		var letter: String = unlocked[(n + k) % unlocked.size()]
		if k == 0 and intro != "":
			letter = intro
		chars[normals[k]] = letter
	return "".join(chars)


## Lisää vihjeen kentän vihjelistaan (alkuun tai loppuun) tai luo listan.
func _intro_hint(root: Node, text: String, first: bool) -> void:
	var hints := root.get_node_or_null("Hints")
	if hints == null:
		_hint(root, [text])
		return
	var steps: PackedStringArray = hints.get("steps")
	if first:
		steps.insert(0, text)
	else:
		steps.append(text)
	hints.set("steps", steps)


func _reset(root: Node, kind: String) -> void:
	for child in root.get_children():
		var node_name := String(child.name)
		var remove := node_name in CONTAINERS or node_name.begins_with("Enemy") or node_name.begins_with("Node3D")
		if node_name.begins_with("Ground") and kind != "plains":
			remove = true
		if remove:
			root.remove_child(child)
			child.free()


func _setup_ground(root: Node, kind: String) -> void:
	match kind:
		"plains":
			if root.get_node_or_null("GroundPlains") == null:
				var ground := (load(GROUND_PLAINS_SCENE) as PackedScene).instantiate()
				ground.name = "GroundPlains"
				root.add_child(ground)
				ground.owner = root
				root.move_child(ground, 0)
		"snow":
			var snow := (load(GROUND_SNOW_SCENE) as PackedScene).instantiate()
			snow.name = "GroundSnowy"
			root.add_child(snow)
			snow.owner = root
			root.move_child(snow, 0)
		"space":
			# No ground in space: the slingshot stands on its own asteroid.
			_pf(root, -8.8, GY, 7.0)


func _add_walls(root: Node) -> void:
	var walls := _container(root, "Walls")
	for entry in [["WallLeft", -11.5], ["WallRight", 15.0]]:
		var body := StaticBody3D.new()
		body.name = entry[0]
		body.position = Vector3(entry[1], 2.25, 0.0)
		# Layer 3 (value 4): enemies collide with it, shots and debris do not.
		body.collision_layer = 4
		body.collision_mask = 0
		_own(root, body, walls)
		var size := Vector3(0.5, 3.5, 6.0)
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		_own(root, shape, body)
		var visual := MeshInstance3D.new()
		visual.name = "MeshInstance3D"
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.6, 0.8, 1.0, 0.1)
		mesh.material = material
		visual.mesh = mesh
		_own(root, visual, body)


func _add_killzones(root: Node) -> void:
	var zones := _container(root, "KillZones")
	var specs := [
		["KillZoneLeft", Vector3(-29.0, 0.0, 0.0), Vector3(35.0, 40.0, 8.0)],
		["KillZoneRight", Vector3(31.0, 0.0, 0.0), Vector3(32.0, 40.0, 8.0)],
		["KillZoneBottom", Vector3(0.0, -10.0, 0.0), Vector3(120.0, 4.0, 8.0)],
	]
	for spec in specs:
		var area := Area3D.new()
		area.name = spec[0]
		area.position = spec[1]
		area.set_script(load(KILLZONE_SCRIPT))
		_own(root, area, zones)
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = spec[2]
		shape.shape = box
		_own(root, shape, area)


# --- Building blocks ---------------------------------------------------------------

func _next(prefix: String) -> int:
	_counts[prefix] = int(_counts.get(prefix, 0)) + 1
	return int(_counts[prefix])


func _container(root: Node, container_name: String) -> Node3D:
	var c := root.get_node_or_null(container_name) as Node3D
	if c == null:
		c = Node3D.new()
		c.name = container_name
		root.add_child(c)
		c.owner = root
	return c


func _own(root: Node, node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = root


## Enemy standing with its feet at `base_y`.
func _e(root: Node, x: float, base_y: float, props: Dictionary = {}, scene: String = ENEMY_SCENE) -> Node3D:
	var enemy := (load(scene) as PackedScene).instantiate() as Node3D
	enemy.name = "Enemy%d" % _next("Enemy")
	enemy.position = Vector3(x, base_y + 0.1, 0.0)
	for key in props:
		enemy.set(key, props[key])
	_own(root, enemy, _container(root, "Enemies"))
	return enemy


func _boss(root: Node, scene: String, x: float, base_y: float) -> Node3D:
	var boss := _e(root, x, base_y, {}, scene)
	boss.name = "Boss"
	return boss


## Block of `type` ("wood", "stone", "ice") centered at (x, y).
func _b(root: Node, type: String, x: float, y: float, w: float = 1.0, h: float = 1.0, d: float = 1.2) -> RigidBody3D:
	var spec: Dictionary = BLOCK_TYPES[type]
	var block := (load(BLOCK_SCENE) as PackedScene).instantiate() as RigidBody3D
	block.name = "%s%d" % [type.capitalize(), _next(type)]
	var size := Vector3(w, h, d)

	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = spec["color"]
	material.roughness = 0.8
	mesh.material = material
	(block.get_node("MeshInstance3D") as MeshInstance3D).mesh = mesh

	var box := BoxShape3D.new()
	box.size = size
	(block.get_node("CollisionShape3D") as CollisionShape3D).shape = box

	block.mass = maxf(w * h * d * float(spec["density"]), 0.2)
	block.set("max_health", spec["hp"])
	block.set("debris_color", spec["color"])
	var physics := PhysicsMaterial.new()
	physics.friction = spec["friction"]
	physics.bounce = spec["bounce"]
	block.physics_material_override = physics
	block.position = Vector3(x, y, 0.0)
	_own(root, block, _container(root, "Blocks"))
	# Without this the mesh/shape size overrides are not saved and every block
	# would load as a 1x1x1 cube.
	root.set_editable_instance(block, true)
	return block


## Vertical stack of `count` blocks standing on `base_y`.
func _stack(root: Node, type: String, x: float, count: int, base_y: float = GY, w: float = 1.0, h: float = 1.0) -> float:
	for i in count:
		_b(root, type, x, base_y + h * (float(i) + 0.5), w, h)
	return base_y + h * float(count)


## Two pillars with a plank on top. Returns the Y of the top of the plank.
func _table(root: Node, type: String, cx: float, base_y: float, pillar_h: float, span: float = 2.4, plank_w: float = 3.4) -> float:
	_b(root, type, cx - span * 0.5, base_y + pillar_h * 0.5, 0.6, pillar_h)
	_b(root, type, cx + span * 0.5, base_y + pillar_h * 0.5, 0.6, pillar_h)
	_b(root, type, cx, base_y + pillar_h + 0.25, plank_w, 0.5)
	return base_y + pillar_h + 0.5


## One storey: two pillars of `type` and a plank (`plank_type`, default same) on top.
## Returns the Y of the top of the plank.
func _floor(root: Node, type: String, cx: float, base_y: float, pillar_h: float, span: float = 2.2, plank_type: String = "") -> float:
	var pt := plank_type if plank_type != "" else type
	_b(root, type, cx - span * 0.5, base_y + pillar_h * 0.5, 0.5, pillar_h)
	_b(root, type, cx + span * 0.5, base_y + pillar_h * 0.5, 0.5, pillar_h)
	_b(root, pt, cx, base_y + pillar_h + 0.25, span + 0.9, 0.5)
	return base_y + pillar_h + 0.5


func _dyn(root: Node, x: float, base_y: float) -> Node3D:
	var dynamite := (load(DYNAMITE_SCENE) as PackedScene).instantiate() as Node3D
	dynamite.name = "Dynamite%d" % _next("Dynamite")
	dynamite.position = Vector3(x, base_y + 0.41, 0.0)
	_own(root, dynamite, _container(root, "Blocks"))
	return dynamite


## Floating rock platform whose top surface is at `top`.
func _pf(root: Node, cx: float, top: float, w: float, d: float = 4.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Platform%d" % _next("Platform")
	body.position = Vector3(cx, top - 0.5, 0.0)
	_own(root, body, _container(root, "Platforms"))

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(w, 1.0, d)
	shape.shape = box
	_own(root, shape, body)

	_add_box_visual(root, body, "Rock", Vector3(w, 1.0, d), Vector3.ZERO, Color(0.34, 0.32, 0.42))
	_add_box_visual(root, body, "Top", Vector3(w, 0.12, d + 0.02), Vector3(0.0, 0.44, 0.0), Color(0.55, 0.55, 0.72))
	return body


func _add_box_visual(root: Node, parent: Node, node_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	visual.mesh = mesh
	visual.position = pos
	_own(root, visual, parent)


func _well(root: Node, x: float, y: float, strength: float, field: float, radius: float, color: Color) -> Node3D:
	var well := (load(WELL_SCENE) as PackedScene).instantiate() as Node3D
	well.name = "GravityWell%d" % _next("Well")
	well.position = Vector3(x, y, 0.0)
	well.set("strength", strength)
	well.set("field_radius", field)
	well.set("planet_radius", radius)
	well.set("planet_color", color)
	_own(root, well, _container(root, "Wells"))
	return well


func _hint(root: Node, steps: Array) -> void:
	var hints := CanvasLayer.new()
	hints.name = "Hints"
	hints.set_script(load(HINT_SCRIPT))
	hints.set("steps", PackedStringArray(steps))
	_own(root, hints, root)


# --- The 20 levels -----------------------------------------------------------------

## Fills the level and returns the ammo queue: "n" = normal, "e" = exploding.
func _fill_level(root: Node, n: int) -> String:
	if n > 20:
		return _compose(root, n)
	var g := GY
	var armored := {"min_hit_strength": 9.0, "death_velocity_change": 6.0, "points": 800}
	var blue := Color(0.35, 0.6, 1.0)
	var red := Color(1.0, 0.35, 0.3)
	var purple := Color(0.7, 0.4, 1.0)
	var orange := Color(1.0, 0.65, 0.25)

	match n:
		# ---- Plains: tutorial -------------------------------------------------------
		1:
			# Shelter: one monkey under a small wooden roof.
			_floor(root, "wood", 7.0, g, 1.7, 2.2)
			_e(root, 7.0, g)
			_hint(root, [
				"Vedä ammusta ritsassa taaksepäin ja päästä irti ampuaksesi.",
				"Pisteviiva näyttää lentoradan. Mitä pidemmälle vedät, sitä kovempaa ammus lentää.",
				"Kaada kaikki apinat ennen kuin ammukset loppuvat!",
			])
			return "nnnn"
		2:
			# Wide fort: a long, low wooden building with three rooms.
			for px in [3.3, 6.75, 10.25, 13.7]:
				_b(root, "wood", px, g + 0.85, 0.5, 1.7)
			var roof := g + 1.7 + 0.25
			_b(root, "wood", 5.0, roof, 3.7, 0.5)
			_b(root, "wood", 8.5, roof, 3.5, 0.5)
			_b(root, "wood", 12.0, roof, 3.7, 0.5)
			_b(root, "ice", 8.5, roof + 0.75, 1.0, 1.0)
			_e(root, 5.0, g)
			_e(root, 8.5, g)
			_e(root, 12.0, g)
			_hint(root, [
				"Apinoita on useita, mutta ammuksia vain muutama.",
				"Räjähtävä ammus räjähtää osuessaan ja kaataa kaikki lähellä olevat apinat.",
				"Yritä osua niin, että yksi ammus hoitaa useamman apinan.",
			])
			return "nnne"
		3:
			# Two towers: a lookout with a monkey on top, and a two-storey house.
			var top_a := _floor(root, "wood", 4.5, g, 1.4, 2.0)
			_e(root, 4.5, top_a)
			var top_b := _floor(root, "wood", 10.5, g, 1.7, 2.2)
			var top_b2 := _floor(root, "wood", 10.5, top_b, 1.2, 1.6)
			_b(root, "ice", 10.5, top_b2 + 0.5, 1.0, 1.0)
			_e(root, 10.5, g)
			_hint(root, [
				"Palikat suojaavat apinoita.",
				"Ammu palikoita: osumista ne halkeilevat ja hajoavat.",
				"Voit myös ampua suojan yli suoraan apinaan.",
			])
			return "nnne"
		4:
			# Tall tower: three storeys getting narrower, a monkey on the very top.
			var t1 := _floor(root, "wood", 9.0, g, 1.8, 2.2)
			var t2 := _floor(root, "wood", 9.0, t1, 1.5, 1.8)
			var t3 := _floor(root, "wood", 9.0, t2, 1.2, 1.4)
			_e(root, 9.0, t3)
			_stack(root, "wood", 2.6, 2)
			_e(root, 3.8, g)
			_e(root, 12.8, g)
			_hint(root, [
				"Putoava palikka tai apina kuolee kovassa iskussa.",
				"Kaada torni, niin apina putoaa mukana.",
				"Voit ampua tornin jalkoja tai suoraan apinaa.",
			])
			return "nnne"
		5:
			# Stone keep with a wooden lookout and an ice cap, plus a wooden table.
			var keep := _floor(root, "stone", 6.0, g, 1.6, 2.4)
			var look := _floor(root, "wood", 6.0, keep, 1.4, 1.8)
			_b(root, "ice", 6.0, look + 0.5, 1.0, 1.0)
			_e(root, 6.0, g)
			var top := _table(root, "wood", 11.0, g, 2.0)
			_e(root, 11.0, top)
			_e(root, 13.3, g)
			_hint(root, [
				"Kivi kestää enemmän kuin puu.",
				"Apina, joka lentää kentän reunan yli, tippuu alueen ulkopuolelle ja kuolee.",
				"Yhdistä kaikki oppimasi. Onnea!",
			])
			return "nnnee"

		# ---- Snow -------------------------------------------------------------------
		6:
			# Ice pyramid shield and a two-storey ice tower.
			_b(root, "ice", 3.2, g + 0.5, 1.0, 1.0)
			_b(root, "ice", 4.2, g + 0.5, 1.0, 1.0)
			_b(root, "ice", 3.7, g + 1.5, 1.0, 1.0)
			_e(root, 5.6, g)
			var t1 := _floor(root, "ice", 10.0, g, 1.8, 2.2)
			var t2 := _floor(root, "ice", 10.0, t1, 1.2, 1.6)
			_e(root, 10.0, t2)
			_e(root, 13.2, g)
			_hint(root, ["Lumikentillä jää on liukasta. Jääpalikat liukuvat ja kaatuvat helposti."])
			return "nnne"
		7:
			# Wooden shed, loose dynamite, and an ice tower with dynamite inside.
			_floor(root, "wood", 4.4, g, 1.7, 2.0)
			_e(root, 4.4, g)
			_dyn(root, 7.2, g)
			_e(root, 8.8, g)
			var top := _floor(root, "ice", 12.2, g, 1.7, 2.2)
			_dyn(root, 12.2, g)
			_e(root, 12.2, top)
			_hint(root, [
				"Dynamiitti räjähtää, kun siihen osuu, ja kaataa kaikki lähellä olevat apinat.",
				"Dynamiitti voi sytyttää toisen dynamiitin. Ketjureaktio!",
			])
			return "nnne"
		8:
			# Multi-structure: wooden tower, ice barricade, stone and wood tower.
			var top_a := _floor(root, "wood", 4.6, g, 2.0, 2.2)
			_dyn(root, 4.6, g)
			_e(root, 4.6, top_a)
			_b(root, "ice", 6.9, g + 0.6, 0.8, 1.2)
			_e(root, 8.0, g)
			var top_b := _floor(root, "stone", 11.2, g, 2.2, 2.4)
			var top_b2 := _floor(root, "wood", 11.2, top_b, 1.2, 1.6)
			_dyn(root, 11.2, g)
			_e(root, 11.2, top_b2)
			_e(root, 13.8, g)
			return "nnnee"
		9:
			_hint(root, ["Panssaroidut apinat kestävät heikot osumat. Vedä ammus täysille!"])
			# Castle: a stone wall, and a stone gate house with a wooden lookout.
			_stack(root, "stone", 4.3, 4)
			_e(root, 6.6, g, armored)
			_dyn(root, 8.3, g)
			_b(root, "stone", 9.5, g + 1.6, 0.6, 3.2)
			_b(root, "stone", 12.5, g + 1.6, 0.6, 3.2)
			_b(root, "stone", 11.0, g + 3.45, 4.2, 0.5)
			var look := _floor(root, "wood", 11.0, g + 3.7, 1.2, 1.8)
			_e(root, 11.0, g, armored)
			_e(root, 11.0, look)
			return "nnnee"
		10:
			_hint(root, [
				"PÄÄPOMO: Lumiapina! Se kestää monta osumaa.",
				"Kova osuma tekee enemmän vahinkoa. Vedä täysille!",
				"Dynamiitti ja räjähtävä ammus auttavat.",
			])
			_floor(root, "ice", 4.6, g, 1.7, 1.8)
			_e(root, 4.6, g)
			_e(root, 7.0, g)
			_stack(root, "ice", 8.6, 3)
			_dyn(root, 9.7, g)
			_boss(root, BOSS_SNOW_SCENE, 11.5, g)
			return "nnnneee"

		# ---- Space ------------------------------------------------------------------
		11:
			_hint(root, [
				"Avaruudessa planeetan painovoima kaartaa ammuksen rataa.",
				"Tähtää planeetan ohi ja anna painovoiman tehdä loput.",
			])
			_pf(root, 11.0, g, 7.0)
			_b(root, "stone", 8.2, g + 0.5, 1.0, 1.0)
			_e(root, 9.5, g)
			_floor(root, "wood", 12.3, g, 1.7, 1.8)
			_e(root, 12.3, g)
			_well(root, 1.5, 4.0, 9.0, 7.5, 1.4, blue)
			return "nnnne"
		12:
			_pf(root, 11.5, g, 6.0)
			_e(root, 10.0, g)
			_floor(root, "ice", 12.8, g, 1.7, 1.6)
			_e(root, 12.8, g)
			_pf(root, 2.5, 2.2, 3.6)
			_e(root, 2.5, 2.2)
			_well(root, 6.5, 5.5, 9.0, 7.0, 1.3, blue)
			return "nnnee"
		13:
			_hint(root, ["Punaiset planeetat työntävät ammuksia poispäin."])
			_pf(root, 11.0, g, 7.5)
			var t1 := _floor(root, "wood", 11.6, g, 2.0, 2.4)
			var t2 := _floor(root, "ice", 11.6, t1, 1.2, 1.6)
			_e(root, 11.6, t2)
			_e(root, 8.7, g)
			_well(root, 0.5, 1.0, -10.0, 6.5, 1.2, red)
			return "nnnee"
		14:
			_pf(root, 11.5, g, 6.5)
			_e(root, 9.2, g)
			var top := _floor(root, "ice", 12.4, g, 1.8, 1.8)
			_dyn(root, 12.4, g)
			_e(root, 12.4, top)
			_pf(root, 5.0, 3.0, 3.2)
			_e(root, 5.0, 3.0)
			_well(root, 0.0, 4.5, 8.0, 6.5, 1.3, blue)
			_well(root, 8.0, 6.0, -8.0, 5.0, 1.0, red)
			return "nnneee"
		15:
			_hint(root, [
				"PÄÄPOMO: Avaruusapina! Se kestää monta osumaa.",
				"Käytä planeettojen painovoimaa ja dynamiittia hyväksesi.",
			])
			_pf(root, 11.5, g, 6.5)
			_boss(root, BOSS_SPACE_SCENE, 11.8, g)
			_e(root, 9.0, g)
			_dyn(root, 13.8, g)
			_pf(root, 3.0, 2.5, 3.2)
			_e(root, 3.0, 2.5)
			_well(root, 6.0, 5.0, 10.0, 7.5, 1.4, purple)
			_well(root, 0.5, 0.0, -8.0, 5.5, 1.0, red)
			return "nnnneeee"
		16:
			_pf(root, 3.0, 1.4, 3.4)
			_b(root, "ice", 1.8, 1.4 + 0.5, 0.9, 1.0)
			_e(root, 3.0, 1.4)
			_pf(root, 8.2, 3.2, 3.4)
			_b(root, "stone", 7.0, 3.2 + 0.5, 0.9, 1.0)
			_e(root, 8.2, 3.2, armored)
			_pf(root, 12.0, 0.8, 3.4)
			_e(root, 12.0, 0.8)
			_dyn(root, 13.0, 0.8)
			_pf(root, 13.2, 4.2, 2.6)
			_e(root, 13.2, 4.2, armored)
			_well(root, 6.0, 6.2, 10.0, 7.0, 1.3, blue)
			_well(root, 0.0, 2.5, -9.0, 5.5, 1.0, red)
			return "nnneee"
		17:
			_pf(root, 11.0, g, 7.5)
			_stack(root, "stone", 7.7, 3)
			_e(root, 9.4, g, armored)
			_dyn(root, 10.6, g)
			_e(root, 12.4, g, armored)
			# Stone shelter over the armored monkey (the roof used to float).
			_floor(root, "stone", 12.4, g, 2.5, 2.0)
			_pf(root, 3.5, 3.0, 3.2)
			_e(root, 3.5, 3.0)
			_well(root, 0.5, 5.5, 10.0, 7.0, 1.4, blue)
			_well(root, 6.5, 3.0, -9.0, 5.0, 1.0, red)
			return "nneee"
		18:
			_pf(root, 11.5, g, 6.0)
			_e(root, 9.6, g)
			var hut := _floor(root, "wood", 11.3, g, 1.6, 1.6)
			_b(root, "ice", 11.3, hut + 0.5, 1.0, 1.0)
			_dyn(root, 11.3, g)
			_e(root, 13.0, g, armored)
			_pf(root, 6.0, 2.4, 3.2)
			_e(root, 6.0, 2.4)
			_pf(root, 11.5, 5.2, 3.2)
			_e(root, 11.5, 5.2, armored)
			_well(root, -1.5, 3.0, -9.0, 5.5, 1.0, red)
			_well(root, 4.5, 6.0, 9.0, 6.5, 1.3, blue)
			_well(root, 9.5, 7.5, -8.0, 4.5, 1.0, red)
			return "nnneee"
		19:
			_pf(root, 11.5, g, 6.5)
			_b(root, "stone", 10.0, g + 1.0, 0.6, 2.0)
			_b(root, "stone", 13.0, g + 1.0, 0.6, 2.0)
			_b(root, "stone", 11.5, g + 2.25, 4.2, 0.5)
			_e(root, 11.5, g, armored)
			var top := g + 2.5
			_b(root, "wood", 10.3, top + 0.9, 0.6, 1.8)
			_b(root, "wood", 12.7, top + 0.9, 0.6, 1.8)
			_b(root, "wood", 11.5, top + 2.05, 3.4, 0.5)
			_e(root, 11.5, top + 2.3, armored)
			_dyn(root, 8.6, g)
			_pf(root, 3.0, 2.8, 3.4)
			_e(root, 3.0, 2.8)
			_well(root, 0.5, 5.0, 10.0, 7.0, 1.4, blue)
			_well(root, 6.5, 6.5, -8.0, 5.0, 1.0, red)
			_well(root, 6.5, 0.0, 8.0, 5.5, 1.1, orange)
			return "nnneee"
		20:
			_hint(root, [
				"LOPPUPOMO: Apinakuningas! Se kestää hyvin monta osumaa.",
				"Kolme planeettaa muuttaa ammusten rataa. Opettele ne.",
				"Käytä kaikki ammukset viisaasti. Onnea!",
			])
			_pf(root, 11.5, g, 6.5)
			_boss(root, BOSS_FINAL_SCENE, 11.8, g)
			_e(root, 8.9, g, armored)
			_dyn(root, 14.0, g)
			_pf(root, 3.5, 3.0, 3.4)
			_e(root, 3.5, 3.0, armored)
			_well(root, 1.0, 5.0, 10.0, 7.0, 1.4, blue)
			_well(root, 6.5, 2.0, -9.0, 5.0, 1.0, red)
			_well(root, 9.0, 7.0, 8.0, 5.0, 1.1, orange)
			return "nnnneeeee"
	return "nnnn"


# --- Levels 21-60: composed from structure archetypes -----------------------------------

const SLINGSHOT_SCENE := "res://scenes/includes/slingshot.tscn"

## Rakennusmateriaalit maailmoittain (painotettu arvonta).
const WORLD_MATERIALS := {
	"beach": ["wood", "wood", "wood", "stone", "ice"],
	"cave": ["stone", "stone", "wood", "ice", "ice"],
	"volcano": ["stone", "stone", "stone", "wood"],
	"exo": ["ice", "ice", "stone", "wood"],
	"sky": ["wood", "wood", "ice", "stone"],
}
## Kenttätyypit: jokainen rivi on yksi kenttä (rakennelmat vasemmalta oikealle).
const LAYOUTS := [
	["hut", "tower"],
	["fort"],
	["tower", "tower"],
	["pyramid", "keep"],
	["wall", "dynhouse", "tower"],
	["bridge", "tower"],
	["keep", "fort"],
	["tower3", "keep", "hut"],
]
const WIDTHS := {"hut": 2.9, "dynhouse": 2.9, "tower": 3.1, "tower3": 3.1, "fort": 6.1, "pyramid": 3.0, "keep": 3.3, "wall": 2.6, "bridge": 4.6}
const WORLD_HINTS := {
	"beach": ["RANTA! Puiset rantamajat hajoavat helposti.", "Etsi rakennelman heikko kohta ja kaada se apinoiden päälle."],
	"cave": ["LUOLA! Kivirakenteet ovat kestäviä.", "Ammu tukipilareita, niin koko rakennelma sortuu."],
	"volcano": ["TULIVUORI! Kivilinnoja ja dynamiittia joka puolella.", "Yksi osuma dynamiittiin voi laukaista ketjureaktion."],
	"exo": ["EKSOPLANEETTA! Painovoimakentät kaartavat ammuksen rataa.", "Sininen planeetta vetää, punainen työntää."],
	"sky": ["TAIVAANSAARET! Saaret leijuvat pilvien yllä.", "Kaada apinat saaren reunan yli – ne putoavat syvyyteen."],
}

var _rng: RandomNumberGenerator = null  # Created lazily in _compose() (survives hot reload).
var _mats: Array = []
var _difficulty: float = 0.0


## Luo tyhjän kenttäscenen (taso + ritsa), jos sitä ei vielä ole.
func _ensure_level_file(n: int) -> void:
	var path := LEVEL_PATH % n
	if ResourceLoader.exists(path):
		return
	var root := Node3D.new()
	root.name = "Level%d" % n
	root.set_script(load(LEVEL_SCRIPT))
	var sling := (load(SLINGSHOT_SCENE) as PackedScene).instantiate() as Node3D
	sling.name = "Slingshot"
	sling.position = Vector3(-8.829, 0.938, 0.0)
	root.add_child(sling)
	sling.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()


func _pick() -> String:
	return _mats[_rng.randi() % _mats.size()]


func _maybe_armored() -> Dictionary:
	if _rng.randf() < _difficulty * 0.35:
		return {"min_hit_strength": 9.0, "death_velocity_change": 6.0, "points": 800}
	return {}


func _compose(root: Node, n: int) -> String:
	var g := GY
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.seed = n * 7919 + 17
	var world_i := (n - 21) / 8
	var k := (n - 21) % 8
	var world: String = ["beach", "cave", "volcano", "exo", "sky"][world_i]
	_difficulty = float(n - 21) / 39.0
	_mats = WORLD_MATERIALS[world]

	var layout: Array = (LAYOUTS[(k + world_i * 3) % LAYOUTS.size()] as Array).duplicate()
	if world == "volcano":
		for i in layout.size():
			if layout[i] == "hut":
				layout[i] = "dynhouse"
	var boss_scene := ""
	if n == 44 or n == 60:
		boss_scene = BOSS_FINAL_SCENE
	elif n == 52:
		boss_scene = BOSS_SPACE_SCENE
	if boss_scene != "":
		layout = ["keep"]

	if k == 0:
		_hint(root, WORLD_HINTS[world])
	elif n == 44:
		_hint(root, ["PÄÄPOMO: Apinakuningas on palannut tulivuoreen!", "Käytä dynamiittia ja räjähtäviä ammuksia."])
	elif n == 52:
		_hint(root, ["PÄÄPOMO: Avaruusapina laskeutui eksoplaneetalle!", "Painovoimakentät auttavat osumaan."])
	elif n == 60:
		_hint(root, ["LOPPUTAISTELU: Tulipomo taivaansaarilla!", "Viimeinen kenttä – näytä mihin pystyt!"])

	if world == "sky":
		_compose_sky(root, layout, boss_scene)
	else:
		var gap := 0.7
		var total := 0.0
		for arch in layout:
			total += float(WIDTHS[arch])
		total += gap * float(layout.size() - 1)
		var right := 9.2 if boss_scene != "" else 14.3
		var x := 2.3 + maxf(right - 2.3 - total, 0.0) * _rng.randf()
		for arch in layout:
			_arch(root, arch, x, g)
			x += float(WIDTHS[arch]) + gap
		if boss_scene != "":
			_boss(root, boss_scene, 11.8, g)
			_dyn(root, 14.0, g)

	if world == "exo":
		var blue := Color(0.35, 0.6, 1.0)
		var red := Color(1.0, 0.35, 0.3)
		_well(root, _rng.randf_range(-1.0, 2.0), _rng.randf_range(5.0, 6.5), 9.0, 6.5, 1.3, blue)
		if _difficulty > 0.6 or boss_scene != "":
			_well(root, _rng.randf_range(5.5, 8.0), _rng.randf_range(7.5, 8.5), -8.0, 4.5, 1.0, red)

	return _ammo_for(boss_scene != "")


func _ammo_for(boss: bool) -> String:
	var enemies := int(_counts.get("Enemy", 0))
	var blocks := int(_counts.get("wood", 0)) + int(_counts.get("stone", 0)) + int(_counts.get("ice", 0))
	var normal := enemies + 1 + (1 if int(_counts.get("stone", 0)) >= 4 else 0)
	var explode := 1 + blocks / 10 + (3 if boss else 0)
	while normal + explode > 9:
		if normal > enemies:
			normal -= 1
		else:
			explode -= 1
	return "n".repeat(normal) + "e".repeat(explode)


## Taivaansaaret: jokainen rakennelma omalla leijuvalla saarellaan.
func _compose_sky(root: Node, layout: Array, boss_scene: String) -> void:
	if boss_scene != "":
		_pf(root, 4.2, 2.6, 4.2)
		_arch(root, "keep", 4.2 - 1.65, 2.6)
		_pf(root, 11.6, GY, 6.4)
		_boss(root, boss_scene, 11.9, GY)
		_dyn(root, 14.0, GY)
		return
	var gap := 1.2
	var total := 0.0
	for arch in layout:
		total += float(WIDTHS[arch]) + 0.8
	total += gap * float(layout.size() - 1)
	var x := 1.6 + maxf(14.6 - 1.6 - total, 0.0) * _rng.randf()
	var tops := [GY, 1.6, 2.8, 4.0]
	for arch in layout:
		var w := float(WIDTHS[arch]) + 0.8
		var top: float = tops[_rng.randi() % tops.size()]
		_pf(root, x + w * 0.5, top, w)
		_arch(root, arch, x + 0.4, top)
		x += w + gap


## Yksi rakennelma, jonka vasen reuna on `x0` ja pohja `base`.
func _arch(root: Node, arch: String, x0: float, base: float) -> void:
	match arch:
		"hut":
			var cx := x0 + 1.45
			var top := _floor(root, _pick(), cx, base, 1.7, 2.0)
			_e(root, cx, base, _maybe_armored())
			if _rng.randf() < 0.5:
				_b(root, "ice", cx, top + 0.5, 1.0, 1.0)
		"dynhouse":
			var cx := x0 + 1.45
			var top := _floor(root, _pick(), cx, base, 1.7, 2.0)
			_dyn(root, cx, base)
			_e(root, cx, top, _maybe_armored())
		"tower", "tower3":
			var cx := x0 + 1.55
			var floors := 3 if arch == "tower3" or (_difficulty > 0.45 and _rng.randf() < 0.6) else 2
			var spans := [2.2, 1.8, 1.4]
			var heights := [1.8, 1.5, 1.2]
			var y := base
			for f in floors:
				y = _floor(root, _pick(), cx, y, heights[f], spans[f])
			_e(root, cx, y, _maybe_armored())
			if arch == "tower3" or _rng.randf() < 0.5:
				_e(root, cx, base)
		"fort":
			var type := _pick()
			for px in [x0 + 0.25, x0 + 3.05, x0 + 5.85]:
				_b(root, type, px, base + 0.85, 0.5, 1.7)
			var roof := base + 1.7 + 0.25
			_b(root, _pick(), x0 + 1.65, roof, 2.8, 0.5)
			_b(root, _pick(), x0 + 4.45, roof, 2.8, 0.5)
			_b(root, "ice", x0 + (1.65 if _rng.randf() < 0.5 else 4.45), roof + 0.75, 1.0, 1.0)
			_e(root, x0 + 1.65, base, _maybe_armored())
			_e(root, x0 + 4.45, base)
		"pyramid":
			var type := _pick()
			for i in 3:
				_b(root, type, x0 + 0.5 + float(i), base + 0.5, 1.0, 1.0)
			for i in 2:
				_b(root, type, x0 + 1.0 + float(i), base + 1.5, 1.0, 1.0)
			_b(root, type, x0 + 1.5, base + 2.5, 1.0, 1.0)
			_e(root, x0 + 1.5, base + 3.0, _maybe_armored())
		"keep":
			var cx := x0 + 1.65
			var t1 := _floor(root, "stone", cx, base, 1.6, 2.4)
			var t2 := _floor(root, _pick(), cx, t1, 1.4, 1.8)
			_e(root, cx, base, _maybe_armored())
			if _rng.randf() < 0.65:
				_e(root, cx, t2)
			else:
				_b(root, "ice", cx, t2 + 0.5, 1.0, 1.0)
		"wall":
			var type := _pick()
			for i in (3 if _rng.randf() < 0.5 else 2):
				_b(root, type, x0 + 0.5, base + 0.5 + float(i), 1.0, 1.0)
			_e(root, x0 + 1.85, base, _maybe_armored())
		"bridge":
			var type := _pick()
			for i in 2:
				_b(root, type, x0 + 0.5, base + 0.5 + float(i), 1.0, 1.0)
				_b(root, type, x0 + 4.1, base + 0.5 + float(i), 1.0, 1.0)
			_b(root, _pick(), x0 + 2.3, base + 2.25, 4.6, 0.5)
			_e(root, x0 + 2.3, base)
			if _rng.randf() < 0.6:
				_e(root, x0 + 2.3, base + 2.5, _maybe_armored())


# --- Scenes made by the generator -----------------------------------------------------

func _save_scene(root: Node, path: String) -> int:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	return err


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	return mesh


func _cone(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


func _make_well_scene() -> int:
	var well := Node3D.new()
	well.name = "GravityWell"
	well.set_script(load(WELL_SCRIPT))
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	planet.mesh = _sphere(0.5)
	planet.scale = Vector3.ONE * 2.4
	well.add_child(planet)
	planet.owner = well
	var field := MeshInstance3D.new()
	field.name = "Field"
	field.mesh = _sphere(0.5)
	field.scale = Vector3.ONE * 14.0
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	well.add_child(field)
	field.owner = well
	return _save_scene(well, WELL_SCENE)


## Adds a colored mesh under the boss "Visual" node.
func _part(boss: Node, mesh: Mesh, node_name: String, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var visual := boss.get_node("Visual")
	var part := MeshInstance3D.new()
	part.name = node_name
	part.mesh = mesh
	part.position = pos
	part.rotation_degrees = rot
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	part.material_override = material
	visual.add_child(part)
	part.owner = boss


func _boss_collider(boss: Node, node_name: String, shape: Shape3D, pos: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.name = node_name
	collider.shape = shape
	collider.position = pos
	boss.add_child(collider)
	collider.owner = boss


func _boss_base(node_name: String, mass_value: float, hp: int, pts: int, label_y: float) -> RigidBody3D:
	var boss := RigidBody3D.new()
	boss.name = node_name
	boss.mass = mass_value
	boss.set_script(load(BOSS_SCRIPT))
	boss.set("max_health", hp)
	boss.set("points", pts)
	boss.set("smoke_size", 2.2)
	boss.set("popup_offset", Vector3(0.0, 3.0, 0.0))
	var physics := PhysicsMaterial.new()
	physics.friction = 0.9
	physics.bounce = 0.05
	boss.physics_material_override = physics
	var visual := Node3D.new()
	visual.name = "Visual"
	boss.add_child(visual)
	visual.owner = boss
	var label := Label3D.new()
	label.name = "HealthLabel"
	label.text = "HP %d/%d" % [hp, hp]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.01
	label.outline_size = 16
	label.no_depth_test = true
	label.position = Vector3(0.0, label_y, 0.0)
	boss.add_child(label)
	label.owner = boss
	return boss


func _sphere_shape(radius: float) -> SphereShape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return shape


func _box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


func _make_boss_scenes() -> int:
	var white := Color(0.95, 0.97, 1.0)
	var black := Color(0.05, 0.05, 0.07)

	# Snow giant: placeholder snowman facing left (-X, towards the slingshot).
	var snow := _boss_base("BossSnow", 6.0, 6, 5000, 4.7)
	_boss_collider(snow, "CollisionShape3D", _sphere_shape(1.2), Vector3(0.0, 1.2, 0.0))
	_boss_collider(snow, "CollisionHead", _sphere_shape(0.8), Vector3(0.0, 2.9, 0.0))
	_part(snow, _sphere(1.2), "Body", Vector3(0.0, 1.2, 0.0), white)
	_part(snow, _sphere(0.8), "Head", Vector3(0.0, 2.9, 0.0), white)
	_part(snow, _sphere(0.1), "EyeA", Vector3(-0.7, 3.05, 0.35), black)
	_part(snow, _sphere(0.1), "EyeB", Vector3(-0.7, 3.05, -0.35), black)
	_part(snow, _cone(0.15, 0.7), "Nose", Vector3(-0.95, 2.85, 0.0), Color(1.0, 0.5, 0.1), Vector3(0.0, 0.0, 90.0))
	var hat := CylinderMesh.new()
	hat.top_radius = 0.55
	hat.bottom_radius = 0.55
	hat.height = 0.6
	_part(snow, hat, "Hat", Vector3(0.0, 3.85, 0.0), Color(0.15, 0.2, 0.4))
	for i in 3:
		_part(snow, _sphere(0.1), "Button%d" % i, Vector3(-1.15, 0.8 + 0.4 * float(i), 0.0), black)
	var err := _save_scene(snow, BOSS_SNOW_SCENE)

	# Space alien: placeholder purple cube creature.
	var space := _boss_base("BossSpace", 8.0, 8, 7500, 3.9)
	_boss_collider(space, "CollisionShape3D", _box_shape(Vector3(2.4, 2.2, 1.6)), Vector3(0.0, 1.1, 0.0))
	var body := BoxMesh.new()
	body.size = Vector3(2.4, 2.2, 1.6)
	_part(space, body, "Body", Vector3(0.0, 1.1, 0.0), Color(0.5, 0.25, 0.75))
	for i in 3:
		var z := -0.5 + 0.5 * float(i)
		_part(space, _sphere(0.22), "Eye%d" % i, Vector3(-1.2, 1.5, z), Color.WHITE)
		_part(space, _sphere(0.1), "Pupil%d" % i, Vector3(-1.38, 1.5, z), black)
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.06
	antenna.bottom_radius = 0.06
	antenna.height = 0.9
	_part(space, antenna, "AntennaA", Vector3(0.0, 2.65, 0.5), Color(0.4, 0.2, 0.6), Vector3(15.0, 0.0, 0.0))
	_part(space, antenna, "AntennaB", Vector3(0.0, 2.65, -0.5), Color(0.4, 0.2, 0.6), Vector3(-15.0, 0.0, 0.0))
	_part(space, _sphere(0.16), "TipA", Vector3(0.0, 3.1, 0.62), Color(0.4, 1.0, 0.5))
	_part(space, _sphere(0.16), "TipB", Vector3(0.0, 3.1, -0.62), Color(0.4, 1.0, 0.5))
	err = maxi(err, _save_scene(space, BOSS_SPACE_SCENE))

	# Final boss: placeholder red horned sphere.
	var final_boss := _boss_base("BossFinal", 10.0, 12, 15000, 4.6)
	_boss_collider(final_boss, "CollisionShape3D", _sphere_shape(1.6), Vector3(0.0, 1.6, 0.0))
	_part(final_boss, _sphere(1.6), "Body", Vector3(0.0, 1.6, 0.0), Color(0.8, 0.1, 0.1))
	_part(final_boss, _cone(0.3, 1.1), "HornA", Vector3(-0.3, 3.3, 0.8), Color(0.15, 0.05, 0.05), Vector3(20.0, 0.0, 0.0))
	_part(final_boss, _cone(0.3, 1.1), "HornB", Vector3(-0.3, 3.3, -0.8), Color(0.15, 0.05, 0.05), Vector3(-20.0, 0.0, 0.0))
	_part(final_boss, _sphere(0.28), "EyeA", Vector3(-1.4, 2.0, 0.55), Color(1.0, 0.9, 0.2))
	_part(final_boss, _sphere(0.28), "EyeB", Vector3(-1.4, 2.0, -0.55), Color(1.0, 0.9, 0.2))
	_part(final_boss, _sphere(0.12), "PupilA", Vector3(-1.62, 2.0, 0.55), black)
	_part(final_boss, _sphere(0.12), "PupilB", Vector3(-1.62, 2.0, -0.55), black)
	var mouth := BoxMesh.new()
	mouth.size = Vector3(0.12, 0.3, 1.0)
	_part(final_boss, mouth, "Mouth", Vector3(-1.56, 1.1, 0.0), black)
	err = maxi(err, _save_scene(final_boss, BOSS_FINAL_SCENE))
	return err

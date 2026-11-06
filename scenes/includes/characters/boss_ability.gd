extends Node
## Pomon erikoiskyky (pelin verkkosivun mukaan). Laita pomon lapseksi nimellä "Ability".
##   rock     NIITTYJÄTTI       Kivenheitto: heittää kiviä ritsan ja linnan väliin (esteitä)
##   frost    JÄÄAPINA          Jääpuhuri: hidastaa lähelle lentävän banaanin kerran
##   sand     AAVIKON KUNINGAS  Hiekkamyrsky: vastatuulipuuskat + kaivautuu ja nousee toisaalla
##   glue     KARKKIHIRVIÖ      Karkkiliima: korjaa vaurioituneet palikat ja liimaa rikotut takaisin
##   lava     TULIVUOREN HERRA  Laavapommit: räjähtävät maahan linnan edessä
##   gravity  APINAKUNINGAS     Painovoimamyrsky: painovoimakentät kiertävät ja vaihtavat suuntaa

const SpeechBubble := preload("res://scenes/ui/speech_bubble.gd")
const GridWall := preload("res://scenes/visual/grid_wall.gd")
const Explosion := preload("res://scenes/includes/explosion.gd")
const Vfx := preload("res://scenes/visual/vfx.gd")

##   orbit    AVARUUSAPINA      Kiertävä kuu torjuu banaaneja
##   wave     MERIROSVOAPINA    Hyökyaalto pyyhkii maassa makaavat banaanit pois
##   shield   KRISTALLIAPINA    Kristallikilpi: ajoittain osumat eivät vahingoita
##   holo     MUUKALAISAPINA    Hologrammit: harhakuvat ottavat osumat vastaan
##   tornado  MYRSKYAPINA       Pyörremyrsky kulkee kentän poikki ja nostaa banaaneja
@export_enum("rock", "frost", "sand", "glue", "lava", "gravity", "orbit", "wave", "shield", "holo", "tornado") var kind: String = "rock"
## Sekunteja kykyjen välillä (satunnainen väliltä).
@export var interval: Vector2 = Vector2(4.5, 6.5)
## Ensimmäinen käyttö vasta tämän jälkeen (kenttä ehtii asettua).
@export var first_delay: float = 4.0
@export var color: Color = Color(1, 1, 1)

const LINES := {
	"rock": ["Kivi tulee!", "Väistä tätä!", "Hah, este!"],
	"frost": ["Jäädy!", "Brrr!", "Kylmää kyytiä!"],
	"sand": ["Hiekkamyrsky!", "Etsi minut!", "Tuuli on puolellani!"],
	"glue": ["Liimaa!", "Korjataan!", "Sokerilla kasaan!"],
	"lava": ["Laavaa!", "Kuumaa tavaraa!", "Pam!"],
	"gravity": ["Polvistu!", "Painovoima on minun!", "Kaikki pyörii!"],
	"orbit": ["Kuu suojaa minua!", "Kiertoradalla!", "Ohi meni!"],
	"wave": ["Hyökyaalto!", "Arrr!", "Meri vie!"],
	"shield": ["Kristallikilpi!", "Et läpäise tätä!", "Kimallus!"],
	"holo": ["Kumpi olen minä?", "Hihii, väärä!", "Hologrammi!"],
	"tornado": ["Pyörremyrsky!", "Tuuli nousee!", "Wuuush!"],
}

var _boss: RigidBody3D = null
var _rng := RandomNumberGenerator.new()
var _wait: float = 0.0
var _time: float = 0.0
# Hiekkamyrsky
var _gust_left: float = 0.0
var _gust_dir: Vector3 = Vector3.LEFT
var _spots: Array[float] = []
# Karkkiliima
var _templates: Array = []
var _rebuilds_left: int = 4
# Painovoima
var _wells: Array = []
var _well_home: Array = []


func _ready() -> void:
	_boss = get_parent() as RigidBody3D
	_rng.randomize()
	_wait = first_delay
	if kind == "glue":
		_remember_blocks.call_deferred()
	if kind == "gravity":
		_find_wells.call_deferred()
	if kind == "sand" and _boss != null:
		var x := _boss.position.x
		_spots = [x, x - 1.7, x + 1.0]


func _alive() -> bool:
	return is_instance_valid(_boss) and bool(_boss.get("_alive"))


func _physics_process(delta: float) -> void:
	if not _alive():
		return
	_time += delta
	match kind:
		"frost":
			_frost_check()
		"sand":
			_apply_gust(delta)
		"gravity":
			_orbit_wells(delta)
		"orbit":
			_update_moon(delta)
		"shield":
			_update_shield(delta)
		"tornado":
			_update_tornado(delta)
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _rng.randf_range(interval.x, interval.y)
	match kind:
		"rock":
			_throw(false)
		"lava":
			_throw(true)
		"sand":
			_start_gust()
			if _rng.randf() < 0.6:
				_burrow()
		"glue":
			_glue()
		"gravity":
			_flip_wells()


func _say(chance: float = 0.5) -> void:
	if _rng.randf() > chance:
		return
	var lines: Array = LINES.get(kind, [])
	if not lines.is_empty():
		SpeechBubble.say(_boss, lines[_rng.randi() % lines.size()], 1.4, float(_boss.get("popup_offset").y), "")


func _sound(event: String, volume: float = 0.0, pitch: float = 1.0) -> void:
	var sounds := get_node_or_null("/root/SoundManager")
	if sounds != null:
		sounds.call("play", event, volume, 0.08, 0.1, pitch)


func _world() -> Node:
	var w := get_tree().current_scene
	return w if w != null else _boss.get_parent()


# --- Kivi / laavapommi ------------------------------------------------------------

## Heittää kiven tai laavapommin ballistisesti ritsan ja linnan väliin.
func _throw(lava: bool) -> void:
	var start := _boss.global_position + Vector3(-0.8, 3.0, 0.0)
	var target := Vector3(_rng.randf_range(-4.0, 2.5), 0.6, 0.0)
	var flight := _rng.randf_range(1.1, 1.5)
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var v := Vector3((target.x - start.x) / flight, (target.y - start.y) / flight + 0.5 * g * flight, 0.0)

	var body := RigidBody3D.new()
	body.name = "LavaBomb" if lava else "Boulder"
	body.mass = 3.0 if not lava else 1.0
	body.axis_lock_linear_z = true
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 2
	body.add_to_group("boss_projectiles")
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55 if not lava else 0.4
	shape.shape = sphere
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = sphere.radius
	sm.height = sphere.radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	if lava:
		mat.albedo_color = Color("3a1a12")
		mat.emission_enabled = true
		mat.emission = Color("ff6a1a")
		mat.emission_energy_multiplier = 2.2
	else:
		mat.albedo_color = Color("8a8f99")
		mat.roughness = 1.0
	mesh.material_override = mat
	body.add_child(mesh)
	_world().add_child(body)
	# Pomon omat ammukset eivät osu pomoon itseensä.
	body.add_collision_exception_with(_boss)
	_boss.add_collision_exception_with(body)
	body.global_position = start
	body.linear_velocity = v
	body.angular_velocity = Vector3(0, 0, _rng.randf_range(-6.0, 6.0))
	if lava:
		body.body_entered.connect(_lava_hit.bind(body))
	else:
		# Kivi jää esteeksi hetkeksi ja häviää sitten.
		get_tree().create_timer(7.0, false).timeout.connect(func() -> void:
			if is_instance_valid(body):
				var t := body.create_tween()
				t.tween_property(mesh, "scale", Vector3.ONE * 0.01, 0.3)
				t.tween_callback(body.queue_free))
	_say(0.35)
	_sound("launch", -4.0, 0.6)
	_call_wobble("jump", [0.6, false])


func _lava_hit(_other: Node, bomb: RigidBody3D) -> void:
	if not is_instance_valid(bomb) or bomb.is_queued_for_deletion():
		return
	var at := bomb.global_position
	bomb.queue_free()
	var fx := Explosion.new()
	fx.size = 0.7
	_world().add_child(fx)
	fx.global_position = at
	GridWall.splash(get_tree(), at, 0.9, Color("ff6a1a"))
	# Työntää lähellä lepääviä banaaneja ja palikoita.
	for node in get_tree().get_nodes_in_group("bananas"):
		var b := node as RigidBody3D
		if b != null and not b.freeze and b.global_position.distance_to(at) < 2.5:
			b.apply_central_impulse((b.global_position - at).normalized() * 6.0 * b.mass + Vector3.UP * 3.0 * b.mass)


# --- Jääpuhuri ---------------------------------------------------------------------

func _frost_check() -> void:
	for node in get_tree().get_nodes_in_group("bananas"):
		var b := node as RigidBody3D
		if b == null or b.freeze or b.has_meta("frosted"):
			continue
		var d := b.global_position.distance_to(_boss.global_position)
		if d < 7.5 and b.linear_velocity.length() > 4.0:
			b.set_meta("frosted", true)
			b.linear_velocity *= 0.45
			Vfx.feather_puff(_world(), b.global_position)
			GridWall.splash(get_tree(), b.global_position, 0.8, Color("9be9ff"))
			_sound("hit_ice", 0.0, 1.2)
			_say(0.6)


# --- Hiekkamyrsky ja kaivautuminen ----------------------------------------------

func _start_gust() -> void:
	_gust_left = 2.4
	_gust_dir = Vector3(-1.0, _rng.randf_range(-0.3, 0.6), 0.0).normalized()
	GridWall.splash(get_tree(), _boss.global_position + Vector3(-6, 2, 0), 1.2, Color("ffc45e"))
	_sound("launch", -2.0, 0.5)
	_say(0.4)


func _apply_gust(delta: float) -> void:
	if _gust_left <= 0.0:
		return
	_gust_left -= delta
	for node in get_tree().get_nodes_in_group("bananas"):
		var b := node as RigidBody3D
		if b != null and not b.freeze:
			b.linear_velocity += _gust_dir * 7.0 * delta


func _burrow() -> void:
	if _spots.is_empty():
		return
	var visual := _boss.get_node_or_null("Visual") as Node3D
	var target_x: float = _spots[_rng.randi() % _spots.size()]
	if absf(target_x - _boss.position.x) < 0.5:
		return
	_boss.set("_self_jump_left", 2.0)
	Vfx.block_break(_world(), _boss.global_position, "wood", Vector3(2, 1, 1))
	var t := _boss.create_tween()
	if visual != null:
		t.tween_property(visual, "position:y", -3.5, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		if not _alive():
			return
		var p := _boss.position
		p.x = target_x
		_boss.position = p
		_boss.set("_home_x", _boss.global_position.x)
		_boss.linear_velocity = Vector3.ZERO
		_boss.set("_self_jump_left", 1.5))
	if visual != null:
		t.tween_property(visual, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		if _alive():
			Vfx.block_break(_world(), _boss.global_position, "wood", Vector3(2, 1, 1)))


# --- Karkkiliima ------------------------------------------------------------------

func _remember_blocks() -> void:
	if _boss == null:
		return
	for node in get_tree().get_nodes_in_group("destructibles"):
		var block := node as RigidBody3D
		if block == null or block.global_position.distance_to(_boss.global_position) > 14.0:
			continue
		_templates.append({"node": block, "copy": block.duplicate(), "xf": block.global_transform, "parent": block.get_parent()})


func _glue() -> void:
	var fixed := 0
	for entry in _templates:
		var block = entry["node"]
		if is_instance_valid(block) and not block.is_queued_for_deletion() and not bool(block.get("_broken")):
			if float(block.get("health")) < float(block.get("max_health")):
				block.set("health", block.get("max_health"))
				if block.has_method("_show_damage"):
					block.call("_show_damage")
				fixed += 1
		elif _rebuilds_left > 0 and is_instance_valid(entry["parent"]):
			# Palikka hajosi: liimataan uusi samaan kohtaan.
			var copy: Node3D = (entry["copy"] as Node3D).duplicate()
			entry["parent"].add_child(copy)
			copy.global_transform = entry["xf"]
			copy.scale = Vector3.ONE * 0.2
			copy.create_tween().tween_property(copy, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			entry["node"] = copy
			GridWall.splash(get_tree(), copy.global_position, 0.6, Color("ff8adf"))
			_rebuilds_left -= 1
			fixed += 1
			if _rebuilds_left <= 0:
				break
	if fixed > 0:
		Vfx.star_burst(_world(), _boss.global_position + Vector3(0, 2, 0), 10)
		_sound("ability_splitter", -4.0, 1.3)
		_say(0.7)


# --- Painovoimamyrsky ------------------------------------------------------------

func _find_wells() -> void:
	for w in get_tree().get_nodes_in_group("gravity_wells"):
		if w is Node3D:
			_wells.append(w)
			_well_home.append((w as Node3D).global_position)


func _orbit_wells(delta: float) -> void:
	for i in _wells.size():
		var w := _wells[i] as Node3D
		if not is_instance_valid(w):
			continue
		var home: Vector3 = _well_home[i]
		var a := _time * 0.6 + float(i) * PI
		w.global_position = home + Vector3(cos(a) * 1.8, sin(a) * 1.2, 0.0)


func _flip_wells() -> void:
	for w in _wells:
		if is_instance_valid(w) and "strength" in w:
			w.set("strength", -float(w.get("strength")))
			GridWall.splash(get_tree(), (w as Node3D).global_position, 1.0, Color("ffd64a"))
	_sound("boss_laugh", -3.0, 1.0)
	_say(0.6)


func _call_wobble(method: String, args: Array) -> void:
	var wobble := _boss.get_node_or_null("Visual/Wobble")
	if wobble != null and wobble.has_method(method):
		wobble.callv(method, args)

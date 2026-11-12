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
@export_enum("rock", "frost", "sand", "glue", "lava", "gravity", "orbit", "wave", "shield", "holo", "tornado", "crane", "guards", "balloon") var kind: String = "rock"
##   crane    RAKENNUSAPINA     Torninosturi pudottaa teräspalkkeja linnan suojaksi
##   guards   RITARIAPINA       Kutsuu enintään kaksi vartija-apinaa (nekin pitää kaataa)
##   balloon  TAITEILIJA-APINA  Nousee ilmapalloilla ylös ja leijuu hetken
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
	"crane": ["Nosturi, laske!", "Lisää palkkeja!", "Rakennetaan!"],
	"guards": ["Vartijat, apuun!", "Puolustakaa linnaa!", "Hyökkäykseen!"],
	"balloon": ["Au revoir!", "Ooh là là!", "Taide lentää!"],
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
		"orbit":
			_moon_speed = -_moon_speed
			_say(0.4)
		"wave":
			_wave()
		"shield":
			_shield_left = 2.6
			_say(0.6)
		"holo":
			_spawn_holograms()
		"tornado":
			_start_tornado()
		"crane":
			_drop_beam()
		"guards":
			_summon_guard()
		"balloon":
			_balloon_up()


# --- Torninosturi -----------------------------------------------------------------

var _beams_left: int = 4


func _drop_beam() -> void:
	if _beams_left <= 0:
		return
	_beams_left -= 1
	var block_scene := load("res://scenes/includes/blocks/block.tscn") as PackedScene
	if block_scene == null:
		return
	var beam := block_scene.instantiate() as RigidBody3D
	var mesh := beam.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var shape := beam.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var size := Vector3(2.4, 0.4, 1.2)
	if mesh != null:
		var bm := BoxMesh.new()
		bm.size = size
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("d84a2a")
		m.roughness = 0.5
		m.metallic = 0.4
		bm.material = m
		mesh.mesh = bm
	if shape != null:
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
	beam.name = "SteelBeam"
	beam.set("max_health", 30.0)
	beam.set("start_asleep", false)
	beam.mass = 2.0
	_boss.get_parent().add_child(beam)
	beam.global_position = Vector3(_rng.randf_range(4.0, 9.0), 14.0, 0.0)
	_sound("launch", -4.0, 0.5)
	_say(0.5)


# --- Vartijat ---------------------------------------------------------------------

var _guards_left: int = 2


func _summon_guard() -> void:
	if _guards_left <= 0:
		return
	_guards_left -= 1
	var enemy_scene := load("res://scenes/includes/characters/enemy_plain.tscn") as PackedScene
	if enemy_scene == null:
		return
	var guard := enemy_scene.instantiate() as Node3D
	guard.name = "Guard"
	# Laskeutuminen ei saa tappaa vartijaa (muuten pelaaja saisi ilmaiset pisteet).
	guard.set("grace_time", 2.5)
	_boss.get_parent().add_child(guard)
	guard.global_position = _boss.global_position + Vector3(-2.2, 1.4, 0.0)
	Vfx.star_burst(_world(), guard.global_position, 10)
	GridWall.splash(get_tree(), guard.global_position, 0.8, Color("e83a3a"))
	_sound("level_start", -6.0, 1.2)
	_say(0.8)


# --- Ilmapallot -------------------------------------------------------------------

var _balloons: Node3D = null


func _balloon_up() -> void:
	if _balloons != null:
		return
	_balloons = Node3D.new()
	_balloons.name = "Balloons"
	var colors := [Color("ff4a8a"), Color("4ac8ff"), Color("ffd64a")]
	for i in 3:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.4
		b.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.roughness = 0.25
		b.material_override = mat
		b.position = Vector3((float(i) - 1.0) * 0.9, 6.5 + absf(float(i) - 1.0) * -0.4, 0.0)
		_balloons.add_child(b)
	_boss.add_child(_balloons)
	_boss.set("_self_jump_left", 6.0)
	var start := _boss.global_position
	_boss.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_boss.freeze = true
	var t := _boss.create_tween()
	t.tween_property(_boss, "global_position", start + Vector3(0.0, 3.2, 0.0), 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_interval(2.6)
	t.tween_property(_boss, "global_position", start, 0.9).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void:
		if is_instance_valid(_balloons):
			_balloons.queue_free()
		_balloons = null
		if is_instance_valid(_boss):
			_boss.freeze = false
			_boss.set("_self_jump_left", 0.5))
	_say(0.7)


# --- Kiertävä kuu ---------------------------------------------------------------

var _moon: AnimatableBody3D = null
var _moon_angle: float = 0.0
var _moon_speed: float = 1.6


func _update_moon(delta: float) -> void:
	if _moon == null:
		_moon = AnimatableBody3D.new()
		_moon.name = "BossMoon"
		_moon.sync_to_physics = false
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.8
		shape.shape = sphere
		_moon.add_child(shape)
		var mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.8
		sm.height = 1.6
		mesh.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("e8e0f8")
		mat.emission_enabled = true
		mat.emission = Color("ffe9a0")
		mat.emission_energy_multiplier = 1.2
		mesh.material_override = mat
		_moon.add_child(mesh)
		_boss.get_parent().add_child(_moon)
		_moon.add_collision_exception_with(_boss)
		_boss.add_collision_exception_with(_moon)
	_moon_angle += _moon_speed * delta
	var center := _boss.global_position + Vector3(0.0, 2.2, 0.0)
	_moon.global_position = center + Vector3(cos(_moon_angle) * 3.4, sin(_moon_angle) * 2.6, 0.0)


func _exit_tree() -> void:
	if is_instance_valid(_moon):
		_moon.queue_free()


# --- Hyökyaalto -------------------------------------------------------------------

func _wave() -> void:
	var moved := 0
	for node in get_tree().get_nodes_in_group("bananas"):
		var b := node as RigidBody3D
		if b == null or b.freeze or b.global_position.y > 2.5:
			continue
		b.linear_velocity = Vector3(-9.0, 3.0, 0.0)
		moved += 1
	for i in 5:
		GridWall.splash(get_tree(), Vector3(12.0 - float(i) * 5.0, 0.8, 0.0), 0.7, Color("4fc6ff"))
	Vfx.feather_puff(_world(), _boss.global_position + Vector3(-2.0, 0.5, 0.0))
	_sound("launch", 0.0, 0.45)
	_say(0.6)


# --- Kristallikilpi ---------------------------------------------------------------

var _shield_left: float = 0.0
var _shield_mesh: MeshInstance3D = null


func _update_shield(delta: float) -> void:
	_shield_left = maxf(_shield_left - delta, 0.0)
	var on := _shield_left > 0.0
	_boss.set("shielded", on)
	if _shield_mesh == null:
		_shield_mesh = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.6
		sm.height = 5.2
		sm.radial_segments = 6
		sm.rings = 3
		_shield_mesh.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.5, 1.0, 0.28)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.45, 1.0)
		mat.emission_energy_multiplier = 1.2
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shield_mesh.material_override = mat
		_shield_mesh.position = Vector3(0.0, 2.0, 0.0)
		_boss.add_child(_shield_mesh)
	_shield_mesh.visible = on
	if on:
		_shield_mesh.rotation.y += delta * 1.5


# --- Hologrammit ------------------------------------------------------------------

func _spawn_holograms() -> void:
	var model := _boss.get_node_or_null("Visual/Wobble") as Node3D
	if model == null or get_tree().get_nodes_in_group("holograms").size() > 0:
		return
	for i in 2:
		var holo := StaticBody3D.new()
		holo.name = "Hologram"
		holo.add_to_group("holograms")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.4, 2.8, 1.5)
		shape.shape = box
		shape.position.y = 1.4
		holo.add_child(shape)
		var copy := model.duplicate(0) as Node3D
		copy.set_script(null)
		holo.add_child(copy)
		for node in copy.find_children("*", "MeshInstance3D", true, false):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 1.0, 0.6, 0.35)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = Color(0.3, 1.0, 0.5)
			mat.emission_energy_multiplier = 0.8
			(node as MeshInstance3D).material_override = mat
		_boss.get_parent().add_child(holo)
		# Leijuvat pomon yläpuolella vasemmalla ja oikealla, eivät linnan päällä.
		var x := _boss.global_position.x + (-1.6 if i == 0 else 1.4)
		holo.global_position = Vector3(x, _boss.global_position.y + 3.6 + float(i) * 0.6, 0.0)
		holo.scale = Vector3.ONE * 0.55
		# Hologrammi puhkeaa, kun banaani osuu siihen, tai häviää itsestään.
		var area := Area3D.new()
		var ashape := CollisionShape3D.new()
		ashape.shape = box
		ashape.position.y = 1.4
		area.add_child(ashape)
		holo.add_child(area)
		area.body_entered.connect(func(body: Node) -> void:
			if body.is_in_group("bananas") and is_instance_valid(holo):
				GridWall.splash(get_tree(), holo.global_position, 0.8, Color("6aff8a"))
				Vfx.star_burst(_world(), holo.global_position + Vector3(0, 1.4, 0), 8)
				holo.queue_free())
		get_tree().create_timer(5.5, false).timeout.connect(func() -> void:
			if is_instance_valid(holo):
				holo.queue_free())
	_sound("ability_splitter", -4.0, 0.8)
	_say(0.6)


# --- Pyörremyrsky -----------------------------------------------------------------

var _tornado: Node3D = null
var _tornado_left: float = 0.0


func _start_tornado() -> void:
	if _tornado == null:
		_tornado = Node3D.new()
		_tornado.name = "Tornado"
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for i in 5:
			var ring := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5 + float(i) * 0.35
			cyl.bottom_radius = 0.35 + float(i) * 0.35
			cyl.height = 1.4
			cyl.cap_top = false
			cyl.cap_bottom = false
			ring.mesh = cyl
			ring.material_override = mat
			ring.position.y = 0.7 + float(i) * 1.4
			_tornado.add_child(ring)
		_boss.get_parent().add_child(_tornado)
	_tornado.visible = true
	_tornado.global_position = Vector3(_boss.global_position.x - 2.0, 0.0, 0.0)
	_tornado_left = 4.0
	_say(0.6)
	_sound("launch", -2.0, 0.4)


func _update_tornado(delta: float) -> void:
	if _tornado == null or _tornado_left <= 0.0:
		if _tornado != null:
			_tornado.visible = false
		return
	_tornado_left -= delta
	_tornado.global_position.x -= 3.2 * delta
	_tornado.rotation.y += delta * 9.0
	var tx := _tornado.global_position.x
	for node in get_tree().get_nodes_in_group("bananas"):
		var b := node as RigidBody3D
		if b != null and not b.freeze and absf(b.global_position.x - tx) < 1.8 and b.global_position.y < 8.0:
			b.linear_velocity.y += 26.0 * delta
			b.linear_velocity.x *= 1.0 - 1.5 * delta
	if fmod(_tornado_left, 0.5) < delta:
		GridWall.splash(get_tree(), Vector3(tx, 2.5, 0.0), 0.5, Color("c8d8ff"))


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

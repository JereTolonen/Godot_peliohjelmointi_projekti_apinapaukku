extends MeshInstance3D
## Neonruudukko pelialueen ja taustan välissä. Normaalisti näkymätön; "roiskeet"
## (leviävät rengasaallot) tuovat sen hetkeksi näkyviin:
##   - satunnaiset välähdykset muutaman sekunnin välein
##   - osumat, palikoiden hajoaminen ja apinoiden kaatuminen (pieni roiske)
##   - räjähdykset (iso roiske)
##   - erikoiskyvyt (kyvyn oman värinen roiske)
##   - pomon laskeutumiset (shokkiaalto)
##
## visual_director.gd luo tämän jokaiseen kenttään. Muut skriptit voivat kutsua:
##   GridWall.splash(get_tree(), paikka, voimakkuus)

const SHADER := preload("res://scenes/visual/shaders/grid_wall.gdshader")
const AmmoIcon := preload("res://scenes/ui/ammo_icon.gd")
const EXPLOSION_SCRIPT := "res://scenes/includes/explosion.gd"
const MAX_RIPPLES := 16
const GROUP := &"grid_wall"

## Teeman väri.
@export var color: Color = Color(0.4, 0.9, 1.0)
## Ruudukon etäisyys pelitason takana (m).
@export var depth: float = 2.0
## Satunnaisten välähdysten väli (s).
@export var idle_interval: Vector2 = Vector2(2.0, 5.0)

var _material: ShaderMaterial = null
var _ripples: Array[Vector4] = []
var _colors: Array[Color] = []
var _next: int = 0
var _time: float = 0.0
var _idle_left: float = 1.5
var _rng := RandomNumberGenerator.new()


## Lisää roiskeen lähimpään ruudukkoon. `strength` ~0.4 (pieni) … 1.6 (iso räjähdys).
static func splash(tree: SceneTree, at: Vector3, strength: float = 0.6, tint: Variant = null) -> void:
	if tree == null:
		return
	var wall := tree.get_first_node_in_group(GROUP)
	if wall != null:
		wall.call("add_ripple", at, strength, tint)


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	# Reilusti isompi kuin mikään roiske, jottei seinän oma reuna koskaan näy.
	quad.size = Vector2(400.0, 140.0)
	mesh = quad
	position = Vector3(0.0, 20.0, -depth)
	extra_cull_margin = 64.0
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("grid_color", color)
	material_override = _material
	for i in MAX_RIPPLES:
		_ripples.append(Vector4.ZERO)
		_colors.append(Color(0, 0, 0, 1))
	_push()
	# Kuunnellaan pelin tapahtumia (kuten SoundManager): olemassa olevat + uudet solmut.
	get_tree().node_added.connect(_on_node_added)
	var level := get_parent()
	while level != null and level.name != &"CurrentLevel":
		level = level.get_parent()
	if level != null:
		for node in level.find_children("*", "", true, false):
			_on_node_added(node)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func add_ripple(at: Vector3, strength: float, tint: Variant = null) -> void:
	var c: Color = tint if tint is Color else color
	# Nopeus: isot roiskeet leviävät nopeammin.
	c.a = 5.0 + strength * 6.0
	_ripples[_next] = Vector4(at.x, at.y, _time, strength)
	_colors[_next] = c
	_next = (_next + 1) % MAX_RIPPLES
	_push()


func _process(delta: float) -> void:
	_time += delta
	_material.set_shader_parameter("now", _time)
	_idle_left -= delta
	if _idle_left <= 0.0:
		_idle_left = _rng.randf_range(idle_interval.x, idle_interval.y)
		_random_shimmer()


## Satunnainen välähdys jossain pelialueen näkyvissä kohdassa.
func _random_shimmer() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := Vector3(cam.global_position.x, cam.global_position.y - 1.0, 0.0)
	var spot := center + Vector3(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-2.0, 6.0), 0.0)
	add_ripple(spot, _rng.randf_range(0.3, 0.55))


func _push() -> void:
	_material.set_shader_parameter("ripples", _ripples)
	var cols: Array[Vector4] = []
	for c in _colors:
		cols.append(Vector4(c.r, c.g, c.b, c.a))
	_material.set_shader_parameter("ripple_colors", cols)


# --- Pelin tapahtumat ---------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node.has_signal("ability_activated") and node.has_signal("character_impact"):
		if not node.is_connected("character_impact", _on_impact):
			node.connect("character_impact", _on_impact)
			node.connect("ability_activated", _on_ability)
		return
	if node.has_signal("broken") and node.has_signal("damaged"):
		node.connect("broken", _on_broken.bind(node))
		return
	if node.has_signal("died"):
		node.connect("died", _on_died.bind(node))
		return
	var script := node.get_script() as Script
	if script != null and script.resource_path == EXPLOSION_SCRIPT:
		# Paikka asetetaan vasta add_child():n jälkeen, joten luetaan se seuraavalla ruudulla.
		_on_explosion.call_deferred(node)


func _on_impact(_instance: Node3D, pos: Vector3) -> void:
	add_ripple(pos, 0.5)


func _on_ability(kind: String, pos: Vector3) -> void:
	var tint: Color = AmmoIcon.KIND_COLORS.get(kind, color)
	add_ripple(pos, 0.9, tint)


func _on_broken(block: Node) -> void:
	if block is Node3D and is_instance_valid(block):
		add_ripple((block as Node3D).global_position, 0.6)


func _on_died(_points: int, monkey: Node) -> void:
	if monkey is Node3D and is_instance_valid(monkey):
		var strength := 1.2 if monkey.has_signal("hurt") else 0.7
		add_ripple((monkey as Node3D).global_position, strength)


func _on_explosion(fx: Node) -> void:
	if fx is Node3D and is_instance_valid(fx):
		var size := float(fx.get("size")) if "size" in fx else 1.0
		add_ripple((fx as Node3D).global_position, 1.3 * size)

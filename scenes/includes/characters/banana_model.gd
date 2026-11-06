@tool
extends Node3D
## Proseduraalinen low-poly banaani ammuksille. Mesh rakennetaan koodissa ja jaetaan
## kaikkien samanlaisten banaanien kesken (välimuisti), joten ulkoista mallia ei tarvita.
##
## Banaani makaa X/Y-tasossa (sivukuvassa näkyy kaari), varsi -X-päässä, kärki +X-päässä.
## Meshit luodaan heti (_init + setterit), jotta ritsan _visual_radius() näkee ne jo
## ennen kuin hahmo lisätään puuhun.

const SOFT := preload("res://scenes/visual/shaders/soft_toon.gdshader")

const SIDES := 6
const RINGS := 16
const STEM_PART := 0.14
const FLESH := Color("fff3c4")

## Banaanin pituus (m), mukaan lukien varsi.
@export var length: float = 1.15:
	set(v):
		length = v
		_rebuild()
## Paksuus keskeltä (säde).
@export var thickness: float = 0.2:
	set(v):
		thickness = v
		_rebuild()
## Kaaren kulma radiaaneina.
@export var curve: float = 1.15:
	set(v):
		curve = v
		_rebuild()
@export var peel_color: Color = Color("ffd23f"):
	set(v):
		peel_color = v
		_rebuild()
@export var tip_color: Color = Color("4a2c12"):
	set(v):
		tip_color = v
		_rebuild()
@export var stem_color: Color = Color("7a8a2a"):
	set(v):
		stem_color = v
		_rebuild()
## Ruskeat pilkut (ylikypsä).
@export var spots: bool = false:
	set(v):
		spots = v
		_rebuild()
## Puoliksi kuorittu: kärjessä hedelmäliha ja kuoriliuskat.
@export var peeled: bool = false:
	set(v):
		peeled = v
		_rebuild()
## 1 = yksi banaani, 3 = terttu.
@export_range(1, 3) var count: int = 1:
	set(v):
		count = clampi(v, 1, 3)
		_rebuild()
## Sytytyslanka ja kipinä varren päähän (räjähtävä banaani).
@export var fuse: bool = false:
	set(v):
		fuse = v
		_rebuild()

static var _mesh_cache: Dictionary = {}
static var _material: ShaderMaterial = null
static var _fuse_mesh: CylinderMesh = null
static var _spark_mesh: SphereMesh = null
static var _fuse_material: StandardMaterial3D = null
static var _spark_material: StandardMaterial3D = null

var _bananas: Array[MeshInstance3D] = []
var _fuse_node: MeshInstance3D = null
var _spark_node: MeshInstance3D = null
var _time: float = 0.0


func _init() -> void:
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Banana%d" % i
		_bananas.append(mi)
		add_child(mi)
	_fuse_node = MeshInstance3D.new()
	_fuse_node.name = "Fuse"
	add_child(_fuse_node)
	_spark_node = MeshInstance3D.new()
	_spark_node.name = "Spark"
	add_child(_spark_node)
	_rebuild()


func _ready() -> void:
	set_process(fuse and not Engine.is_editor_hint())


func _process(delta: float) -> void:
	_time += delta
	if _spark_node != null and _spark_node.mesh != null:
		_spark_node.scale = Vector3.ONE * (1.0 + 0.35 * sin(_time * 30.0) * sin(_time * 7.0))


func _rebuild() -> void:
	if _bananas.is_empty():
		return
	var mesh := _banana_mesh(length, thickness, curve, peel_color, tip_color, stem_color, spots, peeled)
	var material := _shared_material()
	# Terttu: banaanit viuhkana yhteisestä varresta.
	var stem_point := _stem_point()
	var angles: Array = [0.0] if count == 1 else ([-0.22, 0.22] if count == 2 else [-0.3, 0.0, 0.3])
	var depth: Array = [0.0] if count == 1 else ([-0.1, 0.1] if count == 2 else [-0.16, 0.0, 0.16])
	var s := 1.0 if count == 1 else 0.82
	for i in _bananas.size():
		var mi := _bananas[i]
		if i < count:
			mi.mesh = mesh
			mi.material_override = material
			var basis := Basis(Vector3.BACK, float(angles[i])).scaled(Vector3.ONE * s)
			var origin := stem_point - basis * stem_point + Vector3(0, 0, float(depth[i]))
			mi.transform = Transform3D(basis, origin)
		else:
			mi.mesh = null
	_build_fuse(stem_point)


func _build_fuse(stem_point: Vector3) -> void:
	if not fuse:
		_fuse_node.mesh = null
		_spark_node.mesh = null
		return
	if _fuse_mesh == null:
		_fuse_mesh = CylinderMesh.new()
		_fuse_mesh.top_radius = 0.025
		_fuse_mesh.bottom_radius = 0.035
		_fuse_mesh.height = 0.32
		_fuse_mesh.radial_segments = 6
		_fuse_mesh.rings = 1
		_fuse_material = StandardMaterial3D.new()
		_fuse_material.albedo_color = Color("3a2a1e")
		_fuse_material.roughness = 1.0
		_spark_mesh = SphereMesh.new()
		_spark_mesh.radius = 0.08
		_spark_mesh.height = 0.16
		_spark_mesh.radial_segments = 8
		_spark_mesh.rings = 4
		_spark_material = StandardMaterial3D.new()
		_spark_material.albedo_color = Color("ffd84a")
		_spark_material.emission_enabled = true
		_spark_material.emission = Color("ff9a2e")
		_spark_material.emission_energy_multiplier = 3.0
		_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var tilt := Basis(Vector3.BACK, 0.5)
	_fuse_node.mesh = _fuse_mesh
	_fuse_node.material_override = _fuse_material
	_fuse_node.transform = Transform3D(tilt, stem_point + tilt * Vector3(0, 0.16, 0))
	_spark_node.mesh = _spark_mesh
	_spark_node.material_override = _spark_material
	_spark_node.position = stem_point + tilt * Vector3(0, 0.34, 0)


## Varren pään sijainti (sama kaava kuin meshissä, u = 0).
func _stem_point() -> Vector3:
	var c := maxf(curve, 0.01)
	var r := length / c
	var sag := r * (1.0 - cos(c * 0.5))
	var theta := -c * 0.5
	return Vector3(r * sin(theta), r * (1.0 - cos(theta)) - sag * 0.5, 0.0)


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SOFT
		_material.set_shader_parameter("color", Color.WHITE)
		_material.set_shader_parameter("top_tint", Color.WHITE)
		_material.set_shader_parameter("use_vertex_color", 1.0)
	return _material


static func _banana_mesh(len: float, thick: float, arc: float, peel: Color, tip: Color, stem: Color, spotted: bool, is_peeled: bool) -> ArrayMesh:
	var key := "%.3f/%.3f/%.3f/%s/%s/%s/%s/%s" % [len, thick, arc, peel.to_html(), tip.to_html(), stem.to_html(), spotted, is_peeled]
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var c := maxf(arc, 0.01)
	var radius := len / c
	var sag := radius * (1.0 - cos(c * 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	var centers: Array[Vector3] = []
	var tangents: Array[Vector3] = []
	var rings: Array = []
	var ring_colors: Array[Color] = []
	var flap_ring := -1

	for i in RINGS + 1:
		var u := float(i) / float(RINGS)
		var theta := -c * 0.5 + c * u
		var center := Vector3(radius * sin(theta), radius * (1.0 - cos(theta)) - sag * 0.5, 0.0)
		var tangent := Vector3(cos(theta), sin(theta), 0.0)
		var normal := Vector3(-sin(theta), cos(theta), 0.0)
		var r: float
		var col: Color
		if u < STEM_PART:
			r = thick * 0.2
			col = stem
		else:
			var s := (u - STEM_PART) / (1.0 - STEM_PART)
			r = thick * maxf(0.22, pow(sin(PI * s), 0.5))
			col = peel
			if s > 0.92:
				col = tip
			elif is_peeled and s > 0.6:
				col = FLESH
				r *= 0.8
				if flap_ring < 0:
					flap_ring = i
		var ring: Array[Vector3] = []
		for k in SIDES:
			var phi := TAU * float(k) / float(SIDES) + PI / float(SIDES)
			ring.append(center + (normal * cos(phi) + Vector3.BACK * sin(phi)) * r)
		centers.append(center)
		tangents.append(tangent)
		rings.append(ring)
		ring_colors.append(col)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Kylki: jokainen sivu on oma tasainen pinta (low-poly).
	for i in RINGS:
		var a: Array[Vector3] = rings[i]
		var b: Array[Vector3] = rings[i + 1]
		var mid := (centers[i] + centers[i + 1]) * 0.5
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			var col := ring_colors[i]
			if spotted and col == peel and rng.randf() < 0.3:
				col = peel.lerp(tip, 0.55)
			elif col == peel:
				col = col.darkened(0.06) if k % 2 == 0 else col
			var face_center := (a[k] + a[k2] + b[k] + b[k2]) * 0.25
			var out := face_center - mid
			_tri(st, a[k], b[k], b[k2], out, col)
			_tri(st, a[k], b[k2], a[k2], out, col)

	# Varren pää: tasainen kansi.
	var first: Array[Vector3] = rings[0]
	for k in SIDES:
		_tri(st, centers[0], first[k], first[(k + 1) % SIDES], -tangents[0], stem.darkened(0.25))
	# Kärki: pieni nysä.
	var last: Array[Vector3] = rings[RINGS]
	var nub := centers[RINGS] + tangents[RINGS] * thick * 0.25
	for k in SIDES:
		var k2 := (k + 1) % SIDES
		var out := (last[k] + last[k2]) * 0.5 + nub - centers[RINGS] * 2.0
		_tri(st, nub, last[k], last[k2], out, tip.darkened(0.2))

	# Kuoriliuskat roikkumaan taaksepäin.
	if is_peeled and flap_ring > 0:
		var base_ring: Array[Vector3] = rings[flap_ring]
		var base_center := centers[flap_ring]
		var back := -tangents[flap_ring]
		for k in [0, 2, 4]:
			var p0: Vector3 = base_ring[k] * 1.0
			var p1: Vector3 = base_ring[(k + 1) % SIDES] * 1.0
			var side_dir := ((p0 + p1) * 0.5 - base_center).normalized()
			var tip_p := (p0 + p1) * 0.5 + back * len * 0.28 + side_dir * thick * 0.9
			var out := side_dir
			_tri(st, p0, p1, tip_p, out, peel)
			_tri(st, p0, p1, tip_p, -out, FLESH.darkened(0.08))

	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Lisää kolmion niin, että sen etupuoli osoittaa `outward`-suuntaan.
## Godotissa etupuolen kiertosuunta on myötäpäivään.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot(outward) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	# (b - a) x (c - a) osoittaa nyt ulos -> käännetään myötäpäiväiseksi.
	# Shader käyttää COLORia sellaisenaan (lineaarisena), joten muunnetaan sRGB -> lineaarinen.
	color = color.srgb_to_linear()
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(b)

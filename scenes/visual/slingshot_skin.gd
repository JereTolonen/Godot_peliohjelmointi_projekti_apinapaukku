extends Node3D
## Ritsan visuaalinen malli ja kaksi kuminauhaa haarojen päistä ammukseen.
##
## Lukee ritsan tilaa (vedetäänkö, missä ammus on) mutta ei muuta sitä. Pelin oma
## yksittäinen nauha piilotetaan läpinäkyvyydellä, ja tähtäyspisteet saavat
## yhtenäisen ulkoasun.

const ArtStyle := preload("res://scenes/visual/art_style.gd")
const AIM_DOT := preload("res://scenes/visual/shaders/aim_dot.gdshader")

var slingshot: Node3D = null
var anchor_local: Vector3 = Vector3.ZERO

var _bands: Array[MeshInstance3D] = []
var _pouch: MeshInstance3D = null
var _tips: Array[Vector3] = []
var _dots_styled: bool = false
var _was_dragging: bool = false
var _snap: float = 0.0


func _ready() -> void:
	_tips = [get_meta("tip_l", Vector3(-0.36, 1.8, 0.0)), get_meta("tip_r", Vector3(0.36, 1.8, 0.0))]
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.045
	band_mesh.bottom_radius = 0.045
	band_mesh.height = 1.0
	band_mesh.radial_segments = 6
	band_mesh.rings = 1
	band_mesh.material = ArtStyle.flat_material(Color("5a2b20"), 0.5)
	for i in 2:
		var band := MeshInstance3D.new()
		band.mesh = band_mesh
		band.top_level = true
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(band)
		_bands.append(band)
	var pouch_mesh := BoxMesh.new()
	pouch_mesh.size = Vector3(0.16, 0.34, 0.3)
	pouch_mesh.material = ArtStyle.flat_material(Color("6b3a22"), 0.7)
	_pouch = MeshInstance3D.new()
	_pouch.mesh = pouch_mesh
	_pouch.top_level = true
	add_child(_pouch)


func _process(delta: float) -> void:
	if not is_instance_valid(slingshot):
		return
	_style_game_aim()

	var dragging := bool(slingshot.get("_dragging"))
	var body: Variant = slingshot.get("_drag_body")
	var anchor := slingshot.global_transform * anchor_local
	var target := anchor + Vector3(0.0, -0.06, 0.0)
	if dragging and body is Node3D and is_instance_valid(body):
		target = (body as Node3D).global_position
		_was_dragging = true
		_snap = 0.0
	elif _was_dragging:
		# Little twang after the release.
		_was_dragging = false
		_snap = 1.0
	if _snap > 0.0:
		_snap = maxf(_snap - delta * 3.5, 0.0)
		target += Vector3(sin(_snap * 30.0) * 0.25 * _snap, 0.0, 0.0)

	for i in 2:
		var tip := slingshot.global_transform * _tips[i]
		tip.z += 0.09 if i == 0 else -0.09
		_place_band(_bands[i], tip, target)
	_pouch.global_position = target
	_pouch.visible = not dragging


func _place_band(band: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		band.visible = false
		return
	band.visible = true
	var y := dir / length
	var x := y.cross(Vector3.BACK)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	band.global_transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)


## Pelin nauha piiloon ja tähtäyspisteet pehmeiksi, pieneneviksi helmiksi.
func _style_game_aim() -> void:
	var game_band: Variant = slingshot.get("_band")
	if game_band is GeometryInstance3D and is_instance_valid(game_band):
		(game_band as GeometryInstance3D).transparency = 1.0
	if _dots_styled:
		return
	var dots: Variant = slingshot.get("_dots")
	if not (dots is Array) or (dots as Array).is_empty():
		return
	# Kontrastikkaat pisteet: valkoinen keskus, tumma reunus ja varjo (aim_dot.gdshader).
	var material := ShaderMaterial.new()
	material.shader = AIM_DOT
	# Piirretään viimeisenä, kaiken päälle.
	material.render_priority = Material.RENDER_PRIORITY_MAX
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var list := dots as Array
	for i in list.size():
		var dot := list[i] as MeshInstance3D
		if dot == null:
			continue
		dot.mesh = quad
		dot.material_override = material
		var s := lerpf(1.35, 0.55, float(i) / float(maxi(list.size() - 1, 1)))
		dot.scale = Vector3.ONE * s
	_dots_styled = true

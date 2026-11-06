extends RefCounted
## Lyhyet, kevyet efektit: materiaalikohtaiset sirpaleet (puu, kivi, jää), pienet
## osumaroiskeet, tähtipurskeet ja kipinät. Kaikki ovat yhden laukauksen
## GPU-partikkeleita, jotka poistavat itsensä. Meshit ja materiaalit jaetaan.

const ArtStyle := preload("res://scenes/visual/art_style.gd")

static var _meshes: Dictionary = {}
static var _star_texture: ImageTexture = null


static func _shard_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: PrimitiveMesh
	match kind:
		"wood":
			var box := BoxMesh.new()
			box.size = Vector3(0.07, 0.07, 0.34)
			box.material = ArtStyle.flat_material(Color("c98446"), 0.8)
			mesh = box
		"stone":
			var sphere := SphereMesh.new()
			sphere.radius = 0.11
			sphere.height = 0.2
			sphere.radial_segments = 5
			sphere.rings = 3
			sphere.material = ArtStyle.flat_material(Color("8e96a8"), 0.95)
			mesh = sphere
		"ice":
			var prism := PrismMesh.new()
			prism.size = Vector3(0.16, 0.26, 0.05)
			prism.material = ArtStyle.flat_material(Color(0.75, 0.93, 1.0, 0.85), 0.1, 0.6)
			mesh = prism
		"leaf":
			var quad := BoxMesh.new()
			quad.size = Vector3(0.14, 0.02, 0.09)
			quad.material = ArtStyle.flat_material(Color("7cc84a"), 0.9)
			mesh = quad
		"confetti":
			var quad := BoxMesh.new()
			quad.size = Vector3(0.12, 0.02, 0.07)
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			quad.material = mat
			mesh = quad
		_:
			var star := QuadMesh.new()
			star.size = Vector2(0.45, 0.45)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			mat.vertex_color_use_as_albedo = true
			mat.albedo_texture = star_texture()
			star.material = mat
			mesh = star
	_meshes[kind] = mesh
	return mesh


## Valkoinen viisisakarainen tähti läpinäkyvällä taustalla (UI ja partikkelit).
static func star_texture() -> ImageTexture:
	if _star_texture != null:
		return _star_texture
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var a := atan2(p.y, p.x) + PI * 0.5
			var k := cos(a * 5.0) * 0.5 + 0.5
			var r := lerpf(size * 0.2, size * 0.47, pow(k, 2.2))
			var d := p.length()
			var alpha := clampf((r - d) * 0.6, 0.0, 1.0)
			var glow := clampf(1.0 - d / (size * 0.5), 0.0, 1.0) * 0.35
			img.set_pixel(x, y, Color(1, 1, 1, maxf(alpha, glow)))
	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture


static func _burst(world: Node, at: Vector3, mesh: Mesh, amount: int, lifetime: float, speed: Vector2, spread: float, gravity: float, size: Vector2, color_ramp: Gradient = null, spin: float = 8.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.95
	p.fixed_fps = 0
	p.local_coords = false
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0, -gravity, 0)
	pm.angular_velocity_min = -spin * 60.0
	pm.angular_velocity_max = spin * 60.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = size.x
	pm.scale_max = size.y
	pm.particle_flag_rotate_y = true
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	if color_ramp != null:
		var gt := GradientTexture1D.new()
		gt.gradient = color_ramp
		pm.color_ramp = gt
	p.process_material = pm
	world.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.3, false).timeout.connect(p.queue_free)
	return p


## Palikan hajoaminen: sirut materiaalin mukaan + tähtikipinät.
static func block_break(world: Node, at: Vector3, kind: String, block_size: Vector3) -> void:
	var volume := clampf(block_size.x * block_size.y, 0.4, 4.0)
	var n := int(10.0 + volume * 6.0)
	match kind:
		"ice":
			_burst(world, at, _shard_mesh("ice"), n + 6, 1.1, Vector2(3.0, 8.0), 80.0, 14.0, Vector2(0.6, 1.4), null, 10.0)
			_burst(world, at, _shard_mesh("star"), 8, 0.6, Vector2(1.0, 3.5), 180.0, 0.0, Vector2(0.4, 0.9), _fade(Color(0.8, 0.95, 1.0)))
		"stone":
			_burst(world, at, _shard_mesh("stone"), n, 1.2, Vector2(2.0, 6.0), 70.0, 16.0, Vector2(0.6, 1.6), null, 5.0)
		_:
			_burst(world, at, _shard_mesh("wood"), n, 1.2, Vector2(3.0, 7.5), 75.0, 15.0, Vector2(0.6, 1.3), null, 12.0)


## Pieni osumaroiske, kun palikka ottaa vahinkoa mutta ei hajoa.
static func block_chip(world: Node, at: Vector3, kind: String) -> void:
	var mesh := _shard_mesh("ice" if kind == "ice" else ("stone" if kind == "stone" else "wood"))
	_burst(world, at, mesh, 5, 0.7, Vector2(2.0, 4.0), 60.0, 14.0, Vector2(0.35, 0.6), null, 10.0)


## Kultaiset tähdet (apinan kaatuminen, palkinnot).
static func star_burst(world: Node, at: Vector3, amount: int = 12) -> void:
	_burst(world, at, _shard_mesh("star"), amount, 0.9, Vector2(2.5, 6.0), 180.0, 4.0, Vector2(0.6, 1.3), _fade(Color("ffd84a")))


static func confetti(world: Node, at: Vector3, amount: int = 40) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Color("ff5d73"), Color("ffd23f"), Color("3ddc97"), Color("4da6ff"), Color("b67dff")])
	var p := _burst(world, at, _shard_mesh("confetti"), amount, 2.2, Vector2(5.0, 10.0), 50.0, 7.0, Vector2(0.8, 1.4), null, 14.0)
	var pm := p.process_material as ParticleProcessMaterial
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	pm.damping_min = 2.0
	pm.damping_max = 4.0


static func _fade(color: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([color, color, Color(color.r, color.g, color.b, 0.0)])
	return g


# --- Ability effects -------------------------------------------------------------

## Kirkas rengas + välähdys kyvyn aktivoituessa.
static func ability_flash(world: Node, at: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ring)
	ring.global_position = at
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.scale = Vector3.ONE * 0.4
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3.ONE * 4.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.chain().tween_callback(ring.queue_free)
	_burst(world, at, _shard_mesh("star"), 10, 0.5, Vector2(3.0, 6.0), 180.0, 0.0, Vector2(0.5, 1.0), _fade(color))


## Vauhtiviivat lentävän kappaleen perään `duration` sekunniksi.
static func speed_trail(body: Node3D, color: Color, duration: float = 0.8) -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.35
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.spread = 8.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var gt := GradientTexture1D.new()
	gt.gradient = _fade(color)
	pm.color_ramp = gt
	p.process_material = pm
	body.add_child(p)
	p.emitting = true
	body.get_tree().create_timer(duration, false).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false
			p.get_tree().create_timer(0.5, false).timeout.connect(p.queue_free))


## Maata pitkin leviävä iskuaalto + pölyrengas (painava hahmo).
static func shockwave(world: Node, at: Vector3, radius: float = 3.0) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.95, 0.8, 0.85)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ring)
	ring.global_position = at
	ring.scale = Vector3(0.3, 0.3, 0.3)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(radius, 0.6, radius), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	t.chain().tween_callback(ring.queue_free)
	_burst(world, at, _shard_mesh("stone"), 16, 1.0, Vector2(3.0, 7.0), 60.0, 15.0, Vector2(0.5, 1.2), null, 6.0)
	_shake(world, 0.35)


## Valkoisia höyheniä (pommittajan munanpudotus).
static func feather_puff(world: Node, at: Vector3) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	_burst(world, at, _shard_mesh("confetti"), 14, 0.9, Vector2(1.5, 3.5), 180.0, 2.0, Vector2(0.8, 1.3), g, 6.0)


## Pieni kameran tärähdys (h/v_offset, kuten räjähdyksessä, joten kameran ohjaus ei häiriinny).
static func _shake(world: Node, amount: float) -> void:
	var cam := world.get_viewport().get_camera_3d()
	if cam == null:
		return
	var t := cam.create_tween()
	for i in 6:
		var s := amount * (1.0 - float(i) / 6.0)
		t.tween_property(cam, "h_offset", randf_range(-s, s), 0.035)
		t.parallel().tween_property(cam, "v_offset", randf_range(-s, s), 0.035)
	t.tween_property(cam, "h_offset", 0.0, 0.05)
	t.parallel().tween_property(cam, "v_offset", 0.0, 0.05)

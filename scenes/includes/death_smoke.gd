extends Node3D
## Stylized cartoon smoke burst (no external assets). Add it to the scene tree at the
## desired position. It plays once and frees itself.
##
## Layers: big grey puffs, a quick white poof, an expanding ring and a few green sparks.

## Overall scale of the effect.
@export var size: float = 1.0
## Seconds before the effect removes itself.
@export var duration: float = 2.0
## Green sparks (set to false for a plain dust puff).
@export var show_sparks: bool = true
## Expanding white ring (set to false for a plain dust puff).
@export var show_ring: bool = true


func _ready() -> void:
	_spawn_puffs()
	_spawn_poof()
	if show_ring:
		_spawn_ring()
	if show_sparks:
		_spawn_sparks()
	get_tree().create_timer(duration).timeout.connect(queue_free)


func _spawn_puffs() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25 * size
	pm.direction = Vector3.UP
	pm.spread = 100.0
	pm.initial_velocity_min = 1.0 * size
	pm.initial_velocity_max = 3.0 * size
	pm.gravity = Vector3(0.0, 0.8, 0.0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.7 * size
	pm.scale_max = 1.4 * size
	pm.scale_curve = _curve_texture([Vector2(0.0, 0.3), Vector2(0.35, 1.0), Vector2(1.0, 1.15)])
	pm.color_ramp = _ramp_texture(
		PackedColorArray([
			Color(0.97, 0.97, 0.97, 0.95),
			Color(0.78, 0.78, 0.82, 0.7),
			Color(0.55, 0.55, 0.62, 0.0),
		]),
		PackedFloat32Array([0.0, 0.55, 1.0])
	)
	var mesh := _billboard_quad(_disc_texture(0.88), false)
	_spawn_particles(14, 1.2, mesh, pm)


func _spawn_poof() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15 * size
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0 * size
	pm.initial_velocity_max = 7.0 * size
	pm.damping_min = 6.0
	pm.damping_max = 10.0
	pm.scale_min = 0.25 * size
	pm.scale_max = 0.5 * size
	pm.scale_curve = _curve_texture([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	pm.color_ramp = _ramp_texture(
		PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)]),
		PackedFloat32Array([0.0, 1.0])
	)
	var mesh := _billboard_quad(_disc_texture(0.9), false)
	_spawn_particles(10, 0.5, mesh, pm)


func _spawn_sparks() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1 * size
	pm.direction = Vector3.UP
	pm.spread = 120.0
	pm.initial_velocity_min = 3.0 * size
	pm.initial_velocity_max = 7.0 * size
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.scale_min = 0.08 * size
	pm.scale_max = 0.16 * size
	pm.color_ramp = _ramp_texture(
		PackedColorArray([
			Color(0.85, 1.0, 0.45, 1.0),
			Color(0.3, 1.0, 0.35, 1.0),
			Color(0.2, 0.9, 0.3, 0.0),
		]),
		PackedFloat32Array([0.0, 0.5, 1.0])
	)
	var mesh := _billboard_quad(_disc_texture(0.6), true)
	_spawn_particles(10, 0.8, mesh, pm)


func _spawn_ring() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = _ring_texture()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	quad.material = mat

	var ring := MeshInstance3D.new()
	ring.mesh = quad
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 0.3 * size
	add_child(ring)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 1.8 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)


# --- Helpers ----------------------------------------------------------------

func _spawn_particles(amount: int, lifetime: float, mesh: Mesh, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.3
	p.one_shot = true
	p.explosiveness = 1.0
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-20.0, -20.0, -20.0), Vector3(40.0, 40.0, 40.0))
	p.emitting = false
	add_child(p)
	p.emitting = true
	return p


func _billboard_quad(tex: Texture2D, additive: bool) -> QuadMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	return quad


## White disc that stays solid until `solid_until` (0..1) and then fades out.
func _disc_texture(solid_until: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, solid_until, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## Thin hard-edged ring.
func _ring_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.82, 0.86, 0.96, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
		Color.WHITE,
		Color.WHITE,
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func _ramp_texture(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _curve_texture(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt as Vector2)
	var t := CurveTexture.new()
	t.curve = c
	return t

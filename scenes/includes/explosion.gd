extends Node3D
## Stylized, fully procedural explosion (no external assets needed).
## Add it to the scene tree at the desired position. It plays once and frees itself.
##
## Layers: white-hot flash, shockwave ring, cartoon fire puffs, smoke, sparks,
## a short orange light flash and a small camera shake.

## Overall scale of the explosion.
@export var size: float = 1.0
## Strength of the camera shake (0 disables it).
@export var camera_shake: float = 0.3
## Seconds before the effect removes itself.
@export var duration: float = 2.5


func _ready() -> void:
	_spawn_flash()
	_spawn_shockwave()
	_spawn_fire()
	_spawn_smoke()
	_spawn_sparks()
	_spawn_light()
	_shake_camera()
	get_tree().create_timer(duration).timeout.connect(queue_free)


# --- Layers -----------------------------------------------------------------

func _spawn_flash() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.95, 0.7, 1.0)
	mesh.material = mat

	var flash := MeshInstance3D.new()
	flash.mesh = mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.scale = Vector3.ONE * 0.5 * size
	add_child(flash)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 4.0 * size, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.chain().tween_callback(flash.queue_free)


func _spawn_shockwave() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = _ring_texture()
	mat.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
	quad.material = mat

	var ring := MeshInstance3D.new()
	ring.mesh = quad
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 0.4 * size
	add_child(ring)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * 4.5 * size, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)


func _spawn_fire() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3 * size
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0 * size
	pm.initial_velocity_max = 6.0 * size
	pm.gravity = Vector3(0.0, 1.5, 0.0)
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	pm.scale_min = 1.2 * size
	pm.scale_max = 2.4 * size
	pm.scale_curve = _curve_texture([Vector2(0.0, 0.5), Vector2(0.25, 1.0), Vector2(1.0, 0.0)])
	pm.color_ramp = _ramp_texture(
		PackedColorArray([
			Color(1.0, 1.0, 0.8, 1.0),
			Color(1.0, 0.75, 0.1, 1.0),
			Color(1.0, 0.3, 0.05, 0.9),
			Color(0.25, 0.05, 0.02, 0.0),
		]),
		PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	)
	# Hard-edged discs give a cartoon look.
	var mesh := _billboard_quad(_disc_texture(0.9), true)
	_spawn_particles(28, 0.9, mesh, pm)


func _spawn_smoke() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4 * size
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 1.0 * size
	pm.initial_velocity_max = 3.0 * size
	pm.gravity = Vector3(0.0, 0.8, 0.0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 1.5 * size
	pm.scale_max = 3.0 * size
	pm.scale_curve = _curve_texture([Vector2(0.0, 0.3), Vector2(0.4, 1.0), Vector2(1.0, 1.2)])
	pm.color_ramp = _ramp_texture(
		PackedColorArray([
			Color(0.12, 0.1, 0.1, 0.9),
			Color(0.3, 0.28, 0.27, 0.55),
			Color(0.45, 0.43, 0.42, 0.0),
		]),
		PackedFloat32Array([0.0, 0.6, 1.0])
	)
	var mesh := _billboard_quad(_disc_texture(0.85), false)
	_spawn_particles(14, 1.8, mesh, pm)


func _spawn_sparks() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15 * size
	pm.direction = Vector3.UP
	pm.spread = 120.0
	pm.initial_velocity_min = 6.0 * size
	pm.initial_velocity_max = 14.0 * size
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.08 * size
	pm.scale_max = 0.2 * size
	pm.color_ramp = _ramp_texture(
		PackedColorArray([
			Color(1.0, 0.95, 0.6, 1.0),
			Color(1.0, 0.5, 0.1, 1.0),
			Color(1.0, 0.2, 0.0, 0.0),
		]),
		PackedFloat32Array([0.0, 0.5, 1.0])
	)
	var mesh := _billboard_quad(_disc_texture(0.6), true)
	_spawn_particles(30, 1.0, mesh, pm)


func _spawn_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 8.0
	light.omni_range = 10.0 * size
	add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)


func _shake_camera() -> void:
	if camera_shake <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var tw := cam.create_tween()
	var steps := 6
	for i in steps:
		var s := camera_shake * (1.0 - float(i) / float(steps))
		tw.tween_property(cam, "h_offset", randf_range(-s, s), 0.04)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-s, s), 0.04)
	tw.tween_property(cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.05)


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


## Thin hard-edged ring used for the shockwave.
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

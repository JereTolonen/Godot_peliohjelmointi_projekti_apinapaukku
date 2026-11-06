@tool
extends Node3D
## Tekee pomosta hullun näköisen: isot heiluvat mulkosilmät, suu ja läpättävä kieli,
## hyytelömäinen venytys-litistys, sätkivät jalat ja heiluva häntä.
##
## enemy_boss.gd kutsuu hypyissä crouch(), jump(), land() ja osumassa hurt().
## Laita tämä "Visual"-solmun alle ja apinamalli ("Monkey") tämän alle. Visual-solmua ei
## animoida, koska enemy_boss.gd skaalaa sitä osumaefektissä.

## Apinamallin skaala (sama kuin Monkey-solmulla), silmät ja suu sijoitetaan sen mukaan.
@export var model_scale: float = 2.2
## Kuinka hullusti pomo heiluu.
@export_range(0.0, 2.0, 0.05) var craziness: float = 1.0
## Silmien koko suhteessa malliin.
@export var eye_size: float = 0.25
## Kielen väri.
@export var tongue_color: Color = Color("ff5f8f")

enum Pose { IDLE, CROUCH, AIR }

var _time: float = 0.0
var _phase: float = 0.0
var _pose: Pose = Pose.IDLE

# Hyytelöjousi pystyskaalalle.
var _squash: float = 1.0
var _squash_vel: float = 0.0
# Pyörähdys hypyssä.
var _spin: float = 0.0
var _spin_speed: float = 0.0
var _spin_left: float = 0.0
var _dizzy: float = 0.0

var _pupils: Array[MeshInstance3D] = []
var _pupil_offset: Array[Vector2] = []
var _pupil_velocity: Array[Vector2] = []
var _tongue: Node3D = null
var _mouth: MeshInstance3D = null
var _legs: Array[Node3D] = []
var _leg_rest: Array[Vector3] = []
var _tail: Node3D = null
var _tail_rest: Vector3 = Vector3.ZERO
var _last_global: Vector3 = Vector3.ZERO


func _ready() -> void:
	_phase = randf() * TAU
	_build_face()
	_find_limbs()
	_last_global = global_position
	set_process(not Engine.is_editor_hint())


# --- Kutsut pomolta ------------------------------------------------------------

func crouch(duration: float) -> void:
	_pose = Pose.CROUCH
	_squash_vel -= 2.5 / maxf(duration, 0.05) * 0.2


func jump(air_time: float, spin: bool) -> void:
	_pose = Pose.AIR
	_squash_vel += 6.0
	if spin:
		_spin_left = air_time
		_spin_speed = TAU / maxf(air_time * 0.9, 0.2)
	_kick_pupils(Vector2(0, -2.5))


func land() -> void:
	_pose = Pose.IDLE
	_squash = minf(_squash, 0.8)
	_squash_vel -= 5.0
	_kick_pupils(Vector2(0, 3.0))


func hurt() -> void:
	_dizzy = 1.4
	_squash_vel -= 3.0


# --- Rakennus ----------------------------------------------------------------

func _build_face() -> void:
	for child in get_children():
		if child.name.begins_with("Silly_"):
			child.free()
	_pupils.clear()
	_pupil_offset.clear()
	_pupil_velocity.clear()

	var s := model_scale
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.roughness = 0.25
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.02, 0.02)
	black.roughness = 0.15

	# Eri kokoiset silmät näyttävät hullummilta.
	var sizes := [eye_size * 1.15, eye_size * 0.85]
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var r: float = sizes[i] * s
		var eye := MeshInstance3D.new()
		eye.name = "Silly_Eye%d" % i
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = r * 2.0
		sphere.radial_segments = 16
		sphere.rings = 8
		eye.mesh = sphere
		eye.material_override = white
		eye.position = Vector3(side * 0.33 * s, (1.05 + 0.04 * side) * s, 0.58 * s)
		add_child(eye)

		var pupil := MeshInstance3D.new()
		pupil.name = "Pupil"
		var ps := SphereMesh.new()
		ps.radius = r * 0.58
		ps.height = r * 1.16
		ps.radial_segments = 12
		ps.rings = 6
		pupil.mesh = ps
		pupil.material_override = black
		pupil.position = Vector3(0, 0, r * 0.72)
		eye.add_child(pupil)
		_pupils.append(pupil)
		_pupil_offset.append(Vector2(side * 0.3, -0.2))
		_pupil_velocity.append(Vector2.ZERO)

	# Suu: tumma soikio, kieli roikkuu siitä.
	_mouth = MeshInstance3D.new()
	_mouth.name = "Silly_Mouth"
	var mouth_mesh := SphereMesh.new()
	mouth_mesh.radius = 0.22 * s
	mouth_mesh.height = 0.44 * s
	mouth_mesh.radial_segments = 14
	mouth_mesh.rings = 6
	_mouth.mesh = mouth_mesh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("3a0d14")
	dark.roughness = 0.6
	_mouth.material_override = dark
	_mouth.position = Vector3(0.06 * s, 0.6 * s, 0.6 * s)
	_mouth.scale = Vector3(1.0, 0.45, 0.25)
	add_child(_mouth)

	_tongue = Node3D.new()
	_tongue.name = "Silly_Tongue"
	_tongue.position = Vector3(0.12 * s, 0.58 * s, 0.66 * s)
	add_child(_tongue)
	var tongue_mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.11 * s
	capsule.height = 0.5 * s
	capsule.radial_segments = 10
	capsule.rings = 2
	tongue_mesh.mesh = capsule
	var pink := StandardMaterial3D.new()
	pink.albedo_color = tongue_color
	pink.roughness = 0.35
	tongue_mesh.material_override = pink
	tongue_mesh.scale = Vector3(1.0, 1.0, 0.45)
	tongue_mesh.position = Vector3(0, -0.2 * s, 0.03 * s)
	_tongue.add_child(tongue_mesh)


## Apinamallin jalat ja häntä ovat omia solmujaan, joten niitä voi heiluttaa.
func _find_limbs() -> void:
	_legs.clear()
	_leg_rest.clear()
	for node in find_children("leg-*", "Node3D", true, false):
		_legs.append(node as Node3D)
		_leg_rest.append((node as Node3D).rotation)
	_tail = find_child("tail", true, false) as Node3D
	if _tail != null:
		_tail_rest = _tail.rotation


# --- Animaatio ---------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var t := _time + _phase
	var c := craziness
	_dizzy = maxf(_dizzy - delta, 0.0)

	# Hyytelöjousi: kohde riippuu asennosta.
	var target := 1.0 + sin(t * 3.2) * 0.04 * c
	match _pose:
		Pose.CROUCH:
			target = 0.68
		Pose.AIR:
			target = 1.18
	_squash_vel += (target - _squash) * 180.0 * delta
	_squash_vel *= exp(-9.0 * delta)
	_squash = clampf(_squash + _squash_vel * delta, 0.45, 1.6)
	var wide := 1.0 / sqrt(_squash)
	scale = Vector3(wide, _squash, wide)

	# Pyörähdys hypyssä, muuten keinunta.
	if _spin_left > 0.0:
		_spin_left -= delta
		_spin += _spin_speed * delta
		if _spin_left <= 0.0:
			_spin = 0.0
	var rock_y := sin(t * 1.3) * 0.25 * c
	var rock_z := sin(t * 2.1) * 0.08 * c
	if _pose == Pose.AIR:
		rock_z = sin(t * 14.0) * 0.12 * c
	if _dizzy > 0.0:
		rock_z += sin(t * 11.0) * 0.15
	rotation = Vector3(0.0, rock_y + _spin, rock_z)

	# Jalat sätkivät ilmassa, muuten pientä tepastelua. Häntä heiluu aina.
	for i in _legs.size():
		var leg := _legs[i]
		var rest := _leg_rest[i]
		var side := 1.0 if i % 2 == 0 else -1.0
		if _pose == Pose.AIR:
			leg.rotation = rest + Vector3(sin(t * 22.0 + i * 1.7) * 0.9, 0.0, side * 0.6)
		elif _pose == Pose.CROUCH:
			leg.rotation = rest + Vector3(0.0, 0.0, side * 0.35)
		else:
			leg.rotation = rest + Vector3(sin(t * 6.0 + i * PI) * 0.15 * c, 0.0, 0.0)
	if _tail != null:
		var wag := 9.0 if _pose == Pose.AIR else 4.0
		_tail.rotation = _tail_rest + Vector3(0.0, sin(t * wag) * 0.5 * c, sin(t * wag * 0.5) * 0.3 * c)

	# Suu aukeaa ilmassa ja kieli läpättää.
	if _mouth != null:
		var open := 0.45 if _pose == Pose.IDLE else (0.25 if _pose == Pose.CROUCH else 0.9)
		_mouth.scale.y = lerpf(_mouth.scale.y, open, 1.0 - exp(-12.0 * delta))
	if _tongue != null:
		var flap := 0.5 if _pose == Pose.AIR else 0.25
		_tongue.rotation = Vector3(0.25 + sin(t * 9.0) * flap * c, 0.0, sin(t * 5.3) * 0.5 * c)

	_update_pupils(delta, t, c)


func _kick_pupils(kick: Vector2) -> void:
	for i in _pupil_velocity.size():
		_pupil_velocity[i] += kick * (1.0 + 0.4 * i)


## Mulkosilmät: pupillit ovat jousen päässä ja heiluvat liikkeen mukaan.
## Osuman jälkeen ne pyörivät ympyrää (pyörryksissä).
func _update_pupils(delta: float, t: float, c: float) -> void:
	var moved := global_position - _last_global
	_last_global = global_position
	var kick := Vector2(-moved.x, moved.y) * 0.12 / maxf(delta, 0.001)
	for i in _pupils.size():
		var v := _pupil_velocity[i]
		var o := _pupil_offset[i]
		var target := Vector2(sin(t * (1.7 + i)) * 0.6, cos(t * (2.3 - i * 0.6)) * 0.5) * c
		if _dizzy > 0.0:
			var a := t * (14.0 if i == 0 else -17.0)
			target = Vector2(cos(a), sin(a)) * 0.5
		v += ((target - o) * 30.0 + Vector2(0, -4.0)) * delta + kick * delta
		v *= exp(-3.0 * delta)
		o += v * delta
		if o.length() > 0.55:
			o = o.normalized() * 0.55
			v = v.bounce(o.normalized()) * 0.6
		_pupil_velocity[i] = v
		_pupil_offset[i] = o
		var eye_r := (_pupils[i].get_parent() as MeshInstance3D).mesh.get_aabb().size.x * 0.5
		var off := Vector3(o.x, o.y, 0.0) * eye_r
		off.z = sqrt(maxf(eye_r * eye_r * 0.52 - off.x * off.x - off.y * off.y, 0.0))
		_pupils[i].position = off

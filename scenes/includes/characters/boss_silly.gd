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
## Turkin väri (apinamallin tekstuuri kerrotaan tällä). Valkoinen = ennallaan.
@export var fur_tint: Color = Color.WHITE
## Asuste: none, moss, ice, glasses, candy, flame, king.
@export_enum("none", "moss", "ice", "glasses", "candy", "flame", "king", "astronaut", "pirate", "crystal", "alien", "storm", "hardhat", "knight", "beret") var accessory: String = "none"
## Mulkosilmät (pois, jos asuste peittää silmät, esim. aurinkolasit).
@export var googly_eyes: bool = true
## Vihaiset kulmakarvat.
@export var angry: bool = false

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
var _flames: Array[MeshInstance3D] = []


func _ready() -> void:
	_phase = randf() * TAU
	_apply_tint()
	_build_face()
	_build_accessory()
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
	for i in (2 if googly_eyes else 0):
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


## Värjää apinamallin (tekstuuri x fur_tint).
func _apply_tint() -> void:
	if fur_tint == Color.WHITE:
		return
	var model := get_node_or_null("Monkey")
	if model == null:
		return
	# Mallin tekstuurin turkin väri on b06041; kerroin tuo turkin kohti haluttua väriä.
	# Kerroin lasketaan hieman vaaleammasta arvosta, jottei kasvojen vaalea alue pala puhki.
	var base := Color("c98245")
	var mult := Color(minf(fur_tint.r / base.r, 2.4), minf(fur_tint.g / base.g, 2.4), minf(fur_tint.b / base.b, 2.4))
	var peak := maxf(mult.r, maxf(mult.g, mult.b))
	if peak > 1.6:
		mult = Color(mult.r * 1.6 / peak, mult.g * 1.6 / peak, mult.b * 1.6 / peak) * 1.0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = Color(mult.r, mult.g, mult.b)
			mi.set_surface_override_material(i, m)


## Pomon tunnusasuste (verkkosivun pomokuvien mukaan).
func _build_accessory() -> void:
	var s := model_scale
	var top := 1.45 * s
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color("452516")
	if angry and googly_eyes:
		for side in [-1.0, 1.0]:
			var brow := _box(Vector3(0.36, 0.07, 0.08) * s, ink)
			brow.position = Vector3(side * 0.33 * s, 1.36 * s, 0.66 * s)
			brow.rotation.z = side * -0.35
	match accessory:
		"moss":
			var moss := _mat(Color("70d52f"))
			var moss2 := _mat(Color("4a9e18"))
			for side in [-1.0, 1.0]:
				for j in 3:
					var b := _sphere(0.22 * s * (1.0 - j * 0.2), moss if j % 2 == 0 else moss2)
					b.position = Vector3(side * (0.75 - j * 0.12) * s, (1.05 + j * 0.12) * s, (0.1 - j * 0.15) * s)
					b.scale.y = 0.55
			var flower := _sphere(0.12 * s, _mat(Color("ffd64a"), 0.4))
			flower.position = Vector3(0.35 * s, top + 0.05 * s, 0.1 * s)
		"ice":
			var ice := _mat(Color(0.8, 0.95, 1.0), 0.6)
			for j in 5:
				var spike := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.12 * s
				cone.height = (0.45 + 0.15 * float(j % 2)) * s
				cone.radial_segments = 5
				spike.mesh = cone
				spike.material_override = ice
				spike.position = Vector3((-0.5 + 0.25 * j) * s, top + 0.12 * s, -0.05 * s)
				spike.rotation.z = (-0.5 + 0.25 * j) * -0.6
				spike.name = "Silly_IceSpike%d" % j
				add_child(spike)
		"glasses":
			var dark := _mat(Color("1a1410"), 0.2)
			var gold := _mat(Color("ffd64a"), 0.5)
			for side in [-1.0, 1.0]:
				var lens := _box(Vector3(0.42, 0.26, 0.08) * s, dark)
				lens.position = Vector3(side * 0.3 * s, 1.08 * s, 0.68 * s)
			var bridge := _box(Vector3(0.2, 0.06, 0.06) * s, gold)
			bridge.position = Vector3(0.0, 1.12 * s, 0.7 * s)
			# Kultaketju.
			for j in 7:
				var link := _sphere(0.07 * s, gold)
				var a := -1.2 + float(j) * 0.4
				link.position = Vector3(sin(a) * 0.5 * s, (0.72 - cos(a) * 0.08) * s, 0.62 * s)
		"candy":
			var colors := [Color("ffd64a"), Color("9be9ff"), Color("70d52f"), Color("fff0d2"), Color("ff5aa8")]
			for j in 12:
				var dot := _sphere(0.06 * s, _mat(colors[j % colors.size()], 0.3))
				var a := float(j) * 2.4
				dot.position = Vector3(cos(a) * 0.65 * s, (0.4 + fmod(float(j) * 0.37, 1.0) * 0.9) * s, (0.35 + sin(a) * 0.2) * s)
			var stick := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.03 * s
			cyl.bottom_radius = 0.03 * s
			cyl.height = 0.5 * s
			stick.mesh = cyl
			stick.material_override = _mat(Color.WHITE)
			stick.position = Vector3(0.3 * s, top + 0.25 * s, 0.0)
			stick.name = "Silly_Stick"
			add_child(stick)
			var pop := _sphere(0.2 * s, _mat(Color("ef62d2"), 0.5))
			pop.position = Vector3(0.3 * s, top + 0.55 * s, 0.0)
			pop.scale.z = 0.4
		"flame":
			var outer := _mat(Color("ff6a1a"), 2.4)
			var inner := _mat(Color("ffd64a"), 3.0)
			for j in 3:
				var f := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = (0.32 - j * 0.06) * s
				cone.height = (0.8 - j * 0.15) * s
				cone.radial_segments = 8
				f.mesh = cone
				f.material_override = outer if j < 2 else inner
				f.position = Vector3((-0.15 + j * 0.15) * s, top + 0.3 * s, (0.05 * j) * s)
				f.name = "Silly_Flame%d" % j
				add_child(f)
				_flames.append(f)
		"king":
			var gold := _mat(Color("ffd64a"), 0.5)
			var band := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.6 * s
			cyl.bottom_radius = 0.56 * s
			cyl.height = 0.16 * s
			cyl.radial_segments = 16
			band.mesh = cyl
			band.material_override = gold
			band.position = Vector3(0.0, top + 0.02 * s, 0.0)
			band.name = "Silly_Crown"
			add_child(band)
			for j in 5:
				var spike := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.1 * s
				cone.height = 0.28 * s
				cone.radial_segments = 6
				spike.mesh = cone
				spike.material_override = gold
				var a := -0.9 + 0.45 * j
				spike.position = Vector3(sin(a) * 0.55 * s, top + 0.22 * s, cos(a) * 0.3 * s)
				spike.name = "Silly_CrownSpike%d" % j
				add_child(spike)
			var gem := _sphere(0.08 * s, _mat(Color("ef62d2"), 1.0))
			gem.position = Vector3(0.0, top + 0.03 * s, 0.6 * s)
			# Viitta.
			var cape := _box(Vector3(1.7, 1.1, 0.06) * s, _mat(Color("7b3fb5")))
			cape.position = Vector3(0.0, 0.75 * s, -0.66 * s)
		"astronaut":
			# Lasikupu ja antennit.
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.6, 0.9, 1.0, 0.2)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			glass.rim_enabled = true
			glass.rim = 0.7
			var dome := _sphere(1.2 * s, glass)
			dome.position = Vector3(0.0, 0.85 * s, 0.05 * s)
			var metal := _mat(Color("8a5ac0"))
			var glow := _mat(Color("6aff8a"), 2.0)
			for side in [-1.0, 1.0]:
				var ant := _box(Vector3(0.05, 0.55, 0.05) * s, metal)
				ant.position = Vector3(side * 0.4 * s, top + 0.45 * s, 0.0)
				ant.rotation.z = side * -0.3
				var tip := _sphere(0.1 * s, glow)
				tip.position = Vector3(side * 0.5 * s, top + 0.75 * s, 0.0)
		"pirate":
			var black := _mat(Color("1a1410"))
			var hat := _box(Vector3(1.5, 0.35, 0.9) * s, black)
			hat.position = Vector3(0.0, top + 0.12 * s, 0.0)
			var crown := _box(Vector3(0.9, 0.35, 0.7) * s, black)
			crown.position = Vector3(0.0, top + 0.38 * s, 0.0)
			var skull := _sphere(0.1 * s, _mat(Color.WHITE))
			skull.position = Vector3(0.0, top + 0.2 * s, 0.46 * s)
			var patch := _box(Vector3(0.34, 0.3, 0.06) * s, black)
			patch.position = Vector3(0.36 * s, 1.07 * s, 0.84 * s)
			var strap := _box(Vector3(1.3, 0.05, 0.04) * s, black)
			strap.position = Vector3(0.0, 1.2 * s, 0.7 * s)
			strap.rotation.z = -0.25
		"crystal":
			var violet := _mat(Color(0.78, 0.5, 1.0), 1.4)
			var cyan := _mat(Color(0.45, 0.9, 1.0), 1.4)
			for j in 7:
				var c := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.14 * s
				cone.height = (0.5 + 0.2 * float(j % 3)) * s
				cone.radial_segments = 6
				c.mesh = cone
				c.material_override = violet if j % 2 == 0 else cyan
				var a := -1.4 + float(j) * 0.47
				c.position = Vector3(sin(a) * 0.65 * s, top + (0.1 + cos(a) * 0.1) * s, -0.15 * s)
				c.rotation.z = -a * 0.55
				c.name = "Silly_Crystal%d" % j
				add_child(c)
		"alien":
			var green := _mat(Color("6aff8a"), 0.8)
			for side in [-1.0, 1.0]:
				var stalk := _box(Vector3(0.06, 0.6, 0.06) * s, _mat(Color("3a9a4a")))
				stalk.position = Vector3(side * 0.3 * s, top + 0.3 * s, 0.1 * s)
				stalk.rotation.z = side * -0.25
				var bulb := _sphere(0.14 * s, green)
				bulb.position = Vector3(side * 0.38 * s, top + 0.62 * s, 0.1 * s)
			# Kolmas silmä otsassa.
			var eye := _sphere(0.16 * s, _mat(Color.WHITE))
			eye.position = Vector3(0.0, 1.38 * s, 0.62 * s)
			var pupil := _sphere(0.08 * s, _mat(Color("101010")))
			pupil.position = Vector3(0.0, 1.38 * s, 0.76 * s)
		"hardhat":
			var yellow := _mat(Color("ffc21a"), 0.2)
			var helmet := _sphere(0.62 * s, yellow)
			helmet.position = Vector3(0.0, top - 0.05 * s, 0.0)
			helmet.scale = Vector3(1.0, 0.55, 1.0)
			var brim := _box(Vector3(1.4, 0.06, 1.3) * s, yellow)
			brim.position = Vector3(0.0, top - 0.12 * s, 0.12 * s)
			var vest := _box(Vector3(1.6, 0.18, 0.06) * s, _mat(Color("ff7a1a"), 0.3))
			vest.position = Vector3(0.0, 0.55 * s, 0.66 * s)
			var stripe := _box(Vector3(1.6, 0.06, 0.07) * s, _mat(Color("f0f0f0"), 0.8))
			stripe.position = Vector3(0.0, 0.55 * s, 0.68 * s)
			var hammer := _box(Vector3(0.08, 0.7, 0.08) * s, _mat(Color("8a5a2a")))
			hammer.position = Vector3(0.95 * s, 0.7 * s, 0.3 * s)
			hammer.rotation.z = -0.4
			var head := _box(Vector3(0.36, 0.16, 0.16) * s, _mat(Color("7a8090")))
			head.position = Vector3(1.1 * s, 1.0 * s, 0.3 * s)
			head.rotation.z = -0.4
		"knight":
			var steel := _mat(Color("b8c0cc"), 0.15)
			var helm := _sphere(0.66 * s, steel)
			helm.position = Vector3(0.0, top - 0.15 * s, 0.0)
			helm.scale = Vector3(1.0, 0.8, 1.0)
			var visor := _box(Vector3(0.9, 0.08, 0.06) * s, _mat(Color("2a2c34")))
			visor.position = Vector3(0.0, top - 0.2 * s, 0.62 * s)
			var plume := _sphere(0.2 * s, _mat(Color("e83a3a"), 0.3))
			plume.position = Vector3(0.0, top + 0.4 * s, -0.1 * s)
			plume.scale = Vector3(0.6, 1.6, 1.4)
			var shield := _box(Vector3(0.75, 0.95, 0.08) * s, _mat(Color("3a5aa8")))
			shield.position = Vector3(-0.95 * s, 0.7 * s, 0.35 * s)
			shield.rotation.y = 0.5
			var cross := _box(Vector3(0.12, 0.7, 0.09) * s, _mat(Color("ffd64a"), 0.4))
			cross.position = Vector3(-0.95 * s, 0.72 * s, 0.4 * s)
			cross.rotation.y = 0.5
			var sword := _box(Vector3(0.07, 1.2, 0.03) * s, steel)
			sword.position = Vector3(1.0 * s, 0.9 * s, 0.3 * s)
			sword.rotation.z = -0.25
		"beret":
			var beret := _sphere(0.55 * s, _mat(Color("2a2a3a")))
			beret.position = Vector3(0.15 * s, top + 0.02 * s, 0.0)
			beret.scale = Vector3(1.1, 0.32, 1.0)
			beret.rotation.z = -0.2
			var nub := _sphere(0.06 * s, _mat(Color("2a2a3a")))
			nub.position = Vector3(0.2 * s, top + 0.2 * s, 0.0)
			var stache := _mat(Color("2a1a10"))
			for side in [-1.0, 1.0]:
				var m := _box(Vector3(0.32, 0.08, 0.06) * s, stache)
				m.position = Vector3(side * 0.18 * s, 0.75 * s, 0.7 * s)
				m.rotation.z = side * 0.3
			# Raidallinen paita ja maalauspensseli.
			for j in 3:
				var stripe := _box(Vector3(1.55, 0.07, 0.06) * s, _mat(Color("1a2a6a")))
				stripe.position = Vector3(0.0, (0.25 + 0.16 * j) * s, 0.66 * s)
			var brush := _box(Vector3(0.06, 0.6, 0.06) * s, _mat(Color("8a5a2a")))
			brush.position = Vector3(1.0 * s, 0.8 * s, 0.3 * s)
			brush.rotation.z = -0.5
			var tip := _sphere(0.08 * s, _mat(Color("ff4a8a"), 0.6))
			tip.position = Vector3(1.15 * s, 1.08 * s, 0.3 * s)
		"storm":
			# Ukkospilvi päälaella ja salamat.
			var cloud := _mat(Color("8a90a8"))
			for j in 5:
				var puff := _sphere((0.3 + 0.08 * float(j % 2)) * s, cloud)
				puff.position = Vector3((-0.5 + 0.25 * j) * s, top + (0.25 + 0.08 * float(j % 2)) * s, 0.0)
			var bolt_mat := _mat(Color("ffe94a"), 2.5)
			for side in [-1.0, 1.0]:
				var bolt := _box(Vector3(0.08, 0.45, 0.05) * s, bolt_mat)
				bolt.position = Vector3(side * 0.55 * s, top - 0.05 * s, 0.25 * s)
				bolt.rotation.z = side * 0.5
				_flames.append(bolt)
			var goggles := _mat(Color("ffd64a"), 0.3)
			var strap := _box(Vector3(1.5, 0.08, 0.06) * s, _mat(Color("5a3a20")))
			strap.position = Vector3(0.0, 1.3 * s, 0.62 * s)
			for side in [-1.0, 1.0]:
				var g := _box(Vector3(0.3, 0.12, 0.06) * s, goggles)
				g.position = Vector3(side * 0.3 * s, 1.32 * s, 0.66 * s)


func _mat(c: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _sphere(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	mi.name = "Silly_Acc%d" % get_child_count()
	add_child(mi)
	return mi


func _box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.name = "Silly_Acc%d" % get_child_count()
	add_child(mi)
	return mi


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
	# Liekit lepattavat.
	for i in _flames.size():
		_flames[i].scale = Vector3(1.0, 1.0 + sin(t * 14.0 + i * 2.0) * 0.18, 1.0)


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

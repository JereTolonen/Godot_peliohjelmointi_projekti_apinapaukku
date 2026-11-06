extends Node
## Visuaalinen ohjaaja (autoload "VisualDirector").
##
## Pukee jokaisen kentän sen latautuessa: teeman valaistus, taivas ja sumu, taustamaisema
## (vesi, kukkulat, vuoret, pilvet, kasvillisuus tai avaruus), materiaalit palikoille ja
## maastolle, ritsan malli, painovoimakaivojen planeetat, ympäristöpartikkelit ja
## materiaalikohtaiset tuhoefektit. Päävalikon taakse rakennetaan oma pieni diorama.
##
## Kaikki lisätyt solmut ovat vain visuaalisia (ei törmäyksiä, ei ryhmiä), ja ne
## lisätään kentän alle, joten ne poistuvat kentän mukana. Pelilogiikkaa, fysiikkaa,
## collidereita tai ohjausta ei muuteta.

signal level_dressed(number: int, theme: String)

const ArtStyle := preload("res://scenes/visual/art_style.gd")
const Props := preload("res://scenes/visual/prop_factory.gd")
const Vfx := preload("res://scenes/visual/vfx.gd")
const SlingshotSkin := preload("res://scenes/visual/slingshot_skin.gd")
const MenuStyle := preload("res://scenes/ui/menu_style.gd")
const NIGHT_SKY := preload("res://sky/examples/night_sky.tres")
const KIT := "res://assets/mesh/ground/%s.glb"
const MONKEY := "res://assets/mesh/characters/animal-monkey.glb"
const BananaModel := preload("res://scenes/includes/characters/banana_model.gd")
const FOCUS_POST := preload("res://scenes/visual/shaders/focus_post.gdshader")
const GridWall := preload("res://scenes/visual/grid_wall.gd")
const SIMPLE_SKY := preload("res://sky/simple_sky.gdshader")
var _simple_sky: ShaderMaterial = null


## True, kun peli pyörii Compatibility-renderöijällä (web / .web-asetus).
static func _is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Compatibility valaisee samoilla arvoilla n. 1,7x kirkkaammin (sRGB-tilan valaistus),
## joten valot himmennetään siellä, jotta ilme vastaa Forward+/Mobile-versiota.
static func _light_scale() -> float:
	return 0.6 if _is_compatibility() else 1.0
const SOFT_OUTLINE := preload("res://scenes/visual/shaders/soft_outline.gdshader")
## Syvyyssumun enimmäisvoimakkuus kaukana (päivä / yö-teemat).
const FOG_MAX_DAY := 0.6
const FOG_MAX_NIGHT := 0.4
## Sumu alkaa näin monta metriä pelitason takaa ja on täysi näin kaukana sen takana.
const FOG_START_BEHIND := 6.0
const FOG_FULL_BEHIND := 110.0

var _fog_env: Environment = null
var _focus_material: ShaderMaterial = null
var _outline_material: ShaderMaterial = null
var _block_outline_mats: Dictionary = {}
## Palikoiden ääriviivan paksuus (m).
const BLOCK_OUTLINE := 0.05
const Progress := preload("res://scenes/ui/progress_store.gd")

## Nykyinen teema ja kentän numero (HUD ja valikot lukevat nämä).
var current_theme: String = "meadow"
var current_level_number: int = 0
## Kentän indeksi (0-pohjainen), jonka valikko viimeksi käynnisti. Valikko asettaa tämän.
var current_level_index: int = -1
## Kaadetuista apinoista kertyneet pisteet tällä kentällä (HUD ja tulosruutu näyttävät).
var current_score: int = 0

var _menu_diorama: Node3D = null
var _clouds: Array[Node3D] = []
var _spinners: Array[Array] = []
var _day_sky: Material = null
var _menu_time: float = 0.0
var _dot_texture: GradientTexture2D = null


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	_after_start.call_deferred()


func _after_start() -> void:
	for i in 3:
		await get_tree().process_frame
	if _find_level() == null:
		_show_menu_diorama()


func _process(delta: float) -> void:
	for cloud in _clouds:
		if is_instance_valid(cloud):
			var speed: float = cloud.get_meta("speed", 0.4)
			cloud.position.x += speed * delta
			if cloud.position.x > 90.0:
				cloud.position.x = -90.0
	for entry in _spinners:
		var node := entry[0] as Node3D
		if is_instance_valid(node):
			node.rotate(entry[1] as Vector3, float(entry[2]) * delta)
			if entry.size() > 3:
				node.position.y = float(entry[3]) + sin(Time.get_ticks_msec() * 0.001 * float(entry[4])) * 0.3

	if _menu_diorama != null and is_instance_valid(_menu_diorama):
		_menu_time += delta
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			cam.global_position = Vector3(2.5 + sin(_menu_time * 0.12) * 1.6, 5.2 + sin(_menu_time * 0.2) * 0.25, 22.0)
			cam.look_at(Vector3(2.5, 3.6, 0.0))

	_update_focus()


# --- Pelialueen korostus: syvyyssumu, etualan tummennus, ääriviivat ---------------

## Pitää sumun alun ja etuala/tausta-efektin kameran etäisyydessä pelitasosta (z = 0).
func _update_focus() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var forward := -cam.global_transform.basis.z
	var depth := 30.0
	if absf(forward.z) > 0.05:
		depth = clampf(-cam.global_position.z / forward.z, 5.0, 200.0)
	if _fog_env != null:
		_fog_env.fog_depth_begin = depth + FOG_START_BEHIND
		_fog_env.fog_depth_end = depth + FOG_FULL_BEHIND
	var post := cam.get_node_or_null("FocusPost") as MeshInstance3D
	if post == null:
		if _focus_material == null:
			_focus_material = ShaderMaterial.new()
			_focus_material.shader = FOCUS_POST
			# Piirretään ensimmäisenä läpinäkyvistä: jää, partikkelit ym. tulevat sen päälle
			# (ruutukuva otetaan ennen läpinäkyviä, joten muuten ne katoaisivat).
			_focus_material.render_priority = Material.RENDER_PRIORITY_MIN
		post = MeshInstance3D.new()
		post.name = "FocusPost"
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		post.mesh = quad
		post.material_override = _focus_material
		post.extra_cull_margin = 16384.0
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cam.add_child(post)
	_focus_material.set_shader_parameter("focus_depth", depth)


## Palikan ääriviiva: samanmuotoinen laatikko, joka on joka sivulta BLOCK_OUTLINE metriä
## isompi ja piirretään nurinpäin (vain takapinnat) -> siisti, tasapaksu reunus.
## Venytetyissä palikoissa koko lasketaan akselikohtaisesti, jotta viiva on joka sivulla
## yhtä paksu.
func _add_box_outline(block_mesh: MeshInstance3D, ice: bool) -> void:
	if block_mesh == null or block_mesh.get_node_or_null("Outline") != null:
		return
	var s := block_mesh.global_transform.basis.get_scale()
	var w := Vector3(BLOCK_OUTLINE / maxf(s.x, 0.001), BLOCK_OUTLINE / maxf(s.y, 0.001), BLOCK_OUTLINE / maxf(s.z, 0.001))
	# Sama muoto, joka sivulta w verran isompi.
	var shape: Mesh = null
	var src := block_mesh.mesh
	if src is BoxMesh:
		var b := BoxMesh.new()
		b.size = (src as BoxMesh).size + w * 2.0
		shape = b
	elif src is CylinderMesh:
		var c := src as CylinderMesh
		var cyl := CylinderMesh.new()
		cyl.top_radius = c.top_radius + w.x
		cyl.bottom_radius = c.bottom_radius + w.x
		cyl.height = c.height + w.y * 2.0
		cyl.radial_segments = c.radial_segments
		cyl.rings = c.rings
		shape = cyl
	elif src is SphereMesh:
		var sp := src as SphereMesh
		var sph := SphereMesh.new()
		sph.radius = sp.radius + w.x
		sph.height = sp.height + w.y * 2.0
		sph.radial_segments = sp.radial_segments
		sph.rings = sp.rings
		shape = sph
	elif src is CapsuleMesh:
		var cp := src as CapsuleMesh
		var cap := CapsuleMesh.new()
		cap.radius = cp.radius + w.x
		cap.height = cp.height + w.y * 2.0
		shape = cap
	if shape == null:
		return
	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.mesh = shape
	outline.material_override = _block_outline_material(ice)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	block_mesh.add_child(outline)


func _block_outline_material(ice: bool) -> StandardMaterial3D:
	var key := "ice" if ice else "solid"
	if _block_outline_mats.has(key):
		return _block_outline_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.disable_receive_shadows = true
	# Jää on läpinäkyvä: sen reunus on vaalean sininen, ettei sisus näytä tummalta.
	m.albedo_color = Color("2f6fa8") if ice else Color(0.16, 0.08, 0.05)
	_block_outline_mats[key] = m
	return m


## Pehmeä ääriviiva apinoille ja palikoille, jotta ammuttavat kohteet erottuvat.
func _apply_outlines() -> void:
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = SOFT_OUTLINE
	# Palikoille oma ääriviiva: samanmuotoinen, hieman isompi tumma laatikko.
	for node in get_tree().get_nodes_in_group(&"destructibles"):
		var block_mesh := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if block_mesh != null:
			_add_box_outline(block_mesh, ArtStyle.block_kind(node) == "ice")
	# Dynamiitit: tikut, nauha ja sytytyslanka saavat saman tyylisen reunuksen.
	for node in get_tree().get_nodes_in_group(&"dynamite"):
		for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
			if mesh_node.name != &"Outline":
				_add_box_outline(mesh_node as MeshInstance3D, false)
	# Apinoille "inverted hull" -viiva (pyöreille muodoille se toimii hyvin).
	for group in [&"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh_node as MeshInstance3D
				# Pomon mulkosilmät ja kieli saavat jäädä ilman viivaa.
				if mi.name.begins_with("Silly_") or mi.get_parent().name.begins_with("Silly_"):
					continue
				mi.material_overlay = _outline_material


# --- Level detection ----------------------------------------------------------

func _game_root() -> Node:
	return get_tree().current_scene


func _find_level() -> Node:
	var root := _game_root()
	return root.get_node_or_null("CurrentLevel") if root != null else null


func _on_node_added(node: Node) -> void:
	if node.name == &"CurrentLevel" and node.get_parent() == _game_root():
		_dress_level.call_deferred(node)


func _on_level_exiting() -> void:
	_maybe_show_menu.call_deferred()


func _maybe_show_menu() -> void:
	await get_tree().process_frame
	if _find_level() == null:
		_show_menu_diorama()


func _level_number(level: Node) -> int:
	var regex := RegEx.new()
	regex.compile("(\\d+)")
	var m := regex.search(level.scene_file_path.get_file())
	if m != null:
		return int(m.get_string(1))
	return current_level_index + 1


# --- Dressing a level -----------------------------------------------------------

func _dress_level(level: Node) -> void:
	if not is_instance_valid(level) or not level.is_inside_tree():
		return
	_hide_menu_diorama()
	_clouds.clear()
	_spinners.clear()

	var number := _level_number(level)
	current_score = 0
	var ground := "space"
	if level.get_node_or_null("GroundPlains") != null:
		ground = "plains"
	elif level.get_node_or_null("GroundSnowy") != null:
		ground = "snow"
	var theme := ArtStyle.theme_for_level(number, ground)
	current_theme = theme
	current_level_number = number
	if not level.tree_exiting.is_connected(_on_level_exiting):
		level.tree_exiting.connect(_on_level_exiting)

	_apply_environment(theme)
	# Ääriviivat vasta kun pomot ym. ovat rakentaneet osansa (_ready).
	get_tree().create_timer(0.1).timeout.connect(_apply_outlines)
	var dressing := Node3D.new()
	dressing.name = "VisualDressing"
	level.add_child(dressing)
	# Neonruudukko pelialueen takana, teeman reunavalon värinen.
	var grid := GridWall.new()
	grid.name = "GridWall"
	var rim: Array = ArtStyle.lighting_for(theme).get("rim", [])
	if not rim.is_empty():
		grid.color = rim[0]
	dressing.add_child(grid)

	_build_backdrop(dressing, theme, ground != "space")
	_skin_ground(level, theme)
	_skin_platforms(level, theme)
	_hide_walls(level)
	_skin_blocks(level)
	_skin_enemies(level)
	_skin_wells(level)
	_skin_slingshot(level)
	_add_ambient_particles(dressing, theme)
	var lname := ArtStyle.level_name(number)
	_show_banner(number, lname if lname != "" else String(ArtStyle.THEMES[theme]["title"]))
	level_dressed.emit(number, theme)


# --- Environment ------------------------------------------------------------------

func _apply_environment(theme: String) -> void:
	var t: Dictionary = ArtStyle.THEMES[theme]
	var root := _game_root()
	if root == null:
		return
	var env_nodes := root.find_children("*", "WorldEnvironment", true, false)
	if not env_nodes.is_empty():
		var env := (env_nodes[0] as WorldEnvironment).environment
		if env.sky != null:
			if _day_sky == null:
				_day_sky = env.sky.sky_material
			var sky_mat := (NIGHT_SKY if bool(t["night"]) else _day_sky) as ShaderMaterial
			# Compatibility (web) ei aja tyyliteltyä taivasta -> kevyt korvaava taivas.
			if _is_compatibility():
				if _simple_sky == null:
					_simple_sky = ShaderMaterial.new()
					_simple_sky.shader = SIMPLE_SKY
				sky_mat = _simple_sky
				sky_mat.set_shader_parameter("stars_intensity", 3.0 if bool(t["night"]) else 0.0)
			env.sky.sky_material = sky_mat
			if sky_mat != null:
				sky_mat.set_shader_parameter("top_color", t["sky_top"])
				sky_mat.set_shader_parameter("bottom_color", t["sky_bottom"])
				sky_mat.set_shader_parameter("sun_scatter", t["sun_scatter"])
				if bool(t["night"]):
					sky_mat.set_shader_parameter("clouds_density", 0.0)
					sky_mat.set_shader_parameter("stars_intensity", 3.0)
		if t.has("background"):
			env.background_mode = Environment.BG_COLOR
			env.background_color = t["background"]
		else:
			env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = t["ambient"]
		# Täyttö- ja reunavalot tuovat lisävaloa, joten tasainen ambient-valo on hillitympi:
		# varjot jäävät syvemmiksi ja muodot erottuvat.
		env.ambient_light_energy = float(t["ambient_energy"]) * 0.8 * _light_scale()
		# Teeman oma tyylitelty "valokalusto" (ArtStyle.LIGHTING).
		var rig := ArtStyle.lighting_for(theme)
		var glow: Array = rig["glow"]
		var grade: Array = rig["grade"]
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = float(rig["exposure"])
		env.tonemap_white = 1.0
		env.glow_enabled = true
		env.glow_intensity = float(glow[0])
		env.glow_bloom = float(glow[1])
		env.glow_hdr_threshold = float(glow[2])
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.fog_enabled = true
		# Syvyyssumu: alkaa vasta pelialueen takaa (päivitetään _process():ssa kameran
		# mukaan), joten pelialue pysyy terävänä ja tausta häipyy horisontin väriin.
		# Sumun väri on hieman haalistettu -> taustan värit hillitympiä.
		var key: Array = rig["key"]
		var haze := (t["fog"] as Color).lerp(t["sky_bottom"], 0.35).lerp(key[0], 0.12)
		var haze_gray := haze.get_luminance()
		env.fog_light_color = haze.lerp(Color(haze_gray, haze_gray, haze_gray), 0.15)
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.0
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_density = FOG_MAX_NIGHT if bool(t["night"]) else FOG_MAX_DAY
		env.fog_depth_curve = 1.6
		env.fog_sky_affect = 0.0
		_fog_env = env
		env.adjustment_enabled = true
		env.adjustment_saturation = float(rig["saturation"])
		env.adjustment_contrast = float(rig["contrast"])
		env.adjustment_brightness = 1.0
		# Väriluokittelu-tekstuuri latisti taivaan värit, joten tunnelma tehdään valoilla.
		env.adjustment_color_correction = null

	var sky_root := root.get_node_or_null("Sky")
	if sky_root != null and "density_min" in sky_root:
		var clouds := float(t["clouds"])
		sky_root.set("animate_density", clouds > 0.0)
		sky_root.set("density_min", clouds * 0.7)
		sky_root.set("density_max", minf(clouds * 1.25, 1.0))
		sky_root.set("density", clouds)

	var lights := root.find_children("*", "DirectionalLight3D", true, false)
	if not lights.is_empty():
		var light: DirectionalLight3D = null
		for node in lights:
			if not String(node.name).begins_with("Style"):
				light = node as DirectionalLight3D
				break
		if light == null:
			return
		var rig := ArtStyle.lighting_for(theme)
		var key: Array = rig["key"]
		light.rotation_degrees = key[2]
		light.light_color = key[0]
		light.light_energy = float(key[1]) * _light_scale()
		light.shadow_enabled = bool(Progress.get_setting("shadows", true))
		light.shadow_blur = 2.0
		light.shadow_opacity = 0.72
		light.directional_shadow_max_distance = 70.0
		# Lisävalot: värillinen täyttövalo, takaa tuleva reunavalo ja valinnainen alahehku.
		var parent := light.get_parent()
		# Täyttövalo tulee kameran puolelta auringon vastakkaiselta sivulta, jotta se
		# valaisee ne pinnat, jotka pelaaja näkee (aurinko oikealta -> täyttö vasemmalta).
		var fill: Array = rig.get("fill", []).duplicate()
		if not fill.is_empty():
			var sun_rot: Vector3 = key[2]
			fill[2] = Vector3((fill[2] as Vector3).x, -sun_rot.y - 15.0, 0.0)
			fill[1] = float(fill[1]) * 0.85
		_style_light(parent, "StyleFill", fill)
		_style_light(parent, "StyleRim", rig.get("rim", []))
		_style_light(parent, "StyleUnder", rig.get("under", []))


## Luo tai päivittää varjottoman lisävalon. Tyhjä `spec` sammuttaa valon.
func _style_light(parent: Node, light_name: String, spec: Array) -> void:
	var l := parent.get_node_or_null(light_name) as DirectionalLight3D
	if spec.is_empty():
		if l != null:
			l.visible = false
		return
	if l == null:
		l = DirectionalLight3D.new()
		l.name = light_name
		l.shadow_enabled = false
		# Ei vaikuta taivaan aurinkokiekkoon.
		l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		parent.add_child(l)
	l.visible = true
	l.light_color = spec[0]
	l.light_energy = float(spec[1]) * _light_scale()
	l.rotation_degrees = spec[2]
	l.light_specular = 0.6 if light_name == "StyleRim" else 0.2


# --- Backdrop ---------------------------------------------------------------------

func _build_backdrop(parent: Node3D, theme: String, land: bool) -> void:
	var t: Dictionary = ArtStyle.THEMES[theme]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme)
	var backdrop: String = t.get("backdrop", "land" if land else "space")
	if backdrop == "space" or (not land and backdrop != "sky"):
		_build_space_backdrop(parent, theme, rng)
		return
	if backdrop == "sky":
		_build_sky_backdrop(parent, theme, rng)
		return

	# Water / frozen lake / lava sea around the islands.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(320.0, 170.0)
	plane.subdivide_width = 64
	plane.subdivide_depth = 34
	water.mesh = plane
	water.material_override = ArtStyle.lava_material() if backdrop == "volcano" else ArtStyle.water_material(theme)
	water.position = Vector3(0.0, -2.6, -40.0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(water)

	# Meadow strip behind the play area so the world continues backwards.
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(150.0, 4.0, 11.0)
	slab.mesh = box
	slab.material_override = ArtStyle.terrain_material(theme, 0.25, 0.08, "slab")
	slab.position = Vector3(0.0, 0.25 - 2.0, -8.3)
	parent.add_child(slab)

	# Rolling hills and mountains in three layers (fog fades the far ones).
	var hills: Array = t["hills"]
	var mountains := bool(t["mountains"])
	var layers := [
		[-15.0, 14.0, 5.0, 0.1, 0],
		[-32.0, 20.0, 11.0, 0.3, 1],
		[-62.0, 28.0, 24.0 if mountains else 15.0, 0.85 if mountains else 0.4, 2],
	]
	if theme == "canyon":
		layers = [[-62.0, 28.0, 14.0, 0.2, 2]]
	elif backdrop == "cave":
		layers = [[-16.0, 10.0, 16.0, 0.9, 0], [-28.0, 14.0, 26.0, 0.9, 1]]
	for layer in layers:
		var i: int = layer[4]
		var c: Color = hills[i]
		var ridge := MeshInstance3D.new()
		var snow_line := 0.6 if (mountains and i == 2) else (0.82 if mountains and i == 1 else 2.0)
		ridge.mesh = Props.ridge_mesh(-130.0, 130.0, layer[1], layer[2], layer[3], float(i) * 7.3 + rng.randf(), c.darkened(0.18), c.lightened(0.12), snow_line)
		ridge.material_override = ArtStyle.soft_material(Color.WHITE, Color.WHITE, true)
		ridge.position = Vector3(0.0, -2.6, layer[0])
		ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(ridge)

	if backdrop == "cave":
		_build_cave_extras(parent, theme, rng)
	elif backdrop == "volcano":
		_build_volcano_extras(parent, rng)

	# Puffy 3D clouds drifting slowly (dark ash clouds at the volcano, none in the cave).
	var cloud_mat := ArtStyle.soft_material(Color("dfe8f5"), Color(1.12, 1.12, 1.12), false, 3.0, 13.0, 0.15)
	if backdrop == "volcano":
		cloud_mat = ArtStyle.soft_material(Color("4a3a3e"), Color("7a5a58"), false, 3.0, 13.0, 0.0)
	var cloud_count := 8 if float(t["clouds"]) > 0.3 else 5
	if backdrop == "cave":
		cloud_count = 0
	for i in cloud_count:
		var cloud := MeshInstance3D.new()
		cloud.mesh = Props.cloud_mesh(i % 4 + 1)
		cloud.material_override = cloud_mat
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(1.6, 3.2)
		cloud.scale = Vector3(s, s * 0.8, s)
		cloud.position = Vector3(rng.randf_range(-90.0, 90.0), rng.randf_range(13.0, 22.0), rng.randf_range(-48.0, -80.0))
		cloud.set_meta("speed", rng.randf_range(0.25, 0.7))
		parent.add_child(cloud)
		_clouds.append(cloud)

	_scatter_theme_props(parent, theme, rng)


func _build_space_backdrop(parent: Node3D, theme: String, rng: RandomNumberGenerator) -> void:
	var nebula: Array = ArtStyle.THEMES[theme]["nebula"]
	# Big soft nebula glows far away.
	for i in 4:
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(90.0, 150.0), rng.randf_range(60.0, 100.0))
		glow.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = _soft_dot()
		var c: Color = nebula[i % 2]
		mat.albedo_color = Color(c.r, c.g, c.b, 0.22)
		mat.disable_fog = true
		glow.material_override = mat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(rng.randf_range(-70.0, 70.0), rng.randf_range(-10.0, 30.0), -150.0 - float(i) * 5.0)
		glow.rotation.z = rng.randf() * TAU
		parent.add_child(glow)

	# Decorative planets, one with a ring.
	var planet_colors := [Color("ff8a5c"), Color("5cc8ff"), Color("c58aff")]
	for i in 3:
		var planet := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 32
		sphere.rings = 16
		planet.mesh = sphere
		var pc: Color = planet_colors[(i + hash(theme)) % 3]
		planet.material_override = ArtStyle.planet_material(pc.darkened(0.45).lerp(Color("2a1f4a"), 0.3), float(i) * 5.1, 0.02)
		var r: float = [26.0, 12.0, 7.0][i]
		planet.scale = Vector3.ONE * r
		var spots: Array[Vector3] = [Vector3(-150.0, 70.0, -260.0), Vector3(150.0, -30.0, -230.0), Vector3(60.0, 85.0, -280.0)]
		planet.position = spots[i]
		planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(planet)
		_spinners.append([planet, Vector3.UP, 0.03])
		if i == 1:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 1.35
			torus.outer_radius = 2.0
			torus.rings = 48
			torus.ring_segments = 4
			ring.mesh = torus
			ring.material_override = ArtStyle.flat_material(Color(0.6, 0.5, 0.45, 0.45), 0.6, 0.0)
			ring.scale = Vector3(1.0, 0.04, 1.0)
			ring.rotation_degrees = Vector3(18.0, 0.0, 12.0)
			planet.add_child(ring)

	# Floating asteroids (slowly tumbling) around the play area.
	var rock_mat := ArtStyle.soft_material(Color("6f6788"), Color("a59cc4"), false, 2.0, -1.0)
	for i in 16:
		var rock := MeshInstance3D.new()
		rock.mesh = Props.asteroid_mesh(i % 5 + 10)
		rock.material_override = rock_mat
		var s := rng.randf_range(0.3, 1.8)
		rock.scale = Vector3.ONE * s
		var x := rng.randf_range(-45.0, 50.0)
		var z := rng.randf_range(-9.0, -38.0)
		var y := rng.randf_range(-9.0, 16.0)
		rock.position = Vector3(x, y, z)
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(rock)
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		_spinners.append([rock, axis, rng.randf_range(0.1, 0.5), y, rng.randf_range(0.3, 0.7)])


## Luola: katto tippukivineen, lattian stalagmiitit, hehkuvat kristallit ja
## lämpimät soihtuvalot pelialueen lähellä.
func _build_cave_extras(parent: Node3D, theme: String, rng: RandomNumberGenerator) -> void:
	var rock_mat := ArtStyle.soft_material(Color("2e2a3c"), Color("4a4460"), false, 12.0, -2.0)
	var ceiling := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(220.0, 4.0, 80.0)
	ceiling.mesh = box
	ceiling.material_override = rock_mat
	ceiling.position = Vector3(0.0, 21.0, -25.0)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ceiling)

	var hang := MultiMesh.new()
	hang.transform_format = MultiMesh.TRANSFORM_3D
	hang.mesh = Props.spike_mesh(false)
	hang.instance_count = 46
	for i in 46:
		var s := rng.randf_range(0.5, 1.4)
		var x := rng.randf_range(-70.0, 70.0)
		var z := rng.randf_range(-40.0, -3.0) if i % 3 != 0 else rng.randf_range(-3.0, 4.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.6), s))
		hang.set_instance_transform(i, Transform3D(basis, Vector3(x, 19.2, z)))
	var hang_i := MultiMeshInstance3D.new()
	hang_i.multimesh = hang
	hang_i.material_override = rock_mat
	hang_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(hang_i)

	var up := MultiMesh.new()
	up.transform_format = MultiMesh.TRANSFORM_3D
	up.mesh = Props.spike_mesh(true)
	up.instance_count = 24
	for i in 24:
		var s := rng.randf_range(0.3, 0.8)
		up.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * rng.randf_range(0.8, 1.5), s)), Vector3(_side_x(rng), 0.2, rng.randf_range(-5.0, -13.0))))
	var up_i := MultiMeshInstance3D.new()
	up_i.multimesh = up
	up_i.material_override = rock_mat
	parent.add_child(up_i)

	# Warm torches and cool crystal light so the play area reads clearly.
	var lights := [[Vector3(-9.0, 4.5, 3.0), Color("ffb36a"), 1.6], [Vector3(6.0, 7.0, 4.0), Color("8fd8ff"), 1.4], [Vector3(16.0, 4.0, 3.0), Color("c08aff"), 1.2]]
	for l in lights:
		var omni := OmniLight3D.new()
		omni.position = l[0]
		omni.light_color = l[1]
		omni.light_energy = l[2]
		omni.omni_range = 16.0
		omni.shadow_enabled = false
		parent.add_child(omni)


## Tulivuori: savuava kartio taustalla ja hehkuvat laavavirrat.
func _build_volcano_extras(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var volcano := MeshInstance3D.new()
	volcano.mesh = Props.volcano_mesh()
	volcano.position = Vector3(rng.randf_range(-48.0, -30.0) if rng.randf() < 0.5 else rng.randf_range(38.0, 55.0), -2.6, -80.0)
	volcano.scale = Vector3(1.6, 1.8, 1.6)
	volcano.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(volcano)
	var light := OmniLight3D.new()
	light.light_color = Color("ff6a2a")
	light.light_energy = 3.0
	light.omni_range = 40.0
	light.position = volcano.position + Vector3(0, 38.0, 6.0)
	parent.add_child(light)

	# Smoke plume.
	var smoke := GPUParticles3D.new()
	smoke.amount = 26
	smoke.lifetime = 9.0
	smoke.preprocess = 9.0
	smoke.position = volcano.position + Vector3(0, 37.0, 0)
	smoke.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 60, 80))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(9.0, 9.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	smoke.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.3, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0.6, 0.2, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(0.35, 0.25, 0.25, 0.0), Color(0.3, 0.22, 0.22, 0.6), Color(0.4, 0.32, 0.32, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	smoke.process_material = pm
	parent.add_child(smoke)
	smoke.emitting = true


## Taivaansaaret: pilvimeri alapuolella ja kaukaisia leijuvia saaria.
func _build_sky_backdrop(parent: Node3D, theme: String, rng: RandomNumberGenerator) -> void:
	# Teema voi antaa pilvimerelle oman värin (apokalypsin myrskypilvet).
	var cloud_col: Color = ArtStyle.THEMES[theme].get("cloud_sea", Color("c9d8ee"))
	var cloud_mat := ArtStyle.soft_material(cloud_col, Color(1.08, 1.08, 1.08), false, 4.0, -12.0, 0.0)
	var sea := MultiMesh.new()
	sea.transform_format = MultiMesh.TRANSFORM_3D
	sea.mesh = Props.cloud_mesh(2)
	sea.instance_count = 70
	for i in 70:
		var s := rng.randf_range(3.0, 6.0)
		var pos := Vector3(rng.randf_range(-110.0, 110.0), rng.randf_range(-13.0, -10.0), rng.randf_range(-90.0, 12.0))
		sea.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.5, s)), pos))
	var sea_i := MultiMeshInstance3D.new()
	sea_i.multimesh = sea
	sea_i.material_override = cloud_mat
	sea_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sea_i)

	var island_mat := ArtStyle.terrain_material(theme, -1000.0, 0.08, "isle")
	var tree := Props.kit_mesh(KIT % "tree")
	for i in 7:
		var isle := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 1.0
		cone.bottom_radius = 0.15
		cone.height = 1.6
		cone.radial_segments = 9
		isle.mesh = cone
		isle.material_override = island_mat
		var s := rng.randf_range(2.0, 5.0)
		isle.scale = Vector3(s, s, s * 0.8)
		var y := rng.randf_range(-4.0, 14.0)
		var pos := Vector3(_side_x(rng) * 1.6, y, rng.randf_range(-30.0, -70.0))
		isle.position = pos
		isle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(isle)
		_spinners.append([isle, Vector3.UP, 0.02, y, rng.randf_range(0.2, 0.4)])
		if tree["mesh"] != null:
			var tree_node := MeshInstance3D.new()
			tree_node.mesh = tree["mesh"]
			isle.add_child(tree_node)
			tree_node.position = Vector3(0, 0.8, 0)
			tree_node.scale = Vector3.ONE * (0.9 / maxf((tree["aabb"] as AABB).size.y, 0.01))
	for i in 7:
		var cloud := MeshInstance3D.new()
		cloud.mesh = Props.cloud_mesh(i % 4 + 1)
		cloud.material_override = cloud_mat
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(1.8, 3.2)
		cloud.scale = Vector3(s, s * 0.8, s)
		cloud.position = Vector3(rng.randf_range(-90.0, 90.0), rng.randf_range(14.0, 22.0), rng.randf_range(-40.0, -70.0))
		cloud.set_meta("speed", rng.randf_range(0.3, 0.8))
		parent.add_child(cloud)
		_clouds.append(cloud)


func _scatter_theme_props(parent: Node3D, theme: String, rng: RandomNumberGenerator) -> void:
	var kind: String = ArtStyle.THEMES[theme]["props"]
	match kind:
		"meadow":
			_scatter_kit(parent, "tree", 9, Vector2(3.2, 4.4), rng, true)
			_scatter_kit(parent, "flowers", 34, Vector2(0.45, 0.6), rng)
			_scatter_kit(parent, "flowers-tall", 16, Vector2(0.8, 1.1), rng)
			_scatter_kit(parent, "grass", 40, Vector2(0.35, 0.5), rng)
			_scatter_kit(parent, "hedge", 6, Vector2(0.9, 1.1), rng, true)
			_scatter_kit(parent, "rocks", 6, Vector2(0.5, 0.8), rng)
			_front_tufts(parent, ["grass", "flowers"], rng)
		"forest":
			_scatter_kit(parent, "tree-pine", 24, Vector2(4.0, 6.0), rng, true)
			_scatter_kit(parent, "tree", 10, Vector2(3.4, 4.6), rng, true)
			_scatter_kit(parent, "mushrooms", 16, Vector2(0.4, 0.6), rng)
			_scatter_kit(parent, "plant", 12, Vector2(0.6, 0.9), rng)
			_scatter_kit(parent, "grass", 34, Vector2(0.35, 0.5), rng)
			_scatter_kit(parent, "rocks", 8, Vector2(0.5, 0.9), rng)
			_front_tufts(parent, ["grass", "mushrooms"], rng)
		"tropical":
			for i in 10:
				var palm := MeshInstance3D.new()
				palm.mesh = Props.palm_mesh(i % 4 + 1)
				var x := _side_x(rng)
				palm.position = Vector3(x, 0.25, rng.randf_range(-5.0, -12.5))
				palm.rotation.y = rng.randf() * TAU
				var s := rng.randf_range(0.9, 1.25)
				palm.scale = Vector3.ONE * s
				parent.add_child(palm)
			_scatter_kit(parent, "flowers", 16, Vector2(0.45, 0.6), rng)
			_scatter_kit(parent, "grass", 24, Vector2(0.35, 0.5), rng)
			_scatter_kit(parent, "rocks", 8, Vector2(0.5, 0.8), rng)
			_add_islets(parent, theme, rng)
			_front_tufts(parent, ["grass", "flowers"], rng)
		"canyon":
			var mesa_mat := ArtStyle.terrain_material(theme, -1000.0, 0.08, "mesa")
			for i in 8:
				var mesa := MeshInstance3D.new()
				mesa.mesh = Props.mesa_mesh(i + 3)
				mesa.material_override = mesa_mat
				var s := rng.randf_range(1.4, 2.4)
				mesa.scale = Vector3(s, s * rng.randf_range(0.9, 1.4), s)
				mesa.position = Vector3(rng.randf_range(-90.0, 90.0), -2.6, rng.randf_range(-45.0, -75.0))
				mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(mesa)
			for i in 9:
				var cactus := MeshInstance3D.new()
				cactus.mesh = Props.cactus_mesh(i % 3 + 1)
				cactus.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-5.0, -12.5))
				var s := rng.randf_range(0.8, 1.3)
				cactus.scale = Vector3.ONE * s
				cactus.rotation.y = rng.randf() * TAU
				parent.add_child(cactus)
			_scatter_kit(parent, "rocks", 12, Vector2(0.6, 1.1), rng)
			_scatter_kit(parent, "stones", 14, Vector2(0.3, 0.5), rng)
		"snow":
			_scatter_kit(parent, "tree-pine-snow", 20, Vector2(4.0, 5.8), rng, true)
			_scatter_kit(parent, "tree-snow", 10, Vector2(3.2, 4.2), rng, true)
			_scatter_kit(parent, "tree-pine-snow-small", 14, Vector2(1.6, 2.4), rng)
			_scatter_kit(parent, "rocks", 8, Vector2(0.5, 0.9), rng)
		"beach":
			for i in 8:
				var palm := MeshInstance3D.new()
				palm.mesh = Props.palm_mesh(i % 4 + 1)
				palm.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-5.0, -12.5))
				palm.rotation.y = rng.randf() * TAU
				palm.scale = Vector3.ONE * rng.randf_range(0.9, 1.3)
				parent.add_child(palm)
			for i in 6:
				var umbrella := MeshInstance3D.new()
				umbrella.mesh = Props.umbrella_mesh(i)
				umbrella.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-3.6, -7.0))
				umbrella.rotation.y = rng.randf_range(-0.6, 0.6)
				parent.add_child(umbrella)
			var lighthouse := MeshInstance3D.new()
			lighthouse.mesh = Props.lighthouse_mesh()
			lighthouse.position = Vector3(-42.0, -2.6, -34.0)
			parent.add_child(lighthouse)
			_scatter_kit(parent, "rocks", 5, Vector2(0.5, 0.9), rng)
			_scatter_kit(parent, "grass", 14, Vector2(0.35, 0.5), rng)
			_scatter_kit(parent, "flowers", 8, Vector2(0.4, 0.55), rng)
			_add_islets(parent, theme, rng)
		"cave":
			var crystal_mat := ArtStyle.flat_material(Color(0.45, 0.9, 1.0, 0.9), 0.1, 1.3)
			var crystal_mat2 := ArtStyle.flat_material(Color(0.8, 0.5, 1.0, 0.9), 0.1, 1.3)
			for i in 18:
				var crystal := MeshInstance3D.new()
				crystal.mesh = Props.crystal_mesh()
				crystal.material_override = crystal_mat if i % 2 == 0 else crystal_mat2
				crystal.scale = Vector3.ONE * rng.randf_range(1.5, 4.0)
				crystal.position = Vector3(_side_x(rng), 0.1, rng.randf_range(-4.5, -13.0))
				crystal.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
				crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(crystal)
			for i in 12:
				var mush := MeshInstance3D.new()
				mush.mesh = Props.glow_mushroom_mesh(Color("6fe8ff") if i % 3 else Color("ff7ad8"))
				mush.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-4.0, -12.0))
				mush.scale = Vector3.ONE * rng.randf_range(0.8, 2.2)
				parent.add_child(mush)
			_scatter_kit(parent, "rocks", 12, Vector2(0.6, 1.2), rng)
		"volcano":
			_scatter_kit(parent, "rocks", 16, Vector2(0.7, 1.4), rng, true)
			_scatter_kit(parent, "stones", 18, Vector2(0.3, 0.5), rng)
			var glow_mat := ArtStyle.flat_material(Color("ff6a1a"), 0.6, 2.5)
			for i in 10:
				var rock := MeshInstance3D.new()
				rock.mesh = Props.asteroid_mesh(i % 5 + 20)
				rock.material_override = ArtStyle.soft_material(Color("2c2224"), Color("5a3a34"), false, 2.0, 0.0)
				rock.scale = Vector3(rng.randf_range(0.8, 2.0), rng.randf_range(0.6, 1.6), rng.randf_range(0.8, 1.6))
				rock.position = Vector3(_side_x(rng), 0.3, rng.randf_range(-5.0, -12.0))
				parent.add_child(rock)
				var ember := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.18
				sphere.height = 0.36
				sphere.radial_segments = 8
				sphere.rings = 4
				ember.mesh = sphere
				ember.material_override = glow_mat
				ember.position = Vector3(0.0, 0.7, 0.4)
				rock.add_child(ember)
		"exo":
			var bulb_colors := [Color("6affc8"), Color("ffd84a"), Color("ff7ad8")]
			for i in 16:
				var plant := MeshInstance3D.new()
				plant.mesh = Props.alien_plant_mesh(i % 5 + 1, bulb_colors[i % 3])
				plant.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-4.5, -12.5))
				plant.rotation.y = rng.randf() * TAU
				plant.scale = Vector3.ONE * rng.randf_range(0.9, 1.8)
				parent.add_child(plant)
			var spire_mat := ArtStyle.flat_material(Color(0.42, 1.0, 0.78, 0.85), 0.1, 0.9)
			for i in 8:
				var spire := MeshInstance3D.new()
				spire.mesh = Props.crystal_mesh()
				spire.material_override = spire_mat
				spire.scale = Vector3(2.0, rng.randf_range(5.0, 9.0), 2.0)
				spire.position = Vector3(rng.randf_range(-80.0, 80.0), -2.6, rng.randf_range(-20.0, -45.0))
				spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(spire)
			# Two big moons in the sky.
			for i in 2:
				var moon := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 1.0
				sphere.height = 2.0
				sphere.radial_segments = 32
				sphere.rings = 16
				moon.mesh = sphere
				moon.material_override = ArtStyle.planet_material([Color("ffb37a"), Color("8fd8ff")][i], float(i) * 7.0 + 2.0, 0.2)
				moon.scale = Vector3.ONE * [30.0, 12.0][i]
				moon.position = [Vector3(-110.0, 70.0, -230.0), Vector3(90.0, 55.0, -200.0)][i]
				moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(moon)
		"sky":
			pass
		"desert":
			_scatter_desert(parent, theme, rng)
		"candy":
			_scatter_candy(parent, rng)
		"apocalypse":
			_scatter_apocalypse(parent, rng)
		"glacier":
			_scatter_kit(parent, "tree-pine-snow", 9, Vector2(4.0, 5.5), rng, true)
			_scatter_kit(parent, "rocks", 10, Vector2(0.5, 0.9), rng)
			var crystal_mat := ArtStyle.flat_material(Color(0.62, 0.88, 1.0, 0.88), 0.1, 0.45)
			for i in 14:
				var crystal := MeshInstance3D.new()
				crystal.mesh = Props.crystal_mesh()
				crystal.material_override = crystal_mat
				var s := rng.randf_range(2.0, 5.0)
				crystal.scale = Vector3.ONE * s
				crystal.position = Vector3(_side_x(rng), 0.1, rng.randf_range(-6.0, -13.0))
				crystal.rotation.y = rng.randf() * TAU
				crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(crystal)


## Aavikko: pyramidit horisontissa, mesat, kaktukset ja kivet.
func _scatter_desert(parent: Node3D, theme: String, rng: RandomNumberGenerator) -> void:
	var sand_mat := ArtStyle.soft_material(Color("e8b066"), Color("ffe0a8"), false, 14.0, -2.0)
	for i in 4:
		var pyr := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.0
		cone.height = 1.0
		cone.radial_segments = 4
		cone.rings = 1
		pyr.mesh = cone
		pyr.material_override = sand_mat
		var s := rng.randf_range(14.0, 26.0)
		pyr.scale = Vector3(s, s * 0.75, s)
		pyr.position = Vector3([-70.0, -30.0, 45.0, 85.0][i] + rng.randf_range(-8.0, 8.0), -2.6 + s * 0.375, rng.randf_range(-70.0, -95.0))
		pyr.rotation.y = PI * 0.25
		pyr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(pyr)
	var mesa_mat := ArtStyle.terrain_material(theme, -1000.0, 0.08, "mesa")
	for i in 4:
		var mesa := MeshInstance3D.new()
		mesa.mesh = Props.mesa_mesh(i + 7)
		mesa.material_override = mesa_mat
		var s := rng.randf_range(1.2, 2.0)
		mesa.scale = Vector3(s, s, s)
		mesa.position = Vector3(rng.randf_range(-90.0, 90.0), -2.6, rng.randf_range(-40.0, -60.0))
		mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesa)
	for i in 12:
		var cactus := MeshInstance3D.new()
		cactus.mesh = Props.cactus_mesh(i % 3 + 1)
		cactus.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-5.0, -12.5))
		cactus.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		cactus.rotation.y = rng.randf() * TAU
		parent.add_child(cactus)
	_scatter_kit(parent, "rocks", 10, Vector2(0.6, 1.1), rng)
	_scatter_kit(parent, "stones", 12, Vector2(0.3, 0.5), rng)


## Karkkimaa: tikkarit, karkkikepit, kumikarkit ja suklaakivet.
func _scatter_candy(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var colors := [Color("ff5aa8"), Color("ffd64a"), Color("66d0f1"), Color("9b6bff"), Color("70d52f"), Color("ff8a3d")]
	var stick_mat := ArtStyle.flat_material(Color("fff6e8"), 0.5)
	for i in 12:
		var root := Node3D.new()
		root.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-5.0, -13.0))
		var s := rng.randf_range(0.9, 1.8)
		root.scale = Vector3.ONE * s
		parent.add_child(root)
		var stick := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 2.4
		cyl.radial_segments = 8
		stick.mesh = cyl
		stick.material_override = stick_mat
		stick.position.y = 1.2
		root.add_child(stick)
		var candy := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.75
		disc.bottom_radius = 0.75
		disc.height = 0.22
		disc.radial_segments = 20
		candy.mesh = disc
		candy.material_override = ArtStyle.soft_material(colors[i % colors.size()], Color.WHITE)
		candy.rotation.x = PI * 0.5
		candy.position.y = 2.6
		root.add_child(candy)
		var swirl := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.32
		tor.outer_radius = 0.46
		tor.rings = 20
		tor.ring_segments = 8
		swirl.mesh = tor
		swirl.material_override = ArtStyle.flat_material(Color.WHITE, 0.4)
		swirl.rotation.x = PI * 0.5
		swirl.position = Vector3(0.0, 2.6, 0.12)
		root.add_child(swirl)
	# Kumikarkit (puolipallot).
	for i in 22:
		var drop := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.5
		sp.height = 1.0
		sp.is_hemisphere = true
		sp.radial_segments = 14
		sp.rings = 6
		drop.mesh = sp
		drop.material_override = ArtStyle.soft_material(colors[(i * 7) % colors.size()], Color.WHITE)
		drop.position = Vector3(_side_x(rng), 0.25, rng.randf_range(-3.5, -12.0))
		drop.scale = Vector3.ONE * rng.randf_range(0.5, 1.2)
		parent.add_child(drop)
	# Karkkikepit taustalla.
	var red := ArtStyle.flat_material(Color("ff4a5a"), 0.4)
	var white := ArtStyle.flat_material(Color("fff6f0"), 0.4)
	for i in 8:
		var cane := Node3D.new()
		cane.position = Vector3(rng.randf_range(-70.0, 80.0), -2.6, rng.randf_range(-25.0, -45.0))
		var s := rng.randf_range(2.5, 4.5)
		cane.scale = Vector3.ONE * s
		parent.add_child(cane)
		for j in 6:
			var seg := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.35
			c.bottom_radius = 0.35
			c.height = 1.0
			c.radial_segments = 10
			seg.mesh = c
			seg.material_override = red if j % 2 == 0 else white
			seg.position.y = 0.5 + float(j)
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cane.add_child(seg)
		var hook := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.6
		t.outer_radius = 1.3
		hook.mesh = t
		hook.material_override = red
		hook.rotation.x = PI * 0.5
		hook.position = Vector3(0.95, 6.0, 0.0)
		hook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cane.add_child(hook)


## Apokalypsi: halkeillut kuu, leijuvat kivenjärkäleet ja kultaiset kristallit.
func _scatter_apocalypse(parent: Node3D, rng: RandomNumberGenerator) -> void:
	for half in 2:
		var moon := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		sp.is_hemisphere = true
		sp.radial_segments = 32
		sp.rings = 12
		moon.mesh = sp
		moon.material_override = ArtStyle.planet_material(Color("d8c0a8"), 3.0 + float(half), 0.15)
		moon.scale = Vector3.ONE * 26.0
		moon.rotation = Vector3(0.0, 0.0, PI * 0.5 + float(half) * PI + 0.25)
		moon.position = Vector3(-60.0 + float(half) * 14.0, 62.0 - float(half) * 6.0, -220.0)
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(moon)
	var rock_mat := ArtStyle.soft_material(Color("3e2670"), Color("7a5ab0"), false, 4.0, -2.0)
	var gold := ArtStyle.flat_material(Color("ffd64a"), 0.3, 1.6)
	for i in 16:
		var rock := MeshInstance3D.new()
		rock.mesh = Props.asteroid_mesh(i % 6 + 30)
		rock.material_override = rock_mat
		var s := rng.randf_range(1.5, 6.0)
		rock.scale = Vector3(s, s * 0.7, s)
		rock.position = Vector3(rng.randf_range(-80.0, 90.0), rng.randf_range(-4.0, 30.0), rng.randf_range(-25.0, -70.0))
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(rock)
		_spinners.append([rock, Vector3.UP, rng.randf_range(-0.15, 0.15)])
		if i % 3 == 0:
			var c := MeshInstance3D.new()
			c.mesh = Props.crystal_mesh()
			c.material_override = gold
			c.position = Vector3(0.0, 0.6, 0.0)
			c.scale = Vector3.ONE * 0.5
			rock.add_child(c)


## X-koordinaatti taustarekvisiitalle: painottuu pelialueen sivuille, jotta
## rakennelmien takana ei ole sotkua.
func _side_x(rng: RandomNumberGenerator) -> float:
	if rng.randf() < 0.75:
		return rng.randf_range(-55.0, -6.0) if rng.randf() < 0.5 else rng.randf_range(17.0, 60.0)
	return rng.randf_range(-6.0, 17.0)


## Kitin malli (esim. "tree") MultiMeshinä takaniitylle. `tall` = pidä kauempana
## pelialueen takaa.
func _scatter_kit(parent: Node3D, kit_name: String, count: int, height: Vector2, rng: RandomNumberGenerator, tall: bool = false) -> void:
	var kit := Props.kit_mesh(KIT % kit_name)
	var mesh := kit["mesh"] as Mesh
	if mesh == null:
		return
	var aabb := kit["aabb"] as AABB
	var base_xf := kit["transform"] as Transform3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var x := _side_x(rng)
		var z := rng.randf_range(-4.2, -13.0)
		if tall and x > -8.0 and x < 18.0:
			x = rng.randf_range(-40.0, -9.0) if rng.randf() < 0.5 else rng.randf_range(19.0, 45.0)
		var s := rng.randf_range(height.x, height.y) / maxf(aabb.size.y, 0.01)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var origin := Vector3(x, 0.25 - aabb.position.y * s, z)
		mm.set_instance_transform(i, Transform3D(basis, origin) * base_xf)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tall else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## Pienet heinätupsut pelikentän etureunaan (vain sivuilla, ei rakennelmien edessä).
func _front_tufts(parent: Node3D, kits: Array, rng: RandomNumberGenerator) -> void:
	for kit_name in kits:
		var kit := Props.kit_mesh(KIT % kit_name)
		var mesh := kit["mesh"] as Mesh
		if mesh == null:
			continue
		var aabb := kit["aabb"] as AABB
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 14
		for i in 14:
			var x := rng.randf_range(-40.0, -11.0) if i % 2 == 0 else rng.randf_range(16.0, 40.0)
			var s := rng.randf_range(0.25, 0.4) / maxf(aabb.size.y, 0.01)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(basis, Vector3(x, 0.5 - aabb.position.y * s, rng.randf_range(0.6, 1.3))) * (kit["transform"] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


## Pieniä palmusaaria kauempana vedessä (trooppinen teema).
func _add_islets(parent: Node3D, theme: String, rng: RandomNumberGenerator) -> void:
	var mat := ArtStyle.terrain_material(theme, -1000.0, 0.08, "islet")
	for i in 4:
		var islet := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 1.0
		sphere.is_hemisphere = true
		sphere.radial_segments = 16
		sphere.rings = 6
		islet.mesh = sphere
		islet.material_override = mat
		var s := rng.randf_range(3.0, 6.0)
		islet.scale = Vector3(s * 1.4, s * 0.35, s)
		var pos := Vector3(rng.randf_range(-70.0, 70.0), -2.7, rng.randf_range(-24.0, -40.0))
		islet.position = pos
		parent.add_child(islet)
		var palm := MeshInstance3D.new()
		palm.mesh = Props.palm_mesh(i + 1)
		palm.position = pos + Vector3(0.0, s * 0.33, 0.0)
		palm.scale = Vector3.ONE * 1.3
		parent.add_child(palm)


func _soft_dot() -> GradientTexture2D:
	if _dot_texture != null:
		return _dot_texture
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	_dot_texture = GradientTexture2D.new()
	_dot_texture.gradient = g
	_dot_texture.fill = GradientTexture2D.FILL_RADIAL
	_dot_texture.fill_from = Vector2(0.5, 0.5)
	_dot_texture.fill_to = Vector2(1.0, 0.5)
	_dot_texture.width = 64
	_dot_texture.height = 64
	return _dot_texture


# --- Skinning the level's own nodes ----------------------------------------------------

func _skin_ground(level: Node, theme: String) -> void:
	for ground_name in ["GroundPlains", "GroundSnowy"]:
		var ground := level.get_node_or_null(ground_name)
		if ground == null:
			continue
		var material := ArtStyle.terrain_material(theme, 0.5, 0.05, "ground")
		for node in ground.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = material


## Avaruuden tasanteet: kelluvat kallioluodot hehkuvine kristalleineen.
## Törmäysmuoto ei muutu; vanhat laatikkoverkot piilotetaan.
func _skin_platforms(level: Node, theme: String) -> void:
	var platforms := level.get_node_or_null("Platforms")
	if platforms == null:
		return
	var crystal_color: Color = ArtStyle.THEMES[theme].get("crystal", ArtStyle.THEMES[theme].get("nebula", [Color("8fd8ff"), Color("8fd8ff")])[1])
	var crystal_mat := ArtStyle.flat_material(Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.9), 0.15, 1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for body in platforms.get_children():
		if not (body is StaticBody3D):
			continue
		var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var size := (shape_node.shape as BoxShape3D).size
		for child in body.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
		var top_y := (body as Node3D).global_position.y + size.y * 0.5
		var material := ArtStyle.terrain_material(theme, top_y, 0.06, "pf")
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(size.x, size.y, minf(size.z, 3.2))
		slab.mesh = box
		slab.material_override = material
		body.add_child(slab)
		var under := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 1.0
		cone.bottom_radius = 0.18
		cone.height = 2.4
		cone.radial_segments = 9
		cone.rings = 2
		under.mesh = cone
		under.material_override = material
		under.scale = Vector3(size.x * 0.5, 1.0, 1.55)
		under.position = Vector3(0.0, -size.y * 0.5 - 1.15, 0.0)
		body.add_child(under)
		for i in 3:
			var crystal := MeshInstance3D.new()
			crystal.mesh = Props.crystal_mesh()
			crystal.material_override = crystal_mat
			crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var sx := (float(i) - 1.0) * size.x * 0.28 + rng.randf_range(-0.2, 0.2)
			crystal.position = Vector3(sx, -size.y * 0.5 - rng.randf_range(0.3, 1.2), rng.randf_range(0.6, 1.2))
			crystal.rotation = Vector3(PI, rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
			crystal.scale = Vector3.ONE * rng.randf_range(0.8, 1.5)
			body.add_child(crystal)


func _hide_walls(level: Node) -> void:
	var walls := level.get_node_or_null("Walls")
	if walls == null:
		return
	for node in walls.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false


func _skin_blocks(level: Node) -> void:
	for node in level.find_children("*", "RigidBody3D", true, false):
		if not ("debris_color" in node) or not node.has_signal("broken"):
			continue
		var block := node as RigidBody3D
		var kind := ArtStyle.block_kind(block)
		var size := Vector3.ONE
		var shape_node := block.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			size = (shape_node.shape as BoxShape3D).size
		var mesh_node := block.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_node == null:
			continue
		if not (mesh_node.mesh is BoxMesh) or not (mesh_node.mesh as BoxMesh).size.is_equal_approx(size):
			var box := BoxMesh.new()
			box.size = size
			mesh_node.mesh = box
		mesh_node.material_override = ArtStyle.block_material(kind, size)
		block.connect("broken", _on_block_broken.bind(block, kind, size))
		block.connect("damaged", _on_block_damaged.bind(block, kind))


func _on_block_broken(block: Node3D, kind: String, size: Vector3) -> void:
	if is_instance_valid(block) and block.is_inside_tree():
		Vfx.block_break(_game_root(), block.global_position, kind, size)


func _on_block_damaged(_health: float, block: Node3D, kind: String) -> void:
	if not is_instance_valid(block) or not block.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now - int(block.get_meta("last_chip", 0)) < 180:
		return
	block.set_meta("last_chip", now)
	Vfx.block_chip(_game_root(), block.global_position, kind)


func _skin_enemies(level: Node) -> void:
	for node in level.find_children("*", "RigidBody3D", true, false):
		if not node.has_signal("died"):
			continue
		node.connect("died", _on_enemy_died.bind(node))
		# Gentle breathing so the monkeys feel alive.
		for child in node.get_children():
			if child is Node3D and not (child is CollisionShape3D):
				var model := child as Node3D
				var base := model.scale
				var tween := model.create_tween().set_loops()
				var d := randf_range(0.7, 0.95)
				tween.tween_property(model, "scale", Vector3(base.x * 1.03, base.y * 0.96, base.z * 1.03), d).set_trans(Tween.TRANS_SINE)
				tween.tween_property(model, "scale", base, d).set_trans(Tween.TRANS_SINE)
				break


func _on_enemy_died(points: int, enemy: Node3D) -> void:
	current_score += points
	if is_instance_valid(enemy) and enemy.is_inside_tree():
		Vfx.star_burst(_game_root(), enemy.global_position + Vector3(0.0, 0.8, 0.0), 14)


func _skin_wells(level: Node) -> void:
	var i := 0
	for node in level.find_children("*", "Node3D", true, false):
		if not node.has_method("get_pull_acceleration"):
			continue
		var color: Color = node.get("planet_color")
		var pulling := float(node.get("strength")) >= 0.0
		var planet := node.get_node_or_null("Planet") as MeshInstance3D
		if planet != null:
			planet.material_override = ArtStyle.planet_material(color, float(i) * 3.3 + 1.0)
			_spinners.append([planet, Vector3.UP, 0.25])
		var field := node.get_node_or_null("Field") as MeshInstance3D
		if field != null and field.visible:
			field.material_override = ArtStyle.field_material(color if pulling else Color(1.0, 0.4, 0.35), pulling)
		i += 1


func _skin_slingshot(level: Node) -> void:
	for node in level.find_children("*", "Node3D", true, false):
		if not node.is_in_group("slingshot"):
			continue
		var slingshot := node as Node3D
		var old := slingshot.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if old != null:
			old.visible = false
		var anchor := Vector3(0.0, 1.6, 0.0)
		var launch := slingshot.get_node_or_null("LaunchPoint") as Node3D
		if launch != null:
			anchor = launch.position
		var ground := -0.5
		var shape_node := slingshot.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			ground = shape_node.position.y - (shape_node.shape as BoxShape3D).size.y * 0.5
		var model := Props.build_slingshot(anchor, ground)
		model.set_script(SlingshotSkin)
		model.set("slingshot", slingshot)
		model.set("anchor_local", anchor)
		slingshot.add_child(model)


# --- Ambient particles -----------------------------------------------------------

func _add_ambient_particles(parent: Node3D, theme: String) -> void:
	var kind: String = ArtStyle.THEMES[theme]["particles"]
	if kind == "none":
		return
	var p := GPUParticles3D.new()
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -20, -20), Vector3(80, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	match kind:
		"snow":
			p.amount = 160
			p.lifetime = 9.0
			p.preprocess = 9.0
			p.position = Vector3(3.0, 15.0, -2.0)
			pm.emission_box_extents = Vector3(34.0, 0.5, 9.0)
			pm.gravity = Vector3(0.3, -1.6, 0.0)
			pm.initial_velocity_min = 0.0
			pm.initial_velocity_max = 0.4
			pm.scale_min = 0.07
			pm.scale_max = 0.15
			fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0)])
		"leaves":
			p.amount = 26
			p.lifetime = 10.0
			p.preprocess = 10.0
			p.position = Vector3(3.0, 12.0, -3.0)
			p.draw_pass_1 = Vfx._shard_mesh("leaf")
			pm.emission_box_extents = Vector3(32.0, 1.0, 6.0)
			pm.gravity = Vector3(0.5, -0.9, 0.0)
			pm.angular_velocity_min = -120.0
			pm.angular_velocity_max = 120.0
			pm.particle_flag_rotate_y = true
			pm.scale_min = 1.4
			pm.scale_max = 2.2
			fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		"dust":
			p.amount = 40
			p.lifetime = 8.0
			p.preprocess = 8.0
			p.position = Vector3(3.0, 3.0, -2.0)
			pm.emission_box_extents = Vector3(32.0, 3.0, 6.0)
			pm.direction = Vector3(1.0, 0.1, 0.0)
			pm.spread = 15.0
			pm.gravity = Vector3.ZERO
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.4
			pm.scale_min = 0.15
			pm.scale_max = 0.35
			fade.colors = PackedColorArray([Color(1, 0.9, 0.7, 0), Color(1, 0.9, 0.7, 0.5), Color(1, 0.9, 0.7, 0.5), Color(1, 0.9, 0.7, 0)])
		"stardust":
			p.amount = 24
			p.lifetime = 6.0
			p.preprocess = 6.0
			p.position = Vector3(3.0, 5.0, -4.0)
			pm.emission_box_extents = Vector3(36.0, 14.0, 8.0)
			pm.gravity = Vector3.ZERO
			pm.initial_velocity_min = 0.05
			pm.initial_velocity_max = 0.25
			pm.spread = 180.0
			pm.scale_min = 0.025
			pm.scale_max = 0.055
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = Vfx.star_texture()
			fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.9, 0.9, 1, 1), Color(0.9, 0.9, 1, 1), Color(1, 1, 1, 0)])
		"fireflies":
			p.amount = 40
			p.lifetime = 8.0
			p.preprocess = 8.0
			p.position = Vector3(3.0, 4.0, -4.0)
			pm.emission_box_extents = Vector3(30.0, 4.0, 3.0)
			pm.gravity = Vector3(0.0, 0.05, 0.0)
			pm.initial_velocity_min = 0.2
			pm.initial_velocity_max = 0.6
			pm.spread = 180.0
			pm.scale_min = 0.025
			pm.scale_max = 0.05
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fade.colors = PackedColorArray([Color(0.6, 1, 0.8, 0), Color(0.6, 1, 0.8, 1), Color(0.6, 1, 0.8, 1), Color(0.6, 1, 0.8, 0)])
		"embers":
			p.amount = 60
			p.lifetime = 6.0
			p.preprocess = 6.0
			p.position = Vector3(3.0, -1.0, -4.0)
			pm.emission_box_extents = Vector3(34.0, 1.0, 3.0)
			pm.direction = Vector3(0.2, 1.0, 0.0)
			pm.spread = 25.0
			pm.gravity = Vector3(0.4, 0.4, 0.0)
			pm.initial_velocity_min = 1.0
			pm.initial_velocity_max = 2.4
			pm.scale_min = 0.025
			pm.scale_max = 0.05
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fade.colors = PackedColorArray([Color(1, 0.6, 0.2, 0), Color(1, 0.55, 0.15, 1), Color(1, 0.3, 0.1, 0.8), Color(0.5, 0.1, 0.05, 0)])
		"spores":
			p.amount = 45
			p.lifetime = 9.0
			p.preprocess = 9.0
			p.position = Vector3(3.0, 4.0, -5.0)
			pm.emission_box_extents = Vector3(32.0, 5.0, 3.0)
			pm.gravity = Vector3(0.1, 0.15, 0.0)
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.4
			pm.spread = 180.0
			pm.scale_min = 0.03
			pm.scale_max = 0.06
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fade.colors = PackedColorArray([Color(0.6, 1, 0.9, 0), Color(0.7, 1, 0.9, 0.9), Color(1, 0.6, 0.9, 0.9), Color(1, 0.6, 0.9, 0)])
		_:
			# Pollen: tiny warm glowing specks floating upwards.
			p.amount = 50
			p.lifetime = 7.0
			p.preprocess = 7.0
			p.position = Vector3(3.0, 3.5, -1.5)
			pm.emission_box_extents = Vector3(30.0, 3.5, 5.0)
			pm.gravity = Vector3(0.2, 0.25, 0.0)
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.4
			pm.spread = 180.0
			pm.scale_min = 0.035
			pm.scale_max = 0.07
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fade.colors = PackedColorArray([Color(1, 0.85, 0.3, 0), Color(1, 0.85, 0.3, 0.8), Color(1, 0.85, 0.3, 0.8), Color(1, 0.85, 0.3, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	parent.add_child(p)
	p.emitting = true


# --- Level start banner --------------------------------------------------------------

func _show_banner(number: int, title: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	var host: Node = _find_level()
	if host == null:
		host = self
	host.add_child(layer)

	var fade := ColorRect.new()
	fade.color = Color(0.06, 0.07, 0.16, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	var ft := fade.create_tween()
	ft.tween_property(fade, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var banner := VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_theme_constant_override("separation", -6)
	layer.add_child(banner)
	var big := Label.new()
	big.text = "TASO %d" % number
	MenuStyle.style_ribbon(big, 46, "danger" if ArtStyle.is_boss_level(number) else "accent")
	banner.add_child(big)
	var small := Label.new()
	small.text = title.to_upper()
	MenuStyle.style_label(small, 24)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(small)

	await get_tree().process_frame
	if not is_instance_valid(banner):
		return
	banner.position = Vector2((banner.get_viewport_rect().size.x - banner.size.x) * 0.5, -160.0)
	banner.pivot_offset = banner.size * 0.5
	var bt := banner.create_tween()
	bt.tween_property(banner, "position:y", banner.get_viewport_rect().size.y * 0.36, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_interval(1.1)
	bt.tween_property(banner, "modulate:a", 0.0, 0.35)
	bt.parallel().tween_property(banner, "scale", Vector2(1.15, 1.15), 0.35)
	bt.tween_callback(layer.queue_free)


# --- Main menu diorama ------------------------------------------------------------------

func _show_menu_diorama() -> void:
	if _menu_diorama != null and is_instance_valid(_menu_diorama):
		return
	current_theme = "meadow"
	_clouds.clear()
	_spinners.clear()
	_apply_environment("meadow")
	_menu_diorama = Node3D.new()
	_menu_diorama.name = "MenuDiorama"
	add_child(_menu_diorama)
	_menu_time = 0.0

	_build_backdrop(_menu_diorama, "meadow", true)

	var island := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(70.0, 6.0, 3.4)
	island.mesh = box
	island.material_override = ArtStyle.terrain_material("meadow", 0.5, 0.06, "menu")
	island.position = Vector3(0.0, -2.5, 0.0)
	_menu_diorama.add_child(island)

	# A small showcase fort: stone base, wooden frame, ice top.
	var parts := [
		["stone", Vector3(6.0, 1.0, 0.0), Vector3(0.7, 1.0, 1.2)],
		["stone", Vector3(9.0, 1.0, 0.0), Vector3(0.7, 1.0, 1.2)],
		["wood", Vector3(7.5, 1.75, 0.0), Vector3(3.8, 0.5, 1.2)],
		["wood", Vector3(6.4, 2.9, 0.0), Vector3(0.5, 1.8, 1.2)],
		["wood", Vector3(8.6, 2.9, 0.0), Vector3(0.5, 1.8, 1.2)],
		["wood", Vector3(7.5, 4.05, 0.0), Vector3(3.0, 0.5, 1.2)],
		["ice", Vector3(7.5, 4.8, 0.0), Vector3(1.0, 1.0, 1.0)],
		["stone", Vector3(12.0, 1.25, 0.0), Vector3(1.6, 1.5, 1.2)],
		["ice", Vector3(12.0, 2.5, 0.0), Vector3(0.9, 1.0, 1.0)],
	]
	for part in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[2]
		mi.mesh = bm
		mi.material_override = ArtStyle.block_material(part[0], part[2])
		mi.position = part[1]
		_menu_diorama.add_child(mi)

	var monkey_scene := load(MONKEY) as PackedScene
	if monkey_scene != null:
		for spot in [Vector3(7.5, 2.0, 0.0), Vector3(12.0, 3.0, 0.0), Vector3(3.2, 0.5, 0.0)]:
			var monkey := monkey_scene.instantiate() as Node3D
			monkey.position = spot
			monkey.rotation.y = randf_range(-0.4, 0.4)
			_menu_diorama.add_child(monkey)
			var t := monkey.create_tween().set_loops()
			var d := randf_range(0.5, 0.8)
			t.tween_property(monkey, "position:y", spot.y + 0.18, d).set_trans(Tween.TRANS_SINE)
			t.tween_property(monkey, "position:y", spot.y, d).set_trans(Tween.TRANS_SINE)

	var sling := Props.build_slingshot(Vector3(0.0, 1.6, 0.0), -0.45)
	sling.position = Vector3(-6.0, 0.95, 0.0)
	_menu_diorama.add_child(sling)
	# Ammus ritsassa: banaani (sama malli kuin pelissä).
	var banana := Node3D.new()
	banana.set_script(BananaModel)
	banana.set("length", 1.5)
	banana.set("thickness", 0.27)
	banana.position = Vector3(-6.0, 2.25, 0.0)
	_menu_diorama.add_child(banana)
	_spinners.append([banana, Vector3.UP, 0.0, 2.25, 1.6])

	_add_ambient_particles(_menu_diorama, "meadow")


func _hide_menu_diorama() -> void:
	if _menu_diorama != null and is_instance_valid(_menu_diorama):
		_menu_diorama.queue_free()
	_menu_diorama = null

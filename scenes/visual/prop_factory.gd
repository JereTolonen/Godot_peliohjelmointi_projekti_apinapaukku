extends RefCounted
## Proseduraaliset 3D-rekvisiitat: kukkulat, vuoret, pilvet, palmut, kaktukset,
## mesat, asteroidit, kristallit ja ritsan malli. Verkot luodaan kerran ja jaetaan
## (MultiMesh / sama Mesh useassa instanssissa), mikä pitää draw callit pieninä.

const ArtStyle := preload("res://scenes/visual/art_style.gd")

static var _mesh_cache: Dictionary = {}
static var _kit_cache: Dictionary = {}


static func _noise1(x: float, seed: float) -> float:
	return sin(x * 0.13 + seed) * 0.5 + sin(x * 0.29 + seed * 1.7) * 0.3 + sin(x * 0.71 + seed * 2.3) * 0.2


## Kukkula- tai vuorijono: ruudukko x-suunnassa [x0, x1], syvyys `depth`.
## `peak` 0 = pyöreät kukkulat, 1 = terävät vuoret. Lumihuiput vertex-värillä.
static func ridge_mesh(x0: float, x1: float, depth: float, height: float, peak: float, seed: float, low: Color, high: Color, snow_line: float = 2.0) -> ArrayMesh:
	var key := "ridge/%.1f/%.1f/%.1f/%.1f/%.2f/%.2f/%s/%s/%.2f" % [x0, x1, depth, height, peak, seed, low.to_html(), high.to_html(), snow_line]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var nx := int((x1 - x0) / 2.0) + 2
	var nz := 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := []
	for iz in nz:
		var row := []
		var tz := float(iz) / float(nz - 1)
		# Front edge sinks below the base so the ridge has no visible bottom line.
		var profile := sin(tz * PI)
		for ix in nx:
			var x := lerpf(x0, x1, float(ix) / float(nx - 1))
			var n := _noise1(x, seed) * 0.5 + 0.5
			var ridge := 1.0 - absf(_noise1(x * 1.3 + 40.0, seed + 3.0))
			var h := lerpf(n, ridge * ridge, peak) * height * profile
			if iz == 0 or iz == nz - 1:
				h = -2.0
			row.append(h)
		heights.append(row)
	for iz in nz - 1:
		for ix in nx - 1:
			var quad := [
				[ix, iz], [ix + 1, iz], [ix + 1, iz + 1],
				[ix, iz], [ix + 1, iz + 1], [ix, iz + 1],
			]
			for v in quad:
				var x := lerpf(x0, x1, float(v[0]) / float(nx - 1))
				var z := -float(v[1]) / float(nz - 1) * depth
				var h: float = heights[v[1]][v[0]]
				var t := clampf(h / maxf(height, 0.01), 0.0, 1.0)
				var c := low.lerp(high, t)
				if h > height * snow_line:
					c = Color(0.96, 0.98, 1.0)
				st.set_color(c)
				st.add_vertex(Vector3(x, h, z))
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Pörröinen pilvi: useita palloja yhdeksi verkoksi.
static func cloud_mesh(seed: int) -> ArrayMesh:
	var key := "cloud/%d" % seed
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := rng.randi_range(5, 8)
	for i in count:
		var t := float(i) / float(count - 1) - 0.5
		var r := rng.randf_range(0.8, 1.5) * (1.0 - absf(t) * 0.8)
		var pos := Vector3(t * 4.5 + rng.randf_range(-0.3, 0.3), r * 0.35 + rng.randf_range(0.0, 0.4), rng.randf_range(-0.5, 0.5))
		st.append_from(sphere, 0, Transform3D(Basis().scaled(Vector3(r, r * 0.85, r)), pos))
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Palmu: kaareva runko ja roikkuvat lehdet (kaksi pintaa, kaksi materiaalia).
static func palm_mesh(seed: int) -> ArrayMesh:
	var key := "palm/%d" % seed
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := CylinderMesh.new()
	seg.radial_segments = 7
	seg.rings = 1
	seg.height = 0.62
	seg.top_radius = 0.16
	seg.bottom_radius = 0.2
	var lean := rng.randf_range(-0.25, 0.25)
	var pos := Vector3.ZERO
	var dir := Vector3.UP
	for i in 8:
		dir = (Vector3.UP + Vector3(lean * float(i) * 0.25, 0.0, 0.0)).normalized()
		var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if dir != Vector3.UP else Basis()
		var s := 1.0 - float(i) * 0.05
		trunk.append_from(seg, 0, Transform3D(basis.scaled(Vector3(s, 1.0, s)), pos + dir * 0.3))
		pos += dir * 0.56
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := PrismMesh.new()
	leaf.size = Vector3(0.5, 0.08, 1.9)
	var top := pos
	for i in 7:
		var yaw := float(i) / 7.0 * TAU + rng.randf_range(-0.2, 0.2)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(18.0, 34.0)))
		leaves.append_from(leaf, 0, Transform3D(basis, top + basis * Vector3(0.0, 0.0, 0.95) + Vector3(0.0, -0.15, 0.0)))
	var coconut := SphereMesh.new()
	coconut.radius = 0.13
	coconut.height = 0.26
	coconut.radial_segments = 8
	coconut.rings = 4
	for i in 3:
		var a := float(i) * TAU / 3.0
		trunk.append_from(coconut, 0, Transform3D(Basis(), top + Vector3(cos(a) * 0.16, -0.18, sin(a) * 0.16)))
	var mesh := trunk.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, ArtStyle.soft_material(Color("a8733f"), Color("d29a5c"), false, 4.0, 0.0))
	mesh.surface_set_material(1, ArtStyle.soft_material(Color("3fae3c"), Color("8fe060"), false, 5.0, 2.0))
	_mesh_cache[key] = mesh
	return mesh


static func cactus_mesh(seed: int) -> ArrayMesh:
	var key := "cactus/%d" % seed
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CapsuleMesh.new()
	body.radius = 0.32
	body.height = 2.6
	body.radial_segments = 8
	body.rings = 4
	st.append_from(body, 0, Transform3D(Basis(), Vector3(0.0, 1.3, 0.0)))
	var arm := CapsuleMesh.new()
	arm.radius = 0.22
	arm.height = 1.1
	arm.radial_segments = 8
	arm.rings = 3
	for side in [-1.0, 1.0]:
		if rng.randf() < 0.85:
			var h := rng.randf_range(0.9, 1.6)
			st.append_from(arm, 0, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.45, h, 0.0)))
			st.append_from(arm, 0, Transform3D(Basis(), Vector3(side * 0.82, h + 0.4, 0.0)))
	var mesh := st.commit()
	mesh.surface_set_material(0, ArtStyle.soft_material(Color("4f9e4a"), Color("8fd06a"), false, 3.0, 0.0))
	_mesh_cache[key] = mesh
	return mesh


## Kerroksellinen kalliomesa kanjonimaisemaan.
static func mesa_mesh(seed: int) -> ArrayMesh:
	var key := "mesa/%d" % seed
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.0
	var r := rng.randf_range(3.0, 4.5)
	for i in rng.randi_range(2, 4):
		var h := rng.randf_range(1.5, 3.5)
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 7
		cyl.rings = 1
		cyl.height = h
		cyl.bottom_radius = r
		cyl.top_radius = r * 0.9
		st.append_from(cyl, 0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-0.3, 0.3), y + h * 0.5, 0.0)))
		y += h
		r *= rng.randf_range(0.6, 0.85)
	st.deindex()
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Matalapolyinen asteroidi (litteä varjostus).
static func asteroid_mesh(seed: int) -> ArrayMesh:
	var key := "asteroid/%d" % seed
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var sphere := SphereMesh.new()
	sphere.radial_segments = 9
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.6
	# Same position -> same offset so the seam stays closed.
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + noise.get_noise_3dv(v * 2.0) * 0.45
		verts[i] = v * d
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var base := ArrayMesh.new()
	base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(base, 0)
	st.deindex()
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


static func crystal_mesh() -> ArrayMesh:
	if _mesh_cache.has("crystal"):
		return _mesh_cache["crystal"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := CylinderMesh.new()
	c.radial_segments = 5
	c.rings = 1
	c.top_radius = 0.0
	c.bottom_radius = 0.16
	c.height = 0.7
	st.append_from(c, 0, Transform3D(Basis(), Vector3(0.0, 0.35, 0.0)))
	st.append_from(c, 0, Transform3D(Basis(Vector3.BACK, 0.45).scaled(Vector3.ONE * 0.7), Vector3(0.14, 0.22, 0.0)))
	st.append_from(c, 0, Transform3D(Basis(Vector3.BACK, -0.5).scaled(Vector3.ONE * 0.55), Vector3(-0.13, 0.17, 0.05)))
	st.deindex()
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache["crystal"] = mesh
	return mesh


## Hahmo- tai maastokitin .glb-mallin ensimmäinen verkko ja sen paikallinen muunnos.
static func kit_mesh(path: String) -> Dictionary:
	if _kit_cache.has(path):
		return _kit_cache[path]
	var result := {"mesh": null, "transform": Transform3D(), "aabb": AABB()}
	var packed := load(path) as PackedScene
	if packed != null:
		var root := packed.instantiate()
		var found := root.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var mi := found[0] as MeshInstance3D
			var xf := Transform3D()
			var node: Node = mi
			while node != null and node != root:
				if node is Node3D:
					xf = (node as Node3D).transform * xf
				node = node.get_parent()
			result["mesh"] = mi.mesh
			result["transform"] = xf
			result["aabb"] = xf * mi.mesh.get_aabb()
		root.free()
	_kit_cache[path] = result
	return result


## Ritsan malli: puinen Y-haarukka kivijalustalla, kumikääreet haarojen päissä.
## `anchor` = paikallinen piste, josta ammus lähtee (LaunchPoint). `ground` = jalustan alareuna.
static func build_slingshot(anchor: Vector3, ground: float) -> Node3D:
	var root := Node3D.new()
	root.name = "SlingshotModel"
	var wood := ArtStyle.soft_material(Color("8a5530"), Color("c98a52"), false, 3.0, ground)
	var wrap := ArtStyle.flat_material(Color("3a2a2a"), 0.6)

	var trunk_h := (anchor.y - 0.55) - ground
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.13
	tm.bottom_radius = 0.19
	tm.height = trunk_h
	tm.radial_segments = 10
	trunk.mesh = tm
	trunk.material_override = wood
	trunk.position = Vector3(anchor.x, ground + trunk_h * 0.5, anchor.z)
	root.add_child(trunk)

	var fork_base := Vector3(anchor.x, ground + trunk_h - 0.05, anchor.z)
	for side in [-1.0, 1.0]:
		var tip := Vector3(anchor.x + side * 0.36, anchor.y + 0.22, anchor.z)
		var arm := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.085
		am.bottom_radius = 0.12
		am.height = fork_base.distance_to(tip)
		am.radial_segments = 8
		arm.mesh = am
		arm.material_override = wood
		var dir := (tip - fork_base).normalized()
		arm.basis = Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))
		arm.position = (fork_base + tip) * 0.5
		root.add_child(arm)
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.105
		bm.bottom_radius = 0.105
		bm.height = 0.16
		bm.radial_segments = 8
		band.mesh = bm
		band.material_override = wrap
		band.basis = arm.basis
		band.position = tip - dir * 0.12
		root.add_child(band)
		root.set_meta("tip_l" if side < 0.0 else "tip_r", tip)

	# Stone base.
	var rock := MeshInstance3D.new()
	rock.mesh = asteroid_mesh(7)
	rock.material_override = ArtStyle.soft_material(Color("8c93a6"), Color("c4cad8"), false, 1.0, ground)
	rock.scale = Vector3(0.55, 0.28, 0.45)
	rock.position = Vector3(anchor.x, ground + 0.05, anchor.z)
	root.add_child(rock)
	return root


# --- New world props -------------------------------------------------------------

## Raidallinen rantavarjo (tolppa + kartio).
static func umbrella_mesh(seed: int) -> ArrayMesh:
	var key := "umbrella/%d" % seed
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var colors := [Color("ff5d73"), Color("3fa9f5"), Color("ffc12e"), Color("6fd13a")]
	var pole_st := SurfaceTool.new()
	pole_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.05
	pole.height = 2.4
	pole.radial_segments = 6
	pole_st.append_from(pole, 0, Transform3D(Basis(Vector3.BACK, 0.12), Vector3(0, 1.2, 0)))
	var canopy_st := SurfaceTool.new()
	canopy_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.0
	canopy.bottom_radius = 1.3
	canopy.height = 0.55
	canopy.radial_segments = 8
	canopy.rings = 1
	canopy_st.append_from(canopy, 0, Transform3D(Basis(Vector3.BACK, 0.12), Vector3(0.28, 2.4, 0)))
	var mesh := pole_st.commit()
	canopy_st.commit(mesh)
	mesh.surface_set_material(0, ArtStyle.flat_material(Color("f2f2f2"), 0.6))
	mesh.surface_set_material(1, ArtStyle.soft_material(colors[seed % colors.size()], Color(1.15, 1.15, 1.15), false, 1.0, 2.0))
	_mesh_cache[key] = mesh
	return mesh


## Punavalkoinen majakka.
static func lighthouse_mesh() -> ArrayMesh:
	if _mesh_cache.has("lighthouse"):
		return _mesh_cache["lighthouse"]
	var red := SurfaceTool.new()
	red.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := SurfaceTool.new()
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.0
	var r := 1.6
	for i in 6:
		var seg := CylinderMesh.new()
		seg.bottom_radius = r
		seg.top_radius = r - 0.12
		seg.height = 1.6
		seg.radial_segments = 12
		seg.rings = 1
		(red if i % 2 == 0 else white).append_from(seg, 0, Transform3D(Basis(), Vector3(0, y + 0.8, 0)))
		y += 1.6
		r -= 0.12
	var lamp := CylinderMesh.new()
	lamp.top_radius = r
	lamp.bottom_radius = r
	lamp.height = 1.0
	lamp.radial_segments = 12
	white.append_from(lamp, 0, Transform3D(Basis(), Vector3(0, y + 0.5, 0)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = r + 0.25
	roof.height = 0.9
	roof.radial_segments = 12
	red.append_from(roof, 0, Transform3D(Basis(), Vector3(0, y + 1.45, 0)))
	var mesh := red.commit()
	white.commit(mesh)
	mesh.surface_set_material(0, ArtStyle.soft_material(Color("e8473c"), Color(1.1, 1.1, 1.1), false, 10.0, 0.0))
	mesh.surface_set_material(1, ArtStyle.soft_material(Color("f6f1e6"), Color.WHITE, false, 10.0, 0.0, 0.1))
	_mesh_cache["lighthouse"] = mesh
	return mesh


## Tippukivi (kartio). `up` = kasvaa ylöspäin (stalagmiitti), muuten roikkuu.
static func spike_mesh(up: bool) -> ArrayMesh:
	var key := "spike/%s" % up
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := CylinderMesh.new()
	c.top_radius = 0.0 if up else 1.0
	c.bottom_radius = 1.0 if up else 0.0
	c.height = 4.0
	c.radial_segments = 7
	c.rings = 2
	st.append_from(c, 0, Transform3D(Basis(), Vector3(0, 2.0 if up else -2.0, 0)))
	st.deindex()
	st.generate_normals()
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


## Hehkuva sieni (jalka + hattu).
static func glow_mushroom_mesh(color: Color) -> ArrayMesh:
	var key := "mush/" + color.to_html()
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var stem_st := SurfaceTool.new()
	stem_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.12
	stem.bottom_radius = 0.18
	stem.height = 0.9
	stem.radial_segments = 8
	stem_st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.45, 0)))
	var cap_st := SurfaceTool.new()
	cap_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap := SphereMesh.new()
	cap.radius = 0.55
	cap.height = 0.55
	cap.is_hemisphere = true
	cap.radial_segments = 12
	cap.rings = 4
	cap_st.append_from(cap, 0, Transform3D(Basis(), Vector3(0, 0.85, 0)))
	var mesh := stem_st.commit()
	cap_st.commit(mesh)
	mesh.surface_set_material(0, ArtStyle.flat_material(Color("e8e0d0"), 0.8, 0.2))
	mesh.surface_set_material(1, ArtStyle.flat_material(color, 0.5, 1.4))
	_mesh_cache[key] = mesh
	return mesh


## Tulivuori: leveä kartio, jonka huipulla hehkuva kraatteri.
static func volcano_mesh() -> ArrayMesh:
	if _mesh_cache.has("volcano"):
		return _mesh_cache["volcano"]
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cone := CylinderMesh.new()
	cone.top_radius = 4.0
	cone.bottom_radius = 22.0
	cone.height = 20.0
	cone.radial_segments = 14
	cone.rings = 3
	rock.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 10.0, 0)))
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crater := CylinderMesh.new()
	crater.top_radius = 3.6
	crater.bottom_radius = 3.6
	crater.height = 0.2
	crater.radial_segments = 14
	glow.append_from(crater, 0, Transform3D(Basis(), Vector3(0, 20.0, 0)))
	# Lava streams down the front.
	for i in 3:
		var stream := BoxMesh.new()
		stream.size = Vector3(0.9, 14.0, 0.3)
		var a := deg_to_rad(-25.0 + float(i) * 25.0)
		var dir := Vector3(sin(a), 0, cos(a))
		var mid := Vector3(0, 13.0, 0) + dir * 8.5
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(42.0))
		glow.append_from(stream, 0, Transform3D(basis, mid))
	rock.deindex()
	rock.generate_normals()
	var mesh := rock.commit()
	glow.commit(mesh)
	mesh.surface_set_material(0, ArtStyle.soft_material(Color("3a2c30"), Color("6a4a48"), false, 20.0, 0.0))
	mesh.surface_set_material(1, ArtStyle.flat_material(Color("ff6a1a"), 0.6, 3.0, true))
	_mesh_cache["volcano"] = mesh
	return mesh


## Vieraan planeetan kasvi: kaareva varsi ja hehkuva pallo päässä.
static func alien_plant_mesh(seed: int, bulb: Color) -> ArrayMesh:
	var key := "alien/%d/%s" % [seed, bulb.to_html()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stem := SurfaceTool.new()
	stem.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bulbs := SurfaceTool.new()
	bulbs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := CylinderMesh.new()
	seg.top_radius = 0.1
	seg.bottom_radius = 0.14
	seg.height = 0.6
	seg.radial_segments = 6
	seg.rings = 1
	var ball := SphereMesh.new()
	ball.radius = 0.4
	ball.height = 0.8
	ball.radial_segments = 10
	ball.rings = 5
	for branch in rng.randi_range(1, 3):
		var pos := Vector3(rng.randf_range(-0.3, 0.3), 0.0, 0.0)
		var lean := rng.randf_range(-0.35, 0.35)
		var dir := Vector3.UP
		for i in rng.randi_range(4, 7):
			dir = (Vector3.UP + Vector3(lean * float(i) * 0.3, 0, 0)).normalized()
			var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if dir != Vector3.UP else Basis()
			stem.append_from(seg, 0, Transform3D(basis, pos + dir * 0.3))
			pos += dir * 0.55
		var s := rng.randf_range(0.8, 1.4)
		bulbs.append_from(ball, 0, Transform3D(Basis().scaled(Vector3.ONE * s), pos + Vector3(0, 0.25, 0)))
	var mesh := stem.commit()
	bulbs.commit(mesh)
	mesh.surface_set_material(0, ArtStyle.soft_material(Color("2f8f8a"), Color("6fd6c4"), false, 4.0, 0.0))
	mesh.surface_set_material(1, ArtStyle.flat_material(bulb, 0.4, 1.6))
	_mesh_cache[key] = mesh
	return mesh

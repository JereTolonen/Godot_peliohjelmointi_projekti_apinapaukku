extends Node
## Pelibotti, joka pelaa tasot läpi ja kirjaa, onko jokainen taso läpäistävissä
## kentän omilla ammuksilla. Aja scene res://tools/autoplay.tscn.
##
## Botti tähtää laskemalla lentoradan (painovoima + painovoimakentät) ja säteenheitolla
## sen, mihin rata ensimmäisenä osuu. Se käyttää erikoiskykyjä yksinkertaisesti:
## painava ja pommittaja kohteen päällä, jakautuva lähestyessä. Tulokset tiedostoon
## user://autoplay_results.json ja tulosteeseen.

const MonkeyAntics := preload("res://scenes/includes/characters/monkey_antics.gd")

## Ensimmäinen ja viimeinen testattava taso (1-pohjainen). 0 = kaikki.
@export var first_level: int = 1
@export var last_level: int = 0
@export var time_scale: float = 3.0
## Yhden tason enimmäisaika (pelin sekunteina).
@export var level_timeout: float = 120.0

var results: Array = []
var running: bool = true
var current: int = 0


var _saved_progress: PackedByteArray = PackedByteArray()
var _had_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Botin voitot eivät saa muuttaa pelaajan tallennusta: otetaan talteen ja palautetaan.
	_had_progress = FileAccess.file_exists("user://progress.cfg")
	if _had_progress:
		_saved_progress = FileAccess.get_file_as_bytes("user://progress.cfg")
	Engine.time_scale = time_scale
	Engine.physics_ticks_per_second = int(60.0 * time_scale)
	_run.call_deferred()


func _gm() -> Node:
	return get_tree().current_scene.get_node("GameController")


func _run() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	var gm := _gm()
	var total: int = gm.get("_entries").size()
	var last := total if last_level <= 0 else mini(last_level, total)
	for n in range(first_level, last + 1):
		current = n
		var r: Dictionary = await _play_level(gm, n)
		results.append(r)
		print("AUTOPLAY ", JSON.stringify(r))
		_save()
	running = false
	_restore_progress()
	print("AUTOPLAY DONE")
	_save()


func _restore_progress() -> void:
	if _had_progress:
		var f := FileAccess.open("user://progress.cfg", FileAccess.WRITE)
		if f != null:
			f.store_buffer(_saved_progress)
	elif FileAccess.file_exists("user://progress.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))


func _exit_tree() -> void:
	if running:
		_restore_progress()


func _save() -> void:
	var f := FileAccess.open("user://autoplay_results.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"running": running, "current": current, "results": results}, "  "))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _play_level(gm: Node, n: int) -> Dictionary:
	get_tree().paused = false
	gm.call("start_level", n - 1)
	await _wait(1.6)
	var sling := get_tree().get_first_node_in_group("slingshot")
	var start_ms := Time.get_ticks_msec()
	var shots := 0
	var total_ammo: int = int(sling.call("ammo_remaining")) if sling != null else 0
	while true:
		var state := int(gm.get("state"))
		if state == 2 or state == 3:
			break
		if float(Time.get_ticks_msec() - start_ms) / 1000.0 * Engine.time_scale > level_timeout:
			break
		if sling == null or not is_instance_valid(sling):
			sling = get_tree().get_first_node_in_group("slingshot")
			await _wait(0.2)
			continue
		if not bool(sling.call("has_ammo")):
			await _wait(0.3)
			continue
		# Odotetaan, että edellinen laukaus on asettunut.
		var settle := 0.0
		while bool(sling.call("is_busy")) and settle < 7.0:
			await _wait(0.2)
			settle += 0.2 * Engine.time_scale
			_ability_tick(sling)
		if int(gm.get("state")) >= 2:
			break
		await _wait(0.15)
		if float(sling.get("_cooldown_left")) > 0.0:
			await _wait(0.3)
		var target := _choose_target(sling)
		if target.is_empty():
			await _wait(0.3)
			continue
		MonkeyAntics.register_input()
		_shoot(sling, target["pull"])
		_target_x = float(target["x"])
		shots += 1
		# Lennon aikana kyvyt.
		for i in 40:
			await _wait(0.05)
			_ability_tick(sling)
	var final_state := int(gm.get("state"))
	var remaining := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.is_queued_for_deletion():
			remaining += 1
	return {"level": n, "won": final_state == 2, "shots": shots, "ammo": total_ammo, "left": remaining,
		"timeout": final_state < 2}


var _target_x: float = 0.0


func _ability_tick(sling: Node) -> void:
	var projs: Array = sling.get("_projectiles")
	for p in projs:
		if not bool(p.get("ability", false)):
			continue
		var bv: Variant = p.get("body")
		if not is_instance_valid(bv):
			continue
		var body := bv as RigidBody3D
		if body == null or body.has_meta("slingshot_touched"):
			continue
		var kind := String(p.get("kind", ""))
		var dx := absf(body.global_position.x - _target_x)
		var tap := false
		match kind:
			"heavy", "bomber":
				tap = dx < 0.7
			"splitter":
				tap = body.global_position.x > _target_x - 6.0
			"exploding":
				tap = dx < 0.4
			"speedy":
				tap = float(p["age"]) > 0.35 and body.linear_velocity.y < 1.0
		if tap:
			sling.call("_try_activate_ability")


func _shoot(sling: Node, pull: Vector3) -> void:
	var scene: PackedScene = sling.call("_next_scene")
	if scene == null:
		return
	var character := scene.instantiate() as Node3D
	var body: RigidBody3D = sling.call("_make_projectile", character)
	sling.call("_world").add_child(body)
	body.global_position = sling.call("_anchor")
	sling.set("_drag_body", body)
	sling.set("_drag_character", character)
	sling.set("_pull", pull)
	sling.set("_dragging", true)
	sling.call("_release_drag")


## Paras tähtäys johonkin jäljellä olevaan apinaan.
func _choose_target(sling: Node) -> Dictionary:
	var anchor: Vector3 = sling.call("_anchor")
	var power := float(sling.get("power"))
	var max_pull := float(sling.get("max_pull"))
	var g := float(sling.get("gravity"))
	var space := (sling as Node3D).get_world_3d().direct_space_state
	var targets: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and not e.is_queued_for_deletion():
			targets.append(e)
	if targets.is_empty():
		return {}
	var best := {}
	var best_score := INF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for t in targets:
		var tnode := t as Node3D
		var tpos := tnode.global_position + Vector3(0.0, 0.8, 0.0)
		var shape := tnode.get_node_or_null("CollisionShape3D") as Node3D
		if shape != null:
			tpos = shape.global_position
		var a := -20.0
		while a <= 80.0:
			var mag := 1.0
			while mag <= max_pull + 0.01:
				var dir := Vector3(cos(deg_to_rad(a)), sin(deg_to_rad(a)), 0.0)
				var v := dir * mag * power
				var score := _simulate(sling, space, anchor, v, g, tnode, tpos)
				# Pieni satunnaisuus, ettei sama epäonnistunut laukaus toistu.
				score += rng.randf() * 0.4 - mag * 0.08
				if score < best_score:
					best_score = score
					best = {"pull": -dir * mag, "x": tpos.x, "score": score}
				mag += 0.25
			a += 3.0
	return best


func _simulate(sling: Node, space: PhysicsDirectSpaceState3D, start: Vector3, v0: Vector3, g: float, target: Node3D, tpos: Vector3) -> float:
	var p := start
	var v := v0
	var dt := 1.0 / 30.0
	var closest := INF
	for i in 90:
		var acc := Vector3(0.0, -g, 0.0) + (sling.call("_gravity_well_pull", p) as Vector3)
		var np := p + v * dt + acc * (0.5 * dt * dt)
		v += acc * dt
		closest = minf(closest, np.distance_to(tpos))
		var q := PhysicsRayQueryParameters3D.create(p, np, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var col := hit["collider"] as Node
			var hp: Vector3 = hit["position"]
			if col == target or (col != null and target.is_ancestor_of(col)):
				return 0.0
			var d := hp.distance_to(tpos)
			if col is RigidBody3D and d < 2.2:
				return 1.0 + d
			return 4.0 + minf(closest, d)
		p = np
		if p.y < -12.0:
			break
	return 6.0 + closest

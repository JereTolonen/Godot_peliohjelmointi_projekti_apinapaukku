extends Node
## Kehitystyökalu: käynnistää jokaisen kentän ja tarkistaa, että rakennelmat pysyvät
## pystyssä ja apinat hengissä ilman yhtään laukausta. Tulokset tulostuvat riveinä
## "SMOKE L<n> OK/BAD ...". Käyttö: lisää tämä tilapäisesti autoloadiksi ja aja peli;
## poista autoload testin jälkeen (ei kuulu julkaistavaan peliin).

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var gm := get_tree().current_scene.get_node_or_null("GameController")
	if gm == null:
		print("SMOKE no game controller")
		return
	var count: int = (gm.get("_entries") as Array).size()
	print("SMOKE levels=%d" % count)
	var bad := 0
	for i in count:
		gm.call("start_level", i)
		await get_tree().create_timer(0.4).timeout
		var e0 := get_tree().get_nodes_in_group("enemies").size()
		var start := {}
		for b in get_tree().get_nodes_in_group("destructibles"):
			start[b] = (b as Node3D).global_position
		await get_tree().create_timer(3.0).timeout
		var e1 := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.is_queued_for_deletion():
				e1 += 1
		var moved := 0.0
		var lost := 0
		for b in start:
			if not is_instance_valid(b):
				lost += 1
			else:
				moved = maxf(moved, (b as Node3D).global_position.distance_to(start[b]))
		var ok := e0 == e1 and lost == 0 and moved < 0.15 and e0 > 0
		if not ok:
			bad += 1
		print("SMOKE L%d %s enemies %d->%d blocks=%d lost=%d moved=%.2f" % [i + 1, "OK " if ok else "BAD", e0, e1, start.size(), lost, moved])
	print("SMOKE DONE bad=%d" % bad)

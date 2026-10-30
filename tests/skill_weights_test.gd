extends Node

var failures := 0


func check(ok: bool, label: String) -> void:
	print("WEIGHTS %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	Director.stop()
	main.player.set_physics_process(false)
	Skills.unlock(&"fire_1")
	check(Skills._branch_offer_bonus(&"fire_rate") == 3.0, "chosen branch multiplier doubles from 1.5 to 3")
	check(Skills._branch_offer_bonus(&"heavy") == 1.0, "unchosen branch stays at base weight")
	var a := Skills.get_node_by_id(&"fire_2")
	var b := Skills.get_node_by_id(&"heavy_1")
	var old_a := maxf(0.01, a.weight) * 1.5
	check(is_equal_approx(Skills._node_offer_weight(a), old_a * 2.0), "selected node effective weight is exactly twice its previous value")
	var expected := Skills._node_offer_weight(a) / (Skills._node_offer_weight(a) + Skills._node_offer_weight(b))
	RunState.rng.seed = 83241
	var branch_hits := 0
	var fallback_hits := 0
	for i in 12000:
		if Skills._pick_branch({a.branch: [a], b.branch: [b]}, [a.branch, b.branch]) == a.branch:
			branch_hits += 1
		if Skills._pick_node([a, b]) == a:
			fallback_hits += 1
	check(absf(float(branch_hits) / 12000.0 - expected) < 0.015, "branch draw follows seeded weighted probabilities")
	check(absf(float(fallback_hits) / 12000.0 - expected) < 0.015, "cross-branch fallback uses the same weights")
	Skills.unlock(&"fire_2")
	check(Skills._branch_offer_bonus(&"fire_rate") == 3.0, "multiple invested tiers do not compound the bonus")
	for i in 200:
		var options := Skills.pick_options(3)
		var ids := {}
		var branches := {}
		for node in options:
			if not Skills.is_available(node) or ids.has(node.id) or branches.has(node.branch):
				check(false, "offers remain available, distinct, and branch-diverse")
			ids[node.id] = true
			branches[node.branch] = true
	check(Skills.pick_options(3, [&"fire_3"] ).all(func(node): return node.id != &"fire_3"), "reroll exclusions remain respected")
	print("SKILL WEIGHTS TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

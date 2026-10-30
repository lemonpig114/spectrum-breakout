extends Node

var failures := 0


func check(ok: bool, label: String) -> void:
	print("FIRE %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	Director.stop()
	var player: Player = main.player
	player.controls_enabled = false
	player.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	Skills.unlock(&"fire_1")
	Skills.unlock(&"fire_2")
	check(is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), 1.0), "tier two has no damage penalty")
	check(is_equal_approx(player.weapon.get_final_fire_rate(), 3.0 * 1.65 * 1.05), "tier two adds forty percent and five percent final rate")
	Skills.unlock(&"fire_3")
	check(player.weapon.stats.get_value(&"spread_degrees") == 10.0, "tier three adds ten degrees")
	Skills.unlock(&"fire_4")
	check(is_equal_approx(player.weapon.get_final_fire_rate(), 3.0 * 1.85 * 1.05 * 1.2)
		and Skills.fire_rate_cap_multiplier() == 9.0, "tier four retains original rate and cap")
	for pair in [[0.0, 1], [0.49, 1], [0.5, 2], [0.99, 2], [1.0, 3], [1.5, 4]]:
		check(Skills.fire_extra_shot_count(pair[0]) == pair[1], "extra shot threshold %s" % pair[0])
	var state := RunState.rng.state
	RunState.rng.seed = 5419
	var procs := 0
	for i in 20000:
		if Skills.roll_fire_extra_shots(1.0) > 0:
			procs += 1
	check(absf(float(procs) / 20000.0 - 0.3) < 0.012, "seeded proc frequency stays near thirty percent")
	var combat: WeaponCombat = main.projectile_manager.combat
	combat.set_physics_process(false)
	var count := 0
	while count == 0:
		state = RunState.rng.state
		player._pellet_offsets(1, deg_to_rad(10.0))
		count = Skills.roll_fire_extra_shots(player.weapon.get_final_fire_rate() / 3.0 - 1.0)
	RunState.rng.state = state
	var manager: ProjectileManager = main.projectile_manager
	var before := manager._active.size()
	player._fire(Vector2.RIGHT)
	check(manager._active.size() == before + 1 and combat._events.size() == count,
		"one trigger queues exactly one group of extra attacks")
	for event in combat._events:
		var angle := absf((event.direction as Vector2).angle_to(Vector2.RIGHT))
		check(angle >= deg_to_rad(25.0) and angle <= deg_to_rad(55.0), "extra shot has high angular offset")
	combat._physics_process(0.0)
	check(manager._active.size() == before + 1 + count and combat._events.is_empty(), "queued extras cannot recursively generate extras")
	for bullet in manager._active.duplicate():
		manager.release(bullet)
	var enemies: Array[Enemy] = []
	for i in 3:
		var enemy := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), null, ColorType.RED)
		main.world.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.global_position = player.global_position + Vector2(70 + i * 80, 0)
		enemy.health = 10000.0
		enemy.max_health = 10000.0
		enemies.append(enemy)
	player.weapon.stats.set_base(&"pierce", 1)
	manager.fire(player.global_position, Vector2.RIGHT, player.weapon.stats, ColorType.BLUE, player.weapon.core, false, 1.0, 1.0, 1.0, 1.0, true, &"", player.weapon, combat.new_budget())
	var bullet: Projectile = manager._active.back()
	bullet._on_body_entered(enemies[0])
	check(bullet.ricochets == 0 and bullet.pierce == 1 and bullet.active_index >= 0,
		"bounce redirects the original projectile without consuming pierce")
	check(bullet.direction.dot((enemies[1].global_position - bullet.global_position).normalized()) > 0.999,
		"bounce chooses nearest different living enemy")
	bullet._on_body_entered(enemies[1])
	check(bullet.pierce == 0 and bullet.active_index >= 0, "pierce remains available after bouncing")
	bullet._on_body_entered(enemies[2])
	check(bullet.active_index < 0, "projectile releases after bounce and pierce are spent")
	var snapshot := {"weapon": player.weapon, "budget": combat.new_budget(), "ricochets": 1,
		"hit_ids": {}, "damage": 10.0, "color": ColorType.BLUE, "heavy": false}
	combat._queue_area_ricochet(snapshot, enemies[0], &"sword")
	check(combat._events.is_empty(), "sword waves never inherit ricochet")
	for form in [&"wave", &"scythe"]:
		var attack := snapshot.duplicate(true)
		combat._queue_area_ricochet(attack, enemies[0], form)
		check(combat._events.size() == 1 and int(combat._events[0].ricochets) == 0,
			"area form queues one finite redirected follow-up: %s" % form)
		combat._events.clear()
		combat._head = 0
	var lightning := WeaponRuntime.new(player.weapon.core)
	lightning.acquire_form(&"lightning")
	lightning.stats.set_base(&"ricochet", 1)
	combat._visuals.clear()
	combat._lightning({"origin": player.global_position, "direction": Vector2.RIGHT, "damage": 10.0,
		"color": ColorType.BLUE, "heavy": false, "weapon": lightning, "budget": combat.new_budget(), "secondary": false})
	check(combat._visuals.size() == 3, "lightning gains one additional full-damage chain segment")
	print("FIRE LINE TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

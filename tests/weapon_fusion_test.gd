extends Node

var failures := 0


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.8).timeout
	Director.stop()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	var player: Player = main.player
	var combat: WeaponCombat = main.projectile_manager.combat
	var ids: Array[StringName] = [&"sword", &"lightning", &"star", &"boomerang"]
	for id in ids:
		failures += _check(ContentDB.get_data(id) is WeaponTraitResource, "weapon resource %s" % id)
	main._queue_weapon_reward("测试宝箱")
	failures += _check(main.weapon_choice_panel.visible and get_tree().paused,
		"weapon reward opens modal choice")
	main.weapon_choice_panel._choose(0)
	failures += _check(player.weapon.owned_forms.size() == 1 and not get_tree().paused,
		"first reward selects weapon and resumes")
	player.weapon.owned_forms.clear()
	player.weapon.traits.clear()
	player.weapon.primary_form = &""
	failures += _check(Skills.grant_relic(&"epic_weapon_cache"), "unique weapon relic can be acquired")
	failures += _check(main.weapon_choice_panel.visible, "weapon relic opens choice")
	main.weapon_choice_panel._choose(0)
	player.weapon.owned_forms.clear()
	player.weapon.traits.clear()
	player.weapon.primary_form = &""
	var original_damage := player.weapon.get_final_damage()
	failures += _check(player.weapon.acquire_form(&"sword"), "first weapon acquired")
	failures += _check(player.weapon.primary_form == &"sword", "first weapon replaces basic form")
	failures += _check(not player.weapon.acquire_form(&"sword"), "duplicate weapon rejected")
	failures += _check(player.weapon.acquire_form(&"lightning"), "second weapon acquired")
	failures += _check(player.weapon.select_primary(&"lightning") and player.weapon.has_form(&"sword"),
		"primary changes without losing secondary")
	failures += _check(is_equal_approx(player.weapon.get_final_damage(), original_damage),
		"form choice preserves StatBlock")
	var budget := combat.new_budget()
	for i in 140:
		if i % combat.DERIVATIVES_PER_FRAME == 0:
			combat._derivative_frame = -1
		combat.enqueue({"kind": &"return_arc", "path": [Vector2.ZERO],
			"damage": 0.0, "color": 0, "budget": budget})
	failures += _check(int(budget.spawned) == 128, "derivative events capped at 128 per root")
	combat._events.clear()
	combat._head = 0
	var frame_budget := combat.new_budget()
	combat._derivative_frame = -1
	for i in 60:
		combat.enqueue({"kind": &"return_arc", "path": [Vector2.ZERO],
			"damage": 0.0, "color": 0, "budget": frame_budget})
	failures += _check(int(frame_budget.spawned) == combat.DERIVATIVES_PER_FRAME, "derivative events capped per frame")
	combat._events.clear()
	combat._head = 0
	combat._derivative_frame = -1
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var enemy_type := ContentDB.get_enemy(&"chaser_square")
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.configure(enemy_type, player)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health
	main.world.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(80, 0)
	enemy.set_physics_process(false)
	player.set("_invuln", 999.0)
	var base_health := enemy.health
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health < base_health, "lightning deals immediate queued damage")
	player.weapon.select_primary(&"sword")
	base_health = enemy.health
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	for frame in 20:
		combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health < base_health, "sword deals area damage")
	combat._sword_waves.clear()
	player.weapon.acquire_form(&"star")
	player.weapon.select_primary(&"star")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	failures += _check(main.projectile_manager._active.size() > 0, "star fires physical projectile")
	for projectile in main.projectile_manager._active.duplicate():
		main.projectile_manager.release(projectile)
	player.weapon.owned_forms.clear()
	player.weapon.traits.clear()
	player.weapon.primary_form = &""
	player.weapon.acquire_form(&"star")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var star_parent: Projectile = main.projectile_manager._active.back()
	star_parent._on_body_entered(enemy)
	combat._physics_process(1.0 / 60.0)
	failures += _check(main.projectile_manager._active.size() == 5, "star creates five shards")
	if not main.projectile_manager._active.is_empty():
		var star_child: Projectile = main.projectile_manager._active.back()
		star_child._on_body_entered(enemy)
		failures += _check(combat._events.is_empty(), "star shards cannot split again")
	for projectile in main.projectile_manager._active.duplicate():
		main.projectile_manager.release(projectile)
	player.weapon.owned_forms.clear()
	player.weapon.traits.clear()
	player.weapon.primary_form = &""
	player.weapon.acquire_form(&"boomerang")
	player.weapon.select_primary(&"boomerang")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var last: Projectile = main.projectile_manager._active.back()
	failures += _check(last.weapon.has_form(&"boomerang"), "boomerang fires returning projectile")
	enemy.health = enemy.max_health
	last._on_body_entered(enemy)
	var after_outbound_hit := enemy.health
	failures += _check(last._returning, "boomerang enters return mode")
	last._on_body_entered(enemy)
	var after_return_hit := enemy.health
	failures += _check(after_return_hit < after_outbound_hit,
		"boomerang can hit same enemy on return")
	last._on_body_entered(enemy)
	failures += _check(is_equal_approx(enemy.health, after_return_hit),
		"boomerang return hits each enemy once")
	for projectile in main.projectile_manager._active.duplicate():
		main.projectile_manager.release(projectile)
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			for primary in [ids[a], ids[b]]:
				player.weapon.owned_forms.clear()
				player.weapon.traits.clear()
				player.weapon.primary_form = &""
				player.weapon.acquire_form(ids[b])
				player.weapon.acquire_form(ids[a])
				player.weapon.select_primary(primary)
				enemy.global_position = player.global_position + Vector2(80, 0)
				enemy.health = enemy.max_health
				combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
					player.color_index, false, player.weapon)
				for frame in 20:
					combat._physics_process(1.0 / 60.0)
				failures += _check(enemy.health < enemy.max_health or not main.projectile_manager._active.is_empty(),
					"fusion %s + %s primary %s attacks" % [ids[a], ids[b], primary])
				if primary == &"sword" and player.weapon.has_form(&"boomerang"):
					failures += _check(main.projectile_manager._active.is_empty() and not combat._sword_waves.is_empty(),
						"sword boomerang returns the slash without an extra projectile")
				if primary == &"star" and player.weapon.has_form(&"boomerang"):
					failures += _check(main.projectile_manager._active.size() == 1,
						"star boomerang uses the star itself as the returning shot")
				for projectile in main.projectile_manager._active.duplicate():
					main.projectile_manager.release(projectile)
				combat._events.clear()
				combat._head = 0
				combat._sword_waves.clear()
	player.weapon.owned_forms.clear()
	player.weapon.traits.clear()
	player.weapon.primary_form = &""
	player.weapon.acquire_form(&"sword")
	player.weapon.acquire_form(&"boomerang")
	player.weapon.select_primary(&"sword")
	enemy.global_position = player.global_position + Vector2(80, 0)
	enemy.health = enemy.max_health
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	for frame in 17:
		combat._physics_process(1.0 / 60.0)
	var after_sword_outbound := enemy.health
	for frame in 18:
		combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health < after_sword_outbound,
		"sword boomerang return damages the same enemy once more")
	combat._sword_waves.clear()
	if main.debug_console != null:
		var console: DebugConsole = main.debug_console
		var tilde := InputEventKey.new()
		tilde.pressed = true
		tilde.physical_keycode = KEY_QUOTELEFT
		console._unhandled_key_input(tilde)
		failures += _check(console.visible and get_tree().paused, "tilde opens debug console")
		console._unhandled_key_input(tilde)
		failures += _check(not console.visible and not get_tree().paused, "tilde closes debug console")
		console._input.text = "w sw"
		console._complete()
		failures += _check(console._input.text == "w sword ", "console Tab completes weapon")
		var before_gold := RunState.gold
		console._submit("gold 25")
		failures += _check(RunState.gold == before_gold + 25, "console grants gold")
		var before_enemies := get_tree().get_nodes_in_group(&"enemies").size()
		console._submit("e triangle 5")
		failures += _check(get_tree().get_nodes_in_group(&"enemies").size() == before_enemies + 5,
			"console spawns requested enemy count")
		console._unhandled_key_input(tilde)
		console._submit("w star")
		failures += _check(main.weapon_choice_panel.visible and get_tree().paused and
			player.weapon.has_form(&"star") and player.weapon.primary_form == &"sword",
			"console weapon opens primary choice without auto switching")
		var star_index: int = main.weapon_choice_panel._choices.find(&"star")
		main.weapon_choice_panel._choose(star_index)
		failures += _check(player.weapon.primary_form == &"star" and not get_tree().paused,
			"console primary choice applies selected form")
		console._input.text = "rw sw"
		console._complete()
		failures += _check(console._input.text == "rw sword ", "console Tab completes remove weapon")
		console._submit("rw star")
		failures += _check(not player.weapon.has_form(&"star") and player.weapon.primary_form == &"sword",
			"console removes primary and selects remaining form")
		console._submit("rw sword")
		console._submit("rw boomerang")
		failures += _check(player.weapon.owned_forms.is_empty() and player.weapon.traits.is_empty()
			and player.weapon.primary_form == &"", "console removes all weapons and restores basic attack")
	print("WEAPON FUSION TEST %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("PASS ", label)
		return 0
	push_error("FAIL " + label)
	return 1

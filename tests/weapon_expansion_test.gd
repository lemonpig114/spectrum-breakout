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
	player.controls_enabled = false
	player.set_physics_process(false)
	var combat: WeaponCombat = main.projectile_manager.combat
	var manager: ProjectileManager = main.projectile_manager
	var ids: Array[StringName] = [&"sword", &"lightning", &"star", &"boomerang",
		&"cannon", &"sprite", &"wave", &"scythe"]
	for id in ids:
		failures += _check(ContentDB.get_data(id) is WeaponTraitResource, "weapon exists: %s" % id)
	failures += _check(is_equal_approx((ContentDB.get_data(&"lightning") as WeaponTraitResource).damage_scale, 0.8),
		"lightning primary scale is 80 percent")
	var order_a := WeaponRuntime.new(player.weapon.core)
	var order_b := WeaponRuntime.new(player.weapon.core)
	for id in ids:
		order_a.acquire_form(id)
	var reverse_ids := ids.duplicate()
	reverse_ids.reverse()
	for id in reverse_ids:
		order_b.acquire_form(id)
	failures += _check(order_a.primary_form == &"sword" and order_b.primary_form == &"sword",
		"fixed primary priority is independent of acquisition order")
	failures += _check(order_a.primary_data().damage_scale == 2.5
		and order_a.primary_data().fire_rate_scale == 0.5,
		"sword scythe combo uses 250 percent damage and half attack speed")
	var enemy := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(&"chaser_square"), player, ColorType.GREEN)
	enemy.max_health = 100000.0
	enemy.health = enemy.max_health
	main.world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = player.global_position + Vector2(80.0, 0.0)
	player.set("_invuln", 999.0)

	_set_forms(player.weapon, [&"cannon"], &"cannon")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var cannon: Projectile = manager._active.back()
	failures += _check(is_equal_approx(cannon.speed,
		player.weapon.stats.get_value(&"projectile_speed") * 0.5), "cannon launches at half normal speed")
	var before := enemy.health
	cannon._on_body_entered(enemy)
	combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health < before and manager._active.is_empty(),
		"cannon explodes on impact without direct hit projectile")
	_set_forms(player.weapon, [&"cannon", &"star"], &"cannon")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var fused_cannon: Projectile = manager._active.back()
	fused_cannon._on_body_entered(enemy)
	combat._physics_process(1.0 / 60.0)
	var star_shards := 0
	for projectile in manager._active:
		if projectile.form_at_fire == &"star":
			star_shards += 1
	failures += _check(star_shards == 5,
		"cannon star fusion emits five star-behavior shards")
	for projectile in manager._active.duplicate():
		manager.release(projectile)

	_set_forms(player.weapon, [&"sprite"], &"sprite")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var sprite: Projectile = manager._active.back()
	sprite.global_position = enemy.global_position - Vector2(75.0, 0.0)
	sprite._physics_process(0.8)
	failures += _check(sprite.get("_sprite_dashing") and sprite.speed > 800.0,
		"sprite slows then seeks and dashes")
	sprite.set("_sprite_attacks_left", 2)
	sprite._on_body_entered(enemy)
	failures += _check(sprite.active_index >= 0 and int(sprite.get("_sprite_attacks_left")) == 1,
		"sprite can attack again when pierce grants another hit")
	manager.release(sprite)
	_set_forms(player.weapon, [&"sprite", &"boomerang"], &"sprite")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var returning_sprite: Projectile = manager._active.back()
	returning_sprite._on_body_entered(enemy)
	failures += _check(bool(returning_sprite.get("_returning")),
		"sprite boomerang returns after final hit")
	manager.release(returning_sprite)
	_set_forms(player.weapon, [&"sprite"], &"sprite")
	for i in 30:
		combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
			player.color_index, false, player.weapon)
	var batched_sprites := 0
	for projectile in manager._active:
		if projectile.batch_sprite:
			batched_sprites += 1
	failures += _check(manager.active_sprite_trails == 24 and batched_sprites == 6,
		"sprite trail budget keeps extra round shots in the batch")
	for projectile in manager._active.duplicate():
		manager.release(projectile)
	failures += _check(manager.active_sprite_trails == 0,
		"sprite trails return to the budget on release")

	_set_forms(player.weapon, [&"wave"], &"wave")
	before = enemy.health
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health == before and combat._wave_pulses.size() == 1,
		"wave launches one slow front without instantly hitting its full range")
	for i in 40:
		combat._physics_process(1.0 / 60.0)
	failures += _check(float(enemy.get("_water_drag_time")) > 0.0 and enemy.health < before
		and int(combat._wave_pulses[0].hits.get(enemy.get_instance_id(), 0)) == 3
		and combat._wave_pulses.size() == 1,
		"single moving wave hits three times with soft push and no wet")
	combat._wave_pulses.clear()
	failures += _check(float(enemy.get("_water_drag_time")) > 0.0 and float(enemy.get("_water_drag_time")) > 0.0,
		"water applies short soft push instead of permanent wet")

	_set_forms(player.weapon, [&"scythe"], &"scythe")
	before = enemy.health
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health < before, "scythe hits nearby enemies")

	failures += _check(not player.weapon.acquire_form(&"black_hole"), "black hole is no longer a weapon")
	_set_forms(player.weapon, [&"cannon", &"wave"], &"wave")
	before = enemy.health
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	for i in 40:
		combat._physics_process(1.0 / 60.0)
	failures += _check(enemy.health < before and float(enemy.get("_water_drag_time")) > 0.0,
		"wave and cannon fusion resolves queued explosion")
	combat._wave_pulses.clear()
	combat._scythe_sweeps.clear()
	combat._events.clear()
	combat._head = 0
	combat._process(1.0)
	_set_forms(player.weapon, [&"star", &"sprite"], &"star")
	enemy.global_position = player.global_position + Vector2(100.0, 80.0)
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	var guided: Projectile = manager._active.back()
	guided.set("_fusion_seek_clock", 0.0)
	guided._physics_process(1.0 / 60.0)
	failures += _check(guided.direction.y > 0.0 and guided.form_at_fire == &"star",
		"sprite fusion steers the original star projectile")
	for projectile in manager._active.duplicate():
		manager.release(projectile)
	enemy.global_position = player.global_position + Vector2(80.0, 0.0)
	_set_forms(player.weapon, [&"star", &"scythe"], &"star")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	failures += _check(combat._scythe_sweeps.is_empty(), "scythe secondary waits for impact")
	manager._active.back()._on_body_entered(enemy)
	combat._physics_process(1.0 / 60.0)
	failures += _check(not combat._scythe_sweeps.is_empty()
		and combat._scythe_sweeps.back().origin == enemy.global_position,
		"scythe fusion sweeps at the impact point")
	var secondary_event: Dictionary = combat._scythe_sweeps.back().duplicate()
	var sweep_count := combat._scythe_sweeps.size()
	combat._scythe(secondary_event)
	failures += _check(combat._scythe_sweeps.size() == sweep_count,
		"scythe secondary cooldown blocks repeated hits and shared clone procs")
	combat._physics_process(0.81)
	combat._scythe(secondary_event)
	failures += _check(combat._scythe_sweeps.size() == 1,
		"scythe secondary can trigger again after 0.8 seconds")
	for projectile in manager._active.duplicate():
		manager.release(projectile)
	combat._scythe_sweeps.clear()
	combat._process(1.0)
	combat._events.clear()
	combat._head = 0
	combat._derivative_frame = -1
	_set_forms(player.weapon, [&"scythe", &"boomerang"], &"scythe")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	combat._physics_process(1.0 / 60.0)
	combat._process(1.0 / 60.0)
	var sweep: Dictionary = combat._scythe_sweeps.back()
	failures += _check(sweep.get("trail") is Polygon2D
		and sweep.trail.polygon.size() > 20, "scythe has a real Polygon2D slash trail")
	before = enemy.health
	combat._physics_process(0.12)
	failures += _check(enemy.health == before, "scythe hits each enemy once during its sweep")
	combat._physics_process(0.54)
	combat._physics_process(1.0 / 60.0)
	failures += _check(combat._scythe_sweeps.size() == 1
		and bool(combat._scythe_sweeps[0].get("reverse", false)),
		"scythe boomerang reverses after the first sweep finishes")
	combat._scythe_sweeps.clear()
	combat._sword_waves.clear()
	combat._events.clear()
	combat._head = 0
	combat._delayed_hits.clear()
	_set_forms(player.weapon, [&"sword", &"wave"], &"sword")
	before = enemy.health
	combat.resolve_hit(combat, enemy, 100.0, player.color_index, Vector2.RIGHT,
		false, &"weapon_sword", true, true, true, &"sword", player.weapon,
		true, combat.new_budget())
	var direct_loss := before - enemy.health
	failures += _check(combat._delayed_hits.size() == 2, "water fusion schedules two extra slash judgments")
	combat._physics_process(0.11)
	combat._physics_process(0.12)
	failures += _check(is_equal_approx(before - enemy.health, direct_loss * 1.3),
		"water echoes each deal 15 percent without recursively triggering")
	_set_forms(player.weapon, [&"sword", &"scythe"], &"sword")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	combat._physics_process(1.0 / 60.0)
	failures += _check(combat._scythe_sweeps.size() == 1 and combat._sword_waves.is_empty(),
		"sword scythe begins with a slow scythe sweep")
	combat._physics_process(0.65)
	combat._physics_process(1.0 / 60.0)
	failures += _check(combat._sword_waves.size() == 1
		and float(combat._sword_waves[0].size_scale) == 1.6,
		"sword scythe releases a larger sword wave after the sweep")
	combat._sword_waves.clear()
	combat._scythe_sweeps.clear()
	combat._events.clear()
	combat._head = 0
	_set_forms(player.weapon, [&"sword", &"scythe", &"boomerang", &"cannon"], &"sword")
	combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
		player.color_index, false, player.weapon)
	combat._physics_process(1.0 / 60.0)
	combat._physics_process(0.65)
	combat._physics_process(1.0 / 60.0)
	failures += _check(combat._sword_waves.size() == 1 and bool(combat._sword_waves[0].can_return),
		"scythe sword finisher inherits boomerang without spawning a separate blade")
	var explosions := 0
	for event in combat._events:
		if event.kind == &"explosion":
			explosions += 1
	combat._derivative_frame = -1
	combat._advance_sword_waves(0.08)
	var after_explosions := 0
	for event in combat._events:
		if event.kind == &"explosion":
			after_explosions += 1
	failures += _check(after_explosions > explosions, "scythe sword finisher inherits cannon path blasts")
	var pair_failures := 0
	for primary in ids:
		for secondary in ids:
			if primary == secondary:
				continue
			var pair: Array[StringName] = [primary, secondary]
			_set_forms(player.weapon, pair, primary)
			enemy.health = enemy.max_health
			combat._events.clear()
			combat._head = 0
			combat._sword_waves.clear()
			combat._wave_pulses.clear()
			combat._scythe_sweeps.clear()
			combat._delayed_hits.clear()
			combat._process(1.0)
			combat._derivative_frame = -1
			for projectile in manager._active.duplicate():
				manager.release(projectile)
			combat.fire_weapon(player.global_position, Vector2.RIGHT, player.weapon.stats,
				player.color_index, false, player.weapon)
			combat._physics_process(1.0 / 60.0)
			if enemy.health >= enemy.max_health and combat._sword_waves.is_empty() and combat._wave_pulses.is_empty() \
					and manager._active.is_empty():
				pair_failures += 1
	failures += _check(pair_failures == 0, "all 56 ordered two-weapon forms can attack")
	for projectile in manager._active.duplicate():
		manager.release(projectile)
	combat._events.clear()
	combat._head = 0
	combat._sword_waves.clear()
	combat._wave_pulses.clear()
	combat._scythe_sweeps.clear()

	_set_forms(player.weapon, [], &"")
	failures += _check(main.weapon_choice_panel.open_reward(player, "test")
		and main.weapon_choice_panel._choices.size() == 3
		and main.weapon_choice_panel._scroll.custom_minimum_size.y <= 510.0,
		"weapon reward only offers three acquisition choices")
	main.weapon_choice_panel.visible = false
	combat._events.clear()
	combat._head = 0
	print("WEAPON EXPANSION TEST %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _set_forms(weapon: WeaponRuntime, ids: Array[StringName], primary: StringName) -> void:
	weapon.owned_forms.clear()
	weapon.traits.clear()
	weapon.primary_form = &""
	for id in ids:
		weapon.acquire_form(id)
	weapon.select_primary(primary)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("PASS ", label)
		return 0
	push_error("FAIL " + label)
	return 1

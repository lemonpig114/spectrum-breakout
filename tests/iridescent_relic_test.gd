extends Node

var failures := 0
var main: Node


func check(ok: bool, label: String) -> void:
	print("IRIDESCENT %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func mark_line(branch: StringName) -> void:
	for i in range(1, 5):
		var id := StringName("%s_%d" % [branch, i])
		Skills.unlocked[id] = Skills.get_node_by_id(id)


func mob(id: StringName, at: Vector2) -> Enemy:
	var enemy := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(id), main.player)
	main.world.add_child(enemy)
	enemy.global_position = at
	enemy.set_physics_process(false)
	return enemy


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	Director.stop()
	main.player.set_physics_process(false)
	main.player.controls_enabled = false
	main.player._invuln = 999.0
	var lucifer := Skills.get_relic(&"iridescent_lucifer")
	var michael := Skills.get_relic(&"iridescent_michael")
	check(lucifer.unique and michael.unique, "both new iridescent relics are unique")
	check(not Skills.shop_relic_pool().has(lucifer) and not Skills.shop_relic_pool().has(michael), "locked before all three branches are maxed")
	mark_line(&"path_demon")
	mark_line(&"giant")
	mark_line(&"crit")
	check(Skills.shop_relic_pool().has(lucifer) and not Skills.shop_relic_pool().has(michael), "Lucifer requires demon giant and crit")
	check(not Skills.shop_relic_pool(true).has(lucifer), "iridescent transformations are shop-only")
	Skills.shop_level = 6
	check(not Skills._shop_rarity_weights().has(4), "iridescent weight unavailable before highest shop level")
	Skills.shop_level = 7
	var weights := Skills._shop_rarity_weights()
	check(weights[4] == 0.005 and weights[1] == 0.495, "half-percent iridescent weight deducted from rare fifty percent")
	Skills._weapon_cache_offered = true
	RunState.rng.seed = 7246
	var appearances := 0
	for i in 10000:
		if Skills.shop_offers(1)[0].id == lucifer.id:
			appearances += 1
	print("IRIDESCENT sampled appearances=", appearances)
	check(absf(float(appearances) / 10000.0 - 0.005) < 0.003, "seeded highest-shop draws approximate half-percent iridescent rate")
	var panel: ShopPanel = main.shop_panel
	var dust := RelicResource.new()
	dust.price = 30
	var rare := RelicResource.new()
	rare.price = 60
	for seconds in [0.0, 180.0, 540.0, 1800.0]:
		RunState.elapsed = seconds
		Skills.shop_purchases = 20
		check(absi(panel._price_of(dust) * 2 - panel._price_of(rare)) <= 1, "common price multiplier preserves half-price dust")
	check(panel._price_of(Skills.get_relic(&"epic_weapon_cache")) == 0, "heirloom remains free under inflation")
	RunState.elapsed = 0.0
	Skills.guardian_shields = 5
	Skills.color_shield = 1
	var capacity: float = main.player.max_health
	check(Skills.grant_relic(lucifer.id), "Lucifer acquired")
	check(not Skills.grant_relic(lucifer.id), "Lucifer cannot be acquired twice")
	check(main.player.health == 0.5 and main.player.max_health == 0.5, "Lucifer locks current and maximum hearts to one half")
	check(Skills.demon_shields == int(capacity) and Skills.guardian_shields == 0 and Skills.color_shield == -1, "maximum hearts convert once and ordinary shields are removed")
	check(is_equal_approx(main.player.weapon.stats.get_value(&"damage_mult"), 4.0 + Skills.demon_shields * 0.1), "Lucifer grants three hundred percent plus current shield bonus")
	check(Skills._damage_source_key(&"relic_iridescent_lucifer_healing") == &"relic:iridescent_lucifer", "converted healing is attributed to Lucifer")
	Skills.add_guardian_shields(2)
	check(Skills.guardian_shields == 0, "ordinary shield gains are blocked")
	var damage: float = main.player.weapon.stats.get_value(&"damage")
	main.player.heal(0.5)
	main.player.heal(2.0)
	check(is_equal_approx(main.player.weapon.stats.get_value(&"damage") - damage, 25.0), "fractional and whole overhealing grant ten base damage per heart")
	check(main.player.weapon.stats.get_value(&"damage_final") == 2.0, "Lucifer final damage doubles")
	var count := Skills.demon_shields
	var modifier := StatModifierResource.new()
	modifier.stat = &"max_health"
	modifier.target = StatModifierResource.Target.PLAYER
	modifier.value = 1.0
	main.player.apply_stat_modifier(modifier)
	main.player.refresh_derived()
	main.player.refresh_derived()
	check(Skills.demon_shields == count + 1 and main.player.max_health == 0.5, "new maximum heart converts once without refresh duplication")
	if OS.get_cmdline_user_args().has("--preview"):
		await preview()
		return
	var boss := Director.spawn_boss_now(main.player.global_position + Vector2(300, 0))
	boss.set_physics_process(false)
	var boss_health := boss.health
	var triangle := mob(&"chaser_triangle", main.player.global_position + Vector2(400, 0))
	var hex := mob(&"chaser_hex", main.player.global_position + Vector2(400, 100))
	hex.rally_hex()
	var round_enemy := mob(&"chaser_round", main.player.global_position)
	Skills.demon_shields = 1
	Skills._sync_lucifer_bonuses()
	main.player._invuln = 0.0
	main.player.take_damage(1.0, triangle)
	check(main.player.health == 0.5 and not RunState.is_dead and Skills.demon_shields == 0, "demon shield absorbs hit before explosion deaths can recurse")
	check(triangle.is_dead and hex.is_dead and round_enemy.is_dead and boss.health == boss_health, "shield breaks kill all ordinary mobs including guarded hex but never bosses")
	Skills._tick_demon_shield(29.9)
	check(Skills.demon_shields == 0, "empty shield has a full thirty second cooldown")
	Skills._tick_demon_shield(0.1)
	Skills._tick_demon_shield(60.0)
	check(Skills.demon_shields == 1, "regeneration grants one shield and stops while one exists")
	GameSave.storage_path = "user://iridescent_test.dat"
	GameSave.clear_run()
	var saved_damage: float = main.player.weapon.stats.get_value(&"damage")
	var saved_shields := Skills.demon_shields
	check(GameSave.write_run(main) and GameSave.request_continue(), "Lucifer progress saves")
	main.queue_free()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Director.stop()
	main.player.set_physics_process(false)
	main.player._invuln = 999.0
	check(Skills.demon_shields == saved_shields and main.player.weapon.stats.get_value(&"damage") == saved_damage and main.player.max_health == 0.5, "continue restores converted health damage and shields without replay")
	main.player.refresh_derived()
	check(Skills.demon_shields == saved_shields, "continue refresh cannot duplicate shields")
	GameSave.clear_run()
	GameSave.storage_path = "user://run_save.dat"
	Skills.owned_relics.clear()
	Skills.unlocked.clear()
	michael = Skills.get_relic(&"iridescent_michael")
	mark_line(&"path_angel")
	mark_line(&"crit")
	check(not Skills.shop_relic_pool().has(michael), "Michael also requires weakness branch")
	mark_line(&"weak")
	check(Skills.shop_relic_pool().has(michael), "Michael unlocks with angel crit and weakness")
	var console := DebugConsole.new()
	add_child(console)
	console.setup(main)
	var old_crit: float = main.player.stats.get_value(&"crit_chance")
	console._submit("r 米迦勒")
	check(Skills.relic_count(michael.id) == 1, "console grants relic by Chinese name")
	check(is_equal_approx(main.player.stats.get_value(&"crit_chance") - old_crit, 0.5), "Michael adds fifty percentage points of critical chance")
	console._submit("r michael")
	check(Skills.relic_count(michael.id) == 1, "console respects unique relics")
	var target := mob(&"chaser_triangle", main.player.global_position + Vector2(200, 0))
	target.health = target.max_health * 0.59
	var context := DamageContext.new()
	context.target = target
	context.amount = 0.0
	target.take_damage(context)
	check(not target.is_dead, "ordinary hit cannot trigger Michael")
	context.add_tag(&"super_crit")
	target.health = target.max_health * 0.60
	target.take_damage(context)
	check(not target.is_dead, "Michael uses strict below sixty percent threshold")
	target.health = target.max_health * 0.59
	target.take_damage(context)
	check(target.is_dead, "super crit executes ordinary target below sixty percent")
	boss = Director.boss
	boss.set_physics_process(false)
	context.target = boss
	boss.health = boss.max_health * 0.30
	boss.take_damage(context)
	check(not boss.is_dead, "Boss exactly thirty percent survives zero-damage super crit")
	boss.health = boss.max_health * 0.29
	boss.take_damage(context)
	check(boss.is_dead, "super crit executes Boss below thirty percent")
	var hex_boss := Director.spawn_hex_boss_now(main.player.global_position + Vector2(300, 0))
	hex_boss.set_physics_process(false)
	for i in hex_boss.edge_health.size():
		hex_boss.edge_health[i] = hex_boss.edge_max_health * 0.29
	hex_boss._refresh_total()
	context.target = hex_boss
	context.color_index = -1
	hex_boss.take_damage(context)
	check(hex_boss.is_dead, "Michael explicitly executes hex Boss below thirty percent despite normal execution resistance")
	console.queue_free()
	print("IRIDESCENT RELIC TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func preview() -> void:
	for i in 6:
		mob(&"chaser_hex" if i % 2 == 0 else &"chaser_triangle", main.player.global_position + Vector2.from_angle(i * TAU / 6.0) * 230.0)
	var filename := "visual_lucifer_mobile.png" if GameInput.touch_controls_active else "visual_lucifer_desktop.png"
	if OS.get_cmdline_user_args().has("--shop"):
		main.shop_panel.open(main.player)
		main.shop_panel._offers.clear()
		for i in 11:
			main.shop_panel._offers.append(Skills.get_relic(&"iridescent_lucifer" if i == 0 else (&"iridescent_michael" if i == 1 else &"dust_knife")))
		main.shop_panel._offer_prices.clear()
		for relic in main.shop_panel._offers:
			main.shop_panel._offer_prices.append(main.shop_panel._price_of(relic))
		main.shop_panel._sold.resize(11)
		main.shop_panel._sold.fill(false)
		main.shop_panel._appear = 1.0
		main.shop_panel.queue_redraw()
		filename = "visual_iridescent_shop.png"
	else:
		FX.execution_number(main.player.global_position + Vector2(80, -70))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/" + filename)
	get_tree().quit()

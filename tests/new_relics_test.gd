extends Node

var failures := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	var player: Player = main.player
	player.controls_enabled = false
	player.set("_invuln", 999.0)

	var new_ids := [
		&"rare_dog_food", &"rare_ounce_soul", &"rare_mystery_gift",
		&"rare_high_bond", &"rare_bloody_bandage", &"epic_health_crystal",
		&"epic_vip_card", &"epic_war_arrow", &"epic_shield_generator",
		&"epic_classic_revolver", &"epic_prism", &"epic_water_candle",
		&"epic_travel_journal",
	]
	for id in new_ids:
		_check(Skills.get_relic(id) != null, "%s is in the catalog" % id)

	_check(Skills.grant_relic(&"rare_dog_food")
		and is_equal_approx(player.stats.get_value(&"summon_damage"), 1.15),
		"dog food boosts summon damage")
	_check(Skills.grant_relic(&"rare_ounce_soul") and Skills.soul_kills == 50,
		"ounce of soul adds fifty")
	var gold_before := RunState.gold
	_check(Skills.grant_relic(&"rare_high_bond") and RunState.gold == gold_before - 1000
		and is_equal_approx(Skills.gold_income(), 12.0),
		"high bond creates debt and fixed income")
	for _i in 3:
		Skills.grant_relic(&"rare_bloody_bandage")
	_check(is_equal_approx(Skills.damage_invuln_bonus(), 3.0)
		and not Skills.grant_relic(&"rare_bloody_bandage"),
		"blood bandage caps at three")

	var hearts_before := player.max_health
	_check(Skills.grant_relic(&"epic_health_crystal")
		and is_equal_approx(player.max_health, hearts_before + 1.0),
		"health crystal adds one maximum heart")
	var crit_before := Skills.get_crit_chance(null)
	var crit_damage_before := Skills.get_crit_damage(null)
	_check(Skills.grant_relic(&"epic_war_arrow")
		and is_equal_approx(Skills.get_crit_chance(null), crit_before + 0.15)
		and is_equal_approx(Skills.get_crit_damage(null), crit_damage_before + 0.30),
		"war arrow grants crit chance and damage")
	_check(Skills.grant_relic(&"epic_prism")
		and is_equal_approx(Skills.weakness_multiplier(), 2.0),
		"prism raises weakness multiplier")
	var panel: ShopPanel = main.shop_panel
	panel.open(player)
	var vip_offers: Array[RelicResource] = panel.get("_offers")
	var vip_prices: Array[int] = panel.get("_offer_prices")
	vip_offers[0] = Skills.get_relic(&"epic_vip_card")
	vip_prices[0] = 0
	panel._buy(0)
	_check(Skills.relic_count(&"epic_vip_card") == 1
		and Skills.shop_slots() == 5 and Skills.free_rerolls() == 3
		and (panel.get("_offers") as Array).size() == 5
		and int(panel.get("_free_rerolls")) == 3
		and not Skills.grant_relic(&"epic_vip_card"),
		"buying VIP immediately expands the shelf and adds two rerolls")
	panel.close()
	Skills.shop_level = 6
	_check(Skills.shop_slots() == 11 and Skills.can_upgrade_shop(),
		"VIP slot does not consume the last paid shop upgrade")
	Skills.shop_level = 7
	_check(Skills.shop_slots() == 12 and not Skills.can_upgrade_shop(),
		"VIP keeps an extra slot above the ordinary eleven-slot cap")
	Skills.shop_level = 0
	_check(Skills.grant_relic(&"epic_water_candle")
		and is_equal_approx(Director.spawn_rate(0.0), 3.6),
		"water candle increases real spawn rate")
	Skills.grant_relic(&"epic_travel_journal")
	RunState.level = 10
	RunState.xp = 0
	gold_before = RunState.gold
	Skills.on_player_moved(499.0)
	_check(RunState.gold == gold_before, "travel journal waits for full distance")
	Skills.on_player_moved(1.0)
	_check(RunState.gold == gold_before + 5 and RunState.xp == 6,
		"travel journal pays gold and experience")

	_check(Skills.grant_relic(&"epic_shield_generator"), "shield generator can be picked")
	RunState.energy = RunState.max_energy
	var next_color := ColorType.next(RunState.color_index, 1)
	_check(RunState.select_color(next_color) and is_equal_approx(RunState.energy, RunState.max_energy - 2.0)
		and Skills.color_shield == next_color,
		"switch costs two energy and creates a color shield")
	var source := Enemy.new()
	source.color_index = ColorType.next(next_color, 1)
	_check(not Skills.try_color_shield(source) and Skills.color_shield == next_color,
		"other colors do not consume the shield")
	source.color_index = next_color
	var health_before := player.health
	player.set("_invuln", 0.0)
	player.take_damage(1.0, source)
	_check(Skills.color_shield < 0 and is_equal_approx(player.health, health_before),
		"matching attack is blocked without health loss")
	source.free()
	player.set("_invuln", 0.0)
	player.take_damage(0.5)
	_check(is_equal_approx(float(player.get("_invuln")), 4.0),
		"three bandages extend real damage invulnerability to four seconds")

	_check(Skills.grant_relic(&"epic_classic_revolver"), "classic revolver can be picked")
	RunState.energy = RunState.max_energy
	_check(RunState.cycle_color(1), "revolver triggers on switching")
	var before_shots := (player.projectile_manager.get("_active") as Array).size()
	Skills._tick_revolver(0.6)
	var after_shots := (player.projectile_manager.get("_active") as Array).size()
	_check(after_shots - before_shots == 15, "one revolver makes fifteen sequential bullets")

	var saved_relics: Array[RelicResource] = Skills.relics.duplicate()
	Skills.relics = [Skills.get_relic(&"rare_mystery_gift"), Skills.get_relic(&"epic_health_crystal")]
	var crystals_before := Skills.relic_count(&"epic_health_crystal")
	_check(Skills.grant_relic(&"rare_mystery_gift")
		and Skills.relic_count(&"epic_health_crystal") == crystals_before + 1
		and Skills.relic_count(&"rare_mystery_gift") == 0,
		"mystery gift grants another relic without occupying a slot")
	Skills.relics = saved_relics
	var soul_target := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	soul_target.configure(ContentDB.get_enemy(&"chaser_hex"), player, ColorType.RED)
	main.world.add_child(soul_target)
	soul_target.health = 100.0
	Skills.soul_kills = 50
	_check(Skills.grant_relic(&"demon_soul_blade"),
		"soul blade needs no soul or circle skill")
	_check(Skills.get_relic(&"demon_soul_blade").rarity == RelicResource.RARITY_EPIC
		and Skills.get_relic(&"demon_soul_blade").unique
		and not Skills.grant_relic(&"demon_soul_blade"),
		"soul blade is a unique epic relic")
	Skills._apply_soul_blade_hit(soul_target)
	_check(is_equal_approx(soul_target.health, 100.0 - 0.25 * 55.0 * 0.70),
		"soul blade uses one quarter of soul count plus five")
	soul_target.queue_free()

	print("NEW RELICS TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", message)

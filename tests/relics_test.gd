extends Node

## 遗物专项无头测试：
## godot --headless --fixed-fps 60 --path . res://tests/relics_test.tscn
##
## 覆盖尘灰遗物的数值、默认可重复拾取并叠加、唯一遗物拒绝重复、
## 一次性物品（苹果）不占栏、钝刀片的扣血，以及恶魔/天使遗物的“颗心”单位。

var failures := 0
var main: Node
var player: Player


func _ready() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	main = main_scene.instantiate()
	add_child(main)

	await get_tree().create_timer(2.4).timeout
	Director.stop()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

	player = main.player
	player.set("_invuln", 999.0)
	failures += _check(player != null, "player exists")

	_test_catalog()
	_test_crit_relics()
	_test_damage_rate_relics()
	_test_consumables()
	_test_utility_relics()
	_test_lucky_relics()
	_test_extended_relics()
	_test_impact_releaser()
	_test_heart_scale_relics()
	_test_impact_weakness_synergy()
	_test_new_relics()

	print("RELIC TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_catalog() -> void:
	var dust := 0
	var sided := 0
	var neutral := 0
	for relic in Skills.relics:
		if relic.side == &"":
			neutral += 1
			if relic.rarity == RelicResource.RARITY_DUST:
				dust += 1
		else:
			sided += 1
	failures += _check(Skills.relics.size() == 55, "55 relics in the catalog")
	failures += _check(dust == 10, "10 dust-tier relics")
	failures += _check(neutral == 51, "51 neutral relics")
	failures += _check(sided == 4, "4 demon/angel relics")

	var unique_sided := 0
	var repeatable_neutral := 0
	for relic in Skills.relics:
		if relic.unique and relic.side != &"":
			unique_sided += 1
		if not relic.unique and relic.side == &"":
			repeatable_neutral += 1
	failures += _check(unique_sided == 4, "demon/angel relics are marked unique")
	failures += _check(repeatable_neutral == 40, "most neutral relics are repeatable")
	failures += _check(
		Skills.get_relic(&"dust_knife").repeat_label() == ""
			and Skills.get_relic(&"demon_pointed_vessel").repeat_label() == "唯一",
		"repeat_label exposes the 唯一 tag"
	)
	failures += _check(Skills.get_relic(&"dust_apple") != null, "get_relic finds dust apple")
	failures += _check(Skills.get_relic(&"missing_relic") == null, "get_relic returns null for unknown ids")


func _test_crit_relics() -> void:
	var crit_damage := player.stats.get_value(&"crit_damage")
	failures += _check(Skills.grant_relic(&"dust_knife"), "knife can be picked up")
	failures += _check(
		is_equal_approx(player.stats.get_value(&"crit_damage"), crit_damage + 0.15),
		"knife grants +15% crit damage"
	)
	failures += _check(Skills.relic_count(&"dust_knife") == 1, "relic_count tracks the first pickup")
	failures += _check(Skills.grant_relic(&"dust_knife"), "duplicate dust relic can be picked up")
	failures += _check(
		is_equal_approx(player.stats.get_value(&"crit_damage"), crit_damage + 0.30),
		"duplicate dust relic stacks its effect"
	)
	failures += _check(Skills.relic_count(&"dust_knife") == 2, "relic_count increments on duplicates")

	var owned := Skills.owned_relics.size()
	var crit_chance := player.stats.get_value(&"crit_chance")
	failures += _check(Skills.grant_relic(&"dust_paper_star"), "paper star can be picked up")
	failures += _check(
		is_equal_approx(player.stats.get_value(&"crit_chance"), crit_chance + 0.05),
		"paper star grants +5% crit chance"
	)
	failures += _check(Skills.owned_relics.size() == owned + 1, "paper star occupies a relic slot")
	failures += _check(Skills.grant_relic(&"dust_paper_star") and Skills.grant_relic(&"dust_paper_star")
		and not Skills.grant_relic(&"dust_paper_star"), "paper star caps at three")
	failures += _check(Skills.grant_relic(&"dust_knife") and Skills.grant_relic(&"dust_knife")
		and Skills.relic_count(&"dust_knife") == 4, "knife has no stack cap")
	failures += _check(Skills.grant_relic(&"rare_three_leaf")
		and not Skills.grant_relic(&"rare_three_leaf"),
		"three-leaf clover is available before luck tier one and unique")


func _test_damage_rate_relics() -> void:
	var damage := player.weapon.stats.get_value(&"damage")
	var rate := player.weapon.stats.get_value(&"fire_rate_mult")
	failures += _check(Skills.grant_relic(&"dust_iron_glove"), "iron glove can be picked up")
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"damage"), damage + 3.0),
		"iron glove grants +3 flat damage"
	)
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate - 0.05),
		"iron glove costs 5% fire rate"
	)

	var flat_damage := player.weapon.stats.get_value(&"damage")
	var rate_before := player.weapon.stats.get_value(&"fire_rate_mult")
	failures += _check(Skills.grant_relic(&"dust_cloth_glove"), "cloth glove can be picked up")
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"damage"), flat_damage - 3.0),
		"cloth glove costs 3 flat damage"
	)
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate_before + 0.15),
		"cloth glove grants +15% fire rate"
	)


func _test_consumables() -> void:
	failures += _check(Skills.get_relic(&"dust_knife").max_stacks == 0, "knife has no stack cap")
	failures += _check(Skills.get_relic(&"dust_paper_star").max_stacks == 3, "paper star caps at three")
	failures += _check(Skills.get_relic(&"dust_running_shoes").max_stacks == 3, "running shoes cap at three")
	failures += _check(Skills.get_relic(&"rare_reroll").max_stacks == 10, "reroll caps at ten")
	failures += _check(Skills.get_relic(&"rare_feast").rarity == RelicResource.RARITY_EPIC, "feast is epic")
	failures += _check(Skills.get_relic(&"rare_feast").max_stacks == 3, "feast caps at three")
	var owned := Skills.owned_relics.size()
	player.health = 2.0
	var max_health := player.max_health
	var expected := Player.snap_to_half(minf(max_health, 2.0 + 2.0))
	failures += _check(Skills.grant_relic(&"dust_apple"), "apple can be eaten")
	failures += _check(is_equal_approx(player.health, expected), "apple heals two hearts")
	failures += _check(Skills.owned_relics.size() == owned, "consumable does not occupy a slot")
	failures += _check(Skills.grant_relic(&"dust_apple"), "a second apple is allowed")

	player.health = 4.0
	var damage := player.weapon.stats.get_value(&"damage")
	failures += _check(Skills.grant_relic(&"dust_blunt_blade"), "blunt blade can be picked up")
	failures += _check(is_equal_approx(player.health, 3.0), "blunt blade costs one heart")
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"damage"), damage + 5.0),
		"blunt blade grants +5 flat damage"
	)


func _test_utility_relics() -> void:
	var speed := player.stats.get_value(&"move_speed")
	failures += _check(Skills.grant_relic(&"dust_running_shoes"), "running shoes can be picked up")
	failures += _check(
		is_equal_approx(player.stats.get_value(&"move_speed"), speed * 1.05),
		"running shoes grant +5% move speed"
	)

	var rate := player.weapon.stats.get_value(&"fire_rate_mult")
	var crit_chance := player.stats.get_value(&"crit_chance")
	var crit_damage := player.stats.get_value(&"crit_damage")
	failures += _check(Skills.grant_relic(&"dust_blindfold"), "blindfold can be picked up")
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate + 0.20),
		"blindfold grants +20% fire rate"
	)
	failures += _check(
		is_equal_approx(player.stats.get_value(&"crit_chance"), crit_chance - 0.03),
		"blindfold costs 3% crit chance"
	)
	failures += _check(
		is_equal_approx(player.stats.get_value(&"crit_damage"), crit_damage - 0.07),
		"blindfold costs 7% crit damage"
	)


func _test_lucky_relics() -> void:
	failures += _check(
		not Skills.grant_relic(&"rare_four_leaf"),
		"lucky relics cannot be picked before luck tier 1"
	)
	Skills.unlock(&"luck_1", true)
	var luck := Skills.luck()
	failures += _check(Skills.grant_relic(&"rare_four_leaf"), "four-leaf clover can be picked after luck 1")
	failures += _check(is_equal_approx(Skills.luck(), luck + 4.0), "four-leaf clover grants +4 luck")

	failures += _check(Skills.grant_relic(&"rare_bullet_shell"), "bullet shell can be picked")
	failures += _check(Skills.grant_relic(&"rare_bullet_shell"), "bullet shell stacks to 2")
	failures += _check(Skills.grant_relic(&"rare_bullet_shell"), "bullet shell stacks to 3")
	failures += _check(
		not Skills.grant_relic(&"rare_bullet_shell"),
		"bullet shell rejects a fourth stack"
	)
	failures += _check(Skills.relic_count(&"rare_bullet_shell") == 3, "bullet shell caps at three copies")
	failures += _check(is_equal_approx(Skills.chain_fire_chance(), 0.30), "three shells give 30% chain fire")

	var free_before := Skills.free_rerolls()
	failures += _check(Skills.grant_relic(&"rare_reroll"), "reroll relic can be picked")
	failures += _check(Skills.free_rerolls() == free_before + 1, "reroll relic grants a free reroll")

	var bond_gold := RunState.gold
	failures += _check(Skills.grant_relic(&"rare_bond"), "bond can be picked")
	failures += _check(RunState.gold == bond_gold - 300, "bond deducts 300 gold after pickup and may create debt")
	failures += _check(is_equal_approx(Skills.gold_income(), 3.0), "bond pays three gold per second")
	var gold_gain_base := player.stats.get_base(&"gold_gain")
	player.stats.set_base(&"gold_gain", 2.0)
	RunState.set("_income_accum", 0.0)
	var before_interest := RunState.gold
	RunState._process(1.0)
	failures += _check(RunState.gold == before_interest + 3,
		"bond interest ignores the gold gain multiplier")
	player.stats.set_base(&"gold_gain", gold_gain_base)

	failures += _check(Skills.get_relic(&"rare_pocket_watch") == null,
		"pocket watch is removed from the relic pool")


## 人类用.md 第二页的蓝色遗物：生命上限、金块、肾上腺素、大餐、骰子、透镜、盔甲、吸铁石。
func _test_extended_relics() -> void:
	var max_health := player.max_health
	player.health = 0.5
	failures += _check(Skills.grant_relic(&"rare_golden_apple"), "golden apple can be picked")
	failures += _check(
		is_equal_approx(player.max_health, max_health),
		"golden apple does not change max health"
	)
	failures += _check(is_equal_approx(player.health, player.max_health), "golden apple heals to full")

	var speed := player.stats.get_value(&"move_speed")
	var damage_mult := player.weapon.stats.get_value(&"damage_mult")
	var radius := player.body_radius
	max_health = player.max_health
	failures += _check(Skills.grant_relic(&"rare_feast"), "feast can be picked")
	failures += _check(
		is_equal_approx(player.max_health, max_health + 1.0),
		"feast grants one heart of max health"
	)
	failures += _check(
		is_equal_approx(player.stats.get_value(&"move_speed"), speed * 0.95 / 1.05),
		"feast costs 10% move speed"
	)
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), damage_mult + 0.30),
		"feast grants +30% damage multiplier"
	)
	failures += _check(player.body_radius > radius, "feast slightly enlarges the body")

	var gold_before := RunState.gold
	failures += _check(
		Skills.shop_relic_pool().all(func(relic): return relic.id != &"rare_gold_nugget"),
		"gold nugget never appears on the shop shelf"
	)
	failures += _check(
		Skills.shop_relic_pool(true).any(func(relic): return relic.id == &"rare_gold_nugget"),
		"gold nugget is available to the chest pool"
	)
	failures += _check(Skills.grant_relic(&"rare_gold_nugget"), "gold nugget can be opened from a chest")
	failures += _check(RunState.gold >= gold_before + 500, "gold nugget pays 500 gold")

	failures += _check(Skills.grant_relic(&"rare_prism_lens"), "three-color lens can be picked")
	failures += _check(
		is_equal_approx(Skills.lens_damage_bonus(ColorType.RED), 0.15),
		"lens adds +15% damage multiplier to red attacks"
	)
	failures += _check(
		is_equal_approx(Skills.lens_damage_bonus(ColorType.BLUE), 0.15),
		"lens adds +15% damage multiplier to blue attacks"
	)
	failures += _check(
		is_equal_approx(Skills.lens_damage_bonus(ColorType.GREEN), 0.15),
		"lens also affects green attacks"
	)

	var old_health := player.health
	player.health = 3.5
	failures += _check(Skills.grant_relic(&"rare_cracked_armor"), "cracked armor can be picked")
	failures += _check(
		is_equal_approx(Skills.cracked_armor_bonus(), (player.max_health - 3.5) * 0.05),
		"cracked armor grants 5% damage multiplier per missing heart"
	)
	failures += _check(Skills.grant_relic(&"rare_cracked_armor"), "cracked armor stacks")
	failures += _check(
		is_equal_approx(Skills.cracked_armor_bonus(), (player.max_health - 3.5) * 0.10),
		"a second cracked armor doubles the bonus"
	)
	player.health = old_health

	var damage_mult_before := player.weapon.stats.get_value(&"damage_mult")
	failures += _check(Skills.grant_relic(&"rare_adrenaline"), "adrenaline can be picked")
	EventBus.player_damaged.emit(0.5)
	failures += _check(
		player.weapon.stats.get_value(&"damage_mult") >= damage_mult_before + 0.99,
		"taking damage triggers +100% adrenaline damage"
	)
	Skills._tick_adrenaline(10.0)
	failures += _check(
		player.weapon.stats.get_value(&"damage_mult") <= damage_mult_before + 0.51,
		"adrenaline fades linearly after half its duration"
	)
	Skills._tick_adrenaline(10.0)
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), damage_mult_before),
		"adrenaline expires after twenty seconds"
	)

	failures += _check(Skills.grant_relic(&"rare_fate_dice"), "fate dice can be picked")
	failures += _check(
		Skills.dice_roll() >= 1 and Skills.dice_roll() <= 6,
		"fate dice immediately rolls a d6"
	)
	Skills._dice_time = 0.01
	Skills._tick_dice(0.1)
	failures += _check(
		Skills.dice_roll() >= 1 and Skills.dice_roll() <= 6,
		"fate dice rerolls every ten seconds"
	)

	var regen_before := Skills.energy_regen_multiplier()
	failures += _check(Skills.grant_relic(&"rare_battery"), "battery can be picked")
	failures += _check(
		is_equal_approx(Skills.energy_regen_multiplier(), regen_before + 0.20),
		"battery grants +20% energy regeneration"
	)

	var radius_before := Skills.pickup_radius_multiplier()
	failures += _check(Skills.grant_relic(&"dust_magnet"), "magnet can be picked")
	failures += _check(
		is_equal_approx(Skills.pickup_radius_multiplier(), radius_before + 0.30),
		"magnet grants +30% pickup range"
	)
	for tier in range(1, 5):
		Skills.unlock(StringName("xp_%d" % tier), true)
	failures += _check(
		Skills.shop_relic_pool().all(func(relic): return relic.id != &"dust_magnet"),
		"magnet leaves the shop once the xp line is maxed"
	)


## 冲击释放器：切换形态时只打击新形态克制、且在半径内的敌人；
## 可以暴击，但即使开了强制超暴击也不能变成超暴击。
func _test_impact_releaser() -> void:
	RunState.energy = RunState.max_energy
	if RunState.color_index != ColorType.RED:
		RunState.select_color(ColorType.RED)
	failures += _check(RunState.color_index == ColorType.RED, "impact test starts from red")

	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var weak_enemy: Enemy = enemy_scene.instantiate()
	weak_enemy.configure(ContentDB.get_enemy(&"chaser_hex"), player, ColorType.BLUE)
	main.world.add_child(weak_enemy)
	weak_enemy.global_position = player.global_position + Vector2(60.0, 0.0)
	weak_enemy.health = 9999.0

	var same_enemy: Enemy = enemy_scene.instantiate()
	same_enemy.configure(ContentDB.get_enemy(&"chaser_square"), player, ColorType.GREEN)
	main.world.add_child(same_enemy)
	same_enemy.global_position = player.global_position + Vector2(0.0, 70.0)
	same_enemy.health = 9999.0

	var far_enemy: Enemy = enemy_scene.instantiate()
	far_enemy.configure(ContentDB.get_enemy(&"chaser_hex"), player, ColorType.BLUE)
	main.world.add_child(far_enemy)
	far_enemy.global_position = player.global_position + Vector2(500.0, 0.0)
	far_enemy.health = 9999.0

	failures += _check(Skills.grant_relic(&"rare_impact_releaser"), "impact releaser can be picked")
	RunState.energy = RunState.max_energy
	failures += _check(RunState.cycle_color(1), "impact test switches red to green")
	failures += _check(
		is_equal_approx(RunState.color_index, ColorType.GREEN),
		"impact test is green after switching"
	)
	failures += _check(weak_enemy.health < 9999.0, "impact hits enemies weak to the new color")
	failures += _check(
		9999.0 - weak_enemy.health >= Skills.impact_base_damage(ColorType.GREEN) * 2.0
			* Skills.weakness_multiplier() * weak_enemy.armor_multiplier() - 0.01,
		"impact deals at least 200 percent weapon damage before possible crit"
	)
	failures += _check(
		is_equal_approx(same_enemy.health, 9999.0),
		"impact ignores enemies the new color does not counter"
	)
	failures += _check(
		is_equal_approx(far_enemy.health, 9999.0),
		"impact ignores countered enemies outside its radius"
	)

	var old_crit := player.stats.get_value(&"crit_chance")
	player.stats.set_base(&"crit_chance", 0.0)
	var normal_context := Skills.build_hit_context(player, weak_enemy, 10.0, ColorType.GREEN, false, false)
	failures += _check(
		is_equal_approx(normal_context.amount, 10.0 * Skills.weakness_multiplier()),
		"weakness multiplier is applied to the supplied impact damage"
	)

	player.stats.set_base(&"crit_chance", 1.0)
	Skills.debug_force_super_crit = true
	var context := Skills.build_hit_context(player, weak_enemy, 10.0, ColorType.GREEN, false)
	failures += _check(context.is_crit, "impact damage can crit")
	failures += _check(not context.has_tag(&"super_crit"), "impact damage can never super crit")
	Skills.debug_force_super_crit = false
	player.stats.set_base(&"crit_chance", old_crit)

	failures += _check(Skills.grant_relic(&"rare_impact_releaser"), "impact releaser stacks")
	failures += _check(Skills.relic_count(&"rare_impact_releaser") == 2, "impact releaser counts two copies")

	weak_enemy.queue_free()
	same_enemy.queue_free()
	far_enemy.queue_free()


func _test_heart_scale_relics() -> void:
	var max_health := player.max_health
	failures += _check(Skills.grant_relic(&"demon_pointed_vessel"), "pointed vessel can be picked up")
	failures += _check(is_equal_approx(player.health, 0.5), "pointed vessel sets current health to half a heart")
	failures += _check(is_equal_approx(player.max_health, max_health), "pointed vessel preserves maximum health")
	Skills._tick_pointed_vessel()
	failures += _check(player.weapon.stats.get_value(&"damage") > player.weapon.core.damage,
		"pointed vessel converts missing health to flat damage")

	failures += _check(
		not Skills.grant_relic(&"demon_pointed_vessel"),
		"unique relic rejects a second copy"
	)
	failures += _check(
		is_equal_approx(player.max_health, max_health),
		"rejected duplicate leaves stats untouched"
	)

	failures += _check(Skills.grant_relic(&"angel_guardian"), "guardian can be picked up")
	failures += _check(Skills.guardian_shields == 2, "guardian grants two shields")
	failures += _check(Skills.try_guardian_shield() and Skills.guardian_shields == 1,
		"one shield absorbs a whole hit")


func _test_new_relics() -> void:
	failures += _check(is_equal_approx(Skills.lottery_chance(), minf(0.09, 0.03 * (1.0 + Skills.luck() * 0.01))),
		"lottery scales from three percent with luck")
	failures += _check(Skills.get_relic(&"dust_lottery").consumable, "lottery is a one-use draw")
	var crit := player.stats.get_value(&"crit_chance")
	var crit_damage := player.stats.get_value(&"crit_damage")
	failures += _check(Skills.grant_relic(&"rare_flint"), "flint can be picked")
	failures += _check(is_equal_approx(player.stats.get_value(&"crit_chance"), crit + 0.05)
		and is_equal_approx(player.stats.get_value(&"crit_damage"), crit_damage + 0.15),
		"flint grants crit chance and crit damage")
	var xp_rate := Skills.xp_multiplier()
	var gold_rate := Skills.gold_multiplier()
	Skills.grant_relic(&"rare_dictionary")
	Skills.grant_relic(&"rare_silver_coin")
	failures += _check(is_equal_approx(Skills.xp_multiplier(), xp_rate * 1.15), "dictionary adds 15% XP gain")
	failures += _check(is_equal_approx(Skills.gold_multiplier(), gold_rate + 0.15), "silver coin adds gold gain")
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var target := enemy_scene.instantiate() as Enemy
	target.configure(ContentDB.get_enemy(&"chaser_triangle"), player)
	main.world.add_child(target)
	target.global_position = player.global_position + Vector2(350.0, 0.0)
	target.max_health = 10000.0
	target.health = 10000.0
	for data in [
		[&"rare_poison_arrow", ColorType.GREEN, &"arrow_poison"],
		[&"rare_frost_arrow", ColorType.BLUE, &"arrow_frost"],
		[&"rare_burning_arrow", ColorType.RED, &"arrow_burning"],
	]:
		var relic := Skills.get_relic(data[0])
		failures += _check(relic.offer_weight == 0.5 and relic.unique, "arrow has half offer weight and one-copy cap")
		Skills.grant_relic(data[0])
		var health_before := target.health
		Skills._apply_arrow_hit(target, data[1], data[2])
		failures += _check(target.health < health_before, "arrow deals direct colored damage")
	Skills.grant_relic(&"demon_soul_blade")
	var soul_before := Skills.soul_kills
	target.health = 1.0
	Skills._apply_soul_blade_hit(target)
	failures += _check(target.is_dead and Skills.soul_kills == soul_before + 1,
		"soul blade soul hit grants a soul on kill")
	player.health = 2.0
	player.set("_invuln", 0.0)
	player.take_damage(2.0)
	failures += _check(is_equal_approx(player.health, 2.0) and Skills.guardian_shields == 0,
		"guardian shield blocks a full lethal hit")
	target.queue_free()


## 冲击释放器按一次“弱点命中”结算，弱 3 的元素附着与弱 4 的处决都应生效。
func _test_impact_weakness_synergy() -> void:
	for tier in range(1, 4):
		Skills.unlock(StringName("weak_%d" % tier), true)
	RunState.energy = RunState.max_energy
	if RunState.color_index != ColorType.RED:
		RunState.select_color(ColorType.RED)

	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var target: Enemy = enemy_scene.instantiate()
	target.configure(ContentDB.get_enemy(&"chaser_hex"), player, ColorType.BLUE)
	main.world.add_child(target)
	target.global_position = player.global_position + Vector2(60.0, 0.0)
	target.max_health = 9999.0
	target.health = 9999.0

	RunState.energy = RunState.max_energy
	failures += _check(RunState.cycle_color(1), "synergy test switches red to green")
	failures += _check(
		float(target.get("_poison_dps")) > 0.0,
		"impact weakness hit triggers the weak tier 3 elemental status"
	)
	failures += _check(not target.is_dead, "impact weakness hit does not execute before tier 4")

	Skills.unlock(&"weak_4", true)
	var execute_target: Enemy = enemy_scene.instantiate()
	execute_target.configure(ContentDB.get_enemy(&"chaser_hex"), player, ColorType.BLUE)
	main.world.add_child(execute_target)
	execute_target.global_position = player.global_position + Vector2(80.0, 0.0)
	# 远高于冲击伤害，但生命比例低于 15%，满足弱 4 的处决阈值。
	execute_target.max_health = 1000000.0
	execute_target.health = 1000.0

	RunState.energy = RunState.max_energy
	RunState.select_color(ColorType.RED)
	RunState.energy = RunState.max_energy
	failures += _check(RunState.cycle_color(1), "synergy test switches to green again")
	failures += _check(
		execute_target.is_dead,
		"impact weakness hit triggers the weak tier 4 execution"
	)

	target.queue_free()
	execute_target.queue_free()


func _check(condition: bool, label: String) -> int:
	if condition:
		print("RELIC PASS  %s" % label)
		return 0
	print("RELIC FAIL  %s" % label)
	return 1

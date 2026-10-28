extends Node

## 技能树专项无头测试：
## godot --headless --fixed-fps 60 --path . res://tests/skills_test.tscn
##
## 覆盖解锁规则、11 条线的静态/动态效果、恶魔/天使互斥与遗物翻倍、
## 暴击/闪避、元素状态、溅射、灵魂真实伤害、处决。

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

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
	failures += _check(player != null, "player exists")
	failures += _check(not get_tree().paused, "run is not paused before skill tests")

	_test_catalog_rules()
	_test_fire_line()
	_test_spread_line()
	_test_heavy_line()
	_test_energy_line()
	_test_speed_line()
	_test_shotgun_line()
	_test_luck_line()
	_test_path_line()
	_test_xp_gold_lines()
	_test_soul_line()
	_test_splash_line()
	_test_weakness_line()
	_test_elemental_pipeline()
	_test_crit_line()
	_test_forced_super_crit()
	_test_combat_helpers()
	await _test_projectile_pipeline()

	print("SKILL TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_catalog_rules() -> void:
	failures += _check(Skills.nodes.size() == 76, "76 skill nodes")
	failures += _check(Skills.relics.size() == 52, "52 relics")
	failures += _check(Skills.get_available_nodes().size() == 19, "all nineteen tier-1 nodes start available")

	failures += _check(Skills.is_available(Skills.get_node_by_id(&"fire_1")), "tier 1 available")
	failures += _check(not Skills.is_available(Skills.get_node_by_id(&"fire_2")), "tier 2 gated by tier 1")
	failures += _check(not Skills.is_available(Skills.get_node_by_id(&"fire_4")), "tier 4 gated by 2 and 3")
	failures += _check(Skills.is_available(Skills.get_node_by_id(&"path_demon_1")), "demon path available")
	failures += _check(Skills.is_available(Skills.get_node_by_id(&"path_angel_1")), "angel path available")

	_unlock(&"fire_1")
	failures += _check(Skills.is_available(Skills.get_node_by_id(&"fire_2")), "tier 2 opens after tier 1")
	failures += _check(Skills.is_available(Skills.get_node_by_id(&"fire_3")), "tier 3 opens after tier 1")
	failures += _check(not Skills.is_available(Skills.get_node_by_id(&"fire_4")), "tier 4 still locked without 2 and 3")
	_unlock(&"fire_2")
	_unlock(&"fire_3")
	failures += _check(Skills.is_available(Skills.get_node_by_id(&"fire_4")), "tier 4 opens after 2 and 3")


func _test_fire_line() -> void:
	var rate_before := player.weapon.get_final_fire_rate()
	failures += _check(rate_before > 3.0, "fire line raises fire rate")
	_unlock(&"fire_4")
	failures += _check(is_equal_approx(Skills.fire_rate_cap_multiplier(), 9.0), "fire cap triples")
	failures += _check(player.weapon.stats.get_value(&"damage_mult") < 1.0, "overdrive trades damage for speed")


## 单发子弹也必须吃到 spread_degrees：曾经只有 count > 1 才应用偏移。
func _test_spread_line() -> void:
	player.controls_enabled = false
	var spread_degrees := player.weapon.stats.get_value(&"spread_degrees")
	failures += _check(is_equal_approx(spread_degrees, 7.0), "fire tier 3 adds 7 degrees spread")

	var manager: ProjectileManager = main.projectile_manager
	var before := manager._active.size()
	for i in 30:
		player._fire(Vector2.RIGHT)
	var fired := manager._active.size() - before
	failures += _check(fired >= 30, "spread test fires 30 projectiles")

	var max_deviation := 0.0
	var cone_limit := deg_to_rad(spread_degrees * 0.5) + 0.0001
	for i in range(manager._active.size() - fired, manager._active.size()):
		var projectile: Projectile = manager._active[i]
		max_deviation = maxf(
			max_deviation,
			absf(projectile.direction.angle_to(Vector2.RIGHT))
		)
	failures += _check(max_deviation > 0.0005, "single-shot spread deviates from aim direction")
	failures += _check(max_deviation <= cone_limit, "single-shot spread stays inside the cone")

	for i in range(manager._active.size() - 1, -1, -1):
		manager.release(manager._active[i])


func _test_heavy_line() -> void:
	var damage_before := player.weapon.get_final_damage()
	var mult_before := player.weapon.stats.get_value(&"damage_mult")
	_unlock(&"heavy_1")
	failures += _check(is_equal_approx(player.weapon.stats.get_value(&"damage"), 20.0), "heavy tier 1 adds 10 flat damage")
	failures += _check(is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), mult_before + 0.20), "heavy tier 1 adds 20% multiplier")
	var rate_before := player.weapon.stats.get_value(&"fire_rate_mult")
	_unlock(&"heavy_2")
	failures += _check(is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate_before - 0.20), "heavy tier 2 trades 20% fire rate")
	_unlock(&"heavy_3")
	failures += _check(player.weapon.get_final_damage() > damage_before, "heavy line raises damage")
	failures += _check(int(player.weapon.stats.get_value(&"pierce")) >= 1, "heavy tier 3 adds pierce")
	_unlock(&"heavy_4")
	failures += _check(is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), mult_before + 1.10), "heavy tiers add 110% total multiplier")
	failures += _check(is_equal_approx(player.weapon.stats.get_value(&"damage_final"), 1.20), "heavy tier 4 adds 20% absolute multiplier")
	failures += _check(Skills.heavy_shot_enabled(), "five-second execution unlocked")

	player.controls_enabled = false
	player.set("_heavy_timer", 0.0)
	player.set("_heavy_primed", false)
	player.set("_fire_cooldown", 0.0)
	var manager: ProjectileManager = main.projectile_manager
	var before := manager._active.size()
	player._fire(Vector2.UP)
	failures += _check(manager._active.size() == before, "five-second shot charges before firing")
	failures += _check(bool(player.get("_heavy_primed")), "heavy shot is primed")
	player.set("_fire_cooldown", 0.0)
	player._fire(Vector2.UP)
	failures += _check(manager._active.size() == before + 1, "primed heavy shot fires")
	if manager._active.size() > before:
		failures += _check(manager._active.back().is_heavy, "primed shot uses heavy projectile")
		manager.release(manager._active.back())


func _test_energy_line() -> void:
	var max_before := RunState.max_energy
	_unlock(&"energy_1")
	failures += _check(is_equal_approx(RunState.max_energy, max_before + 1.0), "energy tier 1 raises cap")
	failures += _check(is_equal_approx(Skills.energy_regen_multiplier(), 1.30),
		"energy tier 1 raises regeneration by thirty percent")
	_unlock(&"energy_2")
	failures += _check(is_equal_approx(Skills.energy_regen_multiplier(), 1.40),
		"energy tier 2 adds ten percent regeneration")
	RunState.energy = RunState.max_energy
	var damage_before := player.weapon.stats.get_value(&"damage_mult")
	var rate_before := player.weapon.stats.get_value(&"fire_rate_mult")
	RunState.spend_energy(2.0)
	failures += _check(Skills._energy_buff_timers.size() == 2
		and is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), damage_before + 0.20)
		and is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate_before + 0.10),
		"tier 2 adds one damage and fire-rate layer per energy point")
	failures += _check(Skills._damage_source_key(&"skill_energy_2_damage") == &"skill:energy_2",
		"energy damage is attributed to tier 2 in the damage breakdown")
	Skills._tick_energy_buff(3.0)
	RunState.spend_energy(1.0)
	Skills._tick_energy_buff(2.1)
	failures += _check(Skills._energy_buff_timers.size() == 1
		and is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), damage_before + 0.10)
		and is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate_before + 0.05),
		"later spending does not refresh earlier energy layers")
	Skills._tick_energy_buff(3.0)
	failures += _check(Skills._energy_buff_timers.is_empty()
		and is_equal_approx(player.weapon.stats.get_value(&"damage_mult"), damage_before)
		and is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate_before),
		"each five-second energy layer expires independently")
	_unlock(&"energy_3")
	_unlock(&"energy_4")
	failures += _check(Skills.energy_max_bonus() == 5, "energy line grants +5 cap")
	failures += _check(is_equal_approx(RunState.max_energy, 8.0), "energy cap reaches 8")
	RunState.energy = 3.0
	failures += _check(is_equal_approx(Skills.energy_regen_multiplier(), 1.90),
		"low-energy regeneration stacks additively")

	var rng_state := RunState.rng.state
	var miss_seed := -1
	var hit_seed := -1
	for candidate in 1000:
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate
		var first := probe.randf()
		var second := probe.randf()
		if first >= 0.20 and second < 0.20 and miss_seed < 0:
			miss_seed = candidate
		if first < 0.20 and second >= 0.20 and hit_seed < 0:
			hit_seed = candidate
		if miss_seed >= 0 and hit_seed >= 0:
			break
	failures += _check(miss_seed >= 0 and hit_seed >= 0, "found deterministic tier-4 roll seeds")
	if miss_seed >= 0 and hit_seed >= 0:
		RunState.energy = RunState.max_energy
		RunState.rng.seed = miss_seed
		RunState.spend_energy(2.0)
		failures += _check(is_equal_approx(RunState.energy, RunState.max_energy - 2.0),
			"two-point spend rolls refill once, not twice")
		RunState.energy = RunState.max_energy
		RunState.rng.seed = hit_seed
		RunState.spend_energy(2.0)
		failures += _check(is_equal_approx(RunState.energy, RunState.max_energy),
			"successful tier-4 roll refills energy immediately")
	RunState.rng.state = rng_state


func _test_speed_line() -> void:
	var move_before := player.stats.get_value(&"move_speed")
	var rate_before := player.weapon.get_final_fire_rate()
	_unlock(&"speed_1")
	_unlock(&"speed_2")
	failures += _check(player.stats.get_value(&"move_speed") > move_before, "speed line raises move speed")
	failures += _check(player.weapon.get_final_fire_rate() > rate_before, "speed tiers raise fire rate")
	failures += _check(player.body_radius < Player.RADIUS, "speed tier 2 shrinks the body")

	_unlock(&"speed_3")
	Skills._tick_speed_rate()
	failures += _check(player.weapon.stats.get_value(&"fire_rate_final") > 1.0, "move bonus converts into final fire rate")

	_unlock(&"speed_4")
	failures += _check(is_equal_approx(player.effective_move_speed(), minf(player.stats.get_value(&"move_speed"), Player.MOVE_SPEED_CAP * 1.3)), "tier 4 raises the move speed cap")


func _test_shotgun_line() -> void:
	var projectiles_before := int(player.weapon.stats.get_value(&"projectiles_per_shot"))
	var damage_before := player.weapon.stats.get_value(&"damage_mult")
	var spread_before := player.weapon.stats.get_value(&"spread_degrees")
	var rate_before := player.weapon.stats.get_value(&"fire_rate_mult")
	_unlock(&"shotgun_1")
	failures += _check(
		int(player.weapon.stats.get_value(&"projectiles_per_shot")) == projectiles_before + 1,
		"shotgun tier 1 adds one projectile"
	)
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"spread_degrees"), spread_before + 10.0),
		"shotgun tier 1 adds 10 degrees spread"
	)
	failures += _check(
		player.weapon.stats.get_value(&"damage_mult") < damage_before,
		"shotgun tier 1 trades damage for pellets"
	)

	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"fire_rate_mult"), rate_before - 0.10),
		"shotgun tier 1 adds a 10 percent fire-rate penalty"
	)
	# 双弹只侧移枪口，沿瞄准线平行；三弹以上仍保留扇面与随机偏差。
	player.set("_heavy_timer", 10.0)
	player.set("_heavy_primed", false)
	var shot_two := _capture_shot_angles()
	failures += _check(shot_two.size() == 2, "shotgun tier 1 fires two pellets")
	failures += _check(is_zero_approx(shot_two[0]) and is_zero_approx(shot_two[1]),
		"two pellets travel exactly parallel to the aim line")
	_test_dual_shot_geometry()

	_unlock(&"shotgun_2")
	var manager: ProjectileManager = main.projectile_manager
	var corpse := _spawn_enemy(player.global_position + Vector2(80.0, 0.0), 999.0)
	var before := manager._active.size()
	EventBus.enemy_killed.emit(corpse, 0, 0)
	failures += _check(
		manager._active.size() >= before + 3,
		"shotgun tier 2 bursts three fragments on kill"
	)
	var shard := manager._active[before] as Projectile
	var base_speed := player.weapon.stats.get_value(&"projectile_speed")
	var base_lifetime := player.weapon.stats.get_value(&"projectile_lifetime")
	failures += _check(shard != null and shard.speed <= base_speed * 0.55,
		"fragments travel much slower than normal shots")
	failures += _check(shard != null and shard.lifetime <= base_lifetime * 0.50,
		"fragments have a much shorter range")
	failures += _check(shard != null and shard.pierce == 0, "fragments do not inherit pierce")
	failures += _check(shard != null and not shard.allow_crit, "fragments do not inherit crit")
	corpse.queue_free()

	_unlock(&"shotgun_3")
	failures += _check(
		int(player.weapon.stats.get_value(&"projectiles_per_shot")) == projectiles_before + 2,
		"shotgun tier 3 adds one more projectile"
	)
	failures += _check(
		player.weapon.stats.get_value(&"pierce") >= 1.0,
		"shotgun tier 3 adds pierce"
	)
	failures += _check(
		is_equal_approx(player.weapon.stats.get_value(&"spread_degrees"), spread_before + 15.0),
		"shotgun tier 3 adds 5 more degrees spread"
	)

	var shot_three := _capture_shot_angles()
	failures += _check(shot_three.size() == 3, "shotgun tier 3 fires three pellets")
	var jitter_half_three := deg_to_rad(player.weapon.stats.get_value(&"spread_degrees")) * 0.5
	var center_gap := minf(minf(absf(shot_three[0]), absf(shot_three[1])), absf(shot_three[2]))
	failures += _check(
		center_gap <= jitter_half_three + 0.001,
		"odd pellet count keeps one pellet near the aim line"
	)
	failures += _check(
		shot_three[2] - shot_three[0] <= deg_to_rad(23.0) + jitter_half_three * 2.0 + 0.001,
		"three-pellet fan plus jitter stays inside its cone"
	)

	var before_double := int(player.weapon.stats.get_value(&"projectiles_per_shot"))
	_unlock(&"shotgun_4")
	failures += _check(
		int(player.weapon.stats.get_value(&"projectiles_per_shot")) == before_double * 2,
		"shotgun tier 4 doubles the final projectile count"
	)

	var shot_six := _capture_shot_angles()
	failures += _check(shot_six.size() == 6, "doubled shotgun fires six pellets")
	var jitter_half_six := deg_to_rad(player.weapon.stats.get_value(&"spread_degrees")) * 0.5
	failures += _check(
		shot_six[5] - shot_six[0]
			<= deg_to_rad(Player.SHOTGUN_MAX_FAN_DEG) + jitter_half_six * 2.0 + 0.001,
		"pellet fan plus spread respects the maximum cone"
	)
	var distinct := {}
	for angle in shot_six:
		distinct[snappedf(angle, 0.0001)] = true
	failures += _check(distinct.size() == 6, "all six pellets get their own random direction")


func _test_dual_shot_geometry() -> void:
	var manager: ProjectileManager = main.projectile_manager
	for direction in [Vector2.RIGHT, Vector2.UP, Vector2(-0.6, 0.8)]:
		var before := manager._active.size()
		player._fire(direction)
		if manager._active.size() - before != 2:
			failures += _check(false, "dual-shot geometry produces two projectiles")
			continue
		var a := manager._active[before] as Projectile
		var b := manager._active[before + 1] as Projectile
		var separation := a.global_position - b.global_position
		var midpoint := (a.global_position + b.global_position) * 0.5
		var expected: Vector2 = player.global_position + direction * (player.body_radius + 14.0)
		failures += _check(a.direction.is_equal_approx(direction) and b.direction.is_equal_approx(direction),
			"dual shot stays parallel for aim %s" % direction)
		failures += _check(absf(separation.dot(direction)) < 0.001 and separation.length() > 4.0,
			"dual barrels separate sideways instead of overlapping")
		failures += _check(midpoint.distance_to(expected) < 0.001,
			"dual barrels stay symmetric around the aim line")
		for index in range(manager._active.size() - 1, before - 1, -1):
			manager.release(manager._active[index])


func _test_luck_line() -> void:
	failures += _check(Skills.luck() == 0.0, "luck starts at zero")
	failures += _check(Skills.chest_drop_chance() == 0.0, "chests cannot drop before luck tier 1")
	failures += _check(not Skills.grant_relic(&"rare_four_leaf"), "lucky relics are gated behind luck tier 1")

	_unlock(&"luck_1")
	failures += _check(is_equal_approx(Skills.luck(), 12.0), "luck tier 1 grants +12 luck")
	failures += _check(is_equal_approx(Skills.chest_drop_chance(), 0.044), "tier 1 chest chance is 4.4%")
	failures += _check(Skills.chest_drop_chance() > 0.0, "luck tier 1 unlocks chest drops")
	failures += _check(Skills.grant_relic(&"rare_four_leaf"), "lucky relics unlock with luck tier 1")
	var chance_before := Skills.chest_drop_chance()

	_unlock(&"luck_2")
	failures += _check(is_equal_approx(Skills.luck(), 28.0), "luck tier 2 grants +12 luck (plus four-leaf)")
	failures += _check(Skills.chest_drop_chance() > chance_before, "more luck raises the chest drop rate")
	failures += _check(
		is_equal_approx(Skills.chest_relic_chance(), 0.15),
		"luck tier 2 raises the chest relic chance to 15%"
	)

	var owned_before := Skills.owned_relics.size()
	_unlock(&"luck_3")
	failures += _check(Skills.owned_relics.size() == owned_before + 1, "luck tier 3 grants a lucky relic")
	failures += _check(
		not Skills.owned_relics.is_empty() and Skills.owned_relics.back().lucky,
		"the tier 3 gift is a lucky relic"
	)

	_unlock(&"luck_4")
	var luck_before := Skills.luck()
	Pickups.spawn_chest(player.global_position + Vector2(600.0, 0.0))
	failures += _check(is_equal_approx(Skills.luck(), luck_before + 6.0), "discovering a chest grants +6 temporary luck")
	Pickups.clear()
	Skills._tick_temp_luck(61.0)
	failures += _check(is_equal_approx(Skills.temp_luck(), 0.0), "temporary luck expires")

	# 后期上限：掉箱 6%、宝箱转化遗物 20%。
	# 3 阶随机礼物可能是幸运 -3 的三叶草；显式制造高幸运，不依赖抽奖结果。
	Skills.grant_temp_luck(100.0, 1.0)
	failures += _check(
		is_equal_approx(Skills.chest_drop_chance(), 0.06),
		"late-game chest drop chance caps at 6%"
	)
	Skills._tick_temp_luck(2.0)
	for i in 4:
		Skills.grant_relic(&"legendary_rainbow_clover")
	failures += _check(
		is_equal_approx(Skills.chest_relic_chance(), 0.20),
		"late-game chest relic chance caps at 20%"
	)
	Skills.grant_relic(&"legendary_rainbow_clover")
	failures += _check(
		is_equal_approx(Skills.chest_relic_chance(), 0.20),
		"chest relic chance stays at the cap"
	)


func _test_path_line() -> void:
	var owned_before := Skills.owned_relics.size()
	_unlock(&"path_demon_1")
	failures += _check(Skills.owned_relics.size() == owned_before + 1, "demon contract grants a relic")
	failures += _check(not Skills.is_available(Skills.get_node_by_id(&"path_angel_1")), "angel path disappears after demon")

	_unlock(&"path_demon_2")
	failures += _check(
		is_equal_approx(Skills.shop_weight_multiplier(&"demon"), 1.0),
		"committing a path no longer doubles side relic weights"
	)
	failures += _check(Skills.shop_quality_bonus(&"demon") == 1, "demon shop quality bonus recorded")

	var owned_after_contract := Skills.owned_relics.size()
	_unlock(&"path_demon_3")
	failures += _check(
		Skills.owned_relics.size() == owned_after_contract + 1,
		"demon tier 3 grants a second relic"
	)
	failures += _check(Skills.altars_enabled(&"demon"), "demon altar flag recorded")

	var power_before := player.weapon.get_final_damage() * player.weapon.get_final_fire_rate()
	_unlock(&"path_demon_4")
	var power_after := player.weapon.get_final_damage() * player.weapon.get_final_fire_rate()
	failures += _check(power_after > power_before, "demon tier 4 doubles relic bonuses")


func _test_xp_gold_lines() -> void:
	var xp_before := Skills.xp_multiplier()
	failures += _check(is_equal_approx(Skills.pickup_radius_multiplier(), 1.0), "pickup range starts at 100%")
	_unlock(&"xp_1")
	failures += _check(
		is_equal_approx(Skills.pickup_radius_multiplier(), 1.5),
		"xp tier 1 widens pickup range for both drops"
	)
	_unlock(&"xp_2")
	_unlock(&"xp_3")
	_unlock(&"xp_4")
	failures += _check(is_equal_approx(Skills.xp_multiplier(), xp_before + 0.7), "xp line reaches +70%")

	var gold_before := Skills.gold_multiplier()
	_unlock(&"gold_1")
	failures += _check(
		is_equal_approx(Skills.pickup_radius_multiplier(), 2.0),
		"xp and gold tier 1 stack to double the pickup range"
	)
	_unlock(&"gold_2")
	_unlock(&"gold_3")
	_unlock(&"gold_4")
	# 幸运线三阶可能随机送出“幸运币”（+10% 金币），它和金币线的加算区叠在一起，
	# 因此这里只检查金币线确实带来了 +45% 档位的提升，不强求绝对差值。
	var gold_after := Skills.gold_multiplier()
	failures += _check(
		gold_after >= gold_before + 0.44 and gold_after <= gold_before + 0.62,
		"gold line reaches its +45%% bonus (%.2f -> %.2f)" % [gold_before, gold_after]
	)
	failures += _check(Skills.gold_kill_bonus() == 1, "gold tier 2 adds kill gold")
	failures += _check(Skills.xp_auto_collect() and Skills.gold_auto_collect(), "auto collect flags recorded")


func _test_soul_line() -> void:
	_unlock(&"soul_1")
	_unlock(&"soul_2")
	_unlock(&"soul_3")
	_unlock(&"soul_4")
	failures += _check(is_equal_approx(Skills.soul_interval(), 2.0), "soul interval becomes 2s")
	failures += _check(is_equal_approx(Skills.soul_radius(), 270.0), "soul radius grows 50%")
	failures += _check(Skills.soul_multiplier() > 1.7 - 0.001, "soul multiplier becomes 1.7")
	failures += _check(Skills.soul_damage() >= 30.0, "soul tier 4 adds flat damage")


func _test_splash_line() -> void:
	_unlock(&"splash_1")
	failures += _check(Skills.has_splash(), "splash unlocked")
	_unlock(&"splash_2")
	failures += _check(is_equal_approx(Skills.splash_ratio(), 0.6), "splash ratio becomes 60%")
	_unlock(&"splash_3")
	failures += _check(is_equal_approx(Skills.splash_radius(), 120.0), "splash radius grows 50%")
	var final_rate_before := player.weapon.stats.get_value(&"fire_rate_final")
	var final_damage_before := player.weapon.stats.get_value(&"damage_final")
	_unlock(&"splash_4")
	failures += _check(Skills.splash_every_hit(), "splash triggers on every hit")
	failures += _check(player.weapon.stats.get_value(&"damage_final") < final_damage_before, "splash tier 4 lowers final damage")
	failures += _check(
		player.weapon.stats.get_value(&"fire_rate_final") < final_rate_before,
		"splash tier 4 lowers final fire rate"
	)


func _test_weakness_line() -> void:
	var weakness_before := Skills.weakness_multiplier()
	_unlock(&"weak_1")
	failures += _check(Skills.weakness_multiplier() > weakness_before, "weakness multiplier rises")
	failures += _check(is_equal_approx(Skills.weakness_multiplier(), 2.0), "weakness multiplier is 200%")
	_unlock(&"weak_2")
	failures += _check(is_equal_approx(Skills.elemental_multiplier(), 1.3), "elemental damage reaches +30%")
	_unlock(&"weak_3")
	_unlock(&"weak_4")


func _test_elemental_pipeline() -> void:
	var text_layer := FX._text_layer as FloatingTextLayer
	var base_health := 5000.0
	var elemental := Skills.elemental_multiplier()
	var red := _spawn_enemy(player.global_position + Vector2(90.0, 0.0), base_health)
	red.color_index = _weak_target_color(ColorType.RED)
	var red_base := _elemental_test_hit(red, ColorType.RED)
	failures += _check(red._healthbar.burn, "red weak hit attaches burn icon")
	var red_before := red.health
	FX._elemental_label_frame = -1
	red._apply_dot_tick()
	failures += _check(_last_damage_style(text_layer) == FloatingTextLayer.STYLE_BURN, "burn tick emits orange burn damage text")
	for i in 3:
		red._apply_dot_tick()
	failures += _check(is_equal_approx(red_before - red.health, red_base * 2.0 * elemental * Skills.weakness_multiplier()), "red attachment includes weakness damage without crit")
	failures += _check(red._healthbar._burn_pulse > 0.0 and not red._healthbar.burn, "burn icon jumps on its final damage tick")
	red.queue_free()

	var green := _spawn_enemy(player.global_position + Vector2(90.0, 0.0), base_health)
	green.color_index = _weak_target_color(ColorType.GREEN)
	var green_base := _elemental_test_hit(green, ColorType.GREEN)
	failures += _check(green._healthbar.poison, "green weak hit attaches poison icon")
	var green_before := green.health
	FX._elemental_label_frame = -1
	green._apply_dot_tick()
	green._apply_dot_tick()
	failures += _check(is_equal_approx(green_before - green.health, green_base * 0.45 * elemental * Skills.weakness_multiplier()), "poison includes weakness damage without crit")
	failures += _check(green._healthbar._poison_pulse > 0.0 and _last_damage_style(text_layer) == FloatingTextLayer.STYLE_POISON, "poison tick jumps and emits green damage text")
	green.queue_free()

	var blue := _spawn_enemy(player.global_position + Vector2(90.0, 0.0), base_health)
	blue.color_index = _weak_target_color(ColorType.BLUE)
	_elemental_test_hit(blue, ColorType.BLUE)
	failures += _check(blue._healthbar.ice and is_equal_approx(blue._slow, 0.25 * elemental), "blue weak hit attaches ice and slows")
	var second_base := player.weapon.get_final_damage()
	var preview := Skills.build_hit_context(player, blue, second_base, ColorType.BLUE, false, false)
	var blue_before := blue.health
	FX._elemental_label_frame = -1
	_elemental_test_hit(blue, ColorType.BLUE)
	failures += _check(preview.elemental_bonus > 0.0 and is_equal_approx(blue_before - blue.health, preview.amount), "ice bonus is included exactly once in health loss")
	failures += _check(blue._healthbar._ice_pulse > 0.0 and _last_damage_style(text_layer) == FloatingTextLayer.STYLE_ICE, "ice icon jumps and emits blue bonus text")
	blue.queue_free()
	failures += _check(float(Skills.damage_totals.get(&"base", 0.0)) > 0.0, "direct projectile health loss is recorded")
	failures += _check(float(Skills.damage_totals.get(&"skill:weak_3_burn", 0.0)) > 0.0
		and float(Skills.damage_totals.get(&"skill:weak_3_poison", 0.0)) > 0.0
		and float(Skills.damage_totals.get(&"skill:weak_3_ice", 0.0)) > 0.0,
		"all three elemental damage sources are recorded")
	failures += _check(float(Skills.damage_bonus_estimates.get(&"skill:heavy_1", 0.0)) > 0.0,
		"heavy damage modifier has an estimated contribution")


func _weak_target_color(attack_color: int) -> int:
	for candidate in ColorType.COUNT:
		if RunState.color_relation(attack_color, candidate) == &"advantage":
			return candidate
	return -1


func _elemental_test_hit(enemy: Enemy, attack_color: int) -> float:
	var manager: ProjectileManager = main.projectile_manager
	manager.fire(enemy.global_position - Vector2(30.0, 0.0), Vector2.RIGHT,
		player.weapon.stats, attack_color, player.weapon.core,
		false, 1.0, 1.0, 1.0, 1.0, false)
	var shot: Projectile = manager._active.back()
	var base := shot.damage
	shot._on_body_entered(enemy)
	return base


func _last_damage_style(layer: FloatingTextLayer) -> int:
	return layer._styles[(layer._cursor - 1 + FloatingTextLayer.MAX_TEXTS) % FloatingTextLayer.MAX_TEXTS]


func _test_crit_line() -> void:
	var crit_before := Skills.get_crit_chance(null)
	var crit_damage_before := Skills.get_crit_damage(null)
	_unlock(&"crit_1")
	_unlock(&"crit_2")
	failures += _check(Skills.get_crit_chance(null) > crit_before, "crit chance rises")
	failures += _check(
		is_equal_approx(Skills.get_crit_damage(null), crit_damage_before + 0.7),
		"crit line adds 70% crit damage"
	)
	_unlock(&"crit_3")
	_unlock(&"crit_4")
	failures += _check(is_equal_approx(Skills.get_super_crit_chance(), 0.01), "super crit chance is 1%")

	var enemy := _spawn_enemy(player.global_position + Vector2(100.0, 0.0), 500.0)
	enemy.health = enemy.max_health * 0.5
	var missing_bonus := Skills.get_crit_chance(enemy) - Skills.get_crit_chance(null)
	failures += _check(missing_bonus > 0.24 and missing_bonus < 0.26, "half-health target adds 25% crit")
	failures += _check(Skills.get_crit_damage(enemy) > Skills.get_crit_damage(null) + 0.99, "half-health target adds 100% crit damage")
	enemy.queue_free()


## 调试开关：--force-super-crit 必须让真实命中上下文变成超暴击。
func _test_forced_super_crit() -> void:
	Skills.debug_force_super_crit = true
	failures += _check(is_equal_approx(Skills.get_super_crit_chance(), 1.0), "debug flag forces 100% super crit")

	var enemy := _spawn_enemy(player.global_position + Vector2(120.0, 0.0), 99999.0)
	var context := Skills.build_hit_context(player, enemy, 10.0, player.color_index)
	failures += _check(context.is_crit, "forced super crit is also a crit")
	failures += _check(context.has_tag(&"super_crit"), "forced hit carries the super crit tag")
	enemy.queue_free()

	Skills.debug_force_super_crit = false
	failures += _check(
		is_equal_approx(Skills.get_super_crit_chance(), 0.01),
		"disabling the debug flag restores the normal 1% chance"
	)


func _test_combat_helpers() -> void:
	# 元素状态：灼伤每半秒一跳，中毒同频持续，冰附着。
	var status_enemy := _spawn_enemy(player.global_position + Vector2(80.0, 0.0), 500.0)
	status_enemy.apply_burn(100.0)
	status_enemy._apply_dot_tick()
	failures += _check(is_equal_approx(status_enemy.health, 475.0), "burn deals a quarter of its total per half-second tick")
	status_enemy.apply_poison(10.0)
	status_enemy._apply_dot_tick()
	failures += _check(is_equal_approx(status_enemy.health, 445.0), "poison deals half its DPS each tick")
	status_enemy.apply_ice(3.0)
	failures += _check(status_enemy.has_ice(), "ice attachment is active")
	status_enemy.take_true_damage(5.0)
	failures += _check(is_equal_approx(status_enemy.health, 440.0), "true damage ignores color")

	# 处决：弱点命中且低于 15%。
	status_enemy.health = status_enemy.max_health * 0.1
	Skills.try_execute(status_enemy, true)
	failures += _check(status_enemy.is_dead, "weakness execution kills low-health enemies")

	# 溅射：周围两个敌人同时受伤。
	var splash_center := player.global_position + Vector2(0.0, 140.0)
	var splash_a := _spawn_enemy(splash_center + Vector2(30.0, 0.0), 100.0)
	var splash_b := _spawn_enemy(splash_center + Vector2(60.0, 0.0), 100.0)
	Skills.apply_splash(splash_center, 50.0, ColorType.RED, null)
	failures += _check(splash_a.health < 100.0 and splash_b.health < 100.0, "splash hits nearby enemies")
	splash_a.queue_free()
	splash_b.queue_free()

	# 灵魂脉冲：真实伤害数值精确。
	var soul_enemy := _spawn_enemy(player.global_position + Vector2(60.0, 0.0), 1000.0)
	var soul_amount := Skills.soul_damage()
	Skills._do_soul_pulse()
	failures += _check(
		is_equal_approx(soul_enemy.health, 1000.0 - soul_amount),
		"soul pulse deals exact true damage"
	)
	soul_enemy.queue_free()


## 真实弹道结算：一发子弹同时验证命中、溅射与重型弹参数。
func _test_projectile_pipeline() -> void:
	Director.stop()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	# 前序击杀留下的经验可能在本帧触发新的升级；先清掉地面奖励再恢复物理。
	Pickups.clear()
	main.level_up_panel.close()
	main.set("_level_ups_pending", 0)
	RunState.release_pause(&"level_up")

	player.controls_enabled = false
	player.global_position = Vector2.ZERO
	Skills.set("_soul_timer", 999.0)  # 隔离灵魂脉冲，确保伤害来自这发子弹。

	# 血量取得足够高：此处技能全开，一发暴击/超暴击可能远超 1000，
	# 若敌人被打死，死亡 Tween 会在断言前释放节点。
	const PIPELINE_HEALTH := 1_000_000.0
	var direct := _spawn_enemy(Vector2(220.0, 0.0), PIPELINE_HEALTH)
	var splashed := _spawn_enemy(Vector2(260.0, 80.0), PIPELINE_HEALTH)
	direct._contact_cooldown = 999.0
	splashed._contact_cooldown = 999.0

	var manager: ProjectileManager = main.projectile_manager
	manager.fire(
		player.global_position,
		Vector2.RIGHT,
		player.weapon.stats,
		player.color_index,
		player.weapon.core
	)
	failures += _check(not manager._active.is_empty(), "projectile fired")
	await get_tree().create_timer(0.7).timeout

	var direct_hit := is_instance_valid(direct) and direct.health < PIPELINE_HEALTH
	var splash_hit := is_instance_valid(splashed) and splashed.health < PIPELINE_HEALTH
	failures += _check(direct_hit, "projectile damages the direct target")
	failures += _check(splash_hit, "splash damages nearby targets")
	manager.fire(Vector2(0.0, -300.0), Vector2.UP, player.weapon.stats, player.color_index, player.weapon.core, false)
	var normal_projectile: Projectile = manager._active.back()
	manager.fire(Vector2(0.0, -300.0), Vector2.UP, player.weapon.stats, player.color_index, player.weapon.core, true)
	var heavy_projectile: Projectile = manager._active.back()
	failures += _check(heavy_projectile.damage > normal_projectile.damage * 2.0, "five-second shot deals over double damage")
	failures += _check(heavy_projectile.projectile_size > normal_projectile.projectile_size, "five-second shot is larger")
	manager.release(normal_projectile)
	manager.release(heavy_projectile)



func _unlock(id: StringName) -> void:
	failures += _check(Skills.unlock(id), "unlock %s" % id)
	# 此套验证解锁后的数值；领取交互与倒计时由 relic_choice_test 独立覆盖。
	while not Skills.pending_relic_offers.is_empty():
		Skills.resolve_relic_offer(Skills.pending_relic_offers[0].ticket, true)


## 记录一次开火产生的所有弹丸角度，并立刻回收；角度已排序。
func _capture_shot_angles() -> Array[float]:
	var manager: ProjectileManager = main.projectile_manager
	var before := manager._active.size()
	player._fire(Vector2.RIGHT)
	var angles: Array[float] = []
	for i in range(before, manager._active.size()):
		angles.append((manager._active[i] as Projectile).direction.angle())
	for i in range(manager._active.size() - 1, before - 1, -1):
		manager.release(manager._active[i])
	angles.sort()
	return angles


func _spawn_enemy(position: Vector2, health: float) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), player)
	main.world.add_child(enemy)
	enemy.global_position = position
	enemy.max_health = health
	enemy.health = health
	return enemy


func _check(condition: bool, label: String) -> int:
	if condition:
		print("SKILL PASS: %s" % label)
		return 0
	print("SKILL FAIL: %s" % label)
	return 1

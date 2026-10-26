extends Node

## 恶魔/天使祭坛专项无头测试：
## godot --headless --fixed-fps 60 --path . res://tests/altars_test.tscn

var failures := 0
var main: Node
var player: Player
var panel: AltarPanel


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
	panel = main.get_node("HUD/AltarPanel") as AltarPanel

	failures += _check(player != null, "player exists")
	failures += _check(panel != null, "altar panel exists")

	await _test_gating()
	await _test_demon_trade()
	await _test_demon_fallback()
	await _test_angel_trade()

	print("ALTAR TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_gating() -> void:
	failures += _check(Skills.altar_side() == &"", "no altar side before a contract")
	failures += _check(
		Director.spawn_altar_now(Vector2.ZERO) == null,
		"director refuses to spawn an altar without tier 3"
	)
	failures += _check(
		get_tree().get_nodes_in_group(&"altar").is_empty(),
		"no altar exists before it is unlocked"
	)


func _test_demon_trade() -> void:
	Skills.unlock(&"path_demon_1", true)
	Skills.unlock(&"path_demon_2", true)
	Skills.unlock(&"path_demon_3", true)
	_accept_first_discard_rest()
	failures += _check(Skills.altar_side() == &"demon", "demon contract unlocks altars")
	failures += _check(Skills.altars_enabled(&"demon"), "demon tier 3 reports altars enabled")
	failures += _check(Skills.side_relic_remaining(&"demon") == 1,
		"one demon relic remains after discarding the second contract offer")
	# 三心开局叠加恶魔遗物后可能不足以支付一整颗心；给祭坛流程测试留出上限。
	var first_trade_health := StatModifierResource.new()
	first_trade_health.stat = &"max_health"
	first_trade_health.op = StatModifierResource.Op.FLAT
	first_trade_health.value = 2.0
	first_trade_health.target = StatModifierResource.Target.PLAYER
	first_trade_health.source = &"altar_first_trade_test_bonus"
	player.apply_stat_modifier(first_trade_health)

	var altar := Director.spawn_altar_now(player.global_position + Vector2(80.0, 0.0))
	failures += _check(altar != null, "demon altar spawns")
	failures += _check(altar.side == &"demon", "altar carries the committed side")
	failures += _check(
		get_tree().get_nodes_in_group(&"altar").size() == 1,
		"altar joins the altar group"
	)
	failures += _check(
		Director.spawn_altar_now(Vector2(900.0, 500.0)) == altar,
		"only one altar exists at a time"
	)
	failures += _check(
		is_equal_approx(altar.health_cost(), 1.0),
		"demon altar costs one max heart"
	)

	# 靠到玩家身边触发交互，Main 应暂停并打开面板。
	altar.global_position = player.global_position
	await get_tree().create_timer(0.2).timeout
	failures += _check(panel.visible, "touching the altar opens the panel")
	failures += _check(get_tree().paused, "altar pauses the tree")
	failures += _check(not main.hud_control.visible, "HUD hides while the altar is open")

	var max_before := player.max_health
	var owned_before := _owned_side_relics(&"demon")
	var gold_before := RunState.gold

	panel._trade()
	await get_tree().create_timer(0.1).timeout
	failures += _check(not Skills.pending_relic_offers.is_empty(), "altar reward waits for pickup choice")
	_accept_rewards()

	failures += _check(not panel.visible, "trading closes the altar panel")
	failures += _check(not get_tree().paused, "trading resumes the tree")
	failures += _check(main.hud_control.visible, "HUD returns after trading")
	failures += _check(
		player.max_health <= max_before - 1.0,
		"demon altar reduces max health by at least one heart"
	)
	failures += _check(
		_owned_side_relics(&"demon") == owned_before + 1,
		"demon altar grants one side relic"
	)
	failures += _check(RunState.gold == gold_before, "demon altar does not charge gold")
	failures += _check(Skills.side_relic_remaining(&"demon") == 0,
		"both demon relics are owned after the trade")

	await get_tree().create_timer(0.5).timeout
	failures += _check(
		get_tree().get_nodes_in_group(&"altar").is_empty(),
		"altar leaves after the trade"
	)


func _test_demon_fallback() -> void:
	var altar := Director.spawn_altar_now(player.global_position + Vector2(80.0, 0.0))
	failures += _check(altar != null, "a second altar can spawn later")
	failures += _check(not altar.reward_is_relic(), "empty side pool switches to a gift")
	failures += _check(
		altar.reward_label().contains("鲜血馈赠"),
		"demon gift is labelled as a blood gift"
	)

	# 给测试角色一点上限余量，并压低生命，验证空池交易改为回血。
	var bonus := StatModifierResource.new()
	bonus.stat = &"max_health"
	bonus.op = StatModifierResource.Op.FLAT
	bonus.value = 2.0
	bonus.target = StatModifierResource.Target.PLAYER
	bonus.source = &"altar_test_bonus"
	player.apply_stat_modifier(bonus)
	player.health = 1.0
	EventBus.player_health_changed.emit(player.health, player.max_health)

	var max_before := player.max_health
	var health_before := player.health
	altar.global_position = player.global_position
	await get_tree().create_timer(0.2).timeout
	panel._trade()
	await get_tree().create_timer(0.1).timeout

	failures += _check(
		player.max_health <= max_before - 1.0,
		"empty-pool demon trade still charges max health"
	)
	failures += _check(
		player.health >= minf(player.max_health, health_before + 1.5),
		"empty-pool demon trade heals two hearts"
	)
	await get_tree().create_timer(0.5).timeout


func _test_angel_trade() -> void:
	# 重新开始一局技能树，改走天使线；保留测试角色节点即可。
	Skills.begin_run()
	Skills.bind_player(player)
	RunState.is_running = true
	RunState.is_dead = false
	Skills.unlock(&"path_angel_1", true)
	Skills.unlock(&"path_angel_2", true)
	Skills.unlock(&"path_angel_3", true)
	_accept_first_discard_rest()
	failures += _check(Skills.altar_side() == &"angel", "angel contract unlocks angel altars")

	RunState.elapsed = 130.0
	RunState.gold = 1000
	var altar := Director.spawn_altar_now(player.global_position + Vector2(80.0, 0.0))
	failures += _check(altar != null and altar.side == &"angel", "angel altar spawns")
	failures += _check(altar.gold_cost() == 160, "angel price is 120 + 20 per minute")

	var gold_before := RunState.gold
	var owned_before := _owned_side_relics(&"angel")
	altar.global_position = player.global_position
	await get_tree().create_timer(0.2).timeout
	failures += _check(panel.visible, "angel altar opens its panel")
	panel._trade()
	await get_tree().create_timer(0.1).timeout

	failures += _check(
		RunState.gold == gold_before - 160,
		"angel altar charges the expected gold"
	)
	_accept_rewards()
	failures += _check(
		_owned_side_relics(&"angel") == owned_before + 1,
		"angel altar grants one angel relic"
	)
	failures += _check(Skills.side_relic_remaining(&"angel") == 0,
		"both angel relics are owned after the trade")
	failures += _check(not panel.visible, "angel panel closes after trading")
	await get_tree().create_timer(0.5).timeout


func _accept_rewards() -> void:
	while not Skills.pending_relic_offers.is_empty():
		Skills.resolve_relic_offer(Skills.pending_relic_offers[0].ticket, true)


func _accept_first_discard_rest() -> void:
	var take := true
	while not Skills.pending_relic_offers.is_empty():
		Skills.resolve_relic_offer(Skills.pending_relic_offers[0].ticket, take)
		take = false


func _owned_side_relics(side: StringName) -> int:
	var count := 0
	for relic in Skills.owned_relics:
		if relic.side == side:
			count += 1
	return count


func _check(condition: bool, label: String) -> int:
	if condition:
		print("ALTAR PASS  %s" % label)
		return 0
	print("ALTAR FAIL  %s" % label)
	return 1

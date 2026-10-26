extends Node

var failures := 0
var main: Node


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	if OS.get_cmdline_user_args().has("--preview"):
		await _preview()
		return
	_test_cap_and_reservations()
	_test_results_and_reuse()
	await _test_animation_lifecycle()
	print("DICE TEST %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_cap_and_reservations() -> void:
	_check(Skills.get_relic(&"rare_fate_dice").max_stacks == 2, "fate dice has a two-copy cap")
	_check(Skills.offer_relic(&"rare_fate_dice", "宝箱"), "first reward reserves a copy")
	_check(Skills.offer_relic(&"rare_fate_dice", "宝箱"), "second reward reserves a copy")
	_check(not Skills.offer_relic(&"rare_fate_dice", "宝箱"), "third pending reward is rejected")
	_check(not _in_shop(), "pending copies exclude dice from shop and chest pools")
	Skills.resolve_relic_offer(Skills.pending_relic_offers[0].ticket, false)
	_check(Skills.offer_relic(&"rare_fate_dice", "宝箱"), "discard releases the reserved slot")
	while not Skills.pending_relic_offers.is_empty():
		Skills.resolve_relic_offer(Skills.pending_relic_offers[0].ticket, true)
	_check(Skills.relic_count(&"rare_fate_dice") == 2, "two rewards can be accepted")
	var previous_roll := Skills.dice_roll()
	_check(not Skills.grant_relic(&"rare_fate_dice") and Skills.dice_roll() == previous_roll, "third direct pickup cannot reroll or apply effects")
	_check(not _in_shop(), "owned two-copy dice is excluded from offers")


func _in_shop() -> bool:
	for relic in Skills.shop_relic_pool(true):
		if relic.id == &"rare_fate_dice":
			return true
	return false


func _test_results_and_reuse() -> void:
	var effect: DiceRollEffect = FX._dice_effect
	var seen := {}
	RunState.rng.seed = 24680
	var correct := true
	for i in 128:
		Skills._roll_dice()
		var value := Skills.dice_roll()
		seen[value] = true
		if not effect.visible or effect.result != value or FX._dice_effect != effect:
			correct = false
		var damage: float = [-0.4, -0.4, 0.0, 0.2, 0.4, 0.6][value - 1]
		var rate: float = [0.6, 1.0, 1.0, 1.0, 1.4, 1.6][value - 1]
		if not is_equal_approx(Skills._dice_damage_mod.value, damage) or not is_equal_approx(Skills._dice_rate_mod.value, rate):
			correct = false
	_check(correct and seen.size() == 6, "all six results match two-copy modifiers and reuse the same animation node")
	for value in range(1, 7):
		effect.play(main.player, value)
		effect._process(DiceRollEffect.ROLL_TIME + 0.01)
		_check(effect.displayed_value == value and effect.rotation == 0.0, "animation settles on face %d" % value)
	Skills._dice_time = 0.01
	Skills._tick_dice(0.02)
	_check(effect.visible and effect.result == Skills.dice_roll() and Skills._dice_time == 10.0, "ten-second reroll restarts the result animation")


func _test_animation_lifecycle() -> void:
	var effect: DiceRollEffect = FX._dice_effect
	main.player.position += Vector2(40, 0)
	await get_tree().create_timer(0.05).timeout
	_check(is_equal_approx(effect.global_position.x, main.player.global_position.x), "dice follows the moving player")
	RunState.request_pause(&"manual_pause")
	var age := effect._age
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(effect._age, age), "pause freezes the dice animation")
	RunState.release_pause(&"manual_pause")
	await get_tree().create_timer(DiceRollEffect.LIFETIME + 0.05).timeout
	_check(not effect.visible and not effect.is_processing(), "finished animation hides and stops processing")
	Skills._roll_dice()
	RunState.end_run()
	_check(not effect.visible, "run end clears the dice immediately")


func _preview() -> void:
	Skills.grant_relic(&"rare_fate_dice")
	if OS.get_cmdline_user_args().has("--shot"):
		for i in 100:
			Skills._roll_dice()
			if Skills.dice_roll() == 6:
				break
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/dice_result.png")
		get_tree().quit()
		return
	while is_inside_tree():
		await get_tree().create_timer(3.0).timeout
		Skills._roll_dice()


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("DICE %s: %s" % ["PASS" if ok else "FAIL", description])

extends Node

var failures := 0
var main: Node
var panel: RelicChoicePanel


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	main.player.controls_enabled = false
	main.player.set("_invuln", 999.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	panel = main.get_node("HUD/RelicChoicePanel")
	RunState.level = 1000
	if OS.get_cmdline_user_args().has("--preview"):
		await _preview()
		return
	_test_luck()
	await _test_choice_and_queue()
	await _test_countdown_and_pause()
	_test_reservations_and_death()
	print("RELIC CHOICE %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_luck() -> void:
	var briefs_complete := true
	for relic in Skills.relics:
		if relic.brief_description.is_empty() or relic.brief_description.contains("\n"):
			briefs_complete = false
	_check(briefs_complete, "all 52 relics provide a one-line brief description")
	Skills.unlock(&"luck_1")
	_check(Skills.luck() == 12 and is_equal_approx(Skills.chest_drop_chance(), 0.044), "first tier improves early resource drops")
	_check(is_equal_approx(Skills.chest_relic_chance(), 0.10), "base relic conversion is 10 percent")
	Skills.unlock(&"luck_2")
	_check(Skills.luck() == 24 and is_equal_approx(Skills.chest_drop_chance(), 0.06), "second tier reaches the 6 percent chest cap")
	_check(is_equal_approx(Skills.chest_relic_chance(), 0.15), "second tier relic conversion is 15 percent")
	Skills.unlock(&"luck_3")
	_check(Skills.luck() == 40 and Skills.relic_count(&"epic_six_sided_die") == 1 and Skills.pending_relic_offers.size() == 1, "tier three gives luck now but queues its relic")
	Skills.resolve_relic_offer(Skills.pending_relic_offers[0].ticket, false)
	Skills.unlock(&"luck_4")
	Pickups.spawn_chest(main.player.global_position + Vector2(700, 0))
	_check(Skills.temp_luck() == 6 and Pickups.total_count() == 1, "Koi triggers when a chest appears before opening")
	Skills._tick_temp_luck(30)
	Pickups.spawn_chest(main.player.global_position + Vector2(-700, 0))
	_check(Skills.temp_luck() == 6 and Skills._temp_luck_time == 60, "chest discovery refreshes without stacking")
	Pickups.clear()
	Skills._tick_temp_luck(61)
	for i in 3:
		Skills.grant_relic(&"legendary_rainbow_clover")
	_check(is_equal_approx(Skills.chest_relic_chance(), 0.20), "rainbow clovers cannot exceed the 20 percent conversion cap")
	_check(Skills.chest_drop_chance() * Skills.chest_relic_chance() <= 0.012001, "late-game relic expectation is capped at 1.2 percent per kill")


func _test_choice_and_queue() -> void:
	var health: float = main.player.health
	var damage: float = main.player.weapon.get_final_damage()
	Skills.offer_relic(&"dust_blunt_blade", "宝箱", true)
	Skills.offer_relic(&"dust_knife", "宝箱", true)
	await get_tree().create_timer(0.1).timeout
	_check(panel.visible and panel._details.text.contains("损失一颗心"), "brief description preserves the pickup penalty")
	_check(panel._card.size.x <= 420.5 and panel._details.autowrap_mode == TextServer.AUTOWRAP_OFF, "pickup strip uses a compact width and one-line description")
	_check(main.player.health == health and main.player.weapon.get_final_damage() == damage, "pending relic has no effects before choice")
	_check(not Skills.resolve_relic_offer(Skills.pending_relic_offers[1].ticket, true), "cannot accept a queued item out of order")
	panel._discard_button.pressed.emit()
	_check(main.player.health == health and Skills.relic_count(&"dust_blunt_blade") == 0, "discard avoids pickup penalties and grants nothing")
	await get_tree().create_timer(0.1).timeout
	_check(panel.visible and panel._remaining > 4.8, "next item gets its own five seconds")
	panel._take_button.pressed.emit()
	panel._take_button.pressed.emit()
	_check(Skills.relic_count(&"dust_knife") == 1, "pickup applies exactly once even on repeated input")
	_check(Skills.temp_luck() == 0, "accepting a relic does not trigger Koi")
	Skills.offer_relic(&"rare_fate_dice", "天选奖励")
	await get_tree().create_timer(0.1).timeout
	_check(panel._details.text == "定时掷骰，火力随点数起伏" and panel._card.tooltip_text == Skills.get_relic(&"rare_fate_dice").description, "brief text is compact and full numbers remain in the tooltip")
	panel._discard_button.pressed.emit()


func _test_countdown_and_pause() -> void:
	Skills.offer_relic(&"dust_knife", "宝箱")
	await get_tree().create_timer(2.0).timeout
	_check(panel._remaining > 2.8 and panel._remaining < 3.2 and Skills.relic_count(&"dust_knife") == 1, "no auto pickup before five seconds")
	var remaining := panel._remaining
	RunState.request_pause(&"manual_pause")
	await get_tree().create_timer(0.4).timeout
	_check(not panel.visible and is_equal_approx(panel._remaining, remaining), "modal pause hides the card and freezes its timer")
	RunState.release_pause(&"manual_pause")
	await get_tree().create_timer(3.2).timeout
	_check(Skills.relic_count(&"dust_knife") == 2 and Skills.pending_relic_offers.is_empty(), "five active seconds automatically accept")


func _test_reservations_and_death() -> void:
	_check(Skills.offer_relic(&"demon_pointed_vessel", "契约") and not Skills.offer_relic(&"demon_pointed_vessel", "契约"), "unique pending rewards cannot be duplicated")
	Skills.clear_relic_offers()
	for i in 3:
		_check(Skills.offer_relic(&"rare_bullet_shell", "宝箱"), "stack-limited relic can reserve an available slot")
	_check(not Skills.offer_relic(&"rare_bullet_shell", "宝箱"), "pending copies respect stack cap")
	Skills.clear_relic_offers()
	Skills.offer_relic(&"dust_knife", "宝箱")
	var old_ticket: int = Skills.pending_relic_offers[0].ticket
	main.player.take_damage(0.5)
	# 模拟结束事件；Main 的死亡收尾另由冒烟测试覆盖。
	RunState.end_run()
	_check(Skills.pending_relic_offers.is_empty(), "run end clears unclaimed rewards")
	_check(not Skills.resolve_relic_offer(old_ticket, true), "stale card cannot claim after run end")


func _preview() -> void:
	Skills.offer_relic(&"dust_blunt_blade", "宝箱")
	Skills.offer_relic(&"rare_fate_dice", "天选奖励")
	if OS.get_cmdline_user_args().has("--shot"):
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/relic_choice.png")
		get_tree().quit()
		return
	# 验收模式每 12 秒补两件样品，可直接点拾取/丢弃或等待读条。
	while is_inside_tree():
		await get_tree().create_timer(12).timeout
		Skills.offer_relic(&"dust_blunt_blade", "宝箱")
		Skills.offer_relic(&"rare_fate_dice", "天选奖励")


func _unhandled_input(event: InputEvent) -> void:
	if OS.get_cmdline_user_args().has("--preview") and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("RELIC CHOICE %s: %s" % ["PASS" if ok else "FAIL", description])

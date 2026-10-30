extends Node

var failures := 0
var main: Node


func check(ok: bool, label: String) -> void:
	print("SAVE %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _ready() -> void:
	GameSave.storage_path = "user://save_game_test.dat"
	GameSave.clear_run()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	Director.stop()
	main.player.set_physics_process(false)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	for id in [&"energy_1", &"energy_2", &"fire_1", &"speed_3", &"giant_2"]:
		Skills.unlock(id, true)
	Skills.grant_relic(&"rare_bond")
	Skills.grant_relic(&"rare_bond")
	Skills.grant_relic(&"rare_fate_dice")
	Skills.grant_relic(&"epic_weapon_cache")
	if main.weapon_choice_panel.visible:
		main.weapon_choice_panel._choose(0)
	main.player.weapon.acquire_form(&"sword")
	main.player.weapon.acquire_form(&"boomerang")
	Skills.guardian_shields = 3
	Skills.color_shield = ColorType.BLUE
	Skills.soul_kills = 77
	Skills._giant_kills = 45
	Skills._energy_buff_timers.assign([2.5, 4.0])
	Skills._update_energy_buff()
	Skills._weapon_cache_offered = true
	RunState.elapsed = 231.4
	RunState.gold = -275
	RunState.level = 17
	RunState.xp = 33
	RunState.energy = 1.25
	RunState.color_index = ColorType.BLUE
	main.player.health = 1.5
	main.player.global_position = Vector2(720, -410)
	main.player._heavy_timer = 4.7
	Director._boss_spawned = true
	Director._merchant_timer = 44.6
	Pickups.clear()
	Pickups.field._append_item(PickupField.KIND_XP, Vector2(1000, 1000), 17, 0.0)
	Pickups.field._append_item(PickupField.KIND_GOLD, Vector2(1100, 1000), 23, 0.0)
	var damage: float = main.player.weapon.get_final_damage()
	var modifiers: int = main.player.weapon.stats._modifiers.size()
	var dice_roll := Skills.dice_roll()
	var weapons: Array = main.player.weapon.owned_forms.duplicate()
	check(not GameSave.is_live(main), "embedded tests cannot autosave to a player's live slot")
	check(GameSave.write_run(main), "first disk save succeeds")
	check(GameSave.write_run(main), "replacement save and backup succeed")
	var saved := GameSave.read_run()
	check(not saved.is_empty() and saved.run.gold == -275 and saved.run.level == 17, "disk round trip retains run values")
	# Simulate a bad main file; the previous valid save remains loadable.
	var file := FileAccess.open(GameSave.storage_path, FileAccess.WRITE)
	file.store_var({"version": -1})
	file.close()
	check(GameSave.read_run().get("version") == GameSave.VERSION, "invalid primary file falls back to backup")
	check(GameSave.request_continue(), "continue request loads a valid snapshot")
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	check(not menu.buttons[1].disabled, "valid save enables Continue on the main menu")
	menu._activate(1)
	check(menu._next_scene == "res://scenes/main.tscn" and not GameSave.pending.is_empty(),
		"Continue requests saved gameplay rather than opening character selection")
	menu.queue_free()
	main.queue_free()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Director.stop()
	main.player.set_physics_process(false)
	check(is_equal_approx(RunState.elapsed, 231.4) and RunState.gold == -275 and RunState.level == 17 and RunState.xp == 33,
		"new scene resumes time, negative money, level and experience")
	check(main.player.health == 1.5 and main.player.global_position == Vector2(720, -410)
		and is_equal_approx(RunState.energy, 1.25) and RunState.color_index == ColorType.BLUE,
		"health, position, energy and color are restored")
	check(main.player.weapon.owned_forms == weapons and Skills.relic_count(&"rare_bond") == 2,
		"weapons and duplicate relic stacks survive scene recreation")
	check(is_equal_approx(main.player.weapon.get_final_damage(), damage) and main.player.weapon.stats._modifiers.size() == modifiers,
		"stat modifiers restore exactly without replaying relic rewards or penalties")
	check(Skills._energy_buff_mod != null and Skills._dice_damage_mod != null and Skills.dice_roll() == dice_roll,
		"dynamic modifier references reconnect and loading does not reroll dice")
	Skills._energy_buff_timers.clear()
	Skills._update_energy_buff()
	check(Skills._energy_buff_mod.value == 0.0, "restored energy modifier still responds to its timer")
	check(Skills.guardian_shields == 3 and Skills.color_shield == ColorType.BLUE and Skills.soul_kills == 77
		and Skills._giant_kills == 45 and Skills._weapon_cache_offered, "shields, kill counters and one-time shop flags restore")
	check(Director._boss_spawned and Director.boss == null and is_equal_approx(Director._merchant_timer, 44.6),
		"defeated boss stays defeated and merchant schedule is preserved")
	check(Pickups.field.currency_count() == 2 and RunState.xp == 33 and RunState.gold == -275,
		"uncollected drops restore on the ground without crediting money or experience")
	# Active boss, unfinished choices and a shop shelf are persistent too.
	Director._boss_spawned = false
	var boss := Director.spawn_boss_now(Vector2(900, -400))
	boss.health = 321.0
	main.shop_panel.open(main.player)
	var relic := Skills.get_relic(&"epic_weapon_cache")
	main.shop_panel._offers.assign([relic])
	main.shop_panel._offer_prices.assign([0])
	main.shop_panel._sold.assign([false])
	main.shop_panel._free_rerolls = 2
	RunState.request_pause(&"shop")
	check(GameSave.write_run(main) and GameSave.request_continue(), "paused shop can be saved")
	main.queue_free()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Director.stop()
	check(Director.boss != null and Director.boss.health == 321.0, "living boss resumes with saved health")
	check(get_tree().paused and main.shop_panel.visible and main.shop_panel._offers[0].id == relic.id
		and main.shop_panel._offer_prices[0] == 0 and main.shop_panel._free_rerolls == 2,
		"shop resumes the exact shelf, fixed price and free refresh balance")
	main._on_shop_closed()
	main._level_ups_pending = 1
	var options := Skills.pick_options(3)
	var option_ids: Array[StringName] = []
	for option in options:
		option_ids.append(option.id)
	main.level_up_panel.open(options, 1)
	RunState.request_pause(&"level_up")
	main._weapon_rewards.assign(["Boss 宝箱"])
	check(GameSave.write_run(main) and GameSave.request_continue(), "unfinished level choice can be saved")
	main.queue_free()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Director.stop()
	var restored_ids: Array[StringName] = []
	for option in main.level_up_panel._options:
		restored_ids.append(option.id)
	check(main.level_up_panel.visible and restored_ids == option_ids and main.level_up_panel._rerolls_left == 1,
		"unspent upgrade restores exact choices and reroll count")
	check(main._weapon_rewards.size() == 1, "queued boss weapon reward survives the level modal")
	main.level_up_panel._choose(0)
	check(main.weapon_choice_panel.visible, "finishing restored upgrade opens the queued weapon reward")
	var weapon_choices: Array = main.weapon_choice_panel._choices.duplicate()
	check(GameSave.write_run(main) and GameSave.request_continue(), "active weapon choice can be saved")
	main.queue_free()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Director.stop()
	check(main.weapon_choice_panel.visible and main.weapon_choice_panel._choices == weapon_choices,
		"weapon reward resumes exact candidates without rerolling")
	GameSave._main = weakref(main)
	RunState.gold = -123
	GameSave._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(GameSave.read_run().run.gold == -123, "mobile background notification saves current progress")
	main.player.health = 0.5
	main.player._invuln = 0.0
	Skills.guardian_shields = 0
	Skills.color_shield = -1
	main.player.take_damage(1000.0)
	check(GameSave.read_run().is_empty() and RunState.is_dead, "actual death clears the primary and backup saves")
	GameSave._main = null
	GameSave.storage_path = "user://run_save.dat"
	print("SAVE GAME TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().paused = false
	get_tree().quit(0 if failures == 0 else 1)

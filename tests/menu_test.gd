extends Node

## 无头菜单测试：机体数据、选择界面写入选择、加载界面跳转、
## 以及 Main 生成 Player 时使用所选机体与统一基础攻击（角色差异只来自基础倍率）。
## godot --headless --fixed-fps 60 --path . res://tests/menu_test.tscn

var failures := 0


func _ready() -> void:
	var characters := ContentDB.get_characters()
	failures += _check(characters.size() == 1, "only prism is playable")
	failures += _check(
		characters.size() >= 1 and characters[0].id == &"prism",
		"characters are sorted by order"
	)

	# 选择界面：唯一机体出击，写入 RunState 并请求主场景。
	var select := load("res://scenes/character_select.tscn").instantiate() as Control
	add_child(select)
	await get_tree().process_frame
	select.set("_selected", 0)
	select.call("_start_run")
	failures += _check(
		RunState.selected_character_id == &"prism",
		"start run records the selected character"
	)
	failures += _check(
		str(select.get("_next_scene")) == "res://scenes/main.tscn",
		"start run requests the main scene"
	)

	# 加载界面：结束时请求选择机体界面。
	var boot := load("res://scenes/boot.tscn").instantiate() as Control
	select.queue_free()
	add_child(boot)
	await get_tree().process_frame
	boot.call("_finish")
	failures += _check(
		str(boot.get("_next_scene")) == "res://scenes/character_select.tscn",
		"boot screen continues to character select"
	)
	boot.queue_free()
	await get_tree().process_frame

	# 主场景：Player 读取所选机体与武器。
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var player := main.get("player") as Player
	failures += _check(
		player != null and player.character != null and player.character.id == &"prism",
		"main spawns the selected character"
	)
	failures += _check(
		player != null and player.weapon.core != null
			and player.weapon.core.id == CharacterResource.BASE_WEAPON_ID,
		"selected character uses the shared base attack"
	)
	var core: WeaponCoreResource = player.weapon.core
	var prism: CharacterResource = player.character
	failures += _check(
		player != null
			and is_equal_approx(player.weapon.get_final_damage(), core.damage * prism.damage_multiplier)
			and is_equal_approx(
				player.weapon.get_final_fire_rate(),
				core.fire_rate * prism.fire_rate_multiplier
			),
		"character multipliers scale the base attack"
	)
	failures += _check(
		player != null and is_equal_approx(player.max_health, 3.0)
			and is_equal_approx(player.stats.get_value(&"move_speed"), 250.0)
			and is_equal_approx(Skills.xp_multiplier(), 1.2)
			and Skills.relic_count(&"epic_six_sided_die") == 1,
		"selected character stats reach the player"
	)
	failures += _check(is_equal_approx(core.damage, 10.0) and Skills.free_rerolls() == 1,
		"base attack and one free shop refresh")
	main.set("_level_ups_pending", 1)
	main.call("_open_next_level_up")
	var level_panel: LevelUpPanel = main.level_up_panel
	var old_options: Array[StringName] = []
	for option in level_panel._options:
		old_options.append(option.id)
	failures += _check(level_panel._rerolls_left == 1, "starter die grants one skill reroll")
	level_panel.reroll_requested.emit()
	var replaced := true
	for option in level_panel._options:
		if old_options.has(option.id):
			replaced = false
	failures += _check(replaced and level_panel._rerolls_left == 0, "reroll replaces all available options once")
	main.call("_on_skill_chosen", level_panel._options[0])

	# 死亡结算：两个按钮分别请求重开 / 返回主界面；R 也走重开。
	var game_over := GameOverPanel.new()
	add_child(game_over)
	game_over.size = Vector2(1152.0, 648.0)
	game_over.open()
	failures += _check(game_over.visible, "game over panel opens")
	var retry_hits := [0]
	var menu_hits := [0]
	game_over.retry_requested.connect(func() -> void: retry_hits[0] += 1)
	game_over.menu_requested.connect(func() -> void: menu_hits[0] += 1)
	var game_over_buttons: Array = game_over.call("_button_rects")
	_click_control(game_over, game_over_buttons[0].get_center())
	failures += _check(
		retry_hits[0] == 1 and menu_hits[0] == 0,
		"game over retry button requests a restart"
	)
	_click_control(game_over, game_over_buttons[1].get_center())
	failures += _check(menu_hits[0] == 1, "game over menu button requests the main scene")
	_press_key(game_over, KEY_R)
	failures += _check(retry_hits[0] == 2, "R restarts from the game over panel")
	game_over.queue_free()

	# 暂停菜单：确认「返回主界面」发出信号，不再直接关闭游戏。
	var pause := PausePanel.new()
	add_child(pause)
	pause.size = Vector2(1152.0, 648.0)
	Skills.unlock(&"sprite_1", true)
	Skills.unlock(&"circle_1", true)
	pause.open()
	var viewed_branches: Array[StringName] = []
	for entry in pause.get("_branch_cache"):
		viewed_branches.append(entry["branch"])
	failures += _check(viewed_branches.has(&"sprite") and viewed_branches.has(&"circle"),
		"pause skill view includes the new summon and circle branches")
	pause.set("_screen", 2)
	var pause_menu_hits := [0]
	pause.menu_requested.connect(func() -> void: pause_menu_hits[0] += 1)
	var quit_buttons: Array = pause.call("_right_button_rects", pause.call("_layout"), 2)
	_click_control(pause, quit_buttons[1].get_center())
	failures += _check(
		pause_menu_hits[0] == 1,
		"pause quit confirmation returns to the main scene instead of quitting"
	)
	pause.queue_free()
	await get_tree().process_frame

	if failures == 0:
		print("MENU TEST PASS")
	else:
		print("MENU TEST FAIL (%d failures)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _click_control(control: Control, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	control.call("_gui_input", event)


func _press_key(control: Control, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	control.call("_input", event)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("MENU PASS: %s" % label)
		return 0
	print("MENU FAIL: %s" % label)
	return 1

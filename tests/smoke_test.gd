extends Node

## 无头冒烟测试：加载主场景，跑固定时长，检查刷怪/自动攻击/金币经验是否工作。
## 运行：
## godot --headless --fixed-fps 60 --path . res://tests/smoke_test.tscn


func _ready() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	add_child(main)

	await get_tree().create_timer(2.0).timeout
	print("SMOKE intro_done running=%s" % RunState.is_running)
	# 刷怪率翻倍后前十秒就可能升级并暂停；此探针先看连续战斗，末尾单测升级。
	RunState.level = 100

	await get_tree().create_timer(10.0).timeout
	var enemies := get_tree().get_nodes_in_group("enemies")
	var player_health := -1.0
	if main.get("player") != null:
		player_health = main.player.health

	print("SMOKE summary elapsed=%.2f running=%s enemies=%d gold=%d xp=%d level=%d hp=%.1f color=%d energy=%.2f" % [
		RunState.elapsed,
		RunState.is_running,
		enemies.size(),
		RunState.gold,
		RunState.xp,
		RunState.level,
		player_health,
		RunState.color_index,
		RunState.energy,
	])
	print("SMOKE hdr_2d_exists=%s hdr_2d=%s" % [
		ProjectSettings.has_setting("rendering/viewport/hdr_2d"),
		ProjectSettings.get_setting("rendering/viewport/hdr_2d"),
	])

	var failures := 0

	# 泛光脉冲：只在大事件使用，必须能增强并回到基线，不能永久改坏环境。
	var world_environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var glow_before := 0.0
	if world_environment != null and world_environment.environment != null:
		glow_before = world_environment.environment.glow_intensity
	FX.glow_pulse(1.0, 0.12)
	failures += _check(
		world_environment != null
			and world_environment.environment.glow_intensity > glow_before,
		"glow pulse boosts environment glow"
	)
	await get_tree().create_timer(0.25).timeout
	failures += _check(
		world_environment != null
			and is_equal_approx(world_environment.environment.glow_intensity, glow_before),
		"glow pulse returns to baseline"
	)

	var rules := RunState.color_rules
	failures += _check(is_equal_approx(rules.multiplier(ColorType.RED, ColorType.GREEN), 1.5), "red > green +50%")
	failures += _check(is_equal_approx(rules.multiplier(ColorType.GREEN, ColorType.BLUE), 1.5), "green > blue +50%")
	failures += _check(is_equal_approx(rules.multiplier(ColorType.BLUE, ColorType.RED), 1.5), "blue > red +50%")
	failures += _check(is_equal_approx(rules.multiplier(ColorType.RED, ColorType.RED), 0.7), "same color -30%")
	failures += _check(is_equal_approx(rules.multiplier(ColorType.RED, ColorType.BLUE), 1.0), "reverse color 0%")

	var color_before := RunState.color_index
	var energy_before := RunState.energy
	var cycled := RunState.cycle_color(1)
	failures += _check(cycled, "cycle_color succeeds with energy")
	failures += _check(RunState.color_index == ColorType.next(color_before), "color advances by one")
	failures += _check(is_equal_approx(RunState.energy, energy_before - 1.0), "cycle costs 1 energy")

	failures += _check(ContentDB.get_enemies().size() >= 4, "content db has 4 enemy types")
	failures += _check(ContentDB.has(&"basic_bolt"), "content db has basic_bolt")
	failures += _check(ContentDB.get_characters().size() == 1, "one playable character")
	failures += _check(
		main.player.character != null
			and main.player.character.id == RunState.selected_character_id,
		"player uses the selected character"
	)
	failures += _check(
		main.player.weapon.core != null
			and main.player.weapon.core.id == CharacterResource.BASE_WEAPON_ID,
		"player uses the shared base attack"
	)
	failures += _check(Skills.nodes.size() == 76, "skill tree has 76 nodes")
	failures += _check(Skills.relics.size() == 52, "relic pool has 52 relics")
	failures += _check(not Skills.get_available_nodes().is_empty(), "skill tree offers starting nodes")

	# 手动暂停：Esc / 右上角按钮走同一条路径，关闭后恢复 HUD。
	main._toggle_manual_pause()
	failures += _check(get_tree().paused, "manual pause pauses the tree")
	failures += _check(main.pause_panel.visible, "manual pause opens the pause panel")
	failures += _check(not main.hud_control.visible, "HUD hides while manually paused")
	main._toggle_manual_pause()
	failures += _check(not get_tree().paused, "manual resume unpauses the tree")
	failures += _check(not main.pause_panel.visible, "pause panel closes on resume")
	failures += _check(main.hud_control.visible, "HUD returns after manual pause")

	var was_paused := get_tree().paused
	RunState.request_pause(&"smoke_test")
	failures += _check(get_tree().paused, "request_pause pauses the tree")
	RunState.release_pause(&"smoke_test")
	if not was_paused:
		failures += _check(not get_tree().paused, "release_pause resumes the tree")

	# 受伤反击：近身强制击杀，外圈击退。
	var enemy_scene := load("res://scenes/enemies/enemy.tscn") as PackedScene
	var near_enemy := enemy_scene.instantiate()
	near_enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player)
	main.world.add_child(near_enemy)
	near_enemy.global_position = main.player.global_position + Vector2(40.0, 0.0)

	var far_enemy := enemy_scene.instantiate()
	far_enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player)
	main.world.add_child(far_enemy)
	far_enemy.global_position = main.player.global_position + Vector2(200.0, 0.0)

	main.player.set("_invuln", 0.0)
	main.player.take_damage(0.5)
	failures += _check(near_enemy.is_dead, "panic shockwave kills nearby enemies")
	failures += _check(float(far_enemy.get("_knockback_time")) > 0.0, "panic shockwave knocks back outer enemies")

	if is_instance_valid(far_enemy):
		far_enemy.queue_free()
	await get_tree().create_timer(1.0).timeout

	# 升级流程：暂停 -> 面板 -> 选择 -> 应用数值 -> 恢复。
	if not get_tree().paused:
		var needed := RunState._xp_threshold(RunState.level) - RunState.xp
		if needed > 0:
			RunState.add_xp(needed)
			await get_tree().create_timer(0.05).timeout

			failures += _check(get_tree().paused, "level up pauses the tree")
			failures += _check(main.level_up_panel.visible, "level up panel opens")

			var options: Array = main.level_up_panel.get("_options")
			if options.is_empty():
				failures += _check(false, "level up offers options")
			else:
				var chosen: SkillNodeResource = options[0]
				var before_count := Skills.unlocked_count()
				main.level_up_panel._choose(0)

				failures += _check(not get_tree().paused, "level up resumes after choice")
				failures += _check(Skills.unlocked_count() == before_count + 1, "chosen skill is unlocked")
				failures += _check(Skills.is_unlocked(chosen.id), "chosen skill id is recorded")

	# 死亡结算：死亡演出后弹出结算面板并暂停战场。
	EventBus.player_died.emit()
	await get_tree().create_timer(0.9).timeout
	failures += _check(main.game_over_panel.visible, "game over panel opens after the death beat")
	failures += _check(get_tree().paused, "game over pauses the tree")

	# 恢复树状态再退出，避免暂停中关闭导致对象清理不完整。
	main.game_over_panel.close()
	RunState.release_pause(&"game_over")

	if failures > 0:
		print("SMOKE FAILURES: %d" % failures)
		get_tree().quit(1)
	else:
		print("SMOKE all assertions passed")
		get_tree().quit(0)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("SMOKE PASS: %s" % label)
		return 0
	print("SMOKE FAIL: %s" % label)
	return 1

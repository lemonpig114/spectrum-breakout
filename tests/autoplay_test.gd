extends Node

## 自动游玩集成测试：随机选技能、持续切色、注入经验，让弹幕/状态/溅射/灵魂
## 在真实战斗循环中跑 30 秒，最后检查没有卡在暂停或丢失玩家。
##
## godot --headless --fixed-fps 60 --path . res://tests/autoplay_test.tscn

const DURATION := 30.0

var failures := 0
var main: Node
var player: Player
var chosen := 0


func _ready() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	main = main_scene.instantiate()
	add_child(main)

	await get_tree().create_timer(2.4).timeout
	player = main.player
	failures += _check(player != null, "player exists")
	await _autoplay()

	# 收尾：若最后一帧刚好弹出面板，先关掉再断言。
	if get_tree().paused:
		main.level_up_panel.close()
		main.set("_level_ups_pending", 0)
		RunState.release_pause(&"level_up")

	failures += _check(chosen > 0, "autoplay chose at least one skill")
	failures += _check(Skills.unlocked_count() == chosen, "every chosen skill was unlocked")
	failures += _check(Skills.unlocked_count() <= Skills.nodes.size(), "unlock count stays bounded")
	failures += _check(not get_tree().paused, "autoplay ends unpaused")
	failures += _check(player.health > 0.0, "player survived the autoplay run")
	failures += _check(RunState.is_running, "run is still active")
	failures += _check(get_tree().get_nodes_in_group("enemies").size() > 0, "combat kept spawning enemies")

	print("AUTOPLAY skills=%d enemies=%d level=%d time=%.1f %s" % [
		Skills.unlocked_count(),
		get_tree().get_nodes_in_group("enemies").size(),
		RunState.level,
		RunState.elapsed,
		"PASS" if failures == 0 else "FAIL",
	])
	get_tree().quit(0 if failures == 0 else 1)


func _autoplay() -> void:
	var elapsed := 0.0
	var xp_timer := 0.0

	while elapsed < DURATION and is_instance_valid(player) and player.health > 0.0:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta

		# 保持无敌，让测试专注于技能与战斗结算而不是生存。
		player.set("_invuln", 1.0)

		if main.level_up_panel.visible:
			var options: Array = main.level_up_panel.get("_options")
			if options.is_empty():
				main._finish_level_ups()
			else:
				main.level_up_panel._choose(RunState.rng.randi_range(0, options.size() - 1))
				chosen += 1

		xp_timer += delta
		if xp_timer >= 0.8:
			xp_timer = 0.0
			RunState.add_xp(6)

		if RunState.can_switch_color() and RunState.rng.randf() < delta * 0.8:
			RunState.cycle_color(1)


func _check(condition: bool, label: String) -> int:
	if condition:
		print("AUTOPLAY PASS: %s" % label)
		return 0
	print("AUTOPLAY FAIL: %s" % label)
	return 1

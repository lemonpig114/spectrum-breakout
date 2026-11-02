extends Node

## Boss 宝箱专项无头测试：
## godot --headless --fixed-fps 60 --path . res://tests/boss_chest_test.tscn
##
## 覆盖：Boss 击杀掉出可拾取宝箱、远处不会被自动拾取、靠近后播开箱动画、
## 动画播完才打开武器三选一。

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
	player.set("_invuln", 9999.0)
	failures += _check(Skills.relic_count(&"epic_infinite_die") == 1 and Skills.relic_count(&"epic_six_sided_die") == 0,
		"prism starts with infinite die instead of six-sided die")
	for i in 5:
		failures += _check(Skills.grant_relic(&"rare_reroll"), "four-sided die stacks")
	failures += _check(not Skills.grant_relic(&"rare_reroll"), "four-sided die rejects sixth copy")
	for i in 3:
		failures += _check(Skills.grant_relic(&"epic_six_sided_die"), "six-sided die stacks")
	failures += _check(not Skills.grant_relic(&"epic_six_sided_die"), "six-sided die rejects fourth copy")
	failures += _check(Skills.free_rerolls() == 9 and Skills.level_up_rerolls() == 4 and Skills.weapon_reward_rerolls() == 1,
		"three dice contribute to their distinct refresh pools")


	var panel: Node = main.weapon_choice_panel
	failures += _check(not panel.visible, "no weapon panel before any chest")

	# 击杀 Boss：不再直接开武器三选一，而是掉出必须自己捡的宝箱。
	Director.set("_boss_spawned", false)
	var boss := Director.spawn_boss_now(player.global_position + Vector2(240.0, 0.0))
	failures += _check(boss != null, "boss spawns")
	boss.force_kill()
	await get_tree().process_frame
	await get_tree().process_frame

	var chests := get_tree().get_nodes_in_group("boss_chest")
	failures += _check(chests.size() == 1, "boss drops one pickable chest")
	failures += _check(not panel.visible, "killing the boss does not open weapons directly yet")
	failures += _check(GameSave.snapshot(main).has("boss_chest"),
		"pending chest is written into the save snapshot")
	if chests.is_empty():
		_finish()
		return

	var chest := chests[0] as Node2D
	# 清掉 Boss 掉落的经验/金币，避免测试里走近宝箱时升级暂停、冻住开箱动画。
	Pickups.clear()
	# 宝箱停在远处，不应被磁吸 / 自动拾取。
	await get_tree().create_timer(1.2).timeout
	failures += _check(is_instance_valid(chest) and not panel.visible,
		"chest is never auto-collected from a distance")

	# 走到宝箱上：播开箱动画，动画播完才弹武器三选一。
	player.global_position = chest.global_position
	await get_tree().create_timer(0.35).timeout
	failures += _check(not panel.visible, "weapon panel waits for the opening animation")
	await get_tree().create_timer(1.6).timeout
	failures += _check(panel.visible, "opening the chest then reveals the weapon choice")
	var previous: Array = panel._choices.duplicate()
	panel._reroll()
	failures += _check(panel._rerolls_left == 0 and panel._choices != previous,
		"infinite die rerolls Boss reward once with new weapons")

	failures += _check(not GameSave.snapshot(main).has("boss_chest"),
		"opened chest is no longer written into the snapshot")

	_finish()


func _finish() -> void:
	print("BOSS CHEST TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> int:
	if ok:
		print("BOSSCHEST PASS: %s" % label)
		return 0
	print("BOSSCHEST FAIL: %s" % label)
	return 1

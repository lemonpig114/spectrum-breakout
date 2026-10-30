extends Node
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FAIL ", message)

func _ready() -> void:
	var screen: Control = load("res://scenes/character_select.tscn").instantiate()
	add_child(screen)
	screen._open_codex()
	await get_tree().process_frame
	var panel: Control = screen._codex_panel
	check(panel.visible, "codex opens")
	check(panel.entries.size() == 145, "80 skills + 55 relics + 7 enemies + 3 guides")
	for i in 4:
		panel.set_category(i)
		check(panel.filtered.size() == [80, 55, 7, 3][i], "category count")
		for j in panel.filtered.size():
			panel.show_entry(j)
			check(not panel.detail.text.is_empty(), "detail content")
	panel.set_category(1)
	panel.search.text = "命运骰子"
	panel.refresh()
	check(panel.filtered.size() == 1 and panel.detail.text.contains("2"), "dice search and limit")
	panel.search.text = "does-not-exist"
	panel.refresh()
	check(panel.filtered.is_empty(), "empty search")
	panel.closed.emit()
	await get_tree().process_frame
	check(not panel.visible and not screen._started, "close without starting")
	screen.queue_free()
	check(Director.enemy_limit(0) == 40 and Director.enemy_limit(120) == 100 and Director.enemy_limit(300) == 80, "bounded population")
	check(is_equal_approx(Director.health_multiplier(59), 1.0) and is_equal_approx(Director.health_multiplier(60), 1.5), "first-minute hp")
	check(is_equal_approx(Director.health_multiplier(120), 2.0), "third phase hp")
	check(is_equal_approx(Director.health_multiplier(240), 3.5), "plane phase hp")
	check(is_equal_approx(Director.health_multiplier(600), 35.0), "endless base hp")
	check(Director.enemy_damage_multiplier(239.9) == 1.0, "half-heart contact before 240")
	check(Director.enemy_damage_multiplier(240) == 2.0, "full-heart contact after 240")
	var stats := StatBlock.new()
	stats.set_base(&"damage", 10)
	var mod := StatModifierResource.new()
	mod.stat = &"damage"
	mod.source = &"test"
	mod.op = StatModifierResource.Op.FLAT
	mod.value = 5
	stats.add_modifier(mod)
	check(stats.get_value(&"damage") == 15, "indexed modifier")
	mod.value = 9
	check(stats.get_value(&"damage") == 19, "in-place dynamic modifier")
	stats.remove_modifiers_from(&"test")
	check(stats.get_value(&"damage") == 10, "removed index")
	# 验证普通刷新与包围刷新使用同一曲线，资源不被改写。
	var world := Node2D.new()
	add_child(world)
	var target := Node2D.new()
	world.add_child(target)
	Director.world = world
	Director.player = target
	Director._enemy_types = ContentDB.get_enemies()
	RunState.elapsed = 600
	var kind: EnemyTypeResource = ContentDB.get_enemies()[0]
	var base := kind.max_health
	Director._spawn_enemy(kind)
	Director._spawn_ring(3)
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 4, "both spawning paths")
	for enemy in enemies:
		check(is_equal_approx(enemy.health, enemy.type_data.max_health * Director.health_multiplier(600.0)), "spawn hp scaling")
	check(kind.max_health == base, "shared resource unchanged")
	RunState.elapsed = 0
	world.queue_free()
	await get_tree().process_frame
	print("CODEX BALANCE TEST ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

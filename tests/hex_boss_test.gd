extends Node

var failures := 0
var main: Node
var boss: HexBoss


func check(ok: bool, label: String) -> void:
	print("HEX BOSS %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func hit(amount: float, weak: bool, neutral: bool = false) -> void:
	var context := DamageContext.new()
	context.source = main.player
	context.target = boss
	context.amount = amount
	context.color_index = -1 if neutral else ColorType.next(boss.edge_colors[0], -1 if weak else 0)
	context.hit_position = boss.to_global((boss._vertices[0] + boss._vertices[1]) * 0.5)
	if weak:
		context.add_tag(&"weakness")
	boss.take_damage(context)


func mob(id: StringName, at: Vector2) -> Enemy:
	var enemy := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(id), main.player)
	main.world.add_child(enemy)
	enemy.global_position = at
	enemy.set_physics_process(false)
	return enemy


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.0).timeout
	Director.stop()
	main.player.set_physics_process(false)
	main.player.controls_enabled = false
	main.player._invuln = 999.0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	RunState.elapsed = 420.0
	Director._boss_spawned = true
	Director.start()
	Director._process(0.0)
	boss = Director.hex_boss
	check(boss != null and Director._hex_boss_spawned, "director automatically spawns the hex boss at 420 seconds")
	Director._process(0.0)
	check(Director.hex_boss == boss, "director spawns the hex boss only once")
	Director.stop()
	Director._boss_spawned = false
	RunState.elapsed = 0.0
	boss.global_position = main.player.global_position + Vector2(300, 0)
	boss.set_physics_process(false)
	check(boss.edge_health.size() == 6 and boss.edge_max_health == 375000.0, "six independent 25000 times fifteen edges")
	if OS.get_cmdline_user_args().has("--preview"):
		await preview()
		return
	for i in 6:
		var point := boss.to_global((boss._vertices[i] + boss._vertices[(i + 1) % 6]) * 0.5)
		check(boss.damage_color_at(point) == boss.edge_colors[i], "each edge owns its collision color")
		var weak_color := ColorType.next(boss.edge_colors[i], -1)
		var context := Skills.build_hit_context(main.player, boss, 100, weak_color, false, false, point)
		check(context.has_tag(&"weakness"), "shared hit resolver checks impacted edge color")
		context = Skills.build_hit_context(main.player, boss, 100, boss.edge_colors[i], false, false, point)
		var hp := boss.health
		boss.take_damage(context)
		check(boss.health == hp, "same-color impact resisted on each edge")
	var before := boss.edge_health[0]
	hit(1000.0, false)
	check(boss.edge_health[0] == before, "colored nonweak hits are resisted")
	hit(1000.0, true)
	check(boss.edge_health[0] == before - 1000.0 and boss.edge_health[1] == boss.edge_max_health, "weak hit damages only the impacted edge")
	before = boss.edge_health[0]
	hit(1000.0, false, true)
	check(boss.edge_health[0] == before - 50.0, "neutral damage applies five percent")
	before = boss.health
	boss.take_true_damage(1000.0)
	check(is_equal_approx(before - boss.health, 50.0), "soul damage applies five percent")
	var old_speed := boss.move_speed_for_edges()
	var old_spin := boss.spin_speed_for_edges()
	var hex := mob(&"chaser_hex", boss.global_position + Vector2(400, 0))
	var triangle := mob(&"chaser_triangle", boss.global_position + Vector2(400, 100))
	boss.edge_health[1] = 1234.0
	boss._damage_edge(0, boss.edge_max_health * 2.0)
	check(boss.edge_health.size() == 5 and boss.edge_health[0] == boss.edge_max_health, "breaking one edge refills every surviving edge")
	check(boss.move_speed_for_edges() > old_speed and boss.spin_speed_for_edges() > old_spin, "fewer edges increase movement and spin")
	check(hex._hex_rally_time == 5.0 and triangle._hex_rally_time == 0.0, "break gives five second rally only to existing ordinary hex enemies")
	var hp := hex.health
	var context := DamageContext.new()
	context.amount = 1000000.0
	hex.take_damage(context)
	hex.take_true_damage(1000000.0)
	hex.force_kill()
	check(hex.health == hp and not hex.is_dead, "rallied hex blocks direct, soul and forced-kill damage")
	var overlay := get_tree().get_first_node_in_group(&"enemy_overlay_renderer") as EnemyOverlayRenderer
	overlay._process(0.0)
	check(int(overlay.counts[&"rally"]) == 1, "rally has a batched visible shield outline")
	var initial := boss._vertices.duplicate()
	boss._update_morph(HexBoss.MORPH_DURATION * 0.5)
	check(boss._vertices != initial and boss._vertices != boss._morph_to, "surviving corners move through an intermediate shape")
	boss._update_morph(HexBoss.MORPH_DURATION)
	var reached := true
	for i in boss._vertices.size():
		reached = reached and boss._vertices[i].distance_to(boss._morph_to[i]) < 0.001
	check(reached, "reconnection animation reaches the new polygon")
	var bar := BossHealthBar.new()
	bar.set_health(100, 100)
	bar.set_health(50, 100)
	bar.step(0.1)
	check(bar.ratio == 0.5 and bar.trail == 1.0, "front health updates immediately while rear health pauses")
	bar.step(0.5)
	check(bar.trail > 0.5 and bar.trail < 1.0, "rear health eases down instead of vanishing instantly")
	boss._dash_cd = 0.0
	boss._physics_process(0.016)
	var direction := boss._dash_direction
	check(boss._windup > 0.0 and boss._dash_left == 0.0, "dash has an obvious windup")
	main.player.global_position += Vector2(0, 200)
	boss._physics_process(HexBoss.DASH_WINDUP)
	check(boss._dash_left > 0.0 and boss._dash_direction == direction and boss._dash_cd == 15.0, "dash locks one direction and starts a fifteen second cooldown")
	triangle.global_position = boss.global_position + Vector2(100, 0)
	hex.global_position = triangle.global_position
	boss._crush_enemies(boss.global_position, boss.global_position + Vector2(200, 0))
	check(triangle.is_dead and not hex.is_dead, "dash crushes mobs while respecting five second hex invulnerability")
	var count := boss.edge_health.size()
	boss.force_kill()
	boss.execute()
	check(not boss.is_dead and boss.edge_health.size() == count and not boss.can_be_executed(), "execution cannot bypass the edge fight")
	GameSave.storage_path = "user://hex_boss_test.dat"
	GameSave.clear_run()
	boss._dash_left = 0.0
	boss._damage_edge(0, boss.edge_max_health * 2.0)
	boss._update_morph(0.2)
	var saved_vertices := boss._vertices.duplicate()
	var saved_colors := boss.edge_colors.duplicate()
	Director._endless_announced = true
	check(GameSave.write_run(main) and GameSave.request_continue(), "boss can save during a reconnection")
	main.queue_free()
	await get_tree().process_frame
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Director.stop()
	main.player.set_physics_process(false)
	main.player._invuln = 999.0
	boss = Director.hex_boss
	boss.set_physics_process(false)
	check(boss != null and boss.edge_health.size() == 4 and boss._vertices == saved_vertices,
		"continue restores edge count, health and intermediate polygon")
	check(boss.edge_colors == saved_colors, "continue restores independent edge colors")
	check(Director._endless_announced, "continue preserves already shown endless announcement")
	var expected_colors := boss.edge_colors.duplicate()
	expected_colors.remove_at(expected_colors.size() - 1)
	var closing_corner := boss._vertices[boss._vertices.size() - 1]
	boss._damage_edge(boss.edge_health.size() - 1, boss.edge_max_health * 2.0)
	check(boss.edge_colors == expected_colors and boss._vertices[0] == closing_corner,
		"breaking the closing edge preserves surviving color and vertex alignment")
	while not boss.is_dead and boss.edge_health.size() > 2:
		boss._damage_edge(0, boss.edge_max_health * 2.0)
	check(boss.is_dead and boss.edge_health.size() == 2, "boss dies exactly at two remaining edges")
	GameSave.clear_run()
	GameSave.storage_path = "user://run_save.dat"
	get_tree().paused = false
	print("HEX BOSS TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func preview() -> void:
	boss._dash_cd = 0.0
	boss._physics_process(0.016)
	boss._damage_edge(1, boss.edge_max_health * 0.6)
	var hex := mob(&"chaser_hex", boss.global_position + Vector2(150, 95))
	hex.rally_hex()
	if OS.get_cmdline_user_args().has("--broken"):
		boss._damage_edge(0, boss.edge_max_health * 2.0)
		boss._update_morph(0.27)
	if OS.get_cmdline_user_args().has("--endless"):
		RunState.elapsed = 540.0
		EventBus.endless_mode_entered.emit()
		main.hud_control._endless_banner_time = 5.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := "visual_endless_banner.png" if OS.get_cmdline_user_args().has("--endless") else ("visual_hex_boss_broken.png" if OS.get_cmdline_user_args().has("--broken") else "visual_hex_boss.png")
	get_viewport().get_texture().get_image().save_png("res://tests/" + filename)
	get_tree().quit()

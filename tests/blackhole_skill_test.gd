extends Node

var failures := 0
var main: Node
var hole: BlackHoleField
var enemy: Enemy


func check(ok: bool, message: String) -> void:
	print("BLACKHOLE %s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	main.player.controls_enabled = false
	main.player.set_physics_process(false)
	main.player._invuln = 999.0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	hole = main.get_node("World/BlackHoleField")
	hole.set_physics_process(false)
	Skills.unlock(&"blackhole_1")
	if OS.get_cmdline_user_args().has("--preview") or OS.get_cmdline_user_args().has("--preview-initial"):
		await preview()
		return
	hole._physics_process(4.9)
	check(not hole.active, "first cast waits five seconds")
	hole._physics_process(0.1)
	check(hole.active, "first cast starts at five seconds")
	hole.cast(main.player.global_position + Vector2(150, 0))
	enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
	main.world.add_child(enemy)
	enemy.global_position = hole.global_position
	enemy.set_physics_process(false)
	enemy.health = 100000.0
	enemy.max_health = 100000.0
	hole._physics_process(0.5)
	check(is_equal_approx(enemy.health, 99995.0), "half second tick deals five percent of stored damage")
	check(is_equal_approx(enemy._blackhole_slow, 0.4), "initial slow remains forty percent")
	var manager: ProjectileManager = main.projectile_manager
	manager.fire(hole.global_position + Vector2(20, 0), Vector2.RIGHT, main.player.weapon.stats, ColorType.BLUE, main.player.weapon.core)
	var shot: Projectile = manager._active.back()
	shot.damage = 100.0
	var at := shot.global_position
	hole._capture_nearby()
	check(hole.orbits.size() == 1 and shot.orbiting, "capture owns original projectile")
	var before := enemy.health
	hole._physics_process(0.1)
	check(shot.global_position == at and shot.scale.x < 1 and shot.active_index >= 0, "captured projectile shrinks without rotation or movement")
	check(enemy.health == before, "shrinking projectile performs no collision damage")
	hole._physics_process(0.11)
	check(shot.active_index < 0 and hole.orbits.is_empty(), "short shrink returns projectile to pool")
	check(is_equal_approx(hole.damage, 135.0) and hole.absorbed == 1, "absorption adds thirty-five percent once")
	hole._physics_process(0.01)
	check(hole.damage == 135.0, "no duplicate absorption credit")
	hole.suppress_absorb_animation = true
	manager.fire(hole.global_position, Vector2.RIGHT, main.player.weapon.stats, ColorType.BLUE, main.player.weapon.core)
	shot = manager._active.back()
	shot.damage = 40
	hole._capture_nearby()
	check(shot.active_index < 0 and hole.orbits.is_empty() and hole.damage == 149.0, "low FPS skips animation but preserves full thirty-five percent credit")
	hole.suppress_absorb_animation = false
	var attack := {"damage": 80.0, "hit_radius": 20.0, "color": ColorType.BLUE, "visual_scale": 1.0, "consumed": false}
	check(hole.capture_weapon_attack(attack, hole.global_position), "area attack capture remains supported")
	hole._physics_process(0.1)
	check(float(attack.visual_scale) < 1.0 and not attack.consumed, "area attack uses the same short shrink")
	Skills.unlock(&"blackhole_2")
	before = enemy.health
	var expected := (hole.damage + 80.0 * 0.35) * 6.0
	hole.finish()
	check(attack.consumed and hole.orbits.is_empty(), "finish drains pending captures before explosion")
	check(is_equal_approx(before - enemy.health, expected), "explosion deals six hundred percent including pending absorption")
	hole.cast(hole.global_position)
	Skills.unlock(&"fragile_1")
	Skills.unlock(&"blackhole_3")
	before = enemy.health
	hole._physics_process(0.5)
	check(enemy.health < before - 15.0 and enemy.vulnerability > 0, "black hole tick activates fragile through shared damage resolver")
	check(is_equal_approx(enemy._blackhole_slow, 0.7), "tier three retains seventy percent slow")
	Skills.unlock(&"blackhole_4")
	check(hole.size_limit() == BlackHoleField.BASE_RADIUS * 8.0, "tier four size limit remains eight times")
	check(hole.orbit_scale(0.0) == 1.0 and hole.orbit_scale(0.2) == 0.0, "short animation scale is bounded")
	check(not main.player.weapon.acquire_form(&"black_hole"), "black hole remains a skill")
	print("BLACKHOLE TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func preview() -> void:
	if OS.get_cmdline_user_args().has("--preview-initial"):
		hole.cast(main.player.global_position + Vector2(150, 0))
		hole.set_physics_process(true)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/visual_blackhole_outer_range.png")
		get_tree().quit()
		return
	for id in [&"blackhole_2", &"blackhole_3", &"blackhole_4"]:
		Skills.unlock(id)
	hole.cast(main.player.global_position + Vector2(150, 0))
	hole.radius = 90.0
	hole.target_radius = 90.0
	for i in 18:
		var at := hole.global_position + Vector2.from_angle(i * TAU / 18.0) * (90.0 + (i % 3) * 20.0)
		hole._capture(at, 10.0, 4.5, RunState.color_of(i % 3))
	hole.set_physics_process(true)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/visual_blackhole_skill.png")
	get_tree().quit()

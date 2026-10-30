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
	main.player.set("_invuln", 999.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	hole = main.get_node("World/BlackHoleField")
	hole.set_physics_process(false)
	Skills.unlock(&"blackhole_1")
	if OS.get_cmdline_user_args().has("--preview") or OS.get_cmdline_user_args().has("--preview-initial"):
		await preview()
		return
	if OS.get_cmdline_user_args().has("--preview-collapse"):
		Skills.unlock(&"blackhole_2")
		hole.cast(main.player.global_position + Vector2(160, 0))
		hole.radius = 110.0
		var preview_enemy := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		preview_enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
		main.world.add_child(preview_enemy)
		preview_enemy.set_physics_process(false)
		preview_enemy.global_position = hole.global_position + Vector2(45, 0)
		preview_enemy.health = 10000.0
		preview_enemy.max_health = 10000.0
		hole.finish()
		hole._burst = 0.59
		hole._request_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/visual_blackhole_collapse.png")
		get_tree().quit()
		return
	check(not main.player.weapon.acquire_form(&"black_hole"), "removed from weapon pool")
	check(Skills.nodes.size() == 80, "four skills added to catalog")
	check(Skills._rarity_color(RelicResource.RARITY_DUST) == Color(0.65, 0.65, 0.65), "dust quality is neutral gray")
	hole._physics_process(4.9)
	check(not hole.active, "first unlock waits five seconds")
	hole._physics_process(0.2)
	check(hole.active and hole.damage == 100.0 and hole.radius == 40.0 and hole.effect_radius() == 60.0, "casts enlarged black hole with a sixty-unit outer gameplay radius")
	hole.cast(main.player.global_position + Vector2(200, 0))
	enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.configure(ContentDB.get_enemy(&"chaser_triangle"), main.player, ColorType.RED)
	enemy.position = hole.global_position + Vector2(15, 0)
	main.world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.health = 10000
	enemy.max_health = 10000
	var before := enemy.health
	var initial_distance := enemy.global_position.distance_to(hole.global_position)
	hole._physics_process(1.0)
	check(is_equal_approx(before - enemy.health, 5.0), "tick is five percent non-elemental damage")
	check(is_equal_approx(enemy.get("_blackhole_slow"), 0.4) and not enemy.has_ice(), "forty percent slow has no ice attachment")
	check(enemy.global_position.distance_to(hole.global_position) < initial_distance, "tier one already tugs enemies")
	check(is_equal_approx(Skills.damage_totals.get(&"skill:blackhole_1", 0.0), 5.0), "damage attributed to black hole skill")
	hole.cast(hole.global_position)
	main.projectile_manager.fire(hole.global_position + Vector2(35, 0), Vector2.RIGHT,
		main.player.weapon.stats, ColorType.BLUE, main.player.weapon.core)
	var shot: Projectile = main.projectile_manager._active.back()
	shot.damage = 20.0
	hole._capture_nearby()
	check(hole.orbits.size() == 1 and shot.active_index >= 0 and shot.orbiting and hole.damage == 100.0, "captured bullet stays alive and orbits before credit")
	check(shot.visible and shot.batch_rendered, "capture preserves original bullet renderer")
	var shot_position := shot.global_position
	enemy.global_position = shot.global_position
	before = enemy.health
	hole._physics_process(0.05)
	check(enemy.health < before and hole.damage == 100.0, "orbiting bullet still damages enemies before absorption")
	check(shot.active_index >= 0 and shot.visible and shot.orbit_exhausted,
		"spent orbiting bullet stays visible but cannot deal another hit")
	check(hole.target_radius > 40.0, "black hole starts growing before damage is credited")
	check(shot.global_position != shot_position and shot.scale.x < 1.0 and shot.visible,
		"original bullet moves and shrinks along the orbit")
	hole._physics_process(1.85)
	check(hole.damage == 100.0 and hole.orbits.size() == 1, "damage is not credited before two seconds")
	hole._physics_process(0.11)
	check(hole.damage == 110.0 and hole.orbits.size() == 1 and shot.active_index >= 0,
		"two seconds credits fifty percent damage while original bullet remains alive")
	hole._physics_process(1.0)
	check(hole.damage == 110.0 and hole.orbits.is_empty() and hole.target_radius > 40.0 and shot.active_index < 0, "three seconds releases bullet without double credit")
	check(hole.cooldown < 20.0 and hole.cooldown > 16.0, "subsequent cooldown remains twenty seconds")
	for i in 40:
		hole._capture(hole.global_position + Vector2(40, 0), 10.0, 4.0, Color.WHITE)
	hole._physics_process(3.0)
	check(is_equal_approx(hole.target_radius, 160.0), "tier-one radius caps at four times original")
	hole._physics_process(4.0)
	check(not hole.active, "absorption never extends ten-second lifetime")
	Skills.unlock(&"blackhole_2")
	hole.cast(hole.global_position)
	enemy.position = hole.global_position + Vector2(45, 0)
	before = enemy.health
	FX._direct_label_frame = -1
	hole.finish()
	check(is_equal_approx(before - enemy.health, 300.0) and hole.get("_burst_radius") == 120.0, "tier-two explosion deals triple stored damage in double outer radius")
	var text_layer := FX._text_layer as FloatingTextLayer
	var text_index := (text_layer._cursor - 1 + FloatingTextLayer.MAX_TEXTS) % FloatingTextLayer.MAX_TEXTS
	check(text_layer._sizes[text_index] == text_layer._size_for(FloatingTextLayer.STYLE_CRIT)
		and text_layer._styles[text_index] == FloatingTextLayer.STYLE_BURST
		and text_layer._captions[text_index].is_empty(), "explosion uses crit-size neutral text without a false crit caption")
	hole.finish()
	check(is_equal_approx(before - enemy.health, 300.0), "explosion cannot resolve twice")
	Skills.unlock(&"blackhole_3")
	hole.cast(hole.global_position)
	enemy.position = hole.global_position + Vector2(20, 0)
	var distance := enemy.global_position.distance_to(hole.global_position)
	before = enemy.health
	hole._physics_process(1.0)
	check(is_equal_approx(enemy.get("_blackhole_slow"), 0.7) and enemy.global_position.distance_to(hole.global_position) < distance, "tier-three seventy percent slow and displacement tug")
	check(is_equal_approx(before - enemy.health, 15.0), "tier-three tick deals fifteen percent stored damage")
	for id in [&"chaser_triangle", &"chaser_hex", &"square_boss"]:
		var data := ContentDB.get_enemy(id)
		check(data != null, "resistance fixture exists: %s" % id)
		if data == null:
			continue
		var body := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		body.configure(data, null)
		main.world.add_child(body)
		body.set_physics_process(false)
		body.position = Vector2(500, 500)
		var factor := 0.0 if data.is_boss else (0.6 if id == &"chaser_hex" else 1.0)
		body.apply_gravity_displacement(Vector2(20, 0))
		check(is_equal_approx(body.position.x - 500.0, 20.0 * factor), "forced displacement resistance: %s" % id)
		body.apply_knockback(body.global_position - Vector2.RIGHT * 20, 100.0)
		check(is_equal_approx(body._knockback_velocity.length(), 100.0 * factor), "knockback resistance: %s" % id)
		body.apply_water_push(Vector2.RIGHT)
		check(is_equal_approx(body._water_push.length(), 24.0 * factor), "water push resistance: %s" % id)
		body.queue_free()
	var hostile := EnemyProjectile.new()
	hostile.configure(hole.global_position + Vector2(40, 0), Vector2.RIGHT, main.player, Color.RED, 100.0, 2.0)
	main.world.add_child(hostile)
	hostile.set_physics_process(false)
	hole._capture_nearby()
	check(not hostile.is_queued_for_deletion(), "enemy bullets survive before tier four")
	Skills.unlock(&"blackhole_4")
	hole._capture_nearby()
	check(not hostile.is_queued_for_deletion() and hostile.orbiting and hole.orbits.size() == 1, "tier four captures enemy projectiles")
	for i in 90:
		hole._capture(hole.global_position + Vector2(40, 0), 10.0, 4.0, Color.WHITE)
	hole._physics_process(3.0)
	check(is_equal_approx(hole.target_radius, 320.0), "tier-four size caps at eight times original")
	check(hole.radius < hole.target_radius, "growth interpolates instead of jumping to the target size")
	await get_tree().create_timer(0.35).timeout
	check(is_equal_approx(hole.radius, hole.target_radius), "growth tween reaches its target")
	hole.cast(main.player.global_position + Vector2(120, 0))
	enemy.global_position = hole.global_position + Vector2(1000, 0)
	check(main.player._find_nearest_enemy() == hole, "player can aim at an active black hole")
	check(main.projectile_manager.friendly_target(main.player.global_position, 500.0, {}) == hole, "homing projectiles can seek a black hole")
	var clone := MirrorClone.new()
	main.world.add_child(clone)
	clone.setup(main.player, main.player.global_position)
	clone.set_physics_process(false)
	check(clone._nearest_enemy() == hole, "ranged clones can target the black hole")
	hole.age = 8.0
	check(main.player._find_nearest_enemy() != hole, "black hole stops drawing fire when it can no longer capture")
	hole.cast(hole.global_position)
	enemy.global_position = hole.global_position + Vector2(56, 0)
	initial_distance = enemy.global_position.distance_to(hole.global_position)
	before = enemy.health
	hole._physics_process(1.0)
	check(enemy.health < before and enemy._blackhole_slow == 0.7
		and enemy.global_position.distance_to(hole.global_position) < initial_distance,
		"dim outer ring deals damage, slows, and tugs beyond the body radius")
	enemy.global_position = hole.global_position + Vector2(hole.effect_radius() + enemy.radius + 2.0, 0)
	before = enemy.health
	hole._physics_process(1.0)
	check(enemy.health == before, "enemy wholly outside the outer ring takes no periodic damage")
	main.projectile_manager.fire(hole.global_position + Vector2(95, 0), Vector2.RIGHT,
		main.player.weapon.stats, ColorType.BLUE, main.player.weapon.core)
	shot = main.projectile_manager._active.back()
	hole._capture_nearby()
	check(shot.orbiting, "bullet capture also uses the expanded outer radius")
	test_overload_and_cadence()
	await test_area_absorption()
	print("BLACKHOLE TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func test_overload_and_cadence() -> void:
	for count in [50, 51]:
		hole.cast(hole.global_position)
		enemy.global_position = hole.global_position + Vector2(1000, 0)
		for i in count:
			hole._capture(hole.global_position + Vector2(80, 0), 10.0, 5.0, Color.WHITE)
		hole._physics_process(0.1)
		check(is_equal_approx(float(hole.orbits[0].age), 0.1 if count == 50 else 0.2),
			"overload speed switches only above fifty: %d" % count)
	hole.cast(hole.global_position)
	for i in 80:
		hole._capture(hole.global_position + Vector2(80, 0), 10.0, 5.0, Color.WHITE)
	main.projectile_manager.fire(hole.global_position + Vector2(35, 0), Vector2.RIGHT,
		main.player.weapon.stats, ColorType.BLUE, main.player.weapon.core)
	var shot: Projectile = main.projectile_manager._active.back()
	shot.damage = 20.0
	hole._capture_nearby()
	check(hole.orbits.size() == 80 and shot.active_index < 0 and hole.damage == 110.0
		and hole.absorbed == 1 and hole.target_radius > 40.0, "overflow projectile immediately credits, grows, and returns to pool")
	var damage_before := hole.damage
	hole._capture_nearby()
	check(hole.damage == damage_before and hole.absorbed == 1, "overflow cannot be credited twice")
	var combat: WeaponCombat = main.projectile_manager.combat
	var sword := WeaponRuntime.new(main.player.weapon.core)
	sword.acquire_form(&"sword")
	combat.fire_weapon(hole.global_position - Vector2(30, 0), Vector2.RIGHT, sword.stats,
		ColorType.BLUE, false, sword)
	combat._physics_process(0.001)
	var sword_damage: float = combat._sword_waves.back().damage
	hole._capture_nearby()
	check(hole.orbits.size() == 80 and combat._sword_waves.is_empty() and combat._absorbed_attacks.is_empty()
		and is_equal_approx(hole.damage, damage_before + sword_damage * 0.5),
		"overflow sword is removed without leaving an orphan absorbed visual")
	var hostile := EnemyProjectile.new()
	hostile.configure(hole.global_position + Vector2(30, 0), Vector2.RIGHT, main.player, Color.RED, 100.0, 2.0)
	main.world.add_child(hostile)
	damage_before = hole.damage
	hole._capture_nearby()
	check(hostile.is_queued_for_deletion() and hole.orbits.size() == 80 and hole.damage == damage_before + 1.0,
		"tier-four hostile overflow is also swallowed immediately")
	hole.cast(hole.global_position)
	main.projectile_manager.fire(hole.global_position + Vector2(90, 0), Vector2.RIGHT,
		main.player.weapon.stats, ColorType.BLUE, main.player.weapon.core)
	shot = main.projectile_manager._active.back()
	hole._capture_nearby()
	hole._physics_process(1.0 / 60.0)
	var checked_at: Vector2 = hole.orbits[0].last_hit_position
	var visual_at := shot.global_position
	hole._physics_process(1.0 / 60.0)
	check(hole.orbits[0].last_hit_position == checked_at and shot.global_position != visual_at,
		"visual moves every physics frame while collision checks are skipped")
	enemy.global_position = shot.global_position
	var health_before := enemy.health
	hole._physics_process(1.0 / 60.0)
	check(hole.orbits[0].last_hit_position == checked_at and enemy.health == health_before, "second skipped frame performs no orbit hit")
	hole._physics_process(1.0 / 60.0)
	check(hole.orbits[0].last_hit_position != checked_at and enemy.health < health_before,
		"third-frame swept check covers travel since the previous check")


func test_area_absorption() -> void:
	check(is_equal_approx(hole.orbit_scale(2.0), 0.88) and hole.orbit_scale(1.0) > 0.9,
		"first two seconds only slightly shrink captured attacks")
	check(hole.orbit_scale(2.5) < 0.3 and is_zero_approx(hole.orbit_scale(3.0)),
		"final second rapidly shrinks captured attacks to zero")
	var combat: WeaponCombat = main.projectile_manager.combat
	combat.set_physics_process(false)
	for projectile in main.projectile_manager._active.duplicate():
		main.projectile_manager.release(projectile)
	for form in [&"sword", &"wave", &"scythe", &"lightning"]:
		hole.cast(main.player.global_position + Vector2(200, 0))
		enemy.global_position = hole.global_position + Vector2(1000, 0)
		var weapon := WeaponRuntime.new(main.player.weapon.core)
		weapon.acquire_form(form)
		weapon.stats.set_base(&"pierce", 0)
		combat._events.clear()
		combat._head = 0
		combat.fire_weapon(hole.global_position - Vector2(45, 0), Vector2.RIGHT, weapon.stats,
			ColorType.BLUE, false, weapon)
		combat._physics_process(0.001)
		hole._capture_nearby()
		check(hole.orbits.size() == 1 and hole.orbits[0].has("attack"), "captures non-projectile form: %s" % form)
		if hole.orbits.is_empty() or not hole.orbits[0].has("attack"):
			continue
		var attack: Dictionary = hole.orbits[0].attack
		check(attack.form == form and combat._absorbed_attacks.has(attack), "preserves absorbed visual form: %s" % form)
		await get_tree().process_frame
		enemy.global_position = hole.orbits[0].last_position
		var before := enemy.health
		hole._physics_process(0.05)
		check(enemy.health < before and int(attack.remaining) == 0, "captured attack hits once without pierce: %s" % form)
		before = enemy.health
		hole._physics_process(0.05)
		check(enemy.health == before and combat._absorbed_attacks.has(attack), "spent attack remains visible without repeat damage: %s" % form)
		hole._physics_process(1.4)
		check(hole.target_radius > 40.0 and hole.damage == 100.0, "black hole grows during absorption without early damage credit: %s" % form)
		hole._physics_process(0.6)
		check(is_equal_approx(hole.damage, 100.0 + float(attack.damage) * 0.5) and not hole.orbits.is_empty(),
			"area attack credits at two seconds before visual disappearance: %s" % form)
		hole._physics_process(1.0)
		check(hole.orbits.is_empty() and not combat._absorbed_attacks.has(attack)
			and is_equal_approx(hole.damage, 100.0 + float(attack.damage) * 0.5), "area attack credits once and clears after three seconds: %s" % form)
	var weapon := WeaponRuntime.new(main.player.weapon.core)
	weapon.acquire_form(&"sword")
	weapon.stats.set_base(&"pierce", 1)
	var event := {"weapon": weapon, "direction": Vector2.RIGHT, "damage": 10.0,
		"color": ColorType.BLUE, "budget": combat.new_budget()}
	var attack := combat._make_absorbed_attack(event, &"sword", Vector2.ZERO)
	combat.hit_absorbed_attack(attack, enemy, Vector2.RIGHT)
	check(int(attack.remaining) == 1, "one pierce leaves one additional target after the first hit")
	var before := enemy.health
	combat.hit_absorbed_attack(attack, enemy, Vector2.RIGHT)
	check(enemy.health == before and int(attack.remaining) == 1, "pierce cannot repeatedly hit the same target")
	var second := load("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	second.configure(ContentDB.get_enemy(&"chaser_triangle"), null, ColorType.RED)
	main.world.add_child(second)
	second.set_physics_process(false)
	second.health = 10000.0
	combat.hit_absorbed_attack(attack, second, Vector2.RIGHT)
	check(second.health < 10000.0 and int(attack.remaining) == 0, "pierce allows a second distinct enemy then exhausts")
	second.queue_free()
	for form in [&"star", &"boomerang", &"sprite", &"cannon"]:
		hole.cast(main.player.global_position + Vector2(200, 0))
		enemy.global_position = hole.global_position + Vector2(1000, 0)
		var shot_weapon := WeaponRuntime.new(main.player.weapon.core)
		shot_weapon.acquire_form(form)
		combat.fire_weapon(hole.global_position + Vector2(35, 0), Vector2.RIGHT, shot_weapon.stats,
			ColorType.BLUE, false, shot_weapon)
		var shot: Projectile = main.projectile_manager._active.back()
		hole._capture_nearby()
		check(shot.orbiting and shot.visible and shot.form_at_fire == form,
			"original projectile form remains visible during absorption: %s" % form)
		hole._physics_process(2.1)
		check(shot.active_index >= 0 and is_equal_approx(hole.damage, 100.0 + shot.damage * 0.5),
			"projectile credits after two seconds before release: %s" % form)
		hole._physics_process(1.0)
		check(shot.active_index < 0 and hole.orbits.is_empty(), "projectile releases after three seconds: %s" % form)
	combat._events.clear()
	combat._head = 0
	var fusion := WeaponRuntime.new(main.player.weapon.core)
	fusion.acquire_form(&"sword")
	fusion.acquire_form(&"star")
	var fusion_attack := combat._make_absorbed_attack({"weapon": fusion, "direction": Vector2.RIGHT,
		"damage": 10.0, "color": ColorType.BLUE, "budget": combat.new_budget()}, &"sword", Vector2.ZERO)
	combat.hit_absorbed_attack(fusion_attack, enemy, Vector2.RIGHT)
	check(combat._events.size() == 1 and combat._events[0].kind == &"split",
		"absorbed sword preserves star fusion through the bounded event queue")
	combat._events.clear()
	combat._head = 0


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

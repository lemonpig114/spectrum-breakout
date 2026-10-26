extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

var failures := 0
var main: Node
var player: Player
var field: SummonField


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await get_tree().process_frame
	player = main.player
	field = main.world.get_node("SummonField") as SummonField
	player.set("_invuln", 999.0)
	check(field != null, "summon manager attached")
	_test_offer_and_fragile()
	_test_soul()
	await _test_sprite_and_clone()
	await _test_sprite_targeting()
	_test_damage_captions()
	_test_circle()
	_test_giant()
	print("REFORM SKILLS TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_offer_and_fragile() -> void:
	check(Skills._branch_offer_bonus(&"fragile") == 1.0, "unselected branch has normal offer weight")
	check(Skills.unlock(&"fragile_1"), "unlock fragile tier 1")
	check(Skills._branch_offer_bonus(&"fragile") == 1.5, "selected branch has 1.5x offer weight")
	var enemy := spawn_enemy(Vector2(500, 500), 1000.0)
	var context := DamageContext.new()
	context.amount = 10.0
	context.color_index = ColorType.RED
	enemy.take_damage(context)
	check(is_equal_approx(enemy.vulnerability, 0.2), "first hit attaches 20% independent vulnerability")
	check(is_equal_approx(enemy.health, 988.0), "vulnerability amplifies first hit")
	enemy._tick_statuses(1.0)
	check(is_equal_approx(enemy.vulnerability, 0.15), "vulnerability decays five points per second")
	Skills.unlock(&"fragile_2")
	Skills.unlock(&"fragile_3")
	Skills.unlock(&"fragile_4")
	enemy.take_damage(context)
	check(is_equal_approx(enemy.vulnerability, 0.155), "later hit adds half a point")
	enemy._tick_statuses(1.0)
	check(is_equal_approx(enemy.vulnerability, 0.13), "tier 3 halves decay")
	var second := spawn_enemy(Vector2(540, 500), 1000.0)
	second.take_damage(context)
	check(is_equal_approx(second.vulnerability, 0.35), "tier 2 raises first-hit ceiling")
	enemy.queue_free()
	second.queue_free()


func _test_soul() -> void:
	Skills.unlock(&"soul_1")
	Skills.soul_kills = 5
	var stats := player.weapon.stats
	var expected := (stats.get_value(&"damage") * stats.get_value(&"damage_mult") + 5.0) * 1.2
	check(is_equal_approx(Skills.soul_damage(), expected), "soul damage uses raw attack times multiplier plus souls")
	Skills.unlock(&"soul_2")
	Skills.unlock(&"soul_3")
	Skills.unlock(&"soul_4")
	expected = (stats.get_value(&"damage") * stats.get_value(&"damage_mult") + 10.0) * 1.7
	check(is_equal_approx(Skills.soul_damage(), expected), "tier 4 counts souls twice")
	Skills.set("_soul_timer", 999.0)


func _test_sprite_and_clone() -> void:
	Skills.unlock(&"sprite_1")
	Skills.unlock(&"sprite_2")
	Skills.unlock(&"sprite_3")
	await get_tree().create_timer(0.08).timeout
	var first_enemy := spawn_enemy(player.global_position + Vector2(100, 0), 1000.0)
	var base_sprite := field.companions[0]
	base_sprite.global_position = player.global_position
	base_sprite._begin_dash(first_enemy)
	check(is_equal_approx(base_sprite.get("_dash_cooldown"), 2.0), "base sprite dash cooldown is two seconds")
	check(base_sprite.get("_dash_end").distance_to(base_sprite.global_position) >= 440.0, "base sprite crosses its target")
	check(is_equal_approx(base_sprite._dash_speed(), 900.0) and is_equal_approx(base_sprite._return_speed(), 380.0), "base sprite movement speeds")
	base_sprite._update_trail()
	var trail := base_sprite.get("_trail") as Line2D
	var dash_opacity := trail.gradient.sample(0.0).a
	check(trail.width_curve.sample(1.0) < trail.width_curve.sample(0.0), "sprite trail tapers toward its tail")
	base_sprite.set("_dashing", false)
	base_sprite.set("_returning", false)
	base_sprite._update_trail()
	check(trail.gradient.sample(0.0).a < dash_opacity, "idle trail is fainter than dash trail")
	first_enemy.queue_free()
	Skills.unlock(&"sprite_4")
	base_sprite.set("_dashing", true)
	base_sprite._update_trail()
	check(trail.width >= 14.0, "grown sprite dash trail widens with the body")
	base_sprite.set("_dashing", false)
	Skills.unlock(&"clone_1")
	Skills.unlock(&"clone_2")
	Skills.unlock(&"clone_3")
	Skills.unlock(&"clone_4")
	await get_tree().create_timer(0.08).timeout
	check(field.companions.size() == 3, "sprite tiers create three companions")
	var colors := {}
	for companion in field.companions:
		colors[companion.color_index] = true
	check(colors.size() == 3, "three sprites distribute colors evenly")
	check(is_equal_approx(player.stats.get_value(&"summon_damage"), 1.6), "summon damage modifiers stack")
	var enemy := spawn_enemy(player.global_position + Vector2(100, 0), 1000.0)
	var sprite := field.companions[0]
	var bonus_before := sprite.base_bonus
	sprite._hit_along(enemy.global_position - Vector2(20, 0), enemy.global_position + Vector2(20, 0))
	check(enemy.health < 1000.0, "sprite dash hits enemy")
	check(is_equal_approx(sprite.base_bonus, bonus_before + 0.5), "tier 4 grows only that sprite's base attack")
	var second := spawn_enemy(player.global_position + Vector2(260, 0), 1000.0)
	sprite.global_position = player.global_position
	var first_health := enemy.health
	sprite._begin_dash(enemy)
	check(is_equal_approx(sprite.get("_dash_cooldown"), 1.3), "tier 4 sprite dash cooldown is 1.3 seconds")
	check(sprite.get("_dash_end").distance_to(sprite.global_position) >= 520.0, "tier 4 sprite travels farther")
	check(sprite._dash_speed() > 900.0 and sprite._return_speed() > 380.0, "tier 4 sprite dashes and returns faster")
	check(sprite.get("_dash_end").x > second.global_position.x, "sprite locks a dash endpoint beyond its first target")
	for step in 15:
		sprite._physics_process(0.05)
	check(enemy.health < first_health and second.health < 1000.0, "sprite keeps hitting enemies after crossing its target")
	sprite.set("_dash_cooldown", 99.0)
	for step in 25:
		sprite._physics_process(0.1)
	check(sprite.global_position.distance_to(player.global_position) < 45.0, "sprite returns close to player after dash")
	check(field.clones.size() == 1, "clone summons at unlock")
	var clone := field.clones[0]
	check(is_equal_approx(clone.health, 3.0), "colored clone has three hearts")
	clone.set("_shot_cooldown", 0.0)
	clone._physics_process(0.016)
	var clone_shot := false
	for projectile in main.projectile_manager._active:
		if projectile.source_kind == &"clone":
			clone_shot = true
			check(projectile.pierce == 0, "clone shot does not inherit pierce")
			break
	check(clone_shot, "clone fires a pooled single shot")
	enemy.queue_free()
	second.queue_free()


func _test_damage_captions() -> void:
	var enemy := spawn_enemy(player.global_position + Vector2(180, 0), 1000.0)
	var neutral := Skills.build_hit_context(player, enemy, 10.0, -1, false, false)
	check(neutral.relation == &"neutral" and is_equal_approx(neutral.amount, 10.0),
		"uncolored clone damage stays neutral")
	check(enemy._damage_caption(neutral).is_empty(), "uncolored clone has no weakness caption")
	var weak_color := -1
	for color in ColorType.COUNT:
		if RunState.color_relation(color, enemy.color_index) == &"advantage":
			weak_color = color
			break
	var colored := Skills.build_hit_context(player, enemy, 10.0, weak_color, false, false)
	check(colored.has_tag(&"weakness"), "colored tier-three clone can deal weakness damage")
	colored.add_tag(&"elemental")
	colored.is_crit = true
	check(enemy._damage_caption(colored) == "元素 · 弱点 · 暴击", "damage caption keeps all hit tags")
	colored.add_tag(&"super_crit")
	check(enemy._damage_caption(colored) == "元素 · 超暴击", "super critical caption omits weakness")
	enemy.queue_free()


func _test_circle() -> void:
	Skills.unlock(&"circle_1")
	Skills.unlock(&"circle_2")
	var early_victim := spawn_enemy(player.global_position + Vector2(30, 0), 1.0)
	for i in 30:
		field._on_enemy_killed(early_victim, 0, 0.0)
	var early_souls := Skills.soul_kills
	field._circle_damage_tick()
	check(early_victim.is_dead and Skills.soul_kills == early_souls,
		"tier 2 circle damage never grants souls")
	early_victim.queue_free()
	field.set("_circle_time", 0.0)
	Skills.unlock(&"circle_3")
	Skills.unlock(&"circle_4")
	var victim := spawn_enemy(player.global_position + Vector2(30, 0), 1000.0)
	for i in 30:
		field._on_enemy_killed(victim, 0, 0.0)
	check(is_equal_approx(field.get("_circle_time"), SummonField.CIRCLE_DURATION),
		"thirty kills open a ten-second circle")
	var outside := spawn_enemy(player.global_position + Vector2(500, 0), 1000.0)
	field._on_enemy_killed(outside, 0, 0.0)
	check(is_equal_approx(field.get("_circle_time"), SummonField.CIRCLE_DURATION),
		"kills outside the circle do not extend it")
	field._on_enemy_killed(victim, 0, 0.0)
	check(is_equal_approx(field.get("_circle_time"), SummonField.CIRCLE_DURATION),
		"circle kills never extend remaining time beyond the original duration")
	field._tick_circle(1.0)
	var before_inside_kill: float = field.get("_circle_time")
	field._on_enemy_killed(victim, 0, 0.0)
	check(is_equal_approx(field.get("_circle_time"), before_inside_kill + 0.5),
		"kill centered inside the circle restores half a second")
	var edge := spawn_enemy(field.get("_circle_position") + Vector2(SummonField.CIRCLE_RADIUS * 1.35 + 5.0, 0.0), 1000.0)
	var before_edge_kill: float = field.get("_circle_time")
	field._on_enemy_killed(edge, 0, 0.0)
	check(is_equal_approx(field.get("_circle_time"), before_edge_kill + 0.5),
		"enemy brushing the circle edge also extends time")
	field._tick_circle(0.01)
	check(player.weapon.stats.get_value(&"damage_mult") > 1.4, "player inside circle gains damage")
	check(player.weapon.stats.get_value(&"fire_rate_mult") > 1.2, "player inside circle gains fire rate")
	var before := victim.health
	field._circle_damage_tick()
	var expected_tick := (10.0 + float(Skills.soul_kills)) * 0.25 * 1.35
	check(is_equal_approx(before - victim.health, expected_tick), "circle soul damage is halved again")
	var souls_before := Skills.soul_kills
	field._on_enemy_killed(victim, 0, 0.0)
	check(Skills.soul_kills == souls_before, "tier 4 does not grant souls for other kills inside circle")
	var field_victim := spawn_enemy(player.global_position + Vector2(40, 0), 1.0)
	field._circle_damage_tick()
	check(field_victim.is_dead and Skills.soul_kills == souls_before + 1,
		"tier 4 grants one soul only when circle damage kills")
	victim.queue_free()
	outside.queue_free()
	edge.queue_free()
	field_victim.queue_free()


func _test_sprite_targeting() -> void:
	await get_tree().process_frame
	var sprite := field.companions[0]
	sprite.global_position = player.global_position
	var ordinary := spawn_enemy(player.global_position + Vector2(55.0, 0.0), 1000.0)
	ordinary.color_index = sprite.color_index
	var weak_color := -1
	for color in ColorType.COUNT:
		if RunState.color_relation(sprite.color_index, color) == &"advantage":
			weak_color = color
	var weak := spawn_enemy(player.global_position + Vector2(170.0, 0.0), 1000.0)
	weak.color_index = weak_color
	var boss := spawn_enemy(player.global_position + Vector2(320.0, 0.0), 1000.0, &"square_boss")
	check(sprite._choose_target() == boss, "sprite prioritizes a reachable boss over closer enemies")
	boss.queue_free()
	await get_tree().process_frame
	check(sprite._choose_target() == weak, "sprite prioritizes weakness over closer ordinary enemies")
	weak.queue_free()
	ordinary.queue_free()


func _test_giant() -> void:
	var max_before := player.max_health
	var radius_before := player.body_radius
	Skills.unlock(&"giant_1")
	check(player.max_health >= max_before + 1.0 and player.body_radius > radius_before, "giant tier 1 adds heart and body size")
	Skills.unlock(&"giant_2")
	Skills._tick_giant_scaling()
	check(player.weapon.stats.get_value(&"projectile_size") > player.weapon.core.projectile_size, "body growth enlarges projectiles")
	Skills.unlock(&"giant_3")
	player.health = 0.5
	Skills.unlock(&"giant_4")
	check(is_equal_approx(player.health, player.max_health), "giant tier 4 immediately heals to full")
	Skills.set("_giant_kills", 299)
	var victim := spawn_enemy(Vector2(700, 700), 1000.0)
	player.health = player.max_health - 1.0
	Skills._on_enemy_killed(victim, 0, 0.0)
	check(is_equal_approx(player.health, player.max_health - 0.5), "giant restores half a heart per 300 kills")
	victim.queue_free()


func spawn_enemy(position_value: Vector2, hp: float, type_id: StringName = &"chaser_triangle") -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.configure(ContentDB.get_enemy(type_id), player)
	main.world.add_child(enemy)
	enemy.global_position = position_value
	enemy.max_health = hp
	enemy.health = hp
	return enemy


func check(condition: bool, label: String) -> void:
	if condition:
		print("REFORM PASS: %s" % label)
	else:
		failures += 1
		print("REFORM FAIL: %s" % label)

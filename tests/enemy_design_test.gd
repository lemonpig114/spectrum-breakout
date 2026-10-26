extends Node2D

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

class TargetDummy extends Node2D:
	var hits := 0
	var damage_taken := 0.0
	func take_damage(amount: float, _source: Node = null) -> void:
		hits += 1
		damage_taken += amount

var failures := 0


func _ready() -> void:
	var triangle := ContentDB.get_enemy(&"chaser_triangle")
	var square := ContentDB.get_enemy(&"chaser_square")
	var hex := ContentDB.get_enemy(&"chaser_hex")
	var plane_type := ContentDB.get_enemy(&"ranged_plane")
	var round_type := ContentDB.get_enemy(&"chaser_round")
	_check(triangle != null and square != null and hex != null and plane_type != null and round_type != null, "six enemy roles load")
	_check(triangle.max_health == 25.0 and triangle.move_speed > square.move_speed, "triangle fast and 25 hp")
	_check(square.max_health == 60.0 and square.xp_reward == 1.5, "square 60 hp and 1.5 xp")
	_check(hex.max_health == 200.0 and hex.radius > square.radius and hex.move_speed == square.move_speed and hex.xp_reward == 5.0 and hex.gold_reward == 5, "hex armored with normal speed and fivefold drops")
	_check(plane_type.behavior == &"ranged" and plane_type.shape == &"airplane" and plane_type.max_health == 28.0 and plane_type.move_speed < triangle.move_speed and plane_type.shot_interval == 3.0 and plane_type.preferred_distance == 340.0, "plane joins timed spawn at half-screen range")
	_check(round_type.behavior == &"explode" and round_type.max_health < triangle.max_health and round_type.move_speed > triangle.move_speed and round_type.explosion_radius == 64.0, "fast fragile exploding round")

	RunState.begin_run()
	Pickups.spawn_xp(Vector2.ZERO, 1.5)
	_check(RunState.xp == 1, "first fractional pickup grants one xp")
	Pickups.spawn_xp(Vector2.ZERO, 1.5)
	_check(RunState.xp == 3, "fraction carries to next pickup")

	var dummy := TargetDummy.new()
	add_child(dummy)
	dummy.global_position = Vector2(120, 0)
	for color in ColorType.COUNT:
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.configure(triangle, dummy, color)
		add_child(enemy)
		enemy.set_physics_process(false)
		_check(enemy.color_index == color and enemy.type_data == triangle, "shape and color independent %d" % color)
		enemy.queue_free()
	await get_tree().process_frame

	var plane := ENEMY_SCENE.instantiate() as Enemy
	plane.configure(plane_type, dummy, ColorType.BLUE)
	add_child(plane)
	plane.global_position = Vector2.ZERO
	plane.set_physics_process(false)
	_check(plane._wing_top.size() == 3 and plane._wing_bottom.size() == 3, "two triangle wings built")
	Director._enemy_types = [plane_type]
	RunState.elapsed = 999.0
	_check(Director._pick_type() == null, "plane not selected before spawn plan")
	RunState.start()
	plane._fire_ranged()
	_check(get_tree().get_nodes_in_group(&"enemy_projectiles").size() == 1, "plane fires visible projectile")
	await get_tree().create_timer(0.55).timeout
	_check(dummy.hits == 1 and is_equal_approx(dummy.damage_taken, plane_type.contact_damage * 2.0), "late projectile deals one heart once")
	_check(get_tree().get_nodes_in_group(&"enemy_projectiles").is_empty(), "projectile clears after impact")
	RunState.elapsed = 300.0
	var round_enemy := ENEMY_SCENE.instantiate() as Enemy
	round_enemy.configure(round_type, dummy, ColorType.RED)
	add_child(round_enemy)
	round_enemy.set_physics_process(false)
	round_enemy.global_position = dummy.global_position + Vector2(50, 0)
	round_enemy.velocity = Vector2(round_type.move_speed, 0)
	round_enemy._round_spark_timer = 0.0
	for _step in 12:
		round_enemy._update_round_sparks(0.016)
	_check(round_enemy._round_spark_positions.size() <= 2 and not round_enemy._round_spark_positions.is_empty(), "moving round emits sparse sparks")
	round_enemy.force_kill()
	_check(dummy.hits == 2 and dummy.damage_taken == 2.0, "nearby death blast deals one heart once")
	_check(get_tree().get_nodes_in_group(&"round_blasts").size() == 1, "round death shows a brief blast")
	_check(get_tree().get_nodes_in_group(&"round_blasts")[0].get("max_radius") == round_type.explosion_radius, "visible blast matches its damage radius")
	var distant_round := ENEMY_SCENE.instantiate() as Enemy
	distant_round.configure(round_type, dummy, ColorType.RED)
	add_child(distant_round)
	distant_round.set_physics_process(false)
	distant_round.global_position = dummy.global_position + Vector2(65, 0)
	distant_round.force_kill()
	_check(dummy.hits == 2, "blast ends outside its small radius")
	RunState.end_run()
	print("ENEMY DESIGN TEST %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
	print("ENEMY DESIGN %s: %s" % ["PASS" if condition else "FAIL", label])

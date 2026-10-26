extends Node2D

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

class TargetDummy extends Node2D:
	var hits := 0
	var damage_taken := 0.0
	func take_damage(amount: float, _source: Node = null) -> void:
		hits += 1
		damage_taken += amount

var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", label)

func _ready() -> void:
	RunState.begin_run()
	RunState.elapsed = 180.0
	var world := Node2D.new()
	add_child(world)
	var dummy := TargetDummy.new()
	world.add_child(dummy)
	dummy.global_position = Vector2(120, 0)
	Director.world = world
	Director.player = dummy
	Director.set("_boss_spawned", false)
	RunState.start()
	var boss := Director.spawn_boss_now(Vector2.ZERO)
	check(boss != null and boss.type_data.is_boss and boss.max_health == 125000.0, "boss inherits the 180-second health multiplier")
	check(Director.spawn_boss_now(Vector2.ZERO) == boss, "boss spawns once")
	boss.set_physics_process(false)
	var kind := ContentDB.get_enemy(&"chaser_square")
	var near := ENEMY_SCENE.instantiate() as Enemy
	near.configure(kind, dummy, ColorType.RED)
	world.add_child(near)
	near.global_position = Vector2(100, 0)
	near.set_physics_process(false)
	var far := ENEMY_SCENE.instantiate() as Enemy
	far.configure(kind, dummy, ColorType.RED)
	world.add_child(far)
	far.global_position = Vector2(650, 0)
	far.set_physics_process(false)
	boss._enhance_squares(SquareBoss.ENHANCE_RADIUS)
	check(near.empowered and near.max_health == 180.0 and near._speed_multiplier == 1.2, "first enhancement triples hp and adds speed")
	check(not far.empowered, "radius excludes far square")
	near.health = 7.0
	boss._enhance_squares(SquareBoss.ENHANCE_RADIUS)
	check(near.max_health == 180.0 and near.health == 180.0, "second enhancement only heals")
	boss._begin_action(&"summon")
	check(boss._summon_points.size() == 12 and boss._windup >= 0.9, "summon warns at twelve locations")
	boss._resolve_action()
	var summons := get_tree().get_nodes_in_group(&"boss_summons")
	check(summons.size() == 12, "summons twelve squares")
	for summoned in summons:
		(summoned as Enemy).set_physics_process(false)
		check((summoned as Enemy).empowered and summoned.color_index == boss.color_index, "summon starts enhanced and dyed")
	var old_color := boss.color_index
	far.health = 3.0
	boss._begin_action(&"promote")
	check(boss._promote_color != old_color and boss._windup >= 1.1, "promotion has readable windup")
	boss._resolve_action()
	check(boss.color_index != old_color and far.empowered and far.health == far.max_health and far.color_index == boss.color_index, "promotion enhances every square")
	boss._script_index = 2
	boss._script_timer = 0.0
	boss._action = &""
	boss._hammer_cooldown = 0.0
	boss._physics_process(0.016)
	check(boss._action == &"promote", "due promotion cannot be replaced by hammer")
	boss._resolve_action()
	boss._begin_action(&"hammer")
	check(boss._windup >= 0.9 and boss._hammer_cooldown == 10.0, "hammer charge and cooldown")
	dummy.global_position = boss._hammer_point
	boss._resolve_action()
	check(dummy.hits == 1 and dummy.damage_taken == 0.5, "hammer follows the pre-240 half-heart rule")
	check(boss._hammer_fx_time > 0.4 and boss._hammer_fx_center == boss._hammer_point, "hammer leaves grounded impact")
	# 冲击波现在是圆形判定：对角位置超出半径不应再被方形包围盒误伤。
	var reach := SquareBoss.HAMMER_RADIUS + Player.RADIUS
	dummy.global_position = boss._hammer_point + Vector2(reach * 0.74, reach * 0.74)
	boss._wave_impact(boss._hammer_point, SquareBoss.HAMMER_RADIUS)
	check(dummy.hits == 1, "shockwave hitbox is circular")
	dummy.global_position = Vector2(650, 0)
	boss._begin_action(&"dash")
	var locked_target: Vector2 = boss._dash_target
	check(locked_target.distance_to(Vector2(650, 0)) >= 119.0 and boss._windup >= 0.75 and boss._dash_cooldown == 20.0, "dash locks a point beyond the player with shorter charge")
	dummy.global_position = Vector2(850, 0)
	boss._resolve_action()
	boss._step_dash(boss._dash_duration)
	check(boss.global_position.distance_to(locked_target) < 0.1, "dash reaches locked location")
	# Boss 受击不再挤压；攻击预警与本体同一 CanvasItem，缩放会连带拉歪预警框。
	boss._squash()
	for frame in 14:
		boss._physics_process(0.016)
	check(boss.scale.is_equal_approx(Vector2.ONE), "boss ignores hit squash so telegraphs stay stable")
	world.queue_free()
	RunState.end_run()
	await get_tree().process_frame
	print("BOSS TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

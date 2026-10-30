class_name MirrorClone
extends Node2D

## 分身继承玩家当前主武器与基础战斗属性；不继承超暴击。
var player: Player
var lifetime := 15.0
var color_index := -1
var _duration_added := false
var _switch_cooldown := 0.0
var _shot_cooldown := 0.45
var _aim := Vector2.RIGHT
var _age := 0.0
var _target_scan_timer := 0.0
var _cached_target: Node2D


func setup(owner_player: Player, position_value: Vector2) -> void:
	player = owner_player
	global_position = position_value
	if Skills.is_unlocked(&"clone_3"):
		lifetime += 5.0
		_duration_added = true


func _ready() -> void:
	z_index = 4
	add_to_group(&"friendly_clones")


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	if player == null or not is_instance_valid(player) or RunState.is_dead:
		queue_free()
		return
	_age += delta
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return
	if Skills.is_unlocked(&"clone_3") and not _duration_added:
		lifetime += 5.0
		_duration_added = true
	_switch_cooldown = maxf(0.0, _switch_cooldown - delta)
	_shot_cooldown -= delta
	_target_scan_timer -= delta
	if _target_scan_timer <= 0.0 or not is_instance_valid(_cached_target) \
			or (_cached_target is Enemy and _cached_target.is_dead) \
			or (_cached_target.has_method("can_be_targeted") and not _cached_target.can_be_targeted()):
		_cached_target = _nearest_enemy()
		_target_scan_timer = 0.10
	var enemy := _cached_target
	var melee := player.weapon.primary_form == &"sword"
	var desired := player.global_position + Vector2.from_angle(_age * 0.75) * (70.0 if melee else 145.0)
	if enemy != null and (melee or global_position.distance_squared_to(enemy.global_position) < 400.0 * 400.0):
		var away := (global_position - enemy.global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT
		desired = enemy.global_position + away * maxf(enemy.radius + 24.0, 58.0 if melee else 135.0)
	if global_position.distance_squared_to(player.global_position) > 450.0 * 450.0:
		desired = player.global_position
	global_position = global_position.move_toward(desired, player.effective_move_speed() * delta)
	if enemy != null:
		_aim = (enemy.global_position - global_position).normalized()
		if enemy is Enemy and Skills.is_unlocked(&"clone_3") and _switch_cooldown <= 0.0:
			color_index = posmod(enemy.color_index - 1, ColorType.COUNT)
			_switch_cooldown = 1.0
		if _shot_cooldown <= 0.0 and player.projectile_manager != null:
			if not melee or global_position.distance_squared_to(enemy.global_position) <= pow(145.0 + enemy.radius, 2.0):
				player.projectile_manager.combat.fire_weapon(global_position + _aim * 18.0, _aim,
					player.weapon.stats, color_index, false, player.weapon, true,
					player.stats.get_value(&"summon_damage"))
				_shot_cooldown = 1.0 / maxf(0.1, player.weapon.get_final_fire_rate())
	queue_redraw()


func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var distance := 580.0 * 580.0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead:
			continue
		var value := global_position.distance_squared_to(enemy.global_position)
		if value < distance:
			distance = value
			best = enemy
	if player.weapon.primary_form not in [&"sword", &"scythe", &"wave", &"lightning"]:
		for hole in get_tree().get_nodes_in_group(&"friendly_aim_targets"):
			var value := global_position.distance_squared_to(hole.global_position)
			if hole.can_be_targeted() and value < distance:
				distance = value
				best = hole
	return best


func _expire() -> void:
	if is_queued_for_deletion():
		return
	if Skills.is_unlocked(&"clone_4") and player != null and is_instance_valid(player):
		var stats := player.weapon.stats
		var base := stats.get_value(&"damage") * stats.get_value(&"damage_mult") * stats.get_value(&"damage_final")
		var amount := base * 3.0 * player.stats.get_value(&"summon_damage")
		for node in get_tree().get_nodes_in_group(&"enemies"):
			if not (node is Enemy):
				continue
			var enemy := node as Enemy
			if enemy.is_dead or global_position.distance_squared_to(enemy.global_position) > pow(145.0 + enemy.radius, 2.0):
				continue
			var context := Skills.build_hit_context(self, enemy, amount, color_index, false, true)
			context.add_tag(&"clone")
			enemy.take_damage(context)
		FX.shockwave(global_position, Color(0.9, 1.2, 1.8, 0.9), 145.0, 0.26, EnergyBurst.STYLE_SPLASH)
	queue_free()


func _draw() -> void:
	# 与玩家同为圆形机体和前向炮口，但更小、更朴素，无外层光晕。
	var source := RunState.color_of(color_index) if color_index >= 0 else Color(0.82, 0.88, 0.95)
	var c := Color(minf(source.r, 1.0), minf(source.g, 1.0), minf(source.b, 1.0), 0.88)
	var dir := _aim.normalized() if _aim.length_squared() > 0.01 else Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x)
	draw_circle(Vector2.ZERO, 10.5, Color(c.r * 0.10, c.g * 0.10, c.b * 0.10, 0.88))
	draw_arc(Vector2.ZERO, 10.5, 0.0, TAU, 24, c, 1.8, true)
	draw_circle(Vector2.ZERO, 2.2, Color(c.r, c.g, c.b, 0.42))
	var barrel := dir * 16.5
	draw_line(dir * 5.0, barrel, Color(c.r, c.g, c.b, 0.52), 1.3, true)
	draw_line(dir * 7.5 + side * 5.0, barrel, c, 1.6, true)
	draw_line(dir * 7.5 - side * 5.0, barrel, c, 1.6, true)

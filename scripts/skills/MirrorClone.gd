class_name MirrorClone
extends Node2D

## 分身使用玩家当前基础战斗属性，每次只发一颗弹；特殊技能与超暴击不继承。
var player: Player
var health := 2.0
var lifetime := 20.0
var color_index := -1
var _colored_health_added := false
var _switch_cooldown := 0.0
var _shot_cooldown := 0.45
var _contact_cooldown := 0.0
var _aim := Vector2.RIGHT
var _age := 0.0
var _target_scan_timer := 0.0
var _cached_target: Enemy


func setup(owner_player: Player, position_value: Vector2) -> void:
	player = owner_player
	global_position = position_value
	if Skills.is_unlocked(&"clone_3"):
		health = 3.0
		_colored_health_added = true


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
	if Skills.is_unlocked(&"clone_3") and not _colored_health_added:
		_colored_health_added = true
		health += 1.0
	_switch_cooldown = maxf(0.0, _switch_cooldown - delta)
	_shot_cooldown -= delta
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	_target_scan_timer -= delta
	if _target_scan_timer <= 0.0 or not is_instance_valid(_cached_target) or _cached_target.is_dead:
		_cached_target = _nearest_enemy()
		_target_scan_timer = 0.10
	var enemy := _cached_target
	var desired := player.global_position + Vector2.from_angle(_age * 0.75) * 145.0
	if enemy != null and global_position.distance_squared_to(enemy.global_position) < 400.0 * 400.0:
		desired = enemy.global_position + (global_position - enemy.global_position).normalized() * 135.0
	if global_position.distance_squared_to(player.global_position) > 450.0 * 450.0:
		desired = player.global_position
	global_position = global_position.move_toward(desired, 135.0 * delta)
	if enemy != null:
		_aim = (enemy.global_position - global_position).normalized()
		if Skills.is_unlocked(&"clone_3") and _switch_cooldown <= 0.0:
			color_index = posmod(enemy.color_index - 1, ColorType.COUNT)
			_switch_cooldown = 1.0
		if _shot_cooldown <= 0.0 and player.projectile_manager != null:
			player.projectile_manager.fire(global_position + _aim * 18.0, _aim,
				player.weapon.stats, color_index, player.weapon.core, false,
				player.stats.get_value(&"summon_damage"), 0.8, 1.0, 1.0, true, &"clone")
			_shot_cooldown = 1.0 / maxf(0.1, player.weapon.get_final_fire_rate())
		if _contact_cooldown <= 0.0 and global_position.distance_squared_to(enemy.global_position) < pow(enemy.radius + 12.0, 2.0):
			take_damage(enemy.type_data.contact_damage * Director.enemy_damage_multiplier(), enemy)
			_contact_cooldown = 0.8
	queue_redraw()


func _nearest_enemy() -> Enemy:
	var best: Enemy = null
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
	return best


func take_damage(amount: float, _source: Node = null) -> void:
	if health <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		_expire()


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
			if enemy.is_dead or global_position.distance_squared_to(enemy.global_position) > pow(100.0 + enemy.radius, 2.0):
				continue
			var context := Skills.build_hit_context(self, enemy, amount, color_index, false, true)
			context.add_tag(&"clone")
			enemy.take_damage(context)
		FX.shockwave(global_position, Color(0.9, 1.2, 1.8, 0.9), 100.0, 0.26, EnergyBurst.STYLE_SPLASH)
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
	draw_arc(Vector2(0.0, -14.0), 7.0, PI, PI + TAU * clampf(health / 3.0, 0.0, 1.0), 12,
		Color(c.r, c.g, c.b, 0.56), 1.2)

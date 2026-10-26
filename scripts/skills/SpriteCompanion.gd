class_name SpriteCompanion
extends Node2D

## 锁定目标方向后穿过目标继续冲刺；同一敌人一趟只受一次伤，随后回到玩家近旁。
const DASH_SPEED := 900.0
const DASH_MIN_DISTANCE := 440.0
const DASH_OVERSHOOT := 180.0
const RETURN_SPEED := 380.0
const TIER_FOUR_DASH_SPEED := 1250.0
const TIER_FOUR_DASH_MIN_DISTANCE := 520.0
const TIER_FOUR_DASH_OVERSHOOT := 260.0
const TIER_FOUR_RETURN_SPEED := 650.0
const ORBIT_RADIUS := 26.0

var player: Player
var slot := 0
var color_index := ColorType.RED
var base_bonus := 0.0
var _time := 0.0
var _dash_cooldown := 0.6
var _dashing := false
var _returning := false
var _dash_end := Vector2.ZERO
var _hit_ids: Dictionary = {}
var _trail: Line2D
var _trail_points: Array[Vector2] = []
var _trail_idle: Gradient
var _trail_return: Gradient
var _trail_dash: Gradient
var _trail_mode := -1


func setup(owner_player: Player, index: int, color_value: int) -> void:
	player = owner_player
	slot = index
	color_index = color_value
	global_position = player.global_position + Vector2.from_angle(float(index) * TAU / 3.0) * 42.0
	if _trail != null:
		_configure_trail()


func _ready() -> void:
	z_index = 5
	_trail = Line2D.new()
	_trail.default_color = Color.WHITE
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(0.55, 0.58))
	taper.add_point(Vector2(1.0, 0.02))
	_trail.width_curve = taper
	add_child(_trail)
	_configure_trail()


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or RunState.is_dead:
		queue_free()
		return
	_time += delta
	_dash_cooldown -= delta
	var previous := global_position
	if _dashing:
		global_position = global_position.move_toward(_dash_end, _dash_speed() * delta)
		_hit_along(previous, global_position)
		if global_position.distance_squared_to(_dash_end) < 4.0:
			_dashing = false
			_returning = true
	else:
		var angle := _time * 1.3 + float(slot) * TAU / 3.0
		var orbit := player.global_position + Vector2.from_angle(angle) * (ORBIT_RADIUS + sin(_time * 2.4 + slot) * 4.0)
		global_position = global_position.move_toward(orbit, (_return_speed() if _returning else 170.0) * delta)
		if _returning and global_position.distance_squared_to(orbit) < 12.0 * 12.0:
			_returning = false
		if not _returning and _dash_cooldown <= 0.0:
			var enemy := _choose_target()
			if enemy != null:
				_begin_dash(enemy)
			else:
				_dash_cooldown = 0.35
	_update_trail()
	queue_redraw()


func _begin_dash(enemy: Enemy) -> void:
	var to_target := enemy.global_position - global_position
	if to_target.length_squared() < 1.0:
		_dash_cooldown = 0.2
		return
	# 锁定出发时的方向与终点。命中或目标死亡都不改变本次冲刺。
	var upgraded := Skills.is_unlocked(&"sprite_4")
	var minimum := TIER_FOUR_DASH_MIN_DISTANCE if upgraded else DASH_MIN_DISTANCE
	var overshoot := TIER_FOUR_DASH_OVERSHOOT if upgraded else DASH_OVERSHOOT
	_dash_end = global_position + to_target.normalized() * maxf(minimum, to_target.length() + overshoot)
	_dashing = true
	_returning = false
	_dash_cooldown = 1.3 if upgraded else 2.0
	_hit_ids.clear()


func _dash_speed() -> float:
	return TIER_FOUR_DASH_SPEED if Skills.is_unlocked(&"sprite_4") else DASH_SPEED


func _return_speed() -> float:
	return TIER_FOUR_RETURN_SPEED if Skills.is_unlocked(&"sprite_4") else RETURN_SPEED


func _choose_target() -> Enemy:
	var best: Enemy = null
	var best_priority := 3
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead:
			continue
		var is_boss := enemy.type_data != null and enemy.type_data.is_boss
		var distance := global_position.distance_squared_to(enemy.global_position)
		var range_limit := 700.0 if is_boss else 530.0
		if distance > range_limit * range_limit:
			continue
		var priority := 0 if is_boss else (1 if RunState.color_relation(color_index, enemy.color_index) == &"advantage" else 2)
		if priority < best_priority or (priority == best_priority and distance < best_distance):
			best_priority = priority
			best_distance = distance
			best = enemy
	return best


func _hit_along(start: Vector2, finish: Vector2) -> void:
	var wide := Skills.is_unlocked(&"sprite_3")
	var radius := 19.0 if wide else 12.0
	var segment := finish - start
	var length_sq := segment.length_squared()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead or _hit_ids.has(enemy.get_instance_id()):
			continue
		var progress := clampf((enemy.global_position - start).dot(segment) / maxf(1.0, length_sq), 0.0, 1.0)
		var closest := start + segment * progress
		if closest.distance_squared_to(enemy.global_position) > pow(radius + enemy.radius, 2.0):
			continue
		_hit_ids[enemy.get_instance_id()] = true
		var stats := player.weapon.stats
		var base := (stats.get_value(&"damage") + base_bonus) * stats.get_value(&"damage_mult") * stats.get_value(&"damage_final")
		var amount := base * (4.0 if wide else 3.0) * player.stats.get_value(&"summon_damage") * Skills.elemental_multiplier()
		var context := Skills.build_hit_context(self, enemy, amount, color_index, false, false)
		context.add_tag(&"sprite")
		context.add_tag(&"elemental")
		enemy.take_damage(context)
		if not enemy.is_dead and (enemy.type_data == null or not enemy.type_data.is_boss):
			var dash_direction := segment.normalized() if length_sq > 0.001 else Vector2.RIGHT
			enemy.apply_knockback(closest - dash_direction * 24.0, 190.0, 0.16)
		if not enemy.is_dead and context.has_tag(&"weakness"):
			Skills.on_weakness_hit(enemy, base, color_index)
		if Skills.is_unlocked(&"sprite_4"):
			base_bonus += 0.5


func _update_trail() -> void:
	var mode := 2 if _dashing else (1 if _returning else 0)
	var wide := Skills.is_unlocked(&"sprite_3")
	var trail_mode := mode + (3 if wide else 0)
	if trail_mode != _trail_mode:
		_trail_mode = trail_mode
		match mode:
			2:
				_trail.gradient = _trail_dash
				_trail.width = 14.0 if wide else 10.0
			1:
				_trail.gradient = _trail_return
				_trail.width = 5.5 if wide else 4.0
			_:
				_trail.gradient = _trail_idle
				_trail.width = 3.2 if wide else 2.5
	_trail_points.push_front(global_position)
	var max_points := 12 if mode == 2 else (6 if mode == 1 else 4)
	while _trail_points.size() > max_points:
		_trail_points.pop_back()
	var points := PackedVector2Array()
	for point in _trail_points:
		points.append(to_local(point))
	_trail.points = points


func _configure_trail() -> void:
	var color := RunState.color_of(color_index)
	_trail_idle = _trail_gradient(color, 0.23)
	_trail_return = _trail_gradient(color, 0.42)
	_trail_dash = _trail_gradient(color, 0.98)
	_trail_mode = -1


func _trail_gradient(color: Color, opacity: float) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, opacity))
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.45, Color(color.r, color.g, color.b, opacity * 0.38))
	return gradient


func _draw() -> void:
	var color := RunState.color_of(color_index)
	var radius := 8.0 if Skills.is_unlocked(&"sprite_3") else 6.0
	var pulse := 1.0 + 0.10 * sin(_time * 7.0 + float(slot))
	draw_circle(Vector2.ZERO, radius * 2.0 * pulse, Color(color.r, color.g, color.b, 0.15 if _dashing else 0.10))
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.93))
	draw_circle(Vector2(-1.5, -1.5), radius * 0.35, Color(2.5, 2.5, 2.5, 0.9))
	if _dashing:
		var heading := (_dash_end - global_position).normalized()
		var side := Vector2(-heading.y, heading.x)
		for i in 2:
			var offset := -heading * (radius + 7.0 + float(i) * 8.0)
			var alpha := 0.68 - float(i) * 0.24
			draw_line(offset + side * (3.5 + float(i)), offset - heading * (6.0 + float(i) * 2.0),
				Color(color.r, color.g, color.b, alpha), 1.6, true)
			draw_line(offset - side * (3.5 + float(i)), offset - heading * (6.0 + float(i) * 2.0),
				Color(color.r, color.g, color.b, alpha), 1.6, true)

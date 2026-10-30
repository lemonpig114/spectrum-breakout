class_name HexBoss
extends Enemy

const MORPH_DURATION := 0.75
const DASH_COOLDOWN := 15.0
const DASH_WINDUP := 1.4
const DASH_DURATION := 2.2
var edge_max_health := 25000.0
var edge_health := PackedFloat64Array()
var edge_colors := PackedInt32Array()
var _fragment_color := 0
var _vertices := PackedVector2Array()
var _morph_from := PackedVector2Array()
var _morph_to := PackedVector2Array()
var _morph_time := MORPH_DURATION
var _join_edge := -1
var _spin := 0.0
var _dash_cd := DASH_COOLDOWN
var _dash_left := 0.0
var _windup := 0.0
var _dash_direction := Vector2.RIGHT
var _fragment_a := Vector2.ZERO
var _fragment_b := Vector2.ZERO
var _fragment_age := 1.0
var _last_edge := 0
var _resist_time := 0.0
var _edge_flash := PackedFloat32Array()
var _edge_bars: Array[BossHealthBar] = []
var _crush_frame := 0


func _ready() -> void:
	super._ready()
	add_to_group(&"bosses")
	z_index = 6
	_healthbar.hide()
	edge_max_health = max_health / 6.0
	for i in 6:
		edge_health.append(edge_max_health)
		edge_colors.append(ColorType.next(color_index, i))
		_vertices.append(Vector2.from_angle(TAU * i / 6.0) * radius)
		_edge_flash.append(0.0)
	_sync_bars()
	rotation = 0.0
	_request_redraw()


func _squash() -> void:
	pass


func move_speed_for_edges() -> float:
	var lost := 6 - edge_health.size()
	return type_data.move_speed + lost * 24.0 + lost * lost * 3.5


func spin_speed_for_edges() -> float:
	var lost := 6 - edge_health.size()
	return 0.25 + lost * 0.18 + lost * lost * 0.12


func _physics_process(delta: float) -> void:
	if is_dead or RunState.is_dead or not is_instance_valid(target):
		return
	_resist_time = maxf(0.0, _resist_time - delta)
	_fragment_age += delta
	_flash = maxf(0.0, _flash - delta * 5.0)
	_tick_statuses(delta)
	for i in _edge_flash.size():
		_edge_flash[i] = maxf(0.0, _edge_flash[i] - delta * 4.0)
	_update_morph(delta)
	_sync_bars()
	for bar in _edge_bars:
		bar.step(delta)
	if step_unresisted_knockback(delta):
		_request_redraw()
		return
	_dash_cd = maxf(0.0, _dash_cd - delta)
	var spinning := spin_speed_for_edges()
	if _windup > 0.0:
		_windup = maxf(0.0, _windup - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 280.0 * delta)
		spinning *= 1.0 + (1.0 - _windup / DASH_WINDUP) * 2.0
		if _windup <= 0.0:
			_dash_left = DASH_DURATION
			_dash_cd = DASH_COOLDOWN
			velocity = _dash_direction * (move_speed_for_edges() * 3.0 + 220.0) * 0.8
	elif _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
		var desired := _dash_direction * (move_speed_for_edges() * 3.0 + 220.0)
		velocity = velocity.lerp(desired, 1.0 - exp(-0.7 * delta))
		spinning *= 4.0
	else:
		var offset := target.global_position - global_position
		var desired := offset.normalized() * move_speed_for_edges() * (1.0 - _slow)
		if offset.length() < radius + Player.RADIUS + 10.0:
			desired = Vector2.ZERO
		velocity = velocity.lerp(desired, 1.0 - exp(-2.2 * delta))
		if _dash_cd <= 0.0:
			_windup = DASH_WINDUP
			_dash_direction = offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	_spin += spinning * delta
	rotation = _spin
	var previous := global_position
	global_position += velocity * delta
	if _dash_left > 0.0:
		_crush_frame = (_crush_frame + 1) % 3
		if _crush_frame == 0:
			_crush_enemies(previous - velocity * delta * 2.0, global_position)
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	if _contact_cooldown <= 0.0 and global_position.distance_to(target.global_position) <= radius + Player.RADIUS:
		_contact_cooldown = 0.9
		target.take_damage(type_data.contact_damage * Director.enemy_damage_multiplier(), self)
	_request_redraw()


func _crush_enemies(from: Vector2, to: Vector2) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy == self or enemy.is_dead or (enemy.type_data != null and enemy.type_data.is_boss):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position, from, to)
		if closest.distance_squared_to(enemy.global_position) <= (radius * 0.86 + enemy.radius) ** 2:
			enemy.force_kill()


func _update_morph(delta: float) -> void:
	if _morph_time >= MORPH_DURATION or _morph_from.size() != _vertices.size():
		return
	_morph_time = minf(MORPH_DURATION, _morph_time + delta)
	var t := smoothstep(0.0, 1.0, _morph_time / MORPH_DURATION)
	for i in _vertices.size():
		_vertices[i] = _morph_from[i].lerp(_morph_to[i], t)


func _sync_bars() -> void:
	while _edge_bars.size() > edge_health.size():
		_edge_bars.pop_back()
	while _edge_bars.size() < edge_health.size():
		_edge_bars.append(BossHealthBar.new())
	for i in edge_health.size():
		_edge_bars[i].set_health(edge_health[i], edge_max_health)


func _refresh_healthbar() -> void:
	super._refresh_healthbar()
	_sync_bars()


func edge_at(point: Vector2) -> int:
	var local := to_local(point)
	var best := INF
	var result := 0
	for i in _vertices.size():
		var distance := Geometry2D.get_closest_point_to_segment(local, _vertices[i], _vertices[(i + 1) % _vertices.size()]).distance_squared_to(local)
		if distance < best:
			best = distance
			result = i
	return result


func damage_color_at(point: Vector2) -> int:
	return edge_colors[edge_at(point)] if not edge_colors.is_empty() else color_index


func _take_damage_impl(context: DamageContext) -> void:
	if is_dead:
		return
	var neutral := context.color_index < 0
	var point := context.hit_position
	if point.is_equal_approx(global_position) and context.source is Node2D:
		point = (context.source as Node2D).global_position
	if point.is_equal_approx(global_position) and is_instance_valid(target):
		point = target.global_position
	var index := edge_at(point)
	if not neutral and not context.has_tag(&"super_crit") and not ColorType.beats(context.color_index, edge_colors[index]):
		_resist()
		return
	_apply_vulnerability_for_attack()
	var amount := maxf(0.0, context.amount) * (0.05 if neutral else 1.0) * (1.0 + vulnerability)
	var dealt := minf(edge_health[index], amount)
	Skills.record_projectile_damage(context, dealt)
	var style := FloatingTextLayer.STYLE_NORMAL
	if context.has_tag(&"blackhole_explosion"):
		style = FloatingTextLayer.STYLE_BURST
	elif context.has_tag(&"super_crit"):
		style = FloatingTextLayer.STYLE_SUPER_CRIT
	elif context.is_crit:
		style = FloatingTextLayer.STYLE_CRIT
	elif context.has_tag(&"weakness") or context.relation == &"advantage":
		style = FloatingTextLayer.STYLE_WEAKNESS
	var tint := Color(0.88, 0.88, 0.88) if neutral else RunState.color_of(context.color_index)
	FX.damage_number(to_global((_vertices[index] + _vertices[(index + 1) % _vertices.size()]) * 0.5), amount, tint, false, style, _damage_caption(context))
	_damage_edge(index, amount)


func take_true_damage(amount: float, source_key: StringName = &"skill:soul_1") -> void:
	if is_dead:
		return
	var index := edge_at(target.global_position if is_instance_valid(target) else global_position)
	var applied := maxf(0.0, amount) * 0.05 * (1.0 + vulnerability)
	Skills.record_damage(source_key, minf(edge_health[index], applied))
	FX.damage_number(global_position + Vector2(0, -radius), applied, Color(2.4, 2.0, 3.0), false, FloatingTextLayer.STYLE_SOUL)
	_damage_edge(index, applied)


func _apply_dot_tick() -> void:
	var burn := _burn_ticks[_burn_cursor]
	_burn_ticks[_burn_cursor] = 0.0
	_burn_cursor = (_burn_cursor + 1) % 4
	_burn_pending = maxf(0.0, _burn_pending - burn)
	var poison := _poison_dps * 0.5
	var index := clampi(_last_edge, 0, edge_health.size() - 1)
	var total := (burn + poison) * (1.0 + vulnerability)
	if total > 0.0:
		var actual := minf(edge_health[index], total)
		Skills.record_damage(&"skill:weak_3_burn", actual * burn / (burn + poison))
		Skills.record_damage(&"skill:weak_3_poison", actual * poison / (burn + poison))
		if burn > 0:
			_show_elemental_tick(burn, Color(2.6, 0.85, 0.28), FloatingTextLayer.STYLE_BURN, &"burn")
		if poison > 0:
			_show_elemental_tick(poison, Color(0.45, 2.2, 0.65), FloatingTextLayer.STYLE_POISON, &"poison")
		_damage_edge(index, total)
	_refresh_status_icons()


func _damage_edge(index: int, amount: float) -> void:
	_last_edge = index
	edge_health[index] = maxf(0.0, edge_health[index] - amount)
	_edge_flash[index] = 1.0
	_flash = 1.0
	if edge_health[index] <= 0.0:
		_break_edge(index)
	else:
		_refresh_total()
	_sync_bars()
	_request_redraw()


func _refresh_total() -> void:
	max_health = edge_max_health * edge_health.size()
	health = 0.0
	for value in edge_health:
		health += value


func _break_edge(index: int) -> void:
	_fragment_a = _vertices[index]
	_fragment_b = _vertices[(index + 1) % _vertices.size()]
	_fragment_age = 0.0
	_fragment_color = edge_colors[index]
	edge_health.remove_at(index)
	edge_colors.remove_at(index)
	_edge_flash.remove_at(index)
	if index < _edge_bars.size():
		_edge_bars.remove_at(index)
	for i in edge_health.size():
		edge_health[i] = edge_max_health
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Enemy:
			node.rally_hex(5.0)
	FX.shards(to_global((_fragment_a + _fragment_b) * 0.5), RunState.color_of(_fragment_color), 14)
	FX.shake(0.5)
	if edge_health.size() <= 2:
		health = 0.0
		_die()
		return
	var removed_vertex := (index + 1) % _vertices.size()
	_vertices.remove_at(removed_vertex)
	if removed_vertex == 0:
		# Keep surviving edge health/colors aligned when the closing edge breaks.
		var last := _vertices[_vertices.size() - 1]
		_vertices.remove_at(_vertices.size() - 1)
		_vertices.insert(0, last)
	_morph_from = _vertices.duplicate()
	_morph_to.clear()
	var start := _vertices[0].angle()
	for i in _vertices.size():
		_morph_to.append(Vector2.from_angle(start + TAU * i / _vertices.size()) * radius)
	_join_edge = 0 if removed_vertex == 0 else mini(index, _vertices.size() - 1)
	_morph_time = 0.0
	_refresh_total()


func _resist() -> void:
	if _resist_time <= 0.0:
		FX.text_popup(global_position + Vector2(0, -radius - 12), "抵抗", Color(0.6, 0.68, 0.8), 17)
		_resist_time = 0.35


func force_kill() -> void:
	_resist()


func execute() -> void:
	_resist()


func can_be_executed() -> bool:
	return false


func _draw() -> void:
	if is_dead or _vertices.size() < 3:
		return
	var c := RunState.enemy_color_of(color_index)
	draw_colored_polygon(_vertices, Color(c.r * 0.035, c.g * 0.035, c.b * 0.035, 0.95))
	for i in _vertices.size():
		c = RunState.enemy_color_of(edge_colors[i])
		var a := _vertices[i]
		var b := _vertices[(i + 1) % _vertices.size()]
		var mid := (a + b) * 0.5
		var normal := mid.normalized()
		var flash := _edge_flash[i]
		var reconnect := smoothstep(0.0, 0.8, _morph_time / MORPH_DURATION) if i == _join_edge else 1.0
		var end := a.lerp(b, reconnect)
		draw_line(a, end, Color(c.r, c.g, c.b, 0.15), 11.0, true)
		draw_line(a, end, c.lerp(Color(3, 3, 3), flash * 0.6), 3.0, true)
		draw_colored_polygon(PackedVector2Array([a * 0.83, b * 0.83, b * 0.7, a * 0.7]), Color(c.r * 0.2, c.g * 0.2, c.b * 0.2, 0.85))
		draw_line(a * 0.83, b * 0.83, Color(c.r, c.g, c.b, 0.45), 1.2, true)
		draw_line(a * 0.64, a * 0.3, Color(c.r, c.g, c.b, 0.3), 1.0, true)
		draw_circle(a, 3.5, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5))
		if i < _edge_bars.size():
			var bar_at := mid + normal * 27.0
			draw_set_transform(bar_at, -rotation, Vector2.ONE)
			_edge_bars[i].paint(self, Vector2(-32, 0), c, 64, 6, "%d · %d%%" % [i + 1, int(100 * edge_health[i] / edge_max_health)])
			draw_set_transform(Vector2.ZERO)
	c = Color(0.55, 0.7, 0.9)
	var core := PackedVector2Array()
	for i in _vertices.size():
		core.append(Vector2.from_angle(TAU * i / _vertices.size() - _spin * 0.4) * 23.0)
	draw_colored_polygon(core, Color(0.01, 0.02, 0.04))
	var outline := core.duplicate()
	outline.append(core[0])
	draw_polyline(outline, c, 2.0, true)
	draw_circle(Vector2.ZERO, 4.0, c)
	if _fragment_age < 0.65:
		c = RunState.enemy_color_of(_fragment_color)
		var outward := ((_fragment_a + _fragment_b) * 0.5).normalized()
		var travel := outward * _fragment_age * 115.0
		var middle := (_fragment_a + _fragment_b) * 0.5
		draw_line(_fragment_a + travel, middle + travel * 1.25, Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 1.0 - _fragment_age / 0.65), 4.0, true)
		draw_line(middle + travel * 1.25, _fragment_b + travel, Color(c.r, c.g, c.b, 1.0 - _fragment_age / 0.65), 3.0, true)
	draw_set_transform(Vector2.ZERO, -rotation)
	c = Color(0.55, 0.7, 0.9)
	if _windup > 0.0:
		var charge := 1.0 - _windup / DASH_WINDUP
		var side := _dash_direction.orthogonal()
		for offset in [-1.0, 1.0]:
			draw_line(side * radius * offset, side * radius * offset + _dash_direction * (400.0 + charge * 320.0), Color(c.r, c.g, c.b, 0.25 + charge * 0.4), 2.0, true)
		for i in 5:
			var point := _dash_direction * (radius + 40.0 + i * 70.0)
			draw_polyline(PackedVector2Array([point - _dash_direction * 15 + side * 12, point, point - _dash_direction * 15 - side * 12]), Color(c.r, c.g, c.b, 0.35 + charge * 0.4), 2.0, true)

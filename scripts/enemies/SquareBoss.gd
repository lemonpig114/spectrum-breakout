class_name SquareBoss
extends Enemy

## 180 秒的方形 Boss。脚本招式固定为增强→召唤→晋升→召唤；
## 锤击/冲刺只在招式间隙按距离插入，绝不打断蓄力中的晋升。
const SQUARE_SCENE := preload("res://scenes/enemies/enemy.tscn")
const SCRIPT_ACTIONS: Array[StringName] = [&"enhance", &"summon", &"promote", &"summon"]
const ENHANCE_RADIUS := 540.0
const SUMMON_COUNT := 12
const SUMMON_RADIUS := 210.0
const HAMMER_RANGE := 210.0
const HAMMER_RADIUS := 155.0
const DASH_RANGE := 300.0
const DASH_WAVE_RADIUS := 175.0
const WAVE_PUSH_RADIUS := 240.0
const HAMMER_COOLDOWN := 10.0
const DASH_COOLDOWN := 20.0
## 前摇由本体动画和精确落点标记承载；不画遮住战场的大范围提示框。
const ENHANCE_WINDUP := 0.8
const SUMMON_WINDUP := 0.95
const PROMOTE_WINDUP := 1.15
const HAMMER_WINDUP := 0.95
const DASH_WINDUP := 0.78
const SCRIPT_INTERVAL := 3.2

var _script_index := 0
var _script_timer := 0.55
var _hammer_cooldown := 0.0
var _dash_cooldown := 2.5
var _action: StringName = &""
var _windup := 0.0
var _windup_total := 1.0
var _dash_origin := Vector2.ZERO
var _dash_target := Vector2.ZERO
var _dash_elapsed := 0.0
var _dash_duration := 0.0
var _hammer_point := Vector2.ZERO
var _promote_color := ColorType.RED
var _summon_points := PackedVector2Array()
var _plate_angle := 0.0
var _hammer_fx_center := Vector2.ZERO
var _hammer_fx_time := 0.0


func boss_armor_multiplier() -> float:
	return 0.5 if _action == &"summon" else 0.85


func _ready() -> void:
	super._ready()
	add_to_group(&"bosses")
	z_index = 6
	# Boss 改用 _draw 里的常驻大血条：原来的小血条只在受伤后出现，太细且会被
	# 受击挤压一起拉变形，所以直接隐藏。
	_healthbar.visible = false
	rotation = 0.0


## Boss 不做受击挤压。它的攻击预警直接画在同一个 CanvasItem 上，
## 一旦缩放，预警框也会跟着“弹”，看起来像判定范围在抖。
func _squash() -> void:
	pass


func _physics_process(delta: float) -> void:
	if is_dead or RunState.is_dead or target == null or not is_instance_valid(target):
		return
	# 蓄力时角甲加速旋转，蓄满后接近一秒一转，读起来像“上膛”。
	_plate_angle += delta * (0.34 + _charge_amount() * 2.8)
	_hammer_fx_time = maxf(0.0, _hammer_fx_time - delta)
	_flash = maxf(0.0, _flash - delta * 6.0)
	modulate = Color(1.0 + _flash, 1.0 + _flash, 1.0 + _flash)
	# Boss 不做受击挤压（见 _squash），因此也不需要推进挤压恢复。
	_tick_statuses(delta)
	if is_dead:
		return
	_hammer_cooldown = maxf(0.0, _hammer_cooldown - delta)
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	if _action == &"dash_move":
		_step_dash(delta)
	elif _action != &"":
		_windup -= delta
		if _windup <= 0.0:
			_resolve_action()
	else:
		_script_timer -= delta
		var distance := global_position.distance_to(target.global_position)
		if _script_timer <= 0.0:
			_begin_action(SCRIPT_ACTIONS[_script_index])
			_script_index = (_script_index + 1) % SCRIPT_ACTIONS.size()
		elif not (_next_script_action() == &"promote" and _script_timer < 2.0):
			if distance <= HAMMER_RANGE and _hammer_cooldown <= 0.0:
				_begin_action(&"hammer")
			elif distance >= DASH_RANGE and _dash_cooldown <= 0.0:
				_begin_action(&"dash")
		if _action == &"":
			_step_chase(delta)
	queue_redraw()


func _next_script_action() -> StringName:
	return SCRIPT_ACTIONS[_script_index]


func _step_chase(delta: float) -> void:
	var toward := target.global_position - global_position
	var distance := toward.length()
	if distance > radius + Player.RADIUS + 18.0:
		var slow_factor := 1.0 - _slow
		global_position += toward / distance * type_data.move_speed * slow_factor * delta
		_clamp_to_arena()
	if distance <= radius + Player.RADIUS + 2.0 and _contact_cooldown <= 0.0:
		_contact_cooldown = 0.8
		target.take_damage(type_data.contact_damage * Director.enemy_damage_multiplier(), self)
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)


func _begin_action(kind: StringName) -> void:
	_action = kind
	match kind:
		&"enhance":
			_windup_total = ENHANCE_WINDUP
		&"summon":
			_windup_total = SUMMON_WINDUP
			_summon_points = _build_summon_points()
		&"promote":
			_windup_total = PROMOTE_WINDUP
			_promote_color = ColorType.next(color_index, 1)
		&"hammer":
			_windup_total = HAMMER_WINDUP
			_hammer_cooldown = HAMMER_COOLDOWN
			var aim := target.global_position - global_position
			_hammer_point = global_position + (aim.normalized() if aim.length_squared() > 0.001 else Vector2.RIGHT) * 135.0
		&"dash":
			_windup_total = DASH_WINDUP
			_dash_cooldown = DASH_COOLDOWN
			_dash_origin = global_position
			# 蓄力时锁定玩家位置，并越过该点一小段距离。
			var aim := target.global_position - global_position
			_dash_target = target.global_position + (aim.normalized() if aim.length_squared() > 0.001 else Vector2.RIGHT) * 120.0
	_windup = _windup_total
	queue_redraw()


func _resolve_action() -> void:
	var finished := _action
	_action = &""
	match finished:
		&"enhance":
			_enhance_squares(ENHANCE_RADIUS)
		&"summon":
			_summon_squares()
		&"promote":
			color_index = _promote_color
			_refresh_healthbar()
			_enhance_squares(INF)
			FX.glow_pulse(0.32, 0.55)
		&"hammer":
			_wave_impact(_hammer_point, HAMMER_RADIUS, true)
		&"dash":
			_action = &"dash_move"
			_dash_elapsed = 0.0
			_dash_duration = maxf(0.18, _dash_origin.distance_to(_dash_target) / 850.0)
	if finished in [&"enhance", &"summon", &"promote"]:
		_script_timer = SCRIPT_INTERVAL
	queue_redraw()


func _step_dash(delta: float) -> void:
	_dash_elapsed += delta
	var progress := minf(1.0, _dash_elapsed / _dash_duration)
	global_position = _dash_origin.lerp(_dash_target, progress)
	_clamp_to_arena()
	if progress >= 1.0:
		_action = &""
		_wave_impact(global_position, DASH_WAVE_RADIUS)


func _clamp_to_arena() -> void:
	# Boss 与普通敌人一样可以穿过玩家的软墙。
	pass


func _build_summon_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var bounds := RunState.arena_rect.grow(-28.0)
	for i in SUMMON_COUNT:
		var angle := TAU * float(i) / float(SUMMON_COUNT) + _plate_angle
		var point := global_position + Vector2.from_angle(angle) * SUMMON_RADIUS
		point.x = clampf(point.x, bounds.position.x, bounds.end.x)
		point.y = clampf(point.y, bounds.position.y, bounds.end.y)
		points.append(point)
	return points


func _summon_squares() -> void:
	var kind := ContentDB.get_enemy(&"chaser_square")
	if kind == null or get_parent() == null:
		return
	for point in _summon_points:
		var square := SQUARE_SCENE.instantiate() as Enemy
		square.configure(kind, target, color_index)
		square.max_health *= Director.health_multiplier()
		square.health = square.max_health
		get_parent().add_child(square)
		square.global_position = point
		square.empower(color_index)
		# 召唤不检查普通刷怪上限，可把场上总数推到 70 以上；
		# 它们在 enemies 组里仍会占用后续普通补怪配额，因此限制同时存在 24 只。
		square.add_to_group(&"boss_summons")
	_trim_old_summons()
	_summon_points.clear()


func _trim_old_summons() -> void:
	var summons := get_tree().get_nodes_in_group(&"boss_summons")
	while summons.size() > 24:
		var oldest: Enemy = summons.pop_front()
		if is_instance_valid(oldest):
			oldest.remove_from_group(&"enemies")
			oldest.remove_from_group(&"boss_summons")
			oldest.queue_free()


func _enhance_squares(effective_radius: float) -> void:
	var radius_squared := effective_radius * effective_radius
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy == self or enemy.is_dead:
			continue
		if effective_radius != INF and enemy.global_position.distance_squared_to(global_position) > radius_squared:
			continue
		enemy.empower(color_index)


func _wave_impact(center: Vector2, hit_radius: float, is_hammer: bool = false) -> void:
	var tint := RunState.color_of(color_index)
	# 判定与看到的冲击波一致：圆形范围，不再用方形包围盒。
	var hit_distance := hit_radius + ((target as Player).body_radius if target is Player else Player.RADIUS)
	var player_offset := target.global_position - center
	if player_offset.length_squared() <= hit_distance * hit_distance:
		target.take_damage(type_data.contact_damage * Director.enemy_damage_multiplier(), self)
	# 锤击叠加白核、地面裂痕和更强镜头冲量；冲刺保留较轻的双层波。
	FX.shockwave(center, tint, hit_radius * (1.42 if is_hammer else 1.22), 0.42, EnergyBurst.STYLE_HEAVY)
	FX.shockwave(center, tint, hit_radius * 0.58, 0.26, EnergyBurst.STYLE_HEAVY)
	if is_hammer:
		_hammer_fx_center = center
		_hammer_fx_time = 0.46
		FX.hit_burst(center, Color(2.8, 2.8, 2.8), 55.0, 0.15, EnergyBurst.STYLE_STAR)
		Audio.play(&"hit_heavy")
	FX.shake(0.82 if is_hammer else 0.55)
	var push_squared := WAVE_PUSH_RADIUS * WAVE_PUSH_RADIUS
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy == self or enemy.is_dead:
			continue
		if enemy.global_position.distance_squared_to(center) > push_squared:
			continue
		enemy.color_index = color_index
		enemy._refresh_healthbar()
		enemy.queue_redraw()
		enemy.apply_knockback(center, 420.0, 0.36)
	FX.shards(center, tint, 28 if is_hammer else 18)


func _die() -> void:
	if is_dead:
		return
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			FX.shards(global_position + Vector2(sx, sy) * radius * 0.65,
				RunState.color_of(color_index), 14)
	super._die()


func _draw() -> void:
	var tint := RunState.enemy_color_of(color_index)
	var charge := _charge_amount()
	var pulse := 0.5 + 0.5 * sin(_plate_angle * 9.0)
	var core := Color(tint.r * 0.12, tint.g * 0.12, tint.b * 0.12, 1.0)
	var edge_boost := 1.35 + charge * 0.55
	var edge := Color(tint.r * edge_boost, tint.g * edge_boost, tint.b * edge_boost, 1.0)
	var half := radius * 0.9
	_draw_hammer_impact(tint)
	if _action == &"summon":
		_draw_summon_markers(tint, charge)

	# 蓄力光环：不画任何范围提示框，只让本体随蓄力发亮、膨胀。
	if charge > 0.01:
		var aura_tint := RunState.color_of(_promote_color) if _action == &"promote" else tint
		var aura_radius := radius * (0.95 + charge * 0.28 + pulse * 0.06)
		draw_circle(Vector2.ZERO, aura_radius,
			Color(aura_tint.r, aura_tint.g, aura_tint.b, 0.10 + charge * 0.16))
		draw_arc(Vector2.ZERO, aura_radius, 0.0, TAU, 40,
			Color(aura_tint.r, aura_tint.g, aura_tint.b, 0.35 + charge * 0.5),
			1.5 + charge * 3.0, true)

	# 冲刺蓄力：身后拖出逐渐变长的速度线，方向锁定玩家。
	if _action == &"dash":
		_draw_dash_charge(tint, charge)

	# 错位外框、四块分离角甲、旋转核心，让轮廓区别于普通放大方形。
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), core)
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), edge, false, 3.5)
	draw_set_transform(Vector2.ZERO, _plate_angle, Vector2.ONE)
	draw_rect(Rect2(-half * 0.78, -half * 0.78, half * 1.56, half * 1.56),
		Color(tint.r, tint.g, tint.b, 0.58 + charge * 0.3), false, 2.0)
	var core_size := 23.0 * (1.0 + charge * (0.16 + pulse * 0.2))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -core_size), Vector2(core_size, 0),
		Vector2(0, core_size), Vector2(-core_size, 0)
	]), Color(tint.r * (0.34 + charge * 0.5), tint.g * (0.34 + charge * 0.5),
		tint.b * (0.34 + charge * 0.5), 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx, sy) * (half + 9.0 + charge * 8.0)
			var bracket := PackedVector2Array([
				corner - Vector2(sx * 17.0, 0.0), corner,
				corner - Vector2(0.0, sy * 17.0)
			])
			draw_polyline(bracket, edge, 5.0, true)
	# 方锤沿肩部向后抡起、放大并抖动；落点只有小标记，不遮挡战场。
	var hammer_side := Vector2(half + 30.0, 0.0)
	var head_size := 13.0
	if _action == &"hammer":
		var aim := _hammer_point - global_position
		var direction := aim.normalized() if aim.length_squared() > 0.001 else Vector2.RIGHT
		var jitter := sin(_plate_angle * 34.0) * 4.0 * charge
		hammer_side = direction.rotated(-0.92 * charge) * (half + 30.0 + charge * 16.0 + jitter)
		head_size = 13.0 + charge * 8.0
		draw_line(direction * (half + 10.0), hammer_side, edge, 5.0 + charge * 3.0, true)
		_draw_hammer_target(tint, charge)
	else:
		draw_line(hammer_side * 0.62, hammer_side, edge, 5.0, true)
	draw_rect(Rect2(hammer_side - Vector2.ONE * head_size, Vector2.ONE * head_size * 2.0),
		core)
	draw_rect(Rect2(hammer_side - Vector2.ONE * head_size, Vector2.ONE * head_size * 2.0),
		edge, false, 3.0)
	_draw_health_bar(tint)


func _draw_hammer_target(tint: Color, charge: float) -> void:
	var point := _hammer_point - global_position
	var alpha := 0.30 + 0.60 * charge
	var marker := 8.0 + 10.0 * charge
	var glow := Color(tint.r * 1.4, tint.g * 1.4, tint.b * 1.4, alpha)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var tip := point + Vector2(sx, sy) * marker
			draw_line(tip, tip - Vector2(sx * 7.0, 0.0), glow, 2.0 + charge, true)
			draw_line(tip, tip - Vector2(0.0, sy * 7.0), glow, 2.0 + charge, true)
	draw_line(point + Vector2(-5, 0), point + Vector2(5, 0), glow, 1.5, true)
	draw_line(point + Vector2(0, -5), point + Vector2(0, 5), glow, 1.5, true)


func _draw_summon_markers(tint: Color, charge: float) -> void:
	var warning := Color(tint.r, tint.g, tint.b, 0.36 + charge * 0.58)
	for point in _summon_points:
		var local := point - global_position
		var size := 9.0 + charge * 8.0
		var diamond := PackedVector2Array([
			local + Vector2(0, -size), local + Vector2(size, 0),
			local + Vector2(0, size), local + Vector2(-size, 0),
			local + Vector2(0, -size)
		])
		draw_polyline(diamond, warning, 2.0 + charge, true)
		draw_line(local + Vector2(-4, -4), local + Vector2(4, 4), warning, 1.5, true)


func _draw_hammer_impact(tint: Color) -> void:
	if _hammer_fx_time <= 0.0:
		return
	var progress := 1.0 - _hammer_fx_time / 0.46
	var fade := 1.0 - progress
	var center := _hammer_fx_center - global_position
	var length := 48.0 + 95.0 * progress
	var crack_tint := Color(tint.r * 1.5, tint.g * 1.5, tint.b * 1.5, fade * 0.82)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + float(i % 3) * 0.10
		var direction := Vector2.from_angle(angle)
		var bend := Vector2.from_angle(angle + (0.20 if i % 2 == 0 else -0.20))
		var crack := PackedVector2Array([
			center + direction * 14.0,
			center + bend * (length * 0.55),
			center + direction * length
		])
		draw_polyline(crack, crack_tint, 3.0 * fade + 0.7, true)
	var flash_size := 22.0 * fade
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -flash_size), center + Vector2(flash_size, 0),
		center + Vector2(0, flash_size), center + Vector2(-flash_size, 0)
	]), Color(2.8, 2.8, 2.8, fade * 0.9))


func _charge_amount() -> float:
	if _action == &"" or _action == &"dash_move" or _windup_total <= 0.0:
		return 0.0
	return clampf(1.0 - _windup / _windup_total, 0.0, 1.0)


func _draw_dash_charge(tint: Color, charge: float) -> void:
	var offset := _dash_target - global_position
	if offset.length_squared() < 0.001:
		return
	var direction := offset.normalized()
	var side := Vector2(-direction.y, direction.x)
	for i in 5:
		var lateral := (float(i) - 2.0) * 9.0
		var start := -direction * (radius * 0.75 + 4.0) + side * lateral
		var length := 16.0 + charge * 54.0 + absf(lateral) * 0.6
		draw_line(start - direction * length, start,
			Color(tint.r, tint.g, tint.b, 0.12 + 0.42 * charge),
			1.5 + charge * 1.5, true)


## 常驻 Boss 血条：宽 240、高 12，带黑底、边框和数值，任何缩放都不会影响它
## （Boss 本身已取消受击挤压）。
func _draw_health_bar(tint: Color) -> void:
	if is_dead or max_health <= 0.0:
		return
	var width := 240.0
	var height := 12.0
	var top := -radius - 44.0
	var ratio := clampf(health / max_health, 0.0, 1.0)
	draw_rect(Rect2(-width * 0.5 - 3.0, top - 3.0, width + 6.0, height + 6.0),
		Color(0.0, 0.0, 0.0, 0.85))
	draw_rect(Rect2(-width * 0.5, top, width, height), Color(0.10, 0.10, 0.12, 0.95))
	draw_rect(Rect2(-width * 0.5, top, width * ratio, height),
		Color(tint.r * 0.9, tint.g * 0.9, tint.b * 0.9, 1.0))
	draw_rect(Rect2(-width * 0.5, top, width, height),
		Color(tint.r, tint.g, tint.b, 0.95), false, 1.5)
	var font := ThemeDB.fallback_font
	var text := "%d / %d" % [int(ceil(health)), int(max_health)]
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(font, Vector2(-text_size.x * 0.5, top - 8.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.95, 0.98, 1.0, 0.95))



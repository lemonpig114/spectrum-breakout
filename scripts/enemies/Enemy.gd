class_name Enemy
extends CharacterBody2D

const ROUND_EXPLOSION_SCRIPT := preload("res://scripts/fx/RoundExplosion.gd")

var type_data: EnemyTypeResource
var target: Node2D
var color_index := ColorType.RED
var max_health := 10.0
var health := 10.0
var radius := 12.0
var is_dead := false
var empowered := false
var batch_rendered := false
var _speed_multiplier := 1.0

var _visual_angle := 0.0
var _flash := 0.0
var _contact_cooldown := 0.0
var _squash_time := 0.0
var _knockback_velocity := Vector2.ZERO
var _knockback_time := 0.0
var _shot_timer := 0.0
var _movement_accum := 0.0
## 分离力每两帧才重算一次；拥挤时邻居平衡会左右翻转，直接使用会原地抽搐。
## 低通一点，让方向变化经过若干帧过渡，而不是整帧反向。
var _separation_smoothed := Vector2.ZERO
var _points := PackedVector2Array()
var _outline := PackedVector2Array()
var _wing_top := PackedVector2Array()
var _wing_bottom := PackedVector2Array()
var _round_spark_timer := 0.0
var _round_spark_positions: Array[Vector2] = []
var _round_spark_velocities: Array[Vector2] = []
var _round_spark_lives: Array[float] = []

# 弱点元素状态
var _burn_stacks: Array[Dictionary] = []
var _poison_dps := 0.0
var _dot_bucket := 0
var _slow := 0.0
var circle_slow := false
var _slow_time := 0.0
var _ice_time := 0.0
var vulnerability := 0.0
var _vulnerability_applied := false

@onready var _shape: CollisionShape2D = $CollisionShape2D
var _healthbar: EnemyHealthBar
var _last_splash_label_frame := -1000


func configure(enemy_type: EnemyTypeResource, player_target: Node2D, enemy_color: int = -1) -> void:
	type_data = enemy_type
	target = player_target

	if type_data == null:
		return

	color_index = enemy_color if enemy_color >= 0 else RunState.rng.randi_range(0, ColorType.COUNT - 1)
	max_health = type_data.max_health
	health = max_health
	radius = type_data.radius
	visual_angle_random()
	_apply_shape()


func visual_angle_random() -> void:
	_visual_angle = randf() * TAU


func _ready() -> void:
	add_to_group("enemies")
	batch_rendered = type_data != null and type_data.shape == &"polygon" \
		and type_data.sides in [3, 4, 6] \
		and type_data.behavior != &"explode" and not type_data.is_boss \
		and get_tree().get_first_node_in_group(&"enemy_batch_renderer") != null \
		and not OS.get_cmdline_user_args().has("--no-enemy-batch")
	_dot_bucket = get_instance_id() % 4
	EventBus.dot_tick.connect(_on_global_dot_tick)
	_healthbar = EnemyHealthBar.new()
	add_child(_healthbar)
	_healthbar.refresh(health, max_health, radius, RunState.color_of(color_index))
	rotation = _visual_angle
	_healthbar.rotation = -_visual_angle
	if type_data != null and type_data.behavior == &"ranged":
		_shot_timer = type_data.shot_interval * randf_range(0.45, 0.8)
	if type_data != null and type_data.behavior == &"explode":
		_round_spark_timer = randf_range(0.0, 0.18)
	_apply_shape()
	queue_redraw()


func _apply_shape() -> void:
	if _shape == null or _shape.shape == null:
		return
	var circle := _shape.shape.duplicate() as CircleShape2D
	if circle != null:
		circle.radius = radius
		_shape.shape = circle
	_rebuild_polygon()


## 顶点只在这里计算一次；绘制时用 draw_set_transform 旋转，
## 避免每个敌人每帧重新计算三角函数并分配 PackedVector2Array。
func _rebuild_polygon() -> void:
	if type_data != null and type_data.shape == &"airplane":
		# 两片共脊的钝角三角翼：尖端指向朝向，后方留细缝，轮廓与普通三角区别明显。
		_wing_top = PackedVector2Array([
			Vector2(radius, 0), Vector2(-radius * 0.8, -radius * 0.84),
			Vector2(-radius * 0.25, -radius * 0.06),
		])
		_wing_bottom = PackedVector2Array([
			Vector2(radius, 0), Vector2(-radius * 0.25, radius * 0.06),
			Vector2(-radius * 0.8, radius * 0.84),
		])
		return
	var sides := maxi(3, type_data.sides if type_data != null else 3)
	_points.resize(sides)
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		_points[i] = Vector2(cos(angle), sin(angle)) * radius
	_outline = _points.duplicate()
	_outline.append(_points[0])


func _physics_process(delta: float) -> void:
	if is_dead or RunState.is_dead:
		return

	if type_data != null and type_data.behavior == &"ranged" and target != null and is_instance_valid(target):
		var face := target.global_position - global_position
		if face.length_squared() > 0.001:
			_visual_angle = lerp_angle(_visual_angle, face.angle(), 1.0 - exp(-8.0 * delta))
	else:
		_visual_angle += delta * 0.7
	# 旋转交给节点 transform：不重建 _draw 命令，70 个敌人同屏也不会每帧重绘。
	rotation = _visual_angle
	_healthbar.rotation = -_visual_angle

	# 受击闪白用 modulate 表现：只更新节点颜色，不需要重建 _draw 命令。
	# 溅射一次命中 70 个敌人时，这比每帧重绘整个敌人便宜得多。
	var previous_flash := _flash
	_flash = maxf(0.0, _flash - delta * 8.0)
	if _flash > 0.0 or previous_flash > 0.0:
		var bright := 1.0 + _flash * 1.5
		modulate = Color(bright, bright, bright, 1.0)

	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	_update_squash(delta)
	_tick_statuses(delta)
	if is_dead:
		return
	# 远处敌人的位置每两帧更新一次，轮流分摊物理空间索引刷新。
	# 状态伤害、受击闪烁和接触冷却仍逐帧计算；近身及击退保持 60 Hz。
	if _knockback_time <= 0.0 and target != null and is_instance_valid(target) \
		and global_position.distance_squared_to(target.global_position) > 380.0 * 380.0:
		if (Engine.get_physics_frames() + get_instance_id()) % 2 == 0:
			_movement_accum += delta
			return
	delta += _movement_accum
	_movement_accum = 0.0

	if _knockback_time > 0.0:
		_knockback_time = maxf(0.0, _knockback_time - delta)
		velocity = _knockback_velocity
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 1900.0 * delta)
		_move_manually(delta)
		if type_data != null and type_data.behavior == &"explode":
			_update_round_sparks(delta)
		return

	if type_data == null or target == null or not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var target_radius := Player.RADIUS
	if target is Player:
		target_radius = (target as Player).body_radius
	var contact_range := radius + target_radius + 2.0

	var move_speed := type_data.move_speed * _speed_multiplier * (1.0 - maxf(_slow, 0.15 if circle_slow else 0.0))
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	# 追逐 + 邻近分离。空间网格只找九格邻居，不启用敌人间的物理碰撞。
	# 到达接触范围后仍允许侧向挪动，避免所有敌人叠在一个攻击点。
	var pursuit := Vector2.ZERO
	if type_data.behavior == &"ranged":
		if distance > type_data.preferred_distance + 45.0:
			pursuit = to_target / maxf(distance, 0.001)
		elif distance < type_data.preferred_distance - 55.0:
			pursuit = -to_target / maxf(distance, 0.001)
	elif distance > contact_range and distance > 0.001:
		pursuit = to_target / distance
	var steering := pursuit
	if EnemyFlock.enabled:
		# 分离方向每两帧才刷新；拥挤时邻居平衡可能整帧翻转，直接叠加会让
		# 敌人在原地高速来回抽动。低通后方向变化分摊到数帧，仍保留持续斥力。
		_separation_smoothed = _separation_smoothed.lerp(EnemyFlock.separation(self), 0.3)
		steering += _separation_smoothed
	velocity = steering.limit_length(1.12) * move_speed
	_move_manually(delta)
	if type_data.behavior == &"explode":
		_update_round_sparks(delta)
	distance = global_position.distance_to(target.global_position)
	if type_data.behavior == &"ranged":
		_shot_timer -= delta
		if _shot_timer <= 0.0 and distance <= type_data.preferred_distance + 80.0:
			_fire_ranged()
			_shot_timer = type_data.shot_interval

	if _contact_cooldown <= 0.0 and distance <= contact_range:
		if type_data.behavior == &"explode":
			_die()
			return
		if target.has_method("take_damage"):
			# 减速同时延长敌人的接触攻击间隔。
			_contact_cooldown = 0.8 * (1.0 + maxf(_slow, 0.15 if circle_slow else 0.0))
			target.take_damage(type_data.contact_damage * Director.enemy_damage_multiplier(), self)


## 仅圆核使用的小火星。每次最多留两颗短命粒子，避免高密度阶段额外创建节点。
func _update_round_sparks(delta: float) -> void:
	var changed := false
	for i in range(_round_spark_lives.size() - 1, -1, -1):
		_round_spark_lives[i] -= delta
		if _round_spark_lives[i] <= 0.0:
			_round_spark_lives.remove_at(i)
			_round_spark_positions.remove_at(i)
			_round_spark_velocities.remove_at(i)
		else:
			_round_spark_positions[i] += _round_spark_velocities[i] * delta
		changed = true
	_round_spark_timer -= delta
	if velocity.length_squared() > 1600.0 and _round_spark_timer <= 0.0:
		_round_spark_timer = 0.18 + randf_range(-0.035, 0.035)
		var back := -velocity.normalized().rotated(-rotation)
		var side := back.orthogonal()
		_round_spark_positions.append(back * radius * 0.9 + side * randf_range(-radius * 0.45, radius * 0.45))
		_round_spark_velocities.append(-velocity.rotated(-rotation) * 0.85 + side * randf_range(-12.0, 12.0))
		_round_spark_lives.append(0.28)
		changed = true
	if changed:
		queue_redraw()


func _fire_ranged() -> void:
	if get_parent() == null or target == null or not is_instance_valid(target):
		return
	var aim := (target.global_position - global_position).normalized()
	var shot := EnemyProjectile.new()
	get_parent().add_child(shot)
	shot.configure(global_position + aim * (radius + 6.0), aim, target,
		RunState.color_of(color_index), type_data.projectile_speed,
		type_data.contact_damage * Director.enemy_damage_multiplier(), color_index)


## 手动积分移动：敌人可越过玩家的软墙，不走物理求解。
func _move_manually(delta: float) -> void:
	global_position += velocity * delta
	if EnemyFlock.enabled:
		global_position += EnemyFlock.correction(self)
	if target != null and is_instance_valid(target):
		var offset := global_position - target.global_position
		var stop_distance := radius + (target as Player).body_radius + 2.0 if target is Player else radius + Player.RADIUS + 2.0
		if offset.length_squared() < stop_distance * stop_distance:
			global_position = target.global_position + (offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT) * stop_distance


func take_damage(context: DamageContext) -> void:
	if is_dead:
		return

	var original_amount := context.amount
	var original_elemental := context.elemental_bonus
	_apply_vulnerability_for_attack()
	var defense_multiplier := (1.0 + vulnerability) * armor_multiplier()
	context.amount *= defense_multiplier
	context.elemental_bonus *= defense_multiplier
	Skills.record_projectile_damage(context, minf(maxf(health, 0.0), context.amount))
	health -= context.amount
	if context.has_tag(&"splash"):
		# 溅射可能同帧命中整群敌人；保留闪白，避免每只都改物理体缩放。
		_flash = maxf(_flash, 0.55)
	else:
		_flash = 1.0
		_squash()
	_refresh_healthbar()

	var hit_color := RunState.color_of(context.color_index)
	var style := FloatingTextLayer.STYLE_NORMAL
	if context.has_tag(&"super_crit"):
		style = FloatingTextLayer.STYLE_SUPER_CRIT
	elif context.is_crit:
		style = FloatingTextLayer.STYLE_CRIT
	elif context.has_tag(&"splash"):
		style = FloatingTextLayer.STYLE_SPLASH
	elif context.has_tag(&"weakness") or context.relation == &"advantage":
		style = FloatingTextLayer.STYLE_WEAKNESS
	# 大范围溅射会在一帧命中许多目标；同一目标每 0.2 秒最多显示一次小数字。
	# 真实伤害与直接命中的暴击/弱点仍逐次展示，计算伤害完全不受此限制。
	var show_number := true
	if style == FloatingTextLayer.STYLE_SPLASH:
		var frame := Engine.get_physics_frames()
		show_number = frame - _last_splash_label_frame >= 12
		if show_number:
			_last_splash_label_frame = frame
	if show_number:
		FX.damage_number(
			global_position + Vector2(0.0, -radius - 8.0),
			context.amount - context.elemental_bonus,
			hit_color,
			false,
			style,
			_damage_caption(context)
		)
		if context.elemental_bonus > 0.0:
			_healthbar.pulse_status(&"ice")
			FX.damage_number(
				global_position + Vector2(13.0, -radius + 2.0),
				context.elemental_bonus,
				Color(0.5, 1.5, 2.6, 1.0),
				false,
				FloatingTextLayer.STYLE_ICE
			)

	if health <= 0.0:
		_die()
	context.amount = original_amount
	context.elemental_bonus = original_elemental


func _damage_caption(context: DamageContext) -> String:
	var parts := PackedStringArray()
	if context.has_tag(&"elemental"):
		parts.append("元素")
	if context.has_tag(&"splash"):
		parts.append("溅射")
	if context.has_tag(&"super_crit"):
		parts.append("超暴击")
	else:
		if context.has_tag(&"weakness") or context.relation == &"advantage":
			parts.append("弱点")
		if context.is_crit:
			parts.append("暴击")
	return " · ".join(parts)


func missing_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(1.0 - health / max_health, 0.0, 1.0)


## 真实伤害：无视颜色克制与减伤，用于灵魂线。
func take_true_damage(amount: float, source_key: StringName = &"skill:soul_1") -> void:
	if is_dead:
		return

	_apply_vulnerability_for_attack(false)
	amount *= (1.0 + vulnerability) * armor_multiplier()
	Skills.record_damage(source_key, minf(maxf(health, 0.0), amount))
	health -= amount
	_flash = 1.0
	_squash()
	_refresh_healthbar()
	FX.damage_number(
		global_position + Vector2(0.0, -radius - 8.0),
		amount,
		Color(0.82, 0.45, 1.0, 1.0),
		false,
		FloatingTextLayer.STYLE_SOUL
	)

	if health <= 0.0:
		_die()


func apply_burn(total_damage: float) -> void:
	if is_dead or total_damage <= 0.0:
		return
	_burn_stacks.append({"total": total_damage, "ticks": 4})
	_refresh_status_icons()


func apply_poison(dps: float) -> void:
	if is_dead or dps <= 0.0:
		return
	_poison_dps += dps
	_refresh_status_icons()


func apply_slow(amount: float, duration: float) -> void:
	if is_dead:
		return
	_slow = clampf(maxf(_slow, amount), 0.0, 0.6)
	_slow_time = maxf(_slow_time, duration)


func apply_ice(duration: float) -> void:
	if is_dead:
		return
	_ice_time = maxf(_ice_time, duration)
	_refresh_status_icons()


func has_ice() -> bool:
	return _ice_time > 0.0


func _refresh_status_icons() -> void:
	if _healthbar != null:
		_healthbar.set_statuses(not _burn_stacks.is_empty(), _poison_dps > 0.0, _ice_time > 0.0, vulnerability > 0.0)


func _apply_vulnerability_for_attack(add_stack: bool = true) -> void:
	if not Skills.is_unlocked(&"fragile_1"):
		return
	var cap := 0.35 if Skills.is_unlocked(&"fragile_2") else 0.20
	if not _vulnerability_applied:
		_vulnerability_applied = true
		vulnerability = cap
		_refresh_status_icons()
	elif add_stack and Skills.is_unlocked(&"fragile_4"):
		vulnerability = minf(cap, vulnerability + 0.005)
		_refresh_status_icons()


func armor_multiplier() -> float:
	if type_data == null:
		return 1.0
	if type_data.is_boss and has_method("boss_armor_multiplier"):
		return float(call("boss_armor_multiplier"))
	if type_data.id == &"chaser_square":
		return 0.85
	if type_data.id == &"chaser_hex":
		return 0.70
	return 1.0


## 处决：与正常击杀一致地结算奖励。
func execute() -> void:
	force_kill()


func _tick_statuses(delta: float) -> void:
	var visuals_changed := false
	if vulnerability > 0.0:
		vulnerability = maxf(0.0, vulnerability - delta * (0.025 if Skills.is_unlocked(&"fragile_3") else 0.05))
		if vulnerability <= 0.0:
			visuals_changed = true
	if _slow_time > 0.0:
		_slow_time = maxf(0.0, _slow_time - delta)
		if _slow_time <= 0.0:
			_slow = 0.0
			visuals_changed = true
	if _ice_time > 0.0:
		_ice_time = maxf(0.0, _ice_time - delta)
		if _ice_time <= 0.0:
			visuals_changed = true

	# 状态图标独立绘制，只有出现/消失时才刷新血条节点。
	if visuals_changed:
		_refresh_status_icons()


func _on_global_dot_tick(bucket: int) -> void:
	if bucket == _dot_bucket and not is_dead and (not _burn_stacks.is_empty() or _poison_dps > 0.0):
		_apply_dot_tick()


## 灼伤在两秒内每半秒结算一次；中毒每半秒结算半秒的伤害。
func _apply_dot_tick() -> void:
	var burn_damage := 0.0
	for i in range(_burn_stacks.size() - 1, -1, -1):
		var stack: Dictionary = _burn_stacks[i]
		burn_damage += float(stack.get("total", 0.0)) * 0.25
		stack["ticks"] = int(stack.get("ticks", 1)) - 1
		if int(stack["ticks"]) <= 0:
			_burn_stacks.remove_at(i)

	var poison_damage := _poison_dps * 0.5
	var vulnerable_multiplier := 1.0 + vulnerability
	burn_damage *= vulnerable_multiplier * armor_multiplier()
	poison_damage *= vulnerable_multiplier * armor_multiplier()
	var total := burn_damage + poison_damage
	if total > 0.0:
		var dealt := minf(maxf(health, 0.0), total)
		Skills.record_damage(&"skill:weak_3_burn", dealt * burn_damage / total)
		Skills.record_damage(&"skill:weak_3_poison", dealt * poison_damage / total)
		health -= total
		_flash = maxf(_flash, 0.7)
		_refresh_healthbar()
	if burn_damage > 0.0:
		_show_elemental_tick(burn_damage, Color(2.6, 0.85, 0.28), FloatingTextLayer.STYLE_BURN, &"burn")
	if poison_damage > 0.0:
		_show_elemental_tick(poison_damage, Color(0.45, 2.2, 0.65), FloatingTextLayer.STYLE_POISON, &"poison")
	_refresh_status_icons()
	if health <= 0.0:
		_die()


func _show_elemental_tick(amount: float, tint: Color, style: int, kind: StringName) -> void:
	_healthbar.pulse_status(kind)
	FX.damage_number(
		global_position + Vector2(0.0, -radius - 6.0),
		amount,
		tint,
		false,
		style
	)

## 被击退。strength 越大冲得越远，期间不追人、不造成接触伤害。
func apply_knockback(origin: Vector2, strength: float, duration: float = 0.32) -> void:
	if is_dead:
		return

	var direction := global_position - origin
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT.rotated(randf() * TAU)

	_knockback_velocity = direction.normalized() * strength
	_knockback_time = duration
	_flash = maxf(_flash, 0.8)
	_squash()
	queue_redraw()


## 强制击杀：受伤反击用，奖励与正常击杀一致。
func force_kill() -> void:
	if is_dead:
		return
	health = 0.0
	_die()


func _squash() -> void:
	# 用每帧衰减代替 Tween：高攻速下不会再为每次命中创建一个 Tween 对象。
	_squash_time = 0.16
	scale = Vector2(1.28, 0.78)


func _refresh_healthbar() -> void:
	if _healthbar != null:
		_healthbar.refresh(health, max_health, radius, RunState.color_of(color_index))


## Boss 强化只首次加上限和移速；再次命中仅补满血并重新染色。
func empower(boss_color: int) -> void:
	if is_dead or type_data == null or type_data.id != &"chaser_square":
		return
	if not empowered:
		empowered = true
		batch_rendered = false
		max_health *= 3.0
		_speed_multiplier = 1.2
	color_index = boss_color
	health = max_health
	_refresh_healthbar()
	queue_redraw()


func _update_squash(delta: float) -> void:
	if _squash_time <= 0.0:
		return
	_squash_time = maxf(0.0, _squash_time - delta)
	var ease := _squash_time / 0.16
	ease *= ease
	scale = Vector2(1.0 + 0.28 * ease, 1.0 - 0.22 * ease)


## 掉落散点：以尸体为中心随机偏 9–26px；限制在场内，避免掉出边界。
func _scatter_drop_position() -> Vector2:
	var angle := RunState.rng.randf() * TAU
	var radius := RunState.rng.randf_range(9.0, 26.0)
	var position := global_position + Vector2(cos(angle), sin(angle)) * radius
	var bounds := RunState.arena_rect.grow(-24.0)
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)
	return position


func _die() -> void:
	if is_dead:
		return

	is_dead = true
	if type_data != null and type_data.behavior == &"explode":
		# 贴脸自爆与远处击杀使用同一判定，圆波半径直接取资源中的伤害半径。
		if target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) <= type_data.explosion_radius:
			if target.has_method("take_damage"):
				target.take_damage(type_data.contact_damage * Director.enemy_damage_multiplier(), self)
		if get_parent() != null:
			var blast: Node2D = ROUND_EXPLOSION_SCRIPT.new()
			blast.set("tint", RunState.color_of(color_index))
			blast.set("max_radius", type_data.explosion_radius)
			get_parent().add_child(blast)
			blast.global_position = global_position
		FX.shards(global_position, RunState.color_of(color_index), 14)
	_refresh_healthbar()
	remove_from_group("enemies")

	var gold_reward := type_data.gold_reward + Skills.gold_kill_bonus()
	EventBus.enemy_killed.emit(self, gold_reward, type_data.xp_reward)
	# 奖励实体化：掉落交给 PickupField 处理磁吸 / 全屏吸取 / 流光汇入，拾取时才结算。
	# 金币与经验各自散开，避免精确叠在同一点；太挤时也不会堵住拾取路线。
	Pickups.spawn_gold(_scatter_drop_position(), gold_reward)
	Pickups.spawn_xp(_scatter_drop_position(), type_data.xp_reward)

	# 本体短闪后快速退场，把画面交给独立壳片裂解；不放大成扩散外轮廓。
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	modulate = Color(2.6, 2.6, 2.6, 1.0)
	FX.death_effect(global_position, RunState.color_of(color_index))
	Audio.play(&"kill")
	# 击杀不再改变 Engine.time_scale：连续击杀时顿帧会累积成明显的卡顿感。

	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation + 0.18, 0.10)
	tween.tween_property(self, "modulate", Color(2.2, 2.2, 2.2, 0.0), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)


func _draw() -> void:
	if type_data == null or batch_rendered:
		return

	var c := RunState.color_of(color_index)
	var fill := Color(c.r * 0.12, c.g * 0.12, c.b * 0.12, 1.0)

	# 多边形随节点 rotation 旋转，这里只画一次、不重建绘制命令。
	if type_data.shape == &"airplane":
		draw_colored_polygon(_wing_top, fill)
		draw_colored_polygon(_wing_bottom, Color(c.r * 0.20, c.g * 0.20, c.b * 0.20, 1.0))
		for wing in [_wing_top, _wing_bottom]:
			var edge: PackedVector2Array = wing.duplicate()
			edge.append(wing[0])
			draw_polyline(edge, Color(c.r, c.g, c.b, 1.0), 2.0, true)
		draw_line(Vector2(-radius * 0.22, 0), Vector2(radius * 0.72, 0),
			Color(c.r, c.g, c.b, 0.75), 1.0, true)
	else:
		draw_colored_polygon(_points, fill)
		draw_polyline(_outline, Color(c.r, c.g, c.b, 1.0), 2.0, true)
		if type_data.behavior == &"explode":
			for i in _round_spark_lives.size():
				var glow := clampf(_round_spark_lives[i] / 0.28, 0.0, 1.0)
				draw_circle(_round_spark_positions[i], 1.0 + glow * 0.55,
					Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, glow * 0.75))
		if empowered:
			var edge := radius + 3.0
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner := Vector2(sx * edge, sy * edge)
					draw_line(corner, corner - Vector2(sx * 6.0, 0.0), c, 2.0, true)
					draw_line(corner, corner - Vector2(0.0, sy * 6.0), c, 2.0, true)

	# 圆核中心保持空心；状态图标交给独立的血条节点绘制。
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	if type_data.behavior != &"explode":
		draw_circle(Vector2.ZERO, 2.5, Color(c.r, c.g, c.b, 0.9))

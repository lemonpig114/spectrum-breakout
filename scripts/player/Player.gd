class_name Player
extends CharacterBody2D

const RADIUS := 12.0
const MOVE_SPEED := 250.0
const MOVE_SPEED_CAP := 400.0
const DISTANCE_BURST_THRESHOLD := 4000.0
# 生命以“颗心”为单位：一颗 = 1.0，半颗 = 0.5。
# 敌人每次接触固定扣 0.5 心，HUD 直接按整颗/半颗绘制。
const MAX_HEALTH := 5.0
const DRAG_HOLD_MS := 140
const DRAG_DISTANCE := 18.0
const MANUAL_AIM_WINDOW := 0.5
const AUTO_AIM_RANGE := 620.0
const PANIC_KILL_RADIUS := 84.0
const PANIC_PUSH_RADIUS := 280.0
## 三弹以上展开固定扇面再叠随机偏差；双弹改为平行双枪口。
const SHOTGUN_BASE_FAN_DEG := 18.0
const SHOTGUN_FAN_PER_PELLET_DEG := 5.0
const SHOTGUN_MAX_FAN_DEG := 50.0

var projectile_manager: ProjectileManager
var controls_enabled := false
var intro_white := false

var character: CharacterResource
var stats := StatBlock.new()
var max_health := MAX_HEALTH
var health := MAX_HEALTH
var body_radius := RADIUS
var color_index := ColorType.RED
var weapon: WeaponRuntime

# 机体外形与炮口动画：瞄准角平滑追随目标，开火时炮管后坐/枪口闪光。
var _body_style := CharacterVisual.BODY_CIRCLE
var _barrel_style := CharacterVisual.BARREL_CHEVRON
var _base_radius := RADIUS
## 机体的基础倍率：只缩放共用基础攻击，并参与射速上限计算。
var _damage_scale := 1.0
var _fire_rate_scale := 1.0
var _size_scale := 1.0
var _visual_aim := 0.0
var _recoil := 0.0
var _muzzle := 0.0
var _idle_time := 0.0

var _fire_cooldown := 0.0
var _heavy_timer := 0.0
var _heavy_primed := false
## 恶魔祭坛交易次数：每次写入独立的 max_health 修改器 source，永不互相覆盖。
var _altar_trades := 0
var _target: Node2D
var _invuln := 0.0
var _distance_traveled := 0.0
var _speed_burst_time := 0.0
var _base_collision_mask := 0
var _hold_active := false
var _hold_start_ms := 0
var _hold_start_x := 0.0
var _hold_start_position := Vector2.ZERO
var _hold_direction := 0
var _hold_preview_emitted := false
var _touch_switch_gesture := false
var _hold_max_distance := 0.0
var _manual_fire_held := false
var _manual_aim_timer := 0.0
var _manual_aim_direction := Vector2.RIGHT
var _pulse_tween: Tween
# 换色时旧色向新色平滑过渡，并播放一圈扩散/旋转的变身光环。
var _display_color := Color.WHITE
var _color_from := Color.WHITE
var _color_to := Color.WHITE
var _color_blend := 1.0
var _switch_ring := 1.0
var _switch_ring_color := Color.WHITE
var _switch_flash := 0.0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("player")
	color_index = RunState.color_index
	_display_color = RunState.color_of(color_index)
	_color_from = _display_color
	_color_to = _display_color

	character = RunState.get_selected_character()
	var start_speed := MOVE_SPEED
	var start_health := MAX_HEALTH
	if character != null:
		start_speed = character.move_speed
		start_health = character.max_health
		_base_radius = character.body_radius
		_body_style = character.body_style
		_barrel_style = character.barrel_style
		_damage_scale = maxf(0.01, character.damage_multiplier)
		_fire_rate_scale = maxf(0.01, character.fire_rate_multiplier)
		_size_scale = maxf(0.01, character.projectile_size_multiplier)

	# 所有机体共用同一份基础攻击，角色差异只来自上面的基础倍率。
	weapon = WeaponRuntime.new(ContentDB.get_weapon(CharacterResource.BASE_WEAPON_ID))
	if weapon.core == null:
		push_warning("Player: base weapon '%s' missing, using defaults" % CharacterResource.BASE_WEAPON_ID)
		weapon.set_core(WeaponCoreResource.new())
	_apply_character_scaling()

	stats.set_base(&"move_speed", start_speed)
	stats.set_base(&"max_health", start_health)
	# 全局战斗属性：技能/遗物都通过 StatBlock 修改这些值。
	stats.set_base(&"crit_chance", 0.05)
	stats.set_base(&"crit_damage", 1.5)
	stats.set_base(&"dodge", 0.0)
	stats.set_base(&"elemental_damage", 0.0)
	stats.set_base(&"summon_damage", 1.0)
	stats.set_base(&"weakness_multiplier", 1.5)
	stats.set_base(&"xp_gain", 1.0 + (character.xp_gain_bonus if character != null else 0.0))
	stats.set_base(&"gold_gain", 1.0)
	stats.set_base(&"gold_income", 0.0)
	stats.set_base(&"luck", 0.0)
	# 大餐等遗物会让体型略微增大；基础半径仍来自机体。
	stats.set_base(&"body_scale", 1.0)
	max_health = snap_to_half(stats.get_value(&"max_health"))
	health = max_health
	body_radius = _base_radius

	_setup_collision()
	_base_collision_mask = collision_mask
	EventBus.color_changed.connect(_on_color_changed)
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.player_health_changed.emit(health, max_health)
	queue_redraw()


## 把机体基础倍率写入武器 StatBlock。用 MULTIPLY 而不是改核心数值，
## 这样技能/遗物的百分比收益对每个角色完全一致。
func _apply_character_scaling() -> void:
	_add_weapon_scaling(&"damage", _damage_scale)
	_add_weapon_scaling(&"fire_rate", _fire_rate_scale)
	_add_weapon_scaling(&"projectile_size", _size_scale)


func _add_weapon_scaling(stat: StringName, multiplier: float) -> void:
	if weapon == null or is_equal_approx(multiplier, 1.0):
		return
	var scaling := StatModifierResource.new()
	scaling.stat = stat
	scaling.op = StatModifierResource.Op.MULTIPLY
	scaling.value = multiplier
	scaling.priority = -1000
	scaling.source = StringName("character_%s" % String(stat))
	weapon.stats.add_modifier(scaling)


func _setup_collision() -> void:
	if _shape == null or _shape.shape == null:
		return
	var circle := _shape.shape.duplicate() as CircleShape2D
	if circle != null:
		circle.radius = body_radius
		_shape.shape = circle


func _physics_process(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)
	if _speed_burst_time > 0.0:
		_speed_burst_time = maxf(0.0, _speed_burst_time - delta)
		_invuln = maxf(_invuln, 0.1)
		if _speed_burst_time <= 0.0:
			collision_mask = _base_collision_mask
			_shape.set_deferred("disabled", false)

	if not controls_enabled or RunState.is_dead:
		velocity = Vector2.ZERO
		return

	var input_direction := GameInput.mobile_move_direction if GameInput.touch_controls_active else Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down"
	)
	velocity = input_direction * effective_move_speed()
	_apply_soft_wall_resistance()
	var before_position := global_position
	move_and_slide()
	_clamp_to_arena()
	Skills.on_player_moved(global_position.distance_to(before_position))
	if Skills.is_unlocked(&"speed_4") and _speed_burst_time <= 0.0:
		_distance_traveled += global_position.distance_to(before_position)
		if _distance_traveled >= DISTANCE_BURST_THRESHOLD:
			_distance_traveled -= DISTANCE_BURST_THRESHOLD
			_speed_burst_time = 2.0
			collision_mask = 0
			_shape.set_deferred("disabled", true)
			FX.text_popup(global_position + Vector2(0, -28), "极速", Color(0.4, 2.0, 1.4), 16)


func effective_move_speed() -> float:
	var cap := MOVE_SPEED_CAP * (1.3 if Skills.is_unlocked(&"speed_4") else 1.0)
	var raw := stats.get_value(&"move_speed") * (1.3 if _speed_burst_time > 0.0 else 1.0)
	return minf(raw, cap)


func _process(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_idle_time += delta
	_recoil = maxf(0.0, _recoil - delta * 7.0)
	_muzzle = maxf(0.0, _muzzle - delta * 11.0)
	if _color_blend < 1.0:
		_color_blend = minf(1.0, _color_blend + delta / 0.22)
		_display_color = _color_from.lerp(_color_to, smoothstep(0.0, 1.0, _color_blend))
	_switch_ring = minf(1.0, _switch_ring + delta / 0.38)
	_switch_flash = maxf(0.0, _switch_flash - delta * 7.0)
	if controls_enabled and not RunState.is_dead and Skills.heavy_shot_enabled():
		_heavy_timer = maxf(0.0, _heavy_timer - delta)

	# 桌面左键手动瞄准；手机始终由最近敌人自动索敌。
	if _manual_fire_held:
		_manual_aim_timer = MANUAL_AIM_WINDOW
		var aim := _mouse_aim_direction()
		if aim != Vector2.ZERO:
			_manual_aim_direction = aim
	else:
		_manual_aim_timer = maxf(0.0, _manual_aim_timer - delta)

	if _hold_active and not _hold_preview_emitted:
		if Time.get_ticks_msec() - _hold_start_ms >= DRAG_HOLD_MS:
			_hold_preview_emitted = true
			_emit_switch_preview()

	if RunState.is_dead:
		_target = null
		queue_redraw()
		return

	_target = _find_nearest_enemy()

	# 炮管视觉角平滑追随瞄准方向，转向不生硬；开火时由 _fire 直接对齐。
	var aim_direction := Vector2.ZERO
	if _manual_aim_timer > 0.0:
		aim_direction = _manual_aim_direction
	elif _target != null and is_instance_valid(_target):
		aim_direction = (_target.global_position - global_position).normalized()
	if aim_direction.length_squared() > 0.0001:
		_visual_aim = lerp_angle(_visual_aim, aim_direction.angle(), 1.0 - exp(-13.0 * delta))

	if controls_enabled and _fire_cooldown <= 0.0:
		if _manual_aim_timer > 0.0:
			_fire(_manual_aim_direction)
		elif _target != null:
			_fire((_target.global_position - global_position).normalized())

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or RunState.is_dead:
		return

	if event is InputEventMouseButton:
		if GameInput.touch_controls_active:
			return
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_manual_fire_held = true
				var aim := _mouse_aim_direction()
				if aim != Vector2.ZERO:
					_manual_aim_direction = aim
				_manual_aim_timer = MANUAL_AIM_WINDOW
				# 点击立即朝指针方向射出，不等下一次自动开火。
				if _fire_cooldown <= 0.0:
					_fire(_manual_aim_direction)
			else:
				_manual_fire_held = false
				# 松开后仍保留 0.5 秒手动朝向，避免立刻回吸到最近敌人。
				_manual_aim_timer = MANUAL_AIM_WINDOW
			return
		if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mouse_event.pressed:
			_begin_switch_gesture(mouse_event.position)
		elif _hold_active:
			_finish_switch_gesture(mouse_event.position)
	elif event is InputEventMouseMotion and _hold_active and not GameInput.touch_controls_active:
		var motion_event := event as InputEventMouseMotion
		_update_switch_direction(motion_event.position)


func begin_touch_switch(screen_position: Vector2) -> void:
	_touch_switch_gesture = true
	_begin_switch_gesture(screen_position)


func update_touch_switch(screen_position: Vector2) -> void:
	if _hold_active and _touch_switch_gesture:
		_update_switch_direction(screen_position)


func finish_touch_switch(screen_position: Vector2) -> void:
	if _hold_active and _touch_switch_gesture:
		_finish_switch_gesture(screen_position)


func cancel_touch_switch() -> void:
	if not _touch_switch_gesture:
		return
	_hold_active = false
	_touch_switch_gesture = false
	_hold_direction = 0
	_hold_preview_emitted = false
	EventBus.color_switch_preview.emit(false, Vector2.ZERO, 0, 0, 0)


func _begin_switch_gesture(screen_position: Vector2) -> void:
	_hold_active = true
	_hold_start_ms = Time.get_ticks_msec()
	_hold_start_x = screen_position.x
	_hold_start_position = screen_position
	_hold_direction = 0
	_hold_preview_emitted = false
	_hold_max_distance = 0.0


func _update_switch_direction(screen_position: Vector2) -> void:
	var held_ms := Time.get_ticks_msec() - _hold_start_ms
	var delta_x := screen_position.x - _hold_start_x
	_hold_max_distance = maxf(_hold_max_distance, screen_position.distance_to(_hold_start_position))

	var direction := 0
	if (held_ms >= DRAG_HOLD_MS or _touch_switch_gesture) and absf(delta_x) >= DRAG_DISTANCE:
		direction = 1 if delta_x > 0.0 else -1

	if direction != _hold_direction:
		_hold_direction = direction
		_hold_preview_emitted = true
		_emit_switch_preview()


func _finish_switch_gesture(screen_position: Vector2) -> void:
	_update_switch_direction(screen_position)
	var held_ms := Time.get_ticks_msec() - _hold_start_ms

	if _hold_direction != 0:
		# 长按后向左/右拖动，松开时确认。
		RunState.cycle_color(_hold_direction)
	elif held_ms < DRAG_HOLD_MS and _hold_max_distance < DRAG_DISTANCE:
		# 快速点击：循环到下一个颜色。
		RunState.cycle_color(1)
	# 长按但未拖动：取消，不消耗能量。

	_hold_active = false
	_touch_switch_gesture = false
	_hold_direction = 0
	_hold_preview_emitted = false
	EventBus.color_switch_preview.emit(false, Vector2.ZERO, 0, 0, 0)


func _on_game_paused(paused: bool) -> void:
	if not paused:
		return
	# 暂停期间收不到鼠标松开事件，必须清掉按住状态，避免恢复后一直手动开火。
	_manual_fire_held = false
	_manual_aim_timer = 0.0

	if not _hold_active:
		return
	_hold_active = false
	_touch_switch_gesture = false
	_hold_direction = 0
	_hold_preview_emitted = false
	EventBus.color_switch_preview.emit(false, Vector2.ZERO, 0, 0, 0)


func _mouse_aim_direction() -> Vector2:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() < 4.0:
		return Vector2.ZERO
	return to_mouse.normalized()


func _emit_switch_preview() -> void:
	EventBus.color_switch_preview.emit(
		true,
		_hold_start_position,
		_hold_direction,
		ColorType.next(RunState.color_index, -1),
		ColorType.next(RunState.color_index, 1)
	)


func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance := AUTO_AIM_RANGE * AUTO_AIM_RANGE
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return null
	var half_view := get_viewport_rect().size * 0.5 / camera.zoom
	var visible_rect := Rect2(camera.get_screen_center_position() - half_view, half_view * 2.0)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy is Enemy and enemy.is_dead:
			continue
		if not visible_rect.has_point(enemy.global_position):
			continue
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy

	return best


## 这一发的弹丸角度偏移。spread_degrees 是“射击偏差”：每颗子弹的最终方向
## 都会再叠一次 ±spread/2 的随机角，所以朝同一方向连射两次不会走同一条线。
## 双弹沿瞄准方向平行射出；三弹以上保留固定扇面和逐颗随机偏差。
func _pellet_offsets(count: int, spread: float) -> PackedFloat32Array:
	if count == 2:
		return PackedFloat32Array([0.0, 0.0])
	var offsets := PackedFloat32Array()
	var jitter_half := maxf(0.0, spread) * 0.5

	if count > 1:
		var fan_degrees := minf(
			SHOTGUN_BASE_FAN_DEG + SHOTGUN_FAN_PER_PELLET_DEG * float(count - 2),
			SHOTGUN_MAX_FAN_DEG
		)
		var step := deg_to_rad(fan_degrees) / float(count - 1)
		var center := float(count - 1) * 0.5

		# 排序成“中间 → 两侧”：0、+1、-1、+2、-2…… 偶数弹时从 ±0.5 档开始。
		var ranks: Array[int] = []
		for rank in count:
			ranks.append(rank)
		ranks.sort_custom(func(a: int, b: int) -> bool:
			var da := absf(float(a) - center)
			var db := absf(float(b) - center)
			if is_equal_approx(da, db):
				return a > b
			return da < db
		)
		for rank in ranks:
			var lane_offset := (float(rank) - center) * step
			offsets.append(lane_offset + _shot_jitter(jitter_half))
		return offsets

	offsets.append(_shot_jitter(jitter_half))
	return offsets


## 单颗子弹的随机方向偏差；spread 为 0 时不消耗随机数。
func _shot_jitter(jitter_half: float) -> float:
	if jitter_half <= 0.0:
		return 0.0
	return RunState.rng.randf_range(-jitter_half, jitter_half)


func _fire(shoot_direction: Vector2) -> void:
	if projectile_manager == null:
		return

	var base_direction := shoot_direction
	if base_direction.length_squared() < 0.0001:
		if _target != null and is_instance_valid(_target):
			base_direction = (_target.global_position - global_position).normalized()
		else:
			base_direction = Vector2.RIGHT

	# 开火瞬间炮管直接对准射击方向，并触发后坐与枪口闪光。
	_visual_aim = base_direction.angle()
	_recoil = 1.0
	_muzzle = 1.0

	var weapon_stats := weapon.stats
	var count := maxi(1, int(weapon_stats.get_value(&"projectiles_per_shot")))
	var spread := deg_to_rad(weapon_stats.get_value(&"spread_degrees"))
	var base_angle := base_direction.angle()

	var rate := weapon.get_final_fire_rate()
	var primary_data := weapon.primary_data()
	if primary_data != null:
		rate *= primary_data.fire_rate_scale
	var cap := rate
	if weapon.core != null:
		# 上限也按机体倍率缩放，否则游隼的基础射速会吃掉技能给的成长空间。
		cap = weapon.core.fire_rate * _fire_rate_scale * Skills.fire_rate_cap_multiplier()
		rate = minf(rate, cap)

	var heavy := false
	var cooldown := 1.0 / maxf(0.1, rate)
	if Skills.heavy_shot_enabled():
		if _heavy_primed:
			heavy = true
			_heavy_primed = false
		elif _heavy_timer <= 0.0:
			_heavy_primed = true
			_heavy_timer = 5.0
			_fire_cooldown = cooldown * 2.0
			return
	Audio.play(&"shoot_heavy" if heavy else &"shoot")

	var pellet_offsets := _pellet_offsets(count, spread)
	for i in count:
		var shot_direction := Vector2.RIGHT.rotated(base_angle + pellet_offsets[i])
		var origin := global_position + shot_direction * (body_radius + 14.0)
		if count == 2:
			# 侧移枪口而不是张开角度，让两发保持平行且围绕瞄准线对称。
			var half_gap := maxf(4.0, weapon_stats.get_value(&"projectile_size") * 1.1 * (1.5 if heavy else 1.0))
			origin += shot_direction.orthogonal() * half_gap * (1.0 if i == 0 else -1.0)
		projectile_manager.combat.fire_weapon(origin, shot_direction, weapon_stats,
			color_index, heavy, weapon)

	# 子弹壳：普通射击后有概率立刻连射，下一次间隔压到射速上限对应的间隔。
	if not heavy and Skills.roll_chain_fire():
		_fire_cooldown = 1.0 / maxf(0.1, cap)
	else:
		_fire_cooldown = cooldown
	if heavy:
		global_position -= base_direction * 26.0
		_clamp_to_arena()
		FX.shake(0.16)
		FX.ripple(global_position, 0.45)



func take_damage(amount: float, _source: Node = null) -> void:
	if _invuln > 0.0 or RunState.is_dead:
		return
	if Skills.try_color_shield(_source):
		_invuln = 0.2
		FX.hit_burst(global_position, RunState.current_color(), 48.0, 0.22)
		queue_redraw()
		return
	if Skills.try_guardian_shield():
		_invuln = 0.25
		FX.shockwave(global_position, Color(1.0, 1.0, 1.0, 0.9), 78.0, 0.26, EnergyBurst.STYLE_SPLASH)
		queue_redraw()
		return

	if Skills.roll_dodge():
		_invuln = 0.2
		EventBus.player_dodged.emit()
		FX.text_popup(global_position + Vector2(0.0, -22.0), "闪避", Color(0.75, 0.95, 1.0), 17)
		FX.hit_burst(global_position, Color(1.8, 2.2, 2.6, 1.0), 24.0, 0.2)
		return

	_invuln = 1.0 + Skills.damage_invuln_bonus()
	health = maxf(0.0, health - amount)
	EventBus.player_health_changed.emit(health, max_health)
	EventBus.player_damaged.emit(amount)
	FX.shake(0.32)
	FX.hitstop(0.045)
	FX.shards(global_position, RunState.current_color(), 8)
	_flash_hurt()

	if health <= 0.0:
		_die()
	else:
		_panic_shockwave()


## 受伤反击：近身敌人强制击杀，外圈敌人击退。
func _panic_shockwave() -> void:
	FX.shockwave(global_position, RunState.current_color(), PANIC_PUSH_RADIUS)
	FX.ripple(global_position, 1.0)
	FX.shake(0.18)

	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Enemy):
			continue
		var enemy := node as Enemy
		if enemy.is_dead:
			continue

		var distance := global_position.distance_to(enemy.global_position)
		if distance <= PANIC_KILL_RADIUS:
			enemy.force_kill()
		elif distance <= PANIC_PUSH_RADIUS:
			var falloff := 1.0 - (distance - PANIC_KILL_RADIUS) / maxf(1.0, PANIC_PUSH_RADIUS - PANIC_KILL_RADIUS)
			enemy.apply_knockback(global_position, lerpf(320.0, 1080.0, falloff))


## 技能树/遗物统一入口。PLAYER 侧的 max_health 变化会同步当前生命。
func apply_stat_modifier(modifier: StatModifierResource) -> void:
	if modifier == null:
		return

	match modifier.target:
		StatModifierResource.Target.PLAYER:
			var previous_max := max_health
			stats.add_modifier(modifier)
			max_health = snap_to_half(stats.get_value(&"max_health"))
			if max_health > previous_max:
				health = minf(max_health, health + (max_health - previous_max))
			else:
				health = minf(health, max_health)
			EventBus.player_health_changed.emit(health, max_health)
			refresh_body()
		_:
			weapon.stats.add_modifier(modifier)

	_pulse_visual(1.08)


func remove_modifiers_from(source: StringName) -> void:
	stats.remove_modifiers_from(source)
	weapon.stats.remove_modifiers_from(source)
	max_health = snap_to_half(stats.get_value(&"max_health"))
	health = minf(health, max_health)
	EventBus.player_health_changed.emit(health, max_health)
	refresh_body()


func get_bullet_damage() -> float:
	return weapon.get_final_damage()


func refresh_derived() -> void:
	refresh_body()
	max_health = snap_to_half(stats.get_value(&"max_health"))
	health = minf(health, max_health)
	EventBus.player_health_changed.emit(health, max_health)
	queue_redraw()


## 生命以半颗心为最小刻度，避免百分比上限产生 8.37 这类脏小数。
static func snap_to_half(value: float) -> float:
	return round(value * 2.0) / 2.0


## 回复生命（苹果等）；向上取整到半颗心。
func heal(amount: float) -> void:
	if amount <= 0.0 or RunState.is_dead:
		return
	health = minf(max_health, snap_to_half(health + amount))
	EventBus.player_health_changed.emit(health, max_health)
	queue_redraw()


## 支付生命代价（钝刀片等）：按当前生命的比例扣除，但不会直接扣死。
func pay_health_ratio(ratio: float) -> void:
	if ratio <= 0.0 or RunState.is_dead:
		return
	var loss := health * clampf(ratio, 0.0, 1.0)
	health = maxf(0.5, snap_to_half(health - loss))
	EventBus.player_health_changed.emit(health, max_health)
	queue_redraw()


func pay_health_flat(amount: float) -> void:
	if amount <= 0.0 or RunState.is_dead:
		return
	health = maxf(0.5, snap_to_half(health - amount))
	EventBus.player_health_changed.emit(health, max_health)
	queue_redraw()


## 恶魔祭坛：永久降低生命上限。写入 PLAYER StatBlock（source 唯一），
## 因此之后技能升级触发的 refresh_derived() 不会把代价退回。
## 上限不允许低于 1 颗心；支付成功返回 true。
func pay_max_health(amount: float) -> bool:
	if amount <= 0.0 or RunState.is_dead:
		return false
	if snap_to_half(stats.get_value(&"max_health") - amount) < 1.0:
		return false

	var modifier := StatModifierResource.new()
	modifier.stat = &"max_health"
	modifier.op = StatModifierResource.Op.FLAT
	modifier.value = -amount
	modifier.target = StatModifierResource.Target.PLAYER
	modifier.source = StringName("altar_demon_%d" % _altar_trades)
	_altar_trades += 1
	apply_stat_modifier(modifier)
	return true


func refresh_body() -> void:
	var body_scale := maxf(0.1, stats.get_value(&"body_scale"))
	body_radius = _base_radius * (0.8 if Skills.is_unlocked(&"speed_2") else 1.0) * body_scale
	if _shape != null:
		var circle := _shape.shape as CircleShape2D
		if circle != null:
			circle.radius = body_radius
	queue_redraw()


func _flash_hurt() -> void:
	modulate = Color(2.5, 2.5, 2.5, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.18)


func _die() -> void:
	controls_enabled = false
	_target = null
	_manual_fire_held = false
	_manual_aim_timer = 0.0
	_hold_active = false
	_hold_direction = 0
	_hold_preview_emitted = false
	EventBus.color_switch_preview.emit(false, Vector2.ZERO, 0, 0, 0)
	FX.shards(global_position, RunState.current_color(), 18)
	FX.ripple(global_position, 1.6)
	FX.shake(0.8)
	FX.glow_pulse(1.4, 0.65)
	visible = false
	EventBus.player_died.emit()


func _clamp_to_arena() -> void:
	var bounds := RunState.arena_rect.grow(-body_radius - 6.0)
	# 软墙允许短暂压入边界；最外层只作安全兜底，避免无限离开地图。
	global_position.x = clampf(global_position.x, bounds.position.x - 48.0, bounds.end.x + 48.0)
	global_position.y = clampf(global_position.y, bounds.position.y - 48.0, bounds.end.y + 48.0)


func _apply_soft_wall_resistance() -> void:
	var bounds := RunState.arena_rect.grow(-body_radius - 6.0)
	const WIDTH := 150.0
	for axis in [0, 1]:
		var position_value: float = global_position[axis]
		var direction_value: float = velocity[axis]
		var low: float = bounds.position[axis]
		var high: float = bounds.end[axis]
		if direction_value < 0.0 and position_value < low + WIDTH:
			velocity[axis] *= clampf((position_value - low + 22.0) / WIDTH, 0.0, 1.0)
		elif direction_value > 0.0 and position_value > high - WIDTH:
			velocity[axis] *= clampf((high - position_value + 22.0) / WIDTH, 0.0, 1.0)
		if position_value < low:
			velocity[axis] += (low - position_value) * 12.0
		elif position_value > high:
			velocity[axis] -= (position_value - high) * 12.0


func _on_color_changed(new_color: int) -> void:
	# 从当前正在显示的颜色（可能正处于上一次过渡中）继续向新颜色插值。
	_color_from = _display_color
	color_index = new_color
	_color_to = RunState.color_of(new_color)
	_color_blend = 0.0
	_switch_ring = 0.0
	_switch_ring_color = _color_to
	_switch_flash = 1.0
	queue_redraw()
	if not intro_white:
		_pulse_visual(1.18)
		FX.ripple(global_position, 0.4)


func play_color_reveal() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", Vector2(1.65, 1.65), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	FX.ripple(global_position, 1.2)
	FX.shake(0.28)
	queue_redraw()


func _pulse_visual(strength: float) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", Vector2(strength, strength), 0.06)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var c: Color
	if intro_white:
		c = Color(2.8, 2.8, 2.8, 1.0)
	else:
		c = _display_color

	var alpha := 1.0
	if _invuln > 0.0 and fmod(_invuln, 0.12) < 0.06:
		alpha = 0.35

	# 换色瞬间的白光核心，快速衰减，避免常驻发白。
	if not intro_white and _switch_flash > 0.0:
		draw_circle(
			Vector2.ZERO,
			body_radius * (1.0 + 0.55 * (1.0 - _switch_flash)),
			Color(2.8, 2.8, 2.8, _switch_flash * 0.16 * alpha)
		)

	CharacterVisual.draw_unit(
		self,
		Vector2.ZERO,
		body_radius,
		c,
		_body_style,
		_barrel_style,
		_visual_aim,
		_idle_time,
		_recoil,
		_muzzle,
		alpha
	)
	if Skills.color_shield >= 0:
		var shield_color := RunState.color_of(Skills.color_shield)
		var shield_radius := body_radius + 9.0 + sin(_idle_time * 3.0) * 1.2
		draw_arc(Vector2.ZERO, shield_radius, 0.0, TAU, 32,
			Color(shield_color.r, shield_color.g, shield_color.b, 0.68 * alpha), 2.0, true)

	# 变身光环：新颜色向外扩散，同时三道弧线绕身体旋转淡出。
	if not intro_white and _switch_ring < 1.0:
		var ring_t := _switch_ring
		var ring_color := _switch_ring_color
		var ring_alpha := (1.0 - ring_t) * 0.75 * alpha
		draw_arc(
			Vector2.ZERO,
			body_radius * (1.0 + 1.6 * ring_t),
			0.0,
			TAU,
			48,
			Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha),
			2.0,
			true
		)
		var arc_radius := body_radius + 4.0 + 12.0 * ring_t
		for i in 3:
			var start_angle := TAU * float(i) / 3.0 + ring_t * 4.5
			draw_arc(
				Vector2.ZERO,
				arc_radius,
				start_angle,
				start_angle + 0.55,
				10,
				Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha * 0.8),
				1.8,
				true
			)

	if _manual_aim_timer > 0.0:
		# 手动瞄准期间在炮口前补一小段白线，和自动瞄准区分开。
		var aim := Vector2.from_angle(_visual_aim)
		draw_line(
			aim * (body_radius + 20.0),
			aim * (body_radius + 32.0),
			Color(1.0, 1.0, 1.0, alpha * 0.55),
			1.5,
			true
		)

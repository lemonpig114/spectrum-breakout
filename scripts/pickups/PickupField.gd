class_name PickupField
extends Node2D

## 经验/金币掉落层。
##
## 性能约束（同 FX / ProjectileManager）：
## - 掉落物不创建节点：种类/数量/位置/状态都存在 Packed 数组里，由本节点一个 _draw 绘制。
## - 拾取时借用池化的 Line2D 画“流光”拖尾，不每掉落新建节点或 Tween。
## - 全屏吸取（xp_4 / gold_3）在生成时直接进入收集状态，不产生地面掉落物。
## - 地面掉落有上限；同类型近位置掉落会合并数量，10 秒后扩大就近合并范围。

const KIND_XP := 0
const KIND_GOLD := 1
const KIND_CHEST := 2
const STATE_IDLE := 0
const STATE_COLLECT := 1

## 地面掉落上限、同时模拟的掉落总上限与流光并发上限。
## 超出的流光不画线但仍会飞入结算；总上限超出时直接入账，避免全屏吸取无限堆积。
const MAX_IDLE := 90
const MAX_ITEMS := 200
const MAX_STREAKS := 32

const MAGNET_RADIUS := 88.0
const COLLECT_RADIUS := 15.0
const MERGE_RADIUS := 12.0
const AGED_MERGE_RADIUS := 80.0
const AGED_MERGE_DELAY := 10.0

const MAGNET_START_SPEED := 260.0
const AUTO_START_SPEED := 760.0
const COLLECT_ACCEL := 2600.0
const MAX_COLLECT_SPEED := 2200.0
## 金币比经验慢 25%，让两种掉落的拾取手感有区分。
const GOLD_SPEED_SCALE := 0.75
const STREAK_MIN_LENGTH := 16.0
const STREAK_MAX_LENGTH := 92.0
const STREAK_WIDTH := 3.6

const GOLD_FILL := Color(1.85, 1.2, 0.28, 1.0)
const GOLD_GLOW := Color(2.35, 1.65, 0.45, 1.0)
const XP_FILL := Color(0.28, 1.1, 1.45, 1.0)
const XP_GLOW := Color(0.5, 2.05, 2.35, 1.0)
const CHEST_FILL := Color(1.55, 0.82, 0.22, 1.0)
const CHEST_GLOW := Color(2.4, 1.65, 0.55, 1.0)

var _kind := PackedInt32Array()
var _state := PackedInt32Array()
var _amount := PackedFloat32Array()
var _merged_count := PackedInt32Array()
var _item_pos := PackedVector2Array()
var _phase := PackedFloat32Array()
var _age := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _line_of := PackedInt32Array()

# Line2D 池：索引 i 对应 _lines[i]，_free_lines 里是当前空闲线。
var _lines: Array[Line2D] = []
var _free_lines: PackedInt32Array = PackedInt32Array()
var _gradient_gold: Gradient
var _gradient_xp: Gradient
var _width_curve: Curve

var _player: Player
var _time := 0.0
var _idle_visual_timer := 0.0
var _aged_merge_timer := 0.0
var visual_redraw_step := 0.05
var force_full_detail := false

# 复用的绘制/拖尾缓冲，避免每帧分配 Packed 数组。
var _diamond := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _diamond_outline := PackedVector2Array([
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO
])
var _streak_points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	_build_streak_pool()
	Pickups.attach(self)
	queue_redraw()


func _exit_tree() -> void:
	Pickups.detach(self)


func _process(delta: float) -> void:
	_time += delta
	var player := _player_node()
	var player_alive := player != null and not RunState.is_dead
	# 经验/金币一阶技能会放大磁吸半径，对两种掉落同时生效。
	var magnet_radius := MAGNET_RADIUS * Skills.pickup_radius_multiplier()

	for i in range(_item_pos.size() - 1, -1, -1):
		_age[i] += delta
		if _state[i] == STATE_IDLE:
			if player_alive:
				var distance_sq := _item_pos[i].distance_squared_to(player.global_position)
				if distance_sq <= magnet_radius * magnet_radius:
					_begin_collect(i, MAGNET_START_SPEED)
			continue

		if not player_alive:
			continue

		var target := player.global_position
		var to_target := target - _item_pos[i]
		var distance := to_target.length()
		if distance <= COLLECT_RADIUS:
			_finish(i)
			continue

		var direction := to_target / distance
		var speed_scale := _speed_scale(_kind[i])
		_speed[i] = minf(
			MAX_COLLECT_SPEED * speed_scale,
			_speed[i] + COLLECT_ACCEL * speed_scale * delta
		)
		# 目标本身在移动，玩家速度 + 掉落速度可能让单帧步长跨过收集半径。
		# 若不截断，掉落会在玩家两侧反复越过后又折返，看起来像“抽搐”。
		var step := _speed[i] * delta
		if step >= distance - COLLECT_RADIUS:
			_finish(i)
			continue
		_item_pos[i] += direction * step
		_update_streak(i, direction, target)
	_aged_merge_timer += delta
	if _aged_merge_timer >= 1.0:
		_aged_merge_timer = fmod(_aged_merge_timer, 1.0)
		_merge_aged_neighbours()

	# 地面掉落只轻微上下浮动，20 Hz 足够；收集流光由各自 Line2D 更新。
	# 密集波次 200 个地面物每帧重建绘制命令会成为明显主线程开销。
	if not _item_pos.is_empty() and (_item_pos.size() <= 80 or force_full_detail):
		_idle_visual_timer += delta
		if _idle_visual_timer >= visual_redraw_step:
			_idle_visual_timer = fmod(_idle_visual_timer, visual_redraw_step)
			queue_redraw()


func _draw() -> void:
	var compact := _item_pos.size() > 80 and not force_full_detail
	for i in _item_pos.size():
		if _state[i] != STATE_IDLE:
			continue

		var center := _item_pos[i] if compact else _item_pos[i] + Vector2(0.0, sin(_time * 2.6 + _phase[i]) * 1.5)
		var pulse := 0.5 if compact else 0.5 + 0.5 * sin(_time * 3.4 + _phase[i] * 1.7)
		var size_scale := 1.0 + minf(1.3, 0.27 * sqrt(float(maxi(0, _merged_count[i] - 1))))

		if _kind[i] == KIND_CHEST:
			var half := Vector2(6.4, 4.8)
			draw_rect(
				Rect2(center - half, half * 2.0),
				Color(CHEST_FILL.r, CHEST_FILL.g, CHEST_FILL.b, 0.9)
			)
			draw_rect(
				Rect2(center - half, half * 2.0),
				Color(CHEST_GLOW.r, CHEST_GLOW.g, CHEST_GLOW.b, 0.9),
				false,
				1.4
			)
			draw_rect(
				Rect2(center + Vector2(-1.3, -half.y - 1.0), Vector2(2.6, 3.0)),
				Color(0.35, 0.18, 0.05, 1.0)
			)
			draw_circle(center + Vector2(0.0, 0.8), 1.2, Color(2.8, 2.4, 1.5, 1.0))
			draw_arc(
				center,
				9.0 + pulse * 2.0,
				0.0,
				TAU,
				20,
				Color(CHEST_GLOW.r, CHEST_GLOW.g, CHEST_GLOW.b, 0.25 + 0.3 * pulse),
				1.0,
				true
			)
		elif _kind[i] == KIND_GOLD:
			draw_circle(center, 3.4 * size_scale, GOLD_FILL)
			if not compact:
				draw_circle(
				center,
				(5.0 + pulse * 1.4) * size_scale,
				Color(GOLD_GLOW.r, GOLD_GLOW.g, GOLD_GLOW.b, 0.2 + 0.35 * pulse),
				false,
				1.0
				)
		else:
			var radius := 3.6 * size_scale
			_diamond[0] = center + Vector2(0.0, -radius)
			_diamond[1] = center + Vector2(radius, 0.0)
			_diamond[2] = center + Vector2(0.0, radius)
			_diamond[3] = center + Vector2(-radius, 0.0)
			_diamond_outline[0] = _diamond[0]
			_diamond_outline[1] = _diamond[1]
			_diamond_outline[2] = _diamond[2]
			_diamond_outline[3] = _diamond[3]
			_diamond_outline[4] = _diamond[0]
			draw_colored_polygon(_diamond, XP_FILL)
			if not compact:
				draw_polyline(_diamond_outline, XP_GLOW, 1.3, false)
				draw_circle(center, 1.1, Color(2.0, 2.6, 2.9, 0.85))


# ── 生成 ────────────────────────────────────────────────────────

func spawn_gold(world_position: Vector2, amount: int) -> void:
	_spawn(KIND_GOLD, world_position, amount, Skills.gold_auto_collect())


func spawn_xp(world_position: Vector2, amount: float) -> void:
	_spawn(KIND_XP, world_position, amount, Skills.xp_auto_collect())


## 宝箱由幸运线掉落；不参与金币/经验的自动吸取，靠近磁吸后由 Skills.open_chest 结算。
func spawn_chest(world_position: Vector2) -> void:
	_spawn(KIND_CHEST, world_position, 1, false)


## 商人吸附：把场上所有地面经验/金币一次性转为高速收集状态，宝箱留在原地。
## 返回被吸走的数量；已经在飞行中的掉落不重复计数。
func vacuum_all() -> int:
	var moved := 0
	for i in _state.size():
		if _state[i] != STATE_IDLE or _kind[i] == KIND_CHEST:
			continue
		_begin_collect(i, MAX_COLLECT_SPEED)
		moved += 1
	if moved > 0:
		queue_redraw()
	return moved


## 场上剩余的经验/金币数量（含飞行中）。商人的“吸完再进店”用它判断，
## 宝箱不参与，避免因为一个没开的箱子卡住商店。
func currency_count() -> int:
	var count := 0
	for i in _kind.size():
		if _kind[i] != KIND_CHEST:
			count += 1
	return count


func _spawn(kind: int, world_position: Vector2, amount: float, auto_collect: bool) -> void:
	if amount <= 0:
		return

	if auto_collect:
		# 自动吸取技能等同于已经拾取；场上对象已满时直接结算。
		if kind != KIND_CHEST and _item_pos.size() >= MAX_ITEMS:
			_credit(kind, amount)
			return
		_append_item(kind, world_position, amount, AUTO_START_SPEED)
		return

	# 同类型、同位置的掉落直接合并数量，压低对象数与绘制调用。
	# 宝箱每个都是独立奖励，不能合并。
	if kind != KIND_CHEST:
		for i in _item_pos.size():
			if _state[i] != STATE_IDLE or _kind[i] != kind:
				continue
			if _item_pos[i].distance_squared_to(world_position) <= MERGE_RADIUS * MERGE_RADIUS:
				_amount[i] += amount
				_merged_count[i] += 1
				queue_redraw()
				return

	# 普通地面掉落必须真正被拾取才结算；超出总量时先丢弃旧货币。
	if kind != KIND_CHEST and _item_pos.size() >= MAX_ITEMS:
		if not _discard_oldest_idle():
			return

	if kind != KIND_CHEST and idle_count() >= MAX_IDLE:
		if not _discard_oldest_idle():
			return

	_append_item(kind, world_position, amount, 0.0)


func _append_item(kind: int, world_position: Vector2, amount: float, start_speed: float) -> void:
	_kind.append(kind)
	_state.append(STATE_IDLE)
	_amount.append(amount)
	_merged_count.append(1)
	_item_pos.append(world_position)
	_phase.append(RunState.rng.randf() * TAU)
	_age.append(0.0)
	_speed.append(0.0)
	_line_of.append(-1)

	if start_speed > 0.0:
		_begin_collect(_item_pos.size() - 1, start_speed)
	queue_redraw()


## 老掉落每秒尝试一次就近归堆；只合并同类地面货币，不提前发放奖励。
func _merge_aged_neighbours() -> void:
	var i := 0
	while i < _item_pos.size():
		if _state[i] != STATE_IDLE or _kind[i] == KIND_CHEST or _age[i] < AGED_MERGE_DELAY:
			i += 1
			continue
		var nearest := -1
		var best_distance := AGED_MERGE_RADIUS * AGED_MERGE_RADIUS
		for j in _item_pos.size():
			if j == i or _state[j] != STATE_IDLE or _kind[j] != _kind[i] or _age[j] < AGED_MERGE_DELAY:
				continue
			var distance := _item_pos[i].distance_squared_to(_item_pos[j])
			if distance < best_distance:
				best_distance = distance
				nearest = j
		if nearest < 0:
			i += 1
			continue
		_amount[nearest] += _amount[i]
		_merged_count[nearest] += _merged_count[i]
		_age[nearest] = maxf(_age[nearest], _age[i])
		_remove_item(i)


## 场地满时移除最老的未拾取货币；丢失奖励不结算，宝箱始终保留。
func _discard_oldest_idle() -> bool:
	var oldest := -1
	var oldest_age := -1.0
	for i in _state.size():
		if _state[i] != STATE_IDLE or _kind[i] == KIND_CHEST:
			continue
		if _age[i] > oldest_age:
			oldest_age = _age[i]
			oldest = i
	if oldest >= 0:
		_remove_item(oldest)
		return true
	return false


# ── 收集与流光 ──────────────────────────────────────────────────

func _begin_collect(index: int, start_speed: float) -> void:
	if _state[index] == STATE_COLLECT:
		return
	_state[index] = STATE_COLLECT
	_speed[index] = start_speed * _speed_scale(_kind[index])

	var line_index := _acquire_line()
	_line_of[index] = line_index
	if line_index < 0:
		return

	var line := _lines[line_index]
	line.gradient = _gradient_xp if _kind[index] == KIND_XP else _gradient_gold
	line.visible = true
	_update_streak(index, Vector2.ZERO, _player_position())


func _update_streak(index: int, direction: Vector2, target: Vector2) -> void:
	var line_index := _line_of[index]
	if line_index < 0:
		return

	var head := _item_pos[index]
	if direction.length_squared() < 0.0001:
		direction = (target - head).normalized()
	if direction.length_squared() < 0.0001:
		# 掉落与玩家完全重合时不要保留上一条流光的位置，否则会闪一下旧拖尾。
		_lines[line_index].points = PackedVector2Array([head, head])
		return

	var trail_length := clampf(_speed[index] * 0.04, STREAK_MIN_LENGTH, STREAK_MAX_LENGTH)
	var perpendicular := Vector2(-direction.y, direction.x)
	var wobble := sin(_time * 14.0 + _phase[index] * 6.0) * trail_length * 0.10

	_streak_points[0] = head
	_streak_points[1] = head - direction * trail_length * 0.55 + perpendicular * wobble
	_streak_points[2] = head - direction * trail_length
	_lines[line_index].points = _streak_points


func _finish(index: int) -> void:
	if _kind[index] == KIND_CHEST:
		# 开箱音在 Skills.open_chest() 内统一播放，避免两条入口重复。
		Skills.open_chest(_item_pos[index])
	else:
		Audio.play(&"gold" if _kind[index] == KIND_GOLD else &"xp")
		_credit(_kind[index], _amount[index])
	_release_line(_line_of[index])
	_remove_item(index)


func _credit(kind: int, amount: float) -> void:
	if kind == KIND_GOLD:
		RunState.add_gold(int(round(amount)))
	elif kind == KIND_XP:
		RunState.add_xp(amount)


func _remove_item(index: int) -> void:
	var last := _item_pos.size() - 1
	if index != last:
		_kind[index] = _kind[last]
		_state[index] = _state[last]
		_amount[index] = _amount[last]
		_merged_count[index] = _merged_count[last]
		_item_pos[index] = _item_pos[last]
		_phase[index] = _phase[last]
		_age[index] = _age[last]
		_speed[index] = _speed[last]
		_line_of[index] = _line_of[last]

	_kind.remove_at(last)
	_state.remove_at(last)
	_amount.remove_at(last)
	_merged_count.remove_at(last)
	_item_pos.remove_at(last)
	_phase.remove_at(last)
	_age.remove_at(last)
	_speed.remove_at(last)
	_line_of.remove_at(last)
	queue_redraw()


# ── Line2D 池 ───────────────────────────────────────────────────

func _build_streak_pool() -> void:
	# 流光头端保持满宽、尾端收成尖，避免头端太细看起来像断开的短线。
	_width_curve = Curve.new()
	_width_curve.add_point(Vector2(0.0, 1.0))
	_width_curve.add_point(Vector2(0.3, 0.8))
	_width_curve.add_point(Vector2(1.0, 0.0))
	# 流光头端必须与地面掉落的填充色一致（金币金、经验青）。
	_gradient_gold = _make_gradient(GOLD_FILL)
	_gradient_xp = _make_gradient(XP_FILL)

	_free_lines.resize(MAX_STREAKS)
	for i in MAX_STREAKS:
		var line := Line2D.new()
		line.width = STREAK_WIDTH
		line.width_curve = _width_curve
		line.gradient = _gradient_xp
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.antialiased = false
		line.z_index = 2
		line.visible = false
		add_child(line)
		_lines.append(line)
		_free_lines[i] = i


func _make_gradient(head: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(head.r, head.g, head.b, 1.0),
		Color(head.r * 0.85, head.g * 0.85, head.b * 0.85, 0.6),
		Color(head.r * 0.7, head.g * 0.7, head.b * 0.7, 0.0),
	])
	return gradient


func _acquire_line() -> int:
	if _free_lines.is_empty():
		return -1
	var line_index := _free_lines[_free_lines.size() - 1]
	_free_lines.resize(_free_lines.size() - 1)
	return line_index


func _release_line(line_index: int) -> void:
	if line_index < 0 or line_index >= _lines.size():
		return
	_lines[line_index].visible = false
	_free_lines.append(line_index)


# ── 查询 / 清理 ─────────────────────────────────────────────────

func _speed_scale(kind: int) -> float:
	if kind == KIND_GOLD:
		return GOLD_SPEED_SCALE
	if kind == KIND_CHEST:
		return 0.9
	return 1.0


func _player_node() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group(&"player") as Player
	return _player


func _player_position() -> Vector2:
	var player := _player_node()
	return player.global_position if player != null else global_position


func idle_count() -> int:
	var count := 0
	for state in _state:
		if state == STATE_IDLE:
			count += 1
	return count


func collecting_count() -> int:
	return _state.size() - idle_count()


func total_count() -> int:
	return _state.size()


func active_streak_count() -> int:
	return _lines.size() - _free_lines.size()


func clear() -> void:
	for line in _lines:
		line.visible = false
	_free_lines.resize(MAX_STREAKS)
	for i in MAX_STREAKS:
		_free_lines[i] = i

	_kind.clear()
	_state.clear()
	_amount.clear()
	_item_pos.clear()
	_phase.clear()
	_age.clear()
	_merged_count.clear()
	_speed.clear()
	_line_of.clear()
	queue_redraw()

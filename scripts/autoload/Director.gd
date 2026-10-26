extends Node

## 前六分钟按时间阶段刷怪；300–360 秒为六边形围剿。
## 商店等“可发现事件”后续也挂在这里。

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/square_boss.tscn")
const MAX_ENEMIES := 80
const MIN_PACK_SIZE := 3
const MAX_PACK_SIZE := 5
## 120–180 秒改为包围式刷新：不再五只成簇，按黄金角绕玩家推进，颜色各自独立。
const SURROUND_PHASE := 3
const HEX_SURROUND_PHASE := 7
const SURROUND_STEP := 2.399963
const SURROUND_MIN_DISTANCE := 620.0
const SURROUND_MAX_DISTANCE := 840.0
## 商人：1:20 必定出现第一只，之后约每 90 秒出现一只。
## 隐藏机制：一次到访买空整排货架，下一只商人提前 10 秒（每次商店最多一次）。
const MERCHANT_FIRST_DELAY := 80.0
const MERCHANT_INTERVAL := 90.0
const SHELF_CLEAR_BONUS := 10.0
## 祭坛：契约 3 阶解锁后开始计时；同时在场的祭坛只有一座。
const ALTAR_FIRST_DELAY := 40.0
const ALTAR_INTERVAL := 90.0

var world: Node2D
var player: Node2D
var merchant: Merchant
var altar: Altar
var boss: SquareBoss

var _spawning := false
var _spawn_timer := 0.8
var _phase_index := -1
var _phase_spawn_index := 0
var _pack_color := ColorType.RED
var _pack_anchor := Vector2.ZERO
var _pack_remaining := 0
var _ring_angle := 0.0
var _merchant_timer := MERCHANT_FIRST_DELAY
var _altar_timer := ALTAR_FIRST_DELAY
var _rng := RandomNumberGenerator.new()
var _enemy_types: Array[EnemyTypeResource] = []
var _boss_spawned := false


func setup(world_node: Node2D) -> void:
	world = world_node
	player = get_tree().get_first_node_in_group("player")
	merchant = null
	altar = null
	boss = null
	_boss_spawned = false
	_spawning = false
	_spawn_timer = 0.8
	_phase_index = -1
	_phase_spawn_index = 0
	_pack_remaining = 0
	_ring_angle = 0.0
	_merchant_timer = MERCHANT_FIRST_DELAY
	_altar_timer = ALTAR_FIRST_DELAY
	_rng.randomize()

	_enemy_types = ContentDB.get_enemies()
	_enemy_types.sort_custom(func(a, b): return a.unlock_time < b.unlock_time)


func start() -> void:
	_spawning = true
	_spawn_timer = 0.8


func stop() -> void:
	_spawning = false


func _process(delta: float) -> void:
	if not _spawning or not RunState.is_running:
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	var phase := spawn_phase()
	if phase != _phase_index:
		_phase_index = phase
		_phase_spawn_index = 0
		_pack_remaining = 0
		_spawn_timer = minf(_spawn_timer, _spawn_interval(phase))
	_spawn_timer -= delta
	while _spawn_timer <= 0.0:
		for _i in _spawn_batch_size(phase):
			_spawn_phase_enemy(phase)
		_spawn_timer += _spawn_interval(phase)
	if phase >= 4 and boss == null and not _boss_spawned:
		spawn_boss_now()

	_update_merchant(delta)
	_update_altar(delta)


## 祭坛计时：必须先选择契约并点出 3 阶；未解锁时计时器保持初始值。
## 场上有祭坛时暂停倒计时，离开后从 ALTAR_INTERVAL 重新开始。
func _update_altar(delta: float) -> void:
	if Skills.altar_side() == &"":
		_altar_timer = ALTAR_FIRST_DELAY
		return
	if altar != null and is_instance_valid(altar):
		return
	altar = null

	_altar_timer = maxf(0.0, _altar_timer - delta)
	if _altar_timer <= 0.0:
		spawn_altar_now()


## 测试/调试入口：在没有 3 阶时返回 null，不会凭空生成祭坛。
func spawn_altar_now(position_override: Vector2 = Vector2.INF) -> Altar:
	if world == null:
		return null
	var side := Skills.altar_side()
	if side == &"":
		return null
	if altar != null and is_instance_valid(altar):
		return altar
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return null

	var node := Altar.new()
	node.setup(player as Player, side)
	node.position = _altar_position() if position_override == Vector2.INF else position_override
	world.add_child(node)
	altar = node
	_altar_timer = ALTAR_INTERVAL
	EventBus.altar_spawned.emit(node)
	return node


func _altar_position() -> Vector2:
	var center := player.global_position
	var bounds := RunState.arena_rect.grow(-90.0)
	for attempt in 10:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(320.0, 520.0)
		var candidate := center + Vector2(cos(angle), sin(angle)) * distance
		candidate.x = clampf(candidate.x, bounds.position.x, bounds.end.x)
		candidate.y = clampf(candidate.y, bounds.position.y, bounds.end.y)
		if candidate.distance_to(center) >= 260.0:
			return candidate
	return center + Vector2(360.0, 0.0)


## 商人计时：出生后按 Skills.merchant_interval() 排下一只（基础 90 秒）。
## 提前买完离开也不会让下一只提前出现，节奏可预期。
func _update_merchant(delta: float) -> void:
	_merchant_timer = maxf(0.0, _merchant_timer - delta)
	if merchant != null and is_instance_valid(merchant):
		return
	merchant = null
	if _merchant_timer <= 0.0:
		spawn_merchant_now()


## 测试/调试也可以直接叫出商人；position_override 为 INF 时自动选在场外。
func spawn_merchant_now(position_override: Vector2 = Vector2.INF) -> Merchant:
	if world == null:
		return null
	if merchant != null and is_instance_valid(merchant):
		return merchant
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return null

	merchant = Merchant.new()
	merchant.setup(player)
	merchant.position = (
		_merchant_position() if position_override == Vector2.INF else position_override
	)
	world.add_child(merchant)
	_merchant_timer = Skills.merchant_interval()
	EventBus.merchant_spawned.emit(merchant)
	return merchant


## 买空货架的隐藏奖励：只提前“下一次”商人的倒计时，不改变基础间隔。
## 当前商人还在场时也安全，倒计时归零后会等它离场再刷。
func shorten_next_merchant(seconds: float) -> void:
	_merchant_timer = maxf(0.0, _merchant_timer - maxf(0.0, seconds))


func _merchant_position() -> Vector2:
	var center := player.global_position
	var bounds := RunState.arena_rect.grow(-90.0)

	# 尽量刷在玩家视野外，让 HUD 的方向箭头有存在感；太靠近场地边缘时夹回场内。
	for attempt in 10:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(700.0, 920.0)
		var candidate := center + Vector2(cos(angle), sin(angle)) * distance
		candidate.x = clampf(candidate.x, bounds.position.x, bounds.end.x)
		candidate.y = clampf(candidate.y, bounds.position.y, bounds.end.y)
		if candidate.distance_to(center) >= 560.0:
			return candidate

	return center + Vector2(620.0, -420.0)


func spawn_phase(at_time: float = -1.0) -> int:
	var seconds := RunState.elapsed if at_time < 0.0 else at_time
	if seconds < 30.0:
		return 0
	if seconds < 60.0:
		return 1
	if seconds < 120.0:
		return 2
	if seconds < 180.0:
		return 3
	if seconds < 240.0:
		return 4
	if seconds < 270.0:
		return 5
	if seconds < 300.0:
		return 6
	if seconds < 360.0:
		return 7
	return 8


func spawn_rate(at_time: float = -1.0) -> float:
	return _phase_rate(spawn_phase(at_time)) * Skills.spawn_rate_multiplier()


func _phase_rate(phase: int) -> float:
	match phase:
		0: return 3.0
		1: return 4.0
		2: return 6.0
		3: return 13.0
		4: return 6.0
		5: return 8.0
		6: return 12.0
		7: return 6.0
		_: return 8.0


func _spawn_batch_size(phase: int) -> int:
	return 13 if phase == 3 else 1


func _spawn_interval(phase: int) -> float:
	return float(_spawn_batch_size(phase)) / (_phase_rate(phase) * Skills.spawn_rate_multiplier())


func _phase_type(phase: int, index: int) -> EnemyTypeResource:
	var wanted: StringName
	match phase:
		1, 2: wanted = &"chaser_square" if index % 5 == 4 else &"chaser_triangle"
		4: wanted = &"chaser_square"
		5: wanted = &"ranged_plane" if index % 8 < 3 else &"chaser_square"
		6:
			var cycle := index % 12
			wanted = &"ranged_plane" if cycle < 2 else (&"chaser_square" if cycle < 6 else (&"chaser_triangle" if cycle < 10 else &"chaser_round"))
		7: wanted = &"chaser_hex"
		8: wanted = [&"chaser_round", &"ranged_plane", &"chaser_square"][index % 3]
		_: wanted = &"chaser_triangle"
	for enemy_type in _enemy_types:
		if enemy_type.id == wanted:
			return enemy_type
	return null


func _spawn_phase_enemy(phase: int) -> void:
	var enemy_type := _phase_type(phase, _phase_spawn_index)
	# 包围阶段每只单独上色、直接落在环上，不进同色簇。
	if phase == SURROUND_PHASE or phase == HEX_SURROUND_PHASE:
		_phase_spawn_index += 1
		_spawn_enemy(enemy_type, _rng.randi_range(0, ColorType.COUNT - 1), _surround_position(), true)
		return
	# 飞机单独出现；同一循环中的五只方形共享颜色和较松散的出生区域。
	if phase == 5:
		var index := _phase_spawn_index % 8
		_phase_spawn_index += 1
		if index < 3:
			_spawn_enemy(enemy_type, _rng.randi_range(0, ColorType.COUNT - 1), _spawn_position(), true)
		else:
			if index == 3:
				_pack_color = _rng.randi_range(0, ColorType.COUNT - 1)
				_pack_anchor = _spawn_position()
			_spawn_enemy(enemy_type, _pack_color, _pack_anchor)
		return
	if _pack_remaining <= 0:
		_pack_color = _rng.randi_range(0, ColorType.COUNT - 1)
		_pack_anchor = _spawn_position()
		_pack_remaining = _rng.randi_range(MIN_PACK_SIZE, MAX_PACK_SIZE)
	_phase_spawn_index += 1
	_pack_remaining -= 1
	_spawn_enemy(enemy_type, _pack_color, _pack_anchor)


func _pick_type() -> EnemyTypeResource:
	var unlocked: Array[EnemyTypeResource] = []
	var total_weight := 0.0
	for enemy_type in _enemy_types:
		if enemy_type.spawn_weight > 0.0 and RunState.elapsed >= enemy_type.unlock_time:
			unlocked.append(enemy_type)
			total_weight += enemy_type.spawn_weight

	if unlocked.is_empty() or total_weight <= 0.0:
		return null

	var roll := _rng.randf() * total_weight
	for enemy_type in unlocked:
		if roll <= enemy_type.spawn_weight:
			return enemy_type
		roll -= enemy_type.spawn_weight

	return unlocked.back()


func _spawn_enemy(enemy_type: EnemyTypeResource, enemy_color: int = -1, anchor: Vector2 = Vector2.INF, exact := false) -> void:
	if enemy_type == null or world == null:
		return
	if _enemy_count() >= enemy_limit():
		return

	var enemy := ENEMY_SCENE.instantiate()
	enemy.configure(enemy_type, player, enemy_color if enemy_color >= 0 else _rng.randi_range(0, ColorType.COUNT - 1))
	enemy.max_health *= health_multiplier()
	enemy.health = enemy.max_health
	if anchor == Vector2.INF:
		enemy.position = _spawn_position()
	elif exact:
		enemy.position = anchor
	else:
		enemy.position = _cluster_position(anchor)
	world.add_child(enemy)


func spawn_boss_now(position_override: Vector2 = Vector2.INF) -> SquareBoss:
	if _boss_spawned or world == null or player == null or not is_instance_valid(player):
		return boss
	var boss_type := ContentDB.get_enemy(&"square_boss")
	if boss_type == null:
		return null
	boss = BOSS_SCENE.instantiate() as SquareBoss
	boss.configure(boss_type, player, _rng.randi_range(0, ColorType.COUNT - 1))
	boss.max_health *= health_multiplier(180.0)
	boss.health = boss.max_health
	boss.position = _boss_position() if position_override == Vector2.INF else position_override
	world.add_child(boss)
	_boss_spawned = true
	FX.shards(boss.global_position, RunState.color_of(boss.color_index), 18)
	return boss


func _boss_position() -> Vector2:
	var bounds := RunState.arena_rect.grow(-90.0)
	var angle := _rng.randf() * TAU
	var point := player.global_position + Vector2.from_angle(angle) * 490.0
	return Vector2(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y)
	)


## 包围阶段：黄金角推进 + 少量抖动，连续刷新会自然铺满玩家四周。
## 玩家贴边时夹取可能把点拉近，过近就退回常规的随机远点。
func _surround_position() -> Vector2:
	_ring_angle = fmod(_ring_angle + SURROUND_STEP, TAU)
	var angle := _ring_angle + _rng.randf_range(-0.35, 0.35)
	var distance := _rng.randf_range(SURROUND_MIN_DISTANCE, SURROUND_MAX_DISTANCE)
	var center := player.global_position
	var bounds := RunState.arena_rect.grow(-60.0)
	var point := center + Vector2(cos(angle), sin(angle)) * distance
	point.x = clampf(point.x, bounds.position.x, bounds.end.x)
	point.y = clampf(point.y, bounds.position.y, bounds.end.y)
	if point.distance_to(center) < 380.0:
		return _spawn_position()
	return point


func _cluster_position(anchor: Vector2) -> Vector2:
	var offset := Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(32.0, 122.0)
	var bounds := RunState.arena_rect.grow(-60.0)
	return Vector2(
		clampf(anchor.x + offset.x, bounds.position.x, bounds.end.x),
		clampf(anchor.y + offset.y, bounds.position.y, bounds.end.y)
	)


func _spawn_ring(count: int) -> void:
	if player == null or not is_instance_valid(player):
		return

	var start_angle := _rng.randf() * TAU
	for i in count:
		var enemy_type := _pick_type()
		if enemy_type == null or _enemy_count() >= enemy_limit():
			return
		var angle := start_angle + TAU * float(i) / float(count)
		var spawn_position := player.global_position + Vector2(cos(angle), sin(angle)) * 720.0
		var bounds := RunState.arena_rect.grow(-60.0)
		spawn_position.x = clampf(spawn_position.x, bounds.position.x, bounds.end.x)
		spawn_position.y = clampf(spawn_position.y, bounds.position.y, bounds.end.y)

		var enemy := ENEMY_SCENE.instantiate()
		enemy.configure(enemy_type, player, _rng.randi_range(0, ColorType.COUNT - 1))
		enemy.max_health *= health_multiplier()
		enemy.health = enemy.max_health
		enemy.position = spawn_position
		world.add_child(enemy)


func _spawn_position() -> Vector2:
	var center := player.global_position
	var bounds := RunState.arena_rect.grow(-60.0)

	for attempt in 8:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(620.0, 860.0)
		var spawn_position := center + Vector2(cos(angle), sin(angle)) * distance
		spawn_position.x = clampf(spawn_position.x, bounds.position.x, bounds.end.x)
		spawn_position.y = clampf(spawn_position.y, bounds.position.y, bounds.end.y)
		if spawn_position.distance_to(center) >= 380.0:
			return spawn_position

	return center


func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


## 高压阶段也保留硬上限，避免后期长时间未清怪时无限堆积。
func enemy_limit(at_time: float = -1.0) -> int:
	var seconds := RunState.elapsed if at_time < 0.0 else at_time
	if spawn_phase(at_time) == SURROUND_PHASE:
		return 100
	return mini(MAX_ENEMIES, 40 + int(maxf(0.0, seconds) / 30.0) * 5)


func health_multiplier(at_time: float = -1.0) -> float:
	var seconds := RunState.elapsed if at_time < 0.0 else at_time
	if seconds < 15.0:
		return 0.8
	match spawn_phase(at_time):
		0, 1: return 1.0
		2: return 1.5
		3: return 2.0
		4: return 2.5
		5: return 3.5
		6: return 5.0
		7: return 6.0
		_: return 6.0


func enemy_damage_multiplier(at_time: float = -1.0) -> float:
	return 2.0 if spawn_phase(at_time) >= 5 else 1.0

class_name EnemyFlock
extends RefCounted

## 仅做鸟群算法的“分离”：敌人仍用手动积分，碰撞层保留给子弹。
## 每两个物理帧从存活敌人构建一次 64px 空间网格；单只只看相邻九格。
const CELL_SIZE := 64.0
const GAP := 4.0
## 分离力的原始强度。真正导致抽搐的是方向每两帧整帧翻转、以及位置修正被
## 重复施加；现在由 Enemy 对方向做低通、修正按每帧减半，强度仍保留以便撑开人堆。
const PUSH_STRENGTH := 5.0
const MAX_NEIGHBORS := 20
## 网格每两帧刷新一次，位置修正也缓存两帧；每帧只承担一半，避免重复推过头。
const CORRECTION_PER_FRAME := 0.5
const NEIGHBOR_OFFSETS := [
	Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]
## 压测时可关闭分离，量化其成本；正常游戏始终为 true。
static var enabled := true

static var _frame := -1
static var _cells: Dictionary = {}
static var _corrections: Dictionary = {}
static var _steerings: Dictionary = {}




static func separation(enemy: Enemy) -> Vector2:
	_ensure_grid(enemy)
	var id := enemy.get_instance_id()
	if _steerings.has(id):
		return _steerings[id]
	var center := _cell(enemy.global_position)
	var push := Vector2.ZERO
	var correction := Vector2.ZERO
	var examined := 0
	var own_position := enemy.global_position
	var own_radius := enemy.radius
	for offset in NEIGHBOR_OFFSETS:
		var neighbours: Array = _cells.get(center + offset, [])
		if neighbours.is_empty():
			continue
		# 从不同下标开始，避免拥挤时所有敌人只参照同一批靠前出生的怪。
		var start := int(id % neighbours.size())
		for step in mini(neighbours.size(), MAX_NEIGHBORS - examined):
			examined += 1
			# 必须先校验再转换：敌人可能在两次网格刷新之间被 queue_free，
			# 对已释放实例做 `as Enemy` 会直接抛出“Trying to cast a freed object.”
			# 并中断本次物理帧，Boss 召唤物裁剪时最容易触发。
			var candidate: Variant = neighbours[(start + step) % neighbours.size()]
			if not is_instance_valid(candidate):
				continue
			var other := candidate as Enemy
			if other == null or other == enemy or other.is_dead:
				continue
			var away := own_position - other.global_position
			var minimum := own_radius + other.radius + GAP
			var distance_squared := away.length_squared()
			if distance_squared >= minimum * minimum:
				continue
			if distance_squared < 0.001:
				# 完全重合也要有稳定且成对相反的方向。
				var first := mini(id, other.get_instance_id())
				var second := maxi(id, other.get_instance_id())
				var angle := float((first * 31 + second * 17) % 360) * PI / 180.0
				away = Vector2.from_angle(angle if id == first else angle + PI)
				push += away
				correction += away * minimum * 0.5
			else:
				var distance := sqrt(distance_squared)
				push += away / distance * (1.0 - distance / minimum)
				correction += away / distance * (minimum - distance) * 0.5
		if examined >= MAX_NEIGHBORS:
			break
	_corrections[id] = correction.limit_length(4.0)
	var steering := push.limit_length(1.0) * PUSH_STRENGTH
	_steerings[id] = steering
	return steering


static func _ensure_grid(enemy: Enemy) -> void:
	var frame := Engine.get_physics_frames()
	# 30Hz 更新邻居关系与分离力；60Hz 仍逐帧追逐与移动。
	# 超过两帧未刷新（换场景、重开一局）时无条件重建，避免继续引用上一局的对象。
	if _frame < 0 or (frame % 2 == 0 and _frame != frame) or frame - _frame > 2:
		_rebuild(enemy.get_tree())
		_frame = frame


## 软位置修正：追逐的径向速度再大，也不应把多只敌人压在同一像素。
## 每对最多各承担约一半穿插深度；每两帧合计封顶 4px，再分摊到两帧，避免突然弹跳。
static func correction(enemy: Enemy) -> Vector2:
	_ensure_grid(enemy)
	var value: Vector2 = _corrections.get(enemy.get_instance_id(), Vector2.ZERO)
	return value * CORRECTION_PER_FRAME




static func _rebuild(tree: SceneTree) -> void:
	_cells.clear()
	_corrections.clear()
	_steerings.clear()
	for node in tree.get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead:
			continue
		var key := _cell(enemy.global_position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(enemy)


static func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))

class_name ProjectileManager
extends Node2D

## 弹幕接口层：Player 只调用 fire()，内部以后可以换成 MultiMesh + 手动模拟，
## 而不影响武器/技能/遗物的代码。

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")
const MAX_POOL := 512
const PREWARM_COUNT := 64

var _pool: Array[Projectile] = []
var _active: Array[Projectile] = []


func _ready() -> void:
	# 预先创建子弹节点，避免第一次开火时的实例化/碰撞体构建尖峰。
	for i in PREWARM_COUNT:
		_pool.append(_create_pooled())


func _create_pooled() -> Projectile:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	add_child(projectile)
	projectile.visible = false
	projectile.collision_mask = 0
	projectile.set_physics_process(false)
	return projectile


func fire(
	origin: Vector2,
	direction: Vector2,
	stats: StatBlock,
	color_index: int,
	core: WeaponCoreResource,
	heavy: bool = false,
	damage_scale: float = 1.0,
	size_scale: float = 1.0,
	speed_scale: float = 1.0,
	lifetime_scale: float = 1.0,
	allow_crit: bool = true,
	source_kind: StringName = &""
) -> void:
	var projectile: Projectile = null

	while not _pool.is_empty():
		var candidate: Projectile = _pool.pop_back()
		if is_instance_valid(candidate):
			projectile = candidate
			break

	if projectile == null:
		projectile = PROJECTILE_SCENE.instantiate()
		add_child(projectile)
	elif projectile.get_parent() == null:
		add_child(projectile)

	projectile.setup(
		self, origin, direction, stats, color_index, core, heavy, damage_scale, size_scale,
		speed_scale, lifetime_scale, allow_crit, source_kind
	)
	_active.append(projectile)


func release(projectile: Projectile) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return

	var index := _active.find(projectile)
	if index >= 0:
		_active.remove_at(index)

	projectile.visible = false
	projectile.collision_mask = 0
	projectile.set_physics_process(false)

	if _pool.size() < MAX_POOL:
		_pool.append(projectile)
	else:
		projectile.queue_free()

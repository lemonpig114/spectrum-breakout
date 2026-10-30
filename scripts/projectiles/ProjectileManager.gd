class_name ProjectileManager
extends Node2D

## 弹幕接口层：Player 只调用 fire()，内部以后可以换成 MultiMesh + 手动模拟，
## 而不影响武器/技能/遗物的代码。

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")
const BATCH_RENDERER := preload("res://scripts/projectiles/ProjectileBatchRenderer.gd")
const WEAPON_COMBAT := preload("res://scripts/weapon/WeaponCombat.gd")
const MAX_POOL := 512
const PREWARM_COUNT := 64
const MAX_DERIVED_ACTIVE := 32
const MAX_SPRITE_TRAILS := 24

var _pool: Array[Projectile] = []
var _active: Array[Projectile] = []
var batch_renderer: ProjectileBatchRenderer
var batch_enabled := true
var combat: WeaponCombat
var derived_active := 0
var active_sprite_trails := 0
var _guidance_frame := -100
var _guidance_enemies: Array = []
var _guidance_cache := {}



func guidance_target(origin: Vector2, reach: float, excluded: Dictionary) -> Enemy:
	var frame := Engine.get_physics_frames()
	if frame < _guidance_frame or frame - _guidance_frame >= 6:
		_guidance_frame = frame
		_guidance_enemies = get_tree().get_nodes_in_group(&"enemies")
		_guidance_cache.clear()
	var key := Vector3i(floori(origin.x / 96.0), floori(origin.y / 96.0), int(reach))
	var cached: Variant = _guidance_cache.get(key)
	if is_instance_valid(cached) and not cached.is_dead \
			and not excluded.has(cached.get_instance_id()) \
			and origin.distance_squared_to(cached.global_position) <= reach * reach:
		return cached as Enemy
	var best: Enemy
	var best_distance := reach * reach
	for candidate in _guidance_enemies:
		if not is_instance_valid(candidate):
			continue
		var enemy := candidate as Enemy
		if enemy.is_dead or excluded.has(enemy.get_instance_id()):
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	if best != null and not is_instance_valid(cached):
		_guidance_cache[key] = best
	return best


func friendly_target(origin: Vector2, reach: float, excluded: Dictionary) -> Node2D:
	var best: Node2D = guidance_target(origin, reach, excluded)
	var best_distance := origin.distance_squared_to(best.global_position) if best != null else reach * reach
	for node in get_tree().get_nodes_in_group(&"friendly_aim_targets"):
		if node.has_method("can_be_targeted") and node.can_be_targeted() and not excluded.has(node.get_instance_id()):
			var distance := origin.distance_squared_to(node.global_position)
			if distance < best_distance:
				best = node
				best_distance = distance
	return best


func _ready() -> void:
	batch_enabled = not OS.get_cmdline_user_args().has("--no-projectile-batch")
	batch_renderer = BATCH_RENDERER.new()
	batch_renderer.manager = self
	add_child(batch_renderer)
	batch_renderer.set_process(batch_enabled)
	combat = WEAPON_COMBAT.new()
	combat.manager = self
	add_child(combat)
	# 预先创建子弹节点，避免第一次开火时的实例化/碰撞体构建尖峰。
	for i in PREWARM_COUNT:
		_pool.append(_create_pooled())


func _create_pooled() -> Projectile:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	add_child(projectile)
	projectile.visible = false
	projectile.collision_mask = 0
	projectile.set_physics_process(false)
	projectile.get_node("CollisionShape2D").set_deferred("disabled", true)
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
	source_kind: StringName = &"",
	weapon: WeaponRuntime = null,
	budget: Dictionary = {},
	can_split: bool = true,
	form_override: StringName = &""
) -> void:
	var derived := weapon != null and not can_split and source_kind in [&"weapon:star", &"clone"]
	if derived and derived_active >= MAX_DERIVED_ACTIVE:
		return
	var projectile: Projectile = null

	while not _pool.is_empty():
		var candidate: Projectile = _pool.pop_back()
		if is_instance_valid(candidate):
			projectile = candidate
			break

	if projectile == null:
		projectile = _create_pooled()
	elif projectile.get_parent() == null:
		add_child(projectile)

	projectile.setup(
		self, origin, direction, stats, color_index, core, heavy, damage_scale, size_scale,
		speed_scale, lifetime_scale, allow_crit, source_kind, weapon, budget, can_split, form_override
	)
	projectile.active_index = _active.size()
	_active.append(projectile)
	if derived:
		derived_active += 1


func release(projectile: Projectile) -> void:
	if projectile == null or not is_instance_valid(projectile):
		return

	var index := projectile.active_index
	if index < 0 or index >= _active.size() or _active[index] != projectile:
		return
	projectile.deactivate_sprite_trail()
	projectile.orbiting = false
	var last_index := _active.size() - 1
	if index != last_index:
		var moved := _active[last_index]
		_active[index] = moved
		moved.active_index = index
	_active.pop_back()
	projectile.active_index = -1
	if projectile.is_derived:
		derived_active = maxi(0, derived_active - 1)
		projectile.is_derived = false

	projectile.visible = false
	projectile.collision_mask = 0
	projectile.set_physics_process(false)
	projectile.get_node("CollisionShape2D").set_deferred("disabled", true)

	if _pool.size() < MAX_POOL:
		_pool.append(projectile)
	else:
		projectile.queue_free()


func acquire_sprite_trail() -> bool:
	if active_sprite_trails >= MAX_SPRITE_TRAILS:
		return false
	active_sprite_trails += 1
	return true


func release_sprite_trail() -> void:
	active_sprite_trails = maxi(0, active_sprite_trails - 1)

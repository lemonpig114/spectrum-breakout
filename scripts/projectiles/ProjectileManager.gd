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
var _moving_projectile := false
var centralized_collision := OS.get_cmdline_user_args().has("--centralized-projectile-collision") and not OS.get_cmdline_user_args().has("--legacy-projectile-physics")
var _collision_cells := {}
var _collision_frame := -1
var _query_ids := {}
var _collision_enemies: Array[Enemy] = []
var _collision_positions := PackedVector2Array()
var _collision_radii := PackedFloat32Array()
var _collision_ids := PackedInt64Array()
var _bounds_frame := -1
var _bounds := Rect2()
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
) -> Projectile:
	if not projectile_visible_bounds().has_point(origin): return null
	var derived := weapon != null and not can_split and source_kind in [&"weapon:star", &"clone"]
	if derived and derived_active >= MAX_DERIVED_ACTIVE:
		return null
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
	projectile.monitoring = not centralized_collision
	if centralized_collision:
		projectile.set_physics_process(false)
		projectile.collision_mask = 0
		projectile.monitoring = false
		projectile.get_node("CollisionShape2D").set_deferred("disabled", true)
	projectile.active_index = _active.size()
	_active.append(projectile)
	if derived:
		derived_active += 1
	return projectile


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


func projectile_visible_bounds() -> Rect2:
	var frame := Engine.get_physics_frames()
	if _bounds_frame != frame:
		_bounds_frame = frame
		var camera := get_viewport().get_camera_2d()
		if camera != null:
			var half_view := get_viewport_rect().size * 0.5 / camera.zoom
			_bounds = Rect2(camera.get_screen_center_position()-half_view, half_view*2)
		else:
			_bounds = Rect2(Vector2.ZERO,get_viewport_rect().size)
	return _bounds


func clip_weapon_range(origin: Vector2, direction: Vector2, requested: float) -> float:
	var bounds := projectile_visible_bounds()
	if not bounds.has_point(origin): return 0.0
	var dir := direction.normalized()
	var distance := maxf(0,requested)
	if dir.x > 0.00001: distance = minf(distance,(bounds.end.x-origin.x)/dir.x)
	elif dir.x < -0.00001: distance = minf(distance,(bounds.position.x-origin.x)/dir.x)
	if dir.y > 0.00001: distance = minf(distance,(bounds.end.y-origin.y)/dir.y)
	elif dir.y < -0.00001: distance = minf(distance,(bounds.position.y-origin.y)/dir.y)
	return maxf(0,distance)


func _physics_process(delta: float) -> void:
	if not centralized_collision: return
	var clock := CombatProfiler.begin()
	_ensure_collision_grid()
	for shot in _active.duplicate():
		if not is_instance_valid(shot) or shot.active_index < 0 or shot.orbiting: continue
		var start: Vector2 = shot.global_position
		var traveled: float = shot.distance_traveled
		_moving_projectile = true
		var move_clock := CombatProfiler.begin()
		shot._simulate_projectile(delta)
		CombatProfiler.end(&"projectile_movement", move_clock)
		_moving_projectile = false
		if shot.active_index < 0 or shot.orbiting: continue
		var finish: Vector2 = shot.global_position
		if not shot._returning and shot._return_extension < 0.0:
			finish = start + (finish-start).limit_length(maxf(0, shot.range_limit-traveled))
		if not (shot._pending_retire and shot.form_at_fire == &"cannon"):
			_sweep_projectile(shot, start, finish)
		if shot.active_index >= 0 and shot._pending_retire: release(shot)
	CombatProfiler.end(&"projectile_manager", clock)


func _ensure_collision_grid() -> void:
	var frame := Engine.get_physics_frames()
	if _collision_frame == frame: return
	_collision_frame = frame
	_collision_cells.clear()
	_collision_enemies.clear()
	_collision_positions.clear()
	_collision_radii.clear()
	_collision_ids.clear()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead: continue
		var index := _collision_enemies.size()
		_collision_enemies.append(enemy)
		_collision_positions.append(enemy.global_position)
		_collision_radii.append(enemy.radius)
		_collision_ids.append(enemy.get_instance_id())
		var low := Vector2i(((enemy.global_position-Vector2.ONE*enemy.radius)/72.0).floor())
		var high := Vector2i(((enemy.global_position+Vector2.ONE*enemy.radius)/72.0).floor())
		for y in range(low.y, high.y+1):
			for x in range(low.x, high.x+1):
				var key := Vector2i(x,y)
				if not _collision_cells.has(key): _collision_cells[key] = []
				_collision_cells[key].append(index)


## Reuse the same spatial snapshot for melee, waves, explosions and chain queries.
func enemies_near(origin: Vector2, reach: float) -> Array[Enemy]:
	_ensure_collision_grid()
	# Broad attacks should not visit hundreds of empty grid cells.
	if reach >= 144.0: return _collision_enemies
	var found: Array[Enemy] = []
	var seen := {}
	var low := Vector2i(((origin-Vector2.ONE*reach)/72.0).floor())
	var high := Vector2i(((origin+Vector2.ONE*reach)/72.0).floor())
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			for index: int in _collision_cells.get(Vector2i(x,y), []):
				if seen.has(index): continue
				seen[index] = true
				var enemy := _collision_enemies[index]
				if is_instance_valid(enemy) and not enemy.is_dead: found.append(enemy)
	return found


func _sweep_projectile(shot: Projectile, start: Vector2, finish: Vector2) -> void:
	var query_clock := CombatProfiler.begin()
	var radius := maxf(3, shot.projectile_size*0.9)
	var low := Vector2i(((start.min(finish)-Vector2.ONE*radius)/72.0).floor())
	var high := Vector2i(((start.max(finish)+Vector2.ONE*radius)/72.0).floor())
	_query_ids.clear()
	var hits: Array[int] = []
	var hit_ids: Dictionary = shot._return_hit_ids if shot._returning else shot._hit_ids
	for y in range(low.y, high.y+1):
		for x in range(low.x, high.x+1):
			for index: int in _collision_cells.get(Vector2i(x,y), []):
				if _query_ids.has(index) or hit_ids.has(_collision_ids[index]): continue
				_query_ids[index] = true
				var at := _collision_positions[index]
				if Geometry2D.get_closest_point_to_segment(at,start,finish).distance_squared_to(at) <= (_collision_radii[index]+radius)**2:
					hits.append(index)
	if hits.size() > 1:
		hits.sort_custom(func(a: int,b: int): return start.distance_squared_to(_collision_positions[a])<start.distance_squared_to(_collision_positions[b]))
	CombatProfiler.end(&"projectile_candidates", query_clock)
	for index in hits:
		if shot.active_index < 0 or shot.orbiting: break
		var enemy := _collision_enemies[index]
		if is_instance_valid(enemy) and not enemy.is_dead: shot._on_body_entered(enemy)



func acquire_sprite_trail() -> bool:
	if active_sprite_trails >= MAX_SPRITE_TRAILS:
		return false
	active_sprite_trails += 1
	return true


func release_sprite_trail() -> void:
	active_sprite_trails = maxi(0, active_sprite_trails - 1)

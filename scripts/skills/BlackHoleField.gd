class_name BlackHoleField
extends Node2D

## 捕获攻击仅快速缩小后回收，不再移动或补做碰撞；销毁时计入35%伤害。
const INTERVAL := 20.0
const FIRST_CAST_DELAY := 5.0
const DURATION := 10.0
const ORBIT_DURATION := 0.2
const ABSORB_RATIO := 0.35
const TICK_INTERVAL := 0.5
var suppress_absorb_animation := false
var _fps_sample := 0.0
const BASE_RADIUS := 40.0
const OUTER_RANGE_SCALE := 1.5
const MAX_ORBITS := 128
const CAPTURES_PER_SCAN := 8
const DIRECT_ABSORB_THRESHOLD := 80

var player: Player
var manager: ProjectileManager
var active := false
var age := 0.0
var cooldown := FIRST_CAST_DELAY
var damage := 100.0
var radius := BASE_RADIUS
var target_radius := BASE_RADIUS
var absorbed := 0
var orbits: Array[Dictionary] = []
var _tick := 0.0
var _scan := 0.0
var _angle := 0.0
var _burst := 0.0
var _burst_radius := 0.0
var _visual_time := 0.0
var _redraw_dirty := false
var _points := PackedVector2Array()
var _growth_tween: Tween
var _disk: Polygon2D
var _disk_material: ShaderMaterial
var _collapse_disk: Polygon2D
var _collapse_material: ShaderMaterial
var _absorb_flash := 0.0
var _growth_dirty := false


func _ready() -> void:
	add_to_group(&"friendly_aim_targets")
	_disk = Polygon2D.new()
	_disk.polygon = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	_disk.uv = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)])
	_disk_material = ShaderMaterial.new()
	_disk_material.shader = preload("res://shaders/blackhole_disk.gdshader")
	_disk.material = _disk_material
	_disk.z_index = -1
	_disk.visible = false
	add_child(_disk)
	_collapse_disk = Polygon2D.new()
	_collapse_disk.polygon = _disk.polygon
	_collapse_material = ShaderMaterial.new()
	_collapse_material.shader = preload("res://shaders/blackhole_collapse.gdshader")
	_collapse_disk.material = _collapse_material
	_collapse_disk.visible = false
	add_child(_collapse_disk)


func can_be_targeted() -> bool:
	return active and age <= DURATION - ORBIT_DURATION


func setup(owner_player: Player, projectiles: ProjectileManager) -> void:
	player = owner_player
	manager = projectiles
	z_index = 4


func size_limit() -> float:
	return BASE_RADIUS * (8.0 if Skills.is_unlocked(&"blackhole_4") else 4.0)


func effect_radius() -> float:
	return radius * OUTER_RANGE_SCALE


func cast(at: Vector2) -> void:
	global_position = at
	active = true
	age = 0.0
	damage = 100.0
	if _growth_tween != null:
		_growth_tween.kill()
	radius = BASE_RADIUS
	target_radius = BASE_RADIUS
	_growth_dirty = false
	absorbed = 0
	_clear_orbits()
	_tick = 0.0
	_scan = 0.0
	_burst = 0.0
	_absorb_flash = 0.0
	cooldown = INTERVAL
	Audio.play(&"weapon_black_hole")
	_request_redraw()


func _physics_process(delta: float) -> void:
	var clock := preload("res://scripts/game/CombatProfiler.gd").begin()
	_simulate_hole(delta)
	preload("res://scripts/game/CombatProfiler.gd").end(&"blackhole", clock)


func _simulate_hole(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not RunState.is_running or RunState.is_dead:
		return
	if not Skills.is_unlocked(&"blackhole_1"):
		return
	cooldown -= delta
	_angle += delta * (3.6 if Skills.is_unlocked(&"blackhole_3") else 2.0)
	_burst = maxf(0.0, _burst - delta)
	_absorb_flash = maxf(0.0, _absorb_flash - delta * 3.0)
	if not active:
		if cooldown <= 0.0:
			var target := manager.guidance_target(player.global_position, 520.0, {})
			var offset := Vector2.RIGHT * 160.0
			if target != null:
				offset = (target.global_position - player.global_position).limit_length(220.0)
			cast(player.global_position + offset)
		if _burst > 0.0:
			_request_redraw()
		return
	age += delta
	_fps_sample += delta
	if _fps_sample >= 0.5:
		_fps_sample = 0.0
		var fps := Engine.get_frames_per_second()
		if fps > 0 and fps < 10:
			suppress_absorb_animation = true
		elif fps >= 15:
			suppress_absorb_animation = false
	for i in range(orbits.size() - 1, -1, -1):
		var entry: Dictionary = orbits[i]
		entry.age = float(entry.age) + delta
		if suppress_absorb_animation or float(entry.age) >= ORBIT_DURATION or not _orbit_valid(entry):
			_ingest_orbit(entry)
			orbits.remove_at(i)
		else:
			_advance_orbit(entry)
	_scan += delta
	if _scan >= 0.1:
		_scan = fmod(_scan, 0.1)
		# 仅预留短缩小时间；收尾会结算尚未完成的捕获。
		if age <= DURATION - ORBIT_DURATION:
			_capture_nearby()
		_apply_slow()
	_tick += delta
	while _tick >= TICK_INTERVAL:
		_tick -= TICK_INTERVAL
		_hit_area(effect_radius(), damage * (0.15 if Skills.is_unlocked(&"blackhole_3") else 0.05), true)
	if age >= DURATION:
		finish()
	_visual_time += delta
	if _visual_time >= 1.0 / 30.0:
		_visual_time = fmod(_visual_time, 1.0 / 30.0)
		_request_redraw()


func _capture_nearby() -> void:
	var accepted := 0
	var reach := effect_radius() + 40.0
	# 管理器活跃表会交换末项；遍历快照，避免回收时跳过或重复捕获。
	for projectile in manager._active.duplicate():
		if accepted >= CAPTURES_PER_SCAN or orbits.size() >= MAX_ORBITS:
			break
		if projectile.active_index < 0 or projectile.orbiting or global_position.distance_squared_to(projectile.global_position) > reach * reach:
			continue
		_capture(projectile.global_position, projectile.damage, projectile.projectile_size,
			RunState.color_of(projectile.color_index))
		orbits.back().body = weakref(projectile)
		orbits.back().serial = projectile.spawn_serial
		orbits.back().trail_width = projectile._sprite_trail.width if projectile._has_sprite_trail and projectile._sprite_trail != null else 0.0
		projectile.orbiting = true
		projectile.set_physics_process(false)
		projectile.collision_mask = 0
		projectile.get_node("CollisionShape2D").set_deferred("disabled", true)
		_absorb_overflow()
		accepted += 1
	if accepted < CAPTURES_PER_SCAN and orbits.size() < MAX_ORBITS:
		accepted += manager.combat.absorb_nearby_attacks(self, CAPTURES_PER_SCAN - accepted)
	if not Skills.is_unlocked(&"blackhole_4"):
		return
	for node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		if accepted >= CAPTURES_PER_SCAN or orbits.size() >= MAX_ORBITS:
			break
		var projectile := node as EnemyProjectile
		if projectile == null or projectile.orbiting or projectile.is_queued_for_deletion() \
				or global_position.distance_squared_to(projectile.global_position) > reach * reach:
			continue
		_capture(projectile.global_position, projectile.damage, 4.0, projectile.tint)
		orbits.back().body = weakref(projectile)
		projectile.orbiting = true
		projectile.set_physics_process(false)
		_absorb_overflow()
		accepted += 1


func _capture(at: Vector2, hit_damage: float, size: float, tint: Color) -> void:
	var offset := at - global_position
	orbits.append({"angle": offset.angle(), "radius": maxf(12.0, offset.length()),
		"damage": hit_damage, "size": size, "tint": tint, "age": 0.0,
		"last_position": at, "last_hit_position": at, "body": null, "serial": -1})


func capture_weapon_attack(attack: Dictionary, at: Vector2) -> bool:
	if not can_be_targeted() or orbits.size() >= MAX_ORBITS:
		return false
	_capture(at, float(attack.damage), float(attack.hit_radius), RunState.color_of(int(attack.color)))
	orbits.back().attack = attack
	_absorb_overflow()
	return true


func _absorb_overflow() -> void:
	if suppress_absorb_animation or orbits.size() > DIRECT_ABSORB_THRESHOLD:
		var orbit: Dictionary = orbits.pop_back()
		_ingest_orbit(orbit)


func _ingest_orbit(orbit: Dictionary) -> void:
	if _orbit_valid(orbit):
		if not bool(orbit.get("credited", false)):
			damage += float(orbit.damage) * ABSORB_RATIO
			orbit.credited = true
		var remaining_growth := 1.0
		target_radius = minf(size_limit(), target_radius + BASE_RADIUS * 0.12 * remaining_growth)
		_growth_dirty = true
		absorbed += 1
	_release_orbit(orbit)


func orbit_scale(seconds: float) -> float:
	return pow(1.0 - clampf(seconds / ORBIT_DURATION, 0.0, 1.0), 2.0)


func _orbit_valid(orbit: Dictionary) -> bool:
	if orbit.body == null:
		return true
	var body: Node2D = orbit.body.get_ref()
	if body == null or body.is_queued_for_deletion():
		return false
	if body is Projectile:
		return body.active_index >= 0 and body.spawn_serial == int(orbit.serial) and body.orbiting
	return true


func _release_orbit(orbit: Dictionary) -> void:
	if orbit.has("attack"):
		orbit.attack.consumed = true
		manager.combat.release_absorbed_attack(orbit.attack)
		return
	if orbit.body == null or not _orbit_valid(orbit):
		return
	var body: Node2D = orbit.body.get_ref()
	if body is Projectile:
		body.orbiting = false
		manager.release(body)
	else:
		body.queue_free()


func _clear_orbits() -> void:
	for orbit in orbits:
		_release_orbit(orbit)
	orbits.clear()


func _advance_orbit(entry: Dictionary, _check_hits: bool = false) -> void:
	# Legacy method name retained for capture callers; no orbit, rotation or collision work.
	var shrink := orbit_scale(float(entry.age))
	if entry.has("attack"):
		entry.attack.visual_scale = shrink
		return
	if entry.body == null or not _orbit_valid(entry):
		return
	var body: Node2D = entry.body.get_ref()
	body.scale = Vector2.ONE * maxf(0.001, shrink)
	if body is Projectile and body._has_sprite_trail and body._sprite_trail != null:
		body._sprite_trail.visible = false


func _apply_slow() -> void:
	var slow := 0.7 if Skills.is_unlocked(&"blackhole_3") else 0.4
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and not enemy.is_dead \
				and global_position.distance_squared_to(enemy.global_position) <= (effect_radius() + enemy.radius) ** 2:
			enemy.apply_blackhole_slow(slow, 0.2)


func _hit_area(reach: float, amount: float, tug: bool, explosion: bool = false) -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead \
				or global_position.distance_squared_to(enemy.global_position) > (reach + enemy.radius) ** 2:
			continue
		var hit := DamageContext.new()
		hit.source = self
		hit.target = enemy
		hit.hit_position = global_position
		hit.amount = amount
		hit.color_index = -1
		hit.add_tag(&"blackhole")
		if explosion:
			hit.add_tag(&"blackhole_explosion")
		enemy.take_damage(hit)
		if tug and not enemy.is_dead:
			var pull := (global_position - enemy.global_position).limit_length(32.0 if Skills.is_unlocked(&"blackhole_3") else 16.0)
			enemy.apply_gravity_displacement(pull)


func finish() -> void:
	if not active:
		return
	active = false
	for entry in orbits:
		_ingest_orbit(entry)
	orbits.clear()
	if Skills.is_unlocked(&"blackhole_2"):
		_burst_radius = effect_radius() * 2.0
		_burst = 0.75
		_hit_area(_burst_radius, damage * 6.0, true, true)
		Audio.play(&"weapon_hit_black_hole")
	_request_redraw()


func _draw() -> void:
	if _collapse_disk != null:
		_collapse_disk.visible = _burst > 0.0
	if _disk != null:
		_disk.visible = active
	if active:
		var fade := minf(1.0, age * 4.0) * minf(1.0, (DURATION - age) * 3.0)
		_disk.scale = Vector2.ONE * radius * 1.65
		_disk_material.set_shader_parameter("phase", _angle)
		_disk_material.set_shader_parameter("opacity", fade)
		_disk_material.set_shader_parameter("pulse", _absorb_flash)
		_disk_material.set_shader_parameter("outer_radius", effect_radius() / (radius * 1.65))
		draw_circle(Vector2.ZERO, radius * 0.36, Color(0.008, 0.003, 0.02, 0.97 * fade))
		for mote in 24:
			var travel := fposmod(_angle * 0.08 + float(mote) * 0.618, 1.0)
			var distance := radius * lerpf(1.32, 0.36, travel)
			var angle := mote * 2.399963 + _angle + travel * 2.4
			var point := Vector2.from_angle(angle) * Vector2(distance, distance * 0.72)
			draw_circle(point, 0.8 + (1.0 - travel) * 0.8,
				Color(1.15, 0.65, 1.8, sin(travel * PI) * 0.5 * fade))
		for arm in 3:
			_points.resize(22)
			for step in 22:
				var t := float(step) / 21.0
				_points[step] = Vector2.from_angle(_angle + arm * TAU / 3.0 + t * 3.8) * radius * lerpf(0.12, 1.0, t)
			draw_polyline(_points, Color(0.65, 0.35, 1.1, 0.18 * fade), maxf(1.2, radius * 0.022), true)
		draw_arc(Vector2.ZERO, radius, _angle, _angle + TAU * 0.78, 36,
			Color(0.94, 0.76, 1.3, 0.16 * fade), 1.0, true)
		draw_circle(Vector2.ZERO, radius * 0.19, Color(0.005, 0.003, 0.01, fade))
	if _burst > 0.0:
		_draw_collapse()


func _draw_collapse() -> void:
	_collapse_disk.scale = Vector2.ONE * _burst_radius * 1.22
	_collapse_material.set_shader_parameter("progress", clampf(1.0 - _burst / 0.75, 0.0, 1.0))


func _request_redraw() -> void:
	_redraw_dirty = true


func _process(_delta: float) -> void:
	if _growth_dirty:
		_growth_dirty = false
		_absorb_flash = 0.7
		if _growth_tween != null:
			_growth_tween.kill()
		_growth_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_growth_tween.tween_property(self, "radius", target_radius, 0.28)
	if _redraw_dirty:
		_redraw_dirty = false
		queue_redraw()

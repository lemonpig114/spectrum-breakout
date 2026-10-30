class_name WeaponCombat
extends Node2D

## 直接命中统一结算；派生攻击只入 FIFO 队列，逐物理帧限额处理。
const EVENTS_PER_FRAME := 256
const DERIVATIVES_PER_ATTACK := 128
const QUEUE_LIMIT := 4096
const VISUAL_LIMIT := 160
const DERIVATIVES_PER_FRAME := 8
const SWORD_WAVE_DISTANCE := 145.0
const SWORD_WAVE_WIDTH := 108.0
const SWORD_WAVE_DEPTH := 34.0
const SWORD_WAVE_DURATION := 0.28
const CHAIN_RANGE := 210.0
const WAVE_RANGE := 240.0
const WAVE_HALF_WIDTH := 55.0
const WAVE_SPEED := 180.0
const WAVE_DEPTH := 72.0
const SCYTHE_RADIUS := 125.0
const SCYTHE_SWEEP_DURATION := 0.65
const SCYTHE_SECONDARY_COOLDOWN := 0.8
const SCYTHE_TRAIL := preload("res://scripts/fx/ScytheTrail.gd")

var manager
var player
var _events: Array[Dictionary] = []
var _head := 0
var _visuals: Array[Dictionary] = []
var _sword_waves: Array[Dictionary] = []
var _wave_pulses: Array[Dictionary] = []
var _scythe_sweeps: Array[Dictionary] = []
var _scythe_trail_pool: Array[Polygon2D] = []
var _scythe_trail_count := 0
var _scythe_secondary_cooldown := 0.0
var _sword_draw_scale := 1.0
var _delayed_hits: Array[Dictionary] = []
var _redraw_dirty := false
var _absorbed_attacks: Array[Dictionary] = []
var _derivative_frame := -1
var _derivatives_this_frame := 0


func _physics_process(_delta: float) -> void:
	var clock := preload("res://scripts/game/CombatProfiler.gd").begin()
	_simulate_attacks(_delta)
	preload("res://scripts/game/CombatProfiler.gd").end(&"weapon_queue", clock)


func _simulate_attacks(_delta: float) -> void:
	_scythe_secondary_cooldown = maxf(0.0, _scythe_secondary_cooldown - _delta)
	for i in range(_delayed_hits.size() - 1, -1, -1):
		_delayed_hits[i].delay = float(_delayed_hits[i].delay) - _delta
		if float(_delayed_hits[i].delay) <= 0.0:
			var echo: Dictionary = _delayed_hits[i]
			_delayed_hits.remove_at(i)
			enqueue(echo)
	var processed := 0
	while _head < _events.size() and processed < EVENTS_PER_FRAME:
		var event: Dictionary = _events[_head]
		_head += 1
		processed += 1
		match event.kind:
			&"extra_shot": fire_weapon(event.origin, event.direction, event.weapon.stats, int(event.color), bool(event.heavy), event.weapon)
			&"sword": _sword(event)
			&"lightning": _lightning(event)
			&"split": _split(event)
			&"return_arc": _return_arc(event)
			&"explosion": _explosion(event)
			&"wave": _wave(event)
			&"scythe": _scythe(event)
			&"water_echo": _water_echo(event)
	if _head >= _events.size():
		_events.clear()
		_head = 0
	elif _head > 512:
		_events = _events.slice(_head)
		_head = 0
	_advance_sword_waves(_delta)
	_advance_water_waves(_delta)
	_advance_scythe_sweeps(_delta)


func _process(delta: float) -> void:
	var had_visuals := not _visuals.is_empty()
	for i in range(_visuals.size() - 1, -1, -1):
		_visuals[i].time = float(_visuals[i].time) - delta
		if _visuals[i].get("kind") == &"scythe" and _visuals[i].get("trail") != null:
			var visual: Dictionary = _visuals[i]
			var progress := clampf(float(visual.age) / SCYTHE_SWEEP_DURATION, 0.0, 1.0)
			var turn := -1.0 if bool(visual.get("reverse", false)) else 1.0
			visual.trail.update_sweep(to_local(visual.origin),
				(visual.direction as Vector2).angle() + turn * TAU * progress,
				float(visual.radius) * 0.82, progress,
				RunState.color_of(int(visual.color)), bool(visual.get("reverse", false)))
		if _visuals[i].time <= 0.0:
			var trail: Polygon2D = _visuals[i].get("trail") as Polygon2D
			if trail != null:
				trail.visible = false
				_scythe_trail_pool.append(trail)
			_visuals.remove_at(i)
	if _redraw_dirty or had_visuals or not _sword_waves.is_empty() or not _wave_pulses.is_empty() or not _absorbed_attacks.is_empty():
		_redraw_dirty = false
		queue_redraw()


func _draw() -> void:
	for attack in _absorbed_attacks:
		_draw_absorbed_attack(attack)
	for wave in _sword_waves:
		_draw_sword_wave(wave)
	for wave in _wave_pulses:
		_draw_wave_visual(wave, RunState.color_of(int(wave.color)))
	for visual in _visuals:
		var c := RunState.color_of(int(visual.color))
		match visual.get("kind", &"line"):
			&"wave": _draw_wave_visual(visual, c)
			&"scythe": _draw_scythe_visual(visual, c)
			&"explosion": _draw_explosion_visual(visual, c)
			_:
				var alpha := clampf(float(visual.time) / 0.17, 0.0, 1.0)
				draw_line(to_local(visual.from), to_local(visual.to),
					Color(c.r, c.g, c.b, alpha), 3.0 * alpha, true)


func _draw_wave_visual(visual: Dictionary, c: Color) -> void:
	var age: float = clampf(float(visual.age) / float(visual.duration), 0.0, 1.0)
	var direction: Vector2 = visual.direction
	var side := direction.orthogonal()
	var center: Vector2 = to_local(visual.position)
	var fade := 1.0 - smoothstep(0.75, 1.0, age)
	var front := PackedVector2Array()
	var back := PackedVector2Array()
	var front_colors := PackedColorArray()
	var back_colors := PackedColorArray()
	for i in 25:
		var u := float(i) / 12.0 - 1.0
		var taper := pow(maxf(0.0, 1.0 - absf(u)), 0.7)
		var point := _wave_front_point(center, direction, side, u, age)
		front.append(point + direction * (2.5 * taper))
		back.append(point - direction * ((27.0 + sin(u * 4.0 + age * 2.0) * 4.0) * taper))
		front_colors.append(Color(c.r, c.g, c.b, 0.085 * taper * fade))
		back_colors.append(Color(c.r, c.g, c.b, 0.008 * taper * fade))
	var sheet := front.duplicate()
	var colors := front_colors
	for i in range(24, -1, -1):
		sheet.append(back[i])
		colors.append(back_colors[i])
	draw_polygon(sheet, colors)
	for i in 24:
		var u := (float(i) + 0.5) / 12.0 - 1.0
		var taper := pow(maxf(0.0, 1.0 - absf(u)), 0.55)
		draw_line(front[i], front[i + 1],
			Color(c.r, c.g, c.b, 0.19 * taper * fade), 1.5, true)
	var anchors := [-0.83, -0.34, 0.31, 0.76]
	for stream in 4:
		var u: float = anchors[stream]
		var anchor := _wave_front_point(center, direction, side, u, age) - direction * 5.0
		var length := 34.0 + float((stream * 13) % 29)
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var left_colors := PackedColorArray()
		var right_colors := PackedColorArray()
		for step in 9:
			var q := float(step) / 8.0
			var drift := sin(q * PI) * (10.0 + float(stream) * 3.0) \
				* (-1.0 if stream < 2 else 1.0)
			var point := anchor - direction * length * q \
				+ side * (drift + q * q * float(stream - 2) * 6.0)
			var thickness := 2.3 * (1.0 - q) * sin(PI * (0.15 + q * 0.75))
			left.append(point - side * thickness)
			right.append(point + side * thickness)
			var alpha := 0.10 * (1.0 - q) * fade
			left_colors.append(Color(c.r, c.g, c.b, alpha))
			right_colors.append(Color(c.r, c.g, c.b, alpha * 0.3))
		var ribbon := left.duplicate()
		var ribbon_colors := left_colors
		for i in range(8, -1, -1):
			ribbon.append(right[i])
			ribbon_colors.append(right_colors[i])
		draw_polygon(ribbon, ribbon_colors)
		if stream == 1 or stream == 3:
			draw_circle(left[7] - direction * 3.0, 1.2,
				Color(c.r, c.g, c.b, 0.11 * fade))


func _wave_front_point(center: Vector2, direction: Vector2, side: Vector2,
		u: float, age: float) -> Vector2:
	var dome := 18.0 * (1.0 - u * u)
	var curl := sin(u * 5.6 + age * 3.0) * 4.5 * (1.0 - u * u)
	var uneven := sin(u * 11.0 + 1.8) * 1.5 * (1.0 - absf(u))
	return center + side * (u * WAVE_HALF_WIDTH) + direction * (dome + curl + uneven)


func _draw_scythe_visual(visual: Dictionary, c: Color) -> void:
	var age: float = clampf(float(visual.age) / SCYTHE_SWEEP_DURATION, 0.0, 1.0)
	var center: Vector2 = to_local(visual.origin)
	var turn := -1.0 if bool(visual.get("reverse", false)) else 1.0
	var angle: float = (visual.direction as Vector2).angle() + turn * TAU * age
	var radius := float(visual.radius) * 0.82
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		var arc_angle := angle - 1.1 + t * 1.25
		var taper := pow(sin(PI * t), 1.15)
		outer.append(center + Vector2.from_angle(arc_angle) * (radius + 4.0 * taper))
		inner.append(center + Vector2.from_angle(arc_angle) * (radius - 7.0 * taper))
	var polygon := outer.duplicate()
	for i in range(inner.size() - 1, -1, -1):
		polygon.append(inner[i])
	var alpha := 0.72 * (1.0 - age * 0.65)
	draw_colored_polygon(polygon, Color(c.r, c.g, c.b, alpha * 0.42))
	draw_polyline(outer, Color(2.2, 2.2, 2.2, alpha * 0.78), 1.9, true)
	var handle_end: Vector2 = inner[0]
	var handle_direction := (handle_end - center).normalized()
	var handle_start := center + handle_direction * 14.0
	draw_line(handle_start, handle_end, Color(0.03, 0.04, 0.08, alpha), 8.0, true)
	draw_line(handle_start, handle_end, Color(c.r, c.g, c.b, alpha * 0.42), 3.0, true)
	draw_line(handle_start, handle_start + handle_direction * 15.0,
		Color(2.0, 2.0, 2.0, alpha * 0.65), 1.5, true)


func _draw_explosion_visual(visual: Dictionary, c: Color) -> void:
	var age: float = 1.0 - clampf(float(visual.time) / 0.22, 0.0, 1.0)
	var center: Vector2 = to_local(visual.origin)
	var radius: float = float(visual.radius) * (0.28 + age * 0.72)
	var fade := 1.0 - age
	var halo_extent := Vector2.ONE * radius * 1.25
	draw_texture_rect(preload("res://scripts/fx/NeonTexture.gd").halo(),
		Rect2(center - halo_extent, halo_extent * 2.0), false,
		Color(c.r, c.g, c.b, 0.18 * fade))
	for i in 10:
		var angle := TAU * (float(i) + 0.17 * sin(float(i) * 7.1)) / 10.0
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		var length := radius * (0.64 + 0.32 * absf(sin(float(i) * 12.7)))
		var base := center + direction * radius * 0.28
		var tip := center + direction * length + side * sin(float(i) * 5.7) * radius * 0.1
		draw_polygon(PackedVector2Array([
			base - side * radius * 0.11, base + side * radius * 0.08, tip,
		]), PackedColorArray([
			Color(c.r, c.g, c.b, 0.40 * fade),
			Color(c.r, c.g, c.b, 0.30 * fade),
			Color(c.r, c.g, c.b, 0.0),
		]))
		draw_line(base, tip, Color(c.r, c.g, c.b, 0.31 * fade), 1.4, true)
	draw_circle(center, radius * 0.19 * (1.0 - age * 0.45),
		Color(2.0, 2.0, 2.0, 0.48 * fade))


func new_budget() -> Dictionary:
	return {"spawned": 0}


func enqueue(event: Dictionary, derivative: bool = true) -> bool:
	if derivative and _events.size() - _head >= QUEUE_LIMIT:
		return false
	if derivative:
		var frame := Engine.get_physics_frames()
		if frame != _derivative_frame:
			_derivative_frame = frame
			_derivatives_this_frame = 0
		if _derivatives_this_frame >= DERIVATIVES_PER_FRAME:
			return false
		var budget: Dictionary = event.get("budget", {})
		if int(budget.get("spawned", 0)) >= DERIVATIVES_PER_ATTACK:
			return false
		budget.spawned = int(budget.get("spawned", 0)) + 1
		_derivatives_this_frame += 1
	_events.append(event)
	return true


func _add_visual(visual: Dictionary) -> void:
	if _visuals.size() < VISUAL_LIMIT:
		_visuals.append(visual)


func fire_weapon(origin: Vector2, direction: Vector2, stats: StatBlock,
		color_index: int, heavy: bool, weapon: WeaponRuntime,
		clone_attack: bool = false, summon_scale: float = 1.0) -> void:
	var form := weapon.primary_form
	if form in [&"sword", &"scythe"] and weapon.has_form(&"sword") and weapon.has_form(&"scythe"):
		form = &"scythe"
	var budget := new_budget()
	var scale := 1.0
	var data := weapon.primary_data()
	if data != null:
		scale = data.damage_scale
	var base_damage := _weapon_damage(stats, color_index, heavy) * summon_scale
	var damage := base_damage * scale
	if form == &"sprite" and player != null:
		damage *= player.stats.get_value(&"summon_damage")
	match form:
		&"sword":
			enqueue({"kind": &"sword", "origin": origin, "direction": direction,
				"damage": damage, "color": color_index, "heavy": heavy,
				"weapon": weapon, "budget": budget, "secondary": false,
				"clone": clone_attack, "summon_scale": summon_scale}, false)
		&"lightning":
			enqueue({"kind": &"lightning", "origin": origin, "direction": direction,
				"damage": damage, "color": color_index, "heavy": heavy,
				"weapon": weapon, "budget": budget, "secondary": false,
				"clone": clone_attack, "summon_scale": summon_scale}, false)
		&"wave", &"scythe":
			if form == &"wave":
				damage = base_damage * 0.3
			enqueue({"kind": form, "origin": origin, "direction": direction,
				"damage": damage, "base_damage": base_damage, "color": color_index,
				"heavy": heavy, "weapon": weapon, "budget": budget,
				"secondary": false, "clone": clone_attack, "pulse": 0}, false)
		_:
			var projectile_scale := scale * summon_scale
			if form == &"sprite" and player != null:
				projectile_scale *= player.stats.get_value(&"summon_damage")
			manager.fire(origin, direction, stats, color_index, weapon.core, heavy, projectile_scale,
				0.8 if clone_attack else 1.0, 1.0, 1.0, true,
				&"clone" if clone_attack else StringName("weapon:%s" % String(form)), weapon, budget)


func _weapon_damage(stats: StatBlock, color_index: int, heavy: bool) -> float:
	var raw := stats.get_value(&"damage") + (40.0 if heavy else 0.0)
	var mult := stats.get_value(&"damage_mult") + Skills.lens_damage_bonus(color_index) + Skills.cracked_armor_bonus()
	return raw * mult * stats.get_value(&"damage_final") * (2.5 if heavy else 1.0)


func resolve_hit(source: Node, enemy: Enemy, damage: float, color_index: int,
		direction: Vector2, heavy: bool, source_kind: StringName,
		first_hit: bool, last_hit: bool, allow_crit: bool = true,
		weapon_id: StringName = &"", weapon: WeaponRuntime = null,
		trigger_traits: bool = true, attack_budget: Dictionary = {},
		apply_water_force: bool = true) -> float:
	if enemy == null or enemy.is_dead:
		return 0.0
	var hit_position := enemy.global_position - direction.normalized() * enemy.radius
	if source is Projectile:
		hit_position = (source as Projectile).global_position
	var context := Skills.build_hit_context(source, enemy, damage, color_index,
		source_kind != &"clone", allow_crit, hit_position)
	if source_kind == &"clone":
		context.add_tag(&"clone")
	context.weapon_id = weapon_id
	var before := enemy.health
	enemy.take_damage(context)
	if source_kind != &"clone":
		Skills.apply_relic_projectile_procs(enemy)
	var weakness := context.has_tag(&"weakness")
	var hit_sound := &"hit"
	if context.has_tag(&"super_crit"):
		hit_sound = &"super_crit"
	elif context.is_crit:
		hit_sound = &"crit"
	elif weakness:
		hit_sound = &"weak_hit"
	elif heavy:
		hit_sound = &"hit_heavy"
	Audio.play(hit_sound if weapon_id in [&"", &"basic", &"basic_bolt"] else StringName("weapon_hit_%s" % String(weapon_id)))
	if not enemy.is_dead and source_kind != &"clone":
		if weakness:
			Skills.on_weakness_hit(enemy, damage, color_index)
		Skills.try_execute(enemy, weakness)
		if Skills.is_unlocked(&"heavy_2") and (enemy.type_data == null or not enemy.type_data.is_boss):
			enemy.apply_knockback(enemy.global_position - direction * 15.0, 300.0, 0.18)
	if source_kind != &"clone":
		Skills.try_gold_on_hit(enemy.global_position)
	var burst_color := RunState.color_of(color_index)
	if context.has_tag(&"super_crit"):
		burst_color = Color(2.8, 2.8, 2.8, 1.0)
	elif weakness or context.is_crit:
		burst_color = burst_color.lerp(Color.WHITE, 0.25)
	FX.hit_spark(enemy.global_position, burst_color, weakness or context.is_crit)
	FX.hit_impact(enemy.global_position, burst_color, direction)
	if context.is_crit:
		FX.hit_burst(enemy.global_position, burst_color, 22.0, 0.16, EnergyBurst.STYLE_STAR)
	if heavy:
		FX.hit_burst(enemy.global_position, burst_color, 38.0, 0.28, EnergyBurst.STYLE_HEAVY)
	if source_kind != &"clone" and weapon_id != &"cannon" and Skills.has_splash() and (Skills.splash_every_hit() or first_hit or last_hit):
		Skills.apply_splash(enemy.global_position, context.amount, color_index, enemy)
	if trigger_traits and weapon != null:
		var budget := attack_budget if not attack_budget.is_empty() else new_budget()
		if weapon.has_form(&"scythe") and weapon_id not in [&"scythe", &"sword"] \
				and not bool(budget.get("scythe_triggered", false)):
			budget.scythe_triggered = true
			enqueue({"kind": &"scythe", "origin": enemy.global_position,
				"direction": direction, "damage": damage * 0.35, "radius": 70.0,
				"color": color_index, "heavy": false, "weapon": weapon,
				"budget": budget, "secondary": true, "clone": source_kind == &"clone"})
		if weapon.has_form(&"wave") and not enemy.is_dead and apply_water_force:
			enemy.apply_water_push(direction)
		if weapon.has_form(&"wave") and weapon_id in [&"sword", &"scythe"]:
			for delay in [0.10, 0.22]:
				if _delayed_hits.size() < 256:
					_delayed_hits.append({"kind": &"water_echo", "delay": delay,
						"target": weakref(enemy), "damage": damage * 0.15,
						"direction": direction, "color": color_index, "weapon": weapon,
						"weapon_id": weapon_id, "source_kind": source_kind, "budget": budget})
		if weapon.has_form(&"cannon") and weapon_id != &"sword":
			enqueue({"kind": &"explosion", "origin": enemy.global_position,
				"damage": damage * 0.55, "radius": 82.0,
				"color": color_index, "weapon": weapon,
				"budget": budget, "secondary": true,
				"excluded": enemy, "clone": source_kind == &"clone"})
	return minf(before, context.amount)


func on_projectile_hit(projectile: Node, enemy: Enemy, first_hit: bool, last_hit: bool) -> void:
	var form: StringName = projectile.form_at_fire
	if form == &"cannon":
		queue_cannon_explosion(projectile, enemy.global_position)
		return
	var attribution := form
	if String(projectile.source_kind).begins_with("weapon:"):
		attribution = StringName(String(projectile.source_kind).trim_prefix("weapon:"))
	resolve_hit(projectile, enemy, projectile.damage, projectile.color_index,
		projectile.direction, projectile.is_heavy, projectile.source_kind,
		first_hit, last_hit, projectile.allow_crit, attribution,
		projectile.weapon, true, projectile.budget)
	var weapon: WeaponRuntime = projectile.weapon
	if weapon == null:
		return
	if weapon.has_form(&"lightning") and form != &"lightning" and not projectile.chain_triggered:
		projectile.chain_triggered = true
		enqueue({"kind": &"lightning", "origin": enemy.global_position,
			"direction": projectile.direction, "damage": projectile.damage * 0.5,
			"color": projectile.color_index, "heavy": false, "weapon": weapon,
			"budget": projectile.budget, "secondary": true, "excluded": enemy,
			"clone": projectile.source_kind == &"clone"})
	if weapon.has_form(&"star") and form != &"star" and projectile.can_split:
		projectile.can_split = false
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": projectile.direction, "damage_scale": projectile.shot_scale * 0.5,
			"color": projectile.color_index, "weapon": weapon, "budget": projectile.budget,
			"clone": projectile.source_kind == &"clone"})
	elif form == &"star" and projectile.can_split:
		projectile.can_split = false
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": projectile.direction, "damage_scale": projectile.shot_scale * 0.5,
			"color": projectile.color_index, "weapon": weapon, "budget": projectile.budget,
			"clone": projectile.source_kind == &"clone"})
	if weapon.has_form(&"sword") and form != &"sword" and form != &"boomerang" and not projectile.sword_triggered:
		projectile.sword_triggered = true
		enqueue({"kind": &"sword", "origin": enemy.global_position,
			"direction": projectile.direction, "damage": projectile.damage * 0.6,
			"color": projectile.color_index, "heavy": false, "weapon": weapon,
			"budget": projectile.budget, "secondary": true,
			"clone": projectile.source_kind == &"clone"})


func queue_cannon_explosion(projectile: Projectile, position: Vector2) -> void:
	var splash_bonus := Skills.splash_ratio() if Skills.has_splash() else 0.0
	enqueue({"kind": &"explosion", "origin": position,
		"damage": projectile.damage * (1.0 + splash_bonus),
		"radius": 88.0 + (Skills.splash_radius() * 0.25 if Skills.has_splash() else 0.0),
		"color": projectile.color_index, "weapon": projectile.weapon,
		"budget": projectile.budget, "secondary": false,
		"clone": projectile.source_kind == &"clone"}, false)
	var weapon: WeaponRuntime = projectile.weapon
	if weapon == null:
		return
	var derived := {"origin": position, "direction": projectile.direction,
		"color": projectile.color_index, "weapon": weapon,
		"budget": projectile.budget, "clone": projectile.source_kind == &"clone"}
	if weapon.has_form(&"scythe") and not bool(projectile.budget.get("scythe_triggered", false)):
		projectile.budget.scythe_triggered = true
		var scythe_event := derived.duplicate()
		scythe_event.merge({"kind": &"scythe", "damage": projectile.damage * 0.35,
			"radius": 70.0, "heavy": false, "secondary": true})
		enqueue(scythe_event)
	if weapon.has_form(&"star"):
		var star_event := derived.duplicate()
		star_event.kind = &"split"
		star_event.damage_scale = projectile.shot_scale * 0.5
		enqueue(star_event)
	if weapon.has_form(&"lightning"):
		var lightning_event := derived.duplicate()
		lightning_event.kind = &"lightning"
		lightning_event.damage = projectile.damage * 0.5
		lightning_event.heavy = false
		lightning_event.secondary = true
		enqueue(lightning_event)
	if weapon.has_form(&"sword"):
		var sword_event := derived.duplicate()
		sword_event.kind = &"sword"
		sword_event.damage = projectile.damage * 0.6
		sword_event.heavy = false
		sword_event.secondary = true
		enqueue(sword_event)
	if weapon.has_form(&"boomerang") and player != null:
		enqueue({"kind": &"return_arc", "path": [player.global_position, position],
			"damage": projectile.damage * 0.5, "color": projectile.color_index,
			"budget": projectile.budget, "weapon": weapon, "attribution": &"cannon",
			"clone": projectile.source_kind == &"clone"})


## Transfer live area attacks to the same bounded orbit system as projectiles.
func absorb_nearby_attacks(hole: BlackHoleField, limit: int) -> int:
	var count := 0
	for spec in [{"form": &"sword", "list": _sword_waves}, {"form": &"wave", "list": _wave_pulses}, {"form": &"scythe", "list": _scythe_sweeps}]:
		var list: Array = spec.list
		for i in range(list.size() - 1, -1, -1):
			if count >= limit:
				return count
			var original: Dictionary = list[i]
			var at: Vector2 = original.origin
			if spec.form == &"sword":
				var progress := clampf(float(original.age) / SWORD_WAVE_DURATION, 0.0, 1.0)
				var distance := lerpf(22.0, SWORD_WAVE_DISTANCE * float(original.get("size_scale", 1.0)), 1.0 - progress if original.returning else progress)
				if (original.weapon as WeaponRuntime).has_form(&"sprite"):
					distance *= 1.22
				at += (original.direction as Vector2) * distance
			elif spec.form == &"wave":
				at = original.position
			elif spec.form == &"scythe":
				var turn := -1.0 if bool(original.get("reverse", false)) else 1.0
				var angle := (original.direction as Vector2).angle() + turn * TAU * clampf(float(original.age) / SCYTHE_SWEEP_DURATION, 0.0, 1.0)
				at += Vector2.from_angle(angle) * float(original.radius) * 0.82
			var shape_reach := 16.0 if spec.form == &"scythe" else 54.0 * float(original.get("size_scale", 1.0))
			if at.distance_squared_to(hole.global_position) > (hole.effect_radius() + 40.0 + shape_reach) ** 2:
				continue
			var attack := _make_absorbed_attack(original, spec.form, at)
			if not hole.capture_weapon_attack(attack, at):
				return count
			if not bool(attack.get("consumed", false)):
				_absorbed_attacks.append(attack)
			list.remove_at(i)
			if spec.form == &"scythe":
				_visuals.erase(original)
				var trail: Polygon2D = original.get("trail")
				if trail != null:
					trail.hide()
					_scythe_trail_pool.append(trail)
			count += 1
	_request_redraw()
	return count


func _make_absorbed_attack(original: Dictionary, form: StringName, at: Vector2) -> Dictionary:
	var weapon: WeaponRuntime = original.weapon
	var hits: Dictionary = original.get("hit_ids", original.get("hits", {})).duplicate()
	for id in original.get("return_ids", {}):
		hits[id] = true
	return {"form": form, "damage": float(original.damage) * (0.65 if original.get("returning", false) else 1.0),
		"kind": form, "secondary": original.get("secondary", false), "summon_scale": original.get("summon_scale", 1.0),
		"color": original.color, "heavy": original.get("heavy", false), "weapon": weapon,
		"budget": original.budget, "clone": original.get("clone", false), "hit_ids": hits,
		"remaining": maxi(0, 1 + int(weapon.stats.get_value(&"pierce")) - hits.size()),
		"position": at, "angle": (original.direction as Vector2).angle(), "visual_scale": 1.0,
		"hit_radius": 12.0 if form == &"lightning" else (54.0 * float(original.get("size_scale", 1.0))),
		"size_scale": original.get("size_scale", 1.0)}


func _absorb_lightning_segment(event: Dictionary, origin: Vector2, aim: Vector2, reach: float) -> bool:
	var nearest: BlackHoleField
	var distance := reach
	for node in get_tree().get_nodes_in_group(&"friendly_aim_targets"):
		var hole := node as BlackHoleField
		if hole == null or not hole.can_be_targeted():
			continue
		var offset := hole.global_position - origin
		var along := offset.dot(aim)
		if along < 0.0 or along > distance or absf(offset.cross(aim)) > hole.effect_radius() + 40.0:
			continue
		nearest = hole
		distance = along
	if nearest == null:
		return false
	var at := origin + aim * distance
	var attack := _make_absorbed_attack(event, &"lightning", at)
	if not nearest.capture_weapon_attack(attack, at):
		return false
	if not bool(attack.get("consumed", false)):
		_absorbed_attacks.append(attack)
	_add_visual({"kind": &"line", "from": origin, "to": at, "color": event.color, "time": 0.17})
	return true


func hit_absorbed_attack(attack: Dictionary, enemy: Enemy, direction: Vector2) -> void:
	var id := enemy.get_instance_id()
	if int(attack.remaining) <= 0 or attack.hit_ids.has(id):
		return
	var first: bool = attack.hit_ids.is_empty()
	attack.hit_ids[id] = true
	attack.remaining = int(attack.remaining) - 1
	resolve_hit(self, enemy, float(attack.damage), int(attack.color), direction,
		bool(attack.heavy), &"clone" if attack.clone else StringName("weapon_%s" % attack.form),
		first, int(attack.remaining) == 0, true, attack.form, attack.weapon, true, attack.budget)
	if first and not bool(attack.secondary):
		attack.direction = direction
		if attack.form == &"sword":
			_sword_first_hit_effects(attack, enemy)
		elif attack.form in [&"wave", &"scythe"]:
			_nonprojectile_first_hit_effects(attack, enemy)
		elif attack.form == &"lightning" and (attack.weapon as WeaponRuntime).has_form(&"star"):
			enqueue({"kind": &"split", "origin": enemy.global_position, "direction": direction,
				"damage_scale": float(attack.damage) * 0.5 / maxf(0.001, _weapon_damage(attack.weapon.stats, int(attack.color), false)),
				"color": attack.color, "weapon": attack.weapon, "budget": attack.budget, "clone": attack.clone})


func release_absorbed_attack(attack: Dictionary) -> void:
	_absorbed_attacks.erase(attack)
	_request_redraw()


func _draw_absorbed_attack(attack: Dictionary) -> void:
	var shrink := float(attack.visual_scale)
	draw_set_transform(to_local(attack.position), float(attack.angle), Vector2.ONE * shrink)
	var c := RunState.color_of(int(attack.color))
	match attack.form:
		&"sword":
			var distance := lerpf(22.0, SWORD_WAVE_DISTANCE * float(attack.size_scale), 0.18)
			_draw_sword_wave({"origin": global_position - Vector2.RIGHT * distance, "direction": Vector2.RIGHT,
				"age": SWORD_WAVE_DURATION * 0.18, "returning": false, "size_scale": attack.size_scale,
				"weapon": attack.weapon, "color": attack.color})
		&"wave":
			_draw_wave_visual({"age": 0.15, "duration": 1.0, "direction": Vector2.RIGHT,
				"position": global_position}, c)
		&"scythe":
			var center := global_position - Vector2.from_angle(TAU * 0.12 / SCYTHE_SWEEP_DURATION) * 70.0 * 0.82
			_draw_scythe_visual({"origin": center, "direction": Vector2.RIGHT,
				"age": 0.12, "radius": 70.0}, c)
		&"lightning":
			draw_polyline(PackedVector2Array([Vector2(-16, 0), Vector2(-5, -6), Vector2(0, 4), Vector2(6, -4), Vector2(16, 0)]), c, 2.0, true)
	draw_set_transform(Vector2.ZERO)


func _sword(event: Dictionary) -> void:
	Audio.play(&"weapon_sword")
	if _sword_waves.size() >= 48:
		return
	_sword_waves.append({
		"origin": event.origin, "direction": (event.direction as Vector2).normalized(),
		"age": 0.0, "returning": false, "hit_ids": event.get("excluded_ids", {}).duplicate(), "return_ids": event.get("excluded_ids", {}).duplicate(),
		"first_hit": true, "damage": event.damage, "color": event.color,
		"heavy": event.heavy, "weapon": event.weapon, "budget": event.budget,
		"secondary": event.secondary, "clone": event.get("clone", false),
		"summon_scale": event.get("summon_scale", 1.0),
		"size_scale": event.get("size_scale", 1.0),
		"finisher": event.get("finisher", false),
		"can_return": (not bool(event.secondary) or bool(event.get("finisher", false))) and (event.weapon as WeaponRuntime).has_form(&"boomerang"),
	})
	_request_redraw()


func _advance_sword_waves(delta: float) -> void:
	for i in range(_sword_waves.size() - 1, -1, -1):
		var wave: Dictionary = _sword_waves[i]
		wave.age = float(wave.age) + delta
		if float(wave.age) >= SWORD_WAVE_DURATION:

			if bool(wave.can_return) and not bool(wave.returning):
				wave.returning = true
				wave.age = 0.0
			else:
				_sword_waves.remove_at(i)
				_request_redraw()
				continue
		var progress := clampf(float(wave.age) / SWORD_WAVE_DURATION, 0.0, 1.0)
		var distance := lerpf(22.0, SWORD_WAVE_DISTANCE * float(wave.get("size_scale", 1.0)), 1.0 - progress if bool(wave.returning) else progress)
		if (wave.weapon as WeaponRuntime).has_form(&"sprite"):
			distance *= 1.22
		var direction: Vector2 = wave.direction
		var position: Vector2 = wave.origin + direction * distance
		if (not bool(wave.secondary) or bool(wave.finisher)) and not bool(wave.returning) and (wave.weapon as WeaponRuntime).has_form(&"cannon"):
			var last_blast: float = float(wave.get("last_blast", 0.0))
			if distance - last_blast >= 36.0:
				wave.last_blast = distance
				enqueue({"kind": &"explosion", "origin": position,
					"damage": float(wave.damage) * 0.45, "radius": 52.0,
					"color": wave.color, "weapon": wave.weapon,
					"budget": wave.budget, "secondary": true,
					"clone": wave.clone})
		var side := direction.orthogonal()
		var hit_ids: Dictionary = wave.return_ids if bool(wave.returning) else wave.hit_ids
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or hit_ids.has(enemy.get_instance_id()):
				continue
			var offset := enemy.global_position - position
			if absf(offset.dot(direction)) > SWORD_WAVE_DEPTH * 0.5 * float(wave.get("size_scale", 1.0)) + enemy.radius \
					or absf(offset.dot(side)) > SWORD_WAVE_WIDTH * 0.5 * float(wave.get("size_scale", 1.0)) + enemy.radius:
				continue
			hit_ids[enemy.get_instance_id()] = true
			var first := bool(wave.first_hit)
			wave.first_hit = false
			resolve_hit(self, enemy, float(wave.damage) * (0.65 if bool(wave.returning) else 1.0),
				int(wave.color), direction, bool(wave.heavy) and not bool(wave.returning),
				&"clone" if bool(wave.clone) else &"weapon_sword", first, true, true,
				&"sword", wave.weapon, true, wave.budget)
			enemy.apply_knockback(wave.origin, 220.0, 0.16)
			if first and not bool(wave.secondary) and not bool(wave.returning):
				_sword_first_hit_effects(wave, enemy)


func _sword_first_hit_effects(wave: Dictionary, enemy: Enemy) -> void:
	var weapon: WeaponRuntime = wave.weapon
	if weapon.has_form(&"lightning"):
		enqueue({"kind": &"lightning", "origin": enemy.global_position,
			"direction": wave.direction, "damage": float(wave.damage) * 0.5,
			"color": wave.color, "heavy": false, "weapon": weapon,
			"budget": wave.budget, "secondary": true, "excluded": enemy,
			"clone": wave.clone})
	if weapon.has_form(&"star"):
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": wave.direction, "damage_scale": 0.6 * float(wave.summon_scale),
			"color": wave.color, "weapon": weapon, "budget": wave.budget,
			"clone": wave.clone})


func _draw_sword_wave(wave: Dictionary) -> void:
	_sword_draw_scale = float(wave.get("size_scale", 1.0))
	var progress := clampf(float(wave.age) / SWORD_WAVE_DURATION, 0.0, 1.0)
	var fade := pow(1.0 - progress, 1.25) * (0.72 if bool(wave.returning) else 1.0)
	var distance := lerpf(22.0, SWORD_WAVE_DISTANCE * float(wave.get("size_scale", 1.0)), 1.0 - progress if bool(wave.returning) else progress)
	if (wave.weapon as WeaponRuntime).has_form(&"sprite"):
		distance *= 1.22
	var direction: Vector2 = wave.direction
	var center: Vector2 = to_local(wave.origin + direction * distance)
	var side := direction.orthogonal()
	var color := RunState.color_of(int(wave.color))
	# 单条弧形刀气，起止端分列瞄准轴两侧；层叠色带形成长尾和刀锋高光。
	_draw_sword_ribbon(center, direction, side, color, fade, Vector2.ZERO, 17.0, 0.26)
	_draw_sword_ribbon(center, direction, side, color, fade, Vector2(-7.0, 0.0), 7.0, 0.35)
	_draw_sword_ribbon(center, direction, side, color.lerp(Color.WHITE, 0.5), fade,
		Vector2(2.0, 0.0), 3.0, 0.9)
	_draw_sword_ribbon(center, direction, side, color.lerp(Color.WHITE, 0.7), fade,
		Vector2(6.0, 0.0), 1.1, 0.55)


func _draw_sword_ribbon(center: Vector2, forward: Vector2, side: Vector2,
		color: Color, fade: float, shift: Vector2, thickness: float, opacity: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var left_colors := PackedColorArray()
	var right_colors := PackedColorArray()
	for i in 19:
		var t := float(i) / 18.0
		var point := _sword_curve(t) * _sword_draw_scale
		var tangent := (_sword_curve(minf(1.0, t + 0.01)) - _sword_curve(maxf(0.0, t - 0.01))).normalized()
		var normal := tangent.orthogonal()
		var taper := pow(sin(PI * t), 0.65)
		var width := thickness * _sword_draw_scale * taper * (0.55 + 0.45 * t)
		var base := center + forward * (point.x + shift.x) + side * (point.y + shift.y)
		var normal_world := forward * normal.x + side * normal.y
		left.append(base - normal_world * width)
		right.append(base + normal_world * width)
		var alpha := opacity * fade * taper
		left_colors.append(Color(color.r, color.g, color.b, alpha * 0.25))
		right_colors.append(Color(color.r, color.g, color.b, alpha))
	var points := left.duplicate()
	var colors := left_colors
	for i in range(18, -1, -1):
		points.append(right[i])
		colors.append(right_colors[i])
	draw_polygon(points, colors)


func _sword_curve(t: float) -> Vector2:
	var u := 1.0 - t
	return Vector2(-24.0, 53.0) * (u * u * u) \
		+ Vector2(55.0, 51.0) * (3.0 * u * u * t) \
		+ Vector2(55.0, -51.0) * (3.0 * u * t * t) \
		+ Vector2(-24.0, -53.0) * (t * t * t)


func _lightning(event: Dictionary) -> void:
	var weapon: WeaponRuntime = event.weapon
	var origin: Vector2 = event.origin
	var previous: Enemy = event.get("excluded") as Enemy
	var visited := {}
	if previous != null:
		visited[previous.get_instance_id()] = true
	var path: Array[Vector2] = [origin]
	var pierce := maxi(0, int(weapon.stats.get_value(&"pierce")))
	var total := (1 if bool(event.secondary) else 2) + pierce + maxi(0, int(weapon.stats.get_value(&"ricochet")))
	for hop in total:
		var best: Enemy
		var best_distance := INF
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or enemy == previous:
				continue
			if hop >= total - pierce and visited.has(enemy.get_instance_id()):
				continue
			var offset := enemy.global_position - origin
			var dist := offset.length_squared()
			var reach := (620.0 if hop == 0 and not bool(event.secondary) else CHAIN_RANGE)
			if weapon.has_form(&"sprite"):
				reach += 100.0
			if dist > reach ** 2:
				continue
			if hop == 0 and not bool(event.secondary) and absf((event.direction as Vector2).angle_to(offset)) > PI / 4.0:
				continue
			if dist < best_distance:
				best = enemy
				best_distance = dist
		var aim: Vector2 = (best.global_position - origin).normalized() if best != null else event.direction
		var absorb_reach := sqrt(best_distance) if best != null else (620.0 if hop == 0 else CHAIN_RANGE)
		var segment := event.duplicate()
		segment.hit_ids = visited.duplicate()
		segment.damage = float(event.damage) * (0.5 if hop >= total - pierce else 1.0)
		if _absorb_lightning_segment(segment, origin, aim, absorb_reach):
			break
		if best == null:
			break
		var damage := float(event.damage) * (0.5 if hop >= total - pierce else 1.0)
		resolve_hit(self, best, damage, int(event.color),
			(best.global_position - origin).normalized(), bool(event.heavy),
			&"clone" if bool(event.get("clone", false)) else &"weapon_lightning",
			hop == 0, hop == total - 1, true, &"lightning", weapon, true, event.budget)
		_add_visual({"kind": &"line", "from": origin, "to": best.global_position,
			"color": event.color, "time": 0.17})
		origin = best.global_position
		path.append(origin)
		visited[best.get_instance_id()] = true
		previous = best
	if not bool(event.secondary) and path.size() > 1:
		if weapon.has_form(&"star"):
			enqueue({"kind": &"split", "origin": origin,
				"direction": event.direction, "damage_scale": float(event.damage) * 0.5 / maxf(0.001, _weapon_damage(weapon.stats, int(event.color), false)),
				"color": event.color, "weapon": weapon, "budget": event.budget,
				"clone": event.get("clone", false)})
		if weapon.has_form(&"boomerang"):
			enqueue({"kind": &"return_arc", "path": path, "damage": float(event.damage) * 0.5,
				"color": event.color, "budget": event.budget, "weapon": weapon,
				"clone": event.get("clone", false)})
		if weapon.has_form(&"sword"):
			enqueue({"kind": &"sword", "origin": origin,
				"direction": event.direction, "damage": float(event.damage) * 0.6,
				"color": event.color, "heavy": false, "weapon": weapon,
				"budget": event.budget, "secondary": true,
				"clone": event.get("clone", false)})


func _split(event: Dictionary) -> void:
	var weapon: WeaponRuntime = event.weapon
	for i in 5:
		var angle := (event.direction as Vector2).angle() + TAU * float(i) / 5.0
		var direction := Vector2.from_angle(angle)
		var budget: Dictionary = event.budget
		if int(budget.spawned) >= DERIVATIVES_PER_ATTACK:
			break
		budget.spawned = int(budget.spawned) + 1
		manager.fire(event.origin + direction * 12.0, direction, weapon.stats,
			int(event.color), weapon.core, false, float(event.damage_scale),
			0.65, 1.0, 0.7, false,
			&"clone" if bool(event.get("clone", false)) else &"weapon:star",
			event.weapon, budget, false, &"star")


func _return_arc(event: Dictionary) -> void:
	var path: Array = event.path
	var hit_ids := {}
	for i in range(path.size() - 1, 0, -1):
		var start: Vector2 = path[i]
		var finish: Vector2 = path[i - 1]
		_add_visual({"kind": &"line", "from": start, "to": finish,
			"color": event.color, "time": 0.17})
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or hit_ids.has(enemy.get_instance_id()):
				continue
			if Geometry2D.get_closest_point_to_segment(enemy.global_position, start, finish).distance_to(enemy.global_position) <= enemy.radius + 8.0:
				hit_ids[enemy.get_instance_id()] = true
				resolve_hit(self, enemy, float(event.damage), int(event.color),
					(finish - start).normalized(), false,
					&"clone" if bool(event.get("clone", false)) else &"weapon_lightning",
					false, true, true, event.get("attribution", &"lightning"), event.get("weapon"), true, event.budget)


func _explosion(event: Dictionary) -> void:
	Audio.play(&"weapon_hit_cannon")
	var origin: Vector2 = event.origin
	var radius: float = float(event.radius)
	_add_visual({"kind": &"explosion", "origin": origin, "radius": radius,
		"color": event.color, "time": 0.22})
	var excluded: Enemy = event.get("excluded") as Enemy
	var weapon: WeaponRuntime = event.get("weapon") as WeaponRuntime
	var first := true
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead or enemy == excluded:
			continue
		if enemy.global_position.distance_squared_to(origin) > (radius + enemy.radius) ** 2:
			continue
		resolve_hit(self, enemy, float(event.damage), int(event.color),
			(enemy.global_position - origin).normalized(), false,
			&"clone" if bool(event.get("clone", false)) else &"weapon_cannon",
			first, true, true, &"cannon", weapon, false, event.budget)
		if weapon != null and weapon.has_form(&"wave") and not enemy.is_dead:
			enemy.apply_water_push((enemy.global_position - origin).normalized())
		first = false


func _wave(event: Dictionary) -> void:
	if _wave_pulses.size() >= 64:
		return
	var weapon: WeaponRuntime = event.weapon
	var wave := event.duplicate()
	wave.direction = (event.direction as Vector2).normalized()
	wave.age = 0.0
	wave.distance = 22.0
	wave.reach = WAVE_RANGE + maxi(0, int(weapon.stats.get_value(&"pierce"))) * 20.0
	if weapon.has_form(&"sprite"):
		wave.reach += 50.0
	wave.speed = WAVE_SPEED * maxf(0.25, weapon.stats.get_value(&"projectile_speed") / 720.0)
	wave.duration = (float(wave.reach) - 22.0) / float(wave.speed)
	wave.position = event.origin + wave.direction * 22.0
	wave.hits = {}
	for id in event.get("excluded_ids", {}):
		wave.hits[id] = 3
	wave.ricochets = event.get("ricochets", int(weapon.stats.get_value(&"ricochet")))
	wave.next_hits = {}
	wave.first_hit = true
	_wave_pulses.append(wave)


func _advance_water_waves(delta: float) -> void:
	for i in range(_wave_pulses.size() - 1, -1, -1):
		var wave: Dictionary = _wave_pulses[i]
		wave.age = float(wave.age) + delta
		wave.distance = minf(float(wave.reach), 22.0 + float(wave.speed) * float(wave.age))
		wave.position = wave.origin + wave.direction * float(wave.distance)
		var direction: Vector2 = wave.direction
		var side := direction.orthogonal()
		var weapon: WeaponRuntime = wave.weapon
		var half_width := WAVE_HALF_WIDTH + maxi(0, int(weapon.stats.get_value(&"pierce"))) * 5.0
		for node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead:
				continue
			var id := enemy.get_instance_id()
			var count := int(wave.hits.get(id, 0))
			if count >= 3 or float(wave.age) < float(wave.next_hits.get(id, 0.0)):
				continue
			var offset := enemy.global_position - (wave.position as Vector2)
			if absf(offset.dot(direction)) > WAVE_DEPTH * 0.5 + enemy.radius \
					or absf(offset.dot(side)) > half_width + enemy.radius:
				continue
			wave.hits[id] = count + 1
			wave.next_hits[id] = float(wave.age) + 0.12
			resolve_hit(self, enemy, float(wave.damage), int(wave.color), direction,
				bool(wave.heavy), &"clone" if bool(wave.clone) else &"weapon_wave",
				bool(wave.first_hit), count == 2, true, &"wave", weapon, count == 0,
				wave.budget, count == 0)
			_queue_area_ricochet(wave, enemy, &"wave")
			if bool(wave.first_hit):
				_nonprojectile_first_hit_effects(wave, enemy)
				wave.first_hit = false
		if float(wave.age) >= float(wave.duration):
			_wave_pulses.remove_at(i)
			if not bool(wave.secondary) and weapon.has_form(&"boomerang"):
				enqueue({"kind": &"wave", "origin": wave.position,
					"direction": -direction, "damage": float(wave.damage) * 0.6,
					"color": wave.color, "heavy": false, "weapon": weapon,
					"budget": wave.budget, "secondary": true, "clone": wave.clone})


func _scythe(event: Dictionary) -> void:
	if _scythe_sweeps.size() >= 64:
		return
	if bool(event.secondary) and not bool(event.get("reverse", false)) and not bool(event.get("is_ricochet", false)):
		if _scythe_secondary_cooldown > 0.0:
			return
		var secondary_count := 0
		for active in _scythe_sweeps:
			if bool(active.secondary) and not bool(active.get("reverse", false)):
				secondary_count += 1
		if secondary_count >= 4:
			return
		_scythe_secondary_cooldown = SCYTHE_SECONDARY_COOLDOWN
	var weapon: WeaponRuntime = event.weapon
	Audio.play(&"weapon_scythe")
	var sweep := event.duplicate()
	sweep.kind = &"scythe"
	sweep.age = 0.0
	sweep.time = SCYTHE_SWEEP_DURATION
	sweep.hits = event.get("excluded_ids", {}).duplicate()
	sweep.ricochets = event.get("ricochets", int(weapon.stats.get_value(&"ricochet")))
	sweep.first_hit = true
	sweep.radius = float(event.get("radius", SCYTHE_RADIUS)) + maxi(0, int(weapon.stats.get_value(&"pierce"))) * 12.0
	if weapon.has_form(&"sprite"):
		sweep.radius += 25.0
	_scythe_sweeps.append(sweep)
	if _visuals.size() < VISUAL_LIMIT:
		var trail: Polygon2D
		if not _scythe_trail_pool.is_empty():
			trail = _scythe_trail_pool.pop_back()
		elif _scythe_trail_count < 24:
			trail = SCYTHE_TRAIL.new()
			trail.z_index = -1
			add_child(trail)
			_scythe_trail_count += 1
		if trail != null:
			trail.visible = true
			sweep.trail = trail
		_add_visual(sweep)


func _advance_scythe_sweeps(delta: float) -> void:
	for i in range(_scythe_sweeps.size() - 1, -1, -1):
		var sweep: Dictionary = _scythe_sweeps[i]
		sweep.age = float(sweep.age) + delta
		var weapon: WeaponRuntime = sweep.weapon
		var turn := -1.0 if bool(sweep.get("reverse", false)) else 1.0
		var covered := minf(TAU, float(sweep.age) / SCYTHE_SWEEP_DURATION * TAU)
		for node in get_tree().get_nodes_in_group(&"enemies"):
			if bool(sweep.secondary) and not bool(sweep.get("reverse", false)) and sweep.hits.size() >= 6:
				break
			var enemy := node as Enemy
			if enemy == null or enemy.is_dead or sweep.hits.has(enemy.get_instance_id()):
				continue
			var offset := enemy.global_position - (sweep.origin as Vector2)
			if offset.length_squared() > (float(sweep.radius) + enemy.radius) ** 2:
				continue
			var angle := fposmod((offset.angle() - (sweep.direction as Vector2).angle()) * turn, TAU)
			if angle > covered + 0.08:
				continue
			sweep.hits[enemy.get_instance_id()] = true
			resolve_hit(self, enemy, float(sweep.damage), int(sweep.color), offset.normalized(),
				bool(sweep.heavy), &"clone" if bool(sweep.clone) else &"weapon_scythe",
				bool(sweep.first_hit), true, true, &"scythe", weapon, true, sweep.budget)
			_queue_area_ricochet(sweep, enemy, &"scythe")
			if weapon.has_form(&"sword"):
				enemy.apply_knockback(sweep.origin, 185.0, 0.15)
			if bool(sweep.first_hit):
				_nonprojectile_first_hit_effects(sweep, enemy)
				sweep.first_hit = false
		if float(sweep.age) >= SCYTHE_SWEEP_DURATION:
			_scythe_sweeps.remove_at(i)
			if not bool(sweep.secondary) and weapon.has_form(&"sword"):
				enqueue({"kind": &"sword", "origin": sweep.origin,
					"direction": sweep.direction, "damage": float(sweep.damage) * 1.2 / 2.5,
					"color": sweep.color, "heavy": false, "weapon": weapon,
					"budget": sweep.budget, "secondary": true, "clone": sweep.clone,
					"size_scale": 1.6, "finisher": true})
			if not bool(sweep.secondary) and weapon.has_form(&"boomerang"):
				enqueue({"kind": &"scythe", "origin": sweep.origin,
					"direction": sweep.direction, "damage": float(sweep.damage) * 0.55,
					"color": sweep.color, "heavy": false, "weapon": weapon,
					"budget": sweep.budget, "secondary": true, "clone": sweep.clone,
					"reverse": true})


## Area forms translate a bounce into one redirected follow-up of that same form.
## Always enqueue; the transferred counter prevents recursive follow-up chains.
func _queue_area_ricochet(attack: Dictionary, enemy: Enemy, form: StringName) -> void:
	if form == &"sword":
		return
	var remaining := int(attack.get("ricochets", 0))
	if remaining <= 0:
		return
	var excluded: Dictionary = attack.get("hit_ids", attack.get("hits", {})).duplicate()
	excluded[enemy.get_instance_id()] = true
	var reach := SCYTHE_RADIUS if form == &"scythe" else (SWORD_WAVE_DISTANCE if form == &"sword" else WAVE_RANGE)
	var next: Enemy = manager.guidance_target(enemy.global_position, reach, excluded)
	if next == null:
		return
	attack.ricochets = 0
	enqueue({"kind": form, "origin": enemy.global_position,
		"direction": (next.global_position - enemy.global_position).normalized(),
		"damage": attack.damage, "color": attack.color, "heavy": attack.heavy,
		"weapon": attack.weapon, "budget": attack.budget, "secondary": true,
		"clone": attack.get("clone", false), "ricochets": remaining - 1,
		"excluded_ids": excluded, "is_ricochet": true,
		"summon_scale": attack.get("summon_scale", 1.0), "size_scale": attack.get("size_scale", 1.0)})


func _nonprojectile_first_hit_effects(event: Dictionary, enemy: Enemy) -> void:
	if bool(event.secondary):
		return
	var weapon: WeaponRuntime = event.weapon
	if weapon.has_form(&"lightning"):
		enqueue({"kind": &"lightning", "origin": enemy.global_position,
			"direction": event.direction, "damage": float(event.damage) * 0.5,
			"color": event.color, "heavy": false, "weapon": weapon,
			"budget": event.budget, "secondary": true, "excluded": enemy,
			"clone": event.clone})
	if weapon.has_form(&"star"):
		enqueue({"kind": &"split", "origin": enemy.global_position,
			"direction": event.direction, "damage_scale": float(event.damage) * 0.5 / maxf(0.001, _weapon_damage(weapon.stats, int(event.color), false)),
			"color": event.color, "weapon": weapon,
			"budget": event.budget, "clone": event.clone})
	if weapon.has_form(&"sword") and event.get("kind") != &"scythe":
		enqueue({"kind": &"sword", "origin": enemy.global_position,
			"direction": event.direction, "damage": float(event.damage) * 0.6,
			"color": event.color, "heavy": false, "weapon": weapon,
			"budget": event.budget, "secondary": true, "clone": event.clone})


func _water_echo(event: Dictionary) -> void:
	var target: Variant = (event.target as WeakRef).get_ref()
	if not is_instance_valid(target) or target.is_dead:
		return
	resolve_hit(self, target, float(event.damage), int(event.color), event.direction,
		false, event.source_kind, false, false, true, event.weapon_id,
		event.weapon, false, event.budget, false)
	target.apply_water_push(event.direction)


func _request_redraw() -> void:
	_redraw_dirty = true

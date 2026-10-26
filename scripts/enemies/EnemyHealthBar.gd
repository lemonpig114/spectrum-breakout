class_name EnemyHealthBar
extends Node2D

## 与敌人身体分离的绘制缓存：生命条与小状态图标独立刷新，不重建敌人轮廓。
var current := 0.0
var maximum := 1.0
var body_radius := 12.0
var tint := Color.WHITE
var burn := false
var poison := false
var ice := false
var fragile := false
var _burn_pulse := 0.0
var _poison_pulse := 0.0
var _ice_pulse := 0.0
var _pulse_redraw_accum := 0.0
const PULSE_TIME := 0.16
const PULSE_REDRAW_STEP := 0.05


func _ready() -> void:
	set_process(false)


func set_statuses(has_burn: bool, has_poison: bool, has_ice: bool, has_fragile: bool = false) -> void:
	if burn == has_burn and poison == has_poison and ice == has_ice and fragile == has_fragile:
		return
	burn = has_burn
	poison = has_poison
	ice = has_ice
	fragile = has_fragile
	queue_redraw()


func pulse_status(kind: StringName) -> void:
	match kind:
		&"burn":
			_burn_pulse = PULSE_TIME
		&"poison":
			_poison_pulse = PULSE_TIME
		&"ice":
			_ice_pulse = PULSE_TIME
		_:
			return
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_burn_pulse = maxf(0.0, _burn_pulse - delta)
	_poison_pulse = maxf(0.0, _poison_pulse - delta)
	_ice_pulse = maxf(0.0, _ice_pulse - delta)
	_pulse_redraw_accum += delta
	var done := _burn_pulse <= 0.0 and _poison_pulse <= 0.0 and _ice_pulse <= 0.0
	if _pulse_redraw_accum >= PULSE_REDRAW_STEP or done:
		_pulse_redraw_accum = 0.0
		queue_redraw()
	if done:
		set_process(false)


func refresh(value: float, max_value: float, enemy_radius: float, color: Color) -> void:
	var old_width := roundi(body_radius * 2.0 * clampf(current / maximum, 0.0, 1.0)) if maximum > 0.0 else 0
	var new_width := roundi(enemy_radius * 2.0 * clampf(value / max_value, 0.0, 1.0)) if max_value > 0.0 else 0
	var was_visible := current < maximum and current > 0.0
	var is_visible := value < max_value and value > 0.0
	var needs_redraw := was_visible != is_visible or (is_visible and (old_width != new_width or body_radius != enemy_radius or tint != color))
	current = value
	maximum = max_value
	body_radius = enemy_radius
	tint = color
	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	if current < maximum and current > 0.0 and maximum > 0.0:
		var width := body_radius * 2.0
		var y := -body_radius - 8.0
		draw_rect(Rect2(-width * 0.5, y, width, 2.0), Color(1.0, 1.0, 1.0, 0.18))
		draw_rect(Rect2(-width * 0.5, y, width * clampf(current / maximum, 0.0, 1.0), 2.0),
			Color(tint.r, tint.g, tint.b, 0.9))
	_draw_statuses()


func _draw_statuses() -> void:
	var show_burn := burn or _burn_pulse > 0.0
	var show_poison := poison or _poison_pulse > 0.0
	var show_ice := ice or _ice_pulse > 0.0
	var count := int(show_burn) + int(show_poison) + int(show_ice) + int(fragile)
	if count == 0:
		return
	var x := -float(count - 1) * 6.5
	var y := body_radius + 10.0
	if show_burn:
		_draw_status_icon(x, y, &"burn", _burn_pulse)
		x += 13.0
	if show_poison:
		_draw_status_icon(x, y, &"poison", _poison_pulse)
		x += 13.0
	if show_ice:
		_draw_status_icon(x, y, &"ice", _ice_pulse)
		x += 13.0
	if fragile:
		_draw_status_icon(x, y, &"fragile", 0.0)


func _draw_status_icon(x: float, y: float, kind: StringName, pulse: float) -> void:
	var progress := pulse / PULSE_TIME
	var scale_value := 1.0 + 0.22 * progress
	draw_set_transform(Vector2(x, y - 3.0 * progress), 0.0, Vector2.ONE * scale_value)
	draw_rect(Rect2(-5.5, -5.5, 11.0, 11.0), Color(0.015, 0.025, 0.055, 0.78))
	match kind:
		&"burn":
			draw_colored_polygon(PackedVector2Array([
				Vector2(-3.5, 4.0), Vector2(-2.5, -1.0), Vector2(0.0, -5.0),
				Vector2(1.0, 0.0), Vector2(3.0, -2.0), Vector2(3.5, 4.0),
			]), Color(2.5, 0.65, 0.2, 0.95))
		&"poison":
			draw_circle(Vector2(-2.0, -1.5), 1.8, Color(0.45, 2.2, 0.6, 0.95))
			draw_circle(Vector2(2.0, 1.5), 2.5, Color(0.45, 2.2, 0.6, 0.95))
		&"ice":
			var c := Color(0.5, 1.55, 2.6, 0.95)
			draw_line(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), c, 1.4, true)
			draw_line(Vector2(0.0, -4.0), Vector2(0.0, 4.0), c, 1.4, true)
			draw_line(Vector2(-3.0, -3.0), Vector2(3.0, 3.0), c, 1.0, true)
			draw_line(Vector2(-3.0, 3.0), Vector2(3.0, -3.0), c, 1.0, true)
		&"fragile":
			var c := Color(1.7, 0.55, 1.25, 0.95)
			draw_line(Vector2(-3.0, -4.0), Vector2(1.0, -1.0), c, 1.5, true)
			draw_line(Vector2(1.0, -1.0), Vector2(-1.0, 1.0), c, 1.5, true)
			draw_line(Vector2(-1.0, 1.0), Vector2(3.0, 4.0), c, 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

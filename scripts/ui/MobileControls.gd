class_name MobileControls
extends Control

## 浮动式单摇杆：左下区域移动，其余游戏区域轻点/横滑/长按切色。
## 使用触点 index，允许一根手指移动时另一根手指独立切色。
const JOYSTICK_RADIUS := 68.0
const DEAD_ZONE := 10.0
const FULL_SPEED_DISTANCE := 57.0
const REPOSITION_DISTANCE := 106.0

var _player: Player
var _pause_button: Control
var _relic_panel: RelicChoicePanel
var _modal_panels: Array[Control] = []
var _move_index := -1
var _switch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var _pulse := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _exit_tree() -> void:
	_reset_touches()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_reset_touches()


func bind(player: Player, pause_button: Control, relic_panel: RelicChoicePanel,
		modal_panels: Array[Control]) -> void:
	_player = player
	_pause_button = pause_button
	_relic_panel = relic_panel
	_modal_panels = modal_panels
	visible = _can_play()


func _process(delta: float) -> void:
	var active := _can_play()
	if not active and (_move_index >= 0 or _switch_index >= 0):
		_reset_touches()
	if visible != active:
		visible = active
		queue_redraw()
	if _move_index >= 0:
		_pulse += delta
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not GameInput.touch_controls_active:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not _can_play():
				return
			if _move_index < 0 and _is_move_zone(touch.position):
				_begin_move(touch.index, touch.position)
				get_viewport().set_input_as_handled()
			elif _switch_index < 0 and not _is_ui_point(touch.position):
				_switch_index = touch.index
				_player.begin_touch_switch(touch.position)
				get_viewport().set_input_as_handled()
		elif touch.index == _move_index:
			_end_move()
			get_viewport().set_input_as_handled()
		elif touch.index == _switch_index:
			_switch_index = -1
			if _can_play():
				_player.finish_touch_switch(touch.position)
			else:
				_player.cancel_touch_switch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _move_index:
			_update_move(drag.position)
			get_viewport().set_input_as_handled()
		elif drag.index == _switch_index:
			_player.update_touch_switch(drag.position)
			get_viewport().set_input_as_handled()


func _can_play() -> bool:
	if not GameInput.touch_controls_active or _player == null or not is_instance_valid(_player):
		return false
	if not _player.controls_enabled or not RunState.is_running or RunState.is_dead or get_tree().paused:
		return false
	for panel in _modal_panels:
		if panel != null and panel.visible:
			return false
	return true


func _is_move_zone(point: Vector2) -> bool:
	return point.x < size.x * 0.43 and point.y > size.y * 0.34


func _is_ui_point(point: Vector2) -> bool:
	if point.y < 76.0:
		return true
	if _pause_button != null and _pause_button.get_global_rect().has_point(point):
		return true
	if _relic_panel != null and _relic_panel.visible and _relic_panel._card != null:
		return _relic_panel._card.get_global_rect().has_point(point)
	return false


func _begin_move(index: int, point: Vector2) -> void:
	_move_index = index
	_base = point
	_knob = point
	_pulse = 0.0
	GameInput.mobile_move_direction = Vector2.ZERO
	queue_redraw()


func _update_move(point: Vector2) -> void:
	var displacement := point - _base
	var distance := displacement.length()
	if distance > REPOSITION_DISTANCE:
		# 拖过外环时基座缓慢追上手指，避免长时间顶在硬边界。
		_base += displacement.normalized() * (distance - REPOSITION_DISTANCE) * 0.32
		displacement = point - _base
		distance = displacement.length()
	_knob = _base + displacement.limit_length(JOYSTICK_RADIUS)
	if distance <= DEAD_ZONE:
		GameInput.mobile_move_direction = Vector2.ZERO
	else:
		var amount := clampf((distance - DEAD_ZONE) / (FULL_SPEED_DISTANCE - DEAD_ZONE), 0.0, 1.0)
		var strength := smoothstep(0.0, 1.0, amount)
		GameInput.mobile_move_direction = displacement.normalized() * strength
	queue_redraw()


func _end_move() -> void:
	_move_index = -1
	GameInput.mobile_move_direction = Vector2.ZERO
	queue_redraw()


func _reset_touches() -> void:
	_end_move()
	if _switch_index >= 0 and _player != null and is_instance_valid(_player):
		_player.cancel_touch_switch()
	_switch_index = -1


func _draw() -> void:
	if _move_index < 0:
		return
	var cyan := Color(0.32, 1.12, 1.42)
	var base_alpha := 0.52 + 0.05 * sin(_pulse * 3.5)
	var offset := _knob - _base
	var magnitude := clampf(offset.length() / JOYSTICK_RADIUS, 0.0, 1.0)
	# 透明底盘、错开的刻度与短弧，和角色光谱特效保持同一线宽语言。
	draw_circle(_base, JOYSTICK_RADIUS + 17.0, Color(0.08, 0.58, 1.2, 0.045))
	draw_circle(_base, JOYSTICK_RADIUS + 13.0, Color(0.03, 0.09, 0.14, 0.13))
	draw_circle(_base, JOYSTICK_RADIUS, Color(0.05, 0.13, 0.19, 0.18))
	for quadrant in 4:
		var start := float(quadrant) * PI * 0.5 + 0.16
		draw_arc(_base, JOYSTICK_RADIUS, start, start + PI * 0.5 - 0.32, 12,
			Color(cyan.r, cyan.g, cyan.b, base_alpha), 2.2, true)
	for tick in 8:
		var angle := float(tick) * TAU / 8.0
		var direction := Vector2.from_angle(angle)
		draw_line(_base + direction * 75.0, _base + direction * (81.0 if tick % 2 == 0 else 78.0),
			Color(cyan.r, cyan.g, cyan.b, 0.35), 1.5, true)
	if magnitude > 0.03:
		draw_line(_base, _knob, Color(cyan.r, cyan.g, cyan.b, 0.20 + magnitude * 0.16),
			5.0, true)
	draw_circle(_knob, 34.0, Color(0.12, 0.72, 1.3, 0.075))
	draw_circle(_knob, 29.0, Color(0.06, 0.20, 0.27, 0.42))
	draw_circle(_knob, 23.0, Color(cyan.r, cyan.g, cyan.b, 0.11 + magnitude * 0.10))
	draw_arc(_knob, 25.0, 0.0, TAU, 28, Color(cyan.r, cyan.g, cyan.b, 0.70), 2.1, true)
	draw_circle(_knob, 4.0, Color(0.66, 1.0, 1.0, 0.65))

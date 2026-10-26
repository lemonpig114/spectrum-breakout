class_name AltarPanel
extends Control

## 恶魔/天使祭坛交易面板。和商店一样在暂停状态下运行，
## 只负责展示代价/奖励并调用 Altar.trade()；关闭后由 Main 让祭坛离场。

signal closed(traded: bool)

const PANEL_SIZE := Vector2(560.0, 360.0)
const BUTTON_SIZE := Vector2(196.0, 52.0)
const BUTTON_GAP := 22.0

var _altar: Altar
var _player: Player
var _font: Font
var _appear := 0.0
var _hover_button := -1
var _message := ""
var _message_time := 0.0
var _message_success := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_font = ThemeDB.fallback_font


func open(altar: Altar, player_node: Player) -> void:
	_altar = altar
	_player = player_node
	_appear = 0.0
	_hover_button = -1
	_message = ""
	_message_time = 0.0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_altar = null
	_player = null
	_hover_button = -1
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_font = ThemeDB.fallback_font
	_appear = minf(1.0, _appear + delta * 7.0)
	_message_time = maxf(0.0, _message_time - delta)
	queue_redraw()


func _trade() -> void:
	if _altar == null or not is_instance_valid(_altar):
		_finish(false)
		return
	if _player == null or not is_instance_valid(_player):
		_finish(false)
		return
	if not _altar.can_afford(_player):
		var message := "代价不足，无法交易"
		if _altar.side != &"demon":
			message = "金币不足，还差 %d" % maxi(0, _altar.gold_cost() - RunState.gold)
		_flash(message, false)
		return
	if not _altar.trade(_player):
		_flash("交易失败", false)
		return
	_finish(true)


func _leave() -> void:
	Audio.play(&"ui_click")
	_finish(false)


func _finish(traded: bool) -> void:
	close()
	closed.emit(traded)


func _flash(message: String, success: bool) -> void:
	_message = message
	_message_time = 1.6
	_message_success = success
	Audio.play(&"ui_buy" if success else &"ui_click")
	queue_redraw()


func _draw() -> void:
	if not visible or _font == null or _altar == null:
		return

	var ease := 1.0 - pow(1.0 - _appear, 3.0)
	var color := Altar.side_color(_altar.side)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.78 * ease))

	var panel := Rect2((size - PANEL_SIZE) * 0.5, PANEL_SIZE)
	panel.position.y += (1.0 - ease) * 16.0
	draw_rect(panel, Color(0.035, 0.035, 0.05, 0.98 * ease))
	draw_rect(panel, Color(1.0, 1.0, 1.0, 0.12 * ease), false, 1.4)
	draw_rect(
		Rect2(panel.position, Vector2(panel.size.x, 3.0)),
		Color(color.r, color.g, color.b, 0.9 * ease)
	)

	var title := "%s祭坛" % Altar.side_name(_altar.side)
	_text_centered(title, panel.position.y + 62.0, 34, Color(color.r, color.g, color.b, 0.98 * ease))
	_text_centered(
		"献上代价，换取%s的力量" % Altar.side_name(_altar.side),
		panel.position.y + 88.0,
		13,
		Color(1.0, 1.0, 1.0, 0.45 * ease)
	)

	var row_y := panel.position.y + 136.0
	var left := panel.position.x + 44.0
	var right := panel.position.x + PANEL_SIZE.x - 44.0

	# 代价
	draw_string(
		_font,
		Vector2(left, row_y),
		"代价",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		Color(1.0, 1.0, 1.0, 0.4 * ease)
	)
	draw_string(
		_font,
		Vector2(left, row_y + 26.0),
		_altar.cost_label(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		19,
		Color(1.0, 0.62, 0.5, 0.95 * ease)
	)

	# 奖励（右对齐）
	var reward_lines := _altar.reward_label().split("\n")
	for i in reward_lines.size():
		var line: String = reward_lines[i]
		var font_size := 19 if i == 0 else 12
		var line_color := (
			Color(color.r, color.g, color.b, 0.95 * ease)
			if i == 0
			else Color(1.0, 1.0, 1.0, 0.45 * ease)
		)
		var width := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(
			_font,
			Vector2(right - width, row_y + 26.0 + 20.0 * float(i)),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			line_color
		)
	draw_string(
		_font,
		Vector2(right - _font.get_string_size("奖励", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x, row_y),
		"奖励",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		Color(1.0, 1.0, 1.0, 0.4 * ease)
	)

	var divider_y := panel.position.y + 196.0
	draw_line(
		Vector2(panel.position.x + 32.0, divider_y),
		Vector2(panel.end.x - 32.0, divider_y),
		Color(1.0, 1.0, 1.0, 0.08 * ease),
		1.0
	)

	var status := "持有金币 %d" % RunState.gold
	if _altar.side == &"demon":
		status = ""
		if _player != null:
			status = "当前生命上限 %.1f 颗" % _player.max_health
	_text_centered(status, divider_y + 26.0, 13, Color(1.0, 1.0, 1.0, 0.5 * ease))

	var trade_rect := _button_rect(0, ease)
	var leave_rect := _button_rect(1, ease)
	var affordable := _altar.can_afford(_player)
	_draw_button(
		trade_rect,
		"交易",
		_hover_button == 0,
		affordable,
		ease,
		color
	)
	_draw_button(
		leave_rect,
		"离开",
		_hover_button == 1,
		true,
		ease,
		Color(0.7, 0.75, 0.8, 1.0)
	)

	_text_centered(
		"回车交易 · Esc 离开",
		panel.end.y - 22.0,
		12,
		Color(1.0, 1.0, 1.0, 0.32 * ease)
	)

	if _message_time > 0.0:
		var message_color := Color(0.55, 1.0, 0.6, 0.95) if _message_success \
			else Color(1.0, 0.45, 0.4, 0.95)
		_text_centered(_message, divider_y + 52.0, 13, message_color)


func _draw_button(
	rect: Rect2,
	label: String,
	hovered: bool,
	enabled: bool,
	alpha: float,
	accent: Color
) -> void:
	var border := 0.9 if hovered and enabled else 0.35
	if not enabled:
		border = 0.15
	draw_rect(rect, Color(0.06, 0.07, 0.1, 0.98 * alpha))
	draw_rect(
		rect,
		Color(accent.r, accent.g, accent.b, border * alpha),
		false,
		1.6
	)
	var text_color := Color(accent.r, accent.g, accent.b, (0.95 if enabled else 0.35) * alpha)
	draw_string(
		_font,
		rect.position + Vector2(0.0, rect.size.y * 0.5 + 6.0),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		17,
		text_color
	)


func _button_rect(index: int, ease: float) -> Rect2:
	var panel := Rect2((size - PANEL_SIZE) * 0.5, PANEL_SIZE)
	var total := BUTTON_SIZE.x * 2.0 + BUTTON_GAP
	var origin_x := panel.position.x + (PANEL_SIZE.x - total) * 0.5
	var y := panel.position.y + 262.0 + (1.0 - ease) * 16.0
	return Rect2(
		Vector2(origin_x + float(index) * (BUTTON_SIZE.x + BUTTON_GAP), y),
		BUTTON_SIZE
	)


func _button_at(point: Vector2) -> int:
	for index in 2:
		if _button_rect(index, 1.0).has_point(point):
			return index
	return -1


func _text_centered(text: String, baseline_y: float, font_size: int, color: Color) -> void:
	if _font == null:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(
		_font,
		Vector2((size.x - width) * 0.5, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var button := _button_at(motion.position)
		if button != _hover_button:
			_hover_button = button
			queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var button := _button_at(mouse.position)
			if button == 0:
				accept_event()
				_trade()
			elif button == 1:
				accept_event()
				_leave()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_trade()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_leave()
			get_viewport().set_input_as_handled()

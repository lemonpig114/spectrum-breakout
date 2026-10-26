class_name GameOverPanel
extends Control

## 死亡结算：显示本局数据，提供「再来一局 / 返回主界面」。
## Main 在死亡演出后暂停整棵树，因此本面板用 PROCESS_MODE_ALWAYS 继续响应输入。

signal retry_requested
signal menu_requested

const WGHT_AXIS := 0x77676874
const DANGER := Color(1.0, 0.32, 0.30, 1.0)
const GOLD := Color(1.0, 0.84, 0.38, 1.0)
const MENU_BLUE := Color(0.62, 0.78, 0.95, 1.0)
const BUTTON_SIZE := Vector2(196.0, 54.0)
const BUTTON_GAP := 20.0
const CARD_SIZE := Vector2(560.0, 312.0)

var _font: Font
var _bold_font: FontVariation
var _appear := 0.0
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_NONE
	visible = false
	_refresh_fonts()


func open() -> void:
	visible = true
	_appear = 0.0
	_hover = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_refresh_fonts()
	queue_redraw()


func close() -> void:
	visible = false
	_hover = -1
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_appear = minf(1.0, _appear + delta * 5.0)
	_refresh_fonts()
	queue_redraw()


func _refresh_fonts() -> void:
	var current := ThemeDB.fallback_font
	if current == null or current == _font:
		return
	_font = current
	_bold_font = FontVariation.new()
	_bold_font.base_font = current
	_bold_font.variation_opentype = {WGHT_AXIS: 800}


func _draw() -> void:
	if not visible or _font == null:
		return

	var ease := 1.0 - pow(1.0 - _appear, 3.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.82 * ease))
	if ease <= 0.0:
		return

	var card: Rect2 = _layout()["card"]
	card.position.y += (1.0 - ease) * 16.0

	draw_rect(card, Color(0.035, 0.042, 0.065, 0.97 * ease))
	draw_rect(card, Color(DANGER.r, DANGER.g, DANGER.b, 0.38 * ease), false, 1.5)
	draw_rect(
		Rect2(card.position, Vector2(card.size.x, 3.0)),
		Color(DANGER.r, DANGER.g, DANGER.b, 0.85 * ease)
	)
	draw_rect(
		Rect2(card.position + Vector2(0.0, 3.0), Vector2(card.size.x, 26.0)),
		Color(DANGER.r, DANGER.g, DANGER.b, 0.06 * ease)
	)

	_text_centered(
		"被围剿了",
		card.position.y + 78.0,
		40,
		Color(1.0, 0.90, 0.88, 0.97 * ease),
		true
	)
	_text_centered(
		"存活 %s    等级 %d    金币 %d" % [
			_format_time(RunState.elapsed), RunState.level, RunState.gold
		],
		card.position.y + 120.0,
		17,
		Color(1.0, 1.0, 1.0, 0.68 * ease)
	)

	var divider_y := card.position.y + 152.0
	draw_line(
		Vector2(card.position.x + 36.0, divider_y),
		Vector2(card.end.x - 36.0, divider_y),
		Color(1.0, 1.0, 1.0, 0.09 * ease),
		1.0
	)

	var buttons := _button_rects()
	_draw_button(buttons[0], 0, "再来一局", "" if GameInput.touch_controls_active else "R", ease)
	_draw_button(buttons[1], 1, "返回主界面", "" if GameInput.touch_controls_active else "Esc", ease)

	_text_centered(
		"再来一局沿用当前机体，进程不会保存",
		card.end.y - 30.0,
		10,
		Color(1.0, 1.0, 1.0, 0.30 * ease)
	)


func _draw_button(rect: Rect2, index: int, label: String, hint: String, alpha: float) -> void:
	var hovered := _hover == index
	var accent := GOLD if index == 0 else MENU_BLUE
	var fill := Color(0.055, 0.07, 0.10, 0.92 * alpha)
	if hovered:
		fill = Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.96 * alpha)
	draw_rect(rect, fill)
	draw_rect(
		rect,
		Color(accent.r, accent.g, accent.b, (0.90 if hovered else 0.32) * alpha),
		false,
		1.5 if hovered else 1.0
	)

	draw_string(
		_bold_font if _bold_font != null else _font,
		Vector2(rect.position.x, rect.position.y + (36.0 if hint.is_empty() else 27.0)),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		18,
		Color(1.0, 1.0, 1.0, 0.95 * alpha)
	)
	if not hint.is_empty():
		draw_string(
			_font,
			Vector2(rect.position.x, rect.position.y + 43.0),
			hint,
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			9,
			Color(accent.r, accent.g, accent.b, 0.62 * alpha)
		)


func _layout() -> Dictionary:
	var width := clampf(CARD_SIZE.x, 320.0, maxf(320.0, size.x - 48.0))
	var card_size := Vector2(width, CARD_SIZE.y)
	return {"card": Rect2((size - card_size) * 0.5, card_size)}


func _button_rects() -> Array[Rect2]:
	var card: Rect2 = _layout()["card"]
	var button_w := minf(BUTTON_SIZE.x, (card.size.x - 56.0 - BUTTON_GAP) * 0.5)
	var total := button_w * 2.0 + BUTTON_GAP
	var origin := Vector2(card.position.x + (card.size.x - total) * 0.5, card.position.y + 190.0)
	return [
		Rect2(origin, Vector2(button_w, BUTTON_SIZE.y)),
		Rect2(origin + Vector2(button_w + BUTTON_GAP, 0.0), Vector2(button_w, BUTTON_SIZE.y)),
	]


func _button_at(point: Vector2) -> int:
	var buttons := _button_rects()
	for i in buttons.size():
		if buttons[i].has_point(point):
			return i
	return -1


func _text_centered(text: String, baseline_y: float, font_size: int, color: Color, bold := false) -> void:
	var draw_font: Font = _font
	if bold and _bold_font != null:
		draw_font = _bold_font
	var width := draw_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	).x
	draw_string(
		draw_font,
		Vector2((size.x - width) * 0.5, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseMotion:
		var index := _button_at((event as InputEventMouseMotion).position)
		mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
		)
		if index != _hover:
			_hover = index
			queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var index := _button_at(mouse.position)
			if index >= 0:
				accept_event()
				_activate(index)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	if key.is_action_pressed(&"restart"):
		_consume_input()
		_activate(0)
	elif key.keycode == KEY_ESCAPE:
		_consume_input()
		_activate(1)
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_consume_input()
		_activate(0)


func _activate(index: int) -> void:
	Audio.play(&"ui_click")
	if index == 0:
		retry_requested.emit()
	else:
		menu_requested.emit()


## 场景切换可能立刻把本节点移出树；先取视口，避免 set_input_as_handled 落在 null 上。
func _consume_input() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

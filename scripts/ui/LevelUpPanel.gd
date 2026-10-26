class_name LevelUpPanel
extends Control

## 升级三选一：从当前可解锁的技能树节点里抽 3 个。
## 面板在暂停状态下运行（process_mode = WHEN_PAUSED），选择后通过信号交给 Main。

signal skill_chosen(node: SkillNodeResource)
signal reroll_requested

const GLYPH := preload("res://scripts/ui/SkillGlyph.gd")
const CARD_SIZE := Vector2(280.0, 252.0)
const CARD_GAP := 26.0
const TIER_NAMES: Array[String] = ["I", "II", "III", "IV"]

var _options: Array[SkillNodeResource] = []
var _rerolls_left := 0
var _hover := -1
var _appear := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_font = ThemeDB.fallback_font


func open(options: Array[SkillNodeResource], rerolls: int = 0) -> void:
	_options = options
	_rerolls_left = rerolls
	_hover = -1
	_appear = 0.0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	_options.clear()
	_rerolls_left = 0
	_hover = -1
	queue_redraw()


func _process(delta: float) -> void:
	_font = ThemeDB.fallback_font
	_appear = minf(1.0, _appear + delta * 7.0)
	queue_redraw()


func _draw() -> void:
	if not visible or _options.is_empty() or _font == null:
		return

	var ease := 1.0 - pow(1.0 - _appear, 3.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, ease))

	var rects := _card_rects()
	var top := rects[0].position.y

	_draw_text_centered(
		"升级！",
		top - 92.0 + (1.0 - ease) * 12.0,
		42,
		Color(1.0, 1.0, 1.0, 0.96 * ease)
	)
	_draw_text_centered(
		"等级 %d · 选择一个技能节点" % RunState.level,
		top - 56.0 + (1.0 - ease) * 12.0,
		15,
		Color(1.0, 1.0, 1.0, 0.55 * ease)
	)

	for i in _options.size():
		var rect := rects[i]
		rect.position.y += (1.0 - ease) * 14.0
		_draw_card(rect, _options[i], i, i == _hover, ease)

	_draw_text_centered(
		"点击卡片，或按 1 / 2 / 3 选择",
		rects[0].end.y + 44.0 + (1.0 - ease) * 14.0,
		14,
		Color(1.0, 1.0, 1.0, 0.42 * ease)
	)
	if _rerolls_left > 0:
		var reroll_rect := _reroll_rect()
		draw_rect(reroll_rect, Color(0.06, 0.12, 0.16, 0.9 * ease))
		draw_rect(reroll_rect, Color(0.35, 0.88, 1.0, 0.8 * ease), false, 1.5)
		_draw_text_centered("重选一次 · R", reroll_rect.position.y + 23.0, 15,
			Color(0.75, 0.95, 1.0, ease))


func _draw_card(
	rect: Rect2,
	node: SkillNodeResource,
	index: int,
	hovered: bool,
	alpha: float
) -> void:
	var accent := node.accent
	var bg_alpha := 1.0 if hovered else 0.97
	var border_alpha := 0.95 if hovered else 0.35

	draw_rect(rect, Color(0.045, 0.06, 0.095, bg_alpha * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, border_alpha * alpha), false, 2.0)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 3.0)),
		Color(accent.r, accent.g, accent.b, 0.9 * alpha)
	)

	draw_string(
		_font,
		rect.position + Vector2(16.0, 27.0),
		str(index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		Color(accent.r, accent.g, accent.b, 0.75 * alpha)
	)

	var branch_text := "%s · %s" % [
		node.branch_name,
		TIER_NAMES[clampi(node.tier - 1, 0, TIER_NAMES.size() - 1)],
	]
	var branch_width := _font.get_string_size(
		branch_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13
	).x
	var glyph_center := rect.position + Vector2(rect.size.x - 16.0 - branch_width - 16.0, 22.0)
	GLYPH.draw_branch(self, node.branch, glyph_center, 6.5,
		Color(accent.r, accent.g, accent.b, 0.88 * alpha))
	draw_string(
		_font,
		rect.position + Vector2(rect.size.x - 16.0 - branch_width, 27.0),
		branch_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color(accent.r, accent.g, accent.b, 0.85 * alpha)
	)

	draw_string(
		_font,
		rect.position + Vector2(0.0, 66.0),
		node.display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		24,
		Color(1.0, 1.0, 1.0, 0.96 * alpha)
	)

	draw_line(
		rect.position + Vector2(22.0, 84.0),
		rect.position + Vector2(rect.size.x - 22.0, 84.0),
		Color(1.0, 1.0, 1.0, 0.09 * alpha),
		1.0
	)

	draw_multiline_string(
		_font,
		rect.position + Vector2(20.0, 106.0),
		node.description,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 40.0,
		14,
		7,
		Color(1.0, 1.0, 1.0, 0.72 * alpha)
	)

	draw_line(
		rect.position + Vector2(18.0, rect.size.y - 32.0),
		rect.end + Vector2(-18.0, -32.0),
		Color(1.0, 1.0, 1.0, 0.1 * alpha),
		1.0
	)

	draw_string(
		_font,
		rect.position + Vector2(0.0, rect.size.y - 12.0),
		"第 %d 阶技能" % node.tier,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		12,
		Color(1.0, 1.0, 1.0, 0.38 * alpha)
	)


func _card_rects() -> Array[Rect2]:
	var count := _options.size()
	var total_width := CARD_SIZE.x * float(count) + CARD_GAP * float(count - 1)
	var start := Vector2(
		(size.x - total_width) * 0.5,
		(size.y - CARD_SIZE.y) * 0.5 + 20.0
	)

	var rects: Array[Rect2] = []
	for i in count:
		rects.append(Rect2(start + Vector2(float(i) * (CARD_SIZE.x + CARD_GAP), 0.0), CARD_SIZE))
	return rects


func _draw_text_centered(text: String, baseline_y: float, font_size: int, color: Color) -> void:
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
		var motion_event := event as InputEventMouseMotion
		var index := _index_at(motion_event.position)
		if index != _hover:
			_hover = index
			queue_redraw()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if _rerolls_left > 0 and _reroll_rect().has_point(mouse_event.position):
				accept_event()
				reroll_requested.emit()
				return
			var index := _index_at(mouse_event.position)
			if index >= 0:
				accept_event()
				_choose(index)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var index := -1
	if key_event.keycode == KEY_R and _rerolls_left > 0:
		get_viewport().set_input_as_handled()
		reroll_requested.emit()
		return
	match key_event.keycode:
		KEY_1, KEY_KP_1:
			index = 0
		KEY_2, KEY_KP_2:
			index = 1
		KEY_3, KEY_KP_3:
			index = 2

	if index >= 0 and index < _options.size():
		get_viewport().set_input_as_handled()
		_choose(index)


func _index_at(point: Vector2) -> int:
	var rects := _card_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1


func _reroll_rect() -> Rect2:
	var rects := _card_rects()
	if rects.is_empty():
		return Rect2()
	return Rect2(Vector2((size.x - 158.0) * 0.5, rects[0].end.y + 58.0), Vector2(158.0, 34.0))


func _choose(index: int) -> void:
	if index < 0 or index >= _options.size():
		return
	var node := _options[index]
	Audio.play(&"ui_click")
	close()
	skill_chosen.emit(node)

extends MenuScreen

## 选择机体界面。三张卡片共用 CharacterVisual 的绘制，菜单预览与局内外形一致。
## 鼠标悬停高亮、点击选中、再次点击出击；键盘 ← → 切换，回车/空格出击。

const MAIN_SCENE := "res://scenes/main.tscn"
const CARD_SIZE := Vector2(310.0, 380.0)
const CARD_GAP := 28.0

var _characters: Array[CharacterResource] = []
var _selected := 0
var _hover_card := -1
var _hover_start := false
var _hover_codex := false
var _hover_codex_close := false
var _codex_open := false
var _codex_panel: Control
var _card_anim: Array[float] = []
var _started := false


func _screen_ready() -> void:
	_codex_panel = preload("res://scripts/ui/CodexPanel.gd").new()
	add_child(_codex_panel)
	_codex_panel.hide()
	_codex_panel.closed.connect(_close_codex)
	_characters = ContentDB.get_characters()
	for i in _characters.size():
		_card_anim.append(0.0)
		if _characters[i].id == RunState.selected_character_id:
			_selected = i

	# 内容索引损坏时留在选择页并报错，不能默默替用户选角进入空战场。
	if _characters.is_empty():
		push_error("CharacterSelect: no character resources loaded")


func _screen_process(delta: float) -> void:
	_codex_panel.visible = _codex_open
	for i in _card_anim.size():
		var target := 1.0 if i == _selected else 0.0
		_card_anim[i] = move_toward(_card_anim[i], target, delta * 6.0)


func _draw() -> void:
	draw_backdrop()

	var cx := size.x * 0.5
	draw_text_centered("选择机体", 88.0, 38, Color(0.96, 0.98, 1.0, 0.96), true)
	draw_text_centered("SELECT YOUR UNIT", 112.0, 12, Color(1.0, 1.0, 1.0, 0.32))
	draw_line(
		Vector2(44.0, 128.0),
		Vector2(size.x - 44.0, 128.0),
		Color(1.0, 1.0, 1.0, 0.08),
		1.0
	)

	if font != null:
		draw_string(
			font, Vector2(36.0, 38.0), "RUN PROTOCOL // 01",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.22)
		)
		draw_string(
			font,
			Vector2(size.x - 36.0 - 120.0, 38.0),
			"%d UNITS ONLINE" % _characters.size(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			11,
			Color(1.0, 1.0, 1.0, 0.22)
		)

	var rects := _card_rects()
	for i in rects.size():
		_draw_card(rects[i], _characters[i], i)

	_draw_start_button()
	_draw_codex_button()

	draw_text_centered(
		"回车 / 空格 出击",
		size.y - 52.0,
		13,
		Color(1.0, 1.0, 1.0, 0.38)
	)
	draw_text_centered(
		"点击卡片选择，再次点击出击",
		size.y - 32.0,
		11,
		Color(1.0, 1.0, 1.0, 0.24)
	)


	draw_fade_overlay()


func _card_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _characters.is_empty():
		return rects
	var count := _characters.size()
	var total_width := CARD_SIZE.x * float(count) + CARD_GAP * float(count - 1)
	var start := Vector2(
		(size.x - total_width) * 0.5,
		maxf(152.0, size.y * 0.235)
	)
	for i in count:
		rects.append(
			Rect2(start + Vector2(float(i) * (CARD_SIZE.x + CARD_GAP), 0.0), CARD_SIZE)
		)
	return rects


func _draw_card(rect: Rect2, character: CharacterResource, index: int) -> void:
	var accent := character.accent
	var anim := _card_anim[index]
	var hovered := index == _hover_card

	# 选中卡片背后的大范围柔光。
	if anim > 0.01:
		draw_circle(
			rect.position + Vector2(rect.size.x * 0.5, 96.0),
			118.0,
			Color(accent.r * 0.30, accent.g * 0.30, accent.b * 0.30, 0.05 * anim)
		)

	draw_rect(rect, Color(0.032, 0.046, 0.075, 0.94))
	if anim > 0.01:
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.045 * anim))

	var border_alpha := 0.34 + 0.58 * anim
	if hovered:
		border_alpha = minf(1.0, border_alpha + 0.18)
	draw_rect(
		rect,
		Color(accent.r, accent.g, accent.b, border_alpha),
		false,
		1.5 + 1.2 * anim
	)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 3.0)),
		Color(accent.r, accent.g, accent.b, 0.55 + 0.45 * anim)
	)

	# 选中时四角加短刻线，和技能卡区分开。
	if anim > 0.01:
		var tick := 12.0 * anim
		var tick_color := Color(accent.r, accent.g, accent.b, 0.9 * anim)
		draw_line(rect.position, rect.position + Vector2(tick, 0.0), tick_color, 2.0, true)
		draw_line(rect.position, rect.position + Vector2(0.0, tick), tick_color, 2.0, true)
		draw_line(
			rect.position + Vector2(rect.size.x - tick, 0.0),
			rect.position + Vector2(rect.size.x, 0.0),
			tick_color, 2.0, true
		)
		draw_line(
			rect.position + Vector2(rect.size.x, 0.0),
			rect.position + Vector2(rect.size.x, tick),
			tick_color, 2.0, true
		)

	if font != null:
		draw_string(
			font,
			rect.position + Vector2(18.0, 28.0),
			"UNIT %02d" % (index + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			11,
			Color(accent.r, accent.g, accent.b, 0.6)
		)

	# 机体预览：缓慢旋转瞄准方向，外形与局内一致。
	var preview_boost := 1.9 if character.id == &"prism" else 1.7
	var preview_color := Color(
		minf(2.2, accent.r * preview_boost),
		minf(2.2, accent.g * preview_boost),
		minf(2.2, accent.b * preview_boost),
		1.0
	)
	CharacterVisual.draw_unit(
		self,
		rect.position + Vector2(rect.size.x * 0.5, 108.0),
		34.0,
		preview_color,
		character.body_style,
		character.barrel_style,
		screen_time * 0.7 + float(index) * 2.1,
		screen_time + float(index) * 0.7
	)

	draw_string(
		bold_font,
		rect.position + Vector2(0.0, 186.0),
		character.display_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		27,
		Color(0.96, 0.98, 1.0, 0.96)
	)
	draw_string(
		font,
		rect.position + Vector2(0.0, 211.0),
		character.role,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		13,
		Color(accent.r, accent.g, accent.b, 0.85)
	)

	draw_line(
		rect.position + Vector2(24.0, 226.0),
		rect.position + Vector2(rect.size.x - 24.0, 226.0),
		Color(1.0, 1.0, 1.0, 0.09),
		1.0
	)

	draw_multiline_string(
		font,
		rect.position + Vector2(24.0, 248.0),
		character.description,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x - 48.0,
		13,
		3,
		Color(1.0, 1.0, 1.0, 0.60)
	)

	_draw_stat_rows(rect, character, accent)


func _draw_stat_rows(rect: Rect2, character: CharacterResource, accent: Color) -> void:
	# 火力 = 共用基础攻击 × 机体倍率，和局内实际 DPS 一致。
	var core := ContentDB.get_weapon(CharacterResource.BASE_WEAPON_ID)
	var power := 0.0
	if core != null:
		power = core.damage * character.damage_multiplier \
			* core.fire_rate * character.fire_rate_multiplier

	var max_health_text := "%.1f" % character.max_health
	if is_equal_approx(character.max_health, roundf(character.max_health)):
		max_health_text = str(int(roundf(character.max_health)))

	var rows: Array[Dictionary] = [
		{
			"label": "生命",
			"fill": character.max_health / 8.0,
			"value": "%s 心" % max_health_text,
		},
		{
			"label": "移速",
			"fill": character.move_speed / 330.0,
			"value": "%d" % int(round(character.move_speed)),
		},
		{
			"label": "火力",
			"fill": power / 52.0,
			"value": "%.0f/s" % power,
		},
	]

	var bar_left := rect.position.x + 76.0
	var bar_right := rect.position.x + rect.size.x - 60.0
	for i in rows.size():
		var row := rows[i]
		var baseline := rect.position.y + 306.0 + float(i) * 24.0
		var value_fill := clampf(float(row["fill"]), 0.0, 1.0)

		draw_string(
			font,
			Vector2(rect.position.x + 22.0, baseline),
			str(row["label"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			Color(1.0, 1.0, 1.0, 0.44)
		)

		var bar := Rect2(Vector2(bar_left, baseline - 5.0), Vector2(bar_right - bar_left, 3.0))
		draw_rect(bar, Color(1.0, 1.0, 1.0, 0.08))
		draw_rect(
			Rect2(bar.position, Vector2(bar.size.x * value_fill, bar.size.y)),
			Color(accent.r, accent.g, accent.b, 0.85)
		)

		draw_string(
			font,
			Vector2(rect.position.x + rect.size.x - 56.0, baseline),
			str(row["value"]),
			HORIZONTAL_ALIGNMENT_RIGHT,
			40.0,
			12,
			Color(1.0, 1.0, 1.0, 0.62)
		)


func _start_rect() -> Rect2:
	var rects := _card_rects()
	if rects.is_empty():
		return Rect2()
	var width := 248.0
	return Rect2(
		Vector2((size.x - width) * 0.5, rects[0].end.y + 36.0),
		Vector2(width, 46.0)
	)


func _draw_start_button() -> void:
	var rect := _start_rect()
	if rect.size == Vector2.ZERO:
		return

	var accent := _characters[_selected].accent
	draw_rect(rect, Color(0.04, 0.055, 0.085, 0.9))
	if _hover_start:
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.12))
	draw_rect(
		rect,
		Color(accent.r, accent.g, accent.b, 0.85 if _hover_start else 0.55),
		false,
		1.6
	)
	draw_string(
		bold_font,
		rect.position + Vector2(0.0, 31.0),
		"出 击",
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		20,
		Color(0.98, 0.99, 1.0, 0.96)
	)


func _codex_button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 154.0, 52.0), Vector2(118.0, 34.0))


func _codex_panel_rect() -> Rect2:
	var panel_size := Vector2(minf(780.0, size.x - 100.0), minf(480.0, size.y - 120.0))
	return Rect2((size - panel_size) * 0.5, panel_size)


func _codex_close_rect() -> Rect2:
	var panel := _codex_panel_rect()
	return Rect2(Vector2(panel.get_center().x - 90.0, panel.end.y - 62.0), Vector2(180.0, 42.0))


func _menu_accent() -> Color:
	if _characters.is_empty():
		return Color(1.0, 0.84, 0.38)
	return _characters[_selected].accent


func _draw_codex_button() -> void:
	var rect := _codex_button_rect()
	var accent := _menu_accent()
	draw_rect(rect, Color(0.035, 0.048, 0.074, 0.9))
	if _hover_codex:
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.10))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.52 if _hover_codex else 0.26), false, 1.0)
	draw_string(font, rect.position + Vector2(14.0, 23.0), "图鉴",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13,
		Color(0.96, 0.98, 1.0, 0.82))
	draw_string(font, Vector2(rect.end.x - 53.0, rect.position.y + 21.0), "CODEX",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 1.0, 1.0, 0.28))


func _open_codex() -> void:
	_codex_open = true
	_codex_panel.show()
	_hover_codex = false
	_hover_codex_close = false


func _close_codex() -> void:
	_codex_open = false
	_codex_panel.hide()
	_hover_codex_close = false


func _gui_input(event: InputEvent) -> void:
	if is_transitioning() or _characters.is_empty():
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _codex_open:
			_hover_codex_close = _codex_close_rect().has_point(motion.position)
			return
		var hover := _index_at(motion.position)
		if hover != _hover_card:
			_hover_card = hover
		_hover_start = _start_rect().has_point(motion.position)
		_hover_codex = _codex_button_rect().has_point(motion.position)
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		if _codex_open:
			accept_event()
			if _codex_close_rect().has_point(mouse_event.position) \
				or not _codex_panel_rect().has_point(mouse_event.position):
				_close_codex()
			return
		if _codex_button_rect().has_point(mouse_event.position):
			accept_event()
			_open_codex()
			return
		var index := _index_at(mouse_event.position)
		if index >= 0:
			accept_event()
			if index == _selected:
				_start_run()
			else:
				_selected = index
		elif _start_rect().has_point(mouse_event.position):
			accept_event()
			_start_run()


func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning() or _characters.is_empty():
		return
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if _codex_open:
		return

	match key_event.keycode:
		KEY_LEFT, KEY_A:
			_selected = posmod(_selected - 1, _characters.size())
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
			_selected = posmod(_selected + 1, _characters.size())
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_start_run()
			get_viewport().set_input_as_handled()
		KEY_C:
			_open_codex()
			get_viewport().set_input_as_handled()


func _index_at(point: Vector2) -> int:
	var rects := _card_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1


func _start_run() -> void:
	if _started or _characters.is_empty():
		return
	_started = true
	RunState.selected_character_id = _characters[_selected].id
	change_screen(MAIN_SCENE)

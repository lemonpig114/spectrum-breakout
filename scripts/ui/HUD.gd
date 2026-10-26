extends Control

## M0 HUD：生命、能量、当前/左右候选颜色、计时、金币、首局提示、死亡界面。
## 全部使用 _draw 程序化绘制，不依赖贴图。

const HEALTH_ORIGIN := Vector2(24.0, 30.0)
const HEALTH_ICONS_PER_ROW := 10
const HEALTH_ICON_LIMIT := 30
const HEALTH_ICON_SPACING := 24.0
const HEALTH_ROW_SPACING := 24.0

var _font: Font
var _hp := 100.0
var _max_hp := 100.0
var _switch_preview := false
var _preview_previous := 0
var _preview_next := 1
var _preview_position := Vector2.ZERO
var _preview_direction := 0
# 轮盘开合用弹簧驱动，避免出现/消失过于生硬；左右高亮也做连续插值。
var _wheel_open := 0.0
var _wheel_open_velocity := 0.0
var _wheel_side := 0.0
var _wheel_spin := 0.0
var _wheel_commit_flash := 0.0
var _wheel_commit_color := Color.WHITE
# 底部当前色槽的换色脉冲，让快速点击也有可见的反馈。
var _selector_flash := 0.0
var _selector_flash_color := Color.WHITE
var _energy_flash := 0.0
var _damage_flash := 0.0
var _hint_time := 0.0
## 克制三角：右键进入选择时就开始显示，选择结束后只保留很短的一段渐隐。
var _relation_preview := false
var _relation_color := 0
var _relation_time := 0.0
var _show_debug := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_relation_color = RunState.color_index

	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.color_switch_preview.connect(_on_switch_preview)
	EventBus.color_switch_failed.connect(_on_switch_failed)
	EventBus.color_changed.connect(_on_color_changed)
	queue_redraw()


func _process(delta: float) -> void:
	if RunState.is_running:
		_hint_time += delta
	_update_wheel(delta)
	_selector_flash = maxf(0.0, _selector_flash - delta * 3.5)
	_energy_flash = maxf(0.0, _energy_flash - delta * 3.0)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.8)
	_relation_time = maxf(0.0, _relation_time - delta)
	queue_redraw()


## 轮盘展开/收起、左右高亮、旋转刻度与确认脉冲的逐帧状态。
func _update_wheel(delta: float) -> void:
	var target := 1.0 if _switch_preview else 0.0
	_wheel_open_velocity += (target - _wheel_open) * 320.0 * delta
	_wheel_open_velocity *= exp(-24.0 * delta)
	_wheel_open += _wheel_open_velocity * delta
	if _wheel_open < 0.0:
		_wheel_open = 0.0
		_wheel_open_velocity = 0.0
	elif _wheel_open > 1.12:
		_wheel_open = 1.12
		_wheel_open_velocity = minf(_wheel_open_velocity, 0.0)

	if _switch_preview:
		_wheel_side = lerpf(_wheel_side, float(_preview_direction), 1.0 - exp(-16.0 * delta))
	# 收起过程中也保持旋转，直到轮盘完全消失。
	_wheel_spin += delta * 2.6
	_wheel_commit_flash = maxf(0.0, _wheel_commit_flash - delta * 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
			_show_debug = not _show_debug
			queue_redraw()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	# Main 在子节点 _ready 之后才设置全局字体，因此这里每帧取一次。
	_font = ThemeDB.fallback_font
	if _font == null:
		return
	if not RunState.is_running and not RunState.is_dead:
		return

	_draw_health()
	_draw_energy()
	_draw_color_selector()
	_draw_color_relation()
	_draw_top_info()
	_draw_hint()
	_draw_switch_indicator()
	_draw_event_markers()
	_draw_damage_flash()

	if _show_debug:
		_draw_debug_overlay()


## F3：显示帧时间与对象数量，方便确认卡顿是否来自逻辑/物理尖峰。
func _draw_debug_overlay() -> void:
	const FONT_SIZE := 12
	var fps := Engine.get_frames_per_second()
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var text := "FPS %d  %.1f ms | 物理 %.1f ms | 敌人 %d | 掉落 %d | 节点 %d" % [
		fps, frame_ms, physics_ms, enemies, Pickups.total_count(),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	]
	var width := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE
	).x
	var position := Vector2(size.x - width - 24.0, 84.0)
	draw_rect(
		Rect2(position + Vector2(-8.0, -13.0), Vector2(width + 16.0, 20.0)),
		Color(0.0, 0.0, 0.0, 0.6)
	)
	draw_string(
		_font,
		position,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		FONT_SIZE,
		Color(0.55, 1.0, 0.85, 0.92)
	)


func _on_health_changed(current: float, maximum: float) -> void:
	_hp = current
	_max_hp = maximum
	queue_redraw()


func _on_player_damaged(_amount: float) -> void:
	_damage_flash = 1.0
	queue_redraw()


func _on_switch_preview(
	active: bool,
	screen_position: Vector2,
	direction: int,
	previous_color: int,
	next_color: int
) -> void:
	# 关闭预览时保留最后的位置/方向/颜色，让轮盘收起动画仍然完整。
	if active:
		_preview_position = screen_position
		_preview_direction = direction
		_preview_previous = previous_color
		_preview_next = next_color
		# 一进入右键选择就显示克制图，并跟随当前拖拽方向指向的候选颜色。
		_relation_preview = true
		_relation_time = 3.0
		if direction > 0:
			_relation_color = next_color
		elif direction < 0:
			_relation_color = previous_color
		else:
			_relation_color = RunState.color_index
	else:
		# 提交时 color_changed 已先更新颜色；取消时回到当前颜色。
		# 选择结束后只留 1.2 秒的确认渐隐，不再常驻 3 秒。
		_relation_preview = false
		_relation_color = RunState.color_index
		_relation_time = 1.2
	_switch_preview = active
	queue_redraw()


## 换色时：底部色槽打出一圈脉冲；若轮盘正展开，再在轮盘上扩散一圈。
func _on_color_changed(new_color: int) -> void:
	_selector_flash = 1.0
	_selector_flash_color = RunState.ui_color_of(new_color)
	# 快速点击没有预览阶段，这里补一个短确认；拖拽选择时图标已经在显示。
	_relation_color = new_color
	_relation_time = 1.2
	if _switch_preview or _wheel_open > 0.05:
		_wheel_commit_flash = 1.0
		_wheel_commit_color = _selector_flash_color
	queue_redraw()


func _on_switch_failed() -> void:
	_energy_flash = 1.0
	queue_redraw()


## 棱角化的心形生命槽：1 颗 = 1.0 生命，0.5 显示左半颗。
func _draw_health() -> void:
	var max_hp := maxf(0.5, _max_hp)
	var hearts := maxi(1, int(ceil(max_hp)))
	var shields := maxi(0, Skills.guardian_shields)
	var numeric := hearts + shields > HEALTH_ICON_LIMIT
	var low_health := _hp > 0.0 and _hp / max_hp <= 0.3
	var pulse := 1.0
	if low_health:
		pulse = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.012)
	if numeric:
		_draw_heart_at(HEALTH_ORIGIN + Vector2(12, 0), 1.0, pulse)
		var label := "%s / %s" % [_format_half(_hp), _format_half(_max_hp)]
		draw_string(_font, HEALTH_ORIGIN + Vector2(28, 5), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1.0, 0.86, 0.88, 0.95))
		if shields > 0:
			var label_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
			var shield_center := HEALTH_ORIGIN + Vector2(42.0 + label_width, 0.0)
			_draw_guardian_icon(shield_center)
			draw_string(_font, shield_center + Vector2(14, 5), "×%d" % shields,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(0.8, 0.95, 1.0, 0.96))
		return

	for i in hearts:
		_draw_heart_at(_health_icon_center(i), clampf(_hp - float(i), 0.0, 1.0), pulse)
	for i in shields:
		_draw_guardian_icon(_health_icon_center(hearts + i))

	draw_string(
		_font,
		Vector2(24.0, 58.0 + _health_extra_height()),
		"生命 %s / %s 心" % [_format_half(_hp), _format_half(_max_hp)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color(1.0, 1.0, 1.0, 0.55)
	)


func _health_icon_center(index: int) -> Vector2:
	return HEALTH_ORIGIN + Vector2(
		HEALTH_ICON_SPACING * (float(index % HEALTH_ICONS_PER_ROW) + 0.5),
		HEALTH_ROW_SPACING * float(index / HEALTH_ICONS_PER_ROW)
	)


func _health_extra_height() -> float:
	var count := maxi(1, int(ceil(maxf(0.5, _max_hp)))) + maxi(0, Skills.guardian_shields)
	if count > HEALTH_ICON_LIMIT:
		return 0.0
	return HEALTH_ROW_SPACING * float((count - 1) / HEALTH_ICONS_PER_ROW)


func _draw_heart_at(center: Vector2, fraction: float, pulse: float) -> void:
	var points := _heart_points(center, 1.0, 1.0)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_colored_polygon(points, Color(0.12, 0.035, 0.065, 0.88))
	draw_polyline(outline, Color(0.65, 0.21, 0.28, 0.56), 1.3, true)
	if fraction <= 0.001:
		return
	var fill_color := Color(1.55, 0.13, 0.27, 0.96 * pulse)
	if fraction >= 0.999:
		draw_colored_polygon(points, fill_color)
	else:
		for piece in _clip_heart_fill(points, fraction):
			if piece.size() >= 3:
				draw_colored_polygon(piece, fill_color)
	draw_polyline(outline, Color(2.0, 0.43, 0.52, 0.9 * pulse), 1.3, true)
	if fraction >= 0.999:
		draw_line(center + Vector2(-6.5, -5.2), center + Vector2(-2.6, -6.0),
			Color(2.4, 0.75, 0.82, 0.72 * pulse), 1.15, true)


func _draw_guardian_icon(center: Vector2) -> void:
	var shield := PackedVector2Array([
		center + Vector2(0, -10), center + Vector2(9, -7),
		center + Vector2(8, 2), center + Vector2(0, 9),
		center + Vector2(-8, 2), center + Vector2(-9, -7),
	])
	draw_colored_polygon(shield, Color(0.48, 0.8, 1.15, 0.5))
	var outline := shield.duplicate()
	outline.append(shield[0])
	draw_polyline(outline, Color(0.78, 1.0, 1.5, 0.95), 1.5, true)


## 0.5 → "0.5"；整数不显示小数尾巴。
func _format_half(value: float) -> String:
	var halves := int(round(value * 2.0))
	if halves % 2 == 0:
		return str(int(halves / 2))
	return "%.1f" % (float(halves) * 0.5)


## 十二顶点小型切面心形；避免每帧为每颗心计算三角函数与幂。
func _heart_points(center: Vector2, sx: float, sy: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-10, -3) * Vector2(sx, sy),
		center + Vector2(-9, -7) * Vector2(sx, sy),
		center + Vector2(-6, -9) * Vector2(sx, sy),
		center + Vector2(-2, -9) * Vector2(sx, sy),
		center + Vector2(0, -6) * Vector2(sx, sy),
		center + Vector2(2, -9) * Vector2(sx, sy),
		center + Vector2(6, -9) * Vector2(sx, sy),
		center + Vector2(9, -7) * Vector2(sx, sy),
		center + Vector2(10, -3) * Vector2(sx, sy),
		center + Vector2(9, 2) * Vector2(sx, sy),
		center + Vector2(0, 10) * Vector2(sx, sy),
		center + Vector2(-9, 2) * Vector2(sx, sy),
	])


## 从左向右填充 fraction（0..1），用多边形裁剪得到残血形状。
## 0.5 时正好是左半边实心 / 右半边空心的以撒式半颗心。
func _clip_heart_fill(points: PackedVector2Array, fraction: float) -> Array[PackedVector2Array]:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	var split_x := lerpf(min_x, max_x, clampf(fraction, 0.0, 1.0))
	var clip := PackedVector2Array([
		Vector2(min_x - 1.0, min_y - 1.0),
		Vector2(split_x, min_y - 1.0),
		Vector2(split_x, max_y + 1.0),
		Vector2(min_x - 1.0, max_y + 1.0),
	])
	return Geometry2D.intersect_polygons(points, clip)


func _draw_energy() -> void:
	var extra := _health_extra_height()
	var base := Vector2(32.0, 82.0 + extra)
	var pip_color := Color(0.3, 0.82, 1.0, 1.0).lerp(Color(1.0, 0.25, 0.3, 1.0), _energy_flash)

	var pips := maxi(1, int(ceil(RunState.max_energy)))
	var spacing := minf(26.0, 182.0 / float(pips))
	for i in pips:
		var center := base + Vector2(float(i) * spacing, 0.0)
		var fill := clampf(RunState.energy - float(i), 0.0, 1.0)
		var alpha := 0.16 + 0.84 * fill
		var points := _diamond_points(center, 6.5)
		draw_colored_polygon(points, Color(pip_color.r, pip_color.g, pip_color.b, alpha * 0.55))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(pip_color.r, pip_color.g, pip_color.b, alpha), 1.5, true)

	draw_string(
		_font,
		Vector2(24.0, 108.0 + extra),
		"能量 %d / %d" % [int(floor(RunState.energy)), int(round(RunState.max_energy))],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color(1.0, 1.0, 1.0, 0.55)
	)

	var crit := int(round(Skills.get_crit_chance(null) * 100.0))
	var dodge := int(round(Skills.effective_dodge() * 100.0))
	var stat_text := "暴击 %d%%    闪避 %d%%" % [crit, dodge]
	var luck := Skills.luck()
	if luck > 0.0:
		stat_text += "    幸运 %d" % int(round(luck))
	draw_string(
		_font,
		Vector2(24.0, 128.0 + extra),
		stat_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		Color(1.0, 1.0, 1.0, 0.42)
	)


func _draw_color_selector() -> void:
	var center := Vector2(size.x * 0.5, size.y - 54.0)
	var current := RunState.color_index
	var previous := _preview_previous
	var next := _preview_next

	if not _switch_preview:
		previous = ColorType.next(current, -1)
		next = ColorType.next(current, 1)

	var wheel_open := clampf(_wheel_open, 0.0, 1.0)
	var side_alpha := lerpf(0.35, 1.0, wheel_open)

	if wheel_open > 0.01:
		draw_line(
			center + Vector2(-54.0, 0.0),
			center + Vector2(-18.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.18 * wheel_open),
			1.0
		)
		draw_line(
			center + Vector2(18.0, 0.0),
			center + Vector2(54.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.18 * wheel_open),
			1.0
		)

	_draw_color_slot(center + Vector2(-64.0, 0.0), previous, 10.0, side_alpha, false)
	_draw_color_slot(center, current, 14.0, 1.0, true)
	_draw_color_slot(center + Vector2(64.0, 0.0), next, 10.0, side_alpha, false)

	if _selector_flash > 0.0:
		var flash_t := 1.0 - _selector_flash
		var flash_color := _selector_flash_color
		draw_arc(
			center,
			14.0 + 22.0 * flash_t,
			0.0,
			TAU,
			40,
			Color(flash_color.r, flash_color.g, flash_color.b, 0.55 * _selector_flash),
			2.0,
			true
		)


## 换色槽右侧的克制三角：红→绿→蓝→红。
## 每条直边代表“左边颜色克制右边颜色”，箭头画在边的中段并指向被克制的颜色，
## 所以不会和端点色球叠在一起；当前颜色的出边最亮，指向当前颜色的边次之，另一条压暗。
## 只在换色后出现 3 秒（最后 0.8 秒渐隐），纯图形、无文字与倍率。
func _draw_color_relation() -> void:
	if (not _relation_preview and _relation_time <= 0.0) \
			or RunState.is_dead or RunState.is_ui_paused():
		return
	var alpha := 1.0 if _relation_preview else clampf(_relation_time / 0.8, 0.0, 1.0)
	if alpha <= 0.01:
		return

	var origin := Vector2(size.x * 0.5, size.y - 54.0) + Vector2(138.0, 0.0)
	var current := _relation_color
	var radius := 30.0
	var node_radius := 8.5
	# 0=上(红) 1=右下(绿) 2=左下(蓝)，角度递增在屏幕坐标里就是顺时针。
	var angles := [-PI * 0.5, -PI * 0.5 + TAU / 3.0, -PI * 0.5 + TAU * 2.0 / 3.0]

	# 暗底保证三角在亮弹幕上也读得清；不是面板，只做对比。
	draw_circle(origin, radius + 12.0, Color(0.015, 0.015, 0.035, 0.46 * alpha))
	draw_arc(origin, radius + 12.0, 0.0, TAU, 48,
		Color(1.0, 1.0, 1.0, 0.10 * alpha), 1.0, true)

	for i in 3:
		var from_index := ColorType.next(ColorType.RED, i)
		var to_index := ColorType.next(ColorType.RED, (i + 1) % 3)
		var from_point := origin + Vector2.from_angle(float(angles[i])) * radius
		var to_point := origin + Vector2.from_angle(float(angles[(i + 1) % 3])) * radius
		var direction := (to_point - from_point).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var line_start := from_point + direction * (node_radius + 4.0)
		var line_end := to_point - direction * (node_radius + 6.0)
		var base := RunState.ui_color_of(from_index)

		var is_out := from_index == current
		var edge_alpha := alpha
		if not is_out:
			# 三条关系都要看得见；只把当前颜色的出边拉到最亮，另外两条压低但仍可读。
			edge_alpha *= 0.85 if to_index == current else 0.55
		draw_line(
			line_start,
			line_end,
			Color(base.r, base.g, base.b, 0.9 * edge_alpha),
			2.6 if is_out else 1.7,
			true
		)

		# 箭头放在边的中段，避免压在端点色球上。
		var head := line_start.lerp(line_end, 0.62)
		var head_length := 9.5 if is_out else 8.0
		var head_width := 6.6 if is_out else 5.6
		draw_colored_polygon(PackedVector2Array([
			head + direction * head_length,
			head - direction * 2.2 + perpendicular * head_width,
			head - direction * 2.2 - perpendicular * head_width,
		]), Color(base.r, base.g, base.b, edge_alpha))

	for i in 3:
		var color_index := ColorType.next(ColorType.RED, i)
		var base := RunState.ui_color_of(color_index)
		var node := origin + Vector2.from_angle(float(angles[i])) * radius
		var is_current := color_index == current
		draw_circle(node, node_radius + (2.0 if is_current else 0.0),
			Color(base.r, base.g, base.b, 0.20 * alpha))
		draw_circle(node, node_radius * 0.68,
			Color(base.r, base.g, base.b, alpha))
		if is_current:
			draw_arc(node, node_radius + 4.5, 0.0, TAU, 32,
				Color(1.0, 1.0, 1.0, 0.95 * alpha), 1.8, true)
			draw_circle(node, node_radius * 0.24, Color(1.0, 1.0, 1.0, 0.95 * alpha))


func _draw_color_slot(
	center: Vector2,
	color_index: int,
	radius: float,
	alpha: float,
	is_current: bool
) -> void:
	var base := RunState.ui_color_of(color_index)
	var c := Color(base.r, base.g, base.b, alpha)

	draw_circle(center, radius, Color(base.r, base.g, base.b, alpha * 0.16))
	draw_arc(center, radius, 0.0, TAU, 40, c, 2.0 if is_current else 1.5, true)
	draw_circle(center, radius * 0.28, c)

	if is_current:
		draw_arc(
			center,
			radius + 4.0,
			0.0,
			TAU,
			40,
			Color(c.r, c.g, c.b, 0.28),
			1.0,
			true
		)


func _draw_top_info() -> void:
	var time_text := _format_time(RunState.elapsed)
	var time_width := _font.get_string_size(
		time_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24
	).x
	draw_string(
		_font,
		Vector2((size.x - time_width) * 0.5, 40.0),
		time_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		Color(1.0, 1.0, 1.0, 0.86)
	)

	var level_text := "等级 %d · 技能 %d" % [RunState.level, Skills.unlocked_count()]
	var level_width := _font.get_string_size(
		level_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13
	).x
	draw_string(
		_font,
		Vector2((size.x - level_width) * 0.5, 62.0),
		level_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color(1.0, 1.0, 1.0, 0.45)
	)

	var gold_text := "金币 %d" % RunState.gold
	var gold_width := _font.get_string_size(
		gold_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16
	).x
	# 右上角留出暂停按钮的位置。
	draw_string(
		_font,
		Vector2(size.x - gold_width - 82.0, 40.0),
		gold_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		Color(1.0, 0.85, 0.35, 0.85)
	)


func _draw_hint() -> void:
	if _hint_time >= 12.0:
		return

	var alpha := 1.0
	if _hint_time > 8.0:
		alpha = clampf(1.0 - (_hint_time - 8.0) / 4.0, 0.0, 1.0)

	_draw_text_centered(
		"左键：朝指针射击    右键点击：循环颜色    长按拖动：左/右选择并松开确认",
		size.y - 100.0,
		13,
		Color(1.0, 1.0, 1.0, 0.5 * alpha)
	)


## 长按右键时，在按下位置显示左右两个半圆：
## 左半圆 = 上一个颜色，右半圆 = 下一个颜色，拖动方向决定高亮，松开确认。
## 展开、左右切换、确认和收起都带连续动画，不再瞬间出现/消失。
func _draw_switch_indicator() -> void:
	if _wheel_open <= 0.01 or RunState.is_dead or RunState.is_ui_paused():
		return

	var open := clampf(_wheel_open, 0.0, 1.0)
	# 保留一点弹簧过冲，让轮盘展开时有个很轻的回弹。
	var grow := clampf(_wheel_open, 0.0, 1.06)
	var center := _preview_position
	center.x = clampf(center.x, 52.0, size.x - 52.0)
	center.y = clampf(center.y, 52.0, size.y - 52.0)

	var radius := 38.0 * grow
	var enabled := RunState.energy >= 1.0
	var pulse := 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.009)
	var alpha := (1.0 if enabled else 0.35) * open * pulse
	if alpha <= 0.001:
		return

	# 底层是一个略微放大的旋转光环，让轮盘像被“旋出来”的。
	draw_circle(center, radius + 10.0 * open, Color(0.0, 0.0, 0.0, 0.3 * alpha))
	draw_arc(
		center,
		radius + 7.0 * open,
		0.0,
		TAU,
		48,
		Color(1.0, 1.0, 1.0, 0.18 * alpha),
		1.0,
		true
	)
	draw_arc(
		center,
		radius + 9.0 * open,
		_wheel_spin,
		_wheel_spin + 0.9,
		16,
		Color(1.0, 1.0, 1.0, 0.45 * alpha),
		1.6,
		true
	)

	# 三个轨道刻度缓慢旋转，增强“轮盘”的可动感。
	for i in 3:
		var angle := _wheel_spin * 0.8 + TAU * float(i) / 3.0
		var tick_position := center + Vector2(cos(angle), sin(angle)) * (radius + 14.0 * open)
		draw_circle(tick_position, 1.6 + 0.8 * open, Color(1.0, 1.0, 1.0, 0.4 * alpha))

	var left_strength := clampf(-_wheel_side, 0.0, 1.0)
	var right_strength := clampf(_wheel_side, 0.0, 1.0)
	_draw_half_disc(center, radius, false, _preview_previous, left_strength, alpha)
	_draw_half_disc(center, radius, true, _preview_next, right_strength, alpha)

	draw_line(
		center + Vector2(0.0, -radius * 0.92),
		center + Vector2(0.0, radius * 0.92),
		Color(1.0, 1.0, 1.0, 0.22 * alpha),
		1.5,
		true
	)
	draw_circle(center, 3.0 * open, Color(1.0, 1.0, 1.0, 0.85 * alpha))

	# 确认换色：新颜色的圆环向外扩散并淡出。
	if _wheel_commit_flash > 0.0:
		var flash_t := 1.0 - _wheel_commit_flash
		var commit := _wheel_commit_color
		draw_circle(
			center,
			radius * (0.55 + 0.9 * flash_t),
			Color(commit.r, commit.g, commit.b, 0.1 * _wheel_commit_flash)
		)
		draw_arc(
			center,
			radius * (1.0 + 0.95 * flash_t),
			0.0,
			TAU,
			48,
			Color(commit.r, commit.g, commit.b, 0.6 * _wheel_commit_flash),
			2.5,
			true
		)

	var caption := "左右拖动选择"
	if not enabled:
		caption = "能量不足"
	elif _preview_direction < 0:
		caption = "松开切到左色"
	elif _preview_direction > 0:
		caption = "松开切到右色"

	_draw_text_at(
		center.x,
		center.y + radius + 26.0 * open,
		caption,
		13,
		Color(1.0, 1.0, 1.0, 0.65 * alpha)
	)


func _draw_half_disc(
	center: Vector2,
	radius: float,
	is_right: bool,
	color_index: int,
	strength: float,
	alpha: float
) -> void:
	var base := RunState.ui_color_of(color_index)
	var fill_alpha := lerpf(0.16, 0.58, strength) * alpha
	var line_alpha := lerpf(0.4, 1.0, strength) * alpha
	var line_width := lerpf(1.5, 2.6, strength)
	var gap := 0.1

	var start_angle := -PI * 0.5 + gap if is_right else PI * 0.5 + gap
	var end_angle := PI * 0.5 - gap if is_right else PI * 1.5 - gap

	var points := PackedVector2Array([center])
	const STEPS := 24
	for i in STEPS + 1:
		var angle := lerpf(start_angle, end_angle, float(i) / float(STEPS))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, Color(base.r, base.g, base.b, fill_alpha))
	draw_arc(
		center,
		radius,
		start_angle,
		end_angle,
		28,
		Color(base.r, base.g, base.b, line_alpha),
		line_width,
		true
	)

	var direction := 1.0 if is_right else -1.0
	draw_circle(
		center + Vector2(direction * radius * 0.5, 0.0),
		lerpf(3.2, 4.8, strength),
		Color(base.r, base.g, base.b, line_alpha)
	)

	# 拖动方向上的箭头随 strength 淡入并向外推，而不是二元切换。
	if strength > 0.01:
		var chevron_center := center + Vector2(direction * radius * lerpf(0.66, 0.82, strength), 0.0)
		var chevron := PackedVector2Array([
			chevron_center + Vector2(-direction * 4.0, -5.0),
			chevron_center + Vector2(direction * 3.0, 0.0),
			chevron_center + Vector2(-direction * 4.0, 5.0),
		])
		draw_polyline(chevron, Color(1.0, 1.0, 1.0, 0.82 * strength * alpha), 1.8, true)


## 商人/祭坛不在屏幕内时，在屏幕边缘画一个箭头指向它。
## 世界坐标 → 屏幕坐标用当前 Canvas 变换，缩放/震屏都能正确跟随。
func _draw_event_markers() -> void:
	if RunState.is_dead or RunState.is_ui_paused():
		return

	var merchant := get_tree().get_first_node_in_group(&"merchant") as Node2D
	if merchant != null and is_instance_valid(merchant):
		_draw_edge_marker(
			merchant,
			Color(1.0, 0.8, 0.28, 1.0),
			Color(2.2, 1.55, 0.35, 0.95),
			"商人",
			1.0
		)

	var altar := get_tree().get_first_node_in_group(&"altar") as Altar
	if altar != null and is_instance_valid(altar):
		var color := Altar.side_color(altar.side)
		_draw_edge_marker(altar, color, color, "祭坛", 1.1)


func _draw_edge_marker(
	target_node: Node2D,
	ring_color: Color,
	arrow_color: Color,
	label: String,
	scale_factor: float
) -> void:
	var screen := get_viewport().get_canvas_transform() * target_node.global_position
	var margin := 58.0
	var visible_rect := Rect2(
		Vector2(margin, margin),
		Vector2(size.x - margin * 2.0, size.y - margin * 2.0)
	)
	if visible_rect.has_point(screen):
		return

	var target := Vector2(
		clampf(screen.x, margin, size.x - margin),
		clampf(screen.y, margin, size.y - margin)
	)
	var direction := screen - size * 0.5
	if direction.length_squared() < 0.01:
		direction = Vector2.DOWN
	direction = direction.normalized()

	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
	var circle_radius := 21.0 * scale_factor
	draw_circle(target, circle_radius, Color(ring_color.r, ring_color.g, ring_color.b, 0.09 * pulse))
	draw_arc(
		target,
		circle_radius - 3.0,
		0.0,
		TAU,
		32,
		Color(ring_color.r, ring_color.g, ring_color.b, 0.72 * pulse),
		1.5,
		true
	)

	# 箭头本身用 HDR 颜色，让 glow 把屏幕边缘的提示推出来。
	var perpendicular := Vector2(-direction.y, direction.x)
	var base := target - direction * 7.0
	var arrow := PackedVector2Array([
		target + direction * 15.0,
		base + perpendicular * 8.0,
		base - perpendicular * 8.0,
	])
	draw_colored_polygon(
		arrow,
		Color(arrow_color.r, arrow_color.g, arrow_color.b, 0.95 * pulse)
	)

	_draw_text_at(
		target.x,
		minf(target.y + 38.0, size.y - 10.0),
		label,
		13,
		Color(ring_color.r, ring_color.g, ring_color.b, 0.9)
	)


func _draw_damage_flash() -> void:
	if _damage_flash <= 0.0:
		return

	var strength := clampf(_damage_flash, 0.0, 1.0)
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(1.0, 0.03, 0.08, 0.09 * strength)
	)
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(1.0, 0.05, 0.12, 0.3 * strength),
		false,
		36.0
	)


func _draw_text_centered(text: String, baseline_y: float, font_size: int, color: Color) -> void:
	_draw_text_at(size.x * 0.5, baseline_y, text, font_size, color)


func _draw_text_at(center_x: float, baseline_y: float, text: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(
		_font,
		Vector2(center_x - width * 0.5, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _diamond_points(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	var minutes := total / 60
	var remaining_seconds := total % 60
	return "%02d:%02d" % [minutes, remaining_seconds]

extends MenuScreen

## 开局加载动画：标题、三色轨道、进度条，结束后淡出进入主菜单。
## 资源实际是瞬时加载的，这里是一段约 1.8 秒的风格化启动演出，可随时跳过。

const DURATION := 1.8
const SELECT_SCENE := "res://scenes/main_menu.tscn"

var _loading := 0.0
var _finished := false


func _screen_ready() -> void:
	Engine.time_scale = 1.0


func _screen_process(delta: float) -> void:
	if _finished:
		return

	var t := clampf(screen_time / DURATION, 0.0, 1.0)
	_loading = 1.0 - pow(1.0 - t, 2.0)
	if t >= 1.0 and screen_time >= DURATION + 0.12:
		_finish()


func _input(event: InputEvent) -> void:
	if _finished or is_transitioning() or screen_time < 0.25:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			_finish()
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_loading = 1.0
	change_screen(SELECT_SCENE)


func _draw() -> void:
	draw_backdrop()

	var cx := size.x * 0.5
	var orbit_center := Vector2(cx, size.y * 0.285)
	var orbit_radius := minf(96.0, size.y * 0.14)
	var orbit_colors: Array[Color] = [
		Color(1.9, 0.22, 0.30, 1.0),
		Color(0.28, 1.9, 0.52, 1.0),
		Color(0.30, 0.55, 2.1, 1.0),
	]

	# 三色轨道：三枚三角绕中心缓慢公转，速度略有差异。
	draw_arc(
		orbit_center,
		orbit_radius,
		0.0,
		TAU,
		64,
		Color(1.0, 1.0, 1.0, 0.055),
		1.0,
		true
	)
	for i in 3:
		var angle := screen_time * (0.9 + float(i) * 0.13) + TAU * float(i) / 3.0
		var point := orbit_center + Vector2.from_angle(angle) * orbit_radius
		var tri := PackedVector2Array([
			point + Vector2.from_angle(angle) * 8.0,
			point + Vector2.from_angle(angle + 2.3) * 6.6,
			point + Vector2.from_angle(angle - 2.3) * 6.6,
		])
		draw_colored_polygon(tri, Color(orbit_colors[i].r, orbit_colors[i].g, orbit_colors[i].b, 0.85))
		draw_arc(
			orbit_center,
			orbit_radius,
			angle - 0.65,
			angle,
			16,
			Color(orbit_colors[i].r, orbit_colors[i].g, orbit_colors[i].b, 0.20),
			1.4,
			true
		)

	# 标题：白色主体 + 冷暖错位的色差重影。
	if bold_font != null:
		var title := "光谱突围"
		var title_size := 64
		var title_width := bold_font.get_string_size(
			title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size
		).x
		var title_x := (size.x - title_width) * 0.5
		var baseline := size.y * 0.46
		draw_string(
			bold_font, Vector2(title_x - 2.5, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, Color(2.0, 0.16, 0.30, 0.42)
		)
		draw_string(
			bold_font, Vector2(title_x + 2.5, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, Color(0.22, 0.48, 2.2, 0.42)
		)
		draw_string(
			bold_font, Vector2(title_x, baseline), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size, Color(0.96, 0.98, 1.0, 0.97)
		)

	draw_text_centered("S P E C T R U M   B R E A K O U T", size.y * 0.505, 12, Color(1.0, 1.0, 1.0, 0.34))

	# 进度条：红 / 绿 / 蓝三段依次填满。
	var bar_width := minf(420.0, size.x * 0.42)
	var bar := Rect2(cx - bar_width * 0.5, size.y * 0.65, bar_width, 2.0)
	draw_rect(bar.grow(1.0), Color(1.0, 1.0, 1.0, 0.07))
	var filled := bar_width * _loading
	var segment_colors: Array[Color] = [
		Color(1.8, 0.24, 0.28, 1.0),
		Color(0.26, 1.8, 0.46, 1.0),
		Color(0.30, 0.52, 2.0, 1.0),
	]
	for i in 3:
		var seg_start := bar_width * float(i) / 3.0
		var seg_end := bar_width * float(i + 1) / 3.0
		var vis_end := minf(seg_end, filled)
		if vis_end > seg_start:
			draw_rect(
				Rect2(
					bar.position + Vector2(seg_start, 0.0),
					Vector2(vis_end - seg_start, bar.size.y)
				),
				segment_colors[i]
			)
	if _loading > 0.01 and _loading < 1.0:
		draw_diamond(
			bar.position + Vector2(filled, 0.0),
			4.0,
			Color(2.4, 2.4, 2.4, 0.9)
		)

	var dots := ".".repeat(int(screen_time * 3.0) % 4)
	var caption := "正在校准色彩矩阵" + dots
	if _loading >= 0.999:
		caption = "色彩矩阵就绪"
	draw_text_centered(caption, size.y * 0.65 + 30.0, 13, Color(1.0, 1.0, 1.0, 0.48))

	# 四角装饰文字。
	if font != null:
		draw_string(
			font, Vector2(36.0, 38.0), "SPECTRUM BREAKOUT // BOOT",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.22)
		)
		if not _finished:
			draw_text_centered(
				"点击或按任意键跳过", size.y - 34.0, 12, Color(1.0, 1.0, 1.0, 0.28)
			)

	draw_fade_overlay()

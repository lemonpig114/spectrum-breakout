class_name MenuScreen
extends Control

## 开局流程（加载动画 → 选择机体）的公共基类。
## 负责字体、深色网格背景、淡出转场和居中文字，子类只画自己的内容。
## 这些界面都用自绘，不依赖贴图，和局内 HUD 的极简霓虹风格保持一致。

const FONT_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"
# OpenType 的 wght 轴标签，必须用整数；字符串 "wght" 会被静默忽略。
const WGHT_AXIS := 0x77676874

var font: Font
var bold_font: FontVariation
var screen_time := 0.0

var _fade := 0.0
var _next_scene := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load(FONT_PATH)
	if font != null:
		ThemeDB.fallback_font = font
		ThemeDB.fallback_font_size = 16
		bold_font = FontVariation.new()
		bold_font.base_font = font
		bold_font.variation_opentype = {WGHT_AXIS: 800}
	RenderingServer.set_default_clear_color(Color.BLACK)
	_screen_ready()


func _process(delta: float) -> void:
	screen_time += delta

	if not _next_scene.is_empty():
		_fade = minf(1.0, _fade + delta * 3.4)
		if _fade >= 1.0:
			var target := _next_scene
			_next_scene = ""
			get_tree().change_scene_to_file(target)
			return

	_screen_process(delta)
	queue_redraw()


## 子类初始化钩子。
func _screen_ready() -> void:
	pass


## 子类每帧逻辑钩子。
func _screen_process(_delta: float) -> void:
	pass


func change_screen(path: String) -> void:
	if _next_scene.is_empty():
		_fade = 0.0
		_next_scene = path


func is_transitioning() -> bool:
	return not _next_scene.is_empty()


## 深色网格背景 + 缓慢移动的扫描线。
func draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.008, 0.014, 1.0))

	var step := 64.0
	var x := -step + fmod(screen_time * 7.0, step)
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(0.06, 0.09, 0.145, 0.75), 1.0)
		x += step

	var y := -step + fmod(screen_time * 4.0, step)
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.06, 0.09, 0.145, 0.75), 1.0)
		y += step

	var scan_y := fmod(screen_time * 70.0, size.y + 160.0) - 80.0
	draw_line(
		Vector2(0.0, scan_y),
		Vector2(size.x, scan_y),
		Color(0.10, 0.20, 0.34, 0.12),
		1.0
	)


func draw_fade_overlay() -> void:
	if _fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, _fade))


func draw_text_centered(
	text: String, baseline_y: float, font_size: int, color: Color, use_bold: bool = false
) -> void:
	var draw_font: Font = font
	if use_bold and bold_font != null:
		draw_font = bold_font
	if draw_font == null:
		return
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


func draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius, 0.0),
		]),
		color
	)

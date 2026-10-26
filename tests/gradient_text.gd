extends Node2D

## 开发用：开局即显示、永不消失的渐变文字对照场景，用于反复调 Shader。
## godot --path . res://tests/gradient_text.tscn
## 截图：godot --path . res://tests/gradient_text.tscn -- --shot res://tests/gradient_text.png
##
## 场景内容：
## - 64 px 的 270 / 1013 / 2700 / 88888，检查字符内部与字符之间的连续性；
## - 35 px 的 2700，检查游戏内实际字号；
## - 常规 / 粗体 / 纯白对照，确认字体、基线、字重。

const FONT_PATH := "res://assets/fonts/NotoSansSC-Variable.ttf"
const GRADIENT_SHADER := preload("res://shaders/super_crit_gradient.gdshader")
# OpenType 的 wght 轴标签。字典键必须是整数标签，字符串 "wght" 不会被识别。
const WGHT_AXIS := 0x77676874

const SAMPLES := [
	["270", 64, Vector2(160.0, 120.0), 0.0, 6],
	["1013", 64, Vector2(520.0, 120.0), 1.6, 6],
	["2700", 64, Vector2(880.0, 120.0), 3.2, 6],
	["88888", 64, Vector2(160.0, 300.0), 4.8, 6],
	["2700", 35, Vector2(520.0, 300.0), 2.4, 6],
]

var _bold_font: FontVariation


func _ready() -> void:
	var font := load(FONT_PATH) as Font
	if font != null:
		ThemeDB.fallback_font = font

	_bold_font = FontVariation.new()
	_bold_font.base_font = font
	_bold_font.variation_opentype = {WGHT_AXIS: 800}

	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0))

	for sample in SAMPLES:
		_add_gradient(sample[0], sample[1], sample[2], sample[3], sample[4])

	# 常规 / 粗体 / 纯白对照。
	_add_plain("2700 常规", 48, Vector2(160.0, 480.0), null)
	_add_plain("2700 粗体", 48, Vector2(480.0, 480.0), _bold_font)
	_add_plain("2700", 64, Vector2(880.0, 300.0), null)

	_maybe_capture()


func _add_gradient(
	text: String, font_size: int, position: Vector2, phase: float, outline: int
) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_override("font", _bold_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = label.get_minimum_size()

	var material := ShaderMaterial.new()
	material.shader = GRADIENT_SHADER
	material.set_shader_parameter("rim_strength", 0.8)
	material.set_shader_parameter(
		"text_size",
		Vector2(float(font_size) * float(text.length()) * 0.62, float(font_size) * 1.45)
	)
	material.set_shader_parameter("phase", phase)
	label.material = material
	add_child(label)


func _add_plain(text: String, font_size: int, position: Vector2, font: Font) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = label.get_minimum_size()
	add_child(label)


func _maybe_capture() -> void:
	var args := OS.get_cmdline_user_args()
	var shot_index := args.find("--shot")
	if shot_index < 0 or shot_index + 1 >= args.size():
		return
	var path := args[shot_index + 1]

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("GRADIENT screenshot error=%s path=%s" % [error, path])
	get_tree().quit()

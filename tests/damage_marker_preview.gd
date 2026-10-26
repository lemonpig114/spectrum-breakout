extends Node2D
var layer: FloatingTextLayer
var age := 0.0
var snapshot := false
var font: Font
func _ready() -> void:
	font = load("res://assets/fonts/NotoSansSC-Variable.ttf")
	ThemeDB.fallback_font = font
	layer = FloatingTextLayer.new()
	add_child(layer)
	var args := OS.get_cmdline_user_args()
	snapshot = args.has("--shot")
	_spawn()
	if snapshot:
		await get_tree().create_timer(0.20).timeout
		await RenderingServer.frame_post_draw
		var filename := "res://tests/damage_number_new.png"
		print("MARKER screenshot=", layer.get_viewport().get_texture().get_image().save_png(filename), " ", filename)
		get_tree().quit()

func _process(delta: float) -> void:
	age += delta
	if age > 1.2 and not snapshot:
		age = 0.0
		_spawn()
	queue_redraw()

func _spawn() -> void:
	layer.add_text(Vector2(310, 184), "124", Color(0.3, 1.8, 0.8), 0, FloatingTextLayer.STYLE_WEAKNESS)
	layer.add_text(Vector2(310, 276), "348", Color(2.2, 1.1, 0.3), 0, FloatingTextLayer.STYLE_CRIT)
	layer.add_text(Vector2(310, 368), "67", Color(2.2, 1.3, 0.45), 0, FloatingTextLayer.STYLE_ELEMENTAL)
	layer.add_text(Vector2(310, 462), "1228", Color.WHITE, 0, FloatingTextLayer.STYLE_SUPER_CRIT)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.012, 0.018, 0.032))
	draw_string(font, Vector2(72, 72), "伤害数字 · 居中短词与轻缩放", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.85, 0.94, 1))
	draw_string(font, Vector2(76, 105), "弱点 / 暴击保持攻击颜色 · 超暴击保留彩色渐变", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.66, 0.75))
	var names := ["弱点", "暴击", "元素", "超暴击"]
	for i in 4:
		var y := 168.0 + float(i) * 92.0
		draw_rect(Rect2(72, y, 560, 76), Color(0.028, 0.042, 0.07), true)
		draw_rect(Rect2(72, y, 560, 76), Color(0.12, 0.24, 0.32), false, 1)
		draw_string(font, Vector2(98, y + 47), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.67, 0.78, 0.87))

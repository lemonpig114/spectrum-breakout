extends Node2D

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const KINDS := [&"chaser_triangle", &"chaser_square", &"chaser_hex", &"ranged_plane", &"chaser_round"]
const NAMES := ["迅捷三角 · 25", "基础方块 · 60", "重装六边 · 200", "飞翼射手 · 240 秒", "疾爆圆核 · 300 秒"]
var font: Font


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansSC-Variable.ttf")
	ThemeDB.fallback_font = font
	var target := Node2D.new()
	add_child(target)
	for row in KINDS.size():
		for color in ColorType.COUNT:
			var enemy := ENEMY_SCENE.instantiate() as Enemy
			enemy.configure(ContentDB.get_enemy(KINDS[row]), target, color)
			add_child(enemy)
			enemy.global_position = Vector2(420.0 + color * 250.0, 160.0 + row * 110.0)
			enemy.scale = Vector2(2.2, 2.2)
			enemy.rotation = 0.0
			enemy._visual_angle = 0.0
			enemy._healthbar.visible = false
			enemy.set_physics_process(false)
	queue_redraw()
	if OS.get_cmdline_user_args().has("--shot"):
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var path := "res://tests/enemy_roster_preview.png"
		print("ENEMY ROSTER screenshot=", get_viewport().get_texture().get_image().save_png(path), " ", path)
		get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.012, 0.018, 0.032))
	draw_string(font, Vector2(60, 66), "敌人类型 × 独立颜色", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(0.86, 0.94, 1.0))
	for color in ColorType.COUNT:
		draw_string(font, Vector2(390 + color * 250, 100), ["红", "绿", "蓝"][color],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, RunState.color_of(color))
	for row in KINDS.size():
		var y := 115.0 + row * 110.0
		draw_rect(Rect2(50, y, 1140, 90), Color(0.035, 0.055, 0.08, 0.75))
		draw_rect(Rect2(50, y, 1140, 90), Color(0.14, 0.21, 0.28, 0.65), false, 1.0)
		draw_string(font, Vector2(74, y + 54), NAMES[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.82, 0.9))

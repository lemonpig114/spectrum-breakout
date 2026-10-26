extends Node2D

## 第九轮视觉验收台：Space 重播，Enter 进入正常游戏；不修改玩法资源。
const TITLES := ["01  精准暴击", "02  重型冲击", "03  溅射爆破", "04  灵魂共振", "05  反击震波", "06  壳体碎裂"]
const NOTES := ["锐利星芒 · 保留清晰边缘", "短促白核 · 暖色能量层", "断环碎片 · 向外扩散", "六芒印记 · 旋转雾带", "双层冲击 · 外沿渐隐", "独立壳片 · 分离消隐"]
var _timer := 0.0
var _clock := 0.0
var _colors: Array[Color] = [Color(0.2, 1.6, 2.4), Color(2.4, 1.1, 0.2), Color(2.4, 0.15, 0.35), Color(1.1, 0.35, 2.4), Color(2.4, 0.65, 0.15), Color(0.15, 2.2, 0.65)]


func _ready() -> void:
	ThemeDB.fallback_font = load("res://assets/fonts/NotoSansSC-Variable.ttf")
	RunState.begin_run()
	add_to_group("fx_layer")
	FX.prewarm(self)
	_label("视觉实验室  /  NEON STUDIES", Vector2(52, 26), 25, Color(0.85, 0.94, 1))
	_label("几何轮廓 × 柔光纹理 × 动态能量层", Vector2(54, 66), 15, Color(0.4, 0.55, 0.66))
	for i in 6:
		var origin := Vector2(52 + (i % 3) * 398, 116 + (i / 3) * 230)
		_label(TITLES[i], origin + Vector2(18, 12), 18, _colors[i].clamp())
		_label(NOTES[i], origin + Vector2(18, 191), 13, Color(0.45, 0.58, 0.68))
	_label("RGB 弹丸  /  渐变尾焰与白热核心", Vector2(54, 601), 15, Color(0.65, 0.77, 0.85))
	var replay := Button.new()
	replay.text = "重播特效  [Space]"
	replay.position = Vector2(790, 646)
	replay.size = Vector2(205, 42)
	replay.pressed.connect(_replay)
	add_child(replay)
	var play := Button.new()
	play.text = "进入实战  [Enter]"
	play.position = Vector2(1010, 646)
	play.size = Vector2(215, 42)
	play.pressed.connect(_play)
	add_child(play)
	_replay()
	if OS.get_cmdline_user_args().has("--shot"):
		await get_tree().create_timer(0.18).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/visual_review.png")
		get_tree().quit()


func _label(value: String, at: Vector2, size: int, tint: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.modulate = tint
	add_child(label)


func _replay() -> void:
	_timer = 1.35
	for i in 6:
		var center := Vector2(238 + (i % 3) * 398, 232 + (i / 3) * 230)
		FX.hit_burst(center, _colors[i], 62.0 if i != 4 else 76.0, 0.78, i)
		if i == 5:
			FX.shards(center, _colors[i], 12)


func _play() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_replay()
		elif event.keycode == KEY_ENTER:
			_play()


func _process(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer <= 0:
		_replay()
	queue_redraw()


func _draw() -> void:
	for x in range(0, 1280, 32):
		draw_line(Vector2(x, 0), Vector2(x, 720), Color(0.04, 0.075, 0.105, 0.5))
	for y in range(0, 720, 32):
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0.04, 0.075, 0.105, 0.5))
	for i in 6:
		var origin := Vector2(52 + (i % 3) * 398, 116 + (i / 3) * 230)
		draw_style_box(_panel_style(), Rect2(origin, Vector2(380, 216)))
	# 三色弹丸的同款尾焰示意，不参与碰撞或伤害。
	for i in 3:
		var c := _colors[[2, 5, 0][i]]
		var p := Vector2(180 + i * 220 + fmod(_clock * 110.0, 125.0), 662)
		draw_texture_rect(preload("res://scripts/fx/NeonTexture.gd").halo(), Rect2(p - Vector2(20, 20), Vector2(40, 40)), false, Color(c, 0.4))
		draw_polygon(PackedVector2Array([p + Vector2(10, 0), p + Vector2(-4, 5), p + Vector2(-64, 0), p + Vector2(-4, -5)]), PackedColorArray([c, Color(c, 0.6), Color(c, 0), Color(c, 0.6)]))
		draw_circle(p, 2.0, Color(2.5, 2.5, 2.5))


var _panel: StyleBoxFlat
func _panel_style() -> StyleBoxFlat:
	if _panel == null:
		_panel = StyleBoxFlat.new()
		_panel.bg_color = Color(0.012, 0.022, 0.034, 0.88)
		_panel.border_color = Color(0.1, 0.18, 0.24, 0.7)
		_panel.set_border_width_all(1)
		_panel.set_corner_radius_all(12)
	return _panel

extends MenuScreen

var buttons: Array[Button] = []
var settings: Control
var codex: Control
var _save_summary := "暂无可继续的存档"


func _screen_ready() -> void:
	Engine.time_scale = 1.0
	var data := GameSave.read_run()
	if not data.is_empty():
		var seconds := int(data.run.get("elapsed", 0))
		_save_summary = "%02d:%02d  ·  等级 %d" % [seconds / 60, seconds % 60, int(data.run.get("level", 1))]
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.offset_left = -180
	column.offset_right = 180
	column.offset_top = -76
	column.offset_bottom = 230
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var titles := ["开始游戏", "继续游戏", "设置", "图鉴", "退出"]
	for i in titles.size():
		var button := _button(titles[i])
		button.pressed.connect(_activate.bind(i))
		column.add_child(button)
		buttons.append(button)
	buttons[1].disabled = data.is_empty()
	settings = _make_settings()
	add_child(settings)
	settings.hide()
	codex = preload("res://scripts/ui/CodexPanel.gd").new()
	add_child(codex)
	codex.hide()
	codex.closed.connect(func(): codex.hide())


func _draw() -> void:
	draw_backdrop()
	draw_text_centered("光谱突围", size.y * 0.18, 48, Color(0.9, 0.96, 1.0), true)
	draw_text_centered("SPECTRUM BREAKOUT", size.y * 0.18 + 30, 14, Color(0.35, 0.65, 0.95, 0.65))
	var center := Vector2(size.x * 0.5, size.y * 0.31)
	for i in 3:
		var color: Color = [Color(1.0, 0.2, 0.35), Color(0.2, 1.0, 0.45), Color(0.24, 0.48, 1.0)][i]
		draw_arc(center, 23 + i * 6, screen_time * (0.2 + i * 0.08) + i * 2.1,
			screen_time * (0.2 + i * 0.08) + i * 2.1 + 3.5, 32, color, 2.0, true)
	draw_text_centered(_save_summary, size.y - 56, 15, Color(0.55, 0.7, 0.82, 0.8))
	draw_fade_overlay()


func _button(title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 21)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.055, 0.095, 0.96)
		style.border_color = Color(0.22, 0.55, 0.85, 0.75 if state in ["hover", "focus"] else 0.25)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(state, style)
	return button


func _activate(index: int) -> void:
	if is_transitioning():
		return
	Audio.play(&"ui_click")
	match index:
		0:
			GameSave.pending = {}
			change_screen("res://scenes/character_select.tscn")
		1:
			if GameSave.request_continue():
				change_screen("res://scenes/main.tscn")
			else:
				buttons[1].disabled = true
		2: settings.show()
		3: codex.show()
		4: get_tree().quit()


func _make_settings() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.008, 0.02, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var volume_label := Label.new()
	volume_label.text = "音效音量"
	box.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = Audio.volume()
	volume.custom_minimum_size.y = 34
	volume.value_changed.connect(func(value): Audio.set_volume(value))
	box.add_child(volume)
	var mute := CheckButton.new()
	mute.text = "静音"
	mute.custom_minimum_size.y = 44
	mute.button_pressed = Audio.is_muted()
	mute.toggled.connect(func(value): Audio.set_muted(value))
	box.add_child(mute)
	var fps := CheckButton.new()
	fps.text = "显示 FPS"
	fps.custom_minimum_size.y = 44
	fps.button_pressed = GameInput.show_fps
	fps.toggled.connect(func(value): GameInput.set_show_fps(value))
	box.add_child(fps)
	if GameInput.touch_controls_active:
		var follow := CheckButton.new()
		follow.text = "摇杆底座跟随手指"
		follow.custom_minimum_size.y = 44
		follow.button_pressed = GameInput.joystick_follow
		follow.toggled.connect(func(value): GameInput.set_joystick_follow(value))
		box.add_child(follow)
	var back := _button("返回")
	back.pressed.connect(func(): overlay.hide())
	box.add_child(back)
	return overlay


func _unhandled_input(event: InputEvent) -> void:
	if settings.visible and event.is_action_pressed(&"pause"):
		settings.hide()
		get_viewport().set_input_as_handled()

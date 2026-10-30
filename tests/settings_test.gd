extends Node

var failures := 0


func check(ok: bool, label: String) -> void:
	print("SETTINGS %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(2.4).timeout
	Director.stop()
	var was_mobile := GameInput.touch_controls_active
	var was_fps := GameInput.show_fps
	main._toggle_manual_pause()
	var panel: PausePanel = main.pause_panel
	panel._screen = PausePanel.Screen.SETTINGS
	for mobile in [false, true]:
		GameInput.touch_controls_active = mobile
		var hud_size: Vector2 = main.hud_control.size
		main.camera.setup(main.player, RunState.arena_rect)
		check(main.camera.zoom == Vector2.ONE * (1.3 if mobile else 1.0), "mobile camera magnifies world by thirty percent only")
		check(main.hud_control.size == hud_size, "camera magnification leaves HUD and touch dimensions unchanged")
		GameInput.set_show_fps(false)
		var layout := panel._layout()
		var rect := panel._fps_setting_rect(layout)
		check(not rect.intersects(panel._mute_rect(layout)), "FPS row does not overlap audio settings")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = rect.get_center()
		panel._gui_input(click)
		check(GameInput.show_fps, "desktop/mobile settings enable FPS")
		var config := ConfigFile.new()
		check(config.load(GameInput.DISPLAY_SETTINGS_PATH) == OK and config.get_value("hud", "show_fps", false), "FPS preference is saved")
		panel._gui_input(click)
		check(not GameInput.show_fps, "FPS setting switches off")
	GameInput.touch_controls_active = was_mobile
	GameInput.set_show_fps(was_fps)
	main._toggle_manual_pause()
	# Cache must invalidate for in-place dynamic changes, not only new modifiers.
	var stats := StatBlock.new()
	stats.set_base(&"damage", 10.0)
	var modifier := StatModifierResource.new()
	modifier.source = &"test"
	modifier.value = 5.0
	stats.add_modifier(modifier)
	check(stats.get_value(&"damage") == 15.0, "cached stat initially correct")
	modifier.value = 8.0
	check(stats.get_value(&"damage") == 18.0, "changing modifier value invalidates cached stat immediately")
	check(stats.get_value_without_source(&"damage", &"test") == 10.0, "source-removal estimate retains exact semantics")
	stats.set_base(&"damage", 20.0)
	check(stats.get_value(&"damage") == 28.0, "base-stat change invalidates cached value")
	stats.remove_modifiers_from(&"test")
	check(stats.get_value(&"damage") == 20.0, "modifier removal invalidates cached value")
	print("SETTINGS TEST %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

extends Node

## godot --headless --path . res://tests/mobile_controls_test.tscn -- --mobile-controls-test
var failures := 0


func _ready() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var mobile: MobileControls = main.get("mobile_controls")
	var player: Player = main.get("player")
	var pause_panel: PausePanel = main.get("pause_panel")
	player.controls_enabled = true
	RunState.start()
	mobile._process(0.016)
	failures += _check(GameInput.touch_controls_active, "touch mode is enabled")
	failures += _check(mobile.visible, "floating controls appear during play")

	mobile._input(_touch(1, Vector2(110, 550), true))
	mobile._input(_drag(1, Vector2(175, 550)))
	failures += _check(GameInput.mobile_move_direction.x > 0.95, "joystick reaches full speed")
	failures += _check(absf(GameInput.mobile_move_direction.y) < 0.01, "joystick keeps heading")

	var first_color := RunState.color_index
	mobile._input(_touch(2, Vector2(900, 560), true))
	mobile._input(_touch(2, Vector2(900, 560), false))
	failures += _check(RunState.color_index == ColorType.next(first_color), "second finger tap switches color")
	failures += _check(GameInput.mobile_move_direction.x > 0.95, "second finger does not interrupt movement")

	var color_after_tap := RunState.color_index
	mobile._input(_touch(2, Vector2(900, 560), true))
	mobile._input(_drag(2, Vector2(855, 560)))
	mobile._input(_touch(2, Vector2(855, 560), false))
	failures += _check(RunState.color_index == ColorType.next(color_after_tap, -1), "left swipe switches back")

	mobile._input(_touch(1, Vector2(175, 550), false))
	failures += _check(GameInput.mobile_move_direction == Vector2.ZERO, "lift releases movement")

	mobile._input(_touch(3, Vector2(120, 550), true))
	mobile._input(_drag(3, Vector2(125, 550)))
	failures += _check(GameInput.mobile_move_direction == Vector2.ZERO, "small motion stays inside dead zone")
	mobile._input(_drag(3, Vector2(300, 550)))
	failures += _check(mobile._base.x > 120.0 and GameInput.mobile_move_direction.x > 0.95,
		"floating base follows a long thumb drag")
	RunState.request_pause(&"manual_pause")
	mobile._process(0.016)
	failures += _check(GameInput.mobile_move_direction == Vector2.ZERO and mobile._move_index < 0,
		"pause releases joystick")
	RunState.release_pause(&"manual_pause")
	var pause_point := Vector2(mobile.size.x - 45.0, 45.0)
	mobile._input(_touch(5, pause_point, true))
	failures += _check(mobile._switch_index < 0, "pause button touch is not a color gesture")

	var color_before_hold := RunState.color_index
	mobile._input(_touch(6, Vector2(900, 550), true))
	player._hold_start_ms -= 200
	player._process(0.016)
	failures += _check(player._hold_preview_emitted, "long hold opens color preview")
	mobile._input(_touch(6, Vector2(900, 550), false))
	failures += _check(RunState.color_index == color_before_hold, "long hold without direction cancels")
	mobile._input(_touch(7, Vector2(900, 550), true))
	mobile._input(_drag(7, Vector2(900, 500)))
	mobile._input(_touch(7, Vector2(900, 500), false))
	failures += _check(RunState.color_index == color_before_hold, "vertical swipe does not become a tap")

	var emulated_mouse := InputEventMouseButton.new()
	emulated_mouse.button_index = MOUSE_BUTTON_LEFT
	emulated_mouse.pressed = true
	player._unhandled_input(emulated_mouse)
	failures += _check(not player._manual_fire_held, "touch mode ignores mouse aim")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	failures += _check(get_tree().paused and pause_panel.visible,
		"Android back opens pause instead of quitting")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	failures += _check(not get_tree().paused and not pause_panel.visible,
		"Android back resumes from pause")
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	failures += _check(get_tree().paused, "backgrounding pauses the run")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mobile-shot="):
			mobile._input(_touch(4, Vector2(170, 560), true))
			mobile._input(_drag(4, Vector2(218, 533)))
			await RenderingServer.frame_post_draw
			var path := argument.trim_prefix("--mobile-shot=")
			var image := get_viewport().get_texture().get_image()
			image.save_png(path)
			print("MOBILE SHOT ", path)
			break

	print("MOBILE CONTROLS %s" % ("PASS" if failures == 0 else "FAIL: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event


func _check(condition: bool, label: String) -> int:
	if condition:
		print("PASS ", label)
		return 0
	push_error("FAIL " + label)
	return 1

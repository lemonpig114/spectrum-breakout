class_name PauseButton
extends Control

## 右上角的小暂停按钮。程序化绘制，不使用贴图。
## 点击后由 Main 打开 PausePanel；隐藏 HUD 时会随父节点一起消失。

signal pressed

var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "暂停" if GameInput.touch_controls_active else "暂停 (Esc)"
	if GameInput.touch_controls_active:
		offset_left = -82.0
		offset_top = 40.0
		offset_right = -16.0
		offset_bottom = 106.0


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5

	draw_circle(center, radius, Color(0.02, 0.03, 0.05, 0.72 if _hover else 0.5))
	draw_arc(
		center,
		radius - 1.0,
		0.0,
		TAU,
		32,
		Color(1.0, 0.86, 0.45, 0.9 if _hover else 0.5),
		1.4,
		true
	)

	var bar := Color(1.0, 0.9, 0.55, 1.0 if _hover else 0.82)
	var half_height := 6.0
	var width := 3.2
	draw_rect(
		Rect2(center + Vector2(-6.2, -half_height), Vector2(width, half_height * 2.0)),
		bar
	)
	draw_rect(
		Rect2(center + Vector2(3.0, -half_height), Vector2(width, half_height * 2.0)),
		bar
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var hovering := Rect2(Vector2.ZERO, size).has_point(motion.position)
		if hovering != _hover:
			_hover = hovering
			queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			accept_event()
			Audio.play(&"ui_click")
			pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover:
		_hover = false
		queue_redraw()

class_name CameraRig
extends Camera2D

## 跟随、trauma 震屏、开局拉远。HUD 在 CanvasLayer 中，不受相机影响。

var target: Node2D
var follow_speed := 6.0
var shake_strength := 18.0

var _trauma := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("camera_rig")
	_rng.randomize()
	enabled = true


func setup(follow_target: Node2D, arena: Rect2) -> void:
	target = follow_target
	limit_left = int(arena.position.x)
	limit_top = int(arena.position.y)
	limit_right = int(arena.position.x + arena.size.x)
	limit_bottom = int(arena.position.y + arena.size.y)
	global_position = follow_target.global_position
	zoom = Vector2.ONE * gameplay_zoom()


func gameplay_zoom() -> float:
	return 1.3 if GameInput.touch_controls_active else 1.0


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		var weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(target.global_position, weight)

	_trauma = maxf(0.0, _trauma - delta * 2.2)
	if _trauma > 0.0:
		var amount := _trauma * _trauma * shake_strength
		offset = Vector2(
			_rng.randf_range(-amount, amount),
			_rng.randf_range(-amount, amount)
		)
		rotation = _rng.randf_range(-0.006, 0.006) * _trauma
	else:
		offset = Vector2.ZERO
		rotation = 0.0


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func play_intro(start_zoom: float, end_zoom: float, duration: float) -> void:
	zoom = Vector2.ONE * start_zoom * gameplay_zoom()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "zoom", Vector2.ONE * end_zoom * gameplay_zoom(), duration)

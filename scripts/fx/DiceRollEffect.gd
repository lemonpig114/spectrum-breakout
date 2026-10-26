class_name DiceRollEffect
extends Node2D

## 每局复用一个小骰子；先翻滚，再明确停在真实结算点数上。
const ROLL_TIME := 0.32
const HOLD_TIME := 0.95
const FADE_TIME := 0.25
const LIFETIME := ROLL_TIME + HOLD_TIME + FADE_TIME
const PIPS := [
	[Vector2(0, 0)],
	[Vector2(-1, -1), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
]

var result := 1
var displayed_value := 1
var _age := 0.0
var _target: Node2D


func _ready() -> void:
	z_index = 45
	clear()


func play(target: Node2D, value: int) -> void:
	_target = target
	result = clampi(value, 1, 6)
	_age = 0.0
	displayed_value = result
	visible = true
	set_process(true)
	_update_pose()
	queue_redraw()


func clear() -> void:
	visible = false
	_target = null
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	set_process(false)


func _process(delta: float) -> void:
	if not is_instance_valid(_target) or RunState.is_dead:
		clear()
		return
	_age += delta
	if _age >= LIFETIME:
		clear()
		return
	_update_pose()
	queue_redraw()


func _update_pose() -> void:
	if not is_instance_valid(_target):
		return
	var rolling := _age < ROLL_TIME
	var phase := clampf(_age / ROLL_TIME, 0.0, 1.0)
	# 视觉翻面只由时间计算，不消费战斗 RNG，也不参与属性结算。
	displayed_value = 1 + posmod(result + int(_age * 28.0), 6) if rolling else result
	rotation = sin(phase * TAU * 2.0) * 0.42 * (1.0 - phase) if rolling else 0.0
	var pop := 0.88 + 0.12 * phase + 0.20 * sin(phase * PI)
	scale = Vector2.ONE * pop
	global_position = _target.global_position + Vector2(0, -52.0 - sin(phase * PI) * 9.0)
	modulate.a = 1.0 - clampf((_age - ROLL_TIME - HOLD_TIME) / FADE_TIME, 0.0, 1.0)


func _draw() -> void:
	var tint := Color(0.65, 0.78, 0.90)
	if _age >= ROLL_TIME:
		if result <= 2:
			tint = Color(1.1, 0.34, 0.40)
		elif result >= 4:
			tint = Color(1.6, 1.15, 0.38) if result == 6 else Color(0.45, 1.1, 0.78)
	draw_texture_rect(preload("res://scripts/fx/NeonTexture.gd").halo(), Rect2(-32, -32, 64, 64), false, Color(tint, 0.20))
	draw_rect(Rect2(-17, -15, 34, 34), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-16, -16, 32, 32), Color(0.025, 0.035, 0.055, 0.95))
	draw_rect(Rect2(-16, -16, 32, 32), Color(tint, 0.9), false, 1.5)
	for pip in PIPS[displayed_value - 1]:
		draw_circle(pip * 8.0, 2.5, tint)

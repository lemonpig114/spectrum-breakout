class_name RoundExplosion
extends Node2D

## 圆核的伤害范围用扩张圆波标明，短裂光保留爆炸力度。
const DURATION := 0.24

var tint := Color.WHITE
var max_radius := 64.0
var _time := 0.0


func _ready() -> void:
	add_to_group(&"round_blasts")
	z_index = 8


func _process(delta: float) -> void:
	_time += delta
	if _time >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_time / DURATION, 0.0, 1.0)
	var fade := 1.0 - progress
	var ring_fade := 1.0 - pow(progress, 2.2)
	var ring_radius := lerpf(5.0, max_radius, minf(progress / 0.72, 1.0))
	var reach := lerpf(13.0, max_radius - 6.0, sin(progress * PI * 0.5))
	draw_circle(Vector2.ZERO, ring_radius, Color(tint.r, tint.g, tint.b, ring_fade * 0.045))
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48,
		Color(tint.r * 1.7, tint.g * 1.7, tint.b * 1.7, ring_fade * 0.92), 2.8, true)
	draw_arc(Vector2.ZERO, maxf(1.0, ring_radius - 4.0), 0.0, TAU, 48,
		Color(2.2, 2.2, 2.2, ring_fade * 0.16), 1.0, true)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + (0.08 if i % 2 == 0 else -0.08)
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		var start := direction * (5.0 + progress * 13.0)
		var tip := direction * reach
		var width := (5.0 if i % 2 == 0 else 3.5) * fade
		draw_colored_polygon(PackedVector2Array([start - side * width, tip, start + side * width]),
			Color(tint.r * 1.5, tint.g * 1.5, tint.b * 1.5, fade * 0.7))
		draw_line(start, tip, Color(tint.r * 2.0, tint.g * 2.0, tint.b * 2.0, fade * 0.85), 1.5, true)
	var core := 8.0 * fade
	if core > 0.1:
		draw_colored_polygon(PackedVector2Array([
			Vector2(core, 0), Vector2(0, core), Vector2(-core, 0), Vector2(0, -core)
		]), Color(2.4, 2.4, 2.4, fade))

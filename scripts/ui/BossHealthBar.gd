class_name BossHealthBar
extends RefCounted

var ratio := 1.0
var trail := 1.0
var _delay := 0.0
var _initialized := false
var current := 1.0
var maximum := 1.0


func set_health(value: float, limit: float) -> void:
	current = maxf(0.0, value)
	maximum = maxf(1.0, limit)
	var next := clampf(current / maximum, 0.0, 1.0)
	if not _initialized or next > ratio:
		trail = next
		_initialized = true
	elif next < ratio:
		_delay = 0.18
	ratio = next


func step(delta: float) -> void:
	_delay = maxf(0.0, _delay - delta)
	if _delay <= 0.0:
		trail = lerpf(trail, ratio, 1.0 - exp(-4.5 * delta))
		if absf(trail - ratio) < 0.001:
			trail = ratio


func paint(canvas: CanvasItem, at: Vector2, tint: Color, width: float = 260.0, height: float = 12.0, caption: String = "") -> void:
	canvas.draw_rect(Rect2(at - Vector2(3, 3), Vector2(width + 6, height + 6)), Color(0.012, 0.02, 0.04, 0.96))
	canvas.draw_rect(Rect2(at, Vector2(width, height)), Color(0.08, 0.1, 0.15, 0.95))
	canvas.draw_rect(Rect2(at, Vector2(width * trail, height)), Color(0.46, 0.42, 0.58, 0.8))
	var fill_width := width * ratio
	for row in 4:
		var shade: float = [0.95, 0.72, 0.54, 0.34][row]
		canvas.draw_rect(Rect2(at + Vector2(0, height * row / 4.0), Vector2(fill_width, height / 4.0)),
			Color(tint.r * shade, tint.g * shade, tint.b * shade, 0.95))
	# Short slanted cuts give the fill an etched-metal texture.
	var x := 7.0
	while x + 5.0 < fill_width:
		canvas.draw_line(at + Vector2(x, height), at + Vector2(x + 5.0, 0), Color(0.01, 0.02, 0.04, 0.48), 1.0)
		x += 13.0
	canvas.draw_line(at, at + Vector2(width, 0), Color(tint.r, tint.g, tint.b, 0.5), 1.0)
	canvas.draw_line(at + Vector2(width * ratio, 0), at + Vector2(width * ratio, height), Color(1.8, 1.8, 2.0, 0.7), 1.0)
	if not caption.is_empty():
		var font := ThemeDB.fallback_font
		var size := 11 if width < 100 else 15
		var text_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		canvas.draw_string_outline(font, at + Vector2((width - text_width) * 0.5, -6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color.BLACK)
		canvas.draw_string(font, at + Vector2((width - text_width) * 0.5, -6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.9, 0.94, 1.0))

class_name CardFeedback
extends Node2D

static var active_count := 0
var from := Vector2.ZERO
var destination := Vector2.ZERO
var tint := Color(0.45, 0.85, 1)
var age := 0.0

static func zoom_begin(canvas: CanvasItem, rect: Rect2, factor: float) -> void:
	canvas.draw_set_transform(rect.get_center() * (1.0 - factor), 0, Vector2.ONE * factor)

static func play(owner: Control, rect: Rect2, color: Color) -> void:
	if active_count >= 8: return
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.get_tree().root.add_child(layer)
	var effect := CardFeedback.new()
	effect.from = owner.get_global_transform_with_canvas() * rect.get_center()
	effect.destination = owner.get_viewport_rect().size - Vector2(42, 42)
	var player := owner.get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null:
		effect.destination = player.get_global_transform_with_canvas().origin
	effect.tint = color
	layer.add_child(effect)
	active_count += 1

func _exit_tree() -> void:
	active_count = maxi(0, active_count - 1)

func _process(delta: float) -> void:
	age += delta
	if age >= 0.42:
		get_parent().queue_free()
	queue_redraw()

func _draw() -> void:
	var t := clampf(age / 0.42, 0, 1)
	var eased := t * t
	var middle := from.lerp(destination, 0.5) + Vector2(0, -90)
	var head := from * (1-eased) * (1-eased) + middle * 2 * eased * (1-eased) + destination * eased * eased
	for i in 16:
		var direction := Vector2.from_angle(float(i) * 2.399963)
		var at := from.lerp(head, minf(1, t * 3)) + direction * sin(t * PI) * (18 + i * 2)
		draw_rect(Rect2(at, Vector2(3, 7) * (1-t)), Color(tint, (1-t)*0.8))
	draw_line(head, head.lerp(from, 0.12), Color(tint, 1-t), 3 * (1-t), true)
	draw_circle(head, 4 * (1-t), Color(1.5, 1.7, 2, 1-t))

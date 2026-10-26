class_name GridBackground
extends ColorRect

## 暗网格 + 爆炸涟漪扭曲。涟漪使用网格自身 UV 偏移，
## 不走全屏读屏，因此不会把 HUD 一起扭曲。

const RIPPLE_SLOTS := 4

var _elapsed := 0.0
var _material: ShaderMaterial
var _player: Node2D
var _ripples: Array[Vector4] = [
	Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO
]
var _ripple_index := 0


func _ready() -> void:
	add_to_group("grid_background")
	_material = material as ShaderMaterial
	if _material != null:
		_material = _material.duplicate() as ShaderMaterial
		material = _material
		_material.set_shader_parameter("rect_size", size)
		_material.set_shader_parameter("shader_time", 0.0)
		_push_ripples()


func _process(delta: float) -> void:
	_elapsed += delta
	if _material != null:
		_material.set_shader_parameter("shader_time", _elapsed)
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group(&"player") as Node2D
		if _player != null:
			var p := _player.global_position - global_position
			var edge_distance := minf(minf(p.x, p.y), minf(size.x - p.x, size.y - p.y))
			_material.set_shader_parameter("wall_visibility",
				1.0 - smoothstep(180.0, 500.0, edge_distance))


func configure_rect(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	if _material != null:
		_material.set_shader_parameter("rect_size", size)


func add_ripple(world_position: Vector2, strength: float = 1.0) -> void:
	if _material == null:
		return

	var local_position := world_position - global_position
	_ripples[_ripple_index] = Vector4(
		local_position.x,
		local_position.y,
		_elapsed,
		maxf(0.0, strength)
	)
	_ripple_index = (_ripple_index + 1) % RIPPLE_SLOTS
	_push_ripples()


func _push_ripples() -> void:
	if _material == null:
		return
	for i in RIPPLE_SLOTS:
		_material.set_shader_parameter("ripple%d" % i, _ripples[i])

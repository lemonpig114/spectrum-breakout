class_name NeonTexture
extends RefCounted

## 共享的小尺寸柔光纹理，只生成一次；颜色由绘制端调制。
static var _halo: GradientTexture2D


static func halo() -> GradientTexture2D:
	if _halo == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.45, 0.75, 1.0])
		gradient.colors = PackedColorArray([
			Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.38),
			Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.025), Color(1, 1, 1, 0),
		])
		_halo = GradientTexture2D.new()
		_halo.gradient = gradient
		_halo.width = 64
		_halo.height = 64
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
	return _halo

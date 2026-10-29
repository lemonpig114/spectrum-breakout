class_name EnergyBurst
extends Node2D

## 一次性能量爆点。由 FX 的对象池创建和回收，不需要场景文件。
##
## 不同事件使用不同的几何语言，避免所有爆炸都长成同一个圆环：
## - STAR    暴击/闪避：四芒星闪光，短、锐、没有整圆；
## - HEAVY   重型弹命中：环 + 辐条 + 白核，强调重量；
## - SPLASH  溅射：六边形碎环 + 向外飞散的三角碎片；
## - SOUL    灵魂脉冲：旋转的双层菱形印记 + 向内收束的光点；
## - PANIC   受伤反击：大双环 + 放射刻线，低频但压迫感强；
## - SHATTER 敌人死亡：独立壳片分离、翻转、消隐，不画圆环/圆弧。

const STYLE_STAR := 0
const STYLE_HEAVY := 1
const STYLE_SPLASH := 2
const STYLE_SOUL := 3
const STYLE_PANIC := 4
const STYLE_SHATTER := 5
const VEIL_CAP := 12
static var _active_veils := 0

var color := Color.WHITE
var max_radius := 30.0
var duration := 0.26
var style := STYLE_STAR

var _age := 0.0
var _veil: Sprite2D
var _veil_material: ShaderMaterial
var _serial := 0
var _veil_enabled := true
var _owns_veil_slot := false
var _fragment_phase := 0.0


func _ready() -> void:
	_veil_enabled = not OS.get_cmdline_user_args().has("--no-energy-veil")
	# 材质和节点只在预热时分配，复用时只重置参数。
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = preload("res://shaders/energy_veil.gdshader")
	_veil = Sprite2D.new()
	_veil.texture = preload("res://scripts/fx/NeonTexture.gd").halo()
	_veil.material = _veil_material
	_veil.show_behind_parent = true
	add_child(_veil)


func setup(
	world_position: Vector2,
	burst_color: Color,
	radius: float,
	life: float,
	burst_style: int
) -> void:
	position = world_position
	color = burst_color
	max_radius = radius
	duration = maxf(0.05, life)
	style = burst_style
	# 爆破更短促；灵魂降低亮度，保留紫色饱和度。
	if style == STYLE_SPLASH:
		duration = maxf(0.05, duration * 0.70)
	elif style == STYLE_SOUL:
		color = Color(color.r * 0.82, color.g * 0.82, color.b * 0.82, color.a)
	z_index = 30
	_age = 0.0
	_serial += 1
	_fragment_phase = world_position.x * 0.017 + world_position.y * 0.031
	# 暴击保留锐利星芒，其余爆点叠加柔软的局部能量层。
	release_veil()
	_owns_veil_slot = _veil_enabled and style != STYLE_STAR and style != STYLE_SHATTER and _active_veils < VEIL_CAP
	if _owns_veil_slot:
		_active_veils += 1
	_veil.visible = _owns_veil_slot
	_veil.scale = Vector2.ONE * max_radius * 2.6 / 64.0
	_veil_material.set_shader_parameter("tint", color)
	_veil_material.set_shader_parameter("effect_style", float(style))
	_veil_material.set_shader_parameter("phase", float(_serial) * 2.399)
	_veil_material.set_shader_parameter("progress", 0.0)
	visible = true
	set_process(true)
	queue_redraw()


## 连锁爆炸时只给前 12 个爆点叠能量雾，其余保留几何反馈。
func release_veil() -> void:
	if _owns_veil_slot:
		_active_veils = maxi(0, _active_veils - 1)
		_owns_veil_slot = false
	if _veil != null:
		_veil.visible = false


func _exit_tree() -> void:
	release_veil()


func _process(delta: float) -> void:
	_age += delta
	if _veil.visible:
		_veil_material.set_shader_parameter("progress", minf(_age / duration, 1.0))
	if _age >= duration:
		# 由 FX 回收到对象池，不再 self-free。
		set_process(false)
		if is_instance_valid(FX):
			FX.release_burst(self)
		else:
			queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / duration, 0.0, 1.0)
	var ease_t := 1.0 - pow(1.0 - t, 3.0)
	var alpha := 1.0 - t

	match style:
		STYLE_HEAVY:
			_draw_heavy(t, ease_t, alpha)
		STYLE_SPLASH:
			_draw_splash(t, ease_t, alpha)
		STYLE_SOUL:
			_draw_soul(t, ease_t, alpha)
		STYLE_PANIC:
			_draw_panic(t, ease_t, alpha)
		STYLE_SHATTER:
			_draw_shatter(t, ease_t, alpha)
		_:
			_draw_star(t, ease_t, alpha)


## 暴击/闪避：四芒星 + 斜向短芒 + 旋转菱形外框，没有完整圆环。
func _draw_star(t: float, ease_t: float, alpha: float) -> void:
	var reach := max_radius * lerpf(0.35, 1.0, ease_t)
	var tint := Color(color.r, color.g, color.b, alpha)

	for i in 4:
		var angle := TAU * float(i) / 4.0 + 0.22 + t * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var perpendicular := Vector2(-direction.y, direction.x)
		var tip := direction * reach
		var wide := reach * 0.15 * (1.0 - t * 0.55)
		draw_colored_polygon(
			PackedVector2Array([
				tip,
				direction * reach * 0.12 + perpendicular * wide,
				direction * reach * 0.12 - perpendicular * wide,
			]),
			Color(tint.r, tint.g, tint.b, alpha * 0.42)
		)

	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25 + t * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var perpendicular := Vector2(-direction.y, direction.x)
		var tip := direction * reach * 0.58
		var wide := reach * 0.07 * (1.0 - t * 0.5)
		draw_colored_polygon(
			PackedVector2Array([
				tip,
				perpendicular * wide,
				-perpendicular * wide,
			]),
			Color(tint.r, tint.g, tint.b, alpha * 0.28)
		)

	var outline := PackedVector2Array()
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25 + t * 0.75
		outline.append(Vector2(cos(angle), sin(angle)) * reach * 0.94)
	outline.append(outline[0])
	draw_polyline(outline, Color(tint.r, tint.g, tint.b, alpha * 0.78), 1.6, true)

	draw_circle(
		Vector2.ZERO,
		max_radius * 0.14 * (1.0 - ease_t),
		Color(1.0, 1.0, 1.0, alpha * 0.85)
	)


## 重型弹：完整圆环 + 放射刻线 + 白核，和暴击的星芒区分开。
func _draw_heavy(t: float, ease_t: float, alpha: float) -> void:
	var radius := max_radius * lerpf(0.18, 1.0, ease_t)
	var line_width := 2.8 * (1.0 - t * 0.55)
	var tint := Color(color.r, color.g, color.b, alpha)

	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(tint.r, tint.g, tint.b, alpha * 0.8), line_width, true)
	draw_arc(
		Vector2.ZERO,
		radius * 0.72,
		0.0,
		TAU,
		32,
		Color(tint.r, tint.g, tint.b, alpha * 0.32),
		line_width * 0.7,
		true
	)

	for i in 10:
		var angle := TAU * float(i) / 10.0 + 0.18
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			direction * radius * 0.86,
			direction * radius * 1.06,
			Color(tint.r, tint.g, tint.b, alpha * 0.5),
			1.4,
			true
		)

	draw_circle(
		Vector2.ZERO,
		max_radius * 0.2 * (1.0 - ease_t),
		Color(1.0, 1.0, 1.0, alpha * 0.65)
	)


## 溅射：六段碎环 + 外飞的三角碎片 + 很淡的六边形内影。
func _draw_splash(t: float, ease_t: float, alpha: float) -> void:
	var radius := max_radius * lerpf(0.08, 1.0, ease_t)
	var line_width := 2.1 * (1.0 - t * 0.5)
	var tint := Color(color.r, color.g, color.b, alpha)

	for i in 6:
		var start := TAU * float(i) / 6.0 + 0.2 + t * 0.45
		draw_arc(
			Vector2.ZERO,
			radius,
			start,
			start + TAU / 6.0 * 0.58,
			6,
			Color(tint.r, tint.g, tint.b, alpha * 0.82),
			line_width,
			true
		)

	for i in 6:
		var angle := TAU * float(i) / 6.0 + 0.85
		var direction := Vector2(cos(angle), sin(angle))
		var perpendicular := Vector2(-direction.y, direction.x)
		var center := direction * max_radius * lerpf(0.12, 1.14, ease_t)
		var size := max_radius * 0.075 * (1.0 - t)
		if size <= 0.2:
			continue
		draw_colored_polygon(
			PackedVector2Array([
				center + direction * size,
				center - direction * size * 0.3 + perpendicular * size * 0.7,
				center - direction * size * 0.3 - perpendicular * size * 0.7,
			]),
			Color(tint.r, tint.g, tint.b, alpha * 0.36)
		)


## 灵魂脉冲：双层旋转六芒星印记 + 由外向内收束的光点 + 上升的微光。
## 用六芒星而不是菱形，和暴击的四芒星彻底区分。
func _draw_soul(t: float, ease_t: float, alpha: float) -> void:
	var radius := max_radius * lerpf(0.3, 0.94, ease_t)
	var rotation := _age * 2.0
	var tint := Color(color.r, color.g, color.b, alpha)

	for layer in 2:
		var layer_radius := radius * (1.0 - 0.22 * float(layer))
		var offset := rotation + float(layer) * PI / 3.0
		var layer_alpha := alpha * (0.78 if layer == 0 else 0.3)
		for triangle in 2:
			var points := PackedVector2Array()
			for i in 3:
				var angle := offset + float(triangle) * PI / 3.0 + TAU * float(i) / 3.0
				points.append(Vector2(cos(angle), sin(angle)) * layer_radius)
			points.append(points[0])
			draw_polyline(
				points,
				Color(tint.r, tint.g, tint.b, layer_alpha),
				1.7 if layer == 0 else 1.0,
				true
			)

	# 六个小菱形从外圈向内收束，形成“吸魂”而不是向外炸开的感觉。
	for i in 6:
		var angle := TAU * float(i) / 6.0 + rotation * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var center := direction * radius * lerpf(0.95, 0.48, ease_t)
		var size := 2.4 * (1.0 - t) + 0.7
		var perpendicular := Vector2(-direction.y, direction.x)
		var diamond := PackedVector2Array([
			center + direction * size,
			center + perpendicular * size,
			center - direction * size,
			center - perpendicular * size,
			center + direction * size,
		])
		draw_polyline(diamond, Color(tint.r, tint.g, tint.b, alpha * 0.55), 1.0, true)

	# 几缕向上飘散的微光。
	for i in 4:
		var x := (float(i) - 1.5) * radius * 0.16
		var y := -radius * (0.12 + 0.55 * ease_t) - float(i % 2) * 5.0
		draw_circle(
			Vector2(x, y),
			1.7 * (1.0 - t) + 0.4,
			Color(tint.r, tint.g, tint.b, alpha * 0.45)
		)

	draw_circle(
		Vector2.ZERO,
		radius * 0.13 * (1.0 - t * 0.6),
		Color(tint.r, tint.g, tint.b, alpha * 0.22)
	)


## 受伤反击：大双环 + 放射刻线 + 白核。低频事件，保留最强压迫感。
func _draw_panic(t: float, ease_t: float, alpha: float) -> void:
	var radius := max_radius * lerpf(0.18, 1.0, ease_t)
	var line_width := 4.5 * (1.0 - t * 0.6)
	var tint := Color(color.r, color.g, color.b, alpha)

	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(tint.r, tint.g, tint.b, alpha * 0.85), line_width, true)
	draw_arc(
		Vector2.ZERO,
		radius * 0.62,
		0.0,
		TAU,
		32,
		Color(tint.r, tint.g, tint.b, alpha * 0.5),
		line_width * 0.7,
		true
	)
	for i in 12:
		var angle := TAU * float(i) / 12.0 + 0.12
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			direction * radius * 0.7,
			direction * radius * 0.95,
			Color(tint.r, tint.g, tint.b, alpha * 0.38),
			1.3,
			true
		)
	draw_circle(
		Vector2.ZERO,
		max_radius * 0.12 * (1.0 - ease_t),
		Color(1.0, 1.0, 1.0, alpha * 0.32)
	)


## 死亡：七块不规则壳片分离，不连接、不画圆弧，也不叠环形薄雾。
func _draw_shatter(t: float, ease_t: float, alpha: float) -> void:
	for i in 7:
		var seed_value := float(i) * 2.399 + _fragment_phase
		var direction := Vector2.from_angle(seed_value)
		var distance := max_radius * (0.16 + ease_t * (0.52 + 0.40 * absf(sin(seed_value * 1.7))))
		var center := direction * distance + Vector2(0, 10.0 * t * t)
		var size := max_radius * (0.10 + 0.06 * absf(cos(seed_value))) * (1.0 - t * 0.65)
		var angle := seed_value + t * (2.0 if i % 2 == 0 else -2.6)
		var axis := Vector2.from_angle(angle)
		var perpendicular := axis.orthogonal() * (0.5 + 0.35 * absf(cos(t * 5.0 + seed_value)))
		var points := PackedVector2Array([
			center + axis * size,
			center - axis * size * 0.35 + perpendicular * size,
			center - axis * size * 0.65 - perpendicular * size * 0.45,
		])
		draw_colored_polygon(points, Color(color.r, color.g, color.b, alpha * alpha * 0.38))
		# 只高亮壳片两条断边，避免形成连续环形轮廓。
		draw_polyline(points, Color(color.r, color.g, color.b, alpha * 0.88), 1.2, true)

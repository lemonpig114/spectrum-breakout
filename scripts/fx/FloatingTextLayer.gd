class_name FloatingTextLayer
extends Node2D

## 统一绘制所有浮动文字（伤害数字、闪避、处决……）。
##
## 之前在每次命中时创建 Label + Tween，会产生大量节点、主题覆盖和 Tween 分配，
## 高射速下容易造成帧时间尖峰。这里改用固定容量的槽位数组 + 单节点 _draw：
## 只在启动时分配，之后每帧复用，内存占用固定、无每跳垃圾。
##
## 伤害数字按样式分层：
## - 普通：小号、短促上浮；
## - 弱点：字号更大、粗描边，并用双重绘制模拟加粗；
## - 暴击：字号更大，出现时有一个快速放大的 pop；
## - 超级暴击：35 px 加粗，整串共用一条连续琉璃渐变（专用 Label 池 +
##   渐变 Shader），不再是逐字符纯色拼接；
## - 溅射：更小更淡，避免一次命中刷满屏幕。

const MAX_TEXTS := 48
const MAX_IMPACTS := 32
const IMPACT_LIFETIME := 0.13
const IMPACTS_PER_FRAME := 4

const STYLE_NORMAL := 0
const STYLE_WEAKNESS := 1
const STYLE_CRIT := 2
const STYLE_SUPER_CRIT := 3
const STYLE_SPLASH := 4
const STYLE_ELEMENTAL := 5
const STYLE_SOUL := 6
const STYLE_BURN := 7
const STYLE_POISON := 8
const STYLE_ICE := 9
const STYLE_BURST := 10
const STYLE_EXECUTION := 11

# 超级暴击用独立的固定容量 Label 池。数量很少（正常只有暴击 4 阶后的 1%，
# 调试时强制全超暴击），池满后覆盖最旧的数字，不会随命中增长。
const SUPER_CRIT_POOL := 6
const SUPER_CRIT_FONT_SIZE := 40
const SUPER_CRIT_LIFETIME := 0.95
const SUPER_CRIT_RISE := 30.0
const SUPER_CRIT_OUTLINE := 6
const SUPER_CRIT_SHADER := preload("res://shaders/super_crit_gradient.gdshader")

var _cursor := 0
var _visual_dirty := false

var _positions: Array[Vector2] = []
var _texts: Array[String] = []
var _captions: Array[String] = []
var _colors: Array[Color] = []
var _sizes: Array[int] = []
var _styles: Array[int] = []
var _lifetimes: Array[float] = []
var _ages: Array[float] = []
var _drift_x: Array[float] = []
var _alive: Array[bool] = []
var _impact_positions: Array[Vector2] = []
var _impact_colors: Array[Color] = []
var _impact_angles: Array[float] = []
var _impact_ages: Array[float] = []
var _impact_alive: Array[bool] = []
var _impact_cursor := 0
var _impact_frame := -1
var _impacts_this_frame := 0
var _impact_shape := PackedVector2Array([
	Vector2(-9, 0), Vector2(-2, -3), Vector2(11, 0), Vector2(-2, 3),
])

# 超级暴击 Label 池：每个槽位只有一个 Label，黑描边走 Label 自带 outline，
# 渐变/白色镜面边/冷暖和色散全部由 Shader 在同一个 Label 内完成。
var _sc_roots: Array[Node2D] = []
var _sc_labels: Array[Label] = []
var _sc_captions: Array[Label] = []
var _sc_materials: Array[ShaderMaterial] = []
var _sc_caption_materials: Array[ShaderMaterial] = []
var _sc_bold_base: Font
var _sc_bold_font: FontVariation
var _emphasis_base: Font
var _emphasis_font: FontVariation
var _sc_positions: Array[Vector2] = []
var _sc_ages: Array[float] = []
var _sc_drift_x: Array[float] = []
var _sc_alive: Array[bool] = []
var _sc_cursor := 0


func _ready() -> void:
	z_index = 40
	_positions.resize(MAX_TEXTS)
	_texts.resize(MAX_TEXTS)
	_captions.resize(MAX_TEXTS)
	_colors.resize(MAX_TEXTS)
	_sizes.resize(MAX_TEXTS)
	_styles.resize(MAX_TEXTS)
	_lifetimes.resize(MAX_TEXTS)
	_ages.resize(MAX_TEXTS)
	_drift_x.resize(MAX_TEXTS)
	_alive.resize(MAX_TEXTS)
	_alive.fill(false)
	_impact_positions.resize(MAX_IMPACTS)
	_impact_colors.resize(MAX_IMPACTS)
	_impact_angles.resize(MAX_IMPACTS)
	_impact_ages.resize(MAX_IMPACTS)
	_impact_alive.resize(MAX_IMPACTS)
	_impact_alive.fill(false)
	_build_super_crit_pool()


## font_size <= 0 时使用该样式的默认字号。
func add_text(
	world_position: Vector2,
	text: String,
	color: Color,
	font_size: int,
	style: int = STYLE_NORMAL,
	caption: String = ""
) -> void:
	if style == STYLE_SUPER_CRIT:
		_spawn_super_crit(world_position, text, caption)
		return

	var index := _cursor
	_cursor = (_cursor + 1) % MAX_TEXTS
	var elemental := style == STYLE_BURN or style == STYLE_POISON or style == STYLE_ICE
	var side := (-1.0 if index % 2 == 0 else 1.0) if elemental else (-1.0 if randf() < 0.5 else 1.0)
	_drift_x[index] = side * randf_range(32.0, 48.0) if elemental else side * randf_range(14.0, 28.0)
	_positions[index] = world_position + Vector2(side * randf_range(3.0, 7.0), -12.0 + randf_range(-2.0, 2.0))
	_texts[index] = text
	_captions[index] = caption
	_colors[index] = color
	_sizes[index] = font_size if font_size > 0 else _size_for(style)
	_styles[index] = style
	_lifetimes[index] = _lifetime_for(style)
	_ages[index] = 0.0
	_alive[index] = true
	_visual_dirty = true


func add_impact(world_position: Vector2, tint: Color, direction: Vector2) -> void:
	var frame := Engine.get_process_frames()
	if frame != _impact_frame:
		_impact_frame = frame
		_impacts_this_frame = 0
	if _impacts_this_frame >= IMPACTS_PER_FRAME:
		return
	_impacts_this_frame += 1
	var index := _impact_cursor
	_impact_cursor = (_impact_cursor + 1) % MAX_IMPACTS
	_impact_positions[index] = world_position
	_impact_colors[index] = tint
	_impact_angles[index] = direction.angle() if direction.length_squared() > 0.001 else randf() * TAU
	_impact_ages[index] = 0.0
	_impact_alive[index] = true
	_visual_dirty = true


func clear() -> void:
	for i in MAX_TEXTS:
		_alive[i] = false
	for i in MAX_IMPACTS:
		_impact_alive[i] = false
	for i in SUPER_CRIT_POOL:
		_sc_alive[i] = false
		_sc_roots[i].visible = false
	_visual_dirty = true


func _process(delta: float) -> void:
	var any_alive := false
	for i in MAX_TEXTS:
		if not _alive[i]:
			continue
		var age := _ages[i] + delta
		if age >= _lifetimes[i]:
			_alive[i] = false
			_visual_dirty = true
			continue
		_ages[i] = age
		_positions[i].x += _drift_x[i] * delta
		_positions[i].y -= _rise_speed(_styles[i]) * delta
		any_alive = true
	for i in MAX_IMPACTS:
		if not _impact_alive[i]:
			continue
		_impact_ages[i] += delta
		if _impact_ages[i] >= IMPACT_LIFETIME:
			_impact_alive[i] = false
		else:
			any_alive = true

	_update_super_crit(delta)

	if any_alive or _visual_dirty:
		_visual_dirty = false
		queue_redraw()


func _draw() -> void:
	var clock := preload("res://scripts/game/CombatProfiler.gd").begin()
	_draw_texts()
	preload("res://scripts/game/CombatProfiler.gd").end(&"text_draw", clock)


func _draw_texts() -> void:
	# Main 可能在 FX.prewarm 之后才设置中文字体，因此每帧读取一次。
	var base_font := ThemeDB.fallback_font
	if base_font == null:
		return
	for i in MAX_IMPACTS:
		if not _impact_alive[i]:
			continue
		var t := _impact_ages[i] / IMPACT_LIFETIME
		var scale_value := 1.4 - 0.85 * t
		var tint := _impact_colors[i]
		var alpha := (1.0 - t) * (1.0 - t)
		draw_set_transform(_impact_positions[i], _impact_angles[i], Vector2.ONE * scale_value)
		draw_colored_polygon(_impact_shape, Color(tint.r, tint.g, tint.b, 0.70 * alpha))
		draw_line(Vector2(-13, -5), Vector2(-5, -1), Color(tint.r, tint.g, tint.b, 0.48 * alpha), 1.2, true)
		draw_line(Vector2(-13, 5), Vector2(-5, 1), Color(tint.r, tint.g, tint.b, 0.48 * alpha), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i in MAX_TEXTS:
		if not _alive[i]:
			continue

		var style := _styles[i]
		var font := _emphasis_font_for(base_font) if style in [STYLE_WEAKNESS, STYLE_CRIT, STYLE_SOUL, STYLE_BURST] else base_font
		var lifetime := _lifetimes[i]
		var age := _ages[i]
		var t := clampf(age / lifetime, 0.0, 1.0)
		var alpha := 1.0 - t * t
		if style == STYLE_SPLASH:
			alpha *= 0.72

		var base := _colors[i]
		var draw_color := Color(base.r, base.g, base.b, base.a * alpha)
		var outline_color := Color(0.0, 0.0, 0.0, 0.85 * alpha)
		if style == STYLE_EXECUTION:
			outline_color = Color(1.5, 0.025, 0.06, alpha)

		# 用缩放后的局部坐标绘制，避免每帧修改字号导致字体缓存抖动。
		var draw_position := _positions[i] + Vector2(0.0, float(_sizes[i]))
		var pop := _pop_scale(style, age)
		draw_set_transform(draw_position, 0.0, Vector2(pop, pop))
		draw_string_outline(
			font, Vector2.ZERO, _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_sizes[i], _outline_width(style), outline_color
		)
		draw_string(
			font, Vector2.ZERO, _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_sizes[i], draw_color
		)
		if style == STYLE_WEAKNESS or style == STYLE_SOUL:
			# 中文字体没有现成的粗体变体，用轻微错位重绘模拟加粗。
			draw_string(
				font, Vector2(1.0, 0.0), _texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				_sizes[i], draw_color
			)
		_draw_caption(font, style, _texts[i], _captions[i], _sizes[i], draw_color, alpha)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 超暴击数字和标题由同一组池化 Label 绘制彩色渐变。


func _draw_caption(font: Font, style: int, number: String, custom_caption: String, number_size: int, tint: Color, alpha: float) -> void:
	var caption := custom_caption
	if caption.is_empty() and style == STYLE_WEAKNESS:
		caption = "弱点"
	elif caption.is_empty() and style == STYLE_SOUL:
		caption = "灵魂"
	elif caption.is_empty() and style == STYLE_BURN:
		caption = "灼烧"
	elif caption.is_empty() and style == STYLE_POISON:
		caption = "中毒"
	elif caption.is_empty() and style == STYLE_ICE:
		caption = "冰裂"
	elif caption.is_empty() and style == STYLE_CRIT:
		caption = "暴击"
	if caption.is_empty():
		return
	var caption_size := 10 if caption.length() > 4 or style == STYLE_BURN or style == STYLE_POISON or style == STYLE_ICE else 11
	var number_width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, number_size).x
	var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, caption_size).x
	var at := Vector2((number_width - caption_width) * 0.5, -float(number_size) - 4.0)
	draw_string_outline(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		caption_size, 2, Color(0, 0, 0, 0.8 * alpha))
	draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		caption_size, Color(tint.r, tint.g, tint.b, alpha * 0.92))


## 构建超级暴击 Label 池：每个槽位只有一个 Label。
## 黑描边用 Label 自带 outline，其余效果都由同一个 Shader 完成，
## 避免多层半透明 Label 叠加把主体洗白或出现层级错乱。
func _build_super_crit_pool() -> void:
	for i in SUPER_CRIT_POOL:
		var root := Node2D.new()
		root.visible = false
		add_child(root)

		var label := _make_super_crit_label()
		var material := ShaderMaterial.new()
		material.shader = SUPER_CRIT_SHADER
		material.set_shader_parameter("rim_strength", 0.8)
		label.material = material
		root.add_child(label)
		var caption := _make_super_crit_caption()
		var caption_material := ShaderMaterial.new()
		caption_material.shader = SUPER_CRIT_SHADER
		caption_material.set_shader_parameter("rim_strength", 0.45)
		caption_material.set_shader_parameter("fringe_strength", 0.25)
		caption.material = caption_material
		root.add_child(caption)

		_sc_roots.append(root)
		_sc_labels.append(label)
		_sc_captions.append(caption)
		_sc_materials.append(material)
		_sc_caption_materials.append(caption_material)
		_sc_positions.append(Vector2.ZERO)
		_sc_ages.append(0.0)
		_sc_drift_x.append(0.0)
		_sc_alive.append(false)


## 可变字体（Noto Sans SC）的粗体变体。缓存一份，避免每次命中创建 FontVariation。
func _super_crit_font() -> Font:
	var base := ThemeDB.fallback_font
	if base == null:
		return null
	if _sc_bold_font == null or _sc_bold_base != base:
		_sc_bold_base = base
		_sc_bold_font = FontVariation.new()
		_sc_bold_font.base_font = base
		_sc_bold_font.variation_opentype = {0x77676874: 800}
	return _sc_bold_font


func _emphasis_font_for(base: Font) -> Font:
	if _emphasis_font == null or _emphasis_base != base:
		_emphasis_base = base
		_emphasis_font = FontVariation.new()
		_emphasis_font.base_font = base
		_emphasis_font.variation_opentype = {0x77676874: 720}
	return _emphasis_font


func _make_super_crit_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", SUPER_CRIT_FONT_SIZE)
	# 字体色为白，Shader 以“非黑”判定色身；描边色为黑，Shader 原样保留。
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", SUPER_CRIT_OUTLINE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_super_crit_caption() -> Label:
	var label := Label.new()
	label.text = "超暴击"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _spawn_super_crit(world_position: Vector2, text: String, custom_caption: String = "") -> void:
	var index := _sc_cursor
	_sc_cursor = (_sc_cursor + 1) % SUPER_CRIT_POOL

	var label := _sc_labels[index]
	var caption := _sc_captions[index]
	var font := _super_crit_font()
	if font != null:
		label.add_theme_font_override("font", font)
		caption.add_theme_font_override("font", font)
	label.text = text
	caption.text = custom_caption if not custom_caption.is_empty() else "超暴击"
	label.size = label.get_minimum_size()
	caption.size = caption.get_minimum_size()
	caption.position = Vector2((label.size.x - caption.size.x) * 0.5, -caption.size.y + 2.0)

	# 渐变按去掉描边留白后的实际字形宽度归一化，整串色带速度才一致。
	var glyph_width: float = label.size.x - float(SUPER_CRIT_OUTLINE) * 2.0
	var material := _sc_materials[index]
	material.set_shader_parameter(
		"text_size",
		Vector2(maxf(glyph_width, 1.0), float(SUPER_CRIT_FONT_SIZE) * 1.45)
	)
	var phase := randf() * 6.0
	material.set_shader_parameter("phase", phase)
	var caption_material := _sc_caption_materials[index]
	caption_material.set_shader_parameter("text_size", Vector2(maxf(caption.size.x - 4.0, 1.0), caption.size.y))
	caption_material.set_shader_parameter("phase", phase)

	_sc_positions[index] = world_position + Vector2(randf_range(-8.0, 8.0), -12.0)
	_sc_drift_x[index] = randf_range(12.0, 24.0) * (-1.0 if randf() < 0.5 else 1.0)
	_sc_ages[index] = 0.0
	_sc_alive[index] = true

	var root := _sc_roots[index]
	root.position = _sc_positions[index]
	root.scale = Vector2.ONE
	root.modulate = Color(1, 1, 1, 1)
	root.visible = true


func _update_super_crit(delta: float) -> void:
	for i in SUPER_CRIT_POOL:
		if not _sc_alive[i]:
			continue

		var age := _sc_ages[i] + delta
		var root := _sc_roots[i]
		if age >= SUPER_CRIT_LIFETIME:
			_sc_alive[i] = false
			root.visible = false
			continue

		_sc_ages[i] = age
		_sc_positions[i].x += _sc_drift_x[i] * delta
		_sc_positions[i].y -= SUPER_CRIT_RISE * delta

		var t := clampf(age / SUPER_CRIT_LIFETIME, 0.0, 1.0)
		var pop := 1.0 + 0.34 * pow(1.0 - minf(age / 0.18, 1.0), 2.0)
		root.position = _sc_positions[i]
		root.scale = Vector2(pop, pop)
		root.modulate = Color(1, 1, 1, 1.0 - t * t)


func _size_for(style: int) -> int:
	match style:
		STYLE_WEAKNESS, STYLE_SOUL:
			return 24
		STYLE_CRIT, STYLE_BURST:
			return 29
		STYLE_SUPER_CRIT:
			return SUPER_CRIT_FONT_SIZE
		STYLE_SPLASH:
			return 11
		STYLE_ELEMENTAL:
			return 12
		STYLE_BURN, STYLE_POISON, STYLE_ICE:
			return 17
		_:
			return 15


func _lifetime_for(style: int) -> float:
	match style:
		STYLE_WEAKNESS, STYLE_SOUL:
			return 0.6
		STYLE_CRIT, STYLE_BURST:
			return 0.7
		STYLE_SUPER_CRIT:
			return 0.95
		STYLE_SPLASH:
			return 0.42
		STYLE_ELEMENTAL:
			return 0.5
		STYLE_BURN, STYLE_POISON, STYLE_ICE:
			return 0.58
		_:
			return 0.55


func _rise_speed(style: int) -> float:
	match style:
		STYLE_WEAKNESS, STYLE_SOUL:
			return 58.0
		STYLE_CRIT, STYLE_BURST:
			return 42.0
		STYLE_SUPER_CRIT:
			return 30.0
		STYLE_SPLASH:
			return 46.0
		STYLE_ELEMENTAL:
			return 52.0
		STYLE_BURN, STYLE_POISON, STYLE_ICE:
			return 46.0
		_:
			return 62.0


func _outline_width(style: int) -> int:
	match style:
		STYLE_WEAKNESS, STYLE_SOUL:
			return 4
		STYLE_CRIT, STYLE_BURST:
			return 3
		STYLE_SUPER_CRIT:
			return 5
		STYLE_SPLASH:
			return 1
		STYLE_ELEMENTAL:
			return 2
		STYLE_BURN, STYLE_POISON, STYLE_ICE:
			return 2
		_:
			return 2


## 暴击在最初 0.16 秒内从大字号弹回正常尺寸，弱点只有很轻的强调。
func _pop_scale(style: int, age: float) -> float:
	match style:
		STYLE_WEAKNESS, STYLE_SOUL:
			return 1.0 + 0.12 * pow(1.0 - minf(age / 0.12, 1.0), 2.0)
		STYLE_CRIT, STYLE_BURST:
			return 1.0 + 0.26 * pow(1.0 - minf(age / 0.16, 1.0), 2.0)
		STYLE_SUPER_CRIT:
			return 1.0 + 0.34 * pow(1.0 - minf(age / 0.18, 1.0), 2.0)
		STYLE_BURN, STYLE_POISON, STYLE_ICE:
			return 1.0 + 0.10 * pow(1.0 - minf(age / 0.12, 1.0), 2.0)
		_:
			return 1.0

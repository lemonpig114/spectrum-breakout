class_name ColorRulesResource
extends Resource

## 颜色克制数据。数值与颜色都放在 Resource 里，方便后续调参和做遗物改规则。

@export var id: StringName = &"default_color_rules"
@export var advantage_multiplier: float = 1.5
@export var same_multiplier: float = 0.7
@export var reverse_multiplier: float = 1.0
@export var hdr_boost: float = 2.4

@export var red: Color = Color(1.0, 0.12, 0.22, 1.0)
@export var green: Color = Color(0.12, 1.0, 0.38, 1.0)
@export var blue: Color = Color(0.2, 0.45, 1.0, 1.0)


func color_for(color_index: int) -> Color:
	match color_index:
		ColorType.RED:
			return red
		ColorType.GREEN:
			return green
		ColorType.BLUE:
			return blue
	return Color.WHITE


func hdr_color_for(color_index: int) -> Color:
	var c := color_for(color_index)
	# 蓝色与选角预览保持同一亮度比例，避免通用 HDR 倍率把蓝色推白。
	var boost := 1.7 if color_index == ColorType.BLUE else hdr_boost
	return Color(c.r * boost, c.g * boost, c.b * boost, 1.0)


func dim_color_for(color_index: int, factor: float = 0.14) -> Color:
	var c := color_for(color_index)
	return Color(c.r * factor, c.g * factor, c.b * factor, 1.0)


func multiplier(attacker: int, defender: int) -> float:
	if ColorType.is_same(attacker, defender):
		return same_multiplier
	if ColorType.beats(attacker, defender):
		return advantage_multiplier
	return reverse_multiplier


func relation(attacker: int, defender: int) -> StringName:
	if ColorType.is_same(attacker, defender):
		return &"same"
	if ColorType.beats(attacker, defender):
		return &"advantage"
	return &"neutral"

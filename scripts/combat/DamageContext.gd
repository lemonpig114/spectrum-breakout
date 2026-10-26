class_name DamageContext
extends RefCounted

## 一次伤害的完整上下文。所有系统只读/追加这个对象，不直接改敌人内部状态。

var source: Node = null
var target: Node = null
var amount: float = 0.0
## 已计入 amount 的元素附加伤害；绘制数字时与主伤害分开显示。
var elemental_bonus: float = 0.0
var color_index: int = ColorType.RED
var relation: StringName = &"neutral"
var color_multiplier: float = 1.0
var hit_position: Vector2 = Vector2.ZERO
var tags: Array[StringName] = []
var is_crit: bool = false
var is_killing_blow: bool = false


func add_tag(tag: StringName) -> void:
	if not tags.has(tag):
		tags.append(tag)


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)

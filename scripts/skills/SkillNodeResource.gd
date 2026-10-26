class_name SkillNodeResource
extends Resource

## 局内技能树节点。
## 解锁规则由 prerequisites 描述：1 阶无前置；2/3 阶需要 1 阶；4 阶需要 2 阶和 3 阶。
## 普通数值通过 modifiers 进入对应 StatBlock；结算规则类能力由 Skills 根据 id/flags 处理。

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"core"
@export var branch_name: String = ""
@export var tier: int = 1
@export var prerequisites: Array[StringName] = []
@export var modifiers: Array[StatModifierResource] = []
@export var flags: Array[StringName] = []
@export var weight: float = 1.0
@export var accent: Color = Color.WHITE


func has_flag(flag: StringName) -> bool:
	return flags.has(flag)

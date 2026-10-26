class_name UpgradeOptionResource
extends Resource

## 升级选项。升级面板只负责展示，实际数值通过 modifier 落到 StatBlock。

enum Target {
	WEAPON,
	PLAYER,
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var target: Target = Target.WEAPON
@export var modifier: StatModifierResource
@export var weight: float = 1.0
@export var max_stacks: int = 8


func create_modifier() -> StatModifierResource:
	if modifier == null:
		return null
	var copy := modifier.duplicate() as StatModifierResource
	if copy == null:
		return null
	copy.source = id
	return copy

class_name StatModifierResource
extends Resource

## 数据驱动的属性修改器。skills / relics / fusion 最终都落到这里。

enum Op {
	FLAT,
	ADD_PERCENT,
	MULTIPLY,
}

enum Target {
	WEAPON,
	PLAYER,
}

@export var stat: StringName = &"damage"
@export var op: Op = Op.FLAT
@export var value: float = 0.0
@export var priority: int = 0
@export var source: StringName = &""
## 修改器落在哪个 StatBlock：武器或玩家。
@export var target: Target = Target.WEAPON

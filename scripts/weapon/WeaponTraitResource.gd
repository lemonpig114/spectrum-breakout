class_name WeaponTraitResource
extends Resource

## 武器行为特质。M0 只定义数据结构，融合系统在 M3 接入。

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var tags: Array[StringName] = []
@export var priority: int = 0
@export var damage_scale: float = 1.0
@export var fire_rate_scale: float = 1.0
@export var brief: String = ""

class_name FusionRuleResource
extends Resource

## 签名融合规则：tag 集合满足条件时，覆盖通用合成结果。

@export var id: StringName = &""
@export var display_name: String = ""
@export var required_tags: Array[StringName] = []
@export var result_traits: Array[StringName] = []
@export var parameter_overrides: Dictionary = {}
@export var priority: int = 0

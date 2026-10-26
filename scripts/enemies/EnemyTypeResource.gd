class_name EnemyTypeResource
extends Resource

## 形状决定职责；颜色由刷怪器独立选择，三种颜色都能出现在每一类敌人身上。

@export var id: StringName = &""
@export var display_name: String = ""
@export var sides: int = 3
@export var shape: StringName = &"polygon"
@export var max_health: float = 24.0
@export var move_speed: float = 120.0
@export var contact_damage: float = 8.0
@export var radius: float = 12.0
@export var xp_reward: float = 1.0
@export var gold_reward: int = 1
@export var spawn_weight: float = 1.0
@export var unlock_time: float = 0.0
@export var behavior: StringName = &"chase"
@export var preferred_distance: float = 0.0
@export var shot_interval: float = 2.4
@export var projectile_speed: float = 300.0
@export var explosion_radius: float = 0.0
## Boss 的处决阈值与普通敌人不同（5% / 15%）。
@export var is_boss: bool = false

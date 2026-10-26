class_name WeaponCoreResource
extends Resource

## 武器的“核心形态”。融合时通常保留当前 Core，叠加新武器的 Trait。

@export var id: StringName = &""
@export var display_name: String = ""
@export var damage: float = 10.0
@export var fire_rate: float = 3.0
@export var projectile_speed: float = 720.0
@export var projectile_size: float = 5.0
@export var projectile_lifetime: float = 1.1
@export var projectiles_per_shot: int = 1
@export var spread_degrees: float = 0.0
@export var pierce: int = 0
@export var projectile_sides: int = 4
@export var tags: Array[StringName] = []

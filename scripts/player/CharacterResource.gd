class_name CharacterResource
extends Resource

## 可操作机体。只影响开局形态与基础数值，颜色仍由 RunState 的红/绿/蓝循环决定。
## 外形由 CharacterVisual 绘制，body_style / barrel_style 与那边的常量一一对应。
##
## 攻击统一：所有机体共用同一份基础攻击（BASE_WEAPON_ID），角色差异只由下面的
## 三个基础倍率提供。倍率以 MULTIPLY 修改器写入武器 StatBlock，位于基础层，
## 因此技能/遗物的百分比收益对每个角色完全一致。

## 所有机体共用的基础攻击核心。
const BASE_WEAPON_ID := &"basic_bolt"

## 对应 CharacterVisual.BODY_CIRCLE / HEXAGON / TRIANGLE。
@export_enum("圆形", "六边形", "三角") var body_style: int = 0
## 对应 CharacterVisual.BARREL_CHEVRON / TWIN / ARROW。
@export_enum("人字炮", "双轨炮", "箭形炮") var barrel_style: int = 0

@export var id: StringName = &""
@export var display_name: String = ""
## 一句话定位，显示在角色卡标题下方。
@export var role: String = ""
@export_multiline var description: String = ""
## 角色选择界面的排序，从 0 开始。
@export var order: int = 0

## 仅用于菜单/卡片的高亮色，不参与战斗颜色判定。
@export var accent: Color = Color(0.24, 0.48, 1.0, 1.0)

@export var body_radius: float = 12.0
## 生命单位是“颗心”，HUD 按整颗/半颗绘制。
@export var max_health: float = 5.0
@export var move_speed: float = 250.0
@export var xp_gain_bonus: float = 0.0

## 角色基础倍率：只缩放共用的基础攻击，不改变核心数值本身。
@export var damage_multiplier: float = 1.0
@export var fire_rate_multiplier: float = 1.0
@export var projectile_size_multiplier: float = 1.0

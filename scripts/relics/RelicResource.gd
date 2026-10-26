class_name RelicResource
extends Resource

## 独立遗物。正负数值杠杆 + 特殊规则标签，商店在后续里程碑接入。

const RARITY_DUST := 0
const RARITY_RARE := 1
const RARITY_EPIC := 2
const RARITY_LEGENDARY := 3
const RARITY_IRIDESCENT := 4
const RARITY_CURSED := 5

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## 战斗中拾取条专用，无数值的一句话；完整数值仍在商店/暂停详情显示。
@export var brief_description: String = ""
@export var price: int = 10
@export var rarity: int = RARITY_DUST
## &"demon" / &"angel"；普通遗物留空。
@export var side: StringName = &""
@export var modifiers: Array[StatModifierResource] = []
@export var rule_tags: Array[StringName] = []

## 唯一遗物：整局最多获得一次。默认 false，即默认可重复拾取并叠加。
@export var unique: bool = false
## 一次性商店物品（例如苹果）：拾取后不进入遗物列表。
@export var consumable: bool = false
## 拾取时立即回复最大生命的比例（0.3 = 30%）。
@export var pickup_heal_ratio: float = 0.0
## 拾取时立即回复的固定心数（1.0 = 一颗心）。
@export var pickup_heal_hearts: float = 0.0
## 拾取时立即损失当前生命的比例（0.2 = 20%）。
@export var pickup_health_loss_ratio: float = 0.0
## 拾取时损失固定心数，最低保留半颗心。
@export var pickup_health_loss_hearts: float = 0.0
## 拾取时立即获得的金币（金块）。
@export var pickup_gold: int = 0
## 只可能从宝箱中出现，不进入商店货架。
@export var chest_only: bool = false
## 幸运遗物：只有解锁幸运 1 阶后才会进入商店 / 宝箱池。
@export var lucky: bool = false
## 0 = 可无限叠加；大于 0 时整局最多拥有这么多份（子弹壳 = 3）。
@export var max_stacks: int = 0
## 同品质抽取时的相对权重；箭矢为 0.5，避免占据过多货架。
@export var offer_weight: float = 1.0


## 商店/描述里的限定标签：唯一遗物显示“唯一”，可重复遗物为空。
func repeat_label() -> String:
	return "唯一" if unique else ""

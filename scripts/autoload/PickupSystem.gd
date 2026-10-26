extends Node

## 经验/金币掉落的全局入口。与 FX 相同的模式：
## 全局 API 在这里，实际的对象池、运动与绘制在 Main 场景的 PickupField 里。
## 没有掉落层时（例如只跑单元测试），直接结算，保持旧行为。

var field: PickupField


func attach(field_node: PickupField) -> void:
	field = field_node


func detach(field_node: PickupField) -> void:
	if field == field_node:
		field = null


func spawn_gold(world_position: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	if field != null and is_instance_valid(field):
		field.spawn_gold(world_position, amount)
		return
	RunState.add_gold(amount)


func spawn_xp(world_position: Vector2, amount: float) -> void:
	if amount <= 0:
		return
	if field != null and is_instance_valid(field):
		field.spawn_xp(world_position, amount)
		return
	RunState.add_xp(amount)


## 幸运线宝箱；没有掉落层时直接打开，保证测试场景也能拿到奖励。
func spawn_chest(world_position: Vector2) -> void:
	Skills.on_chest_discovered()
	if field != null and is_instance_valid(field):
		field.spawn_chest(world_position)
		return
	Skills.open_chest(world_position)


func clear() -> void:
	if field != null and is_instance_valid(field):
		field.clear()


## F3 调试面板用：场上掉落物总数（地面 + 飞行中）。
func total_count() -> int:
	if field != null and is_instance_valid(field):
		return field.total_count()
	return 0


func collecting_count() -> int:
	if field != null and is_instance_valid(field):
		return field.collecting_count()
	return 0


## 商人吸附：没有掉落层时无事可做（奖励本来就已经结算）。
func vacuum_all() -> int:
	if field != null and is_instance_valid(field):
		return field.vacuum_all()
	return 0


## 剩余经验/金币数量，宝箱不计；没有掉落层时视为已吸完。
func currency_count() -> int:
	if field != null and is_instance_valid(field):
		return field.currency_count()
	return 0

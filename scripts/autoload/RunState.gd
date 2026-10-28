extends Node

## 单局状态：颜色、能量、金币、经验、计时。
## 不持有场景节点；需要场景对象的地方通过 group 或信号解决。

const ENERGY_MAX := 3.0
const ENERGY_REGEN := 0.4
const EARLY_XP_REQUIREMENTS := [6, 12, 20, 30]
const COLOR_RULES_PATH := "res://data/colors/default_color_rules.tres"

var color_rules: ColorRulesResource
var rng := RandomNumberGenerator.new()
var arena_rect := Rect2(-1200.0, -900.0, 2400.0, 1800.0)

var color_index: int = ColorType.RED
## 角色选择界面写入，Main 生成 Player 时读取；不随 begin_run 重置。
var selected_character_id: StringName = &"prism"
var energy: float = ENERGY_MAX
var max_energy: float = ENERGY_MAX
var gold: int = 0
var xp: int = 0
var level: int = 1
var elapsed: float = 0.0
var is_running := false
var is_dead := false

var _last_energy_pip := -1
var _last_time_sent := -1.0
var _pause_reasons: Dictionary = {}
var _xp_fraction := 0.0
var _gold_fraction := 0.0
## 债券等“收益”遗物的金币累积器，避免每帧 add_gold(0)。
var _income_accum := 0.0
var _dot_clock := 0.0
var _dot_bucket := 0


func _ready() -> void:
	rng.randomize()
	color_rules = load(COLOR_RULES_PATH) as ColorRulesResource
	if color_rules == null:
		push_error("RunState: failed to load color rules, using defaults")
		color_rules = ColorRulesResource.new()


func begin_run() -> void:
	_pause_reasons.clear()
	get_tree().paused = false
	rng.randomize()

	# 技能树必须先重置，能量上限等派生值才能按本局初始状态计算。
	Skills.begin_run()

	max_energy = ENERGY_MAX + Skills.energy_max_bonus()
	color_index = rng.randi_range(0, ColorType.COUNT - 1)
	energy = max_energy
	gold = 0
	xp = 0
	level = 1
	elapsed = 0.0
	is_running = false
	is_dead = false
	_last_energy_pip = -1
	_last_time_sent = -1.0
	_xp_fraction = 0.0
	_gold_fraction = 0.0
	_income_accum = 0.0
	_dot_clock = 0.0
	_dot_bucket = 0

	_emit_energy(true)
	EventBus.color_changed.emit(color_index)
	EventBus.gold_changed.emit(gold)
	EventBus.xp_changed.emit(xp, level)
	EventBus.run_time_changed.emit(0.0)


func start() -> void:
	is_running = true
	EventBus.run_started.emit()


func end_run() -> void:
	is_running = false
	is_dead = true
	EventBus.run_ended.emit()


## 返回主界面：结束本局、清空暂停原因，但不进入死亡结算。
func abandon_run() -> void:
	is_running = false
	is_dead = false
	_pause_reasons.clear()
	if get_tree().paused:
		get_tree().paused = false
		EventBus.game_paused.emit(false)
	EventBus.run_ended.emit()


## 暂停按“原因”计数：升级、商店等可以同时存在，最后一个释放时才真正恢复。
func request_pause(reason: StringName) -> void:
	if _pause_reasons.has(reason):
		return
	_pause_reasons[reason] = true
	if not get_tree().paused:
		get_tree().paused = true
		EventBus.game_paused.emit(true)


func release_pause(reason: StringName) -> void:
	if not _pause_reasons.has(reason):
		return
	_pause_reasons.erase(reason)
	if _pause_reasons.is_empty() and get_tree().paused:
		get_tree().paused = false
		EventBus.game_paused.emit(false)


func is_ui_paused() -> bool:
	return not _pause_reasons.is_empty()


func _process(delta: float) -> void:
	if not is_running:
		return

	elapsed += delta
	_dot_clock += delta
	while _dot_clock >= 0.125:
		_dot_clock -= 0.125
		_dot_bucket = (_dot_bucket + 1) % 4
		EventBus.dot_tick.emit(_dot_bucket)

	if energy < max_energy:
		var regen := ENERGY_REGEN * Skills.energy_regen_multiplier()
		energy = minf(max_energy, energy + regen * delta)
		_emit_energy()

	var income := Skills.gold_income()
	if income > 0.0:
		_income_accum += income * delta
		var payout := int(floor(_income_accum))
		if payout > 0:
			_income_accum -= float(payout)
			# 债券是固定利息，直接入账，不走 gold_gain 倍率。
			add_gold_debt(payout)

	if elapsed - _last_time_sent >= 0.1:
		_last_time_sent = elapsed
		EventBus.run_time_changed.emit(elapsed)


func color_of(color_value: int) -> Color:
	return color_rules.hdr_color_for(color_value)


## 当前选择的机体。直接运行 main.tscn（测试、截图）时回退到棱镜/第一个角色。
func get_selected_character() -> CharacterResource:
	selected_character_id = &"prism"
	var character := ContentDB.get_character(selected_character_id)
	if character != null:
		return character
	character = ContentDB.get_character(&"prism")
	if character != null:
		return character
	var all := ContentDB.get_characters()
	return all[0] if not all.is_empty() else null


func ui_color_of(color_value: int) -> Color:
	return color_rules.color_for(color_value)


func dim_color_of(color_value: int) -> Color:
	return color_rules.dim_color_for(color_value)


func current_color() -> Color:
	return color_of(color_index)


func color_multiplier(attacker: int, defender: int) -> float:
	return color_rules.multiplier(attacker, defender)


func color_relation(attacker: int, defender: int) -> StringName:
	return color_rules.relation(attacker, defender)


func can_switch_color() -> bool:
	return energy >= switch_energy_cost()


func switch_energy_cost() -> float:
	return 1.0 + (1.0 if Skills.relic_count(&"epic_shield_generator") > 0 else 0.0)


func cycle_color(direction: int = 1) -> bool:
	if not can_switch_color():
		EventBus.color_switch_failed.emit()
		return false
	return _set_color(ColorType.next(color_index, direction))


func select_color(target: int) -> bool:
	if target == color_index:
		return false
	if not can_switch_color():
		EventBus.color_switch_failed.emit()
		return false
	return _set_color(target)


func spend_energy(amount: float) -> bool:
	if energy < amount:
		EventBus.color_switch_failed.emit()
		return false
	energy -= amount
	_emit_energy(true)
	EventBus.energy_spent.emit(amount)
	return true


func restore_energy_full() -> void:
	energy = max_energy
	_emit_energy(true)


## 技能树改变能量上限时调用；新增的上限会立即补满对应能量。
func refresh_energy_caps() -> void:
	var new_max := ENERGY_MAX + Skills.energy_max_bonus()
	if new_max > max_energy:
		energy = minf(new_max, energy + (new_max - max_energy))
	max_energy = new_max
	energy = clampf(energy, 0.0, max_energy)
	_last_energy_pip = -1
	_emit_energy(true)


## 商店消费：金币不足时返回 false 且不扣款。
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


## 退款不经过金币倍率，用于购买流程中的防御性回滚。
func refund_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	EventBus.gold_changed.emit(gold)


## 遗物代价与固定收益直接调整余额，不经过金币获取倍率；商店消费仍要求余额足够。
func add_gold_debt(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	EventBus.gold_changed.emit(gold)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	# 金币倍率用小数累积，避免每次击杀取整后吃掉收益。
	_gold_fraction += float(amount) * Skills.gold_multiplier()
	var gained := int(floor(_gold_fraction))
	if gained <= 0:
		return
	_gold_fraction -= float(gained)
	gold += gained
	EventBus.gold_changed.emit(gold)
	Skills.on_gold_gained(gained)


func add_xp(amount: float) -> void:
	if amount <= 0:
		return

	_xp_fraction += float(amount) * Skills.xp_multiplier()
	var gained := int(floor(_xp_fraction))
	if gained <= 0:
		return
	_xp_fraction -= float(gained)

	xp += gained
	var threshold := _xp_threshold(level)
	while xp >= threshold:
		xp -= threshold
		level += 1
		threshold = _xp_threshold(level)
		EventBus.level_up.emit(level)
	EventBus.xp_changed.emit(xp, level)


## 调试入口：跳过 XP 直接连升 count 级。仍逐级发 level_up，
## 让 Main 的正常三选一流程依次排队，而不是只改 HUD 上的数字。
func debug_grant_levels(count: int) -> void:
	for _i in maxi(0, count):
		xp = 0
		level += 1
		EventBus.level_up.emit(level)
	if count > 0:
		EventBus.xp_changed.emit(xp, level)


func _xp_threshold(current_level: int) -> int:
	if current_level >= 1 and current_level <= EARLY_XP_REQUIREMENTS.size():
		return EARLY_XP_REQUIREMENTS[current_level - 1]
	var late_level := maxi(0, current_level - 5)
	var threshold := 8 + current_level * 6 + roundi(0.50 * late_level * late_level)
	if current_level > 30:
		var high_level := current_level - 30
		threshold += 10 * high_level + roundi(0.70 * high_level * high_level)
	return threshold


func _set_color(target: int) -> bool:
	if target == color_index:
		return false

	var cost := switch_energy_cost()
	if energy < cost:
		EventBus.color_switch_failed.emit()
		return false
	color_index = posmod(target, ColorType.COUNT)
	energy = maxf(0.0, energy - cost)
	_emit_energy(true)
	EventBus.energy_spent.emit(cost)
	EventBus.color_changed.emit(color_index)
	return true


func _emit_energy(force: bool = false) -> void:
	var pip := int(floor(energy))
	if force or pip != _last_energy_pip:
		_last_energy_pip = pip
		EventBus.energy_changed.emit(energy, max_energy)

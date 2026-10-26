extends Node

## 全局信号总线。系统之间只通过这里通信，避免相互直接引用。

signal color_changed(color_index: int)
signal color_switch_preview(
	active: bool,
	screen_position: Vector2,
	direction: int,
	previous_color: int,
	next_color: int
)
signal color_switch_failed

signal energy_changed(energy: float, maximum: float)
signal energy_spent(amount: float)
signal player_health_changed(current: float, maximum: float)
signal player_damaged(amount: float)
signal player_dodged
signal player_died

signal game_paused(paused: bool)

signal enemy_killed(enemy: Node, gold: int, xp: float)
signal gold_changed(gold: int)
signal xp_changed(xp: int, level: int)
signal level_up(level: int)

signal run_time_changed(seconds: float)
signal run_started
signal run_ended

## 商人：出现时 HUD 画屏幕外箭头，接触后打开商店。
signal merchant_spawned(merchant: Node)
signal merchant_reached(merchant: Node)
signal merchant_despawned(merchant: Node)

## 恶魔/天使祭坛：3 阶解锁后在地面出现，接触后暂停并打开交易面板。
signal altar_spawned(altar: Node)
signal altar_reached(altar: Node)
signal altar_despawned(altar: Node)

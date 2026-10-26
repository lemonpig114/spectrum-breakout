class_name ColorType
extends RefCounted

## 红 → 绿 → 蓝 → 红 的循环顺序。
## 克制关系：红克绿、绿克蓝、蓝克红（即 next 方向）。

enum { RED, GREEN, BLUE }

const COUNT := 3
const NAMES: Array[String] = ["红", "绿", "蓝"]


static func next(color_index: int, step: int = 1) -> int:
	return posmod(color_index + step, COUNT)


static func beats(attacker: int, defender: int) -> bool:
	return next(attacker) == defender


static func is_same(attacker: int, defender: int) -> bool:
	return attacker == defender

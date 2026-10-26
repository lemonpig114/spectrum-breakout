extends Node

var failures := 0
var levels: Array[int] = []


func _ready() -> void:
	RunState.begin_run()
	EventBus.level_up.connect(func(level: int): levels.append(level))
	_check([RunState._xp_threshold(1), RunState._xp_threshold(2), RunState._xp_threshold(3), RunState._xp_threshold(4)] == [6, 12, 20, 30], "early thresholds are 6/12/20/30")
	for level in range(5, 101):
		var late := level - 5
		var expected := 8 + level * 6 + roundi(0.50 * late * late)
		if level > 30:
			var high := level - 30
			expected += 10 * high + roundi(0.70 * high * high)
		if RunState._xp_threshold(level) != expected:
			failures += 1
	_check(failures == 0, "levels 5-30 and 30+ follow separate continuous growth curves")
	_check(RunState._xp_threshold(31) > RunState._xp_threshold(30) and
		RunState._xp_threshold(40) > 8 + 40 * 6 + roundi(0.50 * 35 * 35),
		"level thirty onward requires more experience")
	RunState.add_xp(5)
	_check(RunState.level == 1 and RunState.xp == 5, "first level does not trigger early")
	RunState.add_xp(1)
	_check(RunState.level == 2 and RunState.xp == 0, "six experience grants the first level")
	RunState.add_xp(13)
	_check(RunState.level == 3 and RunState.xp == 1, "overflow carries into the next early level")
	RunState.add_xp(19)
	RunState.add_xp(30)
	_check(RunState.level == 5 and RunState.xp == 0, "68 total XP reaches level five")
	RunState.add_xp(38)
	_check(RunState.level == 6 and RunState.xp == 0, "level five keeps its old threshold")
	RunState.add_xp(100)
	_check(RunState.level == 8 and RunState.xp == 3, "large XP award resolves multiple levels without loss")
	_check(levels == [2, 3, 4, 5, 6, 7, 8], "each level emits exactly one event in order")
	# 调试连升：跳过 XP，但逐级发事件，供 Main 正常排队三选一。
	levels.clear()
	RunState.xp = 4
	RunState.debug_grant_levels(10)
	_check(RunState.level == 18 and RunState.xp == 0, "debug grants ten levels and clears xp")
	_check(levels == [9, 10, 11, 12, 13, 14, 15, 16, 17, 18], "debug emits one level_up per granted level")
	print("XP TEST %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
	print("XP %s: %s" % ["PASS" if ok else "FAIL", description])

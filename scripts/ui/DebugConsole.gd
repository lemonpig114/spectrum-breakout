class_name DebugConsole
extends Control

## 桌面调试包专用；正式版的启用策略以后从配置文件读取。
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const WEAPONS := ["sword", "lightning", "star", "boomerang"]
const ENEMY_ALIASES := {
	"triangle": &"chaser_triangle", "square": &"chaser_square",
	"hex": &"chaser_hex", "plane": &"ranged_plane", "round": &"chaser_round",
}
const COMMANDS := ["help", "w", "rw", "primary", "e", "boss", "gold", "xp", "clear", "fps"]

var main: Node2D
var _input: LineEdit
var _output: RichTextLabel
var _history: Array[String] = []
var _history_index := 0
var _lines: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 80)
	panel.custom_minimum_size = Vector2(520, 210)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.055, 0.94)
	style.border_color = Color(0.32, 0.80, 1.0, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_output = RichTextLabel.new()
	_output.custom_minimum_size = Vector2(490, 155)
	_output.bbcode_enabled = false
	_output.scroll_following = true
	_output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_output)
	_input = LineEdit.new()
	_input.placeholder_text = "输入命令 · Tab 补全 · ↑ 历史 · ~ 关闭"
	_input.custom_minimum_size.y = 34
	_input.text_submitted.connect(_submit)
	_input.gui_input.connect(_on_line_input)
	column.add_child(_input)
	_log("调试控制台已就绪。输入 help 查看命令。")


func setup(main_node: Node2D) -> void:
	main = main_node


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode != KEY_QUOTELEFT and event.keycode != KEY_QUOTELEFT:
		return
	if visible:
		_close()
	elif main != null and RunState.is_running and not RunState.is_dead and not RunState.is_ui_paused():
		visible = true
		RunState.request_pause(&"debug_console")
		_input.grab_focus()
	get_viewport().set_input_as_handled()


func _close() -> void:
	visible = false
	_input.release_focus()
	RunState.release_pause(&"debug_console")


func _on_line_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_QUOTELEFT:
		_close()
		accept_event()
		return
	match event.keycode:
		KEY_TAB:
			_complete()
			accept_event()
		KEY_UP:
			if not _history.is_empty():
				_history_index = maxi(0, _history_index - 1)
				_input.text = _history[_history_index]
				_input.caret_column = _input.text.length()
			accept_event()
		KEY_DOWN:
			if not _history.is_empty():
				_history_index = mini(_history.size(), _history_index + 1)
				_input.text = _history[_history_index] if _history_index < _history.size() else ""
				_input.caret_column = _input.text.length()
			accept_event()
		KEY_ESCAPE:
			_close()
			accept_event()
		KEY_QUOTELEFT:
			_close()
			accept_event()


func _complete() -> void:
	var parts := _input.text.strip_edges().split(" ", false)
	var options: Array[String] = []
	var prefix := ""
	if parts.size() <= 1 and not _input.text.ends_with(" "):
		prefix = parts[0] if not parts.is_empty() else ""
		for command in COMMANDS:
			if command.begins_with(prefix):
				options.append(command)
	else:
		var command := parts[0]
		prefix = "" if _input.text.ends_with(" ") else parts[-1]
		var candidates := WEAPONS if command in ["w", "rw", "primary"] else ENEMY_ALIASES.keys()
		for candidate in candidates:
			if String(candidate).begins_with(prefix):
				options.append(String(candidate))
	if options.size() == 1:
		if parts.size() <= 1 and not _input.text.ends_with(" "):
			_input.text = options[0] + " "
		else:
			_input.text = parts[0] + " " + options[0] + " "
		_input.caret_column = _input.text.length()
	elif options.size() > 1:
		_log("可补全：" + "  ".join(options))


func _submit(raw: String) -> void:
	var line := raw.strip_edges().to_lower()
	_input.clear()
	if line.is_empty():
		return
	_history.append(line)
	_history_index = _history.size()
	_log("> " + line)
	var args := line.split(" ", false)
	match args[0]:
		"help": _log("w 剑名 | rw 剑名 | primary 剑名 | e 怪名 数量 [red/green/blue] | boss | gold 数量 | xp 数量 | clear | fps")
		"w": _weapon(args)
		"rw": _remove_weapon(args)
		"primary": _primary(args)
		"e": _enemies(args)
		"boss":
			var boss := Director.spawn_boss_now(main.player.global_position + Vector2(300, 0))
			_log("Boss 已生成" if boss != null else "Boss 已在场上或无法生成")
		"gold":
			RunState.add_gold(_number(args, 1, 100))
			_log("金币：%d" % RunState.gold)
		"xp":
			RunState.add_xp(_number(args, 1, 100))
			_log("增加经验")
			if main.level_up_panel.visible:
				_close()
		"clear":
			for enemy in get_tree().get_nodes_in_group(&"enemies"):
				enemy.queue_free()
			_log("已清除敌人")
		"fps": _log("FPS %d · 敌人 %d · 弹体 %d" % [Engine.get_frames_per_second(),
			get_tree().get_nodes_in_group(&"enemies").size(), main.projectile_manager._active.size()])
		_: _log("未知命令。输入 help。")
	if visible:
		_input.grab_focus()


func _weapon(args: PackedStringArray) -> void:
	if args.size() < 2 or not WEAPONS.has(args[1]):
		_log("用法：w sword|lightning|star|boomerang")
		return
	var id := StringName(args[1])
	if main.player.weapon.acquire_form(id):
		_log("已获得：%s；请选择主形态" % args[1])
		_close()
		main.open_debug_weapon_choice()
	else:
		_log("武器已拥有或资源缺失")


func _remove_weapon(args: PackedStringArray) -> void:
	if args.size() < 2 or not WEAPONS.has(args[1]):
		_log("用法：rw sword|lightning|star|boomerang")
		return
	if not main.player.weapon.remove_form(StringName(args[1])):
		_log("尚未拥有该武器")
		return
	var primary := String(main.player.weapon.primary_form)
	_log("已移除：%s；当前主形态：%s" % [args[1], primary if not primary.is_empty() else "基础弹"])


func _primary(args: PackedStringArray) -> void:
	if args.size() < 2 or not main.player.weapon.select_primary(StringName(args[1])):
		_log("用法：primary 已拥有的武器名")
		return
	_log("主形态：%s" % args[1])


func _enemies(args: PackedStringArray) -> void:
	if args.size() < 2 or not ENEMY_ALIASES.has(args[1]):
		_log("用法：e triangle|square|hex|plane|round 数量 [red/green/blue]")
		return
	var data := ContentDB.get_enemy(ENEMY_ALIASES[args[1]])
	if data == null:
		_log("敌人资源缺失")
		return
	var count := clampi(_number(args, 2, 1), 1, 500)
	var color := -1
	if args.size() > 3:
		color = ["red", "green", "blue"].find(args[3])
	for i in count:
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.configure(data, main.player, color if color >= 0 else i % 3)
		enemy.max_health *= Director.health_multiplier()
		enemy.health = enemy.max_health
		main.world.add_child(enemy)
		var angle := TAU * float(i) / float(count)
		enemy.global_position = main.player.global_position + Vector2.from_angle(angle) * (240.0 + float(i % 5) * 16.0)
	_log("生成 %d 只 %s" % [count, args[1]])


func _number(args: PackedStringArray, index: int, fallback: int) -> int:
	if index >= args.size() or not args[index].is_valid_int():
		return fallback
	return int(args[index])


func _log(message: String) -> void:
	_lines.append(message)
	if _lines.size() > 12:
		_lines.pop_front()
	_output.text = "\n".join(_lines)

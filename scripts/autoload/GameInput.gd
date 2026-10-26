extends Node

## 在进入游戏前注册输入动作，避免手写 project.godot 的 InputEvent 序列化。
## 右键切色使用原始鼠标事件（需要区分点击/长按拖动），不注册为动作。

func _enter_tree() -> void:
	_register_keys(&"move_left", [KEY_A, KEY_LEFT])
	_register_keys(&"move_right", [KEY_D, KEY_RIGHT])
	_register_keys(&"move_up", [KEY_W, KEY_UP])
	_register_keys(&"move_down", [KEY_S, KEY_DOWN])
	_register_keys(&"dash", [KEY_SPACE])
	_register_keys(&"restart", [KEY_R])
	_register_keys(&"pause", [KEY_ESCAPE])


func _register_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

extends Node

## 菜单截图：加载动画或选择机体界面，用于检查版式与发光。
## godot --path . res://tests/menu_screenshot.tscn -- --mode boot --shot res://tests/screenshot_boot.png
## godot --path . res://tests/menu_screenshot.tscn -- --mode select --index 1 --shot res://tests/screenshot_select.png

const BOOT_SCENE := preload("res://scenes/boot.tscn")
const SELECT_SCENE := preload("res://scenes/character_select.tscn")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := _arg_value(args, "--mode", "select")
	var path := _arg_value(args, "--shot", "res://tests/screenshot_%s.png" % mode)
	var index := int(_arg_value(args, "--index", "0"))

	if mode == "boot":
		add_child(BOOT_SCENE.instantiate())
		await get_tree().create_timer(0.9).timeout
	else:
		var screen := SELECT_SCENE.instantiate()
		add_child(screen)
		if index > 0:
			screen.set("_selected", index)
			screen.set("_hover_card", index)
		if mode == "codex":
			screen.call("_open_codex")
			screen._codex_panel.set_category(int(_arg_value(args, "--category", "0")))
			screen._codex_panel.search.text = _arg_value(args, "--search", "")
			screen._codex_panel.refresh()
		await get_tree().create_timer(0.7).timeout

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("MENU screenshot error=%s path=%s" % [error, path])
	get_tree().quit()


func _arg_value(args: PackedStringArray, key: String, fallback: String) -> String:
	var index := args.find(key)
	if index < 0 or index + 1 >= args.size():
		return fallback
	return args[index + 1]

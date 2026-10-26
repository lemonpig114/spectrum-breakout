extends SceneTree

## 开发用：把截图局部放大，便于检查渐变是否在字符内部/字符之间连续。
## godot --headless --path . --script res://tests/zoom_screenshot.gd -- \
##     res://tests/screenshot_supercrit.png res://tests/screenshot_supercrit_4x.png 4 560 170 280 180
## 参数：输入路径 输出路径 放大倍数 x y w h（后四个可省略，默认全图放大）。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("ZOOM usage: <in.png> <out.png> <scale> [x y w h]")
		quit(2)
		return

	var source := Image.load_from_file(args[0])
	if source == null:
		print("ZOOM failed to load %s" % args[0])
		quit(1)
		return

	var scale := maxi(1, int(args[2]))
	var region := Rect2i(Vector2i.ZERO, source.get_size())
	if args.size() >= 7:
		region = Rect2i(
			int(args[3]), int(args[4]), int(args[5]), int(args[6])
		)
		region = region.intersection(Rect2i(Vector2i.ZERO, source.get_size()))

	var cropped := source.get_region(region)
	cropped.resize(region.size.x * scale, region.size.y * scale, Image.INTERPOLATE_NEAREST)
	var error := cropped.save_png(args[1])
	print("ZOOM saved error=%s region=%s scale=%s path=%s" % [
		error, region, scale, args[1]
	])
	quit(0 if error == OK else 1)

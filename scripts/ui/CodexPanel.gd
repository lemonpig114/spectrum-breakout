extends Control
## 只读图鉴：直接读取正式内容资源，不依赖本局解锁状态。
signal closed
var entries: Array[Dictionary] = []
var filtered: Array[Dictionary] = []
var category := 0
var search: LineEdit
var listing: ItemList
var detail: RichTextLabel
var counter: Label
var tabs: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.026, 0.043, 1.0)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "图鉴   /   战斗档案"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "返回" if GameInput.touch_controls_active else "返回  ·  Esc"
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	column.add_child(navigation)
	for i in 4:
		var button := Button.new()
		button.text = ["技能路线", "遗物", "敌人", "颜色与生存"][i]
		button.custom_minimum_size = Vector2(140, 38)
		button.toggle_mode = true
		button.pressed.connect(set_category.bind(i))
		navigation.add_child(button)
		tabs.append(button)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、路线或效果…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String): refresh())
	column.add_child(search)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	column.add_child(body)
	listing = ItemList.new()
	listing.custom_minimum_size.x = 330
	listing.size_flags_vertical = SIZE_EXPAND_FILL
	listing.add_theme_constant_override("v_separation", 14)
	listing.add_theme_font_size_override("font_size", 17)
	listing.item_selected.connect(show_entry)
	body.add_child(listing)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.size_flags_horizontal = SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("normal_font_size", 18)
	detail.add_theme_constant_override("line_separation", 10)
	body.add_child(detail)
	counter = Label.new()
	counter.add_theme_color_override("font_color", Color(0.55, 0.64, 0.73))
	column.add_child(counter)
	var skin := Theme.new()
	skin.set_stylebox("normal", "Button", box(Color(0.045, 0.065, 0.10)))
	skin.set_stylebox("hover", "Button", box(Color(0.08, 0.14, 0.20)))
	skin.set_stylebox("pressed", "Button", box(Color(0.09, 0.24, 0.30)))
	skin.set_stylebox("panel", "ItemList", box(Color(0.025, 0.04, 0.065)))
	skin.set_stylebox("selected", "ItemList", box(Color(0.08, 0.19, 0.25)))
	skin.set_stylebox("selected_focus", "ItemList", box(Color(0.08, 0.22, 0.28)))
	skin.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.05, 0.08)))
	skin.set_stylebox("normal", "RichTextLabel", box(Color(0.025, 0.04, 0.065)))
	theme = skin
	build_entries()
	set_category(0)

func build_entries() -> void:
	entries.clear()
	var skills := SkillCatalog.build()
	var names := {}
	for skill in skills:
		names[skill.id] = skill.display_name
	for skill in skills:
		var requirements := PackedStringArray()
		for id in skill.prerequisites:
			requirements.append(names.get(id, str(id)))
		var route := "起始技能" if requirements.is_empty() else "前置：" + " + ".join(requirements)
		add_entry(0, skill.display_name, skill.branch_name + " · " + str(skill.tier) + " 阶",
			skill.description + "\n\n" + route, skill.accent)
	var qualities := ["尘灰", "微光", "炬火", "璀璨", "幻彩", "诅咒"]
	for relic in SkillCatalog.build_relics():
		var source := "商店 / 宝箱"
		if relic.chest_only:
			source = "宝箱"
		elif relic.side != &"":
			source = "恶魔契约 / 祭坛 / 商店" if relic.side == &"demon" else "天使契约 / 祭坛 / 商店"
		elif relic.lucky:
			source = "解锁幸运后：商店 / 宝箱"
		if relic.id == &"iridescent_lucifer":
			source = "恶魔、巨化、暴击线全部点满：最高等级商店（唯一）"
		elif relic.id == &"iridescent_michael":
			source = "天使、暴击、弱点线全部点满：最高等级商店（唯一）"
		elif relic.id == &"epic_weapon_cache":
			source = "商店独立1%判定，固定免费（唯一）"
		add_entry(1, relic.display_name, qualities[relic.rarity], relic.description + "\n\n来源：" + source, Skills._rarity_color(relic.rarity))
	var enemies := ContentDB.get_enemies()
	enemies.sort_custom(func(a, b): return a.unlock_time < b.unlock_time if a.unlock_time != b.unlock_time else a.display_name < b.display_name)
	for enemy in enemies:
		var role := "快速逼近，生命较低。"
		var accent := Color(0.6, 0.85, 1.0)
		if enemy.sides == 4:
			role = "基础近战单位，速度与耐久均衡。"
			accent = Color(0.95, 0.76, 0.47)
		elif enemy.sides == 6:
			role = "大型重装单位，缓慢而耐打。"
			accent = Color(0.78, 0.62, 1.0)
		if enemy.behavior == &"ranged":
			role = "双钝角三角翼组成的远程单位，会与玩家保持距离并射击。"
			accent = Color(0.66, 0.94, 0.96)
		if enemy.behavior == &"explode":
			role = "高速逼近的圆核。接触玩家或被击杀时都会在小范围内爆炸。"
			accent = Color(1.0, 0.66, 0.42)
		if enemy.is_boss:
			role = "180 秒登场的方形首领。增强附近方形、预告召唤、晋升换色，并以方锤和定点冲刺限制走位。"
			accent = Color(1.0, 0.55, 0.82)
		if enemy.id == &"hex_boss":
			role = "420 秒登场。六条边独立配色与血量，只承受对应边的弱点伤害；无色及灵魂伤害按5%结算。破边使其余边回满、场上六边形加速且无敌5秒；余边不多于两条时死亡。边数越少移动和自转越快，冲刺会撞死小怪。每条边最终375000生命。"
		var appearance := "首次出现  %d 秒" % int(enemy.unlock_time)
		add_entry(2, enemy.display_name, "红 / 绿 / 蓝均可能",
			role + "\n\n基础生命  %.0f\n移动速度  %.0f\n接触伤害  %.1f 心\n经验  %.1f    金币  %d\n%s\n\n颜色随机，与形状和职责独立。生命只在新刷出时随时间增长。" % [enemy.max_health, enemy.move_speed, enemy.contact_damage, enemy.xp_reward, enemy.gold_reward, appearance], accent)
	var rules := RunState.color_rules
	var color_input_hint := "右键轻点切换颜色；按住并横拖选择颜色。"
	if GameInput.touch_controls_active:
		color_input_hint = "轻点切换颜色；长按查看，左右滑动选择颜色。"
	add_entry(3, "颜色克制", "红 → 绿 → 蓝 → 红", "红色克制绿色，绿色克制蓝色，蓝色克制红色。\n\n克制伤害 ×%.1f，同色 ×%.1f，逆向 ×%.1f。\n%s每次切换消耗 1 能量。" % [rules.advantage_multiplier, rules.same_multiplier, rules.reverse_multiplier, color_input_hint], Color(0.5, 0.85, 1))
	add_entry(3, "成长与拾取", "升级 / 宝箱 / 商人", "前四次升级需要 6 / 12 / 20 / 30 经验。\n金币与经验靠近后吸收；商人到达时会收集地面资源。\n遗物出现后可拾取或丢弃，5 秒未选择自动拾取。暂停时停止读条。", Color(0.5, 0.85, 1))
	var pause_hint := "点右上角暂停查看本局技能与遗物。" if GameInput.touch_controls_active else \
		"按 Esc 查看本局技能与遗物。"
	add_entry(3, "技能路线", "20 条路线 · 80 项技能", "一阶开启路线；二阶和三阶都只需一阶。四阶需要同时拥有二阶、三阶。\n恰好两发子弹会平行射出；三发以上形成扇形。\n%s" % pause_hint, Color(0.5, 0.85, 1))

func add_entry(group: int, title: String, subtitle: String, body: String, accent: Color) -> void:
	entries.append({"category": group, "title": title, "subtitle": subtitle, "body": body, "accent": Color(clampf(accent.r, 0, 1), clampf(accent.g, 0, 1), clampf(accent.b, 0, 1)).lerp(Color.WHITE, 0.30)})

func set_category(value: int) -> void:
	category = value
	for i in tabs.size():
		tabs[i].button_pressed = i == value
	refresh()

func refresh() -> void:
	filtered.clear()
	listing.clear()
	var query := search.text.strip_edges().to_lower()
	for entry in entries:
		if entry.category != category:
			continue
		if not query.is_empty() and not (entry.title + entry.subtitle + entry.body).to_lower().contains(query):
			continue
		filtered.append(entry)
		listing.add_item(entry.subtitle + "   /   " + entry.title)
		listing.set_item_custom_fg_color(listing.item_count - 1, entry.accent)
	counter.text = "%d 条记录  ·  滚轮浏览，点击查看完整效果" % filtered.size()
	detail.text = "没有匹配的记录，试试其他关键词。"
	if not filtered.is_empty():
		listing.select(0)
		show_entry(0)

func show_entry(index: int) -> void:
	var entry := filtered[index]
	detail.text = "[font_size=30][color=#%s]%s[/color][/font_size]\n[color=#8297ac]%s[/color]\n\n%s" % [entry.accent.to_html(false), entry.title, entry.subtitle, entry.body]
	detail.scroll_to_line(0)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()


func box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.18, 0.32, 0.42, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

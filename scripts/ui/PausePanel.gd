class_name PausePanel
extends Control

## 手动暂停界面：左侧查看本局技能路线 / 遗物清单，右侧放菜单操作。
## 使用独立的暂停原因 &"manual_pause"，与升级/商店互不干扰。
## 面板本身在 paused 状态下继续处理输入与绘制。

signal closed
## 「退出」不再关闭游戏，而是交给 Main 回到机体选择界面。
signal menu_requested

const GLYPH := preload("res://scripts/ui/SkillGlyph.gd")
const GOLD := Color(1.0, 0.84, 0.38, 1.0)
const DANGER := Color(1.0, 0.32, 0.30, 1.0)
const WGHT_AXIS := 0x77676874

const SKILL_BRANCH_ORDER: Array[StringName] = [
	&"fire_rate", &"heavy", &"energy", &"speed",
	&"demon", &"angel", &"xp", &"gold",
	&"soul", &"splash", &"weakness", &"crit",
	&"shotgun", &"luck", &"fragile", &"sprite", &"clone", &"circle", &"giant",
]
const TIER_NAMES: Array[String] = ["I", "II", "III", "IV"]
const RARITY_NAMES: Array[String] = ["尘灰", "微光", "炬火", "璀璨", "幻彩", "诅咒"]

enum Screen { MENU, SETTINGS, QUIT }

var _font: Font
var _bold_font: FontVariation
var _appear := 0.0
var _time := 0.0
var _screen := Screen.MENU
var _tab := 0
var _menu_hover := -1
var _tab_hover := -1
var _settings_hover := -1
var _quit_hover := -1
var _branch_hover := -1
var _skill_hover := &""
var _relic_hover := &""
var _focus_skill_id: StringName = &""
var _focus_relic_id: StringName = &""
var _route_scroll := 0.0
var _route_scroll_target := 0.0
var _relic_scroll := 0.0
var _relic_scroll_target := 0.0
var _damage_scroll := 0
var _branch_cache: Array[Dictionary] = []
var _relic_cache: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_refresh_fonts()


func open() -> void:
	visible = true
	_appear = 0.0
	_time = 0.0
	_screen = Screen.MENU
	_tab = 0
	_menu_hover = -1
	_tab_hover = -1
	_settings_hover = -1
	_quit_hover = -1
	_branch_hover = -1
	_skill_hover = &""
	_relic_hover = &""
	_route_scroll = 0.0
	_route_scroll_target = 0.0
	_relic_scroll = 0.0
	_relic_scroll_target = 0.0
	_damage_scroll = 0
	_refresh_fonts()
	_rebuild_cache()
	queue_redraw()


func close() -> void:
	visible = false
	_skill_hover = &""
	_relic_hover = &""
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_appear = minf(1.0, _appear + delta * 5.2)
	_time += delta
	# 滚动是“目标位置 + 快速缓动”，滚轮只改目标，不改当前位置。
	var ease := 1.0 - exp(-18.0 * delta)
	_route_scroll = _approach(_route_scroll, _route_scroll_target, ease)
	_relic_scroll = _approach(_relic_scroll, _relic_scroll_target, ease)
	_refresh_fonts()
	queue_redraw()


# ── 数据缓存 ────────────────────────────────────────────────────

func _refresh_fonts() -> void:
	var current := ThemeDB.fallback_font
	if current == null or current == _font:
		return
	_font = current
	_bold_font = FontVariation.new()
	_bold_font.base_font = current
	_bold_font.variation_opentype = {WGHT_AXIS: 800}


func _rebuild_cache() -> void:
	_branch_cache.clear()
	for branch in SKILL_BRANCH_ORDER:
		var line_nodes: Array[SkillNodeResource] = []
		for node in Skills.nodes:
			if node.branch == branch:
				line_nodes.append(node)
		if line_nodes.is_empty():
			continue
		line_nodes.sort_custom(func(a: SkillNodeResource, b: SkillNodeResource) -> bool:
			return a.tier < b.tier
		)
		# 只收录本局真正走进来的路线，未选择的路线不占地图空间。
		var unlocked_count := 0
		for node in line_nodes:
			if Skills.is_unlocked(node.id):
				unlocked_count += 1
		if unlocked_count <= 0:
			continue
		_branch_cache.append({
			"branch": branch,
			"name": line_nodes[0].branch_name,
			"accent": line_nodes[0].accent,
			"nodes": line_nodes,
			"unlocked_count": unlocked_count,
		})

	_relic_cache.clear()
	var counts: Dictionary = {}
	var definitions: Dictionary = {}
	for relic in Skills.owned_relics:
		counts[relic.id] = int(counts.get(relic.id, 0)) + 1
		definitions[relic.id] = relic
	for relic in Skills.relics:
		if counts.has(relic.id):
			definitions[relic.id] = relic
	for relic_id in counts.keys():
		var definition := definitions.get(relic_id) as RelicResource
		if definition != null:
			_relic_cache.append({
				"relic": definition,
				"count": int(counts[relic_id]),
			})
	_relic_cache.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := a["relic"] as RelicResource
		var rb := b["relic"] as RelicResource
		if ra.rarity != rb.rarity:
			return ra.rarity > rb.rarity
		return ra.display_name < rb.display_name
	)

	if _focus_skill_id == &"" or not Skills.is_unlocked(_focus_skill_id):
		_focus_skill_id = &""
		# Dictionary 保持插入顺序：优先展示最近解锁的节点。
		var unlocked_nodes := Skills.unlocked.values()
		if not unlocked_nodes.is_empty():
			_focus_skill_id = (unlocked_nodes[unlocked_nodes.size() - 1] as SkillNodeResource).id
	if _focus_skill_id == &"" and not _branch_cache.is_empty():
		_focus_skill_id = (_branch_cache[0]["nodes"][0] as SkillNodeResource).id

	if _focus_relic_id == &"" and not _relic_cache.is_empty():
		_focus_relic_id = (_relic_cache[0]["relic"] as RelicResource).id


# ── 绘制入口 ────────────────────────────────────────────────────

func _draw() -> void:
	if not visible or _font == null:
		return
	var ease := 1.0 - pow(1.0 - _appear, 3.0)
	var layout := _layout()

	_draw_backdrop(ease)
	_draw_panel(layout, ease)
	_draw_header(layout, ease)
	_draw_tabs(layout, ease)
	if _tab == 0:
		_draw_skill_map(layout, ease)
	elif _tab == 1:
		_draw_relic_grid(layout, ease)
	else:
		_draw_damage_stats(layout, ease)
	_draw_detail(layout, ease)
	_draw_right_column(layout, ease)
	_draw_footer(layout, ease)


func _draw_backdrop(alpha: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.78 * alpha))
	var card := _panel_rect()
	# 极淡的同心圆，让背景不是一块死黑。
	for i in 3:
		var radius := card.size.x * (0.52 + float(i) * 0.18)
		draw_circle(
			card.get_center() + Vector2(card.size.x * 0.18, -card.size.y * 0.06),
			radius,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.015 * alpha),
			false,
			1.0,
			true
		)


func _draw_panel(layout: Dictionary, alpha: float) -> void:
	var card: Rect2 = layout["card"]
	var rise := Vector2(0.0, (1.0 - alpha) * 18.0)

	draw_rect(Rect2(card.position + rise + Vector2(8.0, 10.0), card.size), Color(0.0, 0.0, 0.0, 0.45 * alpha))
	draw_rect(Rect2(card.position + rise, card.size), Color(0.024, 0.031, 0.050, 0.985 * alpha))

	# 内部细网格。
	var grid_color := Color(1.0, 1.0, 1.0, 0.014 * alpha)
	var gx := card.position.x + 48.0
	while gx < card.end.x:
		draw_line(Vector2(gx, card.position.y), Vector2(gx, card.end.y), grid_color, 1.0)
		gx += 48.0
	var gy := card.position.y + 48.0
	while gy < card.end.y:
		draw_line(Vector2(card.position.x, gy), Vector2(card.end.x, gy), grid_color, 1.0)
		gy += 48.0

	draw_rect(Rect2(card.position + rise, card.size), Color(1.0, 1.0, 1.0, 0.14 * alpha), false, 1.5)
	draw_rect(
		Rect2(card.position + rise, Vector2(card.size.x, 2.0)),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * alpha)
	)

	# 四角括号。
	var corner := 17.0
	var corners := [
		[card.position + Vector2(8.0, 8.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)],
		[card.position + Vector2(card.size.x - 8.0, 8.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0)],
		[card.position + Vector2(8.0, card.size.y - 8.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0)],
		[card.position + Vector2(card.size.x - 8.0, card.size.y - 8.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)],
	]
	var corner_color := Color(GOLD.r, GOLD.g, GOLD.b, 0.42 * alpha)
	for corner_data in corners:
		var origin: Vector2 = corner_data[0] + rise
		draw_line(origin, origin + (corner_data[1] as Vector2) * corner, corner_color, 1.0)
		draw_line(origin, origin + (corner_data[2] as Vector2) * corner, corner_color, 1.0)

	var divider_x: float = layout["divider_x"]
	draw_line(
		Vector2(divider_x, layout["body_y"]),
		Vector2(divider_x, layout["body_bottom"]),
		Color(1.0, 1.0, 1.0, 0.06 * alpha),
		1.0
	)


func _draw_header(layout: Dictionary, alpha: float) -> void:
	var card: Rect2 = layout["card"]
	var pad: float = layout["pad"]
	var rise := (1.0 - alpha) * 12.0
	var x := card.position.x + pad
	var y := card.position.y + 25.0 + rise

	draw_rect(Rect2(Vector2(x, y + 7.0), Vector2(7.0, 7.0)), Color(GOLD.r, GOLD.g, GOLD.b, 0.95 * alpha))
	_text("已暂停", Vector2(x + 16.0, y + 16.0), 22, Color(1.0, 1.0, 1.0, 0.96 * alpha), true)
	var subtitle_x := x + 16.0 + _text_width("已暂停", 22, true) + 14.0
	_text("PAUSED  ·  本局构筑总览", Vector2(subtitle_x, y + 14.0), 9,
		Color(1.0, 1.0, 1.0, 0.30 * alpha))

	_text_right("RUN  %s" % _format_time(RunState.elapsed), card.end.x - pad, y + 12.0, 10,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha))
	_text_right("光谱突围", card.end.x - pad, y + 31.0, 13,
		Color(1.0, 1.0, 1.0, 0.34 * alpha), true)


func _draw_tabs(layout: Dictionary, alpha: float) -> void:
	var rects := _tab_rects(layout)
	var labels := ["技能路线", "遗物清单", "伤害统计"]
	var badges := ["%d / %d" % [Skills.unlocked_count(), Skills.nodes.size()], "%d 件" % Skills.owned_relics.size(), "本局"]

	for i in rects.size():
		var rect: Rect2 = rects[i]
		var active := _tab == i
		var hovered := _tab_hover == i
		var fill := Color(0.07, 0.085, 0.12, 0.95 * alpha) if active else Color(0.038, 0.048, 0.072, 0.9 * alpha)
		if hovered and not active:
			fill = Color(0.06, 0.075, 0.105, 0.95 * alpha)
		draw_rect(rect, fill)
		var border := Color(GOLD.r, GOLD.g, GOLD.b, 0.72 * alpha) if active else Color(1.0, 1.0, 1.0, 0.10 * alpha)
		draw_rect(rect, border, false, 1.2)
		if active:
			draw_rect(
				Rect2(rect.position + Vector2(0.0, rect.size.y - 2.0), Vector2(rect.size.x, 2.0)),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.95 * alpha)
			)

		var text_color := Color(1.0, 0.92, 0.66, 0.96 * alpha) if active else Color(1.0, 1.0, 1.0, 0.56 * alpha)
		_text(labels[i], rect.position + Vector2(16.0, 25.0), 13, text_color, active)
		_text_right(badges[i], rect.end.x - 14.0, rect.position.y + 24.0, 9,
			Color(1.0, 1.0, 1.0, 0.34 * alpha) if not active else Color(1.0, 0.92, 0.66, 0.62 * alpha))

	var hint_right: float = layout["left_x"] + layout["left_w"]
	_text_right(
		("%d 条已选路线 · %d 个节点 · %s查看详情" % [_branch_cache.size(), Skills.unlocked_count(),
			"点按" if GameInput.touch_controls_active else "悬停"]) if _tab == 0 else ("本局已拥有遗物" if _tab == 1 else "实际伤害与单项增伤估算"),
		hint_right,
		rects[0].position.y + 25.0,
		10,
		Color(1.0, 1.0, 1.0, 0.27 * alpha)
	)


func _draw_skill_map(layout: Dictionary, alpha: float) -> void:
	var main: Rect2 = layout["main"]
	if _branch_cache.is_empty():
		_text("还没有选择技能路线", main.get_center() + Vector2(0.0, -8.0), 16,
			Color(1.0, 1.0, 1.0, 0.38 * alpha), true, main.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text("在升级界面选择第一个节点后，这里会画出你本局走出的菱形路线",
			main.get_center() + Vector2(0.0, 20.0), 10,
			Color(1.0, 1.0, 1.0, 0.26 * alpha), false, main.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return

	var grid := _skill_grid(layout)
	_route_scroll = clampf(_route_scroll, 0.0, float(grid["max_scroll"]))
	_route_scroll_target = clampf(_route_scroll_target, 0.0, float(grid["max_scroll"]))
	for i in _branch_cache.size():
		var rect := _branch_rect(layout, i)
		# 与遗物网格一致：只画完整落在可视区内的路线卡。
		if rect.position.y < main.position.y - 0.5 or rect.end.y > main.end.y + 0.5:
			continue
		_draw_branch(layout, i, alpha)

	if float(grid["max_scroll"]) > 0.5:
		var track := Rect2(
			Vector2(main.end.x - 3.0, main.position.y + 2.0),
			Vector2(2.0, main.size.y - 4.0)
		)
		draw_rect(track, Color(1.0, 1.0, 1.0, 0.05 * alpha))
		var ratio := clampf(_route_scroll / float(grid["max_scroll"]), 0.0, 1.0)
		var thumb_h := track.size.y * clampf(float(grid["visible_rows"]) / float(grid["total_rows"]), 0.12, 1.0)
		draw_rect(
			Rect2(track.position + Vector2(0.0, (track.size.y - thumb_h) * ratio), Vector2(2.0, thumb_h)),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha)
		)


func _draw_branch(layout: Dictionary, index: int, alpha: float) -> void:
	var entry: Dictionary = _branch_cache[index]
	var line_nodes: Array = entry["nodes"]
	var accent: Color = entry["accent"]
	var rect := _branch_rect(layout, index)
	var hovered := _branch_hover == index
	var unlocked_count := int(entry["unlocked_count"])

	var fill := Color(0.045, 0.059, 0.088, 0.88 * alpha)
	if hovered:
		fill = Color(
			0.055 + accent.r * 0.035,
			0.069 + accent.g * 0.035,
			0.098 + accent.b * 0.035,
			0.96 * alpha
		)
	draw_rect(rect, fill)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.055 * alpha), false, 1.0)
	if hovered:
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.46 * alpha), false, 1.2)
	draw_rect(
		Rect2(rect.position + Vector2(0.0, 10.0), Vector2(3.0, rect.size.y - 20.0)),
		Color(accent.r, accent.g, accent.b, 0.78 * alpha)
	)

	# 卡片头部：图标、路线名、已点亮节点数。
	var label_color := Color(accent.r, accent.g, accent.b, 0.96 * alpha)
	GLYPH.draw_branch(self, entry["branch"], rect.position + Vector2(19.0, 21.0), 10.0,
		Color(label_color.r, label_color.g, label_color.b, label_color.a * 0.92))
	_text(str(entry["name"]), rect.position + Vector2(35.0, 26.0), 14, label_color, true)
	_text_right("%d / 4" % unlocked_count, rect.end.x - 13.0, rect.position.y + 25.0, 10,
		Color(1.0, 0.94, 0.76, 0.52 * alpha))
	draw_line(
		rect.position + Vector2(13.0, 36.0),
		Vector2(rect.end.x - 13.0, rect.position.y + 36.0),
		Color(1.0, 1.0, 1.0, 0.06 * alpha),
		1.0
	)

	var centers: Array[Vector2] = []
	for tier_index in 4:
		centers.append(_skill_node_center(layout, index, tier_index))
	var node_radius := _node_radius(rect)

	# 菱形连接：I→II、I→III、II→IV、III→IV。
	var edges := [[0, 1], [0, 2], [1, 3], [2, 3]]
	for edge in edges:
		var a: Vector2 = centers[int(edge[0])]
		var b: Vector2 = centers[int(edge[1])]
		var node_a := line_nodes[int(edge[0])] as SkillNodeResource
		var node_b := line_nodes[int(edge[1])] as SkillNodeResource
		var active := Skills.is_unlocked(node_a.id) and Skills.is_unlocked(node_b.id)
		draw_line(a, b, Color(1.0, 1.0, 1.0, 0.055 * alpha), 1.0, true)
		if active:
			draw_line(a, b, Color(accent.r, accent.g, accent.b, 0.34 * alpha), 2.0, true)

	for tier_index in 4:
		var node := line_nodes[tier_index] as SkillNodeResource
		var center: Vector2 = centers[tier_index]
		var unlocked := Skills.is_unlocked(node.id)
		var available := Skills.is_available(node)
		var state_color: Color
		if unlocked:
			state_color = Color(accent.r, accent.g, accent.b, 0.98 * alpha)
		elif available:
			state_color = Color(accent.r, accent.g, accent.b, 0.64 * alpha)
		else:
			state_color = Color(1.0, 1.0, 1.0, 0.22 * alpha)

		if unlocked:
			draw_circle(center, node_radius + 6.0, Color(accent.r, accent.g, accent.b, 0.10 * alpha))
			draw_circle(center, node_radius, Color(accent.r, accent.g, accent.b, 0.18 * alpha))
			draw_circle(center, node_radius, Color(accent.r, accent.g, accent.b, 0.94 * alpha), false, 2.0, true)
		elif available:
			var pulse := 0.5 + 0.5 * sin(_time * 2.4 + float(index) * 0.7 + float(tier_index) * 0.4)
			draw_circle(center, node_radius + 5.0 + pulse * 3.0, Color(accent.r, accent.g, accent.b, 0.10 * alpha))
			draw_circle(center, node_radius, Color(0.03, 0.04, 0.06, 0.85 * alpha))
			draw_circle(center, node_radius, Color(accent.r, accent.g, accent.b, 0.62 * alpha), false, 1.6, true)
		else:
			draw_circle(center, node_radius, Color(1.0, 1.0, 1.0, 0.045 * alpha))
			draw_circle(center, node_radius, Color(1.0, 1.0, 1.0, 0.14 * alpha), false, 1.0, true)

		var numeral_size := int(clampf(node_radius * 0.62, 9.0, 13.0))
		_text(TIER_NAMES[tier_index], Vector2(center.x - node_radius, center.y + float(numeral_size) * 0.36),
			numeral_size, state_color, true, node_radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER)

		var name_color := Color(1.0, 1.0, 1.0, 0.82 * alpha) if unlocked \
			else (Color(1.0, 1.0, 1.0, 0.52 * alpha) if available else Color(1.0, 1.0, 1.0, 0.24 * alpha))
		_draw_skill_caption(node.display_name, rect, centers, tier_index, node_radius, name_color)


func _draw_skill_caption(
	text: String,
	rect: Rect2,
	centers: Array[Vector2],
	tier_index: int,
	node_radius: float,
	color: Color
) -> void:
	var left_center: Vector2 = centers[0]
	var mid_y := left_center.y
	match tier_index:
		0:
			draw_string(_font,
				Vector2(rect.position.x + 4.0, mid_y + node_radius + 15.0),
				text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x * 0.38, 9.5, color)
		1:
			var top_center: Vector2 = centers[1]
			draw_string(_font,
				Vector2(top_center.x + node_radius + 6.0, top_center.y + 4.0),
				text, HORIZONTAL_ALIGNMENT_LEFT,
				rect.end.x - top_center.x - node_radius - 16.0, 9.5, color)
		2:
			var bottom_center: Vector2 = centers[2]
			draw_string(_font,
				Vector2(bottom_center.x - 70.0, bottom_center.y + node_radius + 14.0),
				text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 9.5, color)
		3:
			draw_string(_font,
				Vector2(rect.end.x - rect.size.x * 0.38 - 4.0, mid_y + node_radius + 15.0),
				text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x * 0.38, 9.5, color)


func _draw_relic_grid(layout: Dictionary, alpha: float) -> void:
	var main: Rect2 = layout["main"]
	if _relic_cache.is_empty():
		_text("还没有拾取遗物", main.get_center() + Vector2(0.0, -6.0), 15,
			Color(1.0, 1.0, 1.0, 0.35 * alpha), true, main.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text("商人和宝箱会带来第一件构筑零件", main.get_center() + Vector2(0.0, 20.0), 10,
			Color(1.0, 1.0, 1.0, 0.25 * alpha), false, main.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		return

	var columns := 4 if main.size.x >= 720.0 else 3
	var gap := 10.0
	var card_w := (main.size.x - gap * float(columns - 1)) / float(columns)
	var card_h := 78.0
	var step := card_h + gap
	var scroll := _relic_scroll
	for i in _relic_cache.size():
		var row := i / columns
		var col := i % columns
		var rect := Rect2(
			main.position + Vector2(float(col) * (card_w + gap), float(row) * step - scroll),
			Vector2(card_w, card_h)
		)
		# 只画完整落在可视区内的卡片，避免滚到详情栏上。
		if rect.position.y < main.position.y - 0.5 or rect.end.y > main.end.y + 0.5:
			continue
		_draw_relic_card(rect, _relic_cache[i], alpha)

	var total_rows := int(ceil(float(_relic_cache.size()) / float(columns)))
	var visible_rows := int(floor((main.size.y + gap) / step))
	if total_rows > visible_rows:
		var track := Rect2(
			Vector2(main.end.x - 3.0, main.position.y + 2.0),
			Vector2(2.0, main.size.y - 4.0)
		)
		draw_rect(track, Color(1.0, 1.0, 1.0, 0.05 * alpha))
		var max_scroll := float(total_rows - visible_rows) * step
		var ratio := clampf(scroll / maxf(1.0, max_scroll), 0.0, 1.0)
		var thumb_h := track.size.y * clampf(float(visible_rows) / float(total_rows), 0.12, 1.0)
		draw_rect(
			Rect2(track.position + Vector2(0.0, (track.size.y - thumb_h) * ratio), Vector2(2.0, thumb_h)),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha)
		)


func _draw_relic_card(rect: Rect2, entry: Dictionary, alpha: float) -> void:
	var relic := entry["relic"] as RelicResource
	var count := int(entry["count"])
	var accent := _relic_accent(relic)
	var hovered := _relic_hover == relic.id
	draw_rect(rect, Color(0.046, 0.060, 0.090, 0.93 * alpha))
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.44 * alpha) if hovered else Color(1.0, 1.0, 1.0, 0.06 * alpha), false, 1.0)
	draw_rect(
		Rect2(rect.position, Vector2(2.0, rect.size.y)),
		Color(accent.r, accent.g, accent.b, 0.85 * alpha)
	)

	var icon_center := rect.position + Vector2(26.0, 33.0)
	_draw_relic_gem(icon_center, 13.0, accent, relic.side, alpha)

	var text_x := rect.position.x + 47.0
	_text(relic.display_name, Vector2(text_x, rect.position.y + 25.0), 12.5,
		Color(1.0, 1.0, 1.0, 0.90 * alpha), true)
	_text("%s · %s" % [_rarity_name(relic.rarity), _relic_tag_text(relic)],
		Vector2(text_x, rect.position.y + 41.0), 8.5,
		Color(accent.r, accent.g, accent.b, 0.75 * alpha))

	var description := relic.description.replace("\n", "  ")
	draw_multiline_string(
		_font,
		Vector2(text_x, rect.position.y + 54.0),
		description,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 58.0,
		8.0,
		2,
		Color(1.0, 1.0, 1.0, 0.38 * alpha)
	)

	if count > 1:
		var badge_text := "×%d" % count
		var badge_width := _text_width(badge_text, 10, true) + 10.0
		var badge := Rect2(
			Vector2(rect.end.x - badge_width - 8.0, rect.position.y + 8.0),
			Vector2(badge_width, 17.0)
		)
		draw_rect(badge, Color(accent.r, accent.g, accent.b, 0.17 * alpha))
		draw_rect(badge, Color(accent.r, accent.g, accent.b, 0.45 * alpha), false, 1.0)
		draw_string(_font, badge.position + Vector2(5.0, 12.5), badge_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10,
			Color(1.0, 0.96, 0.82, 0.92 * alpha))


func _draw_detail(layout: Dictionary, alpha: float) -> void:
	var rect: Rect2 = layout["detail"]
	draw_rect(rect, Color(0.032, 0.043, 0.064, 0.96 * alpha))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.07 * alpha), false, 1.0)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 1.0)),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.22 * alpha)
	)

	if _tab == 0:
		var node := Skills.get_node_by_id(_focus_skill_id)
		if node == null:
			_text("悬停技能节点查看效果与前置", rect.position + Vector2(18.0, 36.0), 11,
				Color(1.0, 1.0, 1.0, 0.30 * alpha))
			return
		var accent := node.accent
		var glyph_center := rect.position + Vector2(30.0, rect.size.y * 0.5)
		draw_circle(glyph_center, 18.0, Color(accent.r, accent.g, accent.b, 0.11 * alpha))
		draw_circle(glyph_center, 18.0, Color(accent.r, accent.g, accent.b, 0.48 * alpha), false, 1.2, true)
		GLYPH.draw_branch(self, node.branch, glyph_center, 12.0, accent)

		var text_x := rect.position.x + 58.0
		_text("%s  ·  %s 阶" % [node.branch_name, TIER_NAMES[clampi(node.tier - 1, 0, 3)]],
			Vector2(text_x, rect.position.y + 22.0), 9.5,
			Color(accent.r, accent.g, accent.b, 0.82 * alpha))
		_text(node.display_name, Vector2(text_x, rect.position.y + 44.0), 16,
			Color(1.0, 1.0, 1.0, 0.94 * alpha), true)
		draw_multiline_string(
			_font,
			Vector2(text_x, rect.position.y + 64.0),
			node.description,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 150.0,
			10.0,
			2,
			Color(1.0, 1.0, 1.0, 0.62 * alpha)
		)

		var state := _skill_state(node)
		var state_text: String = state["text"]
		var state_color: Color = state["color"]
		var badge_w := _text_width(state_text, 9.5, true) + 18.0
		var badge := Rect2(
			Vector2(rect.end.x - badge_w - 14.0, rect.position.y + 15.0),
			Vector2(badge_w, 20.0)
		)
		draw_rect(badge, Color(state_color.r, state_color.g, state_color.b, 0.13 * alpha))
		draw_rect(badge, Color(state_color.r, state_color.g, state_color.b, 0.45 * alpha), false, 1.0)
		draw_string(_font, badge.position + Vector2(9.0, 14.0), state_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9.5,
			Color(state_color.r, state_color.g, state_color.b, 0.9 * alpha))
	elif _tab == 1:
		var relic := _find_relic(_focus_relic_id)
		if relic == null:
			_text("拾取遗物后，这里会显示品质、标签与效果", rect.position + Vector2(18.0, 36.0), 11,
				Color(1.0, 1.0, 1.0, 0.30 * alpha))
			return
		var accent := _relic_accent(relic)
		var glyph_center := rect.position + Vector2(30.0, rect.size.y * 0.5)
		_draw_relic_gem(glyph_center, 15.0, accent, relic.side, alpha)
		var text_x := rect.position.x + 58.0
		var count := Skills.relic_count(relic.id)
		_text("%s  ·  %s" % [_rarity_name(relic.rarity), _relic_tag_text(relic)],
			Vector2(text_x, rect.position.y + 22.0), 9.5,
			Color(accent.r, accent.g, accent.b, 0.82 * alpha))
		_text(relic.display_name, Vector2(text_x, rect.position.y + 44.0), 16,
			Color(1.0, 1.0, 1.0, 0.94 * alpha), true)
		draw_multiline_string(
			_font,
			Vector2(text_x, rect.position.y + 64.0),
			relic.description,
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 150.0,
			10.0,
			2,
			Color(1.0, 1.0, 1.0, 0.62 * alpha)
		)
		_text_right("持有 ×%d" % count, rect.end.x - 14.0, rect.position.y + 32.0, 12,
			Color(accent.r, accent.g, accent.b, 0.82 * alpha), true)
	else:
		_text("统计口径", rect.position + Vector2(18.0, 28.0), 13, Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * alpha), true)
		_text("直接伤害只计敌人实际损失的生命，击杀溢出不计。", rect.position + Vector2(18.0, 51.0), 10,
			Color(1.0, 1.0, 1.0, 0.68 * alpha))
		_text("增伤为逐项移除后的估算，不可相加；射速、弹数等暂未分摊。", rect.position + Vector2(18.0, 72.0), 10,
			Color(1.0, 1.0, 1.0, 0.52 * alpha))


func _draw_damage_stats(layout: Dictionary, alpha: float) -> void:
	var main: Rect2 = layout["main"]
	var rows: Array[Dictionary] = []
	for key in Skills.damage_totals:
		rows.append({"key": key, "value": float(Skills.damage_totals[key]), "estimated": false})
	for key in Skills.damage_bonus_estimates:
		rows.append({"key": key, "value": float(Skills.damage_bonus_estimates[key]), "estimated": true})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["value"]) > float(b["value"])
	)
	if rows.is_empty():
		_text("尚未造成伤害", main.position + Vector2(18.0, 34.0), 14,
			Color(1.0, 1.0, 1.0, 0.55 * alpha))
		return
	var row_h := 32.0
	var visible_count := maxi(1, int(main.size.y / row_h))
	_damage_scroll = clampi(_damage_scroll, 0, maxi(0, rows.size() - visible_count))
	for index in range(_damage_scroll, mini(rows.size(), _damage_scroll + visible_count)):
		var row := rows[index]
		var y := main.position.y + float(index - _damage_scroll) * row_h
		var rect := Rect2(main.position.x, y, main.size.x - 4.0, row_h - 3.0)
		draw_rect(rect, Color(0.045, 0.061, 0.086, 0.82 * alpha))
		var estimated := bool(row["estimated"])
		var label := Skills.damage_source_name(row["key"])
		_text(("增伤 · " if estimated else "伤害 · ") + label,
			Vector2(rect.position.x + 12.0, y + 20.0), 11,
			Color(0.75, 0.82, 0.96, 0.78 * alpha) if estimated else Color(1.0, 1.0, 1.0, 0.88 * alpha))
		_text_right("%.0f" % float(row["value"]), rect.end.x - 12.0, y + 20.0, 12,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * alpha), true)


func _draw_right_column(layout: Dictionary, alpha: float) -> void:
	var x: float = layout["right_x"]
	var w: float = layout["right_w"]
	var y: float = layout["body_y"]
	_text("菜单", Vector2(x, y + 16.0), 17, Color(1.0, 1.0, 1.0, 0.94 * alpha), true)
	_text("RUN  MENU", Vector2(x, y + 29.0), 8, Color(1.0, 1.0, 1.0, 0.25 * alpha))

	if _screen == Screen.SETTINGS:
		_draw_settings(layout, alpha)
		return
	if _screen == Screen.QUIT:
		_draw_quit(layout, alpha)
		return

	_draw_summary(layout, alpha)
	_draw_quick_hints(layout, alpha)

	var buttons := _right_button_rects(layout, 3)
	_draw_action_button(buttons[0], "继续游戏", 0, _menu_hover == 0, alpha, true)
	_draw_action_button(buttons[1], "设置", 1, _menu_hover == 1, alpha, false)
	_draw_action_button(buttons[2], "返回主界面", 2, _menu_hover == 2, alpha, false, true)


func _draw_summary(layout: Dictionary, alpha: float) -> void:
	var rect := _summary_rect(layout)
	draw_rect(rect, Color(0.046, 0.059, 0.088, 0.94 * alpha))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.07 * alpha), false, 1.0)
	draw_rect(
		Rect2(rect.position, Vector2(3.0, rect.size.y)),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.74 * alpha)
	)
	_text("本局记录", rect.position + Vector2(16.0, 22.0), 10,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.82 * alpha), true)
	draw_line(
		rect.position + Vector2(16.0, 31.0),
		rect.position + Vector2(rect.size.x - 16.0, 31.0),
		Color(1.0, 1.0, 1.0, 0.08 * alpha),
		1.0
	)

	var character := RunState.get_selected_character()
	var character_name := "棱镜"
	if character != null:
		character_name = character.display_name
	var rows := [
		["机体", character_name],
		["存活", _format_time(RunState.elapsed)],
		["等级", str(RunState.level)],
		["金币", str(RunState.gold)],
		["技能", "%d / %d" % [Skills.unlocked_count(), Skills.nodes.size()]],
		["遗物", "%d 件" % Skills.owned_relics.size()],
	]
	for i in rows.size():
		var baseline := rect.position.y + 52.0 + float(i) * 22.0
		_text(rows[i][0], Vector2(rect.position.x + 16.0, baseline), 10.5,
			Color(1.0, 1.0, 1.0, 0.36 * alpha))
		_text_right(rows[i][1], rect.end.x - 16.0, baseline, 12,
			Color(1.0, 1.0, 1.0, 0.84 * alpha), true)


func _draw_quick_hints(layout: Dictionary, alpha: float) -> void:
	var rect := _hints_rect(layout)
	draw_rect(rect, Color(0.034, 0.044, 0.065, 0.7 * alpha))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.045 * alpha), false, 1.0)
	_text("触屏操作" if GameInput.touch_controls_active else "快捷键",
		rect.position + Vector2(14.0, 18.0), 9,
		Color(1.0, 1.0, 1.0, 0.34 * alpha))
	var hints := [
		["Esc", "继续游戏"],
		["Tab", "切换页签"],
		["M", "音效开关"],
	]
	if GameInput.touch_controls_active:
		hints = [["点按", "选择操作"], ["拖动", "浏览列表"], ["返回", "继续游戏"]]
	for i in hints.size():
		var baseline := rect.position.y + 38.0 + float(i) * 18.0
		var key_color := Color(GOLD.r, GOLD.g, GOLD.b, 0.58 * alpha)
		_text(hints[i][0], Vector2(rect.position.x + 14.0, baseline), 8.5, key_color, true)
		_text(hints[i][1], Vector2(rect.position.x + 50.0, baseline), 9,
			Color(1.0, 1.0, 1.0, 0.42 * alpha))


func _draw_action_button(
	rect: Rect2,
	label: String,
	icon: int,
	hovered: bool,
	alpha: float,
	primary: bool = false,
	danger: bool = false
) -> void:
	var accent := GOLD
	if danger:
		accent = DANGER
	var fill := Color(0.055, 0.07, 0.10, 0.94 * alpha)
	if primary:
		fill = Color(0.10, 0.095, 0.065, 0.95 * alpha) if not hovered else Color(0.14, 0.125, 0.075, 0.98 * alpha)
	elif hovered:
		fill = Color(0.08, 0.09, 0.12, 0.98 * alpha)
	draw_rect(rect, fill)
	var border_alpha := 0.85 if primary else (0.58 if hovered else 0.20)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, border_alpha * alpha), false, 1.4 if hovered or primary else 1.0)
	if primary:
		draw_rect(
			Rect2(rect.position, Vector2(3.0, rect.size.y)),
			Color(accent.r, accent.g, accent.b, 0.95 * alpha)
		)

	var icon_center := rect.position + Vector2(23.0, rect.size.y * 0.5)
	_draw_menu_icon(icon, icon_center, 8.0, Color(accent.r, accent.g, accent.b, 0.88 * alpha))
	draw_string(
		_font,
		Vector2(rect.position.x + 40.0, rect.position.y + rect.size.y * 0.5 + 5.5),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 56.0,
		13.5 if primary else 13,
		Color(accent.r, accent.g, accent.b, 0.98 * alpha) if primary else Color(1.0, 1.0, 1.0, 0.82 * alpha),
	)
	if primary:
		draw_string(
			_font,
			Vector2(rect.end.x - 24.0, rect.position.y + rect.size.y * 0.5 + 5.0),
			"›",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			16,
			Color(accent.r, accent.g, accent.b, 0.68 * alpha)
		)


func _draw_settings(layout: Dictionary, alpha: float) -> void:
	var rect := _settings_rect(layout)
	draw_rect(rect, Color(0.045, 0.059, 0.088, 0.94 * alpha))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.07 * alpha), false, 1.0)
	draw_rect(
		Rect2(rect.position, Vector2(3.0, rect.size.y)),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.72 * alpha)
	)
	_text("声音", rect.position + Vector2(16.0, 23.0), 11,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.78 * alpha), true)

	var volume := Audio.volume()
	_text("主音量", rect.position + Vector2(16.0, 49.0), 11,
		Color(1.0, 1.0, 1.0, 0.66 * alpha))
	_text_right("%d%%" % int(round(volume * 100.0)), rect.end.x - 16.0, rect.position.y + 49.0, 12,
		Color(1.0, 1.0, 1.0, 0.84 * alpha), true)

	var bar := _volume_bar_rect(layout)
	draw_rect(bar, Color(1.0, 1.0, 1.0, 0.07 * alpha))
	var fill_color := Color(1.0, 1.0, 1.0, 0.28 * alpha) if Audio.is_muted() else Color(GOLD.r, GOLD.g, GOLD.b, 0.86 * alpha)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * volume, bar.size.y)), fill_color)
	var knob := Vector2(bar.position.x + bar.size.x * volume, bar.get_center().y)
	draw_circle(knob, 5.5, Color(0.045, 0.055, 0.075, alpha))
	draw_circle(knob, 5.5, fill_color, false, 1.4, true)

	var controls := _volume_button_rects(layout)
	_draw_small_button(controls[0], "−", _settings_hover == 0, alpha)
	_draw_small_button(controls[1], "+", _settings_hover == 1, alpha)

	var mute_rect := _mute_rect(layout)
	var mute_hovered := _settings_hover == 2
	draw_rect(mute_rect, Color(0.055, 0.07, 0.10, 0.92 * alpha))
	draw_rect(mute_rect, Color(1.0, 1.0, 1.0, 0.20 if mute_hovered else 0.07) * Color(1, 1, 1, alpha), false, 1.0)
	var state_text := "已静音" if Audio.is_muted() else "开启"
	_text("音效", mute_rect.position + Vector2(14.0, 25.0), 11,
		Color(1.0, 1.0, 1.0, 0.64 * alpha))
	_text_right(state_text, mute_rect.end.x - 14.0, mute_rect.position.y + 25.0, 11,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.82 * alpha) if not Audio.is_muted() else Color(1.0, 1.0, 1.0, 0.38 * alpha), true)
	var tip_rect := _settings_tip_rect(layout)
	if GameInput.touch_controls_active:
		var joystick_rect := _joystick_setting_rect(layout)
		draw_rect(joystick_rect, Color(0.055, 0.07, 0.10, 0.92 * alpha))
		draw_rect(joystick_rect,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha) if _settings_hover == 4
			else Color(1.0, 1.0, 1.0, 0.10 * alpha), false, 1.0)
		_text("虚拟摇杆", joystick_rect.position + Vector2(14.0, 25.0), 11,
			Color(1.0, 1.0, 1.0, 0.78 * alpha))
		_text_right("跟随" if GameInput.joystick_follow else "不跟随",
			joystick_rect.end.x - 14.0, joystick_rect.position.y + 25.0, 11,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.86 * alpha), true)
		_text("触点生成 · 默认不跟随", joystick_rect.position + Vector2(14.0, 49.0), 9,
			Color(1.0, 1.0, 1.0, 0.36 * alpha))
	draw_rect(tip_rect, Color(0.034, 0.044, 0.065, 0.68 * alpha))
	draw_rect(tip_rect, Color(1.0, 1.0, 1.0, 0.045 * alpha), false, 1.0)
	_text("点按" if GameInput.touch_controls_active else "M", tip_rect.position + Vector2(14.0, 19.0), 9,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.58 * alpha), true)
	_text("随时静音 / 取消静音", tip_rect.position + Vector2(38.0, 19.0), 9,
		Color(1.0, 1.0, 1.0, 0.40 * alpha))
	_text("音量与静音状态会自动保存", tip_rect.position + Vector2(14.0, 36.0), 8.5,
		Color(1.0, 1.0, 1.0, 0.24 * alpha))

	var back := _right_button_rects(layout, 1)[0]
	_draw_action_button(back, "返回菜单", 0, _settings_hover == 3, alpha, true)


func _draw_small_button(rect: Rect2, label: String, hovered: bool, alpha: float) -> void:
	draw_rect(rect, Color(0.075, 0.09, 0.12, 0.92 * alpha) if hovered else Color(0.045, 0.058, 0.085, 0.92 * alpha))
	draw_rect(rect, Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * alpha) if hovered else Color(1.0, 1.0, 1.0, 0.10 * alpha), false, 1.0)
	draw_string(_font, rect.position + Vector2(0.0, rect.size.y * 0.5 + 5.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16,
		Color(1.0, 0.92, 0.65, 0.88 * alpha))


func _draw_quit(layout: Dictionary, alpha: float) -> void:
	var rect := _quit_card_rect(layout)
	draw_rect(rect, Color(0.075, 0.040, 0.045, 0.92 * alpha))
	draw_rect(rect, Color(DANGER.r, DANGER.g, DANGER.b, 0.35 * alpha), false, 1.0)
	draw_rect(
		Rect2(rect.position, Vector2(3.0, rect.size.y)),
		Color(DANGER.r, DANGER.g, DANGER.b, 0.85 * alpha)
	)
	var icon_center := rect.position + Vector2(rect.size.x * 0.5, 42.0)
	draw_circle(icon_center, 20.0, Color(DANGER.r, DANGER.g, DANGER.b, 0.10 * alpha))
	draw_circle(icon_center, 20.0, Color(DANGER.r, DANGER.g, DANGER.b, 0.55 * alpha), false, 1.3, true)
	draw_line(icon_center + Vector2(0.0, -10.0), icon_center + Vector2(0.0, 4.0),
		Color(1.0, 0.65, 0.60, 0.95 * alpha), 2.0, true)
	draw_circle(icon_center + Vector2(0.0, 11.0), 1.6, Color(1.0, 0.65, 0.60, 0.95 * alpha))
	_text("返回主界面？", rect.position + Vector2(0.0, 88.0), 19,
		Color(1.0, 0.88, 0.84, 0.96 * alpha), true, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text("本局进度不会保存", rect.position + Vector2(0.0, 111.0), 10,
		Color(1.0, 1.0, 1.0, 0.46 * alpha), false, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text("确认后回到机体选择界面", rect.position + Vector2(0.0, 129.0), 9,
		Color(1.0, 1.0, 1.0, 0.28 * alpha), false, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)

	var buttons := _right_button_rects(layout, 2)
	_draw_action_button(buttons[0], "返回游戏", 0, _quit_hover == 0, alpha, true)
	_draw_action_button(buttons[1], "确认返回", 2, _quit_hover == 1, alpha, false, true)


func _draw_footer(layout: Dictionary, alpha: float) -> void:
	var card: Rect2 = layout["card"]
	var text := "点按选择 · 拖动浏览列表" if GameInput.touch_controls_active else \
		"Esc 返回 / 继续    Tab 切换    M 静音    滚轮 浏览列表"
	draw_string(
		_font,
		Vector2(card.position.x + 22.0, card.end.y - 9.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		8.5,
		Color(1.0, 1.0, 1.0, 0.22 * alpha)
	)
	_text_right("PAUSE  ·  BUILD OVERVIEW", card.end.x - 22.0, card.end.y - 9.0, 8,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.24 * alpha))


# ── 布局 ────────────────────────────────────────────────────────

func _panel_rect() -> Rect2:
	var margin := clampf(minf(size.x, size.y) * 0.04, 16.0, 40.0)
	var panel_size := Vector2(
		minf(size.x - margin * 2.0, 1500.0),
		minf(size.y - margin * 2.0, 900.0)
	)
	return Rect2((size - panel_size) * 0.5, panel_size)


func _layout() -> Dictionary:
	var card := _panel_rect()
	var pad := 22.0
	var header_h := 54.0
	var body_y := card.position.y + pad + header_h + 8.0
	var body_bottom := card.end.y - pad
	var right_w := clampf(card.size.x * 0.245, 260.0, 340.0)
	var left_x := card.position.x + pad
	var left_w := card.size.x - pad * 2.0 - right_w - 20.0
	var right_x := left_x + left_w + 20.0
	var tabs_y := body_y
	var tabs_h := 38.0
	var main_y := tabs_y + tabs_h + 10.0
	var detail_h := 92.0
	var detail_y := body_bottom - detail_h
	var main_h := detail_y - 10.0 - main_y
	return {
		"card": card,
		"pad": pad,
		"body_y": body_y,
		"body_bottom": body_bottom,
		"left_x": left_x,
		"left_w": left_w,
		"right_x": right_x,
		"right_w": right_w,
		"divider_x": left_x + left_w + 10.0,
		"tabs_y": tabs_y,
		"tabs_h": tabs_h,
		"main": Rect2(left_x, main_y, left_w, main_h),
		"detail": Rect2(left_x, detail_y, left_w, detail_h),
	}


func _tab_rects(layout: Dictionary) -> Array[Rect2]:
	var x: float = layout["left_x"]
	var y: float = layout["tabs_y"]
	var h: float = layout["tabs_h"]
	var w := minf(156.0, (layout["left_w"] as float - 16.0) / 3.0)
	return [
		Rect2(Vector2(x, y), Vector2(w, h)),
		Rect2(Vector2(x + w + 8.0, y), Vector2(w, h)),
		Rect2(Vector2(x + (w + 8.0) * 2.0, y), Vector2(w, h)),
	]


func _skill_grid(layout: Dictionary) -> Dictionary:
	var main: Rect2 = layout["main"]
	var columns := 3 if main.size.x < 1000.0 else 4
	var gap_x := 12.0
	var gap_y := 12.0
	var count := maxi(1, _branch_cache.size())
	var total_rows := int(ceil(float(count) / float(columns)))
	var visible_rows := clampi(total_rows, 1, 2)
	var col_w := (main.size.x - gap_x * float(columns - 1)) / float(columns)
	var row_h := (main.size.y - gap_y * float(visible_rows - 1)) / float(visible_rows)
	var step := row_h + gap_y
	return {
		"main": main,
		"columns": columns,
		"gap_x": gap_x,
		"gap_y": gap_y,
		"col_w": col_w,
		"row_h": row_h,
		"step": step,
		"total_rows": total_rows,
		"visible_rows": visible_rows,
		"max_scroll": maxf(0.0, float(total_rows - visible_rows) * step),
	}


func _branch_rect(layout: Dictionary, index: int) -> Rect2:
	var grid := _skill_grid(layout)
	var main: Rect2 = grid["main"]
	var columns := int(grid["columns"])
	var col := index % columns
	var row := index / columns
	return Rect2(
		main.position + Vector2(
			float(col) * (float(grid["col_w"]) + float(grid["gap_x"])),
			float(row) * float(grid["step"]) - _route_scroll
		),
		Vector2(float(grid["col_w"]), float(grid["row_h"]))
	)


func _node_radius(rect: Rect2) -> float:
	return clampf(rect.size.y * 0.09, 14.0, 22.0)


func _skill_node_center(layout: Dictionary, branch_index: int, tier_index: int) -> Vector2:
	var rect := _branch_rect(layout, branch_index)
	var body_top := rect.position.y + 40.0
	var body_h := maxf(40.0, rect.size.y - 50.0)
	var mid_y := body_top + body_h * 0.5
	var half_h := minf(body_h * 0.31, 104.0)
	var side := clampf(rect.size.x * 0.2, 46.0, 66.0)
	match tier_index:
		0:
			return Vector2(rect.position.x + side, mid_y)
		1:
			return Vector2(rect.position.x + rect.size.x * 0.5, mid_y - half_h)
		2:
			return Vector2(rect.position.x + rect.size.x * 0.5, mid_y + half_h)
		_:
			return Vector2(rect.end.x - side, mid_y)


func _branch_at(layout: Dictionary, point: Vector2) -> int:
	var main: Rect2 = layout["main"]
	if not main.has_point(point):
		return -1
	for i in _branch_cache.size():
		var rect := _branch_rect(layout, i)
		if rect.position.y < main.position.y - 0.5 or rect.end.y > main.end.y + 0.5:
			continue
		if rect.has_point(point):
			return i
	return -1


func _skill_node_at(layout: Dictionary, point: Vector2) -> Dictionary:
	var branch_index := _branch_at(layout, point)
	if branch_index < 0:
		return {}
	var rect := _branch_rect(layout, branch_index)
	var radius := _node_radius(rect) + 8.0
	for tier_index in 4:
		if point.distance_to(_skill_node_center(layout, branch_index, tier_index)) <= radius:
			return {
				"branch": branch_index,
				"tier": tier_index,
				"node": _branch_cache[branch_index]["nodes"][tier_index],
			}
	return {"branch": branch_index, "tier": -1}


func _right_button_rects(layout: Dictionary, count: int) -> Array[Rect2]:
	var x: float = layout["right_x"]
	var w: float = layout["right_w"]
	var bottom: float = layout["body_bottom"] - 28.0
	var height := 48.0
	var gap := 10.0
	var total := height * float(count) + gap * float(count - 1)
	var y := bottom - total
	var rects: Array[Rect2] = []
	for i in count:
		rects.append(Rect2(Vector2(x, y + float(i) * (height + gap)), Vector2(w, height)))
	return rects


func _summary_rect(layout: Dictionary) -> Rect2:
	return Rect2(
		Vector2(layout["right_x"], layout["body_y"] + 38.0),
		Vector2(layout["right_w"], 184.0)
	)


func _hints_rect(layout: Dictionary) -> Rect2:
	var summary := _summary_rect(layout)
	return Rect2(
		Vector2(summary.position.x, summary.end.y + 12.0),
		Vector2(summary.size.x, 98.0)
	)


func _settings_rect(layout: Dictionary) -> Rect2:
	return Rect2(
		Vector2(layout["right_x"], layout["body_y"] + 38.0),
		Vector2(layout["right_w"], 174.0)
	)


func _volume_bar_rect(layout: Dictionary) -> Rect2:
	var rect := _settings_rect(layout)
	return Rect2(
		Vector2(rect.position.x + 16.0, rect.position.y + 70.0),
		Vector2(rect.size.x - 32.0, 7.0)
	)


func _volume_button_rects(layout: Dictionary) -> Array[Rect2]:
	var bar := _volume_bar_rect(layout)
	var y := bar.position.y + 18.0
	return [
		Rect2(Vector2(bar.position.x, y), Vector2(36.0, 30.0)),
		Rect2(Vector2(bar.end.x - 36.0, y), Vector2(36.0, 30.0)),
	]


func _mute_rect(layout: Dictionary) -> Rect2:
	var settings := _settings_rect(layout)
	return Rect2(
		Vector2(settings.position.x + 16.0, settings.position.y + 126.0),
		Vector2(settings.size.x - 32.0, 40.0)
	)


func _settings_tip_rect(layout: Dictionary) -> Rect2:
	var settings := _settings_rect(layout)
	return Rect2(
		Vector2(settings.position.x, settings.end.y + (92.0 if GameInput.touch_controls_active else 12.0)),
		Vector2(settings.size.x, 50.0)
	)


func _joystick_setting_rect(layout: Dictionary) -> Rect2:
	var settings := _settings_rect(layout)
	return Rect2(Vector2(settings.position.x, settings.end.y + 12.0),
		Vector2(settings.size.x, 68.0))


func _quit_card_rect(layout: Dictionary) -> Rect2:
	return Rect2(
		Vector2(layout["right_x"], layout["body_y"] + 38.0),
		Vector2(layout["right_w"], 154.0)
	)


func _relic_grid_geometry(layout: Dictionary) -> Dictionary:
	var main: Rect2 = layout["main"]
	var columns := 4 if main.size.x >= 720.0 else 3
	var gap := 10.0
	var card_w := (main.size.x - gap * float(columns - 1)) / float(columns)
	var card_h := 78.0
	return {
		"main": main,
		"columns": columns,
		"gap": gap,
		"card_w": card_w,
		"card_h": card_h,
		"step": card_h + gap,
	}


func _relic_card_at(layout: Dictionary, point: Vector2) -> int:
	if _tab != 1:
		return -1
	var geometry := _relic_grid_geometry(layout)
	var main: Rect2 = geometry["main"]
	if not main.has_point(point):
		return -1
	for i in _relic_cache.size():
		var row := i / int(geometry["columns"])
		var col := i % int(geometry["columns"])
		var rect := Rect2(
			main.position + Vector2(
				float(col) * (float(geometry["card_w"]) + float(geometry["gap"])),
				float(row) * float(geometry["step"]) - _relic_scroll
			),
			Vector2(float(geometry["card_w"]), float(geometry["card_h"]))
		)
		if rect.has_point(point):
			return i
	return -1


# ── 输入 ────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			if _tab == 0:
				_scroll_routes(-1.0)
				accept_event()
			elif _tab == 1 and _relic_scroll_target > 0.0:
				_scroll_relics(-1.0)
				accept_event()
			elif _tab == 2:
				_damage_scroll = maxi(0, _damage_scroll - 1)
				queue_redraw()
				accept_event()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			if _tab == 0:
				_scroll_routes(1.0)
				accept_event()
			elif _tab == 1:
				_scroll_relics(1.0)
				accept_event()
			elif _tab == 2:
				_damage_scroll += 1
				queue_redraw()
				accept_event()
		elif mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_click(mouse.position)


func _update_hover(point: Vector2) -> void:
	var layout := _layout()
	_tab_hover = -1
	_menu_hover = -1
	_settings_hover = -1
	_quit_hover = -1
	_branch_hover = -1
	_skill_hover = &""
	_relic_hover = &""

	if _screen == Screen.MENU:
		var tabs := _tab_rects(layout)
		for i in tabs.size():
			if tabs[i].has_point(point):
				_tab_hover = i
		var buttons := _right_button_rects(layout, 3)
		for i in buttons.size():
			if buttons[i].has_point(point):
				_menu_hover = i
	elif _screen == Screen.SETTINGS:
		var volume_buttons := _volume_button_rects(layout)
		for i in volume_buttons.size():
			if volume_buttons[i].has_point(point):
				_settings_hover = i
		if _mute_rect(layout).has_point(point):
			_settings_hover = 2
		if GameInput.touch_controls_active and _joystick_setting_rect(layout).has_point(point):
			_settings_hover = 4
		if _right_button_rects(layout, 1)[0].has_point(point):
			_settings_hover = 3
	else:
		var buttons := _right_button_rects(layout, 2)
		for i in buttons.size():
			if buttons[i].has_point(point):
				_quit_hover = i

	if _tab == 0 and _screen == Screen.MENU:
		var hit := _skill_node_at(layout, point)
		if not hit.is_empty():
			_branch_hover = int(hit["branch"])
			if int(hit["tier"]) >= 0:
				var node := hit["node"] as SkillNodeResource
				_skill_hover = node.id
				_focus_skill_id = node.id
	elif _tab == 1 and _screen == Screen.MENU:
		var relic_index := _relic_card_at(layout, point)
		if relic_index >= 0:
			var relic := _relic_cache[relic_index]["relic"] as RelicResource
			_relic_hover = relic.id
			_focus_relic_id = relic.id


func _click(point: Vector2) -> void:
	var layout := _layout()

	if _screen == Screen.SETTINGS:
		var volume_buttons := _volume_button_rects(layout)
		for i in volume_buttons.size():
			if volume_buttons[i].has_point(point):
				accept_event()
				_adjust_volume(-0.1 if i == 0 else 0.1)
				return
		var bar := _volume_bar_rect(layout)
		var bar_hit := Rect2(bar.position - Vector2(0.0, 8.0), bar.size + Vector2(0.0, 16.0))
		if bar_hit.has_point(point):
			accept_event()
			if Audio.is_muted():
				Audio.set_muted(false)
			Audio.set_volume(clampf((point.x - bar.position.x) / bar.size.x, 0.0, 1.0))
			Audio.play(&"ui_click")
			queue_redraw()
			return
		if _mute_rect(layout).has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			Audio.toggle_muted()
			queue_redraw()
			return
		if GameInput.touch_controls_active and _joystick_setting_rect(layout).has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			GameInput.set_joystick_follow(not GameInput.joystick_follow)
			queue_redraw()
			return
		if _right_button_rects(layout, 1)[0].has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			_screen = Screen.MENU
			queue_redraw()
			return
		return

	if _screen == Screen.QUIT:
		var buttons := _right_button_rects(layout, 2)
		if buttons[0].has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			_screen = Screen.MENU
			queue_redraw()
		elif buttons[1].has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			menu_requested.emit()
		return

	var tabs := _tab_rects(layout)
	for i in tabs.size():
		if tabs[i].has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			_tab = i
			_route_scroll = 0.0
			_route_scroll_target = 0.0
			_relic_scroll = 0.0
			_relic_scroll_target = 0.0
			queue_redraw()
			return

	var buttons := _right_button_rects(layout, 3)
	for i in buttons.size():
		if buttons[i].has_point(point):
			accept_event()
			Audio.play(&"ui_click")
			match i:
				0:
					_resume()
				1:
					_screen = Screen.SETTINGS
					queue_redraw()
				2:
					_screen = Screen.QUIT
					queue_redraw()
			return

	if _tab == 0:
		var hit := _skill_node_at(layout, point)
		if not hit.is_empty() and int(hit["tier"]) >= 0:
			accept_event()
			Audio.play(&"ui_click")
			var node := hit["node"] as SkillNodeResource
			_focus_skill_id = node.id
			queue_redraw()

	elif _tab == 1:
		var relic_index := _relic_card_at(layout, point)
		if relic_index >= 0:
			accept_event()
			Audio.play(&"ui_click")
			_focus_relic_id = (_relic_cache[relic_index]["relic"] as RelicResource).id
			queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	if key.keycode == KEY_M:
		Audio.play(&"ui_click")
		Audio.toggle_muted()
		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if _screen == Screen.SETTINGS:
		match key.keycode:
			KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
				Audio.play(&"ui_click")
				_screen = Screen.MENU
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				_adjust_volume(-0.1)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_adjust_volume(0.1)
				get_viewport().set_input_as_handled()
		return

	if _screen == Screen.QUIT:
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			Audio.play(&"ui_click")
			_screen = Screen.MENU
			queue_redraw()
			get_viewport().set_input_as_handled()
		return

	if key.keycode == KEY_TAB:
		_tab = (_tab + 1) % 3
		_route_scroll = 0.0
		_route_scroll_target = 0.0
		_relic_scroll = 0.0
		_relic_scroll_target = 0.0
		Audio.play(&"ui_click")
		queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_resume()
		get_viewport().set_input_as_handled()


func _adjust_volume(delta: float) -> void:
	if Audio.is_muted():
		Audio.set_muted(false)
	Audio.set_volume(clampf(snappedf(Audio.volume() + delta, 0.05), 0.0, 1.0))
	Audio.play(&"ui_click")
	queue_redraw()


func _scroll_routes(direction: float) -> void:
	var grid := _skill_grid(_layout())
	var step := float(grid["step"])
	var max_scroll := float(grid["max_scroll"])
	_route_scroll_target = clampf(_route_scroll_target + direction * step, 0.0, max_scroll)
	queue_redraw()


func _scroll_relics(direction: float) -> void:
	var geometry := _relic_grid_geometry(_layout())
	var main: Rect2 = geometry["main"]
	var columns := int(geometry["columns"])
	var total_rows := int(ceil(float(_relic_cache.size()) / float(columns)))
	var visible_rows := int(floor((main.size.y + float(geometry["gap"])) / float(geometry["step"])))
	var max_scroll := maxf(0.0, float(total_rows - visible_rows) * float(geometry["step"]))
	_relic_scroll_target = clampf(
		_relic_scroll_target + direction * float(geometry["step"]), 0.0, max_scroll
	)
	queue_redraw()


## 快速缓动；足够接近时直接吸附，避免长时间停在亚像素位置。
func _approach(current: float, target: float, weight: float) -> float:
	var value := lerpf(current, target, weight)
	if absf(target - value) < 0.05:
		return target
	return value


func _resume() -> void:
	Audio.play(&"ui_click")
	close()
	closed.emit()


# ── 小工具 ──────────────────────────────────────────────────────

func _skill_state(node: SkillNodeResource) -> Dictionary:
	if Skills.is_unlocked(node.id):
		return {"text": "已解锁", "color": node.accent}
	for prerequisite in node.prerequisites:
		if not Skills.is_unlocked(prerequisite):
			return {"text": "前置未解锁", "color": Color(1.0, 1.0, 1.0, 0.38)}
	if node.branch == &"demon" and Skills.is_unlocked(&"path_angel_1"):
		return {"text": "阵营冲突", "color": DANGER}
	if node.branch == &"angel" and Skills.is_unlocked(&"path_demon_1"):
		return {"text": "阵营冲突", "color": DANGER}
	if Skills.is_available(node):
		return {"text": "可解锁", "color": GOLD}
	return {"text": "未解锁", "color": Color(1.0, 1.0, 1.0, 0.38)}


func _find_relic(relic_id: StringName) -> RelicResource:
	for entry in _relic_cache:
		var relic := entry["relic"] as RelicResource
		if relic.id == relic_id:
			return relic
	return null


func _relic_accent(relic: RelicResource) -> Color:
	if relic.side == &"demon":
		return Color(1.0, 0.24, 0.28)
	if relic.side == &"angel":
		return Color(1.0, 0.86, 0.42)
	match relic.rarity:
		RelicResource.RARITY_RARE:
			return Color(0.45, 0.72, 1.0)
		RelicResource.RARITY_EPIC:
			return Color(0.75, 0.45, 1.0)
		RelicResource.RARITY_LEGENDARY:
			return Color(1.0, 0.65, 0.25)
		RelicResource.RARITY_IRIDESCENT:
			var rainbow := Color.from_hsv(fmod(_time * 0.18, 1.0), 0.55, 1.0)
			return Color(rainbow.r * 1.5, rainbow.g * 1.5, rainbow.b * 1.5)
		RelicResource.RARITY_CURSED:
			return Color(1.0, 0.25, 0.3)
		_:
			return Color(0.76, 0.70, 0.58)


func _rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func _relic_tag_text(relic: RelicResource) -> String:
	var tags: Array[String] = []
	if relic.side == &"demon":
		tags.append("恶魔")
	elif relic.side == &"angel":
		tags.append("天使")
	if relic.unique:
		tags.append("唯一")
	if relic.chest_only:
		tags.append("宝箱")
	if relic.lucky:
		tags.append("幸运")
	if relic.max_stacks > 0:
		tags.append("上限 %d" % relic.max_stacks)
	if tags.is_empty():
		tags.append("遗物")
	return " · ".join(tags)


func _draw_relic_gem(center: Vector2, radius: float, color: Color, side: StringName, alpha: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 0.78, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius * 0.78, 0.0),
		center + Vector2(0.0, -radius),
	])
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius * 0.78, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius * 0.78, 0.0),
		]),
		Color(color.r, color.g, color.b, 0.14 * alpha)
	)
	draw_polyline(points, Color(color.r, color.g, color.b, 0.82 * alpha), 1.3, true)
	draw_line(
		center + Vector2(-radius * 0.52, 0.0),
		center + Vector2(radius * 0.52, 0.0),
		Color(color.r, color.g, color.b, 0.30 * alpha),
		1.0
	)
	if side == &"demon":
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0.0, radius * 0.28),
			center + Vector2(-radius * 0.26, -radius * 0.18),
			center + Vector2(radius * 0.26, -radius * 0.18),
		]), Color(color.r, color.g, color.b, 0.85 * alpha))
	elif side == &"angel":
		draw_arc(center + Vector2(0.0, -radius * 0.08), radius * 0.30,
			PI, TAU, 12, Color(color.r, color.g, color.b, 0.88 * alpha), 1.4, true)
		draw_line(center + Vector2(0.0, radius * 0.05), center + Vector2(0.0, radius * 0.42),
			Color(color.r, color.g, color.b, 0.88 * alpha), 1.4, true)
	else:
		draw_circle(center, radius * 0.17, Color(color.r, color.g, color.b, 0.80 * alpha))


func _draw_menu_icon(kind: int, center: Vector2, radius: float, color: Color) -> void:
	match kind:
		0:
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-radius * 0.45, -radius * 0.72),
				center + Vector2(radius * 0.72, 0.0),
				center + Vector2(-radius * 0.45, radius * 0.72),
			]), color)
		1:
			for i in 3:
				var y := center.y + (-radius * 0.62 + float(i) * radius * 0.62)
				draw_line(Vector2(center.x - radius * 0.82, y), Vector2(center.x + radius * 0.82, y),
					color, 1.2, true)
				var knob_x := center.x + (-radius * 0.36 if i == 0 else (radius * 0.42 if i == 1 else 0.0))
				draw_circle(Vector2(knob_x, y), 2.1, color)
		2:
			draw_line(Vector2(center.x - radius * 0.72, center.y - radius * 0.72),
				Vector2(center.x + radius * 0.18, center.y - radius * 0.72), color, 1.5, true)
			draw_line(Vector2(center.x - radius * 0.72, center.y - radius * 0.72),
				Vector2(center.x - radius * 0.72, center.y + radius * 0.72), color, 1.5, true)
			draw_line(Vector2(center.x - radius * 0.72, center.y + radius * 0.72),
				Vector2(center.x + radius * 0.18, center.y + radius * 0.72), color, 1.5, true)
			draw_line(Vector2(center.x - radius * 0.10, center.y),
				Vector2(center.x + radius * 0.72, center.y), color, 1.5, true)
			draw_line(Vector2(center.x + radius * 0.38, center.y - radius * 0.34),
				Vector2(center.x + radius * 0.72, center.y), color, 1.5, true)
			draw_line(Vector2(center.x + radius * 0.38, center.y + radius * 0.34),
				Vector2(center.x + radius * 0.72, center.y), color, 1.5, true)


func _text(
	text: String,
	position: Vector2,
	font_size: int,
	color: Color,
	bold: bool = false,
	width: float = -1.0,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	var font: Font = _bold_font if bold and _bold_font != null else _font
	draw_string(font, position, text, alignment, width, font_size, color)


func _text_right(text: String, right_x: float, baseline_y: float, font_size: int,
	color: Color, bold: bool = false) -> void:
	var font: Font = _bold_font if bold and _bold_font != null else _font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(font, Vector2(right_x - width, baseline_y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _text_width(text: String, font_size: int, bold: bool = false) -> float:
	var font: Font = _bold_font if bold and _bold_font != null else _font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]

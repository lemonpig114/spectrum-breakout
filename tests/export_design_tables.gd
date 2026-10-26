extends Node

## 从正式资源更新根目录两张策划表；按 id 保留“策划备注”列。
const SKILL_PATH := "res://技能设计表.md"
const RELIC_PATH := "res://遗物设计表.md"


func _ready() -> void:
	var skills := SkillCatalog.build()
	var relics := SkillCatalog.build_relics()
	if skills.size() != 76 or relics.size() != 51:
		push_error("设计表导出中止：技能/遗物数量与预期不符")
		get_tree().quit(1)
		return
	_write_skills(skills)
	_write_relics(relics)
	print("DESIGN TABLES EXPORTED skills=%d relics=%d" % [skills.size(), relics.size()])
	get_tree().quit()


func _write_skills(skills: Array[SkillNodeResource]) -> void:
	var notes := _read_notes(SKILL_PATH)
	var lines := PackedStringArray([
		"# 技能设计表（当前实装）",
		"",
		"> 数据源：`scripts/skills/SkillCatalog.gd`。运行 `res://tests/export_design_tables.tscn` 可在数值改动后刷新；脚本按 ID 保留最后一列的策划备注。详解见 `docs/SKILLS.md`。",
		"> 当前 19 条路线、76 项技能；一阶无前置，二/三阶只需一阶，四阶需二阶与三阶。",
		"",
		"| 路线 | 阶 | ID | 名称 | 前置 | 游戏内当前效果 | 策划备注 |",
		"| --- | ---: | --- | --- | --- | --- | --- |",
	])
	for skill in skills:
		var prerequisite_names := PackedStringArray()
		for id in skill.prerequisites:
			prerequisite_names.append(String(id))
		var prereqs := "—" if prerequisite_names.is_empty() else "、".join(prerequisite_names)
		lines.append("| %s | %d | `%s` | %s | %s | %s | %s |" % [
			_cell(skill.branch_name), skill.tier, skill.id, _cell(skill.display_name),
			_cell(prereqs), _cell(skill.description), notes.get(String(skill.id), "")
		])
	_write(SKILL_PATH, "\n".join(lines) + "\n")


func _write_relics(relics: Array[RelicResource]) -> void:
	var notes := _read_notes(RELIC_PATH)
	var rarity_names := ["尘灰", "微光", "炬火", "璀璨", "幻彩", "诅咒"]
	var lines := PackedStringArray([
		"# 遗物设计表（当前实装）",
		"",
		"> 数据源：`scripts/skills/SkillCatalog.gd`。运行 `res://tests/export_design_tables.tscn` 可在数值改动后刷新；脚本按 ID 保留最后一列的策划备注。完整结算与获取规则见 `docs/RELICS.md`。",
		"> 当前 51 件；基础价格会随局内时间增长。拾取条显示短句，详细数值以当前效果列为准。",
		"",
		"| 品质 | ID | 名称 | 来源限制 | 基础价 | 持有上限 | 当前效果 | 拾取短句 | 策划备注 |",
		"| --- | --- | --- | --- | ---: | --- | --- | --- | --- |",
	])
	for relic in relics:
		var source := "普通"
		if relic.side != &"":
			source = "恶魔" if relic.side == &"demon" else "天使"
		elif relic.chest_only:
			source = "仅宝箱"
		elif relic.lucky:
			source = "幸运一阶后"
		var cap := "唯一" if relic.unique else ("%d 件" % relic.max_stacks if relic.max_stacks > 0 else "不限")
		if relic.consumable:
			cap = "消耗品"
		lines.append("| %s | `%s` | %s | %s | %d | %s | %s | %s | %s |" % [
			rarity_names[relic.rarity], relic.id, _cell(relic.display_name), source,
			relic.price, cap, _cell(relic.description), _cell(relic.brief_description),
			notes.get(String(relic.id), "")
		])
	_write(RELIC_PATH, "\n".join(lines) + "\n")


func _cell(value: String) -> String:
	return value.replace("\r", "").replace("\n", "<br>").replace("|", "／")


func _read_notes(path: String) -> Dictionary:
	var notes := {}
	if not FileAccess.file_exists(path):
		return notes
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.begins_with("|") or not line.contains("`"):
			continue
		var parts := line.split("|")
		if parts.size() < 4:
			continue
		var note := parts[parts.size() - 2].strip_edges()
		for part in parts:
			var field := part.strip_edges()
			if field.begins_with("`") and field.ends_with("`"):
				notes[field.trim_prefix("`").trim_suffix("`")] = note
				break
	return notes


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入设计表：%s" % path)
		return
	file.store_string(contents)

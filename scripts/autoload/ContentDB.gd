extends Node

## 启动时扫描 res://data 下的 Resource，建立 id -> Resource 索引。
## 所有内容（武器/敌人/技能/遗物/融合规则）都从这里取，便于后续换成数据库或 Mod。

var _items: Dictionary = {}


func _ready() -> void:
	_scan_directory("res://data")


func get_data(id: StringName) -> Resource:
	return _items.get(id)


func get_weapon(id: StringName) -> WeaponCoreResource:
	return _items.get(id) as WeaponCoreResource


func get_enemy(id: StringName) -> EnemyTypeResource:
	return _items.get(id) as EnemyTypeResource


func get_character(id: StringName) -> CharacterResource:
	return _items.get(id) as CharacterResource


## 按 order 排序，角色选择界面直接使用。
func get_characters() -> Array[CharacterResource]:
	var result: Array[CharacterResource] = []
	for resource in _items.values():
		if resource is CharacterResource and resource.id == &"prism":
			result.append(resource)
	result.sort_custom(func(a: CharacterResource, b: CharacterResource) -> bool:
		return a.order < b.order
	)
	return result


func get_enemies() -> Array[EnemyTypeResource]:
	var result: Array[EnemyTypeResource] = []
	for resource in _items.values():
		if resource is EnemyTypeResource:
			result.append(resource)
	return result


func get_upgrades() -> Array[UpgradeOptionResource]:
	var result: Array[UpgradeOptionResource] = []
	for resource in _items.values():
		if resource is UpgradeOptionResource:
			result.append(resource)
	return result


func has(id: StringName) -> bool:
	return _items.has(id)


func all_ids() -> Array:
	return _items.keys()


func _scan_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue

		var full_path := path.path_join(entry)
		if directory.current_is_dir():
			_scan_directory(full_path)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			_load_resource(full_path)

		entry = directory.get_next()

	directory.list_dir_end()


func _load_resource(path: String) -> void:
	var resource := load(path)
	if resource == null:
		push_error("ContentDB: failed to load %s" % path)
		return

	var id_value = resource.get("id")
	if id_value == null or String(id_value).is_empty():
		push_warning("ContentDB: resource has no id: %s" % path)
		return

	var key := StringName(id_value)
	if _items.has(key):
		push_error("ContentDB: duplicate id '%s' at %s" % [key, path])
		return

	_items[key] = resource

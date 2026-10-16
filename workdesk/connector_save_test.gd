extends SceneTree

var failures = 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var main = load("res://world/main.gd").new()
	var serializer = load("res://save_manager.gd").new()
	var equipment = EquipmentComponent.new()
	root.add_child(equipment)
	var colors = ["red", "blue", "yellow", "purple"]
	var saved_items = []
	for row in range(4):
		for column in range(2):
			var item = BaseItem.new("test", "保存用装備", null, EquipmentSlot.EquipmentType.WEAPON)
			item.shape.assign([Vector2i.ZERO])
			item.connectors.append({"cell": Vector2i.ZERO, "direction": Vector2i.RIGHT if column == 0 else Vector2i.LEFT, "color": colors[row]})
			equipment.equipment_data.place_item(item, column, row)
			saved_items.append(serializer._serialize_item(item))
	var before = equipment.get_connector_effects()
	var config = ConfigFile.new()
	config.set_value("test", "items", saved_items)
	config.save("res://workdesk/connector_roundtrip.cfg")
	var loaded = ConfigFile.new()
	loaded.load("res://workdesk/connector_roundtrip.cfg")
	equipment.equipment_data.clear()
	for data in loaded.get_value("test", "items"):
		var restored = main._deserialize_item(data)
		check(restored.connectors == data.connectors, "ConfigFile changed connector location/direction/color")
		restored.ensure_connectors()
		check(restored.connectors == data.connectors, "UI initialization regenerated saved connectors")
		equipment.equipment_data.add_item(restored)
	check(equipment.get_connector_effects() == before, "Restored equipment connection effects changed")
	var generated = EquipmentGenerator.enhance_item(ItemDatabase.get_item_by_id("fire_sword"), 10)
	for rotation in range(4):
		generated.rotate()
		var data = serializer._serialize_item(generated)
		var restored = main._deserialize_item(data)
		check(restored.shape == generated.shape and restored.connectors == generated.connectors, "Rotated generated gear layout changed")
	var empty = BaseItem.new("empty_test", "端子なし装備", null, EquipmentSlot.EquipmentType.WEAPON)
	empty.shape.assign([Vector2i.ZERO])
	empty.attack = 5
	empty.connectors_initialized = true
	var restored_empty = main._deserialize_item(serializer._serialize_item(empty))
	check(restored_empty.connectors.is_empty(), "Empty connector layout regenerated on load")
	var legacy = {"id": "rusty_sword", "equipment_type": 3, "attack": 2, "shape": [Vector2i.ZERO], "grid_x": 1, "grid_y": 2}
	var first = main._deserialize_item(legacy)
	for index in range(20): randf()
	var second = main._deserialize_item(legacy)
	check(not first.connectors.is_empty() and first.connectors == second.connectors, "Legacy reconstruction changes across loads")
	var potion = ItemDatabase.get_item_by_id("potion_double")
	potion.connectors.append({"cell": Vector2i.ZERO, "direction": Vector2i.UP, "color": "red"})
	check(main._deserialize_item(serializer._serialize_item(potion)).connectors.is_empty(), "Consumable retained connectors")
	main.free()
	serializer.free()
	print("CONNECTOR_SAVE_TEST failures=", failures)
	quit(1 if failures else 0)

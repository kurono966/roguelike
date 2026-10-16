extends SceneTree

var failures = 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var equipment = EquipmentComponent.new()
	root.add_child(equipment)
	for item in ItemDatabase.get_all_items():
		var enhanced = EquipmentGenerator.enhance_item(item, 10)
		if item.equipment_type == -1:
			check(not enhanced.is_equippable(), item.id + " became equipment")
			check(enhanced.id == item.id, item.id + " received equipment affixes")
			enhanced.connectors.append({"cell": Vector2i.ZERO, "direction": Vector2i.UP, "color": "red"})
			enhanced.ensure_connectors()
			check(enhanced.connectors.is_empty(), item.id + " retained connectors")
			check(not equipment.equip_item(enhanced), item.id + " equipped via helper")
			check(not equipment.equipment_data.place_item(enhanced, 0, 0), item.id + " equipped via grid/drop")
			check(equipment.add_to_bag(enhanced), item.id + " could not enter bag")
			equipment.bag_data.clear()
		else:
			check(enhanced.is_equippable(), item.id + " lost equipment type")
			check(equipment.equip_item(enhanced), item.id + " could not equip")
			equipment.equipment_data.clear()
	var main = load("res://world/main.gd").new()
	var old_potion = main._deserialize_item({"id": "potion_double_generated_123", "name": "Old potion", "equipment_type": -1, "attack": 50, "shape": [Vector2i.ZERO]})
	check(old_potion.id == "potion_double" and old_potion.attack == 0, "Old generated potion not repaired")
	check(old_potion.effects.has("spawn_shadow") and old_potion.connectors.is_empty(), "Old potion lost use effect")
	var potion = main._deserialize_item({"id": "potion", "shape": [Vector2i.ZERO]})
	check(potion.heal > 0 and not potion.is_equippable(), "Loaded potion lost healing/type")
	main.free()
	print("ITEM_TYPE_TEST failures=", failures)
	quit(1 if failures else 0)

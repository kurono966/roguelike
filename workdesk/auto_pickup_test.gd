extends Node

var failures = 0

func _ready():
	call_deferred("_run")

func _check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _run():
	var main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_tree().get_nodes_in_group(group):
			actor.queue_free()
	await get_tree().process_frame
	main._is_on_world_map = false
	main._traps.clear()
	main._burning_grass.clear()
	main.player.equipment_component.equipment_data.items.clear()
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT):
			main._map_data[x][y] = main.CellType.WALL
			main._explored_tiles[x][y] = true
	for x in range(23, 30):
		for y in range(23, 30):
			main._map_data[x][y] = main.CellType.FLOOR
	main._setup_pathfinding()
	# Legacy item placements and saved floors include a visual -4px offset.
	for offset in [Vector2(0, -4), Vector2.ZERO]:
		main.player.position = Vector2(25, 25) * 32
		var item = load("res://items/world_item.tscn").instantiate()
		item.position = Vector2(27, 25) * 32 + offset
		item.set_item(ItemDatabase.get_item_by_id("potion").duplicate(true))
		item.add_to_group("items")
		item.add_to_group("entities")
		main.add_child(item)
		var path = main._find_path_to_nearest_visible_item(Vector2i(25, 25))
		_check(not path.is_empty() and Vector2i(path.back()) == Vector2i(27, 25), "Item target is on the wrong tile: " + str(offset))
		main._current_game_state = main.TurnPhase.PLAYER_TURN
		main._is_processing_action = false
		main._is_auto_exploring = true
		main._auto_explore_path.clear()
		main._auto_explore_index = 0
		for step in range(12):
			if not is_instance_valid(item) or item.is_queued_for_deletion():
				break
			main._auto_move_cooldown = 0
			await main._continue_auto_explore()
			await get_tree().create_timer(0.15).timeout
		_check(not is_instance_valid(item) or item.is_queued_for_deletion(), "Auto explore looped without picking up item: " + str(offset))
		main._stop_auto_explore()
		if is_instance_valid(item):
			item.queue_free()
		await get_tree().process_frame
	# A failed pickup must not attract subsequent paths, even after restarting
	# exploration or freeing bag space. Other items of the same type still count.
	var bag = main.player.equipment_component.bag_data
	bag.clear()
	var blocker = BaseItem.new("test_blocker", "Full bag", null, -1, 10, 4)
	_check(bag.place_item(blocker, 0, 0), "Could not fill bag")
	main.player.position = Vector2(26, 25) * 32
	var failed = load("res://items/world_item.tscn").instantiate()
	failed.position = Vector2(27, 25) * 32
	failed.set_item(ItemDatabase.get_item_by_id("potion").duplicate(true))
	failed.add_to_group("items")
	main.add_child(failed)
	main._is_auto_exploring = true
	await main._try_move_character(main.player, Vector2.RIGHT)
	_check(failed.item_data.auto_pickup_ignored, "Movement pickup failure was not remembered")
	main._auto_pickup_items_at_feet()
	_check(main._is_auto_exploring, "Full bag stopped exploration")
	main._stop_auto_explore()
	bag.clear()
	main.player.position = Vector2(25, 25) * 32
	_check(main._find_path_to_nearest_visible_item(Vector2i(25, 25)).is_empty(), "Failed item was targeted again")
	var other = load("res://items/world_item.tscn").instantiate()
	other.position = Vector2(28, 25) * 32
	other.set_item(ItemDatabase.get_item_by_id("potion").duplicate(true))
	other.add_to_group("items")
	main.add_child(other)
	var next = main._find_path_to_nearest_visible_item(Vector2i(25, 25))
	_check(not next.is_empty() and Vector2i(next.back()) == Vector2i(28, 25), "Ignoring one potion ignored other potions")
	var serializer = load("res://save_manager.gd").new()
	var restored = main._deserialize_item(serializer._serialize_item(failed.item_data))
	_check(restored.auto_pickup_ignored, "Save/load forgot ignored item")
	serializer.free()
	_check(main.player.pickup_item(failed.item_data), "Ignored item could not be manually picked up")
	_check(not failed.item_data.auto_pickup_ignored, "Manual pickup did not reset ignored state")
	failed.queue_free()
	other.queue_free()
	print("AUTO_PICKUP_TEST failures=", failures)
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

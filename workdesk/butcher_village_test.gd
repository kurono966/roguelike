extends SceneTree

var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	for entity in get_nodes_in_group("entities"):
		if entity != main.player: entity.queue_free()
	await process_frame
	main._is_on_world_map = false
	main.current_floor = 1
	for x in range(20, 31):
		for y in range(20, 31): main._map_data[x][y] = main.CellType.FLOOR
	main.player.position = Vector2(25, 25) * 32
	main._calculate_fov()
	var manager = main.corpse_manager
	var adjacent = manager.add_corpse("goblin", "小鬼", Vector2(26, 25) * 32)
	var underfoot = manager.add_corpse("bat", "コウモリ", main.player.position)
	var distant = manager.add_corpse("goblin", "小鬼", Vector2(29, 25) * 32)
	check(manager.butcher_near_player(), "Butchering failed")
	check(not manager.corpses.has(underfoot) and manager.corpses.has(adjacent), "Did not prefer corpse underfoot")
	check(manager.corpses.has(distant), "Consumed distant corpse")
	var meat_count = 0
	for item in get_nodes_in_group("items"):
		if item.item_data.id == "butchered_meat":
			meat_count += 1
			check(item.item_data.restore_hunger == 20 and not item.item_data.is_equippable(), "Meat is not valid food")
	check(meat_count == 1, "Wrong meat yield")
	var turn_before = main._turn_count
	var gold_before = main.player.gold
	await main._handle_butcher()
	check(main._turn_count == turn_before + 1 and main.player.last_action_id == "butcher", "Butcher did not consume exactly one turn")
	check(main.player.gold == gold_before and not manager.corpses.has(adjacent), "Butcher changed gold or left corpse")
	turn_before = main._turn_count
	await main._handle_butcher()
	check(main._turn_count == turn_before, "No-corpse attempt consumed a turn")
	check(not main.has_method("_handle_shop_purchase") and not root.get_node("GameUI").has_method("open_trade_menu"), "Trade entry points remain")
	main._change_floor(6, 0, false)
	await process_frame
	check(get_nodes_in_group("enemies").is_empty(), "Hostile spawned on village floor")
	check(not get_nodes_in_group("npcs").is_empty(), "Village has no NPCs")
	for npc in get_nodes_in_group("npcs"):
		check(npc.is_npc and not npc.is_in_group("enemies"), "Village NPC is hostile")
	main._try_spawn_periodic_enemy()
	main.enemy_manager.try_spawn_periodic_enemy()
	check(get_nodes_in_group("enemies").is_empty(), "Periodic spawn added village hostile")
	print("BUTCHER_VILLAGE_TEST failures=", failures)
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)

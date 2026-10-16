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
	main.player.equipment_component.equipment_data.clear()
	for x in range(20, 31):
		for y in range(20, 31): main._map_data[x][y] = main.CellType.FLOOR
	main.player.position = Vector2(25, 25) * 32
	main._calculate_fov()
	var manager = main.corpse_manager
	var player = main.player
	player.strength = 1
	player.dexterity = 1
	player.intelligence = 1
	var basic = manager.get_butchery_stats(player)
	check(basic.turns == 30 and is_equal_approx(basic.success, 0.5) and is_equal_approx(basic.special, 0.02), "Basic rates changed")
	player.strength = 15
	player.dexterity = 8
	player.intelligence = 10
	var improved = manager.get_butchery_stats(player)
	check(improved.turns == 16 and improved.success > basic.success and improved.special > basic.special, "Attributes did not improve butchering")
	player.strength = 100
	player.dexterity = 100
	player.intelligence = 100
	var capped = manager.get_butchery_stats(player)
	check(capped.turns == 1 and capped.success == 0.95 and capped.special == 0.5, "Caps incorrect")
	var corpse = manager.add_corpse("goblin", "小鬼", player.position)
	check(manager.finish_butchering(corpse, {"success": 1.0, "special": 1.0}), "Successful roll failed")
	var found_special = false
	for item in get_nodes_in_group("items"):
		if item.item_data.id == "prime_meat": found_special = item.item_data.restore_hunger == 60
	check(found_special, "Special item not generated")
	corpse = manager.add_corpse("goblin", "小鬼", player.position)
	var count_before = get_nodes_in_group("items").size()
	check(not manager.finish_butchering(corpse, {"success": 0.0, "special": 1.0}), "Failed roll succeeded")
	check(not manager.corpses.has(corpse) and get_nodes_in_group("items").size() == count_before, "Failure left corpse or generated loot")
	player.strength = 1
	player.hunger = 100
	corpse = manager.add_corpse("goblin", "小鬼", player.position)
	var before = main._turn_count
	await main._handle_butcher()
	check(main._turn_count - before == 30, "Weak player did not spend 30 turns")
	check(not manager.corpses.has(corpse) and not main._is_butchering and not main._is_processing_action, "Completed task not cleaned up")
	corpse = manager.add_corpse("goblin", "小鬼", player.position)
	before = main._turn_count
	create_timer(0.18).timeout.connect(func(): main._is_butchering = false)
	await main._handle_butcher()
	check(main._turn_count > before and main._turn_count - before < 30 and manager.corpses.has(corpse), "Cancel did not preserve corpse and spent turns")
	before = main._turn_count
	create_timer(0.18).timeout.connect(func(): player.take_damage(1))
	await main._handle_butcher()
	check(main._turn_count - before < 30 and manager.corpses.has(corpse), "Damage did not interrupt work")
	before = main._turn_count
	create_timer(0.18).timeout.connect(func(): main._change_floor(2, 0, false))
	await main._handle_butcher()
	check(main.current_floor == 2 and not main._is_butchering and not main._is_processing_action, "Floor transition left task running")
	print("BUTCHERY_DURATION_TEST failures=", failures)
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)

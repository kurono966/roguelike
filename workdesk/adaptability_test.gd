extends SceneTree

class TestTurns extends TurnManager:
	func process_enemy_turns():
		pass

var failures = 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var gs = root.get_node("GameState")
	gs.player_class = 0
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_nodes_in_group(group): actor.queue_free()
	await process_frame
	await process_frame
	main._is_on_world_map = false
	main.player.status_effects.clear()
	main._traps.clear()
	main._burning_grass.clear()
	main._steam_tiles.clear()
	for x in range(20, 36):
		for y in range(20, 36): main._map_data[x][y] = main.CellType.FLOOR
	var player = main.player
	player.position = Vector2(25, 25) * 32
	player.mp = 0
	player.turn_counter = 0
	player.last_action_id = ""
	main._setup_pathfinding()
	main._calculate_fov()
	var enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	enemy.apply_definition(EnemyDatabase.get_enemy_def("zakomushi"))
	enemy.position = Vector2(30, 25) * 32
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	main.add_child(enemy)
	var turns = TestTurns.new()
	main.add_child(turns)
	turns.setup(main)
	main.turn_manager = turns
	await main._end_player_turn(-1, "wait")
	check(player.mp == 0 and player.last_action_id == "wait", "First action should only initialize history")
	await main._try_move_character(player, Vector2.RIGHT)
	await main._end_player_turn()
	check(player.mp == 1 and player.last_action_id == "move", "Movement did not trigger adaptation once")
	await create_timer(0.2).timeout
	await main._try_move_character(player, Vector2.LEFT)
	await main._end_player_turn()
	check(player.mp == 1, "Consecutive movement recovered MP")
	await create_timer(0.2).timeout
	player.on_skill_executed({"id": "fireball", "mp_cost": 0}, false)
	await main._end_player_turn()
	check(player.last_action_id == "skill:fireball" and player.mp == 2, "Fireball has no individual action ID")
	player.on_skill_executed({"id": "heal", "mp_cost": 0}, false)
	await main._end_player_turn()
	check(player.last_action_id == "skill:heal" and player.mp == 3, "Different skill did not count as a changed action")
	player.on_skill_executed({"id": "heal", "mp_cost": 0}, false)
	await main._end_player_turn()
	check(player.mp == 3, "Repeated skill recovered MP")
	for id in ["potion", "potion", "scroll_mapping"]:
		var item = ItemDatabase.get_item_by_id(id)
		player.equipment_component.add_to_bag(item)
		player._consume_item(item, "test consume")
		await process_frame
		check(player.last_action_id == "item:" + id, "Item ID not recorded")
	check(player.mp == 5, "Item change/repetition recovery incorrect")
	main._visible_tiles[30][25] = false
	await main._end_player_turn(-1, "attack")
	check(player.mp == 5 and player.last_action_id == "attack", "Out-of-combat action did not update history without recovery")
	main._visible_tiles[30][25] = true
	await main._end_player_turn(-1, "attack")
	check(player.mp == 5, "Entering combat recovered for the same previous action")
	gs.player_class = 1
	await main._end_player_turn(-1, "wait")
	check(player.mp == 5 and player.last_action_id == "wait", "Non-balanced class received adaptation")
	gs.player_class = 0
	player.on_skill_executed({"id": "teleport", "mp_cost": 2}, false)
	await main._end_player_turn()
	check(player.mp == 4 and player.last_action_id == "skill:teleport", "Adaptation did not recover after paying individual skill cost")
	player.mp = player.max_mp
	await main._end_player_turn(-1, "ranged_attack")
	check(player.mp == player.max_mp, "Adaptation exceeded max MP")
	enemy.hp = 1000
	enemy.position = Vector2(26, 25) * 32
	player.mp = 0
	player.hit_rate = 1.0
	await main._handle_attack(player, enemy)
	await main._end_player_turn()
	check(player.last_action_id == "attack" and player.mp == 1, "Real normal attack was not recorded")
	await main._handle_attack(player, enemy)
	await main._end_player_turn()
	check(player.mp == 1, "Consecutive real normal attacks recovered MP")
	var last = player.last_action_id
	main.start_skill_targeting({"id": "fireball", "name": "火球", "range": 6})
	main.target_manager.cancel_targeting()
	check(player.last_action_id == last, "Cancelled targeting changed history")
	main._map_data[26][25] = main.CellType.WALL
	check(not await main._try_move_character(player, Vector2.RIGHT) and player.last_action_id == last, "Failed movement changed history")
	main._deserialize_player(player, {"player_class": 0, "last_action_id": "skill:teleport"})
	check(player.last_action_id == "skill:teleport", "Loading lost last action ID")
	print("ADAPTABILITY_TEST failures=", failures)
	quit(1 if failures else 0)

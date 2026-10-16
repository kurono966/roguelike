extends SceneTree

class TestTurns extends TurnManager:
	func start_player_turn():
		pass

var failures = 0
var main

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func spawn(id: String, cell: Vector2i):
	var enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	enemy.apply_definition(EnemyDatabase.get_enemy_def(id))
	enemy.position = Vector2(cell) * 32
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	main.add_child(enemy)
	return enemy

func seed_for(revive: bool):
	var probe = RandomNumberGenerator.new()
	for seed_value in range(100):
		probe.seed = seed_value
		if (probe.randf() < 0.5) == revive:
			main.corpse_manager.rng.seed = seed_value
			return

func run_test():
	main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_nodes_in_group(group): actor.queue_free()
	await process_frame
	main._is_on_world_map = false
	main.current_floor = 2
	main._current_branch = 0
	main._burning_grass.clear()
	main._frozen_tiles.clear()
	main._steam_tiles.clear()
	main._poison_gas_tiles.clear()
	main._traps.clear()
	main._hazards.clear()
	for x in range(20, 36):
		for y in range(20, 36):
			main._map_data[x][y] = main.CellType.FLOOR
	main.player.position = Vector2(24, 25) * 32
	main.player.hp = 1000
	main._setup_pathfinding()
	main._calculate_fov()
	var victim = spawn("root_eater", Vector2i(28, 25))
	victim.loot_table.clear()
	victim.hp = 0
	victim.die()
	victim.die()
	var manager = main.corpse_manager
	check(manager.corpses.size() == 1, "Death made duplicate or missing corpses")
	var corpse = manager.corpses.front()
	check(corpse.enemy_id == "root_eater" and corpse.enemy_name == "根食い" and corpse.death_grid == Vector2i(28, 25), "Corpse lost enemy identity or death tile")
	check(corpse.death_position == Vector2(28, 25) * 32 and corpse.visible, "Corpse lost death position or visible trace")
	check(not corpse.is_in_group("entities") and not main._astar_grid.is_point_solid(corpse.death_grid), "Corpse blocks actors/navigation")
	await process_frame
	var hidden = manager.add_corpse("bat", "隠れた死体", Vector2(25, 23) * 32)
	main._map_data[25][24] = main.CellType.WALL
	main._setup_pathfinding()
	var keeper = spawn("gravekeeper", Vector2i(25, 25))
	check(keeper.is_gravekeeper, "Gravekeeper definition not applied")
	check(manager.find_target(keeper).get("corpse") == corpse, "Keeper chose a corpse hidden by a wall")
	var turns = TestTurns.new()
	main.add_child(turns)
	turns.setup(main)
	var player_hp = main.player.hp
	await turns.process_enemy_turns()
	check(keeper.position.distance_to(corpse.position) < 96 and main.player.hp == player_hp, "Keeper attacked adjacent player instead of pursuing corpse")
	keeper.position = corpse.position
	var attack_before = keeper.attack_power
	seed_for(false)
	await turns.process_enemy_turns()
	check(keeper.attack_power == attack_before + 2 and not manager.corpses.has(corpse), "Absorption did not consume corpse and grant attack")
	check(main.player.hp == player_hp, "Absorption allowed a second action")
	var serializer = load("res://save_manager.gd").new()
	var saved_keeper = serializer._serialize_enemy(keeper)
	main._deserialize_enemy(saved_keeper)
	var restored_keeper = get_nodes_in_group("enemies").back()
	check(restored_keeper.is_gravekeeper and restored_keeper.attack_power == keeper.attack_power, "Save/load lost attack growth or behavior")
	restored_keeper.queue_free()
	serializer.free()
	await process_frame
	manager.remove_corpse(hidden)
	var revive_corpse = manager.add_corpse("bat", "復活コウモリ", keeper.position)
	seed_for(true)
	var count_before = get_nodes_in_group("enemies").size()
	await turns.process_enemy_turns()
	check(not manager.corpses.has(revive_corpse) and get_nodes_in_group("enemies").size() == count_before + 1, "Resurrection did not consume corpse/spawn enemy")
	var revived = get_nodes_in_group("enemies").back()
	check(revived.enemy_id == "bat" and revived.enemy_name == "復活コウモリ" and revived.hp == revived.max_hp, "Wrong resurrected enemy identity/HP")
	check(revived.position != keeper.position and keeper.attack_power == attack_before + 2, "Resurrection overlapped keeper or also granted attack")
	manager.clear_all()
	check(not await manager.act(keeper), "No-corpse AI did not return control to aggressive behavior")
	var old_distance = keeper.position.distance_to(main.player.position)
	await turns.process_enemy_turns()
	check(keeper.position.distance_to(main.player.position) < old_distance, "Keeper did not chase player when no corpses exist")
	main._visible_tiles[35][35] = false
	var unseen = manager.add_corpse("bat", "未知の死体", Vector2(35, 35) * 32)
	check(not unseen.visible, "Offscreen death leaked through fog")
	main._visible_tiles[35][35] = true
	manager.refresh_visibility()
	check(unseen.visible and unseen.discovered, "Visible corpse not discovered")
	main._visible_tiles[35][35] = false
	manager.refresh_visibility()
	check(unseen.visible and unseen.modulate.r < 0.5, "Discovered corpse not remembered in fog")
	manager.clear_all()
	var entry = manager.add_corpse("bat", "保存する残骸", Vector2(28, 26) * 32)
	var config = ConfigFile.new()
	config.set_value("world", "corpses", manager.serialize())
	config.save("res://workdesk/corpse_roundtrip.cfg")
	var loaded = ConfigFile.new()
	loaded.load("res://workdesk/corpse_roundtrip.cfg")
	manager.restore(loaded.get_value("world", "corpses", []))
	check(manager.corpses.size() == 1 and manager.corpses.front().enemy_name == "保存する残骸", "Corpse ConfigFile roundtrip failed")
	await main._zoom_out_to_world_map()
	check(manager.corpses.size() == 1, "Rejected floor transition erased corpses")
	main._save_current_floor_to_cache()
	await main._change_floor(3, 0)
	check(manager.corpses.is_empty(), "Corpses survived floor transition")
	await main._change_floor(2, 0, true)
	check(manager.corpses.is_empty(), "Floor cache resurrected expired corpses")
	print("GRAVEKEEPER_TEST failures=", failures)
	quit(1 if failures else 0)

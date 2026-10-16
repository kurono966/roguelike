extends SceneTree

class TestTurns extends TurnManager:
	func start_player_turn():
		pass

class Spawner extends EnemyManager:
	func _get_random_enemy_data() -> Dictionary:
		return EnemyDatabase.get_enemy_def("root_eater")
	func _get_random_position_in_room(_room: Rect2i) -> Vector2i:
		return Vector2i(26, 25)

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
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_nodes_in_group(group): actor.queue_free()
	await process_frame
	main._is_on_world_map = false
	main._burning_grass.clear()
	main._frozen_tiles.clear()
	main._steam_tiles.clear()
	main._poison_gas_tiles.clear()
	main._traps.clear()
	main._hazards.clear()
	for x in range(20, 32):
		for y in range(20, 32):
			main._map_data[x][y] = main.CellType.FLOOR
	main._map_data[26][25] = main.CellType.GRASS
	main.player.position = Vector2(25, 25) * 32
	main.player.hp = 1000
	main._setup_pathfinding()
	var spawner = Spawner.new()
	main.add_child(spawner)
	spawner.setup(main)
	spawner._spawn_enemy_in_room(Rect2i(20, 20, 12, 12))
	var eater = get_nodes_in_group("enemies").back()
	check(eater.enemy_name == "根食い" and eater.grass_heal == 5, "Real spawn lost definition/ability")
	var turns = TestTurns.new()
	main.add_child(turns)
	turns.setup(main)
	var hp_before = main.player.hp
	await turns.process_enemy_turns()
	check(eater.hp == eater.max_hp + 5 and eater.max_hp == 20, "Eating at full HP did not overheal by 5")
	check(main._map_data[26][25] == main.CellType.FLOOR, "Eaten grass remained")
	check(main.player.hp == hp_before and eater.position == Vector2(26, 25) * 32, "Eating did not consume the action")
	main._map_data[26][24] = main.CellType.GRASS
	await turns.process_enemy_turns()
	check(eater.hp == 30 and eater.max_hp == 20, "Repeated eating did not stack excess HP")
	check(not turns._try_eat_grass(eater), "Grass could be eaten twice")
	main._map_data[27][25] = main.CellType.GRASS
	main._burning_grass[Vector2i(27, 25)] = {"turns_remaining": 3}
	check(not turns._try_eat_grass(eater), "Burning grass was edible")
	main._burning_grass.clear()
	eater.status_effects["paralyze"] = {"duration": 3}
	check(not turns._try_eat_grass(eater), "Paralyzed monster ate grass")
	eater.status_effects.clear()
	eater.heal(1)
	check(eater.hp == 30, "Ordinary heal removed excess HP")
	main._deserialize_enemy({"enemy_id": "root_eater", "hp": eater.hp, "max_hp": eater.max_hp, "position_x": 896, "position_y": 800})
	var restored = get_nodes_in_group("enemies").back()
	check(restored.grass_heal == 5 and restored.hp == 30 and restored.max_hp == 20, "Restoration lost eating/overheal")
	restored.hp = 2
	check(turns._try_eat_grass(restored) and restored.hp == 7 and restored.max_hp == 20, "Eating while injured did not heal exactly 5")
	for floor_number in [1, 5, 10]:
		check(EnemyDatabase.get_enemy_definitions(floor_number, 3).any(func(data): return data.id == "root_eater"), "Green branch does not spawn root eaters")
	print("ROOT_EATER_TEST failures=", failures)
	quit(1 if failures else 0)

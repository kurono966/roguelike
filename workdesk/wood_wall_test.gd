extends Node

var failures = 0
var main
const WOOD = MapDefinitions.CellType.WOOD_WALL
const WALL = MapDefinitions.CellType.WALL
const FLOOR = MapDefinitions.CellType.FLOOR

func _ready():
	call_deferred("_run")

func _check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _blocked(pos: Vector2i):
	_check(not main.map_controller.is_walkable(pos, true, true), "Wood is walkable")
	_check(not main._is_auto_explore_walkable(pos), "Auto explore routes through wood")
	for grid in [main._astar_grid, main._astar_grid_swim, main._astar_grid_fly]:
		_check(grid.is_point_solid(pos), "Movement mode paths through wood")
	_check(not main._has_line_of_sight(Vector2i(25, 25), Vector2i(27, 25)), "Wood does not block LOS")
	main._calculate_fov()
	_check(not main._visible_tiles[27][25], "Wood does not block FOV")

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_tree().get_nodes_in_group(group):
			actor.queue_free()
	await get_tree().process_frame
	main._is_on_world_map = false
	main.current_floor = 2
	main._traps.clear()
	main._steam_tiles.clear()
	main._burning_grass.clear()
	main._frozen_tiles.clear()
	main.player.status_effects.clear()
	main.player.equipment_component.equipment_data.items.clear()
	main.player.position = Vector2(25, 25) * 32
	main.player.mp = 100
	main.player.max_mp = 100
	main.player.max_hp = 1000
	main.player.hp = 1000
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT):
			main._map_data[x][y] = WALL
	for x in range(23, 30):
		main._map_data[x][25] = FLOOR
	var pos = Vector2i(26, 25)
	main._map_data[26][25] = WOOD
	main._setup_pathfinding()
	_blocked(pos)
	_check(not await main._try_move_character(main.player, Vector2.RIGHT), "Player walked through unlit wood")
	await main._handle_ranged_attack(main.player, Vector2i(29, 25), 1, "arrow")
	_check(not main._burning_grass.has(pos), "Non-fire shot ignited wood")
	await main._handle_ranged_attack(main.player, Vector2i(29, 25), 1, "fire")
	_check(main._burning_grass.has(pos), "Fire projectile did not ignite first wall")
	_check(main._burning_grass[pos].turns_remaining == 5, "Incorrect burn lifetime")
	_blocked(pos)
	_check(not await main._try_move_character(main.player, Vector2.RIGHT), "Player walked through burning wood")
	# Persistence uses the existing fire-state dictionary and unchanged tile ID.
	main._save_current_floor_to_cache_with_key("wood_test")
	_check(main._load_floor_from_cache("wood_test", false), "Could not reload burning floor")
	main.player.position = Vector2(25, 25) * 32
	_check(main._map_data[26][25] == WOOD and main._burning_grass[pos].turns_remaining == 5, "Revisit lost burning wall/lifetime")
	for turn_index in range(4):
		main._process_burning_grass()
		_check(main._map_data[26][25] == WOOD, "Wall vanished before five turns")
		_blocked(pos)
	main._process_burning_grass()
	_check(main._map_data[26][25] == FLOOR and not main._burning_grass.has(pos), "Wall did not burn to floor")
	for grid in [main._astar_grid, main._astar_grid_swim, main._astar_grid_fly]:
		_check(not grid.is_point_solid(pos), "Burnout left stale path collision")
	_check(main._has_line_of_sight(Vector2i(25, 25), Vector2i(27, 25)), "Burnout left stale LOS")
	_check(main._visible_tiles[27][25], "Burnout left stale FOV")
	_check(await main._try_move_character(main.player, Vector2.RIGHT), "Could not walk through burned wall")
	main.player.position = Vector2(25, 25) * 32
	main._map_data[26][25] = WOOD
	main._map_data[26][26] = WOOD
	main._setup_pathfinding()
	main._ignite_grass(pos)
	main._burning_grass[pos].spread_chance = 100
	main._process_burning_grass()
	_check(main._burning_grass.has(Vector2i(26, 26)), "Fire did not spread to adjacent wood")
	_check(main._burning_grass[Vector2i(26, 26)].turns_remaining == 5, "New fire ticked in its ignition turn")
	_check(not main._burning_grass.has(Vector2i(26, 24)), "Stone wall caught fire")
	main._burning_grass.clear()
	main._ignite_grass(pos)
	main._burning_grass[pos].spread_chance = 0
	main._process_burning_grass()
	_check(not main._burning_grass.has(Vector2i(26, 26)), "Zero-probability fire still spread")
	main._ignite_grass(pos)
	_check(main._burning_grass[pos].turns_remaining == 4, "Repeated hit reset burning lifetime")
	main._burning_grass.clear()
	main._map_data[26][26] = WALL
	main._current_game_state = main.TurnPhase.PLAYER_TURN
	await main._execute_directional_skill(Vector2(29, 25) * 32, SkillDatabase.get_skill_by_id("fireball"))
	_check(main._burning_grass.has(pos), "Player fireball did not ignite wood wall on impact")
	main._burning_grass.clear()
	main._map_data[26][26] = WOOD
	main.player.mp = 100
	await main._execute_point_skill(Vector2(25, 25) * 32, SkillDatabase.get_skill_by_id("explosion"))
	_check(main._burning_grass.has(pos) and main._burning_grass.has(Vector2i(26, 26)), "Explosion did not ignite wood walls in area")
	# Compare material ratios on identical seeded dungeon geometry.
	var generator = DungeonGenerator.new()
	add_child(generator)
	var ratios = []
	for branch in [0, 3]:
		seed(42)
		var generated = generator.generate_map(2, branch)
		var wooden = 0
		var solid = 0
		for x in range(main.MAP_WIDTH):
			for y in range(main.MAP_HEIGHT):
				var cell = generated.map_data[x][y]
				if cell in [WALL, WOOD]: solid += 1
				if cell == WOOD: wooden += 1
				if x == 0 or y == 0 or x == main.MAP_WIDTH - 1 or y == main.MAP_HEIGHT - 1:
					_check(cell != WOOD, "Wood generated on map boundary")
		ratios.append(float(wooden) / solid)
	_check(ratios[1] > 0.4 and ratios[1] > ratios[0] * 3, "Green floors do not favor wood: " + str(ratios))
	print("WOOD_WALL_TEST failures=", failures, " wood_ratios=", ratios)
	await get_tree().create_timer(2.1).timeout
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

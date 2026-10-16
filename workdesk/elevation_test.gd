extends Node

var failures = 0
var main

func _ready(): call_deferred("_run")

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func valid_path(path: Array):
	for i in range(1, path.size()):
		check(main.can_step_height(path[i - 1], path[i]), "A* returned an impossible height edge")

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_tree().get_nodes_in_group(group): actor.queue_free()
	await get_tree().process_frame
	main._is_on_world_map = false
	main.current_floor = 2
	main._traps.clear()
	main._burning_grass.clear()
	main._steam_tiles.clear()
	main._frozen_tiles.clear()
	main._height_data = ElevationMap.normalize([], main.MAP_WIDTH, main.MAP_HEIGHT)
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT): main._map_data[x][y] = main.CellType.WALL
	for x in range(23, 30):
		for y in range(23, 30): main._map_data[x][y] = main.CellType.FLOOR
	var start = Vector2i(25, 25)
	var goal = Vector2i(26, 25)
	main.player.position = Vector2(start) * 32
	main._height_data[25][25] = 0
	main._height_data[26][25] = 2
	main._setup_pathfinding()
	main._calculate_fov()
	var before_fov = main._visible_tiles.duplicate(true)
	main.set_tile_height(goal, 1)
	main._calculate_fov()
	check(main._visible_tiles != before_fov, "Height edits did not recalculate terrain occlusion")
	main.set_tile_height(goal, 2)
	check(not await main._try_move_character(main.player, Vector2.RIGHT), "Player climbed a two-level cliff")
	for grid in [main._astar_grid, main._astar_grid_swim, main._astar_grid_fly]:
		var path = grid.get_id_path(start, goal)
		check(path.size() > 2, "A* failed to detour around cliff")
		valid_path(path)
	# Isolate the two cells: there is no legal edge, despite both being floors.
	for x in range(23, 30):
		for y in range(23, 30):
			if Vector2i(x, y) not in [start, goal]: main._map_data[x][y] = main.CellType.WALL
	main._setup_pathfinding()
	check(main._astar_grid.get_id_path(start, goal).is_empty(), "A* routed through an impassable cliff")
	main.set_tile_height(goal, 1)
	check(main._astar_grid.get_id_path(start, goal).size() == 2, "Height edit did not update A*")
	check(await main._try_move_character(main.player, Vector2.RIGHT), "Player could not climb a single level")
	await get_tree().create_timer(0.2).timeout
	main.set_tile_height(start, 2)
	check(await main._try_move_character(main.player, Vector2.LEFT), "Player could not descend/climb normal-high edge")
	await get_tree().create_timer(0.2).timeout
	main.set_tile_height(goal, 0)
	check(not await main._try_move_character(main.player, Vector2.RIGHT), "Player descended a two-level cliff")
	main._save_current_floor_to_cache_with_key("elevation_test")
	main._height_data = []
	main._load_floor_from_cache("elevation_test", false)
	check(main.get_tile_height(start) == 2 and main.get_tile_height(goal) == 0, "Revisit lost heights")
	main._floor_caches["elevation_test"].erase("height_data")
	main._load_floor_from_cache("elevation_test", false)
	check(main.get_tile_height(start) == 1 and main.get_tile_height(goal) == 1, "Old cache did not default to normal height")
	# Connected dungeon land must remain connected after adding elevations.
	var generator = DungeonGenerator.new()
	add_child(generator)
	for branch in [0, 3, 10]:
		seed(1234 + branch)
		var generated = generator.generate_map(2, branch)
		var terrain: Array = generated.map_data
		var heights = ElevationMap.generate(terrain)
		main._map_data = terrain
		main._height_data = ElevationMap.normalize([], main.MAP_WIDTH, main.MAP_HEIGHT)
		main._setup_pathfinding()
		var from = Vector2i(generated.rooms[0].get_center())
		var reachable = []
		for room in generated.rooms:
			var target = Vector2i(room.get_center())
			if not main._astar_grid.get_id_path(from, target).is_empty(): reachable.append(target)
		main._height_data = heights
		main._setup_pathfinding()
		for target in reachable:
			var path = main._astar_grid.get_id_path(from, target)
			check(not path.is_empty(), "Elevation disconnected a room/stair")
			valid_path(path)
		var counts = [0, 0, 0]
		var changed_edges = 0
		for x in range(main.MAP_WIDTH):
			for y in range(main.MAP_HEIGHT):
				check(heights[x][y] in [0, 1, 2], "Invalid elevation")
				counts[heights[x][y]] += 1
				if x > 0 and heights[x][y] != heights[x - 1][y]: changed_edges += 1
		check(counts.min() > 0, "Generation omitted a height level")
		check(counts[1] > counts[0] + counts[2], "Normal terrain is no longer the majority")
		check(counts[1] > main.MAP_WIDTH * main.MAP_HEIGHT * 0.75, "Too many elevated tiles")
		print("ELEVATION_DENSITY branch=", branch, " low/normal/high=", counts)
		check(changed_edges < main.MAP_WIDTH * main.MAP_HEIGHT / 3, "Height generation is too noisy")
	main._draw_map()
	await get_tree().process_frame
	check(is_instance_valid(main._elevation_overlay), "Height overlay was not created")
	check(is_instance_valid(main._elevation_blur) and main._elevation_blur.material is ShaderMaterial, "Missing off-height blur")
	check(main._elevation_blur.get_parent() == main._elevation_overlay, "Blur must render over height shading and below fire/actors")
	check(is_instance_valid(main._terrain_foreground) and main._terrain_foreground.get_index() > main._elevation_blur.get_index(), "Floor markings must render after height blur")
	# Roads remain flat even when loading older elevation data.
	main._map_data[25][25] = main.CellType.ASH
	main._map_data[26][25] = main.CellType.ASH
	main._height_data[25][25] = 0
	main._height_data[26][25] = 2
	main._setup_pathfinding()
	check(main.get_tile_height(Vector2i(25, 25)) == 1 and main.get_tile_height(Vector2i(26, 25)) == 1, "Existing roads were not flattened")
	main.set_tile_height(Vector2i(25, 25), 2)
	check(main.get_tile_height(Vector2i(25, 25)) == 1, "Road accepted a non-flat height")
	# Generated water has a low bed but a normal-height water/ice surface.
	main._map_data[26][25] = main.CellType.WATER
	var basin_heights = ElevationMap.generate(main._map_data)
	check(basin_heights[26][25] == 0, "Generated water bed is not low")
	main._height_data[26][25] = 0
	main._liquid_state.clear()
	main._setup_pathfinding()
	check(is_equal_approx(main.get_surface_height(Vector2i(26, 25)), 1.0), "Generated water surface is not normal height")
	check(main._astar_grid_swim.heights[26][25] == 1, "Swimming paths used the bed instead of the surface")
	main.liquid_manager._sync_liquids()
	check(main._liquid_state[Vector2i(26, 25)].volume == 4, "Generated basin lost its initial water depth")
	main._map_data[26][25] = main.CellType.ICE
	check(main.get_movement_height(Vector2i(26, 25)) == 1, "Ice surface fell to the basin bed")
	# Camera zoom approaches each target smoothly rather than jumping.
	main.player.position = Vector2(25, 25) * 32
	main._map_data[25][25] = main.CellType.FLOOR
	main._height_data[25][25] = 0
	main.camera.zoom = Vector2.ONE * 0.66
	main._update_height_camera(0.05)
	check(main.camera.zoom.x < 0.66 and main.camera.zoom.x > 0.60, "Low-ground zoom did not ease toward a wider view")
	for frame in range(20): main._update_height_camera(0.1)
	check(absf(main.camera.zoom.x - 0.60) < 0.001, "Low-ground camera target is wrong")
	main._height_data[25][25] = 2
	for frame in range(20): main._update_height_camera(0.1)
	check(absf(main.camera.zoom.x - 0.72) < 0.001, "High-ground camera target is wrong")
	main.player.position = Vector2(26, 25) * 32
	for frame in range(20): main._update_height_camera(0.1)
	check(absf(main.camera.zoom.x - 0.66) < 0.001, "Water/ice camera used bed height instead of surface")
	print("ELEVATION_TEST failures=", failures)
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

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
	await process_frame
	main._is_on_world_map = false
	main._steam_tiles.clear()
	main._frozen_tiles.clear()
	main._traps.clear()
	for x in range(24, 29):
		for y in range(24, 28):
			main._map_data[x][y] = main.CellType.FLOOR
			main._height_data[x][y] = 2 if x == 26 else 0
	main._setup_pathfinding()
	var low = Vector2i(25, 25)
	var high = Vector2i(26, 25)
	check(main._height_data[26][25] == 2, "Stored heights must remain intact")
	check(main.get_tile_height(high) == 1 and main.get_surface_height(low) == 1.0, "Old heights still affect gameplay")
	check(main.can_step_height(low, high), "Old cliff blocks player movement")
	for grid in [main._astar_grid, main._astar_grid_swim, main._astar_grid_fly]:
		check(grid.can_step(low, high), "Old cliff blocks NPC pathfinding")
	check(main._has_line_of_sight(low, Vector2i(27, 25)), "Old ridge blocks sight")
	check(main._get_height_occluder(low, Vector2i(27, 25), func(_pos): return 100.0) == Vector2i(-1, -1), "Height projectile/preview blocker active")
	main._map_data[26][25] = main.CellType.WALL
	check(not main._has_line_of_sight(low, Vector2i(27, 25)), "Walls stopped blocking sight")
	main._map_data[26][25] = main.CellType.WATER
	main._liquid_state.clear()
	main._liquid_state[high] = {"kind": main.CellType.WATER, "volume": 4, "ground": main.CellType.FLOOR}
	var before = main._map_data.duplicate(true)
	main.liquid_manager.process_turn()
	check(main._map_data == before, "Disabled elevation liquid simulation moved water")
	check(main.get_movement_height(high) == 1, "Water surface creates a height difference")
	main.player.position = Vector2(high) * 32
	main.camera.zoom = Vector2.ONE * main.BASE_CAMERA_ZOOM
	main._update_height_camera(1.0)
	check(main.camera.zoom == Vector2.ONE * main.BASE_CAMERA_ZOOM, "Height camera zoom still active")
	main._draw_map()
	check(not is_instance_valid(main._elevation_overlay) or not main._elevation_overlay.visible, "Elevation shading/blur still visible")
	var generated = ElevationMap.generate([[main.CellType.FLOOR, main.CellType.WATER]])
	check(generated == [[1, 1]], "New maps still generate elevation")
	print("ELEVATION_DISABLED_TEST failures=", failures)
	quit(1 if failures else 0)

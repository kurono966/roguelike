extends SceneTree

var failures = 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func active_gases() -> Array:
	return get_nodes_in_group("gas_overlays").filter(func(node): return not node.is_queued_for_deletion())

func run_test():
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	await process_frame
	main._is_on_world_map = false
	main._steam_tiles.clear()
	main._poison_gas_tiles.clear()
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT):
			main._visible_tiles[x][y] = false
			main._explored_tiles[x][y] = false
	for x in range(25, 28):
		main._map_data[x][25] = main.CellType.GRASS if x != 26 else main.CellType.FLOOR
		main._visible_tiles[x][25] = x != 27
		main._explored_tiles[x][25] = true
		main._height_data[x][25] = x - 25
		main._poison_gas_tiles[Vector2i(x, 25)] = {"density": 2, "turns_remaining": 3}
	main._steam_tiles[Vector2i(25, 25)] = {"density": 1, "turns_remaining": 3}
	for alternate in [false, true]:
		if alternate:
			main.visibility_manager.map_data = main._map_data
			main.visibility_manager.visible_tiles = main._visible_tiles
			main.visibility_manager.explored_tiles = main._explored_tiles
			main.visibility_manager.draw_map()
		else:
			main._draw_map()
		var overlays = active_gases()
		check(overlays.size() == 3, "Both renderers must draw grass/floor gas and steam, hiding unseen gas")
		for overlay in overlays:
			check(overlay.z_index > 1 and overlay.z_index < 4, "Gas must render above grass and below items")
			check(overlay.position != Vector2(27, 25) * 32, "Unseen gas leaked")
	main._poison_gas_tiles.clear()
	main._steam_tiles.clear()
	main._draw_map()
	check(active_gases().is_empty(), "Expired gas remained visible")
	print("GAS_VISIBILITY_TEST failures=", failures)
	quit(1 if failures else 0)

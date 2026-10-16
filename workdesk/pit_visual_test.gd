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
	main.tileset_manager.set_process(false)
	main.current_floor = 2
	main._is_on_world_map = false
	var pos = Vector2i(25, 25)
	var dirs = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var source = main.tile_map.tile_set.get_source(0)
	var image = main.tileset_manager._combined_image
	var pit_rect = Rect2i(MapDefinitions.PIT_ATLAS_START * 32, 0, 16 * 32, 32)
	var before = image.get_region(pit_rect).get_data()
	var crystal_before = image.get_region(Rect2i(46 * 32, 0, 32, 32)).get_data()
	for time_sec in [0.0, 0.5, 1.5]:
		main.tileset_manager._animate_crystals(time_sec)
		_check(image.get_region(pit_rect).get_data() == before, "Crystal animation overwrote pit images")
	_check(image.get_region(Rect2i(46 * 32, 0, 32, 32)).get_data() != crystal_before, "Crystal animation stopped working")
	for mask in range(16):
		main._map_data[25][25] = main.CellType.PIT
		for bit in range(4):
			var adjacent = pos + dirs[bit]
			main._map_data[adjacent.x][adjacent.y] = main.CellType.PIT if mask & (1 << bit) else main.CellType.FLOOR
		var expected = Vector2i(MapDefinitions.PIT_ATLAS_START + mask, 0)
		_check(source.has_tile(expected), "Missing pit atlas tile")
		_check(main._get_map_cell_atlas_coords(main._map_data, 25, 25) == expected, "Wrong pit lookup for mask " + str(mask))
		for renderer in [main, main.visibility_manager]:
			main._explored_tiles[25][25] = true
			main._visible_tiles[25][25] = true
			if renderer == main: renderer._draw_map()
			else: renderer.draw_map()
			_check(main.tile_map.get_cell_atlas_coords(0, pos) == expected, "Visible pit references wrong atlas tile")
			main._visible_tiles[25][25] = false
			if renderer == main: renderer._draw_map()
			else: renderer.draw_map()
			_check(main.memory_tile_map.get_cell_atlas_coords(0, pos) == expected, "Remembered pit references wrong atlas tile")
	print("PIT_VISUAL_TEST failures=", failures)
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

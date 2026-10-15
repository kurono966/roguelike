extends Node

var failures: int = 0

class TrapHost extends Node2D:
	var _traps: Dictionary
	var _trap_visuals: Dictionary = {}
	var world: Node2D

	func _draw_map():
		pass

	func _update_astar_tile(pos: Vector2i, solid: bool):
		world._update_astar_tile(pos, solid)

func _ready():
	call_deferred("_run")

func _check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)

func _run():
	var main = load("res://world/main.gd").new()
	main.tile_map = TileMap.new()
	main.map_controller = MapController.new()
	main.map_controller.setup(main)
	for x in range(main.MAP_WIDTH):
		var column = []
		column.resize(main.MAP_HEIGHT)
		column.fill(MapDefinitions.CellType.FLOOR)
		main._map_data.append(column)
	main._setup_pathfinding()
	var start = Time.get_ticks_usec()
	for i in range(100):
		main._setup_pathfinding()
	print("BENCH_PATH_100_US: ", Time.get_ticks_usec() - start)
	start = Time.get_ticks_usec()
	for i in range(1000):
		main._create_ascii_stairs_texture(Color.GOLD)
	print("BENCH_TEXTURE_1000_US: ", Time.get_ticks_usec() - start)
	if "--benchmark-only" in OS.get_cmdline_user_args():
		_cleanup(main)
		get_tree().quit()
		return

	var grid = main._astar_grid
	main._setup_pathfinding()
	_check(main._astar_grid == grid, "Path grid was needlessly replaced")
	var cases = [
		[MapDefinitions.CellType.FLOOR, false, false, false],
		[MapDefinitions.CellType.WATER, true, false, false],
		[MapDefinitions.CellType.LAVA, true, true, false],
		[MapDefinitions.CellType.PIT, true, true, false],
		[MapDefinitions.CellType.WALL, true, true, true],
		[MapDefinitions.CellType.TREE, true, true, false],
		[MapDefinitions.CellType.ROCK, true, true, false],
		[MapDefinitions.CellType.DOOR_CLOSED, false, false, false],
		[MapDefinitions.CellType.DOOR_LOCKED, true, false, false],
		[MapDefinitions.CellType.STAIRS_UP, false, false, false],
		[MapDefinitions.CellType.VOLCANIC_ASH, false, false, false],
	]
	var pos = Vector2i(3, 3)
	for entry in cases:
		main._map_data[pos.x][pos.y] = entry[0]
		main._setup_pathfinding()
		var grids = [main._astar_grid, main._astar_grid_swim, main._astar_grid_fly]
		for index in range(3):
			_check(grids[index].is_point_solid(pos) == entry[index + 1], "Terrain mismatch: %s / mode %d" % [entry[0], index])
	main._map_data[pos.x][pos.y] = MapDefinitions.CellType.WATER
	main._frozen_tiles[pos] = {}
	main._setup_pathfinding()
	_check(not main._astar_grid.is_point_solid(pos), "Frozen water blocked walking")
	main._traps[pos] = {"is_revealed": true}
	main._setup_pathfinding()
	_check(main._astar_grid.is_point_solid(pos), "Frozen tile bypassed revealed trap")
	main._traps.clear()
	main._frozen_tiles.clear()
	main._map_data[pos.x][pos.y] = MapDefinitions.CellType.WALL
	main._setup_pathfinding()
	main._map_data[pos.x][pos.y] = MapDefinitions.CellType.FLOOR
	main._setup_pathfinding()
	_check(not main._astar_grid.is_point_solid(pos), "Reused grid retained an old obstacle")
	# A single changed tile must retain movement-specific terrain rules.
	main._map_data[pos.x][pos.y] = MapDefinitions.CellType.WATER
	main._update_astar_tile(pos, false)
	_check(main._astar_grid.is_point_solid(pos), "Single-tile update let walkers cross water")
	_check(not main._astar_grid_swim.is_point_solid(pos), "Single-tile update blocked swimmers")
	# Revealing one trap updates only that tile and keeps the current grid alive.
	var hazards = HazardManager.new()
	var trap_host = TrapHost.new()
	trap_host.world = main
	trap_host._traps = main._traps
	add_child(trap_host)
	hazards.main = trap_host
	main._traps[pos] = {"is_revealed": false}
	grid = main._astar_grid
	hazards.reveal_trap(pos)
	_check(main._astar_grid == grid and grid.is_point_solid(pos), "Revealing trap failed to update its tile")
	hazards.free()
	trap_host.free()
	main._world_map_data = main._map_data.duplicate(true)
	main._world_map_data[pos.x][pos.y] = MapDefinitions.WorldCell.SEA
	main._is_on_world_map = true
	main._setup_pathfinding()
	_check(main._astar_grid.is_point_solid(pos), "World sea was walkable")
	main._world_map_data[pos.x][pos.y] = MapDefinitions.WorldCell.ROAD
	main._setup_pathfinding()
	_check(not main._astar_grid.is_point_solid(pos), "World road was blocked")
	_check(main._create_ascii_stairs_texture(Color.GOLD) == main._create_ascii_stairs_texture(Color.GOLD), "Stair texture was regenerated")
	_check(main._create_ascii_stairs_texture(Color.GOLD) != main._create_ascii_stairs_texture(Color.BLUE), "Stair color cache collided")
	var ui = get_node("/root/PlayerUi")
	_check(ui.level_label.is_inside_tree(), "Compatibility label has no lifecycle owner")
	ui.update_hp(8, 10)
	var hp_tween = ui.current_tween
	for i in range(20):
		ui.update_hp(8, 10)
	_check(ui.current_tween == hp_tween, "Unchanged HP restarted its animation")
	await get_tree().create_timer(0.4).timeout
	_check(is_equal_approx(ui.hp_bar.value, 8.0), "HP animation did not reach target")
	ui.update_hp(7, 10)
	_check(ui.current_tween != hp_tween, "Changed HP did not refresh")
	ui.update_hp(7, 12)
	_check(ui.hp_bar.max_value == 12 and ui.hp_label.text == "7/12", "Changed maximum HP did not refresh")
	_cleanup(main)
	print("OPTIMIZATION_TEST: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _cleanup(main):
	main.map_controller.free()
	main.tile_map.free()
	main.free()

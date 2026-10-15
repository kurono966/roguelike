extends Node

var failures: int = 0

func _ready():
	call_deferred("_run")

func _check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)

func _run():
	# Do not generate a world: construct the real map/pathfinding/movement code.
	var main = load("res://world/main.gd").new()
	main.tile_map = TileMap.new()
	main.player = CharacterBody2D.new()
	main.map_controller = MapController.new()
	main.map_controller.setup(main)
	for x in range(main.MAP_WIDTH):
		var column = []
		column.resize(main.MAP_HEIGHT)
		column.fill(MapDefinitions.CellType.FLOOR)
		main._map_data.append(column)
	var trap_pos = Vector2i(3, 3)
	main._traps[trap_pos] = {"type": "poison_gas", "is_revealed": true}
	main._setup_pathfinding()
	for grid in [main._astar_grid, main._astar_grid_swim, main._astar_grid_fly]:
		var path = grid.get_id_path(Vector2i(2, 3), Vector2i(4, 3))
		_check(path.size() > 2, "No detour around revealed trap")
		_check(not path.has(trap_pos), "Path crossed revealed trap")
	main._update_astar_tile(trap_pos, false)
	_check(main._astar_grid.is_point_solid(trap_pos), "Tile update erased trap avoidance")

	# Every non-player move (pursuit, flee, wander, ally fallback) uses this gate.
	var actor = CharacterBody2D.new()
	actor.position = Vector2(2, 3) * 32
	for group in ["enemies", "npcs", "allies"]:
		actor.add_to_group(group)
		var moved = await main._try_move_character(actor, Vector2.RIGHT)
		_check(not moved and actor.position == Vector2(64, 96), "Actor entered known trap: " + group)
		actor.remove_from_group(group)
	# With only one retreat tile available, do not choose it if it is trapped.
	actor.position = Vector2.ZERO
	var tiny_map = [[MapDefinitions.CellType.FLOOR], [MapDefinitions.CellType.FLOOR]]
	main._traps[Vector2i(1, 0)] = {"is_revealed": true}
	_check(EnemyAI.get_flee_direction(actor, Vector2i(-1, 0), tiny_map, main) == Vector2.ZERO, "Flee direction selected known trap")
	main._traps.erase(Vector2i(1, 0))
	main._traps[trap_pos].is_revealed = false
	main._setup_pathfinding()
	_check(not main._astar_grid.is_point_solid(trap_pos), "Hidden trap leaked into pathfinding")
	_check(main._astar_grid.get_id_path(Vector2i(2, 3), Vector2i(4, 3)).has(trap_pos), "Hidden trap changed route")
	actor.free()
	main.map_controller.free()
	main.tile_map.free()
	main.player.free()
	main.free()
	print("TRAP_AVOIDANCE_TEST: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

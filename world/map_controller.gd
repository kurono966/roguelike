class_name MapController
extends Node

var main_node: Node2D
var tile_map: TileMap
var dungeon_generator: DungeonGenerator

# Map data
var map_data: Array = []
var rooms: Array = []
var visible_tiles: Array = []
var explored_tiles: Array = []

# Pathfinding
var astar_grid: ElevationPathGrid
var astar_grid_swim: ElevationPathGrid
var astar_grid_fly: ElevationPathGrid

# Map state
var current_floor: int = 0
var current_branch: int = 0
var is_on_world_map: bool = false
var world_map_data: Array = []
var world_player_pos: Vector2i = Vector2i.ZERO
var starting_village_pos: Vector2i = Vector2i.ZERO
var dungeon_village_pos: Vector2i = Vector2i.ZERO

# Floor caching
var floor_caches: Dictionary = {}
var overworld_preview_maps: Dictionary = {}

# Constants
const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE
const SWIM_PATH_BLOCKERS = [CellType.WALL, CellType.WOOD_WALL, CellType.LAVA, CellType.PIT, CellType.TREE, CellType.TREE_FRUIT, CellType.ROCK]

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	dungeon_generator = DungeonGenerator.new()
	add_child(dungeon_generator)

func generate_map(floor: int, branch: int, local_type: int = -1, is_starting_village: bool = false, is_dungeon_village: bool = false) -> Dictionary:
	current_floor = floor
	current_branch = branch
	
	if floor == 0:
		var res = dungeon_generator.generate_map(floor, branch, local_type, main_node, is_starting_village, is_dungeon_village)
		map_data = res["map_data"]
		rooms = res["rooms"]
		is_on_world_map = true
		return res
	else:
		var res = dungeon_generator.generate_map(floor, branch, -1, main_node, false, false)
		map_data = res["map_data"]
		rooms = res["rooms"]
		is_on_world_map = false
		return res

func setup_pathfinding():
	# Build each movement mode once, using the live map held by Main.
	if main_node:
		map_data = main_node._map_data
		main_node._height_data = ElevationMap.normalize(main_node._height_data, MAP_WIDTH, MAP_HEIGHT)
		ElevationMap.flatten_roads(main_node._height_data, map_data)
	if astar_grid == null:
		astar_grid = ElevationPathGrid.new()
		astar_grid_swim = ElevationPathGrid.new()
		astar_grid_fly = ElevationPathGrid.new()
	for grid in [astar_grid, astar_grid_swim, astar_grid_fly]:
		grid.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
		grid.cell_size = Vector2.ONE
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.heights = [] if main_node._is_on_world_map else main_node._height_data
		grid.jumping_enabled = false
		if grid.is_dirty():
			grid.update()

	var use_world_map = main_node != null and main_node._is_on_world_map
	var source: Array = main_node._world_map_data if use_world_map else map_data
	var traps: Dictionary = main_node._traps if main_node else {}
	var frozen: Dictionary = main_node._frozen_tiles if main_node else {}
	for x in range(MAP_WIDTH):
		var row: Array = source[x] if x < source.size() and source[x] is Array else []
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			var cell: int = row[y] if y < row.size() else CellType.WALL
			if use_world_map:
				var blocked = y >= row.size() or cell == MapDefinitions.WorldCell.SEA or cell == MapDefinitions.WorldCell.MOUNTAIN
				astar_grid.set_point_solid(pos, blocked)
				astar_grid_swim.set_point_solid(pos, blocked)
				astar_grid_fly.set_point_solid(pos, blocked)
				continue
			var known_trap = traps.has(pos) and traps[pos].get("is_revealed", false)
			_set_path_tile(pos, cell, frozen.has(pos), known_trap)

func _set_path_tile(pos: Vector2i, cell: int, frozen: bool, blocked: bool):
	astar_grid.set_point_solid(pos, blocked or not _can_path_through(cell, frozen, false, false))
	astar_grid_swim.set_point_solid(pos, blocked or not _can_path_through(cell, frozen, true, false))
	astar_grid_fly.set_point_solid(pos, blocked or not _can_path_through(cell, frozen, false, true))

static func _can_path_through(cell: int, frozen: bool, swim: bool, fly: bool) -> bool:
	# Path planning includes doors actors can open; collision is checked on moving.
	if cell in [CellType.WALL, CellType.WOOD_WALL]:
		return false
	if fly:
		return cell not in [CellType.WALL, CellType.WOOD_WALL]
	if swim:
		return cell not in SWIM_PATH_BLOCKERS
	if frozen:
		return true
	match cell:
		CellType.FLOOR, CellType.GRASS, CellType.ASH, CellType.VOLCANIC_ASH, CellType.CRYSTAL_FLOOR, CellType.ICE, CellType.DOOR_OPEN, CellType.DOOR_CLOSED, CellType.STAIRS, CellType.STAIRS_UP, CellType.STAIRS_BLUE, CellType.STAIRS_GREEN, CellType.STAIRS_RED, CellType.STAIRS_PURPLE, CellType.STAIRS_GOLD:
			return true
	return false

func update_pathfinding_tile(pos: Vector2i, make_solid: bool = false):
	if not is_grid_in_bounds(pos):
		return
	var blocked = make_solid or main_node._is_revealed_trap(pos)
	_set_path_tile(pos, main_node._map_data[pos.x][pos.y], main_node._frozen_tiles.has(pos), blocked)

func is_walkable(grid_pos: Vector2i, allow_swim: bool = false, allow_fly: bool = false) -> bool:
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT:
		return false
	if is_on_world_map:
		return true
	
	# Guard against uninitialized or malformed map_data
	if map_data.is_empty():
		return false
	if grid_pos.x >= map_data.size():
		return false
	var row = map_data[grid_pos.x]
	if typeof(row) != TYPE_ARRAY or row.is_empty():
		return false
	if grid_pos.y >= row.size():
		return false
	
	var cell = row[grid_pos.y]
	
	if cell in [CellType.WALL, CellType.WOOD_WALL] or cell == CellType.DOOR_CLOSED or cell == CellType.DOOR_LOCKED:
		return false
	if cell == CellType.WATER and not allow_swim and not allow_fly:
		return false
	if (cell == CellType.LAVA or cell == CellType.PIT) and not allow_fly:
		return false
	if cell == CellType.TREE or cell == CellType.TREE_FRUIT or cell == CellType.ROCK:
		return false
	
	return true

func is_grid_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < MAP_WIDTH and grid_pos.y >= 0 and grid_pos.y < MAP_HEIGHT

func is_stairs_cell(cell_type: int) -> bool:
	return cell_type == CellType.STAIRS or \
		   cell_type == CellType.STAIRS_UP or \
		   cell_type == CellType.STAIRS_BLUE or \
		   cell_type == CellType.STAIRS_GREEN or \
		   cell_type == CellType.STAIRS_RED or \
		   cell_type == CellType.STAIRS_PURPLE or \
		   cell_type == CellType.STAIRS_GOLD

func get_stairs_tooltip(cell_type: int) -> String:
	match cell_type:
		CellType.STAIRS:
			return "通常の階段\n次の通常階層へ降ります。"
		CellType.STAIRS_UP:
			return "上りの階段\n前の階層へ戻ります。"
		CellType.STAIRS_BLUE:
			return "青の階段\n水のダンジョンへ降ります。"
		CellType.STAIRS_GREEN:
			return "緑の階段\n森のダンジョンへ降ります。"
		CellType.STAIRS_RED:
			return "赤の階段\n火山のダンジョンへ降ります。"
		CellType.STAIRS_PURPLE:
			return "紫の階段\n結晶のダンジョンへ降ります。"
		CellType.STAIRS_GOLD:
			return "金色の階段\n始まりのダンジョンへ降ります。"
	return "階段\n次の階層へ降ります。"

func get_random_floor_position() -> Vector2:
	# Guard against uninitialized or malformed map_data
	if map_data.is_empty() or map_data.size() < MAP_WIDTH:
		return Vector2.ZERO
	
	for i in range(100):
		var x = randi_range(1, MAP_WIDTH - 2)
		var y = randi_range(1, MAP_HEIGHT - 2)
		
		# Bounds check before accessing
		if x >= map_data.size() or map_data[x].is_empty() or y >= map_data[x].size():
			continue
		
		var cell = map_data[x][y]
		if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.VOLCANIC_ASH or cell == CellType.CRYSTAL_FLOOR or cell == CellType.ICE:
			var grid_pos = Vector2i(x, y)
			
			# Check if occupied
			var occupied = false
			var player = main_node.player
			if player:
				var p_grid = tile_map.local_to_map(player.position)
				if p_grid == grid_pos:
					occupied = true
			if not occupied:
				if not main_node or not main_node.get_tree():
					continue
				for entity in main_node.get_tree().get_nodes_in_group("entities"):
					if is_instance_valid(entity) and not entity.is_queued_for_deletion():
						var ent_grid = tile_map.local_to_map(entity.position)
						if ent_grid == grid_pos:
							occupied = true
							break
			if not occupied:
				return Vector2(x, y) * TILE_SIZE
	return Vector2.ZERO

func get_center_spawn_pos(fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	var center = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
	if _is_local_spawn_tile(center):
		return center

	var max_radius = maxi(MAP_WIDTH, MAP_HEIGHT)
	for radius in range(1, max_radius):
		for x in range(center.x - radius, center.x + radius + 1):
			for y in range(center.y - radius, center.y + radius + 1):
				if x != center.x - radius and x != center.x + radius and y != center.y - radius and y != center.y + radius:
					continue
				var pos = Vector2i(x, y)
				if _is_local_spawn_tile(pos):
					return pos

	if _is_local_spawn_tile(fallback):
		return fallback
	return center

func _is_local_spawn_tile(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
		return false
	if map_data.is_empty() or pos.x >= map_data.size() or pos.y >= map_data[pos.x].size():
		return false
	var cell = map_data[pos.x][pos.y]
	return cell == CellType.FLOOR or \
				  cell == CellType.GRASS or \
				  cell == CellType.ASH or \
				  cell == CellType.VOLCANIC_ASH or \
				  cell == CellType.CRYSTAL_FLOOR or \
				  cell == CellType.ICE or \
				  is_stairs_cell(cell) or \
				  cell == CellType.DOOR_OPEN or \
				  cell == CellType.DOOR_CLOSED

func count_explored_tiles() -> int:
	var count = 0
	# Guard against uninitialized or malformed explored_tiles
	if explored_tiles.is_empty() or explored_tiles.size() < MAP_WIDTH:
		return 0
	
	for x in range(MAP_WIDTH):
		if x >= explored_tiles.size() or explored_tiles[x].is_empty():
			continue
		
		for y in range(MAP_HEIGHT):
			if y >= explored_tiles[x].size():
				continue
			if explored_tiles[x][y]:
				count += 1
	return count

func find_path_to_nearest_stairs(start_grid: Vector2i) -> Array:
	if start_grid.x < 0 or start_grid.x >= MAP_WIDTH or start_grid.y < 0 or start_grid.y >= MAP_HEIGHT:
		return []

	var nearest_stairs_pos = null
	var nearest_dist = INF

	for x in range(MAP_WIDTH):
		# Skip if row doesn't exist or is empty
		if x >= map_data.size() or map_data[x].is_empty():
			continue
		
		for y in range(MAP_HEIGHT):
			# Skip if y is out of bounds
			if y >= map_data[x].size():
				continue
			
			if is_stairs_cell(map_data[x][y]):
				var stairs_pos = Vector2i(x, y)
				var dist = start_grid.distance_to(stairs_pos)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_stairs_pos = stairs_pos

	if nearest_stairs_pos == null:
		return []

	return astar_grid.get_id_path(start_grid, nearest_stairs_pos)

func find_path_to_nearest_unexplored(start_grid: Vector2i) -> Array:
	if start_grid.x < 0 or start_grid.x >= MAP_WIDTH or start_grid.y < 0 or start_grid.y >= MAP_HEIGHT:
		return []

	var nearest_unexplored = null
	var nearest_dist = INF

	for x in range(MAP_WIDTH):
		# Skip if row doesn't exist or is empty
		if x >= map_data.size() or map_data[x].is_empty():
			continue
		
		for y in range(MAP_HEIGHT):
			# Skip if y is out of bounds
			if y >= map_data[x].size():
				continue
			
			if not explored_tiles[x][y] and map_data[x][y] not in [CellType.WALL, CellType.WOOD_WALL]:
				var pos = Vector2i(x, y)
				var dist = start_grid.distance_to(pos)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_unexplored = pos

	if nearest_unexplored == null:
		return []

	return astar_grid.get_id_path(start_grid, nearest_unexplored)

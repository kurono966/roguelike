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
var astar_grid: AStarGrid2D
var astar_grid_swim: AStarGrid2D
var astar_grid_fly: AStarGrid2D

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
	# main側で直接生成されたマップデータも反映する（map_controllerを経由しない生成フロー対策）
	if main_node:
		var main_map = main_node.get("_map_data")
		if typeof(main_map) == TYPE_ARRAY and main_map.size() >= MAP_WIDTH:
			map_data = main_map

	astar_grid = AStarGrid2D.new()
	astar_grid_swim = AStarGrid2D.new()
	astar_grid_fly = AStarGrid2D.new()
	
	_setup_astar_grid(astar_grid, false, false)
	_setup_astar_grid(astar_grid_swim, true, false)
	_setup_astar_grid(astar_grid_fly, false, true)

func _setup_astar_grid(grid: AStarGrid2D, allow_swim: bool, allow_fly: bool):
	# Guard against uninitialized or malformed map_data
	if map_data.is_empty() or map_data.size() < MAP_WIDTH:
		grid.update()
		return
	
	grid.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	
	for x in range(MAP_WIDTH):
		# Check if row exists
		if x >= map_data.size():
			for y in range(MAP_HEIGHT):
				grid.set_point_solid(Vector2i(x, y), true)
			continue
		
		var row = map_data[x]
		# Check if row is a valid non-empty array
		if typeof(row) != TYPE_ARRAY or row.size() == 0:
			for y in range(MAP_HEIGHT):
				grid.set_point_solid(Vector2i(x, y), true)
			continue
		
		for y in range(MAP_HEIGHT):
			if y >= row.size():
				grid.set_point_solid(Vector2i(x, y), true)
				continue
			var cell = row[y]
			var is_solid = cell == CellType.WALL or cell == CellType.DOOR_CLOSED or cell == CellType.DOOR_LOCKED
			
			if not is_solid:
				if cell == CellType.WATER and not allow_swim and not allow_fly:
					is_solid = true
				elif (cell == CellType.LAVA or cell == CellType.PIT) and not allow_fly:
					is_solid = true
				elif cell == CellType.TREE or cell == CellType.TREE_FRUIT or cell == CellType.ROCK:
					is_solid = true
			
			grid.set_point_solid(Vector2i(x, y), is_solid)

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
	
	if cell == CellType.WALL or cell == CellType.DOOR_CLOSED or cell == CellType.DOOR_LOCKED:
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
			
			if not explored_tiles[x][y] and map_data[x][y] != CellType.WALL:
				var pos = Vector2i(x, y)
				var dist = start_grid.distance_to(pos)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_unexplored = pos

	if nearest_unexplored == null:
		return []

	return astar_grid.get_id_path(start_grid, nearest_unexplored)

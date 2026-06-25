class_name VisibilityManager
extends Node

var main_node: Node2D
var player
var tile_map: TileMap
var memory_tile_map: TileMap
var map_data: Array
var visible_tiles: Array
var explored_tiles: Array
var burning_grass: Dictionary
var frozen_tiles: Dictionary
var steam_tiles: Dictionary

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE
const FOV_RADIUS = 8
const STEAM_FOV_RADIUS = 3
var current_fov_radius = FOV_RADIUS

const LAYER_VISIBLE = 0
const LAYER_MEMORY = 1

func setup(main: Node2D):
	main_node = main
	player = main.player
	tile_map = main.tile_map
	if "memory_tile_map" in main:
		memory_tile_map = main.memory_tile_map
	# Arrays will be assigned later after map generation

func calculate_fov():
	if not is_instance_valid(player):
		player = main_node.get_node_or_null("Player")
	if not is_instance_valid(player):
		return
	var player_grid_pos = tile_map.local_to_map(player.position)
	current_fov_radius = STEAM_FOV_RADIUS if steam_tiles.has(player_grid_pos) else FOV_RADIUS
	
	# Reset visibility
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			visible_tiles[x][y] = false
			
	# Player's own tile is always visible
	visible_tiles[player_grid_pos.x][player_grid_pos.y] = true
	explored_tiles[player_grid_pos.x][player_grid_pos.y] = true

	# Debug Class Magic Eye (Reveal All)
	var gs = main_node.get_node_or_null("/root/GameState")
	if gs and gs.player_class == 99:
		for x in range(MAP_WIDTH):
			for y in range(MAP_HEIGHT):
				visible_tiles[x][y] = true
				explored_tiles[x][y] = true
		update_entity_visibility()
		return


	# Scan all 8 octants
	for i in range(8):
		_cast_light_octant(player_grid_pos, 1, 1.0, 0.0,
			_get_transform(i).x.x, _get_transform(i).x.y,
			_get_transform(i).y.x, _get_transform(i).y.y)

	# Ensure minimum 2-tile radius visibility (for hallways)
	var hall_vis_range = 2
	for x in range(player_grid_pos.x - hall_vis_range, player_grid_pos.x + hall_vis_range + 1):
		for y in range(player_grid_pos.y - hall_vis_range, player_grid_pos.y + hall_vis_range + 1):
			if x >= 0 and x < MAP_WIDTH and y >= 0 and y < MAP_HEIGHT:
				if main_node._has_line_of_sight(player_grid_pos, Vector2i(x, y)):
					visible_tiles[x][y] = true
					explored_tiles[x][y] = true

	update_entity_visibility()

func update_entity_visibility():
	var entities = main_node.get_tree().get_nodes_in_group("entities")
	for entity in entities:
		update_single_entity_visibility(entity)
		
	# Update Torch Visibility
	for torch in main_node.get_tree().get_nodes_in_group("torches"):
		var grid_pos = tile_map.local_to_map(torch.position)
		if grid_pos.x >= 0 and grid_pos.x < MAP_WIDTH and grid_pos.y >= 0 and grid_pos.y < MAP_HEIGHT:
			torch.visible = visible_tiles[grid_pos.x][grid_pos.y]
		else:
			torch.visible = false

func is_entity_visible_to_player(entity: Node2D) -> bool:
	if not is_instance_valid(entity) or not is_instance_valid(player):
		return false
	if entity == player:
		return true
		
	var grid_pos = tile_map.local_to_map(entity.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
	
	if grid_pos.x >= 0 and grid_pos.x < MAP_WIDTH and grid_pos.y >= 0 and grid_pos.y < MAP_HEIGHT:
		var is_visible = visible_tiles[grid_pos.x][grid_pos.y]
		
		# 草むらのステルス判定: 隣接していない、かつ「千里眼」スキルがない場合は敵を非表示にする
		if is_visible and map_data[grid_pos.x][grid_pos.y] == CellType.GRASS:
			if entity.is_in_group("enemies"):
				var player_grid_pos = tile_map.local_to_map(player.position)
				var dist_x = abs(grid_pos.x - player_grid_pos.x)
				var dist_y = abs(grid_pos.y - player_grid_pos.y)
				
				var has_special_skill = ("known_skills" in player and player.known_skills.has("clairvoyance"))
				
				# 草むらの認識距離判定
				var max_recognition_dist = 1
				var gs = main_node.get_node_or_null("/root/GameState")
				if gs and gs.player_class == 2: # Rogue
					max_recognition_dist = 3
				
				if dist_x > max_recognition_dist or dist_y > max_recognition_dist:
					if not has_special_skill:
						is_visible = false
		return is_visible
	return false

func update_single_entity_visibility(entity):
	if not is_instance_valid(entity): return
	if entity == player: return
	
	entity.visible = is_entity_visible_to_player(entity)


func _cast_light_octant(origin: Vector2i, row: int, start_slope: float, end_slope: float, xx: int, xy: int, yx: int, yy: int):
	if start_slope < end_slope:
		return

	var new_start_slope = start_slope
	var blocked = false
	
	for col in range(row, current_fov_radius + 1):
		var dx = -col
		for dy in range(-col, 1):
			var current_x = origin.x + dx * xx + dy * xy
			var current_y = origin.y + dx * yx + dy * yy
			
			var left_slope = (dy - 0.5) / (dx + 0.5)
			var right_slope = (dy + 0.5) / (dx - 0.5)
			
			if new_start_slope < right_slope:
				continue
			elif end_slope > left_slope:
				break
			
			# Check bounds and set visibility
			if current_x >= 0 and current_x < MAP_WIDTH and current_y >= 0 and current_y < MAP_HEIGHT:
				if (Vector2i(current_x, current_y) - origin).length() <= current_fov_radius:
					visible_tiles[current_x][current_y] = true
					explored_tiles[current_x][current_y] = true

					if blocked: # Previous cell was blocked
						var is_opaque = map_data[current_x][current_y] == CellType.WALL or \
										map_data[current_x][current_y] == CellType.DOOR_CLOSED or \
										map_data[current_x][current_y] == CellType.TREE or \
										map_data[current_x][current_y] == CellType.TREE_FRUIT or \
										map_data[current_x][current_y] == CellType.ROCK or \
										steam_tiles.has(Vector2i(current_x, current_y))
						if is_opaque:
							new_start_slope = right_slope
							continue
						else:
							blocked = false
							new_start_slope = right_slope
					else:
						var is_blocking = map_data[current_x][current_y] == CellType.WALL or \
										map_data[current_x][current_y] == CellType.DOOR_CLOSED or \
										map_data[current_x][current_y] == CellType.TREE or \
										map_data[current_x][current_y] == CellType.TREE_FRUIT or \
										map_data[current_x][current_y] == CellType.ROCK or \
										steam_tiles.has(Vector2i(current_x, current_y))
						if is_blocking and col < current_fov_radius:
							blocked = true
							_cast_light_octant(origin, col + 1, new_start_slope, left_slope, xx, xy, yx, yy)
							new_start_slope = right_slope
			else: # Out of bounds
				break
				
func _get_transform(octant: int) -> Transform2D:
	# Returns a transform for mapping coordinates to each octant
	match octant:
		0: return Transform2D(Vector2(1, 0),  Vector2(0, 1), Vector2.ZERO)
		1: return Transform2D(Vector2(0, 1),  Vector2(1, 0), Vector2.ZERO)
		2: return Transform2D(Vector2(0, -1), Vector2(1, 0), Vector2.ZERO)
		3: return Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO)
		4: return Transform2D(Vector2(-1, 0), Vector2(0, -1), Vector2.ZERO)
		5: return Transform2D(Vector2(0, -1), Vector2(-1, 0), Vector2.ZERO)
		6: return Transform2D(Vector2(0, 1),  Vector2(-1, 0), Vector2.ZERO)
		7: return Transform2D(Vector2(1, 0),  Vector2(0, -1), Vector2.ZERO)
	return Transform2D() # Should not happen

func draw_map():
	tile_map.clear_layer(LAYER_VISIBLE)
	tile_map.clear_layer(LAYER_MEMORY)
	if is_instance_valid(memory_tile_map):
		memory_tile_map.clear()
	
	# Clear old fire overlays
	main_node.get_tree().call_group("fire_overlays", "queue_free")
	if main_node.has_method("_draw_overworld_neighbor_previews"):
		main_node._draw_overworld_neighbor_previews()
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if explored_tiles[x][y]:
				var cell_type = map_data[x][y]
				var tile_coords = Vector2i(x, y)
				var atlas_coords = Vector2i(0, 0)
				
				match cell_type:
					CellType.WALL:
						# Calculate neighbor bitmask for connecting walls
						var mask = 0
						# N=1, E=2, S=4, W=8
						if y > 0 and map_data[x][y-1] == CellType.WALL: mask |= 1
						if x < MAP_WIDTH - 1 and map_data[x+1][y] == CellType.WALL: mask |= 2
						if y < MAP_HEIGHT - 1 and map_data[x][y+1] == CellType.WALL: mask |= 4
						if x > 0 and map_data[x-1][y] == CellType.WALL: mask |= 8
						atlas_coords.x = mask
					CellType.FLOOR:
						atlas_coords.x = 16
					CellType.STAIRS:
						atlas_coords.x = 17
					CellType.WATER:
						# Calculate neighbor bitmask for connecting water
						var mask = 0
						if y > 0 and map_data[x][y-1] == CellType.WATER: mask |= 1
						if x < MAP_WIDTH - 1 and map_data[x+1][y] == CellType.WATER: mask |= 2
						if y < MAP_HEIGHT - 1 and map_data[x][y+1] == CellType.WATER: mask |= 4
						if x > 0 and map_data[x-1][y] == CellType.WATER: mask |= 8
						atlas_coords.x = 18 + mask
					CellType.GRASS:
						atlas_coords.x = 34
					CellType.STAIRS_BLUE:
						atlas_coords.x = 35
					CellType.STAIRS_GREEN:
						atlas_coords.x = 16  # Use floor for STAIRS_GREEN (not implemented yet)
					CellType.LAVA:
						atlas_coords.x = 40
					CellType.ASH:
						atlas_coords.x = 41
					CellType.CRYSTAL_FLOOR:
						var crystal_mask = 0
						if y > 0 and map_data[x][y-1] == CellType.CRYSTAL_FLOOR: crystal_mask |= 1
						if x < MAP_WIDTH - 1 and map_data[x+1][y] == CellType.CRYSTAL_FLOOR: crystal_mask |= 2
						if y < MAP_HEIGHT - 1 and map_data[x][y+1] == CellType.CRYSTAL_FLOOR: crystal_mask |= 4
						if x > 0 and map_data[x-1][y] == CellType.CRYSTAL_FLOOR: crystal_mask |= 8
						atlas_coords.x = 45 + crystal_mask
					CellType.STAIRS_RED:
						atlas_coords.x = 43
					CellType.STAIRS_PURPLE:
						atlas_coords.x = 44
					CellType.TREE:
						atlas_coords.x = 80
					CellType.TREE_FRUIT:
						atlas_coords.x = 81
					CellType.ROCK:
						atlas_coords.x = 82
					CellType.DOOR_CLOSED:
						atlas_coords.x = 36
					CellType.DOOR_OPEN:
						atlas_coords.x = 37
					9:  # DOOR_LOCKED (using integer value to bypass enum matching issues)
						atlas_coords.x = 38
					10:  # ICE (using integer value to bypass enum matching issues)
						atlas_coords.x = 39
					_:
						# Default to floor for unknown cell types
						atlas_coords.x = 16
				
				if visible_tiles[x][y]:
					tile_map.set_cell(LAYER_VISIBLE, tile_coords, 0, atlas_coords)
					
					var pos = Vector2i(x, y)
					
					# Tint burning grass tiles red
					if burning_grass.has(pos):
						var fire_overlay = ColorRect.new()
						fire_overlay.color = Color(1.0, 0.3, 0.0, 0.5)
						fire_overlay.size = Vector2(TILE_SIZE, TILE_SIZE)
						fire_overlay.position = Vector2(tile_coords) * TILE_SIZE
						fire_overlay.add_to_group("fire_overlays")
						main_node.add_child(fire_overlay)
					
					# Tint frozen tiles light blue
					if frozen_tiles.has(pos):
						var frost_overlay = ColorRect.new()
						frost_overlay.color = Color(0.5, 0.8, 1.0, 0.4)
						frost_overlay.size = Vector2(TILE_SIZE, TILE_SIZE)
						frost_overlay.position = Vector2(tile_coords) * TILE_SIZE
						frost_overlay.add_to_group("fire_overlays") # Repurposing group for easy clearing
						main_node.add_child(frost_overlay)
						
					# Show steam as semi-transparent white
					if steam_tiles.has(pos):
						var steam_overlay = ColorRect.new()
						steam_overlay.color = Color(0.9, 0.9, 0.9, 0.75)
						steam_overlay.size = Vector2(TILE_SIZE, TILE_SIZE)
						steam_overlay.position = Vector2(tile_coords) * TILE_SIZE
						steam_overlay.add_to_group("fire_overlays")
						main_node.add_child(steam_overlay)
				else:
					if is_instance_valid(memory_tile_map):
						memory_tile_map.set_cell(0, tile_coords, 0, atlas_coords)
					else:
						tile_map.set_cell(LAYER_MEMORY, tile_coords, 0, atlas_coords)
			else:
				# Clear cells that are NOT explored
				tile_map.set_cell(LAYER_VISIBLE, Vector2i(x, y), -1)
				tile_map.set_cell(LAYER_MEMORY, Vector2i(x, y), -1)
				if is_instance_valid(memory_tile_map):
					memory_tile_map.set_cell(0, Vector2i(x, y), -1)

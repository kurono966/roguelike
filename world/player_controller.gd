class_name PlayerController
extends Node

var main_node: Node2D
var player: CharacterBody2D
var tile_map: TileMap
var map_controller: MapController

# Movement state
var is_auto_moving: bool = false
var auto_move_direction: Vector2 = Vector2.ZERO
var auto_move_initial_mask: int = 0
var last_player_grid_pos: Vector2i = Vector2i.ZERO

# Path following
var is_path_following: bool = false
var current_path: Array = []
var path_index: int = 0
var path_stop_on_new_enemy: bool = true
var path_continue_after_attack: bool = false
var enemies_at_path_start: int = 0

# Auto explore
var is_auto_exploring: bool = false
var auto_explore_path: Array = []
var auto_explore_index: int = 0

# Resting
var is_resting: bool = false
var rest_target_hp: bool = false
var rest_target_mp: bool = false

# Constants
const AUTO_MOVE_DELAY: float = 0.02
var auto_move_cooldown: float = 0.0
var is_processing_action: bool = false

const TILE_SIZE = MapDefinitions.TILE_SIZE
const CellType = MapDefinitions.CellType

func setup(main: Node2D):
	main_node = main
	player = main.player
	tile_map = main.tile_map
	map_controller = main.map_controller

func try_move_player(direction: Vector2) -> bool:
	if is_processing_action:
		return false
	
	is_processing_action = true
	
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = player_grid + Vector2i(int(direction.x), int(direction.y))
	
	# Check bounds
	if target_grid.x < 0 or target_grid.x >= MapDefinitions.MAP_WIDTH or target_grid.y < 0 or target_grid.y >= MapDefinitions.MAP_HEIGHT:
		is_processing_action = false
		return false
	
	if not main_node.can_step_height(player_grid, target_grid):
		is_processing_action = false
		return false

	# Check for enemy to attack
	if _try_attack_adjacent_enemy():
		is_processing_action = false
		return true
	
	# Check if walkable
	if not map_controller.is_walkable(target_grid, player.can_swim):
		is_processing_action = false
		return false
	
	# Check for door interaction
	var cell = map_controller.map_data[target_grid.x][target_grid.y]
	if cell == CellType.DOOR_CLOSED:
		_try_open_door(target_grid)
		is_processing_action = false
		return true
	
	# Move player
	player.move_to_grid(target_grid)
	last_player_grid_pos = player_grid
	
	# Update terrain info
	_update_player_terrain_info(target_grid)
	
	is_processing_action = false
	return true

func _try_attack_adjacent_enemy() -> bool:
	var player_grid = tile_map.local_to_map(player.position)
	
	# Check for current target
	var current_target = main_node._current_target_enemy
	if current_target and is_instance_valid(current_target):
		var is_friendly = current_target.is_in_group("allies") or (current_target.is_in_group("npcs") and not current_target.is_in_group("enemies"))
		if not is_friendly:
			var target_grid = tile_map.local_to_map(current_target.position)
			var diff = target_grid - player_grid
			if _can_player_recognize_entity(current_target) and abs(diff.x) <= 1 and abs(diff.y) <= 1 and (abs(diff.x) + abs(diff.y) > 0):
				main_node._handle_attack(player, current_target)
				return true
	
	# Check for other adjacent enemies
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, 
					  Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	
	for dir in directions:
		var check_pos = player_grid + dir
		if not main_node or not main_node.get_tree():
			continue
		var targets = main_node.get_tree().get_nodes_in_group("enemies") + main_node.get_tree().get_nodes_in_group("npcs")
		
		for child in targets:
			if not is_instance_valid(child) or child.is_queued_for_deletion(): continue
			if not (child is Node2D): continue
			
			var is_friendly = child.is_in_group("allies") or (child.is_in_group("npcs") and not child.is_in_group("enemies"))
			if is_friendly: continue
			
			var enemy_grid = tile_map.local_to_map(child.position)
			
			if enemy_grid == check_pos:
				if not _can_player_recognize_entity(child):
					continue
				
				if check_pos.x >= 0 and check_pos.x < MapDefinitions.MAP_WIDTH and \
				   check_pos.y >= 0 and check_pos.y < MapDefinitions.MAP_HEIGHT and \
				   map_controller.visible_tiles[check_pos.x][check_pos.y]:
					main_node._handle_attack(player, child)
					return true
	
	return false

func _can_player_recognize_entity(entity) -> bool:
	if main_node.visibility_manager:
		return main_node.visibility_manager.is_entity_visible_to_player(entity)
	return false

func _try_open_door(door_grid: Vector2i):
	var cell = map_controller.map_data[door_grid.x][door_grid.y]
	if cell == CellType.DOOR_CLOSED:
		map_controller.map_data[door_grid.x][door_grid.y] = CellType.DOOR_OPEN
		main_node.tileset_manager.update_tile(door_grid.x, door_grid.y, cell)
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("ドアを開けた", Color.WHITE)

func _update_player_terrain_info(grid_pos: Vector2i):
	var cell = map_controller.map_data[grid_pos.x][grid_pos.y]
	
	player.is_on_water = (cell == CellType.WATER)
	player.is_in_grass = (cell == CellType.GRASS)
	
	if player.has_method("update_on_grass"):
		player.update_on_grass(cell == CellType.GRASS)

func start_auto_move(direction: Vector2):
	is_auto_moving = true
	auto_move_direction = direction
	
	var current_grid = tile_map.local_to_map(player.position)
	auto_move_initial_mask = _get_walkable_mask(current_grid)
	
	_continue_auto_move()

func _get_walkable_mask(grid_pos: Vector2i) -> int:
	var mask = 0
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for i in range(dirs.size()):
		if map_controller.is_walkable(grid_pos + dirs[i], player.can_swim):
			mask |= (1 << i)
	return mask

func _continue_auto_move():
	if auto_move_cooldown > 0.0: return
	if is_processing_action: return
	
	var current_grid = tile_map.local_to_map(player.position)
	var target_grid = current_grid + Vector2i(int(auto_move_direction.x), int(auto_move_direction.y))
	
	# Check if should stop
	var current_mask = _get_walkable_mask(current_grid)
	if current_mask != auto_move_initial_mask:
		stop_auto_move()
		return
	
	# Try move
	if try_move_player(auto_move_direction):
		auto_move_cooldown = AUTO_MOVE_DELAY
	else:
		stop_auto_move()

func stop_auto_move():
	is_auto_moving = false
	auto_move_direction = Vector2.ZERO

func start_path_following(target_grid: Vector2i):
	if is_processing_action:
		return
	
	var player_grid = tile_map.local_to_map(player.position)
	
	if not map_controller.is_walkable(target_grid, player.can_swim):
		return
	
	var path_grid = map_controller.astar_grid
	if not map_controller.is_on_world_map and player.can_swim:
		path_grid = map_controller.astar_grid_swim
	
	var path = path_grid.get_id_path(player_grid, target_grid)
	
	if path.size() > 1:
		var enemies_in_view = _get_visible_enemies()
		enemies_at_path_start = enemies_in_view.size()
		
		current_path = path
		path_index = 1
		path_stop_on_new_enemy = true
		path_continue_after_attack = false
		is_path_following = true

func _continue_path_following():
	if auto_move_cooldown > 0.0: return
	if is_processing_action: return
	
	if path_index >= current_path.size():
		stop_path_following()
		return
	
	# Check for new enemies
	if path_stop_on_new_enemy:
		var current_enemies = _get_visible_enemies()
		if current_enemies.size() > enemies_at_path_start:
			stop_path_following()
			return
	
	var target_grid = current_path[path_index]
	var player_grid = tile_map.local_to_map(player.position)
	var direction = Vector2(target_grid - player_grid)
	
	if try_move_player(direction):
		path_index += 1
		auto_move_cooldown = AUTO_MOVE_DELAY
	else:
		# Try to attack if enemy in the way
		if _try_attack_adjacent_enemy():
			if not path_continue_after_attack:
				stop_path_following()
		else:
			stop_path_following()

func stop_path_following():
	is_path_following = false
	current_path.clear()
	path_index = 0

func _get_visible_enemies() -> Array:
	var visible_enemies = []
	if not main_node or not main_node.get_tree():
		return visible_enemies
	var enemies = main_node.get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if _can_player_recognize_entity(enemy):
			visible_enemies.append(enemy)
	
	return visible_enemies

func start_auto_explore():
	if is_processing_action:
		return
	
	var player_grid = tile_map.local_to_map(player.position)
	auto_explore_path = map_controller.find_path_to_nearest_unexplored(player_grid)
	
	if auto_explore_path.size() > 1:
		is_auto_exploring = true
		auto_explore_index = 1
		_continue_auto_explore()

func _continue_auto_explore():
	if not is_auto_exploring:
		return
	if auto_move_cooldown > 0.0:
		return
	if is_processing_action:
		return
	
	if auto_explore_index >= auto_explore_path.size():
		# Find new target
		var player_grid = tile_map.local_to_map(player.position)
		auto_explore_path = map_controller.find_path_to_nearest_unexplored(player_grid)
		if auto_explore_path.size() <= 1:
			stop_auto_explore("探索完了")
			return
		auto_explore_index = 1
	
	var target_grid = auto_explore_path[auto_explore_index]
	var player_grid = tile_map.local_to_map(player.position)
	var direction = Vector2(target_grid - player_grid)
	
	if try_move_player(direction):
		auto_explore_index += 1
		auto_move_cooldown = AUTO_MOVE_DELAY
	else:
		# Try to attack if enemy in the way
		if _try_attack_adjacent_enemy():
			pass
		else:
			stop_auto_explore("探索を中断")

func stop_auto_explore(reason: String = ""):
	var was_running = is_auto_exploring
	is_auto_exploring = false
	auto_explore_path.clear()
	auto_explore_index = 0
	
	if was_running and reason != "":
		var log_ui = main_node.get_node_or_null("/root/LogUI")
		if log_ui and log_ui.has_method("add_log"):
			log_ui.add_log(reason, Color(1.0, 0.8, 0.4))

func start_rest(target_hp: bool = false, target_mp: bool = false):
	is_resting = true
	rest_target_hp = target_hp
	rest_target_mp = target_mp
	_continue_rest()

func _continue_rest():
	if not is_resting:
		return
	
	# Check if rest is complete
	if rest_target_hp and player.hp >= player.max_hp:
		stop_rest("HPが全回復した")
		return
	if rest_target_mp and player.mp >= player.max_mp:
		stop_rest("MPが全回復した")
		return
	if not rest_target_hp and not rest_target_mp:
		# Rest until fully healed
		if player.hp >= player.max_hp and player.mp >= player.max_mp:
			stop_rest("全回復した")
			return
	
	# Check for nearby enemies
	var nearby_enemies = _get_visible_enemies()
	if nearby_enemies.size() > 0:
		stop_rest("敵が近くにいるため休憩を中止")
		return
	
	# End turn to rest
	await main_node._end_player_turn()

func stop_rest(reason: String = ""):
	var was_resting = is_resting
	is_resting = false
	rest_target_hp = false
	rest_target_mp = false
	
	if was_resting and reason != "":
		var log_ui = main_node.get_node_or_null("/root/LogUI")
		if log_ui and log_ui.has_method("add_log"):
			log_ui.add_log(reason, Color(0.3, 1.0, 0.3))

func process(delta):
	if auto_move_cooldown > 0.0:
		auto_move_cooldown -= delta
	
	if is_auto_moving:
		_continue_auto_move()
	
	if is_path_following:
		_continue_path_following()
	
	if is_auto_exploring:
		_continue_auto_explore()
	
	if is_resting and main_node._current_game_state == main_node.TurnPhase.PLAYER_TURN:
		_continue_rest()

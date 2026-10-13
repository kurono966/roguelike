class_name ItemManager
extends Node

var main_node: Node2D
var tile_map: TileMap
var map_controller: MapController

const WorldItemScene = preload("res://items/world_item.tscn")
const ItemDatabase = preload("res://items/item_database.gd")
const TorchScene = preload("res://items/torch.tscn")

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	map_controller = main.map_controller

func spawn_items_for_floor(floor: int, rooms: Array):
	if floor == 0:
		return
	
	var items_per_room = randi_range(1, 3)
	
	for room in rooms:
		for i in range(items_per_room):
			_spawn_item_in_room(room)

func _spawn_item_in_room(room: Rect2i):
	var item = _get_random_item(main_node.current_floor)
	if not item:
		return
	
	var spawn_pos = _get_random_position_in_room(room)
	if spawn_pos == Vector2i.ZERO:
		return
	
	spawn_world_item(item, Vector2(spawn_pos) * TILE_SIZE)

func _get_random_item(floor: int = 1) -> BaseItem:
	if main_node.current_branch == 10:
		return ItemDatabase.get_beginner_item(floor)
	
	return ItemDatabase.get_random_item(floor)

func _get_random_position_in_room(room: Rect2i) -> Vector2i:
	for attempt in range(50):
		var x = randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
		var y = randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		var pos = Vector2i(x, y)
		
		if not map_controller.is_grid_in_bounds(pos):
			continue
		
		var cell = map_controller.map_data[pos.x][pos.y]
		if cell != CellType.FLOOR and cell != CellType.GRASS:
			continue
		
		# Check if item already exists at position
		if get_item_at_grid(pos) != null:
			continue
		
		return pos
	
	return Vector2i.ZERO

func spawn_world_item(item: BaseItem, world_pos: Vector2):
	var grid_pos = tile_map.local_to_map(world_pos)
	var target_grid = find_nearest_empty_cell(grid_pos)
	
	if target_grid == Vector2i(-1, -1):
		print("No valid position for item: ", item.name)
		return
	
	var world_item = WorldItemScene.instantiate()
	world_item.position = Vector2(target_grid) * TILE_SIZE
	world_item.set_item(item)
	world_item.add_to_group("items")
	world_item.add_to_group("entities")
	
	main_node.add_child(world_item)
	print("Spawned item: ", item.name, " at ", target_grid)
	
	# Trigger trap if item is dropped on it
	if main_node.hazard_manager and main_node._traps.has(target_grid):
		main_node.hazard_manager.trigger_trap(target_grid, world_item)

func place_item_at_player(item: BaseItem):
	if not main_node.player:
		return
	
	spawn_world_item(item, main_node.player.position)

func get_item_at_player_position() -> Node2D:
	var player_grid = tile_map.local_to_map(main_node.player.position)
	return get_item_at_grid(player_grid)

func get_item_at_grid(grid_pos: Vector2i) -> Node2D:
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			continue
		
		var item_grid = tile_map.local_to_map(item.position)
		if item_grid == grid_pos:
			return item
	
	return null

func find_nearest_empty_cell(start_grid: Vector2i, max_radius: int = 3) -> Vector2i:
	if _is_grid_valid_for_item(start_grid) and get_item_at_grid(start_grid) == null:
		return start_grid
	
	for radius in range(1, max_radius + 1):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				if x == 0 and y == 0:
					continue
				
				var pos = start_grid + Vector2i(x, y)
				if _is_grid_valid_for_item(pos) and get_item_at_grid(pos) == null:
					return pos
	
	return Vector2i(-1, -1)

func _is_grid_valid_for_item(pos: Vector2i) -> bool:
	if not map_controller.is_grid_in_bounds(pos):
		return false
	
	var cell = map_controller.map_data[pos.x][pos.y]
	
	return cell != CellType.WALL and \
		   cell != CellType.WATER and \
		   cell != CellType.LAVA and \
		   cell != CellType.TREE and \
		   cell != CellType.TREE_FRUIT and \
		   cell != CellType.ROCK

func spawn_torches_for_floor(rooms: Array):
	if main_node.current_floor == 0:
		return
	
	var torches_per_room = randi_range(0, 2)
	
	for room in rooms:
		for i in range(torches_per_room):
			_spawn_torch_in_room(room)

func _spawn_torch_in_room(room: Rect2i):
	var spawn_pos = _get_random_position_in_room(room)
	if spawn_pos == Vector2i.ZERO:
		return
	
	var torch = TorchScene.instantiate()
	torch.position = Vector2(spawn_pos) * TILE_SIZE
	torch.add_to_group("torches")
	
	main_node.add_child(torch)
	print("Spawned torch at ", spawn_pos)

func remove_all_items():
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item):
			item.queue_free()
	
	for torch in main_node.get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.queue_free()

func get_nearby_items(player_grid: Vector2i, radius: int = 1) -> Array:
	var nearby_items = []
	
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			continue
		
		var item_grid = tile_map.local_to_map(item.position)
		var dist = player_grid.distance_to(item_grid)
		
		if dist <= radius:
			nearby_items.append(item)
	
	return nearby_items

func pickup_item(item: Node2D) -> bool:
	if not is_instance_valid(item):
		return false
	
	var item_data = item.item_data
	if not item_data:
		return false
	
	var player = main_node.player
	if not player or not player.equipment_component:
		return false
	
	# Try to add to bag first
	if player.equipment_component.add_to_bag(item_data):
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%sを拾った" % item_data.name, Color.WHITE)
		
		item.queue_free()
		return true
	
	# Try to equip if bag is full
	if player.equipment_component.equip_item(item_data):
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("%sを装備した" % item_data.name, Color.WHITE)
		
		item.queue_free()
		return true
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("インベントリがいっぱいです", Color.RED)
	
	return false

func drop_item(item: BaseItem, player_position: Vector2):
	spawn_world_item(item, player_position)

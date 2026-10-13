class_name WorldMapManager
extends Node

var main_node: Node2D
var tile_map: TileMap
var player: Node2D

const WorldCell = MapDefinitions.WorldCell
const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	player = main.player

func init_world_map():
	var generator = DungeonGenerator.new()
	var world_map_data = generator.generate_world_map()
	
	var start_pos = Vector2i.ZERO
	var found_village = false
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if world_map_data[x][y] == WorldCell.VILLAGE:
				start_pos = Vector2i(x, y)
				found_village = true
				break
		if found_village: break
		
	if not found_village:
		for x in range(MAP_WIDTH):
			for y in range(MAP_HEIGHT):
				if world_map_data[x][y] == WorldCell.GRASS:
					start_pos = Vector2i(x, y)
					found_village = true
					break
			if found_village: break
			
	main_node._world_player_pos = start_pos
	main_node._starting_village_pos = start_pos
	main_node._is_on_world_map = false
	main_node._world_map_data = world_map_data
	
	# Find other villages to assign the dungeon village
	var other_villages = []
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if world_map_data[x][y] == WorldCell.VILLAGE and Vector2i(x, y) != start_pos:
				other_villages.append(Vector2i(x, y))
	
	if not other_villages.is_empty():
		main_node._dungeon_village_pos = other_villages.pick_random()
	else:
		# If no other villages, place dungeon village randomly but far from start
		var placed = false
		for _i in range(100):
			var x = randi_range(5, MAP_WIDTH - 6)
			var y = randi_range(5, MAP_HEIGHT - 6)
			var pos = Vector2i(x, y)
			if pos.distance_to(start_pos) > 15:
				main_node._dungeon_village_pos = pos
				world_map_data[x][y] = WorldCell.VILLAGE
				placed = true
				break
		if not placed:
			main_node._dungeon_village_pos = Vector2i(MAP_WIDTH - 5, MAP_HEIGHT - 5)

	# Place the dungeon entrance on the world map
	var dungeon_placed = false
	var attempts = 200
	while not dungeon_placed and attempts > 0:
		var x = randi_range(1, MAP_WIDTH - 2)
		var y = randi_range(1, MAP_HEIGHT - 2)
		var pos = Vector2i(x, y)
		var cell = world_map_data[x][y]

		# Place on walkable biomes, but not too close to important villages
		var biome_data = BiomeDefinitions.get_biome_data(cell)
		var is_walkable = biome_data.is_empty() or biome_data.get("walkable", true)
		if is_walkable and cell != WorldCell.VILLAGE and pos.distance_to(main_node._starting_village_pos) > 10 and \
		(main_node._dungeon_village_pos == Vector2i.ZERO or pos.distance_to(main_node._dungeon_village_pos) > 10):
			world_map_data[x][y] = WorldCell.DUNGEON
			dungeon_placed = true
			print("Dungeon placed at: ", pos)

		attempts -= 1

	if not dungeon_placed:
		print("Warning: Failed to place dungeon on the world map. Placing fallback.")
		for x in range(MAP_WIDTH -1, 0, -1):
			var found = false
			for y in range(MAP_HEIGHT -1, 0, -1):
				var pos = Vector2i(x,y)
				var cell = world_map_data[x][y]
				var biome_data = BiomeDefinitions.get_biome_data(cell)
				var is_walkable = biome_data.is_empty() or biome_data.get("walkable", true)
				if is_walkable and cell != WorldCell.VILLAGE:
					world_map_data[x][y] = WorldCell.DUNGEON
					found = true
					print("Fallback Dungeon placed at: ", pos)
					break
			if found:
				break

	# Generate local overworld for the starting village
	var result = main_node.map_controller.generate_map(0, 0, WorldCell.VILLAGE, true, false)
	main_node._map_data = result["map_data"]
	main_node._rooms = result["rooms"]
	
	main_node._visible_tiles.resize(MAP_WIDTH)
	main_node._explored_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		main_node._visible_tiles[x] = []
		main_node._visible_tiles[x].resize(MAP_HEIGHT)
		main_node._explored_tiles[x] = []
		main_node._explored_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			main_node._visible_tiles[x][y] = false
			main_node._explored_tiles[x][y] = false

func zoom_out_to_world_map():
	if main_node._is_on_world_map:
		return
	if main_node.current_floor != 0:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("ここではワールドマップを開けない！", Color(0.9, 0.4, 0.4))
		return
		
	# Save current local map to cache
	main_node._save_current_floor_to_cache()
	
	# Gather allies data so they travel with the player
	main_node._saved_allies.clear()
	var allies = main_node.get_tree().get_nodes_in_group("allies")
	for ally in allies:
		if is_instance_valid(ally) and not ally.is_queued_for_deletion():
			main_node._saved_allies.append({
				"enemy_id": ally.enemy_id if "enemy_id" in ally else "zakomushi",
				"enemy_name": ally.enemy_name if "enemy_name" in ally else "仲間",
				"hp": ally.hp if "hp" in ally else 10,
				"max_hp": ally.max_hp if "max_hp" in ally else 10,
				"attack": ally.attack_power if "attack_power" in ally else 5,
				"defense": ally.defense if "defense" in ally else 0,
				"attack_range": ally.attack_range if "attack_range" in ally else 1.5,
				"sprite_path": ally.sprite_path if "sprite_path" in ally else "",
				"is_flying": ally.is_flying if "is_flying" in ally else false,
				"is_ally": true
			})
			
	# Safely clear all entities from the active scene tree to prevent world map interaction
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.remove_from_group("enemies")
			enemy.remove_from_group("entities")
			enemy.queue_free()
		
	for npc in main_node.get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc):
			npc.remove_from_group("npcs")
			npc.remove_from_group("entities")
			npc.queue_free()
		
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item):
			item.remove_from_group("items")
			item.remove_from_group("entities")
			item.queue_free()
		
	for torch in main_node.get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.remove_from_group("torches")
			torch.queue_free()
		
	# Clear other temporary local map graphics like fire overlays, steam overlays, blood decals
	main_node.get_tree().call_group("fire_overlays", "queue_free")
	main_node.get_tree().call_group("blood_decals", "queue_free")
	
	main_node._is_on_world_map = true
	main_node._update_lighting_for_map_type()
	player.position = Vector2(main_node._world_player_pos) * TILE_SIZE
	main_node._last_player_grid_pos = main_node._world_player_pos
	main_node.camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	main_node.camera.reset_smoothing()
	
	_draw_world_map()
	
	if main_node.PlayerUi:
		main_node.PlayerUi.update_floor("ワールド")
		
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("ワールドマップにズームアウトした。", Color(0.2, 0.7, 0.9))

func zoom_in_to_local_map():
	if not main_node._is_on_world_map:
		return
		
	var cell_type = main_node._world_map_data[main_node._world_player_pos.x][main_node._world_player_pos.y]
	# Check if biome is walkable using biome data
	var biome_data = BiomeDefinitions.get_biome_data(cell_type)
	if not biome_data.is_empty() and biome_data.get("walkable", true) == false:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("ここには進入できない！", Color(0.9, 0.2, 0.2))
		return
		
	main_node._is_on_world_map = false
	main_node._update_lighting_for_map_type()
	
	# Restore 2D visuals and hide ASCII overlay
	tile_map.visible = true
	if is_instance_valid(player):
		player.visible = true
	if main_node._ascii_map_layer:
		main_node._ascii_map_layer.visible = false
	
	var cache_key = "local_overworld_%d_%d" % [main_node._world_player_pos.x, main_node._world_player_pos.y]
	if not main_node._load_floor_from_cache(cache_key, false, false, true):
		# Clear old entities before generating
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(enemy): enemy.queue_free()
		for npc in main_node.get_tree().get_nodes_in_group("npcs"):
			if is_instance_valid(npc): npc.queue_free()
		for item in main_node.get_tree().get_nodes_in_group("items"):
			if is_instance_valid(item): item.queue_free()
		for torch in main_node.get_tree().get_nodes_in_group("torches"):
			if is_instance_valid(torch): torch.queue_free()
			
		main_node._generate_map(cell_type)
		main_node._setup_pathfinding()
		
		var fallback_spawn = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
		if not main_node._rooms.is_empty():
			fallback_spawn = main_node._rooms[0].get_center()
		var spawn_pos = main_node._get_center_spawn_pos(fallback_spawn)
		player.position = Vector2(spawn_pos) * TILE_SIZE
		main_node._last_player_grid_pos = spawn_pos
		
		if cell_type == WorldCell.VILLAGE:
			main_node.npc_manager.spawn_village_npcs()
		else:
			main_node._spawn_enemies()
			main_node._spawn_items()
		main_node._spawn_torches()
		
		# Spawn saved allies near the player
		for adata in main_node._saved_allies:
			main_node.npc_manager.spawn_ally_near_player(adata)
		main_node._saved_allies.clear()
		
	# Sync VisibilityManager
	if main_node.visibility_manager:
		main_node.visibility_manager.map_data = main_node._map_data
		main_node.visibility_manager.visible_tiles = main_node._visible_tiles
		main_node.visibility_manager.explored_tiles = main_node._explored_tiles
		main_node.visibility_manager.calculate_fov()
		main_node.visibility_manager.draw_map()
	else:
		main_node._calculate_fov()
		main_node._draw_map()
		
	main_node.camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	main_node.camera.reset_smoothing()
	
	if main_node.PlayerUi:
		main_node.PlayerUi.update_floor(0)
		
	var cell_names = {
		WorldCell.SEA: "海",
		WorldCell.GRASS: "草原",
		WorldCell.FOREST: "森林",
		WorldCell.MOUNTAIN: "山岳",
		WorldCell.VILLAGE: "村",
		WorldCell.DUNGEON: "ダンジョンの入口",
		WorldCell.ROAD: "街道",
		WorldCell.DEEP_FOREST: "深い森林",
		WorldCell.CONIFER_FOREST: "針葉樹林",
		WorldCell.DRYLAND: "乾燥地帯",
		WorldCell.DESERT: "砂漠",
		WorldCell.ROCKLAND: "岩場",
		WorldCell.WETLAND: "湿地",
		WorldCell.SWAMP: "沼地",
		WorldCell.HIGHLAND: "高地",
		WorldCell.SNOWLAND: "雪原",
		WorldCell.FROZEN_LAND: "凍結地帯",
		WorldCell.COAST: "海岸",
		WorldCell.RIVERBANK: "河川周辺",
		WorldCell.LAKESHORE: "湖沼周辺",
		WorldCell.WASTELAND: "荒廃地",
		WorldCell.ANOMALY_ZONE: "異常地帯",
		WorldCell.GRASSLAND_EDGE: "草原の端",
		WorldCell.FOREST_EDGE: "森林の端",
		WorldCell.DESERT_EDGE: "砂漠の端",
		WorldCell.SNOWLAND_EDGE: "雪原の端",
		WorldCell.SWAMP_EDGE: "沼地の端"
	}
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("%s にズームインした。" % cell_names.get(cell_type, "地上"), Color(0.2, 0.9, 0.4))

func _draw_world_map():
	tile_map.clear_layer(main_node.LAYER_VISIBLE)
	tile_map.clear_layer(main_node.LAYER_MEMORY)
	
	# Clear old overlays
	main_node.get_tree().call_group("fire_overlays", "queue_free")
	main_node.get_tree().call_group("world_village_icons", "queue_free")
	
	# Hide all non-player entities on world map
	for entity in main_node.get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity) and entity != player:
			entity.visible = false
	for torch in main_node.get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.visible = false
			
	# Restore 2D TileMap and Player sprite (drawing ASCII tiles directly onto them!)
	tile_map.visible = true
	if is_instance_valid(player):
		player.visible = true
		
	# Hide the full-screen terminal text overlay
	if main_node._ascii_map_layer:
		main_node._ascii_map_layer.visible = false
		
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var cell = main_node._world_map_data[x][y]
			var tile_coords = Vector2i(x, y)
			var atlas_coords = Vector2i(0, 0)
			
			match cell:
				WorldCell.SEA:
					atlas_coords.x = 83
				WorldCell.GRASS:
					atlas_coords.x = 84
				WorldCell.FOREST:
					atlas_coords.x = 85
				WorldCell.MOUNTAIN:
					atlas_coords.x = 86
				WorldCell.VILLAGE:
					atlas_coords.x = 87
				WorldCell.DUNGEON:
					atlas_coords.x = 88
				WorldCell.ROAD:
					atlas_coords.x = 89
				WorldCell.DEEP_FOREST:
					atlas_coords.x = 85
					atlas_coords.y = 1  # Darker forest
				WorldCell.CONIFER_FOREST:
					atlas_coords.x = 85
					atlas_coords.y = 2  # Different forest type
				WorldCell.DRYLAND:
					atlas_coords.x = 84
					atlas_coords.y = 1  # Dryer grass
				WorldCell.DESERT:
					atlas_coords.x = 90
				WorldCell.ROCKLAND:
					atlas_coords.x = 91
				WorldCell.WETLAND:
					atlas_coords.x = 84
					atlas_coords.y = 2  # Wet grass
				WorldCell.SWAMP:
					atlas_coords.x = 92
				WorldCell.HIGHLAND:
					atlas_coords.x = 86
					atlas_coords.y = 1  # Lower mountain
				WorldCell.SNOWLAND:
					atlas_coords.x = 93
				WorldCell.FROZEN_LAND:
					atlas_coords.x = 94
				WorldCell.COAST:
					atlas_coords.x = 95
				WorldCell.RIVERBANK:
					atlas_coords.x = 84
					atlas_coords.y = 3  # River grass
				WorldCell.LAKESHORE:
					atlas_coords.x = 84
					atlas_coords.y = 4  # Lake grass
				WorldCell.WASTELAND:
					atlas_coords.x = 96
				WorldCell.ANOMALY_ZONE:
					atlas_coords.x = 97
				# Transition zones
				WorldCell.GRASSLAND_EDGE:
					atlas_coords.x = 84
					atlas_coords.y = 5
				WorldCell.FOREST_EDGE:
					atlas_coords.x = 85
					atlas_coords.y = 3
				WorldCell.DESERT_EDGE:
					atlas_coords.x = 90
					atlas_coords.y = 1
				WorldCell.SNOWLAND_EDGE:
					atlas_coords.x = 93
					atlas_coords.y = 1
				WorldCell.SWAMP_EDGE:
					atlas_coords.x = 92
					atlas_coords.y = 1
				_:
					atlas_coords.x = 84
					
			tile_map.set_cell(main_node.LAYER_VISIBLE, tile_coords, 0, atlas_coords)
			
	if main_node.minimap_controller:
		main_node.minimap_controller.update_minimap()

func get_overworld_preview_map(chunk_pos: Vector2i) -> Dictionary:
	if chunk_pos.x < 0 or chunk_pos.x >= MAP_WIDTH or chunk_pos.y < 0 or chunk_pos.y >= MAP_HEIGHT:
		return {}
	var cache_key = "local_overworld_%d_%d" % [chunk_pos.x, chunk_pos.y]
	if main_node._floor_caches.has(cache_key):
		return {
			"map_data": main_node._floor_caches[cache_key]["map_data"],
			"rooms": main_node._floor_caches[cache_key]["rooms"]
		}
	if main_node._overworld_preview_maps.has(cache_key):
		return main_node._overworld_preview_maps[cache_key]
	var previous_world_pos = main_node._world_player_pos
	main_node._world_player_pos = chunk_pos
	var cell = main_node._world_map_data[chunk_pos.x][chunk_pos.y]
	var generator = DungeonGenerator.new()
	var is_starting = cell == WorldCell.VILLAGE and chunk_pos == main_node._starting_village_pos
	var is_dungeon = cell == WorldCell.VILLAGE and chunk_pos == main_node._dungeon_village_pos
	var result = generator.generate_map(0, main_node._current_branch, cell, main_node, is_starting, is_dungeon)
	generator.free()
	main_node._world_player_pos = previous_world_pos
	
	main_node._overworld_preview_maps[cache_key] = {
		"map_data": result["map_data"].duplicate(true),
		"rooms": result["rooms"].duplicate(true)
	}
	return main_node._overworld_preview_maps[cache_key]

func get_overworld_preview_cell(display_pos: Vector2i) -> int:
	var chunk_delta = Vector2i.ZERO
	if display_pos.x < 0:
		chunk_delta.x = -1
	elif display_pos.x >= MAP_WIDTH:
		chunk_delta.x = 1
	if display_pos.y < 0:
		chunk_delta.y = -1
	elif display_pos.y >= MAP_HEIGHT:
		chunk_delta.y = 1
	var local_pos = display_pos - Vector2i(chunk_delta.x * MAP_WIDTH, chunk_delta.y * MAP_HEIGHT)
	if local_pos.x < 0 or local_pos.x >= MAP_WIDTH or local_pos.y < 0 or local_pos.y >= MAP_HEIGHT:
		return CellType.WALL
	if chunk_delta == Vector2i.ZERO:
		return main_node._map_data[local_pos.x][local_pos.y]
	var preview = get_overworld_preview_map(main_node._world_player_pos + chunk_delta)
	if preview.is_empty():
		return CellType.WALL
	var preview_map = preview["map_data"]
	return preview_map[local_pos.x][local_pos.y]

func has_overworld_preview_line_of_sight(from_grid: Vector2i, to_grid: Vector2i) -> bool:
	var line_points = main_node._get_line_points(from_grid, to_grid)
	for p in line_points:
		if p == from_grid or p == to_grid:
			continue
		var cell = get_overworld_preview_cell(p)
		if cell == CellType.WALL or cell == CellType.DOOR_CLOSED or cell == CellType.DOOR_LOCKED or cell == CellType.TREE or cell == CellType.TREE_FRUIT or cell == CellType.ROCK:
			return false
	return true

func is_overworld_preview_visible(player_grid: Vector2i, tile_coords: Vector2i) -> bool:
	if (tile_coords - player_grid).length() > main_node.FOV_RADIUS:
		return false
	return has_overworld_preview_line_of_sight(player_grid, tile_coords)

func draw_overworld_preview_map(preview_map: Array, offset: Vector2i, player_grid: Vector2i) -> void:
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var tile_coords = Vector2i(x, y) + offset
			if not is_overworld_preview_visible(player_grid, tile_coords):
				continue
			var atlas_coords = main_node._get_map_cell_atlas_coords(preview_map, x, y)
			tile_map.set_cell(main_node.LAYER_VISIBLE, tile_coords, 0, atlas_coords)

func draw_overworld_neighbor_previews() -> void:
	if main_node.current_floor != 0 or main_node._is_on_world_map:
		return
	if not is_instance_valid(player):
		return
	var player_grid = tile_map.local_to_map(player.position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var chunk_pos = main_node._world_player_pos + Vector2i(dx, dy)
			var preview = get_overworld_preview_map(chunk_pos)
			if preview.is_empty():
				continue
			draw_overworld_preview_map(preview["map_data"], Vector2i(dx * MAP_WIDTH, dy * MAP_HEIGHT), player_grid)
class_name SaveManagerExtended
extends Node

var main_node: Node2D
var tile_map: TileMap
var player: Node2D

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	player = main.player

func save_current_floor_to_cache_with_key(floor_key: String):
	# Save with the provided key instead of generating one
	var items_data = []
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			var item_center = item.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var grid_pos = Vector2i(int(item_center.x / TILE_SIZE), int(item_center.y / TILE_SIZE))
			items_data.append({
				"grid_pos": grid_pos,
				"item_data": item.item_data
			})
			
	var enemies_data = []
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			if enemy.is_in_group("allies"):
				continue
			enemies_data.append({
				"enemy_id": enemy.enemy_id,
				"enemy_name": enemy.enemy_name,
				"hp": enemy.hp,
				"max_hp": enemy.max_hp,
				"attack": enemy.attack_power if "attack_power" in enemy else 5,
				"defense": enemy.defense,
				"attack_range": enemy.attack_range if "attack_range" in enemy else 1.5,
				"sprite_path": enemy.sprite_path if "sprite_path" in enemy else "",
				"is_flying": enemy.is_flying if "is_flying" in enemy else false,
				"grid_pos": Vector2i(enemy.position / TILE_SIZE),
				"fear": enemy.fear if "fear" in enemy else 0,
				"affection": enemy.affection if "affection" in enemy else 0,
				"xp_value": enemy.xp_value if "xp_value" in enemy else 10
			})
			
	var npcs_data = []
	for npc in main_node.get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc) and not npc.is_queued_for_deletion():
			if npc.is_in_group("allies"):
				continue
			npcs_data.append({
				"enemy_id": npc.enemy_id if "enemy_id" in npc else "zakomushi",
				"enemy_name": npc.enemy_name,
				"hp": npc.hp,
				"max_hp": npc.max_hp,
				"attack": npc.attack_power if "attack_power" in npc else 5,
				"defense": npc.defense,
				"attack_range": npc.attack_range if "attack_range" in npc else 1.5,
				"sprite_path": npc.sprite_path if "sprite_path" in npc else "",
				"is_flying": npc.is_flying if "is_flying" in npc else false,
				"grid_pos": Vector2i(npc.position / TILE_SIZE),
				"fear": npc.fear if "fear" in npc else 0,
				"affection": npc.affection if "affection" in npc else 0,
				"trade_items": npc.trade_items.duplicate() if "trade_items" in npc else [],
				"inventory_items": npc.inventory_items.duplicate() if "inventory_items" in npc else [],
				"inventory_initialized": npc._inventory_initialized if "_inventory_initialized" in npc else false
			})
			
	main_node._floor_caches[floor_key] = {
		"map_data": main_node._map_data.duplicate(true),
		"rooms": main_node._rooms.duplicate(true),
		"explored_tiles": main_node._explored_tiles.duplicate(true),
		"burning_grass": main_node._burning_grass.duplicate(),
		"frozen_tiles": main_node._frozen_tiles.duplicate(),
		"steam_tiles": main_node._steam_tiles.duplicate(),
		"items": items_data,
		"enemies": enemies_data,
		"npcs": npcs_data,
		"player_exit_grid": Vector2i.ZERO  # Not used for seamless chunk transitions
	}

func save_current_floor_to_cache():
	var floor_key = ""
	if main_node.current_floor == 0:
		floor_key = "local_overworld_%d_%d" % [main_node._world_player_pos.x, main_node._world_player_pos.y]
	else:
		floor_key = "dungeon_%d_%d_floor_%d_branch_%d" % [main_node._world_player_pos.x, main_node._world_player_pos.y, main_node.current_floor, main_node._current_branch]
	
	var items_data = []
	for item in main_node.get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			var item_center = item.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var grid_pos = Vector2i(int(item_center.x / TILE_SIZE), int(item_center.y / TILE_SIZE))
			items_data.append({
				"grid_pos": grid_pos,
				"item_data": item.item_data
			})
			
	var enemies_data = []
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			if enemy.is_in_group("allies"):
				continue
			var enemy_center = enemy.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var grid_pos = Vector2i(int(enemy_center.x / TILE_SIZE), int(enemy_center.y / TILE_SIZE))
			enemies_data.append({
				"grid_pos": grid_pos,
				"enemy_id": enemy.enemy_id if "enemy_id" in enemy else "zakomushi",
				"enemy_name": enemy.enemy_name,
				"sprite_path": enemy.sprite_path if "sprite_path" in enemy else "",
				"hp": enemy.hp,
				"max_hp": enemy.max_hp,
				"fear": enemy.fear if "fear" in enemy else 0,
				"affection": enemy.affection if "affection" in enemy else 0,
				"is_hostile_to_player_only": enemy.is_hostile_to_player_only if "is_hostile_to_player_only" in enemy else false,
				"attack": enemy.attack_power if "attack_power" in enemy else 5,
				"defense": enemy.defense,
				"skill_id": enemy.skill_id if "skill_id" in enemy else "",
				"attack_range": enemy.attack_range if "attack_range" in enemy else 1,
				"skill_cooldown": enemy.skill_cooldown if "skill_cooldown" in enemy else 0,
				"max_skill_cooldown": enemy.max_skill_cooldown if "max_skill_cooldown" in enemy else 5,
				"level": enemy.level if "level" in enemy else 1,
				"xp_value": enemy.xp_value if "xp_value" in enemy else 10
			})
			
	var npcs_data = []
	for npc in main_node.get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc) and not npc.is_queued_for_deletion():
			if npc.is_in_group("allies"):
				continue
			var npc_center = npc.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var grid_pos = Vector2i(int(npc_center.x / TILE_SIZE), int(npc_center.y / TILE_SIZE))
			npcs_data.append({
				"grid_pos": grid_pos,
				"enemy_id": npc.enemy_id if "enemy_id" in npc else "villager",
				"enemy_name": npc.enemy_name,
				"sprite_path": npc.sprite_path if "sprite_path" in npc else "",
				"hp": npc.hp,
				"max_hp": npc.max_hp,
				"fear": npc.fear if "fear" in npc else 0,
				"affection": npc.affection if "affection" in npc else 0,
				"trade_items": npc.trade_items.duplicate(true) if "trade_items" in npc else [],
				"inventory_items": npc.inventory_items.duplicate(true) if "inventory_items" in npc else [],
				"inventory_initialized": npc._inventory_initialized if "_inventory_initialized" in npc else false
			})
			
	main_node._floor_caches[floor_key] = {
		"map_data": main_node._map_data.duplicate(true),
		"rooms": main_node._rooms.duplicate(true),
		"explored_tiles": main_node._explored_tiles.duplicate(true),
		"burning_grass": main_node._burning_grass.duplicate(),
		"frozen_tiles": main_node._frozen_tiles.duplicate(),
		"steam_tiles": main_node._steam_tiles.duplicate(),
		"items": items_data,
		"enemies": enemies_data,
		"npcs": npcs_data,
		"player_exit_grid": Vector2i(player.position / TILE_SIZE) if is_instance_valid(player) else Vector2i.ZERO
	}

func load_floor_from_cache(floor_key: String, is_upward: bool, is_seamless: bool = false, prefer_center_spawn: bool = false) -> bool:
	if not main_node._floor_caches.has(floor_key):
		return false
		
	var cache = main_node._floor_caches[floor_key]
	main_node._map_data = cache["map_data"].duplicate(true)
	main_node._rooms = cache["rooms"].duplicate(true)
	main_node._explored_tiles = cache["explored_tiles"].duplicate(true)
	main_node._burning_grass = cache["burning_grass"].duplicate()
	main_node._frozen_tiles = cache["frozen_tiles"].duplicate()
	main_node._steam_tiles = cache["steam_tiles"].duplicate()
	
	main_node._visible_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		main_node._visible_tiles[x] = []
		main_node._visible_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			main_node._visible_tiles[x][y] = false
			
	var allies = main_node.get_tree().get_nodes_in_group("allies")
	var ally_data = []
	for ally in allies:
		if is_instance_valid(ally) and not ally.is_queued_for_deletion():
			ally_data.append({
				"enemy_id": ally.enemy_id if "enemy_id" in ally else "zakomushi",
				"enemy_name": ally.enemy_name,
				"hp": ally.hp,
				"max_hp": ally.max_hp,
				"attack": ally.attack_power if "attack_power" in ally else 5,
				"defense": ally.defense,
				"attack_range": ally.attack_range if "attack_range" in ally else 1.5,
				"sprite_path": ally.sprite_path if "sprite_path" in ally else "",
				"is_flying": ally.is_flying if "is_flying" in ally else false,
				"is_ally": true
			})
			# Immediately remove from groups and queue free
			ally.remove_from_group("allies")
			ally.remove_from_group("entities")
			if ally.is_in_group("enemies"):
				ally.remove_from_group("enemies")
			if ally.is_in_group("npcs"):
				ally.remove_from_group("npcs")
			ally.queue_free()
			
	# Append saved allies from the world map
	for saved_ally in main_node._saved_allies:
		ally_data.append(saved_ally)
	main_node._saved_allies.clear()
			
	# Safely remove old entities from scene tree and groups immediately
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
	
	main_node._setup_pathfinding()
	
	player = main_node.get_node_or_null("Player")
	if is_instance_valid(player):
		if not is_seamless:
			var spawn_pos = cache["player_exit_grid"]
			if prefer_center_spawn:
				spawn_pos = main_node._get_center_spawn_pos(spawn_pos)
			else:
				# Reposition player on matching stairs when returning
				# Downward (is_upward == false) -> Place on STAIRS_UP
				# Upward (is_upward == true) -> Place on STAIRS
				# Floor 0 (Overworld) -> Always place on cave entrance (STAIRS)
				var target_stair_type = CellType.STAIRS if is_upward else CellType.STAIRS_UP
				if main_node.current_floor == 0:
					target_stair_type = CellType.STAIRS
					
				var found_stair = false
				for x in range(MAP_WIDTH):
					for y in range(MAP_HEIGHT):
						if main_node._map_data[x][y] == target_stair_type:
							spawn_pos = Vector2i(x, y)
							found_stair = true
							break
					if found_stair: break
				
			player.position = Vector2(spawn_pos) * TILE_SIZE
			main_node._last_player_grid_pos = spawn_pos
			main_node.camera.position = player.position
			main_node.camera.reset_smoothing()
		# For seamless chunk transitions, position will be set by the caller
			
		if player.has_method("update_terrain_info"):
			var current_grid_pos = Vector2i(player.position / TILE_SIZE)
			if current_grid_pos.x >= 0 and current_grid_pos.x < MAP_WIDTH and current_grid_pos.y >= 0 and current_grid_pos.y < MAP_HEIGHT:
				var is_grass = main_node._map_data[current_grid_pos.x][current_grid_pos.y] == CellType.GRASS
				var is_water = main_node._map_data[current_grid_pos.x][current_grid_pos.y] == CellType.WATER
				player.update_terrain_info(is_grass, is_water)
		
	var item_scene = load("res://items/world_item.tscn")
	for idata in cache["items"]:
		var item_node = item_scene.instantiate()
		item_node.position = Vector2(idata["grid_pos"]) * TILE_SIZE - Vector2(0, 4)
		item_node.item_data = idata["item_data"]
		item_node.add_to_group("items")
		item_node.add_to_group("entities")
		main_node.add_child(item_node)
		
	var enemy_scene = load("res://actors/enemy/enemy.tscn")
	for edata in cache["enemies"]:
		var enemy_node = enemy_scene.instantiate()
		enemy_node.enemy_id = edata["enemy_id"]
		enemy_node.enemy_name = edata["enemy_name"]
		if "sprite_path" in edata and edata["sprite_path"] != "":
			enemy_node.sprite_path = edata["sprite_path"]
		enemy_node.hp = edata["hp"]
		enemy_node.max_hp = edata["max_hp"]
		enemy_node.fear = int(edata.get("fear", 0))
		enemy_node.affection = int(edata.get("affection", 0))
		enemy_node.is_hostile_to_player_only = bool(edata.get("is_hostile_to_player_only", false))
		if "attack_power" in enemy_node:
			enemy_node.attack_power = edata["attack"]
		if "defense" in enemy_node:
			enemy_node.defense = edata["defense"]
		enemy_node.skill_id = str(edata.get("skill_id", ""))
		enemy_node.attack_range = int(edata.get("attack_range", 1))
		enemy_node.skill_cooldown = int(edata.get("skill_cooldown", 0))
		enemy_node.max_skill_cooldown = int(edata.get("max_skill_cooldown", 5))
		if "level" in enemy_node:
			enemy_node.level = edata["level"]
		if "exp_reward" in enemy_node:
			enemy_node.exp_reward = edata["xp_value"]
		enemy_node.position = Vector2(edata["grid_pos"]) * TILE_SIZE
		enemy_node.add_to_group("enemies")
		enemy_node.add_to_group("entities")
		main_node.add_child(enemy_node)
		
	var npc_scene = load("res://actors/enemy/enemy.tscn")
	for ndata in cache["npcs"]:
		var npc_node = npc_scene.instantiate()
		npc_node.enemy_id = ndata["enemy_id"]
		npc_node.enemy_name = ndata["enemy_name"]
		if "sprite_path" in ndata and ndata["sprite_path"] != "":
			npc_node.sprite_path = ndata["sprite_path"]
		npc_node.hp = ndata["hp"]
		npc_node.max_hp = ndata["max_hp"]
		npc_node.fear = int(ndata.get("fear", 0))
		npc_node.affection = int(ndata.get("affection", 0))
		npc_node.is_npc = true
		npc_node.trade_items = ndata["trade_items"]
		npc_node.inventory_items.assign(ndata.get("inventory_items", []))
		npc_node._inventory_initialized = ndata.get("inventory_initialized", false)
		npc_node.position = Vector2(ndata["grid_pos"]) * TILE_SIZE
		npc_node.add_to_group("npcs")
		npc_node.add_to_group("entities")
		main_node.add_child(npc_node)
		
	for adata in ally_data:
		main_node.npc_manager.spawn_ally_near_player(adata)
		
	main_node._spawn_torches()
	
	# Sync VisibilityManager references for the loaded floor
	if main_node.visibility_manager:
		main_node.visibility_manager.map_data = main_node._map_data
		main_node.visibility_manager.visible_tiles = main_node._visible_tiles
		main_node.visibility_manager.explored_tiles = main_node._explored_tiles
		main_node.visibility_manager.burning_grass = main_node._burning_grass
		main_node.visibility_manager.frozen_tiles = main_node._frozen_tiles
		main_node.visibility_manager.steam_tiles = main_node._steam_tiles
		if not is_seamless:
			main_node.visibility_manager.calculate_fov()
			main_node.visibility_manager.draw_map()
	else:
		if not is_seamless:
			main_node._calculate_fov()
			main_node._draw_map()
	return true
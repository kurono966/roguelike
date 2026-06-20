extends Node

const SAVE_PATH: String = "user://save_game.cfg"

func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(player: CharacterBody2D, main: Node2D) -> bool:
	if not player or not main:
		return false
		
	var config = ConfigFile.new()
	var gs = get_node_or_null("/root/GameState")
	var player_class: int = 0
	if gs and "player_class" in gs:
		player_class = gs.player_class
	
	# 1. Serialize Player to "player" section
	config.set_value("player", "player_class", player_class)
	config.set_value("player", "strength", player.strength if "strength" in player else 10)
	config.set_value("player", "dexterity", player.dexterity if "dexterity" in player else 10)
	config.set_value("player", "intelligence", player.intelligence if "intelligence" in player else 10)
	config.set_value("player", "level", player.level if "level" in player else 1)
	config.set_value("player", "exp", player.exp if "exp" in player else 0)
	config.set_value("player", "exp_to_next_level", player.exp_to_next_level if "exp_to_next_level" in player else 10)
	config.set_value("player", "gold", player.gold if "gold" in player else 0)
	config.set_value("player", "hunger", player.hunger if "hunger" in player else 100)
	config.set_value("player", "max_hunger", player.max_hunger if "max_hunger" in player else 100)
	config.set_value("player", "position_x", player.position.x)
	config.set_value("player", "position_y", player.position.y)
	config.set_value("player", "level_hp_bonus", player.level_hp_bonus if "level_hp_bonus" in player else 0)
	config.set_value("player", "level_mp_bonus", player.level_mp_bonus if "level_mp_bonus" in player else 0)
	config.set_value("player", "initial_hp_bonus", player.initial_hp_bonus if "initial_hp_bonus" in player else 0)
	config.set_value("player", "initial_mp_bonus", player.initial_mp_bonus if "initial_mp_bonus" in player else 0)
	config.set_value("player", "base_can_swim", player._base_can_swim if "_base_can_swim" in player else false)
	config.set_value("player", "turn_counter", player.turn_counter if "turn_counter" in player else 0)
	config.set_value("player", "turns_since_damage", player.turns_since_damage if "turns_since_damage" in player else 0)
	config.set_value("player", "status_effects", _make_safe(player.status_effects) if "status_effects" in player else {})
	config.set_value("player", "skill_cooldowns", _make_safe(player.skill_cooldowns) if "skill_cooldowns" in player else {})
	config.set_value("player", "ranged_weapon_cooldown", player.ranged_weapon_cooldown if "ranged_weapon_cooldown" in player else 0)
	config.set_value("player", "bonus_action_available", player.bonus_action_available if "bonus_action_available" in player else false)
	config.set_value("player", "ranged_weapon_shots_fired", player.ranged_weapon_shots_fired if "ranged_weapon_shots_fired" in player else 0)
	config.set_value("player", "base_known_skills", player.base_known_skills.duplicate() if "base_known_skills" in player else [])
	config.set_value("player", "max_hp", player.max_hp if "max_hp" in player else 10)
	config.set_value("player", "hp", player.hp if "hp" in player else 10)
	config.set_value("player", "max_mp", player.max_mp if "max_mp" in player else 5)
	config.set_value("player", "mp", player.mp if "mp" in player else 5)
	
	# Serialize Inventory/Equipment
	var eq_items = []
	var bag_items = []
	if "equipment_component" in player and player.equipment_component:
		var eq_comp = player.equipment_component
		if "equipment_data" in eq_comp and eq_comp.equipment_data:
			for item in eq_comp.equipment_data.items:
				eq_items.append(_serialize_item(item))
		if "bag_data" in eq_comp and eq_comp.bag_data:
			for item in eq_comp.bag_data.items:
				bag_items.append(_serialize_item(item))
	
	config.set_value("player", "equipment", {"items": eq_items})
	config.set_value("player", "bag", {"items": bag_items})
	
	# 2. Serialize World Map & Floor Data to "world" section
	config.set_value("world", "current_floor", main.current_floor if "current_floor" in main else 1)
	config.set_value("world", "current_branch", main._current_branch if "_current_branch" in main else 0)
	config.set_value("world", "is_on_world_map", main._is_on_world_map if "_is_on_world_map" in main else false)
	config.set_value("world", "world_map_data", main._world_map_data if "_world_map_data" in main else [])
	config.set_value("world", "world_player_pos_x", main._world_player_pos.x if "_world_player_pos" in main else 0)
	config.set_value("world", "world_player_pos_y", main._world_player_pos.y if "_world_player_pos" in main else 0)
	config.set_value("world", "starting_village_pos_x", main._starting_village_pos.x if "_starting_village_pos" in main else 0)
	config.set_value("world", "starting_village_pos_y", main._starting_village_pos.y if "_starting_village_pos" in main else 0)
	config.set_value("world", "dungeon_village_pos_x", main._dungeon_village_pos.x if "_dungeon_village_pos" in main else 0)
	config.set_value("world", "dungeon_village_pos_y", main._dungeon_village_pos.y if "_dungeon_village_pos" in main else 0)
	config.set_value("world", "map_data", main._map_data if "_map_data" in main else [])
	config.set_value("world", "explored_tiles", main._explored_tiles if "_explored_tiles" in main else []) # 2D Array directly supported by ConfigFile
	
	var enemies_array: Array = []
	var npcs_array: Array = []
	
	var all_chars: Array = []
	var visited: Dictionary = {}
	var char_groups = ["enemies", "npcs", "allies"]
	for g in char_groups:
		for char_node in main.get_tree().get_nodes_in_group(g):
			if is_instance_valid(char_node) and not char_node.is_queued_for_deletion():
				if not visited.has(char_node):
					visited[char_node] = true
					all_chars.append(char_node)
					
	for char_node in all_chars:
		var is_ally = char_node.is_in_group("allies")
		var is_npc = char_node.is_npc if "is_npc" in char_node else false
		
		var char_data = _serialize_enemy(char_node)
		if is_npc and not is_ally:
			npcs_array.append(char_data)
		else:
			char_data["is_ally"] = is_ally
			enemies_array.append(char_data)
	
	config.set_value("world", "enemies", enemies_array)
	config.set_value("world", "npcs", npcs_array)
	
	var items_array: Array = []
	for item_node in main.get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item_node) and not item_node.is_queued_for_deletion():
			var item_data_prop = item_node.item_data if "item_data" in item_node else null
			if item_data_prop:
				items_array.append({
					"position_x": item_node.position.x,
					"position_y": item_node.position.y,
					"item": _serialize_item(item_data_prop)
				})
	config.set_value("world", "items", items_array)
	
	var torches_array: Array = []
	for torch in main.get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch) and not torch.is_queued_for_deletion():
			torches_array.append({
				"x": torch.position.x,
				"y": torch.position.y
			})
	config.set_value("world", "torches", torches_array)
	
	var hazards_array: Array = []
	if "_hazards" in main:
		for pos in main._hazards:
			var h = main._hazards[pos]
			hazards_array.append({
				"x": pos.x,
				"y": pos.y,
				"type": h.type if "type" in h else "",
				"duration": h.duration if "duration" in h else 0,
				"damage": h.damage if "damage" in h else 0
			})
	config.set_value("world", "hazards", hazards_array)
	
	var burning_grass_array: Array = []
	if "_burning_grass" in main:
		for pos in main._burning_grass:
			var entry = main._burning_grass[pos].duplicate()
			entry["x"] = pos.x
			entry["y"] = pos.y
			burning_grass_array.append(entry)
	config.set_value("world", "burning_grass", burning_grass_array)
	
	var frozen_tiles_array: Array = []
	if "_frozen_tiles" in main:
		for pos in main._frozen_tiles:
			var entry = main._frozen_tiles[pos].duplicate()
			entry["x"] = pos.x
			entry["y"] = pos.y
			frozen_tiles_array.append(entry)
	config.set_value("world", "frozen_tiles", frozen_tiles_array)
	
	var steam_tiles_array: Array = []
	if "_steam_tiles" in main:
		for pos in main._steam_tiles:
			var entry = main._steam_tiles[pos].duplicate()
			entry["x"] = pos.x
			entry["y"] = pos.y
			steam_tiles_array.append(entry)
	config.set_value("world", "steam_tiles", steam_tiles_array)
	
	var err = config.save(SAVE_PATH)
	return err == OK

func load_game() -> Dictionary:
	if not save_exists():
		return {}
		
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK:
		return {}
		
	var player_data = {}
	if config.has_section("player"):
		for key in config.get_section_keys("player"):
			player_data[key] = config.get_value("player", key)
			
	var world_data = {}
	if config.has_section("world"):
		for key in config.get_section_keys("world"):
			world_data[key] = config.get_value("world", key)
			
	return {
		"player": player_data,
		"world": world_data
	}

func _serialize_item(item: BaseItem) -> Dictionary:
	if not item:
		return {}
		
	return {
		"id": item.id,
		"name": item.display_name,
		"equipment_type": item.equipment_type,
		"attack": item.attack,
		"defense": item.defense,
		"grid_x": item.grid_position.x,
		"grid_y": item.grid_position.y,
		"strength": item.strength,
		"dexterity": item.dexterity,
		"intelligence": item.intelligence,
		"max_hp": item.max_hp,
		"max_mp": item.max_mp,
		"value": item.value,
		"rarity": item.rarity,
		"description": item.description,
		"shape": item.shape, # Array[Vector2i] directly supported
		"effects": _make_safe(item.effects) if item.effects else {},
		"granted_skills": item.granted_skills.duplicate() if item.granted_skills else [],
		"prefix_name": item.prefix_name,
		"suffix_name": item.suffix_name,
		"generated_level": item.generated_level
	}

func _serialize_enemy(enemy: CharacterBody2D) -> Dictionary:
	if not enemy:
		return {}
		
	return {
		"enemy_id": enemy.enemy_id if "enemy_id" in enemy else "",
		"enemy_name": enemy.enemy_name if "enemy_name" in enemy else "",
		"position_x": enemy.position.x,
		"position_y": enemy.position.y,
		"hp": enemy.hp if "hp" in enemy else 10,
		"max_hp": enemy.max_hp if "max_hp" in enemy else 10,
		"fear": enemy.fear if "fear" in enemy else 0,
		"affection": enemy.affection if "affection" in enemy else 0,
		"is_hostile_to_player_only": enemy.is_hostile_to_player_only if "is_hostile_to_player_only" in enemy else false,
		"status_effects": _make_safe(enemy.status_effects) if "status_effects" in enemy and enemy.status_effects else {},
		"skill_cooldown": enemy.skill_cooldown if "skill_cooldown" in enemy else 0,
		"skill_id": enemy.skill_id if "skill_id" in enemy else "",
		"attack_range": enemy.attack_range if "attack_range" in enemy else 1,
		"max_skill_cooldown": enemy.max_skill_cooldown if "max_skill_cooldown" in enemy else 5,
		"is_npc": enemy.is_npc if "is_npc" in enemy else false,
		"sprite_path": enemy.sprite_path if "sprite_path" in enemy else "",
		"is_ally": enemy.is_in_group("allies")
	}

# Decompress helper is kept for main.gd compatibility
# Returns the 2D array directly if it was saved by ConfigFile as such
func decompress_explored_tiles(data, map_width: int, map_height: int) -> Array:
	if data is Array and data.size() > 0 and data[0] is Array:
		return data
		
	var map = []
	map.resize(map_width)
	for x in range(map_width):
		map[x] = []
		map[x].resize(map_height)
		for y in range(map_height):
			map[x][y] = false
			
	for cell in data:
		if cell is Array and cell.size() >= 2:
			var x = int(cell[0])
			var y = int(cell[1])
			if x >= 0 and x < map_width and y >= 0 and y < map_height:
				map[x][y] = true
	return map

# Recursive safety check to strip non-native JSON types (like Nodes, Callables)
func _make_safe(data):
	if data is Dictionary:
		var safe_dict = {}
		for key in data:
			var val = data[key]
			var safe_val = _make_safe(val)
			if safe_val != null:
				safe_dict[key] = safe_val
		return safe_dict
	elif data is Array:
		var safe_array = []
		for item in data:
			var safe_val = _make_safe(item)
			if safe_val != null:
				safe_array.append(safe_val)
		return safe_array
	elif data is String or data is int or data is float or data is bool or data is Vector2 or data is Vector2i or data is Color or data is Rect2 or data is Rect2i:
		return data
	elif data == null:
		return null
	else:
		# Exclude complex objects/nodes to prevent serializing native Godot instances
		return null

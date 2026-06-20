class_name EnemyAI
extends RefCounted

const TILE_SIZE = 32
const MAP_WIDTH = 80 # Should match MapDefinitions but referencing main constants is hard if circular
# Better to pass context

static func determine_move_target(enemy: CharacterBody2D, player_grid_pos: Vector2i, map_data: Array, main_node: Node, player_is_visible: bool = true) -> Dictionary:
	# Returns { "moved": bool, "target": Vector2i or null, "flee": bool }
	
	var enemy_grid_pos = Vector2i(int(enemy.position.x / TILE_SIZE), int(enemy.position.y / TILE_SIZE))
	
	var result = {
		"move_target": null,
		"flee_target": false,
		"target_pos_if_aggressive": null
	}
	
	# Default Aggressive Logic Target
	if is_instance_valid(enemy) and player_is_visible:
		result.target_pos_if_aggressive = player_grid_pos
	elif is_instance_valid(enemy) and "last_known_player_pos" in enemy and enemy.last_known_player_pos != null:
		if enemy_grid_pos == enemy.last_known_player_pos:
			enemy.last_known_player_pos = null # Lost trail
		else:
			result.target_pos_if_aggressive = enemy.last_known_player_pos

	var ai_type = 0 # Default AGGRESSIVE
	if "ai_type" in enemy:
		ai_type = enemy.ai_type

	# A terrified actor prioritizes survival regardless of its normal AI type.
	if "fear" in enemy and enemy.fear >= 50 and player_is_visible:
		result.flee_target = true
		result.move_target = null
		return result

	match ai_type:
		0: # AGGRESSIVE
			result.move_target = result.target_pos_if_aggressive
			
		1: # COWARD
			if enemy.hp < enemy.max_hp * 0.4 and player_is_visible:
				result.flee_target = true
			else:
				result.move_target = result.target_pos_if_aggressive
				
		2: # SNIPER
			if player_is_visible:
				var dist = Vector2(enemy_grid_pos).distance_to(Vector2(player_grid_pos))
				var ideal_range = enemy.attack_range
				if dist < ideal_range * 0.6: # Too close, move away
					result.flee_target = true
				elif dist > ideal_range: # Too far, close in
					result.move_target = player_grid_pos
				else:
					# Good range, stay put
					result.move_target = null
			else:
				result.move_target = result.target_pos_if_aggressive
				
		3: # IMMOBILE
			result.move_target = null
			
		4: # RANDOM
			result.move_target = null
		
		5: # GRASS_SCATTER
			if enemy.hp <= enemy.max_hp * 0.5 and player_is_visible:
				result.flee_target = true
			else:
				var grass_target = _find_nearby_grass(enemy_grid_pos, map_data)
				result.move_target = grass_target if grass_target != null else result.target_pos_if_aggressive

	return result

static func get_flee_direction(enemy: CharacterBody2D, player_grid_pos: Vector2i, map_data: Array) -> Vector2:
	var enemy_grid_pos = Vector2i(int(enemy.position.x / TILE_SIZE), int(enemy.position.y / TILE_SIZE))
	var flee_dirs = []
	
	# Check 8 directions
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var dir = Vector2(dx, dy)
			var next_pos = enemy_grid_pos + Vector2i(dir)
			
			# Check bounds and terrain
			# Note: We assume map_data is [x][y]
			if next_pos.x >= 0 and next_pos.x < map_data.size() and next_pos.y >= 0 and next_pos.y < map_data[0].size():
				var cell = map_data[next_pos.x][next_pos.y]
				# 0=WALL, 2=WATER (approx check, relying on main's constants is risky without explicit import)
				# Best to just use a helper function or assume caller validates
				# For now, simplistic check: assume non-wall
				# To be safe, we return ALL candidates and let Main validate movement
				
				# Check distance
				var dist = Vector2(next_pos).distance_to(Vector2(player_grid_pos))
				var current_dist = Vector2(enemy_grid_pos).distance_to(Vector2(player_grid_pos))
				if dist > current_dist:
					flee_dirs.append(dir)
	
	if flee_dirs.size() > 0:
		return flee_dirs.pick_random()
	return Vector2.ZERO

static func _find_nearby_grass(origin: Vector2i, map_data: Array, radius: int = 7):
	var best_pos = null
	var best_dist = INF
	for x in range(max(0, origin.x - radius), min(map_data.size(), origin.x + radius + 1)):
		for y in range(max(0, origin.y - radius), min(map_data[0].size(), origin.y + radius + 1)):
			if map_data[x][y] != MapDefinitions.CellType.GRASS:
				continue
			var pos = Vector2i(x, y)
			var dist = Vector2(origin).distance_to(Vector2(pos))
			if dist < best_dist:
				best_dist = dist
				best_pos = pos
	return best_pos

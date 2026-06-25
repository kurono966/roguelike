class_name TurnManager
extends Node

var main_node: Node2D
var player
var tile_map: TileMap

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	player = main.player
	tile_map = main.tile_map

func end_player_turn():
	# Check for bonus action (e.g. Speed Bonus)
	if player and ("bonus_action_available" in player and player.bonus_action_available):
		player.bonus_action_available = false
		
		# Set cooldown to prevent immediate subsequent bonus
		main_node._swimmer_cooldown = true
		
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("スイマーボーナス: もう1回行動できる！", Color(0.3, 0.8, 1.0))
		
		main_node._current_game_state = main_node.TurnPhase.PLAYER_TURN
		return

	# Normal turn end - Reset cooldown
	main_node._swimmer_cooldown = false

	if player and player.has_method("on_turn_end"):
		player.on_turn_end()
	
	main_node._current_game_state = main_node.TurnPhase.ENEMY_TURN
	main_node._turn_count += 1
	
	# Periodic Enemy Spawning
	if main_node._turn_count % main_node.SPAWN_INTERVAL == 0:
		main_node._try_spawn_periodic_enemy()
		
	await process_enemy_turns()

func start_player_turn():
	if player.hp <= 0: return

	main_node._check_drowning()
	
	if player and player.has_method("has_status_effect"):
		if player.has_status_effect("paralysis"):
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("体が麻痺して動けない！", Color.YELLOW)
			print("Player is paralyzed. Skipping turn.")
			
			# 麻痺時のウェイト (0.15秒)
			await main_node.get_tree().create_timer(0.15).timeout
			
			await end_player_turn()
			return
		elif player.has_status_effect("sleep"):
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("眠りこけていて動けない！", Color.YELLOW)
			print("Player is asleep. Skipping turn.")
			
			# ウェイト (0.15秒)
			await main_node.get_tree().create_timer(0.15).timeout
			
			await end_player_turn()
			return

	main_node._current_game_state = main_node.TurnPhase.PLAYER_TURN

func process_enemy_turns():
	tile_map.clear_layer(main_node.LAYER_DEBUG)
	
	if main_node.has_method("_check_and_pull_neighbor_enemies"):
		main_node._check_and_pull_neighbor_enemies()
		
	var player_grid_pos = tile_map.local_to_map(player.position)
	
	main_node._process_hazards()
	main_node._process_burning_grass()
	main_node._process_steam()
	main_node._process_frozen_tiles()
	
	var all_actors = []
	all_actors.append_array(main_node.get_tree().get_nodes_in_group("enemies"))
	all_actors.append_array(main_node.get_tree().get_nodes_in_group("npcs"))
	
	for child in all_actors:
		# GLOBAL DEATH CHECK
		if player.hp <= 0:
			print("Player is dead. Stopping enemy turns.")
			return

		if not is_instance_valid(child) or child.is_queued_for_deletion(): continue
		
		# Skip allies - they will be processed separately
		if child.is_in_group("allies"):
			continue
		
		# Process status effects (DOT)
		if child.has_method("process_turn_effects"):
			child.process_turn_effects()
			
		# Check if enemy died from DOT
		if not is_instance_valid(child) or child.is_queued_for_deletion(): continue
			
		# Skip turn if paralyzed
		if child.has_method("is_paralyzed") and child.is_paralyzed():
			continue
			
		var enemy = child
		
		# --- Target Selection ---
		var target_node = _get_closest_hostile(enemy)
		var target_visible_to_enemy = false
		var target_grid_pos = Vector2i.ZERO
		var dist_to_target = INF
		var enemy_grid_pos = tile_map.local_to_map(enemy.position)
		
		if is_instance_valid(target_node):
			target_grid_pos = tile_map.local_to_map(target_node.position)
			dist_to_target = Vector2(enemy_grid_pos).distance_to(Vector2(target_grid_pos))
			
			# Blind effect: severely limits vision range (1 tile max)
			var vision_range = 10
			if enemy.has_method("is_blinded") and enemy.is_blinded():
				vision_range = 1
			
			if dist_to_target <= vision_range:
				if main_node._has_line_of_sight(enemy_grid_pos, target_grid_pos):
					target_visible_to_enemy = true
			
			# Hiding in Grass Logic (only against player)
			if target_node == player and main_node._map_data[target_grid_pos.x][target_grid_pos.y] == CellType.GRASS:
				if dist_to_target > 1.5:
					target_visible_to_enemy = false
					
		# AI Decision Making
		var is_enemy_in_fov = false
		if main_node.visibility_manager and enemy_grid_pos.x >= 0 and enemy_grid_pos.x < MAP_WIDTH and enemy_grid_pos.y >= 0 and enemy_grid_pos.y < MAP_HEIGHT:
			is_enemy_in_fov = main_node.visibility_manager.visible_tiles[enemy_grid_pos.x][enemy_grid_pos.y]
			
		var moved = false
		var acted = false
		var is_terrified = "fear" in enemy and enemy.fear >= 50
		
		# Skip attack if target is hidden
		if not is_terrified and target_visible_to_enemy and is_instance_valid(target_node):
			# Cooldown tick
			if enemy.skill_cooldown > 0:
				enemy.skill_cooldown -= 1
			
			if enemy.skill_id == "flame_scatter" and is_enemy_in_fov:
				var can_fireball = dist_to_target <= enemy.attack_range and main_node._has_line_of_sight(enemy_grid_pos, target_grid_pos)
				if enemy.skill_cooldown <= 0 and main_node._flame_scatter_has_grass(enemy):
					await main_node._execute_flame_scatter(enemy)
					enemy.skill_cooldown = randi_range(7, enemy.max_skill_cooldown)
					acted = true
				elif can_fireball:
					await main_node._execute_enemy_fireball(enemy, target_grid_pos)
					acted = true
			
			# Check Attack Range
			if not acted and is_enemy_in_fov and dist_to_target <= enemy.attack_range:
				var has_skill = enemy.skill_id != ""
				var skill_ready = enemy.skill_cooldown <= 0
				var can_attack_now = true
				
				# Line of Sight Check for Ranged
				if enemy.attack_range > 1.5:
					if not main_node._has_line_of_sight(enemy_grid_pos, target_grid_pos):
						can_attack_now = false
				
				if can_attack_now:
					if has_skill and skill_ready:
						await main_node._execute_enemy_skill_v2(enemy, target_grid_pos) # target_grid_pos works as arg
						acted = true
					elif dist_to_target <= 1.5:
						await main_node._handle_attack(enemy, target_node)
						acted = true
		
		# Update Memory
		if is_instance_valid(enemy) and is_enemy_in_fov and target_visible_to_enemy and is_instance_valid(target_node):
			if "last_known_player_pos" in enemy:
				enemy.last_known_player_pos = target_grid_pos
		
		# Safety check before AI processing
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue

		# Determine movement target
		# AI uses player_grid_pos for backward compatibility, but we send the generic target. 
		# If no target, we pass enemy_grid_pos just to not break it.
		var ai_target_input = target_grid_pos if is_instance_valid(target_node) else enemy_grid_pos
		var ai_decision = EnemyAI.determine_move_target(enemy, ai_target_input, main_node._map_data, main_node, target_visible_to_enemy)
		var move_target = ai_decision.move_target
		
		# Override move target if target is hidden and no memory
		if not target_visible_to_enemy:
			if "last_known_player_pos" in enemy and enemy.last_known_player_pos != null:
				move_target = enemy.last_known_player_pos
			else:
				move_target = null
				
		var flee_target = ai_decision.flee_target
		
		# Move/Wander if still valid and not acted
		if is_instance_valid(enemy):
			# Flee Logic
			if not acted and flee_target:
				var flee_dir = EnemyAI.get_flee_direction(enemy, ai_target_input, main_node._map_data)
				if flee_dir != Vector2.ZERO:
					if enemy.skill_id == "flame_scatter":
						var grass_dir = main_node._get_grass_preferred_direction(enemy, flee_dir)
						if grass_dir != Vector2.ZERO:
							flee_dir = grass_dir
					moved = await main_node._try_move_character(enemy, flee_dir)

			# Move if not acted (and didn't flee)
			if not acted and not moved and move_target != null:
				var path = []
				
				if "is_flying" in enemy and enemy.is_flying:
					path = main_node._astar_grid_fly.get_point_path(enemy_grid_pos, move_target)
				elif "can_swim" in enemy and enemy.can_swim:
					path = main_node._astar_grid_swim.get_point_path(enemy_grid_pos, move_target)
				else:
					path = main_node._astar_grid.get_point_path(enemy_grid_pos, move_target)
				
				if path.size() > 1:
					var move_direction = path[1] - Vector2(enemy_grid_pos)
					if enemy.skill_id == "flame_scatter":
						var grass_dir = main_node._get_grass_preferred_direction(enemy, move_direction)
						if grass_dir != Vector2.ZERO:
							move_direction = grass_dir
					moved = await main_node._try_move_character(enemy, move_direction)
					
					# Avoidance Logic
					if not moved:
						var target_vec = (Vector2(move_target) - Vector2(enemy_grid_pos)).normalized()
						var alternatives = []
						
						for dx in range(-1, 2):
							for dy in range(-1, 2):
								if dx == 0 and dy == 0: continue
								var dir = Vector2(dx, dy)
								if dir == move_direction: continue
								
								if dir.dot(target_vec) > 0.0:
									alternatives.append(dir)
						
						alternatives.shuffle()
						
						for alt_dir in alternatives:
							if await main_node._try_move_character(enemy, alt_dir):
								moved = true
								break
			
			# Wander Randomly if not chased/moved
			if not moved and not acted:
				var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, 
								  Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
				var random_dir = directions.pick_random()
				await main_node._try_move_character(enemy, random_dir)
			
			if main_node.visibility_manager:
				main_node.visibility_manager.update_single_entity_visibility(enemy)
	
	# Process ally turns (following player)
	var allies = main_node.get_tree().get_nodes_in_group("allies")
	for ally in allies:
		if not is_instance_valid(ally) or ally.is_queued_for_deletion(): continue
		
		# Process status effects
		if ally.has_method("process_turn_effects"):
			ally.process_turn_effects()
		
		# Skip if paralyzed
		if ally.has_method("is_paralyzed") and ally.is_paralyzed():
			continue
		
		# Get ally and player positions
		var ally_grid_pos = tile_map.local_to_map(ally.position)
		var ally_player_grid_pos = tile_map.local_to_map(player.position)
		var dist_to_player = ally_grid_pos.distance_to(ally_player_grid_pos)
		
		# Attack nearby enemies
		var nearby_enemies = []
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion(): continue
			var enemy_grid_pos = tile_map.local_to_map(enemy.position)
			var dist = ally_grid_pos.distance_to(enemy_grid_pos)
			if dist <= ally.attack_range:
				nearby_enemies.append({"enemy": enemy, "dist": dist, "pos": enemy_grid_pos})
		
		# Sort by distance and attack closest
		nearby_enemies.sort_custom(func(a, b): return a.dist < b.dist)
		if nearby_enemies.size() > 0:
			var target = nearby_enemies[0]
			await main_node._handle_attack(ally, target.enemy)
		# Follow into the player's previous tile so allies stay adjacent behind the player.
		elif dist_to_player > 1.5:
			var follow_target = main_node._last_player_grid_pos
			if follow_target == Vector2i.ZERO or follow_target.distance_to(ally_player_grid_pos) > 1.5:
				follow_target = ally_player_grid_pos
			var path = []
			if "is_flying" in ally and ally.is_flying:
				path = main_node._astar_grid_fly.get_point_path(ally_grid_pos, follow_target)
			elif "can_swim" in ally and ally.can_swim:
				path = main_node._astar_grid_swim.get_point_path(ally_grid_pos, follow_target)
			else:
				path = main_node._astar_grid.get_point_path(ally_grid_pos, follow_target)
			
			var moved = false
			if path.size() > 1:
				var move_direction = path[1] - Vector2(ally_grid_pos)
				moved = await main_node._try_move_character(ally, move_direction)
			
			# Fallback: try direct direction if pathfinding fails
			if not moved:
				var best_dir = Vector2.ZERO
				var best_score = -INF
				
				# Try all 8 directions and pick the one that reduces distance most
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if dx == 0 and dy == 0: continue
						var test_dir = Vector2(dx, dy)
						var test_pos = ally_grid_pos + Vector2i(int(test_dir.x), int(test_dir.y))
						
						# Check if position is valid
						if test_pos.x >= 0 and test_pos.x < main_node.MAP_WIDTH and test_pos.y >= 0 and test_pos.y < main_node.MAP_HEIGHT:
							var cell_type = main_node._map_data[test_pos.x][test_pos.y]
							var is_fly = "is_flying" in ally and ally.is_flying
							var is_swim = "can_swim" in ally and ally.can_swim
							
							var is_walkable_dir = false
							if cell_type == main_node.CellType.WALL:
								is_walkable_dir = false
							elif cell_type == main_node.CellType.WATER:
								is_walkable_dir = is_fly or is_swim
							elif cell_type == main_node.CellType.LAVA or cell_type == main_node.CellType.PIT:
								is_walkable_dir = is_fly
							else:
								is_walkable_dir = true
								
							if is_walkable_dir:
								var new_dist = test_pos.distance_to(follow_target)
								var score = (ally_grid_pos.distance_to(follow_target) - new_dist)
								if score > best_score:
									best_score = score
									best_dir = test_dir
				
				if best_dir != Vector2.ZERO:
					await main_node._try_move_character(ally, best_dir)

	print("Enemy turns processing complete. Starting player turn.")
	await start_player_turn()

func _get_closest_hostile(actor: Node2D) -> Node2D:
	var hostiles = []
	if "fear" in actor and actor.fear >= 50:
		return player
	if "is_hostile_to_player_only" in actor and actor.is_hostile_to_player_only:
		return player
	if actor.is_in_group("enemies"):
		hostiles.append_array(main_node.get_tree().get_nodes_in_group("npcs"))
		hostiles.append(player)
	elif actor.is_in_group("npcs"):
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if "is_hostile_to_player_only" in enemy and enemy.is_hostile_to_player_only:
				continue
			hostiles.append(enemy)
		
	var closest = null
	var min_dist = INF
	
	for h in hostiles:
		if not is_instance_valid(h) or h.is_queued_for_deletion(): continue
		if ("hp" in h and h.hp <= 0): continue
		var d = actor.position.distance_to(h.position)
		if d < min_dist:
			min_dist = d
			closest = h
			
	return closest

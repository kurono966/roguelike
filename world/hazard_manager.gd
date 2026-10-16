class_name HazardManager
extends Node

## HazardManager owns the behavior for environmental hazards and status effects:
## acid puddles, burning grass (fire spread), water freezing/melting, water
## electrification, and steam.
##
## NOTE: the underlying state dictionaries (_hazards, _burning_grass,
## _frozen_tiles, _steam_tiles, _steam_exposure) are still declared and owned
## by main.gd, because a lot of unrelated code (movement/walkability checks,
## _draw_map, FOV, save/load) reads them directly. This manager always reads
## and writes them through the `main` reference so there is a single source
## of truth and nothing needs to be kept in sync.

var main: Node2D

func setup(m: Node2D) -> void:
	main = m

# ------------------------------------------------------------------------------
# Acid Hazards
# ------------------------------------------------------------------------------

func create_hazard(type: String, world_pos: Vector2):
	var grid_pos = main.tile_map.local_to_map(world_pos)
	if grid_pos.x < 0 or grid_pos.x >= main.MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= main.MAP_HEIGHT: return
	
	main._hazards[grid_pos] = {
		"type": type,
		"duration": 20, # Default duration
		"damage": 2 # Acid damage
	}
	spawn_hazard_visual(grid_pos, type)

func spawn_hazard_visual(grid_pos: Vector2i, type: String):
	var sprite = Sprite2D.new()
	var img = Image.create(main.TILE_SIZE, main.TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.8, 0.2, 0.5) if type == "acid_puddle" else Color.RED)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(grid_pos) * main.TILE_SIZE + Vector2(main.TILE_SIZE / 2.0, main.TILE_SIZE / 2.0)
	sprite.z_index = 0 # On floor
	sprite.add_to_group("hazard_visuals")
	sprite.set_meta("grid_pos", grid_pos)
	main.add_child(sprite)

func process_hazards():
	var to_remove = []
	for grid_pos in main._hazards.keys():
		var data = main._hazards[grid_pos]
		data.duration -= 1
		
		# Apply effect
		if not main or not main.get_tree():
			return
		for entity in main.get_tree().get_nodes_in_group("entities"):
			if not is_instance_valid(entity): continue
			var e_grid = main.tile_map.local_to_map(entity.position)
			if e_grid == grid_pos:
				if data.type == "acid_puddle":
					if entity.has_method("take_damage"):
						entity.take_damage(data.damage)
						if main.has_node("/root/LogUI"):
							var name = entity.name
							if "enemy_name" in entity: name = entity.enemy_name
							main.get_node("/root/LogUI").add_log("%s は酸で溶けている！ (%dダメ)" % [name, data.damage], Color.GREEN_YELLOW)
						
						# Also apply burn?
						if entity.has_method("apply_effect") and randf() < 0.3:
							entity.apply_effect("burn", {"duration": 3, "damage": 1})
		
		if data.duration <= 0:
			to_remove.append(grid_pos)
			
	for pos in to_remove:
		main._hazards.erase(pos)
		remove_hazard_visual(pos)

func remove_hazard_visual(grid_pos: Vector2i):
	if not main or not main.get_tree():
		return
	for node in main.get_tree().get_nodes_in_group("hazard_visuals"):
		# Check validity before accessing meta - though nodes in group should be valid
		if is_instance_valid(node) and node.has_meta("grid_pos") and node.get_meta("grid_pos") == grid_pos:
			node.queue_free()

# ------------------------------------------------------------------------------
# Water Electrification
# ------------------------------------------------------------------------------

func electrify_water(start_pos: Vector2i, damage_val: int = -1):
	"""Spread electricity through all connected water tiles using flood fill"""
	var electrified_tiles = []
	var to_check = [start_pos]
	var checked = {}
	
	# Flood fill to find all connected water tiles
	while to_check.size() > 0:
		var pos = to_check.pop_front()
		var key = Vector2i(pos.x, pos.y)
		
		# Skip if already checked
		if checked.has(key):
			continue
		checked[key] = true
		
		# Check bounds
		if pos.x < 0 or pos.x >= main.MAP_WIDTH or pos.y < 0 or pos.y >= main.MAP_HEIGHT:
			continue
		
		# Check if water
		if main._map_data[pos.x][pos.y] != main.CellType.WATER:
			continue
		
		# Add to electrified list
		electrified_tiles.append(pos)
		
		# Add adjacent tiles to check
		to_check.append(Vector2i(pos.x + 1, pos.y))
		to_check.append(Vector2i(pos.x - 1, pos.y))
		to_check.append(Vector2i(pos.x, pos.y + 1))
		to_check.append(Vector2i(pos.x, pos.y - 1))
	
	if electrified_tiles.size() == 0:
		return
	
	# Visual effect: Flash all electrified tiles
	for tile_pos in electrified_tiles:
		var flash = ColorRect.new()
		flash.color = Color(1.0, 1.0, 0.0, 0.6)  # Yellow
		flash.size = Vector2(main.TILE_SIZE, main.TILE_SIZE)
		flash.position = Vector2(tile_pos) * main.TILE_SIZE
		main.add_child(flash)
		
		var flash_tween = main.create_tween()
		flash_tween.tween_property(flash, "modulate:a", 0.0, 0.5)
		flash_tween.tween_callback(flash.queue_free)
	
	# 1. Collect all entities currently on electrified water
	var entities_on_water = []
	if not main or not main.get_tree():
		return
	for entity in main.get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity):
			var entity_grid = main.tile_map.local_to_map(entity.position)
			if electrified_tiles.has(entity_grid):
				entities_on_water.append(entity)
	
	# 2. Damage each valid entity once
	var base_damage = damage_val
	if base_damage == -1:
		if main.target_manager and main.target_manager.targeting_skill:
			base_damage = main.target_manager.targeting_skill.get("damage", 6)
		else:
			base_damage = 6
			
	for entity in entities_on_water:
		if is_instance_valid(entity) and entity.has_method("take_damage"):
			entity.take_damage(base_damage, null, ["electric"])
			
			var entity_name = entity.name
			if "enemy_name" in entity:
				entity_name = entity.enemy_name
			elif entity == main.player:
				entity_name = "自分"
			
			if main.has_node("/root/LogUI"):
				main.get_node("/root/LogUI").add_log("[雷] %s に感電ダメージ %d！" % [entity_name, base_damage], Color.YELLOW)
	
	# Log the chain reaction
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("[雷] 電気が水を伝って %d マスに広がった！" % electrified_tiles.size(), Color(1.0, 1.0, 0.5))

# ------------------------------------------------------------------------------
# Burning Grass / Fire Spread
# ------------------------------------------------------------------------------

func ignite_grass(pos: Vector2i):
	# Grass and wooden walls share fire timers, visuals, and save/cache storage.
	if not main._is_grid_in_bounds(pos):
		return
	var cell = main._map_data[pos.x][pos.y]
	if cell not in [main.CellType.GRASS, main.CellType.WOOD_WALL]:
		return
	if main._burning_grass.has(pos):
		return  # Already burning
	
	main._burning_grass[pos] = {
		"turns_remaining": 5,
		"spread_chance": 30 if cell == main.CellType.WOOD_WALL else 50
	}
	
	# Visual effect for initial ignition
	update_burning_grass_visual(pos)
	
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("[炎] 木製の壁が燃え始めた！" if cell == main.CellType.WOOD_WALL else "[炎] 草むらが燃え始めた！", Color.ORANGE_RED)

func process_burning_grass():
	"""Process burning grass each turn: spread fire and damage entities"""
	if main._burning_grass.is_empty():
		return
	
	var to_remove = []
	var new_fires = []
	
	# 1. Collect all entities on burning tiles first to avoid issues with freed nodes in nested loops
	var entities_on_fire = {} # entity: total_damage
	if not main or not main.get_tree():
		return
	for pos in main._burning_grass.keys():
		for entity in main.get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(entity):
				var entity_grid = main.tile_map.local_to_map(entity.position)
				if entity_grid == pos:
					entities_on_fire[entity] = 2 # Fire damage
	
	# 2. Apply damage to each entity once
	for entity in entities_on_fire.keys():
		if is_instance_valid(entity) and entity.has_method("take_damage"):
			var fire_dmg = entities_on_fire[entity]
			if is_fire_immune(entity):
				continue
			entity.take_damage(fire_dmg, null, ["fire"])
			
			var entity_name = entity.name
			if "enemy_name" in entity:
				entity_name = entity.enemy_name
			elif entity == main.player:
				entity_name = "自分"
			
			if main.has_node("/root/LogUI"):
				main.get_node("/root/LogUI").add_log("[炎] %s が炎上ダメージを受けた！ (%d)" % [entity_name, fire_dmg], Color.ORANGE_RED)
	
	# 3. Spread fire and manage turns
	for pos in main._burning_grass.keys():
		var fire_data = main._burning_grass[pos]
		fire_data.turns_remaining -= 1
		
		if fire_data.turns_remaining > 0:
			var spread_chance = fire_data.spread_chance
			var adjacent_tiles = [
				Vector2i(pos.x + 1, pos.y),
				Vector2i(pos.x - 1, pos.y),
				Vector2i(pos.x, pos.y + 1),
				Vector2i(pos.x, pos.y - 1)
			]
			
			for adj_pos in adjacent_tiles:
				# Check bounds
				if adj_pos.x < 0 or adj_pos.x >= main.MAP_WIDTH or adj_pos.y < 0 or adj_pos.y >= main.MAP_HEIGHT:
					continue
				
				# Spread to adjacent fuel without ticking newly lit fires this turn.
				if main._map_data[adj_pos.x][adj_pos.y] in [main.CellType.GRASS, main.CellType.WOOD_WALL] and not main._burning_grass.has(adj_pos):
					if randi() % 100 < spread_chance:
						new_fires.append(adj_pos)
		
		# Remove if burned out
		if fire_data.turns_remaining <= 0:
			to_remove.append(pos)
			# Convert to floor
			main._map_data[pos.x][pos.y] = main.CellType.FLOOR
			main._update_astar_tile(pos, false)
	
	# Remove burned out fires
	for pos in to_remove:
		main._burning_grass.erase(pos)
	
	# Add new fires
	for pos in new_fires:
		ignite_grass(pos)
	
	# Update visuals
	if not to_remove.is_empty():
		# Rebuild wall occluders once for the entire batch of burned tiles.
		main._update_shadow_cell(to_remove[0])
		main._calculate_fov()
	main._draw_map()

func is_fire_immune(entity) -> bool:
	return is_instance_valid(entity) and "fire_immune" in entity and entity.fire_immune

func try_enemy_grass_ignition(enemy, grid_pos: Vector2i):
	if grid_pos.x < 0 or grid_pos.x >= main.MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= main.MAP_HEIGHT:
		return
	if main._map_data[grid_pos.x][grid_pos.y] != main.CellType.GRASS or main._burning_grass.has(grid_pos):
		return
	if randf() <= enemy.grass_ignition_chance:
		ignite_grass(grid_pos)

func flame_scatter_has_grass(enemy, radius: int = 2) -> bool:
	var origin = main.tile_map.local_to_map(enemy.position)
	for x in range(origin.x - radius, origin.x + radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			var pos = Vector2i(x, y)
			if pos.x < 0 or pos.x >= main.MAP_WIDTH or pos.y < 0 or pos.y >= main.MAP_HEIGHT:
				continue
			if Vector2(origin).distance_to(Vector2(pos)) > radius:
				continue
			if main._map_data[pos.x][pos.y] in [main.CellType.GRASS, main.CellType.WOOD_WALL] and not main._burning_grass.has(pos):
				return true
	return false

func get_grass_preferred_direction(enemy, desired_dir: Vector2) -> Vector2:
	var origin = main.tile_map.local_to_map(enemy.position)
	var candidates = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var dir = Vector2(dx, dy)
			var pos = origin + Vector2i(dir)
			if main._is_revealed_trap(pos):
				continue
			if pos.x < 0 or pos.x >= main.MAP_WIDTH or pos.y < 0 or pos.y >= main.MAP_HEIGHT:
				continue
			if main._map_data[pos.x][pos.y] != main.CellType.GRASS:
				continue
			if desired_dir != Vector2.ZERO and dir.dot(desired_dir.normalized()) < -0.1:
				continue
			candidates.append(dir)
	if candidates.is_empty():
		return Vector2.ZERO
	candidates.shuffle()
	return candidates[0]

func execute_enemy_fireball(enemy, target_grid_pos: Vector2i):
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("%s は小さな火球を放った！" % enemy.enemy_name, Color.ORANGE_RED)
	await main._handle_ranged_attack(enemy, target_grid_pos, max(1, enemy.attack_power), "fire")

func execute_flame_scatter(enemy):
	var origin = main.tile_map.local_to_map(enemy.position)
	var ignited = 0
	var melted = 0
	var radius = 2
	for x in range(origin.x - radius, origin.x + radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			var pos = Vector2i(x, y)
			if pos.x < 0 or pos.x >= main.MAP_WIDTH or pos.y < 0 or pos.y >= main.MAP_HEIGHT:
				continue
			if Vector2(origin).distance_to(Vector2(pos)) > radius:
				continue
			if main._map_data[pos.x][pos.y] in [main.CellType.GRASS, main.CellType.WOOD_WALL] and not main._burning_grass.has(pos):
				ignite_grass(pos)
				if main._burning_grass.has(pos) and main._map_data[pos.x][pos.y] == main.CellType.GRASS:
					main._burning_grass[pos].spread_chance = 25
				ignited += 1
			# Melt ice
			if main._map_data[pos.x][pos.y] == main.CellType.ICE and main._frozen_tiles.has(pos):
				main._map_data[pos.x][pos.y] = main.CellType.WATER
				main._frozen_tiles.erase(pos)
				melted += 1
	if ignited > 0 or melted > 0:
		create_steam(origin)
		if main.has_node("/root/LogUI"):
			if ignited > 0:
				main.get_node("/root/LogUI").add_log("%s は炎の種をまき散らした！" % enemy.enemy_name, Color.ORANGE_RED)
			if melted > 0:
				main.get_node("/root/LogUI").add_log("[炎] 氷が溶けた！", Color.ORANGE)
		main._setup_pathfinding()
		main._calculate_fov()
		main._draw_map()

func update_burning_grass_visual(pos: Vector2i):
	"""Update tile color to show it's burning - called during _draw_map"""
	# This will be handled in _draw_map by checking main._burning_grass
	pass

# ------------------------------------------------------------------------------
# Steam
# ------------------------------------------------------------------------------

func create_steam(pos: Vector2i):
	"""Fire hitting water creates steam that obscures vision - gas-like random spread"""
	# Place steam at origin first (always)
	if pos.x >= 0 and pos.x < main.MAP_WIDTH and pos.y >= 0 and pos.y < main.MAP_HEIGHT:
		main._steam_tiles[pos] = {
			"turns_remaining": 8,
			"density": 3  # density: 3=thick, 2=medium, 1=thin
		}
	
	# BFS-style random spread from origin
	var frontier = [pos]
	var visited = {pos: true}
	
	for _wave in range(3):  # 3 waves of expansion
		var next_frontier = []
		for cur in frontier:
			# Shuffle directions for randomness
			var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			dirs.shuffle()
			for d in dirs:
				var npos = cur + d
				if npos.x < 0 or npos.x >= main.MAP_WIDTH or npos.y < 0 or npos.y >= main.MAP_HEIGHT:
					continue
				if visited.has(npos):
					continue
				# Cannot pass through walls
				if main._map_data[npos.x][npos.y] in [main.CellType.WALL, main.CellType.WOOD_WALL]:
					continue
				visited[npos] = true
				# Spread probability decreases with distance
				var spread_chance = 0.85 - _wave * 0.15
				if randf() < spread_chance:
					var density = max(1, 3 - _wave)
					var turns = 6 + randi() % 3 - _wave
					if not main._steam_tiles.has(npos) or main._steam_tiles[npos].turns_remaining < turns:
						main._steam_tiles[npos] = {
							"turns_remaining": max(2, turns),
							"density": density
						}
					next_frontier.append(npos)
		frontier = next_frontier
	
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("💨 蒸気が立ち込めた！", Color.LIGHT_GRAY)

func process_steam():
	"""Process steam tiles each turn - gas-like random spreading"""
	if main._steam_tiles.is_empty():
		main._steam_exposure.clear()
		return
	
	var to_remove = []
	var new_steam: Dictionary = {}
	
	for pos in main._steam_tiles.keys():
		var data = main._steam_tiles[pos]
		data.turns_remaining -= 1
		
		# Density decreases as steam ages
		if data.turns_remaining == 4:
			data.density = max(1, data.get("density", 2) - 1)
		elif data.turns_remaining == 2:
			data.density = 1
		
		if data.turns_remaining <= 0:
			to_remove.append(pos)
			continue
		
		# Gas-like random diffusion: try to spread to adjacent floor tiles
		var density = data.get("density", 1)
		var spread_prob = 0.3 + density * 0.1  # thick steam spreads more
		
		var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		dirs.shuffle()
		for d in dirs:
			var npos = pos + d
			if npos.x < 0 or npos.x >= main.MAP_WIDTH or npos.y < 0 or npos.y >= main.MAP_HEIGHT:
				continue
			# Steam cannot pass through walls
			if main._map_data[npos.x][npos.y] in [main.CellType.WALL, main.CellType.WOOD_WALL]:
				continue
			# Skip if already has strong steam
			if main._steam_tiles.has(npos) and main._steam_tiles[npos].turns_remaining >= data.turns_remaining:
				continue
			if new_steam.has(npos) and new_steam[npos].turns_remaining >= data.turns_remaining - 1:
				continue
			if randf() < spread_prob:
				# New steam tile is weaker (1 less turn, lower density)
				new_steam[npos] = {
					"turns_remaining": max(1, data.turns_remaining - 1),
					"density": max(1, density - 1)
				}
	
	for pos in to_remove:
		main._steam_tiles.erase(pos)
	
	# Merge newly spread steam
	for pos in new_steam.keys():
		if not main._steam_tiles.has(pos):
			main._steam_tiles[pos] = new_steam[pos]
		else:
			# Refresh if new steam is stronger
			if new_steam[pos].turns_remaining > main._steam_tiles[pos].turns_remaining:
				main._steam_tiles[pos] = new_steam[pos]
	
	var current_exposure = {}
	if not main or not main.get_tree():
		return
	for entity in main.get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity):
			continue
		var entity_grid = main.tile_map.local_to_map(entity.position)
		if not main._steam_tiles.has(entity_grid):
			continue
		
		var entity_id = entity.get_instance_id()
		var turns_in_steam = int(main._steam_exposure.get(entity_id, 0)) + 1
		current_exposure[entity_id] = turns_in_steam
		
		if turns_in_steam >= 2 and entity.has_method("take_damage"):
			entity.take_damage(1, null, ["steam"])
			if main.has_node("/root/LogUI"):
				var entity_name = entity.name
				if "enemy_name" in entity:
					entity_name = entity.enemy_name
				elif entity == main.player:
					entity_name = "Player"
				main.get_node("/root/LogUI").add_log("%s is choking in the steam!" % entity_name, Color.LIGHT_GRAY)
	main._steam_exposure = current_exposure
	
	# Recalculate FOV if steam changed
	main._calculate_fov()
	main._draw_map()

# ------------------------------------------------------------------------------
# Freezing
# ------------------------------------------------------------------------------

func freeze_water(pos: Vector2i, freeze_adjacent: bool = true):
	"""Ice hitting water freezes it, creating slippery floor"""
	if main._map_data[pos.x][pos.y] != main.CellType.WATER:
		return
	
	# Freeze this tile and adjacent water tiles
	var tiles_to_freeze = [pos]
	if freeze_adjacent:
		var adjacent = [
			Vector2i(pos.x + 1, pos.y),
			Vector2i(pos.x - 1, pos.y),
			Vector2i(pos.x, pos.y + 1),
			Vector2i(pos.x, pos.y - 1)
		]
		
		for adj_pos in adjacent:
			if adj_pos.x < 0 or adj_pos.x >= main.MAP_WIDTH or adj_pos.y < 0 or adj_pos.y >= main.MAP_HEIGHT:
				continue
			if main._map_data[adj_pos.x][adj_pos.y] == main.CellType.WATER:
				tiles_to_freeze.append(adj_pos)
	
	for freeze_pos in tiles_to_freeze:
		# Change cell type from WATER to ICE
		main._map_data[freeze_pos.x][freeze_pos.y] = main.CellType.ICE
		main._frozen_tiles[freeze_pos] = {
			"turns_remaining": 4  # Ice lasts 4 turns
		}
	
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("[氷] 水が凍結した！ (%d タイル)" % tiles_to_freeze.size(), Color.CYAN)

func process_frozen_tiles():
	"""Process frozen tiles - ice no longer melts automatically, only from fire/heat effects"""
	# It only melts when affected by fire or other heat-based effects
	pass

# ------------------------------------------------------------------------------
# Traps & Poison Gas
# ------------------------------------------------------------------------------

func spawn_trap(pos: Vector2i, type: String):
	if pos.x < 0 or pos.x >= main.MAP_WIDTH or pos.y < 0 or pos.y >= main.MAP_HEIGHT: return
	
	main._traps[pos] = {
		"type": type,
		"is_revealed": false
	}

func reveal_trap(pos: Vector2i):
	if not main._traps.has(pos): return
	var trap_data = main._traps[pos]
	if trap_data.is_revealed: return
	
	trap_data.is_revealed = true
	
	# Remove old sprite-based visual if one was accidentally created
	if main._trap_visuals.has(pos):
		var old_sprite = main._trap_visuals[pos]
		if is_instance_valid(old_sprite):
			old_sprite.queue_free()
		main._trap_visuals.erase(pos)
	
	# Trigger a redraw to show the ASCII trap symbol
	main._draw_map()
	
	# Update pathfinding so enemies avoid the revealed trap
	main._update_astar_tile(pos, false)
	
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("罠を発見した！", Color.YELLOW)


func trigger_trap(pos: Vector2i, entity: Node):
	if not main._traps.has(pos): return
	
	var trap_data = main._traps[pos]
	var type = trap_data.type
	
	var entity_name = "何か"
	if is_instance_valid(entity):
		entity_name = entity.name
		if "enemy_name" in entity:
			entity_name = entity.enemy_name
		elif entity == main.player:
			entity_name = "自分"
			
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("%sは罠を踏んだ！" % entity_name, Color.RED)
		
	if type == "poison_gas":
		create_poison_gas(pos)
		
	# Reveal the trap so it stays visible and persists
	reveal_trap(pos)

func create_poison_gas(pos: Vector2i):
	# Gas-like random spread from origin
	if pos.x >= 0 and pos.x < main.MAP_WIDTH and pos.y >= 0 and pos.y < main.MAP_HEIGHT:
		main._poison_gas_tiles[pos] = {
			"turns_remaining": 10,
			"density": 3
		}
	
	var frontier = [pos]
	var visited = {pos: true}
	
	for _wave in range(3):
		var next_frontier = []
		for cur in frontier:
			var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			dirs.shuffle()
			for d in dirs:
				var npos = cur + d
				if npos.x < 0 or npos.x >= main.MAP_WIDTH or npos.y < 0 or npos.y >= main.MAP_HEIGHT:
					continue
				if visited.has(npos):
					continue
				if main._map_data[npos.x][npos.y] in [main.CellType.WALL, main.CellType.WOOD_WALL]:
					continue
				visited[npos] = true
				
				var spread_chance = 0.8 - _wave * 0.2
				if randf() < spread_chance:
					var density = max(1, 3 - _wave)
					var turns = 8 + randi() % 3 - _wave
					if not main._poison_gas_tiles.has(npos) or main._poison_gas_tiles[npos].turns_remaining < turns:
						main._poison_gas_tiles[npos] = {
							"turns_remaining": max(2, turns),
							"density": density
						}
					next_frontier.append(npos)
		frontier = next_frontier
	
	if main.has_node("/root/LogUI"):
		main.get_node("/root/LogUI").add_log("[毒] 毒ガスが噴き出した！", Color(0.6, 0.2, 0.8))

func process_poison_gas():
	if main._poison_gas_tiles.is_empty():
		main._poison_gas_exposure.clear()
		return
	
	var to_remove = []
	var new_gas: Dictionary = {}
	
	for pos in main._poison_gas_tiles.keys():
		var data = main._poison_gas_tiles[pos]
		data.turns_remaining -= 1
		
		if data.turns_remaining == 5:
			data.density = max(1, data.get("density", 2) - 1)
		elif data.turns_remaining == 2:
			data.density = 1
		
		if data.turns_remaining <= 0:
			to_remove.append(pos)
			continue
		
		var density = data.get("density", 1)
		var spread_prob = 0.2 + density * 0.1
		
		var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		dirs.shuffle()
		for d in dirs:
			var npos = pos + d
			if npos.x < 0 or npos.x >= main.MAP_WIDTH or npos.y < 0 or npos.y >= main.MAP_HEIGHT:
				continue
			if main._map_data[npos.x][npos.y] in [main.CellType.WALL, main.CellType.WOOD_WALL]:
				continue
			if main._poison_gas_tiles.has(npos) and main._poison_gas_tiles[npos].turns_remaining >= data.turns_remaining:
				continue
			if new_gas.has(npos) and new_gas[npos].turns_remaining >= data.turns_remaining - 1:
				continue
			if randf() < spread_prob:
				new_gas[npos] = {
					"turns_remaining": max(1, data.turns_remaining - 1),
					"density": max(1, density - 1)
				}
	
	for pos in to_remove:
		main._poison_gas_tiles.erase(pos)
	
	for pos in new_gas.keys():
		if not main._poison_gas_tiles.has(pos):
			main._poison_gas_tiles[pos] = new_gas[pos]
		else:
			if new_gas[pos].turns_remaining > main._poison_gas_tiles[pos].turns_remaining:
				main._poison_gas_tiles[pos] = new_gas[pos]
	
	var current_exposure = {}
	if not main or not main.get_tree():
		return
	for entity in main.get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity):
			continue
		var entity_grid = main.tile_map.local_to_map(entity.position)
		if not main._poison_gas_tiles.has(entity_grid):
			continue
		
		var entity_id = entity.get_instance_id()
		var turns_in_gas = int(main._poison_gas_exposure.get(entity_id, 0)) + 1
		current_exposure[entity_id] = turns_in_gas
		
		if turns_in_gas >= 1 and entity.has_method("take_damage"):
			entity.take_damage(2, null, ["poison"])
			if main.has_node("/root/LogUI"):
				var entity_name = entity.name
				if "enemy_name" in entity:
					entity_name = entity.enemy_name
				elif entity == main.player:
					entity_name = "Player"
				main.get_node("/root/LogUI").add_log("%s は毒ガスでむせ返っている！" % entity_name, Color(0.6, 0.2, 0.8))
			
			# Apply poison status effect if it exists
			if entity.has_method("apply_effect"):
				entity.apply_effect("poison", {"duration": 5, "damage": 1})
				
	main._poison_gas_exposure = current_exposure
	
	main._calculate_fov()
	main._draw_map()

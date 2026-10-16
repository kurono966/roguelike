class_name SkillExecutor
extends Node

var main_node: Node2D
var player: CharacterBody2D
var tile_map: TileMap
var map_controller: MapController

const CellType = MapDefinitions.CellType
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	player = main.player
	tile_map = main.tile_map
	map_controller = main.map_controller

func execute_skill(target_pos: Vector2, skill_data: Dictionary):
	var skill_id = skill_data.get("id", "")
	var skill_type = skill_data.get("type", "self")
	
	match skill_type:
		"self":
			await _execute_self_skill(skill_data)
		"direction":
			await _execute_directional_skill(target_pos, skill_data)
		"point":
			await _execute_point_skill(target_pos, skill_data)
		"target_enemy":
			await _execute_target_enemy_skill(target_pos, skill_data)

func _execute_self_skill(skill_data: Dictionary):
	var skill_id = skill_data.get("id", "")
	var mp_cost = skill_data.get("mp_cost", 0)
	var hp_cost = skill_data.get("hp_cost", 0)
	
	# Check costs
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	if player.hp <= hp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("HPが足りない", Color.RED)
		return
	
	# Deduct costs
	player.mp -= mp_cost
	if hp_cost > 0:
		player.take_damage(hp_cost)
	
	match skill_id:
		"heal":
			_execute_heal_skill(skill_data)
		"teleport":
			await _execute_teleport_skill(skill_data)
		"acid_puddle":
			_execute_acid_puddle_skill(skill_data)
		"cyclone_slash":
			await _execute_cyclone_slash(skill_data)
	
	# Update UI
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_heal_skill(skill_data: Dictionary):
	var heal_amount = skill_data.get("heal_amount", 8)
	var int_bonus = player.get_total_intelligence() if player.has_method("get_total_intelligence") else player.intelligence
	var total_heal = heal_amount + int(int_bonus * 0.5)
	
	player.heal(total_heal)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("癒やしの光でHPを回復した", Color(0.3, 1.0, 0.3))

func _execute_teleport_skill(skill_data: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	var teleport_positions = []
	
	# Find valid teleport positions
	for x in range(MapDefinitions.MAP_WIDTH):
		for y in range(MapDefinitions.MAP_HEIGHT):
			var pos = Vector2i(x, y)
			if map_controller.is_walkable(pos, player.can_swim):
				var dist = player_grid.distance_to(pos)
				if dist >= 3 and dist <= 8:  # Teleport range
					teleport_positions.append(pos)
	
	if teleport_positions.is_empty():
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("転移先が見つからなかった", Color.GRAY)
		return
	
	var target_pos = teleport_positions.pick_random()
	player.move_to_grid(target_pos)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("瞬間移動した", Color.CYAN)

func _execute_acid_puddle_skill(skill_data: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	var radius = 1
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = player_grid + Vector2i(dx, dy)
			if map_controller.is_grid_in_bounds(pos):
				main_node.create_hazard("acid", Vector2(pos) * TILE_SIZE)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("酸の水溜まりを撒き散らした", Color.GREEN)

func _execute_cyclone_slash(skill_data: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	var damage = _calculate_skill_damage(skill_data, null)
	var elements = _get_skill_elements(skill_data)
	
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			
			var target_grid = player_grid + Vector2i(dx, dy)
			var target_pos = Vector2(target_grid) * TILE_SIZE
			
			# Check for enemies
			for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
					continue
				
				var enemy_grid = tile_map.local_to_map(enemy.position)
				if enemy_grid == target_grid:
					main_node._handle_attack(player, enemy)
					break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("回転斬りを放った", Color.ORANGE)

func _execute_directional_skill(target_pos: Vector2, skill_data: Dictionary):
	var skill_id = skill_data.get("id", "")
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var direction = (target_grid - player_grid).sign()
	
	# Normalize direction to cardinal
	if abs(direction.x) > abs(direction.y):
		direction = Vector2i(sign(direction.x), 0)
	else:
		direction = Vector2i(0, sign(direction.y))
	
	match skill_id:
		"fireball":
			await _execute_fireball_skill(direction, skill_data)
		"iceball":
			await _execute_iceball_skill(direction, skill_data)
		"lightning":
			await _execute_lightning_skill(direction, skill_data)
		"blank_shot":
			await _execute_blank_shot_skill(direction, skill_data)
		"web_shot":
			await _execute_web_shot_skill(direction, skill_data)
		"gale_thrust":
			await _execute_gale_thrust_skill(target_pos, skill_data)
		"grass_snipe":
			await _execute_grass_snipe_skill(target_pos, skill_data)
		"blood_beam":
			await _execute_blood_beam_skill(direction, skill_data)
		"charge":
			await _execute_charge_skill(target_pos)
		_:
			await _execute_generic_direction_skill(direction, skill_data)

func _execute_fireball_skill(direction: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 3)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var damage = _calculate_skill_damage(skill_data, null)
	var player_grid = tile_map.local_to_map(player.position)
	var range_val = skill_data.get("range", 6)
	
	# Fire projectile along direction
	for i in range(1, range_val + 1):
		var check_pos = player_grid + direction * i
		if not map_controller.is_grid_in_bounds(check_pos):
			break
		
		var cell = map_controller.map_data[check_pos.x][check_pos.y]
		if cell in [CellType.WALL, CellType.WOOD_WALL]:
			main_node._ignite_grass(check_pos)
			break
		
		# Check for enemies
		var hit_enemy = false
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == check_pos:
				main_node._handle_attack(player, enemy)
				hit_enemy = true
				
				# Apply burn effect
				if enemy.has_method("apply_effect"):
					enemy.apply_effect("burn", {"duration": 5, "damage": 1})
				break
		
		if hit_enemy:
			break
		
		# Spawn fire visual
		var fire_pos = Vector2(check_pos) * TILE_SIZE
		main_node._spawn_skill_particles(fire_pos + Vector2(16, 16), "fire", 0.3)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("火炎球を放った", Color.ORANGE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_iceball_skill(direction: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 3)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var damage = _calculate_skill_damage(skill_data, null)
	var player_grid = tile_map.local_to_map(player.position)
	var range_val = skill_data.get("range", 6)
	
	for i in range(1, range_val + 1):
		var check_pos = player_grid + direction * i
		if not map_controller.is_grid_in_bounds(check_pos):
			break
		
		var cell = map_controller.map_data[check_pos.x][check_pos.y]
		if cell in [CellType.WALL, CellType.WOOD_WALL]:
			break
		
		# Check for enemies
		var hit_enemy = false
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == check_pos:
				main_node._handle_attack(player, enemy)
				hit_enemy = true
				
				# Apply freeze effect
				if enemy.has_method("apply_effect"):
					enemy.apply_effect("paralyze", {"duration": 3})
				break
		
		if hit_enemy:
			break
		
		# Freeze water tiles
		if cell == CellType.WATER:
			map_controller.map_data[check_pos.x][check_pos.y] = CellType.ICE
			main_node.tileset_manager.update_tile(check_pos.x, check_pos.y, CellType.WATER)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("アイス・ボールを放った", Color.CYAN)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_lightning_skill(direction: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 6)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var damage = _calculate_skill_damage(skill_data, null)
	var player_grid = tile_map.local_to_map(player.position)
	var range_val = skill_data.get("range", 5)
	
	# Find first target in direction
	var target_pos = null
	for i in range(1, range_val + 1):
		var check_pos = player_grid + direction * i
		if not map_controller.is_grid_in_bounds(check_pos):
			break
		
		var cell = map_controller.map_data[check_pos.x][check_pos.y]
		if cell in [CellType.WALL, CellType.WOOD_WALL]:
			break
		
		# Check for enemies
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == check_pos:
				target_pos = enemy.position
				break
		
		if target_pos:
			break
	
	if target_pos:
		main_node._handle_attack(player, main_node.get_node_at_position(target_pos))
		main_node._spawn_skill_particles(target_pos + Vector2(16, 16), "lightning", 0.5)
		
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("紫電を放った", Color.YELLOW)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_blank_shot_skill(direction: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 2)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var damage = _calculate_skill_damage(skill_data, null)
	var player_grid = tile_map.local_to_map(player.position)
	var range_val = skill_data.get("range", 4)
	
	for i in range(1, range_val + 1):
		var check_pos = player_grid + direction * i
		if not map_controller.is_grid_in_bounds(check_pos):
			break
		
		var cell = map_controller.map_data[check_pos.x][check_pos.y]
		if cell in [CellType.WALL, CellType.WOOD_WALL]:
			break
		
		# Check for enemies
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == check_pos:
				main_node._handle_attack(player, enemy)
				break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("ブランク・ショットを放った", Color.WHITE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_web_shot_skill(direction: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 4)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var damage = _calculate_skill_damage(skill_data, null)
	var player_grid = tile_map.local_to_map(player.position)
	var range_val = skill_data.get("range", 5)
	
	for i in range(1, range_val + 1):
		var check_pos = player_grid + direction * i
		if not map_controller.is_grid_in_bounds(check_pos):
			break
		
		var cell = map_controller.map_data[check_pos.x][check_pos.y]
		if cell in [CellType.WALL, CellType.WOOD_WALL]:
			break
		
		# Check for enemies
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == check_pos:
				main_node._handle_attack(player, enemy)
				
				# Apply paralyze effect
				if enemy.has_method("apply_effect"):
					enemy.apply_effect("paralyze", {"duration": 3})
				break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("蜘蛛の糸を放った", Color.GRAY)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_gale_thrust_skill(target_pos: Vector2, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 4)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var line_points = _get_line_points(player_grid, target_grid)
	var damage = _calculate_skill_damage(skill_data, null)
	
	for point in line_points:
		if not map_controller.is_grid_in_bounds(point):
			continue
		
		# Check for enemies
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == point:
				main_node._handle_attack(player, enemy)
				
				# Knockback
				var knock_dir = (enemy_grid - player_grid).sign()
				var knock_pos = enemy_grid + knock_dir
				if map_controller.is_walkable(knock_pos, enemy.can_swim if enemy.has_method("can_swim") else false):
					enemy.move_to_grid(knock_pos)
				break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("烈風突きを放った", Color.CYAN)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_grass_snipe_skill(target_pos: Vector2, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 4)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var distance = player_grid.distance_to(target_grid)
	
	# Cannot target adjacent enemies
	if distance <= 1.5:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("隣接する敵には当たらない", Color.GRAY)
		main_node.target_manager.cancel_targeting()
		await main_node._end_player_turn()
		return
	
	var damage = _calculate_skill_damage(skill_data, null)
	
	# Double damage if in grass
	if player.is_in_grass:
		damage *= 2
	
	# Check for enemy at target
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		
		var enemy_grid = tile_map.local_to_map(enemy.position)
		if enemy_grid == target_grid:
			main_node._handle_attack(player, enemy)
			break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("グラス・スナイプを放った", Color.GREEN)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_blood_beam_skill(direction: Vector2i, skill_data: Dictionary):
	var hp_cost = skill_data.get("hp_cost", 5)
	if player.hp <= hp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("HPが足りない", Color.RED)
		return
	
	player.take_damage(hp_cost)
	
	var damage = _calculate_skill_damage(skill_data, null)
	var player_grid = tile_map.local_to_map(player.position)
	var range_val = skill_data.get("range", 7)
	var blind_chance = skill_data.get("blind_chance", 0.4)
	var transfer_status = skill_data.get("transfer_status", false)
	
	# Find first target
	var target_enemy = null
	for i in range(1, range_val + 1):
		var check_pos = player_grid + direction * i
		if not map_controller.is_grid_in_bounds(check_pos):
			break
		
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == check_pos:
				target_enemy = enemy
				break
		
		if target_enemy:
			break
	
	if target_enemy:
		main_node._handle_attack(player, target_enemy)
		
		# Blind chance
		if randf() < blind_chance and target_enemy.has_method("apply_effect"):
			target_enemy.apply_effect("blind", {"duration": 5})
		
		# Transfer status effects
		if transfer_status:
			for effect_id in player.status_effects.keys():
				if target_enemy.has_method("apply_effect"):
					target_enemy.apply_effect(effect_id, player.status_effects[effect_id].duplicate())
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("ブラッド・ビームを放った", Color.RED)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_charge_skill(target_pos: Vector2):
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var path = map_controller.astar_grid.get_id_path(player_grid, target_grid)
	
	if path.size() <= 1:
		return
	
	# Move along path until hit
	for i in range(1, path.size()):
		var next_pos = path[i]
		var direction = Vector2(next_pos - player_grid).sign()
		
		# Check for collision
		var hit_enemy = false
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			
			var enemy_grid = tile_map.local_to_map(enemy.position)
			if enemy_grid == next_pos:
				main_node._handle_attack(player, enemy)
				
				# Knockback
				var knock_dir = direction
				var knock_pos = enemy_grid + knock_dir
				if map_controller.is_grid_in_bounds(knock_pos) and map_controller.is_walkable(knock_pos, enemy.can_swim if enemy.has_method("can_swim") else false):
					enemy.move_to_grid(knock_pos)
				
				hit_enemy = true
				break
		
		if hit_enemy:
			break
		
		# Move player
		player.move_to_grid(next_pos)
		player_grid = next_pos
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("猛牛突進を放った", Color.ORANGE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_generic_direction_skill(direction: Vector2i, skill_data: Dictionary):
	# Fallback for unimplemented directional skills
	var mp_cost = skill_data.get("mp_cost", 0)
	if mp_cost > 0 and player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	if mp_cost > 0:
		player.mp -= mp_cost
		if main_node.PlayerUi:
			main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_point_skill(target_pos: Vector2, skill_data: Dictionary):
	var skill_id = skill_data.get("id", "")
	var target_grid = tile_map.local_to_map(target_pos)
	
	match skill_id:
		"explosion":
			await _execute_explosion_skill(target_grid, skill_data)
		"meteor":
			await _execute_meteor_skill(target_grid, skill_data)
		"freeze":
			await _execute_freeze_skill_player(target_grid, skill_data)
		"wall":
			await _execute_wall_skill(target_grid, skill_data)
		_:
			await _execute_generic_point_skill(target_grid, skill_data)

func _execute_explosion_skill(target_grid: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 8)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var radius = skill_data.get("radius", 1)
	var damage = _calculate_skill_damage(skill_data, null)
	
	# Apply damage in radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = target_grid + Vector2i(dx, dy)
			if not map_controller.is_grid_in_bounds(pos):
				continue
			
			var world_pos = Vector2(pos) * TILE_SIZE
			main_node._spawn_skill_particles(world_pos + Vector2(16, 16), "explosion", 0.6)
			main_node._ignite_grass(pos)
			
			# Check for enemies
			for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
					continue
				
				var enemy_grid = tile_map.local_to_map(enemy.position)
				if enemy_grid == pos:
					main_node._handle_attack(player, enemy)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("爆裂魔法を放った", Color.ORANGE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_meteor_skill(target_grid: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 15)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var radius = skill_data.get("radius", 2)
	var damage = _calculate_skill_damage(skill_data, null)
	
	# Apply damage in larger radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = target_grid + Vector2i(dx, dy)
			if not map_controller.is_grid_in_bounds(pos):
				continue
			
			var world_pos = Vector2(pos) * TILE_SIZE
			main_node._spawn_skill_particles(world_pos + Vector2(16, 16), "meteor", 0.8)
			main_node._ignite_grass(pos)
			
			# Check for enemies
			for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
					continue
				
				var enemy_grid = tile_map.local_to_map(enemy.position)
				if enemy_grid == pos:
					main_node._handle_attack(player, enemy)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("メテオ・ストライクを放った", Color.RED)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_freeze_skill_player(target_grid: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 5)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	await _apply_freeze_area(player, target_grid, skill_data)

func _apply_freeze_area(caster, target_grid: Vector2i, skill_data: Dictionary):
	var radius = skill_data.get("radius", 1)
	var damage = skill_data.get("damage", 6)
	var froze_any = false
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = target_grid + Vector2i(dx, dy)
			if not map_controller.is_grid_in_bounds(pos):
				continue
			
			var cell = map_controller.map_data[pos.x][pos.y]
			
			if cell == CellType.WATER:
				map_controller.map_data[pos.x][pos.y] = CellType.ICE
				main_node.tileset_manager.update_tile(pos.x, pos.y, CellType.WATER)
				froze_any = true
				
				var world_pos = Vector2(pos) * TILE_SIZE
				main_node._spawn_skill_particles(world_pos + Vector2(16, 16), "ice", 0.4)
			
			# Damage enemies in area
			for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
					continue
				
				var enemy_grid = tile_map.local_to_map(enemy.position)
				if enemy_grid == pos:
					if caster == player:
						main_node._handle_attack(player, enemy)
					else:
						main_node._handle_attack(caster, enemy)
	
	if froze_any:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("氷結魔法を放った", Color.CYAN)
	else:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("凍結できる水がなかった", Color.GRAY)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_wall_skill(target_grid: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 5)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	if not map_controller.is_grid_in_bounds(target_grid):
		return
	
	var cell = map_controller.map_data[target_grid.x][target_grid.y]
	
	# Check if there's an entity at target
	var entity_at_target = null
	for entity in main_node.get_tree().get_nodes_in_group("enemies") + main_node.get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(entity) or entity.is_queued_for_deletion():
			continue
		
		var entity_grid = tile_map.local_to_map(entity.position)
		if entity_grid == target_grid:
			entity_at_target = entity
			break
	
	if entity_at_target:
		# Damage entity and try to displace
		main_node._handle_attack(player, entity_at_target)
		
		# Try to find empty adjacent cell
		var displaced = false
		var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		directions.shuffle()
		
		for dir in directions:
			var new_pos = target_grid + dir
			if map_controller.is_grid_in_bounds(new_pos) and map_controller.is_walkable(new_pos, entity_at_target.can_swim if entity_at_target.has_method("can_swim") else false):
				entity_at_target.move_to_grid(new_pos)
				displaced = true
				break
		
		if not displaced:
			# No escape, entity dies
			entity_at_target.take_damage(999, player)
	
	# Place wall
	map_controller.map_data[target_grid.x][target_grid.y] = CellType.WALL
	main_node.tileset_manager.update_tile(target_grid.x, target_grid.y, cell)
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("ウォールを生成した", Color.GRAY)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_generic_point_skill(target_grid: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 0)
	if mp_cost > 0 and player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	if mp_cost > 0:
		player.mp -= mp_cost
		if main_node.PlayerUi:
			main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_target_enemy_skill(target_pos: Vector2, skill_data: Dictionary):
	var skill_id = skill_data.get("id", "")
	var target_grid = tile_map.local_to_map(target_pos)
	
	match skill_id:
		"helm_splitter":
			await _execute_helm_splitter_skill(target_pos, skill_data)
		"super_seoi_nage":
			await _execute_super_seoi_nage_skill(target_pos, skill_data)
		"mug":
			await _execute_mug_skill(target_pos, skill_data)
		_:
			await _execute_generic_target_skill(target_grid, skill_data)

func _execute_helm_splitter_skill(target_pos: Vector2, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 3)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	
	# Check if adjacent
	var distance = player_grid.distance_to(target_grid)
	if distance > 1.5:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("隣接する敵のみ対象", Color.GRAY)
		main_node.target_manager.cancel_targeting()
		await main_node._end_player_turn()
		return
	
	# Find enemy at target
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		
		var enemy_grid = tile_map.local_to_map(enemy.position)
		if enemy_grid == target_grid:
			# Calculate damage with penetration
			var base_damage = _calculate_skill_damage(skill_data, enemy)
			var penetration = 0.6  # 60% penetration
			
			# Temporarily set penetration for this attack
			var old_pen = player.penetration_rate if player.has_method("penetration_rate") else 0.0
			if player.has_method("penetration_rate"):
				player.penetration_rate = penetration
			
			main_node._handle_attack(player, enemy)
			
			# Restore penetration
			if player.has_method("penetration_rate"):
				player.penetration_rate = old_pen
			
			break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("兜割りを放った", Color.ORANGE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_super_seoi_nage_skill(target_pos: Vector2, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 4)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var user_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var offset = target_grid - user_grid
	var throw_dir = -offset.sign()
	var throw_distance = skill_data.get("throw_distance", 5)
	var landing_damage = skill_data.get("landing_damage", 6)
	var collision_damage = skill_data.get("collision_damage", 12)
	
	# Check if adjacent
	var distance = user_grid.distance_to(target_grid)
	if distance > 1.5:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("隣接する敵のみ対象", Color.GRAY)
		main_node.target_manager.cancel_targeting()
		await main_node._end_player_turn()
		return
	
	# Find enemy at target
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		
		var enemy_grid = tile_map.local_to_map(enemy.position)
		if enemy_grid == target_grid:
			# Calculate throw path
			var landing_pos = target_grid
			for i in range(1, throw_distance + 1):
				var check_pos = target_grid + throw_dir * i
				if not map_controller.is_grid_in_bounds(check_pos):
					break
				
				var cell = map_controller.map_data[check_pos.x][check_pos.y]
				if cell in [CellType.WALL, CellType.WOOD_WALL]:
					break
				
				landing_pos = check_pos
			
			# Move enemy
			enemy.move_to_grid(landing_pos)
			
			# Apply landing damage
			enemy.take_damage(landing_damage, player)
			
			# Check for collision
			for other_enemy in main_node.get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(other_enemy) or other_enemy.is_queued_for_deletion():
					continue
				if other_enemy == enemy:
					continue
				
				var other_grid = tile_map.local_to_map(other_enemy.position)
				if other_grid == landing_pos:
					other_enemy.take_damage(collision_damage, player)
					enemy.take_damage(collision_damage, player)
					break
			
			break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("超背負投を放った", Color.ORANGE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_mug_skill(target_pos: Vector2, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 2)
	if player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	player.mp -= mp_cost
	if main_node.PlayerUi:
		main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	
	# Check if adjacent
	var distance = player_grid.distance_to(target_grid)
	if distance > 1.5:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("隣接する敵のみ対象", Color.GRAY)
		main_node.target_manager.cancel_targeting()
		await main_node._end_player_turn()
		return
	
	# Find enemy at target
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		
		var enemy_grid = tile_map.local_to_map(enemy.position)
		if enemy_grid == target_grid:
			# Attack and steal gold
			main_node._handle_attack(player, enemy)
			
			var steal_amount = randi_range(1, 10)
			if enemy.gold and enemy.gold >= steal_amount:
				enemy.gold -= steal_amount
				player.gold += steal_amount
				
				if main_node.has_node("/root/LogUI"):
					main_node.get_node("/root/LogUI").add_log("%dGを奪った！" % steal_amount, Color.YELLOW)
			
			break
	
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log("強奪を放った", Color.ORANGE)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _execute_generic_target_skill(target_grid: Vector2i, skill_data: Dictionary):
	var mp_cost = skill_data.get("mp_cost", 0)
	if mp_cost > 0 and player.mp < mp_cost:
		if main_node.has_node("/root/LogUI"):
			main_node.get_node("/root/LogUI").add_log("MPが足りない", Color.RED)
		return
	
	if mp_cost > 0:
		player.mp -= mp_cost
		if main_node.PlayerUi:
			main_node.PlayerUi.update_mp(player.mp, player.max_mp)
	
	main_node.target_manager.cancel_targeting()
	await main_node._end_player_turn()

func _calculate_skill_damage(skill: Dictionary, target_entity) -> int:
	var base_dmg = skill.get("damage", 0)
	var dmg = 0
	
	if typeof(base_dmg) == TYPE_FLOAT:
		# Multiplier-based damage
		var base_attack = player.attack_power if player else 1
		dmg = int(base_attack * base_dmg)
	else:
		dmg = base_dmg
	
	# Apply stat scaling
	if skill.has("str_scaling"):
		var str_val = player.get_total_strength() if player.has_method("get_total_strength") else player.strength
		dmg += int(str_val * skill["str_scaling"])
	
	if skill.has("dex_scaling"):
		var dex_val = player.get_total_dexterity() if player.has_method("get_total_dexterity") else player.dexterity
		dmg += int(dex_val * skill["dex_scaling"])
	
	if skill.has("int_scaling"):
		var int_val = player.get_total_intelligence() if player.has_method("get_total_intelligence") else player.intelligence
		dmg += int(int_val * skill["int_scaling"])
	
	# Crystal floor magic boost (+50%)
	if skill.get("is_magic", false) and player:
		var p_grid = tile_map.local_to_map(player.position)
		if map_controller.is_grid_in_bounds(p_grid) and map_controller.map_data[p_grid.x][p_grid.y] == CellType.CRYSTAL_FLOOR:
			dmg = int(dmg * 1.5)
			if main_node.has_node("/root/LogUI"):
				main_node.get_node("/root/LogUI").add_log("[*] 結晶床の魔力共鳴で威力が上昇した！ (+50%)", Color(0.4, 0.9, 1.0))
	
	return max(1, dmg)

func _get_skill_elements(skill: Dictionary) -> Array:
	var elems = skill.get("elements", [])
	if elems.is_empty():
		elems = ["normal"]
	return elems

func _get_line_points(start: Vector2i, end: Vector2i) -> Array:
	var points = []
	var dx = abs(end.x - start.x)
	var dy = abs(end.y - start.y)
	var sx = 1 if start.x < end.x else -1
	var sy = 1 if start.y < end.y else -1
	var err = dx - dy
	
	var x = start.x
	var y = start.y
	
	while true:
		points.append(Vector2i(x, y))
		
		if x == end.x and y == end.y:
			break
		
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	
	return points

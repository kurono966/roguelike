class_name EnemyManager
extends Node

var main_node: Node2D
var tile_map: TileMap
var map_controller: MapController

const EnemyScene = preload("res://actors/enemy/enemy.tscn")
const EnemyDatabase = preload("res://actors/enemy/enemy_database.gd")

# Enemy spawning
const MAX_ENEMIES_PER_ROOM = 2
const SPAWN_INTERVAL = 50
const MAX_ACTIVE_ENEMIES = 105

# Enemy state
var current_floor: int = 0
var current_branch: int = 0

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	map_controller = main.map_controller

func spawn_enemies_for_floor(floor: int, branch: int, rooms: Array):
	current_floor = floor
	current_branch = branch
	
	if floor == 0:
		_spawn_village_npcs()
		return
	
	for room in rooms:
		var enemies_in_room = randi() % (MAX_ENEMIES_PER_ROOM + 1)
		
		# More enemies in deeper floors
		var depth_bonus = floor / 3
		enemies_in_room += depth_bonus
		
		for i in range(enemies_in_room):
			_spawn_enemy_in_room(room)

func _spawn_enemy_in_room(room: Rect2i):
	var enemy_data = _get_random_enemy_data()
	if enemy_data.is_empty():
		return
	
	var spawn_pos = _get_random_position_in_room(room)
	if spawn_pos == Vector2i.ZERO:
		return
	
	var enemy = EnemyScene.instantiate()
	enemy.position = Vector2(spawn_pos) * TILE_SIZE
	
	# Apply enemy data
	enemy.enemy_id = enemy_data.get("id", "zakomushi")
	enemy.enemy_name = enemy_data.get("name", "Enemy")
	enemy.sprite_path = enemy_data.get("sprite_path", "")
	enemy.hp = enemy_data.get("hp", 5)
	enemy.max_hp = enemy.hp
	enemy.attack_power = enemy_data.get("attack", 1)
	enemy.defense = enemy_data.get("defense", 0)
	enemy.exp_reward = enemy_data.get("exp_reward", 2)
	
	# Apply special properties
	if enemy_data.has("can_swim"):
		enemy.can_swim = enemy_data["can_swim"]
	if enemy_data.has("is_flying"):
		enemy.is_flying = enemy_data["is_flying"]
	if enemy_data.has("attack_range"):
		enemy.attack_range = enemy_data["attack_range"]
	if enemy_data.has("skill_id"):
		enemy.skill_id = enemy_data["skill_id"]
	if enemy_data.has("loot_table"):
		enemy.loot_table = enemy_data["loot_table"]
	if enemy_data.has("on_hit_effects"):
		enemy.on_hit_effects = enemy_data["on_hit_effects"]
	if enemy_data.has("weaknesses"):
		enemy.weaknesses = enemy_data["weaknesses"]
	if enemy_data.has("resistances"):
		enemy.resistances = enemy_data["resistances"]
	if enemy_data.has("fire_immune"):
		enemy.fire_immune = enemy_data["fire_immune"]
	
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	
	main_node.add_child(enemy)
	print("Spawned enemy: ", enemy.enemy_name, " at ", spawn_pos)

func _get_random_enemy_data() -> Dictionary:
	var all_enemies = EnemyDatabase.get_enemy_definitions(current_floor, current_branch)
	if all_enemies.is_empty():
		return {}
	
	# Filter enemies by floor/branch requirements
	var available_enemies = []
	for enemy_data in all_enemies:
		var min_floor = enemy_data.get("min_floor", 1)
		var max_floor = enemy_data.get("max_floor", 99)
		var allowed_branches = enemy_data.get("branches", [])
		
		if current_floor < min_floor or current_floor > max_floor:
			continue
		
		if not allowed_branches.is_empty() and not allowed_branches.has(current_branch):
			continue
		
		available_enemies.append(enemy_data)
	
	if available_enemies.is_empty():
		return all_enemies.pick_random()
	
	return available_enemies.pick_random()

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
		
		# Check if occupied
		var occupied = false
		if not main_node or not main_node.get_tree():
			return Vector2i.ZERO
		for entity in main_node.get_tree().get_nodes_in_group("entities"):
			if not is_instance_valid(entity) or entity.is_queued_for_deletion():
				continue
			
			var entity_grid = tile_map.local_to_map(entity.position)
			if entity_grid == pos:
				occupied = true
				break
		
		if not occupied:
			return pos
	
	return Vector2i.ZERO

func _spawn_village_npcs():
	# Spawn friendly NPCs in starting village
	var npc_positions = [
		Vector2i(10, 10),
		Vector2i(15, 12),
		Vector2i(12, 15)
	]
	
	for pos in npc_positions:
		if not map_controller.is_grid_in_bounds(pos):
			continue
		
		var npc = EnemyScene.instantiate()
		npc.position = Vector2(pos) * TILE_SIZE
		npc.enemy_id = "villager"
		npc.enemy_name = "村人"
		npc.is_npc = true
		npc.hp = 10
		npc.max_hp = 10
		npc.attack_power = 0
		npc.defense = 0
		npc.trade_items = [
			{"id": "potion", "price": 15},
			{"id": "gummy", "price": 12}
		]
		
		npc.add_to_group("npcs")
		npc.add_to_group("entities")
		
		main_node.add_child(npc)
		print("Spawned NPC: ", npc.enemy_name, " at ", pos)

func try_spawn_periodic_enemy():
	if current_floor == 0 or current_floor == 6:
		return
	
	if not main_node or not main_node.get_tree():
		return
	var current_enemies = main_node.get_tree().get_nodes_in_group("enemies").size()
	if current_enemies >= MAX_ACTIVE_ENEMIES:
		return
	
	# Spawn near player but not in view
	var player_grid = tile_map.local_to_map(main_node.player.position)
	var spawn_positions = []
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			var dist = player_grid.distance_to(pos)
			
			if dist >= 10 and dist <= 20:
				if map_controller.is_walkable(pos, false):
					var cell = map_controller.map_data[pos.x][pos.y]
					if cell == CellType.FLOOR or cell == CellType.GRASS:
						spawn_positions.append(pos)
	
	if spawn_positions.is_empty():
		return
	
	var spawn_pos = spawn_positions.pick_random()
	var enemy_data = _get_random_enemy_data()
	
	if not enemy_data.is_empty():
		var enemy = EnemyScene.instantiate()
		enemy.position = Vector2(spawn_pos) * TILE_SIZE
		
		enemy.enemy_id = enemy_data.get("id", "zakomushi")
		enemy.enemy_name = enemy_data.get("name", "Enemy")
		enemy.hp = enemy_data.get("hp", 5)
		enemy.max_hp = enemy.hp
		enemy.attack_power = enemy_data.get("attack", 1)
		enemy.defense = enemy_data.get("defense", 0)
		
		enemy.add_to_group("enemies")
		enemy.add_to_group("entities")
		
		main_node.add_child(enemy)
		print("Periodic Spawn: ", enemy.enemy_name, " at ", spawn_pos)

func get_visible_enemies() -> Array:
	var visible_enemies = []
	if not main_node or not main_node.get_tree():
		return visible_enemies
	var enemies = main_node.get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if main_node.visibility_manager and main_node.visibility_manager.is_entity_visible_to_player(enemy):
			visible_enemies.append(enemy)
	
	return visible_enemies

func get_hostile_entities(actor: Node2D) -> Array:
	var hostiles = []
	
	if "fear" in actor and actor.fear >= 50:
		hostiles.append(main_node.player)
		return hostiles
	
	if "is_hostile_to_player_only" in actor and actor.is_hostile_to_player_only:
		hostiles.append(main_node.player)
		return hostiles
	
	if not main_node or not main_node.get_tree():
		return hostiles
	if actor.is_in_group("enemies"):
		hostiles.append_array(main_node.get_tree().get_nodes_in_group("npcs"))
		hostiles.append(main_node.player)
	elif actor.is_in_group("npcs"):
		for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
			if "is_hostile_to_player_only" in enemy and enemy.is_hostile_to_player_only:
				continue
			hostiles.append(enemy)
	
	return hostiles

func get_closest_hostile(actor: Node2D) -> Node2D:
	var hostiles = get_hostile_entities(actor)
	
	var closest = null
	var min_dist = INF
	
	for h in hostiles:
		if not is_instance_valid(h) or h.is_queued_for_deletion():
			continue
		if "hp" in h and h.hp <= 0:
			continue
		
		var d = actor.position.distance_to(h.position)
		if d < min_dist:
			min_dist = d
			closest = h
	
	return closest

func remove_all_enemies():
	if not main_node or not main_node.get_tree():
		return
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	
	for npc in main_node.get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc):
			npc.queue_free()
	
	for ally in main_node.get_tree().get_nodes_in_group("allies"):
		if is_instance_valid(ally):
			ally.queue_free()

func get_enemy_at_grid(grid_pos: Vector2i) -> Node2D:
	if not main_node or not main_node.get_tree():
		return null
	for enemy in main_node.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		
		var enemy_grid = tile_map.local_to_map(enemy.position)
		if enemy_grid == grid_pos:
			return enemy
	
	return null

func get_npc_at_grid(grid_pos: Vector2i) -> Node2D:
	if not main_node or not main_node.get_tree():
		return null
	for npc in main_node.get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(npc) or npc.is_queued_for_deletion():
			continue
		
		var npc_grid = tile_map.local_to_map(npc.position)
		if npc_grid == grid_pos:
			return npc
	
	return null

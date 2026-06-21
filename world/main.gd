extends Node2D

const WHITE_TILE_SOURCE_ID = 2
const LAYER_VISIBLE = 0
const LAYER_MEMORY = 1
const LAYER_DEBUG = 2

enum TurnPhase { PLAYER_TURN, ENEMY_TURN, TARGETING }
var _current_game_state = TurnPhase.PLAYER_TURN
var _current_target_enemy = null  # 現在ターゲット中の敵

@onready var player = $Player
@onready var tile_map = $TileMap
var memory_tile_map: TileMap
@onready var camera = $Camera2D
@onready var hit_sound_player = $HitSoundPlayer

const EnemyScene = preload("res://actors/enemy/enemy.tscn")  # 全エネミー共通シーン
const WorldItemScene = preload("res://items/world_item.tscn")
const ItemDatabase = preload("res://items/item_database.gd")
const TorchScene = preload("res://items/torch.tscn")
# const ItemTexture = preload("res://assets/placeholder_bait.png")

const TILE_SIZE = MapDefinitions.TILE_SIZE  # 1タイルのサイズ（ピクセル）
const MAP_WIDTH = MapDefinitions.MAP_WIDTH   # マップの幅（タイル数）
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT  # マップの高さ（タイル数）

const FOV_RADIUS = 8 # Field of View radius

const MAX_ENEMIES_PER_ROOM = 2
const SHOP_MAX_USES_PER_FLOOR = 2
const SHOP_OFFERS = [
	{"id": "potion", "price": 15},
	{"id": "gummy", "price": 12},
	{"id": "ether", "price": 18},
	{"id": "scroll_teleport", "price": 25},
	{"id": "high_potion", "price": 40},
	{"id": "high_ether", "price": 40},
	{"id": "potion_str", "price": 60}
]

# Enemy Stats Table (ID -> Stats)
# Used to configure spawned enemies

const CellType = MapDefinitions.CellType
var _map_data = []
var _current_branch = 0 # 0: Normal, 1: Dangerous/Alternative
var current_floor = 0 # Start on floor 0 (Overworld)
var _is_on_world_map: bool = false
var _world_map_data: Array = []
var _saved_allies: Array = []
var _world_player_pos: Vector2i = Vector2i.ZERO
var _ascii_map_layer: CanvasLayer = null
var _ascii_map_label: RichTextLabel = null
var _starting_village_pos: Vector2i = Vector2i.ZERO
var _dungeon_village_pos: Vector2i = Vector2i.ZERO
var _floor_caches = {} # Caches for all floors: floor_key -> cache_dict
var _visible_tiles = [] # Stores current visibility state
var _explored_tiles = [] # Stores tiles the player has seen
var _rooms = []
var _astar_grid = AStarGrid2D.new()
var _astar_grid_swim = AStarGrid2D.new()
var _astar_grid_fly = AStarGrid2D.new()
var combat_manager: CombatManager
var turn_manager: TurnManager
var visibility_manager: VisibilityManager
var tileset_manager: TilesetManager
var shadow_manager: ShadowManager
var input_handler: InputHandler
var target_manager: TargetManager

var _is_auto_moving = false
var _auto_move_direction = Vector2.ZERO
var _auto_move_initial_mask = 0
var _last_player_grid_pos: Vector2i = Vector2i.ZERO

# Resting state
var _is_resting = false
var _rest_target_hp: bool = false
var _rest_target_mp: bool = false

var _is_processing_action = false # Lock to prevent async re-entry in _process

# マウスクリックによる経路移動
var _is_path_following = false
var _current_path: Array = []
var _path_index: int = 0
var _path_stop_on_new_enemy: bool = true
var _path_continue_after_attack: bool = false
var _is_auto_exploring: bool = false
var _auto_explore_path: Array = []
var _auto_explore_index: int = 0
const AUTO_MOVE_DELAY: float = 0.02
var _auto_move_cooldown: float = 0.0
var _enemies_at_path_start: int = 0  # 経路開始時の敵の数
var _web_audio_initialized: bool = false
var _hazards: Dictionary = {} # { Vector2i: {type, duration, damage} }
var _burning_grass: Dictionary = {} # { Vector2i: {turns_remaining} } - Tracks burning grass tiles
var _frozen_tiles: Dictionary = {} # { Vector2i: {turns_remaining} } - Frozen water tiles
var _steam_tiles: Dictionary = {} # { Vector2i: {turns_remaining} } - Steam obscuring vision
var _steam_exposure: Dictionary = {} # { instance_id: consecutive turns in steam }
var _jammed_doors: Dictionary = {} # { Vector2i: true } - Doors with broken locks that cannot be picked

var _turn_count: int = 0
const WORLD_MAP_MOVE_TURN_COST: int = 10
var _world_map_move_turn_cost_pending: bool = false
var _swimmer_cooldown: bool = false # Tracks swimmer bonus action state
const SPAWN_INTERVAL: int = 50
const MAX_ACTIVE_ENEMIES: int = 105
var _shop_uses_this_floor: int = 0

var minimap_controller: MinimapController

func _ready():
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.03, 1.0))
	randomize()
	_shop_uses_this_floor = 0
	add_to_group("main")
	player = get_node_or_null("Player")
	if not is_instance_valid(player):
		push_error("Player node is missing or invalid.")
		return
	
	combat_manager = CombatManager.new()
	combat_manager.setup(self)
	add_child(combat_manager)
	
	turn_manager = TurnManager.new()
	turn_manager.setup(self)
	add_child(turn_manager)
	
	visibility_manager = VisibilityManager.new()
	visibility_manager.setup(self)
	add_child(visibility_manager)
	
	input_handler = InputHandler.new()
	input_handler.setup(self)
	add_child(input_handler)
	
	target_manager = TargetManager.new()
	target_manager.setup(self)
	add_child(target_manager)
	
	tileset_manager = TilesetManager.new()
	tileset_manager.setup(self)
	add_child(tileset_manager)

	shadow_manager = ShadowManager.new()
	shadow_manager.name = "ShadowManager"
	add_child(shadow_manager)
	
	minimap_controller = MinimapController.new()
	add_child(minimap_controller)
	
	# Force unmute master bus just in case
	var master_bus = AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, 0.0)
		AudioServer.set_bus_mute(master_bus, false)
	
	if hit_sound_player:
		# Trying to use stream if available in scene, otherwise load generic
		if not hit_sound_player.stream:
			if ResourceLoader.exists("res://assets/sounds/shoot.mp3"):
				hit_sound_player.stream = load("res://assets/sounds/shoot.mp3")

	if is_instance_valid(player) and player.has_signal("turn_end_triggered"):
		player.turn_end_triggered.connect(func(): await _end_player_turn())
		
	if tileset_manager:
		tileset_manager.create_tileset()
		# Force tileset refresh
		tile_map.tile_set = tile_map.tile_set
		
	# Setup memory_tile_map
	memory_tile_map = TileMap.new()
	memory_tile_map.name = "MemoryTileMap"
	memory_tile_map.tile_set = tile_map.tile_set
	var memory_mat = CanvasItemMaterial.new()
	memory_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	memory_tile_map.material = memory_mat
	memory_tile_map.modulate = Color(0.32, 0.32, 0.36, 1.0)
	add_child(memory_tile_map)
	move_child(memory_tile_map, tile_map.get_index())
	
	if visibility_manager:
		visibility_manager.memory_tile_map = memory_tile_map
		
	# DEBUG starts at floor 4
	var global_gs = get_node_or_null("/root/GameState")
	if global_gs and global_gs.player_class == 99:
		current_floor = 4
		if PlayerUi:
			PlayerUi.update_floor(current_floor)
			
	if current_floor == 0:
		_init_world_map()
	else:
		_generate_map()
		_setup_pathfinding() # Setup A* grid
	
	# Now that map is generated, update visibility_manager references
	if visibility_manager:
		visibility_manager.map_data = _map_data
		visibility_manager.visible_tiles = _visible_tiles
		visibility_manager.explored_tiles = _explored_tiles
		visibility_manager.burning_grass = _burning_grass
		visibility_manager.frozen_tiles = _frozen_tiles
		visibility_manager.steam_tiles = _steam_tiles
		visibility_manager.draw_map()
	
	# Setup layers
	# Ensure we have enough layers
	while tile_map.get_layers_count() < 3:
		tile_map.add_layer(-1)
	
	# Set dim color for memory layer (dark blue-gray, low saturation)
	tile_map.set_layer_modulate(LAYER_MEMORY, Color(0.25, 0.28, 0.35, 1.0))
	# Normal color for visible layer
	tile_map.set_layer_modulate(LAYER_VISIBLE, Color(0.95, 0.95, 0.95, 1.0))
	
	_update_lighting_for_map_type()
	
	# プレイヤーを最初の部屋の中心に配置
	if not _rooms.is_empty():
		player = get_node_or_null("Player")
		if not is_instance_valid(player):
			push_error("Player node was freed before initial placement.")
			return
		var first_room_center = _rooms[0].get_center()
		var spawn_pos = first_room_center
		
		# 中心が水なら周囲を探す
		if _map_data[spawn_pos.x][spawn_pos.y] == CellType.WATER or _map_data[spawn_pos.x][spawn_pos.y] == CellType.LAVA:
			var found = false
			# 渦巻き状に探索
			for r in range(1, 5):
				for x in range(spawn_pos.x - r, spawn_pos.x + r + 1):
					for y in range(spawn_pos.y - r, spawn_pos.y + r + 1):
						if x >= 0 and x < MAP_WIDTH and y >= 0 and y < MAP_HEIGHT:
							if _map_data[x][y] == CellType.FLOOR:
								spawn_pos = Vector2i(x, y)
								found = true
								break
					if found: break
				if found: break
		
		player.position = Vector2(spawn_pos) * TILE_SIZE
		_last_player_grid_pos = spawn_pos
		
		if player.has_method("update_on_grass"):
			player.update_on_grass(_map_data[spawn_pos.x][spawn_pos.y] == CellType.GRASS)
		
		# カメラを設定
		camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		camera.make_current()
		camera.zoom = Vector2(1.0, 1.0)
		camera.position_smoothing_speed = 5.0
	
	if current_floor == 0:
		_spawn_village_npcs()
	else:
		_spawn_enemies()
		_spawn_items()
	_spawn_torches()
	_current_game_state = TurnPhase.PLAYER_TURN
	
	if visibility_manager:
		visibility_manager.calculate_fov()
		visibility_manager.draw_map()
	
	if PlayerUi:
		PlayerUi.update_floor(current_floor)
	
	# プレイヤーのHPをUIに反映
	if PlayerUi and player:
		PlayerUi.update_hp(player.hp, player.max_hp)

	minimap_controller.setup(self)
	minimap_controller.update_minimap()





func get_random_floor_position() -> Vector2:
	for i in range(100):
		var x = randi_range(1, MAP_WIDTH - 2)
		var y = randi_range(1, MAP_HEIGHT - 2)
		var cell = _map_data[x][y]
		if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.CRYSTAL_FLOOR or cell == CellType.ICE:
			var grid_pos = Vector2i(x, y)
			
			# Check if occupied by player or other entities
			var occupied = false
			if player:
				var p_grid = tile_map.local_to_map(player.position)
				if p_grid == grid_pos:
					occupied = true
			if not occupied:
				for entity in get_tree().get_nodes_in_group("entities"):
					if is_instance_valid(entity) and not entity.is_queued_for_deletion():
						var ent_grid = tile_map.local_to_map(entity.position)
						if ent_grid == grid_pos:
							occupied = true
							break
			if not occupied:
				return Vector2(x, y) * TILE_SIZE
	return Vector2.ZERO



	

		












func _try_attack_adjacent_enemy() -> bool:
	# Cancel trade if player attacks
	if _is_trading:
		cancel_trade()
	
	var player_grid = tile_map.local_to_map(player.position)
	
	# 1. ターゲット中の敵が隣接していれば優先して攻撃
	if _current_target_enemy and is_instance_valid(_current_target_enemy):
		var target = _current_target_enemy
		var is_friendly = target.is_in_group("allies") or (target.is_in_group("npcs") and not target.is_in_group("enemies"))
		if not is_friendly:
			var target_grid = tile_map.local_to_map(target.position)
			var diff = target_grid - player_grid
			if _can_player_recognize_entity(target) and abs(diff.x) <= 1 and abs(diff.y) <= 1 and (abs(diff.x) + abs(diff.y) > 0):
				_handle_attack(player, target)
				return true

	# 2. その他の隣接する敵を攻撃
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, 
					  Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	
	for dir in directions:
		var check_pos = player_grid + dir
		
		# Check both enemies and npcs
		var targets = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("npcs")
		
		for child in targets:
			if not is_instance_valid(child) or child.is_queued_for_deletion(): continue
			if not (child is Node2D): continue
			var is_friendly = child.is_in_group("allies") or (child.is_in_group("npcs") and not child.is_in_group("enemies"))
			if is_friendly: continue
			
			var enemy_grid = tile_map.local_to_map(child.position)
			
			if enemy_grid == check_pos:
				if not _can_player_recognize_entity(child):
					continue
				# 視界内のターゲットのみ攻撃可能
				if check_pos.x >= 0 and check_pos.x < MAP_WIDTH and \
				   check_pos.y >= 0 and check_pos.y < MAP_HEIGHT and \
				   _visible_tiles[check_pos.x][check_pos.y]:
					_handle_attack(player, child)
					return true
	
	return false

func _try_target_next_enemy():
	var visible_enemies = _get_visible_enemies()
	if visible_enemies.is_empty():
		_current_target_enemy = null
		return

	if _current_target_enemy == null:
		_current_target_enemy = visible_enemies[0]
	else:
		var index = visible_enemies.find(_current_target_enemy)
		if index == -1 or index == visible_enemies.size() - 1:
			_current_target_enemy = visible_enemies[0]
		else:
			_current_target_enemy = visible_enemies[index + 1]
	
	print("Targeted: ", _current_target_enemy.name)

func _start_auto_move(direction: Vector2):
	_is_auto_moving = true
	_auto_move_direction = direction
	
	# Record current environment (walkable neighbors)
	var current_grid = tile_map.local_to_map(player.position)
	_auto_move_initial_mask = _get_walkable_mask(current_grid)
	
	_continue_auto_move()

func _get_walkable_mask(grid_pos: Vector2i) -> int:
	var mask = 0
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for i in range(dirs.size()):
		if _is_walkable(grid_pos + dirs[i]):
			mask |= (1 << i)
	return mask

func _handle_mouse_click(screen_pos: Vector2):
	var world_pos = get_global_mouse_position()
	var target_grid = tile_map.local_to_map(world_pos)
	
	if target_grid.x < 0 or target_grid.x >= MAP_WIDTH or target_grid.y < 0 or target_grid.y >= MAP_HEIGHT:
		return
	
	if not _is_walkable(target_grid):
		return
	
	var player_grid = tile_map.local_to_map(player.position)
	
	if player_grid == target_grid:
		return
	
	_setup_pathfinding()
	var path_grid = _astar_grid
	if not _is_on_world_map and player and player.can_swim:
		path_grid = _astar_grid_swim
	var path = path_grid.get_id_path(player_grid, target_grid)
	
	if path.size() > 1:
		var enemies_in_view = _get_visible_enemies()
		_enemies_at_path_start = enemies_in_view.size()
		
		# Always set full path. Safety stop is handled in _continue_path_following
		_current_path = path
		
		_path_index = 1
		_path_stop_on_new_enemy = true
		_path_continue_after_attack = false
		_is_path_following = true

func _get_visible_enemies() -> Array:
	var visible_enemies = []
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if _can_player_recognize_entity(enemy):
			visible_enemies.append(enemy)
	
	return visible_enemies

func _get_visible_entities() -> Array:
	var visible_entities = []
	var entities = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("npcs")
	
	for entity in entities:
		if _can_player_recognize_entity(entity):
			visible_entities.append(entity)
	
	return visible_entities

func _can_player_recognize_entity(entity) -> bool:
	if not visibility_manager: return false
	return visibility_manager.is_entity_visible_to_player(entity)

# 強制移動（ノックバック・投げ飛ばし）の着地時に、穴へ落下するかを処理する。
# 通常移動では既存の移動処理がプレイヤーの落下を処理するため、ここでは強制移動だけから呼び出す。
func _resolve_forced_landing(entity, landing_grid: Vector2i) -> bool:
	if not is_instance_valid(entity) or not _is_grid_in_bounds(landing_grid):
		return false
	if _map_data[landing_grid.x][landing_grid.y] != CellType.PIT:
		return false
	if "is_flying" in entity and entity.is_flying:
		return false

	if entity == player:
		var damage_amount = 10
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("落とし穴に落ちて %d のダメージを受けた！" % damage_amount, Color(0.9, 0.2, 0.2))
		if player.has_method("play_fall_sound"):
			player.play_fall_sound()
		player.take_damage(damage_amount, null, ["normal"])
		if is_instance_valid(player) and player.hp > 0:
			_change_floor(current_floor + 1, _current_branch, false, true)
	else:
		var entity_name = entity.enemy_name if "enemy_name" in entity else entity.name
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s は落とし穴に落ちた！" % entity_name, Color.ORANGE)
		entity.queue_free()

	return true

# プレイヤーのターン終了処理
func _end_player_turn():
	if _is_on_world_map:
		if _world_map_move_turn_cost_pending:
			_world_map_move_turn_cost_pending = false
			_advance_world_map_turns(WORLD_MAP_MOVE_TURN_COST)
		_current_game_state = TurnPhase.PLAYER_TURN
		return
		
	if turn_manager:
		await turn_manager.end_player_turn()
	else:
		push_error("TurnManager not initialized")

func _advance_world_map_turns(turn_cost: int) -> void:
	if not is_instance_valid(player) or not player.has_method("on_turn_end"):
		return

	for _turn in range(turn_cost):
		if not is_instance_valid(player) or player.hp <= 0:
			break
		player.on_turn_end()

func _try_spawn_periodic_enemy():
	# Skip periodic spawn in deep village (Floor 6) or overworld villages (Floor 0)
	if current_floor == 6:
		return
	if current_floor == 0:
		var world_cell = _world_map_data[_world_player_pos.x][_world_player_pos.y]
		if world_cell == WorldCell.VILLAGE:
			return
		
	var current_enemies = get_tree().get_nodes_in_group("enemies").size()
	if current_enemies >= MAX_ACTIVE_ENEMIES:
		return

	var enemy_types = EnemyDatabase.get_enemy_definitions(current_floor, _current_branch)
	if enemy_types.is_empty(): return
	
	# Try to find a valid spawn position (not visible to player)
	var spawn_pos = Vector2.ZERO
	var success = false
	var player_grid = tile_map.local_to_map(player.position)
	
	for i in range(20): # Try 20 times
		spawn_pos = get_random_floor_position()
		if spawn_pos == Vector2.ZERO: continue
		
		# Check visibility - Don't spawn in plain sight
		var grid_pos = tile_map.local_to_map(spawn_pos)
		if _visible_tiles[grid_pos.x][grid_pos.y]:
			continue
			
		# Check if position is occupied by another entity
		var occupied = false
		for entity in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(entity) and not entity.is_queued_for_deletion():
				var ent_grid = tile_map.local_to_map(entity.position)
				if ent_grid == grid_pos:
					occupied = true
					break
		if occupied:
			continue
			
		# Optional: Check distance from player (not too close)
		if Vector2(player_grid).distance_to(Vector2(grid_pos)) < 10:
			continue
			
		success = true
		break
	
	if success:
		var type = enemy_types.pick_random()
		var enemy = EnemyScene.instantiate()
		enemy.enemy_name = type.name
		enemy.enemy_id = type.get("id", type.name)
		enemy.hp = int(type.hp)
		enemy.max_hp = int(type.hp)
		enemy.attack_power = int(type.atk)
		enemy.exp_reward = type.get("exp", 2)
		if "weak" in type: enemy.weaknesses = type.weak
		if "resist" in type: enemy.resistances = type.resist
		if "fire_immune" in type: enemy.fire_immune = type.fire_immune
		if "grass_ignition_chance" in type: enemy.grass_ignition_chance = type.grass_ignition_chance
		if "color" in type: enemy.base_color = type.color
		if "can_swim" in enemy: enemy.can_swim = type.get("swim", false)
		if "knockback" in type: enemy.has_knockback = type.knockback
		if "loot" in type: enemy.loot_table = type.loot
		if "sprite" in type: enemy.sprite_path = type.sprite
		else: enemy.sprite_path = ""
		
		if "skill" in type:
			enemy.skill_id = type.skill
			enemy.attack_range = type.get("range", 1)
			enemy.max_skill_cooldown = type.get("cooldown", 5)
			enemy.skill_cooldown = randi_range(0, enemy.max_skill_cooldown)
		if "on_hit" in type: enemy.on_hit_effects = type.on_hit
		if "penetration" in type: enemy.penetration_rate = type.penetration
		if "intelligence" in type: enemy.intelligence = type.intelligence
		if "ai" in type: enemy.ai_type = type.ai

		enemy.position = spawn_pos
		
		# Assign groups based on is_npc property
		if type.get("is_npc", false):
			enemy.is_npc = true
			enemy.add_to_group("npcs")
		else:
			enemy.add_to_group("enemies")
			
		enemy.add_to_group("entities")
		add_child(enemy)
		print("Periodic Spawn: ", enemy.enemy_name, " at ", spawn_pos)

func _is_hostile(a, b) -> bool:
	if a == player and b.is_in_group("enemies"): return true
	if b == player and a.is_in_group("enemies"): return true
	if a.is_in_group("enemies") and b.is_in_group("npcs"): return true
	if a.is_in_group("npcs") and b.is_in_group("enemies"): return true
	return false

func _try_move_character(character, direction: Vector2):
	# Cancel trade if player moves
	if character == player and _is_trading:
		cancel_trade()
		
	# World map movement
	if _is_on_world_map and character == player:
		var target_grid_pos = Vector2i(player.position / TILE_SIZE) + Vector2i(direction)
		if target_grid_pos.x >= 0 and target_grid_pos.x < MAP_WIDTH and \
		   target_grid_pos.y >= 0 and target_grid_pos.y < MAP_HEIGHT:
			var cell = _world_map_data[target_grid_pos.x][target_grid_pos.y]
			if cell != WorldCell.SEA and cell != WorldCell.MOUNTAIN:
				_world_player_pos = target_grid_pos
				var is_fast = _is_auto_moving or _is_path_following or _is_auto_exploring
				player.move_to_grid(target_grid_pos, is_fast)
				_last_player_grid_pos = target_grid_pos
				_world_map_move_turn_cost_pending = true
				_draw_world_map()
				
				var cell_names = {
					WorldCell.SEA: "海",
					WorldCell.GRASS: "平原",
					WorldCell.FOREST: "森",
					WorldCell.MOUNTAIN: "山脈",
					WorldCell.VILLAGE: "村",
					WorldCell.DUNGEON: "ダンジョン",
					WorldCell.ROAD: "街道"
				}
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("%s に移動した (%d, %d)" % [cell_names.get(cell, "未知の土地"), target_grid_pos.x, target_grid_pos.y], Color(0.8, 0.8, 0.8))
				return true
		return false
	
	# Prevent moving while animating to avoid coordinate drift (Anti-Wall-Clip)
	# BUT allow auto-moving to be fast (handled by move_to_grid fast tween)
	var is_fast_move = _is_auto_moving or _is_path_following or _is_auto_exploring
	if character == player and ("is_moving" in player and player.is_moving) and not is_fast_move:
		return false

	# Manual grid calculation for consistent behavior across platforms (especially Web)
	var char_center = character.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var current_grid_pos = Vector2i(int(char_center.x / TILE_SIZE), int(char_center.y / TILE_SIZE))
	var target_grid_pos = current_grid_pos + Vector2i(direction)
	
	if target_grid_pos.x < 0 or target_grid_pos.x >= MAP_WIDTH or \
	   target_grid_pos.y < 0 or target_grid_pos.y >= MAP_HEIGHT:
		if current_floor == 0 and not _is_on_world_map and character == player:
			var exit_dir = Vector2i.ZERO
			var new_local_pos = target_grid_pos
			
			if target_grid_pos.x < 0:
				exit_dir = Vector2i.LEFT
				new_local_pos.x = MAP_WIDTH - 2
			elif target_grid_pos.x >= MAP_WIDTH:
				exit_dir = Vector2i.RIGHT
				new_local_pos.x = 1
			elif target_grid_pos.y < 0:
				exit_dir = Vector2i.UP
				new_local_pos.y = MAP_HEIGHT - 2
			elif target_grid_pos.y >= MAP_HEIGHT:
				exit_dir = Vector2i.DOWN
				new_local_pos.y = 1
				
			if exit_dir != Vector2i.ZERO:
				var target_world_pos = _world_player_pos + exit_dir
				if target_world_pos.x >= 0 and target_world_pos.x < MAP_WIDTH and \
				   target_world_pos.y >= 0 and target_world_pos.y < MAP_HEIGHT:
					var cell = _world_map_data[target_world_pos.x][target_world_pos.y]
					if cell != WorldCell.SEA and cell != WorldCell.MOUNTAIN:
						# Save and transition
						_save_current_floor_to_cache()
						_world_player_pos = target_world_pos
						var cache_key = "local_overworld_%d_%d" % [_world_player_pos.x, _world_player_pos.y]
						
						# Clear current screen entities
						for enemy in get_tree().get_nodes_in_group("enemies"):
							if is_instance_valid(enemy): enemy.queue_free()
						for npc in get_tree().get_nodes_in_group("npcs"):
							if is_instance_valid(npc): npc.queue_free()
						for item in get_tree().get_nodes_in_group("items"):
							if is_instance_valid(item): item.queue_free()
						for torch in get_tree().get_nodes_in_group("torches"):
							if is_instance_valid(torch): torch.queue_free()
							
						if not _load_floor_from_cache(cache_key, false, true):
							_generate_map(cell)
							_setup_pathfinding()
							
							if cell == WorldCell.VILLAGE:
								_spawn_village_npcs()
							else:
								_spawn_enemies()
								_spawn_items()
							_spawn_torches()
						
						# Put player at the opposite edge
						player.position = Vector2(new_local_pos) * TILE_SIZE
						_last_player_grid_pos = new_local_pos
						
						if visibility_manager:
							visibility_manager.map_data = _map_data
							visibility_manager.visible_tiles = _visible_tiles
							visibility_manager.explored_tiles = _explored_tiles
							visibility_manager.calculate_fov()
							visibility_manager.draw_map()
						else:
							_calculate_fov()
							_draw_map()
							
						camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
						camera.reset_smoothing()
						
						var cell_names = {
							WorldCell.GRASS: "平原",
							WorldCell.FOREST: "森",
							WorldCell.VILLAGE: "村",
							WorldCell.DUNGEON: "ダンジョンの入口",
							WorldCell.ROAD: "街道"
						}
						if has_node("/root/LogUI"):
							get_node("/root/LogUI").add_log("%s にシームレスに移動した。" % cell_names.get(cell, "地上"), Color(0.2, 0.9, 0.4))
						return true
					else:
						if has_node("/root/LogUI"):
							get_node("/root/LogUI").add_log("そちらは海か山で進めない！", Color(0.9, 0.2, 0.2))
		return false

	var cell_type = _map_data[target_grid_pos.x][target_grid_pos.y]
	if cell_type == CellType.TREE_FRUIT:
		if character == player:
			var item_db = load("res://items/item_database.gd")
			var item = item_db.get_item_by_id("berry")
			if item:
				var target_item = item.duplicate(true)
				var added = player.pickup_item(target_item)
				if not added:
					place_item_at_player(target_item)
			_map_data[target_grid_pos.x][target_grid_pos.y] = CellType.TREE
			_draw_map()
			return true
		else:
			var is_fly = character.is_flying if "is_flying" in character else false
			if not is_fly:
				return false
				
	if cell_type == CellType.TREE or cell_type == CellType.ROCK:
		var is_fly = character.is_flying if "is_flying" in character else false
		if not is_fly:
			return false

	if cell_type == CellType.WALL:
		return false
	if cell_type == CellType.LAVA:
		var is_fly = character.is_flying if "is_flying" in character else false
		if not is_fly:
			return false
	if cell_type == CellType.PIT:
		if character == player:
			if _is_auto_exploring or _is_path_following or _is_auto_moving:
				return false
		else:
			var is_fly = character.is_flying if "is_flying" in character else false
			if not is_fly:
				return false
	
	# ---- 扉インタラクション ----
	if cell_type == CellType.DOOR_CLOSED:
		if character == player:
			# プレイヤーは扉を開ける（1ターン消費）
			_map_data[target_grid_pos.x][target_grid_pos.y] = CellType.DOOR_OPEN
			_update_shadow_cell(target_grid_pos)
			_update_astar_tile(target_grid_pos, false) # 開けたので通行可能に
			_calculate_fov()
			_draw_map()
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("扉を開けた。", Color(0.85, 0.65, 0.30))
			if player.has_method("play_door_open_sound"):
				player.play_door_open_sound()
			return true
		else:
			# 敵は intelligence >= 1 の場合のみ扉を開けられる
			var intel = character.intelligence if "intelligence" in character else 0
			if intel >= 1:
				_map_data[target_grid_pos.x][target_grid_pos.y] = CellType.DOOR_OPEN
				_update_shadow_cell(target_grid_pos)
				_update_astar_tile(target_grid_pos, false)
				_calculate_fov()
				_draw_map()
				# 開けた後、移動は次の行で継続する（fall through）
			else:
				# 知能が低い敵は扉を通れない
				return false
	
	if cell_type == CellType.DOOR_LOCKED:
		if character == player:
			# Check if door is already jammed
			if _jammed_doors.has(target_grid_pos):
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("鍵が壊れていて解錠できない！", Color(0.9, 0.4, 0.4))
				return false
			
			# プレイヤーは鍵のかかった扉を解錠しようとする
			if player.has_method("play_lockpick_sound"):
				player.play_lockpick_sound()
				
			var dex = player.dexterity if "dexterity" in player else 10
			var success_chance = _calculate_lockpick_chance(dex)
			var roll = randi() % 100
			if roll < success_chance:
				# 解錠成功
				_map_data[target_grid_pos.x][target_grid_pos.y] = CellType.DOOR_OPEN
				_update_shadow_cell(target_grid_pos)
				_update_astar_tile(target_grid_pos, false)
				_calculate_fov()
				_draw_map()
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("鍵を解除した！", Color(0.3, 0.9, 0.3))
				if player.has_method("play_door_open_sound"):
					# Wait a tiny bit or play concurrently
					player.play_door_open_sound()
				return true
			else:
				# 解錠失敗 - chance to jam the door
				var jam_chance = 25 # 25% chance to jam on failure
				if randi() % 100 < jam_chance:
					_jammed_doors[target_grid_pos] = true
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("鍵が壊れてしまった！解錠できなくなった...", Color(0.9, 0.2, 0.2))
				else:
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("鍵の解除に失敗した...", Color(0.9, 0.4, 0.4))
				return false
		else:
			# 敵は鍵のかかった扉を開けられない
			return false
	
	# Can walk on water if character can swim OR if it is frozen (ICE)
	var is_frozen = _frozen_tiles.has(target_grid_pos) or cell_type == CellType.ICE
	if cell_type == CellType.WATER and not is_frozen:
		if _is_auto_exploring or _is_path_following or _is_auto_moving:
			return false
		elif not ("can_swim" in character and character.can_swim):
			if character == player:
				pass # Player can enter water but will drown
			else:
				return false

	for child in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not (child is Node2D):
			continue
		# Manual grid calculation
		var child_center = child.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		var child_grid = Vector2i(int(child_center.x / TILE_SIZE), int(child_center.y / TILE_SIZE))
		if child != character and child_grid == target_grid_pos:
			if child.is_in_group("items"):
				# Allow walking over items for now
				continue
				
			if _is_hostile(character, child):
				await _handle_attack(character, child)
				return true
			elif character == player and (child.is_in_group("npcs") or child.is_in_group("allies")):
				# Swap positions with friendly actors.
				var npc = child
				var npc_name = "NPC"
				if "enemy_name" in npc: npc_name = npc.enemy_name
				
				var player_old_pos = player.position
				var npc_old_pos = npc.position
				_last_player_grid_pos = current_grid_pos
				
				# Animate swap
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(player, "position", npc_old_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(npc, "position", player_old_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				await tween.finished
				
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("%s と入れ替わった" % npc_name, Color(0.8, 1.0, 0.8))
				
				# Update FOV after swap
				_calculate_fov()
				_draw_map()
				if visibility_manager:
					visibility_manager.update_single_entity_visibility(npc)
				return true
			else:
				return false

	if character.has_method("move_to_grid"):
		var is_fast = (_is_auto_moving or _is_path_following or _is_auto_exploring) if character == player else false
		if character == player:
			_last_player_grid_pos = current_grid_pos
		character.move_to_grid(target_grid_pos, is_fast)
	else:
		if character == player:
			_last_player_grid_pos = current_grid_pos
		character.move(direction)
	
	var new_cell_type = _map_data[target_grid_pos.x][target_grid_pos.y]
	if character != player and "grass_ignition_chance" in character and character.grass_ignition_chance > 0.0:
		_try_enemy_grass_ignition(character, target_grid_pos)
		
	if character != player and new_cell_type == CellType.WATER and "enemy_name" in character and character.enemy_name == "スパークスライム":
		_electrify_water(target_grid_pos)
	
	if character == player and player.has_method("update_terrain_info"):
		var is_grass = new_cell_type == CellType.GRASS
		var is_water = new_cell_type == CellType.WATER
		player.update_terrain_info(is_grass, is_water)
	
	# Cure burn if moving into water
	if new_cell_type == CellType.WATER and character.has_method("remove_effect"):
		character.remove_effect("burn")
		
	if character == player:
		# Check for items at new position
		for child in get_tree().get_nodes_in_group("items"):
			if not is_instance_valid(child) or child.is_queued_for_deletion():
				continue
			if not (child is Node2D):
				continue
			var item_center = child.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var child_grid_pos = Vector2i(int(item_center.x / TILE_SIZE), int(item_center.y / TILE_SIZE))
			if child_grid_pos == target_grid_pos:
				# Attempt to pick up
				if player.pickup_item(child.item_data):
					child.queue_free()
				break
				
		if new_cell_type == CellType.PIT:
			var damage_amount = 10
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("落とし穴に落ちて %d のダメージを受けた！" % damage_amount, Color(0.9, 0.2, 0.2))
			if player.has_method("play_fall_sound"):
				player.play_fall_sound()
			player.take_damage(damage_amount, null, ["normal"])
			
			if is_instance_valid(player) and player.hp > 0:
				_change_floor(current_floor + 1, _current_branch, false, true)

		_calculate_fov()
		_draw_map()
	
	# Swimmer Speed Bonus: If Swimmer class (4) + swimming item + on water, grant bonus action
	if character == player:
		if new_cell_type == CellType.WATER:
			var gs = get_node_or_null("/root/GameState")
			# Class 4 = Swimmer
			# Check water_step_cooldown to prevent infinite turns
			if gs and gs.player_class == 4 and player.is_using_swim_gear():
				if not _swimmer_cooldown:
					# Grant bonus action
					player.bonus_action_available = true
					if has_node("/root/LogUI"):
						pass # Log handled in _end_turn
				else:
					pass # Cooldown active
	
	return true

func _process(delta):
	# Tooltip Logic
	_update_tooltip()

	if _auto_move_cooldown > 0.0:
		_auto_move_cooldown -= delta

	if PlayerUi and player:
		PlayerUi.update_hp(player.hp, player.max_hp)
		PlayerUi.update_level(player.level)
		PlayerUi.update_gold(player.gold)
		PlayerUi.update_exp(player.exp, player.exp_to_next_level)
		PlayerUi.update_hunger(player.hunger, player.max_hunger)
		PlayerUi.update_turns(player.turn_counter)
	
	if _is_auto_moving and _current_game_state == TurnPhase.PLAYER_TURN:
		_continue_auto_move()
	
	if _is_path_following and _current_game_state == TurnPhase.PLAYER_TURN:
		_continue_path_following()

	if _is_auto_exploring and _current_game_state == TurnPhase.PLAYER_TURN:
		_continue_auto_explore()
	
	if _is_resting and _current_game_state == TurnPhase.PLAYER_TURN:
		_continue_rest()

func _update_tooltip():
	if not GameUI: return
	
	var grid_pos: Vector2i
	if target_manager and target_manager.targeting_look:
		grid_pos = target_manager.keyboard_target_grid
		
		# Set GameUI tooltip position override
		var global_pos = target_manager.get_target_pos_global()
		var screen_pos = get_global_transform_with_canvas() * global_pos
		GameUI.tooltip_override_position = screen_pos
	else:
		if GameUI.is_visible or GameUI.is_skill_visible:
			GameUI.hide_tooltip()
			return
		var mouse_pos = get_global_mouse_position()
		grid_pos = tile_map.local_to_map(mouse_pos)
		GameUI.tooltip_override_position = null

	# Check if tile matches any entity
	# Only if visible or explored? Typically only if visible in FOV.
	
	# Note: vector equality search in arrays can be slow if many entities,
	# but for < 100 entities it's fine.
	
	var tooltip_text = ""
	
	# Check Enemies, Allies, NPCs (avoiding duplicates)
	var targets = []
	for g in ["enemies", "allies", "npcs"]:
		for node in get_tree().get_nodes_in_group(g):
			if is_instance_valid(node) and not targets.has(node):
				targets.append(node)
				
	for child in targets:
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not (child is Node2D):
			continue
		if not _can_player_recognize_entity(child): continue
		var ent_grid = tile_map.local_to_map(child.position)
		if ent_grid == grid_pos:
			var name_str = child.name
			if "enemy_name" in child: name_str = child.enemy_name
			
			var hp_str = ""
			if "hp" in child and "max_hp" in child: # If max hp known
				hp_str = "HP: %d/%d" % [child.hp, child.max_hp]
			elif "hp" in child:
				hp_str = "HP: %d" % child.hp
				
			var status = ""
			if child.has_method("is_paralyzed") and child.is_paralyzed():
				status = " [麻痺]"
				
			var weak_str = ""
			var resist_str = ""
			if "weaknesses" in child and child.weaknesses.size() > 0:
				weak_str = "\n弱点: " + ", ".join(child.weaknesses)
			if "resistances" in child and child.resistances.size() > 0:
				resist_str = "\n耐性: " + ", ".join(child.resistances)

			var npc_debug_str = ""
			var is_npc_character = child.is_in_group("npcs") \
				or child.is_in_group("allies") \
				or ("is_hostile_to_player_only" in child and child.is_hostile_to_player_only)
			if input_handler and input_handler.debug_mode and is_npc_character:
				npc_debug_str = "\n[DEBUG] 好感度: %d / 恐怖: %d" % [
					child.affection if "affection" in child else 0,
					child.fear if "fear" in child else 0
				]
			
			tooltip_text = "%s\n%s%s%s%s%s" % [name_str, hp_str, status, weak_str, resist_str, npc_debug_str]
			# 日本語表記に変換
			var t_dict = {"fire":"炎", "ice":"氷", "electric":"雷", "water":"水", "blunt":"打撃", "pierce":"刺突", "magic":"魔法"}
			for en_key in t_dict.keys():
				tooltip_text = tooltip_text.replace(en_key, t_dict[en_key])
			break
	
	# Check Items if no enemy found
	if tooltip_text == "":
		for child in get_tree().get_nodes_in_group("items"):
			if not is_instance_valid(child) or child.is_queued_for_deletion():
				continue
			if not (child is Node2D):
				continue
			# visible check? Items might be visible if in memory?
			# Usually we assume items are visible if rendered.
			if not child.visible: continue
			
			var item_grid = tile_map.local_to_map(child.position)
			if item_grid == grid_pos:
				if "item_data" in child:
					tooltip_text = child.item_data.name
					break

	# Check stairs if no entity or item found
	if tooltip_text == "" and _is_grid_in_bounds(grid_pos):
		if _explored_tiles[grid_pos.x][grid_pos.y]:
			var cell_type = _map_data[grid_pos.x][grid_pos.y]
			if _is_stairs_cell(cell_type):
				tooltip_text = _get_stairs_tooltip(cell_type)
	
	if tooltip_text != "":
		GameUI.show_tooltip(tooltip_text)
	else:
		GameUI.hide_tooltip()

func _continue_auto_move():
	if _auto_move_cooldown > 0.0: return
	if _is_processing_action: return

	# Wait for animation to finish before moving input
	if player and ("is_moving" in player and player.is_moving):
		return
		
	_is_processing_action = true

	# Stop if enemies are visible
	var enemies_in_view = _get_visible_enemies()
	if enemies_in_view.size() > 0:
		_is_auto_moving = false
		_is_processing_action = false
		print("Auto-move stopped: Enemy in sight")
		return

	# 2. Check if the NEXT tile has a different environment
	var current_grid = tile_map.local_to_map(player.position)
	var next_grid = current_grid + Vector2i(_auto_move_direction)
	
	if _is_walkable(next_grid):
		# 1. Terrain Type Change Check (Water edge, etc.)
		var current_cell_type = _map_data[current_grid.x][current_grid.y]
		var next_cell_type = _map_data[next_grid.x][next_grid.y]
		
		if current_cell_type != next_cell_type:
			_is_auto_moving = false
			_is_processing_action = false
			print("Auto-move stopped: Terrain changed")
			return

		# 2. Walkable Mask Check (Restore past condition: Corners, Intersections)
		var next_mask = _get_walkable_mask(next_grid)
		if next_mask != _auto_move_initial_mask:
			_is_auto_moving = false
			_is_processing_action = false
			print("Auto-move stopped: Environment changed (Mask)")
			return

	var moved = await _try_move_character(player, _auto_move_direction)
	if not moved:
		_is_auto_moving = false
		_is_processing_action = false
		print("Auto-move stopped: Blocked")
		return
	
	# 3. Stop if we stepped on something interesting
	var new_grid = tile_map.local_to_map(player.position)
	var cell = _map_data[new_grid.x][new_grid.y]
	if _is_stairs_cell(cell):
		_is_auto_moving = false
		_is_processing_action = false
		print("Auto-move stopped: Reached stairs")
		return
		
	# Check for items at new position
	for child in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not (child is Node2D):
			continue
		if tile_map.local_to_map(child.position) == new_grid:
			_is_auto_moving = false
			_is_processing_action = false
			print("Auto-move stopped: Found item")
			break

	await _end_player_turn()
	_auto_move_cooldown = AUTO_MOVE_DELAY
	_is_processing_action = false



func _is_walkable(grid_pos: Vector2i) -> bool:
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT:
		return false
	if _is_on_world_map:
		var cell = _world_map_data[grid_pos.x][grid_pos.y]
		return cell != WorldCell.SEA and cell != WorldCell.MOUNTAIN
		
	var cell = _map_data[grid_pos.x][grid_pos.y]
	# DOOR_CLOSED is now walkable for auto-move (will be opened automatically)
	# DOOR_LOCKED is not walkable (requires lock picking)
	# ICE is walkable (frozen water)
	if cell == CellType.WALL or cell == CellType.DOOR_LOCKED or cell == CellType.LAVA or cell == CellType.PIT:
		return false
	if cell == CellType.WATER and not _frozen_tiles.has(grid_pos):
		return false
	return true

func _calculate_lockpick_chance(dex: int) -> int:
	# Calculate lockpick success chance based on DEX
	# Base chance: 20%
	# Each point of DEX above 10 adds 5%
	# Each point of DEX below 10 subtracts 5%
	# Cap between 5% and 95%
	var base_chance = 20
	var dex_modifier = (dex - 10) * 5
	var chance = base_chance + dex_modifier
	return clamp(chance, 5, 95)

func _continue_path_following():
	if _auto_move_cooldown > 0.0: return
	if _is_processing_action: return
	
	if player and ("is_moving" in player and player.is_moving):
		return
	
	if _path_index >= _current_path.size():
		_is_path_following = false
		_current_path.clear()
		_path_continue_after_attack = false
		return

	_is_processing_action = true

	# Stop if new enemies are visible compared to start of path
	var enemies_in_view = _get_visible_enemies()
	# Filter out invisible enemies (just in case _get_visible_enemies doesn't check .visible property?)
	# Whatever _get_visible_enemies returns should be trusted if implemented correctly.
	if _path_stop_on_new_enemy and enemies_in_view.size() > _enemies_at_path_start:
		_is_path_following = false
		_current_path.clear()
		_path_continue_after_attack = false
		_is_processing_action = false
		print("Path following stopped: New enemy in sight")
		return

	var current_grid = tile_map.local_to_map(player.position)
	
	# Advance path index if we've reached the current waypoint
	while _path_index < _current_path.size() and current_grid == Vector2i(_current_path[_path_index]):
		_path_index += 1
		
	if _path_index >= _current_path.size():
		_is_path_following = false
		_current_path.clear()
		_path_continue_after_attack = false
		_is_processing_action = false
		return

	var next_grid = Vector2i(_current_path[_path_index])
	var diff = next_grid - current_grid
	
	# If the AStar path has a gap or we drifted out of sync, immediately rebuild to avoid wall clipping
	if abs(diff.x) > 1 or abs(diff.y) > 1:
		var goal_grid = Vector2i(_current_path[_current_path.size() - 1])
		var path_grid = _astar_grid
		if not _is_on_world_map and player and player.can_swim:
			path_grid = _astar_grid_swim
		var rebuilt: Array = Array(path_grid.get_id_path(current_grid, goal_grid))
		if rebuilt.size() > 1:
			_current_path = rebuilt
			_path_index = 1
			next_grid = Vector2i(_current_path[_path_index])
			diff = next_grid - current_grid
		else:
			_is_path_following = false
			_current_path.clear()
			_path_continue_after_attack = false
			_is_processing_action = false
			print("Path following stopped: Invalid gap")
			return
			
	var direction = Vector2(diff)
	
	var hp_before = player.hp if player else 0
	
	# Try move
	var moved = await _try_move_character(player, direction)
	var end_grid = tile_map.local_to_map(player.position)
	
	if moved:
		# If we attacked or swapped, `start_grid` == `end_grid` might be true (if no movement happened but action taken)
		# Or if we moved, `end_grid` != `current_grid`.
		# Waypoint advancement is handled naturally at the beginning of the next cycle.
		if current_grid == end_grid and not _path_continue_after_attack:
			# Acted but didn't move, and we shouldn't continue
			_is_path_following = false
			_current_path.clear()
			_path_continue_after_attack = false
			print("Path following stopped: Attacked")
			
		await _end_player_turn()
		if player and player.hp < hp_before:
			_is_path_following = false
			_current_path.clear()
			_path_continue_after_attack = false
			_is_processing_action = false
			var log_ui = get_tree().root.get_node_or_null("LogUI")
			if log_ui and log_ui.has_method("add_log"):
				log_ui.add_log("ダメージを受けたため自動移動を停止しました。", Color(1.0, 0.8, 0.4))
			return
	else:
		# Blocked - recalculate path if we're doing a long distance auto movement
		var path_grid = _astar_grid
		if not _is_on_world_map and player and player.can_swim:
			path_grid = _astar_grid_swim
		var goal_grid = Vector2i(_current_path[_current_path.size() - 1])
		
		var rebuilt: Array = Array(path_grid.get_id_path(current_grid, goal_grid))
		if rebuilt.size() > 1 and Vector2i(rebuilt[1]) != current_grid + Vector2i(direction):
			# Found an alternative route to avoid dynamic obstacle
			_current_path = rebuilt
			_path_index = 1 # Start towards new first step
			await _end_player_turn() # Costs a turn to recalculate / wait
			if player and player.hp < hp_before:
				_is_path_following = false
				_current_path.clear()
				_path_continue_after_attack = false
				_is_processing_action = false
				var log_ui = get_tree().root.get_node_or_null("LogUI")
				if log_ui and log_ui.has_method("add_log"):
					log_ui.add_log("ダメージを受けたため自動移動を停止しました。", Color(1.0, 0.8, 0.4))
				return
		else:
			_is_path_following = false
			_current_path.clear()
			_path_continue_after_attack = false
			print("Path following stopped: Blocked permanently")
	
	_auto_move_cooldown = AUTO_MOVE_DELAY
	_is_processing_action = false

func _start_auto_explore():
	if _current_game_state != TurnPhase.PLAYER_TURN:
		return
	if _is_processing_action:
		return

	# Keep only one auto-action mode active at a time.
	_is_auto_moving = false
	_is_path_following = false
	_current_path.clear()
	_path_continue_after_attack = false
	_is_resting = false

	var enemies_in_view = _get_visible_enemies()
	if enemies_in_view.size() > 0:
		var log_ui0 = get_tree().root.get_node_or_null("LogUI")
		if log_ui0 and log_ui0.has_method("add_log"):
			log_ui0.add_log("敵が見えているため自動探索を開始できません。", Color(1.0, 0.6, 0.3))
		return

	var start_grid = tile_map.local_to_map(player.position)
	_auto_explore_path = _find_auto_explore_target_path(start_grid)
	if _auto_explore_path.size() <= 1:
		var log_ui1 = get_tree().root.get_node_or_null("LogUI")
		if log_ui1 and log_ui1.has_method("add_log"):
			log_ui1.add_log("探索可能な未探索エリアが見つかりません。", Color(0.8, 0.8, 0.8))
		return

	_auto_explore_index = 1
	_is_auto_exploring = true
	var log_ui2 = get_tree().root.get_node_or_null("LogUI")
	if log_ui2 and log_ui2.has_method("add_log"):
		log_ui2.add_log("自動探索を開始します。", Color(0.7, 0.9, 1.0))

	_continue_auto_explore()

func _stop_auto_explore(reason: String = ""):
	var was_running = _is_auto_exploring
	_is_auto_exploring = false
	_auto_explore_path.clear()
	_auto_explore_index = 0
	if was_running and reason != "":
		var log_ui = get_tree().root.get_node_or_null("LogUI")
		if log_ui and log_ui.has_method("add_log"):
			log_ui.add_log(reason, Color(1.0, 0.8, 0.4))

func _continue_auto_explore():
	if not _is_auto_exploring:
		return
	if _auto_move_cooldown > 0.0:
		return
	if _current_game_state != TurnPhase.PLAYER_TURN:
		return
	if _is_processing_action:
		return
	if player and ("is_moving" in player and player.is_moving):
		return

	_is_processing_action = true

	var enemies_in_view = _get_visible_enemies()
	if enemies_in_view.size() > 0:
		_stop_auto_explore("敵を発見したため自動探索を停止しました。")
		_is_processing_action = false
		return

	var current_grid = tile_map.local_to_map(player.position)

	# Rebuild path when exhausted or when position got out-of-sync.
	var need_repath = _auto_explore_path.is_empty() or _auto_explore_index >= _auto_explore_path.size()
	if not need_repath and _auto_explore_index > 0:
		var expected_grid = Vector2i(_auto_explore_path[_auto_explore_index - 1])
		need_repath = expected_grid != current_grid

	if need_repath:
		_auto_explore_path = _find_auto_explore_target_path(current_grid)
		if _auto_explore_path.size() <= 1:
			_stop_auto_explore("未探索エリアの探索を完了しました。")
			_is_processing_action = false
			return
		_auto_explore_index = 1

	var next_grid = Vector2i(_auto_explore_path[_auto_explore_index])
	var direction = Vector2(next_grid - current_grid)
	var hp_before = player.hp

	var moved = await _try_move_character(player, direction)
	if not moved:
		# Dynamic obstacle (entity) etc. Retry from current position next frame.
		_auto_explore_path = _find_auto_explore_target_path(current_grid)
		_auto_explore_index = 1
		if _auto_explore_path.size() <= 1:
			_stop_auto_explore("未探索エリアへの経路が見つからないため停止しました。")
		_auto_move_cooldown = AUTO_MOVE_DELAY
		_is_processing_action = false
		return

	var start_grid = current_grid
	var end_grid = tile_map.local_to_map(player.position)
	var attacked_in_place = start_grid == end_grid
	if not attacked_in_place:
		_auto_explore_index += 1

	await _end_player_turn()

	if player.hp < hp_before:
		_stop_auto_explore("ダメージを受けたため自動探索を停止しました。")
	elif attacked_in_place:
		_stop_auto_explore("会敵したため自動探索を停止しました。")
	elif _get_visible_enemies_check().size() > 0:
		_stop_auto_explore("敵を発見したため自動探索を停止しました。")

	_auto_move_cooldown = AUTO_MOVE_DELAY
	_is_processing_action = false

func _is_auto_explore_walkable(grid_pos: Vector2i) -> bool:
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT:
		return false
	var cell = _map_data[grid_pos.x][grid_pos.y]
	if cell == CellType.WALL or cell == CellType.DOOR_LOCKED or cell == CellType.LAVA or cell == CellType.PIT or cell == CellType.TREE or cell == CellType.TREE_FRUIT or cell == CellType.ROCK:
		return false
	# DOOR_CLOSED is now walkable for auto-explore (will be opened automatically)
	# ICE is walkable (frozen water)
	# WATER is walkable only if frozen (never walk in unfrozen water during auto-explore even if player can swim)
	if cell == CellType.WATER and not _frozen_tiles.has(grid_pos):
		return false

	# Avoid burning tiles for auto-explore if the player is not fire immune
	if _burning_grass.has(grid_pos):
		if not _is_fire_immune(player):
			return false

	return true

func _find_auto_explore_target_path(start_grid: Vector2i) -> Array:
	var item_path = _find_path_to_nearest_visible_item(start_grid)
	if item_path.size() > 1:
		return item_path
	return _find_path_to_nearest_unexplored(start_grid)

func _find_path_to_nearest_visible_item(start_grid: Vector2i) -> Array:
	if not _is_auto_explore_walkable(start_grid):
		return []
	var best_path: Array = []
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			continue
		if not (item is Node2D):
			continue
		if not item.visible:
			continue
		var item_grid = tile_map.local_to_map(item.position)
		if not _is_auto_explore_walkable(item_grid):
			continue
		var path: Array = Array(_astar_grid.get_id_path(start_grid, item_grid))
		if path.size() <= 1:
			continue
		if best_path.is_empty() or path.size() < best_path.size():
			best_path = path
	return best_path

func _is_stairs_cell(cell_type: int) -> bool:
	return cell_type == CellType.STAIRS or cell_type == CellType.STAIRS_BLUE or cell_type == CellType.STAIRS_GREEN or cell_type == CellType.STAIRS_RED or cell_type == CellType.STAIRS_PURPLE or cell_type == CellType.STAIRS_GOLD

func _is_grid_in_bounds(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < MAP_WIDTH and grid_pos.y >= 0 and grid_pos.y < MAP_HEIGHT

func _get_stairs_tooltip(cell_type: int) -> String:
	match cell_type:
		CellType.STAIRS:
			return "通常の階段\n次の通常階層へ降ります。"
		CellType.STAIRS_BLUE:
			return "青い階段 - 水域\n水場が多い分岐へ降ります。\n水棲の敵が出やすい階層です。"
		CellType.STAIRS_GREEN:
			return "緑の階段 - 草地\n草や森が多い分岐へ降ります。\n炎に弱い敵や草地の戦闘が増えます。"
		CellType.STAIRS_RED:
			return "赤い階段 - 火山\n溶岩と灰の分岐へ降ります。\n火属性の危険が高い階層です。"
		CellType.STAIRS_PURPLE:
			return "紫の階段 - 結晶洞\n結晶床が広がる分岐へ降ります。\n魔法や硬い敵に注意が必要です。"
		CellType.STAIRS_GOLD:
			return "金色の階段\n始まりのダンジョンへ降ります。"
	return "階段\n次の階層へ降ります。"

func _find_path_to_nearest_stairs(start_grid: Vector2i) -> Array:
	if start_grid.x < 0 or start_grid.x >= MAP_WIDTH or start_grid.y < 0 or start_grid.y >= MAP_HEIGHT:
		return []

	var can_swim = player and player.can_swim
	
	var dirs = [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	
	var queue: Array = [start_grid]
	var visited := {}
	var came_from := {}
	visited[start_grid] = true

	var target_stairs = null

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if _is_stairs_cell(_map_data[current.x][current.y]):
			target_stairs = current
			break

		for dir in dirs:
			var nxt = current + dir
			if visited.has(nxt):
				continue
				
			if nxt.x < 0 or nxt.x >= MAP_WIDTH or nxt.y < 0 or nxt.y >= MAP_HEIGHT:
				continue
				
			if not _explored_tiles[nxt.x][nxt.y]:
				continue
				
			var cell = _map_data[nxt.x][nxt.y]
			# E-key Auto-move pathfinder should never route through water tiles (even if the player has can_swim)
			# DOOR_OPEN is treated as floor. DOOR_CLOSED is now walkable (will be opened automatically).
			# DOOR_LOCKED is not walkable (requires lock picking).
			# ICE is walkable (frozen water).
			var is_walkable = (cell == CellType.FLOOR or cell == CellType.STAIRS or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.CRYSTAL_FLOOR or cell == CellType.STAIRS_BLUE or cell == CellType.STAIRS_GREEN or cell == CellType.STAIRS_RED or cell == CellType.STAIRS_PURPLE or cell == CellType.STAIRS_GOLD or cell == CellType.DOOR_OPEN or cell == CellType.DOOR_CLOSED or cell == CellType.ICE or _frozen_tiles.has(nxt))
			
			if not is_walkable:
				continue

			# Diagonal check (prevent clipping corners of walls)
			if abs(dir.x) == 1 and abs(dir.y) == 1:
				var neighbor_x = _map_data[current.x + dir.x][current.y]
				var neighbor_y = _map_data[current.x][current.y + dir.y]
				if neighbor_x == CellType.WALL or neighbor_y == CellType.WALL:
					continue

			visited[nxt] = true
			came_from[nxt] = current
			queue.push_back(nxt)

	if target_stairs != null:
		return _reconstruct_grid_path(came_from, start_grid, target_stairs)

	return []

func _count_explored_tiles() -> int:
	var count = 0
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _explored_tiles[x][y]:
				count += 1
	return count

func _start_auto_move_to_stairs():
	if _current_game_state != TurnPhase.PLAYER_TURN:
		return
	if _is_processing_action:
		return

	# Keep only one auto-action mode active at a time.
	_is_auto_moving = false
	_is_path_following = false
	_current_path.clear()
	_path_continue_after_attack = false
	_is_resting = false
	_stop_auto_explore()

	var enemies_in_view = _get_visible_enemies()
	if enemies_in_view.size() > 0:
		var log_ui0 = get_tree().root.get_node_or_null("LogUI")
		if log_ui0 and log_ui0.has_method("add_log"):
			log_ui0.add_log("Enemy in sight. Auto move to stairs canceled.", Color(1.0, 0.6, 0.3))
		return

	var start_grid = tile_map.local_to_map(player.position)
	if _is_stairs_cell(_map_data[start_grid.x][start_grid.y]):
		var log_ui1 = get_tree().root.get_node_or_null("LogUI")
		if log_ui1 and log_ui1.has_method("add_log"):
			log_ui1.add_log("Already on stairs.", Color(0.8, 0.8, 0.8))
		return

	# 経路計算前にパスファインディンググリッドを更新（凍結タイルなどの変更を反映）
	_setup_pathfinding()
	
	var path = _find_path_to_nearest_stairs(start_grid)
	if path.size() <= 1:
		var log_ui2 = get_tree().root.get_node_or_null("LogUI")
		if log_ui2 and log_ui2.has_method("add_log"):
			log_ui2.add_log("No reachable mapped normal stairs found.", Color(0.8, 0.8, 0.8))
		return

	_enemies_at_path_start = 0
	_current_path = path
	_path_index = 1
	_path_stop_on_new_enemy = true
	_path_continue_after_attack = false
	_is_path_following = true
	
	# 経路の詳細をログ出力（デバッグ用）
	print("Path to stairs calculated: ")
	for i in range(min(path.size(), 10)):
		print("  [", i, "] ", path[i])
	if path.size() > 10:
		print("  ... and ", path.size() - 10, " more points")

	var log_ui3 = get_tree().root.get_node_or_null("LogUI")
	if log_ui3 and log_ui3.has_method("add_log"):
		log_ui3.add_log("Auto moving to stairs... (path length: %d)" % path.size(), Color(0.7, 0.9, 1.0))

func _find_path_to_nearest_unexplored(start_grid: Vector2i) -> Array:
	if not _is_auto_explore_walkable(start_grid):
		return []

	var dirs = [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	var queue: Array = [start_grid]
	var visited := {}
	var came_from := {}
	visited[start_grid] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()

		if current != start_grid and not _explored_tiles[current.x][current.y]:
			return _reconstruct_grid_path(came_from, start_grid, current)

		for dir in dirs:
			var nxt = current + dir
			if visited.has(nxt):
				continue
			if not _is_auto_explore_walkable(nxt):
				continue
			visited[nxt] = true
			came_from[nxt] = current
			queue.push_back(nxt)

	return []

func _reconstruct_grid_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var path: Array = [goal]
	var cur = goal
	while cur != start:
		if not came_from.has(cur):
			return []
		cur = came_from[cur]
		path.push_front(cur)
	return path

func _start_rest():
	# Start resting only if currently player's turn
	if _current_game_state != TurnPhase.PLAYER_TURN:
		return
	
	# Do not start if enemies are already visible
	var enemies_in_view = _get_visible_enemies_check()
	if enemies_in_view.size() > 0:
		var log_ui = get_tree().root.get_node_or_null("LogUI")
		if log_ui and log_ui.has_method("add_log"):
			log_ui.add_log("敵が近くにいるので休憩できない…", Color(1.0, 0.6, 0.3))
		return
	
	_is_resting = true
	# Remember which resources we want to recover
	_rest_target_hp = player and player.hp < player.max_hp
	_rest_target_mp = player and player.mp < player.max_mp
	var log_ui2 = get_tree().root.get_node_or_null("LogUI")
	if log_ui2 and log_ui2.has_method("add_log"):
		log_ui2.add_log("休憩を開始した…", Color(0.8, 0.9, 1.0))
	
	_continue_rest()

func _continue_rest():
	if not _is_resting:
		return
	if _current_game_state != TurnPhase.PLAYER_TURN:
		return
	if _is_processing_action: return
	
	_is_processing_action = true
	
	# Stop if enemies become visible
	var enemies_in_view = _get_visible_enemies_check()
	if enemies_in_view.size() > 0:
		_is_resting = false
		_is_processing_action = false
		var log_ui = get_tree().root.get_node_or_null("LogUI")
		if log_ui and log_ui.has_method("add_log"):
			log_ui.add_log("敵の気配を感じて休憩をやめた。", Color(1.0, 0.6, 0.3))
		return
	
	# Stop based on what we intended to recover at start
	if player:
		var hp_full = player.hp >= player.max_hp
		var mp_full = player.mp >= player.max_mp
		var should_stop = false
		# 両方減っていた場合: どちらかが満タンになったら停止
		if _rest_target_hp and _rest_target_mp:
			should_stop = hp_full or mp_full
		# 片方だけ減っていた場合: その片方が満タンになるまで続ける
		elif _rest_target_hp:
			should_stop = hp_full
		elif _rest_target_mp:
			should_stop = mp_full
		if should_stop:
			_is_resting = false
			_is_processing_action = false
			var log_ui2 = get_tree().root.get_node_or_null("LogUI")
			if log_ui2 and log_ui2.has_method("add_log"):
				log_ui2.add_log("十分に休憩した。", Color(0.7, 1.0, 0.7))
			return
	
	# Stop if hunger is getting dangerous (残り10%以下)
	if player and player.max_hunger > 0:
		var hunger_ratio = float(player.hunger) / float(player.max_hunger)
		if hunger_ratio <= 0.1:
			_is_resting = false
			_is_processing_action = false
			var log_ui3 = get_tree().root.get_node_or_null("LogUI")
			if log_ui3 and log_ui3.has_method("add_log"):
				log_ui3.add_log("お腹が減ってきたので休憩をやめた。", Color(1.0, 0.8, 0.4))
			return
	
	var hp_before = player.hp if player else 0
	
	# Consume one turn as a wait action
	var log_ui4 = get_tree().root.get_node_or_null("LogUI")
	if log_ui4 and log_ui4.has_method("add_log"):
		log_ui4.add_log("休憩中…", Color(0.6, 0.8, 1.0))
	await _end_player_turn()
	
	if player and player.hp < hp_before:
		_is_resting = false
		_is_processing_action = false
		var log_ui = get_tree().root.get_node_or_null("LogUI")
		if log_ui and log_ui.has_method("add_log"):
			log_ui.add_log("ダメージを受けたため休憩をやめた。", Color(1.0, 0.8, 0.4))
		return
		
	_is_processing_action = false

func _handle_attack(attacker, defender):
	if combat_manager:
		await combat_manager.handle_attack(attacker, defender)
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("Error: CombatManager not initialized", Color.RED)
		
	# Spark Slime Water Electrification on attack
	if is_instance_valid(attacker) and "enemy_name" in attacker and attacker.enemy_name == "スパークスライム":
		var att_grid = tile_map.local_to_map(attacker.position)
		if _map_data[att_grid.x][att_grid.y] == CellType.WATER:
			_electrify_water(att_grid)

func _spawn_enemies():
	# Village Floor handling
	if current_floor == 6:
		_spawn_village_npcs()
		return
		
	# 敵のバランス調整
	var enemy_types = EnemyDatabase.get_enemy_definitions(current_floor, _current_branch)
	
	# Scale stats by floor - DISABLED per user request
	var stat_multiplier = 1.0 # + (current_floor * 0.1)

	for i in range(1, _rooms.size()):
		var room = _rooms[i]
		var max_enemies = MAX_ENEMIES_PER_ROOM
		if _current_branch == 10:
			max_enemies = 1
			
		var enemy_count = randi_range(1, max_enemies)
		
		for j in range(enemy_count):
			var attempts = 10
			while attempts > 0:
				var x = randi_range(room.position.x, room.position.x + room.size.x - 1)
				var y = randi_range(room.position.y, room.position.y + room.size.y - 1)
				if _map_data[x][y] == CellType.FLOOR:
					var enemy = EnemyScene.instantiate()
					
					# Randomize Type
					var type = enemy_types.pick_random()
					enemy.enemy_name = type.name
					enemy.enemy_id = type.get("id", type.name) # Important for saving/loading!
					
					var hp_val = int(type.hp)
					var atk_val = int(type.atk)
					if _current_branch == 10:
						hp_val = maxi(1, int(hp_val * 0.7))
						atk_val = maxi(1, int(atk_val * 0.7))
						
					enemy.hp = hp_val
					enemy.max_hp = hp_val
					enemy.attack_power = atk_val
					enemy.exp_reward = type.get("exp", 2)
					if "weak" in type: enemy.weaknesses = type.weak
					if "resist" in type: enemy.resistances = type.resist
					if "fire_immune" in type: enemy.fire_immune = type.fire_immune
					if "grass_ignition_chance" in type: enemy.grass_ignition_chance = type.grass_ignition_chance
					if "color" in type:
						enemy.base_color = type.color
					if "can_swim" in enemy:
						enemy.can_swim = type.swim
					if "is_flying" in enemy:
						enemy.is_flying = type.get("fly", false)
					
					if "knockback" in type:
						enemy.has_knockback = type.knockback

					if "loot" in type:
						enemy.loot_table = type.loot

					if "sprite" in type:
						enemy.sprite_path = type.sprite
					else:
						enemy.sprite_path = "" # Force fallback sprite generation
						
					if "skill" in type:
						enemy.skill_id = type.skill
						enemy.attack_range = type.get("range", 1)
						enemy.max_skill_cooldown = type.get("cooldown", 5)
						enemy.skill_cooldown = randi_range(0, enemy.max_skill_cooldown)

					if "on_hit" in type:
						enemy.on_hit_effects = type.on_hit

					if "penetration" in type:
						enemy.penetration_rate = type.penetration

					if "intelligence" in type:
						enemy.intelligence = type.intelligence
					if "ai" in type:
						enemy.ai_type = type.ai
					
					enemy.position = Vector2(x, y) * TILE_SIZE
					
					# Assign groups based on is_npc property
					if type.get("is_npc", false):
						enemy.is_npc = true
						enemy.add_to_group("npcs")
					else:
						enemy.add_to_group("enemies")
						
					enemy.add_to_group("entities")
					add_child(enemy)
					enemy.visible = false
					break
				attempts -= 1

	# --- NPC Spawn: Always spawn 1 NPC per floor ---
	var npc_types = EnemyDatabase.get_npc_definitions(current_floor)
	if npc_types.size() > 0 and _rooms.size() >= 2:
		var npc_type = npc_types.pick_random()
		var npc_room = _rooms[randi_range(1, _rooms.size() - 1)]  # Avoid room 0 (player start)
		
		for _attempt in range(20):
			var nx = randi_range(npc_room.position.x, npc_room.position.x + npc_room.size.x - 1)
			var ny = randi_range(npc_room.position.y, npc_room.position.y + npc_room.size.y - 1)
			if _map_data[nx][ny] == CellType.FLOOR:
				_spawn_single_npc(npc_type, Vector2(nx, ny) * TILE_SIZE)
				break

func _spawn_ally_near_player(data: Dictionary):
	if not player or not is_instance_valid(player):
		return
	
	var player_grid = tile_map.local_to_map(player.position)
	var spawn_positions = []
	
	# Retrieve database definition to check if this ally can swim
	var can_swim_check = false
	var ally_id = data.get("enemy_id", "zakomushi")
	var db_def = EnemyDatabase.get_enemy_def(ally_id)
	if not db_def.is_empty() and db_def.get("swim", false):
		can_swim_check = true
	
	# Find valid spawn positions around the player
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if dx == 0 and dy == 0: continue
			var test_pos = player_grid + Vector2i(dx, dy)
			if test_pos.x >= 0 and test_pos.x < MAP_WIDTH and test_pos.y >= 0 and test_pos.y < MAP_HEIGHT:
				var cell = _map_data[test_pos.x][test_pos.y]
				var is_walkable = cell == CellType.FLOOR or \
								  cell == CellType.GRASS or \
								  cell == CellType.ASH or \
								  cell == CellType.CRYSTAL_FLOOR or \
								  cell == CellType.ICE or \
								  cell == CellType.DOOR_OPEN or \
								  cell == CellType.STAIRS or \
								  cell == CellType.STAIRS_BLUE or \
								  cell == CellType.STAIRS_GREEN or \
								  cell == CellType.STAIRS_RED or \
								  cell == CellType.STAIRS_PURPLE or \
								  cell == CellType.STAIRS_GOLD
				
				if cell == CellType.WATER and can_swim_check:
					is_walkable = true
					
				if is_walkable:
					# Check if position is not occupied
					var occupied = false
					for entity in get_tree().get_nodes_in_group("entities"):
						if is_instance_valid(entity) and entity != player:
							var entity_grid = tile_map.local_to_map(entity.position)
							if entity_grid == test_pos:
								occupied = true
								break
					if not occupied:
						var dist = test_pos.distance_to(player_grid)
						spawn_positions.append({"pos": test_pos, "dist": dist})
	
	# Sort by distance and pick closest
	spawn_positions.sort_custom(func(a, b): return a.dist < b.dist)
	
	var spawn_pos = player_grid
	if spawn_positions.size() > 0:
		spawn_pos = spawn_positions[0].pos
		
	var ally = EnemyScene.instantiate()
	
	ally.enemy_name = data.get("enemy_name", "仲間")
	ally.enemy_id = data.get("enemy_id", "zakomushi")
	if ally.enemy_id == "zakomushi" and ally.enemy_name != "仲間":
		ally.enemy_id = ally.enemy_name
		
	var def = EnemyDatabase.get_enemy_def(ally.enemy_id)
	if not def.is_empty():
		ally.enemy_name = def.name
		ally.hp = data.get("hp", int(def.hp))
		ally.max_hp = data.get("max_hp", int(def.hp))
		ally.attack_power = data.get("attack", int(def.atk))
		if "color" in def: ally.base_color = def.color
		if "swim" in def: ally.can_swim = def.swim
		if "sprite_path" in data and data["sprite_path"] != "":
			ally.sprite_path = data["sprite_path"]
		elif "sprite" in def:
			ally.sprite_path = def.sprite
		else:
			ally.sprite_path = ""
		if "weak" in def: ally.weaknesses = def.weak
		if "resist" in def: ally.resistances = def.resist
		if "fire_immune" in def: ally.fire_immune = def.fire_immune
		if "on_hit" in def: ally.on_hit_effects = def.on_hit
		if "penetration" in def: ally.penetration_rate = def.penetration
		if "intelligence" in def: ally.intelligence = def.intelligence
		if "knockback" in def: ally.has_knockback = def.knockback
		if "loot" in def: ally.loot_table = def.loot
		if "trade_items" in def: ally.trade_items = def.trade_items.duplicate()
	else:
		ally.hp = data.get("hp", 10)
		ally.max_hp = data.get("max_hp", 10)
		ally.attack_power = data.get("attack", 5)
		if "sprite_path" in data:
			ally.sprite_path = data["sprite_path"]
		else:
			ally.sprite_path = ""
		
	ally.defense = data.get("defense", 0)
	ally.attack_range = data.get("attack_range", 1.5)
	
	if "is_flying" in data:
		ally.is_flying = data["is_flying"]
		
	ally.is_npc = true
	ally.add_to_group("allies")
	ally.add_to_group("npcs")
	ally.add_to_group("entities")
	
	ally.position = Vector2(spawn_pos) * TILE_SIZE
	add_child(ally)
	
	# Set ally AI and appearance AFTER add_child so sprite node is initialized
	ally.set_ally(player)
	ally.visible = false

func _spawn_village_npcs():
	var npc_types = EnemyDatabase.get_npc_definitions(current_floor)
	if npc_types.is_empty(): return
	
	var npc_count = randi_range(3, 8)
	var spawned = 0
	
	# 通行可能タイルの定義
	var is_walkable = func(cell: int) -> bool:
		return cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.CRYSTAL_FLOOR

	# 村全体の通行可能エリアからランダムに位置を選んでスポーン
	for i in range(npc_count):
		var success = false
		for attempt in range(100):
			var rx = randi_range(4, MAP_WIDTH - 5)
			var ry = randi_range(4, MAP_HEIGHT - 5)
			
			if is_walkable.call(_map_data[rx][ry]):
				# 他のエンティティと重なっていないかチェック
				var occupied = false
				for entity in get_tree().get_nodes_in_group("entities"):
					if is_instance_valid(entity):
						var e_grid = tile_map.local_to_map(entity.position)
						if e_grid == Vector2i(rx, ry):
							occupied = true
							break
				if not occupied:
					var type = npc_types.pick_random()
					_spawn_single_npc(type, Vector2(rx, ry) * TILE_SIZE)
					spawned += 1
					success = true
					break
		if not success:
			print("Village NPC Spawn: Failed to find valid position for NPC #", i)
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("平穏な里に辿り着いた。", Color(0.1, 1.0, 0.5))

func _spawn_single_npc(type: Dictionary, pos: Vector2):
	var npc = EnemyScene.instantiate()
	npc.enemy_name = type.name
	npc.enemy_id = type.get("id", type.name)
	npc.hp = int(type.hp)
	npc.max_hp = int(type.hp)
	npc.attack_power = int(type.atk)
	npc.exp_reward = 0
	if "color" in type: npc.base_color = type.color
	if "can_swim" in npc: npc.can_swim = type.get("swim", false)
	if "sprite" in type: npc.sprite_path = type.sprite
	if "skill" in type:
		npc.skill_id = type.skill
		npc.attack_range = type.get("range", 1)
		npc.max_skill_cooldown = type.get("cooldown", 5)
		npc.skill_cooldown = randi_range(0, npc.max_skill_cooldown)
	if "trade_items" in type:
		npc.trade_items = type.trade_items.duplicate()
	npc.is_npc = true
	npc.position = pos
	npc.add_to_group("npcs")
	npc.add_to_group("entities")
	add_child(npc)
	npc.visible = false
	print("NPC Spawned: ", npc.enemy_name, " at ", pos)

func _generate_map(local_type: int = -1):
	var generator = DungeonGenerator.new()
	var is_starting = false
	var is_dungeon = false
	if current_floor == 0 and local_type == WorldCell.VILLAGE:
		if _world_player_pos == _starting_village_pos:
			is_starting = true
		elif _world_player_pos == _dungeon_village_pos:
			is_dungeon = true
			
	var result = generator.generate_map(current_floor, _current_branch, local_type, self, is_starting, is_dungeon)
	_map_data = result["map_data"]
	_rooms = result["rooms"]
	generator.free()
	
	_visible_tiles.resize(MAP_WIDTH)
	_explored_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		_visible_tiles[x] = []
		_visible_tiles[x].resize(MAP_HEIGHT)
		_explored_tiles[x] = []
		_explored_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			_visible_tiles[x][y] = false
			_explored_tiles[x][y] = false

func _setup_pathfinding():
	_astar_grid.clear()
	_astar_grid.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	_astar_grid.cell_size = Vector2(1, 1)
	_astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar_grid.jumping_enabled = false

	if _is_on_world_map:
		for x in range(MAP_WIDTH):
			for y in range(MAP_HEIGHT):
				var pos = Vector2i(x, y)
				var cell = _world_map_data[x][y]
				if cell != WorldCell.SEA and cell != WorldCell.MOUNTAIN:
					_astar_grid.set_point_solid(pos, false)
				else:
					_astar_grid.set_point_solid(pos, true)
		_astar_grid.update()
		return

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var pos = Vector2i(x, y)
			var is_walkable_base = _map_data[x][y] == CellType.FLOOR or _map_data[x][y] == CellType.STAIRS or _map_data[x][y] == CellType.GRASS or _map_data[x][y] == CellType.ASH or _map_data[x][y] == CellType.CRYSTAL_FLOOR or _map_data[x][y] == CellType.STAIRS_BLUE or _map_data[x][y] == CellType.STAIRS_GREEN or _map_data[x][y] == CellType.STAIRS_RED or _map_data[x][y] == CellType.STAIRS_PURPLE or _map_data[x][y] == CellType.STAIRS_GOLD or _map_data[x][y] == CellType.DOOR_OPEN or _map_data[x][y] == CellType.DOOR_CLOSED or _map_data[x][y] == CellType.ICE
			var is_frozen = _frozen_tiles.has(pos)
			
			if is_walkable_base or is_frozen:
				_astar_grid.set_point_solid(pos, false)
			else:
				_astar_grid.set_point_solid(pos, true)
	_astar_grid.update()

	_astar_grid_swim.clear()
	_astar_grid_swim.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	_astar_grid_swim.cell_size = Vector2(1, 1)
	_astar_grid_swim.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar_grid_swim.jumping_enabled = false
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _map_data[x][y] == CellType.WALL or _map_data[x][y] == CellType.LAVA or _map_data[x][y] == CellType.PIT or _map_data[x][y] == CellType.TREE or _map_data[x][y] == CellType.TREE_FRUIT or _map_data[x][y] == CellType.ROCK:
				_astar_grid_swim.set_point_solid(Vector2i(x, y), true)
			else:
				_astar_grid_swim.set_point_solid(Vector2i(x, y), false)
	_astar_grid_swim.update()

	_astar_grid_fly.clear()
	_astar_grid_fly.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	_astar_grid_fly.cell_size = Vector2(1, 1)
	_astar_grid_fly.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar_grid_fly.jumping_enabled = false
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _map_data[x][y] == CellType.WALL:
				_astar_grid_fly.set_point_solid(Vector2i(x, y), true)
			else:
				_astar_grid_fly.set_point_solid(Vector2i(x, y), false)
	_astar_grid_fly.update()




func _draw_map():
	tile_map.clear_layer(LAYER_VISIBLE)
	tile_map.clear_layer(LAYER_MEMORY)
	if is_instance_valid(memory_tile_map):
		memory_tile_map.clear()
	
	
	# Clear old fire overlays and blood decals
	get_tree().call_group("fire_overlays", "queue_free")
	get_tree().call_group("blood_decals", "queue_free")
	get_tree().call_group("world_village_icons", "queue_free")
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _explored_tiles[x][y]:
				var cell_type = _map_data[x][y]
				var tile_coords = Vector2i(x, y)
				var atlas_coords = Vector2i(0, 0)
				
				match cell_type:
					CellType.WALL:
						# Calculate neighbor bitmask for connecting walls
						var mask = 0
						# N=1, E=2, S=4, W=8
						if y > 0 and _map_data[x][y-1] == CellType.WALL: mask |= 1
						if x < MAP_WIDTH - 1 and _map_data[x+1][y] == CellType.WALL: mask |= 2
						if y < MAP_HEIGHT - 1 and _map_data[x][y+1] == CellType.WALL: mask |= 4
						if x > 0 and _map_data[x-1][y] == CellType.WALL: mask |= 8
						atlas_coords.x = mask
					CellType.FLOOR:
						atlas_coords.x = 16
					CellType.STAIRS:
						atlas_coords.x = 17
					CellType.WATER:
						# Calculate neighbor bitmask for connecting water
						var mask = 0
						if y > 0 and _map_data[x][y-1] == CellType.WATER: mask |= 1
						if x < MAP_WIDTH - 1 and _map_data[x+1][y] == CellType.WATER: mask |= 2
						if y < MAP_HEIGHT - 1 and _map_data[x][y+1] == CellType.WATER: mask |= 4
						if x > 0 and _map_data[x-1][y] == CellType.WATER: mask |= 8
						atlas_coords.x = 18 + mask
					CellType.GRASS:
						atlas_coords.x = 34
					CellType.STAIRS_BLUE:
						atlas_coords.x = 16 # Use floor base, draw sprite on top
					CellType.STAIRS_GREEN:
						atlas_coords.x = 16 # Use
					CellType.LAVA:
						atlas_coords.x = 40
					CellType.ASH:
						atlas_coords.x = 41
					CellType.CRYSTAL_FLOOR:
						# Calculate neighbor bitmask for connecting crystal floor
						var mask = 0
						if y > 0 and _map_data[x][y-1] == CellType.CRYSTAL_FLOOR: mask |= 1
						if x < MAP_WIDTH - 1 and _map_data[x+1][y] == CellType.CRYSTAL_FLOOR: mask |= 2
						if y < MAP_HEIGHT - 1 and _map_data[x][y+1] == CellType.CRYSTAL_FLOOR: mask |= 4
						if x > 0 and _map_data[x-1][y] == CellType.CRYSTAL_FLOOR: mask |= 8
						atlas_coords.x = 45 + mask
					CellType.STAIRS_RED:
						atlas_coords.x = 16
					CellType.STAIRS_PURPLE:
						atlas_coords.x = 16
					CellType.STAIRS_GOLD:
						atlas_coords.x = 79
					CellType.DOOR_CLOSED:
						atlas_coords.x = 36
					CellType.DOOR_OPEN:
						atlas_coords.x = 37
					9: # DOOR_LOCKED
						atlas_coords.x = 38
					10: # ICE
						atlas_coords.x = 39
					CellType.PIT:
						var mask = 0
						if y > 0 and _map_data[x][y-1] == CellType.PIT: mask |= 1
						if x < MAP_WIDTH - 1 and _map_data[x+1][y] == CellType.PIT: mask |= 2
						if y < MAP_HEIGHT - 1 and _map_data[x][y+1] == CellType.PIT: mask |= 4
						if x > 0 and _map_data[x-1][y] == CellType.PIT: mask |= 8
						atlas_coords.x = 61 + mask
					CellType.STAIRS_UP:
						atlas_coords.x = 77
					CellType.TREE:
						atlas_coords.x = 80
					CellType.TREE_FRUIT:
						atlas_coords.x = 81
					CellType.ROCK:
						atlas_coords.x = 82
				
				if _visible_tiles[x][y]:
					tile_map.set_cell(LAYER_VISIBLE, tile_coords, 0, atlas_coords)
					
					var pos = Vector2i(x, y)
					
					# Custom Stairs Rendering (Visible)
					# Custom Stairs Rendering (Visible)
					if cell_type == CellType.STAIRS_GREEN:
						_draw_custom_stairs(tile_coords, Color(0.1, 1.0, 0.1), true) # Pure bright green
					elif cell_type == CellType.STAIRS_BLUE:
						_draw_custom_stairs(tile_coords, Color(0.1, 0.4, 1.0), true) # Pure bright blue
					elif cell_type == CellType.STAIRS_RED:
						_draw_custom_stairs(tile_coords, Color(1.0, 0.2, 0.05), true)
					elif cell_type == CellType.STAIRS_PURPLE:
						_draw_custom_stairs(tile_coords, Color(0.65, 0.25, 1.0), true)

					# Tint burning grass tiles red
					if _burning_grass.has(pos):
						var fire_overlay = ColorRect.new()
						fire_overlay.color = Color(1.0, 0.3, 0.0, 0.5)
						fire_overlay.size = Vector2(TILE_SIZE, TILE_SIZE)
						fire_overlay.position = Vector2(tile_coords) * TILE_SIZE
						fire_overlay.add_to_group("fire_overlays")
						add_child(fire_overlay)
					
					# Tint frozen tiles light blue
					if _frozen_tiles.has(pos):
						var frost_overlay = ColorRect.new()
						frost_overlay.color = Color(0.5, 0.8, 1.0, 0.4)
						frost_overlay.size = Vector2(TILE_SIZE, TILE_SIZE)
						frost_overlay.position = Vector2(tile_coords) * TILE_SIZE
						frost_overlay.add_to_group("fire_overlays") # Repurposing group for easy clearing
						add_child(frost_overlay)
						
					# Show steam as semi-transparent white - density affects opacity
					if _steam_tiles.has(pos):
						var steam_data = _steam_tiles[pos]
						var steam_density = steam_data.get("density", 1)
						var steam_alpha = 0.3 + steam_density * 0.15  # density 1=0.45, 2=0.60, 3=0.75
						var steam_overlay = ColorRect.new()
						steam_overlay.color = Color(0.92, 0.92, 0.95, steam_alpha)
						steam_overlay.size = Vector2(TILE_SIZE, TILE_SIZE)
						steam_overlay.position = Vector2(tile_coords) * TILE_SIZE
						steam_overlay.add_to_group("fire_overlays")
						add_child(steam_overlay)
				else:
					if is_instance_valid(memory_tile_map):
						memory_tile_map.set_cell(0, tile_coords, 0, atlas_coords)
					else:
						tile_map.set_cell(LAYER_MEMORY, tile_coords, 0, atlas_coords)
					
					# Custom Stairs Rendering (Memory - Darker, No Particles)
					# Custom Stairs Rendering (Memory - Darker, No Particles)
					if cell_type == CellType.STAIRS_GREEN:
						_draw_custom_stairs(tile_coords, Color(0.2, 0.6, 0.2), false) # Visible dark green
					elif cell_type == CellType.STAIRS_BLUE:
						_draw_custom_stairs(tile_coords, Color(0.2, 0.3, 0.7), false) # Visible dark blue
					elif cell_type == CellType.STAIRS_RED:
						_draw_custom_stairs(tile_coords, Color(0.6, 0.18, 0.08), false)
					elif cell_type == CellType.STAIRS_PURPLE:
						_draw_custom_stairs(tile_coords, Color(0.35, 0.18, 0.55), false)

	minimap_controller.update_minimap()



# ---- 扉を閉じる処理 ----
# プレイヤーの隣接マス（斜め含む）にある開いた扉を探して閉じる
func _handle_close_door():
	if not is_instance_valid(player): return
	var player_grid = tile_map.local_to_map(player.position)
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]
	for dir in dirs:
		var check = player_grid + dir
		if check.x < 0 or check.x >= MAP_WIDTH or check.y < 0 or check.y >= MAP_HEIGHT:
			continue
		if _map_data[check.x][check.y] == CellType.DOOR_OPEN:
			# 扉の位置にエンティティがいれば閉じられない
			var blocked_by_entity = false
			for entity in get_tree().get_nodes_in_group("entities"):
				if not is_instance_valid(entity): continue
				var eg = tile_map.local_to_map(entity.position)
				if eg == check:
					blocked_by_entity = true
					break
			if blocked_by_entity:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("扉を閉じられない（何かが邪魔している）", Color(0.85, 0.65, 0.30))
				continue
			_map_data[check.x][check.y] = CellType.DOOR_CLOSED
			_update_shadow_cell(check)
			_update_astar_tile(check, true) # 閉じたので通行不可に
			_calculate_fov()
			_draw_map()
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("扉を閉じた。", Color(0.85, 0.65, 0.30))
			if player.has_method("play_door_close_sound"):
				player.play_door_close_sound()
			await _end_player_turn()
			return
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("閉じられる扉が隣にない。", Color(0.6, 0.6, 0.6))

# ---- 壁を掘る処理 ----
func _handle_dig(target_grid: Vector2i):
	if not is_instance_valid(player): return
	
	if player.hunger <= 0:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("空腹で壁を掘る力がない…", Color(0.85, 0.3, 0.3))
		return
	
	if target_grid.x <= 0 or target_grid.x >= MAP_WIDTH - 1 or target_grid.y <= 0 or target_grid.y >= MAP_HEIGHT - 1:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("外周の硬い壁は掘れません。", Color(0.85, 0.3, 0.3))
		return
		
	if _map_data[target_grid.x][target_grid.y] == CellType.WALL:
		# STRに応じた満腹度（hunger）の消費計算（STRが低いほど消費が多い）
		var str_val = player.get_total_strength() if player.has_method("get_total_strength") else player.strength
		var hunger_cost = int(max(1, ceil(15.0 / float(max(1, str_val)))))
		
		# 満腹度を消費（下限は0）
		player.hunger = max(player.hunger - hunger_cost, 0)
		
		_map_data[target_grid.x][target_grid.y] = CellType.FLOOR
		_update_shadow_cell(target_grid)
		_update_astar_tile(target_grid, false) # 床にしたので通行可能に
		_calculate_fov()
		_draw_map()
		
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("壁を掘った（満腹度 -%d）。" % hunger_cost, Color(0.85, 0.65, 0.30))
			
		if hit_sound_player:
			hit_sound_player.pitch_scale = randf_range(0.8, 0.9)
			hit_sound_player.play()
			
		await _end_player_turn()
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("そこには掘れる壁がありません。", Color(0.6, 0.6, 0.6))

# ---- AStarグリッドの単タイル更新 ----
# 扉の開閉のたびに全グリッドを再構築しないための最適化
func _update_astar_tile(pos: Vector2i, make_solid: bool):
	_astar_grid.set_point_solid(pos, make_solid)
	_astar_grid.update()
	_astar_grid_swim.set_point_solid(pos, make_solid)
	_astar_grid_swim.update()
	_astar_grid_fly.set_point_solid(pos, make_solid)
	_astar_grid_fly.update()


func _handle_reload():
	if not player: return
	
	var ranged_weapon = player._get_ranged_weapon() if player.has_method("_get_ranged_weapon") else null
	if not ranged_weapon:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("遠距離武器を装備していません", Color.GRAY)
		return
		
	var magazine_size = ranged_weapon.effects.get("magazine_size", 0)
	if magazine_size <= 0:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("この武器はリロードできません", Color.GRAY)
		return
		
	if player.ranged_weapon_shots_fired <= 0:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("弾倉は満タンです", Color.YELLOW)
		return
		
	# 予備弾薬チェック
	if player.ammo_inventory <= 0:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("予備の弾薬がありません！", Color.RED)
		return

	# Reload Logic
	var reload_type = ranged_weapon.effects.get("reload_type", "single")
	var loaded_amount = 0
	
	var needed = 0
	if reload_type == "full":
		needed = player.ranged_weapon_shots_fired
	else:
		needed = 1
		
	# 実際に補充できる量
	loaded_amount = min(needed, player.ammo_inventory)
	
	player.ranged_weapon_shots_fired -= loaded_amount
	player.ammo_inventory -= loaded_amount
	
	if PlayerUi:
		PlayerUi.update_ammo(player.ammo_inventory)
	
	print("Reload! Loaded: ", loaded_amount, " Remaining Reserve: ", player.ammo_inventory)
		
	var current_bullets = magazine_size - player.ranged_weapon_shots_fired
	
	print("Reload action. Current bullets: ", current_bullets, "/", magazine_size)
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("弾丸を%d発補充しました (%d/%d)" % [loaded_amount, current_bullets, magazine_size], Color(0.6, 1.0, 0.6))
	
	# Play reload sound
	if player.has_method("play_reload_sound"):
		player.play_reload_sound()
	
	await _end_player_turn()

func _calculate_fov():
	if visibility_manager:
		visibility_manager.calculate_fov()
	else:
		push_error("VisibilityManager missing in _calculate_fov")

func _update_entity_visibility():
	if visibility_manager:
		visibility_manager.update_entity_visibility()
		
	# Update Torch Visibility
	for torch in get_tree().get_nodes_in_group("torches"):
		var grid_pos = tile_map.local_to_map(torch.position)
		if grid_pos.x >= 0 and grid_pos.x < MAP_WIDTH and grid_pos.y >= 0 and grid_pos.y < MAP_HEIGHT:
			torch.visible = _visible_tiles[grid_pos.x][grid_pos.y]
		else:
			torch.visible = false

func _update_single_entity_visibility(entity):
	if visibility_manager:
		visibility_manager.update_single_entity_visibility(entity)

func _cast_light_octant(origin: Vector2i, row: int, start_slope: float, end_slope: float, xx: int, xy: int, yx: int, yy: int):
	if start_slope < end_slope:
		return

	var new_start_slope = start_slope
	var blocked = false
	
	for col in range(row, FOV_RADIUS + 1):
		var current_pos = origin + Vector2i(col * xx + 0 * xy, col * yx + 0 * yy) # Placeholder for col/row transform
		
		var dx = -col
		for dy in range(-col, 1):
			var current_x = origin.x + dx * xx + dy * xy
			var current_y = origin.y + dx * yx + dy * yy
			
			var left_slope = (dy - 0.5) / (dx + 0.5)
			var right_slope = (dy + 0.5) / (dx - 0.5)
			
			if new_start_slope < right_slope:
				continue
			elif end_slope > left_slope:
				break
			
			# Check bounds and set visibility
			if current_x >= 0 and current_x < MAP_WIDTH and current_y >= 0 and current_y < MAP_HEIGHT:
				if (Vector2i(current_x, current_y) - origin).length() <= FOV_RADIUS:
					_visible_tiles[current_x][current_y] = true
					_explored_tiles[current_x][current_y] = true

					if blocked: # Previous cell was blocked
						if _map_data[current_x][current_y] == CellType.WALL or _steam_tiles.has(Vector2i(current_x, current_y)):
							new_start_slope = right_slope
							continue
						else:
							blocked = false
							new_start_slope = right_slope
					else:
						var is_blocking = _map_data[current_x][current_y] == CellType.WALL or _steam_tiles.has(Vector2i(current_x, current_y))
						if is_blocking and col < FOV_RADIUS:
							blocked = true
							_cast_light_octant(origin, col + 1, new_start_slope, left_slope, xx, xy, yx, yy)
							new_start_slope = right_slope
			else: # Out of bounds
				break
				
func _get_transform(octant: int) -> Transform2D:
	# Returns a transform for mapping coordinates to each octant
	match octant:
		0: return Transform2D(Vector2(1, 0),  Vector2(0, 1), Vector2.ZERO)
		1: return Transform2D(Vector2(0, 1),  Vector2(1, 0), Vector2.ZERO)
		2: return Transform2D(Vector2(0, -1), Vector2(1, 0), Vector2.ZERO)
		3: return Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO)
		4: return Transform2D(Vector2(-1, 0), Vector2(0, -1), Vector2.ZERO)
		5: return Transform2D(Vector2(0, -1), Vector2(-1, 0), Vector2.ZERO)
		6: return Transform2D(Vector2(0, 1),  Vector2(-1, 0), Vector2.ZERO)
		7: return Transform2D(Vector2(1, 0),  Vector2(0, -1), Vector2.ZERO)
	return Transform2D() # Should not happen


func _save_current_floor_to_cache():
	var floor_key = ""
	if current_floor == 0:
		floor_key = "local_overworld_%d_%d" % [_world_player_pos.x, _world_player_pos.y]
	else:
		floor_key = "dungeon_%d_%d_floor_%d_branch_%d" % [_world_player_pos.x, _world_player_pos.y, current_floor, _current_branch]
	
	var items_data = []
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			var item_center = item.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var grid_pos = Vector2i(int(item_center.x / TILE_SIZE), int(item_center.y / TILE_SIZE))
			items_data.append({
				"grid_pos": grid_pos,
				"item_data": item.item_data
			})
			
	var enemies_data = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
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
	for npc in get_tree().get_nodes_in_group("npcs"):
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
			
	_floor_caches[floor_key] = {
		"map_data": _map_data.duplicate(true),
		"rooms": _rooms.duplicate(true),
		"explored_tiles": _explored_tiles.duplicate(true),
		"burning_grass": _burning_grass.duplicate(),
		"frozen_tiles": _frozen_tiles.duplicate(),
		"steam_tiles": _steam_tiles.duplicate(),
		"items": items_data,
		"enemies": enemies_data,
		"npcs": npcs_data,
		"player_exit_grid": Vector2i(player.position / TILE_SIZE) if is_instance_valid(player) else Vector2i.ZERO
	}

func _load_floor_from_cache(floor_key: String, is_upward: bool, is_seamless: bool = false) -> bool:
	if not _floor_caches.has(floor_key):
		return false
		
	var cache = _floor_caches[floor_key]
	_map_data = cache["map_data"].duplicate(true)
	_rooms = cache["rooms"].duplicate(true)
	_explored_tiles = cache["explored_tiles"].duplicate(true)
	_burning_grass = cache["burning_grass"].duplicate()
	_frozen_tiles = cache["frozen_tiles"].duplicate()
	_steam_tiles = cache["steam_tiles"].duplicate()
	
	_visible_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		_visible_tiles[x] = []
		_visible_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			_visible_tiles[x][y] = false
			
	var allies = get_tree().get_nodes_in_group("allies")
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
	for saved_ally in _saved_allies:
		ally_data.append(saved_ally)
	_saved_allies.clear()
			
	# Safely remove old entities from scene tree and groups immediately
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.remove_from_group("enemies")
			enemy.remove_from_group("entities")
			enemy.queue_free()
			
	for npc in get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc):
			npc.remove_from_group("npcs")
			npc.remove_from_group("entities")
			npc.queue_free()
			
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item):
			item.remove_from_group("items")
			item.remove_from_group("entities")
			item.queue_free()
			
	for torch in get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.remove_from_group("torches")
			torch.queue_free()
	
	_setup_pathfinding()
	
	player = get_node_or_null("Player")
	if is_instance_valid(player):
		var spawn_pos = cache["player_exit_grid"]
		
		if not is_seamless:
			# Reposition player on matching stairs when returning
			# Downward (is_upward == false) -> Place on STAIRS_UP
			# Upward (is_upward == true) -> Place on STAIRS
			# Floor 0 (Overworld) -> Always place on cave entrance (STAIRS)
			var target_stair_type = CellType.STAIRS if is_upward else CellType.STAIRS_UP
			if current_floor == 0:
				target_stair_type = CellType.STAIRS
				
			var found_stair = false
			for x in range(MAP_WIDTH):
				for y in range(MAP_HEIGHT):
					if _map_data[x][y] == target_stair_type:
						spawn_pos = Vector2i(x, y)
						found_stair = true
						break
				if found_stair: break
				
			player.position = Vector2(spawn_pos) * TILE_SIZE
			_last_player_grid_pos = spawn_pos
			camera.position = player.position
			camera.reset_smoothing()
			
		if player.has_method("update_terrain_info"):
			var current_grid_pos = Vector2i(player.position / TILE_SIZE)
			if current_grid_pos.x >= 0 and current_grid_pos.x < MAP_WIDTH and current_grid_pos.y >= 0 and current_grid_pos.y < MAP_HEIGHT:
				var is_grass = _map_data[current_grid_pos.x][current_grid_pos.y] == CellType.GRASS
				var is_water = _map_data[current_grid_pos.x][current_grid_pos.y] == CellType.WATER
				player.update_terrain_info(is_grass, is_water)
		
	var item_scene = load("res://items/world_item.tscn")
	for idata in cache["items"]:
		var item_node = item_scene.instantiate()
		item_node.position = Vector2(idata["grid_pos"]) * TILE_SIZE
		item_node.item_data = idata["item_data"]
		item_node.add_to_group("items")
		item_node.add_to_group("entities")
		add_child(item_node)
		
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
		add_child(enemy_node)
		
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
		add_child(npc_node)
		
	for adata in ally_data:
		_spawn_ally_near_player(adata)
		
	_spawn_torches()
	
	# Sync VisibilityManager references for the loaded floor
	if visibility_manager:
		visibility_manager.map_data = _map_data
		visibility_manager.visible_tiles = _visible_tiles
		visibility_manager.explored_tiles = _explored_tiles
		visibility_manager.burning_grass = _burning_grass
		visibility_manager.frozen_tiles = _frozen_tiles
		visibility_manager.steam_tiles = _steam_tiles
		visibility_manager.calculate_fov()
		visibility_manager.draw_map()
	else:
		_calculate_fov()
		_draw_map()
	return true

func _change_floor(target_floor: int, target_branch: int = 0, is_upward: bool = false, is_pit: bool = false):
	# Save current floor
	_save_current_floor_to_cache()
	
	current_floor = target_floor
	_current_branch = target_branch
	_shop_uses_this_floor = 0
	
	var msg = ""
	if is_pit:
		msg = "落とし穴から次の階層へ落ちた！"
	elif is_upward:
		if current_floor == 0:
			msg = "洞窟を出て地上に戻った！"
		else:
			msg = "上り階段を上った！"
	else:
		if current_floor == 1:
			msg = "洞窟の入り口を降りた！"
		else:
			msg = "下り階段を下りた！"
		
	print(msg, " Floor: ", current_floor)
	if has_node("/root/LogUI"):
		var color = Color(1, 0.8, 0.2)
		if is_pit:
			color = Color(0.9, 0.4, 0.4)
		elif is_upward:
			color = Color(0.2, 0.9, 0.4)
		elif target_branch == 2: color = Color(0.2, 0.6, 1.0) # Blue
		elif target_branch == 3: color = Color(0.2, 1.0, 0.2) # Green
		elif target_branch == 1: color = Color(1, 0.2, 0.2) # Red
		elif target_branch == 4: color = Color(1.0, 0.25, 0.05) # Volcanic
		elif target_branch == 5: color = Color(0.65, 0.25, 1.0) # Crystal
		
		if is_pit or is_upward:
			get_node("/root/LogUI").add_log("%s 階層 %d へ" % [msg, current_floor], color)
		else:
			get_node("/root/LogUI").add_log("%s 階層 %d へ (Branch %d)" % [msg, current_floor, target_branch], color)
	
	if PlayerUi:
		PlayerUi.update_floor(current_floor)
		
	if player and player.has_method("replenish_ammo"):
		player.replenish_ammo(20)
		
	var floor_key = ""
	if current_floor == 0:
		floor_key = "local_overworld_%d_%d" % [_world_player_pos.x, _world_player_pos.y]
	else:
		floor_key = "dungeon_%d_%d_floor_%d_branch_%d" % [_world_player_pos.x, _world_player_pos.y, current_floor, _current_branch]
		
	if _load_floor_from_cache(floor_key, is_upward):
		return
		
	# Cache not found, generate new map
	var ally_data = []
	var allies = get_tree().get_nodes_in_group("allies")
	for ally in allies:
		if is_instance_valid(ally) and not ally.is_queued_for_deletion():
			ally_data.append({
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
	
	for ally in allies:
		if is_instance_valid(ally):
			ally.remove_from_group("allies")
			ally.remove_from_group("entities")
			if ally.is_in_group("npcs"):
				ally.remove_from_group("npcs")
			ally.queue_free()
	
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.remove_from_group("enemies")
			enemy.remove_from_group("entities")
			enemy.queue_free()
	for npc in get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc):
			npc.remove_from_group("npcs")
			npc.remove_from_group("entities")
			npc.queue_free()
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item):
			item.remove_from_group("items")
			item.remove_from_group("entities")
			item.queue_free()
	for torch in get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.remove_from_group("torches")
			torch.queue_free()
	
	if current_floor == 0:
		var cell_type = _world_map_data[_world_player_pos.x][_world_player_pos.y]
		_generate_map(cell_type)
	else:
		_generate_map()
	_setup_pathfinding()
	
	if visibility_manager:
		visibility_manager.map_data = _map_data
		visibility_manager.visible_tiles = _visible_tiles
		visibility_manager.explored_tiles = _explored_tiles
		visibility_manager.burning_grass = _burning_grass
		visibility_manager.frozen_tiles = _frozen_tiles
		visibility_manager.steam_tiles = _steam_tiles
		visibility_manager.calculate_fov()
		visibility_manager.draw_map()

	if not _rooms.is_empty():
		player = get_node_or_null("Player")
		if is_instance_valid(player):
			var spawn_pos = _rooms[0].get_center()
			
			if current_floor == 0:
				spawn_pos = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
				
			if current_floor >= 1:
				var target_stair = CellType.STAIRS if is_upward else CellType.STAIRS_UP
				var found_stair = false
				for x in range(MAP_WIDTH):
					for y in range(MAP_HEIGHT):
						if _map_data[x][y] == target_stair:
							spawn_pos = Vector2i(x, y)
							found_stair = true
							break
					if found_stair: break
					
			player.position = Vector2(spawn_pos) * TILE_SIZE
			_last_player_grid_pos = spawn_pos
			if player.has_method("update_terrain_info"):
				var is_grass = _map_data[spawn_pos.x][spawn_pos.y] == CellType.GRASS
				var is_water = _map_data[spawn_pos.x][spawn_pos.y] == CellType.WATER
				player.update_terrain_info(is_grass, is_water)
			camera.position = player.position
			camera.reset_smoothing()

	if current_floor == 0:
		_spawn_village_npcs()
	else:
		_spawn_enemies()
		_spawn_items()
		
	for data in ally_data:
		_spawn_ally_near_player(data)

	_spawn_torches()
	_calculate_fov()
	_draw_map()

func _spawn_torches():
	var torch_scene = load("res://items/torch.tscn")
	if not torch_scene: return
	
	# Place torches on walls occasionally
	# Scan for walls that have floor adjacent to them (so the torch is visible)
	# For simplicity, let's just pick random spots in rooms and place them on walls?
	# Or, iterate through all map tiles. Since map is small-ish (60x40), iterating is fine.
	
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			if _map_data[x][y] == CellType.WALL:
				# Check neighbors for floor
				var has_floor_neighbor = false
				if _map_data[x+1][y] == CellType.FLOOR or \
				   _map_data[x-1][y] == CellType.FLOOR or \
				   _map_data[x][y+1] == CellType.FLOOR or \
				   _map_data[x][y-1] == CellType.FLOOR:
					has_floor_neighbor = true
				
				if has_floor_neighbor:
					# 5% chance to spawn a torch on suitable wall
					if randf() < 0.05:
						var torch = torch_scene.instantiate()
						torch.position = Vector2(x, y) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
						torch.add_to_group("torches")
						torch.visible = false # Start hidden, reveal in FOV update
						add_child(torch)
	_draw_map()

	await _end_player_turn()

func _spawn_items():
	print("Spawning items...")
	var items_spawned = 0
	
	# Beginner branch 3F: Spawn guaranteed special treasures in the last room
	if _current_branch == 10 and current_floor == 3:
		var last_room = _rooms.back()
		var guaranteed_items = ["long_sword", "golden_gummy", "potion_str"]
		for item_id in guaranteed_items:
			var attempts = 20
			while attempts > 0:
				var x = randi_range(last_room.position.x, last_room.position.x + last_room.size.x - 1)
				var y = randi_range(last_room.position.y, last_room.position.y + last_room.size.y - 1)
				if _map_data[x][y] == CellType.FLOOR or _map_data[x][y] == CellType.GRASS:
					var item = WorldItemScene.instantiate()
					item.position = Vector2(x, y) * TILE_SIZE
					
					var item_data = ItemDatabase.get_item_by_id(item_id)
					if item_data:
						item.set_item(item_data)
						item.add_to_group("items")
						item.add_to_group("entities")
						add_child(item)
						print("Guaranteed treasure spawned: ", item_id, " at ", item.position)
						items_spawned += 1
						break
				attempts -= 1

	for i in range(1, _rooms.size()):
		var room = _rooms[i]
		
		# If this is beginner branch 3F, skip random item spawns in the last room since we placed treasures
		if _current_branch == 10 and current_floor == 3 and i == _rooms.size() - 1:
			continue
			
		var spawn_chance = 50 - (current_floor * 1)
		spawn_chance = clamp(spawn_chance, 20, 90)
		
		if _current_branch == 1:
			spawn_chance += 30 # Higher chance in dangerous branch
			spawn_chance = min(spawn_chance, 100)
			
		if randi_range(0, 100) < spawn_chance:
			var attempts = 10
			while attempts > 0:
				var x = randi_range(room.position.x, room.position.x + room.size.x - 1)
				var y = randi_range(room.position.y, room.position.y + room.size.y - 1)
				if _map_data[x][y] == CellType.FLOOR or _map_data[x][y] == CellType.GRASS:
					var item = WorldItemScene.instantiate()
					item.position = Vector2(x, y) * TILE_SIZE
					
					var item_data
					if _current_branch == 10:
						item_data = ItemDatabase.get_beginner_item(current_floor)
					else:
						item_data = ItemDatabase.get_random_item(current_floor)
						
					item.set_item(item_data)
					item.add_to_group("items")
					item.add_to_group("entities")
					add_child(item)
					print("Item spawned at: ", item.position)
					items_spawned += 1
					break
				attempts -= 1
	print("Total items spawned: ", items_spawned)

# Targeting variables
var _targeting_item = null
var _targeting_skill = null
var _targeting_line: Line2D
var _targeting_is_ranged_weapon: bool = false
var _keyboard_target_grid: Vector2i = Vector2i.ZERO

func start_ranged_attack(weapon_item):
	var range_val = 6
	if weapon_item.effects.has("range"): range_val = weapon_item.effects["range"]
	target_manager.start_targeting(player.position, range_val, weapon_item, null, true, 0, true)
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("射撃ターゲットを選択してください (左クリックで発射)", Color.YELLOW)

func start_throw_targeting(item):
	target_manager.start_targeting(player.position, 6, item, null, false, 0, true)
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("ターゲットを選択してください (左クリックで決定, 右クリックでキャンセル)", Color.YELLOW)

func start_skill_targeting(skill_data):
	var range_val = skill_data.get("range", 6)
	var aoe = skill_data.get("radius", 0)
	var type = skill_data.get("type", "target")
	var is_line = (type != "point") 
	target_manager.start_targeting(player.position, range_val, null, skill_data, false, aoe, is_line)
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("%s のターゲットを選択してください" % skill_data["name"], Color.CYAN)

func start_look_mode():
	if not target_manager: return
	target_manager.start_look_targeting(player.position)
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("観察モード (方向キーで移動, ESCまたはXでキャンセル)", Color.YELLOW)

func _execute_directional_attack(direction: Vector2) -> bool:
	if not player or ("is_moving" in player and player.is_moving):
		return false
		
	# Prevent attacking while already moving/acting
	if _is_path_following or _is_auto_moving or _is_resting or _is_auto_exploring:
		return false
		
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = player_grid + Vector2i(direction)
	
	if target_grid.x < 0 or target_grid.x >= MAP_WIDTH or target_grid.y < 0 or target_grid.y >= MAP_HEIGHT:
		return false
		
	# Check if there is an entity at the target tile
	var target_entity = null
	for child in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if child == player or child.is_in_group("items"):
			continue
		if not (child is Node2D):
			continue
		var child_grid = tile_map.local_to_map(child.position)
		if child_grid == target_grid:
			target_entity = child
			break
				
	if target_entity:
		if not _is_hostile(player, target_entity) and not target_entity.is_in_group("npcs"):
			if has_node("/root/LogUI"):
				var entity_name = target_entity.enemy_name if "enemy_name" in target_entity else "味方"
				get_node("/root/LogUI").add_log("%s を攻撃することはできません。" % entity_name, Color.GRAY)
			return false
		
		# Attack the hostile entity!
		await _handle_attack(player, target_entity)
		return true
		
	# If no entity, perform a swing in empty space/grass
	var cell_type = _map_data[target_grid.x][target_grid.y]
	
	# Bump/Swing Animation
	var sprite = player.get_node_or_null("Sprite2D")
	if sprite:
		var start_pos = sprite.position
		if "sprite_offset" in player:
			start_pos = player.sprite_offset
		var bump_pos = start_pos + direction * 16.0
		var tween = create_tween()
		tween.tween_property(sprite, "position", bump_pos, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position", start_pos, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tween.finished
		
	# Log the swing
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("空振りした。", Color(0.7, 0.7, 0.7))
		
	# Fire-Grass Synergy: Ignite if grass and player's weapon has fire/burn attribute
	if cell_type == CellType.GRASS:
		var is_fire_attack = false
		if player.has_method("get_on_hit_effects"):
			for effects in player.get_on_hit_effects():
				if effects.has("burn"):
					is_fire_attack = true
					break
		
		if is_fire_attack:
			_ignite_grass(target_grid)
			
	# Water Electrification Synergy: Electrify if water and player has spark core
	elif cell_type == CellType.WATER:
		var is_electric_attack = false
		if player.has_method("_check_equipment_effect") and player._check_equipment_effect("spark_core_effect"):
			is_electric_attack = true
			
		if is_electric_attack:
			_electrify_water(target_grid)
			
	return true

func _start_targeting_visuals():
	if not _targeting_line:
		_targeting_line = Line2D.new()
		_targeting_line.width = 2
		_targeting_line.default_color = Color(1, 0, 0, 0.7)
		add_child(_targeting_line)
	_targeting_line.visible = true
	
	# Initialize keyboard cursor:
	# Priority 1: Nearest Visible Enemy
	var enemies = _get_visible_enemies()
	var nearest_enemy = null
	var min_dist = 9999.0
	var player_pos = tile_map.local_to_map(player.position)
	
	for enemy in enemies:
		var e_pos = tile_map.local_to_map(enemy.position)
		var dist = Vector2(player_pos).distance_squared_to(Vector2(e_pos))
		if dist < min_dist:
			min_dist = dist
			nearest_enemy = enemy
			
	if nearest_enemy:
		_keyboard_target_grid = tile_map.local_to_map(nearest_enemy.position)
	else:
		# Fallback: Player position
		_keyboard_target_grid = player_pos
	
	# Initial Draw
	_draw_targeting_line()

func _cancel_targeting():
	_current_game_state = TurnPhase.PLAYER_TURN
	_targeting_item = null
	_targeting_skill = null
	_targeting_is_ranged_weapon = false
	if _targeting_line:
		_targeting_line.visible = false
	print("Targeting canceled")

func _update_targeting_cursor():
	if _current_game_state != TurnPhase.TARGETING: return
	
	# If using mouse, update keyboard grid to mouse pos
	var mouse_pos = get_global_mouse_position()
	var mouse_grid = tile_map.local_to_map(mouse_pos)
	
	# Only update if mouse actually moved to a different tile to avoid overwriting keyboard input constantly?
	# For simplicity, let's prioritize keyboard if function called via keyboard, or mouse if mouse motion event.
	# But here we are called from _input which differentiates.
	# So this function is primarily for MOUSE motion updates.
	
	_keyboard_target_grid = mouse_grid
	_draw_targeting_line()

func _move_targeting_cursor(direction: Vector2i):
	_keyboard_target_grid += direction
	_draw_targeting_line()

func _draw_targeting_line():
	if not _targeting_line: return
	
	var player_center = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var target_center = Vector2(_keyboard_target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	_targeting_line.clear_points()
	_targeting_line.add_point(player_center)
	_targeting_line.add_point(target_center)

func _execute_ranged_attack(target_pos: Vector2):
	if not target_manager.targeting_item: return
	var _targeting_item = target_manager.targeting_item
	
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	
	# Range Check
	var range_limit = 6
	if _targeting_item.effects.has("range"):
		range_limit = _targeting_item.effects["range"]
		
	var dist = Vector2(player_grid).distance_to(Vector2(target_grid))
	if dist > range_limit:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("射程外だ！", Color.GRAY)
		return

	# Play Shoot Sound
	if hit_sound_player:
		hit_sound_player.pitch_scale = randf_range(0.95, 1.05)
		hit_sound_player.play()
		
	var line_points = _get_line_points(player_grid, target_grid)
	
	var hit_pos = target_grid
	var hit_entity = null
	
	# Trace
	for i in range(1, line_points.size()):
		var p = line_points[i]
		# Check Bounds
		if p.x < 0 or p.x >= MAP_WIDTH or p.y < 0 or p.y >= MAP_HEIGHT:
			hit_pos = line_points[i-1]
			break
			
		# Check Wall or Door
		if _map_data[p.x][p.y] == CellType.WALL or _map_data[p.x][p.y] == CellType.DOOR_CLOSED or _map_data[p.x][p.y] == CellType.DOOR_LOCKED:
			hit_pos = line_points[i-1]
			if has_node("/root/LogUI") and i < line_points.size()-1:
				pass # Wall/Door hit
			break
			
		# Check Enemy
		var enemy_hit = false
		for enemy in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(enemy) and enemy != player and enemy.has_method("take_damage"):
				var e_grid = tile_map.local_to_map(enemy.position)
				if e_grid == p:
					hit_entity = enemy
					hit_pos = p
					enemy_hit = true
					break
		if enemy_hit: break
		
		hit_pos = p
		
	# Animation (Arrow-like)
	var projectile_sprite = Sprite2D.new()
	var img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.7, 0.5)) # Wood color
	projectile_sprite.texture = ImageTexture.create_from_image(img)
	add_child(projectile_sprite)
	projectile_sprite.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	# Rotate towards target
	projectile_sprite.look_at(Vector2(hit_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
	
	var target_world_pos = Vector2(hit_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var tween = create_tween()
	tween.tween_property(projectile_sprite, "position", target_world_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(projectile_sprite.queue_free)
	await tween.finished
	
	# Apply Damage
	if hit_entity:
		# Calculate accuracy: Base 70% + (dexterity * 3%)
		var base_accuracy = 0.70
		var dex_bonus = player.dexterity * 0.03
		var total_accuracy = clamp(base_accuracy + dex_bonus, 0.0, 0.95)
		
		# Check if hit
		if randf() < total_accuracy:
			var dmg = _targeting_item.attack + player.dexterity
			
			# Critical Check
			var is_crit = false
			if player and "crit_rate" in player:
				if randf() < player.crit_rate:
					is_crit = true
					dmg *= 2
					
			if is_instance_valid(hit_entity):
				hit_entity.take_damage(dmg, player, ["normal"], is_crit)
			if has_node("/root/LogUI"):
				var e_name = hit_entity.name
				if is_instance_valid(hit_entity) and "enemy_name" in hit_entity: e_name = hit_entity.enemy_name
				var crit_text = " (会心!)" if is_crit else ""
				get_node("/root/LogUI").add_log("%s を撃って %s に %d ダメージ！%s" % [_targeting_item.name, e_name, dmg, crit_text], Color.ORANGE)
		else:
			# Miss
			if has_node("/root/LogUI"):
				var e_name = hit_entity.name
				if "enemy_name" in hit_entity: e_name = hit_entity.enemy_name
				get_node("/root/LogUI").add_log("矢は %s を外れた！" % e_name, Color.GRAY)
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("矢は虚しく飛んでいった。", Color.GRAY)

	# Apply cooldown or magazine system
	var magazine_size = _targeting_item.effects.get("magazine_size", 0)
	
	if magazine_size > 0:
		# Magazine-based weapon (Magnum, Pistol)
		player.ranged_weapon_shots_fired += 1
		
		if player.ranged_weapon_shots_fired >= magazine_size:
			# Magazine empty
			# If cooldown is 0, it means manual reload required.
			var weapon_cooldown = _targeting_item.effects.get("cooldown", 0)
			
			if weapon_cooldown > 0:
				# Automatic cooldown/reload system
				player.ranged_weapon_cooldown = weapon_cooldown
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("弾切れ！ 再充填中...", Color.YELLOW)
			else:
				# Manual reload required
				player.ranged_weapon_cooldown = 0
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("弾倉が空になった！ リロード(R)が必要", Color.RED)
		else:
			# Still have shots left
			var remaining = magazine_size - player.ranged_weapon_shots_fired
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("残弾: %d" % remaining, Color(0.7, 0.7, 1.0))
	else:
		# Cooldown-based weapon (Bow)
		var weapon_cooldown = 2 # Default cooldown
		if _targeting_item.effects.has("cooldown"):
			weapon_cooldown = _targeting_item.effects["cooldown"]
		player.ranged_weapon_cooldown = weapon_cooldown
	
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_throw(target_pos: Vector2):
	if not target_manager.targeting_item: return
	var _targeting_item = target_manager.targeting_item
	
	# 1. Calculate path
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	
	# Simple Raycast on grid
	var line_points = _get_line_points(player_grid, target_grid)
	
	var hit_pos = target_grid
	var hit_entity = null
	
	# Trace line to find first obstacle
	for i in range(1, line_points.size()): # Skip start (player)
		var p = line_points[i]
		if p.x < 0 or p.x >= MAP_WIDTH or p.y < 0 or p.y >= MAP_HEIGHT:
			hit_pos = line_points[i-1]
			break
			
		if _map_data[p.x][p.y] == CellType.WALL or _map_data[p.x][p.y] == CellType.DOOR_CLOSED or _map_data[p.x][p.y] == CellType.DOOR_LOCKED:
			hit_pos = line_points[i-1] # Stop before obstacle
			print("Hit wall or door at ", p)
			break
			
		# Check for enemies
		var enemy_hit = false
		for enemy in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(enemy) and enemy != player and enemy.has_method("take_damage"):
				var e_grid = tile_map.local_to_map(enemy.position)
				if e_grid == p:
					hit_entity = enemy
					hit_pos = p
					enemy_hit = true
					break
		if enemy_hit: break
		
		hit_pos = p # Continue path
	
	# 2. Visual Animation
	var projectile_sprite = Sprite2D.new()
	# Use item texture or a placeholder
	if _targeting_item.texture:
		projectile_sprite.texture = _targeting_item.texture
		projectile_sprite.scale = Vector2(0.5, 0.5) # Smaller item
	else:
		# Fallback
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		projectile_sprite.texture = ImageTexture.create_from_image(img)
		
	add_child(projectile_sprite)
	projectile_sprite.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	var target_world_pos = Vector2(hit_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var tween = create_tween()
	tween.tween_property(projectile_sprite, "position", target_world_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(projectile_sprite.queue_free)
	
	await tween.finished
	
	# 3. Apply Effect
	# 3. Apply Effect
	if hit_entity:
		print("Hit entity: ", hit_entity.name)
		
		# Check for potion/consumable effects
		# Potion / High Potion
		if _targeting_item.id == "potion" or _targeting_item.id == "high_potion":
			if hit_entity.has_method("heal"):
				var amount = 10
				if _targeting_item.id == "high_potion": amount = 30
				hit_entity.heal(amount)
				if has_node("/root/LogUI"):
					var entity_name = hit_entity.name
					if "enemy_name" in hit_entity: entity_name = hit_entity.enemy_name
					get_node("/root/LogUI").add_log("%s は %s に当たって砕けた！ %s のHPが回復した。" % [_targeting_item.name, entity_name, entity_name], Color.GREEN)
			else:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("%s は当たって砕けた。" % _targeting_item.name, Color.GRAY)
					
		# Warp Grass (Teleport Enemy)
		elif _targeting_item.id == "warp_grass":
			var pos = get_random_floor_position()
			if pos != Vector2.ZERO:
				hit_entity.position = pos
				if has_node("/root/LogUI"):
					var entity_name = hit_entity.name
					if "enemy_name" in hit_entity: entity_name = hit_entity.enemy_name
					get_node("/root/LogUI").add_log("%s は %s に当たった！ %s は何処かへ消え去った！" % [_targeting_item.name, entity_name, entity_name], Color.PURPLE)
		
		# Strength Potion (Throwing it wastes it or gives str?)
		# Maybe throwing a str potion at enemy increases their str? Let's treat as waste/damage for now
		
		else:
			# Normal Thrown Damage
			var damage = 1
			if "attack" in _targeting_item and _targeting_item.attack > 0:
				# Weapons and offensive parts
				damage = _targeting_item.attack + player.strength
			elif "defense" in _targeting_item and _targeting_item.defense > 0:
				# Shields and armor
				damage = _targeting_item.defense * 2 + int(player.strength * 0.5)
			elif _targeting_item.id in ["ring", "life_ring", "hunter_ring"]:
				# Rings / accessories
				damage = 2 + int(player.dexterity * 0.3)
			else:
				# Default light/soft items
				damage = 1
				
			damage = max(1, damage)
			
			# Critical Check
			var is_crit = false
			if player and "crit_rate" in player:
				if randf() < player.crit_rate:
					is_crit = true
					damage *= 2
			
			if is_instance_valid(hit_entity):
				hit_entity.take_damage(damage, player, ["normal"], is_crit)
			
			if has_node("/root/LogUI"):
				var entity_name = hit_entity.name
				if "enemy_name" in hit_entity: entity_name = hit_entity.enemy_name
				var crit_text = " (会心!)" if is_crit else ""
				get_node("/root/LogUI").add_log("%s を投げて %s に %d ダメージ！%s" % [_targeting_item.name, entity_name, damage, crit_text], Color.ORANGE)
	else:
		# Drop item on ground
		var world_item = WorldItemScene.instantiate()
		world_item.position = Vector2(hit_pos) * TILE_SIZE
		world_item.set_item(_targeting_item)
		world_item.add_to_group("items")
		world_item.add_to_group("entities")
		add_child(world_item)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s が地面に落ちた。" % _targeting_item.name, Color.GRAY)

	# 4. Remove from inventory
	if player.equipment_component.bag_data.remove_item(_targeting_item):
		pass # Removed from bag
	elif player.equipment_component.equipment_data.remove_item(_targeting_item):
		pass # Removed from equipment
		
	# 5. End Turn
	target_manager.cancel_targeting()
	await _end_player_turn()

func _handle_pickup():
	if not player: return
	
	var picked_any = false
	var items_at_feet = []
	var world_items = get_tree().get_nodes_in_group("items")
	var p_pos = player.position
	
	for wi in world_items:
		if is_instance_valid(wi) and not wi.is_queued_for_deletion() and wi is Node2D:
			if wi.position.distance_to(p_pos) < 16.0:
				if "item_data" in wi and wi.item_data:
					items_at_feet.append(wi)
	
	if items_at_feet.is_empty():
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("足元には何もない", Color.GRAY)
		return
		
	for wi in items_at_feet:
		if not is_instance_valid(wi) or wi.is_queued_for_deletion():
			continue
		if player.pickup_item(wi.item_data):
			wi.queue_free()
			picked_any = true
	
	if picked_any:
		await _end_player_turn()
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("インベントリがいっぱいで拾えない", Color.RED)

func _handle_talk():
	var npcs = get_tree().get_nodes_in_group("npcs") + get_tree().get_nodes_in_group("allies")
	var has_visible_npc = false
	
	for npc in npcs:
		if is_instance_valid(npc) and npc != player:
			# NPC/Ally is visible (within vision)
			if _can_player_recognize_entity(npc):
				has_visible_npc = true
				break
				
	if not has_visible_npc:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("話しかける相手が周りにいません。", Color.GRAY)
		return
		
	if target_manager:
		target_manager.start_talk_targeting(player.position)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("話しかける相手を選択してください (方向キー/クリックで指定, ENTER/Vキー/左クリックで決定, ESC/右クリックでキャンセル)", Color.YELLOW)

func _execute_talk_at(target_grid: Vector2i):
	# Find npc or ally at target_grid
	var target_entity = null
	for entity in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity):
			var e_grid = tile_map.local_to_map(entity.position)
			if e_grid == target_grid:
				target_entity = entity
				break
				
	if not target_entity:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("そこには誰もいません。", Color.GRAY)
		return

	var entity_name = "誰か"
	if "enemy_name" in target_entity:
		entity_name = target_entity.enemy_name
	
	if target_entity.is_in_group("npcs") or target_entity.is_in_group("allies"):
		# Check if NPC is already an ally
		if target_entity.is_in_group("allies"):
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%s: 「もう仲間だよ！」" % entity_name, Color(0.8, 1.0, 0.8))
			await _end_player_turn()
			return
		
		# Check if NPC is weakened (HP <= 40%)
		var is_weakened = false
		if "hp" in target_entity and "max_hp" in target_entity:
			if target_entity.hp <= target_entity.max_hp * 0.4:
				is_weakened = true
				
		var npc_id = target_entity.enemy_id if "enemy_id" in target_entity else "default"
		var greeting = ""
		if is_weakened:
			match npc_id:
				"wanderer_swordsman", "放浪の剣士": greeting = "「ううっ、不覚にも魔物にやられてしまった… 傷が深くて動けん…」"
				"stray_mage", "はぐれ魔道士": greeting = "「あたた… 魔力も体力も底をついてしまった… 誰か助けてくれ…」"
				"villager", "村人": greeting = "「痛い、痛いよぉ… 誰か、ポーションかヒールで助けてください…」"
				"merchant", "商人": greeting = "「うう、商品も体もボロボロだ… 誰か助けてくれたら、お礼はするよ…」"
				"elder", "村の長老": greeting = "「ごほっ、ごほっ… 年寄りにはこの寒さは堪える… 誰か助けておくれ…」"
				"guard", "村の守備隊": greeting = "「くっ… 守備隊の誇りにかけて倒れるわけにはいかんが… もう限界だ…」"
				_: greeting = "「うう… 傷が痛む… 助けてくれ…」"
		else:
			match npc_id:
				"wanderer_swordsman", "放浪 of 剣士", "放浪の剣士": greeting = "「私は世界を旅する剣士だ。腕の立つ仲間を探しているのかい？」"
				"stray_mage", "はぐれ魔道士": greeting = "「私ははぐれ魔道士。何か用かい？ 魔法の研究で忙しいのだがね。」"
				"villager", "村人": greeting = "「こんにちは、旅の方。このあたりは魔物が多くて危険ですよ。」"
				"merchant", "商人": greeting = "「いらっしゃい！ 良い品が揃っているよ。見ていくだけでも歓迎さ！」"
				"elder", "村の長老": greeting = "「おお、旅の者よ。何か困ったことはないかね？」"
				"guard", "村の守備隊": greeting = "「ここは村の境界だ。警戒を怠るわけにはいかん。」"
				_: greeting = "「何か用かね？」"
				
		# Build options array
		var options = []
		if is_weakened:
			options.append("助ける")
		else:
			options.append("仲間にする")
			
		# Check if NPC has trade items
		if "trade_items" in target_entity and not target_entity.trade_items.is_empty():
			options.append("取引する")
			
		options.append("キャンセル")
		
		# Show dialog with customized title/greeting and options
		_talk_choice_npc = target_entity
		var game_ui = get_node_or_null("/root/GameUI")
		if game_ui and game_ui.has_method("show_dialog_menu"):
			# Format dialog title to show NPC Name & Greeting
			var dialog_title = "[%s]\n%s" % [entity_name, greeting]
			game_ui.show_dialog_menu(dialog_title, options)
		return
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s は話しかけられても反応しない..." % entity_name, Color(0.8, 0.8, 0.8))
	
	await _end_player_turn()

var _talk_choice_npc = null

func _handle_dialog_choice(option: String):
	if not _talk_choice_npc:
		return
	
	var npc = _talk_choice_npc
	_talk_choice_npc = null
	
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	
	if option == "取引する":
		if "trade_items" in npc and not npc.trade_items.is_empty():
			_open_trade_menu(npc)
		else:
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%s: 「取引できるものはないよ」" % entity_name, Color(0.8, 0.8, 0.8))
			await _end_player_turn()
	elif option == "仲間にする":
		_show_recruitment_demand(npc)
	elif option == "助ける":
		_help_npc(npc)
	elif option in ["100G払う", "80G払う", "30G払う", "150G払う", "120G払う", "50G払う"]:
		var cost = 50
		if option == "100G払う": cost = 100
		elif option == "80G払う": cost = 80
		elif option == "30G払う": cost = 30
		elif option == "150G払う": cost = 150
		elif option == "120G払う": cost = 120
		
		if player.gold >= cost:
			player.gold -= cost
			if PlayerUi:
				PlayerUi.update_gold(player.gold)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%d ゴールドを支払いました。" % cost, Color.YELLOW)
			_recruit_npc(npc)
		else:
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("ゴールドが足りません！", Color.RED)
			await _end_player_turn()
	elif option == "エーテルを渡す":
		_recruit_with_item(npc, "ether", "エーテル")
	elif option == "銀のグミを渡す":
		_recruit_with_item(npc, "silver_gummy", "銀のグミ")
	elif option == "ポーションを渡す":
		var item_to_remove = null
		if player.equipment_component and player.equipment_component.bag_data:
			for item in player.equipment_component.bag_data.items:
				if item.id == "potion" or item.id == "high_potion":
					item_to_remove = item
					break
		if item_to_remove:
			player.equipment_component.bag_data.remove_item(item_to_remove)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%s を渡しました。" % item_to_remove.name, Color.YELLOW)
			_recruit_npc(npc)
		else:
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("ポーションを持っていません！", Color.RED)
			await _end_player_turn()
	elif option == "キャンセル":
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("会話をキャンセルしました", Color(0.6, 0.6, 0.6))
		await _end_player_turn()

func _show_recruitment_demand(npc):
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	var npc_id = npc.enemy_id if "enemy_id" in npc else "default"
	
	_talk_choice_npc = npc # Save it again for the next dialog choice
	
	var demand_text = ""
	var options = []
	
	match npc_id:
		"wanderer_swordsman", "放浪 of 剣士", "放浪の剣士":
			demand_text = "「私を雇うには 100 ゴールドが必要だが、払えるかい？」"
			options = ["100G払う", "キャンセル"]
		"stray_mage", "はぐれ魔道士":
			demand_text = "「私を連れていきたいなら、研究資金として 80 ゴールド、あるいは「エーテル」を1個譲ってほしいね。」"
			options = ["80G払う", "エーテルを渡す", "キャンセル"]
		"villager", "村人":
			demand_text = "「旅のお供をするには、支度金として 30 ゴールドか「銀のグミ」をいただけないでしょうか？」"
			options = ["30G払う", "銀のグミを渡す", "キャンセル"]
		"merchant", "商人":
			demand_text = "「商売を休んでお前さんについていくからには、保証金として 150 ゴールドもらうよ。」"
			options = ["150G払う", "キャンセル"]
		"guard", "村の守備隊":
			demand_text = "「任務外で同行するとなれば、手当として 120 ゴールド必要だ。」"
			options = ["120G払う", "キャンセル"]
		"elder", "村の長老":
			demand_text = "「老いた体を動かすのは骨が折れる。50 ゴールドか「ポーション」を分けてくれんかのぉ？」"
			options = ["50G払う", "ポーションを渡す", "キャンセル"]
		_:
			demand_text = "「旅のお供をするには、50 ゴールド必要じゃ。」"
			options = ["50G払う", "キャンセル"]
			
	var game_ui = get_node_or_null("/root/GameUI")
	if game_ui and game_ui.has_method("show_dialog_menu"):
		var dialog_title = "[%s]\n%s" % [entity_name, demand_text]
		game_ui.show_dialog_menu(dialog_title, options)

func _recruit_with_item(npc, item_id: String, item_name: String):
	var item_to_remove = null
	if player.equipment_component and player.equipment_component.bag_data:
		for item in player.equipment_component.bag_data.items:
			if item.id == item_id:
				item_to_remove = item
				break
	if item_to_remove:
		player.equipment_component.bag_data.remove_item(item_to_remove)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を渡しました。" % item_name, Color.YELLOW)
		_recruit_npc(npc)
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を持っていません！" % item_name, Color.RED)
		await _end_player_turn()

func _help_npc(npc):
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	
	# Check for Potion / High Potion
	var potion_item = null
	if player.equipment_component and player.equipment_component.bag_data:
		for item in player.equipment_component.bag_data.items:
			if item.id == "potion" or item.id == "high_potion":
				potion_item = item
				break
				
	# Check for Heal Skill & MP
	var has_heal_skill = player.known_skills.has("heal")
	var has_enough_mp = player.mp >= 5
	
	var helped = false
	var method_used = ""
	
	if potion_item:
		# Consume potion
		player.equipment_component.bag_data.remove_item(potion_item)
		helped = true
		method_used = "potion"
	elif has_heal_skill and has_enough_mp:
		# Consume MP
		player.mp -= 5
		if PlayerUi:
			PlayerUi.update_mp(player.mp, player.max_mp)
		player._update_skill_ui()
		helped = true
		method_used = "heal"
		
	if helped:
		# Heal the NPC to full
		npc.heal(npc.max_hp - npc.hp)
		
		# Make them an ally
		npc.add_to_group("allies")
		if npc.is_in_group("npcs"):
			npc.remove_from_group("npcs")
		if npc.has_method("set_ally"):
			npc.set_ally(player)
			
		# Log the result
		if has_node("/root/LogUI"):
			if method_used == "potion":
				get_node("/root/LogUI").add_log("ポーションを使って %s を治療した！" % entity_name, Color(0.3, 1.0, 0.3))
			else:
				get_node("/root/LogUI").add_log("ヒールを使って %s を治療した！" % entity_name, Color(0.3, 1.0, 0.3))
			get_node("/root/LogUI").add_log("%s が仲間になった！" % entity_name, Color(0.0, 1.0, 0.5))
			
		# Visual effect on the NPC
		_spawn_skill_particles(npc.position + Vector2(16, 16), "heal", 0.6)
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s: 「うう… ポーションかヒール魔法があれば…」" % entity_name, Color(0.8, 0.8, 0.8))
			get_node("/root/LogUI").add_log("回復させる手段（ポーションまたはヒール魔法とMP5）がありません！", Color.RED)
			
	await _end_player_turn()

func _recruit_npc(npc):
	var entity_name = npc.enemy_name if "enemy_name" in npc else "誰か"
	
	# Check if NPC is already an ally
	if npc.is_in_group("allies"):
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s はすでに仲間だ" % entity_name, Color.GRAY)
		await _end_player_turn()
		return
	
	# Add NPC to allies group
	npc.add_to_group("allies")
	
	# Remove from npcs group if present
	if npc.is_in_group("npcs"):
		npc.remove_from_group("npcs")
	
	# Change NPC behavior to follow player
	if npc.has_method("set_ally"):
		npc.set_ally(player)
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("%s を仲間にした！" % entity_name, Color(0.0, 1.0, 0.5))
	
	await _end_player_turn()

var _current_trade_npc = null
var _is_trading = false

func _open_trade_menu(npc):
	_current_trade_npc = npc
	_is_trading = true
	var npc_name = npc.enemy_name if "enemy_name" in npc else "商人"
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("%s と取引を開始した", Color(1.0, 0.85, 0.0))
	
	# Open trade UI via GameUI
	if GameUI and GameUI.has_method("open_trade_menu"):
		GameUI.open_trade_menu(npc)
	
	# Don't end turn - trade menu is modal
	# Turn will end after trade is completed

func cancel_trade():
	if _is_trading:
		_is_trading = false
		_current_trade_npc = null
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("取引をキャンセルしました", Color.GRAY)

func _handle_shop_purchase():
	if not player: return
	if _shop_uses_this_floor >= SHOP_MAX_USES_PER_FLOOR:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("No more trades on this floor.", Color.GRAY)
		return
	# Shop only available at stairs tiles
	var p_grid = tile_map.local_to_map(player.position)
	if p_grid.x < 0 or p_grid.x >= MAP_WIDTH or p_grid.y < 0 or p_grid.y >= MAP_HEIGHT:
		return
	var cell = _map_data[p_grid.x][p_grid.y]
	var on_stairs = _is_stairs_cell(cell)
	if not on_stairs:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("A trader only appears at the stairs.", Color.GRAY)
		return
	if SHOP_OFFERS.is_empty():
		return

	var offer = SHOP_OFFERS.pick_random()
	var price = int(offer["price"])
	var item_id = str(offer["id"])
	if player.gold < price:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("Not enough gold. Need %dG." % price, Color.RED)
		return

	var item = ItemDatabase.get_item_by_id(item_id)
	if item == null:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("Trade failed. (Unknown item)", Color.RED)
		return

	if not player.pickup_item(item):
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("Inventory full. Trade canceled.", Color.RED)
		return

	player.gold -= price
	_shop_uses_this_floor += 1
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("Traded %dG for %s." % [price, item.name], Color(1.0, 0.85, 0.0))
	await _end_player_turn()

func _execute_skill(target_pos: Vector2):
	if not target_manager.targeting_skill: return
	var _targeting_skill = target_manager.targeting_skill
	
	# Block input and hide line immediately
	_current_game_state = TurnPhase.ENEMY_TURN
	if target_manager and target_manager.path_line:
		target_manager.path_line.visible = false

	# CHARGE Logic
	if _targeting_skill.get("id", "") == "charge":
		_execute_charge_skill(target_pos)
		return
	
	# EXPLOSION / POINT Skill Logic
	if _targeting_skill.get("type", "") == "point":
		await _execute_point_skill(target_pos, _targeting_skill)
		return

	# DIRECTIONAL/PROJECTILE Skill Logic
	await _execute_directional_skill(target_pos, _targeting_skill)

func _get_line_points(start: Vector2i, end: Vector2i) -> Array:
	var points = []
	var x1 = start.x
	var y1 = start.y
	var x2 = end.x
	var y2 = end.y
	
	var dx = abs(x2 - x1)
	var dy = abs(y2 - y1)
	var sx = 1 if x1 < x2 else -1
	var sy = 1 if y1 < y2 else -1
	var err = dx - dy
	
	while true:
		points.append(Vector2i(x1, y1))
		if x1 == x2 and y1 == y2: break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x1 += sx
		if e2 < dx:
			err += dx
			y1 += sy
	return points


func _create_star_texture(size: int = 8) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var dx = abs(x - center)
			var dy = abs(y - center)
			# Star shape: narrow arms along axes, plus small center diamond
			if dx + dy <= center * 0.7 or (dx < 1.0 and dy < center) or (dy < 1.0 and dx < center):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

func _create_leaf_texture(size: int = 8) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var dx = abs(x - center)
			var dy = abs(y - center)
			# Leaf / Almond shape: diamond with slightly tapered horizontal/vertical edges
			if dx + dy <= center * 1.25 and (dx <= center * 0.7 and dy <= center * 0.7):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _create_plus_texture(size: int = 8) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var dx = abs(x - center)
			var dy = abs(y - center)
			# Plus symbol shape
			if (dx < 1.5 and dy < center * 0.8) or (dy < 1.5 and dx < center * 0.8):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

func _create_diamond_texture(size: int = 8) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = (size - 1) / 2.0
	for x in range(size):
		for y in range(size):
			var dx = abs(x - center)
			var dy = abs(y - center)
			# Sharp diamond shape
			if dx + dy <= center:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _spawn_skill_particles(pos: Vector2, particle_type: String, duration: float = 0.5):
	var particles = CPUParticles2D.new()
	particles.position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.amount = 25
	particles.lifetime = duration
	
	# Create fade-out gradient so particles dissolve beautifully
	var fade_gradient = Gradient.new()
	fade_gradient.set_color(0, Color(1, 1, 1, 1))
	fade_gradient.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade_gradient
	
	match particle_type:
		"meteor":
			particles.color = Color(1.0, 0.2, 0.0, 1) # Bright red/orange
			particles.texture = _create_diamond_texture(8)
			particles.amount = 80
			particles.spread = 180.0
			particles.gravity = Vector2(0, -100)
			particles.initial_velocity_min = 150.0
			particles.initial_velocity_max = 300.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 4.0
			particles.explosiveness = 0.95
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -150.0
			particles.angular_velocity_max = 150.0
		"fire":
			particles.color = Color(1, 0.4, 0, 1) # Orange/Red
			particles.texture = _create_diamond_texture(8)
			particles.spread = 180.0
			particles.gravity = Vector2(0, -60)
			particles.initial_velocity_min = 40.0
			particles.initial_velocity_max = 80.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 2.5
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -120.0
			particles.angular_velocity_max = 120.0
		"lightning":
			particles.color = Color(1, 1, 0.5, 1) # Yellow white
			particles.texture = _create_star_texture(8)
			particles.amount = 30
			particles.spread = 180.0
			particles.gravity = Vector2.ZERO
			particles.initial_velocity_min = 100.0
			particles.initial_velocity_max = 150.0
			particles.scale_amount_min = 0.5
			particles.scale_amount_max = 2.0
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -400.0
			particles.angular_velocity_max = 400.0
		"ice":
			particles.color = Color(0.7, 1.0, 1.0, 1) # Ice cyan
			particles.texture = _create_diamond_texture(8)
			particles.amount = 20
			particles.spread = 180.0
			particles.gravity = Vector2(0, 40)
			particles.initial_velocity_min = 20.0
			particles.initial_velocity_max = 50.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 2.5
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -100.0
			particles.angular_velocity_max = 100.0
		"web":
			particles.color = Color(0.9, 0.9, 0.9, 0.7) # Web white
			particles.texture = _create_diamond_texture(6)
			particles.amount = 15
			particles.spread = 180.0
			particles.gravity = Vector2(0, 0)
			particles.initial_velocity_min = 10.0
			particles.initial_velocity_max = 30.0
			particles.scale_amount_min = 0.8
			particles.scale_amount_max = 2.0
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -80.0
			particles.angular_velocity_max = 80.0
		"heal":
			particles.color = Color(0.6, 1.0, 0.6, 1) # Life green
			particles.texture = _create_plus_texture(10)
			particles.amount = 30
			particles.spread = 180.0
			particles.gravity = Vector2(0, -30)
			particles.initial_velocity_min = 30.0
			particles.initial_velocity_max = 60.0
			particles.scale_amount_min = 0.8
			particles.scale_amount_max = 2.0
			particles.explosiveness = 0.5 # Constant rise
			particles.angle_min = -45.0
			particles.angle_max = 45.0
			particles.angular_velocity_min = -60.0
			particles.angular_velocity_max = 60.0
		"hit_physical":
			particles.color = Color(1.0, 0.9, 0.4, 1.0) # Bright yellow spark
			particles.texture = _create_diamond_texture(8)
			particles.amount = 15
			particles.spread = 180.0
			particles.gravity = Vector2(0, 150) # Fall down slightly
			particles.initial_velocity_min = 80.0
			particles.initial_velocity_max = 140.0
			particles.scale_amount_min = 0.8
			particles.scale_amount_max = 2.0
			particles.explosiveness = 0.9
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -300.0
			particles.angular_velocity_max = 300.0
		"hit_player":
			particles.color = Color(1.0, 0.2, 0.2, 1.0) # Crimson sparks
			particles.texture = _create_diamond_texture(8)
			particles.amount = 12
			particles.spread = 180.0
			particles.gravity = Vector2(0, 180)
			particles.initial_velocity_min = 70.0
			particles.initial_velocity_max = 120.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 2.5
			particles.explosiveness = 0.95
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -250.0
			particles.angular_velocity_max = 250.0
		"levelup":
			particles.color = Color(1.0, 0.85, 0.2, 1.0) # Majestic golden glow stars
			particles.texture = _create_star_texture(12)
			particles.amount = 40
			particles.spread = 360.0 # Multi-directional spray
			particles.gravity = Vector2(0, -100) # Floating skywards
			particles.initial_velocity_min = 60.0
			particles.initial_velocity_max = 160.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 3.0
			particles.explosiveness = 0.35 # Spray fountain
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -250.0
			particles.angular_velocity_max = 250.0
		"blood":
			particles.color = Color(0.75, 0.0, 0.08, 1.0) # Dark crimson blood drops
			particles.texture = _create_diamond_texture(8)
			particles.amount = 30
			particles.spread = 130.0
			particles.gravity = Vector2(0, 120) # Fall downward like drops
			particles.initial_velocity_min = 60.0
			particles.initial_velocity_max = 110.0
			particles.scale_amount_min = 0.8
			particles.scale_amount_max = 2.2
			particles.explosiveness = 0.9
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -150.0
			particles.angular_velocity_max = 150.0
		"void":
			particles.color = Color(0.12, 0.05, 0.22, 1.0) # Very dark purple/black
			particles.texture = _create_diamond_texture(10)
			particles.amount = 40
			particles.spread = 360.0
			particles.gravity = Vector2(0, 0) # Dissolve in place
			particles.initial_velocity_min = 20.0
			particles.initial_velocity_max = 70.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 3.5
			particles.explosiveness = 0.8
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -100.0
			particles.angular_velocity_max = 100.0
		"dust":
			particles.color = Color(0.48, 0.38, 0.28, 1.0) # Dusty dirt brown
			particles.texture = _create_diamond_texture(10)
			particles.amount = 25
			particles.spread = 180.0
			particles.gravity = Vector2(0, -50) # Rise slowly
			particles.initial_velocity_min = 30.0
			particles.initial_velocity_max = 90.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 3.0
			particles.explosiveness = 0.85
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -120.0
			particles.angular_velocity_max = 120.0
		"leaf":
			particles.color = Color(0.2, 0.7, 0.3, 1.0) # Forest Green
			particles.texture = _create_leaf_texture(12)
			particles.amount = 25
			particles.spread = 120.0
			particles.gravity = Vector2(0, 80) # Float down slightly
			particles.initial_velocity_min = 40.0
			particles.initial_velocity_max = 90.0
			particles.scale_amount_min = 1.0
			particles.scale_amount_max = 2.5
			particles.explosiveness = 0.8
			particles.angle_min = -180.0
			particles.angle_max = 180.0
			particles.angular_velocity_min = -300.0
			particles.angular_velocity_max = 300.0
			
	add_child(particles)
	# Use a timer to clean up the particle node after it finishes
	get_tree().create_timer(duration + 0.5).timeout.connect(particles.queue_free)

# 血痕デカールを指定グリッドマスの床に描画する
# is_caster: プレイヤー側(true)はやや大きめ、着弾側(false)は標準サイズ
# persist: フロア遷移時に残り続けるかどうか
func _spawn_blood_decal(grid_pos: Vector2i, is_caster: bool, persist: bool = false) -> void:
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT:
		return

	var size = TILE_SIZE  # 32x32 ピクセル
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	# 背景は透明
	img.fill(Color(0, 0, 0, 0))

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# メインの血溜まり（中央に楕円状の大きな染み）
	var cx = size / 2.0
	var cy = size / 2.0
	var main_rx = rng.randf_range(7.0, 11.0) if is_caster else rng.randf_range(5.0, 9.0)
	var main_ry = rng.randf_range(5.0, 8.0)  if is_caster else rng.randf_range(3.5, 6.5)

	for px in range(size):
		for py in range(size):
			var dx = float(px) - cx
			var dy = float(py) - cy
			# 楕円判定
			if (dx * dx) / (main_rx * main_rx) + (dy * dy) / (main_ry * main_ry) <= 1.0:
				var alpha = rng.randf_range(0.75, 0.92)
				img.set_pixel(px, py, Color(0.55, 0.0, 0.05, alpha))

	# 飛び散った小さな血しぶき（3〜5 個）
	var splat_count = rng.randi_range(3, 5)
	for _i in range(splat_count):
		var sx = rng.randf_range(3.0, float(size) - 3.0)
		var sy = rng.randf_range(3.0, float(size) - 3.0)
		var sr = rng.randf_range(1.5, 3.5)
		for px in range(size):
			for py in range(size):
				var dx = float(px) - sx
				var dy = float(py) - sy
				if dx * dx + dy * dy <= sr * sr:
					var alpha = rng.randf_range(0.55, 0.80)
					img.set_pixel(px, py, Color(0.5, 0.0, 0.04, alpha))

	var decal = Sprite2D.new()
	decal.texture = ImageTexture.create_from_image(img)
	# タイルの中心に配置
	decal.position = Vector2(grid_pos) * TILE_SIZE + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	# ランダムな回転で毎回異なる形に見せる
	decal.rotation = rng.randf_range(0.0, TAU)
	# 床レイヤーの上・エンティティの下
	decal.z_index = 1
	# フロア遷移時に一括削除できるようグループに追加
	if persist:
		decal.add_to_group("persistent_blood_decals")
	else:
		decal.add_to_group("blood_decals")
	add_child(decal)

func shake_camera(intensity: float, duration: float):
	if not camera: return
	
	# Shaking camera offset is clean and stable since it doesn't affect camera global coordinates follow-path logic
	var tween = create_tween()
	var shake_count = max(1, int(duration / 0.05))
	var shake_duration = duration / shake_count
	
	for i in range(shake_count):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(camera, "offset", offset, shake_duration)
		
	# Smoothly return to center
	tween.tween_property(camera, "offset", Vector2.ZERO, shake_duration)



func reveal_map():
	# Reveal all tiles on the current floor (for mapping scroll)
	if _map_data.is_empty():
		return
	
	# Ensure visibility/exploration arrays are initialized
	if _visible_tiles.is_empty():
		_visible_tiles.resize(MAP_WIDTH)
		for x in range(MAP_WIDTH):
			_visible_tiles[x] = []
			_visible_tiles[x].resize(MAP_HEIGHT)
	if _explored_tiles.is_empty():
		_explored_tiles.resize(MAP_WIDTH)
		for x in range(MAP_WIDTH):
			_explored_tiles[x] = []
			_explored_tiles[x].resize(MAP_HEIGHT)
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			_visible_tiles[x][y] = true
			_explored_tiles[x][y] = true
	
	_update_entity_visibility()
	_draw_map()

# ... (rest of the file is similar)
# ... (rest of the file is similar)

# --- Hazard & Special Skill System ---

func create_hazard(type: String, world_pos: Vector2):
	var grid_pos = tile_map.local_to_map(world_pos)
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT: return
	
	_hazards[grid_pos] = {
		"type": type,
		"duration": 20, # Default duration
		"damage": 2 # Acid damage
	}
	_spawn_hazard_visual(grid_pos, type)

func _spawn_hazard_visual(grid_pos: Vector2i, type: String):
	var sprite = Sprite2D.new()
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.8, 0.2, 0.5) if type == "acid_puddle" else Color.RED)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.position = Vector2(grid_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	sprite.z_index = 0 # On floor
	sprite.add_to_group("hazard_visuals")
	sprite.set_meta("grid_pos", grid_pos)
	add_child(sprite)

func _process_hazards():
	var to_remove = []
	for grid_pos in _hazards.keys():
		var data = _hazards[grid_pos]
		data.duration -= 1
		
		# Apply effect
		for entity in get_tree().get_nodes_in_group("entities"):
			if not is_instance_valid(entity): continue
			var e_grid = tile_map.local_to_map(entity.position)
			if e_grid == grid_pos:
				if data.type == "acid_puddle":
					if entity.has_method("take_damage"):
						entity.take_damage(data.damage)
						if has_node("/root/LogUI"):
							var name = entity.name
							if "enemy_name" in entity: name = entity.enemy_name
							get_node("/root/LogUI").add_log("%s は酸で溶けている！ (%dダメ)" % [name, data.damage], Color.GREEN_YELLOW)
					
					# Also apply burn?
					if entity.has_method("apply_effect") and randf() < 0.3:
						entity.apply_effect("burn", {"duration": 3, "damage": 1})
		
		if data.duration <= 0:
			to_remove.append(grid_pos)
			
	for pos in to_remove:
		_hazards.erase(pos)
		_remove_hazard_visual(pos)

func _remove_hazard_visual(grid_pos: Vector2i):
	for node in get_tree().get_nodes_in_group("hazard_visuals"):
		# Check validity before accessing meta - though nodes in group should be valid
		if is_instance_valid(node) and node.has_meta("grid_pos") and node.get_meta("grid_pos") == grid_pos:
			node.queue_free()

func _execute_charge_skill(target_pos: Vector2):
	var _targeting_skill = target_manager.targeting_skill
	# Charge Logic: Move player along path until hit
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var line_points = _get_line_points(player_grid, target_grid)
	
	var stop_pos = player_grid
	var hit_entity = null
	var hit_wall = false
	
	var max_range = _targeting_skill.get("range", 4)
	
	for i in range(1, line_points.size()):
		if i > max_range: break
		
		var p = line_points[i]
		if p.x < 0 or p.x >= MAP_WIDTH or p.y < 0 or p.y >= MAP_HEIGHT: break
		
		if _map_data[p.x][p.y] == CellType.WALL or _map_data[p.x][p.y] == CellType.DOOR_CLOSED or _map_data[p.x][p.y] == CellType.DOOR_LOCKED:
			hit_wall = true
			break
			
		# Check Enemy
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var e_grid = tile_map.local_to_map(enemy.position)
			if e_grid == p:
				hit_entity = enemy
				break
		
		if hit_entity: break
		
		stop_pos = p # Valid step
	
	# Move Player
	var pixel_pos = Vector2(stop_pos) * TILE_SIZE
	
	# Animate Dash
	var tween = create_tween()
	tween.tween_property(player, "position", pixel_pos, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# Dust particles during dash
	_spawn_skill_particles(player.position, "web", 0.3) # Using web as dust
	
	await tween.finished
	
	# Impact particles if hit something
	if hit_entity or hit_wall:
		_spawn_skill_particles(pixel_pos + (Vector2(target_grid - stop_pos) * 16), "web", 0.4)
	
	# Update player internals (position already set by tween, but ensure snap?)
	player.position = pixel_pos
	_calculate_fov()
	_draw_map()
	
	# Apply Hit
	if hit_entity and is_instance_valid(hit_entity):
		var dmg = _calculate_skill_damage(_targeting_skill, hit_entity)
		hit_entity.take_damage(dmg, player)
		
		# Knockback logic (reuse from existing handle_attack knockback but forced)
		if _targeting_skill.get("knockback", false):
			var knock_dir = Vector2i(hit_entity.position/TILE_SIZE) - player_grid
			knock_dir = Vector2i(sign(knock_dir.x), sign(knock_dir.y))
			
			# Simple push 1-2 tiles
			var push_target = Vector2i(hit_entity.position/TILE_SIZE) + knock_dir * 2
			# Check walls... (Simplified for now - just visual push or instant pos update if valid)
			# Re-using _handle_attack logic would be best but it's hard to call specifically.
			# Let's just do a simple push.
			
			var final_push = Vector2i(hit_entity.position/TILE_SIZE)
			for k in range(1, 3):
				var next = Vector2i(hit_entity.position/TILE_SIZE) + knock_dir * k
				if not _is_grid_in_bounds(next):
					break
				if _map_data[next.x][next.y] != CellType.WALL and _map_data[next.x][next.y] != CellType.DOOR_CLOSED and _map_data[next.x][next.y] != CellType.DOOR_LOCKED:
					final_push = next
					if _map_data[next.x][next.y] == CellType.PIT:
						break
				else:
					break
			
			hit_entity.position = Vector2(final_push) * TILE_SIZE
			_resolve_forced_landing(hit_entity, final_push)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%s を体当たりで吹っ飛ばした！" % hit_entity.name, Color.ORANGE)

	# MP Cost
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(_targeting_skill, false)

	target_manager.cancel_targeting()
	await _end_player_turn()

func report_player_crime(crime_type: String, victim, perpetrator):
	if crime_type != "assault_neutral" or perpetrator != player:
		return

	var victim_grid = tile_map.local_to_map(victim.position)
	var witnesses = 0
	for witness in get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(witness) or witness == victim:
			continue
		if not witness.is_npc or witness.is_in_group("allies"):
			continue
		if witness.has_method("is_blinded") and witness.is_blinded():
			continue

		var witness_grid = tile_map.local_to_map(witness.position)
		var vision_range = 3 if _steam_tiles.has(witness_grid) else 8
		if Vector2(witness_grid).distance_to(Vector2(victim_grid)) > vision_range:
			continue
		if not _has_line_of_sight(witness_grid, victim_grid):
			continue

		witness.fear = clampi(witness.fear + 15, 0, 100)
		witness.affection = clampi(witness.affection - 10, -100, 100)
		if witness.affection <= -50 and witness.has_method("_make_hostile"):
			witness._make_hostile()
		witnesses += 1

	if witnesses > 0 and has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log(
			"%d人の中立NPCがあなたの暴行を目撃した。" % witnesses,
			Color(1.0, 0.55, 0.2)
		)

func _has_line_of_sight(from_grid: Vector2i, to_grid: Vector2i) -> bool:
	var line_points = _get_line_points(from_grid, to_grid)
	for p in line_points:
		if p == from_grid or p == to_grid: continue
		if _map_data[p.x][p.y] == CellType.WALL or _map_data[p.x][p.y] == CellType.DOOR_CLOSED or _map_data[p.x][p.y] == CellType.DOOR_LOCKED:
			return false
	return true

func _execute_enemy_skill(enemy, target_grid: Vector2i):
	var skill_id = enemy.skill_id
	# Basic skill lookup
	var skill_data = SkillDatabase.get_skill_by_id(skill_id)
	if skill_data.is_empty(): return
	
	enemy.skill_cooldown = enemy.max_skill_cooldown
	
	print(enemy.name, " uses ", skill_data.name)
	if has_node("/root/LogUI"):
		var e_name = enemy.name
		if "enemy_name" in enemy: e_name = enemy.enemy_name
		get_node("/root/LogUI").add_log("%s が %s を放った！" % [e_name, skill_data.name], Color.RED)

	# Projectile Animation
	var start_pos = enemy.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var end_pos = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	var projectile = Sprite2D.new()
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var color = Color.MAGENTA
	if skill_id == "web_shot": color = Color.WHITE
	elif skill_id == "fireball": color = Color.RED
	elif skill_id == "arrow_shot": color = Color.BROWN
	
	img.fill(rect_circle(8,8, 4, color)) 
	# Actually rect_circle returns color? helper needed or just fill
	img.fill(color)
	
	projectile.texture = ImageTexture.create_from_image(img)
	projectile.position = start_pos
	add_child(projectile)
	
	var tween = create_tween()
	tween.tween_property(projectile, "position", end_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished
	projectile.queue_free()
	
	# Particles
	var p_type = "fire"
	if skill_id == "web_shot": p_type = "web"
	elif skill_id == "lightning": p_type = "lightning"
	
	_spawn_skill_particles(end_pos, p_type, 0.4)
	
	# Apply Damage
	var dmg = skill_data.get("damage", 0)
	player.take_damage(dmg, enemy)
	
	# Apply Effect
	var effect = skill_data.get("effect", "")
	if effect == "paralyze":
		if player.has_method("apply_status_effect"):
			player.apply_status_effect("paralysis", 3)
	elif effect == "burn":
		# Player burn logic
		if player.has_method("take_damage"):
			player.take_damage(1) # Immediate burn dmg? Or status?
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("炎に包まれた！", Color.ORANGE)
	elif effect == "scramble":
		if player.equipment_component and player.equipment_component.equipment_data:
			if player.equipment_component.equipment_data.has_method("scramble"):
				var dropped = player.equipment_component.equipment_data.scramble()
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("インベントリをかき回された！", Color.VIOLET)
					
				# Spawn dropped items
				for item in dropped:
					var world_item = WorldItemScene.instantiate()
					world_item.position = player.position # Stack on player? Or adjacent?
					# Find loose spot
					var drop_pos = player.position
					var p_grid = tile_map.local_to_map(player.position)
					# Try to find empty spot around
					var found = false
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							var check_grid = p_grid + Vector2i(dx, dy)
							if check_grid.x >= 0 and check_grid.x < MAP_WIDTH and check_grid.y >= 0 and check_grid.y < MAP_HEIGHT:
								if _map_data[check_grid.x][check_grid.y] != CellType.WALL:
									drop_pos = Vector2(check_grid) * TILE_SIZE
									found = true
									break
						if found: break
					
					world_item.position = drop_pos
					world_item.set_item(item)
					world_item.add_to_group("items")
					world_item.add_to_group("entities")
					add_child(world_item)
					
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("%s が溢れて地面に落ちた！" % item.name, Color.RED)

func rect_circle(cx, cy, r, color) -> Color:
	return color

func _get_visible_enemies_check() -> Array:
	var visible_enemies = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _can_player_recognize_entity(enemy):
			visible_enemies.append(enemy)
	return visible_enemies

func _load_game():
	var start_time = Time.get_ticks_msec()
	print("[Load] Start load_game")
	var save_mgr = get_node_or_null("/root/SaveManager")
	if not save_mgr:
		print("[Load] Error: SaveManager not found")
		return
	var save_data = save_mgr.load_game()
	if save_data.is_empty():
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("ロードに失敗しました", Color.RED)
		print("[Load] Error: Save data is empty")
		return
	
	print("[Load] Clearing existing game state... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Clear existing game state
	get_tree().call_group("enemies", "queue_free")
	get_tree().call_group("npcs", "queue_free")
	get_tree().call_group("allies", "queue_free")
	get_tree().call_group("items", "queue_free")
	get_tree().call_group("torches", "queue_free")
	get_tree().call_group("hazard_visuals", "queue_free")
	
	# Wait one frame for queue_free cleanup to register
	await get_tree().process_frame
	print("[Load] Existing state cleared. (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	
	# Load world state
	var world_data = save_data.get("world", {})
	current_floor = int(world_data.get("current_floor", 1))
	_current_branch = int(world_data.get("current_branch", 0))
	_is_on_world_map = world_data.get("is_on_world_map", false)
	_world_map_data = _deserialize_world_map(world_data.get("world_map_data", []))
	_world_player_pos = Vector2i(
		world_data.get("world_player_pos_x", 0),
		world_data.get("world_player_pos_y", 0)
	)
	_starting_village_pos = Vector2i(
		world_data.get("starting_village_pos_x", 0),
		world_data.get("starting_village_pos_y", 0)
	)
	_dungeon_village_pos = Vector2i(
		world_data.get("dungeon_village_pos_x", 0),
		world_data.get("dungeon_village_pos_y", 0)
	)
	
	print("[Load] Deserializing map data... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Deserialize map
	_map_data = _deserialize_map(world_data.get("map_data", []), false)
	var compressed_explored = world_data.get("explored_tiles", [])
	if save_mgr and save_mgr.has_method("decompress_explored_tiles"):
		_explored_tiles = save_mgr.decompress_explored_tiles(compressed_explored, MAP_WIDTH, MAP_HEIGHT)
	else:
		_explored_tiles = _deserialize_map(compressed_explored, true)
	
	# Initialize visibility
	_visible_tiles = []
	_visible_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		_visible_tiles[x] = []
		_visible_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			_visible_tiles[x][y] = false
	
	print("[Load] Deserializing player stats... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Load player state
	var player_data = save_data.get("player", {})
	_deserialize_player(player, player_data)
	
	# Setup pathfinding with loaded map
	_setup_pathfinding()
	
	await get_tree().process_frame
	print("[Load] Spawning enemies... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	
	# Load enemies
	var enemies = world_data.get("enemies", [])
	for i in range(enemies.size()):
		_deserialize_enemy(enemies[i])
		if i % 10 == 0:
			await get_tree().process_frame

	print("[Load] Spawning NPCs... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Load NPCs
	var npcs = world_data.get("npcs", [])
	for i in range(npcs.size()):
		var npc_data = npcs[i]
		npc_data["is_npc"] = true
		_deserialize_enemy(npc_data)
		if i % 10 == 0:
			await get_tree().process_frame
	
	print("[Load] Spawning items on ground... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Load world items
	var items = world_data.get("items", [])
	for i in range(items.size()):
		_deserialize_world_item(items[i])
		if i % 15 == 0:
			await get_tree().process_frame

	print("[Load] Spawning torches... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Load torches
	for torch_data in world_data.get("torches", []):
		var torch = TorchScene.instantiate()
		torch.position = Vector2(torch_data.x, torch_data.y)
		torch.add_to_group("torches")
		torch.visible = false 
		add_child(torch)
	
	print("[Load] Loading hazards... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	# Load hazards
	_hazards.clear()
	for hazard_data in world_data.get("hazards", []):
		var grid_pos = Vector2i(int(hazard_data["x"]), int(hazard_data["y"]))
		_hazards[grid_pos] = {
			"type": hazard_data["type"],
			"duration": int(hazard_data["duration"]),
			"damage": int(hazard_data["damage"])
		}
		_spawn_hazard_visual(grid_pos, hazard_data["type"])
	
	# Load environmental effects
	_burning_grass.clear()
	for data in world_data.get("burning_grass", []):
		var pos = Vector2i(int(data["x"]), int(data["y"]))
		var entry = data.duplicate()
		entry.erase("x")
		entry.erase("y")
		_burning_grass[pos] = entry
	
	_frozen_tiles.clear()
	for data in world_data.get("frozen_tiles", []):
		var pos = Vector2i(int(data["x"]), int(data["y"]))
		var entry = data.duplicate()
		entry.erase("x")
		entry.erase("y")
		_frozen_tiles[pos] = entry
	
	_steam_tiles.clear()
	for data in world_data.get("steam_tiles", []):
		var pos = Vector2i(int(data["x"]), int(data["y"]))
		var entry = data.duplicate()
		entry.erase("x")
		entry.erase("y")
		_steam_tiles[pos] = entry
	
	await get_tree().process_frame
	print("[Load] Redrawing map and lighting... (Elapsed: %d ms)" % (Time.get_ticks_msec() - start_time))
	
	# Update visibility manager with loaded references
	if visibility_manager:
		visibility_manager.map_data = _map_data
		visibility_manager.visible_tiles = _visible_tiles
		visibility_manager.explored_tiles = _explored_tiles
		visibility_manager.burning_grass = _burning_grass
		visibility_manager.frozen_tiles = _frozen_tiles
		visibility_manager.steam_tiles = _steam_tiles
		visibility_manager.calculate_fov()
		visibility_manager.draw_map()
	
	# Update visuals
	_update_lighting_for_map_type()
	if _is_on_world_map:
		_draw_world_map()
	else:
		_calculate_fov()
		_draw_map()
	
	# Update UI
	if PlayerUi:
		if _is_on_world_map:
			PlayerUi.update_floor("ワールド")
		else:
			PlayerUi.update_floor(current_floor)
		PlayerUi.update_hp(player.hp, player.max_hp)
		PlayerUi.update_mp(player.mp, player.max_mp)
		PlayerUi.update_level(player.level)
		if ("ammo_inventory" in player and player.ammo_inventory != null):
			PlayerUi.update_ammo(player.ammo_inventory)
	
	# Force camera update
	camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	camera.reset_smoothing()
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("ゲームをロードしました", Color.CYAN)
	
	_current_game_state = TurnPhase.PLAYER_TURN
	print("[Load] Load complete! (Total Time: %d ms)" % (Time.get_ticks_msec() - start_time))

func _deserialize_map(map_array: Array, is_bool_map: bool = false) -> Array:
	var map = []
	map.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		map[x] = []
		map[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			if x < map_array.size() and y < map_array[x].size():
				var val = map_array[x][y]
				if is_bool_map:
					# Force to boolean
					if val is bool:
						map[x][y] = val
					else:
						map[x][y] = bool(val)
				else:
					# Force to integer (enum)
					map[x][y] = int(val)
			else:
				# Default values if missing
				if is_bool_map:
					map[x][y] = false
				else:
					map[x][y] = CellType.WALL
	return map

func _deserialize_player(p, data: Dictionary):
	if "is_moving" in p:
		p.is_moving = false
	# 0. Load Class
	var gs = p.get_node_or_null("/root/GameState")
	if gs and data.has("player_class"):
		gs.player_class = data["player_class"]
		if p.has_method("_load_class_sprite"):
			p._load_class_sprite()
			
	# 1. Basic Stats
	p.strength = data.get("strength", 1)
	p.dexterity = data.get("dexterity", 1)
	p.intelligence = data.get("intelligence", 1)
	p.level = data.get("level", 1)
	p.exp = data.get("exp", 0)
	p.exp_to_next_level = data.get("exp_to_next_level", 10)
	p.gold = data.get("gold", 0)
	p.hunger = data.get("hunger", 100)
	p.max_hunger = data.get("max_hunger", 100)
	p.position = Vector2(data.get("position_x", 0), data.get("position_y", 0))
	p.level_hp_bonus = data.get("level_hp_bonus", 0)
	p.level_mp_bonus = data.get("level_mp_bonus", 0)
	p.initial_hp_bonus = data.get("initial_hp_bonus", 0)
	p.initial_mp_bonus = data.get("initial_mp_bonus", 0)
	p._base_can_swim = data.get("base_can_swim", false)
	p.turn_counter = data.get("turn_counter", 0)
	p.turns_since_damage = data.get("turns_since_damage", 0)
	p.status_effects = data.get("status_effects", {}).duplicate(true)
	p.skill_cooldowns = data.get("skill_cooldowns", {}).duplicate(true)
	p.ranged_weapon_cooldown = data.get("ranged_weapon_cooldown", 0)
	p.bonus_action_available = data.get("bonus_action_available", false)
	p.ranged_weapon_shots_fired = data.get("ranged_weapon_shots_fired", 0)
	
	# 2. Skills (Typed Array)
	p.base_known_skills.clear()
	var saved_skills = data.get("base_known_skills", [])
	for skill_id in saved_skills:
		p.base_known_skills.append(skill_id)
	
	# 3. Equipment (Load this BEFORE setting HP/MP to ensure max caps are up to date)
	if p.equipment_component:
		var equipment_data = data.get("equipment", {})
		var bag_data = data.get("bag", {})
		
		# Clear existing
		p.equipment_component.equipment_data.clear()
		p.equipment_component.bag_data.clear()
		
		# Load equipment items
		for item_dict in equipment_data.get("items", []):
			var item = _deserialize_item(item_dict)
			if item:
				p.equipment_component.equipment_data.add_item(item)
		
		# Load bag items
		for item_dict in bag_data.get("items", []):
			var item = _deserialize_item(item_dict)
			if item:
				p.equipment_component.bag_data.add_item(item)
		for item_dict in bag_data.get("items", []):
			var item = _deserialize_item(item_dict)
			if item:
				p.equipment_component.bag_data.add_item(item)
	
	# 4. HP/MP (Set LAST so intermediate equipment changes don't cap them incorrectly)
	p.max_hp = data.get("max_hp", 10)
	p.hp = data.get("hp", p.max_hp)
	p.max_mp = data.get("max_mp", 5)
	p.mp = data.get("mp", p.max_mp)
	
	if p.has_method("_update_ui_weapon"):
		p._update_ui_weapon()

func _deserialize_item(item_dict: Dictionary) -> BaseItem:
	# Get shape from dict and convert to Vector2i array
	var raw_shape = item_dict.get("shape", [])
	var shape: Array[Vector2i] = []
	var width = 1
	var height = 1
	
	if raw_shape is Array:
		var max_x = 0
		var max_y = 0
		for cell in raw_shape:
			var v = Vector2i(-1, -1)
			if cell is Vector2i:
				v = cell
			elif cell is Dictionary and cell.has("x") and cell.has("y"):
				v = Vector2i(int(cell.x), int(cell.y))
			elif cell is Array and cell.size() >= 2:
				v = Vector2i(int(cell[0]), int(cell[1]))
			
			if v != Vector2i(-1, -1):
				shape.append(v)
				max_x = max(max_x, v.x)
				max_y = max(max_y, v.y)
				
		width = max_x + 1
		height = max_y + 1
	
	var item = BaseItem.new(
		item_dict.get("id", ""),
		item_dict.get("name", ""),
		null,
		item_dict.get("equipment_type", item_dict.get("type", -1)),  # Support both old and new format
		width,
		height,
		item_dict.get("description", ""),
		shape
	)
	
	item.attack = item_dict.get("attack", 0)
	item.defense = item_dict.get("defense", 0)
	item.grid_position = Vector2i(item_dict.get("grid_x", -1), item_dict.get("grid_y", -1))
	item.strength = item_dict.get("strength", 0)
	item.dexterity = item_dict.get("dexterity", 0)
	item.intelligence = item_dict.get("intelligence", 0)
	item.max_hp = item_dict.get("max_hp", 0)
	item.max_mp = item_dict.get("max_mp", 0)
	item.value = item_dict.get("value", 0)
	item.rarity = item_dict.get("rarity", 0)
	item.prefix_name = item_dict.get("prefix_name", "")
	item.suffix_name = item_dict.get("suffix_name", "")
	item.generated_level = item_dict.get("generated_level", 0)
	item.effects = item_dict.get("effects", {}).duplicate(true)
	
	# Proper handling for typed array Arary[String]
	item.granted_skills.clear()
	var skills = item_dict.get("granted_skills", [])
	for s in skills:
		item.granted_skills.append(str(s))
	
	return item

func _deserialize_enemy(enemy_data: Dictionary):
	var saved_is_npc = enemy_data.get("is_npc", false) == true
	var enemy_id = str(enemy_data.get("enemy_id", enemy_data.get("enemy_name", "")))
	if enemy_id == "":
		enemy_id = "NPC" if saved_is_npc else "雑魚虫"
	
	# 全エネミーに共通のシーンを使用（ステータスはDBから読み込む）
	var enemy_scene = EnemyScene
	var enemy = enemy_scene.instantiate()
	
	# Restore Static Data from Database first (Sprites, Colors, etc.)
	var def = EnemyDatabase.get_enemy_def(enemy_id)
	if not def.is_empty():
		enemy.enemy_name = def.name
		enemy.enemy_id = def.name
		
		# Base Stats (Overwritten by save data later if present)
		enemy.max_hp = int(def.hp)
		enemy.attack_power = int(def.atk)
		enemy.defense = int(def.get("def", 0))
		enemy.exp_reward = def.get("exp", 2)
		if "weak" in def: enemy.weaknesses = def.weak
		if "resist" in def: enemy.resistances = def.resist
		if "fire_immune" in def: enemy.fire_immune = def.fire_immune
		if "grass_ignition_chance" in def: enemy.grass_ignition_chance = def.grass_ignition_chance
		
		if "color" in def: enemy.base_color = def.color
		if "swim" in def: enemy.can_swim = def.swim
		if "knockback" in def: enemy.has_knockback = def.knockback
		if "loot" in def: enemy.loot_table = def.loot
		if "sprite" in def: enemy.sprite_path = def.sprite
		else: enemy.sprite_path = ""
		
		if "skill" in def:
			enemy.skill_id = def.skill
			enemy.attack_range = def.get("range", 1)
			enemy.max_skill_cooldown = def.get("cooldown", 5)
			
		if "on_hit" in def: enemy.on_hit_effects = def.on_hit
		if "penetration" in def: enemy.penetration_rate = def.penetration
		if "intelligence" in def: enemy.intelligence = def.intelligence
		if "ai" in def: enemy.ai_type = def.ai
	else:
		enemy.enemy_name = str(enemy_data.get("enemy_name", "NPC" if saved_is_npc else "雑魚虫"))
		enemy.enemy_id = enemy_id
		if saved_is_npc:
			enemy.sprite_path = ""
	
	# Restore sprite_path from save data if present
	if "sprite_path" in enemy_data and enemy_data["sprite_path"] != "":
		enemy.sprite_path = enemy_data["sprite_path"]
	
	# Restore Dynamic Data from Save
	enemy.position = Vector2(enemy_data.get("position_x", 0), enemy_data.get("position_y", 0))
	
	if "hp" in enemy_data: enemy.hp = enemy_data["hp"]
	if "max_hp" in enemy_data: enemy.max_hp = enemy_data["max_hp"] # Persist max hp changes
	if "fear" in enemy_data: enemy.fear = int(enemy_data["fear"])
	if "affection" in enemy_data: enemy.affection = int(enemy_data["affection"])
	if "is_hostile_to_player_only" in enemy_data:
		enemy.is_hostile_to_player_only = bool(enemy_data["is_hostile_to_player_only"])
	if "status_effects" in enemy_data: enemy.status_effects = enemy_data["status_effects"].duplicate(true)
	if "skill_cooldown" in enemy_data: enemy.skill_cooldown = enemy_data["skill_cooldown"]
	if "skill_id" in enemy_data: enemy.skill_id = str(enemy_data["skill_id"])
	if "attack_range" in enemy_data: enemy.attack_range = int(enemy_data["attack_range"])
	if "max_skill_cooldown" in enemy_data:
		enemy.max_skill_cooldown = int(enemy_data["max_skill_cooldown"])
	
	enemy.is_npc = saved_is_npc
	if saved_is_npc:
		enemy.add_to_group("npcs")
	else:
		enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	add_child(enemy)
	if enemy_data.get("is_ally", false) == true:
		enemy.add_to_group("allies")
		if enemy.has_method("set_ally") and player:
			enemy.set_ally(player)
	# Trigger visibility update immediately? Handled by next frame FOV calc.

func _deserialize_world_item(item_data: Dictionary):
	var world_item = WorldItemScene.instantiate()
	world_item.position = Vector2(item_data.get("position_x", 0), item_data.get("position_y", 0))
	
	var item = _deserialize_item(item_data.get("item", {}))
	world_item.set_item(item)
	
	world_item.add_to_group("items")
	world_item.add_to_group("entities")
	add_child(world_item)

func get_item_at_player_position():
	"""Check if there's already an item at player's current position"""
	var player_grid = tile_map.local_to_map(player.position)
	for world_item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(world_item) or world_item.is_queued_for_deletion():
			continue
		if not (world_item is Node2D):
			continue
		var item_grid = tile_map.local_to_map(world_item.position)
		if item_grid == player_grid:
			return world_item
	return null

func get_item_at_grid(grid_pos: Vector2i) -> Node2D:
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			continue
		if not (item is Node2D):
			continue
		var item_pos = tile_map.local_to_map(item.position)
		if item_pos == grid_pos:
			return item
	return null

func find_nearest_empty_cell(start_grid: Vector2i, max_radius: int = 3) -> Vector2i:
	# 1. Check start pos
	if _is_grid_valid_for_item(start_grid) and get_item_at_grid(start_grid) == null:
		return start_grid
		
	# 2. Spiral search
	for r in range(1, max_radius + 1):
		for x in range(start_grid.x - r, start_grid.x + r + 1):
			for y in range(start_grid.y - r, start_grid.y + r + 1):
				# Perimeter check only
				if abs(x - start_grid.x) != r and abs(y - start_grid.y) != r:
					continue
					
				var check_pos = Vector2i(x, y)
				if _is_grid_valid_for_item(check_pos) and get_item_at_grid(check_pos) == null:
					return check_pos
						
	return start_grid # Fallback

func _is_grid_valid_for_item(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
		return false
	var cell = _map_data[pos.x][pos.y]
	# Allow Floor, Grass, Stairs (though stairs might be annoying, better than losing item)
	return cell != CellType.WALL and cell != CellType.WATER and cell != CellType.LAVA and cell != CellType.TREE and cell != CellType.TREE_FRUIT and cell != CellType.ROCK

func spawn_world_item(item: BaseItem, world_pos: Vector2):
	var grid_pos = tile_map.local_to_map(world_pos)
	var target_grid = find_nearest_empty_cell(grid_pos)
	
	var world_item = WorldItemScene.instantiate()
	world_item.position = Vector2(target_grid) * TILE_SIZE
	world_item.set_item(item)
	world_item.add_to_group("items")
	world_item.add_to_group("entities")
	add_child(world_item)

func place_item_at_player(item: BaseItem):
	"""Place an item at the player's current position (with smart placement)"""
	if not player: return
	spawn_world_item(item, player.position)
	print("Placed item at player position: ", item.name)

func _electrify_water(start_pos: Vector2i, damage_val: int = -1):
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
		if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
			continue
		
		# Check if water
		if _map_data[pos.x][pos.y] != CellType.WATER:
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
		flash.size = Vector2(TILE_SIZE, TILE_SIZE)
		flash.position = Vector2(tile_pos) * TILE_SIZE
		add_child(flash)
		
		var flash_tween = create_tween()
		flash_tween.tween_property(flash, "modulate:a", 0.0, 0.5)
		flash_tween.tween_callback(flash.queue_free)
	
	# 1. Collect all entities currently on electrified water
	var entities_on_water = []
	for entity in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity):
			var entity_grid = tile_map.local_to_map(entity.position)
			if electrified_tiles.has(entity_grid):
				entities_on_water.append(entity)
	
	# 2. Damage each valid entity once
	var base_damage = damage_val
	if base_damage == -1:
		if target_manager and target_manager.targeting_skill:
			base_damage = target_manager.targeting_skill.get("damage", 6)
		else:
			base_damage = 6
			
	for entity in entities_on_water:
		if is_instance_valid(entity) and entity.has_method("take_damage"):
			entity.take_damage(base_damage, null, ["electric"])
			
			var entity_name = entity.name
			if "enemy_name" in entity:
				entity_name = entity.enemy_name
			elif entity == player:
				entity_name = "自分"
			
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("⚡ %s に感電ダメージ %d！" % [entity_name, base_damage], Color.YELLOW)
	
	# Log the chain reaction
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("⚡ 電気が水を伝って %d マスに広がった！" % electrified_tiles.size(), Color(1.0, 1.0, 0.5))

func _ignite_grass(pos: Vector2i):
	"""Ignite a grass tile, starting a fire that can spread"""
	if _burning_grass.has(pos):
		return  # Already burning
	
	_burning_grass[pos] = {
		"turns_remaining": 5,  # Grass burns for 5 turns
		"spread_chance": 50    # 50% chance to spread each turn
	}
	
	# Visual effect for initial ignition
	_update_burning_grass_visual(pos)
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("🔥 草むらが燃え始めた！", Color.ORANGE_RED)

func _process_burning_grass():
	"""Process burning grass each turn: spread fire and damage entities"""
	if _burning_grass.is_empty():
		return
	
	var to_remove = []
	var new_fires = []
	
	# 1. Collect all entities on burning tiles first to avoid issues with freed nodes in nested loops
	var entities_on_fire = {} # entity: total_damage
	for pos in _burning_grass.keys():
		for entity in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(entity):
				var entity_grid = tile_map.local_to_map(entity.position)
				if entity_grid == pos:
					entities_on_fire[entity] = 2 # Fire damage
	
	# 2. Apply damage to each entity once
	for entity in entities_on_fire.keys():
		if is_instance_valid(entity) and entity.has_method("take_damage"):
			var fire_dmg = entities_on_fire[entity]
			if _is_fire_immune(entity):
				continue
			entity.take_damage(fire_dmg, null, ["fire"])
			
			var entity_name = entity.name
			if "enemy_name" in entity:
				entity_name = entity.enemy_name
			elif entity == player:
				entity_name = "自分"
			
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("🔥 %s が炎上ダメージを受けた！ (%d)" % [entity_name, fire_dmg], Color.ORANGE_RED)
	
	# 3. Spread fire and manage turns
	for pos in _burning_grass.keys():
		var fire_data = _burning_grass[pos]
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
				if adj_pos.x < 0 or adj_pos.x >= MAP_WIDTH or adj_pos.y < 0 or adj_pos.y >= MAP_HEIGHT:
					continue
				
				# Check if adjacent tile is grass and not already burning
				if _map_data[adj_pos.x][adj_pos.y] == CellType.GRASS and not _burning_grass.has(adj_pos):
					if randi() % 100 < spread_chance:
						new_fires.append(adj_pos)
		
		# Remove if burned out
		if fire_data.turns_remaining <= 0:
			to_remove.append(pos)
			# Convert to floor
			_map_data[pos.x][pos.y] = CellType.FLOOR
	
	# Remove burned out fires
	for pos in to_remove:
		_burning_grass.erase(pos)
	
	# Add new fires
	for pos in new_fires:
		_ignite_grass(pos)
	
	# Update visuals
	_draw_map()

func _is_fire_immune(entity) -> bool:
	return is_instance_valid(entity) and "fire_immune" in entity and entity.fire_immune

func _try_enemy_grass_ignition(enemy, grid_pos: Vector2i):
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT:
		return
	if _map_data[grid_pos.x][grid_pos.y] != CellType.GRASS or _burning_grass.has(grid_pos):
		return
	if randf() <= enemy.grass_ignition_chance:
		_ignite_grass(grid_pos)

func _flame_scatter_has_grass(enemy, radius: int = 2) -> bool:
	var origin = tile_map.local_to_map(enemy.position)
	for x in range(origin.x - radius, origin.x + radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			var pos = Vector2i(x, y)
			if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
				continue
			if _map_data[pos.x][pos.y] == CellType.GRASS and not _burning_grass.has(pos):
				return true
	return false

func _get_grass_preferred_direction(enemy, desired_dir: Vector2) -> Vector2:
	var origin = tile_map.local_to_map(enemy.position)
	var candidates = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var dir = Vector2(dx, dy)
			var pos = origin + Vector2i(dir)
			if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
				continue
			if _map_data[pos.x][pos.y] != CellType.GRASS:
				continue
			if desired_dir != Vector2.ZERO and dir.dot(desired_dir.normalized()) < -0.1:
				continue
			candidates.append(dir)
	if candidates.is_empty():
		return Vector2.ZERO
	candidates.shuffle()
	return candidates[0]

func _execute_enemy_fireball(enemy, target_grid_pos: Vector2i):
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("%s は小さな火球を放った！" % enemy.enemy_name, Color.ORANGE_RED)
	await _handle_ranged_attack(enemy, target_grid_pos, max(1, enemy.attack_power), "fire")

func _execute_flame_scatter(enemy):
	var origin = tile_map.local_to_map(enemy.position)
	var ignited = 0
	var melted = 0
	var radius = 2
	for x in range(origin.x - radius, origin.x + radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			var pos = Vector2i(x, y)
			if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
				continue
			if Vector2(origin).distance_to(Vector2(pos)) > radius:
				continue
			if _map_data[pos.x][pos.y] == CellType.GRASS and not _burning_grass.has(pos):
				_ignite_grass(pos)
				if _burning_grass.has(pos):
					_burning_grass[pos].spread_chance = 25
				ignited += 1
			# Melt ice
			if _map_data[pos.x][pos.y] == CellType.ICE and _frozen_tiles.has(pos):
				_map_data[pos.x][pos.y] = CellType.WATER
				_frozen_tiles.erase(pos)
				melted += 1
	if ignited > 0 or melted > 0:
		_create_steam(origin)
		if has_node("/root/LogUI"):
			if ignited > 0:
				get_node("/root/LogUI").add_log("%s は炎の種をまき散らした！" % enemy.enemy_name, Color.ORANGE_RED)
			if melted > 0:
				get_node("/root/LogUI").add_log("🔥 氷が溶けた！", Color.ORANGE)
		_setup_pathfinding()
		_calculate_fov()
		_draw_map()

func _update_burning_grass_visual(pos: Vector2i):
	"""Update tile color to show it's burning - called during _draw_map"""
	# This will be handled in _draw_map by checking _burning_grass
	pass

func _create_steam(pos: Vector2i):
	"""Fire hitting water creates steam that obscures vision - gas-like random spread"""
	# Place steam at origin first (always)
	if pos.x >= 0 and pos.x < MAP_WIDTH and pos.y >= 0 and pos.y < MAP_HEIGHT:
		_steam_tiles[pos] = {
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
				if npos.x < 0 or npos.x >= MAP_WIDTH or npos.y < 0 or npos.y >= MAP_HEIGHT:
					continue
				if visited.has(npos):
					continue
				# Cannot pass through walls
				if _map_data[npos.x][npos.y] == CellType.WALL:
					continue
				visited[npos] = true
				# Spread probability decreases with distance
				var spread_chance = 0.85 - _wave * 0.15
				if randf() < spread_chance:
					var density = max(1, 3 - _wave)
					var turns = 6 + randi() % 3 - _wave
					if not _steam_tiles.has(npos) or _steam_tiles[npos].turns_remaining < turns:
						_steam_tiles[npos] = {
							"turns_remaining": max(2, turns),
							"density": density
						}
					next_frontier.append(npos)
		frontier = next_frontier
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("💨 蒸気が立ち込めた！", Color.LIGHT_GRAY)

func _freeze_water(pos: Vector2i, freeze_adjacent: bool = true):
	"""Ice hitting water freezes it, creating slippery floor"""
	if _map_data[pos.x][pos.y] != CellType.WATER:
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
			if adj_pos.x < 0 or adj_pos.x >= MAP_WIDTH or adj_pos.y < 0 or adj_pos.y >= MAP_HEIGHT:
				continue
			if _map_data[adj_pos.x][adj_pos.y] == CellType.WATER:
				tiles_to_freeze.append(adj_pos)
	
	for freeze_pos in tiles_to_freeze:
		# Change cell type from WATER to ICE
		_map_data[freeze_pos.x][freeze_pos.y] = CellType.ICE
		_frozen_tiles[freeze_pos] = {
			"turns_remaining": 4  # Ice lasts 4 turns
		}
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("❄️ 水が凍結した！ (%d タイル)" % tiles_to_freeze.size(), Color.CYAN)

func _process_steam():
	"""Process steam tiles each turn - gas-like random spreading"""
	if _steam_tiles.is_empty():
		_steam_exposure.clear()
		return
	
	var to_remove = []
	var new_steam: Dictionary = {}
	
	for pos in _steam_tiles.keys():
		var data = _steam_tiles[pos]
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
			if npos.x < 0 or npos.x >= MAP_WIDTH or npos.y < 0 or npos.y >= MAP_HEIGHT:
				continue
			# Steam cannot pass through walls
			if _map_data[npos.x][npos.y] == CellType.WALL:
				continue
			# Skip if already has strong steam
			if _steam_tiles.has(npos) and _steam_tiles[npos].turns_remaining >= data.turns_remaining:
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
		_steam_tiles.erase(pos)
	
	# Merge newly spread steam
	for pos in new_steam.keys():
		if not _steam_tiles.has(pos):
			_steam_tiles[pos] = new_steam[pos]
		else:
			# Refresh if new steam is stronger
			if new_steam[pos].turns_remaining > _steam_tiles[pos].turns_remaining:
				_steam_tiles[pos] = new_steam[pos]
	
	var current_exposure = {}
	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity):
			continue
		var entity_grid = tile_map.local_to_map(entity.position)
		if not _steam_tiles.has(entity_grid):
			continue
		
		var entity_id = entity.get_instance_id()
		var turns_in_steam = int(_steam_exposure.get(entity_id, 0)) + 1
		current_exposure[entity_id] = turns_in_steam
		
		if turns_in_steam >= 2 and entity.has_method("take_damage"):
			entity.take_damage(1, null, ["steam"])
			if has_node("/root/LogUI"):
				var entity_name = entity.name
				if "enemy_name" in entity:
					entity_name = entity.enemy_name
				elif entity == player:
					entity_name = "Player"
				get_node("/root/LogUI").add_log("%s is choking in the steam!" % entity_name, Color.LIGHT_GRAY)
	_steam_exposure = current_exposure
	
	# Recalculate FOV if steam changed
	_calculate_fov()
	_draw_map()


func _process_frozen_tiles():
	"""Process frozen tiles - ice no longer melts automatically, only from fire/heat effects"""
	# Ice no longer melts automatically each turn
	# It only melts when affected by fire or other heat-based effects
	pass

# ------------------------------------------------------------------------------
# New Skills Implementation
# ------------------------------------------------------------------------------

func _execute_enemy_skill_v2(enemy, target_grid_pos: Vector2i):
	var skill_id = enemy.skill_id
	var log_ui = get_node_or_null("/root/LogUI")
	var damage = enemy.attack_power
	
	if skill_id == "fireball":
		if log_ui:
			log_ui.add_log("%s は火球を放った！" % enemy.enemy_name, Color.ORANGE_RED)
		await _handle_ranged_attack(enemy, target_grid_pos, damage, "fire")

	elif skill_id == "lightning":
		if "intelligence" in enemy:
			damage += enemy.intelligence

		if log_ui: log_ui.add_log("%s は雷を呼び寄せた！" % enemy.enemy_name, Color.YELLOW)
		
		# Visual effect at target location
		var target_world_pos = Vector2(target_grid_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		_spawn_skill_particles(target_world_pos, "lightning", 0.6)
		
		var initial_target = null
		var entities = get_tree().get_nodes_in_group("entities")
		print("DEBUG: Executing Lightning. Entities in group: ", entities.size())
		
		for ent in entities:
			# Fix: Use center of sprite to avoid floating point boundary issues
			var ent_pos = tile_map.local_to_map(ent.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
			if ent_pos == target_grid_pos:
				initial_target = ent
				break
				
		if initial_target:
			print("DEBUG: Initial target hit: ", initial_target.name)
			await _apply_chain_lightning(enemy, initial_target, damage, 4, [])
		else:
			print("DEBUG: No target found at ", target_grid_pos)
			
	elif skill_id == "arrow_shot":
		if log_ui: log_ui.add_log("%s は矢を放った！" % enemy.enemy_name, Color.WHITE)
		await _handle_ranged_attack(enemy, target_grid_pos, damage, "arrow")

	elif skill_id == "web_shot":
		if log_ui: log_ui.add_log("%s は糸を吐いた！" % enemy.enemy_name, Color.WHITE)
		await _handle_ranged_attack(enemy, target_grid_pos, damage, "web")
		
	elif skill_id == "paralyze_touch":
		await _handle_ranged_attack(enemy, target_grid_pos, damage, "paralyze")

	elif skill_id == "freeze":
		if log_ui: log_ui.add_log("%s は凍結魔法を唱えた！" % enemy.enemy_name, Color.CYAN)
		await _execute_freeze_skill(enemy, target_grid_pos)

	elif skill_id == "scramble":
		# Check if target is player
		var player_grid = tile_map.local_to_map(player.position)
		if target_grid_pos != player_grid:
			# Target is not player, don't affect player's inventory
			if log_ui: log_ui.add_log("%s は何かを企んでいる..." % enemy.enemy_name, Color.VIOLET)
			return
		
		if log_ui: log_ui.add_log("%s はニヤリと笑い、インベントリをかき回した！" % enemy.enemy_name, Color.VIOLET)
		
		# Visual cue on enemy
		var tween = create_tween()
		tween.tween_property(enemy, "scale", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(enemy, "scale", Vector2(1.0, 1.0), 0.1)
		
		# Visual cue on player (Confetti/Confusion particles)
		var particles = CPUParticles2D.new()
		particles.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		particles.amount = 20
		particles.lifetime = 1.0
		particles.explosiveness = 0.9
		particles.direction = Vector2(0, -1)
		particles.spread = 180.0
		particles.initial_velocity_min = 60.0
		particles.initial_velocity_max = 120.0
		particles.scale_amount_min = 3.0
		particles.scale_amount_max = 6.0
		particles.color = Color.VIOLET
		particles.one_shot = true
		particles.emitting = true
		add_child(particles)
		var timer = get_tree().create_timer(2.0)
		timer.timeout.connect(particles.queue_free)
		
		if player.equipment_component and player.equipment_component.equipment_data:
			var dropped = player.equipment_component.equipment_data.scramble()
			
			if not dropped.is_empty():
				if log_ui: log_ui.add_log("反動でアイテムが溢れてしまった！", Color.RED)
				var p_grid = tile_map.local_to_map(player.position)
				
				for item in dropped:
					var world_item = WorldItemScene.instantiate()
					var drop_pos = player.position
					var placed = false
					
					# Find a valid spot around player (including under player)
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							var neighbor = p_grid + Vector2i(dx, dy)
							if neighbor.x >= 0 and neighbor.x < MAP_WIDTH and neighbor.y >= 0 and neighbor.y < MAP_HEIGHT:
								if _map_data[neighbor.x][neighbor.y] != CellType.WALL:
									drop_pos = Vector2(neighbor) * TILE_SIZE
									placed = true
									break 
						if placed: break
					
					world_item.position = drop_pos
					world_item.set_item(item)
					world_item.add_to_group("items")
					world_item.add_to_group("entities")
					add_child(world_item)

	if is_instance_valid(enemy):
		enemy.skill_cooldown = enemy.max_skill_cooldown

func _execute_freeze_skill(enemy, target_grid_pos: Vector2i):
	var freeze_skill_data = SkillDatabase.get_skill_by_id("freeze")
	_apply_freeze_area(enemy, target_grid_pos, freeze_skill_data)
	return

	var log_ui = get_node_or_null("/root/LogUI")
	var skill_data = SkillDatabase.get_skill_by_id("freeze")
	var radius = skill_data.get("radius", 1)
	
	var tiles_to_freeze = []
	
	# Get all tiles in the radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = target_grid_pos + Vector2i(dx, dy)
			if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
				continue
			if _map_data[pos.x][pos.y] == CellType.WATER:
				tiles_to_freeze.append(pos)
	
	# Freeze the water tiles
	for freeze_pos in tiles_to_freeze:
		_map_data[freeze_pos.x][freeze_pos.y] = CellType.ICE
		_frozen_tiles[freeze_pos] = {
			"permanent": true  # Ice no longer melts automatically
		}
	
	if tiles_to_freeze.size() > 0:
		if log_ui:
			log_ui.add_log("❄️ 水が凍結した！ (%d タイル)" % tiles_to_freeze.size(), Color.CYAN)
		
		# Visual effect - ice particles
		var particles = CPUParticles2D.new()
		particles.position = Vector2(target_grid_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		particles.amount = 30
		particles.lifetime = 1.5
		particles.explosiveness = 0.8
		particles.direction = Vector2(0, -1)
		particles.spread = 360.0
		particles.initial_velocity_min = 40.0
		particles.initial_velocity_max = 80.0
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 4.0
		particles.color = Color(0.8, 0.9, 1.0)
		particles.one_shot = true
		particles.emitting = true
		add_child(particles)
		var timer = get_tree().create_timer(2.0)
		timer.timeout.connect(particles.queue_free)
		
		# Update map and pathfinding
		_setup_pathfinding()
		_calculate_fov()
		_draw_map()
	else:
		if log_ui:
			log_ui.add_log("凍結できる水がなかった。", Color(0.6, 0.6, 0.6))

func _execute_freeze_skill_player(target_grid: Vector2i):
	var freeze_skill_data = SkillDatabase.get_skill_by_id("freeze")
	_apply_freeze_area(player, target_grid, freeze_skill_data)
	
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(freeze_skill_data, false)
	target_manager.cancel_targeting()
	await _end_player_turn()
	return

	var log_ui = get_node_or_null("/root/LogUI")
	var skill_data = SkillDatabase.get_skill_by_id("freeze")
	var radius = skill_data.get("radius", 1)
	
	var tiles_to_freeze = []
	
	# Get all tiles in the radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = target_grid + Vector2i(dx, dy)
			if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
				continue
			if _map_data[pos.x][pos.y] == CellType.WATER:
				tiles_to_freeze.append(pos)
	
	# Freeze the water tiles
	for freeze_pos in tiles_to_freeze:
		_map_data[freeze_pos.x][freeze_pos.y] = CellType.ICE
		_frozen_tiles[freeze_pos] = {
			"permanent": true  # Ice no longer melts automatically
		}
	
	if tiles_to_freeze.size() > 0:
		if log_ui:
			log_ui.add_log("❄️ 水が凍結した！ (%d タイル)" % tiles_to_freeze.size(), Color.CYAN)
		
		# Visual effect - ice particles
		var target_center = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		var particles = CPUParticles2D.new()
		particles.position = target_center
		particles.amount = 30
		particles.lifetime = 1.5
		particles.explosiveness = 0.8
		particles.direction = Vector2(0, -1)
		particles.spread = 360.0
		particles.initial_velocity_min = 40.0
		particles.initial_velocity_max = 80.0
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 4.0
		particles.color = Color(0.8, 0.9, 1.0)
		particles.one_shot = true
		particles.emitting = true
		add_child(particles)
		var timer = get_tree().create_timer(2.0)
		timer.timeout.connect(particles.queue_free)
		
		# Update map and pathfinding
		_setup_pathfinding()
		_calculate_fov()
		_draw_map()
	else:
		if log_ui:
			log_ui.add_log("凍結できる水がなかった。", Color(0.6, 0.6, 0.6))
	
	# Consume MP & End
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(skill_data, false)
	target_manager.cancel_targeting()
	await _end_player_turn()

func _apply_freeze_area(caster, target_grid: Vector2i, skill_data: Dictionary):
	var log_ui = get_node_or_null("/root/LogUI")
	var radius = skill_data.get("radius", 1)
	var damage = skill_data.get("damage", 0)
	if skill_data.get("is_magic", false) and caster != null and "intelligence" in caster:
		damage += caster.intelligence
	
	var tiles_to_freeze = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos = target_grid + Vector2i(dx, dy)
			if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
				continue
			if _map_data[pos.x][pos.y] == CellType.WATER:
				tiles_to_freeze.append(pos)
	
	for freeze_pos in tiles_to_freeze:
		_map_data[freeze_pos.x][freeze_pos.y] = CellType.ICE
		_frozen_tiles[freeze_pos] = {
			"permanent": true
		}
	
	var damaged_count = 0
	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity) or not entity.has_method("take_damage"):
			continue
		var entity_grid = tile_map.local_to_map(entity.position)
		if abs(entity_grid.x - target_grid.x) <= radius and abs(entity_grid.y - target_grid.y) <= radius:
			entity.take_damage(damage, caster, ["ice"])
			damaged_count += 1
			_spawn_skill_particles(entity.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0), "ice", 0.5)
	
	var target_center = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	_spawn_skill_particles(target_center, "ice", 1.2)
	
	if log_ui:
		if tiles_to_freeze.size() > 0:
			log_ui.add_log("水が凍結した！ (%d タイル)" % tiles_to_freeze.size(), Color.CYAN)
		if damaged_count > 0:
			log_ui.add_log("凍結魔法が %d 体に命中した！" % damaged_count, Color.CYAN)
	
	_setup_pathfinding()
	_calculate_fov()
	_draw_map()

func _find_chain_neighbors_by_pos(center_pos: Vector2, hit_list: Array, ignore_ent = null) -> Array:
	var neighbors = []
	var t_grid = tile_map.local_to_map(center_pos)
	
	var in_water = false
	if t_grid.x >= 0 and t_grid.x < MAP_WIDTH and t_grid.y >= 0 and t_grid.y < MAP_HEIGHT:
		if _map_data[t_grid.x][t_grid.y] == CellType.WATER:
			in_water = true
			
	var reach = 1.6
	if in_water: reach = 3.0
	
	var entities = get_tree().get_nodes_in_group("entities")
	for ent in entities:
		if not is_instance_valid(ent): continue
		if ent == ignore_ent: continue
		if hit_list.has(ent): continue
		
		var e_grid = tile_map.local_to_map(ent.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
		var dist = Vector2(t_grid).distance_to(Vector2(e_grid))
		
		if dist <= reach:
			neighbors.append(ent)
			
	return neighbors

func _apply_chain_lightning(source, current_target, damage: int, chain_left: int, hit_list: Array):
	if chain_left < 0: return
	if hit_list.has(current_target): return
	
	# Cache position explicitly BEFORE damage (in case target dies/queue_free)
	var target_pos_center = Vector2.ZERO
	if is_instance_valid(current_target):
		target_pos_center = current_target.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	else:
		return # Cannot chain from invalid target
	
	hit_list.append(current_target)
	
	# Visual effect at target position
	_spawn_skill_particles(target_pos_center, "lightning", 0.4)
	
	if is_instance_valid(current_target) and current_target.has_method("take_damage"):
		var t_name = current_target.name
		if "enemy_name" in current_target: t_name = current_target.enemy_name
		elif current_target == player: t_name = "Player"
		
		current_target.take_damage(damage, source, ["electric"])
		
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("⚡ %s に電撃が走る！ (%d)" % [t_name, damage], Color.YELLOW)
			
		if is_instance_valid(current_target) and current_target.has_method("apply_effect") and randf() < 0.3:
			current_target.apply_effect("paralysis", {"duration": 2})

	await get_tree().create_timer(0.15).timeout

	# Use cached position for grid check
	var t_grid = tile_map.local_to_map(target_pos_center)
	
	# Check for Water Conductivity
	var in_water = false
	if t_grid.x >= 0 and t_grid.x < MAP_WIDTH and t_grid.y >= 0 and t_grid.y < MAP_HEIGHT:
		if _map_data[t_grid.x][t_grid.y] == CellType.WATER:
			in_water = true

	var neighbors = []
	var entities = get_tree().get_nodes_in_group("entities")
	
	for ent in entities:
		if not is_instance_valid(ent): continue
		if ent == current_target: continue
		if hit_list.has(ent): continue
		
		var e_grid = tile_map.local_to_map(ent.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
		var dist = Vector2(t_grid).distance_to(Vector2(e_grid))
		
		var reach = 1.6 # Slighly more than 1.5 to be safe
		if in_water: reach = 3.0
			
		if dist <= reach:
			neighbors.append(ent)
	
	# Debug log to UI to visualize chain
	# if has_node("/root/LogUI") and neighbors.size() > 0:
	# 	get_node("/root/LogUI").add_log("連鎖: %d 体の敵を感知" % neighbors.size(), Color.ORANGE)

	for n in neighbors:
		await _apply_chain_lightning(current_target, n, damage, chain_left - 1, hit_list)

func _handle_ranged_attack(attacker, target_grid: Vector2i, damage: int, type: String):
	# 弾道の視覚化
	var start_pos = attacker.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var end_pos = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	# 弾道の色とサイズを設定
	var projectile_color = Color.WHITE
	var projectile_size = 16
	var trail_enabled = true
	
	match type:
		"arrow":
			projectile_color = Color(0.7, 0.5, 0.3) # 茶色（矢）
			projectile_size = 20
		"web":
			projectile_color = Color(0.9, 0.9, 0.9, 0.8) # 白（蜘蛛の糸）
			projectile_size = 12
		"paralyze":
			projectile_color = Color(0.8, 0.3, 0.8) # 紫（麻痺）
			projectile_size = 14
		"fire":
			projectile_color = Color.ORANGE_RED
			projectile_size = 14
	
	# 弾道スプライトを作成
	var projectile = Sprite2D.new()
	var img = Image.create(projectile_size, projectile_size, false, Image.FORMAT_RGBA8)
	
	# 円形の弾道を描画
	var center = Vector2(projectile_size / 2.0, projectile_size / 2.0)
	var radius = projectile_size / 2.0 - 2
	for x in range(projectile_size):
		for y in range(projectile_size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= radius:
				# グラデーション効果
				var alpha = 1.0 - (dist / radius) * 0.3
				var color = Color(projectile_color.r, projectile_color.g, projectile_color.b, alpha)
				img.set_pixel(x, y, color)
	
	projectile.texture = ImageTexture.create_from_image(img)
	projectile.position = start_pos
	
	# 弾道の向きを設定
	var direction = (end_pos - start_pos).normalized()
	projectile.rotation = direction.angle()
	
	add_child(projectile)
	
	# 軌跡（トレイル）エフェクト
	var trail_line = Line2D.new()
	trail_line.width = 3
	trail_line.default_color = Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.5)
	trail_line.add_point(start_pos)
	trail_line.add_point(start_pos)
	add_child(trail_line)
	
	# アニメーション
	var tween = create_tween()
	tween.set_parallel(true)
	
	# 弾道の移動
	tween.tween_property(projectile, "position", end_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 軌跡の更新
	tween.tween_property(trail_line, "points", PackedVector2Array([start_pos, end_pos]), 0.25)
	
	await tween.finished
	
	# ターゲットへのダメージ適用（着弾時に即座に適用）
	var target = null
	for ent in get_tree().get_nodes_in_group("entities"):
		if tile_map.local_to_map(ent.position) == target_grid:
			target = ent
			break
	if target:
		if target.has_method("take_damage"):
			var elements = ["fire"] if type == "fire" else ["normal"]
			target.take_damage(damage, attacker, elements)
			if has_node("/root/LogUI"):
				var t_name = target.name
				if "enemy_name" in target: t_name = target.enemy_name
				elif target == player: t_name = "Player"
				get_node("/root/LogUI").add_log("%s に命中！ (%d)" % [t_name, damage], Color.WHITE)
		if type == "web" and target.has_method("apply_effect"):
			target.apply_effect("paralysis", {"duration": 3})
		if type == "paralyze" and target.has_method("apply_effect"):
			target.apply_effect("paralysis", {"duration": 2})
		if type == "fire" and target.has_method("apply_effect") and not _is_fire_immune(target):
			target.apply_effect("burn", {"duration": 3, "damage": 1})
	if type == "fire" and target_grid.x >= 0 and target_grid.x < MAP_WIDTH and target_grid.y >= 0 and target_grid.y < MAP_HEIGHT:
		if _map_data[target_grid.x][target_grid.y] == CellType.GRASS:
			_ignite_grass(target_grid)
	
	# 着弾パーティクル
	var impact_particles = CPUParticles2D.new()
	impact_particles.position = end_pos
	impact_particles.amount = 12
	impact_particles.lifetime = 0.4
	impact_particles.explosiveness = 0.9
	impact_particles.spread = 180.0
	impact_particles.initial_velocity_min = 40.0
	impact_particles.initial_velocity_max = 80.0
	impact_particles.scale_amount_min = 2.0
	impact_particles.scale_amount_max = 4.0
	impact_particles.color = projectile_color
	impact_particles.one_shot = true
	impact_particles.emitting = true
	add_child(impact_particles)
	
	# クリーンアップ（バックグラウンドで実行）
	projectile.queue_free()
	trail_line.call_deferred("queue_free")
	get_tree().create_timer(0.5).timeout.connect(impact_particles.queue_free)

func _check_drowning() -> bool:
	if not player: return false
	
	var grid_pos = tile_map.local_to_map(player.position)
	if grid_pos.x < 0 or grid_pos.x >= MAP_WIDTH or grid_pos.y < 0 or grid_pos.y >= MAP_HEIGHT:
		return false
		
	var cell = _map_data[grid_pos.x][grid_pos.y]
	
	var is_frozen = _frozen_tiles.has(grid_pos)
	if cell == CellType.WATER and not is_frozen and not player.can_swim:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("溺れている！(HP,MP,経験値減少)", Color(0.4, 0.6, 1.0))
			
		var hp_dmg = max(1, player.max_hp / 10)
		var mp_dmg = max(1, player.max_mp / 10)
		var exp_loss = max(1, int(player.exp * 0.1)) # Lose 10% of current exp
		
		player.take_damage(hp_dmg)
		player.mp = max(0, player.mp - mp_dmg)
		player.exp = max(0, player.exp - exp_loss)
		
		if PlayerUi: 
			PlayerUi.update_hp(player.hp, player.max_hp)
			PlayerUi.update_mp(player.mp, player.max_mp)
			PlayerUi.update_exp(player.exp, player.exp_to_next_level)
			
		return true
	
	return false

func _draw_custom_stairs(grid_pos: Vector2i, color: Color, with_particles: bool):
	var sprite = Sprite2D.new()
	var custom_tex_path = ""
	
	# Determine texture path based on color (heuristic)
	var base_name = ""
	if color.g > 0.8: base_name = "stairs_green"
	elif color.b > 0.8 and color.r < 0.5: base_name = "stairs_blue"
	
	if base_name != "":
		# Check for png then jpg
		if ResourceLoader.exists("res://assets/" + base_name + ".png"):
			custom_tex_path = "res://assets/" + base_name + ".png"
		elif ResourceLoader.exists("res://assets/" + base_name + ".jpg"):
			custom_tex_path = "res://assets/" + base_name + ".jpg"
		# Check physical file if not imported (res:// mapping works for FileAccess in editor usually)
		elif FileAccess.file_exists("res://assets/" + base_name + ".png"):
			custom_tex_path = "res://assets/" + base_name + ".png"
		elif FileAccess.file_exists("res://assets/" + base_name + ".jpg"):
			custom_tex_path = "res://assets/" + base_name + ".jpg"
	
	var tex = null
	if custom_tex_path != "":
		# Attempt specific resource load
		if ResourceLoader.exists(custom_tex_path):
			tex = load(custom_tex_path)
		
		# Fallback: Direct image load (bypasses import cache issues)
		if not tex:
			var global_path = ProjectSettings.globalize_path(custom_tex_path)
			if FileAccess.file_exists(global_path):
				var img = Image.load_from_file(global_path)
				if img:
					tex = ImageTexture.create_from_image(img)
	
	if tex:
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # Keep pixel art crisp
		
		# Scale to fit TILE_SIZE (32x32)
		var w = tex.get_width()
		var h = tex.get_height()
		if w > 0 and h > 0:
			var s = Vector2(float(TILE_SIZE) / w, float(TILE_SIZE) / h)
			sprite.scale = s
		
		sprite.modulate = Color(1, 1, 1) 
	else:
		# Fallback to Atlas
		var source = tile_map.tile_set.get_source(0)
		if source and source is TileSetAtlasSource:
			sprite.texture = source.texture
			sprite.region_enabled = true
			sprite.region_rect = Rect2(17 * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)
			sprite.modulate = color
		
	sprite.position = Vector2(grid_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	if not with_particles:
		# For out-of-sight (memory) stairs, use Unshaded material to bypass CanvasModulate
		var memory_mat = CanvasItemMaterial.new()
		memory_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = memory_mat
		# Dim the color slightly since it won't be darkened by CanvasModulate
		sprite.modulate = sprite.modulate * Color(0.35, 0.35, 0.40, 1.0)
		
	sprite.add_to_group("fire_overlays")
	add_child(sprite)

	if with_particles:
		var particles = CPUParticles2D.new()
		particles.position = sprite.position
		particles.amount = 20
		particles.lifetime = 1.0
		particles.preprocess = 1.0
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = Vector2(10, 10)
		particles.gravity = Vector2(0, -30)
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 5.0
		particles.color = color.lightened(0.2)
		particles.add_to_group("fire_overlays")
		add_child(particles)

func _calculate_skill_damage(skill: Dictionary, target_entity) -> int:
	var base_dmg = skill.get("damage", 0)
	var dmg = 0
	
	if skill.get("is_magic", false):
		dmg = base_dmg
		if player:
			dmg += player.get_total_intelligence() if player.has_method("get_total_intelligence") else player.intelligence
	else:
		# 物理スキル: 通常攻撃力に倍率を掛ける
		if player:
			var multiplier = skill.get("damage", 1.0)
			dmg = int(player.attack_power * multiplier)
		else:
			dmg = int(base_dmg)
	
	if skill.has("int_scaling") and player:
		var int_val = player.get_total_intelligence() if player.has_method("get_total_intelligence") else player.intelligence
		dmg += int(int_val * skill.get("int_scaling", 1.0))
		
	if skill.has("str_scaling") and player:
		var str_val = player.get_total_strength() if player.has_method("get_total_strength") else player.strength
		dmg += int(str_val * skill.get("str_scaling", 1.0))
		
	if skill.has("dex_scaling") and player:
		var dex_val = player.get_total_dexterity() if player.has_method("get_total_dexterity") else player.dexterity
		dmg += int(dex_val * skill.get("dex_scaling", 1.0))

	# Grass Snipe double damage when standing in Grass
	if skill.get("id", "") == "grass_snipe" and player:
		var p_grid = tile_map.local_to_map(player.position)
		if _is_grid_in_bounds(p_grid) and _map_data[p_grid.x][p_grid.y] == CellType.GRASS:
			dmg *= 2

	# 物理スキルの防御力減算
	if not skill.get("is_magic", false) and is_instance_valid(target_entity) and target_entity != player:
		var def = 0
		if "defense_power" in target_entity:
			def = target_entity.defense_power
		elif "defense" in target_entity:
			def = target_entity.defense
			
		if skill.get("id", "") == "helm_splitter":
			def = int(def * 0.4)
			
		dmg = max(1, dmg - def)
		
	return dmg

func _get_skill_elements(skill: Dictionary) -> Array:
	var elems = skill.get("elements", [])
	if elems.is_empty():
		elems = ["normal"]
	return elems

func _execute_wall_skill(target_grid: Vector2i, _targeting_skill: Dictionary):
	if not _is_grid_in_bounds(target_grid):
		return
		
	var hit_entity = null
	for entity in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity):
			if not "hp" in entity:
				continue
			var e_grid = tile_map.local_to_map(entity.position)
			if e_grid == target_grid:
				hit_entity = entity
				break
				
	var target_center = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	_spawn_skill_particles(target_center, "dust", 0.5)
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("大地の壁が隆起した！", Color.GOLD)
		
	_map_data[target_grid.x][target_grid.y] = CellType.WALL
	_update_shadow_cell(target_grid)
	
	# Item bury
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			var i_grid = tile_map.local_to_map(item.position)
			if i_grid == target_grid:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("%s は壁に埋もれて消滅した。" % item.item_data.name if "item_data" in item else "アイテム", Color.GRAY)
				item.queue_free()
				
	if hit_entity:
		var base_dmg = _targeting_skill.get("damage", 6)
		var dmg = base_dmg
		if _targeting_skill.get("is_magic", false) and player:
			var int_val = player.get_total_intelligence() if player.has_method("get_total_intelligence") else player.intelligence
			dmg += int_val
			
		var e_name = hit_entity.name
		if "enemy_name" in hit_entity: e_name = hit_entity.enemy_name
		elif hit_entity == player: e_name = "あなた"
		
		if hit_entity.has_method("take_damage"):
			hit_entity.take_damage(dmg, player, ["magic"])
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%s は壁の隆起に巻き込まれ、%d ダメージ！" % [e_name, dmg], Color.ORANGE)
				
		if is_instance_valid(hit_entity) and (hit_entity == player or (hit_entity.hp > 0 if "hp" in hit_entity else false)):
			var valid_moves = []
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nxt = target_grid + Vector2i(dx, dy)
					if not _is_grid_in_bounds(nxt):
						continue
						
					var is_walkable = false
					var cell = _map_data[nxt.x][nxt.y]
					if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.CRYSTAL_FLOOR or cell == CellType.STAIRS or cell == CellType.STAIRS_BLUE or cell == CellType.STAIRS_GREEN or cell == CellType.STAIRS_RED or cell == CellType.STAIRS_PURPLE or cell == CellType.STAIRS_GOLD or cell == CellType.DOOR_OPEN or cell == CellType.ICE or _frozen_tiles.has(nxt):
						is_walkable = true
						
					if is_walkable:
						var occupied = false
						for other in get_tree().get_nodes_in_group("entities"):
							if is_instance_valid(other) and other != hit_entity:
								if not "hp" in other:
									continue
								var o_grid = tile_map.local_to_map(other.position)
								if o_grid == nxt:
									occupied = true
									break
						if not occupied:
							valid_moves.append(nxt)
							
			if valid_moves.size() > 0:
				var rng = RandomNumberGenerator.new()
				rng.randomize()
				var dest = valid_moves[rng.randi() % valid_moves.size()]
				
				var dest_world_pos = Vector2(dest) * TILE_SIZE
				var move_tween = create_tween()
				move_tween.tween_property(hit_entity, "position", dest_world_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("%s は周囲の安全なマスに吹き飛ばされた！" % e_name, Color.YELLOW)
			else:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("%s は逃げ場がなく、壁に押し潰されて消滅した！" % e_name, Color.RED)
				if hit_entity == player:
					player.take_damage(9999, player)
				else:
					hit_entity.queue_free()

	_setup_pathfinding()
	_calculate_fov()
	_draw_map()
	
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(_targeting_skill, false)
		
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_point_skill(target_pos: Vector2, _targeting_skill: Dictionary):
	var target_grid = tile_map.local_to_map(target_pos)
	
	# LOS Check (Optional, but good for balance)
	var player_grid = tile_map.local_to_map(player.position)
	if not _has_line_of_sight(player_grid, target_grid):
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("そこは見えない！", Color.GRAY)
		return # Don't execute, keep targeting? Or fail? Let's fail/return.
	
	# Handle freeze skill specially
	if _targeting_skill.get("id", "") == "freeze":
		await _execute_freeze_skill_player(target_grid)
		return
	elif _targeting_skill.get("id", "") == "wall":
		await _execute_wall_skill(target_grid, _targeting_skill)
		return
	
	# Visual Animation
	var target_center = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var is_meteor = _targeting_skill.get("id", "") == "meteor"
	var tween = create_tween()
	
	if is_meteor:
		# Flashy Meteor Animation
		var meteor_sprite = Sprite2D.new()
		var m_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var center = Vector2(16, 16)
		for mx in range(32):
			for my in range(32):
				if Vector2(mx, my).distance_to(center) <= 16:
					m_img.set_pixel(mx, my, Color.DARK_RED)
					if Vector2(mx, my).distance_to(center) <= 8:
						m_img.set_pixel(mx, my, Color.ORANGE)
		meteor_sprite.texture = ImageTexture.create_from_image(m_img)
		add_child(meteor_sprite)
		
		var start_pos = target_center + Vector2(200, -400) # Diagonal drop
		meteor_sprite.position = start_pos
		meteor_sprite.scale = Vector2(2.0, 2.0)
		
		var tail = CPUParticles2D.new()
		tail.emitting = true
		tail.amount = 40
		tail.lifetime = 0.4
		tail.gravity = Vector2.ZERO
		tail.color = Color.ORANGE
		tail.scale_amount_min = 2.0
		tail.scale_amount_max = 6.0
		meteor_sprite.add_child(tail)
		
		tween.tween_property(meteor_sprite, "position", target_center, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tween.finished
		meteor_sprite.queue_free()
		
		# Huge Explosion flash!
		var flash = ColorRect.new()
		flash.color = Color(1.0, 0.8, 0.6)
		flash.size = Vector2(4000, 4000)
		flash.position = target_center - Vector2(2000, 2000)
		flash.z_index = 100
		add_child(flash)
		
		var flash_tween = create_tween()
		flash_tween.tween_property(flash, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.tween_callback(flash.queue_free)
		
		_spawn_skill_particles(target_center, "meteor", 1.0)
		
		# Screen Shake effect simulation
		shake_camera(12.0, 0.5)
	else:
		# Normal Explosion
		var explosion = Sprite2D.new()
		var img = Image.create(TILE_SIZE * 3, TILE_SIZE * 3, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0.4, 0.0, 0.6)) # Orange semi-transparent
		explosion.texture = ImageTexture.create_from_image(img)
		explosion.position = target_center
		add_child(explosion)
		
		explosion.scale = Vector2(0.1, 0.1)
		tween.tween_property(explosion, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(explosion, "modulate:a", 0.0, 0.2)
		tween.tween_callback(explosion.queue_free)
		
		_spawn_skill_particles(explosion.position, "fire", 0.8)
		await tween.finished
	
	# Apply Damage in Radius
	var radius = _targeting_skill.get("radius", 1)
	var base_dmg = _targeting_skill.get("damage", 10)
	var dmg = _calculate_skill_damage(_targeting_skill, null)
		
	# Critical Check
	var is_crit = false
	if player and "crit_rate" in player:
		# Magic Crit could have a penalty or be harder? 
		# For now, use same rate for simplicity.
		if randf() < player.crit_rate:
			is_crit = true
			dmg *= 2
		
	var hit_count = 0
	
	for x in range(target_grid.x - radius, target_grid.x + radius + 1):
		for y in range(target_grid.y - radius, target_grid.y + radius + 1):
			var check_pos = Vector2i(x, y)
			
			# Melt ice if fire skill
			if _map_data[check_pos.x][check_pos.y] == CellType.ICE and _frozen_tiles.has(check_pos):
				var skill_id = _targeting_skill.get("id", "")
				if skill_id in ["explosion", "meteor", "fireball"]:
					_map_data[check_pos.x][check_pos.y] = CellType.WATER
					_frozen_tiles.erase(check_pos)
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("🔥 氷が溶けた！", Color.ORANGE)
			
			# Check Entities
			for entity in get_tree().get_nodes_in_group("entities"):
				if not is_instance_valid(entity): continue
				var e_grid = tile_map.local_to_map(entity.position)
				if e_grid == check_pos:
					if is_instance_valid(entity) and entity.has_method("take_damage"):
						var elems = _get_skill_elements(_targeting_skill)
						entity.take_damage(dmg, player, elems)
						hit_count += 1
						if entity == player:
							if has_node("/root/LogUI"):
								get_node("/root/LogUI").add_log("自分も爆発に巻き込まれた！(%dダメ)" % dmg, Color.RED)
						elif is_instance_valid(entity):
							var e_name = entity.name
							if "enemy_name" in entity: e_name = entity.enemy_name
							if has_node("/root/LogUI"):
								var crit_text = " (会心!)" if is_crit else ""
								get_node("/root/LogUI").add_log("%s に爆発が命中！(%dダメ)%s" % [e_name, dmg, crit_text], Color.ORANGE)

	if hit_count == 0:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("爆発は虚しく響いた。", Color.GRAY)

	# Consueme MP & End
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(_targeting_skill, false)
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_collapse_skill(target_pos: Vector2, _targeting_skill: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var line_points = _get_line_points(player_grid, target_grid)
	
	var max_range = _targeting_skill.get("range", 5)
	var affected_points = []
	
	for i in range(1, line_points.size()):
		if i > max_range:
			break
		var p = line_points[i]
		if p.x < 0 or p.x >= MAP_WIDTH or p.y < 0 or p.y >= MAP_HEIGHT:
			break
		affected_points.append(p)
		
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("「崩壊」が発動した！空間が歪み始める...", Color.PURPLE)
	
	var map_changed = false
	
	for p in affected_points:
		# Effect
		var world_pos = Vector2(p) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		_spawn_skill_particles(world_pos, "void", 0.5)
		
		# Terrain erase
		var cell = _map_data[p.x][p.y]
		if cell == CellType.WALL or cell == CellType.DOOR_CLOSED or cell == CellType.DOOR_OPEN or cell == CellType.DOOR_LOCKED:
			_map_data[p.x][p.y] = CellType.FLOOR
			map_changed = true
			
		# Overlays erase
		if _burning_grass.has(p):
			_burning_grass.erase(p)
		if _frozen_tiles.has(p):
			_frozen_tiles.erase(p)
		if _steam_tiles.has(p):
			_steam_tiles.erase(p)
			
		# Entity erase
		for entity in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(entity) and entity != player:
				var e_grid = tile_map.local_to_map(entity.position)
				if e_grid == p:
					var e_name = entity.name
					if "enemy_name" in entity: e_name = entity.enemy_name
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("%s は崩壊に巻き込まれ、消滅した！" % e_name, Color.RED)
					if entity.has_method("take_damage"):
						entity.take_damage(9999, player)
					else:
						entity.queue_free()
						
		# Item erase
		for item in get_tree().get_nodes_in_group("items"):
			if is_instance_valid(item) and not item.is_queued_for_deletion():
				var i_grid = tile_map.local_to_map(item.position)
				if i_grid == p:
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("%s は塵となって消え去った。" % item.item_data.name if "item_data" in item else "アイテム", Color.GRAY)
					item.queue_free()

	if map_changed:
		_setup_pathfinding()
		_calculate_fov()
		_draw_map()
		
	# Sleep timer
	player.decay_sleep_timer = 5
	
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(_targeting_skill, false)
		
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_gale_thrust_skill(target_pos: Vector2, skill: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var line_points = _get_line_points(player_grid, target_grid)
	
	var max_range = skill.get("range", 3)
	var affected_points = []
	var direction = Vector2(target_grid - player_grid).sign()
	
	for i in range(1, line_points.size()):
		if i > max_range:
			break
		var p = line_points[i]
		if p.x < 0 or p.x >= MAP_WIDTH or p.y < 0 or p.y >= MAP_HEIGHT:
			break
		if _map_data[p.x][p.y] == CellType.WALL or _map_data[p.x][p.y] == CellType.DOOR_CLOSED or _map_data[p.x][p.y] == CellType.DOOR_LOCKED:
			break
		affected_points.append(p)
		
	var projectile_sprite = Sprite2D.new()
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var center = Vector2(8, 8)
	for x in range(16):
		for y in range(16):
			if Vector2(x, y).distance_to(center) <= 5:
				img.set_pixel(x, y, Color(0.6, 0.9, 1.0, 0.8))
	projectile_sprite.texture = ImageTexture.create_from_image(img)
	add_child(projectile_sprite)
	projectile_sprite.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	var last_pos = target_grid if affected_points.is_empty() else affected_points.back()
	var target_world_pos = Vector2(last_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var tween = create_tween()
	tween.tween_property(projectile_sprite, "position", target_world_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(projectile_sprite.queue_free)
	
	_spawn_skill_particles(target_world_pos, "ice", 0.4)
	await tween.finished
	
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("「烈風突き」を放った！", Color.GOLD)
		
	for p in affected_points:
		for entity in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(entity) and entity != player and "hp" in entity:
				var e_grid = tile_map.local_to_map(entity.position)
				if e_grid == p:
					var dmg = _calculate_skill_damage(skill, entity)
					var e_name = entity.name
					if "enemy_name" in entity: e_name = entity.enemy_name
					
					entity.take_damage(dmg, player, ["normal"])
					if has_node("/root/LogUI"):
						get_node("/root/LogUI").add_log("%s に %d ダメージ！" % [e_name, dmg], Color.ORANGE)
						
					if is_instance_valid(entity) and entity.hp > 0:
						var dest = p + Vector2i(direction)
						if _is_grid_in_bounds(dest):
							var cell = _map_data[dest.x][dest.y]
							if cell != CellType.WALL and cell != CellType.DOOR_CLOSED and cell != CellType.DOOR_LOCKED and cell != CellType.LAVA:
								var occupied = false
								for other in get_tree().get_nodes_in_group("entities"):
									if is_instance_valid(other) and "hp" in other:
										var o_grid = tile_map.local_to_map(other.position)
										if o_grid == dest:
											occupied = true
											break
								if not occupied:
									var dest_world_pos = Vector2(dest) * TILE_SIZE
									var move_tween = create_tween()
									move_tween.tween_property(entity, "position", dest_world_pos, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
									move_tween.finished.connect(_resolve_forced_landing.bind(entity, dest))
									if has_node("/root/LogUI"):
										get_node("/root/LogUI").add_log("%s は後ろに押し戻された！" % e_name, Color.YELLOW)
										
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(skill, false)
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_cyclone_slash(skill: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var p = player_grid + Vector2i(dx, dy)
			var w_pos = Vector2(p) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			_spawn_skill_particles(w_pos, "dust", 0.3)
			
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("「回転斬り」を繰り出した！", Color.GOLD)
		
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var p = player_grid + Vector2i(dx, dy)
			
			for entity in get_tree().get_nodes_in_group("entities"):
				if is_instance_valid(entity) and entity != player and "hp" in entity:
					var e_grid = tile_map.local_to_map(entity.position)
					if e_grid == p:
						var dmg = _calculate_skill_damage(skill, entity)
						var e_name = entity.name
						if "enemy_name" in entity: e_name = entity.enemy_name
						
						entity.take_damage(dmg, player, ["normal"])
						if has_node("/root/LogUI"):
							get_node("/root/LogUI").add_log("%s に %d ダメージ！" % [e_name, dmg], Color.ORANGE)
							
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_helm_splitter_skill(target_pos: Vector2, skill: Dictionary):
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	
	# Range Check (adjacent only)
	var diff = (target_grid - player_grid).abs()
	if diff.x > 1 or diff.y > 1 or target_grid == player_grid:
		target_manager.cancel_targeting()
		return
		
	var hit_entity = null
	for entity in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity) and "hp" in entity:
			var e_grid = tile_map.local_to_map(entity.position)
			if e_grid == target_grid:
				hit_entity = entity
				break
				
	var target_world_pos = Vector2(target_grid) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	# Visual: Vertical split slash
	var slash_sprite = Sprite2D.new()
	var img = Image.create(6, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.9, 0.3, 0.9)) # Bright yellow vertical cut
	slash_sprite.texture = ImageTexture.create_from_image(img)
	add_child(slash_sprite)
	slash_sprite.position = target_world_pos + Vector2(0, -16)
	slash_sprite.scale = Vector2(1.0, 0.1)
	
	var tween = create_tween()
	tween.tween_property(slash_sprite, "scale", Vector2(1.0, 1.2), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(slash_sprite, "position", target_world_pos + Vector2(0, 8), 0.08)
	tween.tween_property(slash_sprite, "modulate:a", 0.0, 0.08)
	tween.tween_callback(slash_sprite.queue_free)
	
	# Sparks and screen shake
	_spawn_skill_particles(target_world_pos, "hit_physical", 0.4)
	shake_camera(5.0, 0.15)
	
	await tween.finished
	
	if hit_entity:
		var dmg = _calculate_skill_damage(skill, hit_entity)
		var e_name = hit_entity.name
		if "enemy_name" in hit_entity: e_name = hit_entity.enemy_name
		
		hit_entity.take_damage(dmg, player, ["normal"])
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("「兜割り」が決まった！ %s に %d ダメージ！" % [e_name, dmg], Color.ORANGE)
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("兜割りは空を切った。", Color.GRAY)
			
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(skill, false)
	target_manager.cancel_targeting()
	await _end_player_turn()

func _execute_super_seoi_nage_skill(target_pos: Vector2, skill: Dictionary):
	var user_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var offset = target_grid - user_grid

	if target_grid == user_grid or abs(offset.x) > 1 or abs(offset.y) > 1:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("超背負投は隣接する対象にしか使えない。", Color.GRAY)
		target_manager.cancel_targeting()
		return

	var target_entity = null
	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity) or entity == player or not entity.has_method("take_damage"):
			continue
		if tile_map.local_to_map(entity.position) == target_grid:
			target_entity = entity
			break

	if not is_instance_valid(target_entity):
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("投げる対象がいない。", Color.GRAY)
		target_manager.cancel_targeting()
		return

	var throw_direction = -offset
	var throw_distance = int(skill.get("throw_distance", 5))
	var landing_grid = user_grid
	var hit_wall = false
	var collision_entity = null
	var flown_distance = 0

	for distance in range(1, throw_distance + 1):
		var next_grid = user_grid + throw_direction * distance
		collision_entity = _get_throw_collision_entity(target_entity, next_grid)
		if is_instance_valid(collision_entity):
			break
		if not _can_throw_target_to(target_entity, next_grid):
			hit_wall = _is_throw_wall(next_grid)
			break
		landing_grid = next_grid
		flown_distance = distance
		if _map_data[next_grid.x][next_grid.y] == CellType.PIT:
			break

	var target_name = target_entity.name
	if "enemy_name" in target_entity:
		target_name = target_entity.enemy_name

	var user_center = player.position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var landing_pos = Vector2(landing_grid) * TILE_SIZE
	var throw_peak = player.position + Vector2(0.0, -TILE_SIZE * 0.8)
	_spawn_skill_particles(user_center, "dust", 0.25)

	var tween = create_tween()
	tween.tween_property(target_entity, "position", throw_peak, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target_entity, "position", landing_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished

	var landing_damage = _calculate_throw_damage(skill, target_entity, "landing_damage")
	target_entity.take_damage(landing_damage, player, ["blunt"])
	_spawn_skill_particles(landing_pos + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0), "hit_physical", 0.3)
	var landed_in_pit = _resolve_forced_landing(target_entity, landing_grid)

	if not landed_in_pit and hit_wall and is_instance_valid(target_entity):
		var collision_damage = _calculate_throw_damage(skill, target_entity, "collision_damage")
		target_entity.take_damage(collision_damage, player, ["blunt"])
		shake_camera(6.0, 0.18)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log(
				"超背負投！ %s は壁に激突！ 落下%d＋衝突%dダメージ！" %
				[target_name, landing_damage, collision_damage],
				Color.RED
			)
	elif not landed_in_pit and is_instance_valid(collision_entity) and is_instance_valid(target_entity):
		var thrown_collision_damage = _calculate_throw_damage(skill, target_entity, "collision_damage")
		var struck_collision_damage = _calculate_throw_damage(skill, collision_entity, "collision_damage")
		target_entity.take_damage(thrown_collision_damage, player, ["blunt"])
		collision_entity.take_damage(struck_collision_damage, player, ["blunt"])
		_spawn_skill_particles(
			collision_entity.position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0),
			"hit_physical",
			0.35
		)
		shake_camera(5.0, 0.15)
		var collision_name = collision_entity.name
		if "enemy_name" in collision_entity:
			collision_name = collision_entity.enemy_name
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log(
				"超背負投！ %s が %s に激突！ 両者に%d／%dダメージ！" %
				[target_name, collision_name, thrown_collision_damage, struck_collision_damage],
				Color.RED
			)
	elif landed_in_pit and has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log(
			"超背負投！ %s を落とし穴へ投げ落とした！" % target_name,
			Color.RED
		)
	elif has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log(
			"超背負投！ %s を%dマス投げ飛ばし、落下で%dダメージ！" %
			[target_name, flown_distance, landing_damage],
			Color.ORANGE
		)

	if visibility_manager:
		visibility_manager.update_entity_visibility()
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(skill, false)
	target_manager.cancel_targeting()
	await _end_player_turn()

func _calculate_throw_damage(skill: Dictionary, target_entity, damage_key: String) -> int:
	var damage = int(skill.get(damage_key, 0))
	var strength = player.get_total_strength() if player.has_method("get_total_strength") else player.strength
	damage += int(strength * float(skill.get("str_scaling", 0.0)))

	var defense = 0
	if "defense_power" in target_entity:
		defense = target_entity.defense_power
	elif "defense" in target_entity:
		defense = target_entity.defense
	return max(1, damage - defense)

func _is_throw_wall(grid_pos: Vector2i) -> bool:
	if not _is_grid_in_bounds(grid_pos):
		return true
	var cell = _map_data[grid_pos.x][grid_pos.y]
	return cell in [
		CellType.WALL,
		CellType.DOOR_CLOSED,
		CellType.DOOR_LOCKED,
		CellType.TREE,
		CellType.TREE_FRUIT,
		CellType.ROCK
	]

func _get_throw_collision_entity(thrown_entity, grid_pos: Vector2i):
	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity) or entity == thrown_entity or entity == player:
			continue
		if entity.is_in_group("items") or not entity.has_method("take_damage"):
			continue
		if tile_map.local_to_map(entity.position) == grid_pos:
			return entity
	return null

func _can_throw_target_to(target_entity, grid_pos: Vector2i) -> bool:
	if not _is_grid_in_bounds(grid_pos):
		return false

	var cell = _map_data[grid_pos.x][grid_pos.y]
	if cell in [
		CellType.WALL,
		CellType.DOOR_CLOSED,
		CellType.DOOR_LOCKED,
		CellType.TREE,
		CellType.TREE_FRUIT,
		CellType.ROCK,
		CellType.LAVA
	]:
		return false

	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity) or entity == target_entity or entity.is_in_group("items"):
			continue
		if tile_map.local_to_map(entity.position) == grid_pos:
			return false

	return true

func _execute_directional_skill(target_pos: Vector2, _targeting_skill: Dictionary):
	var current_skill_id = _targeting_skill.get("id", "")
	if current_skill_id == "collapse":
		await _execute_collapse_skill(target_pos, _targeting_skill)
		return
	elif current_skill_id == "gale_thrust":
		await _execute_gale_thrust_skill(target_pos, _targeting_skill)
		return
	elif current_skill_id == "helm_splitter":
		await _execute_helm_splitter_skill(target_pos, _targeting_skill)
		return
	elif current_skill_id == "super_seoi_nage":
		await _execute_super_seoi_nage_skill(target_pos, _targeting_skill)
		return

	# 1. Path & Hit Calculation (Directional/Projectile)
	var player_grid = tile_map.local_to_map(player.position)
	var target_grid = tile_map.local_to_map(target_pos)
	var line_points = _get_line_points(player_grid, target_grid)
	
	var hit_pos = target_grid
	var hit_entity = null
	
	# Range Check
	var max_range = _targeting_skill.get("range", 6)
	
	for i in range(1, line_points.size()):
		var p = line_points[i]
		
		# Limit Range
		if i > max_range:
			hit_pos = line_points[i-1]
			break
			
		if p.x < 0 or p.x >= MAP_WIDTH or p.y < 0 or p.y >= MAP_HEIGHT:
			hit_pos = line_points[i-1]
			break
		
		# Check Walls or Doors
		if _map_data[p.x][p.y] == CellType.WALL or _map_data[p.x][p.y] == CellType.DOOR_CLOSED or _map_data[p.x][p.y] == CellType.DOOR_LOCKED:
			hit_pos = line_points[i-1]
			break
		
		# Check Enemies
		for enemy in get_tree().get_nodes_in_group("entities"):
			if is_instance_valid(enemy) and enemy != player and enemy.has_method("take_damage"):
				var e_grid = tile_map.local_to_map(enemy.position)
				if e_grid == p:
					if current_skill_id == "grass_snipe" and i == 1:
						continue
					hit_entity = enemy
					hit_pos = p
					break
		if hit_entity: break
		
		hit_pos = p
	
	# 2. Visual Animation
	var projectile_color = Color.RED # Default Fireball
	if _targeting_skill.get("id", "") == "lightning": projectile_color = Color.YELLOW
	elif _targeting_skill.get("id", "") in ["iceball", "ice_bolt"]: projectile_color = Color.CYAN
	elif _targeting_skill.get("id", "") == "web_shot": projectile_color = Color.WHITE
	elif _targeting_skill.get("id", "") == "blood_beam": projectile_color = Color(0.7, 0.0, 0.1)
	elif _targeting_skill.get("id", "") == "grass_snipe": projectile_color = Color(0.1, 0.8, 0.3)
	
	var projectile_sprite = Sprite2D.new()
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	
	# Create a simple circle texture
	var center = Vector2(8, 8)
	for x in range(16):
		for y in range(16):
			if Vector2(x, y).distance_to(center) <= 6:
				img.set_pixel(x, y, projectile_color)
				
	projectile_sprite.texture = ImageTexture.create_from_image(img)
	add_child(projectile_sprite)
	projectile_sprite.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	
	var target_world_pos = Vector2(hit_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	var tween = create_tween()
	tween.tween_property(projectile_sprite, "position", target_world_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(projectile_sprite.queue_free)
	
	# Spawn impact particles
	var projectile_particle_type = "fire"
	if current_skill_id == "lightning": projectile_particle_type = "lightning"
	elif current_skill_id in ["iceball", "ice_bolt"]: projectile_particle_type = "ice"
	elif current_skill_id == "web_shot": projectile_particle_type = "web"
	elif current_skill_id == "blood_beam": projectile_particle_type = "blood"
	elif current_skill_id == "grass_snipe": projectile_particle_type = "leaf"
	
	_spawn_skill_particles(target_world_pos, projectile_particle_type, 0.4)
	
	await tween.finished
	
	# Melt ice if fire skill
	if current_skill_id in ["fireball", "explosion", "meteor"]:
		if _map_data[hit_pos.x][hit_pos.y] == CellType.ICE and _frozen_tiles.has(hit_pos):
			_map_data[hit_pos.x][hit_pos.y] = CellType.WATER
			_frozen_tiles.erase(hit_pos)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("🔥 氷が溶けた！", Color.ORANGE)
			_setup_pathfinding()
			_calculate_fov()
			_draw_map()
	
	# 3. Apply Effect
	if hit_entity:
		var dmg = _calculate_skill_damage(_targeting_skill, hit_entity)
			
		# Critical Check
		var is_crit = false
		if player and "crit_rate" in player:
			if randf() < player.crit_rate:
				is_crit = true
				dmg *= 2
				
		if dmg > 0 and is_instance_valid(hit_entity):
			var elems = _get_skill_elements(_targeting_skill)
			hit_entity.take_damage(dmg, player, elems)
			if has_node("/root/LogUI"):
				var e_name = hit_entity.name
				if "enemy_name" in hit_entity:
					e_name = hit_entity.enemy_name
				var crit_text = " (会心!)" if is_crit else ""
				get_node("/root/LogUI").add_log("%s が命中！ %s に %d ダメージ！%s" % [_targeting_skill.get("name", "?"), e_name, dmg, crit_text], Color.ORANGE)
				
		var effect = _targeting_skill.get("effect", "")
		if effect != "" and is_instance_valid(hit_entity) and hit_entity.has_method("apply_effect"):
			if effect == "burn":
				hit_entity.apply_effect("burn", {"duration": 5, "damage": 2}) # Strong burn
			elif effect == "paralyze":
				hit_entity.apply_effect("paralyze", {"duration": 3})

		# MUG (Steal Gold)
		if _targeting_skill.get("steal_gold", false):
			var stolen = randi_range(5, 15)
			player.gold += stolen
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%d ゴールドを盗んだ！" % stolen, Color.YELLOW)

		# BLOOD BEAM: 盲目効果 + 状態異常転移 (存存チェック不要な処理)
		if current_skill_id == "blood_beam":
			# 盲目効果 (40%確率)
			var blind_chance = _targeting_skill.get("blind_chance", 0.4)
			if is_instance_valid(hit_entity) and randf() < blind_chance and hit_entity.has_method("apply_effect"):
				hit_entity.apply_effect("blind", {"duration": 4})

			# 状態異常転移: プレイヤーの全状態異常を対象に付与
			if is_instance_valid(hit_entity) and _targeting_skill.get("transfer_status", false) and "status_effects" in player:
				for eff_id in player.status_effects.keys():
					if hit_entity.has_method("apply_effect"):
						var eff_data = player.status_effects[eff_id].duplicate()
						hit_entity.apply_effect(eff_id, eff_data)
						if has_node("/root/LogUI"):
							var e_name = hit_entity.name
							if "enemy_name" in hit_entity: e_name = hit_entity.enemy_name
							get_node("/root/LogUI").add_log("%s に %s を転移した！" % [e_name, eff_id], Color(0.8, 0.3, 0.9))
	else:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s は何にも当たらなかった。" % _targeting_skill.get("name", "?"), Color.GRAY)

	# BLOOD BEAM: HP消費はヒット・ミスに関わらず必ず発生
	if current_skill_id == "blood_beam":
		var hp_cost = _targeting_skill.get("hp_cost", 5)
		player.hp = max(1, player.hp - hp_cost)
		# take_damage() を経由しないので自動回復カウンターを手動リセット
		player.turns_since_damage = 0
		if PlayerUi:
			PlayerUi.update_hp(player.hp, player.max_hp)
		_spawn_skill_particles(player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0), "blood", 0.5)
		# プレイヤーのいるマスに血痕を描画（永続）
		_spawn_blood_decal(tile_map.local_to_map(player.position), true, true)
		# 着弾マスにも血痕を描画（永続）
		_spawn_blood_decal(hit_pos, false, true)


	# Lightning-Water Synergy: Electrify connected water tiles
	if _targeting_skill.get("id", "") == "lightning":
		# Player Chain Lightning Logic
		if hit_entity: # Was hit initially
			var center_pos = Vector2(hit_pos) * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			var chain_dmg = _targeting_skill.get("damage", 0)
			if _targeting_skill.get("is_magic", false) and player:
				chain_dmg += player.intelligence
			var ignore = hit_entity if is_instance_valid(hit_entity) else null
			var hit_list = []
			if ignore: hit_list.append(ignore)
			var neighbors = _find_chain_neighbors_by_pos(center_pos, hit_list, ignore)
			for n in neighbors:
				await _apply_chain_lightning(player, n, chain_dmg, 3, hit_list)

		var hit_cell = _map_data[hit_pos.x][hit_pos.y]
		if hit_cell == CellType.WATER:
			_electrify_water(hit_pos)
	
	# Fire-Grass Synergy: Ignite grass tiles
	var effect = _targeting_skill.get("effect", "")
	if effect == "burn":  # Fire-based skills
		var hit_cell = _map_data[hit_pos.x][hit_pos.y]
		if hit_cell == CellType.GRASS:
			_ignite_grass(hit_pos)
		elif hit_cell == CellType.WATER:
			# Fire-Water Synergy: Create steam
			_create_steam(hit_pos)
	
	# Ice-Water Synergy: Freeze water tiles
	if _targeting_skill.get("id", "") in ["iceball", "ice_bolt"]:
		var hit_cell = _map_data[hit_pos.x][hit_pos.y]
		if hit_cell == CellType.WATER:
			_freeze_water(hit_pos, false)

	# 4. Notify Player to consume MP
	if player.has_method("on_skill_executed"):
		player.on_skill_executed(_targeting_skill, false)
		
	# 5. End Turn
	target_manager.cancel_targeting()
	await _end_player_turn()

# === WORLD MAP EXPANSION ===
const WorldCell = MapDefinitions.WorldCell

func _init_world_map():
	var generator = DungeonGenerator.new()
	_world_map_data = generator.generate_world_map()
	
	var start_pos = Vector2i.ZERO
	var found_village = false
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _world_map_data[x][y] == WorldCell.VILLAGE:
				start_pos = Vector2i(x, y)
				found_village = true
				break
		if found_village: break
		
	if not found_village:
		for x in range(MAP_WIDTH):
			for y in range(MAP_HEIGHT):
				if _world_map_data[x][y] == WorldCell.GRASS:
					start_pos = Vector2i(x, y)
					found_village = true
					break
			if found_village: break
			
	_world_player_pos = start_pos
	_starting_village_pos = start_pos
	_is_on_world_map = false
	
	# Find other villages to assign the dungeon village
	var other_villages = []
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _world_map_data[x][y] == WorldCell.VILLAGE and Vector2i(x, y) != start_pos:
				other_villages.append(Vector2i(x, y))
	
	if not other_villages.is_empty():
		_dungeon_village_pos = other_villages.pick_random()
	else:
		_dungeon_village_pos = Vector2i.ZERO
	
	# Generate local overworld for the starting village
	var result = generator.generate_map(0, 0, WorldCell.VILLAGE, self, true, false)
	_map_data = result["map_data"]
	_rooms = result["rooms"]
	generator.free()
	
	_visible_tiles.resize(MAP_WIDTH)
	_explored_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		_visible_tiles[x] = []
		_visible_tiles[x].resize(MAP_HEIGHT)
		_explored_tiles[x] = []
		_explored_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			_visible_tiles[x][y] = false
			_explored_tiles[x][y] = false

func _zoom_out_to_world_map():
	if _is_on_world_map:
		return
	if current_floor != 0:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("ここではワールドマップを開けない！", Color(0.9, 0.4, 0.4))
		return
		
	# Save current local map to cache
	_save_current_floor_to_cache()
	
	# Gather allies data so they travel with the player
	_saved_allies.clear()
	var allies = get_tree().get_nodes_in_group("allies")
	for ally in allies:
		if is_instance_valid(ally) and not ally.is_queued_for_deletion():
			_saved_allies.append({
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
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.remove_from_group("enemies")
			enemy.remove_from_group("entities")
			enemy.queue_free()
			
	for npc in get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc):
			npc.remove_from_group("npcs")
			npc.remove_from_group("entities")
			npc.queue_free()
			
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item):
			item.remove_from_group("items")
			item.remove_from_group("entities")
			item.queue_free()
			
	for torch in get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.remove_from_group("torches")
			torch.queue_free()
			
	# Clear other temporary local map graphics like fire overlays, steam overlays, blood decals
	get_tree().call_group("fire_overlays", "queue_free")
	get_tree().call_group("blood_decals", "queue_free")
	
	_is_on_world_map = true
	_update_lighting_for_map_type()
	player.position = Vector2(_world_player_pos) * TILE_SIZE
	_last_player_grid_pos = _world_player_pos
	camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	camera.reset_smoothing()
	
	_draw_world_map()
	
	if PlayerUi:
		PlayerUi.update_floor("ワールド")
		
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("ワールドマップにズームアウトした。", Color(0.2, 0.7, 0.9))

func _zoom_in_to_local_map():
	if not _is_on_world_map:
		return
		
	var cell_type = _world_map_data[_world_player_pos.x][_world_player_pos.y]
	if cell_type == WorldCell.SEA or cell_type == WorldCell.MOUNTAIN:
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("ここには進入できない！", Color(0.9, 0.2, 0.2))
		return
		
	_is_on_world_map = false
	_update_lighting_for_map_type()
	
	# Restore 2D visuals and hide ASCII overlay
	tile_map.visible = true
	if is_instance_valid(player):
		player.visible = true
	if _ascii_map_layer:
		_ascii_map_layer.visible = false
	
	var cache_key = "local_overworld_%d_%d" % [_world_player_pos.x, _world_player_pos.y]
	if not _load_floor_from_cache(cache_key, false):
		# Clear old entities before generating
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(enemy): enemy.queue_free()
		for npc in get_tree().get_nodes_in_group("npcs"):
			if is_instance_valid(npc): npc.queue_free()
		for item in get_tree().get_nodes_in_group("items"):
			if is_instance_valid(item): item.queue_free()
		for torch in get_tree().get_nodes_in_group("torches"):
			if is_instance_valid(torch): torch.queue_free()
			
		_generate_map(cell_type)
		_setup_pathfinding()
		
		# Set player position at center of first room/village center
		var spawn_pos = Vector2i(MAP_WIDTH/2, MAP_HEIGHT/2)
		if not _rooms.is_empty():
			spawn_pos = _rooms[0].get_center()
			
		player.position = Vector2(spawn_pos) * TILE_SIZE
		_last_player_grid_pos = spawn_pos
		
		if cell_type == WorldCell.VILLAGE:
			_spawn_village_npcs()
		else:
			_spawn_enemies()
			_spawn_items()
		_spawn_torches()
		
		# Spawn saved allies near the player
		for adata in _saved_allies:
			_spawn_ally_near_player(adata)
		_saved_allies.clear()
		
	# Sync VisibilityManager
	if visibility_manager:
		visibility_manager.map_data = _map_data
		visibility_manager.visible_tiles = _visible_tiles
		visibility_manager.explored_tiles = _explored_tiles
		visibility_manager.calculate_fov()
		visibility_manager.draw_map()
	else:
		_calculate_fov()
		_draw_map()
		
	camera.position = player.position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
	camera.reset_smoothing()
	
	if PlayerUi:
		PlayerUi.update_floor(0)
		
	var cell_names = {
		WorldCell.GRASS: "平原",
		WorldCell.FOREST: "森",
		WorldCell.VILLAGE: "村",
		WorldCell.DUNGEON: "ダンジョンの入口",
		WorldCell.ROAD: "街道"
	}
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("%s にズームインした。" % cell_names.get(cell_type, "地上"), Color(0.2, 0.9, 0.4))

func _draw_world_map():
	tile_map.clear_layer(LAYER_VISIBLE)
	tile_map.clear_layer(LAYER_MEMORY)
	
	# Clear old overlays
	get_tree().call_group("fire_overlays", "queue_free")
	get_tree().call_group("world_village_icons", "queue_free")
	
	# Hide all non-player entities on world map
	for entity in get_tree().get_nodes_in_group("entities"):
		if is_instance_valid(entity) and entity != player:
			entity.visible = false
	for torch in get_tree().get_nodes_in_group("torches"):
		if is_instance_valid(torch):
			torch.visible = false
			
	# Restore 2D TileMap and Player sprite (drawing ASCII tiles directly onto them!)
	tile_map.visible = true
	if is_instance_valid(player):
		player.visible = true
		
	# Hide the full-screen terminal text overlay
	if _ascii_map_layer:
		_ascii_map_layer.visible = false
		
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var cell = _world_map_data[x][y]
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
				_:
					atlas_coords.x = 84
					
			tile_map.set_cell(LAYER_VISIBLE, tile_coords, 0, atlas_coords)
			
	if minimap_controller:
		minimap_controller.update_minimap()

func _deserialize_world_map(map_array: Array) -> Array:
	var map = []
	map.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		map[x] = []
		map[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			if x < map_array.size() and y < map_array[x].size():
				map[x][y] = int(map_array[x][y])
			else:
				map[x][y] = WorldCell.SEA
	return map

func _ensure_ascii_map_overlay():
	if _ascii_map_layer:
		return
		
	_ascii_map_layer = CanvasLayer.new()
	_ascii_map_layer.layer = 95
	add_child(_ascii_map_layer)
	
	# Solid near-black background covering the entire main screen
	var bg_panel = Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.04, 0.05, 1.0)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	_ascii_map_layer.add_child(bg_panel)
	
	# Center container to center the entire terminal layout on the screen
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ascii_map_layer.add_child(center_container)
	
	# Monospace terminal view vertical layout (no floating panel/borders)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center_container.add_child(vbox)
	
	# Header with map info
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title = Label.new()
	title.text = "✦ WORLD MAP ✦"
	title.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	title.add_theme_font_size_override("font_size", 14)
	header.add_child(title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var info_lbl = Label.new()
	info_lbl.text = "方向キーで移動 | 進入可能なマスで Enter を押してズームイン"
	info_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	info_lbl.add_theme_font_size_override("font_size", 11)
	header.add_child(info_lbl)
	
	var sep = ColorRect.new()
	sep.color = Color(0.25, 0.25, 0.28, 0.4)
	sep.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sep)
	
	_ascii_map_label = RichTextLabel.new()
	_ascii_map_label.bbcode_enabled = true
	_ascii_map_label.scroll_active = false
	_ascii_map_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ascii_map_label.custom_minimum_size = Vector2(960, 950)
	
	var mono_font = SystemFont.new()
	mono_font.font_names = PackedStringArray(["Consolas", "Courier New", "Courier", "MS Gothic", "monospace"])
	_ascii_map_label.add_theme_font_override("normal_font", mono_font)
	_ascii_map_label.add_theme_font_size_override("normal_font_size", 16)
	_ascii_map_label.add_theme_constant_override("line_separation", 3)
	vbox.add_child(_ascii_map_label)

func _update_ascii_map_text():
	if not _ascii_map_label:
		return
		
	var final_bbcode = ""
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			if Vector2i(x, y) == _world_player_pos:
				final_bbcode += "[color=#ffffff]@[/color] "
				continue
				
			var cell = _world_map_data[x][y]
			match cell:
				WorldCell.SEA:
					final_bbcode += "[color=#385c7d]~[/color] "
				WorldCell.GRASS:
					final_bbcode += "[color=#4a634a].[/color] "
				WorldCell.FOREST:
					final_bbcode += "[color=#2b663b]T[/color] "
				WorldCell.MOUNTAIN:
					final_bbcode += "[color=#6b5c4d]^[/color] "
				WorldCell.VILLAGE:
					final_bbcode += "[color=#d4a73b]V[/color] "
				WorldCell.DUNGEON:
					final_bbcode += "[color=#c23c3c]D[/color] "
				WorldCell.ROAD:
					final_bbcode += "[color=#57575e]#[/color] "
				_:
					final_bbcode += "  "
		final_bbcode += "\n"
		
	_ascii_map_label.text = final_bbcode

func _update_lighting_for_map_type():
	var canvas_modulate = get_node_or_null("CanvasModulate")
	var is_outdoor = _is_on_world_map or current_floor == 0

	if shadow_manager:
		shadow_manager.visible = not is_outdoor
		if not is_outdoor and not _map_data.is_empty():
			shadow_manager.rebuild(_map_data)
	
	if canvas_modulate:
		canvas_modulate.visible = not is_outdoor
		if is_outdoor:
			canvas_modulate.color = Color(1.0, 1.0, 1.0, 1.0)
	
	if is_instance_valid(player):
		var p_light = player.get_node_or_null("PointLight2D")
		if p_light:
			p_light.visible = not is_outdoor
			if not is_outdoor:
				# フロアタイプに応じてライトの色と強度を調整
				_apply_floor_lighting(p_light, canvas_modulate)

func _apply_floor_lighting(p_light: PointLight2D, canvas_modulate):
	# デフォルト: 通常ダンジョン（松明の暖色オレンジ）
	var light_color = Color(1.0, 0.80, 0.58, 1.0)
	var light_energy = 0.72
	var ambient_color = Color(0.06, 0.06, 0.10, 1.0)
	
	# 溶岩フロア判定 (branch 3 などで lava があるフロア)
	var has_lava = false
	var has_crystal = false
	var has_water_dominant = false
	
	# マップデータからフロアタイプを確認
	var lava_count = 0
	var crystal_count = 0
	var water_count = 0
	var floor_count = 0
	for x in range(min(MAP_WIDTH, 30)):
		for y in range(min(MAP_HEIGHT, 20)):
			match _map_data[x][y]:
				CellType.LAVA: lava_count += 1
				CellType.CRYSTAL_FLOOR: crystal_count += 1
				CellType.WATER: water_count += 1
				CellType.FLOOR: floor_count += 1
	
	if lava_count > 5:
		has_lava = true
	elif crystal_count > 5:
		has_crystal = true
	elif water_count > floor_count / 3:
		has_water_dominant = true
	
	if has_lava:
		# 溶岩フロア: 赤みがかった不気味なライト
		light_color = Color(1.0, 0.45, 0.15, 1.0)
		light_energy = 0.66
		ambient_color = Color(0.10, 0.03, 0.02, 1.0)
	elif has_crystal:
		# クリスタルフロア: 紫みがかった神秘的なライト
		light_color = Color(0.85, 0.70, 1.0, 1.0)
		light_energy = 0.70
		ambient_color = Color(0.04, 0.03, 0.10, 1.0)
	elif has_water_dominant:
		# 水場フロア: 青白い冷たいライト
		light_color = Color(0.75, 0.88, 1.0, 1.0)
		light_energy = 0.68
		ambient_color = Color(0.04, 0.05, 0.10, 1.0)
	
	# ライトカラー・エネルギーをアニメーションで適用
	var tween = create_tween()
	tween.tween_property(p_light, "color", light_color, 0.8)
	tween.parallel().tween_property(p_light, "energy", light_energy, 0.8)
	
	if canvas_modulate:
		var cm_tween = create_tween()
		cm_tween.tween_property(canvas_modulate, "color", ambient_color, 1.0)

func _update_shadow_cell(cell: Vector2i):
	if not shadow_manager or _is_on_world_map:
		return
	if cell.x < 0 or cell.x >= _map_data.size():
		return
	if cell.y < 0 or cell.y >= _map_data[cell.x].size():
		return
	var cell_type = _map_data[cell.x][cell.y]
	if cell_type == CellType.WALL or cell_type == CellType.FLOOR:
		shadow_manager.rebuild(_map_data)
	else:
		shadow_manager.update_cell(cell, cell_type)

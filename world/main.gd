extends Node2D

enum GameState { PLAYER_TURN, ENEMY_TURN }
var _current_game_state = GameState.PLAYER_TURN

@onready var player = $Player
@onready var tile_map = $TileMap
@onready var camera = $Camera2D
@onready var hit_sound_player = $HitSoundPlayer
@onready var player_ui = $PlayerUI

const EnemyScene = preload("res://actors/enemy/enemy.tscn")
const StairsScene = preload("res://world/stairs.tscn")

const TILE_SIZE = 32
const MAP_WIDTH = 50
const MAP_HEIGHT = 30

const FOV_RADIUS = 8

const ROOM_MAX_COUNT = 20
const ROOM_MIN_SIZE = 3
const ROOM_MAX_SIZE = 8
const MAX_ENEMIES_PER_ROOM = 2

enum CellType { WALL, FLOOR }
var _map_data = []
var _visible_tiles = []
var _explored_tiles = []
var _rooms = []
var _astar_grid = AStarGrid2D.new()

var current_floor = 0

func _ready():
	randomize()
	_create_tileset()
	_generate_new_level()

func _generate_new_level():
	current_floor += 1
	print("Welcome to floor ", current_floor)

	_clear_level()

	_generate_map()
	_setup_pathfinding()
	
	# Add a layer for debug drawing
	tile_map.add_layer(-1)
	
	if not _rooms.is_empty():
		# Place player in the first room
		var first_room_center = _rooms[0].get_center()
		player.position = first_room_center * TILE_SIZE
		
		camera.position = player.position
		camera.make_current()
		camera.zoom = Vector2(1.0, 1.0)
		camera.position_smoothing_speed = 5.0
		
		_spawn_stairs()
	
	_spawn_enemies()
	_current_game_state = GameState.PLAYER_TURN
	_calculate_fov()
	_draw_map()
	
	if player_ui and player:
		player_ui.update_hp(player.hp, player.MAX_HP)

func _clear_level():
	# Remove all enemies and stairs from the previous level
	for child in get_children():
		if child.is_in_group("enemies") or child.is_in_group("stairs"):
			child.queue_free()
	
	tile_map.clear_layer(1) # Clear debug path layer
	tile_map.clear_layer(-1) # Clear debug drawing layer

const ACTION_UP_LEFT = "ui_up_left"
const ACTION_UP_RIGHT = "ui_up_right"
const ACTION_DOWN_LEFT = "ui_down_left"
const ACTION_DOWN_RIGHT = "ui_down_right"

func _unhandled_input(event):
	if _current_game_state != GameState.PLAYER_TURN:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		var action_taken = false
		if event.keycode == KEY_SPACE or event.keycode == KEY_KP_5 or event.keycode == KEY_CLEAR:
			action_taken = true

		var direction = Vector2.ZERO
		if Input.is_action_pressed(ACTION_UP_LEFT):
			direction = Vector2(-1, -1)
		elif Input.is_action_pressed(ACTION_UP_RIGHT):
			direction = Vector2(1, -1)
		elif Input.is_action_pressed(ACTION_DOWN_LEFT):
			direction = Vector2(-1, 1)
		elif Input.is_action_pressed(ACTION_DOWN_RIGHT):
			direction = Vector2(1, 1)
		else:
			if Input.is_action_pressed("ui_up"):
				direction.y = -1
			if Input.is_action_pressed("ui_down"):
				direction.y = 1
			if Input.is_action_pressed("ui_left"):
				direction.x = -1
			if Input.is_action_pressed("ui_right"):
				direction.x = 1

		if direction != Vector2.ZERO:
			action_taken = _try_move_character(player, direction)
		
		if action_taken:
			_current_game_state = GameState.ENEMY_TURN
			_process_enemy_turns()

func _try_move_character(character, direction: Vector2):
	var current_pos = character.position
	var target_pos = current_pos + direction * TILE_SIZE
	var target_grid_pos = Vector2i(target_pos / TILE_SIZE)
	
	if target_grid_pos.x < 0 or target_grid_pos.x >= MAP_WIDTH or \
	   target_grid_pos.y < 0 or target_grid_pos.y >= MAP_HEIGHT:
		return false

	if _map_data[target_grid_pos.x][target_grid_pos.y] == CellType.WALL:
		return false

	for child in get_children():
		if child.has_method("move") and child != character:
			var other_character_grid_pos = Vector2i(child.position / TILE_SIZE)
			if other_character_grid_pos == target_grid_pos:
				if child == player or character == player:
					_handle_attack(character, child)
					return true
				else:
					return false

	character.move(direction)
	if character == player:
		_calculate_fov()
		_draw_map()
	return true

func _process(delta):
	if player_ui and player:
		player_ui.update_hp(player.hp, player.MAX_HP)

func _process_enemy_turns():
	tile_map.clear_layer(1)
	var player_grid_pos = Vector2i(player.position / TILE_SIZE)
	for child in get_children():
		if child.is_in_group("enemies"):
			var enemy = child
			var enemy_grid_pos = Vector2i(enemy.position / TILE_SIZE)
			
			if enemy_grid_pos.x >= 0 and enemy_grid_pos.x < MAP_WIDTH and \
			   enemy_grid_pos.y >= 0 and enemy_grid_pos.y < MAP_HEIGHT:
				enemy.visible = _visible_tiles[enemy_grid_pos.x][enemy_grid_pos.y]
			
			if enemy.visible:
				var path = _astar_grid.get_point_path(enemy_grid_pos, player_grid_pos)
				
				for point in path:
					tile_map.set_cell(1, Vector2i(point), 1, Vector2i(0,0))
				
				if path.size() > 1:
					var next_step = path[1]
					var move_direction = next_step - Vector2(enemy_grid_pos)
					_try_move_character(enemy, move_direction)
	_current_game_state = GameState.PLAYER_TURN

func _handle_attack(attacker, defender):
	print("Attempting to play hit sound.")
	hit_sound_player.play()
	defender.take_damage(1)

func _spawn_enemies():
	for i in range(1, _rooms.size()):
		var room = _rooms[i]
		var enemy_count = randi_range(1, MAX_ENEMIES_PER_ROOM)
		
		for j in range(enemy_count):
			var x = randi_range(room.position.x, room.position.x + room.size.x - 1)
			var y = randi_range(room.position.y, room.position.y + room.size.y - 1)
			var enemy_pos = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			
			var enemy = EnemyScene.instantiate()
			enemy.position = enemy_pos
			enemy.add_to_group("enemies")
			add_child(enemy)
			enemy.visible = false

func _spawn_stairs():
	if _rooms.size() < 2:
		return

	var last_room = _rooms.back()
	var stairs_pos = last_room.get_center() * TILE_SIZE
	
	var stairs = StairsScene.instantiate()
	stairs.position = stairs_pos
	stairs.add_to_group("stairs")
	stairs.player_entered_stairs.connect(_on_player_entered_stairs)
	add_child(stairs)
	print("Stairs spawned at ", stairs_pos / TILE_SIZE)

func _on_player_entered_stairs():
	print("Player entered stairs! Generating new level.")
	_generate_new_level()

func _create_tileset():
	var tileset = TileSet.new()
	var source = TileSetAtlasSource.new()
	
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	var wall_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	wall_image.fill(Color.from_hsv(0, 0, 0.2))
	
	var floor_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	floor_image.fill(Color.from_hsv(0, 0, 0.5))
	
	var combined_image = Image.create(TILE_SIZE * 2, TILE_SIZE, false, Image.FORMAT_RGBA8)
	combined_image.blit_rect(wall_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(0, 0))
	combined_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(TILE_SIZE, 0))
	
	var texture = ImageTexture.create_from_image(combined_image)
	source.texture = texture
	
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	
tileset.add_source(source, 0)
	
	var debug_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	debug_image.fill(Color(1, 0, 0, 0.5))
	var debug_texture = ImageTexture.create_from_image(debug_image)
	var debug_source = TileSetAtlasSource.new()
	debug_source.texture = debug_texture
	debug_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	debug_source.create_tile(Vector2i(0,0))
	tileset.add_source(debug_source, 1)
	
tile_map.tile_set = tileset

func _generate_map():
	_map_data.resize(MAP_WIDTH)
	_visible_tiles.resize(MAP_WIDTH)
	_explored_tiles.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		_map_data[x] = []
		_map_data[x].resize(MAP_HEIGHT)
		_visible_tiles[x] = []
		_visible_tiles[x].resize(MAP_HEIGHT)
		_explored_tiles[x] = []
		_explored_tiles[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			_map_data[x][y] = CellType.WALL
			_visible_tiles[x][y] = false
			_explored_tiles[x][y] = false
	
	_rooms.clear()
	
	for i in range(ROOM_MAX_COUNT):
		var w = randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var h = randi_range(ROOM_MIN_SIZE, ROOM_MAX_SIZE)
		var x = randi_range(1, MAP_WIDTH - w - 1)
		var y = randi_range(1, MAP_HEIGHT - h - 1)
		
		var new_room = Rect2i(x, y, w, h)
		
		var failed = false
		for other_room in _rooms:
			if new_room.intersects(other_room.grow(1)):
				failed = true
				break
		
		if not failed:
			_create_room(new_room)
			
			if not _rooms.is_empty():
				var prev_room_center = _rooms.back().get_center()
				_create_tunnels(prev_room_center, new_room.get_center())
			
			_rooms.append(new_room)

func _setup_pathfinding():
	_astar_grid.clear()
	_astar_grid.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	_astar_grid.cell_size = Vector2(1, 1)
	_astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS

	var wall_count = 0
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _map_data[x][y] == CellType.FLOOR:
				_astar_grid.set_point_solid(Vector2i(x, y), false)
			else:
				_astar_grid.set_point_solid(Vector2i(x, y), true)
				wall_count += 1
	
	print("A* setup: Found ", wall_count, " wall tiles.")
	_astar_grid.update()

func _create_room(rect: Rect2i):
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			_map_data[x][y] = CellType.FLOOR

func _create_tunnels(start: Vector2i, end: Vector2i):
	for x in range(min(start.x, end.x), max(start.x, end.x) + 1):
		_map_data[x][start.y] = CellType.FLOOR
	
	for y in range(min(start.y, end.y), max(start.y, end.y) + 1):
		_map_data[end.x][y] = CellType.FLOOR

func _draw_map():
	tile_map.clear()
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _explored_tiles[x][y]:
				var cell = _map_data[x][y]
				var tile_coords = Vector2i(x, y)
				var tile_index = 1 if cell == CellType.FLOOR else 0
				tile_map.set_cell(0, tile_coords, 0, Vector2i(tile_index, 0))
	
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if _visible_tiles[x][y]:
				var cell = _map_data[x][y]
				var tile_coords = Vector2i(x, y)
				var tile_index = 1 if cell == CellType.FLOOR else 0
				tile_map.set_cell(0, tile_coords, 0, Vector2i(tile_index, 0))

func _calculate_fov():
	# Reset visible tiles
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			_visible_tiles[x][y] = false
	
	var player_grid_pos = Vector2i(player.position / TILE_SIZE)
	
	if player_grid_pos.x >= 0 and player_grid_pos.x < MAP_WIDTH and \
	   player_grid_pos.y >= 0 and player_grid_pos.y < MAP_HEIGHT:
		_visible_tiles[player_grid_pos.x][player_grid_pos.y] = true
		_explored_tiles[player_grid_pos.x][player_grid_pos.y] = true
	
	for angle in range(0, 360, 5):
		var rad = deg_to_rad(angle)
		var dx = cos(rad)
		var dy = sin(rad)
		
		var x = player_grid_pos.x + 0.5
		var y = player_grid_pos.y + 0.5
		
		for i in range(1, FOV_RADIUS + 1):
			var check_x = int(x + dx * i)
			var check_y = int(y + dy * i)
			
			if check_x < 0 or check_x >= MAP_WIDTH or check_y < 0 or check_y >= MAP_HEIGHT:
				break
			
			_visible_tiles[check_x][check_y] = true
			_explored_tiles[check_x][check_y] = true
			
			if _map_data[check_x][check_y] == CellType.WALL:
				break

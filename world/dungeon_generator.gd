class_name DungeonGenerator
extends Node

const WorldCell = MapDefinitions.WorldCell
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const CellType = MapDefinitions.CellType

var _floor: int = 0
var _branch: int = 0

func generate_map(current_floor: int, current_branch: int, local_type: int = -1, main_inst: Node2D = null, is_starting_village: bool = false, is_dungeon_village: bool = false) -> Dictionary:
	_floor = current_floor
	_branch = current_branch
	
	if current_floor == 0:
		var res = generate_local_overworld(local_type, main_inst, is_starting_village, is_dungeon_village)
		_make_edges_walkable(res["map_data"])
		_blend_overworld_edges(res["map_data"], local_type, main_inst)
		return res
	if current_floor == 6:
		return _generate_village()
		
	var map_data = []
	map_data.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		map_data[x] = []
		map_data[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			map_data[x][y] = CellType.WALL
	
	var rooms = []
	
	var max_rooms = MapDefinitions.ROOM_MAX_COUNT
	if current_branch == 10:
		max_rooms = 8
		
	# Generate Rooms
	for i in range(max_rooms):
		var w = randi_range(MapDefinitions.ROOM_MIN_SIZE, MapDefinitions.ROOM_MAX_SIZE)
		var h = randi_range(MapDefinitions.ROOM_MIN_SIZE, MapDefinitions.ROOM_MAX_SIZE)
		var x = randi_range(1, MAP_WIDTH - w - 1)
		var y = randi_range(1, MAP_HEIGHT - h - 1)
		var new_room = Rect2i(x, y, w, h)
		
		var failed = false
		for other_room in rooms:
			if new_room.intersects(other_room.grow(1)):
				failed = true
				break
		
		if not failed:
			# Randomly choose room type: 0 = Rect, 1 = Ellipse/Round, 2 = Irregular
			var room_type = 0
			# Only use fancy shapes for slightly larger rooms to ensure they are navigable
			if w >= 5 and h >= 5:
				room_type = randi() % 3
			
			_create_room(map_data, new_room, room_type)
			
			if not rooms.is_empty():
				_create_tunnels(map_data, rooms.back().get_center(), new_room.get_center())
			rooms.append(new_room)
			
	# Water Generation
	var water_chance = 50
	var water_steps = 4
	var grass_chance = 10
	
	if current_branch == 1:
		water_chance = min(90, 65 + current_floor)
		grass_chance = 10
	elif current_branch == 2: # Blue Branch (Water Area)
		water_chance = 80 # Very high water chance
		grass_chance = 5
		water_steps = 3
	elif current_branch == 3: # Green Branch (Grass Area)
		water_chance = 0
		grass_chance = 90 # Very high grass chance
		water_steps = 0
	elif current_branch == 4: # Red Branch (Volcanic Area)
		water_chance = 0
		grass_chance = 0
		water_steps = 0
	elif current_branch == 5: # Purple Branch (Crystal Area)
		water_chance = 5
		grass_chance = 0
		water_steps = 1
	elif current_branch == 10: # Beginner Branch
		water_chance = 15
		grass_chance = 60
		water_steps = 2
	else:
		var depth_factor = clamp(current_floor - 1, 0, 10)
		water_chance = clamp(25 + depth_factor * 1, 20, 40)
		grass_chance = clamp(25 - depth_factor, 10, 25)
		
	_generate_water(map_data, water_chance, water_steps)
	if current_branch == 4:
		_generate_volcanic_ash(map_data, 85)
		_generate_lava(map_data, 38, 3)
	elif current_branch == 5:
		_generate_crystal_floor(map_data, 55, 4)
	
	# Waterway Generation (Floor 8+ OR Blue Branch)
	# In Blue Branch (2), water tunnels are common
	if current_branch != 10 and (current_branch == 2 or (current_floor >= 8 and current_branch != 4 and current_branch != 5)) and not rooms.is_empty():
		var tunnel_count = 3
		if current_branch == 2: tunnel_count = 6
		
		for j in range(tunnel_count): # Create a few random water connections
			var room1 = rooms.pick_random()
			var room2 = rooms.pick_random()
			if room1 != room2:
				_create_water_tunnels(map_data, room1.get_center(), room2.get_center())
	
	if not rooms.is_empty():
		_ensure_dry_path(map_data, rooms[0].get_center(), rooms.back().get_center())
		
	_generate_grass(map_data, grass_chance, 5)
	
	# Final Connectivity
	if not rooms.is_empty():
		_ensure_connectivity(map_data, rooms[0].get_center(), rooms.back().get_center())
		
		var last_room_center = rooms.back().get_center()
		var first_room_center = rooms[0].get_center()
		
		# Place STAIRS_UP (Upward stairs) at starting room center
		map_data[first_room_center.x][first_room_center.y] = CellType.STAIRS_UP
		
		if current_branch == 10:
			if current_floor == 3:
				# 3F is the bottom: no down stairs, place return stairs in the last room
				map_data[last_room_center.x][last_room_center.y] = CellType.STAIRS_GOLD
			else:
				map_data[last_room_center.x][last_room_center.y] = CellType.STAIRS
		else:
			# Place STAIRS (Normal) - ALWAYS
			map_data[last_room_center.x][last_room_center.y] = CellType.STAIRS
			
			# Place Branch Stairs
			var branch_stairs = [CellType.STAIRS_BLUE, CellType.STAIRS_GREEN, CellType.STAIRS_RED, CellType.STAIRS_PURPLE]
			var special_stair_type = branch_stairs.pick_random()
				
			var neighbors = [Vector2i(2,0), Vector2i(-2,0), Vector2i(0,2), Vector2i(0,-2), Vector2i(1,1), Vector2i(-1,-1)]
			neighbors.shuffle()
			for n in neighbors:
				var target = last_room_center + n
				if target.x >= 0 and target.x < MAP_WIDTH and target.y >= 0 and target.y < MAP_HEIGHT:
					var cell = map_data[target.x][target.y]
					if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.VOLCANIC_ASH or cell == CellType.CRYSTAL_FLOOR:
						map_data[target.x][target.y] = special_stair_type
						break
					
	if current_branch != 10:
		# Calculate main path between stairs before generating pits
		var main_path = []
		if not rooms.is_empty():
			var astar = AStarGrid2D.new()
			astar.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
			astar.cell_size = Vector2(1, 1)
			astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
			astar.update()
			
			for x in range(MAP_WIDTH):
				for y in range(MAP_HEIGHT):
					if map_data[x][y] == CellType.WALL:
						astar.set_point_solid(Vector2i(x, y), true)
					else:
						astar.set_point_weight_scale(Vector2i(x, y), 1.0)
			
			var start_pos = rooms[0].get_center()
			var end_pos = rooms.back().get_center()
			main_path = astar.get_id_path(start_pos, end_pos)
		
		_generate_pits(map_data, rooms, main_path)
	_place_doors(map_data, rooms)
	
	if not rooms.is_empty():
		_prevent_locked_doors_on_main_path(map_data, rooms[0].get_center(), rooms.back().get_center())
	
	return {
		"map_data": map_data,
		"rooms": rooms
	}

func _generate_overworld(main_inst: Node2D = null, is_starting_village: bool = false, is_dungeon_village: bool = false) -> Dictionary:
	var map_data = []
	map_data.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		map_data[x] = []
		map_data[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			map_data[x][y] = CellType.WALL
			
	var margin = 2
	for x in range(margin, MAP_WIDTH - margin):
		for y in range(margin, MAP_HEIGHT - margin):
			map_data[x][y] = CellType.FLOOR
				
	var pond_centers = []
	for p in range(randi_range(2, 4)):
		var px = randi_range(margin + 4, MAP_WIDTH - margin - 5)
		var py = randi_range(margin + 4, MAP_HEIGHT - margin - 5)
		pond_centers.append(Vector2i(px, py))
		
	for center in pond_centers:
		var radius = randi_range(2, 4)
		for x in range(center.x - radius, center.x + radius + 1):
			for y in range(center.y - radius, center.y + radius + 1):
				if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
					if Vector2(x - center.x, y - center.y).length() <= radius:
						map_data[x][y] = CellType.WATER
						
	var road_tiles = []
	var road_y = MAP_HEIGHT / 2
	var road_x = MAP_WIDTH / 2
	
	var has_left = false
	var has_right = false
	var has_up = false
	var has_down = false
	
	if main_inst and main_inst._world_map_data.size() > 0:
		var wx = main_inst._world_player_pos.x
		var wy = main_inst._world_player_pos.y
		var w_data = main_inst._world_map_data
		
		var _is_road_like = func(cell_val) -> bool:
			return cell_val == WorldCell.ROAD or cell_val == WorldCell.VILLAGE or cell_val == WorldCell.DUNGEON
			
		if wx > 0 and _is_road_like.call(w_data[wx - 1][wy]): has_left = true
		if wx < MAP_WIDTH - 1 and _is_road_like.call(w_data[wx + 1][wy]): has_right = true
		if wy > 0 and _is_road_like.call(w_data[wx][wy - 1]): has_up = true
		if wy < MAP_HEIGHT - 1 and _is_road_like.call(w_data[wx][wy + 1]): has_down = true
		
	# Fallback to horizontal road if no neighbors found
	if not (has_left or has_right or has_up or has_down):
		has_left = true
		has_right = true
	
	var cave_entrance = Vector2i(road_x - 3, road_y - 3)
	
	# 洞窟の入口（階段）の配置 - 道路生成の前に配置して保護する
	if is_starting_village:
		map_data[cave_entrance.x][cave_entrance.y] = CellType.STAIRS_GOLD
	elif is_dungeon_village:
		# ダンジョン村は独自のブランチ（青い階段→ブランチ2）に繋がる
		map_data[cave_entrance.x][cave_entrance.y] = CellType.STAIRS_BLUE
	else:
		map_data[cave_entrance.x][cave_entrance.y] = CellType.FLOOR
		
	if has_left:
		for x in range(0, road_x + 1):
			var cur = map_data[x][road_y]
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[x][road_y] = CellType.ASH
			var cur2 = map_data[x][road_y + 1]
			if cur2 != CellType.STAIRS and cur2 != CellType.STAIRS_GOLD and cur2 != CellType.STAIRS_UP and cur2 != CellType.STAIRS_BLUE and cur2 != CellType.STAIRS_GREEN and cur2 != CellType.STAIRS_RED and cur2 != CellType.STAIRS_PURPLE:
				map_data[x][road_y + 1] = CellType.ASH
			road_tiles.append(Vector2i(x, road_y))
			road_tiles.append(Vector2i(x, road_y + 1))
	if has_right:
		for x in range(road_x, MAP_WIDTH):
			var cur = map_data[x][road_y]
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[x][road_y] = CellType.ASH
			var cur2 = map_data[x][road_y + 1]
			if cur2 != CellType.STAIRS and cur2 != CellType.STAIRS_GOLD and cur2 != CellType.STAIRS_UP and cur2 != CellType.STAIRS_BLUE and cur2 != CellType.STAIRS_GREEN and cur2 != CellType.STAIRS_RED and cur2 != CellType.STAIRS_PURPLE:
				map_data[x][road_y + 1] = CellType.ASH
			road_tiles.append(Vector2i(x, road_y))
			road_tiles.append(Vector2i(x, road_y + 1))
	if has_up:
		for y in range(0, road_y + 1):
			var cur = map_data[road_x][y]
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[road_x][y] = CellType.ASH
			var cur2 = map_data[road_x + 1][y]
			if cur2 != CellType.STAIRS and cur2 != CellType.STAIRS_GOLD and cur2 != CellType.STAIRS_UP and cur2 != CellType.STAIRS_BLUE and cur2 != CellType.STAIRS_GREEN and cur2 != CellType.STAIRS_RED and cur2 != CellType.STAIRS_PURPLE:
				map_data[road_x + 1][y] = CellType.ASH
			road_tiles.append(Vector2i(road_x, y))
			road_tiles.append(Vector2i(road_x + 1, y))
	if has_down:
		for y in range(road_y, MAP_HEIGHT):
			var cur = map_data[road_x][y]
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[road_x][y] = CellType.ASH
			var cur2 = map_data[road_x + 1][y]
			if cur2 != CellType.STAIRS and cur2 != CellType.STAIRS_GOLD and cur2 != CellType.STAIRS_UP and cur2 != CellType.STAIRS_BLUE and cur2 != CellType.STAIRS_GREEN and cur2 != CellType.STAIRS_RED and cur2 != CellType.STAIRS_PURPLE:
				map_data[road_x + 1][y] = CellType.ASH
			road_tiles.append(Vector2i(road_x, y))
			road_tiles.append(Vector2i(road_x + 1, y))
	
	var square_w = 6
	var square_h = 6
	var square = Rect2i(road_x - 2, road_y - 2, square_w, square_h)
	for x in range(square.position.x, square.position.x + square.size.x):
		for y in range(square.position.y, square.position.y + square.size.y):
			if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
				var cur = map_data[x][y]
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.ASH
	
	var rooms = [square]
	var house_count = randi_range(3, 4)
	var houses = []
	
	for attempt in range(50):
		if houses.size() >= house_count: break
		var hw = randi_range(5, 7)
		var hh = randi_range(5, 6)
		var hx = randi_range(margin + 1, MAP_WIDTH - margin - hw - 1)
		var hy = randi_range(margin + 1, MAP_HEIGHT - margin - hh - 1)
		var house_rect = Rect2i(hx, hy, hw, hh)
		
		var overlap = false
		for other in rooms:
			if house_rect.intersects(other.grow(2)):
				overlap = true
				break
				
		if not overlap:
			for x in range(house_rect.position.x, house_rect.position.x + house_rect.size.x):
				for y in range(house_rect.position.y, house_rect.position.y + house_rect.size.y):
					if Vector2i(x, y) in road_tiles:
						overlap = true
						break
				if overlap: break
				
		if not overlap:
			if house_rect.has_point(cave_entrance) or house_rect.grow(1).has_point(cave_entrance):
				overlap = true
				
		if overlap: continue
		
		for x in range(house_rect.position.x, house_rect.position.x + house_rect.size.x):
			for y in range(house_rect.position.y, house_rect.position.y + house_rect.size.y):
				if x == house_rect.position.x or x == house_rect.position.x + house_rect.size.x - 1 \
				or y == house_rect.position.y or y == house_rect.position.y + house_rect.size.y - 1:
					map_data[x][y] = CellType.WALL
				else:
					map_data[x][y] = CellType.CRYSTAL_FLOOR
					
		var door_pos = Vector2i(house_rect.position.x + hw/2, house_rect.position.y + hh - 1)
		map_data[door_pos.x][door_pos.y] = CellType.DOOR_CLOSED
		rooms.append(house_rect)
		houses.append(house_rect)
		
	# 階段のある Rect を rooms の最後に設定する（Mainの処理が rooms.back() を参照するため）
	var exit_rect = Rect2i(cave_entrance.x, cave_entrance.y, 1, 1)
	rooms.append(exit_rect)
	
	# 緑化 (屋外の残った FLOOR を一部 GRASS にする)
	_generate_grass(map_data, 42, 4)
	
	return {
		"map_data": map_data,
		"rooms": rooms
	}

func _generate_village() -> Dictionary:
	var map_data = []
	map_data.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		map_data[x] = []
		map_data[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			map_data[x][y] = CellType.WALL
			
	# 1. 屋外エリアのくり抜き (外周4マスは壁を残す)
	var margin = 4
	for x in range(margin, MAP_WIDTH - margin):
		for y in range(margin, MAP_HEIGHT - margin):
			map_data[x][y] = CellType.FLOOR
			
	# 2. 道路パターンの決定
	# 石畳(ASH)で道路を引く。幅は2マス。
	var road_tiles = [] # 道路の座標リスト
	var road_y = randi_range(MAP_HEIGHT / 3, MAP_HEIGHT * 2 / 3)
	
	# 縦のサブ道路 (ランダムで交差させる)
	var has_vertical_road = randf() < 0.7
	var road_x = randi_range(MAP_WIDTH / 3, MAP_WIDTH * 2 / 3)
	
	# 3. 階段（出口）の配置 - 道路生成の前に配置して保護する
	# 道路の端のいずれか（水平ロードの左端、右端、または垂直ロードの上端、下端）にランダム配置
	# 道路は2マス幅なので、階段は道路の外側に配置する
	var stair_positions = []
	stair_positions.append(Vector2i(margin, road_y - 2)) # 左端（道路の上）
	stair_positions.append(Vector2i(MAP_WIDTH - margin - 1, road_y - 2)) # 右端（道路の上）
	stair_positions.append(Vector2i(margin, road_y + 2)) # 左端（道路の下）
	stair_positions.append(Vector2i(MAP_WIDTH - margin - 1, road_y + 2)) # 右端（道路の下）
	if has_vertical_road:
		stair_positions.append(Vector2i(road_x - 2, margin)) # 上端（道路の左）
		stair_positions.append(Vector2i(road_x + 2, margin)) # 上端（道路の右）
		stair_positions.append(Vector2i(road_x - 2, MAP_HEIGHT - margin - 1)) # 下端（道路の左）
		stair_positions.append(Vector2i(road_x + 2, MAP_HEIGHT - margin - 1)) # 下端（道路の右）
	
	# 有効な階段位置のみをフィルタリング
	var valid_stair_positions = []
	for pos in stair_positions:
		if pos.x >= margin and pos.x < MAP_WIDTH - margin and pos.y >= margin and pos.y < MAP_HEIGHT - margin:
			valid_stair_positions.append(pos)
	
	# 有効な位置がない場合はフォールバック
	if valid_stair_positions.is_empty():
		valid_stair_positions.append(Vector2i(margin, margin))
		valid_stair_positions.append(Vector2i(MAP_WIDTH - margin - 1, margin))
		valid_stair_positions.append(Vector2i(margin, MAP_HEIGHT - margin - 1))
		valid_stair_positions.append(Vector2i(MAP_WIDTH - margin - 1, MAP_HEIGHT - margin - 1))
		
	var stair_pos = valid_stair_positions.pick_random()
	map_data[stair_pos.x][stair_pos.y] = CellType.STAIRS
	
	# 4. 道路の生成（階段を保護）
	# 横のメイン道路
	for x in range(margin, MAP_WIDTH - margin):
		var cur = map_data[x][road_y]
		if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
			map_data[x][road_y] = CellType.ASH
		var cur2 = map_data[x][road_y + 1]
		if cur2 != CellType.STAIRS and cur2 != CellType.STAIRS_GOLD and cur2 != CellType.STAIRS_UP and cur2 != CellType.STAIRS_BLUE and cur2 != CellType.STAIRS_GREEN and cur2 != CellType.STAIRS_RED and cur2 != CellType.STAIRS_PURPLE:
			map_data[x][road_y + 1] = CellType.ASH
		road_tiles.append(Vector2i(x, road_y))
		road_tiles.append(Vector2i(x, road_y + 1))
		
	if has_vertical_road:
		for y in range(margin, MAP_HEIGHT - margin):
			var cur = map_data[road_x][y]
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[road_x][y] = CellType.ASH
			var cur2 = map_data[road_x + 1][y]
			if cur2 != CellType.STAIRS and cur2 != CellType.STAIRS_GOLD and cur2 != CellType.STAIRS_UP and cur2 != CellType.STAIRS_BLUE and cur2 != CellType.STAIRS_GREEN and cur2 != CellType.STAIRS_RED and cur2 != CellType.STAIRS_PURPLE:
				map_data[road_x + 1][y] = CellType.ASH
			road_tiles.append(Vector2i(road_x, y))
			road_tiles.append(Vector2i(road_x + 1, y))

	# 3. 広場と井戸の配置
	# 交差点（縦道がない場合は横道の中央）を広場にする
	var center_x = road_x if has_vertical_road else MAP_WIDTH / 2
	var center_y = road_y
	
	var square_w = randi_range(6, 8)
	var square_h = randi_range(6, 8)
	var square = Rect2i(center_x - square_w/2, center_y - square_h/2, square_w, square_h)
	
	for x in range(square.position.x, square.position.x + square.size.x):
		for y in range(square.position.y, square.position.y + square.size.y):
			if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
				var cur = map_data[x][y]
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.ASH
				
	# 広場の中央に井戸(WATER)
	var well_positions = [
		Vector2i(center_x, center_y),
		Vector2i(center_x + 1, center_y),
		Vector2i(center_x, center_y + 1),
		Vector2i(center_x + 1, center_y + 1)
	]
	for pos in well_positions:
		var cur = map_data[pos.x][pos.y]
		if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
			map_data[pos.x][pos.y] = CellType.WATER

	# 4. 民家 (建物) の配置
	var rooms = [square] # 0番目は広場 (プレイヤーの初期位置スポーン用)
	var house_count = randi_range(5, 7)
	var houses = []
	
	# 民家を配置する試行
	for attempt in range(50):
		if houses.size() >= house_count: break
		
		# ランダムな家サイズ
		var hw = randi_range(5, 8)
		var hh = randi_range(5, 7)
		# 屋外エリア内に配置
		var hx = randi_range(margin + 1, MAP_WIDTH - margin - hw - 1)
		var hy = randi_range(margin + 1, MAP_HEIGHT - margin - hh - 1)
		var house_rect = Rect2i(hx, hy, hw, hh)
		
		# 道路や他の建物と重なっていないかチェック
		# 建物同士は2マス以上空ける
		var overlap = false
		for other in rooms:
			if house_rect.intersects(other.grow(2)):
				overlap = true
				break
				
		# 道路との重なりチェック
		if not overlap:
			for x in range(house_rect.position.x, house_rect.position.x + house_rect.size.x):
				for y in range(house_rect.position.y, house_rect.position.y + house_rect.size.y):
					if Vector2i(x, y) in road_tiles:
						overlap = true
						break
				if overlap: break
				
		if overlap: continue
		
		# 家の生成
		# 外周を WALL、内側を CRYSTAL_FLOOR にする
		for x in range(house_rect.position.x, house_rect.position.x + house_rect.size.x):
			for y in range(house_rect.position.y, house_rect.position.y + house_rect.size.y):
				if x == house_rect.position.x or x == house_rect.position.x + house_rect.size.x - 1 \
				or y == house_rect.position.y or y == house_rect.position.y + house_rect.size.y - 1:
					map_data[x][y] = CellType.WALL
				else:
					map_data[x][y] = CellType.CRYSTAL_FLOOR
					
		# ドアの配置
		# 道路に近い側の壁にドアを作る
		# 家の中心から上下左右のいずれかで、一番近い道路がある方向にドアを作る
		var house_center = house_rect.get_center()
		var door_pos = Vector2i.ZERO
		
		# 簡易判定: 縦横の道路までの距離
		var dist_to_road_y = abs(house_center.y - road_y)
		var dist_to_road_x = abs(house_center.x - road_x) if has_vertical_road else 999
		
		# ドアを配置する壁の向きを決定
		if dist_to_road_x < dist_to_road_y:
			# 縦の道路に近い -> 左右の壁にドア
			var door_x = house_rect.position.x if house_center.x < road_x else house_rect.position.x + house_rect.size.x - 1
			var door_y = house_center.y
			door_pos = Vector2i(door_x, door_y)
		else:
			# 横の道路に近い -> 上下の壁にドア
			var door_x = house_center.x
			var door_y = house_rect.position.y if house_center.y < road_y else house_rect.position.y + house_rect.size.y - 1
			door_pos = Vector2i(door_x, door_y)
			
		map_data[door_pos.x][door_pos.y] = CellType.DOOR_CLOSED
		
		# ドアから道路までの小道 (FLOOR) を引く
		# ドアの向きから真っ直ぐ道路に向かってFLOORを敷く
		if door_pos.x == house_rect.position.x: # 左ドア
			for px in range(margin, door_pos.x):
				if map_data[px][door_pos.y] == CellType.ASH: break
				var cur = map_data[px][door_pos.y]
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[px][door_pos.y] = CellType.FLOOR
		elif door_pos.x == house_rect.position.x + house_rect.size.x - 1: # 右ドア
			for px in range(door_pos.x + 1, MAP_WIDTH - margin):
				if map_data[px][door_pos.y] == CellType.ASH: break
				var cur = map_data[px][door_pos.y]
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[px][door_pos.y] = CellType.FLOOR
		elif door_pos.y == house_rect.position.y: # 上ドア
			for py in range(margin, door_pos.y):
				if map_data[door_pos.x][py] == CellType.ASH: break
				var cur = map_data[door_pos.x][py]
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[door_pos.x][py] = CellType.FLOOR
		else: # 下ドア
			for py in range(door_pos.y + 1, MAP_HEIGHT - margin):
				if map_data[door_pos.x][py] == CellType.ASH: break
				var cur = map_data[door_pos.x][py]
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[door_pos.x][py] = CellType.FLOOR
				
		rooms.append(house_rect)
		houses.append(house_rect)

	# 5. 上の階層へ戻るための上り階段を広場（井戸の横）に配置
	map_data[center_x - 2][center_y] = CellType.STAIRS_UP
	
	# 6. 緑化 (屋外の残った FLOOR を一部 GRASS にする)
	_generate_grass(map_data, 42, 4)
	
	# 7. 階段のある Rect を rooms の最後に設定する（Mainの処理が rooms.back() を参照するため）
	var exit_rect = Rect2i(stair_pos.x, stair_pos.y, 1, 1)
	rooms.append(exit_rect)
	
	return {
		"map_data": map_data,
		"rooms": rooms
	}

func _create_room(map_data: Array, rect: Rect2i, type: int = 0):
	var center = rect.get_center()
	var a = rect.size.x / 2.0
	var b = rect.size.y / 2.0
	
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			match type:
				0: # Rectangle
					map_data[x][y] = CellType.FLOOR
				1: # Ellipse / Round
					var dx = x - center.x
					var dy = y - center.y
					# Check if point is inside ellipse
					if (float(dx * dx) / (a * a)) + (float(dy * dy) / (b * b)) <= 1.0:
						map_data[x][y] = CellType.FLOOR
				2: # Irregular (Chunky)
					var dist_x = min(x - rect.position.x, rect.position.x + rect.size.x - 1 - x)
					var dist_y = min(y - rect.position.y, rect.position.y + rect.size.y - 1 - y)
					if dist_x <= 1 or dist_y <= 1:
						if randi() % 3 != 0: # 66% chance to be floor
							map_data[x][y] = CellType.FLOOR
					else:
						map_data[x][y] = CellType.FLOOR
						
	# Ensure center is always floor for connectivity
	map_data[center.x][center.y] = CellType.FLOOR
	# Also ensure a small cross at center for safety
	if rect.size.x > 2 and rect.size.y > 2:
		map_data[center.x + 1][center.y] = CellType.FLOOR
		map_data[center.x - 1][center.y] = CellType.FLOOR
		map_data[center.x][center.y + 1] = CellType.FLOOR
		map_data[center.x][center.y - 1] = CellType.FLOOR

# ---------------- Door Placement ----------------
# Places doors only at room entrances/exits, not in the middle of corridors
func _place_doors(map_data: Array, rooms: Array):
	var door_chance = 70 # percent
	var locked_chance = 10 # percent of doors that are locked
	if _branch == 10:
		locked_chance = 0
	
	# Helper function to check if a position is inside any room
	var is_in_room = func(pos: Vector2i) -> bool:
		for room in rooms:
			if room.has_point(pos):
				return true
		return false
	
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			if map_data[x][y] != CellType.FLOOR:
				continue
			
			var pos = Vector2i(x, y)
			var n = map_data[x][y - 1]
			var s = map_data[x][y + 1]
			var w = map_data[x - 1][y]
			var e = map_data[x + 1][y]
			
			# A valid door position is a floor tile where:
			# - exactly two OPPOSITE sides are walls (N/S or W/E)
			# - the other two sides are passable (floor, grass, stairs, or another door)
			# - AND it's at a room boundary (one adjacent tile is in a room, the other is not)
			var _passable = func(c: int) -> bool:
				return c == CellType.FLOOR or c == CellType.GRASS or c == CellType.ASH or c == CellType.CRYSTAL_FLOOR or \
					c == CellType.STAIRS or c == CellType.STAIRS_BLUE or \
					c == CellType.STAIRS_GREEN or c == CellType.STAIRS_RED or c == CellType.STAIRS_PURPLE or c == CellType.DOOR_CLOSED or c == CellType.DOOR_LOCKED
			
			var ns_walls = (n == CellType.WALL and s == CellType.WALL)
			var we_walls = (w == CellType.WALL and e == CellType.WALL)
			
			var is_corridor_entry = false
			if ns_walls and _passable.call(w) and _passable.call(e):
				is_corridor_entry = true
			elif we_walls and _passable.call(n) and _passable.call(s):
				is_corridor_entry = true
			
			if not is_corridor_entry:
				continue
			
			# Check if this is at a room boundary
			var is_room_boundary = false
			if ns_walls:
				# Check west and east positions
				var west_in_room = is_in_room.call(Vector2i(x - 1, y))
				var east_in_room = is_in_room.call(Vector2i(x + 1, y))
				if west_in_room != east_in_room:
					is_room_boundary = true
			elif we_walls:
				# Check north and south positions
				var north_in_room = is_in_room.call(Vector2i(x, y - 1))
				var south_in_room = is_in_room.call(Vector2i(x, y + 1))
				if north_in_room != south_in_room:
					is_room_boundary = true
			
			if is_room_boundary and randi() % 100 < door_chance:
				# Decide if this door should be locked
				if randi() % 100 < locked_chance:
					map_data[x][y] = CellType.DOOR_LOCKED
				else:
					map_data[x][y] = CellType.DOOR_CLOSED

func _create_tunnels(map_data: Array, start: Vector2i, end: Vector2i):
	for x in range(min(start.x, end.x), max(start.x, end.x) + 1):
		if start.y >= 0 and start.y < MAP_HEIGHT: map_data[x][start.y] = CellType.FLOOR
	for y in range(min(start.y, end.y), max(start.y, end.y) + 1):
		if end.x >= 0 and end.x < MAP_WIDTH: map_data[end.x][y] = CellType.FLOOR

func _create_water_tunnels(map_data: Array, start: Vector2i, end: Vector2i):
	for x in range(min(start.x, end.x), max(start.x, end.x) + 1):
		if start.y >= 0 and start.y < MAP_HEIGHT: 
			if map_data[x][start.y] == CellType.WALL: # Only replace walls to keep existing features
				map_data[x][start.y] = CellType.WATER
	for y in range(min(start.y, end.y), max(start.y, end.y) + 1):
		if end.x >= 0 and end.x < MAP_WIDTH: 
			if map_data[end.x][y] == CellType.WALL:
				map_data[end.x][y] = CellType.WATER

func _generate_water(map_data: Array, initial_chance: int, simulation_steps: int):
	var temp_map = []
	temp_map.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		temp_map[x] = []
		temp_map[x].resize(MAP_HEIGHT)

	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			temp_map[x][y] = map_data[x][y]
			if map_data[x][y] == CellType.FLOOR and randi() % 100 < initial_chance:
				temp_map[x][y] = CellType.WATER

	for i in range(simulation_steps):
		var next_map = []
		next_map.resize(MAP_WIDTH)
		for x in range(MAP_WIDTH):
			next_map[x] = []
			next_map[x].resize(MAP_HEIGHT)
		
		for x in range(1, MAP_WIDTH - 1):
			for y in range(1, MAP_HEIGHT - 1):
				var neighbor_water = 0
				for nx in range(x - 1, x + 2):
					for ny in range(y - 1, y + 2):
						if nx == x and ny == y: continue
						if temp_map[nx][ny] == CellType.WATER:
							neighbor_water += 1
				
				if temp_map[x][y] == CellType.FLOOR:
					if neighbor_water >= 5: next_map[x][y] = CellType.WATER
					else: next_map[x][y] = CellType.FLOOR
				else: # WATER or WALL
					if temp_map[x][y] == CellType.WATER and neighbor_water < 3:
						next_map[x][y] = CellType.FLOOR
					else:
						next_map[x][y] = temp_map[x][y]
		temp_map = next_map

	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var cur = map_data[x][y]
			if temp_map[x][y] == CellType.WATER and map_data[x][y] != CellType.WALL:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.WATER
			elif temp_map[x][y] == CellType.FLOOR and map_data[x][y] == CellType.WATER:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.FLOOR

func _generate_grass(map_data: Array, initial_chance: int, simulation_steps: int):
	var current_step_map = []
	current_step_map.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		current_step_map[x] = []
		current_step_map[x].resize(MAP_HEIGHT)

	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			current_step_map[x][y] = map_data[x][y]
			if map_data[x][y] == CellType.FLOOR and randi() % 100 < initial_chance:
				current_step_map[x][y] = CellType.GRASS
				
	for i in range(simulation_steps):
		var next_map = []
		next_map.resize(MAP_WIDTH)
		for x in range(MAP_WIDTH):
			next_map[x] = []
			next_map[x].resize(MAP_HEIGHT)
			
		for x in range(1, MAP_WIDTH - 1):
			for y in range(1, MAP_HEIGHT - 1):
				var neighbor_grass = 0
				for nx in range(x - 1, x + 2):
					for ny in range(y - 1, y + 2):
						if nx==x and ny==y: continue
						if current_step_map[nx][ny] == CellType.GRASS:
							neighbor_grass += 1
				
				var current_type = current_step_map[x][y]
				if current_type == CellType.FLOOR:
					if neighbor_grass >= 5: next_map[x][y] = CellType.GRASS
					else: next_map[x][y] = CellType.FLOOR
				elif current_type == CellType.GRASS:
					if neighbor_grass < 3: next_map[x][y] = CellType.FLOOR
					else: next_map[x][y] = CellType.GRASS
				else:
					next_map[x][y] = current_type
		current_step_map = next_map
		
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var cur = map_data[x][y]
			if current_step_map[x][y] == CellType.GRASS and map_data[x][y] == CellType.FLOOR:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.GRASS

func _generate_ash(map_data: Array, initial_chance: int):
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var cur = map_data[x][y]
			if cur == CellType.FLOOR and randi() % 100 < initial_chance:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.ASH

func _generate_volcanic_ash(map_data: Array, initial_chance: int):
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var cur = map_data[x][y]
			if cur == CellType.FLOOR and randi() % 100 < initial_chance:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.VOLCANIC_ASH

func _generate_lava(map_data: Array, initial_chance: int, simulation_steps: int):
	var temp_map = []
	temp_map.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		temp_map[x] = []
		temp_map[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			temp_map[x][y] = map_data[x][y]
			if (map_data[x][y] == CellType.FLOOR or map_data[x][y] == CellType.ASH) and randi() % 100 < initial_chance:
				temp_map[x][y] = CellType.LAVA

	for i in range(simulation_steps):
		var next_map = []
		next_map.resize(MAP_WIDTH)
		for x in range(MAP_WIDTH):
			next_map[x] = []
			next_map[x].resize(MAP_HEIGHT)
		for x in range(1, MAP_WIDTH - 1):
			for y in range(1, MAP_HEIGHT - 1):
				var lava_neighbors = 0
				for nx in range(x - 1, x + 2):
					for ny in range(y - 1, y + 2):
						if nx == x and ny == y: continue
						if temp_map[nx][ny] == CellType.LAVA:
							lava_neighbors += 1
				if temp_map[x][y] == CellType.LAVA:
					next_map[x][y] = CellType.LAVA if lava_neighbors >= 3 else CellType.ASH
				elif temp_map[x][y] == CellType.FLOOR or temp_map[x][y] == CellType.ASH:
					next_map[x][y] = CellType.LAVA if lava_neighbors >= 5 else temp_map[x][y]
				else:
					next_map[x][y] = temp_map[x][y]
		temp_map = next_map

	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var cur = map_data[x][y]
			if temp_map[x][y] == CellType.LAVA and map_data[x][y] != CellType.WALL:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.LAVA

func _generate_crystal_floor(map_data: Array, initial_chance: int, simulation_steps: int):
	var current_map = []
	current_map.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		current_map[x] = []
		current_map[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			current_map[x][y] = map_data[x][y]
			if map_data[x][y] == CellType.FLOOR and randi() % 100 < initial_chance:
				current_map[x][y] = CellType.CRYSTAL_FLOOR

	for i in range(simulation_steps):
		var next_map = []
		next_map.resize(MAP_WIDTH)
		for x in range(MAP_WIDTH):
			next_map[x] = []
			next_map[x].resize(MAP_HEIGHT)
		for x in range(1, MAP_WIDTH - 1):
			for y in range(1, MAP_HEIGHT - 1):
				var crystal_neighbors = 0
				for nx in range(x - 1, x + 2):
					for ny in range(y - 1, y + 2):
						if nx == x and ny == y: continue
						if current_map[nx][ny] == CellType.CRYSTAL_FLOOR:
							crystal_neighbors += 1
				if current_map[x][y] == CellType.FLOOR:
					next_map[x][y] = CellType.CRYSTAL_FLOOR if crystal_neighbors >= 5 else CellType.FLOOR
				elif current_map[x][y] == CellType.CRYSTAL_FLOOR:
					next_map[x][y] = CellType.FLOOR if crystal_neighbors < 3 else CellType.CRYSTAL_FLOOR
				else:
					next_map[x][y] = current_map[x][y]
		current_map = next_map

	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var cur = map_data[x][y]
			if current_map[x][y] == CellType.CRYSTAL_FLOOR and map_data[x][y] == CellType.FLOOR:
				if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
					map_data[x][y] = CellType.CRYSTAL_FLOOR

func _ensure_dry_path(map_data: Array, start: Vector2i, end: Vector2i):
	var astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var cell = map_data[x][y]
			if cell == CellType.WALL:
				astar.set_point_solid(Vector2i(x, y), true)
			elif cell == CellType.WATER or cell == CellType.LAVA:
				astar.set_point_weight_scale(Vector2i(x, y), 10.0)
			else:
				astar.set_point_weight_scale(Vector2i(x, y), 1.0)

	var path = astar.get_id_path(start, end)
	for point in path:
		var cur = map_data[point.x][point.y]
		if cur == CellType.WATER or cur == CellType.LAVA:
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[point.x][point.y] = CellType.FLOOR

func _ensure_connectivity(map_data: Array, start: Vector2i, end: Vector2i):
	var path_grid = AStarGrid2D.new()
	path_grid.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	path_grid.cell_size = Vector2(1, 1)
	path_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	path_grid.update()

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if map_data[x][y] == CellType.WALL:
				path_grid.set_point_solid(Vector2i(x, y), true)
			elif map_data[x][y] == CellType.WATER or map_data[x][y] == CellType.LAVA:
				path_grid.set_point_weight_scale(Vector2i(x, y), 10.0)
			else:
				path_grid.set_point_weight_scale(Vector2i(x, y), 1.0)

	var path = path_grid.get_point_path(start, end)
	for point in path:
		var pos = Vector2i(point)
		var cur = map_data[pos.x][pos.y]
		if cur == CellType.WATER or cur == CellType.LAVA:
			if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
				map_data[pos.x][pos.y] = CellType.FLOOR

func _prevent_locked_doors_on_main_path(map_data: Array, start: Vector2i, end: Vector2i):
	var astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, MAP_WIDTH, MAP_HEIGHT)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var cell = map_data[x][y]
			if cell == CellType.WALL:
				astar.set_point_solid(Vector2i(x, y), true)
			elif cell == CellType.WATER or cell == CellType.LAVA:
				astar.set_point_weight_scale(Vector2i(x, y), 10.0)
			else:
				astar.set_point_weight_scale(Vector2i(x, y), 1.0)

	var path = astar.get_id_path(start, end)
	for point in path:
		if map_data[point.x][point.y] == CellType.DOOR_LOCKED:
			map_data[point.x][point.y] = CellType.DOOR_CLOSED
			print("DungeonGenerator: Unlocked a door on main path at ", point)

func _generate_pits(map_data: Array, rooms: Array, main_path: Array = []):
	if rooms.is_empty():
		return
	
	var spawn_center = rooms[0].get_center()
	
	# Convert main_path to a set for quick lookup
	var path_set = {}
	for point in main_path:
		path_set[point] = true
	
	# Place pits in rooms, skipping the starting room
	for i in range(1, rooms.size()):
		var room = rooms[i]
		
		# 35% chance to generate a larger pit cluster in the room
		if randf() > 0.35:
			continue
			
		# Pick a seed point within the room
		var cx = randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
		var cy = randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
		var seed_pos = Vector2i(cx, cy)
		
		if cx <= 1 or cx >= MAP_WIDTH - 2 or cy <= 1 or cy >= MAP_HEIGHT - 2:
			continue
			
		if seed_pos.distance_to(spawn_center) < 6.0:
			continue
			
		# BFS expansion to grow pit cluster (size between 3 and 7 tiles)
		var pit_tiles = [seed_pos]
		var queue = [seed_pos]
		var max_size = randi_range(3, 7)
		var attempts = 0
		
		while queue.size() > 0 and pit_tiles.size() < max_size and attempts < 30:
			attempts += 1
			var curr = queue.pop_front()
			
			var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
			dirs.shuffle()
			for d in dirs:
				var nxt = curr + d
				if nxt.x >= room.position.x and nxt.x < room.position.x + room.size.x \
				and nxt.y >= room.position.y and nxt.y < room.position.y + room.size.y:
					
					if not pit_tiles.has(nxt) and pit_tiles.size() < max_size:
						var cell = map_data[nxt.x][nxt.y]
						if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.VOLCANIC_ASH or cell == CellType.CRYSTAL_FLOOR:
							pit_tiles.append(nxt)
							queue.append(nxt)
							
		# Validate all expanded tiles
		var valid_pit_tiles = []
		for tile in pit_tiles:
			var too_close = false
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var nx = tile.x + dx
					var ny = tile.y + dy
					if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
						var near_cell = map_data[nx][ny]
						if near_cell == CellType.STAIRS or near_cell == CellType.STAIRS_BLUE or near_cell == CellType.STAIRS_GREEN or near_cell == CellType.STAIRS_RED or near_cell == CellType.STAIRS_PURPLE:
							too_close = true
							break
						if near_cell == CellType.DOOR_CLOSED or near_cell == CellType.DOOR_OPEN or near_cell == CellType.DOOR_LOCKED:
							too_close = true
							break
				if too_close:
					break
			
			# Also check if tile is on the main path between stairs
			if tile in path_set:
				too_close = true
			
			if not too_close:
				valid_pit_tiles.append(tile)
				
		for tile in valid_pit_tiles:
			map_data[tile.x][tile.y] = CellType.PIT

func _generate_elevation_map(local_type: int) -> Array:
	var elevation = []
	elevation.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		elevation[x] = []
		elevation[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			elevation[x][y] = 0.0
	
	if local_type == WorldCell.SEA or local_type == WorldCell.VILLAGE:
		return elevation
	
	# Generate a simple elevation map using multiple sine waves for natural-looking terrain
	var base_elevation = 0.0
	match local_type:
		WorldCell.MOUNTAIN:
			base_elevation = 0.7  # High base
		WorldCell.FOREST:
			base_elevation = 0.35
		WorldCell.DUNGEON:
			base_elevation = 0.25
		_:
			base_elevation = 0.15  # GRASS, ROAD
	
	# Use multiple octaves of noise for organic terrain
	var seed = randi()
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			var fx = float(x) / float(MAP_WIDTH)
			var fy = float(y) / float(MAP_HEIGHT)
			
			# Multi-octave noise simulation
			var n1 = sin(fx * 3.0 + fy * 2.5 + seed * 0.1) * 0.5 + 0.5
			var n2 = sin(fx * 6.0 - fy * 4.0 + seed * 0.2) * 0.25 + 0.25
			var n3 = sin(fx * 12.0 + fy * 8.0 + seed * 0.3) * 0.125 + 0.125
			
			var noise_val = n1 * 0.5 + n2 * 0.3 + n3 * 0.2
			
			# Scale by base elevation
			var elev = noise_val * base_elevation * 2.0
			
			# Clamp and round to discrete levels for clearer visual difference
			elev = clamp(elev, 0.0, 1.0)
			# Discrete levels: 0.0, 0.2, 0.4, 0.6, 0.8, 1.0
			elev = round(elev * 5.0) / 5.0
			
			elevation[x][y] = elev
	
	return elevation

func generate_local_overworld(local_type: int, main_inst: Node2D = null, is_starting_village: bool = false, is_dungeon_village: bool = false) -> Dictionary:
	# If village, use the standard overworld village generation
	if local_type == WorldCell.VILLAGE:
		return _generate_overworld(main_inst, is_starting_village, is_dungeon_village)
		
	# Generate elevation data first
	var elevation = _generate_elevation_map(local_type)
	
	var map_data = []
	map_data.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		map_data[x] = []
		map_data[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			map_data[x][y] = CellType.WALL
			
	var margin = 2
	for x in range(margin, MAP_WIDTH - margin):
		for y in range(margin, MAP_HEIGHT - margin):
			match local_type:
				WorldCell.GRASS, WorldCell.GRASSLAND_EDGE:
					_generate_grassland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.FOREST, WorldCell.FOREST_EDGE:
					_generate_forest_terrain(map_data, x, y, elevation[x][y])
				WorldCell.DEEP_FOREST:
					_generate_deep_forest_terrain(map_data, x, y, elevation[x][y])
				WorldCell.CONIFER_FOREST:
					_generate_conifer_forest_terrain(map_data, x, y, elevation[x][y])
				WorldCell.DRYLAND:
					_generate_dryland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.DESERT, WorldCell.DESERT_EDGE:
					_generate_desert_terrain(map_data, x, y, elevation[x][y])
				WorldCell.ROCKLAND:
					_generate_rockland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.WETLAND:
					_generate_wetland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.SWAMP, WorldCell.SWAMP_EDGE:
					_generate_swamp_terrain(map_data, x, y, elevation[x][y])
				WorldCell.HIGHLAND:
					_generate_highland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.MOUNTAIN:
					_generate_mountain_terrain(map_data, x, y, elevation[x][y])
				WorldCell.SNOWLAND, WorldCell.SNOWLAND_EDGE:
					_generate_snowland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.FROZEN_LAND:
					_generate_frozen_terrain(map_data, x, y, elevation[x][y])
				WorldCell.COAST:
					_generate_coast_terrain(map_data, x, y, elevation[x][y])
				WorldCell.RIVERBANK:
					_generate_riverbank_terrain(map_data, x, y, elevation[x][y])
				WorldCell.LAKESHORE:
					_generate_lakeshore_terrain(map_data, x, y, elevation[x][y])
				WorldCell.WASTELAND:
					_generate_wasteland_terrain(map_data, x, y, elevation[x][y])
				WorldCell.ANOMALY_ZONE:
					_generate_anomaly_terrain(map_data, x, y, elevation[x][y])
				WorldCell.DUNGEON:
					_generate_dungeon_terrain(map_data, x, y, elevation[x][y])
				WorldCell.ROAD:
					_generate_road_terrain(map_data, x, y, elevation[x][y])
				WorldCell.SEA:
					map_data[x][y] = CellType.WATER
				_:
					map_data[x][y] = CellType.GRASS if randf() < 0.35 else CellType.FLOOR
					
	# Add trees (TREE/TREE_FRUIT) and rocks (ROCK) to make the overworld local maps interesting
	var tree_chance = 0.0
	var rock_chance = 0.0
	
	match local_type:
		WorldCell.FOREST:
			tree_chance = 0.12
			rock_chance = 0.01
		WorldCell.GRASS:
			tree_chance = 0.03
			rock_chance = 0.02
		WorldCell.ROAD:
			tree_chance = 0.01
			rock_chance = 0.01
		WorldCell.DUNGEON:
			tree_chance = 0.01
			rock_chance = 0.04
		WorldCell.MOUNTAIN:
			tree_chance = 0.18
			rock_chance = 0.05

	for x in range(margin + 2, MAP_WIDTH - margin - 2):
		for y in range(margin + 2, MAP_HEIGHT - margin - 2):
			if map_data[x][y] == CellType.ASH or \
			   map_data[x][y] == CellType.STAIRS or \
			   map_data[x][y] == CellType.STAIRS_GOLD or \
			   map_data[x][y] == CellType.WATER or \
			   map_data[x][y] == CellType.DOOR_CLOSED or \
			   map_data[x][y] == CellType.DOOR_LOCKED:
				continue
				
			if abs(x - MAP_WIDTH/2) < 4 and abs(y - MAP_HEIGHT/2) < 4:
				continue
				
			var r = randf()
			if r < tree_chance:
				map_data[x][y] = CellType.TREE_FRUIT if randf() < 0.25 else CellType.TREE
			elif r < tree_chance + rock_chance:
				map_data[x][y] = CellType.ROCK
					
	# Add a pond
	var pond_count = randi_range(1, 3)
	if local_type == WorldCell.FOREST: pond_count = randi_range(2, 4)
	if local_type == WorldCell.MOUNTAIN: pond_count = 0
	for p in range(pond_count):
		var px = randi_range(margin + 4, MAP_WIDTH - margin - 5)
		var py = randi_range(margin + 4, MAP_HEIGHT - margin - 5)
		var radius = randi_range(2, 4)
		for x in range(px - radius, px + radius + 1):
			for y in range(py - radius, py + radius + 1):
				if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
					if Vector2(x - px, y - py).length() <= radius:
						map_data[x][y] = CellType.WATER
						
	# Add cave entrance in dungeon local map
	var cave_entrance = Vector2i.ZERO
	if local_type == WorldCell.DUNGEON:
		var cx = MAP_WIDTH / 2
		var cy = MAP_HEIGHT / 2
		cave_entrance = Vector2i(cx, cy)
		
	# Draw dynamic connecting roads if local type is NOT SEA and NOT VILLAGE
	if local_type != WorldCell.SEA and local_type != WorldCell.VILLAGE:
		var has_left = false
		var has_right = false
		var has_up = false
		var has_down = false
		
		if main_inst and main_inst._world_map_data.size() > 0:
			var wx = main_inst._world_player_pos.x
			var wy = main_inst._world_player_pos.y
			var w_data = main_inst._world_map_data
			
			var _is_road_like = func(cell_val) -> bool:
				if local_type == WorldCell.MOUNTAIN:
					# 山道は、ワールドマップで歩ける隣接地形からのみ出入りできる。
					return _is_walkable_biome(cell_val) and cell_val != WorldCell.MOUNTAIN
				# 山に接するローカルマップには、山道へ通じる入口を作る。
				if cell_val == WorldCell.MOUNTAIN:
					return true
				return cell_val == WorldCell.ROAD or cell_val == WorldCell.VILLAGE or cell_val == WorldCell.DUNGEON
				
			if wx > 0 and _is_road_like.call(w_data[wx - 1][wy]): has_left = true
			if wx < MAP_WIDTH - 1 and _is_road_like.call(w_data[wx + 1][wy]): has_right = true
			if wy > 0 and _is_road_like.call(w_data[wx][wy - 1]): has_up = true
			if wy < MAP_HEIGHT - 1 and _is_road_like.call(w_data[wx][wy + 1]): has_down = true
			
		# Fallback to cross roads if no neighbors found AND it is a ROAD cell
		if local_type == WorldCell.ROAD and not (has_left or has_right or has_up or has_down):
			has_left = true
			has_right = true
			has_up = true
			has_down = true
			
		var cx = MAP_WIDTH / 2
		var cy = MAP_HEIGHT / 2
		
		# Define road width and length based on cell type
		var road_width = 3
		if local_type == WorldCell.ROAD:
			road_width = 4 # Make roads wider and more prominent when on a ROAD cell
			
		var path_len_x = MAP_WIDTH / 2
		var path_len_y = MAP_HEIGHT / 2
		
		# 平原・森は端から少し入った道に留め、山道は入口から中央の林まで確実につなぐ。
		if local_type == WorldCell.GRASS or local_type == WorldCell.FOREST:
			path_len_x = 7
			path_len_y = 7
		elif local_type == WorldCell.MOUNTAIN:
			road_width = 2
			
		# Draw horizontal road (Left)
		if has_left:
			var start_x = 0
			var end_x = cx if (local_type == WorldCell.ROAD or local_type == WorldCell.DUNGEON) else path_len_x
			for rx in range(start_x, end_x + 1):
				for w in range(-road_width/2, road_width/2 + (1 if road_width % 2 == 1 else 0)):
					var ry = cy + w
					if ry >= 0 and ry < MAP_HEIGHT:
						var cur = map_data[rx][ry]
						# Do not overwrite any stairs with road tiles
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[rx][ry] = CellType.ASH
						
		# Draw horizontal road (Right)
		if has_right:
			var start_x = MAP_WIDTH - 1
			var end_x = cx if (local_type == WorldCell.ROAD or local_type == WorldCell.DUNGEON) else MAP_WIDTH - 1 - path_len_x
			var r_range = range(end_x, start_x + 1)
			for rx in r_range:
				for w in range(-road_width/2, road_width/2 + (1 if road_width % 2 == 1 else 0)):
					var ry = cy + w
					if ry >= 0 and ry < MAP_HEIGHT:
						var cur = map_data[rx][ry]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[rx][ry] = CellType.ASH
						
		# Draw vertical road (Up)
		if has_up:
			var start_y = 0
			var end_y = cy if (local_type == WorldCell.ROAD or local_type == WorldCell.DUNGEON) else path_len_y
			for ry in range(start_y, end_y + 1):
				for w in range(-road_width/2, road_width/2 + (1 if road_width % 2 == 1 else 0)):
					var rx = cx + w
					if rx >= 0 and rx < MAP_WIDTH:
						var cur = map_data[rx][ry]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[rx][ry] = CellType.ASH
						
		# Draw vertical road (Down)
		if has_down:
			var start_y = MAP_HEIGHT - 1
			var end_y = cy if (local_type == WorldCell.ROAD or local_type == WorldCell.DUNGEON) else MAP_HEIGHT - 1 - path_len_y
			var r_range = range(end_y, start_y + 1)
			for ry in r_range:
				for w in range(-road_width/2, road_width/2 + (1 if road_width % 2 == 1 else 0)):
					var rx = cx + w
					if rx >= 0 and rx < MAP_WIDTH:
						var cur = map_data[rx][ry]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[rx][ry] = CellType.ASH
						
	var rooms = [Rect2i(MAP_WIDTH/2 - 2, MAP_HEIGHT/2 - 2, 4, 4)]
	
	# Clear spawn area
	for x in range(MAP_WIDTH/2 - 3, MAP_WIDTH/2 + 4):
		for y in range(MAP_HEIGHT/2 - 3, MAP_HEIGHT/2 + 4):
			if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
				var cur = map_data[x][y]
				if cur != CellType.ASH and Vector2i(x, y) != cave_entrance:
					if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
						map_data[x][y] = CellType.FLOOR

	# 道路と中央の安全地帯を残しつつ、地形のまとまりと探索対象を追加する。
	var protected_spawn = Rect2i(MAP_WIDTH / 2 - 4, MAP_HEIGHT / 2 - 4, 9, 9)
	_stamp_local_biomes(map_data, local_type, protected_spawn)
	_place_wilderness_buildings(map_data, rooms, local_type, protected_spawn)

	# Finally place the stairs and surrounding wall in dungeon local map (to avoid road/spawn clear overwrites)
	if local_type == WorldCell.DUNGEON:
		var cx = MAP_WIDTH / 2
		var cy = MAP_HEIGHT / 2
		for x in range(cx - 2, cx + 3):
			for y in range(cy - 2, cy + 3):
				if x == cx - 2 or x == cx + 2 or y == cy - 2 or y == cy + 2:
					if randf() < 0.70:
						map_data[x][y] = CellType.WALL
				else:
					map_data[x][y] = CellType.FLOOR
		map_data[cx][cy] = CellType.STAIRS

	return {
		"map_data": map_data,
		"rooms": rooms
	}

func _stamp_local_biomes(map_data: Array, local_type: int, protected_area: Rect2i) -> void:
	if local_type == WorldCell.SEA:
		return

	var feature_count = 3
	if local_type == WorldCell.FOREST:
		feature_count = randi_range(4, 6)
	elif local_type == WorldCell.MOUNTAIN:
		feature_count = randi_range(4, 5)
	elif local_type == WorldCell.ROAD:
		feature_count = randi_range(2, 3)
	elif local_type == WorldCell.DUNGEON:
		feature_count = randi_range(2, 4)

	for _feature in range(feature_count):
		var center = Vector2i(randi_range(5, MAP_WIDTH - 6), randi_range(5, MAP_HEIGHT - 6))
		if protected_area.has_point(center):
			continue

		var radius = randi_range(2, 5)
		var kind = "grove"
		var roll = randf()
		if local_type == WorldCell.MOUNTAIN:
			kind = "grove" if roll < 0.55 else "rocky"
		elif local_type == WorldCell.FOREST:
			kind = "grove" if roll < 0.50 else ("pond" if roll < 0.75 else "clearing")
		elif local_type == WorldCell.DUNGEON:
			kind = "rocky" if roll < 0.55 else "clearing"
		else:
			kind = "pond" if roll < 0.30 else ("grove" if roll < 0.65 else "rocky")

		for x in range(center.x - radius, center.x + radius + 1):
			for y in range(center.y - radius, center.y + radius + 1):
				var pos = Vector2i(x, y)
				if x < 3 or x >= MAP_WIDTH - 3 or y < 3 or y >= MAP_HEIGHT - 3:
					continue
				if protected_area.has_point(pos):
					continue
				if Vector2(pos.x - center.x, pos.y - center.y).length() > radius + randf_range(-0.7, 0.7):
					continue

				var current = map_data[x][y]
				if current == CellType.ASH or current == CellType.STAIRS or current == CellType.STAIRS_GOLD or current == CellType.STAIRS_UP or current == CellType.STAIRS_BLUE or current == CellType.STAIRS_GREEN or current == CellType.STAIRS_RED or current == CellType.STAIRS_PURPLE or current == CellType.DOOR_CLOSED or current == CellType.DOOR_LOCKED:
					continue

				match kind:
					"grove":
						if current != CellType.WATER and randf() < 0.72:
							map_data[x][y] = CellType.TREE_FRUIT if randf() < 0.12 else CellType.TREE
					"rocky":
						if current != CellType.WATER:
							map_data[x][y] = CellType.ROCK if randf() < 0.80 else CellType.WALL
					"pond":
						map_data[x][y] = CellType.WATER
					"clearing":
						if current != CellType.WATER:
							map_data[x][y] = CellType.GRASS if randf() < 0.65 else CellType.FLOOR

func _place_wilderness_buildings(map_data: Array, rooms: Array, local_type: int, protected_area: Rect2i) -> void:
	if local_type == WorldCell.SEA:
		return

	var target_count = 1
	if local_type == WorldCell.GRASS or local_type == WorldCell.ROAD:
		target_count = randi_range(1, 3)
	elif local_type == WorldCell.FOREST or local_type == WorldCell.MOUNTAIN:
		target_count = randi_range(1, 2)
	elif local_type == WorldCell.DUNGEON:
		target_count = 1

	var placed = 0
	for _attempt in range(80):
		if placed >= target_count:
			break

		# 30% chance to generate a maze-like building instead of a room-based one
		var is_maze = randf() < 0.30
		var width = randi_range(10, 15)
		var height = randi_range(7, 10)
		if is_maze:
			# Maze buildings need to be odd-sized for proper corridors
			width = randi_range(9, 15) | 1  # Ensure odd
			height = randi_range(9, 13) | 1 # Ensure odd
			
		var rect = Rect2i(
			randi_range(4, MAP_WIDTH - width - 5),
			randi_range(4, MAP_HEIGHT - height - 5),
			width,
			height
		)
		if rect.grow(2).intersects(protected_area):
			continue

		var blocked = false
		for room in rooms:
			if rect.grow(2).intersects(room.grow(2)):
				blocked = true
				break
		if blocked:
			continue

		for x in range(rect.position.x - 2, rect.end.x + 2):
			for y in range(rect.position.y - 2, rect.end.y + 2):
				if x < 2 or x >= MAP_WIDTH - 2 or y < 2 or y >= MAP_HEIGHT - 2:
					blocked = true
					break
				var cell = map_data[x][y]
				if cell == CellType.ASH or cell == CellType.WATER or cell == CellType.STAIRS or cell == CellType.STAIRS_GOLD or cell == CellType.STAIRS_UP or cell == CellType.STAIRS_BLUE or cell == CellType.STAIRS_GREEN or cell == CellType.STAIRS_RED or cell == CellType.STAIRS_PURPLE:
					blocked = true
					break
			if blocked:
				break
		if blocked:
			continue

		if is_maze:
			_generate_maze_building(map_data, rect)
		else:
			# Standard room-based building
			_generate_room_building(map_data, rect)

		rooms.append(rect)
		placed += 1

func _generate_room_building(map_data: Array, rect: Rect2i) -> void:
	# 床材と間取りを変え、同じ箱型の建物が連続しないようにする。
	var floor_type = CellType.CRYSTAL_FLOOR if randf() < 0.55 else CellType.FLOOR
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var is_outer_wall = x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1
			map_data[x][y] = CellType.WALL if is_outer_wall else floor_type

	var inner_left = rect.position.x + 1
	var inner_right = rect.end.x - 2
	var inner_top = rect.position.y + 1
	var inner_bottom = rect.end.y - 2
	var mid_x = rect.position.x + rect.size.x / 2
	var mid_y = rect.position.y + rect.size.y / 2
	var layout = randi_range(0, 4)

	match layout:
		0: # 縦に並んだ二部屋
			for y in range(inner_top, inner_bottom + 1):
				map_data[mid_x][y] = CellType.WALL
			map_data[mid_x][randi_range(inner_top + 1, inner_bottom - 1)] = CellType.DOOR_CLOSED
		1: # 横に並んだ二部屋
			for x in range(inner_left, inner_right + 1):
				map_data[x][mid_y] = CellType.WALL
			map_data[randi_range(inner_left + 1, inner_right - 1)][mid_y] = CellType.DOOR_CLOSED
		2: # 片側をさらに分割した三部屋
			for y in range(inner_top, inner_bottom + 1):
				map_data[mid_x][y] = CellType.WALL
			map_data[mid_x][randi_range(inner_top + 1, inner_bottom - 1)] = CellType.DOOR_CLOSED
			var split_y = rect.position.y + rect.size.y / 2
			for x in range(inner_left, mid_x):
				map_data[x][split_y] = CellType.WALL
			map_data[randi_range(inner_left + 1, mid_x - 1)][split_y] = CellType.DOOR_CLOSED
		3: # 中央廊下と両脇の小部屋
			var left_divider = rect.position.x + rect.size.x / 3
			var right_divider = rect.position.x + rect.size.x * 2 / 3
			for y in range(inner_top, inner_bottom + 1):
				map_data[left_divider][y] = CellType.WALL
				map_data[right_divider][y] = CellType.WALL
			map_data[left_divider][randi_range(inner_top + 1, inner_bottom - 1)] = CellType.DOOR_CLOSED
			map_data[right_divider][randi_range(inner_top + 1, inner_bottom - 1)] = CellType.DOOR_CLOSED
		4: # 十字廊下で四部屋
			for y in range(inner_top, inner_bottom + 1):
				map_data[mid_x][y] = CellType.WALL
			for x in range(inner_left, inner_right + 1):
				map_data[x][mid_y] = CellType.WALL
			map_data[mid_x][inner_top + 1] = CellType.DOOR_CLOSED
			map_data[mid_x][inner_bottom - 1] = CellType.DOOR_CLOSED
			map_data[inner_left + 1][mid_y] = CellType.DOOR_CLOSED
			map_data[inner_right - 1][mid_y] = CellType.DOOR_CLOSED

	# 外への入口と短いアプローチを、建物の四辺からランダムに選ぶ。
	var entrance_side = randi_range(0, 3)
	var door_pos = Vector2i(mid_x, rect.end.y - 1)
	var outward = Vector2i.DOWN
	if entrance_side == 0:
		door_pos = Vector2i(mid_x, rect.position.y)
		outward = Vector2i.UP
	elif entrance_side == 1:
		door_pos = Vector2i(rect.end.x - 1, mid_y)
		outward = Vector2i.RIGHT
	elif entrance_side == 2:
		door_pos = Vector2i(mid_x, rect.end.y - 1)
		outward = Vector2i.DOWN
	else:
		door_pos = Vector2i(rect.position.x, mid_y)
		outward = Vector2i.LEFT
	map_data[door_pos.x][door_pos.y] = CellType.DOOR_CLOSED
	for step in range(1, 4):
		var approach = door_pos + outward * step
		if approach.x < 2 or approach.x >= MAP_WIDTH - 2 or approach.y < 2 or approach.y >= MAP_HEIGHT - 2:
			break
		if map_data[approach.x][approach.y] == CellType.ASH:
			break
		if map_data[approach.x][approach.y] != CellType.WATER:
			map_data[approach.x][approach.y] = CellType.FLOOR

func _generate_maze_building(map_data: Array, rect: Rect2i) -> void:
	var outer_wall_color = CellType.WALL
	var floor_color = CellType.CRYSTAL_FLOOR if randf() < 0.5 else CellType.FLOOR
	
	# Step 1: Fill entire rect with floor initially
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			map_data[x][y] = floor_color
	
	# Step 2: Carve outer walls
	for x in range(rect.position.x, rect.end.x):
		map_data[x][rect.position.y] = outer_wall_color
		map_data[x][rect.end.y - 1] = outer_wall_color
	for y in range(rect.position.y, rect.end.y):
		map_data[rect.position.x][y] = outer_wall_color
		map_data[rect.end.x - 1][y] = outer_wall_color
	
	# Step 3: DFS Maze generation inside (only on odd cells, with 1-cell corridors)
	# Maze cells are at odd coordinates within the building interior
	var maze_start_x = rect.position.x + 1
	var maze_end_x = rect.end.x - 2
	var maze_start_y = rect.position.y + 1
	var maze_end_y = rect.end.y - 2
	
	# Build grid of cell coordinates (odd positions)
	# First, fill interior with walls (we'll carve paths)
	for x in range(maze_start_x, maze_end_x + 1):
		for y in range(maze_start_y, maze_end_y + 1):
			if x % 2 == 1 and y % 2 == 1:
				# This is a cell position - we already set it to floor
				pass
			else:
				# Wall position - set to wall
				map_data[x][y] = outer_wall_color
	
	# DFS maze generation using recursive backtracker
	var visited = {}
	var stack = []
	
	# Start from a random cell (odd coords)
	var cell_x = maze_start_x + 1
	var cell_y = maze_start_y + 1
	if cell_x % 2 == 0: cell_x += 1
	if cell_y % 2 == 0: cell_y += 1
	if cell_x > maze_end_x: cell_x = maze_start_x + 1
	if cell_y > maze_end_y: cell_y = maze_start_y + 1
	
	visited[Vector2i(cell_x, cell_y)] = true
	stack.append(Vector2i(cell_x, cell_y))
	
	var dirs = [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]
	
	while stack.size() > 0:
		var current = stack.back()
		var unvisited = []
		
		dirs.shuffle()
		for d in dirs:
			var nx = current.x + d.x
			var ny = current.y + d.y
			if nx >= maze_start_x and nx <= maze_end_x and ny >= maze_start_y and ny <= maze_end_y:
				if not visited.has(Vector2i(nx, ny)):
					unvisited.append(d)
		
		if unvisited.size() > 0:
			var chosen = unvisited.pick_random()
			var next_cell = Vector2i(current.x + chosen.x, current.y + chosen.y)
			var wall_x = current.x + chosen.x / 2
			var wall_y = current.y + chosen.y / 2
			
			# Carve wall between current and next
			map_data[wall_x][wall_y] = floor_color
			
			visited[next_cell] = true
			stack.append(next_cell)
		else:
			stack.pop_back()
	
	# Step 4: Decide on entrance side and carve door
	var entrance_side = randi_range(0, 3)
	var mid_x = rect.position.x + rect.size.x / 2
	var mid_y = rect.position.y + rect.size.y / 2
	var door_pos = Vector2i(mid_x, rect.end.y - 1)
	var outward = Vector2i.DOWN
	
	if entrance_side == 0:
		door_pos = Vector2i(mid_x, rect.position.y)
		outward = Vector2i.UP
	elif entrance_side == 1:
		door_pos = Vector2i(rect.end.x - 1, mid_y)
		outward = Vector2i.RIGHT
	elif entrance_side == 2:
		door_pos = Vector2i(mid_x, rect.end.y - 1)
		outward = Vector2i.DOWN
	else:
		door_pos = Vector2i(rect.position.x, mid_y)
		outward = Vector2i.LEFT
	
	map_data[door_pos.x][door_pos.y] = CellType.DOOR_CLOSED
	
	# Carve path from door to nearest maze corridor
	var door_inward = door_pos - outward
	if door_inward.x >= rect.position.x and door_inward.x < rect.end.x and door_inward.y >= rect.position.y and door_inward.y < rect.end.y:
		if map_data[door_inward.x][door_inward.y] != floor_color:
			map_data[door_inward.x][door_inward.y] = floor_color
			# Also try to connect further inward
			var door_inward2 = door_inward - outward
			if door_inward2.x >= rect.position.x and door_inward2.x < rect.end.x and door_inward2.y >= rect.position.y and door_inward2.y < rect.end.y:
				if map_data[door_inward2.x][door_inward2.y] != floor_color:
					map_data[door_inward2.x][door_inward2.y] = floor_color
	
	# Approach path outside
	for step in range(1, 4):
		var approach = door_pos + outward * step
		if approach.x < 2 or approach.x >= MAP_WIDTH - 2 or approach.y < 2 or approach.y >= MAP_HEIGHT - 2:
			break
		if map_data[approach.x][approach.y] == CellType.ASH:
			break
		if map_data[approach.x][approach.y] != CellType.WATER:
			map_data[approach.x][approach.y] = CellType.FLOOR

func generate_world_map() -> Array:
	# Generate terrain-based world map with natural biome distribution
	var seed_val = randi()
	
	# Generate elevation, moisture, and temperature maps with improved parameters
	var elevation = _generate_noise_map(MAP_WIDTH, MAP_HEIGHT, seed_val, 0.006, 5)
	var moisture = _generate_noise_map(MAP_WIDTH, MAP_HEIGHT, seed_val + 1000, 0.005, 4)
	var temperature = _generate_noise_map(MAP_WIDTH, MAP_HEIGHT, seed_val + 2000, 0.0055, 4)
	
	# Apply latitude-based temperature gradient (colder at top, warmer at bottom)
	for y in range(MAP_HEIGHT):
		var lat_factor = 1.0 - (float(y) / float(MAP_HEIGHT))
		for x in range(MAP_WIDTH):
			temperature[x][y] = temperature[x][y] * 0.6 + lat_factor * 0.4
	
	# Generate initial biomes based on terrain
	var world = []
	world.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		world[x] = []
		world[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			world[x][y] = _determine_biome_from_terrain(elevation[x][y], moisture[x][y], temperature[x][y])
	
	# Generate rivers with more natural flow
	_generate_rivers(world, elevation, seed_val + 3000)
	
	# Generate lakes in depressions
	_generate_lakes(world, elevation, moisture)
	
	# Apply smooth biome transitions
	_apply_smooth_biome_transitions(world, elevation, moisture, temperature)
	
	# Place villages
	var villages = _place_villages(world)
	
	# Place dungeons
	var dungeons = _place_dungeons(world, villages)
	
	# Place roads
	_place_roads(world, villages, dungeons)
	
	# Place rare special locations
	_place_rare_special_locations(world, seed_val + 4000)
	
	# Apply biome internal variations
	_apply_biome_internal_variations(world, seed_val + 5000)
	
	# Generate coastal features
	_generate_coastal_features(world, elevation)
	
	return world

func _draw_road(world: Array, start: Vector2i, end: Vector2i):
	var curr = start
	var att = 0
	while curr != end and att < 200:
		att += 1
		if world[curr.x][curr.y] == WorldCell.GRASS or world[curr.x][curr.y] == WorldCell.FOREST:
			world[curr.x][curr.y] = WorldCell.ROAD
			
		var dx = sign(end.x - curr.x)
		var dy = sign(end.y - curr.y)
		
		if dx != 0 and (dy == 0 or randf() < 0.5):
			curr.x += dx
		elif dy != 0:
			curr.y += dy

func _make_edges_walkable(map_data: Array):
	var edge_width = 3
	for x in range(MAP_WIDTH):
		for y in range(MAP_HEIGHT):
			if x < edge_width or x >= MAP_WIDTH - edge_width or y < edge_width or y >= MAP_HEIGHT - edge_width:
				var cur = map_data[x][y]
				if cur == CellType.WALL:
					if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
						map_data[x][y] = CellType.GRASS if randf() < 0.7 else CellType.FLOOR

func _blend_overworld_edges(map_data: Array, local_type: int, main_inst: Node2D = null) -> void:
	if not main_inst or main_inst._world_map_data.is_empty():
		return
	var wx = main_inst._world_player_pos.x
	var wy = main_inst._world_player_pos.y
	var w_data = main_inst._world_map_data
	var dirs = [
		{"delta": Vector2i.LEFT, "side": "left"},
		{"delta": Vector2i.RIGHT, "side": "right"},
		{"delta": Vector2i.UP, "side": "up"},
		{"delta": Vector2i.DOWN, "side": "down"}
	]
	for entry in dirs:
		var neighbor_pos = Vector2i(wx, wy) + entry["delta"]
		if neighbor_pos.x < 0 or neighbor_pos.x >= MAP_WIDTH or neighbor_pos.y < 0 or neighbor_pos.y >= MAP_HEIGHT:
			continue
		_stamp_overworld_edge(map_data, entry["side"], local_type, w_data[neighbor_pos.x][neighbor_pos.y])

func _stamp_overworld_edge(map_data: Array, side: String, local_type: int, neighbor_type: int) -> void:
	var edge_width = 3
	var primary_edge_cell = _edge_cell_for_neighbor(local_type, neighbor_type)
	var secondary_edge_cell = CellType.GRASS # Fallback/blend cell
	
	if primary_edge_cell == CellType.TREE:
		secondary_edge_cell = CellType.GRASS
	elif primary_edge_cell == CellType.ROCK:
		secondary_edge_cell = CellType.ASH
	elif primary_edge_cell == CellType.WATER:
		secondary_edge_cell = CellType.FLOOR # Beach/shoreline
	elif primary_edge_cell == CellType.ASH:
		secondary_edge_cell = CellType.FLOOR
		
	var road_like = _is_world_road_like(local_type) and _is_world_road_like(neighbor_type)
	var center_x = MAP_WIDTH / 2
	var center_y = MAP_HEIGHT / 2
	var road_half_width = 2
	
	for i in range(edge_width):
		# The further from the edge (i=0 is outermost), the lower the chance of placing the primary cell
		var primary_chance = 1.0 - (float(i) / edge_width)
		
		match side:
			"left":
				for y in range(MAP_HEIGHT):
					if randf() < primary_chance:
						map_data[i][y] = primary_edge_cell
					else:
						map_data[i][y] = secondary_edge_cell
			"right":
				for y in range(MAP_HEIGHT):
					if randf() < primary_chance:
						map_data[MAP_WIDTH - 1 - i][y] = primary_edge_cell
					else:
						map_data[MAP_WIDTH - 1 - i][y] = secondary_edge_cell
			"up":
				for x in range(MAP_WIDTH):
					if randf() < primary_chance:
						map_data[x][i] = primary_edge_cell
					else:
						map_data[x][i] = secondary_edge_cell
			"down":
				for x in range(MAP_WIDTH):
					if randf() < primary_chance:
						map_data[x][MAP_HEIGHT - 1 - i] = primary_edge_cell
					else:
						map_data[x][MAP_HEIGHT - 1 - i] = secondary_edge_cell

	# This road logic is still a bit abrupt, but let's keep it for now
	# to ensure connectivity is not broken.
	if road_like:
		match side:
			"left":
				for x in range(0, center_x + 1):
					for y in range(center_y - road_half_width, center_y + road_half_width + 1):
						var cur = map_data[x][y]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[x][y] = CellType.ASH
			"right":
				for x in range(center_x, MAP_WIDTH):
					for y in range(center_y - road_half_width, center_y + road_half_width + 1):
						var cur = map_data[x][y]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[x][y] = CellType.ASH
			"up":
				for y in range(0, center_y + 1):
					for x in range(center_x - road_half_width, center_x + road_half_width + 1):
						var cur = map_data[x][y]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[x][y] = CellType.ASH
			"down":
				for y in range(center_y, MAP_HEIGHT):
					for x in range(center_x - road_half_width, center_x + road_half_width + 1):
						var cur = map_data[x][y]
						if cur != CellType.STAIRS and cur != CellType.STAIRS_GOLD and cur != CellType.STAIRS_UP and cur != CellType.STAIRS_BLUE and cur != CellType.STAIRS_GREEN and cur != CellType.STAIRS_RED and cur != CellType.STAIRS_PURPLE:
							map_data[x][y] = CellType.ASH

func _edge_cell_for_neighbor(local_type: int, neighbor_type: int) -> int:
	if neighbor_type == WorldCell.SEA:
		return CellType.WATER
	if neighbor_type == WorldCell.MOUNTAIN:
		return CellType.ROCK if local_type != WorldCell.MOUNTAIN else CellType.GRASS
	if neighbor_type == WorldCell.FOREST or neighbor_type == WorldCell.DEEP_FOREST or neighbor_type == WorldCell.CONIFER_FOREST:
		return CellType.TREE
	if neighbor_type == WorldCell.DESERT or neighbor_type == WorldCell.DRYLAND:
		return CellType.ASH if local_type != WorldCell.DESERT else CellType.FLOOR
	if neighbor_type == WorldCell.SNOWLAND or neighbor_type == WorldCell.FROZEN_LAND:
		return CellType.ICE if local_type != WorldCell.SNOWLAND else CellType.GRASS
	if neighbor_type == WorldCell.SWAMP or neighbor_type == WorldCell.WETLAND:
		return CellType.WATER if local_type != WorldCell.SWAMP else CellType.GRASS
	if neighbor_type == WorldCell.ROAD or neighbor_type == WorldCell.VILLAGE or neighbor_type == WorldCell.DUNGEON:
		return CellType.ASH
	if neighbor_type == WorldCell.ROCKLAND or neighbor_type == WorldCell.HIGHLAND:
		return CellType.ROCK
	if neighbor_type == WorldCell.WASTELAND:
		return CellType.ASH
	if neighbor_type == WorldCell.ANOMALY_ZONE:
		return CellType.CRYSTAL_FLOOR
	return CellType.GRASS

func _is_world_road_like(cell_type: int) -> bool:
	return cell_type == WorldCell.ROAD or cell_type == WorldCell.VILLAGE or cell_type == WorldCell.DUNGEON

func _is_walkable_biome(cell_type: int) -> bool:
	# Check if a biome is walkable for player movement
	if cell_type == WorldCell.SEA or cell_type == WorldCell.MOUNTAIN:
		return false
	return true

# Terrain-based generation functions
func _generate_noise_map(width: int, height: int, seed: int, scale: float, octaves: int) -> Array:
	var noise_map = []
	noise_map.resize(width)
	for x in range(width):
		noise_map[x] = []
		noise_map[x].resize(height)
		for y in range(height):
			noise_map[x][y] = 0.0
	
	for octave in range(octaves):
		var octave_scale = scale * pow(2.0, octave)
		var amplitude = 1.0 / pow(2.0, octave)
		
		for x in range(width):
			for y in range(height):
				var nx = x * octave_scale + seed * 0.1 * (octave + 1)
				var ny = y * octave_scale + seed * 0.15 * (octave + 1)
				
				# Simple sine-based noise simulation
				var noise_val = sin(nx) * sin(ny) * 0.5 + 0.5
				noise_map[x][y] += noise_val * amplitude
	
	# Normalize
	var max_val = 0.0
	var min_val = 1.0
	for x in range(width):
		for y in range(height):
			if noise_map[x][y] > max_val:
				max_val = noise_map[x][y]
			if noise_map[x][y] < min_val:
				min_val = noise_map[x][y]
	
	if max_val > min_val:
		var range_val = max_val - min_val
		for x in range(width):
			for y in range(height):
				noise_map[x][y] = (noise_map[x][y] - min_val) / range_val
	else:
		# If all values are the same, set to 0.5
		for x in range(width):
			for y in range(height):
				noise_map[x][y] = 0.5
	
	return noise_map

func _determine_biome_from_terrain(elevation: float, moisture: float, temperature: float) -> int:
	# Sea (low elevation)
	if elevation < 0.15:
		return WorldCell.SEA
	
	# Mountain (high elevation)
	if elevation > 0.7:
		if temperature < 0.3:
			return WorldCell.SNOWLAND
		return WorldCell.MOUNTAIN
	
	# Highland (medium-high elevation)
	if elevation > 0.5:
		if temperature < 0.35:
			return WorldCell.SNOWLAND_EDGE
		return WorldCell.HIGHLAND
	
	# Snowland (cold temperature)
	if temperature < 0.25:
		if moisture > 0.6:
			return WorldCell.FROZEN_LAND
		return WorldCell.SNOWLAND
	
	# Desert (hot and dry)
	if temperature > 0.7 and moisture < 0.3:
		return WorldCell.DESERT
	
	# Dryland (warm and somewhat dry)
	if temperature > 0.6 and moisture < 0.4:
		return WorldCell.DRYLAND
	
	# Swamp (wet and low elevation)
	if moisture > 0.8 and elevation < 0.3:
		return WorldCell.SWAMP
	
	# Wetland (wet)
	if moisture > 0.7:
		return WorldCell.WETLAND
	
	# Deep forest (moist and moderate elevation)
	if moisture > 0.5 and elevation > 0.25:
		if temperature < 0.4:
			return WorldCell.CONIFER_FOREST
		return WorldCell.DEEP_FOREST
	
	# Forest (moderate moisture)
	if moisture > 0.4:
		return WorldCell.FOREST
	
	# Rockland (higher elevation, dry)
	if elevation > 0.35 and moisture < 0.35:
		return WorldCell.ROCKLAND
	
	# Grassland (default)
	return WorldCell.GRASS

func _generate_rivers(world: Array, elevation: Array, seed: int):
	# Find high points as river sources
	var sources = []
	for x in range(2, MAP_WIDTH - 2):
		for y in range(2, MAP_HEIGHT - 2):
			if world[x][y] != WorldCell.SEA and elevation[x][y] > 0.5:
				var is_peak = true
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if dx == 0 and dy == 0: continue
						var nx = x + dx
						var ny = y + dy
						if elevation[nx][ny] > elevation[x][y]:
							is_peak = false
							break
					if not is_peak: break
				if is_peak and randf() < 0.15:
					sources.append(Vector2i(x, y))

	# Generate rivers from sources
	for source in sources:
		var curr = source
		var river_length = 0
		while river_length < 40 and world[curr.x][curr.y] != WorldCell.SEA:
			# Mark as riverbank
			if world[curr.x][curr.y] == WorldCell.GRASS or world[curr.x][curr.y] == WorldCell.FOREST:
				world[curr.x][curr.y] = WorldCell.RIVERBANK
			
			# Find lowest neighbor
			var lowest = curr
			var lowest_elev = elevation[curr.x][curr.y]
			var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
			dirs.shuffle()
			
			for d in dirs:
				var next = curr + d
				if next.x >= 1 and next.x < MAP_WIDTH - 1 and next.y >= 1 and next.y < MAP_HEIGHT - 1:
					if elevation[next.x][next.y] < lowest_elev:
						lowest = next
						lowest_elev = elevation[next.x][next.y]
			
			if lowest == curr:
				break
			
			curr = lowest
			river_length += 1

func _generate_lakes(world: Array, elevation: Array, moisture: Array):
	# Find depressions (local minima) with high moisture
	for x in range(3, MAP_WIDTH - 3):
		for y in range(3, MAP_HEIGHT - 3):
			if world[x][y] == WorldCell.SEA or world[x][y] == WorldCell.RIVERBANK:
				continue
			
			var is_depression = true
			var current_elev = elevation[x][y]
			
			# Check if this is a local minimum
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					if dx == 0 and dy == 0: continue
					var nx = x + dx
					var ny = y + dy
					if elevation[nx][ny] < current_elev:
						is_depression = false
						break
				if not is_depression: break
			
			# If depression and high moisture, create lake
			if is_depression and moisture[x][y] > 0.65 and randf() < 0.25:
				var lake_radius = randi_range(2, 5)
				for lx in range(x - lake_radius, x + lake_radius + 1):
					for ly in range(y - lake_radius, y + lake_radius + 1):
						if lx >= 0 and lx < MAP_WIDTH and ly >= 0 and ly < MAP_HEIGHT:
							var dist = Vector2(lx - x, ly - y).length()
							if dist <= lake_radius:
								if world[lx][ly] != WorldCell.SEA and world[lx][ly] != WorldCell.MOUNTAIN:
									if dist < lake_radius * 0.6:
										world[lx][ly] = WorldCell.SEA  # Lake water
									else:
										world[lx][ly] = WorldCell.LAKESHORE  # Lake shore

func _apply_smooth_biome_transitions(world: Array, elevation: Array, moisture: Array, temperature: Array):
	# Apply smooth transition zones between different biomes based on terrain gradients
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			var current = world[x][y]
			var neighbors = []
			
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0: continue
					var nx = x + dx
					var ny = y + dy
					neighbors.append(world[nx][ny])
			
			# Check if this is a boundary between different biome types
			var has_different = false
			var biome_counts = {}
			for n in neighbors:
				if not biome_counts.has(n):
					biome_counts[n] = 0
				biome_counts[n] += 1
				if n != current:
					has_different = true
			
			if has_different:
				# Apply appropriate transition zone based on biome compatibility
				var transition = _get_smooth_transition_biome(current, biome_counts, elevation[x][y], moisture[x][y], temperature[x][y])
				if transition != current:
					world[x][y] = transition

func _get_smooth_transition_biome(current: int, biome_counts: Dictionary, elevation: float, moisture: float, temperature: float) -> int:
	# Find most common different biome
	var max_count = 0
	var dominant_neighbor = current
	
	for biome in biome_counts:
		if biome != current and biome_counts[biome] > max_count:
			max_count = biome_counts[biome]
			dominant_neighbor = biome
	
	# Return appropriate transition zone based on biome compatibility and terrain
	match current:
		WorldCell.GRASS:
			if dominant_neighbor == WorldCell.FOREST:
				return WorldCell.GRASSLAND_EDGE
			elif dominant_neighbor == WorldCell.DESERT:
				return WorldCell.DESERT_EDGE
			elif dominant_neighbor == WorldCell.DRYLAND:
				if moisture < 0.35:
					return WorldCell.DRYLAND
				return WorldCell.GRASSLAND_EDGE
		WorldCell.FOREST:
			if dominant_neighbor == WorldCell.GRASS:
				return WorldCell.FOREST_EDGE
			elif dominant_neighbor == WorldCell.DEEP_FOREST:
				if moisture > 0.6:
					return WorldCell.DEEP_FOREST
				return WorldCell.FOREST
			elif dominant_neighbor == WorldCell.CONIFER_FOREST:
				return WorldCell.CONIFER_FOREST if temperature < 0.4 else WorldCell.FOREST
		WorldCell.DESERT:
			if dominant_neighbor == WorldCell.GRASS or dominant_neighbor == WorldCell.DRYLAND:
				return WorldCell.DESERT_EDGE
			elif dominant_neighbor == WorldCell.ROCKLAND:
				return WorldCell.ROCKLAND if elevation > 0.35 else WorldCell.DESERT_EDGE
		WorldCell.SNOWLAND:
			if dominant_neighbor == WorldCell.CONIFER_FOREST or dominant_neighbor == WorldCell.HIGHLAND:
				return WorldCell.SNOWLAND_EDGE
			elif dominant_neighbor == WorldCell.FROZEN_LAND:
				return WorldCell.FROZEN_LAND if moisture > 0.5 else WorldCell.SNOWLAND
		WorldCell.SWAMP:
			if dominant_neighbor == WorldCell.WETLAND or dominant_neighbor == WorldCell.FOREST:
				return WorldCell.SWAMP_EDGE
			elif dominant_neighbor == WorldCell.DEEP_FOREST:
				return WorldCell.SWAMP if moisture > 0.85 else WorldCell.WETLAND
		WorldCell.HIGHLAND:
			if dominant_neighbor == WorldCell.MOUNTAIN:
				return WorldCell.MOUNTAIN if elevation > 0.65 else WorldCell.HIGHLAND
			elif dominant_neighbor == WorldCell.CONIFER_FOREST:
				return WorldCell.CONIFER_FOREST if moisture > 0.4 else WorldCell.HIGHLAND
		WorldCell.WETLAND:
			if dominant_neighbor == WorldCell.SWAMP:
				return WorldCell.SWAMP if moisture > 0.8 else WorldCell.WETLAND
			elif dominant_neighbor == WorldCell.RIVERBANK or dominant_neighbor == WorldCell.LAKESHORE:
				return dominant_neighbor
	
	return current

func _place_villages(world: Array) -> Array:
	var villages = []
	var attempts = 200
	
	while villages.size() < 3 and attempts > 0:
		attempts -= 1
		var vx = randi_range(3, MAP_WIDTH - 4)
		var vy = randi_range(3, MAP_HEIGHT - 4)
		var cell = world[vx][vy]
		
		# Villages can only be placed in walkable biomes
		if cell == WorldCell.GRASS or cell == WorldCell.FOREST or cell == WorldCell.CONIFER_FOREST or cell == WorldCell.HIGHLAND:
			var too_close = false
			for v in villages:
				if Vector2i(vx, vy).distance_to(v) < 12.0:
					too_close = true
					break
			
			if not too_close:
				world[vx][vy] = WorldCell.VILLAGE
				villages.append(Vector2i(vx, vy))
	
	return villages

func _place_dungeons(world: Array, villages: Array) -> Array:
	var dungeons = []
	var attempts = 300
	
	while dungeons.size() < 4 and attempts > 0:
		attempts -= 1
		var dx = randi_range(3, MAP_WIDTH - 4)
		var dy = randi_range(3, MAP_HEIGHT - 4)
		var cell = world[dx][dy]
		
		# Dungeons can be in various biomes but not in villages or sea
		if cell != WorldCell.SEA and cell != WorldCell.VILLAGE and cell != WorldCell.ANOMALY_ZONE:
			var too_close = false
			for v in villages:
				if Vector2i(dx, dy).distance_to(v) < 8.0:
					too_close = true
					break
			for d in dungeons:
				if Vector2i(dx, dy).distance_to(d) < 10.0:
					too_close = true
					break
			
			if not too_close:
				world[dx][dy] = WorldCell.DUNGEON
				dungeons.append(Vector2i(dx, dy))
	
	return dungeons

func _place_roads(world: Array, villages: Array, dungeons: Array):
	# Connect villages with roads
	for i in range(villages.size()):
		var v1 = villages[i]
		var v2 = villages[(i + 1) % villages.size()]
		_draw_smart_road(world, v1, v2)
	
	# Connect nearby dungeons to villages
	for d in dungeons:
		var closest_village = null
		var closest_dist = 999.0
		
		for v in villages:
			var dist = d.distance_to(v)
			if dist < closest_dist and dist < 20.0:
				closest_dist = dist
				closest_village = v
		
		if closest_village:
			_draw_smart_road(world, closest_village, d)

func _draw_smart_road(world: Array, start: Vector2i, end: Vector2i):
	var curr = start
	var att = 0
	while curr != end and att < 300:
		att += 1
		var cell = world[curr.x][curr.y]
		
		# Only place road on walkable terrain using biome data
		var biome_data = BiomeDefinitions.get_biome_data(cell)
		var is_walkable = biome_data.is_empty() or biome_data.get("walkable", true)
		
		if is_walkable and cell != WorldCell.VILLAGE and cell != WorldCell.DUNGEON:
			world[curr.x][curr.y] = WorldCell.ROAD
		
		# Move towards end with some randomness for natural look
		var dx = sign(end.x - curr.x)
		var dy = sign(end.y - curr.y)
		
		if dx != 0 and (dy == 0 or randf() < 0.6):
			curr.x += dx
		elif dy != 0:
			curr.y += dy

func _place_rare_special_locations(world: Array, seed: int):
	# Place anomaly zones (very rare)
	if randf() < 0.2:
		var ax = randi_range(5, MAP_WIDTH - 6)
		var ay = randi_range(5, MAP_HEIGHT - 6)
		if world[ax][ay] != WorldCell.SEA and world[ax][ay] != WorldCell.VILLAGE and world[ax][ay] != WorldCell.DUNGEON:
			world[ax][ay] = WorldCell.ANOMALY_ZONE
	
	# Place wasteland patches (moderately rare)
	for _i in range(randi_range(1, 3)):
		var wx = randi_range(3, MAP_WIDTH - 4)
		var wy = randi_range(3, MAP_HEIGHT - 4)
		if world[wx][wy] == WorldCell.DRYLAND or world[wx][wy] == WorldCell.ROCKLAND:
			world[wx][wy] = WorldCell.WASTELAND
	
	# Place giant trees (rare forest features)
	if randf() < 0.15:
		var gx = randi_range(5, MAP_WIDTH - 6)
		var gy = randi_range(5, MAP_HEIGHT - 6)
		if world[gx][gy] == WorldCell.FOREST or world[gx][gy] == WorldCell.DEEP_FOREST:
			# Create a small clearing around the giant tree
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var nx = gx + dx
					var ny = gy + dy
					if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
						if dx == 0 and dy == 0:
							world[nx][ny] = WorldCell.DEEP_FOREST  # Giant tree location
						elif Vector2(dx, dy).length() <= 2:
							if world[nx][ny] == WorldCell.FOREST:
								world[nx][ny] = WorldCell.FOREST_EDGE  # Clearing edge
	
	# Place flower fields (rare grassland features)
	if randf() < 0.2:
		var fx = randi_range(5, MAP_WIDTH - 6)
		var fy = randi_range(5, MAP_HEIGHT - 6)
		if world[fx][fy] == WorldCell.GRASS or world[fx][fy] == WorldCell.GRASSLAND_EDGE:
			var flower_radius = randi_range(2, 4)
			for dx in range(-flower_radius, flower_radius + 1):
				for dy in range(-flower_radius, flower_radius + 1):
					var nx = fx + dx
					var ny = fy + dy
					if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
						if Vector2(dx, dy).length() <= flower_radius:
							if world[nx][ny] == WorldCell.GRASS:
								world[nx][ny] = WorldCell.GRASSLAND_EDGE  # Flower field edge
	
	# Place ancient ruins (rare)
	if randf() < 0.12:
		var rx = randi_range(5, MAP_WIDTH - 6)
		var ry = randi_range(5, MAP_HEIGHT - 6)
		if world[rx][ry] != WorldCell.SEA and world[rx][ry] != WorldCell.MOUNTAIN and world[rx][ry] != WorldCell.VILLAGE:
			world[rx][ry] = WorldCell.WASTELAND  # Ruins appear as wasteland on world map

func _apply_biome_internal_variations(world: Array, seed: int):
	# Apply internal variations within biomes to create sub-environments
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	
	for x in range(2, MAP_WIDTH - 2):
		for y in range(2, MAP_HEIGHT - 2):
			var current = world[x][y]
			var variation_roll = rng.randf()
			
			match current:
				WorldCell.FOREST:
					# Forest variations: dense areas, clearings, rocky patches
					if variation_roll < 0.08:
						world[x][y] = WorldCell.DEEP_FOREST  # Dense patch
					elif variation_roll < 0.12:
						world[x][y] = WorldCell.FOREST_EDGE  # Small clearing
					elif variation_roll < 0.15:
						world[x][y] = WorldCell.ROCKLAND  # Rocky forest patch
				
				WorldCell.GRASS:
					# Grassland variations: flower patches, rocky areas
					if variation_roll < 0.05:
						world[x][y] = WorldCell.GRASSLAND_EDGE  # Flower patch
					elif variation_roll < 0.08:
						world[x][y] = WorldCell.ROCKLAND  # Rocky outcrop
				
				WorldCell.DESERT:
					# Desert variations: oasis, rocky areas
					if variation_roll < 0.03:
						world[x][y] = WorldCell.WETLAND  # Small oasis
					elif variation_roll < 0.06:
						world[x][y] = WorldCell.ROCKLAND  # Rock formation
				
				WorldCell.SWAMP:
					# Swamp variations: dryer patches
					if variation_roll < 0.08:
						world[x][y] = WorldCell.WETLAND  # Less swampy area
				
				WorldCell.SNOWLAND:
					# Snowland variations: bare patches
					if variation_roll < 0.06:
						world[x][y] = WorldCell.HIGHLAND  # Bare rock patch

func _generate_coastal_features(world: Array, elevation: Array):
	# Generate coastal features like beaches, cliffs, and rocky shores
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			if world[x][y] == WorldCell.SEA:
				continue
			
			# Check if adjacent to sea
			var is_coastal = false
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0: continue
					var nx = x + dx
					var ny = y + dy
					if world[nx][ny] == WorldCell.SEA:
						is_coastal = true
						break
				if is_coastal: break
			
			if is_coastal:
				# Determine coastal type based on elevation
				if elevation[x][y] < 0.12:
					world[x][y] = WorldCell.COAST  # Beach/sandy shore
				elif elevation[x][y] < 0.18:
					world[x][y] = WorldCell.WETLAND  # Coastal wetland
				else:
					world[x][y] = WorldCell.ROCKLAND  # Rocky cliffs

# Local terrain generation functions for each biome
func _generate_grassland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.55:
		map_data[x][y] = CellType.GRASS
	elif roll < 0.75:
		map_data[x][y] = CellType.FLOOR
	elif roll < 0.82:
		map_data[x][y] = CellType.TREE
	elif roll < 0.88:
		map_data[x][y] = CellType.TREE_FRUIT  # Fruit trees/berry bushes
	elif roll < 0.94:
		map_data[x][y] = CellType.ROCK
	else:
		map_data[x][y] = CellType.GRASS  # Keep as grass but could add flower details later

func _generate_forest_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.35:
		map_data[x][y] = CellType.GRASS
	elif roll < 0.75:
		map_data[x][y] = CellType.TREE
	elif roll < 0.82:
		map_data[x][y] = CellType.TREE_FRUIT
	elif roll < 0.88:
		map_data[x][y] = CellType.FLOOR  # Clearings
	elif roll < 0.94:
		map_data[x][y] = CellType.ROCK  # Rocky forest floor
	else:
		map_data[x][y] = CellType.GRASS  # Mossy patches

func _generate_deep_forest_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.25:
		map_data[x][y] = CellType.GRASS
	elif roll < 0.80:
		map_data[x][y] = CellType.TREE  # Dense trees
	elif roll < 0.87:
		map_data[x][y] = CellType.TREE_FRUIT  # Ancient trees
	elif roll < 0.93:
		map_data[x][y] = CellType.FLOOR  # Small clearings
	else:
		map_data[x][y] = CellType.ROCK  # Fallen logs/rocks

func _generate_conifer_forest_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.30:
		map_data[x][y] = CellType.GRASS
	elif roll < 0.78:
		map_data[x][y] = CellType.TREE  # Pine trees
	elif roll < 0.85:
		map_data[x][y] = CellType.FLOOR  # Needle-covered clearings
	elif roll < 0.92:
		map_data[x][y] = CellType.ROCK  # Rocky outcrops
	elif roll < 0.97:
		map_data[x][y] = CellType.ICE  # Frozen patches
	else:
		map_data[x][y] = CellType.GRASS  # Moss patches

func _generate_dryland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.45:
		map_data[x][y] = CellType.GRASS  # Dry grass
	elif roll < 0.70:
		map_data[x][y] = CellType.FLOOR  # Packed earth
	elif roll < 0.82:
		map_data[x][y] = CellType.ROCK  # Scattered rocks
	elif roll < 0.90:
		map_data[x][y] = CellType.ASH  # Dusty patches
	elif roll < 0.96:
		map_data[x][y] = CellType.TREE  # Scraggly trees
	else:
		map_data[x][y] = CellType.GRASS  # Dead grass patches

func _generate_desert_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.35:
		map_data[x][y] = CellType.FLOOR  # Sand
	elif roll < 0.65:
		map_data[x][y] = CellType.ASH  # Dunes
	elif roll < 0.82:
		map_data[x][y] = CellType.ROCK  # Rock formations
	elif roll < 0.92:
		map_data[x][y] = CellType.WATER  # Rare oasis water
	elif roll < 0.97:
		map_data[x][y] = CellType.TREE  # Dead trees/cacti
	else:
		map_data[x][y] = CellType.ASH  # Sand dunes

func _generate_rockland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.25:
		map_data[x][y] = CellType.FLOOR  # Gravel
	elif roll < 0.70:
		map_data[x][y] = CellType.ROCK  # Boulders
	elif roll < 0.82:
		map_data[x][y] = CellType.GRASS  # Hardy grass
	elif roll < 0.92:
		map_data[x][y] = CellType.WALL  # Cliff faces
	elif roll < 0.97:
		map_data[x][y] = CellType.TREE  # Scrub trees
	else:
		map_data[x][y] = CellType.FLOOR  # Scree

func _generate_wetland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.35:
		map_data[x][y] = CellType.GRASS  # Tall grass
	elif roll < 0.60:
		map_data[x][y] = CellType.WATER  # Puddles
	elif roll < 0.75:
		map_data[x][y] = CellType.FLOOR  # Muddy ground
	elif roll < 0.85:
		map_data[x][y] = CellType.TREE  # Willow trees
	elif roll < 0.94:
		map_data[x][y] = CellType.ROCK  # Stones
	else:
		map_data[x][y] = CellType.GRASS  # Reeds

func _generate_swamp_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.25:
		map_data[x][y] = CellType.GRASS  # Swamp grass
	elif roll < 0.55:
		map_data[x][y] = CellType.WATER  # Deep water
	elif roll < 0.70:
		map_data[x][y] = CellType.FLOOR  # Mud
	elif roll < 0.82:
		map_data[x][y] = CellType.TREE  # Dead trees
	elif roll < 0.92:
		map_data[x][y] = CellType.ROCK  # Submerged rocks
	else:
		map_data[x][y] = CellType.GRASS  # Moss-covered logs

func _generate_highland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.35:
		map_data[x][y] = CellType.GRASS  # Alpine grass
	elif roll < 0.60:
		map_data[x][y] = CellType.FLOOR  # Rocky soil
	elif roll < 0.75:
		map_data[x][y] = CellType.ROCK  # Scattered boulders
	elif roll < 0.85:
		map_data[x][y] = CellType.TREE  # Stunted trees
	elif roll < 0.94:
		map_data[x][y] = CellType.WALL  # Cliff edges
	else:
		map_data[x][y] = CellType.GRASS  # Mountain flowers

func _generate_mountain_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.22:
		map_data[x][y] = CellType.WALL
	elif roll < 0.37:
		map_data[x][y] = CellType.ROCK
	elif roll < 0.82:
		map_data[x][y] = CellType.GRASS
	else:
		map_data[x][y] = CellType.FLOOR

func _generate_snowland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.45:
		map_data[x][y] = CellType.ICE  # Snow
	elif roll < 0.68:
		map_data[x][y] = CellType.FLOOR  # Packed snow
	elif roll < 0.80:
		map_data[x][y] = CellType.GRASS  # Frozen grass
	elif roll < 0.90:
		map_data[x][y] = CellType.TREE  # Snow-covered trees
	elif roll < 0.97:
		map_data[x][y] = CellType.ROCK  # Exposed rocks
	else:
		map_data[x][y] = CellType.ICE  # Ice patches

func _generate_frozen_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.50:
		map_data[x][y] = CellType.ICE  # Thick ice
	elif roll < 0.72:
		map_data[x][y] = CellType.WATER  # Frozen water
	elif roll < 0.85:
		map_data[x][y] = CellType.FLOOR  # Ice-covered ground
	elif roll < 0.93:
		map_data[x][y] = CellType.ROCK  # Glacial rocks
	elif roll < 0.98:
		map_data[x][y] = CellType.TREE  # Frozen trees
	else:
		map_data[x][y] = CellType.ICE  # Ice formations

func _generate_coast_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.30:
		map_data[x][y] = CellType.WATER  # Shoreline water
	elif roll < 0.55:
		map_data[x][y] = CellType.FLOOR  # Sand
	elif roll < 0.72:
		map_data[x][y] = CellType.GRASS  # Beach grass
	elif roll < 0.85:
		map_data[x][y] = CellType.ROCK  # Coastal rocks
	elif roll < 0.94:
		map_data[x][y] = CellType.ASH  # Driftwood
	else:
		map_data[x][y] = CellType.TREE  # Palm trees

func _generate_riverbank_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.35:
		map_data[x][y] = CellType.WATER  # River water
	elif roll < 0.60:
		map_data[x][y] = CellType.GRASS  # River grass
	elif roll < 0.75:
		map_data[x][y] = CellType.FLOOR  # Muddy banks
	elif roll < 0.85:
		map_data[x][y] = CellType.TREE  # River trees
	elif roll < 0.94:
		map_data[x][y] = CellType.ROCK  # River stones
	else:
		map_data[x][y] = CellType.GRASS  # Reeds

func _generate_lakeshore_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.30:
		map_data[x][y] = CellType.WATER  # Lake water
	elif roll < 0.58:
		map_data[x][y] = CellType.GRASS  # Lakeside grass
	elif roll < 0.73:
		map_data[x][y] = CellType.FLOOR  # Sandy shore
	elif roll < 0.85:
		map_data[x][y] = CellType.TREE  # Lakeside trees
	elif roll < 0.94:
		map_data[x][y] = CellType.ROCK  # Beach rocks
	else:
		map_data[x][y] = CellType.GRASS  # Water plants

func _generate_wasteland_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.40:
		map_data[x][y] = CellType.ASH  # Scorched earth
	elif roll < 0.65:
		map_data[x][y] = CellType.FLOOR  # Cracked ground
	elif roll < 0.80:
		map_data[x][y] = CellType.ROCK  # Rubble
	elif roll < 0.90:
		map_data[x][y] = CellType.GRASS  # Dead vegetation
	elif roll < 0.97:
		map_data[x][y] = CellType.WALL  # Ruined walls
	else:
		map_data[x][y] = CellType.ASH  # Ash piles

func _generate_anomaly_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.30:
		map_data[x][y] = CellType.CRYSTAL_FLOOR  # Crystal formations
	elif roll < 0.55:
		map_data[x][y] = CellType.FLOOR  # Distorted ground
	elif roll < 0.75:
		map_data[x][y] = CellType.ROCK  # Floating rocks
	elif roll < 0.88:
		map_data[x][y] = CellType.WATER  # Reality tears
	elif roll < 0.96:
		map_data[x][y] = CellType.PIT  # Void pits
	else:
		map_data[x][y] = CellType.CRYSTAL_FLOOR  # Anomalous crystals

func _generate_dungeon_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.50:
		map_data[x][y] = CellType.ASH  # Stone floor
	elif roll < 0.75:
		map_data[x][y] = CellType.GRASS  # Overgrown patches
	elif roll < 0.88:
		map_data[x][y] = CellType.FLOOR  # Clear ground
	elif roll < 0.95:
		map_data[x][y] = CellType.ROCK  # Rubble
	else:
		map_data[x][y] = CellType.ASH  # Ancient stone

func _generate_road_terrain(map_data: Array, x: int, y: int, elevation: float):
	var roll = randf()
	if roll < 0.70:
		map_data[x][y] = CellType.ASH  # Paved road
	elif roll < 0.85:
		map_data[x][y] = CellType.FLOOR  # Dirt path
	elif roll < 0.92:
		map_data[x][y] = CellType.GRASS  # Roadside grass
	elif roll < 0.97:
		map_data[x][y] = CellType.ROCK  # Road stones
	else:
		map_data[x][y] = CellType.ASH  # Cobblestones

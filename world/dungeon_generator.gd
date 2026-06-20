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
		water_chance = clamp(30 + depth_factor * 2, 20, 60)
		grass_chance = clamp(25 - depth_factor, 10, 25)
		
	_generate_water(map_data, water_chance, water_steps)
	if current_branch == 4:
		_generate_ash(map_data, 85)
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
					if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.CRYSTAL_FLOOR:
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
		
	if has_left:
		for x in range(margin, road_x + 1):
			map_data[x][road_y] = CellType.ASH
			map_data[x][road_y + 1] = CellType.ASH
			road_tiles.append(Vector2i(x, road_y))
			road_tiles.append(Vector2i(x, road_y + 1))
	if has_right:
		for x in range(road_x, MAP_WIDTH - margin):
			map_data[x][road_y] = CellType.ASH
			map_data[x][road_y + 1] = CellType.ASH
			road_tiles.append(Vector2i(x, road_y))
			road_tiles.append(Vector2i(x, road_y + 1))
	if has_up:
		for y in range(margin, road_y + 1):
			map_data[road_x][y] = CellType.ASH
			map_data[road_x + 1][y] = CellType.ASH
			road_tiles.append(Vector2i(road_x, y))
			road_tiles.append(Vector2i(road_x + 1, y))
	if has_down:
		for y in range(road_y, MAP_HEIGHT - margin):
			map_data[road_x][y] = CellType.ASH
			map_data[road_x + 1][y] = CellType.ASH
			road_tiles.append(Vector2i(road_x, y))
			road_tiles.append(Vector2i(road_x + 1, y))
		
	var square_w = 6
	var square_h = 6
	var square = Rect2i(road_x - 2, road_y - 2, square_w, square_h)
	for x in range(square.position.x, square.position.x + square.size.x):
		for y in range(square.position.y, square.position.y + square.size.y):
			if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
				map_data[x][y] = CellType.ASH
				
	var cave_entrance = Vector2i(road_x - 3, road_y - 3)
	
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
		
	# 洞窟の入口（階段）の配置
	if is_starting_village:
		map_data[cave_entrance.x][cave_entrance.y] = CellType.STAIRS_GOLD
	elif is_dungeon_village:
		map_data[cave_entrance.x][cave_entrance.y] = CellType.STAIRS
	else:
		map_data[cave_entrance.x][cave_entrance.y] = CellType.FLOOR
		
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
			
	# 2. 道路パターンの決定と生成
	# 石畳(ASH)で道路を引く。幅は2マス。
	var road_tiles = [] # 道路の座標リスト
	var road_y = randi_range(MAP_HEIGHT / 3, MAP_HEIGHT * 2 / 3)
	
	# 横のメイン道路
	for x in range(margin, MAP_WIDTH - margin):
		map_data[x][road_y] = CellType.ASH
		map_data[x][road_y + 1] = CellType.ASH
		road_tiles.append(Vector2i(x, road_y))
		road_tiles.append(Vector2i(x, road_y + 1))
		
	# 縦のサブ道路 (ランダムで交差させる)
	var has_vertical_road = randf() < 0.7
	var road_x = randi_range(MAP_WIDTH / 3, MAP_WIDTH * 2 / 3)
	if has_vertical_road:
		for y in range(margin, MAP_HEIGHT - margin):
			map_data[road_x][y] = CellType.ASH
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
				map_data[x][y] = CellType.ASH
				
	# 広場の中央に井戸(WATER)
	map_data[center_x][center_y] = CellType.WATER
	map_data[center_x + 1][center_y] = CellType.WATER
	map_data[center_x][center_y + 1] = CellType.WATER
	map_data[center_x + 1][center_y + 1] = CellType.WATER

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
				map_data[px][door_pos.y] = CellType.FLOOR
		elif door_pos.x == house_rect.position.x + house_rect.size.x - 1: # 右ドア
			for px in range(door_pos.x + 1, MAP_WIDTH - margin):
				if map_data[px][door_pos.y] == CellType.ASH: break
				map_data[px][door_pos.y] = CellType.FLOOR
		elif door_pos.y == house_rect.position.y: # 上ドア
			for py in range(margin, door_pos.y):
				if map_data[door_pos.x][py] == CellType.ASH: break
				map_data[door_pos.x][py] = CellType.FLOOR
		else: # 下ドア
			for py in range(door_pos.y + 1, MAP_HEIGHT - margin):
				if map_data[door_pos.x][py] == CellType.ASH: break
				map_data[door_pos.x][py] = CellType.FLOOR
				
		rooms.append(house_rect)
		houses.append(house_rect)

	# 5. 階段（出口）の配置
	# 道路の端のいずれか（水平ロードの左端、右端、または垂直ロードの上端、下端）にランダム配置
	var stair_positions = []
	stair_positions.append(Vector2i(margin, road_y)) # 左端
	stair_positions.append(Vector2i(MAP_WIDTH - margin - 1, road_y)) # 右端
	if has_vertical_road:
		stair_positions.append(Vector2i(road_x, margin)) # 上端
		stair_positions.append(Vector2i(road_x, MAP_HEIGHT - margin - 1)) # 下端
		
	var stair_pos = stair_positions.pick_random()
	map_data[stair_pos.x][stair_pos.y] = CellType.STAIRS
	
	# 上の階層へ戻るための上り階段を広場（井戸の横）に配置
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
			if temp_map[x][y] == CellType.WATER and map_data[x][y] != CellType.WALL:
				map_data[x][y] = CellType.WATER
			elif temp_map[x][y] == CellType.FLOOR and map_data[x][y] == CellType.WATER:
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
			if current_step_map[x][y] == CellType.GRASS and map_data[x][y] == CellType.FLOOR:
				map_data[x][y] = CellType.GRASS

func _generate_ash(map_data: Array, initial_chance: int):
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			if map_data[x][y] == CellType.FLOOR and randi() % 100 < initial_chance:
				map_data[x][y] = CellType.ASH

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
			if temp_map[x][y] == CellType.LAVA and map_data[x][y] != CellType.WALL:
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
			if current_map[x][y] == CellType.CRYSTAL_FLOOR and map_data[x][y] == CellType.FLOOR:
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
		if map_data[point.x][point.y] == CellType.WATER or map_data[point.x][point.y] == CellType.LAVA:
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
		if map_data[pos.x][pos.y] == CellType.WATER or map_data[pos.x][pos.y] == CellType.LAVA:
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
						if cell == CellType.FLOOR or cell == CellType.GRASS or cell == CellType.ASH or cell == CellType.CRYSTAL_FLOOR:
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

func generate_local_overworld(local_type: int, main_inst: Node2D = null, is_starting_village: bool = false, is_dungeon_village: bool = false) -> Dictionary:
	# If village, use the standard overworld village generation
	if local_type == WorldCell.VILLAGE:
		return _generate_overworld(main_inst, is_starting_village, is_dungeon_village)
		
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
				WorldCell.FOREST:
					map_data[x][y] = CellType.GRASS if randf() < 0.8 else CellType.FLOOR
				WorldCell.DUNGEON:
					map_data[x][y] = CellType.ASH if randf() < 0.5 else (CellType.GRASS if randf() < 0.6 else CellType.FLOOR)
				WorldCell.MOUNTAIN:
					map_data[x][y] = CellType.WALL if randf() < 0.60 else (CellType.ROCK if randf() < 0.25 else CellType.ASH)
				WorldCell.SEA:
					map_data[x][y] = CellType.WATER
				_: # WorldCell.GRASS or ROAD
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
			rock_chance = 0.10

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
		
		# For GRASS, FOREST, MOUNTAIN, draw a short side-road (e.g. length of 7 tiles from edge)
		if local_type == WorldCell.GRASS or local_type == WorldCell.FOREST or local_type == WorldCell.MOUNTAIN:
			path_len_x = 7
			path_len_y = 7
			
		# Draw horizontal road (Left)
		if has_left:
			var start_x = 0
			var end_x = cx if (local_type == WorldCell.ROAD or local_type == WorldCell.DUNGEON) else path_len_x
			for rx in range(start_x, end_x + 1):
				for w in range(-road_width/2, road_width/2 + (1 if road_width % 2 == 1 else 0)):
					var ry = cy + w
					if ry >= 0 and ry < MAP_HEIGHT:
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
						map_data[rx][ry] = CellType.ASH
						
		# Draw vertical road (Up)
		if has_up:
			var start_y = 0
			var end_y = cy if (local_type == WorldCell.ROAD or local_type == WorldCell.DUNGEON) else path_len_y
			for ry in range(start_y, end_y + 1):
				for w in range(-road_width/2, road_width/2 + (1 if road_width % 2 == 1 else 0)):
					var rx = cx + w
					if rx >= 0 and rx < MAP_WIDTH:
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
						map_data[rx][ry] = CellType.ASH
						
	var rooms = [Rect2i(MAP_WIDTH/2 - 2, MAP_HEIGHT/2 - 2, 4, 4)]
	
	# Clear spawn area
	for x in range(MAP_WIDTH/2 - 3, MAP_WIDTH/2 + 4):
		for y in range(MAP_HEIGHT/2 - 3, MAP_HEIGHT/2 + 4):
			if x >= margin and x < MAP_WIDTH - margin and y >= margin and y < MAP_HEIGHT - margin:
				if map_data[x][y] == CellType.WALL and Vector2i(x, y) != cave_entrance:
					map_data[x][y] = CellType.FLOOR

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

func generate_world_map() -> Array:
	var world = []
	world.resize(MAP_WIDTH)
	for x in range(MAP_WIDTH):
		world[x] = []
		world[x].resize(MAP_HEIGHT)
		for y in range(MAP_HEIGHT):
			world[x][y] = WorldCell.SEA
			
	var seeds = []
	for i in range(6):
		var sx = randi_range(8, MAP_WIDTH - 9)
		var sy = randi_range(6, MAP_HEIGHT - 7)
		seeds.append(Vector2i(sx, sy))
		
	# Expand land masses
	for center in seeds:
		var radius = randi_range(6, 12)
		for x in range(center.x - radius, center.x + radius + 1):
			for y in range(center.y - radius, center.y + radius + 1):
				if x >= 1 and x < MAP_WIDTH - 1 and y >= 1 and y < MAP_HEIGHT - 1:
					var dist = Vector2(x - center.x, y - center.y).length()
					if dist <= radius:
						var noise = randf()
						if dist < radius - 2.0 or noise < 0.45:
							world[x][y] = WorldCell.GRASS
							
	# Generate mountain ranges
	for i in range(3):
		var start = seeds.pick_random()
		var curr = start
		for step in range(randi_range(8, 15)):
			world[curr.x][curr.y] = WorldCell.MOUNTAIN
			var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
			curr = curr + dirs.pick_random()
			curr.x = clamp(curr.x, 2, MAP_WIDTH - 3)
			curr.y = clamp(curr.y, 2, MAP_HEIGHT - 3)
			if world[curr.x][curr.y] == WorldCell.SEA:
				break
				
	# Generate forests
	for x in range(1, MAP_WIDTH - 1):
		for y in range(1, MAP_HEIGHT - 1):
			if world[x][y] == WorldCell.GRASS:
				var near_mountain = false
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						var nx = x + dx
						var ny = y + dy
						if nx >= 0 and nx < MAP_WIDTH and ny >= 0 and ny < MAP_HEIGHT:
							if world[nx][ny] == WorldCell.MOUNTAIN:
								near_mountain = true
								break
				if near_mountain and randf() < 0.4:
					world[x][y] = WorldCell.FOREST
				elif randf() < 0.15:
					world[x][y] = WorldCell.FOREST
					
	# Place 3 Villages
	var villages = []
	var v0 = seeds[0]
	world[v0.x][v0.y] = WorldCell.VILLAGE
	villages.append(v0)
	
	for i in range(1, seeds.size()):
		if villages.size() >= 3: break
		var pos = seeds[i]
		if world[pos.x][pos.y] == WorldCell.GRASS or world[pos.x][pos.y] == WorldCell.FOREST:
			world[pos.x][pos.y] = WorldCell.VILLAGE
			villages.append(pos)
			
	var attempts = 100
	while villages.size() < 3 and attempts > 0:
		attempts -= 1
		var vx = randi_range(3, MAP_WIDTH - 4)
		var vy = randi_range(3, MAP_HEIGHT - 4)
		if world[vx][vy] == WorldCell.GRASS or world[vx][vy] == WorldCell.FOREST:
			var too_close = false
			for v in villages:
				if Vector2i(vx, vy).distance_to(v) < 10.0:
					too_close = true
					break
			if not too_close:
				world[vx][vy] = WorldCell.VILLAGE
				villages.append(Vector2i(vx, vy))
				
	# Place 4 Dungeons
	var dungeons = []
	attempts = 200
	while dungeons.size() < 4 and attempts > 0:
		attempts -= 1
		var dx = randi_range(3, MAP_WIDTH - 4)
		var dy = randi_range(3, MAP_HEIGHT - 4)
		if world[dx][dy] == WorldCell.GRASS or world[dx][dy] == WorldCell.FOREST or world[dx][dy] == WorldCell.MOUNTAIN:
			var too_close = false
			for v in villages:
				if Vector2i(dx, dy).distance_to(v) < 6.0:
					too_close = true
					break
			for d in dungeons:
				if Vector2i(dx, dy).distance_to(d) < 8.0:
					too_close = true
					break
			if not too_close:
				world[dx][dy] = WorldCell.DUNGEON
				dungeons.append(Vector2i(dx, dy))
				
	# Place roads connecting villages and dungeons
	for i in range(villages.size()):
		var v1 = villages[i]
		var v2 = villages[(i + 1) % villages.size()]
		_draw_road(world, v1, v2)
		
		for d in dungeons:
			if v1.distance_to(d) < 15.0:
				_draw_road(world, v1, d)
				
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
				if map_data[x][y] == CellType.WALL:
					map_data[x][y] = CellType.GRASS if randf() < 0.7 else CellType.FLOOR

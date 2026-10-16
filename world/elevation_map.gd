class_name ElevationMap
extends RefCounted

const LOW = 0
const NORMAL = 1
const HIGH = 2

static func normalize(data: Array, width: int, depth: int) -> Array:
	var result: Array = []
	for x in range(width):
		var column: Array = []
		for y in range(depth):
			var value = data[x][y] if x < data.size() and data[x] is Array and y < data[x].size() else NORMAL
			column.append(clampi(int(value), LOW, HIGH))
		result.append(column)
	return result

static func get_height(data: Array, pos: Vector2i) -> int:
	if pos.x < 0 or pos.x >= data.size() or pos.y < 0 or pos.y >= data[pos.x].size():
		return NORMAL
	return int(data[pos.x][pos.y])

static func can_step(data: Array, from: Vector2i, to: Vector2i) -> bool:
	return absi(get_height(data, from) - get_height(data, to)) <= 1

static func flatten_roads(data: Array, terrain: Array):
	for x in range(mini(data.size(), terrain.size())):
		for y in range(mini(data[x].size(), terrain[x].size())):
			if terrain[x][y] == MapDefinitions.CellType.ASH: data[x][y] = NORMAL

static func generate(terrain: Array) -> Array:
	if terrain.is_empty(): return []
	var width = terrain.size()
	var depth = terrain[0].size()
	var result = normalize([], width, depth)
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.045
	noise.fractal_octaves = 2
	for x in range(width):
		for y in range(depth):
			var value = noise.get_noise_2d(x, y)
			result[x][y] = LOW if value < -0.42 else (HIGH if value > 0.42 else NORMAL)
			# Water remains a continuous surface; flow rules can later replace this.
			if terrain[x][y] in [MapDefinitions.CellType.WATER, MapDefinitions.CellType.ASH]: result[x][y] = NORMAL
	# Build ramps along a spanning tree of each existing land component.
	# Every previously connected land tile remains reachable, while other edges
	# may retain cliffs with a two-level difference and require a detour.
	var visited = {}
	for x in range(width):
		for y in range(depth):
			var start = Vector2i(x, y)
			if visited.has(start) or not is_land(terrain[x][y]): continue
			var queue: Array[Vector2i] = [start]
			visited[start] = true
			var index = 0
			while index < queue.size():
				var current = queue[index]
				index += 1
				for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var next = current + dir
					if next.x < 0 or next.x >= width or next.y < 0 or next.y >= depth: continue
					if visited.has(next) or not is_land(terrain[next.x][next.y]): continue
					result[next.x][next.y] = clampi(result[next.x][next.y], maxi(LOW, result[current.x][current.y] - 1), mini(HIGH, result[current.x][current.y] + 1))
					visited[next] = true
					queue.append(next)
	return result

static func is_land(cell: int) -> bool:
	const C = MapDefinitions.CellType
	return cell not in [C.WALL, C.WOOD_WALL, C.DOOR_LOCKED, C.WATER, C.LAVA, C.PIT, C.TREE, C.TREE_FRUIT, C.ROCK]

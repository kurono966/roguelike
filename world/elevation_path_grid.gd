class_name ElevationPathGrid
extends RefCounted

# Grid-compatible facade over AStar2D. Edges, rather than entire tiles,
# are filtered: a high tile can be reached from normal but not from low.
class HeightGraph extends AStar2D:
	var grid
	func _filter_neighbor(from_id: int, neighbor_id: int) -> bool:
		var owner_grid = grid.get_ref()
		return not owner_grid.can_step(owner_grid.to_cell(from_id), owner_grid.to_cell(neighbor_id))

var region = Rect2i()
var cell_size = Vector2.ONE
var diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
var jumping_enabled = false
var heights: Array = []
var _built_region = Rect2i()
var _graph = HeightGraph.new()

func _init():
	# Weak reference avoids a RefCounted cycle.
	_graph.grid = weakref(self)
	_graph.neighbor_filter_enabled = true

func to_id(pos: Vector2i) -> int:
	return (pos.y - region.position.y) * region.size.x + pos.x - region.position.x

func to_cell(id: int) -> Vector2i:
	return region.position + Vector2i(id % region.size.x, id / region.size.x)

func is_dirty() -> bool:
	return region != _built_region

func update():
	_graph.clear()
	_built_region = region
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var pos = Vector2i(x, y)
			_graph.add_point(to_id(pos), Vector2(pos) * cell_size)
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var pos = Vector2i(x, y)
			for dir in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1)]:
				if region.has_point(pos + dir): _graph.connect_points(to_id(pos), to_id(pos + dir))

func set_point_solid(pos: Vector2i, solid: bool = true):
	if region.has_point(pos): _graph.set_point_disabled(to_id(pos), solid)

func is_point_solid(pos: Vector2i) -> bool:
	return not region.has_point(pos) or _graph.is_point_disabled(to_id(pos))

func can_step(from: Vector2i, to: Vector2i) -> bool:
	if is_point_solid(to) or not ElevationMap.can_step(heights, from, to): return false
	var diff = to - from
	if absi(diff.x) == 1 and absi(diff.y) == 1:
		var side_x = from + Vector2i(diff.x, 0)
		var side_y = from + Vector2i(0, diff.y)
		if is_point_solid(side_x) or is_point_solid(side_y): return false
	return true

func get_id_path(from: Vector2i, to: Vector2i, allow_partial_path: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not region.has_point(from) or is_point_solid(to): return result
	for id in _graph.get_id_path(to_id(from), to_id(to), allow_partial_path): result.append(to_cell(id))
	return result

func get_point_path(from: Vector2i, to: Vector2i, allow_partial_path: bool = false) -> PackedVector2Array:
	var result = PackedVector2Array()
	for cell in get_id_path(from, to, allow_partial_path): result.append(Vector2(cell) * cell_size)
	return result

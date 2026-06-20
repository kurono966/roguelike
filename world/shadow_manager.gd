class_name ShadowManager
extends Node2D

const CellType = MapDefinitions.CellType
const TILE_SIZE = MapDefinitions.TILE_SIZE

var _occluders: Dictionary = {}
var _wall_occluders: Array[LightOccluder2D] = []

func rebuild(map_data: Array):
	for occluder in _occluders.values():
		if is_instance_valid(occluder):
			occluder.queue_free()
	_occluders.clear()
	for occluder in _wall_occluders:
		if is_instance_valid(occluder):
			occluder.queue_free()
	_wall_occluders.clear()

	if map_data.is_empty():
		return

	var width = map_data.size()
	var height = map_data[0].size()
	for y in range(height):
		var run_start = -1
		for x in range(width + 1):
			var is_wall = x < width and map_data[x][y] == CellType.WALL
			if is_wall and run_start < 0:
				run_start = x
			elif not is_wall and run_start >= 0:
				_add_wall_run(run_start, x, y)
				run_start = -1

	for x in range(width):
		for y in range(map_data[x].size()):
			if map_data[x][y] != CellType.WALL:
				update_cell(Vector2i(x, y), map_data[x][y])

func update_cell(cell: Vector2i, cell_type: int):
	var old_occluder = _occluders.get(cell)
	if is_instance_valid(old_occluder):
		old_occluder.queue_free()
	_occluders.erase(cell)

	var polygon = _make_polygon(cell_type)
	if polygon.is_empty():
		return

	var shape = OccluderPolygon2D.new()
	shape.polygon = polygon

	var occluder = LightOccluder2D.new()
	occluder.position = Vector2(cell) * TILE_SIZE
	occluder.occluder = shape
	occluder.occluder_light_mask = 1
	add_child(occluder)
	_occluders[cell] = occluder

func _add_wall_run(start_x: int, end_x: int, y: int):
	var width = float(end_x - start_x) * TILE_SIZE
	var height = float(TILE_SIZE)
	var shape = OccluderPolygon2D.new()
	shape.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(width, 0.0),
		Vector2(width, height),
		Vector2(0.0, height)
	])

	var occluder = LightOccluder2D.new()
	occluder.position = Vector2(start_x * TILE_SIZE, y * TILE_SIZE)
	occluder.occluder = shape
	occluder.occluder_light_mask = 1
	add_child(occluder)
	_wall_occluders.append(occluder)

func _make_polygon(cell_type: int) -> PackedVector2Array:
	var size = float(TILE_SIZE)
	var center = size * 0.5

	match cell_type:
		CellType.WALL:
			return PackedVector2Array([
				Vector2.ZERO,
				Vector2(size, 0.0),
				Vector2(size, size),
				Vector2(0.0, size)
			])
		CellType.DOOR_CLOSED, CellType.DOOR_LOCKED:
			return PackedVector2Array([
				Vector2(4.0, 0.0),
				Vector2(size - 4.0, 0.0),
				Vector2(size - 4.0, size),
				Vector2(4.0, size)
			])
		CellType.TREE, CellType.TREE_FRUIT:
			var radius = center * 0.88
			var diagonal = radius * 0.707
			return PackedVector2Array([
				Vector2(center, center - radius),
				Vector2(center + diagonal, center - diagonal),
				Vector2(center + radius, center),
				Vector2(center + diagonal, center + diagonal),
				Vector2(center, center + radius),
				Vector2(center - diagonal, center + diagonal),
				Vector2(center - radius, center),
				Vector2(center - diagonal, center - diagonal)
			])
		CellType.ROCK:
			var radius = center * 0.72
			var diagonal = radius * 0.707
			return PackedVector2Array([
				Vector2(center, center - radius * 0.9),
				Vector2(center + radius, center - radius * 0.3),
				Vector2(center + diagonal, center + diagonal),
				Vector2(center - diagonal, center + diagonal),
				Vector2(center - radius, center - radius * 0.3)
			])

	return PackedVector2Array()

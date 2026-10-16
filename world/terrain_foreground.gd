extends "res://world/elevation_overlay.gd"

var _elapsed = 0.0

func _init():
	var foreground_material = ShaderMaterial.new()
	foreground_material.shader = preload("res://world/terrain_foreground.gdshader")
	material = foreground_material
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float):
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		queue_redraw() # The atlas texture is replaced by water/crystal animation.

func _draw():
	if not is_instance_valid(main) or main._is_on_world_map: return
	var source = main.tile_map.tile_set.get_source(0)
	var size = float(MapDefinitions.TILE_SIZE)
	for x in range(main._map_data.size()):
		for y in range(main._map_data[x].size()):
			if not main._explored_tiles[x][y]: continue
			var cell = main._map_data[x][y]
			if cell == MapDefinitions.CellType.GRASS:
				_draw_grounded_grass(Vector2(x, y) * size, main.get_tile_height(Vector2i(x, y)), 1.0 if main._visible_tiles[x][y] else 0.35)
				continue
			if not ElevationMap.is_land(cell) and cell != MapDefinitions.CellType.WATER: continue
			var coords = main._get_map_cell_atlas_coords(main._map_data, x, y)
			var tint = Color.WHITE if main._visible_tiles[x][y] else Color(0.35, 0.35, 0.35, 1.0)
			draw_texture_rect_region(source.texture, Rect2(Vector2(x, y) * size, Vector2.ONE * size), Rect2(Vector2(coords) * size, Vector2.ONE * size), tint)

extends Node2D

var main

func _init():
	var blur_material = ShaderMaterial.new()
	blur_material.shader = preload("res://world/elevation_blur.gdshader")
	material = blur_material

func _draw():
	if not is_instance_valid(main) or main._is_on_world_map or not is_instance_valid(main.player): return
	var player_grid = main.tile_map.local_to_map(main.player.position)
	var player_height = main.get_tile_height(player_grid)
	var size = float(MapDefinitions.TILE_SIZE)
	for x in range(main._map_data.size()):
		for y in range(main._map_data[x].size()):
			var pos = Vector2i(x, y)
			if not main._explored_tiles[x][y] or not ElevationMap.is_land(main._map_data[x][y]): continue
			if main.get_tile_height(pos) != player_height:
				draw_rect(Rect2(Vector2(pos) * size, Vector2.ONE * size), Color.WHITE)

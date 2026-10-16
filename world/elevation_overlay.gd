extends Node2D

var main

func _draw():
	if not is_instance_valid(main) or main._is_on_world_map: return
	var size = float(MapDefinitions.TILE_SIZE)
	var ledges: Array = []
	for x in range(main._map_data.size()):
		for y in range(main._map_data[x].size()):
			if not main._explored_tiles[x][y]: continue
			if main._map_data[x][y] == MapDefinitions.CellType.WATER:
				_draw_water_depth(Vector2i(x, y), size)
				continue
			if not ElevationMap.is_land(main._map_data[x][y]): continue
			var pos = Vector2i(x, y)
			var height = main.get_tile_height(pos)
			var opacity = 1.0 if main._visible_tiles[x][y] else 0.35
			var origin = Vector2(pos) * size
			if main._map_data[x][y] == MapDefinitions.CellType.GRASS:
				# Replace the flat grass glyph with a tuft rooted in this surface.
				# Opaque ground also removes the old glyph in remembered tiles.
				draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.02, 0.05, 0.025).darkened(1.0 - opacity))
			if height == ElevationMap.LOW:
				draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.025, 0.10, 0.18, 0.42 * opacity))
			elif height == ElevationMap.HIGH:
				draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.78, 0.72, 0.52, 0.23 * opacity))
			# Height reads through continuous region contours, not per-tile badges.
			for dir in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				var neighbor = pos + dir
				if not main._is_grid_in_bounds(neighbor): continue
				# Do not reveal unseen terrain or draw cliffs against solid walls.
				if not main._explored_tiles[neighbor.x][neighbor.y] or not ElevationMap.is_land(main._map_data[neighbor.x][neighbor.y]): continue
				var difference = height - main.get_tile_height(neighbor)
				if difference <= 0: continue
				var edge_opacity = opacity if main._visible_tiles[neighbor.x][neighbor.y] else 0.35
				ledges.append([origin, dir, difference, edge_opacity])
	# Paint boundaries after all surfaces so shading is independent of map traversal.
	for ledge in ledges:
		_draw_ledge(ledge[0], ledge[1], ledge[2], ledge[3], size)
	# Vegetation and floor markings are painted by terrain_foreground after blur.

func _draw_water_depth(pos: Vector2i, size: float):
	var origin = Vector2(pos) * size
	var opacity = 1.0 if main._visible_tiles[pos.x][pos.y] else 0.35
	var depth = clampf(main.get_surface_height(pos) - main.get_tile_height(pos), 0.0, 1.0)
	draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.0, 0.05, 0.16, depth * 0.23 * opacity))
	# A submerged bank fades into the basin while the animated surface stays level.
	for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var adjacent = pos + dir
		if not main._is_grid_in_bounds(adjacent) or not main._explored_tiles[adjacent.x][adjacent.y]: continue
		if not ElevationMap.is_land(main._map_data[adjacent.x][adjacent.y]): continue
		var start = origin
		var tangent = Vector2.RIGHT
		if dir == Vector2i.RIGHT:
			start += Vector2(size, 0)
			tangent = Vector2.DOWN
		elif dir == Vector2i.DOWN: start += Vector2(0, size)
		elif dir == Vector2i.LEFT: tangent = Vector2.DOWN
		_draw_gradient_band(start, start + tangent * size, -Vector2(dir) * 10,
			Color(0.16, 0.40, 0.44, 0.4 * opacity), Color(0.01, 0.08, 0.18, 0.0))

func _draw_grounded_grass(origin: Vector2, height: int, opacity: float):
	# Use the same atlas tile as neighboring previews; height only changes its
	# placement/tint, never the grass design itself.
	var source = main.tile_map.tile_set.get_source(0)
	var tint = Color(1.0, 1.0, 1.0, opacity)
	if height == ElevationMap.HIGH: tint = Color(1.15, 1.10, 0.80, opacity)
	elif height == ElevationMap.LOW: tint = Color(0.75, 0.85, 1.0, opacity)
	var offset = Vector2(0, (1 - height) * 3)
	draw_texture_rect_region(source.texture, Rect2(origin + offset, Vector2(32, 32)), Rect2(Vector2(34 * 32, 0), Vector2(32, 32)), tint)

func _draw_gradient_band(start: Vector2, end: Vector2, offset: Vector2, near_color: Color, far_color: Color):
	# Smoothstep fading keeps a broad, readable gradient without a hard outer edge.
	for i in range(6):
		var t0 = float(i) / 6.0
		var t1 = float(i + 1) / 6.0
		var color0 = near_color.lerp(far_color, smoothstep(0.0, 1.0, t0))
		var color1 = near_color.lerp(far_color, smoothstep(0.0, 1.0, t1))
		draw_polygon(
			PackedVector2Array([start + offset * t0, end + offset * t0, end + offset * t1, start + offset * t1]),
			PackedColorArray([color0, color0, color1, color1])
		)

func _draw_ledge(origin: Vector2, dir: Vector2i, difference: int, opacity: float, size: float):
	var normal = Vector2(dir)
	var start = origin
	var tangent = Vector2.RIGHT
	if dir == Vector2i.RIGHT:
		start += Vector2(size, 0)
		tangent = Vector2.DOWN
	elif dir == Vector2i.DOWN:
		start += Vector2(0, size)
	elif dir == Vector2i.LEFT:
		tangent = Vector2.DOWN
	var end = start + tangent * size
	# One light source, from the upper left, makes the entire contour read as
	# a raised plateau or a recessed basin instead of unrelated colored squares.
	var light = Vector2(-0.6, -0.8)
	var illumination = clampf((normal.dot(light) + 1.0) * 0.5, 0.0, 1.0)
	var facing_depth = 1.0 if dir == Vector2i.DOWN else (0.8 if dir == Vector2i.RIGHT else 0.45)
	var depth = (7.0 if difference == 1 else 12.0) * facing_depth
	var fade_width = size
	var cast_strength = 0.18 + (1.0 - illumination) * 0.20
	# Tight contact shadow establishes the height of the edge; its broad tail
	# fades over the lower neighbor without covering the terrain's crisp markings.
	_draw_gradient_band(start, end, normal * fade_width,
		Color(0.015, 0.025, 0.045, cast_strength * opacity), Color(0.015, 0.025, 0.045, 0.0))
	_draw_gradient_band(start, end, normal * (5.0 + difference * 2),
		Color(0.005, 0.01, 0.02, (0.58 + difference * 0.08) * opacity), Color(0.005, 0.01, 0.02, 0.0))
	_draw_lower_approach(start, tangent, normal, difference, opacity, size)
	_draw_gradient_band(start - normal * depth, end - normal * depth, -normal * (fade_width - depth),
		Color(0.95, 0.87, 0.67, (0.12 + illumination * 0.16) * opacity), Color(0.95, 0.87, 0.67, 0.0))
	# Exposed earth is deeper on south/east edges, with a bright top lip.
	var face_color = Color(0.14, 0.12, 0.095).lerp(Color(0.36, 0.32, 0.24), illumination)
	_draw_gradient_band(start, end, -normal * depth,
		Color(0.045, 0.04, 0.035, 0.95 * opacity), Color(face_color, 0.86 * opacity))
	for seam in range(1, difference + 1):
		var seam_offset = normal * (depth * float(seam) / float(difference + 1))
		draw_line(start - seam_offset, end - seam_offset, Color(0.52, 0.45, 0.31, 0.20 * opacity), 1)
	draw_line(start - normal * depth, end - normal * depth, Color(0.92, 0.84, 0.64, (0.45 + illumination * 0.35) * opacity), 1.5)
	draw_line(start, end, Color(0.01, 0.01, 0.02, 0.75 * opacity), 1.0)
	if difference == 2:
		# Repeated diagonal marks distinguish an impassable cliff from a small step.
		for offset in range(3, int(size) - 3, 6):
			var point = start + tangent * offset
			draw_line(point - normal, point + tangent * 3 - normal * (depth - 1), Color(0.79, 0.56, 0.31, 0.70 * opacity), 1.5)
	else:
		# A short set of stair treads marks a traversable slope.
		for step in range(3):
			var center = start + tangent * (size * 0.5) - normal * (step + 1)
			draw_line(center - tangent * (4 - step), center + tangent * (4 - step), Color(0.9, 0.82, 0.63, opacity), 1)

func _draw_lower_approach(edge: Vector2, tangent: Vector2, normal: Vector2, difference: int, opacity: float, size: float):
	# All offsets are positive along the outward normal: these marks belong
	# to the LOWER neighboring cell, rather than the high tile's cliff face.
	var center = edge + tangent * (size * 0.5)
	if difference == 1:
		var near_center = center + normal * 2.0
		var far_center = center + normal * (size - 3.0)
		draw_polygon(
			PackedVector2Array([near_center - tangent * 6, near_center + tangent * 6, far_center + tangent * 12, far_center - tangent * 12]),
			PackedColorArray([Color(0.92, 0.77, 0.43, 0.30 * opacity), Color(0.92, 0.77, 0.43, 0.30 * opacity), Color(0.55, 0.63, 0.45, 0.02 * opacity), Color(0.55, 0.63, 0.45, 0.02 * opacity)])
		)
		# Widening contour lines lead the eye from the low floor up to the rim.
		for i in range(3):
			var distance = 7.0 + i * 8.0
			var half_width = 5.0 + i * 2.0
			var point = center + normal * distance
			var alpha = (0.32 - i * 0.07) * opacity
			draw_line(point - tangent * half_width + normal, point + tangent * half_width + normal, Color(0.03, 0.05, 0.04, alpha), 2)
			draw_line(point - tangent * half_width, point + tangent * half_width, Color(0.93, 0.85, 0.63, alpha), 1)
		# Small uphill chevron, pointing back toward the higher neighboring cell.
		var tip = center + normal * 12
		draw_polyline(PackedVector2Array([tip + normal * 4 - tangent * 3, tip, tip + normal * 4 + tangent * 3]), Color(0.88, 0.83, 0.65, 0.40 * opacity), 1.5)
	else:
		# A two-level edge stays visibly sheer; no climbable slope is suggested.
		for i in range(4):
			var point = edge + tangent * (5 + i * 7) + normal * 5
			draw_line(point, point + tangent * 2 + normal * 3, Color(0.88, 0.49, 0.25, 0.55 * opacity), 1.5)

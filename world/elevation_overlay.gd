extends Node2D

var main

func _draw():
	if not is_instance_valid(main) or main._is_on_world_map: return
	var size = float(MapDefinitions.TILE_SIZE)
	var ledges: Array = []
	var grass_tiles: Array = []
	for x in range(main._map_data.size()):
		for y in range(main._map_data[x].size()):
			if not main._explored_tiles[x][y] or not ElevationMap.is_land(main._map_data[x][y]): continue
			var pos = Vector2i(x, y)
			var height = main.get_tile_height(pos)
			var opacity = 1.0 if main._visible_tiles[x][y] else 0.35
			var origin = Vector2(pos) * size
			if main._map_data[x][y] == MapDefinitions.CellType.GRASS:
				# Replace the flat grass glyph with a tuft rooted in this surface.
				# Opaque ground also removes the old glyph in remembered tiles.
				draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.02, 0.05, 0.025).darkened(1.0 - opacity))
				grass_tiles.append([origin, height, opacity])
			if height == ElevationMap.LOW:
				draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.03, 0.12, 0.28, 0.48 * opacity))
			elif height == ElevationMap.HIGH:
				draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.95, 0.78, 0.40, 0.30 * opacity))
			# Small height arrows avoid covering the central terrain/item glyph.
			if height != ElevationMap.NORMAL:
				var center = origin + Vector2(26, 6)
				var direction = -1 if height == ElevationMap.HIGH else 1
				var points = PackedVector2Array([center + Vector2(-3, -2 * direction), center + Vector2(3, -2 * direction), center + Vector2(0, 2 * direction)])
				draw_colored_polygon(points, Color(1.0, 0.86, 0.50, opacity) if height == ElevationMap.HIGH else Color(0.50, 0.80, 1.0, opacity))
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
	# Draw vegetation over terrain shading, with the roots sharing its elevation.
	for grass in grass_tiles:
		_draw_grounded_grass(grass[0], grass[1], grass[2])

func _draw_grounded_grass(origin: Vector2, height: int, opacity: float):
	var root = origin + Vector2(16, 19 + (1 - height) * 3)
	var shadow = PackedVector2Array()
	for i in range(12):
		var angle = TAU * i / 12.0
		shadow.append(root + Vector2(cos(angle) * 8.0, sin(angle) * 2.5 + 1.5))
	draw_colored_polygon(shadow, Color(0.01, 0.025, 0.015, 0.8 * opacity))
	var ground_color = Color(0.58, 0.57, 0.27, 0.65 * opacity) if height == ElevationMap.HIGH else Color(0.20, 0.38, 0.32, 0.65 * opacity)
	draw_line(root + Vector2(-6, 1), root + Vector2(6, 1), ground_color, 1.5)
	var leaf = Color(0.53, 0.88, 0.30, opacity) if height == ElevationMap.HIGH else Color(0.26, 0.63, 0.43, opacity)
	if height == ElevationMap.NORMAL: leaf = Color(0.35, 0.80, 0.38, opacity)
	for blade in [[Vector2(-3, 0), Vector2(-7, -7)], [Vector2.ZERO, Vector2(-1, -10)], [Vector2(3, 0), Vector2(7, -8)]]:
		draw_line(root + blade[0] + Vector2(1, 1), root + blade[1] + Vector2(1, 1), Color(0.01, 0.04, 0.02, opacity), 3)
		draw_line(root + blade[0], root + blade[1], leaf, 2)

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
	var depth = 4.0 if difference == 1 else 7.0
	var fade_width = size
	# Soft shadow on the lower side and a warm rim fading into the upper surface.
	_draw_gradient_band(start, end, normal * fade_width,
		Color(0.02, 0.04, 0.09, (0.48 if difference == 1 else 0.65) * opacity),
		Color(0.02, 0.04, 0.09, 0.0))
	_draw_lower_approach(start, tangent, normal, difference, opacity, size)
	_draw_gradient_band(start - normal * depth, end - normal * depth, -normal * (fade_width - depth),
		Color(1.0, 0.85, 0.54, 0.42 * opacity), Color(1.0, 0.85, 0.54, 0.0))
	# Draw the vertical cliff face inside the high tile, keeping actor grids aligned.
	_draw_gradient_band(start, end, -normal * depth,
		Color(0.08, 0.06, 0.04, 0.85 * opacity), Color(0.40, 0.31, 0.19, 0.42 * opacity))
	draw_line(start - normal * depth, end - normal * depth, Color(1.0, 0.84, 0.49, 0.55 * opacity), 1.0)
	draw_line(start, end, Color(0.01, 0.01, 0.02, 0.55 * opacity), 1.0)
	if difference == 2:
		# Repeated diagonal marks distinguish an impassable cliff from a small step.
		for offset in range(3, int(size) - 3, 6):
			var point = start + tangent * offset
			draw_line(point - normal, point + tangent * 3 - normal * (depth - 1), Color(0.95, 0.49, 0.20, opacity), 1.5)
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
			var alpha = (0.65 - i * 0.14) * opacity
			draw_line(point - tangent * half_width + normal, point + tangent * half_width + normal, Color(0.03, 0.05, 0.04, alpha), 2)
			draw_line(point - tangent * half_width, point + tangent * half_width, Color(0.93, 0.85, 0.63, alpha), 1)
		# Small uphill chevron, pointing back toward the higher neighboring cell.
		var tip = center + normal * 12
		draw_polyline(PackedVector2Array([tip + normal * 4 - tangent * 3, tip, tip + normal * 4 + tangent * 3]), Color(1.0, 0.9, 0.63, 0.7 * opacity), 1.5)
	else:
		# A two-level edge stays visibly sheer; no climbable slope is suggested.
		for i in range(4):
			var point = edge + tangent * (5 + i * 7) + normal * 5
			draw_line(point, point + tangent * 2 + normal * 3, Color(0.88, 0.49, 0.25, 0.55 * opacity), 1.5)

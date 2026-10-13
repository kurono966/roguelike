class_name TilesetManager
extends Node

var main_node: Node2D
var tile_map: TileMap

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

const FLOOR_BASE = Color(0.78, 0.76, 0.70, 1.0)
const FLOOR_GROUT = Color(0.68, 0.66, 0.61, 1.0)
const WALL_DARK = Color(0.16, 0.16, 0.17, 1.0)
const WALL_BASE = Color(0.34, 0.34, 0.36, 1.0)
const WALL_HIGHLIGHT = Color(0.53, 0.52, 0.50, 1.0)

# Water animation state
var _combined_image: Image = null
var _atlas_source: TileSetAtlasSource = null
var _water_anim_time: float = 0.0
var _water_update_timer: float = 0.0
const WATER_UPDATE_INTERVAL: float = 0.25 # Update every 250ms

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map

func _process(delta):
	if _combined_image == null or _atlas_source == null:
		return
	_water_update_timer += delta
	if _water_update_timer >= WATER_UPDATE_INTERVAL:
		_water_update_timer = 0.0
		_water_anim_time += WATER_UPDATE_INTERVAL
		_animate_water()

func _animate_water():
	var time_sec = _water_anim_time
	
	# ASCII tilde ~ glyph bitmap (7 rows x 5 cols)
	var wave_bitmap = [
		".....",
		".#.#.",
		"#.#.#",
		".....",
		".#.#.",
		"#.#.#",
		"....."
	]
	
	# Calculate animation offset (horizontal wave movement)
	var x_offset = int(time_sec * 8.0) % 64  # ~8 pixels/sec scroll
	
	# Water colors
	var bg_water = Color(0.02, 0.04, 0.08, 1.0)  # Dark blue background
	var base_water = Color(0.35, 0.62, 0.95, 1.0)  # ASCII ~ foreground color
	
	# Glyph drawing parameters (matching _draw_ascii_char)
	var scale = 4
	var origin = Vector2i(6, 2)
	
	# Regenerate each of the 16 water tiles with ASCII-style animated waves
	for mask in range(16):
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var center = Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
				var radius = TILE_SIZE/2.0
				var pos = Vector2(x + 0.5, y + 0.5)
				var dist = pos.distance_to(center)
				var in_shape = false
				
				if dist <= radius: in_shape = true
				
				if (mask & 1) and y < center.y and abs(x - center.x) < radius: in_shape = true
				if (mask & 2) and x >= center.x and abs(y - center.y) < radius: in_shape = true
				if (mask & 4) and y >= center.y and abs(x - center.x) < radius: in_shape = true
				if (mask & 8) and x < center.x and abs(y - center.y) < radius: in_shape = true
				
				if in_shape:
					# Determine if this pixel is part of the ~ glyph
					# Map pixel to glyph bitmap coordinates with horizontal scroll
					var gx = (x - origin.x) / scale
					var gy = (y - origin.y) / scale
					
					# Apply horizontal scroll animation to glyph x
					var scroll_offset = int(floor(time_sec * 4.0)) % 5
					gx = (gx - scroll_offset + 5) % 5
					
					var is_char_pixel = false
					if gy >= 0 and gy < wave_bitmap.size():
						var row = wave_bitmap[gy]
						if gx >= 0 and gx < row.length():
							is_char_pixel = row.substr(gx, 1) == "#"
					
					var c: Color
					if is_char_pixel:
						# ASCII wave character with shimmer effect
						# Time-based brightness variation for shimmer
						var shimmer = sin(float(x) * 0.3 + float(y) * 0.2 + time_sec * 3.0) * 0.08
						# Per-pixel noise for subtle texture variation
						var noise_seed = mask * 100 + int(time_sec * 2.0)
						var noise_val = _hash_noise(x, y, noise_seed)
						var noise_shade = (noise_val - 0.5) * 0.06
						
						var shade = shimmer + noise_shade
						c = base_water.lightened(max(shade, 0.0)).darkened(max(-shade, 0.0))
					else:
						# Background water with subtle shimmer
						var bg_shimmer = sin(float(x) * 0.5 + float(y) * 0.3 + time_sec * 2.0) * 0.03
						c = bg_water.lightened(max(bg_shimmer, 0.0)).darkened(max(-bg_shimmer, 0.0))
					
					# Calculate pixel position in the combined image
					var px = (18 + mask) * TILE_SIZE + x
					var py = y
					_combined_image.set_pixel(px, py, c)
	
	# Animate crystal tiles (indices 43 and 46..61) with magical sparkling & pulse
	_animate_crystals(time_sec)
	
	# Update the texture with the modified combined image
	_atlas_source.texture = ImageTexture.create_from_image(_combined_image)

func _animate_crystals(time_sec: float):
	var crystal_glyph = [
		"#...#",
		".#.#.",
		"..#..",
		"#####",
		"..#..",
		".#.#.",
		"#...#"
	]
	var scale = 4
	var origin = Vector2i(6, 2)
	
	# Pulse brightness between cyan, pure white, and azure
	var pulse = (sin(time_sec * 5.0) + 1.0) * 0.5 # 0.0 ~ 1.0 fast pulse
	var base_bg = Color(0.03, 0.05, 0.12, 1.0)
	var glow_intensity = 0.04 + pulse * 0.14
	
	# Primary crystal foreground color shifting from cyan-blue to shining bright diamond white
	var crystal_fg = Color(0.45, 0.85, 1.0, 1.0).lerp(Color(1.0, 1.0, 1.2, 1.0), pulse * 0.85)
	
	# Tile indices to update: 43 (single tile) and 46..61 (autotiles)
	var target_indices = [43]
	for m in range(16):
		target_indices.append(46 + m)
		
	for idx in target_indices:
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var px = idx * TILE_SIZE + x
				var py = y
				
				# Subtle sparkling background
				var bg_sparkle = sin(float(x * 3 + y * 5) + time_sec * 6.0) * 0.04
				var bg_c = base_bg.lightened(max(0.0, bg_sparkle + pulse * 0.06))
				
				# Soft radial glow around crystal center
				var dist_center = Vector2(x - TILE_SIZE/2.0, y - TILE_SIZE/2.0).length()
				if dist_center < TILE_SIZE/2.0:
					var g_alpha = glow_intensity * (1.0 - dist_center / (TILE_SIZE/2.0))
					bg_c = bg_c.lerp(Color(0.4, 0.8, 1.0, 1.0), g_alpha)
					
				# Glyph pixel check
				var gx = (x - origin.x) / scale
				var gy = (y - origin.y) / scale
				var is_glyph = false
				if gy >= 0 and gy < crystal_glyph.size() and gx >= 0 and gx < crystal_glyph[gy].length():
					is_glyph = crystal_glyph[gy].substr(gx, 1) == "#"
					
				if is_glyph:
					var dy = y % scale
					var final_c = crystal_fg
					if dy == 0:
						final_c = final_c.lightened(0.3) # 3D top shine
					elif dy == scale - 1:
						final_c = final_c.darkened(0.2)
					_combined_image.set_pixel(px, py, final_c)
				else:
					_combined_image.set_pixel(px, py, bg_c)


func create_tileset():
	var tileset = TileSet.new()
	var source = TileSetAtlasSource.new()
	tile_map.tile_set = tileset
	
	tileset.add_occlusion_layer(0) # Index 0
	# ShadowManager owns occlusion, so TileMap must not render duplicate shadows.
	tileset.set_occlusion_layer_light_mask(0, 0)
	
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	# Generate 16 bitmask variations for walls
	var wall_variations = []
	var wall_occluders = []
	
	# Pre-define floor color for blending
	var floor_color = FLOOR_BASE
	var floor_image = _make_floor_tile(16)
	
	for mask in range(16):
		var img = _make_wall_tile(mask, floor_image)
		
		wall_variations.append(img)
		
		# Generate Tighter Occluder (0..32 coordinate space)
		var poly = PackedVector2Array()
		var s = float(TILE_SIZE) # 32
		var c = s / 2.0 # 16
		var r_diag = 11.0 # approx 16 * 0.707
		
		# Construct polygon clockwise starting from Top-Center
		poly.append(Vector2(c, 0))
		
		# Top-Right Corner Handling
		if (mask & 1) or (mask & 2):
			poly.append(Vector2(s, 0))
		else:
			poly.append(Vector2(c + r_diag, c - r_diag))
			
		poly.append(Vector2(s, c))
		
		# Bottom-Right Corner
		if (mask & 4) or (mask & 2):
			poly.append(Vector2(s, s))
		else:
			poly.append(Vector2(c + r_diag, c + r_diag))
			
		poly.append(Vector2(c, s))
		
		# Bottom-Left Corner
		if (mask & 4) or (mask & 8):
			poly.append(Vector2(0, s))
		else:
			poly.append(Vector2(c - r_diag, c + r_diag))
			
		poly.append(Vector2(0, c))
		
		# Top-Left Corner
		if (mask & 1) or (mask & 8):
			poly.append(Vector2(0, 0))
		else:
			poly.append(Vector2(c - r_diag, c - r_diag))
			
		var occluder = OccluderPolygon2D.new()
		occluder.polygon = poly
		wall_occluders.append(occluder)
	
	# Generate 16 bitmask variations for water (initial static version)
	var water_variations = []
	for mask in range(16):
		var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(floor_color)
		
		var center = Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		var radius = TILE_SIZE/2.0
		
		var rng = RandomNumberGenerator.new()
		rng.seed = mask * 9876 + 1
		
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var pos = Vector2(x + 0.5, y + 0.5)
				var dist = pos.distance_to(center)
				var in_shape = false
				
				if dist <= radius: in_shape = true
				
				if (mask & 1) and y < center.y and abs(x - center.x) < radius: in_shape = true
				if (mask & 2) and x >= center.x and abs(y - center.y) < radius: in_shape = true
				if (mask & 4) and y >= center.y and abs(x - center.x) < radius: in_shape = true
				if (mask & 8) and x < center.x and abs(y - center.y) < radius: in_shape = true
				
				if in_shape:
					var base_water = Color(0.2, 0.4, 0.8, 1.0)
					var variance = rng.randf_range(-0.05, 0.05)
					img.set_pixel(x, y, base_water.lightened(variance))
		
		water_variations.append(img)
	
	var stairs_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	stairs_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_stairs(stairs_image, Color(0.84, 0.70, 0.24, 1.0), Color(0.30, 0.22, 0.08, 1.0))
	
	var stairs_blue_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	stairs_blue_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_stairs(stairs_blue_image, Color(0.28, 0.47, 0.90, 1.0), Color(0.08, 0.13, 0.32, 1.0))
	
	var grass_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	grass_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_grass_overlay(grass_image)

	# Generate DOOR_CLOSED tile (dark brown vertical bar)
	var door_closed_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	door_closed_image.fill(floor_color)
	var door_frame_color = Color(0.45, 0.28, 0.10, 1.0) # Dark wood frame
	var door_panel_color = Color(0.60, 0.38, 0.15, 1.0) # Lighter wood panel
	var door_knob_color  = Color(0.85, 0.70, 0.20, 1.0) # Gold knob
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			# Outer frame (2px border)
			if x < 2 or x >= TILE_SIZE - 2 or y < 2 or y >= TILE_SIZE - 2:
				door_closed_image.set_pixel(x, y, door_frame_color)
			# Vertical center divider
			elif x >= TILE_SIZE/2 - 1 and x <= TILE_SIZE/2 + 1:
				door_closed_image.set_pixel(x, y, door_frame_color)
			# Horizontal center rail
			elif y >= TILE_SIZE/2 - 1 and y <= TILE_SIZE/2 + 1:
				door_closed_image.set_pixel(x, y, door_frame_color)
			# Panel fill
			else:
				door_closed_image.set_pixel(x, y, door_panel_color)
	# Knob (small dot, right-center area)
	var dkx = TILE_SIZE * 3 / 4
	var dky = TILE_SIZE / 2
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dkx+dx >= 0 and dkx+dx < TILE_SIZE and dky+dy >= 0 and dky+dy < TILE_SIZE:
				door_closed_image.set_pixel(dkx+dx, dky+dy, door_knob_color)

	# Generate DOOR_OPEN tile (open doorway, arch look)
	var door_open_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	door_open_image.fill(floor_color)
	var arch_color = Color(0.45, 0.28, 0.10, 1.0)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			# Left edge post
			if x < 3:
				door_open_image.set_pixel(x, y, arch_color)
			# Right edge post
			elif x >= TILE_SIZE - 3:
				door_open_image.set_pixel(x, y, arch_color)
			# Top lintel
			elif y < 3:
				door_open_image.set_pixel(x, y, arch_color)
			# Floor
			else:
				door_open_image.set_pixel(x, y, floor_color)

	# Generate DOOR_LOCKED tile (closed door, blue-purple color variant of normal door)
	var door_locked_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	door_locked_image.fill(floor_color)
	var locked_frame_color = Color(0.20, 0.15, 0.40, 1.0) # Deep purple frame
	var locked_panel_color = Color(0.35, 0.28, 0.62, 1.0) # Blue-purple panel
	var locked_knob_color  = Color(0.80, 0.85, 0.90, 1.0) # Silver knob (locked)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			# Outer frame (2px border)
			if x < 2 or x >= TILE_SIZE - 2 or y < 2 or y >= TILE_SIZE - 2:
				door_locked_image.set_pixel(x, y, locked_frame_color)
			# Vertical center divider
			elif x >= TILE_SIZE/2 - 1 and x <= TILE_SIZE/2 + 1:
				door_locked_image.set_pixel(x, y, locked_frame_color)
			# Horizontal center rail
			elif y >= TILE_SIZE/2 - 1 and y <= TILE_SIZE/2 + 1:
				door_locked_image.set_pixel(x, y, locked_frame_color)
			# Panel fill
			else:
				door_locked_image.set_pixel(x, y, locked_panel_color)
	# Knob (small dot, right-center area)
	var lkx = TILE_SIZE * 3 / 4  # Locked door knob X
	var lky = TILE_SIZE / 2     # Locked door knob Y
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if lkx+dx >= 0 and lkx+dx < TILE_SIZE and lky+dy >= 0 and lky+dy < TILE_SIZE:
				door_locked_image.set_pixel(lkx+dx, lky+dy, locked_knob_color)

	# Generate ICE tile (frozen water)
	var ice_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	ice_image.fill(floor_color)
	var ice_color = Color(0.8, 0.9, 1.0, 1.0) # Light blue ice
	var ice_crack_color = Color(0.6, 0.75, 0.9, 1.0) # Slightly darker for cracks
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			# Create ice pattern with subtle cracks
			var noise = (x * 7 + y * 13) % 23 / 23.0
			if noise > 0.7:
				ice_image.set_pixel(x, y, ice_crack_color)
			else:
				ice_image.set_pixel(x, y, ice_color)

	var lava_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	lava_image.fill(Color(0.12, 0.04, 0.03, 1.0))
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var heat = sin(float(x + y) * 0.45) + sin(float(x * 2 - y) * 0.25)
			if heat > 0.45:
				lava_image.set_pixel(x, y, Color(1.0, 0.35, 0.05, 1.0))
			elif heat > -0.1:
				lava_image.set_pixel(x, y, Color(0.65, 0.12, 0.02, 1.0))

	var ash_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# Paved cobblestone road design (dark grout border, 3D shaded bricks)
	ash_image.fill(Color(0.18, 0.14, 0.12, 1.0)) # Dark brown grout base
	
	var ash_rng = RandomNumberGenerator.new()
	ash_rng.seed = 404
	
	# Create a cobblestone grid pattern of bricks (horizontal bricks of size 16x8, offset every row)
	for y in range(TILE_SIZE):
		var row = y / 8
		var offset = 8 if (row % 2 == 1) else 0
		for x in range(TILE_SIZE):
			var col = (x + offset) % TILE_SIZE
			var local_x = col % 16
			var local_y = y % 8
			
			# Keep grout lines
			if local_x == 0 or local_y == 0 or local_x == 15 or local_y == 7:
				continue
				
			# Stone base color
			var base_c = Color(0.55, 0.38, 0.28, 1.0) # Warm brown cobblestone
			var tint = ash_rng.randf_range(-0.05, 0.05)
			var grain = _hash_noise(x, y, 404) * 0.10 - 0.05
			var highlight = 0.0
			
			# 3D Highlight & Shadow
			if local_x <= 2 or local_y <= 2:
				highlight = 0.14 # Top-left highlight
			elif local_x >= 13 or local_y >= 5:
				highlight = -0.14 # Bottom-right shadow
				
			var shade = tint + grain + highlight
			var final_c = base_c.lightened(max(shade, 0.0)).darkened(max(-shade, 0.0))
			ash_image.set_pixel(x, y, final_c)

	var volcanic_ash_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# Volcanic ash - darker, reddish-gray cobblestone
	volcanic_ash_image.fill(Color(0.15, 0.12, 0.10, 1.0)) # Darker reddish-gray grout base
	
	var volcanic_ash_rng = RandomNumberGenerator.new()
	volcanic_ash_rng.seed = 505
	
	# Create a cobblestone grid pattern of bricks (horizontal bricks of size 16x8, offset every row)
	for y in range(TILE_SIZE):
		var row = y / 8
		var offset = 8 if (row % 2 == 1) else 0
		for x in range(TILE_SIZE):
			var col = (x + offset) % TILE_SIZE
			var local_x = col % 16
			var local_y = y % 8
			
			# Keep grout lines
			if local_x == 0 or local_y == 0 or local_x == 15 or local_y == 7:
				continue
				
			# Stone base color - darker, more reddish
			var base_c = Color(0.45, 0.32, 0.25, 1.0) # Darker reddish-brown cobblestone
			var tint = volcanic_ash_rng.randf_range(-0.05, 0.05)
			var grain = _hash_noise(x, y, 505) * 0.10 - 0.05
			var highlight = 0.0
			
			# 3D Highlight & Shadow
			if local_x <= 2 or local_y <= 2:
				highlight = 0.12 # Top-left highlight
			elif local_x >= 13 or local_y >= 5:
				highlight = -0.12 # Bottom-right shadow
				
			var shade = tint + grain + highlight
			var final_c = base_c.lightened(max(shade, 0.0)).darkened(max(-shade, 0.0))
			volcanic_ash_image.set_pixel(x, y, final_c)

	var crystal_floor_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	crystal_floor_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_crystal_floor_overlay(crystal_floor_image)
	
	var crystal_variations = []
	for mask in range(16):
		crystal_variations.append(_make_crystal_floor_tile(mask, floor_image))

	var stairs_red_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	stairs_red_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_stairs(stairs_red_image, Color(0.86, 0.22, 0.08, 1.0), Color(0.34, 0.06, 0.03, 1.0))

	var stairs_purple_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	stairs_purple_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_stairs(stairs_purple_image, Color(0.58, 0.34, 0.92, 1.0), Color(0.18, 0.08, 0.32, 1.0))

	# Combine all images (83 standard tiles + 7 ASCII world tiles = 90 total)
	var combined_image = Image.create(TILE_SIZE * 90, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Blit Walls
	for i in range(16):
		combined_image.blit_rect(wall_variations[i], Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(i * TILE_SIZE, 0))
	
	# Blit Floor & Stairs
	combined_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(16 * TILE_SIZE, 0))
	combined_image.blit_rect(stairs_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(17 * TILE_SIZE, 0))
	
	# Blit Water
	for i in range(16):
		combined_image.blit_rect(water_variations[i], Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i((18 + i) * TILE_SIZE, 0))
	
	# Blit Grass
	combined_image.blit_rect(grass_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(34 * TILE_SIZE, 0))
	
	# Blit Stairs Blue
	combined_image.blit_rect(stairs_blue_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(35 * TILE_SIZE, 0))
	
	# Blit Door Closed (36), Door Open (37), Door Locked (38)
	combined_image.blit_rect(door_closed_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(36 * TILE_SIZE, 0))
	combined_image.blit_rect(door_open_image,   Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(37 * TILE_SIZE, 0))
	combined_image.blit_rect(door_locked_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(38 * TILE_SIZE, 0))
	
	# Blit Ice (39)
	combined_image.blit_rect(ice_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(39 * TILE_SIZE, 0))
	combined_image.blit_rect(lava_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(40 * TILE_SIZE, 0))
	combined_image.blit_rect(ash_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(41 * TILE_SIZE, 0))
	combined_image.blit_rect(volcanic_ash_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(42 * TILE_SIZE, 0))
	combined_image.blit_rect(crystal_floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(43 * TILE_SIZE, 0))
	combined_image.blit_rect(stairs_red_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(44 * TILE_SIZE, 0))
	combined_image.blit_rect(stairs_purple_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(45 * TILE_SIZE, 0))
	for i in range(16):
		combined_image.blit_rect(crystal_variations[i], Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i((46 + i) * TILE_SIZE, 0))
	
	# Generate 16 bitmask variations for pit (abyss with rounded corners)
	var pit_variations = []
	for mask in range(16):
		var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
		
		var center = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		var radius = TILE_SIZE / 2.0
		
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var pos = Vector2(x + 0.5, y + 0.5)
				var dist = pos.distance_to(center)
				var in_shape = false
				
				if dist <= radius: in_shape = true
				
				if (mask & 1) and y < center.y and abs(x - center.x) < radius: in_shape = true
				if (mask & 2) and x >= center.x and abs(y - center.y) < radius: in_shape = true
				if (mask & 4) and y >= center.y and abs(x - center.x) < radius: in_shape = true
				if (mask & 8) and x < center.x and abs(y - center.y) < radius: in_shape = true
				
				if in_shape:
					# Calculate factor from center for depth gradient
					var factor = clamp((radius - dist) / radius, 0.0, 1.0)
					if not dist <= radius: # inside connection bars
						factor = 0.5
					
					# Color calculation (deep black/purple abyss)
					var c = Color(0.005, 0.005, 0.01, 1.0)
					if factor > 0.8:
						c = Color(0.005, 0.005, 0.01, 1.0)
					elif factor > 0.4:
						c = Color(0.018, 0.012, 0.025, 1.0)
					else:
						# Lip of the pit
						c = Color(0.035, 0.025, 0.05, 1.0)
						
					img.set_pixel(x, y, c)
		pit_variations.append(img)

	for i in range(16):
		combined_image.blit_rect(pit_variations[i], Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i((61 + i) * TILE_SIZE, 0))
	
	# Generate STAIRS_UP tile (silver stairs leading up)
	var stairs_up_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	stairs_up_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_stairs(stairs_up_image, Color(0.9, 0.9, 0.95, 1.0), Color(0.35, 0.35, 0.4, 1.0))
	combined_image.blit_rect(stairs_up_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(77 * TILE_SIZE, 0))
	
	# Blit Custom Village Icon (78)
	var village_img = null
	if ResourceLoader.exists("res://assets/village.png"):
		var loaded_res = load("res://assets/village.png")
		if loaded_res and loaded_res.has_method("get_image"):
			village_img = loaded_res.get_image()
			village_img.resize(TILE_SIZE, TILE_SIZE)
	
	if village_img:
		var village_combined = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		village_combined.blit_rect(ash_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
		
		# Alpha blend custom village icon over the ash road background
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var px_c = village_img.get_pixel(x, y)
				if px_c.a > 0.0:
					var bg_c = village_combined.get_pixel(x, y)
					var blended_c = bg_c.lerp(px_c, px_c.a)
					village_combined.set_pixel(x, y, blended_c)
					
		combined_image.blit_rect(village_combined, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(78 * TILE_SIZE, 0))
	else:
		# Fallback to closed door if load fails
		combined_image.blit_rect(door_closed_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(78 * TILE_SIZE, 0))
	
	# Generate STAIRS_GOLD tile (gold stairs leading to beginner dungeon)
	var stairs_gold_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	stairs_gold_image.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_stairs(stairs_gold_image, Color(0.95, 0.82, 0.15, 1.0), Color(0.38, 0.28, 0.05, 1.0))
	combined_image.blit_rect(stairs_gold_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(79 * TILE_SIZE, 0))
	
	# Generate TREE (80), TREE_FRUIT (81), ROCK (82)
	var tree_image = _make_tree_tile(floor_image, false)
	var tree_fruit_image = _make_tree_tile(floor_image, true)
	var rock_image = _make_rock_tile(floor_image)
	
	combined_image.blit_rect(tree_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(80 * TILE_SIZE, 0))
	combined_image.blit_rect(tree_fruit_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(81 * TILE_SIZE, 0))
	combined_image.blit_rect(rock_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(82 * TILE_SIZE, 0))
	
	# Create and Blit ASCII World tiles (indices 83..89)
	_create_world_ascii_tiles(combined_image)
	_apply_ascii_dungeon_tiles(combined_image)
	
	# Store references for water animation
	_combined_image = combined_image
	_atlas_source = source
	
	source.texture = ImageTexture.create_from_image(combined_image)
	
	for i in range(90):
		source.create_tile(Vector2i(i, 0))
		if i < 16:
			# Assign dynamic occluder to walls only
			var tile_data = source.get_tile_data(Vector2i(i, 0), 0)
			tile_data.set_occluder(0, wall_occluders[i])
	
	# --- Add occluders to opaque non-wall tiles ---
	var s = float(TILE_SIZE)
	var c = s / 2.0
	
	# DOOR_CLOSED (36) and DOOR_LOCKED (38): tall vertical rectangle occluder
	var door_occluder = OccluderPolygon2D.new()
	door_occluder.polygon = PackedVector2Array([
		Vector2(4, 0), Vector2(s - 4, 0),
		Vector2(s - 4, s), Vector2(4, s)
	])
	for door_idx in [36, 38]:
		var td = source.get_tile_data(Vector2i(door_idx, 0), 0)
		td.set_occluder(0, door_occluder)
	
	# TREE (80) and TREE_FRUIT (81): large rounded octagon occluder
	var tree_occluder = OccluderPolygon2D.new()
	var r = c * 0.88
	var r_diag = r * 0.707
	tree_occluder.polygon = PackedVector2Array([
		Vector2(c, c - r),
		Vector2(c + r_diag, c - r_diag),
		Vector2(c + r, c),
		Vector2(c + r_diag, c + r_diag),
		Vector2(c, c + r),
		Vector2(c - r_diag, c + r_diag),
		Vector2(c - r, c),
		Vector2(c - r_diag, c - r_diag)
	])
	for tree_idx in [80, 81]:
		var td = source.get_tile_data(Vector2i(tree_idx, 0), 0)
		td.set_occluder(0, tree_occluder)
	
	# ROCK (82): medium pentagon occluder (slightly irregular for rocky look)
	var rock_occluder = OccluderPolygon2D.new()
	var rr = c * 0.72
	var rr_d = rr * 0.707
	rock_occluder.polygon = PackedVector2Array([
		Vector2(c, c - rr * 0.9),
		Vector2(c + rr, c - rr * 0.3),
		Vector2(c + rr_d, c + rr_d),
		Vector2(c - rr_d, c + rr_d),
		Vector2(c - rr, c - rr * 0.3)
	])
	var rock_td = source.get_tile_data(Vector2i(82, 0), 0)
	rock_td.set_occluder(0, rock_occluder)

	tileset.add_source(source, 0)
	
	var debug_image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	debug_image.fill(Color(1, 0, 0, 0.5))
	var debug_source = TileSetAtlasSource.new()
	debug_source.texture = ImageTexture.create_from_image(debug_image)
	debug_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	debug_source.create_tile(Vector2i(0,0))
	tileset.add_source(debug_source, 1)

func _make_floor_tile(seed_value: int) -> Image:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(FLOOR_BASE)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Simulate a directional light from top-left
	var light_dir = Vector2(-0.5, -0.7).normalized()
	
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var tile_x = int(x / 8)
			var tile_y = int(y / 8)
			var local_x = x % 8
			var local_y = y % 8
			var checker = float((tile_x + tile_y) % 2) * 0.035
			var grain = _hash_noise(x, y, seed_value) * 0.11 - 0.055
			
			# Directional light contribution based on position within tile
			var light_dot = Vector2(local_x - 3.5, local_y - 3.5).normalized().dot(light_dir)
			var directional_light = clamp(light_dot * 0.06, -0.03, 0.06)
			
			var shade = checker + grain + directional_light
			var c = FLOOR_BASE.lightened(max(shade, 0.0)).darkened(max(-shade, 0.0))
			
			if local_x == 0 or local_y == 0:
				c = FLOOR_GROUT
			elif local_x == 1 or local_y == 1:
				c = c.darkened(0.04)
			elif local_x == 7 or local_y == 7:
				c = c.lightened(0.03)
			
			img.set_pixel(x, y, c)
	
	# Add subtle specular highlights (random bright spots)
	for i in range(26):
		var px = rng.randi_range(2, TILE_SIZE - 3)
		var py = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(px, py, img.get_pixel(px, py).lightened(rng.randf_range(0.12, 0.24)))
	
	# Add subtle vignette effect (darker at edges)
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var edge_dist = min(min(x, TILE_SIZE - 1 - x), min(y, TILE_SIZE - 1 - y))
			if edge_dist < 2:
				var vignette = (2.0 - float(edge_dist)) * 0.03
				var c = img.get_pixel(x, y)
				img.set_pixel(x, y, c.darkened(vignette))
	
	return img

func _make_wall_tile(mask: int, floor_image: Image) -> Image:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	var center = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var radius = TILE_SIZE / 2.0
	
	# Directional light from top-left for dramatic 3D effect
	var light_dir = Vector2(-0.4, -0.8).normalized()
	
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			if not _is_connected_blob_pixel(mask, x, y, center, radius):
				continue
			
			var brick_y = int(y / 8)
			var offset = 4 if brick_y % 2 == 1 else 0
			var brick_x = int((x + offset) / 10)
			var local_x = (x + offset) % 10
			var local_y = y % 8
			var grain = _hash_noise(x, y, mask + 31) * 0.16 - 0.08
			var block_tint = _hash_noise(brick_x, brick_y, mask + 71) * 0.10 - 0.05
			var vertical_light = (1.0 - float(y) / float(TILE_SIZE)) * 0.18
			var edge_shadow = 0.0
			
			if local_x == 0 or local_y == 0:
				img.set_pixel(x, y, WALL_DARK)
				continue
			if local_x == 1 or local_y == 1:
				edge_shadow = 0.15
			
			# Dramatic directional light on wall surface
			var local_pos = Vector2(local_x - 4.5, local_y - 3.5).normalized()
			var light_dot = local_pos.dot(light_dir)
			var directional_light = clamp(light_dot * 0.12, -0.06, 0.12)
			
			# Brick edge highlight (top-left edges catch light)
			var brick_edge_light = 0.0
			if local_x <= 2 and local_y <= 2:
				brick_edge_light = 0.10
			elif local_x <= 2:
				brick_edge_light = 0.05
			elif local_y <= 2:
				brick_edge_light = 0.05
			
			var c = WALL_BASE.lightened(max(grain + block_tint + vertical_light + directional_light + brick_edge_light, 0.0)).darkened(max(-(grain + block_tint + directional_light) + edge_shadow, 0.0))
			if x < 2 or y < 2:
				c = c.lightened(0.15)
			if x >= TILE_SIZE - 2 or y >= TILE_SIZE - 2:
				c = c.darkened(0.20)
			img.set_pixel(x, y, c)
	
	_draw_wall_rim(img, mask)
	return img

func _make_crystal_floor_tile(mask: int, floor_image: Image) -> Image:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	var center = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var radius = TILE_SIZE / 2.0
	
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			if not _is_connected_blob_pixel(mask, x, y, center, radius):
				continue
			
			var edge_distance = min(min(x, TILE_SIZE - 1 - x), min(y, TILE_SIZE - 1 - y))
			var connected_edge = ((mask & 1) and y < 3) or ((mask & 2) and x >= TILE_SIZE - 3) or ((mask & 4) and y >= TILE_SIZE - 3) or ((mask & 8) and x < 3)
			var shimmer = _hash_noise(x, y, 505 + mask * 13) * 0.12
			var base = Color(0.25, 0.18, 0.38, 1.0).lightened(shimmer)
			var old = img.get_pixel(x, y)
			var blend = 0.86
			if edge_distance < 3 and not connected_edge:
				blend = 0.50 + float(edge_distance) * 0.12
			img.set_pixel(x, y, old.lerp(base, blend))
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 505 + mask * 97
	for i in range(16):
		var cx = rng.randi_range(4, TILE_SIZE - 5)
		var cy = rng.randi_range(4, TILE_SIZE - 5)
		if not _is_connected_blob_pixel(mask, cx, cy, center, radius - 2.0):
			continue
		var c = Color(0.55, 0.35, 0.95, 1.0).lightened(rng.randf_range(-0.08, 0.20))
		img.set_pixel(cx, cy, c)
		img.set_pixel(min(cx + 1, TILE_SIZE - 1), cy, c.lightened(0.16))
		img.set_pixel(cx, max(cy - 1, 0), c.lightened(0.22))
	
	return img

func _is_connected_blob_pixel(mask: int, x: int, y: int, center: Vector2, radius: float) -> bool:
	var pos = Vector2(x + 0.5, y + 0.5)
	if pos.distance_to(center) <= radius:
		return true
	if (mask & 1) and y < center.y and abs(x - center.x) < radius:
		return true
	if (mask & 2) and x >= center.x and abs(y - center.y) < radius:
		return true
	if (mask & 4) and y >= center.y and abs(x - center.x) < radius:
		return true
	if (mask & 8) and x < center.x and abs(y - center.y) < radius:
		return true
	return false

func _draw_wall_rim(img: Image, mask: int) -> void:
	for i in range(TILE_SIZE):
		if (mask & 1) == 0:
			img.set_pixel(i, 0, WALL_HIGHLIGHT)
		if (mask & 4) == 0:
			img.set_pixel(i, TILE_SIZE - 1, WALL_DARK)
		if (mask & 8) == 0:
			img.set_pixel(0, i, WALL_HIGHLIGHT.darkened(0.15))
		if (mask & 2) == 0:
			img.set_pixel(TILE_SIZE - 1, i, WALL_DARK)

func _draw_stairs(img: Image, accent: Color, shadow: Color) -> void:
	for step in range(5):
		var y = 7 + step * 4
		var x0 = 6 - step
		var x1 = TILE_SIZE - 6 + step
		for x in range(max(1, x0), min(TILE_SIZE - 1, x1)):
			img.set_pixel(x, y, shadow)
			if y + 1 < TILE_SIZE:
				img.set_pixel(x, y + 1, accent)
	for y in range(8, 27):
		img.set_pixel(8, y, shadow.darkened(0.15))
		img.set_pixel(TILE_SIZE - 9, y, shadow.darkened(0.15))

func _draw_grass_overlay(img: Image) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 999
	
	for i in range(54):
		var x = rng.randi_range(2, TILE_SIZE - 3)
		var y = rng.randi_range(5, TILE_SIZE - 2)
		var height = rng.randi_range(3, 8)
		var lean = rng.randi_range(-2, 2)
		var base_color = Color(0.18, 0.48, 0.18, 1.0).lightened(rng.randf_range(-0.08, 0.22))
		var shadow_color = base_color.darkened(0.28)
		var tip_color = base_color.lightened(0.18)
		
		for j in range(height):
			var t = float(j) / float(max(height - 1, 1))
			var px = int(clamp(x + int(round(float(lean) * t)), 0, TILE_SIZE - 1))
			var py = int(clamp(y - j, 0, TILE_SIZE - 1))
			var c = tip_color if j >= height - 2 else base_color
			img.set_pixel(px, py, c)
			if j < height - 2 and px + 1 < TILE_SIZE and rng.randf() < 0.35:
				img.set_pixel(px + 1, py, shadow_color)
		
		if x > 0 and y < TILE_SIZE:
			img.set_pixel(x - 1, y, shadow_color)
		if x + 1 < TILE_SIZE and y < TILE_SIZE:
			img.set_pixel(x + 1, y, base_color.darkened(0.12))
	
	for i in range(22):
		var x = rng.randi_range(2, TILE_SIZE - 3)
		var y = rng.randi_range(12, TILE_SIZE - 3)
		var moss = Color(0.12, 0.34, 0.14, 1.0).lightened(rng.randf_range(0.0, 0.18))
		img.set_pixel(x, y, moss)
		img.set_pixel(min(x + 1, TILE_SIZE - 1), y, moss.darkened(0.1))
		img.set_pixel(x, min(y + 1, TILE_SIZE - 1), moss.darkened(0.18))

func _draw_crystal_floor_overlay(img: Image) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 505
	var center = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var radius = TILE_SIZE / 2.0 - 2.0
	
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var pos = Vector2(x + 0.5, y + 0.5)
			var dx = abs(pos.x - center.x)
			var dy = abs(pos.y - center.y)
			var rounded_dist = max(dx, dy) + min(dx, dy) * 0.42
			
			if rounded_dist <= radius:
				var edge = clamp((radius - rounded_dist) / 4.0, 0.0, 1.0)
				var shimmer = _hash_noise(x, y, 505) * 0.12
				var base = Color(0.24, 0.18, 0.36, 1.0).lightened(shimmer)
				var old = img.get_pixel(x, y)
				img.set_pixel(x, y, old.lerp(base, 0.35 + edge * 0.55))
			elif rounded_dist <= radius + 2.0:
				var old_edge = img.get_pixel(x, y)
				img.set_pixel(x, y, old_edge.lerp(Color(0.28, 0.22, 0.38, 1.0), 0.25))
	
	for i in range(18):
		var cx = rng.randi_range(5, TILE_SIZE - 6)
		var cy = rng.randi_range(5, TILE_SIZE - 5)
		var pos = Vector2(cx + 0.5, cy + 0.5)
		var dx = abs(pos.x - center.x)
		var dy = abs(pos.y - center.y)
		var rounded_dist = max(dx, dy) + min(dx, dy) * 0.42
		if rounded_dist > radius - 1.0:
			continue
		
		var c = Color(0.55, 0.35, 0.95, 1.0).lightened(rng.randf_range(-0.08, 0.24))
		img.set_pixel(cx, cy, c)
		img.set_pixel(min(cx + 1, TILE_SIZE - 1), cy, c.lightened(0.18))
		img.set_pixel(cx, max(cy - 1, 0), c.lightened(0.25))

func _hash_noise(x: int, y: int, seed_value: int) -> float:
	var n = int(x * 374761393 + y * 668265263 + seed_value * 1442695041)
	n = int((n ^ (n >> 13)) * 1274126177)
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0

func _make_tree_tile(floor_image: Image, with_fruit: bool) -> Image:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	_draw_grass_overlay(img)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 777
	
	# Trunk
	var trunk_color = Color(0.4, 0.25, 0.15)
	var trunk_shadow = Color(0.25, 0.15, 0.1)
	for x in range(14, 18):
		for y in range(18, 28):
			var c = trunk_shadow if x == 14 else trunk_color
			img.set_pixel(x, y, c)
			
	# Foliage
	var f_center = Vector2(16, 12)
	var f_radius = 11.0
	var leaf_color = Color(0.12, 0.50, 0.15)
	var leaf_highlight = Color(0.25, 0.70, 0.25)
	var leaf_shadow = Color(0.06, 0.35, 0.10)
	
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var pos = Vector2(x + 0.5, y + 0.5)
			var dist = pos.distance_to(f_center)
			if dist <= f_radius:
				var shade = (x - 10) + (y - 8)
				var final_c = leaf_color
				if shade < 4:
					final_c = leaf_highlight.lightened(rng.randf_range(0.0, 0.1))
				elif shade > 12:
					final_c = leaf_shadow
				else:
					final_c = leaf_color.lightened(rng.randf_range(-0.05, 0.05))
				
				if rng.randf() < 0.15:
					final_c = final_c.lightened(0.12)
				elif rng.randf() < 0.15:
					final_c = final_c.darkened(0.12)
					
				img.set_pixel(x, y, final_c)
				
	# Fruits
	if with_fruit:
		var fruit_positions = [
			Vector2i(12, 8), Vector2i(19, 9), Vector2i(15, 14), 
			Vector2i(9, 12), Vector2i(22, 12), Vector2i(16, 7)
		]
		var fruit_color = Color(0.9, 0.15, 0.15)
		var fruit_highlight = Color(1.0, 0.6, 0.6)
		for fp in fruit_positions:
			for dx in range(2):
				for dy in range(2):
					var px = fp.x + dx
					var py = fp.y + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						if Vector2(px, py).distance_to(f_center) <= f_radius:
							var c = fruit_highlight if (dx == 0 and dy == 0) else fruit_color
							img.set_pixel(px, py, c)
							
	return img

func _make_rock_tile(floor_image: Image) -> Image:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.blit_rect(floor_image, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
	
	var loaded_rock = null
	if ResourceLoader.exists("res://assets/rock.png"):
		var loaded_res = load("res://assets/rock.png")
		if loaded_res and loaded_res.has_method("get_image"):
			loaded_rock = loaded_res.get_image()
			loaded_rock.resize(TILE_SIZE, TILE_SIZE)
			
	if loaded_rock:
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var px_c = loaded_rock.get_pixel(x, y)
				if px_c.a > 0.0:
					var bg_c = img.get_pixel(x, y)
					var blended_c = bg_c.lerp(px_c, px_c.a)
					img.set_pixel(x, y, blended_c)
		return img
		
	# Fallback to procedural rock
	var rng = RandomNumberGenerator.new()
	rng.seed = 888
	
	var rock_color = Color(0.45, 0.45, 0.48)
	var rock_highlight = Color(0.65, 0.65, 0.68)
	var rock_shadow = Color(0.28, 0.28, 0.30)
	
	for x in range(4, 28):
		for y in range(6, 28):
			var edge_limit = 10.0 + rng.randf_range(-1.5, 1.5)
			var dist_adjusted = Vector2(x - 16, (y - 17) * 1.1).length()
			
			if dist_adjusted <= edge_limit:
				var shade = (x - 10) + (y - 10)
				var final_c = rock_color
				if shade < 6:
					final_c = rock_highlight
				elif shade > 18:
					final_c = rock_shadow
				else:
					final_c = rock_color.lightened(rng.randf_range(-0.05, 0.05))
					
				if (x - y) == 4 or (x + y) == 30:
					if rng.randf() < 0.7:
						final_c = rock_shadow.darkened(0.2)
						
				img.set_pixel(x, y, final_c)
				
	return img

func _draw_pixel_line(img: Image, start: Vector2i, end: Vector2i, color: Color, thickness: int = 2):
	var steps = max(abs(end.x - start.x), max(abs(end.y - start.y), 1)) * 2
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var px = int(round(lerp(float(start.x), float(end.x), t)))
		var py = int(round(lerp(float(start.y), float(end.y), t)))
		
		for dx in range(-thickness/2, (thickness+1)/2):
			for dy in range(-thickness/2, (thickness+1)/2):
				var target_x = px + dx
				var target_y = py + dy
				if target_x >= 0 and target_x < TILE_SIZE and target_y >= 0 and target_y < TILE_SIZE:
					img.set_pixel(target_x, target_y, color)

func _draw_bitmap_glyph(img: Image, bitmap: Array, fg_color: Color):
	for y in range(16):
		var row = bitmap[y]
		for x in range(16):
			if row.substr(x, 1) == "#":
				img.set_pixel(x * 2, y * 2, fg_color)
				img.set_pixel(x * 2 + 1, y * 2, fg_color)
				img.set_pixel(x * 2, y * 2 + 1, fg_color)
				img.set_pixel(x * 2 + 1, y * 2 + 1, fg_color)

func _apply_ascii_dungeon_tiles(combined_image: Image):
	var specs = {
		"wall": {"char": "#", "fg": Color(0.75, 0.75, 0.72, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"floor": {"char": ".", "fg": Color(0.48, 0.48, 0.44, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"stairs_down": {"char": ">", "fg": Color(0.95, 0.78, 0.28, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"stairs_up": {"char": "<", "fg": Color(0.88, 0.88, 0.96, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"water": {"char": "~", "fg": Color(0.35, 0.62, 0.95, 1.0), "bg": Color(0.02, 0.04, 0.08, 1.0)},
		"grass": {"char": "\"", "fg": Color(0.35, 0.80, 0.38, 1.0), "bg": Color(0.02, 0.05, 0.025, 1.0)},
		"door_closed": {"char": "+", "fg": Color(0.75, 0.48, 0.18, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"door_open": {"char": "/", "fg": Color(0.66, 0.46, 0.25, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"door_locked": {"char": "+", "fg": Color(0.55, 0.62, 1.0, 1.0), "bg": Color(0.02, 0.02, 0.025, 1.0)},
		"ice": {"char": "_", "fg": Color(0.72, 0.92, 1.0, 1.0), "bg": Color(0.02, 0.05, 0.07, 1.0)},
		"lava": {"char": "~", "fg": Color(1.0, 0.28, 0.08, 1.0), "bg": Color(0.10, 0.02, 0.01, 1.0)},
		"ash": {"char": ",", "fg": Color(0.08, 0.08, 0.10, 0.7), "bg": Color(0.60, 0.60, 0.62, 1.0)},
		"crystal": {"char": "*", "fg": Color(0.72, 0.95, 1.0, 1.0), "bg": Color(0.02, 0.03, 0.05, 1.0)},
		"pit": {"char": " ", "fg": Color(0.42, 0.50, 0.88, 1.0), "bg": Color(0.12, 0.18, 0.45, 1.0)},
		"tree": {"char": "T", "fg": Color(0.28, 0.78, 0.28, 1.0), "bg": Color(0.02, 0.04, 0.02, 1.0)},
		"tree_fruit": {"char": "Y", "fg": Color(0.65, 0.95, 0.35, 1.0), "bg": Color(0.02, 0.04, 0.02, 1.0)},
		"rock": {"char": "^", "fg": Color(0.70, 0.68, 0.66, 1.0), "bg": Color(0.025, 0.025, 0.03, 1.0)}
	}
	for i in range(16):
		_blit_ascii_tile(combined_image, i, specs["wall"])
	_blit_ascii_tile(combined_image, 16, specs["floor"])
	_blit_ascii_tile(combined_image, 17, specs["stairs_down"])
	for i in range(16):
		_blit_ascii_tile(combined_image, 18 + i, specs["water"])
	_blit_ascii_tile(combined_image, 34, specs["grass"])
	_blit_ascii_tile(combined_image, 35, specs["stairs_down"])
	_blit_ascii_tile(combined_image, 36, specs["door_closed"])
	_blit_ascii_tile(combined_image, 37, specs["door_open"])
	_blit_ascii_tile(combined_image, 38, specs["door_locked"])
	_blit_ascii_tile(combined_image, 39, specs["ice"])
	_blit_ascii_tile(combined_image, 40, specs["lava"])
	_blit_ascii_tile(combined_image, 43, specs["crystal"])
	_blit_ascii_tile(combined_image, 44, specs["stairs_down"])
	_blit_ascii_tile(combined_image, 45, specs["stairs_down"])
	for i in range(16):
		_blit_ascii_tile(combined_image, 46 + i, specs["crystal"])
	for i in range(16):
		_blit_ascii_tile(combined_image, 62 + i, specs["pit"])
	_blit_ascii_tile(combined_image, 77, specs["stairs_up"])
	_blit_ascii_tile(combined_image, 78, specs["door_closed"])
	_blit_ascii_tile(combined_image, 79, specs["stairs_down"])
	_blit_ascii_tile(combined_image, 80, specs["tree"])
	_blit_ascii_tile(combined_image, 81, specs["tree_fruit"])
	_blit_ascii_tile(combined_image, 82, specs["rock"])

func _blit_ascii_tile(combined_image: Image, index: int, spec: Dictionary):
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(spec["bg"])
	
	# Determine if this tile should have glow effect
	var add_glow = false
	var ch = str(spec.get("char", ""))
	if ch == ">" or ch == "<" or ch == "*" or ch == "~":
		add_glow = true
	if index >= 36 and index <= 38: # door tiles
		add_glow = false # doors don't glow
	if index == 40: # lava
		add_glow = true
	
	# For special tiles (stairs, crystal), create subtle ambient light effect on background
	if add_glow:
		var glow_color = Color(spec["fg"].r, spec["fg"].g, spec["fg"].b, 0.04)
		for x in range(TILE_SIZE):
			for y in range(TILE_SIZE):
				var dist_to_center = Vector2(x - TILE_SIZE/2, y - TILE_SIZE/2).length()
				if dist_to_center < TILE_SIZE/2:
					var intensity = 1.0 - dist_to_center / (TILE_SIZE/2)
					var ambient = Color(glow_color.r * intensity, glow_color.g * intensity, glow_color.b * intensity, intensity * 0.04)
					_alpha_blend_pixel(img, x, y, ambient)
	
	_draw_ascii_char(img, ch, spec["fg"], add_glow, true)
	combined_image.blit_rect(img, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(index * TILE_SIZE, 0))

func _draw_ascii_char(img: Image, ch: String, fg_color: Color, add_glow: bool = false, use_gradient: bool = true):
	var glyphs = {
		"#": ["#.#.#", "#####", ".#.#.", "#####", "#.#.#", "#####", ".#.#."],
		".": [".....", ".....", ".....", ".....", ".....", "..#..", "....."],
		">": ["#....", ".#...", "..#..", "...#.", "..#..", ".#...", "#...."],
		"<": ["....#", "...#.", "..#..", ".#...", "..#..", "...#.", "....#"],
		"~": [".....", ".#.#.", "#.#.#", ".....", ".#.#.", "#.#.#", "....."],
		"\"": [".#.#.", ".#.#.", ".....", ".....", ".....", ".....", "....."],
		"+": ["..#..", "..#..", "..#..", "#####", "..#..", "..#..", "..#.."],
		"/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
		"_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
		",": [".....", ".....", ".....", ".....", ".....", "..#..", ".#..."],
		"*": ["#...#", ".#.#.", "..#..", "#####", "..#..", ".#.#.", "#...#"],
		"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
		"Y": ["#...#", ".#.#.", "..#..", "..#..", "..#..", "..#..", "..#.."],
		"^": ["..#..", ".#.#.", "#...#", ".....", ".....", ".....", "....."],
		" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."]
	}
	var bitmap = glyphs.get(ch, glyphs["."])
	var scale = 4
	var origin = Vector2i(6, 2)
	
	# 1. Soft Drop shadow (offset +2, +2)
	var shadow_color = Color(0, 0, 0, 0.45)
	for y in range(bitmap.size()):
		for x in range(bitmap[y].length()):
			if bitmap[y].substr(x, 1) == "#":
				for dx in range(scale):
					for dy in range(scale):
						var sx = origin.x + x * scale + dx + 2
						var sy = origin.y + y * scale + dy + 2
						if sx >= 0 and sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
							_alpha_blend_pixel(img, sx, sy, shadow_color)
	
	# 2. Main character rendering with 3D bevel & gradient
	for y in range(bitmap.size()):
		for x in range(bitmap[y].length()):
			if bitmap[y].substr(x, 1) == "#":
				for dx in range(scale):
					for dy in range(scale):
						var px = origin.x + x * scale + dx
						var py = origin.y + y * scale + dy
						if px < 0 or px >= TILE_SIZE or py < 0 or py >= TILE_SIZE: continue
						
						# Top-down gradient
						var grad_factor = 1.0
						if use_gradient:
							grad_factor = 1.0 - (float(py - origin.y) / float(bitmap.size() * scale)) * 0.3
						
						var final_c = fg_color.lightened(grad_factor * 0.15).darkened((1.0 - grad_factor) * 0.1)
						
						# 3D edge bevel highlights
						if dy == 0 or (dx == 0 and dy <= 1):
							final_c = final_c.lightened(0.25)
						elif dy == scale - 1:
							final_c = final_c.darkened(0.18)
							
						img.set_pixel(px, py, final_c)
	
	# 3. Optional ambient glow effect
	if add_glow:
		var glow_color = Color(fg_color.r, fg_color.g, fg_color.b, 0.12)
		for y in range(bitmap.size()):
			for x in range(bitmap[y].length()):
				if bitmap[y].substr(x, 1) == "#":
					var cpx = origin.x + x * scale + scale / 2
					var cpy = origin.y + y * scale + scale / 2
					for gx in range(-3, 4):
						for gy in range(-3, 4):
							var dist = Vector2(gx, gy).length()
							if dist > 0 and dist <= 3.2:
								var alpha = 0.08 * (1.0 - dist / 3.5)
								var glow_c = Color(glow_color.r, glow_color.g, glow_color.b, alpha)
								var px = cpx + gx
								var py = cpy + gy
								if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
									_alpha_blend_pixel(img, px, py, glow_c)

func _alpha_blend_pixel(img: Image, x: int, y: int, fg: Color):
	if x < 0 or x >= TILE_SIZE or y < 0 or y >= TILE_SIZE:
		return
	var bg = img.get_pixel(x, y)
	var blended = Color(
		fg.r * fg.a + bg.r * (1.0 - fg.a),
		fg.g * fg.a + bg.g * (1.0 - fg.a),
		fg.b * fg.a + bg.b * (1.0 - fg.a),
		1.0
	)
	img.set_pixel(x, y, blended)

func _create_world_ascii_tiles(combined_image: Image):
	var ascii_sea = [
		"................",
		"................",
		"....##......##..",
		"..##..##..##..##",
		"##......##......",
		"................",
		"................",
		"................",
		"................",
		"................",
		"....##......##..",
		"..##..##..##..##",
		"##......##......",
		"................",
		"................",
		"................"
	]
	
	var ascii_grass = [
		"................",
		"................",
		"................",
		"................",
		"................",
		".......##.......",
		"......####......",
		"......####......",
		".......##.......",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................"
	]
	
	var ascii_forest = [
		"................",
		"................",
		"..############..",
		"..############..",
		"..##..####..##..",
		"......####......",
		"......####......",
		"......####......",
		"......####......",
		"......####......",
		"......####......",
		"......####......",
		"......####......",
		"....########....",
		"....########....",
		"................"
	]
	
	var ascii_mountain = [
		"................",
		"......####......",
		".....######.....",
		"....##....##....",
		"...##......##...",
		"..##........##..",
		".##..........##.",
		".##..........##.",
		"##............##",
		"##............##",
		"####........####",
		"####........####",
		"................",
		"................",
		"................",
		"................"
	]
	
	var ascii_village = [
		"................",
		"................",
		"####........####",
		"####........####",
		"..##........##..",
		"..##........##..",
		"...##......##...",
		"...##......##...",
		"....##....##....",
		"....##....##....",
		".....##..##.....",
		".....##..##.....",
		"......####......",
		"......####......",
		"................",
		"................"
	]
	
	var ascii_dungeon = [
		"................",
		"................",
		"############....",
		"##############..",
		"....####....##..",
		"....####.....##.",
		"....####......##",
		"....####......##",
		"....####......##",
		"....####......##",
		"....####.....##.",
		"....####....##..",
		"##############..",
		"############....",
		"................",
		"................"
	]
	
	var ascii_road = [
		"................",
		"....##....##....",
		"....##....##....",
		"....##....##....",
		"..############..",
		"..############..",
		"....##....##....",
		"....##....##....",
		"....##....##....",
		"..############..",
		"..############..",
		"....##....##....",
		"....##....##....",
		"....##....##....",
		"................",
		"................"
	]

	var bg_sea = Color(0.12, 0.22, 0.38, 1.0)
	var fg_sea = Color(0.40, 0.65, 0.90, 1.0)
	var img_sea = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_sea.fill(bg_sea)
	_draw_bitmap_glyph(img_sea, ascii_sea, fg_sea)
	combined_image.blit_rect(img_sea, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(83 * TILE_SIZE, 0))
	
	var bg_grass = Color(0.15, 0.22, 0.16, 1.0)
	var fg_grass = Color(0.50, 0.80, 0.55, 1.0)
	var img_grass = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_grass.fill(bg_grass)
	_draw_bitmap_glyph(img_grass, ascii_grass, fg_grass)
	combined_image.blit_rect(img_grass, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(84 * TILE_SIZE, 0))
	
	var bg_forest = Color(0.10, 0.20, 0.12, 1.0)
	var fg_forest = Color(0.40, 0.85, 0.48, 1.0)
	var img_forest = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_forest.fill(bg_forest)
	_draw_bitmap_glyph(img_forest, ascii_forest, fg_forest)
	combined_image.blit_rect(img_forest, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(85 * TILE_SIZE, 0))
	
	var bg_mountain = Color(0.20, 0.18, 0.20, 1.0)
	var fg_mountain = Color(0.75, 0.70, 0.68, 1.0)
	var img_mountain = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_mountain.fill(bg_mountain)
	_draw_bitmap_glyph(img_mountain, ascii_mountain, fg_mountain)
	combined_image.blit_rect(img_mountain, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(86 * TILE_SIZE, 0))
	
	var bg_village = Color(0.24, 0.22, 0.15, 1.0)
	var fg_village = Color(0.95, 0.82, 0.35, 1.0)
	var img_village = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_village.fill(bg_village)
	_draw_bitmap_glyph(img_village, ascii_village, fg_village)
	combined_image.blit_rect(img_village, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(87 * TILE_SIZE, 0))
	
	var bg_dungeon = Color(0.25, 0.10, 0.10, 1.0)
	var fg_dungeon = Color(0.95, 0.35, 0.35, 1.0)
	var img_dungeon = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_dungeon.fill(bg_dungeon)
	_draw_bitmap_glyph(img_dungeon, ascii_dungeon, fg_dungeon)
	combined_image.blit_rect(img_dungeon, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(88 * TILE_SIZE, 0))
	
	var bg_road = Color(0.18, 0.18, 0.18, 1.0)
	var fg_road = Color(0.60, 0.60, 0.65, 1.0)
	var img_road = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img_road.fill(bg_road)
	_draw_bitmap_glyph(img_road, ascii_road, fg_road)
	combined_image.blit_rect(img_road, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(89 * TILE_SIZE, 0))

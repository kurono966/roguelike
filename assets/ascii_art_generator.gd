class_name AsciiArtGenerator

# Central utility to generate rich, procedural "ASCII + Pixel Art" textures for entities
# Uses high-detail glyph bitmaps, shading, drop shadows, highlights, and borders.

const TILE_SIZE = 32

const GLYPHS: Dictionary = {
	"@": [ # Player / Hero (@ glyph with distinct knight/rogue helmet feel)
		"  ###  ",
		" #   # ",
		" # ### ",
		" # # # ",
		" # ### ",
		" #     ",
		"  #### "
	],
	# Lowercase enemies
	"z": [ # Zakomushi / Vermin
		" ##### ",
		"     # ",
		"    #  ",
		"   #   ",
		"  #    ",
		" #     ",
		" ##### "
	],
	"b": [ # Bat
		" #   # ",
		" #   # ",
		" ##### ",
		" # # # ",
		" ##### ",
		"  # #  ",
		"   #   "
	],
	"h": [ # Hitodama / Spirit
		"   #   ",
		"  ###  ",
		" ##### ",
		" ##### ",
		"  ###  ",
		"   #   ",
		"  # #  "
	],
	"g": [ # Goblin
		" #   # ",
		"  ###  ",
		" # # # ",
		"  ###  ",
		"   #   ",
		" ##### ",
		"  # #  "
	],
	"p": [ # Poison Mushroom
		"  ###  ",
		" ##### ",
		"#######",
		" # # # ",
		"  ###  ",
		"  ###  ",
		"  ###  "
	],
	"x": [ # Spider
		"#  #  #",
		" # # # ",
		"  ###  ",
		"#######",
		"  ###  ",
		" # # # ",
		"#  #  #"
	],
	"r": [ # Red Orc (lesser)
		" #   # ",
		"  ###  ",
		" ##### ",
		" ##### ",
		"  # #  ",
		" ##### ",
		" #   # "
	],
	"w": [ # Shadow
		"       ",
		"  ###  ",
		" #   # ",
		" # # # ",
		" ##### ",
		" # # # ",
		" # # # "
	],
	"m": [ # Merman
		"   #   ",
		"  ###  ",
		" # # # ",
		"  ###  ",
		" ##### ",
		"  ###  ",
		" #   # "
	],
	"n": [ # Water Snake
		"   ##  ",
		"  #  # ",
		"   ##  ",
		"  #  # ",
		"   ##  ",
		"  #    ",
		"  #    "
	],
	"q": [ # Kuragen / Jellyfish
		"  ###  ",
		" ##### ",
		"#######",
		" # # # ",
		" # # # ",
		" #   # ",
		" #   # "
	],
	"t": [ # Trent / Treant
		" ##### ",
		"#######",
		"#######",
		"  ###  ",
		"  ###  ",
		"  ###  ",
		" ##### "
	],
	"l": [ # Leaf Slime
		"   #   ",
		"  ###  ",
		" ##### ",
		"#######",
		"#######",
		" ##### ",
		"  ###  "
	],
	"e": [ # Ember Lizard
		"   ##  ",
		"  #  # ",
		" ######",
		" # #   ",
		" ######",
		" #   # ",
		" #   # "
	],
	# Uppercase / Boss enemies
	"O": [ # Orc
		" #   # ",
		"  ###  ",
		"#######",
		"#######",
		" # # # ",
		"#######",
		" #   # "
	],
	"M": [ # Giant Mantis
		"#     #",
		" #   # ",
		"  ###  ",
		" # # # ",
		"  ###  ",
		" #   # ",
		"#     #"
	],
	"Z": [ # Skeleton
		"  ###  ",
		" # # # ",
		"  ###  ",
		"   #   ",
		" ##### ",
		"   #   ",
		"  # #  "
	],
	"A": [ # Skeleton Archer
		"  ###  ",
		" # # # ",
		"  ### #",
		" ####| ",
		"  #  | ",
		"  #  | ",
		" # # # "
	],
	"S": [ # Slime Giant
		"  #####  ",
		" ####### ",
		"#########",
		"# # # # #",
		"#########",
		" ####### ",
		"  #####  "
	],
	"I": [ # Imp
		"#     #",
		" #   # ",
		"  ###  ",
		" # # # ",
		"  ###  ",
		" ##### ",
		"  # #  "
	],
	"T": [ # Minotaur
		"#     #",
		"##   ##",
		" ##### ",
		" # # # ",
		" ##### ",
		"#######",
		" #   # "
	],
	"R": [ # Animated Armor
		"  ###  ",
		" # # # ",
		"#######",
		"#######",
		" ##### ",
		" ##### ",
		" #   # "
	],
	"D": [ # Dragon
		"#     #",
		"##   ##",
		" ##### ",
		"#######",
		" # # # ",
		"#######",
		" # # # "
	],
	"K": [ # Armored Skeleton
		" ##### ",
		"# # # #",
		" ##### ",
		"   #   ",
		"#######",
		" ##### ",
		" #   # "
	],
	"J": [ # Giant Jellyfish
		" ##### ",
		"#######",
		"#######",
		"# # # #",
		"# # # #",
		"# # # #",
		"# # # #"
	],
	"W": [ # Grim Reaper
		"  ###  ",
		" ##### ",
		"# # # #",
		" #####)",
		"  ### |",
		" #####|",
		"  ### |"
	],
	"G": [ # Crystal Golem
		" ##### ",
		"# ### #",
		"#######",
		" ##### ",
		"#######",
		" ##### ",
		" #   # "
	],
	"Q": [ # Deep Squid
		"  ###  ",
		" ##### ",
		"#######",
		"# # # #",
		" #   # ",
		" # # # ",
		"#  #  #"
	],
	"E": [ # Ice Spirit
		"   #   ",
		" # # # ",
		"  ###  ",
		"#######",
		"  ###  ",
		" # # # ",
		"   #   "
	],
	"P": [ # Spark Slime
		"   #   ",
		"  ###  ",
		" # # # ",
		"#######",
		" # # # ",
		"  ###  ",
		"   #   "
	],
	"F": [ # Forest Vermin
		" #   # ",
		"  ###  ",
		" # # # ",
		" ##### ",
		"#######",
		" # # # ",
		"  ###  "
	],
	"L": [ # Flame Scatterer
		"   #   ",
		"  # #  ",
		" # # # ",
		"#######",
		" # # # ",
		"  ###  ",
		"   #   "
	],
	"B": [ # Baby Jellyfish
		"  ###  ",
		" ##### ",
		" # # # ",
		" ##### ",
		" # # # ",
		"       ",
		"       "
	],
	"C": [ # Crystal Shard
		"   #   ",
		"  ###  ",
		" ##### ",
		"#######",
		" ##### ",
		"  ###  ",
		"   #   "
	]
}

static func create_ascii_sprite(ch: String, fg_color: Color, with_glow: bool = false, bg_pill_color: Color = Color(0, 0, 0, 0)) -> Texture2D:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# If a background pill / badge is requested (e.g. for world items or special bosses)
	if bg_pill_color.a > 0.0:
		var center = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		var rad = 13.0
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var d = Vector2(x + 0.5, y + 0.5).distance_to(center)
				if d <= rad:
					var border_c = bg_pill_color.darkened(0.5)
					if d > rad - 1.5:
						img.set_pixel(x, y, border_c)
					else:
						# subtle radial lighting on pill
						var shade = 1.0 - (d / rad) * 0.3
						img.set_pixel(x, y, bg_pill_color.lightened(shade * 0.15))
						
	var raw_bitmap: Array = GLYPHS.get(ch, [])
	if raw_bitmap.is_empty():
		# Fallback 7x7 block for unknown glyphs
		raw_bitmap = [
			" ##### ",
			" #   # ",
			" # # # ",
			" ##### ",
			" #   # ",
			" #   # ",
			" ##### "
		]
		
	var rows = raw_bitmap.size()
	var cols = raw_bitmap[0].length()
	
	# Calculate scale & center offset
	var scale = 4 if cols <= 7 and rows <= 7 else 3
	var width = cols * scale
	var height = rows * scale
	var origin_x = (TILE_SIZE - width) / 2
	var origin_y = (TILE_SIZE - height) / 2
	
	# 1. Soft Drop Shadow (offset +2, +2)
	var shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	for r in range(rows):
		var line = raw_bitmap[r]
		for c in range(cols):
			if line.substr(c, 1) != " " and line.substr(c, 1) != ".":
				var px = origin_x + c * scale + 2
				var py = origin_y + r * scale + 2
				for dx in range(scale):
					for dy in range(scale):
						_blend_pixel(img, px + dx, py + dy, shadow_color)
						
	# 2. Dark Outline (1px border around the glyph)
	var outline_color = Color(0.04, 0.04, 0.06, 0.95)
	for r in range(rows):
		var line = raw_bitmap[r]
		for c in range(cols):
			if line.substr(c, 1) != " " and line.substr(c, 1) != ".":
				var px = origin_x + c * scale
				var py = origin_y + r * scale
				for ox in [-1, 0, 1]:
					for oy in [-1, 0, 1]:
						if ox == 0 and oy == 0: continue
						for dx in range(scale):
							for dy in range(scale):
								_blend_pixel(img, px + dx + ox, py + dy + oy, outline_color)
								
	# 3. Main Glyph Pixels with 3D Light Shading & Gradient
	for r in range(rows):
		var line = raw_bitmap[r]
		for c in range(cols):
			var ch_char = line.substr(c, 1)
			if ch_char != " " and ch_char != ".":
				var px = origin_x + c * scale
				var py = origin_y + r * scale
				
				# Gradient: brighter top, richer bottom
				var y_ratio = float(r) / float(rows)
				var vert_shade = (1.0 - y_ratio) * 0.25 - (y_ratio * 0.15)
				
				for dx in range(scale):
					for dy in range(scale):
						var is_highlight = (dy == 0 and r == 0) or (dx == 0 and dy == 0)
						var is_shadow = (dy == scale - 1 and r == rows - 1)
						
						var pixel_c = fg_color
						if is_highlight:
							pixel_c = pixel_c.lightened(0.35 + vert_shade)
						elif is_shadow:
							pixel_c = pixel_c.darkened(0.25)
						else:
							if vert_shade >= 0.0:
								pixel_c = pixel_c.lightened(vert_shade)
							else:
								pixel_c = pixel_c.darkened(-vert_shade)
								
						img.set_pixel(px + dx, py + dy, pixel_c)
						
	# 4. Optional Ambient Glow
	if with_glow:
		var glow_c = Color(fg_color.r, fg_color.g, fg_color.b, 0.12)
		for r in range(rows):
			var line = raw_bitmap[r]
			for c in range(cols):
				if line.substr(c, 1) != " " and line.substr(c, 1) != ".":
					var center_px = origin_x + c * scale + scale / 2
					var center_py = origin_y + r * scale + scale / 2
					for gx in range(-3, 4):
						for gy in range(-3, 4):
							var d = Vector2(gx, gy).length()
							if d > 0 and d <= 3.2:
								var a = (1.0 - d / 3.5) * 0.08
								_blend_pixel(img, center_px + gx, center_py + gy, Color(glow_c.r, glow_c.g, glow_c.b, a))
								
	return ImageTexture.create_from_image(img)

static func _blend_pixel(img: Image, x: int, y: int, color: Color):
	if x < 0 or x >= TILE_SIZE or y < 0 or y >= TILE_SIZE:
		return
	var bg = img.get_pixel(x, y)
	var out_a = color.a + bg.a * (1.0 - color.a)
	if out_a <= 0.0: return
	var out_r = (color.r * color.a + bg.r * bg.a * (1.0 - color.a)) / out_a
	var out_g = (color.g * color.a + bg.g * bg.a * (1.0 - color.a)) / out_a
	var out_b = (color.b * color.a + bg.b * bg.a * (1.0 - color.a)) / out_a
	img.set_pixel(x, y, Color(out_r, out_g, out_b, out_a))

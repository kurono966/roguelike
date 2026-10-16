extends CharacterBody2D

const GridVisualMotion = preload("res://actors/grid_visual_motion.gd")

const TILE_SIZE = 32  # 1タイルのサイズ（ピクセル）

@onready var sprite = $Sprite2D
var hp = 5 # Enemy's health points
var max_hp = 5
var _is_highlighted = false
var enemy_name: String = "ザコムシ"  # 敵の名前
var sprite_path: String = "res://assets/zakomushi.png"  # スプライトのパス
var can_swim = false # Default: cannot swim
var is_flying = false # Default: cannot fly
var base_color = Color(0.8, 0.3, 0.3) # Override in subclasses for fallback sprite

var exp_reward: int = 2 # Experience points given when defeated
var status_effects: Dictionary = {} # e.g., {"burn": {"duration": 3, "damage": 1}}
var has_knockback: bool = false # Ability to knock players back
var loot_table: Dictionary = {} # e.g., {"potion": 0.1, "rusty_sword": 0.05}
var on_hit_effects: Dictionary = {} # e.g., {"paralyze": {"chance": 0.3, "duration": 3}}
var trade_items: Array = [] # Items available for trade: [{"id": "potion", "price": 15}, ...]
var inventory_items: Array[BaseItem] = []
var _inventory_initialized: bool = false
var attack_range: int = 1 # Default melee range
var skill_id: String = "" # ID of skill (if any) enemy can use
var skill_cooldown: int = 0
var max_skill_cooldown: int = 5
var is_npc: bool = false
var is_hostile_to_player_only: bool = false
var fear: int = 0
var affection: int = 0
var weaknesses: Array = []
var resistances: Array = []
var fire_immune: bool = false
var grass_ignition_chance: float = 0.0
var grass_heal: int = 0
var is_gravekeeper: bool = false
var _death_processed: bool = false

var enemy_id: String = "zakomushi" # For save/load to pick the right scene
var turns_since_damage: int = 0
const REGEN_TURN_THRESHOLD: int = 10
var _idle_tween: Tween
var _move_tween: Tween
var _base_scale: Vector2 = Vector2.ZERO
var last_known_player_pos = null # Stores Vector2i of last seen player location
var penetration_rate: float = 0.0 # Defense penetration (0.0 - 1.0)
var intelligence: int = 0
var _use_fallback_draw: bool = false
var last_attacker = null # Tracks who dealt the killing blow

enum AiType { AGGRESSIVE, COWARD, SNIPER, IMMOBILE, RANDOM, GRASS_SCATTER, ALLY_FOLLOW }
var ai_type: AiType = AiType.AGGRESSIVE

func apply_definition(data: Dictionary):
	enemy_id = str(data.get("id", enemy_id))
	enemy_name = str(data.get("name", enemy_name))
	hp = int(data.get("hp", 5))
	max_hp = hp
	attack_power = int(data.get("atk", 1))
	defense = int(data.get("def", 0))
	exp_reward = int(data.get("exp", 2))
	base_color = data.get("color", base_color)
	sprite_path = str(data.get("sprite", ""))
	apply_behavior_definition(data)
	skill_cooldown = 0

func apply_behavior_definition(data: Dictionary):
	# Database definitions use these keys in every spawn and restore path.
	can_swim = bool(data.get("swim", false))
	is_flying = bool(data.get("fly", false))
	skill_id = str(data.get("skill", ""))
	attack_range = maxi(1, int(data.get("range", 1)))
	max_skill_cooldown = int(data.get("cooldown", 5))
	ai_type = data.get("ai", 0)
	has_knockback = bool(data.get("knockback", false))
	on_hit_effects = data.get("on_hit", {}).duplicate(true)
	loot_table = data.get("loot", {}).duplicate(true)
	weaknesses = data.get("weak", []).duplicate()
	resistances = data.get("resist", []).duplicate()
	penetration_rate = float(data.get("penetration", 0.0))
	intelligence = int(data.get("intelligence", 0))
	fire_immune = bool(data.get("fire_immune", false))
	grass_ignition_chance = float(data.get("grass_ignition_chance", 0.0))
	grass_heal = int(data.get("grass_heal", 0))
	is_gravekeeper = bool(data.get("gravekeeper", false))

func _ready():
	z_index = 5 # Ensure enemy is above floor/stairs but below UI/Flying text
	# スプライトを読み込み
	_load_enemy_sprite()
	queue_redraw()
	# _start_idle_animation is called inside _load_enemy_sprite

func ensure_inventory_initialized():
	if _inventory_initialized:
		return
	_inventory_initialized = true

	var ItemDatabase = load("res://items/item_database.gd")
	for trade_entry in trade_items:
		var item_id = str(trade_entry.get("id", ""))
		var item = ItemDatabase.get_item_by_id(item_id)
		if item:
			item.value = int(trade_entry.get("price", item.value))
			item.grid_position = Vector2i(-1, -1)
			inventory_items.append(item)

func add_inventory_item(item: BaseItem, price: int = -1):
	ensure_inventory_initialized()
	item.grid_position = Vector2i(-1, -1)
	if price >= 0:
		item.value = price
	inventory_items.append(item)

func remove_inventory_item(item: BaseItem) -> bool:
	ensure_inventory_initialized()
	var index = inventory_items.find(item)
	if index == -1:
		return false
	inventory_items.remove_at(index)
	item.grid_position = Vector2i(-1, -1)
	return true

# status_effects methods
func add_effect(effect_id: String, duration: int, data: Dictionary = {}):
	if effect_id == "burn" and fire_immune:
		return
	if status_effects.has(effect_id):
		return # 重ねがけ防止
		
	var effect_data = data.duplicate()
	effect_data["duration"] = duration
	status_effects[effect_id] = effect_data
	
	if effect_id == "paralyze":
		print(enemy_name, " is paralyzed!")
		if get_node_or_null("/root/LogUI"):
			get_node_or_null("/root/LogUI").add_log("%s は麻痺して動けない！" % enemy_name, Color.YELLOW)
	elif effect_id == "blind":
		print(enemy_name, " is blinded!")
		if get_node_or_null("/root/LogUI"):
			get_node_or_null("/root/LogUI").add_log("%s は視界を失った！" % enemy_name, Color(0.6, 0.1, 0.6))

	_update_status_visuals()

# Alias for compatibility with main.gd
func apply_effect(effect_name: String, params: Dictionary):
	var duration = params.get("duration", 3)
	add_effect(effect_name, duration, params)

func remove_effect(effect_name: String):
	if status_effects.erase(effect_name):
		print(enemy_name, " is no longer ", effect_name)
		_update_status_visuals()

func process_turn_effects():
	var effects_to_remove = []
	
	for effect_name in status_effects.keys():
		var data = status_effects[effect_name]
		
		if effect_name == "burn":
			if fire_immune:
				effects_to_remove.append(effect_name)
				continue
			var damage = data.get("damage", 1)
			take_damage(damage)
			if get_node_or_null("/root/LogUI"):
				get_node_or_null("/root/LogUI").add_log("%s は炎上のダメージを受けた (%d)" % [enemy_name, damage], Color(1.0, 0.5, 0.0))
		
		elif effect_name == "paralyze":
			# Paralyze just ticks down, effect is handled in Main turn logic
			pass

		elif effect_name == "blind":
			# Blind ticks down; vision range reduction is handled in TurnManager
			pass

		data["duration"] -= 1
		if data["duration"] <= 0:
			effects_to_remove.append(effect_name)
			
	for e in effects_to_remove:
		if e == "blind":
			if get_node_or_null("/root/LogUI"):
				get_node_or_null("/root/LogUI").add_log("%s の視界が戻った。" % enemy_name, Color(0.7, 0.4, 0.9))
		remove_effect(e)

	# HP recovery process (same criteria as player)
	if hp < max_hp and hp > 0:
		turns_since_damage += 1
		if turns_since_damage >= REGEN_TURN_THRESHOLD:
			var regen_amount = max(1, int(max_hp * 0.05))
			heal(regen_amount)

func is_paralyzed() -> bool:
	return status_effects.has("paralyze")

func is_blinded() -> bool:
	return status_effects.has("blind")

func _update_status_visuals():
	if status_effects.has("blind"):
		modulate = Color(0.5, 0.2, 0.6) # Dark purple tint
	elif status_effects.has("paralyze"):
		modulate = Color(1.0, 1.0, 0.3) # Yellowish
	elif status_effects.has("burn"):
		modulate = Color(1.0, 0.5, 0.5) # Red tint
	else:
		modulate = Color(1, 1, 1)

# 敵のスプライトを読み込み
func _load_enemy_sprite():
	var sprite = $Sprite2D
	var id = enemy_id.to_lower()
	
	# Override base_color with unique color per enemy type for distinguishability
	if is_hostile_to_player_only:
		base_color = Color(0.9, 0.4, 0.4)
	elif not is_npc:
		var unique_colors = {
			"zakomushi": Color(0.0, 1.0, 0.0),
			"bat": Color(0.5, 0.0, 0.5),
			"hitodama": Color(0.0, 1.0, 1.0),
			"goblin": Color(0.5, 0.5, 0.0),
			"orc": Color(0.0, 0.4, 0.0),
			"poison_mushroom": Color(0.8, 0.4, 0.9),
			"giant_mantis": Color(0.6, 1.0, 0.0),
			"skeleton": Color(0.8, 0.8, 0.8),
			"skeleton_archer": Color(0.7, 0.75, 0.8),
			"slime_giant": Color(0.0, 0.7, 0.7),
			"spider": Color(0.1, 0.1, 0.1),
			"prankster_imp": Color(1.0, 1.0, 0.0),
			"minotaur": Color(0.6, 0.3, 0.1),
			"animated_armor": Color(0.4, 0.45, 0.5),
			"dragon": Color(0.5, 0.0, 0.0),
			"red_orc": Color(1.0, 0.3, 0.0),
			"shadow": Color(0.3, 0.3, 0.8),
			"armored_skeleton": Color(0.35, 0.35, 0.35),
			"kuragen_giant": Color(0.0, 0.5, 1.0),
			"grim_reaper": Color(0.15, 0.15, 0.15),
			"crystal_golem": Color(0.5, 0.8, 0.9),
			"merman": Color(0.0, 0.5, 0.5),
			"water_snake": Color(0.4, 0.8, 0.7),
			"kuragen": Color(0.2, 0.6, 1.0),
			"squid_deep": Color(0.0, 0.0, 0.5),
			"ice_spirit": Color(0.6, 0.8, 0.95),
			"spark_slime": Color(0.9, 0.9, 0.2),
			"forest_zakomushi": Color(0.2, 0.7, 0.2),
			"flame_scatterer": Color(1.0, 0.35, 0.05),
			"trent": Color(0.3, 0.2, 0.05),
			"baby_jellyfish": Color(0.6, 0.8, 1.0),
			"leaf_slime": Color(0.2, 0.8, 0.2),
			"ember_lizard": Color(0.9, 0.3, 0.05),
			"crystal_shard": Color(0.7, 0.7, 0.95),
		}
		if unique_colors.has(id):
			base_color = unique_colors[id]
	
	var ascii_char = _get_ascii_char()
	var has_glow = id in ["hitodama", "crystal_golem", "ice_spirit", "spark_slime", "flame_scatterer", "ember_lizard", "crystal_shard", "dragon", "grim_reaper"]
	sprite.texture = AsciiArtGenerator.create_ascii_sprite(ascii_char, base_color.lightened(0.25), has_glow)
	if id == "gravekeeper" and not is_npc and not is_hostile_to_player_only:
		sprite.texture = AsciiArtGenerator.create_gravekeeper_sprite()
	sprite.modulate = Color.WHITE
	sprite.position = Vector2(16, 16)
	sprite.scale = Vector2.ONE
	_use_fallback_draw = false
	_start_idle_animation()
	return

	# Force fallback if sprite_path is explicitly empty (for procedural enemies)
	if sprite_path == "":
		_generate_fallback_sprite()
		return

	# Try to load the specified sprite path
	if ResourceLoader.exists(sprite_path):
		var texture = load(sprite_path)
		if texture:
			sprite.texture = texture
			# IMPORTANT: Reset color to white so the sprite's own colors show!
			sprite.modulate = Color.WHITE
			sprite.position = Vector2(16, 16)
			
			# Auto-scale to fit 32x32
			var tex_size = texture.get_size()
			var max_dim = max(tex_size.x, tex_size.y)
			if max_dim > 0:
				var target = 32.0
				var s = target / max_dim
				if sprite_path == "res://assets/crystal_golem.png":
					s *= 1.5
				sprite.scale = Vector2(s, s)
				
			# Restart animation to pick up new scale
			_start_idle_animation()
			return
	
	# If sprite not found, use fallback drawing
	print("Sprite not found for ", enemy_name, " at path: ", sprite_path, " - using fallback rendering")
	_generate_fallback_sprite()

# フォールバック用のシンプルなスプライト
# フォールバック描画: 五角形と頭文字
func _generate_fallback_sprite():
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	_use_fallback_draw = true
	queue_redraw()

func _draw():
	if _use_fallback_draw:
		var center = Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		var radius = TILE_SIZE/2.0 - 2
		
		# Draw outline (darker border)
		draw_circle(center, radius, base_color.darkened(0.5))
		# Draw inner area
		draw_circle(center, radius - 2, base_color)
		
		# Text (First character of name)
		if enemy_name.length() > 0:
			var chara = enemy_name.substr(0, 1)
			var font = ThemeDB.fallback_font
			if font:
				var font_size = 14
				var str_size = font.get_string_size(chara, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
				var text_pos = center + Vector2(-str_size.x / 2.0, str_size.y / 4.0 - 1) 
				# Draw text shadow for readability
				draw_string(font, text_pos + Vector2(1, 1), chara, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0,0,0,0.5))
				draw_string(font, text_pos, chara, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# --- HP Bar Drawing ---
	if max_hp > 0:
		var bar_width = TILE_SIZE - 4
		var bar_height = 4
		var bar_x = 2
		var bar_y = TILE_SIZE - bar_height - 2
		
		var bg_rect = Rect2(bar_x, bar_y, bar_width, bar_height)
		draw_rect(bg_rect, Color(0.1, 0.1, 0.1, 0.8)) # Background
		
		var hp_ratio = float(hp) / float(max_hp)
		hp_ratio = clamp(hp_ratio, 0.0, 1.0)
		var fill_width = max(1.0, bar_width * hp_ratio) if hp > 0 else 0.0
		
		var hp_color = Color(0.2, 0.8, 0.2) # Green
		if hp > max_hp: hp_color = Color(0.3, 0.95, 0.9)
		if hp_ratio <= 0.25:
			hp_color = Color(0.8, 0.2, 0.2) # Red
		elif hp_ratio <= 0.5:
			hp_color = Color(0.9, 0.8, 0.2) # Yellow
			
		if fill_width > 0:
			var fill_rect = Rect2(bar_x, bar_y, fill_width, bar_height)
			draw_rect(fill_rect, hp_color)
			# Add a slight highlight to the HP bar for a polished look
			draw_rect(Rect2(bar_x, bar_y, fill_width, 1), Color(1,1,1,0.3))

func _get_ascii_char() -> String:
	if is_hostile_to_player_only:
		return "hostile_npc"
	if is_npc:
		return "@"
	
	var id = enemy_id.to_lower()
	# Unique character mapping for each enemy type
	var char_map = {
		"zakomushi": "z",
		"bat": "b",
		"hitodama": "h",
		"goblin": "g",
		"orc": "O",
		"poison_mushroom": "p",
		"giant_mantis": "M",
		"skeleton": "Z",
		"skeleton_archer": "A",
		"slime_giant": "S",
		"spider": "x",
		"prankster_imp": "I",
		"minotaur": "T",
		"animated_armor": "R",
		"dragon": "D",
		"red_orc": "r",
		"shadow": "w",
		"armored_skeleton": "K",
		"kuragen_giant": "J",
		"grim_reaper": "W",
		"crystal_golem": "G",
		"merman": "m",
		"water_snake": "n",
		"kuragen": "q",
		"squid_deep": "Q",
		"ice_spirit": "E",
		"spark_slime": "P",
		"forest_zakomushi": "F",
		"root_eater": "r",
		"gravekeeper": "G",
		"flame_scatterer": "L",
		"trent": "t",
		"baby_jellyfish": "B",
		"leaf_slime": "l",
		"ember_lizard": "e",
		"crystal_shard": "C",
	}
	
	if char_map.has(id):
		return char_map[id]
	return enemy_name.substr(0, 1).to_upper()

func _create_ascii_sprite(ch: String, fg_color: Color) -> Texture2D:
	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bitmap = _get_ascii_bitmap(ch)
	var scale = 4
	var origin = Vector2i(6, 2)
	for y in range(bitmap.size()):
		for x in range(bitmap[y].length()):
			if bitmap[y].substr(x, 1) == "#":
				for dx in range(scale):
					for dy in range(scale):
						img.set_pixel(origin.x + x * scale + dx, origin.y + y * scale + dy, fg_color)
	return ImageTexture.create_from_image(img)

func _get_ascii_bitmap(ch: String) -> Array:
	match ch:
		"@": return [" ### ", "#...#", "#.###", "#.#.#", "#.###", "#....", " ####"]
		"b": return ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####."]
		"D": return ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."]
		"f": return [".####", "#....", "#....", "###..", "#....", "#....", "#...."]
		"G": return [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."]
		"j": return ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."]
		"l": return ["##...", ".#...", ".#...", ".#...", ".#...", ".#...", "###.."]
		"M": return ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"]
		"m": return [".....", "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#"]
		"o": return [".....", ".###.", "#...#", "#...#", "#...#", "#...#", ".###."]
		"s": return [".####", "#....", "#....", ".###.", "....#", "....#", "####."]
		"T": return ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."]
		"w": return [".....", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"]
		"x": return ["#...#", ".#.#.", "..#..", ".#.#.", "#...#", ".....", "....."]
		"Z": return ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"]
		"z": return ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"]
		"h": return ["#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#"]
		"g": return ["....#", ".###.", "#...#", "#...#", ".###.", "...#.", "###.."]
		"O": return [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."]
		"p": return ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."]
		"S": return [".####", "#....", "#....", ".###.", "....#", "....#", "####."]
		"I": return ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"]
		"A": return [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"]
		"R": return ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"]
		"r": return ["....#", "....#", "####.", "#...#", "#....", "#....", "#...."]
		"K": return ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"]
		"J": return ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."]
		"W": return ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"]
		"n": return ["....#", "....#", "####.", "#...#", "#...#", "#...#", "#...#"]
		"q": return ["...#.", "...#.", ".###.", "#...#", ".###.", "...#.", "...#."]
		"Q": return [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.."]
		"E": return ["#####", "#....", "#....", "####.", "#....", "#....", "#####"]
		"P": return ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."]
		"F": return ["#####", "#....", "#....", "####.", "#....", "#....", "#...."]
		"L": return ["#....", "#....", "#....", "#....", "#....", "#....", "#####"]
		"t": return ["..#..", "..#..", "#####", "..#..", "..#..", "..#..", "..#.."]
		"B": return ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."]
		"e": return ["....#", ".###.", "#...#", "#####", "#....", "#....", ".###."]
		"C": return [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."]
		_: return [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"]

func move(direction: Vector2):
	var target_position = position + direction * TILE_SIZE
	position = target_position.snapped(Vector2.ONE)
	velocity = Vector2.ZERO  # Prevent physics engine from moving the body

var attack_power: int = 1  # 敵の攻撃力
var defense: int = 0
var hit_rate: float = 0.85

func take_damage(amount: int, attacker = null, elements = ["normal"], is_crit: bool = false):
	if typeof(elements) == TYPE_STRING:
		elements = [elements]

	var multiplier = 1.0
	var ext_text = ""
	
	for elem in elements:
		if elem in weaknesses:
			multiplier *= 2.0
			if "弱点" not in ext_text: ext_text += " (弱点!)"
		elif elem in resistances:
			multiplier *= 0.5
			if "耐性" not in ext_text: ext_text += " (耐性)"
		
	var final_amount = max(1, int(amount * multiplier))

	# 根付き状態: 受けるダメージを約10%に軽減
	if status_effects.has("rooted") and final_amount > 0:
		final_amount = max(1, int(round(float(final_amount) * 0.1)))

	hp -= final_amount
	turns_since_damage = 0
	queue_redraw()
	if attacker != null:
		last_attacker = attacker
		# Direct violence has a much stronger personal effect than witnessing it.
		if is_npc and attacker.is_in_group("player"):
			affection = clampi(affection - 100, -100, 100)
			var fear_gain = int(round(float(final_amount) / float(max(1, max_hp)) * 100.0))
			fear = clampi(fear + fear_gain, 0, 100)
			var crime_reporter = get_parent()
			if crime_reporter and crime_reporter.has_method("report_player_crime"):
				crime_reporter.report_player_crime("assault_neutral", self, attacker)
			if affection <= -50:
				_make_hostile()
			
	print("Enemy took ", final_amount, " damage. HP: ", hp)
	
	# Log weakness/resistance info
	if ext_text != "" and has_node("/root/LogUI"):
		var log_color = Color.RED if "弱点" in ext_text else Color.GRAY
		get_node("/root/LogUI").add_log("%s%s" % [enemy_name, ext_text], log_color)
	
	GridVisualMotion.reset(self)

	# --- Juicy Hit Feedback ---
	
	# 1. Hit Flash modulation (Using over-bright modulate values to achieve white/red flash with safe reset)
	if sprite:
		# Kill any ongoing flash tween to avoid initial color corruption on consecutive hits
		if has_meta("flash_tween"):
			var old_tween = get_meta("flash_tween")
			if old_tween and old_tween.is_valid():
				old_tween.kill()
		
		# Base color dynamically calculated (accounting for highlighting)
		var base_color = Color(1.5, 1.5, 1.5) if _is_highlighted else Color(1.0, 1.0, 1.0)
		
		# Set bright white/red hit color immediately
		sprite.modulate = Color(2.5, 2.5, 2.5) if not is_crit else Color(3.5, 1.2, 1.2)
		
		# Tween back to base color safely
		var flash_tween = create_tween()
		set_meta("flash_tween", flash_tween)
		flash_tween.tween_interval(0.04)
		flash_tween.tween_property(sprite, "modulate", base_color, 0.06)

	# Recoil shares ownership of sprite position with movement and attacks.
	if sprite and attacker:
		var recoil_dir = (position - attacker.position).normalized()
		if recoil_dir.is_zero_approx():
			recoil_dir = Vector2.UP
		GridVisualMotion.bump(self, recoil_dir, 10.0 if is_crit else 5.0, 0.04, 0.06)

	# 3. Trigger global camera shake via parent main node
	var main_node = get_parent()
	if main_node and main_node.has_method("shake_camera"):
		if is_crit:
			main_node.shake_camera(6.0, 0.2)
		else:
			main_node.shake_camera(2.0, 0.1)

	# 4. Spawn physical/attribute-specific hit sparks particles
	if main_node and main_node.has_method("_spawn_skill_particles"):
		var p_type = "hit_physical"
		if elements.has("fire"):
			p_type = "fire"
		elif elements.has("ice"):
			p_type = "ice"
		main_node._spawn_skill_particles(position + Vector2(16, 16), p_type, 0.4)

	# ---

	# Play Damage Sound
	var sound_file = "res://assets/sounds/damage.mp3"
	if ResourceLoader.exists(sound_file):
		var asp = AudioStreamPlayer.new()
		asp.stream = load(sound_file)
		add_child(asp)
		asp.finished.connect(asp.queue_free)
		asp.play()

	# Show Floating Text
	var float_text_scene = load("res://ui/floating_text.tscn")
	if float_text_scene:
		var float_text = float_text_scene.instantiate()
		float_text.position = Vector2(16, -16) # Above enemy center
		
		var color = Color(1, 0.3, 0.3) # Default Red
		if is_crit:
			color = Color(1.0, 0.8, 0.1) # Juicy gold for critical hits
		elif multiplier > 1.0:
			color = Color(1.0, 0.5, 0.0) # Orange for weakness
		elif multiplier < 1.0:
			color = Color(0.6, 0.6, 0.6) # Gray for resistance
			
		float_text.set_text(str(final_amount) + ext_text, color, is_crit)
		add_child(float_text)
	
	if hp <= 0:
		die()

func die():
	if _death_processed: return
	_death_processed = true
	var main = get_parent()
	if main and "corpse_manager" in main and main.corpse_manager:
		main.corpse_manager.add_corpse(enemy_id, enemy_name, position)
	print("Enemy defeated!")
	
	if get_node_or_null("/root/LogUI"):
		get_node_or_null("/root/LogUI").add_log("%s を倒した！" % enemy_name, Color.YELLOW)
	
	# Play death sound
	var sound_file = "res://assets/sounds/enemydeath.mp3"
	if ResourceLoader.exists(sound_file):
		var asp = AudioStreamPlayer.new()
		asp.stream = load(sound_file)
		# Add to parent (Main) so it doesn't get deleted immediately with enemy
		get_parent().add_child(asp)
		asp.finished.connect(asp.queue_free)
		asp.play()
	
	# プレイヤーに経験値を与える（プレイヤーが直接倒した場合のみ）
	var killer_is_player = false
	var tree = get_tree()
	if tree:
		var players = tree.get_nodes_in_group("player")
		if players.size() > 0:
			var player = players[0]
			# 影の分身がとどめを刺した場合は、その源（プレイヤー）を倒した者として扱う
			var credited = last_attacker
			if credited is ShadowClone and is_instance_valid(credited.source):
				credited = credited.source
			# Grant EXP only if killed by the player, not by an NPC ally
			if credited == player or (credited == null and not is_in_group("npcs")):
				killer_is_player = true
			if killer_is_player and player.has_method("gain_exp"):
				player.gain_exp(exp_reward)
	
	# --- Loot Drop Logic ---
	if not loot_table.is_empty():
		var ItemDatabase = load("res://items/item_database.gd")
		var WorldItemScene = load("res://items/world_item.tscn")
		
		for item_id in loot_table:
			var chance = loot_table[item_id]
			if randf() < chance:
				var items = ItemDatabase.get_all_items()
				var target_item = null
				for item in items:
					if item.id == item_id:
						target_item = item
						break
				
				if target_item:
					var parent = get_parent()
					if parent.has_method("spawn_world_item"):
						parent.spawn_world_item(target_item, position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
						print("Dropped item: ", target_item.name)
					else:
						# Fallback
						var world_item = WorldItemScene.instantiate()
						parent.add_child(world_item)
						var grid_pos = Vector2i((position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)) / TILE_SIZE)
						world_item.position = Vector2(grid_pos) * TILE_SIZE
						world_item.set_item(target_item)
						world_item.add_to_group("items")
						world_item.add_to_group("entities")
				break

	# NPC inventory is physical: every item still owned is dropped on death.
	ensure_inventory_initialized()
	if not inventory_items.is_empty():
		var parent = get_parent()
		for item in inventory_items:
			item.grid_position = Vector2i(-1, -1)
			if parent.has_method("spawn_world_item"):
				parent.spawn_world_item(item, position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
		inventory_items.clear()
	
	queue_free()

func _make_hostile():
	if not is_npc: return
	is_hostile_to_player_only = true
	is_npc = false
	if is_in_group("npcs"):
		remove_from_group("npcs")
	if not is_in_group("enemies"):
		add_to_group("enemies")
	
	# Change AI to Aggressive
	ai_type = AiType.AGGRESSIVE
	
	# Reset base color if it was an NPC
	base_color = Color(0.9, 0.4, 0.4)
	_load_enemy_sprite()
	
	if get_node_or_null("/root/LogUI"):
		get_node_or_null("/root/LogUI").add_log("%s は激怒した！" % enemy_name, Color.RED)

func heal(amount: int, allow_overheal: bool = false):
	if amount <= 0 or hp <= 0: return
	hp = hp + amount if allow_overheal else maxi(hp, mini(hp + amount, max_hp))
	queue_redraw()
	print("Enemy healed ", amount, " HP. HP: ", hp)
	
	var float_text_scene = load("res://ui/floating_text.tscn")
	if float_text_scene:
		var float_text = float_text_scene.instantiate()
		float_text.position = Vector2(16, -16) # Above enemy center
		float_text.set_text("+" + str(amount), Color(0.3, 1.0, 0.3))
		add_child(float_text)

func set_highlight(enable: bool):
	if _is_highlighted != enable:
		_is_highlighted = enable
		if enable:
			$Sprite2D.modulate = Color(1.5, 1.5, 1.5)  # 明るくする
		else:
			$Sprite2D.modulate = Color(1, 1, 1)  # 通常の色に戻す

var ally_target: CharacterBody2D = null

func set_ally(target: CharacterBody2D):
	ally_target = target
	# Change AI behavior to follow player
	ai_type = AiType.ALLY_FOLLOW
	# Change sprite color to indicate ally status
	if sprite:
		sprite.modulate = Color(0.3, 1.0, 0.3)  # Green tint for allies

func _start_idle_animation():
	if not sprite: return
	
	if _base_scale.is_zero_approx():
		_base_scale = sprite.scale
		if _base_scale.is_zero_approx(): _base_scale = Vector2.ONE
	
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	
	_idle_tween = create_tween().set_loops()
	
	# Subtle breathing squash & stretch
	var squash = _base_scale * Vector2(1.03, 0.97)
	var stretch = _base_scale * Vector2(0.97, 1.03)
	
	_idle_tween.tween_property(sprite, "scale", squash, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(sprite, "scale", stretch, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func move_to_grid(target_grid: Vector2i, is_auto: bool = false):
	GridVisualMotion.reset(self)
	var target_pos = Vector2(target_grid) * TILE_SIZE
	var diff = target_pos - position
	position = target_pos.snapped(Vector2.ONE)
	velocity = Vector2.ZERO
	
	if not sprite: return
	
	if _base_scale.is_zero_approx():
		_base_scale = sprite.scale
		if _base_scale.is_zero_approx(): _base_scale = Vector2.ONE
		
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
		
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
		
	_move_tween = create_tween()
	
	# Slide position back to sprite center
	sprite.position -= diff
	var anim_time = 0.12
	
	_move_tween.set_parallel(true)
	_move_tween.tween_property(sprite, "position", Vector2(16, 16), anim_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Squash & Stretch walk bounce sequence
	var scale_tween = create_tween()
	var stretch_scale = _base_scale * Vector2(0.82, 1.22)
	var squash_scale = _base_scale * Vector2(1.22, 0.82)
	
	scale_tween.tween_property(sprite, "scale", stretch_scale, anim_time * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(sprite, "scale", squash_scale, anim_time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	scale_tween.tween_property(sprite, "scale", _base_scale, anim_time * 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	scale_tween.tween_callback(_start_idle_animation)

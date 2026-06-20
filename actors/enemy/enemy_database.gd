class_name EnemyDatabase
extends RefCounted

const ENEMY_DATA_DIR = "res://actors/enemy/data"
static var _enemy_cache: Dictionary = {}

# Master list of all enemies mapped by a string ID
const ENEMIES = {
	"zakomushi": {"name": "雑魚虫", "hp": 10, "atk": 4, "def": 1, "color": Color.GREEN, "swim": false, "sprite": "res://assets/zakomushi.png", "loot": {"potion": 0.1, "gummy": 0.4, "zakomushi_shell": 0.15}, "penetration": 0.1, "exp": 2, "weak": ["fire"]},
	"bat": {"name": "ワイルド・コウモリ", "hp": 8, "atk": 2, "def": 0, "color": Color.PURPLE, "swim": true, "fly": true, "loot": {"scroll_teleport": 0.05}, "sprite": "res://assets/bat.png", "penetration": 1, "exp": 2, "weak": ["ice", "electric"]},
	"hitodama": {"name": "人魂", "hp": 6, "atk": 3, "def": 0, "color": Color.CYAN, "swim": true, "fly": true, "sprite": "res://assets/hitodama.png", "exp": 3, "weak": ["water"], "resist": ["fire", "ice", "magic"]},
	"goblin": {"name": "小鬼", "hp": 25, "atk": 4, "def": 2, "color": Color.GREEN, "swim": false, "loot": {"rusty_sword": 0.1, "potion": 0.1, "goblin_arm": 0.1}, "sprite": "res://assets/goblin.png", "penetration": 1, "exp": 5, "weak": ["fire"]},
	"orc": {"name": "オーク", "hp": 30, "atk": 6, "def": 4, "color": Color.DARK_GREEN, "swim": false, "loot": {"leather_armor": 0.15, "potion_str": 0.05}, "sprite": "res://assets/orc.png", "penetration": 0.3, "exp": 8, "weak": ["fire"]},
	"poison_mushroom": {"name": "毒キノコ", "hp": 18, "atk": 2, "def": 1, "color": Color.VIOLET, "swim": false, "sprite": "res://assets/poison_mushroom.png", "on_hit": {"paralyze": {"chance": 0.4, "duration": 3}}, "exp": 4, "weak": ["fire"]},
	"giant_mantis": {"name": "大カマキリ", "hp": 22, "atk": 12, "def": 3, "color": Color.CHARTREUSE, "swim": false, "sprite": "res://assets/giant_mantis.png", "penetration": 0.6, "loot": {"potion": 0.1}, "exp": 12, "weak": ["fire"], "resist": ["water"]},
	"skeleton": {"name": "骸骨兵", "hp": 40, "atk": 12, "def": 5, "color": Color.LIGHT_GRAY, "swim": false, "loot": {"round_shield": 0.1}, "sprite": "res://assets/skeleton.png", "exp": 10, "weak": ["blunt"], "resist": ["pierce"]},
	"skeleton_archer": {"name": "骸骨弓兵", "hp": 30, "atk": 10, "def": 3, "color": Color.LIGHT_SLATE_GRAY, "swim": false, "skill": "arrow_shot", "range": 5, "loot": {"gummy": 0.3}, "sprite": "res://assets/skeleton_archer.png", "exp": 12, "weak": ["blunt"], "resist": ["pierce"]},
	"slime_giant": {"name": "大粘液", "hp": 60, "atk": 8, "def": 2, "color": Color.CYAN, "swim": true, "loot": {"potion": 0.3, "gummy": 0.5, "slime_leg": 0.1}, "sprite": "res://assets/slime.png", "exp": 20, "weak": ["fire", "electric"], "resist": ["water"]},
	"spider": {"name": "土蜘蛛", "hp": 20, "atk": 3, "def": 2, "color": Color.BLACK, "swim": false, "skill": "web_shot", "range": 4, "cooldown": 10, "loot": {"spider_leg": 0.2}, "on_hit": {"paralyze": {"chance": 0.4, "duration": 3}}, "sprite": "res://assets/spider.png", "penetration": 0.1, "exp": 15, "weak": ["fire"]},
	"prankster_imp": {"name": "いたずら小僧", "hp": 25, "atk": 5, "def": 2, "color": Color.YELLOW, "swim": false, "fly": true, "skill": "scramble", "range": 1, "cooldown": 1, "loot": {"gummy": 0.4}, "sprite": "res://assets/prankster_imp.png", "exp": 20},
	"minotaur": {"name": "牛頭鬼", "hp": 80, "atk": 16, "def": 8, "color": Color.BROWN, "swim": false, "knockback": true, "loot": {"long_sword": 0.2, "high_potion": 0.1, "minotaur_horn": 0.2}, "sprite": "res://assets/minotaur.png", "penetration": 0.7, "exp": 30},
	"animated_armor": {"name": "動く鎧", "hp": 55, "atk": 14, "def": 12, "color": Color.SLATE_GRAY, "swim": false, "sprite": "res://assets/animated_armor.png", "penetration": 0.4, "loot": {"long_sword": 0.1, "round_shield": 0.15}, "exp": 25, "weak": ["electric", "blunt"], "resist": ["pierce", "fire", "magic"]},
	"dragon": {"name": "ドラゴン", "hp": 150, "atk": 25, "def": 15, "color": Color.DARK_RED, "swim": false, "fly": true, "sprite": "res://assets/dragon.png", "skill": "lightning", "range": 6, "cooldown": 8, "penetration": 0.2, "loot": {"high_potion": 0.5}, "intelligence": 8, "exp": 100, "weak": ["ice", "water"], "resist": ["fire", "magic"]},
	"red_orc": {"name": "赤鬼", "hp": 100, "atk": 20, "def": 10, "color": Color.ORANGE_RED, "swim": false, "loot": {"high_potion": 0.2, "potion_str": 0.1}, "sprite": "res://assets/red_orc.png", "exp": 50, "penetration": 0.5, "weak": ["water"]},
	"shadow": {"name": "影法師", "hp": 50, "atk": 18, "def": 3, "color": Color.DARK_SLATE_BLUE, "swim": true, "loot": {"scroll_teleport": 0.3}, "sprite": "res://assets/shadow.png", "exp": 35, "weak": ["fire"]},
	"armored_skeleton": {"name": "重装骸骨", "hp": 70, "atk": 16, "def": 10, "color": Color.DIM_GRAY, "swim": false, "loot": {"round_shield": 0.2}, "sprite": "res://assets/armored_skeleton.png", "exp": 40, "weak": ["electric", "blunt"], "resist": ["pierce", "fire"]},
	"kuragen_giant": {"name": "大クラゲン", "hp": 90, "atk": 18, "def": 4, "color": Color.BLUE, "swim": true, "sprite": "res://assets/kuragen.png", "skill": "paralyze_touch", "range": 1, "loot": {"scroll_mapping": 0.1}, "exp": 45, "weak": ["electric"], "resist": ["water"]},
	"grim_reaper": {"name": "死神", "hp": 60, "atk": 16, "def": 5, "color": Color.BLACK, "swim": true, "fly": true, "sprite": "res://assets/grim_reaper.png", "penetration": 0.6, "loot": {"potion_str": 0.2}, "exp": 80, "weak": ["fire"]},
	"crystal_golem": {"name": "クリスタルゴーレム", "hp": 120, "atk": 15, "def": 20, "color": Color.SKY_BLUE, "swim": false, "knockback": true, "sprite": "res://assets/crystal_golem.png", "penetration": 0.8, "loot": {"scroll_teleport": 0.5}, "exp": 60, "weak": ["blunt"], "resist": ["magic", "fire", "ice", "electric"]},
	"merman": {"name": "半魚人", "hp": 30, "atk": 10, "def": 4, "color": Color.TEAL, "swim": true, "sprite": "res://assets/merman.png", "loot": {"potion": 0.2}, "exp": 14, "weak": ["electric"], "resist": ["water"]},
	"water_snake": {"name": "水蛇", "hp": 25, "atk": 6, "def": 2, "color": Color.AQUAMARINE, "swim": true, "sprite": "res://assets/water_snake.png", "on_hit": {"poison": {"chance": 0.5, "duration": 5}}, "exp": 10, "weak": ["electric"], "resist": ["water"]},
	"kuragen": {"name": "クラゲン", "hp": 35, "atk": 8, "def": 3, "color": Color.BLUE, "swim": true, "sprite": "res://assets/kuragen.png", "skill": "paralyze_touch", "range": 1, "loot": {"scroll_mapping": 0.1}, "exp": 15, "weak": ["electric"], "resist": ["water"]},
	"squid_deep": {"name": "深海イカ", "hp": 80, "atk": 15, "def": 6, "color": Color.NAVY_BLUE, "swim": true, "skill": "lightning", "range": 4, "cooldown": 6, "intelligence": 5, "loot": {"high_potion": 0.2}, "exp": 45, "weak": ["electric"], "resist": ["water"]},
	"ice_spirit": {"name": "氷の精霊", "hp": 45, "atk": 12, "def": 4, "color": Color.LIGHT_BLUE, "swim": true, "fly": true, "sprite": "res://assets/korinoseirei.png", "skill": "freeze", "range": 4, "cooldown": 8, "intelligence": 6, "loot": {"ether": 0.15}, "exp": 35, "weak": ["fire"], "resist": ["ice", "water"]},
	"spark_slime": {"name": "スパークスライム", "hp": 30, "atk": 5, "def": 2, "color": Color(0.95, 0.95, 0.3), "swim": true, "sprite": "res://assets/spark_slime.png", "skill": "lightning", "range": 4, "cooldown": 6, "loot": {"spark_core": 0.20, "potion": 0.1}, "exp": 15, "weak": ["blunt"], "resist": ["electric", "water"]},
	"forest_zakomushi": {"name": "森 of 雑魚虫", "hp": 10, "atk": 4, "def": 1, "color": Color.GREEN, "swim": false, "sprite": "res://assets/zakomushi.png", "loot": {"potion": 0.1, "gummy": 0.5}, "penetration": 0.1, "exp": 3, "weak": ["fire"]},
	"flame_scatterer": {"name": "フレイムスキャッター", "hp": 16, "atk": 3, "def": 2, "color": Color.ORANGE_RED, "swim": false, "sprite": "res://assets/flame_scatterer.png", "skill": "flame_scatter", "range": 4, "cooldown": 10, "loot": {"ether": 0.08}, "exp": 9, "weak": ["water", "ice"], "resist": ["fire"], "fire_immune": true, "grass_ignition_chance": 0.7, "ai": 5},
	"trent": {"name": "トレント", "hp": 80, "atk": 15, "def": 12, "color": Color.SADDLE_BROWN, "swim": false, "loot": {"high_potion": 0.2}, "sprite": "res://assets/minotaur.png", "exp": 40, "weak": ["fire"], "resist": ["water", "electric"]},
	"baby_jellyfish": {"name": "迷子クラゲ", "hp": 12, "atk": 3, "def": 0, "color": Color(0.6, 0.8, 1.0), "swim": true, "sprite": "res://assets/maigokurage.png", "exp": 2, "weak": ["electric"], "resist": ["water"]},
	"leaf_slime": {"name": "リーフスライム", "hp": 14, "atk": 4, "def": 1, "color": Color(0.4, 0.9, 0.4), "swim": false, "sprite": "res://assets/leafslime.png", "exp": 2, "weak": ["fire"], "resist": ["water"]},
	"ember_lizard": {"name": "火の粉トカゲ", "hp": 16, "atk": 4, "def": 1, "color": Color(1.0, 0.5, 0.2), "swim": false, "sprite": "res://assets/water_snake.png", "exp": 3, "weak": ["water", "ice"], "resist": ["fire"], "fire_immune": true},
	"crystal_shard": {"name": "水晶のかけら", "hp": 14, "atk": 3, "def": 3, "color": Color(0.9, 0.9, 1.0), "swim": false, "fly": true, "sprite": "res://assets/suishonokakera.png", "exp": 3, "weak": ["blunt"], "resist": ["magic"]},
	# NPCs
	"wanderer_swordsman": {"name": "放浪の剣士", "hp": 50, "atk": 15, "def": 8, "color": Color.WHITE, "swim": false, "sprite": "res://assets/wanderer_swordsman.png", "exp": 0, "is_npc": true, "trade_items": [{"id": "gummy", "price": 10}]},
	"stray_mage": {"name": "はぐれ魔道士", "hp": 40, "atk": 8, "def": 4, "color": Color.TURQUOISE, "swim": true, "sprite": "res://assets/stray_mage.png", "skill": "fireball", "range": 4, "cooldown": 3, "exp": 0, "is_npc": true, "trade_items": [{"id": "ether", "price": 15}]},
	"villager": {"name": "村人", "hp": 20, "atk": 2, "def": 1, "color": Color.BEIGE, "swim": false, "sprite": "res://assets/villager.png", "exp": 0, "is_npc": true, "trade_items": [{"id": "potion", "price": 12}]},
	"merchant": {"name": "商人", "hp": 30, "atk": 5, "def": 3, "color": Color.GOLD, "swim": false, "sprite": "res://assets/merchant.png", "exp": 0, "is_npc": true, "trade_items": [{"id": "potion", "price": 15}, {"id": "gummy", "price": 12}, {"id": "ether", "price": 18}, {"id": "high_potion", "price": 40}]},
	"elder": {"name": "村の長老", "hp": 15, "atk": 1, "def": 0, "color": Color.ANTIQUE_WHITE, "swim": false, "sprite": "res://assets/elder.png", "exp": 0, "is_npc": true, "trade_items": [{"id": "potion", "price": 10}, {"id": "gummy", "price": 8}]},
	"guard": {"name": "村の守備隊", "hp": 45, "atk": 12, "def": 10, "color": Color.SKY_BLUE, "swim": false, "sprite": "res://assets/guard.png", "exp": 0, "is_npc": true, "trade_items": [{"id": "potion", "price": 13}]}
}

# Spawning lookup maps by branch and floor thresholds
const SPAWN_TABLES = {
	# 0: Normal Branch
	0: [
		{"floor_max": 1, "pool": ["zakomushi", "bat", "hitodama"]},
		{"floor_max": 3, "pool": ["zakomushi", "bat", "hitodama", "goblin", "orc", "poison_mushroom"]},
		{"floor_max": 6, "pool": ["goblin", "orc", "poison_mushroom", "skeleton", "skeleton_archer", "slime_giant", "spider"]},
		{"floor_max": 9, "pool": ["skeleton", "skeleton_archer", "slime_giant", "spider", "red_orc", "shadow", "armored_skeleton"]},
		{"floor_max": 999, "pool": ["dragon", "red_orc", "shadow", "armored_skeleton", "kuragen_giant", "grim_reaper", "crystal_golem"]}
	],
	# 2: Blue Branch (Water Area)
	2: [
		{"floor_max": 3, "pool": ["baby_jellyfish", "merman", "water_snake", "hitodama", "zakomushi", "bat"]},
		{"floor_max": 6, "pool": ["baby_jellyfish", "merman", "water_snake", "hitodama", "kuragen", "slime_giant", "spark_slime", "zakomushi", "bat", "goblin", "orc"]},
		{"floor_max": 999, "pool": ["merman", "water_snake", "hitodama", "kuragen", "slime_giant", "spark_slime", "squid_deep", "kuragen_giant", "ice_spirit", "goblin", "orc", "skeleton", "skeleton_archer"]}
	],
	# 3: Green Branch (Grass Area)
	3: [
		{"floor_max": 3, "pool": ["leaf_slime", "goblin", "orc", "poison_mushroom", "forest_zakomushi", "zakomushi", "bat", "hitodama"]},
		{"floor_max": 6, "pool": ["leaf_slime", "goblin", "orc", "poison_mushroom", "forest_zakomushi", "giant_mantis", "flame_scatterer", "spider", "zakomushi", "bat", "hitodama", "skeleton", "skeleton_archer"]},
		{"floor_max": 999, "pool": ["goblin", "orc", "poison_mushroom", "giant_mantis", "flame_scatterer", "spider", "trent", "skeleton", "skeleton_archer", "slime_giant"]}
	],
	# 4: Volcanic Branch (Red Area)
	4: [
		{"floor_max": 3, "pool": ["ember_lizard", "forest_zakomushi", "flame_scatterer", "goblin", "orc", "poison_mushroom"]},
		{"floor_max": 6, "pool": ["flame_scatterer", "animated_armor", "red_orc", "shadow", "goblin", "orc", "poison_mushroom", "skeleton", "skeleton_archer", "slime_giant"]},
		{"floor_max": 999, "pool": ["forest_zakomushi", "flame_scatterer", "trent", "dragon", "red_orc", "shadow", "armored_skeleton", "kuragen_giant", "grim_reaper", "crystal_golem", "animated_armor", "minotaur"]}
	],
	# 5: Crystal Branch (Purple Area)
	5: [
		{"floor_max": 3, "pool": ["crystal_shard", "skeleton", "skeleton_archer", "bat"]},
		{"floor_max": 6, "pool": ["crystal_shard", "skeleton", "skeleton_archer", "animated_armor", "shadow", "armored_skeleton"]},
		{"floor_max": 999, "pool": ["skeleton", "skeleton_archer", "animated_armor", "crystal_golem", "dragon", "red_orc", "shadow", "armored_skeleton", "kuragen_giant", "grim_reaper"]}
	],
	# 10: Beginner Branch (Starter Dungeon)
	10: [
		{"floor_max": 1, "pool": ["zakomushi", "baby_jellyfish", "leaf_slime"]},
		{"floor_max": 2, "pool": ["zakomushi", "baby_jellyfish", "leaf_slime", "bat"]},
		{"floor_max": 999, "pool": ["zakomushi", "baby_jellyfish", "leaf_slime", "bat", "hitodama"]}
	],
	# Default / High-Risk Branch (else / branch 1)
	99: [
		{"floor_max": 3, "pool": ["zakomushi", "bat", "hitodama", "goblin", "orc", "poison_mushroom"]},
		{"floor_max": 6, "pool": ["skeleton", "skeleton_archer", "slime_giant", "spider", "animated_armor", "red_orc", "shadow"]},
		{"floor_max": 999, "pool": ["skeleton", "skeleton_archer", "slime_giant", "spider", "dragon", "red_orc", "shadow", "armored_skeleton", "kuragen_giant", "grim_reaper", "crystal_golem", "minotaur", "animated_armor"]}
	]
}

# Resolve active spawning definitions
static func get_enemy_definitions(current_floor: int, current_branch: int) -> Array:
	var enemies = _get_enemy_map()
	var branch_key = current_branch
	if not SPAWN_TABLES.has(branch_key):
		branch_key = 99 # Default high-risk table
		
	var pool_list = SPAWN_TABLES[branch_key]
	var enemy_ids = []
	for entry in pool_list:
		if current_floor <= entry["floor_max"]:
			enemy_ids = entry["pool"]
			break
			
	var enemy_types = []
	for id in enemy_ids:
		if enemies.has(id):
			enemy_types.append(enemies[id])
			
	# Specific Floor Spawns (Mantis/Minotaur/Animated Armor at specific normal floors)
	if current_branch == 0:
		if current_floor >= 3 and current_floor <= 6 and enemies.has("giant_mantis"): enemy_types.append(enemies["giant_mantis"])
		if current_floor >= 3 and current_floor <= 8 and enemies.has("flame_scatterer"): enemy_types.append(enemies["flame_scatterer"])
		if current_floor >= 5 and current_floor <= 9:
			if enemies.has("minotaur"): enemy_types.append(enemies["minotaur"])
			if enemies.has("animated_armor"): enemy_types.append(enemies["animated_armor"])
			
	return enemy_types

static func get_npc_definitions(_current_floor: int) -> Array:
	var enemies = _get_enemy_map()
	return [
		enemies["wanderer_swordsman"],
		enemies["stray_mage"],
		enemies["villager"],
		enemies["merchant"],
		enemies["elder"],
		enemies["guard"]
	]

static func get_enemy_def(enemy_id: String) -> Dictionary:
	var enemies = _get_enemy_map()
	# Search by name property for backward compatibility
	for id in enemies:
		if enemies[id].name == enemy_id:
			return enemies[id]
	return {}

static func _get_enemy_map() -> Dictionary:
	if not _enemy_cache.is_empty():
		return _enemy_cache
	
	var loaded = _load_enemies_from_resources()
	var base_map = loaded if not loaded.is_empty() else ENEMIES.duplicate(true)
	
	# Inject "id" key into each enemy definition for easier referencing
	for id in base_map:
		if base_map[id] is Dictionary:
			base_map[id]["id"] = id
			
	_enemy_cache = base_map
	return _enemy_cache

static func _load_enemies_from_resources() -> Dictionary:
	var enemies = {}
	var dir = DirAccess.open(ENEMY_DATA_DIR)
	if dir == null:
		return enemies
	
	var files = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "tres":
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	
	for file in files:
		var resource = load(ENEMY_DATA_DIR + "/" + file)
		if resource is EnemyData and resource.id != "":
			enemies[resource.id] = resource.to_definition()
	return enemies

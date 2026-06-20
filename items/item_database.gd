class_name ItemDatabase
extends RefCounted

const ITEM_DATA_DIR = "res://items/data"

static func get_all_items() -> Array[BaseItem]:
	var resource_items = _load_items_from_resources()
	
	# Failsafe: if 'berry' was not loaded from resources, append it from fallback list
	var has_berry = false
	for item in resource_items:
		if item.id == "berry":
			has_berry = true
			break
	if not has_berry:
		var fallback_items = _get_fallback_items()
		for item in fallback_items:
			if item.id == "berry":
				resource_items.append(item)
				break
				
	if not resource_items.is_empty():
		return resource_items
	return _get_fallback_items()

static func _load_items_from_resources() -> Array[BaseItem]:
	var items: Array[BaseItem] = []
	var dir = DirAccess.open(ITEM_DATA_DIR)
	if dir == null:
		return items
	
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
		var resource = load(ITEM_DATA_DIR + "/" + file)
		if resource is BaseItem:
			items.append(resource.duplicate(true))
	return items

static func _get_fallback_items() -> Array[BaseItem]:
	var items: Array[BaseItem] = []
	
	items.append(create_item({"id": "rusty_sword", "name": "朽ちた剣", "type": -1, "w": 1, "h": 3, "desc": "長い年月により錆びついた剣。\n切れ味は期待できない。"}))
	items.back().attack = 3
	
	items.append(create_item({"id": "leather_armor", "name": "旅人の革鎧", "type": -1, "w": 2, "h": 2, "desc": "基本的な防具。\n軽くて動きやすい。"}))
	items.back().defense = 2
	
	items.append(create_item({"id": "potion", "name": "癒やしの霊薬", "type": -1, "w": 1, "h": 1, "desc": "傷ついた体を癒やす神秘の薬。\nHPを回復する。", "heal": 10, "restore_hunger": 3}))
	
	# Ether (MP recovery)
	items.append(create_item({"id": "ether", "name": "エーテル", "type": -1, "w": 1, "h": 1, "desc": "魔力を回復する青い霊薬。\nMPを回復する。", "restore_mp": 10, "restore_hunger": 3}))
	
	# Berry (Hunger recovery from trees)
	items.append(create_item({"id": "berry", "name": "木の実", "type": -1, "w": 1, "h": 1, "desc": "森の木々から採れた小さな実。\nほんのり甘く、空腹を満たす。", "restore_hunger": 20}))

	# Gummy (Hunger recovery)
	items.append(create_item({"id": "gummy", "name": "グミ", "type": -1, "w": 1, "h": 1, "desc": "甘いお菓子。\n少しだけお腹が膨れる。", "restore_hunger": 30}))
	
	# Silver Gummy (Medium recovery)
	items.append(create_item({"id": "silver_gummy", "name": "銀のグミ", "type": -1, "w": 1, "h": 1, "desc": "上質な素材で作られたグミ。\n空腹を大いに満たす。", "restore_hunger": 60}))
	
	# Golden Gummy (Full recovery)
	items.append(create_item({"id": "golden_gummy", "name": "黄金のグミ", "type": -1, "w": 1, "h": 1, "desc": "光り輝く伝説のグミ。\n空腹と体力を完全に回復する。", "restore_hunger": 100, "heal": 50}))
	
	items.append(create_item({"id": "round_shield", "name": "丸盾", "type": -1, "w": 2, "h": 2, "desc": "木製の簡素な盾。\n最低限の身を守るのに役立つ。"}))
	items.back().defense = 2
	
	items.append(create_item({"id": "long_sword", "name": "鋼の長剣", "type": -1, "w": 1, "h": 4, "desc": "標準的な長さの剣。\n扱いやすく威力もそこそこ。"}))
	items.back().attack = 6
	
	items.append(create_item({"id": "ring", "name": "ただの指輪", "type": -1, "w": 1, "h": 1, "desc": "きらりと光る指輪。\n特に効果はないようだ。"}))
	items.back().defense = 1
	
	items.append(create_item({"id": "life_ring", "name": "命の指輪", "type": -1, "w": 1, "h": 1, "desc": "生命力が溢れてくる指輪。\n最大HPが増加する。"}))
	items.back().max_hp = 5
	
	items.append(create_item({"id": "hunter_ring", "name": "狩人の指輪", "type": -1, "w": 1, "h": 1, "desc": "狩猟本能を高める指輪。\n草むらでの会心率が上がる。", "effects": {"crit_in_grass": true}}))
	items.back().dexterity = 1
	
	# New L-shaped item
	var l_shape = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]
	items.append(create_item({"id": "l_armor", "name": "異形の鎧", "type": -1, "shape": l_shape, "desc": "奇妙な形状の鎧。\n装備するには工夫が必要だ。"}))
	items.back().defense = 3
 
	# New Cross-shaped item
	var cross_shape = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]
	items.append(create_item({"id": "cross_shield", "name": "聖騎士の盾", "type": -1, "shape": cross_shape, "desc": "十字の形をした神聖な盾。\n高い防御力を誇る。"}))
	items.back().defense = 4

	# Corner-shaped items
	var ge_shape = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)]
	items.append(create_item({"id": "ge_claw", "name": "鉤爪左", "type": -1, "shape": ge_shape, "desc": "[武器] 曲がった鉤爪を左手に固定する武具。\n角を引っ掛けるように斬りつけ、攻撃と器用さが少し上がる。"}))
	items.back().attack = 1
	items.back().dexterity = 1

	var mirrored_ge_shape: Array[Vector2i] = []
	for cell in ge_shape:
		mirrored_ge_shape.append(Vector2i(1 - cell.x, cell.y))
	items.append(create_item({"id": "mirrored_ge_claw", "name": "鉤爪右", "type": -1, "shape": mirrored_ge_shape, "desc": "[武器] 曲がった鉤爪を右手に固定する武具。\n反対向きの角で敵を絡め取り、攻撃と器用さが少し上がる。"}))
	items.back().attack = 1
	items.back().dexterity = 1
	
	# Fire Sword (Burn effect)
	items.append(create_item({
		"id": "fire_sword", 
		"name": "炎の魔剣", 
		"type": -1, 
		"w": 1, 
		"h": 3, 
		"desc": "炎を纏った魔剣。\n攻撃時、敵を炎上させることがある。",
		"effects": {
			"burn": {
				"chance": 0.3,
				"min_duration": 3,
				"max_duration": 10,
				"damage": 1
			}
		}
	}))
	items.back().attack = 3
	
	# --- New Items ---
	
	# High Potion
	items.append(create_item({"id": "high_potion", "name": "上級霊薬", "type": -1, "w": 1, "h": 1, "desc": "高度な調合で作られた霊薬。\nHPを大きく回復する。", "heal": 30, "restore_hunger": 3}))
	
	# High Ether (Large MP recovery)
	items.append(create_item({"id": "high_ether", "name": "ハイエーテル", "type": -1, "w": 1, "h": 1, "desc": "高純度の魔力を含む霊薬。\nMPを大きく回復する。", "restore_mp": 30, "restore_hunger": 3}))
	
	# Scroll of Teleportation
	items.append(create_item({"id": "scroll_teleport", "name": "転移の巻物", "type": -1, "w": 1, "h": 1, "desc": "空間を歪める魔力が込められた巻物。\nランダムな場所へ転移する。"}))
	
	# Scroll of Magic Mapping
	items.append(create_item({"id": "scroll_mapping", "name": "千里眼の巻物", "type": -1, "w": 1, "h": 1, "desc": "フロアの構造を見通す巻物。\nマップ全体を明らかにする。"}))
	
	# Potion of Strength
	items.append(create_item({"id": "potion_str", "name": "怪力の薬", "type": -1, "w": 1, "h": 1, "desc": "飲むと筋肉が隆起する薬。\n力が永続的に上昇する。"}))

	# Warp Grass
	items.append(create_item({"id": "warp_grass", "name": "飛び草", "type": -1, "w": 1, "h": 1, "desc": "食べるとどこかへ飛んでいく草。\n敵に投げつけると...？"}))
	
	# --- Monster Parts (Grafting System) ---
	
	# Slime Leg (Allows Swimming)
	items.append(create_item({
		"id": "slime_leg",
		"name": "スライムの足形",
		"type": -1,
		"w": 2,
		"h": 1,
		"desc": "[足] 粘液状の不定形な足。\n水上を移動可能になる。\n付与スキル: 酸の水溜まり",
		"effects": { "can_swim": true },
		"granted_skills": ["acid_puddle"]
	}))
	items.back().defense = 1
	
	# Minotaur Horn (Knockback)
	items.append(create_item({
		"id": "minotaur_horn",
		"name": "牛頭鬼の角",
		"type": -1,
		"w": 1,
		"h": 2,
		"desc": "[頭] 荒々しい猛牛の角。\n攻撃に吹き飛ばし効果を追加。\n付与スキル: ブルラッシュ",
		"effects": { "knockback": true },
		"granted_skills": ["charge"]
	}))
	items.back().attack = 3
	
	# Goblin Arm (DEX Boost)
	items.append(create_item({
		"id": "goblin_arm",
		"name": "小鬼の腕",
		"type": -1,
		"w": 1,
		"h": 2,
		"desc": "[腕] 緑色の細い腕。\n器用さが上昇する。\n付与スキル: 強奪",
		"granted_skills": ["mug"]
	}))
	items.back().attack = 1
	items.back().dexterity = 2
	
	# Zakomushi Carapace (Defense)
	items.append(create_item({
		"id": "zakomushi_shell",
		"name": "雑魚虫の殻",
		"type": -1,
		"h": 2,
		"desc": "[体] 硬質な蟲の甲殻。\n防御力がある。",
	}))
	items.back().defense = 3
	
	# Spider Leg (Web Shot)
	items.append(create_item({
		"id": "spider_leg",
		"name": "土蜘蛛の脚",
		"type": -1,
		"w": 1,
		"h": 2,
		"desc": "[足] 毛が生えた不気味な脚。\n付与スキル: 蜘蛛の糸",
		"granted_skills": ["web_shot"]
	}))
	items.back().dexterity = 3
	
	# Spark Core (Lightning chain on Water)
	items.append(create_item({
		"id": "spark_core",
		"name": "雷鳴の核",
		"type": -1,
		"w": 1,
		"h": 1,
		"desc": "[核] 電気を帯びたスライムの核。\n雷耐性を得る。\n水の上で攻撃すると周囲 of 敵に雷が連鎖する。\n付与スキル: 紫電",
		"effects": { "electric_resist": true, "spark_core_effect": true },
		"granted_skills": ["lightning"]
	}))
	items.back().intelligence = 2
	
	# Ranged Weapon
	items.append(create_item({
		"id": "wooden_bow",
		"name": "木の弓",
		"type": -1, # Weapon type?
		"w": 1,
		"h": 3,
		"desc": "[武器] シンプルな木の弓。\n遠くの敵を攻撃できる。\n(Fキーで射撃 / クールタイム1ターン)",
		"effects": { "range": 6, "is_ranged": true, "cooldown": 2 }
	}))
	items.back().attack = 2
	
	# Pistol (Full Reload)
	items.append(create_item({
		"id": "pistol",
		"name": "ピストル",
		"type": -1,
		"w": 1,
		"h": 1,
		"desc": "[武器] 標準的な自動拳銃。\nリロードで即座に全弾補充できる。\n(Fキーで射撃 / 弾倉10発 / Rキーでリロード)",
		"effects": { "range": 6, "is_ranged": true, "magazine_size": 10, "reload_type": "full", "cooldown": 0 }
	}))
	items.back().attack = 3
 
	# Magnum Gun
	items.append(create_item({
		"id": "magnum",
		"name": "マグナム",
		"type": -1,
		"w": 2,
		"h": 1,
		"desc": "[武器] 強力な拳銃。\n6発まで連続で撃てる。\n(Fキーで射撃 / 弾倉6発 / Rキーでリロード)",
		"effects": { "range": 8, "is_ranged": true, "magazine_size": 6, "cooldown": 0 }
	}))
	items.back().attack = 5  # 8 -> 5 にナーフ
	
	# Class Starter Equipment
	# Plate Armor (Warrior)
	items.append(create_item({
		"id": "plate_armor",
		"name": "プレートアーマー",
		"type": -1,
		"w": 2,
		"h": 3,
		"desc": "[防具] 重厚な金属の鎧。\nウォリアーの初期装備。\n最大HPが上昇する。"
	}))
	items.back().defense = 2  # 5 -> 2
	items.back().max_hp = 2
	
	# Mage Robe
	items.append(create_item({
		"id": "mage_robe",
		"name": "魔法のローブ",
		"type": -1,
		"w": 2,
		"h": 3,
		"desc": "[防具] 魔力を高めるローブ。\nメイジの初期装備。"
	}))
	items.back().defense = 1  # 2 -> 1
	items.back().intelligence = 2  # 3 -> 2
	items.back().max_mp = 3  # 5 -> 3
	
	# Swimsuit (Swimmer)
	items.append(create_item({
		"id": "swimsuit",
		"name": "競泳水着",
		"type": -1,
		"w": 2,
		"h": 2,
		"desc": "[防具] 水泳に特化した装備。\nスイマーの初期装備。\n水上移動が可能。",
		"effects": { "can_swim": true }
	}))
	items.back().defense = 0
	items.back().dexterity = 1
 
	# Thief Cloak (Rogue)
	items.append(create_item({
		"id": "thief_cloak",
		"name": "盗賊のマント",
		"type": -1,
		"w": 2,
		"h": 2,
		"desc": "[防具] 暗闇に溶け込む黒いマント。\nローグの初期装備。\n身軽で器用さが上昇する。"
	}))
	items.back().defense = 1
	items.back().dexterity = 2
	
	return items

static func create_item(p_args: Dictionary) -> BaseItem:
	var id: String = p_args.get("id", "")
	var item_name: String = p_args.get("name", "")
	var equipment_type: int = p_args.get("type", -1)
	var w: int = p_args.get("w", 1)
	var h: int = p_args.get("h", 1)
	var desc: String = p_args.get("desc", "")
	var shape = p_args.get("shape", null)
	var effects = p_args.get("effects", {})
	var granted_skills = p_args.get("granted_skills", [])
	
	var item = BaseItem.new(id, item_name, null, equipment_type, w, h, desc, shape)
	item.effects = effects
	item.granted_skills.append_array(granted_skills)
	
	# Handle direct stat assignments from args if provided (convenience)
	item.attack = p_args.get("attack", 0)
	item.defense = p_args.get("defense", 0)
	item.strength = p_args.get("strength", 0)
	item.dexterity = p_args.get("dexterity", 0)
	item.intelligence = p_args.get("intelligence", 0)
	item.max_hp = p_args.get("max_hp", 0)
	item.max_mp = p_args.get("max_mp", 0)
	item.heal = p_args.get("heal", 0)
	item.restore_mp = p_args.get("restore_mp", 0)
	item.restore_hunger = p_args.get("restore_hunger", 0)
	
	return item

static func get_random_item(floor_depth: int = 1) -> BaseItem:
	var items = get_all_items()
	
	# Monster part IDs that should only drop from enemies
	var monster_parts = ["slime_leg", "minotaur_horn", "goblin_arm", "spider_leg", "spark_core"]
	
	# Filter based on floor and type
	var spawnable_items = []
	for item in items:
		# Exclude monster parts from floor loot
		if monster_parts.has(item.id):
			continue
			
		# Pistol: Deep floors only (e.g. 5+)
		if item.id == "pistol" and floor_depth < 5:
			continue
			
		spawnable_items.append(item)
	
	if spawnable_items.is_empty():
		return EquipmentGenerator.enhance_item(items.pick_random(), floor_depth)
	
	# Create weighted pool
	var weighted_pool = []
	for item in spawnable_items:
		weighted_pool.append(item)
		# Slightly increase spawn rate for Gummy family
		if "gummy" in item.id:
			weighted_pool.append(item) # Add one more time (2x weight)
			
	return EquipmentGenerator.enhance_item(weighted_pool.pick_random(), floor_depth)

static func get_beginner_item(floor_depth: int = 1) -> BaseItem:
	var items = get_all_items()
	
	var beginner_friendly_ids = [
		"rusty_sword", "leather_armor", "round_shield", "ring", "life_ring", "hunter_ring",
		"potion", "ether", "gummy", "silver_gummy", "wooden_bow"
	]
	
	var spawnable_items = []
	for item in items:
		if beginner_friendly_ids.has(item.id):
			spawnable_items.append(item)
			
	if spawnable_items.is_empty():
		return get_random_item(floor_depth)
		
	var weighted_pool = []
	for item in spawnable_items:
		weighted_pool.append(item)
		if item.id in ["potion", "gummy", "ether"]:
			weighted_pool.append(item)
			weighted_pool.append(item)
			
	return EquipmentGenerator.enhance_item(weighted_pool.pick_random(), floor_depth)

static func get_item_by_id(item_id: String) -> BaseItem:
	var items = get_all_items()
	for item in items:
		if item.id == item_id:
			return item
	return null

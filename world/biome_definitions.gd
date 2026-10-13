class_name BiomeDefinitions
extends RefCounted

const WorldCell = preload("res://world/map_definitions.gd").WorldCell

# Biome properties for world generation and gameplay
static var BiomeData: Dictionary = _init_biome_data()

static func _init_biome_data() -> Dictionary:
	return {
		WorldCell.SEA: {
		"name": "海",
		"color": Color(0.2, 0.4, 0.8),
		"elevation_range": [0.0, 0.1],
		"moisture_range": [0.8, 1.0],
		"temperature_range": [0.3, 0.9],
		"walkable": false,
		"transition_biomes": [WorldCell.COAST, WorldCell.WETLAND],
		"enemy_types": ["water_monster", "fish"],
		"resources": ["fish", "seaweed"],
		"movement_cost": 0,
		"visibility_modifier": 0.0,
		"danger_level": 3,
		"special_events": ["shipwreck", "storm"],
		"poi_types": ["underwater_cave", "sunken_treasure"],
		"rare_resources": ["pearl", "coral"]
	},
	WorldCell.GRASS: {
		"name": "草原",
		"color": Color(0.4, 0.7, 0.3),
		"elevation_range": [0.1, 0.4],
		"moisture_range": [0.3, 0.7],
		"temperature_range": [0.4, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASSLAND_EDGE, WorldCell.FOREST, WorldCell.DRYLAND],
		"enemy_types": ["wolf", "boar", "goblin"],
		"resources": ["herbs", "berries", "wood"],
		"movement_cost": 1,
		"visibility_modifier": 0.0,
		"danger_level": 1,
		"special_events": ["traveling_merchant", "wild_horses"],
		"poi_types": ["abandoned_farm", "hermit_cottage"],
		"rare_resources": ["rare_herbs", "honey"]
	},
	WorldCell.FOREST: {
		"name": "森林",
		"color": Color(0.2, 0.5, 0.2),
		"elevation_range": [0.2, 0.5],
		"moisture_range": [0.5, 0.8],
		"temperature_range": [0.3, 0.7],
		"walkable": true,
		"transition_biomes": [WorldCell.FOREST_EDGE, WorldCell.DEEP_FOREST, WorldCell.WETLAND],
		"enemy_types": ["wolf", "bear", "forest_goblin", "spider"],
		"resources": ["wood", "herbs", "mushrooms", "berries"],
		"movement_cost": 1.2,
		"visibility_modifier": -0.2,
		"danger_level": 2,
		"special_events": ["hunting_party", "forest_fire"],
		"poi_types": ["ancient_tree", "bandit_camp"],
		"rare_resources": ["ancient_wood", "rare_mushrooms"]
	},
	WorldCell.DEEP_FOREST: {
		"name": "深い森林",
		"color": Color(0.1, 0.35, 0.15),
		"elevation_range": [0.2, 0.5],
		"moisture_range": [0.6, 0.9],
		"temperature_range": [0.3, 0.6],
		"walkable": true,
		"transition_biomes": [WorldCell.FOREST, WorldCell.SWAMP],
		"enemy_types": ["bear", "spider", "treant", "forest_spirit"],
		"resources": ["rare_wood", "rare_herbs", "mushrooms"],
		"movement_cost": 1.5,
		"visibility_modifier": -0.4,
		"danger_level": 3,
		"special_events": ["druid_circle", "beast_migration"],
		"poi_types": ["hidden_grove", "ancient_ruins"],
		"rare_resources": ["enchanted_wood", "spirit_essence"]
	},
	WorldCell.CONIFER_FOREST: {
		"name": "針葉樹林",
		"color": Color(0.15, 0.4, 0.18),
		"elevation_range": [0.3, 0.6],
		"moisture_range": [0.4, 0.7],
		"temperature_range": [0.1, 0.4],
		"walkable": true,
		"transition_biomes": [WorldCell.FOREST, WorldCell.SNOWLAND, WorldCell.HIGHLAND],
		"enemy_types": ["wolf", "bear", "snow_goblin"],
		"resources": ["pine_wood", "resin", "winter_herbs"],
		"movement_cost": 1.3,
		"visibility_modifier": -0.25,
		"danger_level": 2
	},
	WorldCell.DRYLAND: {
		"name": "乾燥地帯",
		"color": Color(0.6, 0.5, 0.3),
		"elevation_range": [0.15, 0.45],
		"moisture_range": [0.1, 0.35],
		"temperature_range": [0.5, 0.9],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.DESERT, WorldCell.ROCKLAND],
		"enemy_types": ["scorpion", "lizard", "desert_goblin"],
		"resources": ["dry_herbs", "cactus", "minerals"],
		"movement_cost": 1.1,
		"visibility_modifier": 0.1,
		"danger_level": 2
	},
	WorldCell.DESERT: {
		"name": "砂漠",
		"color": Color(0.8, 0.7, 0.4),
		"elevation_range": [0.1, 0.4],
		"moisture_range": [0.0, 0.2],
		"temperature_range": [0.6, 1.0],
		"walkable": true,
		"transition_biomes": [WorldCell.DESERT_EDGE, WorldCell.DRYLAND, WorldCell.ROCKLAND],
		"enemy_types": ["scorpion", "giant_worm", "sand_demon"],
		"resources": ["oasis_water", "rare_minerals", "cactus"],
		"movement_cost": 1.4,
		"visibility_modifier": 0.2,
		"danger_level": 3,
		"special_events": ["sandstorm", "mirage"],
		"poi_types": ["hidden_oasis", "buried_tomb"],
		"rare_resources": ["ancient_artifacts", "desert_glass"]
	},
	WorldCell.ROCKLAND: {
		"name": "岩場",
		"color": Color(0.5, 0.45, 0.4),
		"elevation_range": [0.3, 0.6],
		"moisture_range": [0.2, 0.5],
		"temperature_range": [0.3, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.MOUNTAIN, WorldCell.DRYLAND, WorldCell.DESERT],
		"enemy_types": ["rock_golem", "lizard", "eagle"],
		"resources": ["stone", "minerals", "ore"],
		"movement_cost": 1.3,
		"visibility_modifier": 0.0,
		"danger_level": 2
	},
	WorldCell.WETLAND: {
		"name": "湿地",
		"color": Color(0.35, 0.55, 0.35),
		"elevation_range": [0.05, 0.25],
		"moisture_range": [0.7, 0.95],
		"temperature_range": [0.4, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.SWAMP, WorldCell.GRASS, WorldCell.COAST],
		"enemy_types": ["frog", "swamp_goblin", "water_snake"],
		"resources": ["water_herbs", "reeds", "fish"],
		"movement_cost": 1.4,
		"visibility_modifier": -0.1,
		"danger_level": 2
	},
	WorldCell.SWAMP: {
		"name": "沼地",
		"color": Color(0.25, 0.4, 0.25),
		"elevation_range": [0.0, 0.2],
		"moisture_range": [0.85, 1.0],
		"temperature_range": [0.3, 0.7],
		"walkable": true,
		"transition_biomes": [WorldCell.SWAMP_EDGE, WorldCell.WETLAND, WorldCell.DEEP_FOREST],
		"enemy_types": ["swamp_monster", "poison_frog", "witch"],
		"resources": ["rare_herbs", "toadstools", "swamp_wood"],
		"movement_cost": 1.8,
		"visibility_modifier": -0.3,
		"danger_level": 4,
		"special_events": ["witch_ritual", "toxic_fog"],
		"poi_types": ["witch_hut", "sunken_shrine"],
		"rare_resources": ["poison_gland", "swamp_pearl"]
	},
	WorldCell.HIGHLAND: {
		"name": "高地",
		"color": Color(0.5, 0.55, 0.45),
		"elevation_range": [0.5, 0.7],
		"moisture_range": [0.3, 0.6],
		"temperature_range": [0.2, 0.5],
		"walkable": true,
		"transition_biomes": [WorldCell.MOUNTAIN, WorldCell.CONIFER_FOREST, WorldCell.ROCKLAND],
		"enemy_types": ["eagle", "mountain_goat", "highland_goblin"],
		"resources": ["mountain_herbs", "stone", "ore"],
		"movement_cost": 1.2,
		"visibility_modifier": 0.15,
		"danger_level": 2
	},
	WorldCell.MOUNTAIN: {
		"name": "山岳",
		"color": Color(0.4, 0.4, 0.45),
		"elevation_range": [0.6, 0.9],
		"moisture_range": [0.2, 0.5],
		"temperature_range": [0.1, 0.4],
		"walkable": false,
		"transition_biomes": [WorldCell.HIGHLAND, WorldCell.SNOWLAND, WorldCell.ROCKLAND],
		"enemy_types": ["eagle", "dragon", "golem"],
		"resources": ["rare_ore", "crystals", "stone"],
		"movement_cost": 0,
		"visibility_modifier": 0.3,
		"danger_level": 4,
		"special_events": ["dragon_sighting", "avalanche"],
		"poi_types": ["dragon_lair", "ancient_mine"],
		"rare_resources": ["dragon_scale", "mithril_ore"]
	},
	WorldCell.SNOWLAND: {
		"name": "雪原",
		"color": Color(0.85, 0.9, 0.95),
		"elevation_range": [0.4, 0.7],
		"moisture_range": [0.4, 0.7],
		"temperature_range": [0.0, 0.2],
		"walkable": true,
		"transition_biomes": [WorldCell.SNOWLAND_EDGE, WorldCell.CONIFER_FOREST, WorldCell.FROZEN_LAND],
		"enemy_types": ["yeti", "ice_wolf", "frost_goblin"],
		"resources": ["ice_crystals", "winter_herbs", "snow_wood"],
		"movement_cost": 1.5,
		"visibility_modifier": 0.1,
		"danger_level": 3,
		"special_events": ["blizzard", "aurora"],
		"poi_types": ["ice_cave", "frozen_ruins"],
		"rare_resources": ["frost_gem", "ancient_ice"]
	},
	WorldCell.FROZEN_LAND: {
		"name": "凍結地帯",
		"color": Color(0.7, 0.8, 0.9),
		"elevation_range": [0.3, 0.6],
		"moisture_range": [0.5, 0.8],
		"temperature_range": [0.0, 0.1],
		"walkable": true,
		"transition_biomes": [WorldCell.SNOWLAND, WorldCell.SEA, WorldCell.SWAMP],
		"enemy_types": ["ice_golem", "frost_wraith", "polar_bear"],
		"resources": ["pure_ice", "frozen_herbs", "rare_crystals"],
		"movement_cost": 1.7,
		"visibility_modifier": 0.15,
		"danger_level": 4
	},
	WorldCell.COAST: {
		"name": "海岸",
		"color": Color(0.6, 0.7, 0.5),
		"elevation_range": [0.05, 0.15],
		"moisture_range": [0.6, 0.85],
		"temperature_range": [0.4, 0.85],
		"walkable": true,
		"transition_biomes": [WorldCell.SEA, WorldCell.GRASS, WorldCell.WETLAND],
		"enemy_types": ["crab", "seagull", "coast_goblin"],
		"resources": ["shellfish", "seaweed", "sand"],
		"movement_cost": 1.1,
		"visibility_modifier": 0.05,
		"danger_level": 1
	},
	WorldCell.RIVERBANK: {
		"name": "河川周辺",
		"color": Color(0.4, 0.6, 0.4),
		"elevation_range": [0.05, 0.2],
		"moisture_range": [0.7, 0.95],
		"temperature_range": [0.3, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.FOREST, WorldCell.WETLAND],
		"enemy_types": ["frog", "river_fish", "otter"],
		"resources": ["river_fish", "water_herbs", "reeds"],
		"movement_cost": 1.2,
		"visibility_modifier": 0.0,
		"danger_level": 1
	},
	WorldCell.LAKESHORE: {
		"name": "湖沼周辺",
		"color": Color(0.35, 0.55, 0.4),
		"elevation_range": [0.05, 0.15],
		"moisture_range": [0.75, 0.98],
		"temperature_range": [0.35, 0.75],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.FOREST, WorldCell.WETLAND],
		"enemy_types": ["frog", "lake_fish", "water_bird"],
		"resources": ["lake_fish", "water_herbs", "fresh_water"],
		"movement_cost": 1.1,
		"visibility_modifier": 0.0,
		"danger_level": 1
	},
	WorldCell.WASTELAND: {
		"name": "荒廃地",
		"color": Color(0.4, 0.35, 0.3),
		"elevation_range": [0.15, 0.4],
		"moisture_range": [0.1, 0.3],
		"temperature_range": [0.4, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.DRYLAND, WorldCell.ROCKLAND, WorldCell.DESERT],
		"enemy_types": ["undead", "corrupted_beast", "wraith"],
		"resources": ["corrupted_ore", "dark_herbs", "ashes"],
		"movement_cost": 1.3,
		"visibility_modifier": -0.1,
		"danger_level": 3
	},
	WorldCell.ANOMALY_ZONE: {
		"name": "異常地帯",
		"color": Color(0.6, 0.2, 0.6),
		"elevation_range": [0.1, 0.6],
		"moisture_range": [0.2, 0.8],
		"temperature_range": [0.2, 0.8],
		"walkable": true,
		"transition_biomes": [],
		"enemy_types": ["void_beast", "anomaly_entity", "eldritch_horror"],
		"resources": ["void_crystals", "anomaly_essence", "reality_shards"],
		"movement_cost": 1.5,
		"visibility_modifier": -0.5,
		"danger_level": 5,
		"special_events": ["reality_tear", "dimensional_rift"],
		"poi_types": ["void_portal", "alien_structure"],
		"rare_resources": ["reality_core", "void_essence"]
	},
	# Transition zones
	WorldCell.GRASSLAND_EDGE: {
		"name": "草原の端",
		"color": Color(0.45, 0.65, 0.35),
		"elevation_range": [0.1, 0.4],
		"moisture_range": [0.25, 0.65],
		"temperature_range": [0.4, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.FOREST, WorldCell.DRYLAND],
		"enemy_types": ["wolf", "boar"],
		"resources": ["herbs", "berries"],
		"movement_cost": 1,
		"visibility_modifier": 0.0,
		"danger_level": 1
	},
	WorldCell.FOREST_EDGE: {
		"name": "森林の端",
		"color": Color(0.25, 0.5, 0.25),
		"elevation_range": [0.2, 0.5],
		"moisture_range": [0.45, 0.75],
		"temperature_range": [0.3, 0.7],
		"walkable": true,
		"transition_biomes": [WorldCell.FOREST, WorldCell.GRASS, WorldCell.DEEP_FOREST],
		"enemy_types": ["wolf", "forest_goblin"],
		"resources": ["wood", "herbs"],
		"movement_cost": 1.1,
		"visibility_modifier": -0.1,
		"danger_level": 1
	},
	WorldCell.DESERT_EDGE: {
		"name": "砂漠の端",
		"color": Color(0.7, 0.6, 0.4),
		"elevation_range": [0.1, 0.4],
		"moisture_range": [0.15, 0.35],
		"temperature_range": [0.5, 0.9],
		"walkable": true,
		"transition_biomes": [WorldCell.DESERT, WorldCell.DRYLAND, WorldCell.ROCKLAND],
		"enemy_types": ["scorpion", "lizard"],
		"resources": ["dry_herbs", "cactus"],
		"movement_cost": 1.2,
		"visibility_modifier": 0.15,
		"danger_level": 2
	},
	WorldCell.SNOWLAND_EDGE: {
		"name": "雪原の端",
		"color": Color(0.8, 0.85, 0.9),
		"elevation_range": [0.35, 0.65],
		"moisture_range": [0.35, 0.65],
		"temperature_range": [0.15, 0.3],
		"walkable": true,
		"transition_biomes": [WorldCell.SNOWLAND, WorldCell.CONIFER_FOREST, WorldCell.HIGHLAND],
		"enemy_types": ["ice_wolf", "frost_goblin"],
		"resources": ["winter_herbs", "ice_crystals"],
		"movement_cost": 1.3,
		"visibility_modifier": 0.05,
		"danger_level": 2
	},
	WorldCell.SWAMP_EDGE: {
		"name": "沼地の端",
		"color": Color(0.3, 0.45, 0.3),
		"elevation_range": [0.05, 0.25],
		"moisture_range": [0.75, 0.9],
		"temperature_range": [0.3, 0.7],
		"walkable": true,
		"transition_biomes": [WorldCell.SWAMP, WorldCell.WETLAND, WorldCell.FOREST],
		"enemy_types": ["frog", "swamp_goblin"],
		"resources": ["water_herbs", "reeds"],
		"movement_cost": 1.5,
		"visibility_modifier": -0.15,
		"danger_level": 2
	},
	# Special locations
	WorldCell.VILLAGE: {
		"name": "村",
		"color": Color(0.7, 0.6, 0.4),
		"elevation_range": [0.1, 0.4],
		"moisture_range": [0.3, 0.7],
		"temperature_range": [0.4, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.FOREST, WorldCell.ROAD],
		"enemy_types": [],
		"resources": ["trade_goods", "supplies"],
		"movement_cost": 1,
		"visibility_modifier": 0.0,
		"danger_level": 0
	},
	WorldCell.DUNGEON: {
		"name": "ダンジョン",
		"color": Color(0.5, 0.3, 0.3),
		"elevation_range": [0.1, 0.5],
		"moisture_range": [0.2, 0.6],
		"temperature_range": [0.3, 0.7],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.FOREST, WorldCell.MOUNTAIN],
		"enemy_types": [],
		"resources": ["treasure", "artifacts"],
		"movement_cost": 1,
		"visibility_modifier": 0.0,
		"danger_level": 0
	},
	WorldCell.ROAD: {
		"name": "街道",
		"color": Color(0.6, 0.55, 0.4),
		"elevation_range": [0.1, 0.4],
		"moisture_range": [0.3, 0.6],
		"temperature_range": [0.4, 0.8],
		"walkable": true,
		"transition_biomes": [WorldCell.GRASS, WorldCell.FOREST, WorldCell.VILLAGE],
		"enemy_types": ["bandit", "highwayman"],
		"resources": [],
		"movement_cost": 0.8,
		"visibility_modifier": 0.1,
		"danger_level": 1
	}
}

static func get_biome_data(biome_type: int) -> Dictionary:
	if BiomeData.has(biome_type):
		return BiomeData[biome_type]
	return {}

static func get_biome_name(biome_type: int) -> String:
	var data = get_biome_data(biome_type)
	if data.has("name"):
		return data["name"]
	return "Unknown"

static func get_biome_color(biome_type: int) -> Color:
	var data = get_biome_data(biome_type)
	if data.has("color"):
		return data["color"]
	return Color(0.5, 0.5, 0.5)

static func is_walkable(biome_type: int) -> bool:
	var data = get_biome_data(biome_type)
	if data.has("walkable"):
		return data["walkable"]
	return true

static func get_movement_cost(biome_type: int) -> float:
	var data = get_biome_data(biome_type)
	if data.has("movement_cost"):
		return data["movement_cost"]
	return 1.0

static func get_danger_level(biome_type: int) -> int:
	var data = get_biome_data(biome_type)
	if data.has("danger_level"):
		return data["danger_level"]
	return 1

static func get_special_events(biome_type: int) -> Array:
	var data = get_biome_data(biome_type)
	if data.has("special_events"):
		return data["special_events"]
	return []

static func get_poi_types(biome_type: int) -> Array:
	var data = get_biome_data(biome_type)
	if data.has("poi_types"):
		return data["poi_types"]
	return []

static func get_rare_resources(biome_type: int) -> Array:
	var data = get_biome_data(biome_type)
	if data.has("rare_resources"):
		return data["rare_resources"]
	return []

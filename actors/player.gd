extends CharacterBody2D

const TILE_SIZE = 32  # 1タイルのサイズ（ピクセル）
const BASE_MAX_HP = 10  # 基本の最大HP
const BASE_MAX_MP = 5   # 基本の最大MP

@onready var camera = get_parent().get_node("Camera2D")  # カメラへの参照
@onready var light = $Light2D  # ライトへの参照

# ステータス
var max_hp: int = BASE_MAX_HP
var hp: int = BASE_MAX_HP
var max_mp: int = BASE_MAX_MP
var mp: int = BASE_MAX_MP
var sprite_offset = Vector2(16, 16) # Offset for centering sprite in tile
var _idle_tween: Tween
var _base_scale: Vector2 = Vector2.ONE
var max_hunger: int = 100
var hunger: int = 100

const HUNGER_WARNING_LEVEL: int = 30
const HUNGER_CRITICAL_LEVEL: int = 10
const HUNGER_DAMAGE_PER_TURN: int = 1

var strength: int = 1  # 力
var dexterity: int = 1  # 器用さ
var intelligence: int = 1  # 知力
var level: int = 1  # レベル
var gold: int = 0:  # 所持金
	set(value):
		var old_gold = gold
		gold = value
		if old_gold != value:
			_on_gold_changed(old_gold, value)
var exp: int = 0  # 現在の経験値
var exp_to_next_level: int = 10  # 次のレベルまでに必要な経験値
var hit_rate: float = 0.85 # Base hit chance (Accuracy)
var level_hp_bonus: int = 0 # Extra HP gained from leveling up
var initial_hp_bonus: int = 0 # Bonus from character creation
var level_mp_bonus: int = 0 
var initial_mp_bonus: int = 0
var _base_can_swim: bool = false # Ability to traverse water (Base)
var is_on_water: bool = false # Current terrain status
var is_in_grass: bool = false

var can_swim: bool:
	get:
		if _base_can_swim: return true
		return _check_equipment_effect("can_swim")

var has_knockback: bool:
	get:
		return _check_equipment_effect("knockback")

func is_using_swim_gear() -> bool:
	return _check_equipment_effect("can_swim")



# HP/MP自動回復
var turns_since_damage: int = 0  # ダメージを受けてからのターン数
const REGEN_TURN_THRESHOLD: int = 10  # 回復開始までのターン数
const MP_REGEN_TURN: int = 20 # MP自然回復に必要なターン数
var turn_counter: int = 0

# 装備関連
@onready var equipment_component: Node = $EquipmentComponent

const SkillDatabase = preload("res://skills/skill_database.gd")
var base_known_skills: Array[String] = []
var known_skills: Array[String] = [] 
var skill_cooldowns: Dictionary = {}
var ranged_weapon_cooldown: int = 0
var bonus_action_available: bool = false
var ranged_weapon_shots_fired: int = 0
var ammo_inventory: int = 20 # Ammo available for the current floor


func _get_equipment_stats() -> Dictionary:
	if equipment_component and equipment_component.has_method("get_total_stats"):
		return equipment_component.get_total_stats()
	return {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"max_mp": 0,
		"strength": 0,
		"dexterity": 0,
		"intelligence": 0
	}

func _get_hunger_attack_multiplier() -> float:
	var ratio = float(hunger) / max(1, max_hunger)
	if ratio >= 0.8:
		return 1.1
	elif ratio >= 0.5:
		return 1.0
	elif ratio >= 0.3:
		return 0.9
	else:
		return 0.8

func _get_hunger_defense_multiplier() -> float:
	var ratio = float(hunger) / max(1, max_hunger)
	if ratio >= 0.8:
		return 1.05
	elif ratio >= 0.5:
		return 1.0
	elif ratio >= 0.3:
		return 0.95
	else:
		return 0.9

# 攻撃力と防御力を計算するプロパティ
var attack_power: int:
	get:
		var equipment_stats = _get_equipment_stats()
		# 攻撃力 = (力 * 2) + 装備の攻撃力
		var total_str = strength + equipment_stats.strength
		var base_value = (total_str * 2) + equipment_stats.attack 
		return int(round(base_value * _get_hunger_attack_multiplier()))

var defense_power: int:
	get:
		var equipment_stats = _get_equipment_stats()
		# 防御力 = 装備の防御力 + 合計器用さの半分
		var total_dex = dexterity + equipment_stats.dexterity
		var base_value = equipment_stats.defense + (total_dex / 2)
		return int(round(base_value * _get_hunger_defense_multiplier()))

var crit_rate: float:
	get:
		# Base 5% + 1% per Dexterity point + Equipment Bonuses
		var base = 0.05
		var dex_bonus = float(dexterity) * 0.01
		
		var equipment_stats = _get_equipment_stats()
		# Add equipment dexterity to bonus? Or is it already in 'dexterity'?
		# 'dexterity' is base stat. Equipment adds separately usually.
		# But wait, equipment_stats.dexterity is added to DEF above.
		# Let's add equipment dex to crit too.
		var equip_dex_bonus = float(equipment_stats.dexterity) * 0.01
		var item_crit_bonus = float(equipment_stats.get("crit_bonus", 0.0))
		
		# Inventory Adjacency Bonuses
		var adj_bonus = 0.0
		if equipment_component and equipment_component.bag_data:
			adj_bonus = equipment_component.bag_data.get_total_crit_bonus()

		var organization_bonus = 0.0
		if equipment_component and equipment_component.equipment_data:
			organization_bonus = float(get_inventory_bonus_state().get("crit_bonus", 0.0))
			
		# Grass Critical Bonus
		var grass_bonus = 0.0
		if is_in_grass and _check_equipment_effect("crit_in_grass"):
			grass_bonus = 0.3 # +30% Crit in grass!
			
		return clamp(base + dex_bonus + equip_dex_bonus + item_crit_bonus + adj_bonus + organization_bonus + grass_bonus, 0.0, 1.0)

var penetration_rate: float:
	get:
		var equipment_stats = _get_equipment_stats()
		return clamp(float(equipment_stats.get("penetration_bonus", 0.0)), 0.0, 0.9)

func get_total_strength() -> int:
	var eq = _get_equipment_stats()
	return strength + eq.strength

func get_total_dexterity() -> int:
	var eq = _get_equipment_stats()
	return dexterity + eq.dexterity

func get_total_intelligence() -> int:
	var eq = _get_equipment_stats()
	return intelligence + eq.intelligence


func _ready():
	z_index = 10 # Ensure player is drawn above floor/stairs overlays
	add_to_group("player")
	add_to_group("entities")
	
	_load_class_sprite()
	
	# Apply Initial Stats from creation
	var gs = get_node_or_null("/root/GameState")
	if gs:
		strength = gs.initial_str
		dexterity = gs.initial_dex
		intelligence = gs.initial_int
		initial_hp_bonus = gs.initial_hp_bonus
		max_hp = BASE_MAX_HP + initial_hp_bonus
		hp = max_hp
		
		# MP Calculation: Base + Int bonus (e.g. +3 per Int over 1? Or just Int * 3. Let's do simple)
		initial_mp_bonus = 0 # Future expansion
		max_mp = BASE_MAX_MP + (intelligence * 2) 
		mp = max_mp
		
		_base_can_swim = gs.initial_can_swim
		
		# Reset internal level bonuses if any (though this is new game)
		level_hp_bonus = 0
		level_mp_bonus = 0
		
		# Set skills based on class
		base_known_skills = gs.initial_skills.duplicate()
	
	# Initialize skills
	_check_skill_learning()
	_update_known_skills()

	
	_start_idle_animation()
	
	# positionをTILE_SIZEの倍数にスナップさせる
	position = position.snapped(Vector2.ONE * TILE_SIZE)
	
	# 装備の変更を監視
	if equipment_component:
		# Wait for component to initialize if needed or directly access
		# Assuming child _ready runs first
		if equipment_component.equipment_data:
			equipment_component.equipment_data.grid_changed.connect(_on_equipment_grid_changed)
		
		# 初期装備を追加
		add_initial_equipment()

const ItemDatabase = preload("res://items/item_database.gd")

func add_initial_equipment():
	if not equipment_component:
		return
	
	# 初期装備を作成
	var items = ItemDatabase.get_all_items()
	
	# 全クラス共通: ポーション、銀のグミ、黄金のグミ、ランダムな指輪
	for item in items:
		if item.id == "potion":
			equipment_component.add_to_bag(item)
		elif item.id == "silver_gummy":
			equipment_component.add_to_bag(item)
		elif item.id == "golden_gummy":
			equipment_component.add_to_bag(item)
	
	# ランダムな指輪を装備（ただの指輪 or 命の指輪）
	var ring_ids = ["ring", "life_ring"]
	var selected_ring_id = ring_ids[randi() % ring_ids.size()]
	for item in items:
		if item.id == selected_ring_id:
			equipment_component.equip_item(item)
			break
	
	# クラス別初期装備
	var gs = get_node_or_null("/root/GameState")
	if gs:
		match gs.player_class:
			0: # Balanced
				# バランスは皮の鎧のみ
				for item in items:
					if item.id == "leather_armor":
						equipment_component.equip_item(item)
						break
			1: # Warrior
				# プレートアーマーを装備
				for item in items:
					if item.id == "plate_armor":
						equipment_component.equip_item(item)
						break
			2: # Rogue
				# ローグには弓を装備済みで開始
				for item in items:
					if item.id == "wooden_bow":
						equipment_component.equip_item(item)
						break
				# また、盗賊のマントも装備
				for item in items:
					if item.id == "thief_cloak":
						equipment_component.equip_item(item)
						break
			3: # Mage
				# メイジローブを装備
				for item in items:
					if item.id == "mage_robe":
						equipment_component.equip_item(item)
						break
			4: # Swimmer
				# 競泳水着を装備
				for item in items:
					if item.id == "swimsuit":
						equipment_component.equip_item(item)
						break
			99: # Debug
				# マグナム
				for item in items:
					if item.id == "magnum":
						equipment_component.equip_item(item)
						break
				# Г字型アイテム
				for item in items:
					if item.id == "ge_claw" or item.id == "mirrored_ge_claw":
						equipment_component.add_to_bag(item)
	
	# 初期スキル: ヒールを追加
	if (not gs or gs.player_class != -1) and not base_known_skills.has("heal"):
		base_known_skills.append("heal")
		_update_known_skills()



# 装備グリッドが変更されたときの処理
signal inventory_bonus_changed(bonus_data)

func _on_equipment_grid_changed():
	print("Equipment grid changed!")
	
	# 最大HPを更新 (基本HP + 初期ボーナス + レベルボーナス + 装備補正 + 力ボーナス[3につき1])
	var equipment_stats = equipment_component.get_total_stats()
	var total_str = strength + equipment_stats.strength
	var str_hp_bonus = int(total_str / 3)
	max_hp = BASE_MAX_HP + initial_hp_bonus + level_hp_bonus + equipment_stats.max_hp + str_hp_bonus
	
	# 最大MPを更新
	var stats_mp_bonus = equipment_stats.get("max_mp", 0)
	var total_int = intelligence + equipment_stats.intelligence
	max_mp = BASE_MAX_MP + level_mp_bonus + (total_int * 2) + stats_mp_bonus
	
	# 現在の数値を新しい最大値に合わせて調整
	hp = min(hp, max_hp)
	mp = min(mp, max_mp)
	
	# UIを更新
	if PlayerUi:
		PlayerUi.update_hp(hp, max_hp)
		PlayerUi.update_mp(mp, max_mp)
	
	# Calculate organization bonus
	hit_rate = 0.85
	
	var bonus = get_inventory_bonus_state()
	hit_rate += bonus.hit_bonus + float(equipment_stats.get("hit_bonus", 0.0))
	
	var total_atk = attack_power
	var total_def = defense_power
	var status_msg = bonus.message
	
	inventory_bonus_changed.emit(bonus)
	
	print("Stats Updated: HP: %d/%d, ATK: %d, DEF: %d%s" % [hp, max_hp, total_atk, total_def, status_msg])
	
	if has_node("/root/LogUI") and status_msg != "":
		get_node("/root/LogUI").add_log("装備変更: HP %d, 攻撃 %d, 防御 %d%s" % [max_hp, total_atk, total_def, status_msg], bonus.color)

	_update_known_skills()
	_update_ui_weapon()

func get_inventory_bonus_state() -> Dictionary:
	var cluster_count = equipment_component.equipment_data.get_cluster_count()
	var is_packed = equipment_component.equipment_data.is_tightly_packed()
	var density = equipment_component.equipment_data.get_packing_density()
	
	var result = {
		"state": "average",
		"message": "",
		"color": Color.WHITE,
		"crit_bonus": 0.0,
		"hit_bonus": 0.0
	}
	
	if cluster_count <= 1 and cluster_count > 0:
		if is_packed:
			# ◎ Excellent (Density 1.0)
			result.state = "perfect"
			result.message = " [◎完璧]: 会心+25% 命中+10%"
			result.color = Color(1.0, 0.84, 0.0) # Gold
			result.crit_bonus = 0.25
			result.hit_bonus = 0.1
		elif density >= 0.75:
			# 〇 Good (High Density)
			result.state = "good"
			result.message = " [〇良好]: 会心+15%"
			result.color = Color(0.3, 1.0, 0.3) # Green
			result.crit_bonus = 0.15
		else:
			# △ Average (Low Density, messy shape)
			result.state = "average"
			result.message = " [△整頓不足]: ボーナスなし"
			result.color = Color(0.8, 0.8, 0.8) # Gray
	elif cluster_count == 2:
		# △ Average (Split clusters)
		result.state = "average"
		result.message = " [△普通]: ボーナスなし"
		result.color = Color(0.8, 0.8, 0.8) # Gray
	elif cluster_count >= 3:
		# ✕ Bad
		result.state = "bad"
		result.message = " [✕散乱]: 命中-20%"
		result.color = Color(1.0, 0.3, 0.3) # Red
		result.hit_bonus = -0.2
		
	return result

func _check_skill_learning():
	var skill_requirements = {
		"fireball": {"level": 2, "str": 0, "dex": 0, "int": 10},
		"iceball": {"level": 3, "str": 0, "dex": 0, "int": 12},
		"helm_splitter": {"level": 3, "str": 10, "dex": 0, "int": 0},
		"super_seoi_nage": {"level": 5, "str": 11, "dex": 2, "int": 0},
		"freeze": {"level": 4, "str": 0, "dex": 0, "int": 11},
		"gale_thrust": {"level": 4, "str": 0, "dex": 10, "int": 0},
		"grass_snipe": {"level": 5, "str": 0, "dex": 11, "int": 0},
		"wall": {"level": 5, "str": 0, "dex": 15, "int": 14},
		"lightning": {"level": 5, "str": 0, "dex": 0, "int": 15},
		"blood_beam": {"level": 6, "str": 13, "dex": 0, "int": 9},
		"teleport": {"level": 6, "str": 0, "dex": 0, "int": 14},
		"cyclone_slash": {"level": 6, "str": 12, "dex": 9, "int": 0},
		"explosion": {"level": 8, "str": 0, "dex": 0, "int": 18},
		"collapse": {"level": 10, "str": 20, "dex": 0, "int": 20},
		"meteor": {"level": 12, "str": 0, "dex": 0, "int": 22}
	}
	
	var learned_any = false
	for skill_id in skill_requirements.keys():
		if base_known_skills.has(skill_id):
			continue
			
		var req = skill_requirements[skill_id]
		# 装備やバフを除いた生ステータスで判定
		if level >= req["level"] and strength >= req["str"] and dexterity >= req["dex"] and intelligence >= req["int"]:
			base_known_skills.append(skill_id)
			learned_any = true
			
			var skill_name = skill_id
			var skill_data = SkillDatabase.get_skill_by_id(skill_id)
			if not skill_data.is_empty():
				skill_name = skill_data.get("name", skill_id)
			
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("スキル「%s」を自然に習得した！" % skill_name, Color.CYAN)
				
	if learned_any:
		_update_known_skills()

func _update_known_skills():
	known_skills = base_known_skills.duplicate()
	
	if equipment_component and equipment_component.equipment_data:
		for item in equipment_component.equipment_data.items:
			if not item.granted_skills.is_empty():
				for skill_id in item.granted_skills:
					if not known_skills.has(skill_id):
						known_skills.append(skill_id)
						print("Skill granted from equipment: ", skill_id)
	
	print("Current Skills: ", known_skills)
	# Defer UI update to ensure PlayerUI is ready
	call_deferred("_update_skill_ui")

func _update_skill_ui():
	print("_update_skill_ui() called with skills: ", known_skills)
	var ui = get_node_or_null("/root/PlayerUi")  # Note: PlayerUi not PlayerUI
	if ui:
		print("PlayerUi found, calling update_skill_bar")
		if ui.has_method("update_skill_bar"):
			ui.update_skill_bar(known_skills, skill_cooldowns)
		else:
			print("ERROR: PlayerUi doesn't have update_skill_bar method!")
	else:
		print("ERROR: PlayerUi not found at /root/PlayerUi")

func get_on_hit_effects() -> Array:
	var effects_list = []
	if equipment_component and equipment_component.equipment_data:
		for item in equipment_component.equipment_data.items:
			if not item.effects.is_empty():
				effects_list.append(item.effects)
	return effects_list

func _check_equipment_effect(key: String) -> bool:
	if equipment_component and equipment_component.equipment_data:
		for item in equipment_component.equipment_data.items:
			if item.effects.has(key) and item.effects[key] == true:
				return true
	return false


var _move_tween: Tween

var is_moving: bool = false

func move_to_grid(target_grid: Vector2i, is_auto: bool = false):
	var target_pos = Vector2(target_grid) * TILE_SIZE
	var diff = target_pos - position
	position = target_pos # Strict Grid Alignment
	
	velocity = Vector2.ZERO
	
	# Visual smoothing
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		# Kill idle tween during movement
		if _idle_tween and _idle_tween.is_valid():
			_idle_tween.kill()
			
		sprite.position -= diff
		
		# Prevent huge visual lag trail during fast auto-move
		if is_auto and sprite.position.length() > TILE_SIZE:
			# Snap closer if trailing too far
			sprite.position = sprite.position.limit_length(TILE_SIZE)
		
		if _move_tween:
			_move_tween.kill()
		_move_tween = create_tween()
		
		is_moving = true
		var anim_time = 0.02 if is_auto else 0.12 # Faster for auto-move, slightly slower for manual bounce
		
		_move_tween.set_parallel(true)
		_move_tween.tween_property(sprite, "position", sprite_offset, anim_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_move_tween.tween_callback(func(): is_moving = false)
		
		if _base_scale.is_zero_approx() or _base_scale == Vector2.ONE:
			_base_scale = sprite.scale
			if _base_scale.is_zero_approx(): _base_scale = Vector2.ONE
			
		# Squash & Stretch walk bounce sequence
		var scale_tween = create_tween()
		if is_auto:
			scale_tween.tween_property(sprite, "scale", _base_scale * Vector2(0.9, 1.1), anim_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			scale_tween.tween_property(sprite, "scale", _base_scale, anim_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			var stretch_scale = _base_scale * Vector2(0.82, 1.22)
			var squash_scale = _base_scale * Vector2(1.22, 0.82)
			scale_tween.tween_property(sprite, "scale", stretch_scale, anim_time * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			scale_tween.tween_property(sprite, "scale", squash_scale, anim_time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			scale_tween.tween_property(sprite, "scale", _base_scale, anim_time * 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			
		scale_tween.tween_callback(_start_idle_animation)
		
	# Light
	var light = get_node_or_null("PointLight2D")
	if light:
		light.position -= diff
		var l_tween = create_tween()
		l_tween.tween_property(light, "position", Vector2(16, 16), 0.1)

# Deprecated wrapper for non-main callers if any
func move(direction: Vector2):
	var grid = Vector2i((position + (direction * TILE_SIZE)) / TILE_SIZE)
	move_to_grid(grid)



func take_damage(amount: int, attacker = null, elements = ["normal"], is_crit: bool = false):
	# Damage calculation is handled by the caller (Main), which accounts for defense & penetration.
	# We just apply the final amount.
	if typeof(elements) == TYPE_STRING:
		elements = [elements]
		
	var multiplier = 1.0
	for elem in elements:
		if elem == "electric":
			if _check_equipment_effect("electric_immune"):
				multiplier = 0.0
			elif _check_equipment_effect("electric_resist"):
				multiplier = 0.5
		elif elem == "fire":
			if _check_equipment_effect("fire_immune"):
				multiplier = 0.0
			elif _check_equipment_effect("fire_resist"):
				multiplier = 0.5
				
	var damage = max(0 if multiplier == 0.0 else 1, int(amount * multiplier))
	hp -= damage
	
	var main_p = get_parent()
	if main_p and main_p.has_method("_stop_auto_explore"):
		main_p._stop_auto_explore("ダメージを受けたため自動探索を停止しました。")
	
	if has_status_effect("sleep"):
		if randf() < 0.9:
			remove_status_effect("sleep")
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("攻撃を受けて目が覚めた！", Color.GREEN)
		else:
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("攻撃を受けたが眠り続けている...", Color.YELLOW)
	
	# ダメージを受けたので回復カウンターをリセット
	turns_since_damage = 0
	
	print("Player took ", damage, " damage. HP: ", hp, "/", max_hp)
	
	# --- Juicy Hit Feedback ---
	
	# Kill movement tween to prevent position desync during damage
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
		is_moving = false
		# Reset sprite position to correct offset
		var sprite = get_node_or_null("Sprite2D")
		if sprite:
			sprite.position = sprite_offset
	
	var sprite = get_node_or_null("Sprite2D")
	# 1. Hit Flash modulation (Intense Red HDR flash with safe reset)
	if sprite:
		# Kill any ongoing flash tween to avoid initial color corruption on consecutive hits
		if has_meta("flash_tween"):
			var old_tween = get_meta("flash_tween")
			if old_tween and old_tween.is_valid():
				old_tween.kill()
		
		# Base color dynamically calculated (accounting for grass transparency)
		var base_color = Color(1.0, 1.0, 1.0, 0.6 if is_in_grass else 1.0)
		
		# Set bright red/white hit color immediately
		sprite.modulate = Color(3.5, 0.4, 0.4) if not is_crit else Color(4.5, 0.2, 0.2)
		
		# Tween back to base color safely
		var flash_tween = create_tween()
		set_meta("flash_tween", flash_tween)
		flash_tween.tween_interval(0.04)
		flash_tween.tween_property(sprite, "modulate", base_color, 0.08)

	# 2. Micro-recoil (nudge away from attacker then snap back)
	if sprite and attacker:
		var orig_pos = sprite.position
		var recoil_dir = (position - attacker.position).normalized()
		if recoil_dir.is_zero_approx():
			recoil_dir = Vector2.DOWN
		var recoil_pos = orig_pos + recoil_dir * (8.0 if is_crit else 4.0)
		var recoil_tween = create_tween()
		recoil_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		recoil_tween.tween_property(sprite, "position", recoil_pos, 0.04)
		recoil_tween.tween_property(sprite, "position", orig_pos, 0.06)

	# 3. Screen shake trigger
	var main_node = get_parent()
	if main_node and main_node.has_method("shake_camera"):
		if is_crit:
			main_node.shake_camera(7.0, 0.22)
		else:
			main_node.shake_camera(3.0, 0.12)

	# 4. Spawn blood sparks particles
	if main_node and main_node.has_method("_spawn_skill_particles"):
		main_node._spawn_skill_particles(position + Vector2(16, 16), "hit_player", 0.4)

	# ---

	# Play Damage Sound
	var sound_file = "res://assets/sounds/damage.mp3"
	if ResourceLoader.exists(sound_file):
		var asp = AudioStreamPlayer.new()
		asp.stream = load(sound_file)
		add_child(asp)
		asp.finished.connect(asp.queue_free)
		asp.play()
	
	# Float Text
	var float_text = load("res://ui/floating_text.tscn").instantiate()
	float_text.position = Vector2(16, -16)
	
	var color = Color(1, 0.2, 0.2)
	if is_crit:
		color = Color(1.0, 0.8, 0.1) # Gold for heavy crit on player
		
	float_text.set_text(str(damage) + (" (会心!)" if is_crit else ""), color, is_crit)
	add_child(float_text)

	if hp <= 0:
		var gs = get_node_or_null("/root/GameState")
		if gs and gs.god_mode:
			hp = 1
			print("God Mode saved you!")
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("God Mode! 耐えた！", Color.MAGENTA)
		else:
			print("Player defeated!")
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("死んでしまった...", Color.RED)
			
			# Disable player processing
			set_process(false)
			set_physics_process(false)
			
			# Call deferred to avoid physics/logic conflict during frame
			_play_gameover_sound()
			_trigger_game_over.call_deferred()

func _play_gameover_sound():
	var sound_file = "res://assets/sounds/gameover.mp3"
	if ResourceLoader.exists(sound_file):
		var asp = AudioStreamPlayer.new()
		asp.stream = load(sound_file)
		# Add to root so it persists
		get_tree().root.add_child(asp)
		asp.finished.connect(asp.queue_free)
		asp.play()

func _trigger_game_over():
	# Simple restart for now, or load Game Over scene if we had one
	# Creating a simple Game Over overlay
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var color_rect = ColorRect.new()
	color_rect.color = Color(0, 0, 0, 0.8)
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(color_rect)
	
	var label = Label.new()
	label.text = "GAME OVER"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color.RED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(label)
	
	await get_tree().create_timer(2.0).timeout
	
	if get_tree():
		get_tree().change_scene_to_file("res://ui/start_menu.tscn")
	else:
		print("Error: SceneTree not available")


func heal(amount: int):
	var old_hp = hp
	hp = min(hp + amount, max_hp)
	var healed = hp - old_hp
	if healed > 0:
		print("Player healed ", healed)
		var float_text = load("res://ui/floating_text.tscn").instantiate()
		float_text.position = Vector2(16, -16)
		float_text.set_text("+" + str(healed), Color(0.3, 1.0, 0.3))
		add_child(float_text)
		
		# Particles
		_spawn_skill_particles(position + Vector2(16, 16), "heal", 0.6)
		
	# UIを更新
	if PlayerUi:
		PlayerUi.update_hp(hp, max_hp)

# 経験値を獲得する
func gain_exp(amount: int):
	exp += amount
	print("★ Player gained ", amount, " EXP! Total: ", exp, "/", exp_to_next_level)
	
	# ログにも表示
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("%d EXP獲得！" % amount, Color(0.5, 1.0, 1.0))
	
	
	# レベルアップチェック
	while exp >= exp_to_next_level:
		level_up()

# レベルアップ処理
func level_up():
	level += 1
	exp -= exp_to_next_level
	exp_to_next_level = int(exp_to_next_level * 1.5)  # 次のレベルに必要な経験値を1.5倍
	
	# ステータスアップ (Growth System)
	var gs = get_node_or_null("/root/GameState")
	var rates = {"str": 0.5, "dex": 0.5, "int": 0.5, "hp": 2.0}
	if gs:
		rates = gs.get_growth_rates(gs.player_class)
	
	# Handle fractional growth
	_accumulate_growth("str", rates.str)
	_accumulate_growth("dex", rates.dex)
	_accumulate_growth("int", rates.int)
	
	# Apply whole number increases
	strength += _get_accumulated_increase("str")
	dexterity += _get_accumulated_increase("dex")
	intelligence += _get_accumulated_increase("int")
	
	# HP Growth (Always meaningful even if fractional, so we can accumulate similarly or just floor it)
	# For HP, usually we get at least some. Let's use similar accumulator.
	_accumulate_growth("hp", rates.hp)
	level_hp_bonus += _get_accumulated_increase("hp")
	
	# Recalculate max HP with new bonus and current equipment
	var equipment_stats = _get_equipment_stats()
	max_hp = BASE_MAX_HP + initial_hp_bonus + level_hp_bonus + equipment_stats.max_hp
	hp = max_hp  # HPを全回復
	
	# MP Growth
	# INT contributes to MP directly (already handled in max_mp calc), but we can add a small flat bonus per level too
	level_mp_bonus += 1 
	
	# Recalculate Max MP
	var stats_mp_bonus = equipment_stats.get("max_mp", 0)
	var total_int = intelligence + equipment_stats.intelligence # Note: equipment_stats.intelligence might need to be added to base if we want it to scale MP? 
	# Actually, max_mp calculation should ideally be a property getter or helper method to avoid duplication.
	# But for now:
	max_mp = BASE_MAX_MP + level_mp_bonus + (total_int * 2) + stats_mp_bonus
	mp = max_mp # Restore MP
	
	print("Level Up! Now level ", level)
	print("Stats increased! HP: ", max_hp, " MP: ", max_mp, " STR: ", strength, " DEX: ", dexterity, " INT: ", intelligence)
	
	# --- Juicy Level Up Feedback ---

	# 1. Screen Shake
	var main_node = get_parent()
	if main_node and main_node.has_method("shake_camera"):
		main_node.shake_camera(8.0, 0.45)
		
	# 2. Golden Rising sparks
	if main_node and main_node.has_method("_spawn_skill_particles"):
		main_node._spawn_skill_particles(position + Vector2(16, 16), "levelup", 1.2)

	# 3. Gold/Yellow Screen Flash tint Overlay
	var flash_canvas = CanvasLayer.new()
	add_child(flash_canvas)
	var flash_rect = ColorRect.new()
	flash_rect.color = Color(1.0, 0.9, 0.4, 0.4) # Transparent golden flash
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_canvas.add_child(flash_rect)
	
	var flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "color:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_callback(flash_canvas.queue_free)

	# 4. Large bouncy "LEVEL UP!" float text
	var float_text_scene = load("res://ui/floating_text.tscn")
	if float_text_scene:
		var lvl_up_text = float_text_scene.instantiate()
		lvl_up_text.position = Vector2(16, -16)
		lvl_up_text.set_text("★ LEVEL UP! ★", Color(1.0, 0.9, 0.0), true) # treated as crit for pop & wiggle
		add_child(lvl_up_text)

	play_level_up_sound()

	# ---

	# ログに表示
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("レベルアップ！ Lv.%d になった！ (MP+%d)" % [level, (max_mp - mp)], Color(1.0, 0.8, 0.0))

	# Update UI
	if PlayerUi:
		PlayerUi.update_level(level)
		PlayerUi.update_hp(hp, max_hp)
		PlayerUi.update_mp(mp, max_mp)

	# スキル習得判定
	_check_skill_learning()

# 状態異常
var status_effects: Dictionary = {}
var decay_sleep_timer: int = -1

func apply_status_effect(effect_id: String, duration: int):
	apply_effect(effect_id, {"duration": duration})

func apply_effect(effect_id: String, params: Dictionary = {}):
	if status_effects.has(effect_id):
		return # 重ねがけ防止
	status_effects[effect_id] = params
	print("Applied status: ", effect_id, " Params: ", params)
	if has_node("/root/LogUI"):
		var effect_name = effect_id
		if effect_id == "paralysis": effect_name = "麻痺"
		elif effect_id == "burn": effect_name = "炎上"
		elif effect_id == "sleep": effect_name = "睡眠"
		get_node("/root/LogUI").add_log("%s 状態になった！" % effect_name, Color.YELLOW)

func remove_status_effect(effect_id: String):
	remove_effect(effect_id)

func remove_effect(effect_id: String):
	if status_effects.has(effect_id):
		status_effects.erase(effect_id)

func has_status_effect(effect_id: String) -> bool:
	return status_effects.has(effect_id)

func is_paralyzed() -> bool:
	return has_status_effect("paralysis")

func process_status_effects():
	var keys_to_remove = []
	for effect_id in status_effects:
		var effect = status_effects[effect_id]
		effect.duration -= 1
		if effect.duration <= 0:
			keys_to_remove.append(effect_id)
	
	for k in keys_to_remove:
		status_effects.erase(k)
		print("Status expired: ", k)
		if has_node("/root/LogUI"):
			var effect_name = k
			if k == "paralysis": effect_name = "麻痺"
			elif k == "sleep": effect_name = "睡眠"
			get_node("/root/LogUI").add_log("%s が治った！" % effect_name, Color.GREEN)

# ターン終了時の処理（HP自動回復）
func on_turn_end():
	turn_counter += 1
	
	if decay_sleep_timer > 0:
		decay_sleep_timer -= 1
		if decay_sleep_timer == 0:
			decay_sleep_timer = -1
			apply_status_effect("sleep", 10)
	
	# Process Cooldowns
	var keys_to_remove = []
	for skill_id in skill_cooldowns:
		skill_cooldowns[skill_id] -= 1
		if skill_cooldowns[skill_id] <= 0:
			keys_to_remove.append(skill_id)
			
	for k in keys_to_remove:
		skill_cooldowns.erase(k)
	
	# Ranged Weapon Cooldown
	if ranged_weapon_cooldown > 0:
		ranged_weapon_cooldown -= 1
		if ranged_weapon_cooldown == 0:
			# Reset shots when cooldown ends? 
			# NOTE: If we are using Magazine system, do NOT reset shots on cooldown end unless it acts as 'refresh'.
			# Pistol/Magnum uses explicit reload, but simple bows use cooldown.
			# Let's check item type? Or just assume simple cooldown reset logic applies to non-magazine?
			# Current logic in update_terrain_info resets shots_fired.
			# If player has Magnum (Magazine), cooldown usually only applies AFTER magazine empty?
			# Actually, main.gd sets cooldown when magazine empties.
			# BUT logic says "Reset shots when cooldown ends". This implies AUTO-RELOAD for cooldown weapons.
			# For Magnum, if cooldown ends, shots set to 0 -> Means fully reloaded.
			# Is this desired? "Magazine empty -> Cooldown -> Full Reload".
			# This seems to be the intended mechanic for "Cooldown based reload" vs "Manual Reload".
			# But current Pistol/Magnum has "Manual Reload (R key)" or "Auto cooldown"?
			# item_database says Pistol: "R key to reload". Magnum: "Cooldown 5 turn".
			# So Magnum is auto-reload.
			# We should keep existing logic:
			ranged_weapon_shots_fired = 0
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("遠距離武器が再使用可能になった", Color.CYAN)
	
	_update_ui_weapon()
	_update_skill_ui()
	
	process_status_effects()

	
	# Hunger System (process every 4 turns)
	if turn_counter % 4 == 0:
		if hunger > 0:
			hunger = max(hunger - 1, 0)
			if hunger == HUNGER_WARNING_LEVEL:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("お腹がすいてきた…", Color(1.0, 0.9, 0.4))
			elif hunger == HUNGER_CRITICAL_LEVEL:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("とても空腹だ！何か食べないと…", Color(1.0, 0.6, 0.3))
		elif hunger == 0:
			# Starvation damage
			take_damage(HUNGER_DAMAGE_PER_TURN)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("空腹で %d ダメージを受けた…" % HUNGER_DAMAGE_PER_TURN, Color(1.0, 0.4, 0.2))
	

	# HPが最大でない場合のみ回復処理
	if hp < max_hp:
		turns_since_damage += 1
		
		# 一定ターン経過後に回復開始
		if turns_since_damage >= REGEN_TURN_THRESHOLD:
			# 最大HPの5%回復（最低1）
			var regen_amount = max(1, int(max_hp * 0.05))
			heal(regen_amount)
			if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("HP回復 +%d" % regen_amount, Color(0.5, 1.0, 0.5))

	# Swimmer Water Regeneration
	# Class 4 = Swimmer
	# Requirement: Class is Swimmer AND equipped with Swimming Equipment (can_swim is true explicitly from gear) AND is in water
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.player_class == 4 and is_on_water and is_using_swim_gear():
		if hp < max_hp:
			heal(1)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("水の中で傷が癒える... (+1)", Color(0.3, 0.8, 1.0))

	# MP Natural Regeneration
	if mp < max_mp:
		var total_int = intelligence
		var eq_stats = _get_equipment_stats()
		total_int += eq_stats.intelligence
		
		var turns_per_mp = max(3, MP_REGEN_TURN - total_int)
		
		if turn_counter % turns_per_mp == 0:
			mp_heal(1)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("MP回復 +1", Color(0.5, 0.5, 1.0))

func update_terrain_info(is_grass: bool, is_water: bool):
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate.a = 0.6 if is_grass else 1.0
	is_on_water = is_water
	is_in_grass = is_grass

	# Cooldowns processed in on_turn_end now to support waiting.
	

	
	_update_ui_weapon()
	_update_skill_ui()

func _update_ui_weapon():
	if not PlayerUi: return
	
	# Get equipped ranged weapon
	var ranged_weapon = _get_ranged_weapon() 
	if not ranged_weapon:
		PlayerUi.update_weapon_info("", 0, 0, 0)
		if "ammo_label" in PlayerUi and PlayerUi.ammo_label:
			PlayerUi.ammo_label.visible = false
		return
		
	var mag_size = ranged_weapon.effects.get("magazine_size", 0)
	PlayerUi.update_weapon_info(ranged_weapon.name, ranged_weapon_shots_fired, mag_size, ranged_weapon_cooldown)
	
	# Update reserve ammo UI
	PlayerUi.update_ammo(ammo_inventory)
	if PlayerUi.ammo_label:
		PlayerUi.ammo_label.visible = true

func mp_heal(amount: int):
	mp = min(mp + amount, max_mp)
	if PlayerUi:
		PlayerUi.update_mp(mp, max_mp)

func replenish_ammo(amount: int):
	ammo_inventory = amount # Reset/Set to fixed amount per floor as requested
	# Alternatively: ammo_inventory += amount
	
	print("Ammo replenished. Current Reserve: ", ammo_inventory)
	if has_node("/root/LogUI"):
		get_node("/root/LogUI").add_log("弾薬を補充した (予備: %d)" % ammo_inventory, Color(0.6, 1.0, 1.0))
	if PlayerUi:
		PlayerUi.update_ammo(ammo_inventory)
	_update_ui_weapon()

func pickup_item(item_data: BaseItem) -> bool:
	if equipment_component.add_to_bag(item_data):
		print("Picked up: ", item_data.name)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を拾った" % item_data.name, Color(0.5, 1.0, 1.0))
		play_pickup_sound()
		return true
	else:
		print("Inventory full!")
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("インベントリがいっぱいで %s を拾えない" % item_data.name, Color(1.0, 0.5, 0.5))
		return false
		

func update_on_grass(is_on_grass: bool):
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate.a = 0.6 if is_on_grass else 1.0

signal turn_end_triggered

func trigger_turn_end():
	turn_end_triggered.emit()

# Growth accumulators
var _growth_accumulators = {
	"str": 0.0,
	"dex": 0.0,
	"int": 0.0,
	"hp": 0.0
}

func _accumulate_growth(stat: String, amount: float):
	if _growth_accumulators.has(stat):
		_growth_accumulators[stat] += amount

func _get_accumulated_increase(stat: String) -> int:
	if _growth_accumulators.has(stat):
		var val = _growth_accumulators[stat]
		var increase = floor(val)
		if increase > 0:
			_growth_accumulators[stat] -= increase
			return int(increase)
	return 0

func _start_idle_animation():
	var sprite = get_node_or_null("Sprite2D")
	if not sprite: return
	
	if _base_scale.is_zero_approx() or _base_scale == Vector2.ONE:
		_base_scale = sprite.scale
		if _base_scale.is_zero_approx(): _base_scale = Vector2.ONE
	
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
		
	_idle_tween = create_tween().set_loops()
	
	# Squash and stretch (subtle breathing animation)
	var squash = _base_scale * Vector2(1.03, 0.97)
	var stretch = _base_scale * Vector2(0.97, 1.03)
	
	_idle_tween.tween_property(sprite, "scale", squash, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(sprite, "scale", stretch, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)



func use_item(item: BaseItem):
	var main_node = get_parent()
	if main_node and main_node.get("_is_on_world_map"):
		if item.id == "scroll_teleport" or item.id == "warp_grass" or item.id == "scroll_mapping":
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("ワールドマップではそのアイテムを使用できません。", Color.GRAY)
			return

	print("Player using item: ", item.name)
	
	# 1. Potion / High Potion
	if item.id == "potion" or item.id == "high_potion":
		heal(item.heal)
		hunger = min(hunger + item.restore_hunger, max_hunger)
		_consume_item(item, "回復薬を飲んだ。HPが%d回復した。(おまけで満腹度+3)" % item.heal)
	
	# 1.2. Ether / High Ether (MP recovery)
	elif item.id == "ether" or item.id == "high_ether":
		var old_mp = mp
		mp = min(mp + item.restore_mp, max_mp)
		var recovered = mp - old_mp
		hunger = min(hunger + item.restore_hunger, max_hunger)
		if has_node("/root/LogUI"):
			if recovered > 0:
				get_node("/root/LogUI").add_log("%s を飲んだ。MPが%d回復した。" % [item.name, recovered], Color(0.3, 0.6, 1.0))
			else:
				get_node("/root/LogUI").add_log("%s を飲んだ。しかしMPは既に最大だ。" % item.name, Color(0.6, 0.6, 0.6))
		_consume_item(item, "")
		
	# 1.4. Berry (Hunger recovery from trees)
	elif item.id == "berry":
		var old_hunger = hunger
		hunger = min(hunger + item.restore_hunger, max_hunger)
		var gained = hunger - old_hunger
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("木の実を食べた。空腹が少しおさまった。(満腹度+%d)" % gained, Color(0.7, 0.9, 0.4))
		_consume_item(item, "")

	# 1.5. Gummy family
	elif item.id == "gummy" or item.id == "silver_gummy" or item.id == "golden_gummy":
		var old_hunger = hunger
		hunger = min(hunger + item.restore_hunger, max_hunger)
		var gained = hunger - old_hunger
		
		if item.heal > 0:
			heal(item.heal)
			
		if item.id == "golden_gummy":
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("黄金のグミを食べた！空腹が完全に満たされ、HPが%d回復した！" % item.heal, Color(1.0, 0.84, 0.0))
		elif item.id == "silver_gummy":
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("銀のグミを食べた。空腹がかなりおさまった。(満腹度+%d)" % gained, Color(0.9, 0.9, 0.9))
		else:
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("グミを食べた。空腹が少しおさまった。(満腹度+%d)" % gained, Color(1.0, 0.8, 0.6))
		
		_consume_item(item, "")
		
	# 2. Strength Potion
	elif item.id == "potion_str":
		strength += 1
		hunger = min(hunger + 3, max_hunger)
		_consume_item(item, "力が湧いてきた！(STR +1) (おまけで満腹度+3)")
		
	# 3. Teleport Scroll / Warp Grass
	elif item.id == "scroll_teleport" or item.id == "warp_grass":
		_teleport_randomly()
		_consume_item(item, "空間が歪んだ！テレポートした！")
		
	# 4. Mapping Scroll
	elif item.id == "scroll_mapping":
		var map_node = get_parent()
		if map_node.has_method("reveal_map"):
			map_node.reveal_map()
			_consume_item(item, "頭の中に地図が浮かび上がった！")
		else:
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("しかし、何も起こらなかった。", Color.GRAY)
				
	# 5. Poison Mushroom
	elif item.id == "poison_mushroom":
		apply_status_effect("paralysis", 3)
		_consume_item(item, "毒キノコを食べた！体が痺れる！")
		
	# 6. Generic Consumable (Fallback for newly added items via Editor)
	else:
		var has_effect = false
		var recovered_hp = 0
		var recovered_mp = 0
		var recovered_hunger = 0
		
		if item.heal > 0:
			var old_hp = hp
			heal(item.heal)
			recovered_hp = hp - old_hp
			has_effect = true
		if item.restore_mp > 0:
			var old_mp = mp
			mp = min(mp + item.restore_mp, max_mp)
			recovered_mp = mp - old_mp
			has_effect = true
		if item.restore_hunger > 0:
			var old_hunger = hunger
			hunger = min(hunger + item.restore_hunger, max_hunger)
			recovered_hunger = hunger - old_hunger
			has_effect = true
			
		if has_effect:
			var log_parts = []
			if recovered_hp > 0: log_parts.append("HPが%d" % recovered_hp)
			if recovered_mp > 0: log_parts.append("MPが%d" % recovered_mp)
			if recovered_hunger > 0: log_parts.append("満腹度が%d" % recovered_hunger)
			
			var effect_text = "、".join(log_parts) + "回復した。"
			_consume_item(item, "%s を使用した。%s" % [item.name, effect_text])
		else:
			print("Cannot use this item")
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("%s は使えない。" % item.name, Color.GRAY)

func _consume_item(item, log_msg):
	# Remove item from inventory (Try bag first, then equipment)
	var removed = false
	if equipment_component.bag_data.remove_item(item):
		removed = true
	elif equipment_component.equipment_data.remove_item(item):
		removed = true
		
	if removed:
		print("Used ", item.name)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log(log_msg, Color(0.5, 1.0, 0.5))
		trigger_turn_end()

func _teleport_randomly():
	var map_node = get_parent()
	if map_node.has_method("get_random_floor_position"):
		var pos = map_node.get_random_floor_position()
		if pos != Vector2.ZERO:
			# Particles at old position
			_spawn_skill_particles(position + Vector2(16, 16), "ice", 0.3)
			
			position = pos
			
			# Particles at new position
			_spawn_skill_particles(position + Vector2(16, 16), "ice", 0.5)
			
			# Camera update is automatic in process
			# Update FOV?
			if map_node.has_method("_calculate_fov"):
				map_node._calculate_fov()
				map_node._draw_map()

# --- Sprite & Animation Handling ---
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.2 # 0.2s per frame



func _load_class_sprite():
	var gs = get_node_or_null("/root/GameState")
	if not gs: return
	
	var sprite = get_node_or_null("Sprite2D")
	if not sprite: return
	
	# Default offset
	sprite_offset = Vector2(16, 16)

	
	var texture_path = ""
	var is_sheet = false
	
	match gs.player_class:
		0: # Balanced (Default)
			# texture_path = "res://assets/player.png" 
			is_sheet = false
		1: # Warrior
			texture_path = "res://assets/warrior.png"
			is_sheet = false
		2: # Rogue
			texture_path = "res://assets/rogue.png"
			is_sheet = false
		3: # Mage
			texture_path = "res://assets/mage.png"
			is_sheet = false
		4: # Swimmer
			texture_path = "res://assets/swimmer.png"
			is_sheet = false
			
	if texture_path != "":
		var tex = load(texture_path)
		if tex:
			sprite.texture = tex
			# Reset basic properties
			sprite.modulate = Color.WHITE
			sprite.position = Vector2(16, 16)
			sprite.hframes = 1
			sprite.vframes = 1
			sprite.frame = 0
			
			# Calculate scale based on texture size to fit within 32x32
			var texture_size = tex.get_size()
			var max_dim = max(texture_size.x, texture_size.y)
			var target_size = 32.0
			
			var scale_factor = target_size / max_dim
			scale_factor *= 1.2 # Fill tile nicely
			
			# Class specifics overrides
			# Class specifics overrides
			if gs.player_class == 1: # Warrior
				pass # Warrior size is fine
			elif gs.player_class == 3: # Mage
				scale_factor *= 1.5 
			else:
				# Rogue(2), Swimmer(4) - boost size
				scale_factor *= 1.8 
			
			sprite.scale = Vector2(scale_factor, scale_factor)
			sprite_offset = Vector2(16, 16)
			sprite.position = sprite_offset
			
			# Use breathing animation for everyone since they are single sprites now
			_use_sheet_anim = false
			_start_idle_animation()

var _use_sheet_anim = false

func _process(delta):
	# Sync camera to player position (smoothly handled by Camera2D smoothing)
	if camera:
		camera.position = position + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
		
	# Animation Update
	if _use_sheet_anim:
		_anim_timer += delta
		if _anim_timer >= ANIM_SPEED:
			_anim_timer = 0.0
			var sprite = get_node_or_null("Sprite2D")
			if sprite:
				sprite.frame = (sprite.frame + 1) % sprite.hframes


func _unhandled_input(event):
	var main_node = get_parent()
	if main_node and main_node.get("_is_on_world_map"):
		return
		
	if event is InputEventKey and event.pressed and not event.is_echo():
		# Map only top-row number keys 1-9 to known_skills indices.
		# Exclude numpad keys so numpad movement works on Web exports.
		var is_top_row_number: bool = event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9
		if is_top_row_number and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx = event.keycode - KEY_1
			if idx < known_skills.size():
				use_skill(known_skills[idx])
			else:
				if has_node("/root/LogUI"):
					get_node("/root/LogUI").add_log("そのスロットにスキルはありません。", Color.GRAY)

# F Key handling is now in main.gd to support targeting mode

func use_skill_by_id(skill_id: String):
	use_skill(skill_id)

func use_skill(skill_id: String):
	var main_node = get_parent()
	if main_node and main_node.get("_is_on_world_map"):
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("ワールドマップではスキルを使用できません。", Color.GRAY)
		return

	if not known_skills.has(skill_id):
		print("Unknown skill or not learned: ", skill_id)
		return

	# Cooldown Check
	if skill_cooldowns.has(skill_id) and skill_cooldowns[skill_id] > 0:
		var turns = skill_cooldowns[skill_id]
		print("Skill on cooldown: ", skill_id, " Turns: ", turns)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s はまだ使えない (あと%dターン)" % [SkillDatabase.get_skill_by_id(skill_id).name, turns], Color.GRAY)
		return

	var skill = SkillDatabase.get_skill_by_id(skill_id)
	if skill.is_empty(): return
	
	if mp < skill.mp_cost:
		print("Not enough MP")
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("MPが足りない！", Color.RED)
		return

	var hp_cost = skill.get("hp_cost", 0)
	if hp_cost > 0 and hp <= hp_cost:
		print("Not enough HP for skill")
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("これ以上HPがない！御衰えだ。", Color.RED)
		return

	print("Player preparing skill: ", skill.name)
	
	match skill.type:
		SkillDatabase.SKILL_TYPE_SELF:
			_execute_self_skill(skill)
		SkillDatabase.SKILL_TYPE_DIRECTION, SkillDatabase.SKILL_TYPE_TARGET_ENEMY, SkillDatabase.SKILL_TYPE_POINT:
			var main = get_tree().current_scene
			# Search for main scene in case player is instantiated deeper
			if not main.has_method("start_skill_targeting"):
				main = get_node("/root/Main") # Try direct root access if standard fails
			
			if main and main.has_method("start_skill_targeting"):
				main.start_skill_targeting(skill)
			else:
				print("Cannot find main scene for targeting")
		_:
			print("Unknown skill type")

func _execute_self_skill(skill):
	# Apply effects
	if skill.id == "heal":
		var base_heal = skill.get("heal_amount", 8)
		var final_heal = base_heal
		if skill.get("is_magic", false):
			final_heal += intelligence
			
		heal(final_heal)
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を唱えた。(+%d回復)" % [skill.name, final_heal], Color.CYAN)
	elif skill.id == "teleport":
		_teleport_randomly()
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("%s を唱えた。空間が歪む！" % skill.name, Color.PURPLE)
	elif skill.id == "cyclone_slash":
		var main = get_tree().current_scene
		if not main.has_method("_execute_cyclone_slash"):
			main = get_node("/root/Main")
		if main and main.has_method("_execute_cyclone_slash"):
			main._execute_cyclone_slash(skill)
			on_skill_executed(skill, false)
			return
	elif skill.id == "acid_puddle":
		var main = get_tree().current_scene
		if not main.has_method("create_hazard"):
			main = get_node("/root/Main")
		if main and main.has_method("create_hazard"):
			for x in range(-1, 2):
				for y in range(-1, 2):
					if x == 0 and y == 0: continue
					var offset = Vector2(x, y) * TILE_SIZE
					main.create_hazard("acid_puddle", position + offset)
			if has_node("/root/LogUI"):
				get_node("/root/LogUI").add_log("周囲に酸の沼を作り出した！", Color.GREEN_YELLOW)
				
	on_skill_executed(skill)

func on_skill_executed(skill, auto_end_turn: bool = true):
	mp -= skill.mp_cost
	
	# Set Cooldown
	var cd = skill.get("cooldown", 0)
	if cd > 0:
		skill_cooldowns[skill["id"]] = cd
		
	if PlayerUi:
		PlayerUi.update_mp(mp, max_mp)
	
	_update_skill_ui()
	
	if auto_end_turn:
		trigger_turn_end()

func _get_ranged_weapon() -> BaseItem:
	var candidates = []
	if equipment_component and equipment_component.equipment_data:
		for item in equipment_component.equipment_data.items:
			if item.effects.has("is_ranged") and item.effects["is_ranged"] == true:
				candidates.append(item)
	
	if candidates.is_empty():
		return null
		
	# Sort candidates: Top-Left first (Ascending Y, then Ascending X)
	candidates.sort_custom(func(a, b):
		if a.grid_position.y != b.grid_position.y:
			return a.grid_position.y < b.grid_position.y
		return a.grid_position.x < b.grid_position.x
	)
	
	return candidates[0]


func apply_debug_upgrade():
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.set_class_stats(99) # Debug Class
		
		# Re-apply stats
		strength = gs.initial_str
		dexterity = gs.initial_dex
		intelligence = gs.initial_int
		initial_hp_bonus = gs.initial_hp_bonus
		
		# Recalculate caps
		level_hp_bonus = 0
		level_mp_bonus = 0
		
		var equipment_stats = _get_equipment_stats()
		max_hp = BASE_MAX_HP + initial_hp_bonus + 0 # Neutralize level bonuses
		hp = max_hp
		
		# MP Calculation matching _ready logic
		max_mp = BASE_MAX_MP + (intelligence * 2)
		mp = max_mp
		
		_base_can_swim = gs.initial_can_swim
		base_known_skills = gs.initial_skills.duplicate()
		_update_known_skills()
		_load_class_sprite()
		
		# Update UI
		if PlayerUi:
			PlayerUi.update_hp(hp, max_hp)
			PlayerUi.update_mp(mp, max_mp)
			PlayerUi.update_level(level)
		
		if has_node("/root/LogUI"):
			get_node("/root/LogUI").add_log("デバッグモードが有効になりました！神の如き強さを得た。", Color.CYAN)


func _spawn_skill_particles(pos: Vector2, particle_type: String, duration: float = 0.5):
	var particles = CPUParticles2D.new()
	# Relative to player if we add to player, but better to add to parent (World)
	particles.position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.amount = 25
	particles.lifetime = duration
	
	match particle_type:
		"fire":
			particles.color = Color(1, 0.4, 0, 1)
			particles.spread = 180.0
			particles.gravity = Vector2(0, -60)
			particles.initial_velocity_min = 40.0
			particles.initial_velocity_max = 80.0
			particles.scale_amount_min = 3.0
			particles.scale_amount_max = 6.0
		"lightning":
			particles.color = Color(1, 1, 0.5, 1)
			particles.amount = 30
			particles.spread = 180.0
			particles.initial_velocity_min = 100.0
			particles.initial_velocity_max = 150.0
		"ice":
			particles.color = Color(0.7, 1.0, 1.0, 1)
			particles.amount = 20
			particles.gravity = Vector2(0, 40)
			particles.initial_velocity_min = 20.0
			particles.initial_velocity_max = 50.0
		"heal":
			particles.color = Color(0.6, 1.0, 0.6, 1)
			particles.amount = 40
			particles.spread = 180.0
			particles.gravity = Vector2(0, -30)
			particles.initial_velocity_min = 30.0
			particles.initial_velocity_max = 60.0
			particles.explosiveness = 0.5
		"blood":
			particles.color = Color(0.8, 0.0, 0.1, 1)
			particles.amount = 35
			particles.spread = 160.0
			particles.gravity = Vector2(0, 60)
			particles.initial_velocity_min = 50.0
			particles.initial_velocity_max = 100.0
			particles.scale_amount_min = 2.0
			particles.scale_amount_max = 5.0
			particles.explosiveness = 0.9
	
	if get_parent():
		get_parent().add_child(particles)
	else:
		add_child(particles)
		
	get_tree().create_timer(duration + 0.5).timeout.connect(particles.queue_free)

var _coin_sound_stream: AudioStream = null
var _coin_loss_sound_stream: AudioStream = null
var _fall_sound_stream: AudioStream = null

func _on_gold_changed(old_gold: int, new_gold: int):
	# UIの自動更新
	var player_ui = get_node_or_null("/root/PlayerUi")
	if player_ui and player_ui.has_method("update_gold"):
		player_ui.update_gold(new_gold)
		
	# シーン準備完了後の変化のみ音を鳴らす (ロード時の発火防止)
	if is_node_ready():
		if new_gold > old_gold:
			_play_coin_sound()
		elif new_gold < old_gold:
			_play_coin_loss_sound()

func _play_coin_sound():
	if _coin_sound_stream == null:
		_coin_sound_stream = _create_coin_sound()
	_play_generated_stream(_coin_sound_stream)

func _play_coin_loss_sound():
	if _coin_loss_sound_stream == null:
		_coin_loss_sound_stream = _create_coin_loss_sound()
	_play_generated_stream(_coin_loss_sound_stream)

func _play_generated_stream(stream: AudioStream):
	if stream:
		var asp = AudioStreamPlayer.new()
		asp.stream = stream
		# Playerが消滅した際にも途切れないように、親ノードかルートに追加する
		var main_node = get_parent()
		if main_node:
			main_node.add_child(asp)
		else:
			get_tree().root.add_child(asp)
		asp.finished.connect(asp.queue_free)
		asp.play()

func _create_coin_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.25
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	var freq1 = 987.77  # B5
	var freq2 = 1318.51 # E6
	var switch_sample = int(mix_rate * 0.07)

	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var freq = freq1 if i < switch_sample else freq2
		phase += 2.0 * PI * freq / mix_rate
		
		var envelope = exp(-t * 9.0)
		var sample_val = sin(phase) * envelope
		
		var int_val = int(sample_val * 24000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _create_coin_loss_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.2
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var freq = 600.0 - (float(i) / num_samples) * 380.0
		phase += 2.0 * PI * freq / mix_rate
		
		var envelope = exp(-t * 12.0)
		var sample_val = sin(phase) * envelope
		
		var int_val = int(sample_val * 20000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func play_fall_sound():
	if _fall_sound_stream == null:
		_fall_sound_stream = _create_fall_sound()
	_play_generated_stream(_fall_sound_stream)

func _create_fall_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.5
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var sample_val = 0.0
		
		if t < 0.3:
			# falling part: slide pitch down rapidly (from 900Hz to 150Hz)
			var freq = 900.0 - (t / 0.3) * 750.0
			phase += 2.0 * PI * freq / mix_rate
			var envelope = 1.0 - (t / 0.3)
			sample_val = sin(phase) * envelope * 0.4
		else:
			# landing part: heavy thud noise (combination of low sine and random noise)
			var t_thud = t - 0.3
			var thud_dur = 0.2
			var freq = 80.0 * exp(-t_thud * 15.0) # decay frequency
			phase += 2.0 * PI * freq / mix_rate
			var noise = randf_range(-1.0, 1.0)
			var envelope = exp(-t_thud * 10.0)
			sample_val = (sin(phase) * 0.7 + noise * 0.3) * envelope * 0.6
		
		var int_val = int(sample_val * 24000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

var _level_up_sound_stream: AudioStream = null
var _pickup_sound_stream: AudioStream = null
var _door_open_sound_stream: AudioStream = null
var _door_close_sound_stream: AudioStream = null
var _lockpick_sound_stream: AudioStream = null
var _reload_sound_stream: AudioStream = null

func play_level_up_sound():
	if _level_up_sound_stream == null:
		_level_up_sound_stream = _create_level_up_sound()
	_play_generated_stream(_level_up_sound_stream)

func play_pickup_sound():
	if _pickup_sound_stream == null:
		_pickup_sound_stream = _create_pickup_sound()
	_play_generated_stream(_pickup_sound_stream)

func play_door_open_sound():
	if _door_open_sound_stream == null:
		_door_open_sound_stream = _create_door_open_sound()
	_play_generated_stream(_door_open_sound_stream)

func play_door_close_sound():
	if _door_close_sound_stream == null:
		_door_close_sound_stream = _create_door_close_sound()
	_play_generated_stream(_door_close_sound_stream)

func play_lockpick_sound():
	if _lockpick_sound_stream == null:
		_lockpick_sound_stream = _create_lockpick_sound()
	_play_generated_stream(_lockpick_sound_stream)

func play_reload_sound():
	if _reload_sound_stream == null:
		_reload_sound_stream = _create_reload_sound()
	_play_generated_stream(_reload_sound_stream)

func _create_level_up_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.6
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	var switch1 = int(mix_rate * 0.1)
	var switch2 = int(mix_rate * 0.2)
	var switch3 = int(mix_rate * 0.3)
	
	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var freq = 523.25 # C5
		if i >= switch3:
			freq = 1046.50 # C6
		elif i >= switch2:
			freq = 783.99 # G5
		elif i >= switch1:
			freq = 659.25 # E5
			
		phase += 2.0 * PI * freq / mix_rate
		
		# Envelope
		var envelope = 1.0
		if i >= switch3:
			var t_final = t - 0.3
			envelope = exp(-t_final * 5.0)
		else:
			envelope = 0.7
			
		# Chiptune feel: square wave
		var sample_val = 1.0 if sin(phase) >= 0.0 else -1.0
		sample_val *= envelope * 0.2
		
		var int_val = int(sample_val * 16000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _create_pickup_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.12
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var freq = 800.0 + (t / duration) * 800.0
		phase += 2.0 * PI * freq / mix_rate
		
		var envelope = exp(-t * 15.0)
		var sample_val = sin(phase) * envelope * 0.3
		
		var int_val = int(sample_val * 20000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _create_door_open_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.35
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var freq = 120.0 + sin(t * 80.0) * 30.0 + randf_range(-10.0, 10.0)
		phase += 2.0 * PI * freq / mix_rate
		
		var envelope = 1.0
		if t < 0.05:
			envelope = t / 0.05
		else:
			envelope = 1.0 - ((t - 0.05) / 0.3)
			
		var sample_val = sin(phase) * envelope * 0.2
		
		var int_val = int(sample_val * 18000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _create_door_close_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.15
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	var phase = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var freq = 150.0 * exp(-t * 20.0)
		phase += 2.0 * PI * freq / mix_rate
		
		var envelope = exp(-t * 25.0)
		var noise = randf_range(-1.0, 1.0)
		var sample_val = (sin(phase) * 0.6 + noise * 0.4) * envelope * 0.4
		
		var int_val = int(sample_val * 20000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _create_lockpick_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.25
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	var click2_start = int(mix_rate * 0.12)
	
	var phase1 = 0.0
	var phase2 = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var sample_val = 0.0
		
		if i < click2_start:
			phase1 += 2.0 * PI * 2200.0 / mix_rate
			var env1 = exp(-t * 60.0)
			sample_val = sin(phase1) * env1 * 0.25
		else:
			var t2 = t - 0.12
			phase2 += 2.0 * PI * 1800.0 / mix_rate
			var env2 = exp(-t2 * 60.0)
			sample_val = sin(phase2) * env2 * 0.25
			
		var int_val = int(sample_val * 16000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _create_reload_sound() -> AudioStream:
	var mix_rate = 44100
	var duration = 0.3
	var num_samples = int(mix_rate * duration)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	
	var step2_start = int(mix_rate * 0.15)
	
	var phase1 = 0.0
	var phase2 = 0.0
	for i in range(num_samples):
		var t = float(i) / mix_rate
		var sample_val = 0.0
		
		if i < step2_start:
			phase1 += 2.0 * PI * 300.0 / mix_rate
			var env = exp(-t * 40.0)
			var noise = randf_range(-1.0, 1.0)
			sample_val = (sin(phase1) * 0.5 + noise * 0.5) * env * 0.3
		else:
			var t2 = t - 0.15
			phase2 += 2.0 * PI * 1000.0 / mix_rate
			var env = exp(-t2 * 60.0)
			var noise = randf_range(-1.0, 1.0)
			sample_val = (sin(phase2) * 0.7 + noise * 0.3) * env * 0.3
			
		var int_val = int(sample_val * 16000.0)
		int_val = clamp(int_val, -32768, 32767)
		
		var idx = i * 2
		data[idx] = int_val & 0xFF
		data[idx + 1] = (int_val >> 8) & 0xFF
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

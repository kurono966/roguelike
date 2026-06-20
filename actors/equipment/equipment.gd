class_name Equipment
extends Resource

# 装備の基本プロパティ
var id: String
var name: String
var description: String
var equipment_type: int  # EquipmentSlot.EquipmentType
var slot_type: int       # EquipmentSlot.EquipmentSlot
var icon: Texture2D

# 装備の基本パラメータ
var attack: int = 0
var defense: int = 0
var max_hp: int = 0
var strength: int = 0  # 力
var dexterity: int = 0 # 器用さ
var intelligence: int = 0 # 知力

# 装備のレアリティ
enum Rarity {
    COMMON,
    UNCOMMON,
    RARE,
    EPIC,
    LEGENDARY
}
var rarity: int = Rarity.COMMON

func _init(
    p_id: String = "", 
    p_name: String = "未設定の装備", 
    p_description: String = "", 
    p_equipment_type: int = 0,
    p_slot_type: int = 0,
    p_attack: int = 0,
    p_defense: int = 0,
    p_max_hp: int = 0,
    p_strength: int = 0,
    p_dexterity: int = 0,
    p_intelligence: int = 0,
    p_rarity: int = Rarity.COMMON
):
    id = p_id
    name = p_name
    description = p_description
    equipment_type = p_equipment_type
    slot_type = p_slot_type
    attack = p_attack
    defense = p_defense
    max_hp = p_max_hp
    strength = p_strength
    dexterity = p_dexterity
    intelligence = p_intelligence
    rarity = p_rarity

# 装備の表示名を取得（レアリティ色付き）
func get_colored_name() -> String:
    var color: String
    match rarity:
        Rarity.UNCOMMON: color = "#00ff00"  # 緑
        Rarity.RARE: color = "#0000ff"       # 青
        Rarity.EPIC: color = "#800080"       # 紫
        Rarity.LEGENDARY: color = "#ffa500"  # オレンジ
        _: color = "#ffffff"                 # 白（通常）
    
    return "[color=%s]%s[/color]" % [color, name]

# 装備の詳細をテキストで取得
func get_description() -> String:
    var desc = "%s\n" % description
    
    if attack != 0:
        desc += "攻撃力: %+d\n" % attack
    if defense != 0:
        desc += "防御力: %+d\n" % defense
    if max_hp != 0:
        desc += "最大HP: %+d\n" % max_hp
    if strength != 0:
        desc += "力: %+d\n" % strength
    if dexterity != 0:
        desc += "器用さ: %+d\n" % dexterity
    if intelligence != 0:
        desc += "知力: %+d\n" % intelligence
    
    return desc

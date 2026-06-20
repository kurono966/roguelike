extends Node
# 装備スロットの種類を定義
enum EquipmentSlot {
	NONE = -1,
	# 両手
	RIGHT_HAND,  # 利き手
	LEFT_HAND,   # 非利き手
	# 指輪スロット（10本の指）
	FINGER_1,    # 親指（右）
	FINGER_2,    # 人差し指（右）
	FINGER_3,    # 中指（右）
	FINGER_4,    # 薬指（右）
	FINGER_5,    # 小指（右）
	FINGER_6,    # 親指（左）
	FINGER_7,    # 人差し指（左）
	FINGER_8,    # 中指（左）
	FINGER_9,    # 薬指（左）
	FINGER_10,   # 小指（左）
	MAX
}

# 装備スロットの表示名を取得
static func get_slot_name(slot: int) -> String:
	match slot:
		EquipmentSlot.RIGHT_HAND: return "右手"
		EquipmentSlot.LEFT_HAND: return "左手"
		EquipmentSlot.FINGER_1: return "右手親指"
		EquipmentSlot.FINGER_2: return "右手人差し指"
		EquipmentSlot.FINGER_3: return "右手中指"
		EquipmentSlot.FINGER_4: return "右手薬指"
		EquipmentSlot.FINGER_5: return "右手小指"
		EquipmentSlot.FINGER_6: return "左手親指"
		EquipmentSlot.FINGER_7: return "左手中指"
		EquipmentSlot.FINGER_8: return "左手薬指"
		EquipmentSlot.FINGER_9: return "左手小指"
		EquipmentSlot.FINGER_10: return "左手人差し指"
		_: return "不明なスロット"

# 装備タイプ（後で使用）
enum EquipmentType {
	WEAPON,
	ARMOR,
	RING,
	AMULET,
	MAX
}

# 装備可能なスロットを取得
static func get_allowed_slots(equip_type: int) -> Array[int]:
	match equip_type:
		EquipmentType.WEAPON: return [EquipmentSlot.RIGHT_HAND, EquipmentSlot.LEFT_HAND]
		EquipmentType.RING: return [
			EquipmentSlot.FINGER_1, EquipmentSlot.FINGER_2, EquipmentSlot.FINGER_3,
			EquipmentSlot.FINGER_4, EquipmentSlot.FINGER_5, EquipmentSlot.FINGER_6,
			EquipmentSlot.FINGER_7, EquipmentSlot.FINGER_8, EquipmentSlot.FINGER_9,
			EquipmentSlot.FINGER_10
		]
		_: return []

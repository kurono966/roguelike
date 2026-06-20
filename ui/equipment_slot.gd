class_name EquipmentSlot
extends RefCounted

enum EquipmentType {
    HEAD,
    CHEST,
    LEGS,
    WEAPON,
    OFFHAND
}

static func get_allowed_slots(item_type: int) -> Array[int]:
    match item_type:
        EquipmentType.HEAD:
            return [EquipmentType.HEAD]
        EquipmentType.CHEST:
            return [EquipmentType.CHEST]
        EquipmentType.LEGS:
            return [EquipmentType.LEGS]
        EquipmentType.WEAPON:
            return [EquipmentType.WEAPON]
        EquipmentType.OFFHAND:
            return [EquipmentType.OFFHAND]
        _:
            return []

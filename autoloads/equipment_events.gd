class_name EquipmentEvents
extends Node

# Equipment events
signal equipment_changed(slot: int, item, from_slot: int, from_equipment: bool)
signal unequip_item(slot: int)
signal use_item(slot: int, item)
signal inventory_changed(slot: int, item, from_slot: int, from_equipment: bool)

# Player stats changed
signal stats_updated(stats: Dictionary)

# Singleton instance
static var instance: Node = null

func _init():
	if instance == null:
		instance = self
	else:
		queue_free()

func _enter_tree():
	if instance == null:
		instance = self

# Emit equipment changed event
static func emit_equipment_changed(slot: int, item, from_slot: int, from_equipment: bool):
	if instance:
		instance.equipment_changed.emit(slot, item, from_slot, from_equipment)

# Emit unequip item event
static func emit_unequip_item(slot: int):
	if instance:
		instance.unequip_item.emit(slot)

# Emit use item event
static func emit_use_item(slot: int, item):
	if instance:
		instance.use_item.emit(slot, item)

# Emit inventory changed event
static func emit_inventory_changed(slot: int, item, from_slot: int, from_equipment: bool):
	if instance:
		instance.inventory_changed.emit(slot, item, from_slot, from_equipment)

# Emit stats updated event
static func emit_stats_updated(stats: Dictionary):
	if instance:
		instance.stats_updated.emit(stats)

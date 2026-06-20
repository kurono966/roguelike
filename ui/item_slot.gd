extends TextureRect
class_name ItemSlot

const EquipmentSlot = preload("res://ui/equipment_slot.gd")

# Create a simple white texture programmatically
var default_texture = ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))

var item = null
var slot_index: int = -1
var is_equipment_slot: bool = false
var equipment_slot_type: int = -1  # Only used for equipment slots

signal item_clicked(slot_index: int, is_equipment_slot: bool, button_index: int)

func _ready():
	texture = default_texture
	tooltip_text = ""

func set_item(new_item):
	item = new_item
	if item:
		texture = item.icon if item and item.has_method("get_icon") else default_texture
		# Update tooltip with item info
		tooltip_text = item.name if "name" in item else ""
	else:
		texture = default_texture
		tooltip_text = ""

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			item_clicked.emit(slot_index, is_equipment_slot, event.button_index)
			accept_event()

func _get_drag_data(_at_position):
	if item:
		var preview = TextureRect.new()
		preview.texture = item.icon
		preview.size = Vector2(32, 32)
		set_drag_preview(preview)
		return {"item": item, "from_slot": slot_index, "is_equipment_slot": is_equipment_slot}
	return null

func _can_drop_data(_at_position, data):
	if not data is Dictionary:
		return false
	if not "item" in data:
		return false

	# If this is an equipment slot, check if the item can be equipped here
	if is_equipment_slot and data["item"].has_method("get_equipment_type"):
		var item_type = data["item"].get_equipment_type()
		var allowed_slots = EquipmentSlot.get_allowed_slots(item_type)
		return equipment_slot_type in allowed_slots
		
	return not is_equipment_slot  # Only allow non-equipment items in inventory slots

func _drop_data(_at_position, data):
	if _can_drop_data(_at_position, data):
		# Emit a signal to handle the item movement in the UI
		item_clicked.emit(slot_index, is_equipment_slot, 0, data)
		accept_event()

extends SceneTree

var failures = 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var player = Node.new()
	player.add_to_group("player")
	var component = EquipmentComponent.new()
	component.name = "EquipmentComponent"
	player.add_child(component)
	root.add_child(player)
	var colors = ["red", "blue", "yellow", "purple"]
	for row in range(4):
		for column in range(2):
			var item = BaseItem.new("test", "装備", null, EquipmentSlot.EquipmentType.WEAPON)
			item.shape.assign([Vector2i.ZERO])
			var direction = Vector2i.RIGHT if column == 0 else Vector2i.LEFT
			if row == 3: direction = Vector2i.DOWN if column == 0 else Vector2i.UP
			item.connectors.append({"cell": Vector2i.ZERO, "direction": direction, "color": colors[row]})
			var pos = Vector2i(4, row + column) if row == 3 else Vector2i(column, row)
			component.equipment_data.place_item(item, pos.x, pos.y)
	var view = load("res://ui/grid_inventory_view.tscn").instantiate()
	view.is_equipment_view = true
	root.add_child(view)
	view.set_grid_data(component.equipment_data)
	check(view.connected_group_overlays.size() == 4, "Initial display lacks connected groups")
	for overlay in view.connected_group_overlays:
		var joints = overlay.find_children("ConnectedJoint*", "Polygon2D", false, false)
		check(joints.size() == 1, "Each connection needs one steady joint")
		check(overlay.find_children("ConnectionBridge*", "Line2D", false, false).size() == 3, "Connection bridge layers missing")
		for child in overlay.get_children():
			if child.has_meta("is_outline"):
				check(child.color.a >= 0.9, "Group outline too faint")
	check(view.pulse_timer.is_stopped(), "Group markers still blink")
	var disconnected = component.equipment_data.items.back()
	disconnected.connectors[0].color = "red"
	component.equipment_data.grid_changed.emit()
	check(view.connected_group_overlays.size() == 3, "Disconnected gear retained highlight")
	view.refresh_view()
	check(view.connected_group_overlays.size() == 3, "Refresh lost or duplicated highlights")
	view.is_equipment_view = false
	view.refresh_view()
	check(view.connected_group_overlays.is_empty(), "Bag shows equipment connection bonuses")
	print("CONNECTOR_VISUAL_TEST failures=", failures)
	quit(1 if failures else 0)

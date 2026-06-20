
# コンテキストメニュー関連
func _show_context_menu(item: BaseItem, screen_pos: Vector2, is_equipped: bool, source_view):
	context_menu_item = item
	context_menu_source_view = source_view
	context_menu.call("show_menu", item, screen_pos, is_equipped)

func _get_cursor_screen_position(view: Control) -> Vector2:
	if not view or not view.has_method("get_cursor_item"):
		return Vector2.ZERO
	
	# カーソルの位置を取得
	var cursor_pos = view.cursor_pos if "cursor_pos" in view else Vector2i.ZERO
	var cell_size = 32  # CELL_SIZE
	
	# ビューのグローバル位置 + カーソル位置
	var local_pos = Vector2(cursor_pos.x * cell_size, cursor_pos.y * cell_size)
	return view.global_position + local_pos + Vector2(cell_size / 2, 0)

func _on_context_menu_action(action: String):
	if not context_menu_item:
		return
	
	var item = context_menu_item
	var is_equipped = (active_view_mode == ActiveView.EQUIPMENT)
	
	match action:
		"使う":
			_use_item(item)
		"投げる":
			_throw_item(item)
		"装備する":
			_equip_item(item)
		"外す":
			_unequip_item(item)
	
	context_menu_item = null
	context_menu_source_view = null

func _use_item(item: BaseItem):
	# バッグから消費アイテムを使用
	print("Using item: ", item.name)
	# 実装は既存のitem_activatedの処理を参照
	if item.is_consumable and player:
		if player.has_method("use_item"):
			player.use_item(item)
			# Update stats immediately after using item
			_update_stats()

func _throw_item(item: BaseItem):
	# 投げる処理
	print("Throwing item: ", item.name)
	# item_throw_requestシグナルを発火
	if context_menu_source_view and context_menu_source_view.has_signal("item_throw_request"):
		context_menu_source_view.emit_signal("item_throw_request", item)

func _equip_item(item: BaseItem):
	# バッグから装備
	print("Equipping item: ", item.name)
	if player and player.equipment_component:
		if player.equipment_component.equip_item(item):
			_update_stats()

func _unequip_item(item: BaseItem):
	# 装備を外す
	print("Unequipping item: ", item.name)
	if player and player.equipment_component:
		if player.equipment_component.unequip_item(item):
			_update_stats()

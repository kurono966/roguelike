extends Control

signal action_selected(action: String)

var item_list: ItemList
var current_item: BaseItem
var action_ids: Array[String] = []

func _ready():
	visible = false
	
	# 背景パネル
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	
	# アイテムリスト
	item_list = ItemList.new()
	item_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	item_list.offset_left = 5
	item_list.offset_top = 5
	item_list.offset_right = -5
	item_list.offset_bottom = -5
	item_list.focus_mode = Control.FOCUS_ALL
	add_child(item_list)
	
	item_list.item_activated.connect(_on_item_activated)

func show_menu(item: BaseItem, position: Vector2, is_equipped: bool = false, is_floor_item: bool = false):
	current_item = item
	action_ids.clear()
	item_list.clear()
	
	# アイテムの種類に応じて選択肢を追加
	if is_floor_item:
		# 足元のアイテム
		action_ids.append("pickup")
		item_list.add_item("拾う")
		
		# 装備可能なら装備オプションも追加
		if item.equipment_type >= 0:
			action_ids.append("equip")
			item_list.add_item("装備する")
		
		# 消費アイテムなら使用オプションも追加
		if item.effects.has("heal") or item.effects.has("mp") or item.effects.has("restore_hunger"):
			action_ids.append("use")
			item_list.add_item("使う")
	elif is_equipped:
		# 装備中
		action_ids.append("unequip")
		item_list.add_item("外す")
	elif item.equipment_type >= 0:
		# 装備可能（equipment_type が 0以上なら装備品）
		action_ids.append("equip")
		item_list.add_item("装備する")
	
	# バッグ内の消費アイテム（床アイテムの場合は上で処理済み）
	if not is_floor_item and (item.effects.has("heal") or item.effects.has("mp") or item.effects.has("restore_hunger")):
		action_ids.append("use")
		item_list.add_item("使う")
	
	# 投げる（すべてのアイテム）
	action_ids.append("throw")
	item_list.add_item("投げる")
	
	# キャンセル
	action_ids.append("cancel")
	item_list.add_item("キャンセル")
	
	# 位置とサイズを設定
	self.global_position = position
	self.size = Vector2(120, action_ids.size() * 25 + 10)
	
	# 画面内に収める
	var vp_size = get_viewport().get_visible_rect().size
	if self.global_position.x + self.size.x > vp_size.x:
		self.global_position.x = vp_size.x - self.size.x
	if self.global_position.y + self.size.y > vp_size.y:
		self.global_position.y = vp_size.y - self.size.y
	
	visible = true
	item_list.grab_focus()
	item_list.select(0)

func _on_item_activated(index: int):
	_select_action(index)

func _unhandled_input(event):
	if not visible:
		return
	
	# Enter/Space で決定
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
		var selected = item_list.get_selected_items()
		if selected.size() > 0:
			_select_action(selected[0])
		get_viewport().set_input_as_handled()
		return
	
	# ESC でキャンセル
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return

signal menu_closed

func close():
	hide()
	menu_closed.emit()

func _select_action(index: int):
	if index < 0 or index >= action_ids.size():
		return
	
	var action = action_ids[index]
	
	if action == "cancel":
		close()
	else:
		action_selected.emit(action)
		close()

extends Control

signal skill_selected(skill_id: String)

@onready var skill_list = $Panel/HBoxContainer/SkillListContainer/SkillList
@onready var description_label = $Panel/HBoxContainer/DescriptionContainer/DescriptionLabel
@onready var use_button = $Panel/HBoxContainer/DescriptionContainer/UseButton
@onready var mp_label = $Panel/HBoxContainer/DescriptionContainer/MPLabel
@onready var cd_label = $Panel/HBoxContainer/DescriptionContainer/CDLabel

const SkillDatabase = preload("res://skills/skill_database.gd")

var selected_skill_id: String = ""
var player_ref = null

# ドラッグ状態
var _drag_start_pos: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_threshold: float = 8.0  # ドラッグと判定する最小移動距離

func _ready():
	visible = false
	use_button.pressed.connect(_on_use_button_pressed)
	skill_list.item_selected.connect(_on_skill_selected)
	visibility_changed.connect(_on_visibility_changed)
	
	# スキルリストのGUI入力を処理してドラッグを検出
	skill_list.gui_input.connect(_on_skill_list_gui_input)

func _on_visibility_changed():
	if visible:
		if player_ref:
			_refresh_skill_list()
		# フォーカスをスキルリストに設定
		if skill_list.item_count > 0:
			skill_list.grab_focus()
			skill_list.select(0)
			_on_skill_selected(0)

func initialize(player):
	player_ref = player
	_refresh_skill_list()

func _refresh_skill_list():
	skill_list.clear()
	description_label.text = "スキルを選択してください。"
	use_button.disabled = true
	mp_label.text = ""
	cd_label.text = ""
	selected_skill_id = ""
	
	if not player_ref: return
	
	if "known_skills" in player_ref:
		for skill_id in player_ref.known_skills:
			var skill = SkillDatabase.get_skill_by_id(skill_id)
			if skill.is_empty(): continue
			
			var index = skill_list.add_item(skill.name)
			skill_list.set_item_metadata(index, skill_id)
			
			# Check logic for enabling/disabling visually?
			# Maybe change color if not enough MP
			if player_ref.mp < skill.mp_cost:
				skill_list.set_item_custom_fg_color(index, Color.RED)
			
			# Check cooldown
			if "skill_cooldowns" in player_ref and player_ref.skill_cooldowns.has(skill_id):
				skill_list.set_item_text(index, skill.name + " (CD)")
				skill_list.set_item_custom_fg_color(index, Color.GRAY)

func _on_skill_selected(index: int):
	selected_skill_id = skill_list.get_item_metadata(index)
	var skill = SkillDatabase.get_skill_by_id(selected_skill_id)
	
	var txt = "[b]%s[/b]\n\n" % skill.name
	
	if skill.get("is_magic", false):
		txt += "[color=cyan][魔法][/color]\n"
	
	txt += "%s\n\n" % skill.description
	
	txt += "消費MP: %d\n" % skill.mp_cost
	txt += "タイプ: %s\n" % skill.type
	
	if player_ref:
		if skill.get("damage", 0.0) > 0.0:
			if skill.get("is_magic", false):
				var dmg = int(skill.damage) + player_ref.intelligence
				txt += "威力: %d [color=cyan](知力補正込)[/color]\n" % dmg
			else:
				var pct = int(skill.damage * 100)
				txt += "威力: %d%% (通常攻撃力基準)\n" % pct
			
		if skill.get("heal_amount", 0) > 0:
			var heal = skill.heal_amount
			if skill.get("is_magic", false):
				heal += player_ref.intelligence
				txt += "回復量: %d [color=cyan](知力補正込)[/color]\n" % heal
			else:
				txt += "回復量: %d\n" % heal
	else:
		if skill.get("damage", 0.0) > 0.0:
			if skill.get("is_magic", false):
				txt += "威力: %d\n" % int(skill.damage)
			else:
				var pct = int(skill.damage * 100)
				txt += "威力: %d%%\n" % pct
		if skill.get("heal_amount", 0) > 0:
			txt += "回復量: %d\n" % skill.heal_amount
	
	if skill.get("range", 0) > 0:
			txt += "射程: %d\n" % skill.range
	
	# ドラッグ操作の説明を追記
	txt += "\n[color=gray][右下スキルバーにドラッグして並べ替え可能][/color]"
		
	description_label.text = txt
	
	# Check usability
	var can_use = true
	var status_msg = ""
	
	if player_ref.mp < skill.mp_cost:
		can_use = false
		status_msg += "[color=red]MPが足りません[/color]\n"
	
	if "skill_cooldowns" in player_ref and player_ref.skill_cooldowns.has(selected_skill_id):
		can_use = false
		var turns = player_ref.skill_cooldowns[selected_skill_id]
		status_msg += "[color=gray]クールダウン中 (あと%dターン)[/color]\n" % turns
		
	cd_label.text = status_msg
	use_button.disabled = !can_use

func _on_use_button_pressed():
	if selected_skill_id != "" and player_ref:
		hide()
		skill_selected.emit(selected_skill_id)
		if player_ref.has_method("use_skill"):
			player_ref.use_skill(selected_skill_id)

# ---- ドラッグ開始ハンドリング ----

func _on_skill_list_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# ドラッグ開始候補位置を記録
				_drag_start_pos = event.global_position
				_is_dragging = false
			else:
				# マウスを離した
				_is_dragging = false
	
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _is_dragging:
			# ドラッグ閾値を超えたらドラッグ開始
			var dist = event.global_position.distance_to(_drag_start_pos)
			if dist >= _drag_threshold and selected_skill_id != "":
				_is_dragging = true
				_begin_drag_to_skill_bar()

func _begin_drag_to_skill_bar():
	"""スキルメニューからスキルバーへのドラッグを開始"""
	if selected_skill_id == "": return
	
	# PlayerUIのdrag開始を呼ぶ
	var player_ui = get_node_or_null("/root/PlayerUi")
	if player_ui and player_ui.has_method("start_drag_from_menu"):
		player_ui.start_drag_from_menu(selected_skill_id)

func _unhandled_input(event):
	if visible:
		# Close menu
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_inventory") or event.is_action_pressed("toggle_skills"):
			hide()
			get_viewport().set_input_as_handled()
			return
		
		# Use skill with Enter key
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
			if selected_skill_id != "" and player_ref and not use_button.disabled:
				_on_use_button_pressed()
				get_viewport().set_input_as_handled()
			return

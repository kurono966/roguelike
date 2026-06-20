extends Node

# アクション名を直接使用
const ACTION_UP_LEFT = "ui_up_left"
const ACTION_UP_RIGHT = "ui_up_right"
const ACTION_DOWN_LEFT = "ui_down_left"
const ACTION_DOWN_RIGHT = "ui_down_right"
const ACTION_TARGET_ENEMY = "target_enemy"
const ACTION_TOGGLE_INVENTORY = "toggle_inventory"
const ACTION_TOGGLE_LOG = "toggle_log"
const ACTION_TOGGLE_SKILLS = "toggle_skills"

func _ready():
	print("InputManager: _ready() called")
	# 既存のアクションをクリア
	_clear_all_actions()
	
	# テンキーの斜め移動を設定
	_setup_numpad_inputs()
	
	# デバッグ用：現在のアクション一覧を表示
	print("InputMap actions: ", InputMap.get_actions())

func _clear_all_actions():
	# すべてのアクションを削除して再作成
	var actions = [
		ACTION_UP_LEFT, 
		ACTION_UP_RIGHT, 
		ACTION_DOWN_LEFT, 
		ACTION_DOWN_RIGHT, 
		ACTION_TARGET_ENEMY,
		ACTION_TOGGLE_INVENTORY,
		ACTION_TOGGLE_LOG
	]
	for action in actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)

func _setup_numpad_inputs():
	print("Setting up numpad inputs...")
	
	# インベントリ切り替えキーの設定
	if not InputMap.has_action(ACTION_TOGGLE_INVENTORY):
		InputMap.add_action(ACTION_TOGGLE_INVENTORY)
	
	# Iキーをインベントリ切り替えに割り当て
	var key = InputEventKey.new()
	key.keycode = KEY_I
	InputMap.action_add_event(ACTION_TOGGLE_INVENTORY, key)
	
	# ESCキーもインベントリを閉じるために使用可能に
	var esc_key = InputEventKey.new()
	esc_key.keycode = KEY_ESCAPE
	InputMap.action_add_event(ACTION_TOGGLE_INVENTORY, esc_key)
	
	print("Inventory toggle key (I/ESC) has been set up")
	
	# ログ切り替えキーの設定
	if not InputMap.has_action(ACTION_TOGGLE_LOG):
		InputMap.add_action(ACTION_TOGGLE_LOG)
	
	# Lキーをログ切り替えに割り当て
	var log_key = InputEventKey.new()
	log_key.keycode = KEY_L
	InputMap.action_add_event(ACTION_TOGGLE_LOG, log_key)
	print("Log toggle key (L) has been set up")

	# スキル切り替えキーの設定
	if not InputMap.has_action(ACTION_TOGGLE_SKILLS):
		InputMap.add_action(ACTION_TOGGLE_SKILLS)
	
	var skill_key = InputEventKey.new()
	skill_key.keycode = KEY_K
	InputMap.action_add_event(ACTION_TOGGLE_SKILLS, skill_key)
	print("Skill toggle key (K) has been set up")
	# 既存のイベントをクリア
	for action in [ACTION_UP_LEFT, ACTION_UP_RIGHT, ACTION_DOWN_LEFT, ACTION_DOWN_RIGHT, ACTION_TARGET_ENEMY]:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
	
	# タブキーで敵をターゲット
	var target_enemy = InputEventKey.new()
	target_enemy.keycode = KEY_TAB
	target_enemy.pressed = true
	InputMap.action_add_event(ACTION_TARGET_ENEMY, target_enemy)
	
	# ブラウザでタブキーが使えないためSキーも追加
	var target_enemy_s = InputEventKey.new()
	target_enemy_s.keycode = KEY_S
	target_enemy_s.pressed = true
	InputMap.action_add_event(ACTION_TARGET_ENEMY, target_enemy_s)
	
	print("  - Mapped TAB and S to ", ACTION_TARGET_ENEMY)
	
	# テンキー7/Home: 左上
	var up_left1 = InputEventKey.new()
	up_left1.keycode = KEY_KP_7
	up_left1.pressed = true
	InputMap.action_add_event(ACTION_UP_LEFT, up_left1)
	print("  - Mapped ", OS.get_keycode_string(KEY_KP_7), " to ", ACTION_UP_LEFT)
	
	var up_left2 = InputEventKey.new()
	up_left2.keycode = KEY_HOME
	up_left2.pressed = true
	InputMap.action_add_event(ACTION_UP_LEFT, up_left2)
	print("  - Mapped ", OS.get_keycode_string(KEY_HOME), " to ", ACTION_UP_LEFT)
	
	# テンキー9/PgUp: 右上
	var up_right1 = InputEventKey.new()
	up_right1.keycode = KEY_KP_9
	up_right1.pressed = true
	InputMap.action_add_event(ACTION_UP_RIGHT, up_right1)
	print("  - Mapped ", OS.get_keycode_string(KEY_KP_9), " to ", ACTION_UP_RIGHT)
	
	var up_right2 = InputEventKey.new()
	up_right2.keycode = KEY_PAGEUP
	up_right2.pressed = true
	InputMap.action_add_event(ACTION_UP_RIGHT, up_right2)
	print("  - Mapped ", OS.get_keycode_string(KEY_PAGEUP), " to ", ACTION_UP_RIGHT)
	
	# テンキー1/End: 左下
	var down_left1 = InputEventKey.new()
	down_left1.keycode = KEY_KP_1
	down_left1.pressed = true
	InputMap.action_add_event(ACTION_DOWN_LEFT, down_left1)
	print("  - Mapped ", OS.get_keycode_string(KEY_KP_1), " to ", ACTION_DOWN_LEFT)
	
	var down_left2 = InputEventKey.new()
	down_left2.keycode = KEY_END
	down_left2.pressed = true
	InputMap.action_add_event(ACTION_DOWN_LEFT, down_left2)
	print("  - Mapped ", OS.get_keycode_string(KEY_END), " to ", ACTION_DOWN_LEFT)
	
	# テンキー3/PgDn: 右下
	var down_right1 = InputEventKey.new()
	down_right1.keycode = KEY_KP_3
	down_right1.pressed = true
	InputMap.action_add_event(ACTION_DOWN_RIGHT, down_right1)
	print("  - Mapped ", OS.get_keycode_string(KEY_KP_3), " to ", ACTION_DOWN_RIGHT)
	
	var down_right2 = InputEventKey.new()
	down_right2.keycode = KEY_PAGEDOWN
	down_right2.pressed = true
	InputMap.action_add_event(ACTION_DOWN_RIGHT, down_right2)
	print("  - Mapped ", OS.get_keycode_string(KEY_PAGEDOWN), " to ", ACTION_DOWN_RIGHT)

	# Fullscreen Toggle (F11)
	if not InputMap.has_action("toggle_fullscreen"):
		InputMap.add_action("toggle_fullscreen")
	
	var f11_key = InputEventKey.new()
	f11_key.keycode = KEY_F11
	InputMap.action_add_event("toggle_fullscreen", f11_key)

func _unhandled_input(event):
	if event.is_action_pressed("toggle_fullscreen"):
		var mode = DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()

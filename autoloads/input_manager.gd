extends Node

# アクション名を直接使用
const ACTION_UP_LEFT = "ui_up_left"
const ACTION_UP_RIGHT = "ui_up_right"
const ACTION_DOWN_LEFT = "ui_down_left"
const ACTION_DOWN_RIGHT = "ui_down_right"

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
	var actions = [ACTION_UP_LEFT, ACTION_UP_RIGHT, ACTION_DOWN_LEFT, ACTION_DOWN_RIGHT]
	for action in actions:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)

func _setup_numpad_inputs():
	print("Setting up numpad inputs...")
	# 既存のイベントをクリア
	for action in [ACTION_UP_LEFT, ACTION_UP_RIGHT, ACTION_DOWN_LEFT, ACTION_DOWN_RIGHT]:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
	
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

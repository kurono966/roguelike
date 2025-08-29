extends SceneTree

func _init():
	# プロジェクト設定を読み込む
	var config = ConfigFile.new()
	var err = config.load("project.godot")
	if err != OK:
		print("Failed to load project.godot")
		return
	
	# autoloadのセクションを取得または作成
	var autoloads = {}
	if config.has_section("autoload"):
		autoloads = config.get_section_keys("autoload")
		for key in autoloads:
			autoloads[key] = config.get_value("autoload", key)
	
	# 既に登録されていないか確認
	var already_exists = false
	for key in autoloads:
		if autoloads[key] == "res://autoloads/input_manager.gd":
			print("InputManager is already in autoloads")
			quit()
			return
	
	# 新しいautoloadを追加
	var new_key = "InputManager"
	var counter = 1
	while autoloads.has(new_key):
		new_key = f"InputManager_{counter}"
		counter += 1
	
	# 設定に追加
	config.set_value("autoload", new_key, "res://autoloads/input_manager.gd")
	
	# 変更を保存
	err = config.save("project.godot")
	if err == OK:
		print("Successfully added InputManager to autoloads")
	else:
		print("Failed to save project.godot")
	
	quit()

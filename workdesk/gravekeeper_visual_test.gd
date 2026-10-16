extends SceneTree

func _initialize():
	call_deferred("run_test")

func run_test():
	var scene = load("res://actors/enemy/enemy.tscn")
	var keeper = scene.instantiate()
	keeper.apply_definition(EnemyDatabase.get_enemy_def("gravekeeper"))
	root.add_child(keeper)
	var sprite_image = keeper.get_node("Sprite2D").texture.get_image()
	assert(sprite_image.get_size() == Vector2i(32, 32))
	assert(sprite_image.get_pixel(12, 8).is_equal_approx(Color("85ffca")), "Ghost eye color missing")
	assert(sprite_image.get_data() != AsciiArtGenerator.create_ascii_sprite("G", keeper.base_color.lightened(0.25)).get_image().get_data(), "Keeper still uses generic G")
	keeper._load_enemy_sprite()
	assert(sprite_image.get_data() == keeper.get_node("Sprite2D").texture.get_image().get_data(), "Refreshing appearance lost custom sprite")
	if "--preview" in OS.get_cmdline_user_args():
		sprite_image.resize(320, 320, Image.INTERPOLATE_NEAREST)
		print("PREVIEW_DATA:", Marshalls.raw_to_base64(sprite_image.save_png_to_buffer()))
	print("GRAVEKEEPER_VISUAL_TEST passed")
	quit()

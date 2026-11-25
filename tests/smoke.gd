extends SceneTree
## Headless smoke test: loads the main scene, starts the game, simulates input and frames.
func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._start_game()
	for i in 600:
		if i % 90 == 10: main._jump()
		if i % 120 == 40: main._change_lane(1 if (i / 120) % 2 == 0 else -1)
		if i % 150 == 70: main._slide()
		await process_frame
	print("SMOKE_OK distance=", main.distance, " fish=", main.fish_count, " dead=", main.dead, " anim=", main.anim != null, " anims=", main.anim.get_animation_list() if main.anim else [])
	quit(0)
	return

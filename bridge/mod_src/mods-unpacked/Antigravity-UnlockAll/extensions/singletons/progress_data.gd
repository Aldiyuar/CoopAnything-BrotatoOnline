extends "res://singletons/progress_data.gd"

func is_unlock_all_save() -> bool:
	return false

func load_game_file(try_fallback: = true) -> void:
	.load_game_file(try_fallback)
	_unlock_everything()

func _unlock_everything() -> void:
	unlock_all()
	set_max_selectable_difficulty()
	if ZoneService:
		for zone in ZoneService.zones:
			if not zones_unlocked.has(zone.my_id):
				zones_unlocked.push_back(zone.my_id)
	if data:
		data["is_unlock_all_save"] = 0

extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"

const AI_DIFFICULTY_VALUE = 7
const AI_ICON_PATH = "res://mods-unpacked/Antigravity-UnlockAll/resources/difficulty_ai.png"

func _get_all_possible_elements(player_index: int) -> Array:
	var list = ._get_all_possible_elements(player_index)
	# Проверяем, есть ли уже сложность AI в списке
	var has_ai = false
	for d in list:
		if d.value == AI_DIFFICULTY_VALUE or d.my_id == "difficulty_ai":
			has_ai = true
			break
			
	if not has_ai:
		var ai_res = _create_ai_difficulty_resource()
		list.push_back(ai_res)
	return list

func _get_unlocked_elements(player_index: int) -> Array:
	var unlocked = ._get_unlocked_elements(player_index)
	var ai_hash = Keys.generate_hash("difficulty_ai")
	if not unlocked.has(ai_hash):
		unlocked.push_back(ai_hash)
	return unlocked

func _create_ai_difficulty_resource() -> DifficultyData:
	# Копируем параметры со сложности 5 или Nightmare
	var base_diff: DifficultyData = null
	for diff in ItemService.difficulties:
		if diff.value == 6 or diff.value == 5:
			base_diff = diff
			break

	var ai_diff: DifficultyData
	if base_diff:
		ai_diff = base_diff.duplicate(true)
	else:
		ai_diff = DifficultyData.new()

	ai_diff.my_id = "difficulty_ai"
	ai_diff.value = AI_DIFFICULTY_VALUE
	ai_diff.tier = 6
	ai_diff.name = "AI Autopilot"
	ai_diff.unlocked_by_default = true
	ai_diff.my_id_hash = Keys.generate_hash(ai_diff.my_id)

	var dir = Directory.new()
	if dir.file_exists(AI_ICON_PATH):
		var img = Image.new()
		if img.load(AI_ICON_PATH) == OK:
			var tex = ImageTexture.new()
			tex.create_from_image(img)
			ai_diff.icon = tex

	var effect = Effect.new()
	effect.text_key = "Режим DeepSeek ИИ-Автопилота (Автозакуп и прокачка)"
	effect.key = "ai_autopilot_mode"
	effect.value = 1
	ai_diff.effects = [effect]

	return ai_diff

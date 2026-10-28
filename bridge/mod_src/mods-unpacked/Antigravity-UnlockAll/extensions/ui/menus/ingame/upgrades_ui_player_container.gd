extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"

var _ai_upgrade_enabled: bool = true
var _upgrade_poll_timer: Timer = null
var _crate_poll_timer: Timer = null
var _is_processing_upgrade: bool = false
var _is_processing_crate: bool = false
var _active_upgrade_request_id: String = ""
var _active_crate_request_id: String = ""
var _upgrade_reroll_step: int = 0
var _upgrade_poll_ticks: int = 0
var _crate_poll_ticks: int = 0
var _upgrade_status_banner: Label = null

const UPGRADE_REQ_PATH = "D:/Brotato/bridge/upgrade_request.json"
const UPGRADE_DEC_PATH = "D:/Brotato/bridge/upgrade_decision.json"
const CRATE_REQ_PATH = "D:/Brotato/bridge/crate_request.json"
const CRATE_DEC_PATH = "D:/Brotato/bridge/crate_decision.json"

func _ready() -> void:
	._ready()
	_upgrade_reroll_step = 0
	_active_upgrade_request_id = ""
	_active_crate_request_id = ""
	_upgrade_poll_ticks = 0
	_crate_poll_ticks = 0
	# AI прокачка включается только если выбрана специальная сложность AI (значение 7)
	_ai_upgrade_enabled = (RunData.current_difficulty == 7)
	if _ai_upgrade_enabled:
		_setup_upgrade_status_ui()

func _setup_upgrade_status_ui() -> void:
	if _upgrade_status_banner == null and _upgrades_container:
		_upgrade_status_banner = Label.new()
		_upgrade_status_banner.name = "AI_Upgrade_Banner"
		_upgrade_status_banner.align = Label.ALIGN_CENTER
		_upgrade_status_banner.text = "AI"
		_upgrade_status_banner.modulate = Color(0.2, 1.0, 0.4, 1.0)
		
		var title_node = _upgrades_container.get_node_or_null("Title")
		if title_node:
			_upgrades_container.add_child(_upgrade_status_banner)
			_upgrades_container.move_child(_upgrade_status_banner, title_node.get_position_in_parent() + 1)
		else:
			_upgrades_container.add_child(_upgrade_status_banner)

# =====================================================================
# 1. ОБРАБОТКА ВЫБОРА ПРОКАЧКИ (LEVEL UP)
# =====================================================================

func show_upgrades_for_level(level: int) -> void:
	.show_upgrades_for_level(level)
	call_deferred("_start_ai_upgrade_flow")

func _start_ai_upgrade_flow() -> void:
	if not _ai_upgrade_enabled:
		return
	_is_processing_upgrade = false
	_upgrade_poll_ticks = 0
	_export_upgrade_data()
	_start_upgrade_poll_timer()

func _export_upgrade_data() -> void:
	_active_upgrade_request_id = "upg_w%s_lvl%s_r%s_%s" % [RunData.current_wave, _level, _upgrade_reroll_step, OS.get_ticks_msec()]
	
	var cur_char = RunData.get_player_character(player_index)
	var char_dict = {
		"name": cur_char.get_name_text() if cur_char else "Unknown",
		"id": cur_char.my_id if cur_char else "unknown"
	}
	
	var weapons_list = []
	for w in RunData.get_player_weapons(player_index):
		weapons_list.append({"name": w.get_name_text(), "tier": w.tier, "id": w.my_id})
		
	var stats_dict = {}
	if ItemService and ItemService.stats:
		for stat in ItemService.stats:
			var stat_name_clean = stat.stat_name.replace("stat_", "").capitalize()
			var stat_val = RunData.get_stat(Keys.generate_hash(stat.stat_name), player_index)
			stats_dict[stat_name_clean] = stat_val
			
	var upgrade_uis = _get_upgrade_uis()
	var options_list = []
	for i in range(upgrade_uis.size()):
		var ui = upgrade_uis[i]
		if ui.visible and ui.upgrade_data:
			var up_data = ui.upgrade_data
			var effects_list = []
			if up_data.effects:
				for eff in up_data.effects:
					var txt = eff.get_text(player_index, false)
					if txt != "" and txt != "[EMPTY]":
						effects_list.append(txt)
			options_list.append({
				"slot": i,
				"name": up_data.get_name_text(),
				"tier": up_data.tier,
				"id": up_data.my_id,
				"effects": effects_list
			})
			
	var export_data = {
		"request_id": _active_upgrade_request_id,
		"wave": RunData.current_wave,
		"level": _level,
		"reroll_step": _upgrade_reroll_step,
		"gold": RunData.get_player_gold(player_index),
		"reroll_price": _reroll_price,
		"character": char_dict,
		"stats": stats_dict,
		"equipped_weapons": weapons_list,
		"options": options_list
	}
	
	var dir = Directory.new()
	if not dir.dir_exists("D:/Brotato/bridge"):
		dir.make_dir_recursive("D:/Brotato/bridge")
		
	if dir.file_exists(UPGRADE_DEC_PATH):
		dir.remove(UPGRADE_DEC_PATH)
		
	var tmp_path = UPGRADE_REQ_PATH + ".tmp"
	var file = File.new()
	if file.open(tmp_path, File.WRITE) == OK:
		file.store_string(JSON.print(export_data, "\t"))
		file.close()
		if dir.file_exists(UPGRADE_REQ_PATH):
			dir.remove(UPGRADE_REQ_PATH)
		dir.rename(tmp_path, UPGRADE_REQ_PATH)
		ModLoaderLog.info("Exported atomic upgrade request (%s)" % _active_upgrade_request_id, "Antigravity:Autopilot")
	else:
		ModLoaderLog.error("Could not write upgrade request file", "Antigravity:Autopilot")

func _start_upgrade_poll_timer() -> void:
	_upgrade_poll_ticks = 0
	if _upgrade_poll_timer == null:
		_upgrade_poll_timer = Timer.new()
		_upgrade_poll_timer.name = "UpgradePollTimer"
		_upgrade_poll_timer.wait_time = 0.2
		_upgrade_poll_timer.autostart = false
		_upgrade_poll_timer.one_shot = false
		_upgrade_poll_timer.connect("timeout", self, "_check_for_upgrade_decision")
		add_child(_upgrade_poll_timer)
	_upgrade_poll_timer.start()

func _check_for_upgrade_decision() -> void:
	if not _ai_upgrade_enabled or _is_processing_upgrade:
		return

	_upgrade_poll_ticks += 1
	if _upgrade_poll_ticks > 60: # 12-15 секунд таймаут
		ModLoaderLog.warning("AI Upgrade Autopilot watchdog timeout (15s). Auto-choosing slot 0.", "Antigravity:Autopilot")
		_upgrade_poll_timer.stop()
		_is_processing_upgrade = false
		var upgrade_uis = _get_upgrade_uis()
		if upgrade_uis.size() > 0 and upgrade_uis[0].visible and upgrade_uis[0].upgrade_data:
			_on_choose_button_pressed(upgrade_uis[0].upgrade_data)
		return
		
	var file = File.new()
	if not file.file_exists(UPGRADE_DEC_PATH):
		return
		
	if file.open(UPGRADE_DEC_PATH, File.READ) != OK:
		return
		
	var content = file.get_as_text()
	file.close()
	
	if content.strip_edges() == "":
		return
		
	var parse_res = JSON.parse(content)
	if parse_res.error != OK:
		return
		
	var decision = parse_res.result
	if not (decision is Dictionary):
		return
		
	var resp_id = decision.get("request_id", "")
	if resp_id != "" and _active_upgrade_request_id != "" and resp_id != _active_upgrade_request_id:
		return
		
	_is_processing_upgrade = true
	_upgrade_poll_timer.stop()
	_apply_upgrade_decision(decision)

func _apply_upgrade_decision(decision: Dictionary) -> void:
	var action = decision.get("action", "choose")
	var dir = Directory.new()
	if dir.file_exists(UPGRADE_DEC_PATH):
		dir.remove(UPGRADE_DEC_PATH)
	if dir.file_exists(UPGRADE_REQ_PATH):
		dir.remove(UPGRADE_REQ_PATH)
		
	if action == "reroll":
		if RunData.get_player_gold(player_index) >= _reroll_price:
			_upgrade_reroll_step += 1
			yield(get_tree().create_timer(0.3), "timeout")
			_on_RerollButton_pressed()
			return
		else:
			# Денег на реролл не хватило, выбираем дефолтный слот 0
			action = "choose"
			
	if action == "choose":
		var slot = int(decision.get("slot", 0))
		var upgrade_uis = _get_upgrade_uis()
		if slot >= 0 and slot < upgrade_uis.size():
			var ui = upgrade_uis[slot]
			if ui.visible and ui.upgrade_data:
				yield(get_tree().create_timer(0.3), "timeout")
				_on_choose_button_pressed(ui.upgrade_data)
				_is_processing_upgrade = false
				_upgrade_reroll_step = 0
				return
				
	_is_processing_upgrade = false

# =====================================================================
# 2. ОБРАБОТКА СУНДУКОВ С ПРЕДМЕТАМИ (CRATES / CONSUMABLES)
# =====================================================================

func show_item(item_data: ItemParentData) -> void:
	.show_item(item_data)
	if _ai_upgrade_enabled:
		call_deferred("_start_ai_crate_flow", item_data)

func _start_ai_crate_flow(item_data: ItemParentData) -> void:
	if not _ai_upgrade_enabled or item_data == null:
		return
	_is_processing_crate = false
	_crate_poll_ticks = 0
	_export_crate_data(item_data)
	_start_crate_poll_timer()

func _export_crate_data(item_data: ItemParentData) -> void:
	_active_crate_request_id = "crate_w%s_%s" % [RunData.current_wave, OS.get_ticks_msec()]

	var cur_char = RunData.get_player_character(player_index)
	var char_dict = {
		"name": cur_char.get_name_text() if cur_char else "Unknown",
		"id": cur_char.my_id if cur_char else "unknown"
	}

	var weapons_list = []
	for w in RunData.get_player_weapons(player_index):
		weapons_list.append({"name": w.get_name_text(), "tier": w.tier, "id": w.my_id})

	var effects_list = []
	if item_data.effects:
		for eff in item_data.effects:
			var txt = eff.get_text(player_index, false)
			if txt != "" and txt != "[EMPTY]":
				effects_list.append(txt)

	var it_dict = {
		"name": item_data.get_name_text(),
		"id": item_data.my_id,
		"type": "Weapon" if item_data is WeaponData else "Item",
		"tier": item_data.tier,
		"effects": effects_list
	}

	var export_data = {
		"request_id": _active_crate_request_id,
		"wave": RunData.current_wave,
		"character": char_dict,
		"equipped_weapons": weapons_list,
		"item": it_dict
	}

	var dir = Directory.new()
	if not dir.dir_exists("D:/Brotato/bridge"):
		dir.make_dir_recursive("D:/Brotato/bridge")

	if dir.file_exists(CRATE_DEC_PATH):
		dir.remove(CRATE_DEC_PATH)

	var tmp_path = CRATE_REQ_PATH + ".tmp"
	var file = File.new()
	if file.open(tmp_path, File.WRITE) == OK:
		file.store_string(JSON.print(export_data, "\t"))
		file.close()
		if dir.file_exists(CRATE_REQ_PATH):
			dir.remove(CRATE_REQ_PATH)
		dir.rename(tmp_path, CRATE_REQ_PATH)
		ModLoaderLog.info("Exported atomic crate request (%s)" % _active_crate_request_id, "Antigravity:Autopilot")
	else:
		ModLoaderLog.error("Could not write crate request file", "Antigravity:Autopilot")

func _start_crate_poll_timer() -> void:
	_crate_poll_ticks = 0
	if _crate_poll_timer == null:
		_crate_poll_timer = Timer.new()
		_crate_poll_timer.name = "CratePollTimer"
		_crate_poll_timer.wait_time = 0.2
		_crate_poll_timer.autostart = false
		_crate_poll_timer.one_shot = false
		_crate_poll_timer.connect("timeout", self, "_check_for_crate_decision")
		add_child(_crate_poll_timer)
	_crate_poll_timer.start()

func _check_for_crate_decision() -> void:
	if not _ai_upgrade_enabled or _is_processing_crate:
		return

	_crate_poll_ticks += 1
	if _crate_poll_ticks > 60: # 12-15 секунд таймаут
		ModLoaderLog.warning("AI Crate Autopilot watchdog timeout. Defaulting to TAKE.", "Antigravity:Autopilot")
		_crate_poll_timer.stop()
		_is_processing_crate = false
		_on_TakeButton_pressed()
		return

	var file = File.new()
	if not file.file_exists(CRATE_DEC_PATH):
		return

	if file.open(CRATE_DEC_PATH, File.READ) != OK:
		return

	var content = file.get_as_text()
	file.close()

	if content.strip_edges() == "":
		return

	var parse_res = JSON.parse(content)
	if parse_res.error != OK:
		return

	var decision = parse_res.result
	if not (decision is Dictionary):
		return

	var resp_id = decision.get("request_id", "")
	if resp_id != "" and _active_crate_request_id != "" and resp_id != _active_crate_request_id:
		return

	_is_processing_crate = true
	_crate_poll_timer.stop()
	_apply_crate_decision(decision)

func _apply_crate_decision(decision: Dictionary) -> void:
	var action = decision.get("action", "take")
	var dir = Directory.new()
	if dir.file_exists(CRATE_DEC_PATH):
		dir.remove(CRATE_DEC_PATH)
	if dir.file_exists(CRATE_REQ_PATH):
		dir.remove(CRATE_REQ_PATH)

	yield(get_tree().create_timer(0.3), "timeout")
	if action == "discard":
		ModLoaderLog.info("AI Autopilot discarded crate item (recycled for materials)", "Antigravity:Autopilot")
		_on_DiscardButton_pressed()
	else:
		ModLoaderLog.info("AI Autopilot took crate item", "Antigravity:Autopilot")
		_on_TakeButton_pressed()

	_is_processing_crate = false

extends "res://ui/menus/shop/shop.gd"

var _autopilot_enabled: bool = true
var _poll_timer: Timer = null
var _status_banner: Label = null
var _is_processing_decision: bool = false
var _active_request_id: String = ""
var _ai_reroll_step: int = 0
var _poll_ticks: int = 0

const REQ_PATH = "D:/Brotato/bridge/shop_request.json"
const DEC_PATH = "D:/Brotato/bridge/shop_decision.json"

func _ready() -> void:
	._ready()
	_ai_reroll_step = 0
	_active_request_id = ""
	# AI включается только если выбрана специальная сложность AI (значение 7)
	_autopilot_enabled = (RunData.current_difficulty == 7)
	if _autopilot_enabled:
		_setup_status_ui()
		call_deferred("_start_autopilot")

func _setup_status_ui() -> void:
	if _status_banner == null:
		_status_banner = Label.new()
		_status_banner.name = "AI_Autopilot_Banner"
		_status_banner.align = Label.ALIGN_CENTER
		_status_banner.text = "AI"
		_status_banner.modulate = Color(0.2, 1.0, 0.4, 1.0)
		
		if _title and _title.get_parent():
			_title.get_parent().add_child(_status_banner)
			_title.get_parent().move_child(_status_banner, _title.get_position_in_parent() + 1)
		else:
			add_child(_status_banner)

func _input(event: InputEvent) -> void:
	._input(event)
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_F2:
		_autopilot_enabled = not _autopilot_enabled
		if _status_banner:
			if _autopilot_enabled:
				_status_banner.text = "AI"
				_status_banner.modulate = Color(0.2, 1.0, 0.4, 1.0)
				_start_autopilot()
			else:
				_status_banner.text = "AI (OFF)"
				_status_banner.modulate = Color(1.0, 0.4, 0.2, 1.0)
				if _poll_timer:
					_poll_timer.stop()

func _start_autopilot() -> void:
	if not _autopilot_enabled:
		return
	_is_processing_decision = false
	_export_shop_data()
	_start_poll_timer()

func _export_shop_data() -> void:
	var player_index = 0
	var player_data = RunData.players_data[player_index]
	var cur_char = player_data.current_character
	
	_active_request_id = "req_w%s_r%s_%s" % [RunData.current_wave, _ai_reroll_step, OS.get_ticks_msec()]
	
	var char_dict = {
		"name": cur_char.get_name_text() if cur_char else "Unknown",
		"id": cur_char.my_id if cur_char else "unknown",
		"bonuses_and_penalties": []
	}
	if cur_char and cur_char.effects:
		for eff in cur_char.effects:
			var txt = eff.get_text(player_index, false)
			if txt != "" and txt != "[EMPTY]":
				char_dict.bonuses_and_penalties.append(txt)
	
	var stats_dict = {}
	if ItemService and ItemService.stats:
		for stat in ItemService.stats:
			var stat_name_clean = stat.stat_name.replace("stat_", "").capitalize()
			var stat_val = RunData.get_stat(Keys.generate_hash(stat.stat_name), player_index)
			stats_dict[stat_name_clean] = stat_val
	
	var weapons_list = []
	var weapons = RunData.get_player_weapons(player_index)
	for w in weapons:
		weapons_list.append({
			"name": w.get_name_text(),
			"tier": w.tier,
			"id": w.my_id
		})
	
	var items_list = []
	var items = RunData.get_player_items(player_index)
	for it in items:
		items_list.append({
			"name": it.get_name_text(),
			"count": RunData.get_nb_item(it.my_id_hash, player_index),
			"id": it.my_id
		})
	
	var shop_items_list = []
	var container = _get_shop_items_container(player_index)
	if container:
		for i in range(4):
			var shop_item_node = container.get_shop_item_node(i)
			if shop_item_node and shop_item_node.item_data:
				var it_data = shop_item_node.item_data
				var effects_list = []
				if it_data.effects:
					for eff in it_data.effects:
						var t = eff.get_text(player_index, false)
						if t != "" and t != "[EMPTY]":
							effects_list.append(t)
				if it_data is WeaponData:
					var w_stats = it_data.get_weapon_stats_text(player_index)
					if w_stats != "":
						effects_list.append(w_stats)
				
				shop_items_list.append({
					"slot": i,
					"name": it_data.get_name_text(),
					"id": it_data.my_id,
					"type": "Weapon" if it_data is WeaponData else "Item",
					"tier": it_data.tier,
					"price": shop_item_node.value,
					"locked": shop_item_node.locked,
					"active": shop_item_node.active,
					"effects": effects_list
				})
	
	var export_data = {
		"request_id": _active_request_id,
		"wave": RunData.current_wave,
		"reroll_count": _ai_reroll_step,
		"gold": RunData.get_player_gold(player_index),
		"reroll_price": _reroll_price[player_index] if _reroll_price.size() > player_index else 0,
		"character": char_dict,
		"stats": stats_dict,
		"equipped_weapons": weapons_list,
		"items": items_list,
		"shop_items": shop_items_list
	}
	
	var dir = Directory.new()
	if not dir.dir_exists("D:/Brotato/bridge"):
		dir.make_dir_recursive("D:/Brotato/bridge")
	
	if dir.file_exists(DEC_PATH):
		dir.remove(DEC_PATH)
	
	var tmp_path = REQ_PATH + ".tmp"
	var file = File.new()
	if file.open(tmp_path, File.WRITE) == OK:
		file.store_string(JSON.print(export_data, "\t"))
		file.close()
		if dir.file_exists(REQ_PATH):
			dir.remove(REQ_PATH)
		dir.rename(tmp_path, REQ_PATH)
		ModLoaderLog.info("Exported atomic shop request (%s)" % _active_request_id, "Antigravity:Autopilot")
	else:
		ModLoaderLog.error("Could not write shop request file", "Antigravity:Autopilot")

func _start_poll_timer() -> void:
	_poll_ticks = 0
	if _status_banner:
		_status_banner.text = "AI (Анализ витрины...)"
	if _poll_timer == null:
		_poll_timer = Timer.new()
		_poll_timer.name = "AutopilotPollTimer"
		_poll_timer.wait_time = 0.25
		_poll_timer.autostart = false
		_poll_timer.one_shot = false
		_poll_timer.connect("timeout", self, "_check_for_decision")
		add_child(_poll_timer)
	_poll_timer.start()

func _check_for_decision() -> void:
	if not _autopilot_enabled or _is_processing_decision:
		return

	_poll_ticks += 1
	if _poll_ticks > 60:
		ModLoaderLog.warning("AI Shop Autopilot watchdog timeout (15s). Auto-proceeding to next wave.", "Antigravity:Autopilot")
		_poll_timer.stop()
		_is_processing_decision = false
		if _status_banner:
			_status_banner.text = "AI (Таймаут)"
			_status_banner.modulate = Color(1.0, 0.6, 0.2, 1.0)
		yield(get_tree().create_timer(0.8), "timeout")
		_on_GoButton_pressed(0)
		return
	
	var file = File.new()
	if not file.file_exists(DEC_PATH):
		return
		
	if file.open(DEC_PATH, File.READ) != OK:
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
	if resp_id != "" and _active_request_id != "" and resp_id != _active_request_id:
		return
		
	_is_processing_decision = true
	_poll_timer.stop()
	_apply_decision(decision)

func _apply_decision(decision: Dictionary) -> void:
	if _status_banner:
		_status_banner.text = "AI (Покупка...)"
	
	var container = _get_shop_items_container(0)
	
	# 1. Применяем действия (buy / lock / unlock)
	if decision.has("actions") and (decision.actions is Array):
		for act in decision.actions:
			if not (act is Dictionary):
				continue
			var action_type = act.get("action", "")
			var slot = int(act.get("slot", -1))
			if slot >= 0 and slot < 4 and container:
				var node = container.get_shop_item_node(slot)
				if node and node.active:
					if action_type == "buy":
						if RunData.get_player_currency(0) >= node.value:
							container.on_shop_item_buy_button_pressed(node)
							yield(get_tree().create_timer(0.2), "timeout")
					elif action_type == "lock":
						if not node.locked:
							node.change_lock_status(true)
					elif action_type == "unlock":
						if node.locked:
							node.change_lock_status(false)
	
	# 2. Реролл, если запрошен ИИ
	var did_reroll = false
	if decision.get("reroll", false):
		if RunData.get_player_currency(0) >= _reroll_price[0]:
			_on_RerollButton_pressed(0)
			did_reroll = true
			_ai_reroll_step += 1
			yield(get_tree().create_timer(0.35), "timeout")
	
	# 3. Очистка файлов IPC
	var dir = Directory.new()
	if dir.file_exists(DEC_PATH):
		dir.remove(DEC_PATH)
	if dir.file_exists(REQ_PATH):
		dir.remove(REQ_PATH)
	
	# 4. Если был реролл, отправляем новый запрос для обновленной витрины!
	if did_reroll:
		_is_processing_decision = false
		_export_shop_data()
		_start_poll_timer()
		return
	
	# 5. Переход к следующей волне
	if decision.get("go_next", true):
		if _status_banner:
			_status_banner.text = "AI (Готово)"
			_status_banner.modulate = Color(0.2, 1.0, 0.4, 1.0)
		yield(get_tree().create_timer(0.6), "timeout")
		_on_GoButton_pressed(0)
	else:
		_is_processing_decision = false

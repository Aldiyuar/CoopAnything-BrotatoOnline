extends "res://ui/menus/shop/coop_shop.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

var _reroll_pending: bool = false

func _enter_tree() -> void:
	NetworkLogger.info("CoopShop: _enter_tree called (players in RunData: %d)" % RunData.get_player_count(), "CoopAnything")

func _ready() -> void:
	NetworkLogger.info("CoopShop: _ready extension entered", "CoopAnything")
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if not net.is_connected("shop_ready_state_changed", self, "_on_network_shop_ready_state_changed"):
			net.connect("shop_ready_state_changed", self, "_on_network_shop_ready_state_changed")
	call_deferred("_setup_coop_shop_network")

func _on_game_lost_focus() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		# Do not pause online coop game on focus lost!
		return
	._on_game_lost_focus()

func _on_GoButton_focus_exited(player_index: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		# Do NOT cancel ready status on focus loss in online co-op!
		return
	._on_GoButton_focus_exited(player_index)

func _on_GoButton_pressed(player_index: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online():
		._on_GoButton_pressed(player_index)
		return
	
	if get_tree().paused:
		return
	
	NetworkLogger.info("CoopShop: _on_GoButton_pressed for player %d (local player: %d, role: %d)" % [player_index, net.my_player_index, net.role], "CoopAnything")
	
	# Only allow the player assigned to this slot to toggle their own ready button
	if player_index != net.my_player_index:
		NetworkLogger.info("CoopShop: Ignoring GoButton click for remote player %d (local player is %d)" % [player_index, net.my_player_index], "CoopAnything")
		return
	
	var is_currently_ready = _player_pressed_go_button[player_index] if player_index < _player_pressed_go_button.size() else false
	var new_ready = not is_currently_ready
	
	# Update local UI immediately
	set_player_ready_ui(player_index, new_ready)
	
	# Broadcast ready state to all peers
	net.rpc("rpc_notify_shop_ready", player_index, new_ready)

func _on_network_shop_ready_state_changed(player_index: int, is_ready: bool) -> void:
	set_player_ready_ui(player_index, is_ready)

func set_player_ready_ui(player_index: int, is_ready: bool) -> void:
	if player_index < _player_pressed_go_button.size():
		_player_pressed_go_button[player_index] = is_ready
	var checkmark = _get_checkmark(player_index)
	if checkmark != null:
		if is_ready:
			checkmark.show()
		else:
			checkmark.hide()
	NetworkLogger.info("CoopShop: UI checkmark for player %d set to: %s" % [player_index + 1, str(is_ready)], "CoopAnything")

func _on_RerollButton_pressed(player_index: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online():
		._on_RerollButton_pressed(player_index)
		return
	
	if net.is_client():
		if player_index == net.my_player_index and not _reroll_pending:
			_on_client_reroll_pressed()
		return
	
	# Host: execute native reroll then sync authoritative items to all peers
	._on_RerollButton_pressed(player_index)
	var gold_after = RunData.get_player_gold(player_index)
	var serialized_items = []
	var locked_count = 0
	if _shop_items.size() > player_index:
		serialized_items = net._serialize_shop_items(_shop_items[player_index])
	if RunData.has_method("get_player_locked_shop_items"):
		locked_count = RunData.get_player_locked_shop_items(player_index).size()
	net.rpc("rpc_confirm_shop_reroll", player_index, gold_after, serialized_items, locked_count)

func on_shop_item_bought(shop_item, player_index: int) -> void:
	.on_shop_item_bought(shop_item, player_index)
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_host():
		var gold_after = RunData.get_player_gold(player_index)
		var item_res_path = net.get_resource_path(shop_item.item_data) if net.has_method("get_resource_path") else ""
		var slot_idx = 0
		var cont = _get_shop_items_container(player_index)
		if cont and "_shop_items" in cont:
			var idx = cont._shop_items.find(shop_item)
			if idx != -1:
				slot_idx = idx
		net.rpc("rpc_confirm_shop_buy", player_index, slot_idx, gold_after, item_res_path)

func advance_to_next_wave(next_wave: int = -1) -> void:
	NetworkLogger.success("CoopShop: Advancing to next wave...", "CoopAnything")
	for p in range(RunData.get_player_count()):
		_player_pressed_go_button[p] = true
	
	ProgressData.save_run_state(_shop_items, _reroll_count, _paid_reroll_count, _initial_free_rerolls, _free_rerolls, _item_steals)
	
	for p in RunData.get_player_count():
		if RunData.get_player_effects(p).has(Keys.used_item_locking_hash):
			if not ChallengeService.is_challenge_completed(ChallengeService.chal_candy_bag_hash) and not RunData.get_player_effect_bool(Keys.used_item_locking_hash, p):
				var shop_item_containers = _get_shop_items_container(p)
				for shop_item in shop_item_containers._shop_items:
					if shop_item != null and shop_item.active and shop_item.locked:
						var effects = RunData.get_player_effects(p)
						effects[Keys.used_item_locking_hash] = 1

	if next_wave > 0:
		RunData.current_wave = next_wave
	else:
		var wave_reset_count: = 0
		for p in RunData.get_player_count():
			var effects = RunData.get_player_effects(p)
			var hourglass_count = effects[Keys.item_hourglass_hash] if effects.has(Keys.item_hourglass_hash) else 0
			if hourglass_count > 0:
				wave_reset_count += hourglass_count
				var source_item = RunData.get_player_item(Keys.item_hourglass_hash, p)
				RunData.remove_item(source_item, p)

			var extra_elite_spawn_chance = effects[Keys.extra_elite_next_wave_chance_hash] if effects.has(Keys.extra_elite_next_wave_chance_hash) else 0
			if Utils.get_chance_success(float(extra_elite_spawn_chance) / 100):
				var rand_elite_id = ItemService.get_random_elite_id_hash_from_zone(ZoneService.current_zone.my_id)
				effects[Keys.extra_enemies_next_wave_hash].append(["res://zones/common/elite/group_elite.tres", 1, rand_elite_id])

		RunData.current_wave += 1 - wave_reset_count

	NetworkLogger.info("CoopShop: Wave set to %d. Loading game_scene..." % RunData.current_wave, "CoopAnything")
	var target_scene = MenuData.game_scene if (MenuData and MenuData.game_scene != "" and MenuData.game_scene != "res://") else "res://main.tscn"
	var _error = get_tree().change_scene(target_scene)

func _setup_coop_shop_network() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online():
		return
	
	NetworkLogger.info("CoopShop: Setting up online shop network hooks for %d players" % RunData.get_player_count(), "CoopAnything")
	
	# Sync initial ready states if any are already recorded
	for p in range(RunData.get_player_count()):
		if net.shop_ready_states.get(p, false):
			set_player_ready_ui(p, true)
	
	if net.is_host():
		var all_shops = {}
		for p in range(RunData.get_player_count()):
			if p < _shop_items.size():
				all_shops[p] = net._serialize_shop_items(_shop_items[p])
		net.cached_initial_shop_items = all_shops
		net.rpc("rpc_sync_initial_shop_items", all_shops)
	elif net.is_client():
		if net.cached_initial_shop_items.size() > 0:
			net.rpc_sync_initial_shop_items(net.cached_initial_shop_items)
	
	var target_player = net.my_player_index
	var container = _get_coop_player_container(target_player) if target_player < CoopService.UI_MAX_PLAYER_COUNT else null
	if container:
		# Note: RerollButton is handled natively via overridden _on_RerollButton_pressed
		# Hook BuyButtons and LockButtons on the ShopItems for local player
		var items_container = _get_shop_items_container(target_player)
		if items_container:
			for slot in range(items_container._shop_items.size()):
				var item = items_container.get_shop_item_node(slot)
				if item:
					var buy_btn = item.get_node_or_null("%BuyButton")
					if not buy_btn:
						buy_btn = item.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/BuyButton")
					if buy_btn and not buy_btn.is_connected("pressed", self, "_on_client_buy_pressed"):
						buy_btn.connect("pressed", self, "_on_client_buy_pressed", [slot])
					
					var lock_btn = item.get_node_or_null("%LockButton")
					if not lock_btn:
						lock_btn = item.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/LockButton")
					if not lock_btn and "_lock_button" in item:
						lock_btn = item._lock_button
					if lock_btn and not lock_btn.is_connected("toggled", self, "_on_client_lock_toggled"):
						lock_btn.connect("toggled", self, "_on_client_lock_toggled", [slot])

func _on_client_buy_pressed(slot_idx: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Shop BUY clicked for player %d slot %d, sending RPC to host..." % [net.my_player_index, slot_idx], "CoopAnything")
		net.rpc_id(1, "rpc_request_shop_buy", net.my_player_index, slot_idx)

func _on_client_lock_toggled(button_pressed: bool, slot_idx: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Shop LOCK toggled for slot %d (%s), sending RPC to host..." % [slot_idx, str(button_pressed)], "CoopAnything")
		net.rpc_id(1, "rpc_request_shop_lock", net.my_player_index, slot_idx, button_pressed)

func _on_client_reroll_pressed() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		_reroll_pending = true
		NetworkLogger.info("Client: Shop REROLL clicked for player %d, sending RPC to host..." % net.my_player_index, "CoopAnything")
		net.rpc_id(1, "rpc_request_shop_reroll", net.my_player_index)

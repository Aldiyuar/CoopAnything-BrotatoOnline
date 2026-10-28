extends "res://ui/menus/shop/coop_shop.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

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
	var _error = get_tree().change_scene(MenuData.game_scene)

func _setup_coop_shop_network() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online():
		return
	
	NetworkLogger.info("CoopShop: Setting up online shop network hooks for %d players" % RunData.get_player_count(), "CoopAnything")
	
	# Sync initial ready states if any are already recorded
	for p in range(RunData.get_player_count()):
		if net.shop_ready_states.get(p, false):
			set_player_ready_ui(p, true)
	
	var container2 = get_node_or_null("Content/HBoxContainer2/CoopShopPlayerContainer2")
	if not container2:
		container2 = get_node_or_null("%CoopShopPlayerContainer2")
	if container2:
		# Hook RerollButton for Player 2
		var reroll_btn = container2.get_node_or_null("%RerollButton")
		if not reroll_btn:
			reroll_btn = container2.get_node_or_null("MarginContainer/Carousel/Content/VBoxContainer/HBoxContainer/RerollButton")
		if reroll_btn and not reroll_btn.is_connected("pressed", self, "_on_client_reroll_pressed"):
			reroll_btn.connect("pressed", self, "_on_client_reroll_pressed")
			
		# Hook BuyButtons on the 4 ShopItems for Player 2
		var items_vbox = container2.get_node_or_null("%ShopItemsContainer")
		if not items_vbox:
			items_vbox = container2.get_node_or_null("MarginContainer/Carousel/Content/VBoxContainer/PanelContainer/ShopItemsContainer")
		if items_vbox:
			var slot = 0
			for child in items_vbox.get_children():
				if child is Control and child.has_method("_on_BuyButton_pressed"):
					var buy_btn = child.get_node_or_null("%BuyButton")
					if not buy_btn:
						buy_btn = child.get_node_or_null("PanelContainer/MarginContainer/VBoxContainer/BuyButton")
					if buy_btn and not buy_btn.is_connected("pressed", self, "_on_client_buy_pressed"):
						buy_btn.connect("pressed", self, "_on_client_buy_pressed", [slot])
					slot += 1

func _on_client_buy_pressed(slot_idx: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Shop BUY clicked for slot %d, sending RPC to host..." % slot_idx, "CoopAnything")
		net.rpc_id(1, "rpc_request_shop_buy", 1, slot_idx)

func _on_client_reroll_pressed() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Shop REROLL clicked, sending RPC to host...", "CoopAnything")
		net.rpc_id(1, "rpc_request_shop_reroll", 1)

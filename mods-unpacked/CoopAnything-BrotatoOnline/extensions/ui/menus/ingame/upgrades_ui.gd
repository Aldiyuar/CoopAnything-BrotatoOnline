extends "res://ui/menus/ingame/upgrades_ui.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

func _ready() -> void:
	call_deferred("_setup_upgrades_network")

func _show_next_player_options() -> bool:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_client():
		# On Client, we only process choices for our own player slot (my_player_index)
		# Remote Host choices are handled on the Host machine
		for p_idx in RunData.get_player_count():
			if p_idx != net.my_player_index:
				if p_idx < _consumables_to_process.size():
					_consumables_to_process[p_idx].clear()
				if p_idx < _upgrades_to_process.size():
					_upgrades_to_process[p_idx].clear()
				if p_idx < _extra_items_to_process.size():
					_extra_items_to_process[p_idx].clear()
				if p_idx < _player_is_choosing.size():
					_player_is_choosing[p_idx] = false
				var container = _get_player_container(p_idx)
				if container:
					container.finish()
	return ._show_next_player_options()

func _setup_upgrades_network() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online():
		return
	
	NetworkLogger.info("UpgradesUI: Initialized online upgrade/crate network hooks", "CoopAnything")
	
	var target_player = net.my_player_index
	var player_container = _get_player_container(target_player) if target_player < _things_to_process_player_containers.size() else null
	if not player_container:
		player_container = get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer" + str(target_player + 1))
	if not player_container:
		player_container = get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/UpgradesUIPlayerContainer" + str(target_player + 1))
	if not player_container:
		player_container = get_node_or_null("Content/HBoxContainer2/CoopUpgradesUIPlayerContainer" + str(target_player + 1))
		
	if player_container:
		# Hook stat upgrade choose buttons
		if player_container.has_method("_get_upgrade_uis"):
			var slot = 0
			for upgrade_card in player_container._get_upgrade_uis():
				var choose_btn = upgrade_card.get_node_or_null("ChooseButton")
				if choose_btn and not choose_btn.is_connected("pressed", self, "_on_client_upgrade_chosen"):
					choose_btn.connect("pressed", self, "_on_client_upgrade_chosen", [slot])
				slot += 1
		else:
			var upgrades_vbox = player_container.get_node_or_null("MarginContainer/VBoxContainer/Carousel/Content/MarginContainer/VBoxContainer/UpgradesContainer")
			if upgrades_vbox:
				var slot = 0
				for upgrade_card in upgrades_vbox.get_children():
					var choose_btn = upgrade_card.get_node_or_null("ChooseButton")
					if choose_btn and not choose_btn.is_connected("pressed", self, "_on_client_upgrade_chosen"):
						choose_btn.connect("pressed", self, "_on_client_upgrade_chosen", [slot])
					slot += 1
					
		# Hook TakeButton for crate items
		var take_btn = player_container.get_node_or_null("%TakeButton")
		if not take_btn:
			take_btn = player_container.get_node_or_null("MarginContainer/VBoxContainer/Carousel/Content/MarginContainer/VBoxContainer/ItemsContainer/HBoxContainer/TakeButton")
		if take_btn and not take_btn.is_connected("pressed", self, "_on_client_crate_taken"):
			take_btn.connect("pressed", self, "_on_client_crate_taken")
			
		# Hook DiscardButton for recycling crate items
		var discard_btn = player_container.get_node_or_null("%DiscardButton")
		if not discard_btn:
			discard_btn = player_container.get_node_or_null("MarginContainer/VBoxContainer/Carousel/Content/MarginContainer/VBoxContainer/ItemsContainer/HBoxContainer/DiscardButton")
		if discard_btn and not discard_btn.is_connected("pressed", self, "_on_client_crate_discarded"):
			discard_btn.connect("pressed", self, "_on_client_crate_discarded")

func _on_client_upgrade_chosen(slot_idx: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Clicked upgrade card %d for player %d, sending RPC to host..." % [slot_idx, net.my_player_index], "CoopAnything")
		net.rpc_id(1, "rpc_request_upgrade", net.my_player_index, slot_idx)

func _on_client_crate_taken() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Clicked crate TAKE for player %d, sending RPC to host..." % net.my_player_index, "CoopAnything")
		net.rpc_id(1, "rpc_request_crate_take", net.my_player_index)

func _on_client_crate_discarded() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_client():
		NetworkLogger.info("Client: Clicked crate DISCARD for player %d, sending RPC to host..." % net.my_player_index, "CoopAnything")
		net.rpc_id(1, "rpc_request_crate_discard", net.my_player_index)

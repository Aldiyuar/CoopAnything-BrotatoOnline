extends "res://singletons/coop_service.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")
const NETWORK_DEVICE_OFFSET: int = 100

func _ready() -> void:
	call_deferred("_init_coop_players")

func _init_coop_players() -> void:
	# Register dummy InputMap actions for virtual network devices (100..103)
	# so Godot engine never throws missing action errors if queried
	for dev in [100, 101, 102, 103]:
		for act in ["ui_pause", "ui_cancel", "ui_select", "ui_up", "ui_down", "ui_left", "ui_right", "ui_info", "ui_ban"]:
			var a = "%s_%d" % [act, dev]
			if not InputMap.has_action(a):
				InputMap.add_action(a)
	setup_coop_players(UI_MAX_PLAYER_COUNT)

func get_remapped_player_device(player_index: int) -> int:
	if player_index < 0 or player_index >= len(connected_players):
		return -1
	return connected_players[player_index][0]

func is_player_using_gamepad(player_index: int) -> bool:
	if player_index < 0 or player_index >= len(connected_players):
		return false
	var dev = connected_players[player_index][0]
	if is_network_device(dev):
		return false
	return connected_players[player_index][1] == PlayerType.GAMEPAD

func setup_coop_players(count: int = UI_MAX_PLAYER_COUNT) -> void:
	connected_players.clear()
	var net_mgr = get_node_or_null("/root/NetworkManager")
	var my_idx = 0
	if net_mgr:
		my_idx = net_mgr.my_player_index
	# Always fill all UI_MAX_PLAYER_COUNT (4) slots so that FocusEmulator 1..4 never crash
	for i in range(UI_MAX_PLAYER_COUNT):
		var dev = 0 if i == my_idx else (NETWORK_DEVICE_OFFSET + i)
		connected_players.push_back([dev, PlayerType.KEYBOARD_AND_MOUSE])
	NetworkLogger.info("CoopService: Configured connected_players (%d player slots initialized, local: %d)" % [connected_players.size(), my_idx], "CoopAnything")
	emit_signal("connected_players_updated", connected_players)

func add_network_player(player_index: int) -> void:
	# Ensure all slots up to UI_MAX_PLAYER_COUNT exist
	while connected_players.size() < UI_MAX_PLAYER_COUNT:
		var next_idx = connected_players.size()
		var dev = 0 if next_idx == 0 else (NETWORK_DEVICE_OFFSET + next_idx)
		connected_players.push_back([dev, PlayerType.KEYBOARD_AND_MOUSE])
		
	var virtual_device: int = NETWORK_DEVICE_OFFSET + player_index
	if player_index < connected_players.size():
		connected_players[player_index] = [virtual_device, PlayerType.KEYBOARD_AND_MOUSE]
		
	NetworkLogger.info("CoopService: Adding network player %d (virtual device %d, registered)" % [player_index, virtual_device], "CoopAnything")
	emit_signal("connected_players_updated", connected_players)

func remove_network_player(player_index: int) -> void:
	var virtual_device: int = NETWORK_DEVICE_OFFSET + player_index
	for i in range(connected_players.size()):
		if connected_players[i][0] == virtual_device:
			NetworkLogger.info("CoopService: Resetting network player %d" % player_index, "CoopAnything")
			connected_players[i] = [i if i == 0 else (NETWORK_DEVICE_OFFSET + i), PlayerType.KEYBOARD_AND_MOUSE]
			emit_signal("connected_players_updated", connected_players)
			return

func is_network_device(device: int) -> bool:
	return device >= NETWORK_DEVICE_OFFSET

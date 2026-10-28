extends "res://ui/menus/ingame/pause_menu.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

func on_game_lost_focus() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		# In online co-op, NEVER steal pause ownership or auto-pause on window focus loss!
		return
	.on_game_lost_focus()

func pause(player_index: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		# In online co-op, ensure pause ownership is always bound to the local human player!
		# On Client, my_player_index is 1, so the menu and focus emulator stay with player 1.
		player_index = net.my_player_index
		NetworkLogger.info("PauseMenu: Pausing for local player %d" % player_index, "CoopAnything")
	.pause(player_index)

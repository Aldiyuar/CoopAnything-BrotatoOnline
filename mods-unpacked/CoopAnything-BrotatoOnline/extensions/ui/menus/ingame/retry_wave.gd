extends "res://ui/menus/ingame/retry_wave.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

func _change_scene(path: String) -> void:
	if path == "" or path == "res://":
		NetworkLogger.warn("retry_wave: _change_scene called with invalid path: '%s'" % path, "CoopAnything")
		return
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if net.is_host():
			NetworkLogger.info("Host: RetryWave scene change to %s, broadcasting to peers..." % path, "CoopAnything")
			net.rpc("rpc_sync_change_scene", path)
	._change_scene(path)

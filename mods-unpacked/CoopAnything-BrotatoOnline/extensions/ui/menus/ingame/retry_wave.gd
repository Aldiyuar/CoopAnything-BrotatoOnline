extends "res://ui/menus/ingame/retry_wave.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

func _ready() -> void:
	._ready()
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and not net.is_host():
		if _confirm_button:
			_confirm_button.disabled = true
		if _ok_button:
			_ok_button.disabled = true
		var cancel_btn = find_node("CancelButton")
		if cancel_btn and cancel_btn is Button:
			cancel_btn.disabled = true

func _change_scene(path: String) -> void:
	if path == "" or path == "res://":
		NetworkLogger.warn("retry_wave: _change_scene called with invalid path: '%s'" % path, "CoopAnything")
		return
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if not net.is_host():
			NetworkLogger.info("Client: retry_wave ignoring local _change_scene request", "CoopAnything")
			return
		NetworkLogger.info("Host: RetryWave scene change to %s, broadcasting to peers..." % path, "CoopAnything")
		net.rpc("rpc_sync_change_scene", path)
	._change_scene(path)

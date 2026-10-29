extends Node

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")
const MOD_DIR = "CoopAnything-BrotatoOnline"
const LOG_NAME = "CoopAnything:BrotatoOnline"

var network_manager = null

func _init() -> void:
	NetworkLogger.info("Initializing CoopAnything-BrotatoOnline...", LOG_NAME)
	
	# Install script extensions
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/main.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/singletons/coop_service.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/entities/units/movement_behaviors/player_movement_behavior.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/ui/menus/pages/main_menu.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/ui/menus/shop/coop_shop.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/ui/menus/ingame/upgrades_ui.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/ui/menus/ingame/pause_menu.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/CoopAnything-BrotatoOnline/extensions/ui/menus/ingame/retry_wave.gd")

func _ready() -> void:
	if ProgressData:
		ProgressData.show_main_title_mod_warning_popup = false
		ProgressData.show_main_title_beta_save_warning_popup = false
		if ProgressData.get("settings"):
			ProgressData.settings.pause_on_focus_lost = false
			
	# Register virtual input actions for network player devices so Godot never throws missing action errors
	for dev in [-1, 100, 101, 102, 103]:
		for act in ["ui_pause", "ui_cancel", "ui_select", "ui_up", "ui_down", "ui_left", "ui_right", "ui_info", "ui_ban"]:
			var action_name = "%s_%s" % [act, dev]
			if not InputMap.has_action(action_name):
				InputMap.add_action(action_name)
		
	NetworkLogger.info("Installing NetworkManager autoload singleton...", LOG_NAME)
	var net_script = load("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_manager.gd")
	network_manager = net_script.new()
	network_manager.name = "NetworkManager"
	get_tree().root.call_deferred("add_child", network_manager)
	
	NetworkLogger.success("CoopAnything-BrotatoOnline ready!", LOG_NAME)

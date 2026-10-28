extends Node

const MOD_DIR = "Antigravity-UnlockAll"
const LOG_NAME = "Antigravity:UnlockAll"

var current_debug_menu = null
var _bridge_pid: int = -1

const BRIDGE_DIR = "D:/Brotato/bridge"
const BRIDGE_SCRIPT = "D:/Brotato/bridge/deepseek_shop_bridge.py"
const PID_FILE = "D:/Brotato/bridge/bridge.pid"
const BROTATO_PID_FILE = "D:/Brotato/bridge/brotato.pid"

func _init():
	ModLoaderLog.info("Initializing Antigravity-UnlockAll...", LOG_NAME)
	ModLoaderMod.install_script_extension("res://mods-unpacked/Antigravity-UnlockAll/extensions/singletons/progress_data.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Antigravity-UnlockAll/extensions/ui/menus/run/difficulty_selection/difficulty_selection.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Antigravity-UnlockAll/extensions/ui/menus/shop/shop.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Antigravity-UnlockAll/extensions/ui/menus/ingame/upgrades_ui_player_container.gd")

func _ready():
	ModLoaderLog.info("Antigravity-UnlockAll ready! F1 = Debug Menu, F2 = Toggle AI Autopilot", LOG_NAME)
	call_deferred("_unlock_all_deferred")
	call_deferred("_ensure_ai_bridge_running")

func _ensure_ai_bridge_running() -> void:
	var dir = Directory.new()
	if not dir.dir_exists(BRIDGE_DIR):
		dir.make_dir_recursive(BRIDGE_DIR)

	# Записываем PID игры Brotato, чтобы мост знал свой родительский процесс
	var bf = File.new()
	if bf.open(BROTATO_PID_FILE, File.WRITE) == OK:
		bf.store_string(str(OS.get_process_id()))
		bf.close()

	if dir.file_exists(PID_FILE):
		var f = File.new()
		if f.open(PID_FILE, File.READ) == OK:
			var pid_str = f.get_as_text().strip_edges()
			f.close()
			if pid_str != "":
				var old_pid = int(pid_str)
				if old_pid > 0 and OS.is_process_running(old_pid):
					ModLoaderLog.info("AI Autopilot Bridge is already running (PID: %s)" % old_pid, LOG_NAME)
					_bridge_pid = old_pid
					return
				else:
					dir.remove(PID_FILE)

	var python_candidates = [
		"C:/Users/Vadim/AppData/Local/Programs/Python/Python313/pythonw.exe",
		"C:/Users/Vadim/AppData/Local/Programs/Python/Python312/pythonw.exe",
		"pythonw",
		"python"
	]
	
	var python_exe = ""
	for cand in python_candidates:
		if cand.begins_with("C:") and dir.file_exists(cand):
			python_exe = cand
			break
	if python_exe == "":
		python_exe = "pythonw"

	ModLoaderLog.info("Starting background AI Autopilot Bridge via: %s..." % python_exe, LOG_NAME)
	var pid = OS.execute(python_exe, [BRIDGE_SCRIPT], false)
	if pid > 0:
		_bridge_pid = pid
		ModLoaderLog.success("Background AI Autopilot Bridge successfully launched (PID: %s)!" % pid, LOG_NAME)
	else:
		ModLoaderLog.error("Failed to start background AI Bridge process.", LOG_NAME)

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		_kill_bridge_process()

func _kill_bridge_process():
	if _bridge_pid > 0 and OS.is_process_running(_bridge_pid):
		ModLoaderLog.info("Stopping AI Autopilot Bridge (PID: %s)..." % _bridge_pid, LOG_NAME)
		OS.kill(_bridge_pid)
		_bridge_pid = -1
		var dir = Directory.new()
		if dir.file_exists(PID_FILE):
			dir.remove(PID_FILE)
		if dir.file_exists(BROTATO_PID_FILE):
			dir.remove(BROTATO_PID_FILE)

func _unlock_all_deferred():
	if DebugService:
		DebugService.unlock_all_chars = true
		DebugService.unlock_all_challenges = true
		DebugService.unlock_all_difficulties = true
	
	if ProgressData:
		ProgressData.unlock_all()
		ProgressData.set_max_selectable_difficulty()
		if ZoneService:
			for zone in ZoneService.zones:
				if not ProgressData.zones_unlocked.has(zone.my_id):
					ProgressData.zones_unlocked.push_back(zone.my_id)
		if ProgressData.data:
			ProgressData.data["is_unlock_all_save"] = 0
		ProgressData.save()
		ModLoaderLog.success("All game content unlocked and clean profile preserved!", LOG_NAME)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_F1:
		_toggle_debug_menu()

func _toggle_debug_menu():
	if is_instance_valid(current_debug_menu):
		current_debug_menu.queue_free()
		current_debug_menu = null
		get_tree().set_pause(false)
	else:
		if DebugService and DebugService.debug_menu:
			current_debug_menu = DebugService.debug_menu.instance()
			var current_scene = get_tree().current_scene
			if current_scene:
				if current_scene.has_node("UI"):
					current_scene.get_node("UI").add_child(current_debug_menu)
				else:
					current_scene.add_child(current_debug_menu)

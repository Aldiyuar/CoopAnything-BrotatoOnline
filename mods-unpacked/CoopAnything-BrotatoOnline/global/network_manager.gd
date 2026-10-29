extends Node

const NetworkConstants = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_constants.gd")
const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

signal role_changed(new_role)
signal peer_joined(peer_id, player_index)
signal peer_left(peer_id, player_index)
signal input_updated(player_index, movement, aim)
signal snapshot_received(snapshot)
signal wave_started(wave_index)
signal shop_ready_state_changed(player_index, is_ready)

var role: int = NetworkConstants.PeerRole.SOLO
var my_player_index: int = 0
var peer_to_player_index: Dictionary = {} # peer_id -> player_index
var player_inputs: Dictionary = {} # player_index -> { "movement": Vector2, "aim": Vector2 }
var synthetic_movement: Vector2 = Vector2.ZERO # Injected movement vector for automated bots / tests
var shop_ready_states: Dictionary = {} # player_index -> bool
var auto_start_match_on_connect: bool = false
var auto_start_shop_test_on_connect: bool = false
var auto_start_postwave_test_on_connect: bool = false
var auto_start_death_test_on_connect: bool = false
var shop_test_step: int = 0
var shop_test_timer: float = 0.0
var postwave_test_step: int = 0
var postwave_test_timer: float = 0.0

var network_enemies: Dictionary = {} # net_id (int) -> Enemy/Neutral Node
var network_enemy_counter: int = 1000

var ground_items: Dictionary = {} # item_id (int) -> Gold or Consumable Node
var network_item_counter: int = 5000

var current_match_seed: int = 123456789
var cached_initial_shop_items: Dictionary = {}

var _enet_peer: NetworkedMultiplayerENet = null
var _accumulated_time: float = 0.0
var _godot_log_timer: float = 0.5
var _godot_log_offset: int = 0

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_process(true)
	var f = File.new()
	if f.open("user://logs/godot.log", File.READ) == OK:
		_godot_log_offset = f.get_len()
		f.close()
	var tree = get_tree()
	var _e1 = tree.connect("network_peer_connected", self, "_on_peer_connected")
	var _e2 = tree.connect("network_peer_disconnected", self, "_on_peer_disconnected")
	var _e3 = tree.connect("connected_to_server", self, "_on_connected_to_server")
	var _e4 = tree.connect("connection_failed", self, "_on_connection_failed")
	var _e5 = tree.connect("server_disconnected", self, "_on_server_disconnected")
	call_deferred("_check_cli_auto_args")

func _process(delta: float) -> void:
	_godot_log_timer -= delta
	if _godot_log_timer <= 0.0:
		_godot_log_timer = 0.5
		_sync_godot_engine_errors()
	if shop_test_step > 0:
		shop_test_timer -= delta
		if shop_test_timer <= 0.0:
			_advance_shop_test_step()
	if postwave_test_step > 0:
		postwave_test_timer -= delta
		if postwave_test_timer <= 0.0:
			_advance_postwave_test_step()

func _sync_godot_engine_errors() -> void:
	var f = File.new()
	if f.open("user://logs/godot.log", File.READ) != OK:
		return
	var f_len = f.get_len()
	if f_len < _godot_log_offset:
		_godot_log_offset = 0
	if f_len > _godot_log_offset:
		f.seek(_godot_log_offset)
		while not f.eof_reached():
			var line = f.get_line()
			if "ERROR:" in line or "SCRIPT ERROR:" in line or "CRASH" in line:
				NetworkLogger.log_engine_error(line)
		_godot_log_offset = f.get_position()
	f.close()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.scancode == KEY_F10:
		capture_screen("hotkey_f10")

func capture_screen(name: String) -> void:
	yield(VisualServer, "frame_post_draw")
	var vp = get_viewport()
	if not vp and get_tree():
		vp = get_tree().root
	if vp:
		var tex = vp.get_texture()
		if tex:
			var img: Image = tex.get_data()
			if img:
				img.flip_y()
				var dir = Directory.new()
				var shots_dir = "user://screenshots"
				if dir.dir_exists("D:/Brotato_Coop_Test"):
					shots_dir = "D:/Brotato_Coop_Test/screenshots"
				dir.make_dir_recursive(shots_dir)
				var path = "%s/%s_%s.png" % [shots_dir, name, str(OS.get_process_id())]
				var err = img.save_png(path)
				if err == OK:
					NetworkLogger.success("[SCREENSHOT] Saved: %s" % path, "CoopAnything")
				else:
					NetworkLogger.error("[SCREENSHOT] Failed to save %s: %d" % [path, err], "CoopAnything")

func _check_cli_auto_args() -> void:
	var args = OS.get_cmdline_args()
	NetworkLogger.info("CLI args: %s" % str(args), "CoopAnything")
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--coop-host":
			NetworkLogger.info("[QA_TEST] Auto-hosting server via CLI...", "CoopAnything")
			host_game(NetworkConstants.DEFAULT_PORT)
			var run_data = get_node_or_null("/root/RunData")
			if run_data and run_data.has_method("set_coop_run"):
				run_data.set_coop_run(true)
		elif arg == "--coop-host-match":
			NetworkLogger.info("[QA_TEST] Auto-hosting arena match via CLI...", "CoopAnything")
			auto_start_match_on_connect = true
			host_game(NetworkConstants.DEFAULT_PORT)
		elif arg == "--coop-host-shop":
			NetworkLogger.info("[QA_TEST] Auto-hosting shop test via CLI...", "CoopAnything")
			auto_start_shop_test_on_connect = true
			host_game(NetworkConstants.DEFAULT_PORT)
		elif arg == "--coop-host-postwave":
			NetworkLogger.info("[QA_TEST] Auto-hosting post-wave full test via CLI...", "CoopAnything")
			auto_start_postwave_test_on_connect = true
			host_game(NetworkConstants.DEFAULT_PORT)
		elif arg == "--coop-host-death":
			NetworkLogger.info("[QA_TEST] Auto-hosting death & gameover test via CLI...", "CoopAnything")
			auto_start_death_test_on_connect = true
			host_game(NetworkConstants.DEFAULT_PORT)
		elif arg == "--coop-join":
			var ip = "127.0.0.1"
			if i + 1 < args.size() and not args[i+1].begins_with("--"):
				ip = args[i+1]
			NetworkLogger.info("[QA_TEST] Auto-joining server at %s via CLI..." % ip, "CoopAnything")
			join_game(ip, NetworkConstants.DEFAULT_PORT)
			var run_data = get_node_or_null("/root/RunData")
			if run_data and run_data.has_method("set_coop_run"):
				run_data.set_coop_run(true)
		elif arg == "--coop-join-death":
			var ip = "127.0.0.1"
			if i + 1 < args.size() and not args[i+1].begins_with("--"):
				ip = args[i+1]
			NetworkLogger.info("[QA_TEST] Auto-joining death test at %s via CLI..." % ip, "CoopAnything")
			join_game(ip, NetworkConstants.DEFAULT_PORT)
			var run_data = get_node_or_null("/root/RunData")
			if run_data and run_data.has_method("set_coop_run"):
				run_data.set_coop_run(true)
		elif arg == "--coop-join-shop":
			var ip = "127.0.0.1"
			if i + 1 < args.size() and not args[i+1].begins_with("--"):
				ip = args[i+1]
			NetworkLogger.info("[QA_TEST] Auto-joining shop test at %s via CLI..." % ip, "CoopAnything")
			join_game(ip, NetworkConstants.DEFAULT_PORT)
		elif arg == "--coop-join-postwave":
			var ip = "127.0.0.1"
			if i + 1 < args.size() and not args[i+1].begins_with("--"):
				ip = args[i+1]
			NetworkLogger.info("[QA_TEST] Auto-joining post-wave full test at %s via CLI..." % ip, "CoopAnything")
			join_game(ip, NetworkConstants.DEFAULT_PORT)

func host_game(port: int = NetworkConstants.DEFAULT_PORT) -> int:
	close_session()
	_enet_peer = NetworkedMultiplayerENet.new()
	var err = _enet_peer.create_server(port, NetworkConstants.MAX_PLAYERS)
	if err != OK:
		NetworkLogger.error("Failed to host on port %d: error %d" % [port, err], "CoopAnything")
		return err
	
	get_tree().network_peer = _enet_peer
	role = NetworkConstants.PeerRole.HOST
	my_player_index = 0
	peer_to_player_index[1] = 0
	player_inputs[0] = {"movement": Vector2.ZERO, "aim": Vector2.ZERO}
	_disable_pause_on_focus_lost()
	emit_signal("role_changed", role)
	NetworkLogger.success("Hosting online game on port %d" % port, "CoopAnything")
	return OK

func join_game(ip: String, port: int = NetworkConstants.DEFAULT_PORT) -> int:
	close_session()
	var target_ip = ip.strip_edges()
	var target_port = port
	if ":" in target_ip:
		var parts = target_ip.split(":")
		target_ip = parts[0].strip_edges()
		if parts.size() > 1 and parts[1].strip_edges().is_valid_integer():
			target_port = int(parts[1].strip_edges())
	_enet_peer = NetworkedMultiplayerENet.new()
	var err = _enet_peer.create_client(target_ip, target_port)
	if err != OK:
		NetworkLogger.error("Failed to connect to %s:%d: error %d" % [target_ip, target_port, err], "CoopAnything")
		return err
	
	get_tree().network_peer = _enet_peer
	role = NetworkConstants.PeerRole.CLIENT
	emit_signal("role_changed", role)
	_isolate_client_save_paths()
	_disable_pause_on_focus_lost()
	NetworkLogger.info("Connecting to %s:%d..." % [target_ip, target_port], "CoopAnything")
	return OK

func _disable_pause_on_focus_lost() -> void:
	if ProgressData and ProgressData.get("settings"):
		ProgressData.settings.pause_on_focus_lost = false
		NetworkLogger.info("Online session: pause_on_focus_lost disabled", "CoopAnything")

func _isolate_client_save_paths() -> void:
	if ProgressData:
		var dir = Directory.new()
		var client_dir = ProgressData.SAVE_DIR + "-Client"
		if not dir.dir_exists(client_dir):
			dir.make_dir_recursive(client_dir)
		ProgressData.SAVE_DIR = client_dir
		NetworkLogger.info("Client SAVE_DIR isolated to: %s" % client_dir, "CoopAnything")

func close_session() -> void:
	if _enet_peer:
		_enet_peer.close_connection()
		_enet_peer = null
	if get_tree().network_peer:
		get_tree().network_peer = null
	role = NetworkConstants.PeerRole.SOLO
	my_player_index = 0
	peer_to_player_index.clear()
	player_inputs.clear()
	shop_ready_states.clear()
	ground_items.clear()
	network_enemies.clear()
	emit_signal("role_changed", role)

func is_online() -> bool:
	return role != NetworkConstants.PeerRole.SOLO

func is_host() -> bool:
	return role == NetworkConstants.PeerRole.HOST

func is_client() -> bool:
	return role == NetworkConstants.PeerRole.CLIENT

# ----------------------------------------------------
# Connection Callbacks
# ----------------------------------------------------
func _on_peer_connected(peer_id: int) -> void:
	NetworkLogger.info("Peer connected: %d" % peer_id, "CoopAnything")
	if is_host():
		# Assign next free player index (1, 2, 3)
		var assigned_idx: int = -1
		for i in range(1, NetworkConstants.MAX_PLAYERS):
			if not peer_to_player_index.values().has(i):
				assigned_idx = i
				break
		
		if assigned_idx != -1:
			peer_to_player_index[peer_id] = assigned_idx
			player_inputs[assigned_idx] = {"movement": Vector2.ZERO, "aim": Vector2.ZERO}
			# Notify the client of their assigned player index
			rpc_id(peer_id, "rpc_assign_player_index", assigned_idx)
			# Add player to native CoopService
			_register_network_player_in_coop_service(assigned_idx)
			emit_signal("peer_joined", peer_id, assigned_idx)
			call_deferred("capture_screen", "03_host_peer_joined")
			if auto_start_match_on_connect:
				var timer = get_tree().create_timer(1.2)
				timer.connect("timeout", self, "start_coop_match")
			elif auto_start_shop_test_on_connect:
				var timer = get_tree().create_timer(1.2)
				timer.connect("timeout", self, "start_shop_test")
			elif auto_start_postwave_test_on_connect:
				var timer = get_tree().create_timer(1.2)
				timer.connect("timeout", self, "start_postwave_test")
			elif auto_start_death_test_on_connect:
				var timer = get_tree().create_timer(1.2)
				timer.connect("timeout", self, "start_death_test")
		else:
			# Server full, disconnect peer
			_enet_peer.disconnect_peer(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	NetworkLogger.info("Peer disconnected: %d" % peer_id, "CoopAnything")
	if peer_to_player_index.has(peer_id):
		var idx = peer_to_player_index[peer_id]
		peer_to_player_index.erase(peer_id)
		player_inputs.erase(idx)
		shop_ready_states.erase(idx)
		_unregister_network_player_in_coop_service(idx)
		emit_signal("peer_left", peer_id, idx)

func _on_connected_to_server() -> void:
	NetworkLogger.success("[QA_TEST] Client: Successfully connected to host server!", "CoopAnything")
	rpc_unreliable_id(1, "rpc_send_player_input", 1.0, 0.5, 0.0, 0.0)

func _on_connection_failed() -> void:
	NetworkLogger.error("[QA_TEST] Connection failed!", "CoopAnything")
	close_session()

func _on_server_disconnected() -> void:
	NetworkLogger.warn("[QA_TEST] Host disconnected.", "CoopAnything")
	close_session()

# ----------------------------------------------------
# Native CoopService Bridge
# ----------------------------------------------------
func _register_network_player_in_coop_service(player_index: int) -> void:
	var coop = get_node_or_null("/root/CoopService")
	if coop and coop.has_method("add_network_player"):
		coop.add_network_player(player_index)

func _unregister_network_player_in_coop_service(player_index: int) -> void:
	var coop = get_node_or_null("/root/CoopService")
	if coop and coop.has_method("remove_network_player"):
		coop.remove_network_player(player_index)

# ----------------------------------------------------
# RPCs
# ----------------------------------------------------
remote func rpc_assign_player_index(assigned_idx: int) -> void:
	my_player_index = assigned_idx
	player_inputs[0] = {"movement": Vector2.ZERO, "aim": Vector2.ZERO}
	player_inputs[assigned_idx] = {"movement": Vector2.ZERO, "aim": Vector2.ZERO}
	NetworkLogger.success("[QA_TEST] Client: Host assigned player slot %d" % assigned_idx, "CoopAnything")
	var run_data = get_node_or_null("/root/RunData")
	if run_data and run_data.has_method("set_coop_run"):
		run_data.set_coop_run(true)
	var coop = get_node_or_null("/root/CoopService")
	if coop and coop.has_method("setup_coop_players"):
		coop.setup_coop_players(2)
	call_deferred("capture_screen", "03_client_slot_assigned")

remote func rpc_broadcast_host_input(movement_x: float, movement_y: float, aim_x: float, aim_y: float) -> void:
	var movement = Vector2(movement_x, movement_y)
	var aim = Vector2(aim_x, aim_y)
	player_inputs[0] = {"movement": movement, "aim": aim}
	emit_signal("input_updated", 0, movement, aim)

remote func rpc_send_player_input(movement_x: float, movement_y: float, aim_x: float, aim_y: float, pos_x: float = 0.0, pos_y: float = 0.0) -> void:
	var sender_id = get_tree().get_rpc_sender_id()
	if peer_to_player_index.has(sender_id):
		var p_idx = peer_to_player_index[sender_id]
		var movement = Vector2(movement_x, movement_y)
		var aim = Vector2(aim_x, aim_y)
		var old_input = player_inputs.get(p_idx, {})
		var old_mov = old_input.get("movement", Vector2.ZERO)
		if movement != Vector2.ZERO and old_mov == Vector2.ZERO:
			NetworkLogger.info("[QA_TEST] Host: Received remote input from player %d: %s" % [p_idx, str(movement)], "CoopAnything")
		player_inputs[p_idx] = {"movement": movement, "aim": aim}
		emit_signal("input_updated", p_idx, movement, aim)
		if pos_x != 0.0 or pos_y != 0.0:
			var main_scene = get_tree().current_scene
			if main_scene and "_players" in main_scene and p_idx < main_scene._players.size():
				var p = main_scene._players[p_idx]
				if is_instance_valid(p) and not p.dead:
					var client_pos = Vector2(pos_x, pos_y)
					var dist = p.global_position.distance_to(client_pos)
					if dist > 300.0:
						p.global_position = client_pos
					elif dist > 150.0:
						p.global_position = p.global_position.linear_interpolate(client_pos, 0.15)

remotesync func rpc_player_died(player_index: int) -> void:
	if is_client():
		NetworkLogger.info("Client: Processing player %d death from Host" % player_index, "CoopAnything")
		var main_scene = get_tree().current_scene
		if main_scene and "_players" in main_scene and player_index < main_scene._players.size():
			var p = main_scene._players[player_index]
			if is_instance_valid(p) and not p.dead:
				p.current_stats.health = 0
				p.die()
				NetworkLogger.success("Client: Player %d successfully transitioned to death state" % player_index, "CoopAnything")

puppet func rpc_sync_player_positions(p_batch: Array) -> void:
	if is_client():
		var main_scene = get_tree().current_scene
		if main_scene and "_players" in main_scene:
			for item in p_batch:
				var p_idx: int = item[0]
				var target_pos = Vector2(item[1], item[2])
				var hp: int = item[3]
				var is_dead: bool = (item.size() > 4 and item[4] == 1) or hp <= 0
				if p_idx < main_scene._players.size():
					var p = main_scene._players[p_idx]
					if is_instance_valid(p):
						if is_dead:
							if not p.dead:
								p.current_stats.health = 0
								p.die()
								NetworkLogger.info("Client: Player %d died (synced via position batch)" % p_idx, "CoopAnything")
							continue
						
						if not p.dead:
							if p_idx != my_player_index:
								var dist = p.global_position.distance_to(target_pos)
								if dist > 250.0:
									p.global_position = target_pos
								p.set_meta("net_target_pos", target_pos)
							else:
								var dist = p.global_position.distance_to(target_pos)
								if dist > 350.0:
									p.global_position = target_pos
								elif dist > 180.0:
									p.global_position = p.global_position.linear_interpolate(target_pos, 0.15)
							p.current_stats.health = hp
							if main_scene.has_method("_on_player_health_updated"):
								main_scene._on_player_health_updated(p, hp, p.max_stats.health)

remotesync func rpc_sync_change_scene(path: String) -> void:
	if path == "" or path == "res://":
		NetworkLogger.warn("rpc_sync_change_scene called with invalid path: '%s'" % path, "CoopAnything")
		return
	network_enemies.clear()
	ground_items.clear()
	if is_client():
		NetworkLogger.info("Client: Syncing scene to %s from Host" % path, "CoopAnything")
		var err = get_tree().change_scene(path)
		if err != OK:
			NetworkLogger.error("Client: Failed to change scene to %s: %d" % [path, err], "CoopAnything")

remotesync func rpc_sync_rng_seed(p_seed: int) -> void:
	current_match_seed = p_seed
	NetworkLogger.info("RNG: Synchronized seed to %d" % p_seed, "CoopAnything")
	seed(p_seed)
	var utils = get_node_or_null("/root/Utils")
	if utils and utils.has_method("set_rng_seed"):
		utils.set_rng_seed(p_seed)

func broadcast_wave_snapshot(snapshot: Dictionary) -> void:
	if is_host():
		rpc_unreliable("rpc_receive_wave_snapshot", snapshot)

func start_coop_match() -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Launching 2-player co-op arena match...", "CoopAnything")
	rpc("rpc_start_match")

remotesync func rpc_start_match() -> void:
	NetworkLogger.info("Starting arena match for connected players!", "CoopAnything")
	_setup_match_rundata()
	if is_host():
		var match_seed = (OS.get_system_time_msecs() ^ OS.get_process_id()) % 1000000000 + 1
		rpc("rpc_sync_rng_seed", match_seed)
	var target_scene = "res://main.tscn"
	var menu_data = get_node_or_null("/root/MenuData")
	if menu_data and menu_data.game_scene and menu_data.game_scene != "" and menu_data.game_scene != "res://":
		target_scene = menu_data.game_scene
	var err = get_tree().change_scene(target_scene)
	if err == OK:
		NetworkLogger.success("Arena scene (%s) loaded successfully!" % target_scene, "CoopAnything")
		call_deferred("_schedule_arena_actions")
	else:
		NetworkLogger.error("Failed to load game scene: %d" % err, "CoopAnything")

func _setup_match_rundata() -> void:
	var run_data = get_node_or_null("/root/RunData")
	if not run_data:
		NetworkLogger.error("RunData not found!", "CoopAnything")
		return
	NetworkLogger.info("Setting up RunData canonically for 2-player match...", "CoopAnything")
	if run_data.has_method("reset"):
		run_data.reset(false)
	run_data.set_coop_run(true)
	run_data.set_player_count(2)
	run_data.current_wave = 1
	
	var zone_service = get_node_or_null("/root/ZoneService")
	if zone_service and zone_service.has_method("get_zone_data"):
		zone_service.current_zone = zone_service.get_zone_data(0).duplicate()
	
	var coop = get_node_or_null("/root/CoopService")
	if coop and coop.has_method("setup_coop_players"):
		coop.setup_coop_players(2)
	
	var char0 = load("res://items/characters/well_rounded/well_rounded_data.tres")
	var char1 = load("res://items/characters/brawler/brawler_data.tres")
	var weapon0 = load("res://weapons/melee/knife/1/knife_data.tres")
	var weapon1 = load("res://weapons/melee/fist/1/fist_data.tres")
	
	if run_data.has_method("add_character"):
		run_data.add_character(char0, 0)
		run_data.add_character(char1, 1)
		
	if run_data.has_method("add_weapon"):
		run_data.add_weapon(weapon0, 0, true)
		run_data.add_weapon(weapon1, 1, true)
		
	if run_data.has_method("add_starting_items_and_weapons"):
		run_data.add_starting_items_and_weapons()
		
	NetworkLogger.success("Configured 2 players in RunData.players_data!", "CoopAnything")

func _schedule_arena_actions() -> void:
	var timer = get_tree().create_timer(3.0)
	timer.connect("timeout", self, "_on_arena_timer")

func _on_arena_timer() -> void:
	capture_screen("04_arena_wave_1")
	call_deferred("_run_arena_patrol_loop")

func _run_arena_patrol_loop() -> void:
	NetworkLogger.info("Starting arena patrol movement loop (Role: %d, MyIdx: %d)..." % [role, my_player_index], "CoopAnything")
	var start_time = OS.get_ticks_msec()
	while (OS.get_ticks_msec() - start_time) < 25000:
		var scene = get_tree().current_scene
		if not scene or not ("_players" in scene):
			break
		var elapsed_s = float(OS.get_ticks_msec() - start_time) / 1000.0
		var angle = elapsed_s * 1.6
		var move_dir: Vector2 = Vector2.ZERO
		if my_player_index == 0:
			# Player 0 (Host): active patrol path across arena
			move_dir = Vector2(cos(angle), sin(angle * 2.0)).normalized()
		else:
			# Player 1 (Client): active counter-patrol path across arena
			move_dir = Vector2(sin(angle), -cos(angle)).normalized()
		
		synthetic_movement = move_dir
		
		var t = get_tree().create_timer(0.1)
		yield(t, "timeout")
	
	synthetic_movement = Vector2.ZERO
	NetworkLogger.info("Arena patrol movement loop completed.", "CoopAnything")
	capture_screen("05_active_movement")

func start_death_test() -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Launching 2-player death & game-over test...", "CoopAnything")
	rpc("rpc_start_death_test")

remotesync func rpc_start_death_test() -> void:
	NetworkLogger.info("Starting death & game over test match!", "CoopAnything")
	_setup_match_rundata()
	if is_host():
		var match_seed = (OS.get_system_time_msecs() ^ OS.get_process_id()) % 1000000000 + 1
		rpc("rpc_sync_rng_seed", match_seed)
	var target_scene = "res://main.tscn"
	var menu_data = get_node_or_null("/root/MenuData")
	if menu_data and menu_data.game_scene and menu_data.game_scene != "" and menu_data.game_scene != "res://":
		target_scene = menu_data.game_scene
	var err = get_tree().change_scene(target_scene)
	if err == OK:
		NetworkLogger.success("Death test: Arena scene loaded successfully!", "CoopAnything")
		call_deferred("_schedule_death_test_sequence")
	else:
		NetworkLogger.error("Failed to load arena scene for death test: %d" % err, "CoopAnything")

func _schedule_death_test_sequence() -> void:
	call_deferred("_run_arena_patrol_loop")
	if not is_host():
		return
	
	# t = 5.0s: Inflict lethal damage on Player 1 (Client)
	var t1 = get_tree().create_timer(5.0)
	t1.connect("timeout", self, "_death_test_kill_p1")

func _death_test_kill_p1() -> void:
	var main_scene = get_tree().current_scene
	if main_scene and "_players" in main_scene and main_scene._players.size() > 1:
		var p1 = main_scene._players[1]
		if is_instance_valid(p1) and not p1.dead:
			NetworkLogger.info("[QA_TEST] Host: Inflicting lethal damage to Player 1...", "CoopAnything")
			var args = TakeDamageArgs.new(0)
			p1.take_damage(999, args)
			call_deferred("capture_screen", "death_01_client_player_died")
	
	# t = 11.0s: Inflict lethal damage on Player 0 (Host) -> leads to team wipe and Game Over
	var t2 = get_tree().create_timer(6.0)
	t2.connect("timeout", self, "_death_test_kill_p0")

func _death_test_kill_p0() -> void:
	var main_scene = get_tree().current_scene
	if main_scene and "_players" in main_scene and main_scene._players.size() > 0:
		var p0 = main_scene._players[0]
		if is_instance_valid(p0) and not p0.dead:
			NetworkLogger.info("[QA_TEST] Host: Inflicting lethal damage to Player 0 (Team Wipe)...", "CoopAnything")
			var args = TakeDamageArgs.new(0)
			p0.take_damage(999, args)
			call_deferred("capture_screen", "death_02_all_players_died")
	
	# t = 3.5s after wipe: Click End Run / Cancel on RetryWave to transition to coop_end_run.tscn
	var t3 = get_tree().create_timer(3.5)
	t3.connect("timeout", self, "_death_test_advance_to_end_run")

func _death_test_advance_to_end_run() -> void:
	var main_scene = get_tree().current_scene
	if main_scene and "_retry_wave" in main_scene:
		var rw = main_scene._retry_wave
		if rw and rw.has_method("_on_CancelButton_pressed"):
			NetworkLogger.info("[QA_TEST] Host: Advancing RetryWave popup to EndRun screen...", "CoopAnything")
			rw._on_CancelButton_pressed()

puppet func rpc_receive_wave_snapshot(snapshot: Dictionary) -> void:
	emit_signal("snapshot_received", snapshot)

# ----------------------------------------------------
# Enemy & World State Replication (Host Authoritative)
# ----------------------------------------------------
remotesync func rpc_spawn_network_enemy(net_id: int, scene_path: String, pos_x: float, pos_y: float, hp: int) -> void:
	if is_client():
		var scene = load(scene_path)
		var main_scene = get_tree().current_scene
		if scene and main_scene and main_scene.has_node("EntitySpawner"):
			var spawner = main_scene.get_node("EntitySpawner")
			var args = EntitySpawner.SpawnEntityArgs.new(Vector2(pos_x, pos_y), EntityType.ENEMY)
			var enemy = spawner.spawn_entity(scene, args)
			if enemy:
				enemy.set_meta("net_id", net_id)
				network_enemies[net_id] = enemy
				enemy.global_position = Vector2(pos_x, pos_y)
				enemy.set_meta("net_target_pos", enemy.global_position)
				enemy.current_stats.health = hp
				enemy.max_stats.health = hp
				NetworkLogger.info("Client: Spawned shared enemy %d (%s) at (%.0f, %.0f)" % [net_id, scene_path.get_file(), pos_x, pos_y], "CoopAnything")

remotesync func rpc_spawn_network_neutral(net_id: int, scene_path: String, pos_x: float, pos_y: float) -> void:
	if is_client():
		var scene = load(scene_path)
		var main_scene = get_tree().current_scene
		if scene and main_scene and main_scene.has_node("EntitySpawner"):
			var spawner = main_scene.get_node("EntitySpawner")
			var args = EntitySpawner.SpawnEntityArgs.new(Vector2(pos_x, pos_y), EntityType.NEUTRAL)
			var neutral = spawner.spawn_entity(scene, args)
			if neutral:
				neutral.set_meta("net_id", net_id)
				network_enemies[net_id] = neutral
				neutral.global_position = Vector2(pos_x, pos_y)
				neutral.set_meta("net_target_pos", neutral.global_position)
				NetworkLogger.info("Client: Spawned shared tree %d at (%.0f, %.0f)" % [net_id, pos_x, pos_y], "CoopAnything")

puppet func rpc_sync_enemy_batch(batch: Array) -> void:
	if is_client():
		for item in batch:
			var net_id: int = item[0]
			if network_enemies.has(net_id):
				var enemy = network_enemies[net_id]
				if is_instance_valid(enemy) and not enemy.dead:
					var target_pos = Vector2(item[1], item[2])
					var dist = enemy.global_position.distance_to(target_pos)
					if dist > 250.0:
						enemy.global_position = target_pos
					enemy.set_meta("net_target_pos", target_pos)
					enemy.current_stats.health = item[3]
					if item[3] <= 0:
						enemy.set_meta("host_killed", true)
						enemy.die()
						network_enemies.erase(net_id)

remotesync func rpc_enemy_died(net_id: int) -> void:
	if is_client() and network_enemies.has(net_id):
		var enemy = network_enemies[net_id]
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.set_meta("host_killed", true)
			enemy.die()
		network_enemies.erase(net_id)

remote func rpc_client_dealt_damage(_net_id: int, _damage: int) -> void:
	# Deprecated: Host is strictly authoritative over all weapon attacks and enemy HP calculations.
	# Left as a no-op handler to prevent errors if a legacy/stale packet is received.
	pass

# ----------------------------------------------------
# Shared Currency (Gold & XP) Synchronization
# ----------------------------------------------------
remotesync func rpc_sync_all_players_gold_and_xp(golds: Array, xps: Array) -> void:
	if is_client():
		var run_data = get_node_or_null("/root/RunData")
		if not run_data:
			return
		for i in range(golds.size()):
			if i < run_data.players_data.size():
				var p_data = run_data.players_data[i]
				p_data.gold = golds[i]
				run_data.emit_signal("gold_changed", golds[i], i)
		for i in range(xps.size()):
			if i < run_data.players_data.size():
				var p_data = run_data.players_data[i]
				p_data.current_xp = xps[i][0]
				p_data.current_level = xps[i][1]
		NetworkLogger.info("Client: Synchronized shared currency! Gold: P0=%d, P1=%d" % [golds[0], golds[1] if golds.size() > 1 else 0], "CoopAnything")

remotesync func rpc_spawn_ground_gold(item_id: int, gold_val: int, start_x: float, start_y: float, dest_x: float, dest_y: float) -> void:
	if is_client():
		var main_scene = get_tree().current_scene
		if main_scene and ("_materials_container" in main_scene):
			var gold = main_scene.get_node_from_pool(main_scene._gold_pool_id, main_scene._materials_container)
			var is_new_instance: bool = false
			if gold == null:
				is_new_instance = true
				gold = main_scene.gold_scene.instance()
			gold.already_picked_up = false
			gold.set_meta("net_item_id", item_id)
			ground_items[item_id] = gold
			if is_new_instance:
				main_scene._materials_container.call_deferred("add_child", gold)
				var _error = gold.connect("picked_up", main_scene, "on_gold_picked_up")
				_error = gold.connect("picked_up", main_scene._effects_manager, "on_gold_picked_up")
				_error = gold.connect("picked_up", main_scene._floating_text_manager, "on_gold_picked_up")
				yield(gold, "ready")
				if not ground_items.has(item_id) or not is_instance_valid(main_scene):
					if is_instance_valid(gold) and is_instance_valid(main_scene):
						gold.already_picked_up = true
						main_scene.add_node_to_pool(gold, main_scene._gold_pool_id)
					return
			gold.value = gold_val
			gold.set_texture(main_scene.gold_sprites.pick_random())
			var start_pos = Vector2(start_x, start_y)
			var dest_pos = Vector2(dest_x, dest_y)
			gold.drop(start_pos, 0.0, dest_pos)
			main_scene._active_golds.push_back(gold)
			emit_signal("gold_spawned")

remotesync func rpc_spawn_ground_consumable(item_id: int, res_path: String, start_x: float, start_y: float, dest_x: float, dest_y: float) -> void:
	if is_client():
		if res_path == "" or res_path == "res://":
			return
		var main_scene = get_tree().current_scene
		if main_scene and ("_consumables_container" in main_scene):
			var data = load(res_path)
			if not data:
				return
			var consumable = main_scene.get_node_from_pool(main_scene._consumable_pool_id, main_scene._consumables_container)
			var is_new_instance: bool = false
			if consumable == null:
				is_new_instance = true
				consumable = main_scene.consumable_scene.instance()
			consumable.already_picked_up = false
			consumable.consumable_data = data
			consumable.set_texture(data.icon)
			consumable.set_meta("net_item_id", item_id)
			ground_items[item_id] = consumable
			if is_new_instance:
				main_scene._consumables_container.call_deferred("add_child", consumable)
				var _error = consumable.connect("picked_up", main_scene, "on_consumable_picked_up")
				yield(consumable, "ready")
				if not ground_items.has(item_id) or not is_instance_valid(main_scene):
					if is_instance_valid(consumable) and is_instance_valid(main_scene):
						consumable.already_picked_up = true
						main_scene.add_node_to_pool(consumable, main_scene._consumable_pool_id)
					return
			var start_pos = Vector2(start_x, start_y)
			var dest_pos = Vector2(dest_x, dest_y)
			consumable.drop(start_pos, 0.0, dest_pos)
			main_scene._consumables.push_back(consumable)
			NetworkLogger.info("Client: Spawned ground consumable %d (%s) at (%.0f, %.0f)" % [item_id, res_path.get_file(), dest_x, dest_y], "CoopAnything")

remote func rpc_request_item_pickup(item_id: int, is_gold: bool, player_index: int) -> void:
	if not is_host():
		return
	if ground_items.has(item_id):
		var item = ground_items[item_id]
		ground_items.erase(item_id)
		if is_instance_valid(item) and not item.already_picked_up:
			var main_scene = get_tree().current_scene
			if main_scene:
				if is_gold and main_scene.has_method("on_gold_picked_up"):
					main_scene.on_gold_picked_up(item, player_index)
				elif not is_gold and main_scene.has_method("on_consumable_picked_up"):
					main_scene.on_consumable_picked_up(item, player_index)

remotesync func rpc_remove_ground_item(item_id: int, is_gold: bool) -> void:
	if ground_items.has(item_id):
		var item = ground_items[item_id]
		ground_items.erase(item_id)
		if is_instance_valid(item) and not item.already_picked_up:
			if item.has_meta("net_item_id") and item.get_meta("net_item_id") != item_id:
				return
			item.already_picked_up = true
			item.set_meta("net_item_id", -1)
			var main_scene = get_tree().current_scene
			if main_scene:
				if is_gold and "_active_golds" in main_scene:
					main_scene._active_golds.erase(item)
					main_scene.add_node_to_pool(item, main_scene._gold_pool_id)
				elif not is_gold and "_consumables" in main_scene:
					main_scene._consumables.erase(item)
					main_scene.add_node_to_pool(item, main_scene._consumable_pool_id)

remotesync func rpc_player_received_crate(player_index: int, res_path: String) -> void:
	if is_client():
		if res_path == "" or res_path == "res://":
			return
		var main_scene = get_tree().current_scene
		if main_scene and ("_consumables_to_process" in main_scene):
			var data = load(res_path)
			if data:
				var ctp = UpgradesUI.ConsumableToProcess.new()
				ctp.consumable_data = data
				ctp.player_index = player_index
				if player_index < main_scene._consumables_to_process.size():
					main_scene._consumables_to_process[player_index].push_back(ctp)
				if player_index < main_scene._things_to_process_player_containers.size():
					main_scene._things_to_process_player_containers[player_index].consumables.add_element(data)
				NetworkLogger.info("Client: Registered crate for player %d (%s)" % [player_index, res_path.get_file()], "CoopAnything")

remotesync func rpc_player_levelled_up(player_index: int, level: int) -> void:
	if is_client():
		var main_scene = get_tree().current_scene
		if main_scene and ("_upgrades_to_process" in main_scene):
			var utp = UpgradesUI.UpgradeToProcess.new()
			utp.level = level
			utp.player_index = player_index
			if player_index < main_scene._upgrades_to_process.size():
				main_scene._upgrades_to_process[player_index].push_back(utp)
			if player_index < main_scene._things_to_process_player_containers.size():
				main_scene._things_to_process_player_containers[player_index].upgrades.add_element(ItemService.get_icon(Keys.icon_upgrade_to_process_hash), level)
			if player_index < main_scene._players_ui.size():
				main_scene._players_ui[player_index].update_level_label()
			NetworkLogger.info("Client: Registered level up for player %d (Level %d)" % [player_index, level], "CoopAnything")

# ----------------------------------------------------
# Shop & Upgrades Network Test Routines
# ----------------------------------------------------
func start_shop_test() -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Starting full Shop & Upgrades multiplayer verification...", "CoopAnything")
	rpc("rpc_load_shop_scene")

remotesync func rpc_load_shop_scene() -> void:
	NetworkLogger.info("CoopShop: Loading shop scene for all players...", "CoopAnything")
	_setup_shop_test_rundata()
	var err = get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
	if err == OK:
		NetworkLogger.success("CoopShop scene loaded successfully!", "CoopAnything")
		shop_test_step = 1
		shop_test_timer = 3.5
	else:
		NetworkLogger.error("Failed to load CoopShop scene: %d" % err, "CoopAnything")

func _setup_shop_test_rundata() -> void:
	var run_data = get_node_or_null("/root/RunData")
	if not run_data:
		return
	NetworkLogger.info("Setting up RunData canonically for 2-player shop...", "CoopAnything")
	if run_data.has_method("reset"):
		run_data.reset(false)
	run_data.set_coop_run(true)
	run_data.set_player_count(2)
	run_data.current_wave = 1
	
	var zone_service = get_node_or_null("/root/ZoneService")
	if zone_service and zone_service.has_method("get_zone_data"):
		zone_service.current_zone = zone_service.get_zone_data(0).duplicate()
	
	var coop = get_node_or_null("/root/CoopService")
	if coop and coop.has_method("setup_coop_players"):
		coop.setup_coop_players(2)
	
	var char0 = load("res://items/characters/well_rounded/well_rounded_data.tres")
	var char1 = load("res://items/characters/brawler/brawler_data.tres")
	var weapon0 = load("res://weapons/melee/knife/1/knife_data.tres")
	var weapon1 = load("res://weapons/melee/fist/1/fist_data.tres")
	
	if run_data.has_method("add_character"):
		run_data.add_character(char0, 0)
		run_data.add_character(char1, 1)
		
	if run_data.has_method("add_weapon"):
		run_data.add_weapon(weapon0, 0, true)
		run_data.add_weapon(weapon1, 1, true)
		
	if run_data.has_method("add_starting_items_and_weapons"):
		run_data.add_starting_items_and_weapons()
		
	if run_data.players_data.size() >= 2:
		run_data.players_data[0].gold = 350
		run_data.players_data[1].gold = 350
		NetworkLogger.success("Canonical RunData configured: 2 players, characters, weapons, and 350 gold!", "CoopAnything")

func _advance_shop_test_step() -> void:
	match shop_test_step:
		1:
			NetworkLogger.info("Shop Test Step 1: Capturing initial shop screen...", "CoopAnything")
			capture_screen("06_shop_screen")
			if is_host():
				var shop = get_tree().current_scene
				if shop:
					var cont1 = shop.get_node_or_null("Content/HBoxContainer2/CoopShopPlayerContainer1")
					if cont1:
						var shop_items_container = cont1.get_node_or_null("MarginContainer/Carousel/Content/VBoxContainer/PanelContainer/ShopItemsContainer")
						if shop_items_container and shop_items_container.get_child_count() > 0:
							var item0 = shop_items_container.get_child(0)
							var gold_before = RunData.get_player_gold(0)
							if item0.has_method("_on_BuyButton_pressed"):
								item0._on_BuyButton_pressed()
							var gold_after = RunData.get_player_gold(0)
							NetworkLogger.success("Host: Bought item in slot 0 for Player 0 (Gold: %d -> %d)" % [gold_before, gold_after], "CoopAnything")
							call_deferred("capture_screen", "07_host_bought_item")
			shop_test_step = 2
			shop_test_timer = 2.5
		2:
			if is_client():
				NetworkLogger.info("Shop Test Step 2: Client sending shop BUY request for slot 0...", "CoopAnything")
				rpc_id(1, "rpc_request_shop_buy", 1, 0)
			shop_test_step = 3
			shop_test_timer = 2.5
		3:
			if is_client():
				NetworkLogger.info("Shop Test Step 3: Client sending shop REROLL request...", "CoopAnything")
				rpc_id(1, "rpc_request_shop_reroll", 1)
			shop_test_step = 4
			shop_test_timer = 2.5
		4:
			NetworkLogger.info("Shop Test Step 4: Marking READY in shop...", "CoopAnything")
			if is_client():
				rpc("rpc_notify_shop_ready", 1, true)
			elif is_host():
				rpc("rpc_notify_shop_ready", 0, true)
			shop_test_step = 5
			shop_test_timer = 3.0
		5:
			NetworkLogger.info("Shop Test Step 5: Verification complete!", "CoopAnything")
			shop_test_step = 0

# ----------------------------------------------------
# Post-Wave (Upgrades + Crates + Shop) Test Routines
# ----------------------------------------------------
func start_postwave_test() -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Starting full Post-Wave Upgrades & Shop multiplayer verification...", "CoopAnything")
	rpc("rpc_load_upgrades_scene")

remotesync func rpc_load_upgrades_scene() -> void:
	NetworkLogger.info("CoopUpgradesUI: Loading post-wave upgrades scene for all players...", "CoopAnything")
	_setup_shop_test_rundata()
	if is_host():
		var pw_seed = 987654321
		rpc("rpc_sync_rng_seed", pw_seed)
	var err = get_tree().change_scene("res://ui/menus/ingame/coop_upgrades_ui.tscn")
	if err == OK:
		NetworkLogger.success("CoopUpgradesUI scene loaded successfully!", "CoopAnything")
		postwave_test_step = 1
		postwave_test_timer = 2.5
	else:
		NetworkLogger.error("Failed to load CoopUpgradesUI scene: %d" % err, "CoopAnything")

func _advance_postwave_test_step() -> void:
	match postwave_test_step:
		1:
			NetworkLogger.info("PostWave Step 1: Populating crate and level-up choices...", "CoopAnything")
			_populate_test_upgrades_and_crates()
			call_deferred("capture_screen", "10_crate_loot_screen")
			if is_host():
				var scene = get_tree().current_scene
				var up_ui = _find_upgrades_ui(scene)
				if up_ui:
					var cont1 = up_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer1")
					if cont1:
						if cont1.has_method("_on_TakeButton_pressed"):
							cont1._on_TakeButton_pressed()
						NetworkLogger.success("Host: Player 0 took crate item (inventory items: %d)" % RunData.get_player_items(0).size(), "CoopAnything")
			postwave_test_step = 2
			postwave_test_timer = 2.5
		2:
			if is_client():
				NetworkLogger.info("PostWave Step 2: Client sending crate TAKE request...", "CoopAnything")
				rpc_id(1, "rpc_request_crate_take", 1)
			postwave_test_step = 3
			postwave_test_timer = 2.5
		3:
			NetworkLogger.info("PostWave Step 3: Choosing level-up stat upgrades...", "CoopAnything")
			call_deferred("capture_screen", "12_stat_upgrades_screen")
			if is_host():
				var scene = get_tree().current_scene
				var up_ui = _find_upgrades_ui(scene)
				if up_ui:
					var cont1 = up_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer1")
					if cont1:
						var cards = cont1._get_upgrade_uis() if cont1.has_method("_get_upgrade_uis") else []
						if cards.size() > 0:
							var upgrade_data = cards[0].get("upgrade_data")
							if upgrade_data:
								RunData.apply_item_effects(upgrade_data, 0)
							if cards[0].has_method("_on_ChooseButton_pressed"):
								cards[0]._on_ChooseButton_pressed()
							NetworkLogger.success("Host: Player 0 chose upgrade card 0", "CoopAnything")
			postwave_test_step = 4
			postwave_test_timer = 2.5
		4:
			if is_client():
				NetworkLogger.info("PostWave Step 4: Client sending upgrade card 0 choice...", "CoopAnything")
				rpc_id(1, "rpc_request_upgrade", 1, 0)
			postwave_test_step = 5
			postwave_test_timer = 2.5
		5:
			NetworkLogger.info("PostWave Step 5: Transitioning to Shop scene...", "CoopAnything")
			if is_host():
				rpc("rpc_load_shop_scene")
			postwave_test_step = 6
			postwave_test_timer = 3.5
		6:
			NetworkLogger.info("PostWave Step 6: Initial shop screen & Host buying slot 0...", "CoopAnything")
			call_deferred("capture_screen", "14_shop_screen")
			if is_host():
				var shop = get_tree().current_scene
				if shop:
					var cont1 = shop.get_node_or_null("Content/HBoxContainer2/CoopShopPlayerContainer1")
					if cont1:
						var shop_items_container = cont1.get_node_or_null("MarginContainer/Carousel/Content/VBoxContainer/PanelContainer/ShopItemsContainer")
						if shop_items_container and shop_items_container.get_child_count() > 0:
							var item0 = shop_items_container.get_child(0)
							var gold_before = RunData.get_player_gold(0)
							if item0.has_method("_on_BuyButton_pressed"):
								item0._on_BuyButton_pressed()
							var gold_after = RunData.get_player_gold(0)
							NetworkLogger.success("Host: Bought item in slot 0 for Player 0 (Gold: %d -> %d)" % [gold_before, gold_after], "CoopAnything")
			postwave_test_step = 7
			postwave_test_timer = 2.5
		7:
			if is_client():
				NetworkLogger.info("PostWave Step 7: Client sending shop BUY request for slot 0...", "CoopAnything")
				rpc_id(1, "rpc_request_shop_buy", 1, 0)
			postwave_test_step = 8
			postwave_test_timer = 2.5
		8:
			if is_client():
				NetworkLogger.info("PostWave Step 8: Client sending shop REROLL request...", "CoopAnything")
				rpc_id(1, "rpc_request_shop_reroll", 1)
			postwave_test_step = 9
			postwave_test_timer = 2.5
		9:
			NetworkLogger.info("PostWave Step 9: Marking READY in shop...", "CoopAnything")
			if is_client():
				rpc("rpc_notify_shop_ready", 1, true)
			elif is_host():
				rpc("rpc_notify_shop_ready", 0, true)
			postwave_test_step = 10
			postwave_test_timer = 3.0
		10:
			NetworkLogger.success("PostWave Step 10: FULL POST-WAVE VERIFICATION COMPLETE!", "CoopAnything")
			postwave_test_step = 0

func _populate_test_upgrades_and_crates() -> void:
	var scene = get_tree().current_scene
	var up_ui = _find_upgrades_ui(scene)
	if up_ui and up_ui.has_method("show_options"):
		var up_class = load("res://ui/menus/ingame/upgrades_ui.gd")
		var up0 = up_class.UpgradeToProcess.new()
		up0.level = 2
		up0.player_index = 0
		var up1 = up_class.UpgradeToProcess.new()
		up1.level = 2
		up1.player_index = 1
		var cons_res = load("res://items/consumables/item_box/item_box_data.tres")
		var crate0 = up_class.ConsumableToProcess.new()
		crate0.consumable_data = cons_res
		crate0.player_index = 0
		var crate1 = up_class.ConsumableToProcess.new()
		crate1.consumable_data = cons_res
		crate1.player_index = 1
		up_ui.show_options([[crate0], [crate1]], [[up0], [up1]])
		NetworkLogger.success("UpgradesUI: show_options populated with 1 crate + 1 level-up per player!", "CoopAnything")

# ----------------------------------------------------
# Shop Network RPCs
# ----------------------------------------------------
func _serialize_shop_items(shop_items_array: Array) -> Array:
	var result: Array = []
	for entry in shop_items_array:
		if entry is Array and entry.size() > 0 and entry[0] != null:
			var res_path: String = entry[0].resource_path
			if res_path == "" and entry[0].get("my_id"):
				var item_service = get_node_or_null("/root/ItemService")
				if item_service:
					var found = item_service.get_element(item_service.items, entry[0].my_id)
					if not found:
						found = item_service.get_element(item_service.weapons, entry[0].my_id)
					if found:
						res_path = found.resource_path
			var second_val = entry[1] if entry.size() > 1 else false
			result.append([res_path, second_val])
	return result

func _deserialize_shop_items(serialized: Array) -> Array:
	var result: Array = []
	for entry in serialized:
		if entry is Array and entry.size() >= 2 and entry[0] != "":
			var res = load(entry[0])
			if res:
				result.append([res, entry[1]])
	return result

remotesync func rpc_sync_initial_shop_items(all_shops: Dictionary) -> void:
	cached_initial_shop_items = all_shops
	if is_client():
		var shop = get_tree().current_scene
		if shop and ("_shop_items" in shop):
			for p_idx in all_shops.keys():
				var p = int(p_idx)
				if p < shop._shop_items.size():
					shop._shop_items[p] = _deserialize_shop_items(all_shops[p_idx])
					var cont = shop._get_shop_items_container(p) if shop.has_method("_get_shop_items_container") else null
					if cont and cont.has_method("set_shop_items"):
						cont.set_shop_items(shop._shop_items[p])

remote func rpc_request_shop_buy(player_index: int, slot_idx: int) -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Received shop BUY request from player %d for slot %d" % [player_index, slot_idx], "CoopAnything")
	var shop = get_tree().current_scene
	if shop:
		var container = shop.get_node_or_null("Content/HBoxContainer2/CoopShopPlayerContainer" + str(player_index + 1))
		if container:
			var items_vbox = container.get_node_or_null("MarginContainer/Carousel/Content/VBoxContainer/PanelContainer/ShopItemsContainer")
			if items_vbox:
				var item = null
				if items_vbox.has_method("get_shop_item_node"):
					item = items_vbox.get_shop_item_node(slot_idx)
				elif slot_idx < items_vbox.get_child_count():
					item = items_vbox.get_child(slot_idx)
				
				if item and item.has_method("_on_BuyButton_pressed"):
					var gold_before = RunData.get_player_gold(player_index)
					item._on_BuyButton_pressed()
					var gold_after = RunData.get_player_gold(player_index)
					NetworkLogger.success("Host: Executed BUY for player %d on slot %d (Gold: %d -> %d)" % [player_index, slot_idx, gold_before, gold_after], "CoopAnything")
					rpc("rpc_confirm_shop_buy", player_index, slot_idx, gold_after)

remotesync func rpc_confirm_shop_buy(player_index: int, slot_idx: int, updated_gold: int) -> void:
	NetworkLogger.info("Confirmed shop buy for player %d (slot %d, remaining gold: %d)" % [player_index, slot_idx, updated_gold], "CoopAnything")
	if RunData and RunData.players_data.size() > player_index:
		RunData.players_data[player_index].gold = updated_gold
	var shop = get_tree().current_scene
	if shop:
		var container = shop.get_node_or_null("Content/HBoxContainer2/CoopShopPlayerContainer" + str(player_index + 1))
		if container:
			var items_vbox = container.get_node_or_null("MarginContainer/Carousel/Content/VBoxContainer/PanelContainer/ShopItemsContainer")
			if items_vbox:
				var item = null
				if items_vbox.has_method("get_shop_item_node"):
					item = items_vbox.get_shop_item_node(slot_idx)
				elif slot_idx < items_vbox.get_child_count():
					item = items_vbox.get_child(slot_idx)
				if item and item.has_method("deactivate"):
					item.deactivate()
	call_deferred("capture_screen", "08_shop_after_client_buy")

remote func rpc_request_shop_reroll(player_index: int) -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Received shop REROLL request from player %d" % player_index, "CoopAnything")
	var shop = get_tree().current_scene
	if shop and shop.has_method("_on_RerollButton_pressed"):
		var gold_before = RunData.get_player_gold(player_index)
		# shop._on_RerollButton_pressed will execute native reroll and broadcast rpc_confirm_shop_reroll
		shop._on_RerollButton_pressed(player_index)
		var gold_after = RunData.get_player_gold(player_index)
		NetworkLogger.success("Host: Executed REROLL for player %d (Gold: %d -> %d)" % [player_index, gold_before, gold_after], "CoopAnything")

remotesync func rpc_confirm_shop_reroll(player_index: int, updated_gold: int, serialized_items: Array = [], _locked_count: int = 0) -> void:
	NetworkLogger.info("Confirmed shop reroll for player %d (Gold: %d, items: %d)" % [player_index, updated_gold, serialized_items.size()], "CoopAnything")
	if RunData and RunData.players_data.size() > player_index:
		RunData.players_data[player_index].gold = updated_gold
		RunData.emit_signal("gold_changed", updated_gold, player_index)
	if is_client() and serialized_items.size() > 0:
		var shop = get_tree().current_scene
		if shop and ("_shop_items" in shop) and player_index < shop._shop_items.size():
			shop._shop_items[player_index] = _deserialize_shop_items(serialized_items)
			var cont = shop._get_shop_items_container(player_index) if shop.has_method("_get_shop_items_container") else null
			if cont and cont.has_method("set_shop_items"):
				cont.set_shop_items(shop._shop_items[player_index])
	call_deferred("capture_screen", "09_shop_after_reroll")

# ----------------------------------------------------
# Upgrades & Crates Network RPCs
# ----------------------------------------------------
remote func rpc_request_upgrade(player_index: int, slot_idx: int) -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Received UPGRADE choice from player %d for card %d" % [player_index, slot_idx], "CoopAnything")
	var scene = get_tree().current_scene
	var upgrades_ui = _find_upgrades_ui(scene)
	if upgrades_ui:
		var container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/CoopUpgradesUIPlayerContainer" + str(player_index + 1))
		if container:
			var cards = []
			if container.has_method("_get_upgrade_uis"):
				cards = container._get_upgrade_uis()
			elif container.has_node("MarginContainer/VBoxContainer/Carousel/Content/MarginContainer/VBoxContainer/UpgradesContainer"):
				cards = container.get_node("MarginContainer/VBoxContainer/Carousel/Content/MarginContainer/VBoxContainer/UpgradesContainer").get_children()
			if slot_idx < cards.size():
				var card = cards[slot_idx]
				if card.has_method("_on_ChooseButton_pressed"):
					card._on_ChooseButton_pressed()
					NetworkLogger.success("Host: Applied UPGRADE %d for player %d" % [slot_idx, player_index], "CoopAnything")
					rpc("rpc_confirm_upgrade", player_index, slot_idx)

remotesync func rpc_confirm_upgrade(player_index: int, slot_idx: int) -> void:
	NetworkLogger.info("Player %d upgrade choice %d confirmed" % [player_index, slot_idx], "CoopAnything")
	var scene = get_tree().current_scene
	var upgrades_ui = _find_upgrades_ui(scene)
	if upgrades_ui and is_client() and player_index == my_player_index:
		var container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/CoopUpgradesUIPlayerContainer" + str(player_index + 1))
		if container and container.has_method("_get_upgrade_uis"):
			var cards = container._get_upgrade_uis()
			if slot_idx < cards.size() and cards[slot_idx].has_method("_on_ChooseButton_pressed"):
				cards[slot_idx]._on_ChooseButton_pressed()
	call_deferred("capture_screen", "13_upgrade_chosen")

remote func rpc_request_crate_take(player_index: int) -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Received CRATE TAKE request from player %d" % player_index, "CoopAnything")
	var scene = get_tree().current_scene
	var upgrades_ui = _find_upgrades_ui(scene)
	if upgrades_ui:
		var container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/CoopUpgradesUIPlayerContainer" + str(player_index + 1))
		if container:
			if container.has_method("_on_TakeButton_pressed"):
				container._on_TakeButton_pressed()
			NetworkLogger.success("Host: Handled crate item for player %d" % player_index, "CoopAnything")
			rpc("rpc_confirm_crate_take", player_index)

remotesync func rpc_confirm_crate_take(player_index: int) -> void:
	NetworkLogger.info("Player %d crate take confirmed" % player_index, "CoopAnything")
	var scene = get_tree().current_scene
	var upgrades_ui = _find_upgrades_ui(scene)
	if upgrades_ui and is_client() and player_index == my_player_index:
		var container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/CoopUpgradesUIPlayerContainer" + str(player_index + 1))
		if container and container.has_method("_on_TakeButton_pressed"):
			container._on_TakeButton_pressed()
	call_deferred("capture_screen", "11_crate_item_taken")

remote func rpc_request_crate_discard(player_index: int) -> void:
	if not is_host():
		return
	NetworkLogger.info("Host: Received CRATE DISCARD request from player %d" % player_index, "CoopAnything")
	var scene = get_tree().current_scene
	var upgrades_ui = _find_upgrades_ui(scene)
	if upgrades_ui:
		var container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer2/UpgradesUIPlayerContainer" + str(player_index + 1))
		if not container:
			container = upgrades_ui.get_node_or_null("Content/HBoxContainer2/CoopUpgradesUIPlayerContainer" + str(player_index + 1))
		if container and container.has_method("_on_DiscardButton_pressed"):
			container._on_DiscardButton_pressed()
			NetworkLogger.success("Host: Recycled crate item for player %d" % player_index, "CoopAnything")
			rpc("rpc_confirm_crate_discard", player_index)

remotesync func rpc_confirm_crate_discard(player_index: int) -> void:
	NetworkLogger.info("Player %d crate discard confirmed" % player_index, "CoopAnything")
	call_deferred("capture_screen", "11_crate_item_discarded")

func _find_upgrades_ui(scene: Node) -> Node:
	if not scene:
		return null
	if scene.name == "CoopUpgradesUI" or scene.name == "UpgradesUI":
		return scene
	var up = scene.get_node_or_null("UI/CoopUpgradesUI")
	if not up: up = scene.get_node_or_null("Content/CoopUpgradesUI")
	if not up: up = scene.get_node_or_null("CoopUpgradesUI")
	if not up: up = scene.get_node_or_null("UI/UpgradesUI")
	return up

# ----------------------------------------------------
# Ready & Advance Flow
# ----------------------------------------------------
remotesync func rpc_notify_shop_ready(player_index: int, is_ready: bool) -> void:
	shop_ready_states[player_index] = is_ready
	NetworkLogger.info("Player %d ready state: %s" % [player_index + 1, str(is_ready)], "CoopAnything")
	emit_signal("shop_ready_state_changed", player_index, is_ready)
	
	var shop = get_tree().current_scene
	if shop and shop.has_method("set_player_ready_ui"):
		shop.set_player_ready_ui(player_index, is_ready)
	
	if is_host():
		var all_ready: bool = true
		for p in range(RunData.get_player_count()):
			if not shop_ready_states.get(p, false):
				all_ready = false
				break
		if all_ready:
			NetworkLogger.success("Host: All players READY in shop! Calculating next wave and advancing...", "CoopAnything")
			var next_wave = RunData.current_wave + 1
			for p in RunData.get_player_count():
				var effects = RunData.get_player_effects(p)
				if effects.has(Keys.item_hourglass_hash) and effects[Keys.item_hourglass_hash] > 0:
					next_wave -= effects[Keys.item_hourglass_hash]
			rpc("rpc_all_ready_advance_wave", next_wave)

remotesync func rpc_all_ready_advance_wave(next_wave: int = -1) -> void:
	shop_ready_states.clear()
	NetworkLogger.info("Advancing from shop to wave %d!" % next_wave, "CoopAnything")
	var shop = get_tree().current_scene
	if shop and shop.has_method("advance_to_next_wave"):
		shop.advance_to_next_wave(next_wave)
	else:
		if next_wave > 0:
			RunData.current_wave = next_wave
		else:
			RunData.current_wave += 1
		var target_scene = MenuData.game_scene if (MenuData and MenuData.game_scene != "" and MenuData.game_scene != "res://") else "res://main.tscn"
		var _err = get_tree().change_scene(target_scene)
	call_deferred("capture_screen", "12_wave_advance_success")

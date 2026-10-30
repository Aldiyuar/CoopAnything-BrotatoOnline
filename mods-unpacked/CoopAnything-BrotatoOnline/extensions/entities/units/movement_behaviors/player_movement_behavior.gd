extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

var _last_sent_movement: Vector2 = Vector2.ZERO
var _last_send_time_msec: int = 0
var _net_mgr = null

func _ready() -> void:
	_net_mgr = get_node_or_null("/root/NetworkManager")

func get_movement() -> Vector2:
	if not _net_mgr or not _net_mgr.is_online():
		return .get_movement()
	
	# If parent player is dead, cease all movement and input immediately
	if _parent and is_instance_valid(_parent) and _parent.dead:
		if _last_sent_movement != Vector2.ZERO:
			_last_sent_movement = Vector2.ZERO
			if _net_mgr.is_client():
				_net_mgr.client_input_seq += 1
				_net_mgr.rpc_id(1, "rpc_send_player_input", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, _net_mgr.client_input_seq)
			elif _net_mgr.is_host():
				_net_mgr.rpc("rpc_broadcast_host_input", 0.0, 0.0, 0.0, 0.0)
		return Vector2.ZERO
	
	# If this player is a remote network player (virtual device >= 100)
	if device >= 100:
		# On Host, remote puppet moves via simulated player input from Client
		# On Client, remote puppet is purely interpolated via net_target_pos; no local move_and_slide
		if _net_mgr.is_host():
			var remote_player_idx = device - 100
			if _net_mgr.player_inputs.has(remote_player_idx):
				return _net_mgr.player_inputs[remote_player_idx].movement
		return Vector2.ZERO
	
	# If this is local player input
	var local_movement = .get_movement()
	
	# If local physical input is idle, allow synthetic bot/test movement
	if local_movement == Vector2.ZERO and _net_mgr.synthetic_movement != Vector2.ZERO:
		local_movement = _net_mgr.synthetic_movement
	
	var now_msec = OS.get_ticks_msec()
	var input_changed = local_movement.distance_squared_to(_last_sent_movement) > 0.0001
	var heartbeat_due = (local_movement.length_squared() > 0.0) and (now_msec - _last_send_time_msec >= 50) # 20 Hz heartbeat

	if input_changed or heartbeat_due:
		_last_sent_movement = local_movement
		_last_send_time_msec = now_msec
		# If we are a Client, stream our local input and position to the Host
		if _net_mgr.is_client():
			var my_pos = Vector2.ZERO
			if _parent and is_instance_valid(_parent):
				my_pos = _parent.global_position
			_net_mgr.client_input_seq += 1
			_net_mgr.rpc_unreliable_id(1, "rpc_send_player_input", local_movement.x, local_movement.y, 0.0, 0.0, my_pos.x, my_pos.y, _net_mgr.client_input_seq)
		# If we are Host, broadcast our local input to all peers
		elif _net_mgr.is_host():
			_net_mgr.rpc_unreliable("rpc_broadcast_host_input", local_movement.x, local_movement.y, 0.0, 0.0)
	
	return local_movement

extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

var _last_sent_movement: Vector2 = Vector2.ZERO
var _net_mgr = null

func _ready() -> void:
	_net_mgr = get_node_or_null("/root/NetworkManager")

func get_movement() -> Vector2:
	if not _net_mgr or not _net_mgr.is_online():
		return .get_movement()
	
	# If parent player is dead, cease all movement and input immediately
	if _parent and is_instance_valid(_parent) and _parent.dead:
		return Vector2.ZERO
	
	# If this player is a remote network player on the Host (virtual device >= 100)
	if device >= 100:
		var remote_player_idx = device - 100
		if _net_mgr.player_inputs.has(remote_player_idx):
			return _net_mgr.player_inputs[remote_player_idx].movement
		return Vector2.ZERO
	
	# If this is local player input
	var local_movement = .get_movement()
	
	# If local physical input is idle, allow synthetic bot/test movement
	if local_movement == Vector2.ZERO and _net_mgr.synthetic_movement != Vector2.ZERO:
		local_movement = _net_mgr.synthetic_movement
	
	# If we are a Client, stream our local input and position to the Host
	if _net_mgr.is_client():
		# Send input at fixed tick rate or on change
		if local_movement != _last_sent_movement or local_movement.length_squared() > 0:
			_last_sent_movement = local_movement
			var my_pos = Vector2.ZERO
			if _parent and is_instance_valid(_parent):
				my_pos = _parent.global_position
			_net_mgr.rpc_unreliable_id(1, "rpc_send_player_input", local_movement.x, local_movement.y, 0.0, 0.0, my_pos.x, my_pos.y)
	# If we are Host, broadcast our local input to all peers
	elif _net_mgr.is_host():
		if local_movement != _last_sent_movement or local_movement.length_squared() > 0:
			_last_sent_movement = local_movement
			_net_mgr.rpc_unreliable("rpc_broadcast_host_input", local_movement.x, local_movement.y, 0.0, 0.0)
	
	return local_movement

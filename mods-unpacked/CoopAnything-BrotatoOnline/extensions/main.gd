extends "res://main.gd"

const NetworkLogger = preload("res://mods-unpacked/CoopAnything-BrotatoOnline/global/network_logger.gd")

var _sync_timer: float = 0.0

func _ready() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		net.network_enemies.clear()
		net.ground_items.clear()
		if net.is_client():
			# Disconnect local wave manager so client never spawns rogue/unshared enemies
			if _wave_manager and _entity_spawner:
				if _wave_manager.is_connected("group_spawn_timing_reached", _entity_spawner, "on_group_spawn_timing_reached"):
					_wave_manager.disconnect("group_spawn_timing_reached", _entity_spawner, "on_group_spawn_timing_reached")
			NetworkLogger.success("Client: Disabled local wave manager enemy spawning (Host Authoritative)", "CoopAnything")
		elif net.is_host():
			NetworkLogger.success("Host: Managing authoritative shared enemies & currency", "CoopAnything")

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_host():
		_sync_timer += delta
		if _sync_timer >= 0.05: # 20 Hz
			_sync_timer = 0.0
			var batch = []
			for net_id in net.network_enemies.keys():
				var entity = net.network_enemies[net_id]
				if is_instance_valid(entity) and not entity.dead:
					batch.append([
						net_id,
						int(entity.global_position.x),
						int(entity.global_position.y),
						int(entity.current_stats.health)
					])
				else:
					net.network_enemies.erase(net_id)
			if batch.size() > 0:
				net.rpc_unreliable("rpc_sync_enemy_batch", batch)
			
			# Broadcast authoritative player positions & health (20 Hz)
			var p_batch = []
			for i in range(_players.size()):
				var p = _players[i]
				if is_instance_valid(p):
					var is_dead = p.dead or p.current_stats.health <= 0
					var cur_hp = 0 if is_dead else int(p.current_stats.health)
					p_batch.append([
						i,
						int(p.global_position.x),
						int(p.global_position.y),
						cur_hp,
						1 if is_dead else 0
					])
			if p_batch.size() > 0:
				net.rpc_unreliable("rpc_sync_player_positions", p_batch)
	elif net and net.is_online() and net.is_client():
		if _entity_spawner:
			if "queue_to_spawn_summons" in _entity_spawner and _entity_spawner.queue_to_spawn_summons.size() > 0:
				_entity_spawner.queue_to_spawn_summons.clear()
			if "queue_to_spawn_trees" in _entity_spawner and _entity_spawner.queue_to_spawn_trees.size() > 0:
				_entity_spawner.queue_to_spawn_trees.clear()

		# Smooth 60 FPS interpolation for remote players
		var weight = clamp(delta * 16.0, 0.0, 1.0)
		for i in range(_players.size()):
			if i != net.my_player_index:
				var p = _players[i]
				if is_instance_valid(p) and not p.dead and p.has_meta("net_target_pos"):
					var target = p.get_meta("net_target_pos")
					p.global_position = p.global_position.linear_interpolate(target, weight)
		
		# Smooth 60 FPS interpolation for shared enemies and trees
		for net_id in net.network_enemies.keys():
			var entity = net.network_enemies[net_id]
			if is_instance_valid(entity) and not entity.dead and entity.has_meta("net_target_pos"):
				var target = entity.get_meta("net_target_pos")
				entity.global_position = entity.global_position.linear_interpolate(target, weight)

func _on_player_died(p_player: Player, args: Entity.DieArgs) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if net.is_host():
			NetworkLogger.info("Host: Player %d died! Broadcasting death to all peers..." % p_player.player_index, "CoopAnything")
			net.rpc("rpc_player_died", p_player.player_index)
	._on_player_died(p_player, args)

func _on_EntitySpawner_enemy_spawned(enemy: Enemy) -> void:
	._on_EntitySpawner_enemy_spawned(enemy)
	if _cleaning_up:
		return
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_host():
		call_deferred("_network_register_enemy", enemy)

func _network_register_enemy(enemy: Enemy) -> void:
	if _cleaning_up or not is_instance_valid(enemy) or enemy.dead:
		return
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online() or not net.is_host():
		return
	net.network_enemy_counter += 1
	var net_id = net.network_enemy_counter
	enemy.set_meta("net_id", net_id)
	net.network_enemies[net_id] = enemy
	var scene_path = enemy.filename
	if scene_path == "" and enemy.get("unit_scene"):
		scene_path = enemy.unit_scene.resource_path
	var hp = int(enemy.current_stats.health)
	net.rpc("rpc_spawn_network_enemy", net_id, scene_path, enemy.global_position.x, enemy.global_position.y, hp)
	NetworkLogger.info("Host: Broadcasted shared enemy %d (%s) at (%.0f, %.0f)" % [net_id, scene_path.get_file(), enemy.global_position.x, enemy.global_position.y], "CoopAnything")

func _on_EntitySpawner_neutral_spawned(neutral: Neutral) -> void:
	._on_EntitySpawner_neutral_spawned(neutral)
	if _cleaning_up:
		return
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_host():
		call_deferred("_network_register_neutral", neutral)

func _network_register_neutral(neutral: Neutral) -> void:
	if _cleaning_up or not is_instance_valid(neutral) or neutral.dead:
		return
	var net = get_node_or_null("/root/NetworkManager")
	if not net or not net.is_online() or not net.is_host():
		return
	net.network_enemy_counter += 1
	var net_id = net.network_enemy_counter
	neutral.set_meta("net_id", net_id)
	net.network_enemies[net_id] = neutral
	net.rpc("rpc_spawn_network_neutral", net_id, neutral.filename, neutral.global_position.x, neutral.global_position.y)

func _on_enemy_died(enemy: Enemy, args: Entity.DieArgs) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if net.is_client():
			RunData.current_living_enemies -= 1
			if enemy.has_meta("net_id"):
				net.network_enemies.erase(enemy.get_meta("net_id"))
			return
		elif net.is_host():
			if enemy.has_meta("net_id"):
				var net_id = enemy.get_meta("net_id")
				net.network_enemies.erase(net_id)
				if not _cleaning_up:
					net.rpc("rpc_enemy_died", net_id)
	._on_enemy_died(enemy, args)

func _on_neutral_died(neutral: Neutral, args: Entity.DieArgs) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if net.is_client():
			RunData.current_living_trees -= 1
			if neutral.has_meta("net_id"):
				net.network_enemies.erase(neutral.get_meta("net_id"))
			return
		elif net.is_host():
			if neutral.has_meta("net_id"):
				var net_id = neutral.get_meta("net_id")
				net.network_enemies.erase(net_id)
				if not _cleaning_up:
					net.rpc("rpc_enemy_died", net_id)
	._on_neutral_died(neutral, args)

func _on_enemy_took_damage(
	enemy: Enemy, 
	value: int, 
	knockback_direction: Vector2, 
	is_crit: bool, 
	is_dodge: bool, 
	is_protected: bool, 
	armor_did_something: bool, 
	args: TakeDamageArgs, 
	hit_type: int, 
	is_one_shot: bool
) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_client():
		# Prevent local client-side weapon simulation from killing an enemy without Host authority
		if is_instance_valid(enemy) and not enemy.get_meta("host_killed", false) and enemy.current_stats.health <= 0:
			enemy.current_stats.health = 1
			enemy.dead = false
	._on_enemy_took_damage(enemy, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
	# Combat is strictly Host-Authoritative.
	# Weapons of all players are simulated directly on the Host, and authoritative enemy HP
	# is replicated to clients via rpc_sync_enemy_batch (20 Hz).
	# Clients do NOT send rpc_client_dealt_damage to prevent double/triple damage application.

func on_gold_changed(new_value: int, player_index: int) -> void:
	.on_gold_changed(new_value, player_index)
	_sync_currencies()

func _sync_currencies() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_host():
		var golds = []
		var xps = []
		for i in range(RunData.get_player_count()):
			golds.append(RunData.get_player_gold(i))
			var p_data = RunData.players_data[i]
			xps.append([p_data.current_xp, p_data.current_level])
		net.rpc("rpc_sync_all_players_gold_and_xp", golds, xps)

func spawn_gold(value: float, pos: Vector2, spread: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if _cleaning_up or net.is_client():
			return
		elif net.is_host():
			var value_floored: = int(value)
			var residual_chance: = value - value_floored
			var spawn_count: = (value_floored + 1) if Utils.get_chance_success(residual_chance) else value_floored
			for _i in range(spawn_count):
				if _active_golds.size() >= MAX_GOLDS:
					var gold_boosted = Utils.get_rand_element(_active_golds)
					gold_boosted.value += Gold.INITIAL_VALUE
					gold_boosted.scale = Vector2(
						min(gold_boosted.scale.x + Gold.INITIAL_VALUE * 0.05, Gold.MAX_SIZE), 
						min(gold_boosted.scale.y + Gold.INITIAL_VALUE * 0.05, Gold.MAX_SIZE)
					)
					continue

				var gold = get_node_from_pool(_gold_pool_id, _materials_container)
				if gold == null:
					gold = gold_scene.instance()
					_materials_container.call_deferred("add_child", gold)
					var _error = gold.connect("picked_up", self, "on_gold_picked_up")
					_error = gold.connect("picked_up", _effects_manager, "on_gold_picked_up")
					_error = gold.connect("picked_up", _floating_text_manager, "on_gold_picked_up")
					yield(gold, "ready")

				if RunData.bonus_gold > 0:
					var gold_value = gold.value
					gold.value += min(gold.value, RunData.bonus_gold)
					gold.boosted = 2
					gold.scale.x = 1.25
					gold.scale.y = 1.25
					RunData.remove_bonus_gold(gold_value)

				gold.set_texture(gold_sprites.pick_random())
				gold.already_picked_up = false
				var dist = rand_range(50, 100 + spread)
				var push_back_destination = ZoneService.get_rand_pos_in_area(pos, dist, 0)
				gold.drop(pos, rand_range(0, 2 * PI), push_back_destination)
				_active_golds.push_back(gold)

				net.network_item_counter += 1
				var item_id = net.network_item_counter
				gold.set_meta("net_item_id", item_id)
				net.ground_items[item_id] = gold

				net.rpc("rpc_spawn_ground_gold", item_id, gold.value, pos.x, pos.y, push_back_destination.x, push_back_destination.y)

			emit_signal("gold_spawned")
			return

	.spawn_gold(value, pos, spread)

func spawn_consumables(unit: Unit) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if _cleaning_up or net.is_client():
			return
		elif net.is_host():
			var luck: = 0.0
			for player_index in RunData.get_player_count():
				luck += Utils.get_stat(Keys.stat_luck_hash, player_index) / 100.0

			var item_chance: float = (unit.stats.item_drop_chance * (1.0 + luck)) / (1.0 + _items_spawned_this_wave)
			var total_chance_change: float = RunData.sum_all_player_effects(Keys.crate_chance_hash) / 100.0
			item_chance = item_chance + item_chance * total_chance_change

			if unit.stats.always_drop_consumables and unit.stats.item_drop_chance >= 1.0 and RunData.current_wave <= RunData.nb_of_waves:
				item_chance = 1.0

			var consumable_to_spawn: ConsumableData = ItemService.get_consumable_to_drop(unit, item_chance)
			if consumable_to_spawn != null:
				var pos: = unit.global_position
				var dist: = rand_range(50, 100 + unit.stats.gold_spread)
				if consumable_to_spawn.my_id_hash == Keys.consumable_item_box_hash or consumable_to_spawn.my_id_hash == Keys.consumable_legendary_item_box_hash:
					_items_spawned_this_wave += 1

				var consumable: Consumable = get_node_from_pool(_consumable_pool_id, _consumables_container)
				if consumable == null:
					consumable = consumable_scene.instance()
					_consumables_container.call_deferred("add_child", consumable)
					var _error = consumable.connect("picked_up", self, "on_consumable_picked_up")
					yield(consumable, "ready")

				consumable.already_picked_up = false
				consumable.consumable_data = consumable_to_spawn
				consumable.set_texture(consumable_to_spawn.icon)
				var push_back_destination: Vector2 = ZoneService.get_rand_pos_in_area(pos, dist, 0)
				consumable.drop(pos, 0, push_back_destination)
				_consumables.push_back(consumable)

				net.network_item_counter += 1
				var item_id = net.network_item_counter
				consumable.set_meta("net_item_id", item_id)
				net.ground_items[item_id] = consumable

				var c_path = _get_consumable_res_path(consumable_to_spawn)
				if c_path != "":
					net.rpc("rpc_spawn_ground_consumable", item_id, c_path, pos.x, pos.y, push_back_destination.x, push_back_destination.y)
			return

	.spawn_consumables(unit)

func on_gold_picked_up(gold: Node, player_index: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if gold.already_picked_up:
			return
		gold.already_picked_up = true
		_active_golds.erase(gold)
		add_node_to_pool(gold, _gold_pool_id)
		
		if ProgressData.settings.alt_gold_sounds:
			SoundManager.play(Utils.get_rand_element(gold_alt_pickup_sounds), -5, 0.2)
		else:
			SoundManager.play(Utils.get_rand_element(gold_pickup_sounds), 0, 0.2)
			
		var item_id = gold.get_meta("net_item_id") if gold.has_meta("net_item_id") else -1
		
		if net.is_client():
			if item_id != -1:
				net.ground_items.erase(item_id)
				net.rpc_id(1, "rpc_request_item_pickup", item_id, true, player_index)
			return
		elif net.is_host():
			var val = gold.value
			RunData.add_gold(val, player_index)
			RunData.add_xp(val, player_index)
			ProgressData.increment_stat("materials_collected")
			if item_id != -1:
				net.ground_items.erase(item_id)
				net.rpc("rpc_remove_ground_item", item_id, true)
			_sync_currencies()
			return
			
	.on_gold_picked_up(gold, player_index)

func on_consumable_picked_up(consumable: Node, player_index: int) -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if consumable.already_picked_up:
			return
		consumable.already_picked_up = true
		_consumables.erase(consumable)
		add_node_to_pool(consumable, _consumable_pool_id)
		
		var item_id = consumable.get_meta("net_item_id") if consumable.has_meta("net_item_id") else -1
		
		if net.is_client():
			if item_id != -1:
				net.ground_items.erase(item_id)
				net.rpc_id(1, "rpc_request_item_pickup", item_id, false, player_index)
			return
		elif net.is_host():
			if item_id != -1:
				net.ground_items.erase(item_id)
				net.rpc("rpc_remove_ground_item", item_id, false)
			_apply_host_consumable(consumable, player_index)
			return
			
	.on_consumable_picked_up(consumable, player_index)

func _apply_host_consumable(consumable: Node, player_index: int) -> void:
	var consumable_data = consumable.consumable_data
	if not consumable_data:
		return
	var item_box_gold_effect = RunData.get_player_effect(Keys.item_box_gold_hash, player_index)
	if consumable_data.my_id_hash == Keys.consumable_item_box_hash or consumable_data.my_id_hash == Keys.consumable_legendary_item_box_hash and item_box_gold_effect != 0:
		RunData.add_gold(item_box_gold_effect, player_index)
		RunData.add_tracked_value(player_index, Keys.item_bag_hash, item_box_gold_effect)

	if consumable_data.to_be_processed_at_end_of_wave:
		var consumable_to_process = UpgradesUI.ConsumableToProcess.new()
		consumable_to_process.consumable_data = consumable_data
		consumable_to_process.player_index = player_index
		_consumables_to_process[player_index].push_back(consumable_to_process)
		_things_to_process_player_containers[player_index].consumables.add_element(consumable_data)
		var net = get_node_or_null("/root/NetworkManager")
		if net and net.is_host():
			var c_path = _get_consumable_res_path(consumable_data)
			if c_path != "":
				net.rpc("rpc_player_received_crate", player_index, c_path)

	if player_index < _players.size():
		_players[player_index].on_consumable_picked_up(consumable_data)

	if not _cleaning_up:
		RunData.handle_explode_effect(Keys.explode_on_consumable_hash, consumable.global_position, player_index)
		RunData.handle_explode_effect(Keys.explode_on_consumable_burning_hash, consumable.global_position, player_index)

	RunData.apply_item_effects(consumable_data, player_index)
	_sync_currencies()

func _get_consumable_res_path(consumable_data: Resource) -> String:
	if not consumable_data:
		return ""
	if consumable_data.resource_path != "" and consumable_data.resource_path != "res://":
		return consumable_data.resource_path
	var my_id = consumable_data.get("my_id")
	if my_id:
		match my_id:
			"consumable_item_box":
				return "res://items/consumables/item_box/item_box_data.tres"
			"consumable_fruit":
				return "res://items/consumables/fruit/fruit_data.tres"
			"consumable_legendary_item_box":
				return "res://items/consumables/legendary_item_box/legendary_item_box_data.tres"
			_:
				var item_service = get_node_or_null("/root/ItemService")
				if item_service:
					var all_c = item_service.get("consumables")
					if all_c is Array:
						for c in all_c:
							if c.get("my_id") == my_id and c.resource_path != "":
								return c.resource_path
	return ""

func on_levelled_up(player_index: int) -> void:
	.on_levelled_up(player_index)
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online() and net.is_host():
		net.rpc("rpc_player_levelled_up", player_index, RunData.get_player_level(player_index))

func on_upgrades_options_processed() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if net.is_client():
			NetworkLogger.info("Client: All local upgrades chosen, waiting for Host scene transition...", "CoopAnything")
			return
		elif net.is_host():
			var target_scene = MenuData.shop_scene if (MenuData and MenuData.shop_scene != "") else "res://ui/menus/shop/coop_shop.tscn"
			NetworkLogger.info("Host: All upgrades chosen! Transitioning all players to shop scene: %s" % target_scene, "CoopAnything")
			net.rpc("rpc_sync_change_scene", target_scene)
	.on_upgrades_options_processed()

func clean_up_room() -> void:
	.clean_up_room()
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		net.network_enemies.clear()
		net.ground_items.clear()
		if net.is_host():
			var postwave_seed = (net.current_match_seed + RunData.current_wave * 104729) % 1000000000 + 1
			net.rpc("rpc_sync_rng_seed", postwave_seed)

func _change_scene(path: String) -> void:
	if path == "" or path == "res://":
		NetworkLogger.warn("main: _change_scene called with invalid path: '%s'" % path, "CoopAnything")
		return
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		if net.is_host():
			NetworkLogger.info("Host: Changing scene to %s, broadcasting to clients..." % path, "CoopAnything")
			net.rpc("rpc_sync_change_scene", path)
	._change_scene(path)

func _on_game_lost_focus() -> void:
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		# Never pause online co-op on window focus loss!
		return
	._on_game_lost_focus()

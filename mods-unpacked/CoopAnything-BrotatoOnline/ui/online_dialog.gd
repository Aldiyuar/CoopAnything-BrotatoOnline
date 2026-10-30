extends PanelContainer
class_name OnlineCoopDialog

var ip_input: LineEdit
var port_input: LineEdit
var status_label: Label
var host_btn: Button
var join_btn: Button
var close_btn: Button

func _init():
	pause_mode = Node.PAUSE_MODE_PROCESS
	anchor_left = 0.25
	anchor_right = 0.75
	anchor_top = 0.2
	anchor_bottom = 0.8
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	sb.border_color = Color(0.9, 0.7, 0.2, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	set("custom_styles/panel", sb)

func show_dialog():
	show()
	if host_btn:
		host_btn.grab_focus()

func _ready():
	var vbox = VBoxContainer.new()
	vbox.set("custom_constants/separation", 16)
	add_child(vbox)
	
	var title = Label.new()
	title.text = "ONLINE CO-OP MULTIPLAYER"
	title.align = Label.ALIGN_CENTER
	vbox.add_child(title)
	
	status_label = Label.new()
	status_label.text = "Status: Idle"
	status_label.align = Label.ALIGN_CENTER
	vbox.add_child(status_label)
	
	# Host Section
	host_btn = Button.new()
	host_btn.text = "HOST GAME (Port 7777)"
	host_btn.connect("pressed", self, "_on_host_pressed")
	vbox.add_child(host_btn)
	
	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Join Section
	var join_hbox = HBoxContainer.new()
	join_hbox.set("custom_constants/separation", 8)
	vbox.add_child(join_hbox)
	
	var ip_lbl = Label.new()
	ip_lbl.text = "IP / Host:"
	join_hbox.add_child(ip_lbl)
	
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "IP or domain (e.g. host.playit.gg:12345)"
	ip_input.text = "127.0.0.1"
	ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_hbox.add_child(ip_input)
	
	var port_lbl = Label.new()
	port_lbl.text = "Port:"
	join_hbox.add_child(port_lbl)
	
	port_input = LineEdit.new()
	port_input.text = "7777"
	port_input.rect_min_size = Vector2(70, 0)
	join_hbox.add_child(port_input)
	
	join_btn = Button.new()
	join_btn.text = "CONNECT / JOIN"
	join_btn.connect("pressed", self, "_on_join_pressed")
	vbox.add_child(join_btn)
	
	# Close Section
	close_btn = Button.new()
	close_btn.text = "BACK / CANCEL"
	close_btn.connect("pressed", self, "_on_close_pressed")
	vbox.add_child(close_btn)
	
	# Connect to NetworkManager signals
	var net = get_node_or_null("/root/NetworkManager")
	if net:
		net.connect("role_changed", self, "_on_role_changed")
		net.connect("peer_joined", self, "_on_peer_joined")

func _on_host_pressed():
	var net = get_node_or_null("/root/NetworkManager")
	if not net:
		return
	var port = int(port_input.text)
	if port <= 0:
		port = 7777
	
	status_label.text = "Status: Hosting server on port %d..." % port
	var res = net.host_game(port)
	if res == OK:
		RunData.set_coop_run(true)
		status_label.text = "Hosting on UDP %d. Waiting for Player 2 to connect..." % port
		host_btn.disabled = true
		join_btn.disabled = true

func _on_join_pressed():
	var net = get_node_or_null("/root/NetworkManager")
	if not net:
		return
	var raw_ip = ip_input.text.strip_edges()
	var port = int(port_input.text)
	if ":" in raw_ip:
		var parts = raw_ip.split(":")
		raw_ip = parts[0].strip_edges()
		if parts.size() > 1 and parts[1].strip_edges().is_valid_integer():
			port = int(parts[1].strip_edges())
			port_input.text = str(port)
	if port <= 0:
		port = 7777
	ip_input.text = raw_ip
	
	status_label.text = "Connecting to %s:%d..." % [raw_ip, port]
	var res = net.join_game(raw_ip, port)
	if res == OK:
		RunData.set_coop_run(true)
		status_label.text = "Connected! Waiting for Host to start match..."
		host_btn.disabled = true
		join_btn.disabled = true
	else:
		status_label.text = "Failed to connect (Error: %d)" % res

func _go_to_character_select():
	hide()
	var _err = get_tree().change_scene(MenuData.character_selection_scene)

func _on_close_pressed():
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_online():
		net.close_session()
	var run_data = get_node_or_null("/root/RunData")
	if run_data and run_data.has_method("set_coop_run"):
		run_data.set_coop_run(false)
	status_label.text = "Status: Idle"
	host_btn.disabled = false
	join_btn.disabled = false
	hide()

func _on_role_changed(new_role):
	if new_role == NetworkConstants.PeerRole.SOLO:
		status_label.text = "Status: Disconnected"
		host_btn.disabled = false
		join_btn.disabled = false

func _on_peer_joined(peer_id, player_idx):
	status_label.text = "Player %d connected (Peer %d)! Starting match in 1s..." % [player_idx + 1, peer_id]
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.is_host():
		var timer = get_tree().create_timer(1.0)
		timer.connect("timeout", net, "start_coop_match")

extends "res://ui/menus/pages/main_menu.gd"

var _online_button: Button = null
var _online_dialog: Control = null

func _ready() -> void:
	# Clear any previous crash recovery warning banner
	var crash_rep = get_node_or_null("/root/CrashReporter")
	if crash_rep:
		crash_rep.previous_crashed_mod = ""
		crash_rep.previous_crash_message = ""
	var err_label = get_node_or_null("%ErrorLabel")
	if err_label:
		err_label.text = ""
		err_label.visible = false
	call_deferred("_setup_online_button")

func _setup_online_button() -> void:
	if not start_button:
		return
	
	_online_button = start_button.duplicate()
	_online_button.name = "OnlineCoopButton"
	_online_button.text = "ONLINE CO-OP"
	
	var parent_container = start_button.get_parent()
	parent_container.add_child_below_node(start_button, _online_button)
	_online_button.connect("pressed", self, "_on_online_coop_pressed")
	
	if options_button:
		_online_button.focus_neighbour_top = start_button.get_path()
		_online_button.focus_neighbour_bottom = options_button.get_path()
		start_button.focus_neighbour_bottom = _online_button.get_path()
		options_button.focus_neighbour_top = _online_button.get_path()
		
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.has_method("capture_screen"):
		net.call_deferred("capture_screen", "01_main_menu")

func _on_online_coop_pressed() -> void:
	if not _online_dialog:
		var dialog_script = load("res://mods-unpacked/CoopAnything-BrotatoOnline/ui/online_dialog.gd")
		_online_dialog = dialog_script.new()
		add_child(_online_dialog)
	
	_online_dialog.show_dialog()
	var net = get_node_or_null("/root/NetworkManager")
	if net and net.has_method("capture_screen"):
		net.call_deferred("capture_screen", "02_online_dialog")

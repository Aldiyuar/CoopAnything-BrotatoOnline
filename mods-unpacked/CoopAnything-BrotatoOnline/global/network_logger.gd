extends Object
class_name NetworkLogger

const TEST_RIG_DIR: String = "D:/Brotato_Coop_Test/logs"
const TEST_RIG_LOG_PATH: String = "D:/Brotato_Coop_Test/logs/coop_all.log"
const PRIMARY_LOG_PATH: String = "user://logs/coop_all.log"
const FALLBACK_LOG_PATH: String = "user://coop_all.log"

static func info(msg: String, context: String = "CoopAnything") -> void:
	_write_log("INFO", msg, context)
	ModLoaderLog.info(msg, context)

static func warn(msg: String, context: String = "CoopAnything") -> void:
	_write_log("WARN", msg, context)
	ModLoaderLog.warn(msg, context)

static func error(msg: String, context: String = "CoopAnything") -> void:
	_write_log("ERROR", msg, context)
	ModLoaderLog.error(msg, context)

static func success(msg: String, context: String = "CoopAnything") -> void:
	_write_log("SUCCESS", msg, context)
	ModLoaderLog.success(msg, context)

static func log_engine_error(line: String) -> void:
	_write_log("ERROR", "[GODOT_ENGINE] " + line.strip_edges(), "Engine")

static func _write_log(level: String, msg: String, context: String) -> void:
	var dt = OS.get_datetime()
	var time_str = "%04d-%02d-%02d %02d:%02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var pid = OS.get_process_id()
	var line = "[%s] [PID:%d] [%s] [%s] %s\n" % [time_str, pid, level, context, msg]
	
	var dir = Directory.new()
	var target_path = PRIMARY_LOG_PATH
	if dir.dir_exists(TEST_RIG_DIR):
		target_path = TEST_RIG_LOG_PATH
	else:
		dir.make_dir_recursive("user://logs")
		
	var f = File.new()
	var err = f.open(target_path, File.READ_WRITE)
	if err != OK:
		err = f.open(target_path, File.WRITE)
	if err != OK:
		target_path = FALLBACK_LOG_PATH
		err = f.open(target_path, File.READ_WRITE)
		if err != OK:
			err = f.open(target_path, File.WRITE)
			
	if err == OK:
		f.seek_end()
		f.store_string(line)
		f.close()
